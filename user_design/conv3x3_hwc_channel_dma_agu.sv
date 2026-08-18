`timescale 1ns / 1ps
`default_nettype none

// Fixed-function DMA address generator for the supplied YOLO 3x3 workload.
// One accepted activation start reproduces one call to
// dma_load_yolo_halo_patch(tile_y, tile_x, cin_block).  One accepted weight
// start reproduces one call to dma_load_weights_slice(w_slice) for a fixed
// (kernel_y, kernel_x, cin_block, cout_block).  Both reference tasks are in
// tb_npu_top_with_srams.sv.
//
// Source tensor layout (byte-addressed HWC):
//   X[32][32][16]
//   address(X[y][x][ci]) = image_base + ((y * 32 + x) * 16) + ci
//
// Output tiling:
//   four 16x16 output tiles selected by tile_y_i/tile_x_i
//   each output tile consumes an 18x18 input patch including one halo element
//
// Channel-parallel activation-bank placement:
//   cin_block_i = 0 -> banks 0..7 hold channels 0..7
//   cin_block_i = 1 -> banks 0..7 hold channels 8..15
//
// For tile-local spatial index p = local_y * 18 + local_x, one command means:
//   source byte for bank r = load_src_addr_o + r, r=0..7
//   destination           = activation_bank[r][p]
//   write enable          = load_dst_bank_mask_o[r]
//
// HWC makes those eight channel bytes contiguous, so only the base source
// address is emitted.  A downstream adapter may service the group with one
// 64-bit read or serialize it for a narrower memory interface.
//
// These are eight different channel bytes, not eight copies of one pixel byte.
// When load_zero_fill_o is high, load_src_addr_o must be ignored.  No external
// read is needed; the adapter writes zero to all eight banks at load_dst_addr_o.
//
// Weight tensor layout (byte-addressed KY-KX-CI-CO):
//   W[3][3][16][16]
//   address(W[ky][kx][ci][co]) =
//       weight_base + (((ky * 3 + kx) * 16 + ci) * 16) + co
//
// A weight command represents one cycle of the reference weight-shift task.
// For shift index s=0..7, output-column lane c=7-s is loaded and:
//   source byte for PE row r = load_src_addr_o +
//                              r * load_src_lane_stride_o, r=0..7
//   load_src_lane_stride_o    = 16
//   load_dst_addr_o           = s (informational; no weight SRAM is addressed)
// After all eight accepted commands, weight_swap_o pulses for one cycle.  The
// downstream adapter should assert the NPU's weight_shift_en while accepting
// weight commands, drive weight_shift_in[r] with each returned byte, and route
// weight_swap_o to swap_weights.

module conv3x3_hwc_channel_dma_agu #(
    parameter int unsigned SRC_ADDR_WIDTH = 32,
    parameter int unsigned ACT_ADDR_WIDTH = 9
)(
    input  logic                         clk_i,
    input  logic                         rst_n,

    // Start/configuration interface.  Config is captured on an accepted start.
    input  logic                         start_i,
    output logic                         start_ready_o,
    input  logic                         load_weight_i, // 0: activation patch, 1: 8x8 weight slice
    input  logic [SRC_ADDR_WIDTH-1:0]    image_base_i,
    input  logic [SRC_ADDR_WIDTH-1:0]    weight_base_i,
    input  logic                         tile_y_i,      // 0: outputs 0..15, 1: 16..31
    input  logic                         tile_x_i,      // 0: outputs 0..15, 1: 16..31
    input  logic                         cin_block_i,   // 0: ci 0..7, 1: ci 8..15
    input  logic                         cout_block_i,  // 0: co 0..7, 1: co 8..15
    input  logic [1:0]                   kernel_y_i,    // valid values: 0..2
    input  logic [1:0]                   kernel_x_i,    // valid values: 0..2

    output logic                         busy_o,
    output logic                         done_o,

    // Protocol-neutral eight-channel load-group command.  For a weight command,
    // load_ready_i acknowledges that the eight lane bytes have been applied on
    // a weight-shift clock, not merely queued; this keeps weight_swap_o ordered
    // after all eight shifts.
    output logic                         load_valid_o,
    input  logic                         load_ready_i,
    output logic [SRC_ADDR_WIDTH-1:0]    load_src_addr_o,
    output logic [4:0]                   load_src_lane_stride_o,
    output logic [ACT_ADDR_WIDTH-1:0]    load_dst_addr_o,
    output logic [7:0]                   load_dst_bank_mask_o,
    output logic                         load_is_weight_o,
    output logic                         load_zero_fill_o,
    output logic                         load_last_o,
    output logic                         weight_swap_o
);

    localparam int unsigned TILE_SIDE          = 18;
    localparam int unsigned TILE_PIXELS        = TILE_SIDE * TILE_SIDE;
    localparam int unsigned LINEAR_COUNT_WIDTH = $clog2(TILE_PIXELS);
    localparam int unsigned COORD_WIDTH        = $clog2(TILE_SIDE);

    localparam logic [LINEAR_COUNT_WIDTH-1:0] LAST_PIXEL = TILE_PIXELS - 1;
    localparam logic [COORD_WIDTH-1:0]        LAST_COORD = TILE_SIDE - 1;

    // HWC source-address increments.  Adjacent x coordinates are 16 bytes
    // apart.  From local (y,17) to (y+1,0): 512 - 17*16 = 240 bytes.
    localparam logic [SRC_ADDR_WIDTH-1:0] PIXEL_STEP = 16;
    localparam logic [SRC_ADDR_WIDTH-1:0] ROW_STEP   = 240;

    // Weight layout strides.  Eight PE rows read eight CI values in parallel;
    // adjacent CI rows are separated by all 16 output channels.
    localparam logic [SRC_ADDR_WIDTH-1:0] WEIGHT_CIN_BLOCK_STEP = 128;
    localparam logic [SRC_ADDR_WIDTH-1:0] WEIGHT_COUT_BLOCK_STEP = 8;
    localparam logic [SRC_ADDR_WIDTH-1:0] WEIGHT_FIRST_COLUMN   = 7;

    // Byte offsets of local patch coordinate (0,0), before channel-block offset.
    // tile 0 starts at global coordinate -1; tile 1 starts at coordinate 15.
    localparam logic [SRC_ADDR_WIDTH-1:0] ORIGIN_00 = -528; // y=-1, x=-1
    localparam logic [SRC_ADDR_WIDTH-1:0] ORIGIN_01 = -272; // y=-1, x=15
    localparam logic [SRC_ADDR_WIDTH-1:0] ORIGIN_10 = 7664; // y=15, x=-1
    localparam logic [SRC_ADDR_WIDTH-1:0] ORIGIN_11 = 7920; // y=15, x=15

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_LOAD,
        STATE_WEIGHT_GAP,
        STATE_WEIGHT_SWAP
    } state_t;

    state_t                            state_q;
    logic                              mode_weight_q;
    logic [LINEAR_COUNT_WIDTH-1:0]     linear_q;
    logic [COORD_WIDTH-1:0]            local_y_q;
    logic [COORD_WIDTH-1:0]            local_x_q;
    logic [2:0]                        weight_shift_q;
    logic [SRC_ADDR_WIDTH-1:0]         src_addr_q;
    logic                              tile_y_q;
    logic                              tile_x_q;

    logic [SRC_ADDR_WIDTH-1:0]         origin_offset_d;
    logic [SRC_ADDR_WIDTH-1:0]         channel_offset_d;
    logic [SRC_ADDR_WIDTH-1:0]         weight_tap_offset_d;
    logic [SRC_ADDR_WIDTH-1:0]         weight_start_addr_d;
    logic                              pad_y;
    logic                              pad_x;

    always_comb begin
        case ({tile_y_i, tile_x_i})
            2'b00: origin_offset_d = ORIGIN_00;
            2'b01: origin_offset_d = ORIGIN_01;
            2'b10: origin_offset_d = ORIGIN_10;
            default: origin_offset_d = ORIGIN_11;
        endcase
    end

    assign channel_offset_d = cin_block_i ? 8 : 0;

    // Fixed 3x3 tap offsets avoid synthesizing a general multiplier.
    always_comb begin
        case ({kernel_y_i, kernel_x_i})
            4'b0000: weight_tap_offset_d = 0;
            4'b0001: weight_tap_offset_d = 256;
            4'b0010: weight_tap_offset_d = 512;
            4'b0100: weight_tap_offset_d = 768;
            4'b0101: weight_tap_offset_d = 1024;
            4'b0110: weight_tap_offset_d = 1280;
            4'b1000: weight_tap_offset_d = 1536;
            4'b1001: weight_tap_offset_d = 1792;
            4'b1010: weight_tap_offset_d = 2048;
            default: weight_tap_offset_d = '0;
        endcase
    end

    assign weight_start_addr_d = weight_base_i + weight_tap_offset_d +
                                 (cin_block_i  ? WEIGHT_CIN_BLOCK_STEP  : '0) +
                                 (cout_block_i ? WEIGHT_COUT_BLOCK_STEP : '0) +
                                 WEIGHT_FIRST_COLUMN;

    // The four supported tiles are all boundary tiles of the 32x32 image.
    assign pad_y = ((!tile_y_q) && (local_y_q == 0)) ||
                   (  tile_y_q  && (local_y_q == LAST_COORD));
    assign pad_x = ((!tile_x_q) && (local_x_q == 0)) ||
                   (  tile_x_q  && (local_x_q == LAST_COORD));

    assign start_ready_o       = (state_q == STATE_IDLE);
    assign busy_o              = (state_q != STATE_IDLE);
    assign load_valid_o        = (state_q == STATE_LOAD);
    assign load_is_weight_o    = mode_weight_q;
    assign load_zero_fill_o    = load_valid_o && !mode_weight_q && (pad_y || pad_x);
    assign load_src_addr_o     = load_zero_fill_o ? '0 : src_addr_q;
    assign load_src_lane_stride_o = mode_weight_q ? 5'd16 : 5'd1;
    assign load_dst_addr_o     = mode_weight_q ? {{(ACT_ADDR_WIDTH-3){1'b0}}, weight_shift_q}
                                                : linear_q;
    assign load_dst_bank_mask_o = 8'hff;
    assign load_last_o         = load_valid_o &&
                                 (mode_weight_q ? (weight_shift_q == 3'd7)
                                                : (linear_q == LAST_PIXEL));
    assign weight_swap_o       = (state_q == STATE_WEIGHT_SWAP);

    always_ff @(posedge clk_i) begin
        if (!rst_n) begin
            state_q     <= STATE_IDLE;
            mode_weight_q <= 1'b0;
            done_o      <= 1'b0;
            linear_q    <= '0;
            local_y_q   <= '0;
            local_x_q   <= '0;
            weight_shift_q <= '0;
            src_addr_q  <= '0;
            tile_y_q    <= 1'b0;
            tile_x_q    <= 1'b0;
        end else begin
            done_o <= 1'b0;

            if (state_q == STATE_IDLE) begin
                if (start_i) begin
                    state_q       <= STATE_LOAD;
                    mode_weight_q <= load_weight_i;
                    linear_q      <= '0;
                    local_y_q     <= '0;
                    local_x_q     <= '0;
                    weight_shift_q <= '0;
                    tile_y_q      <= tile_y_i;
                    tile_x_q      <= tile_x_i;
                    if (load_weight_i) begin
                        src_addr_q <= weight_start_addr_d;
                    end else begin
                        src_addr_q <= image_base_i + origin_offset_d + channel_offset_d;
                    end
                end
            end else if (state_q == STATE_LOAD) begin
                if (load_ready_i) begin
                    if (mode_weight_q) begin
                        if (weight_shift_q == 3'd7) begin
                            state_q <= STATE_WEIGHT_GAP;
                        end else begin
                            weight_shift_q <= weight_shift_q + 1'b1;
                            // Reference task loads output columns 7,6,...,0.
                            src_addr_q <= src_addr_q - 1'b1;
                        end
                    end else begin
                        if (linear_q == LAST_PIXEL) begin
                            state_q <= STATE_IDLE;
                            done_o  <= 1'b1;
                        end else begin
                            linear_q <= linear_q + 1'b1;

                            if (local_x_q == LAST_COORD) begin
                                local_x_q  <= '0;
                                local_y_q  <= local_y_q + 1'b1;
                                src_addr_q <= src_addr_q + ROW_STEP;
                            end else begin
                                local_x_q  <= local_x_q + 1'b1;
                                src_addr_q <= src_addr_q + PIXEL_STEP;
                            end
                        end
                    end
                end
            end else if (state_q == STATE_WEIGHT_GAP) begin
                // Match the reference task's disabled shift cycle before swap.
                state_q <= STATE_WEIGHT_SWAP;
            end else begin
                // STATE_WEIGHT_SWAP: weight_swap_o is high for this full cycle.
                state_q <= STATE_IDLE;
                done_o  <= 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
