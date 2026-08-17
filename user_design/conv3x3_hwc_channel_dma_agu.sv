`timescale 1ns / 1ps
`default_nettype none

// Fixed-function DMA address generator for the supplied YOLO 3x3 workload.
// One accepted start reproduces one call to
// dma_load_yolo_halo_patch(tile_y, tile_x, cin_block) in
// tb_npu_top_with_srams.sv.  The two nested 18-iteration testbench loops are
// implemented by local_y_q/local_x_q counters, so command order and contents
// are preserved without procedural simulation loops in the synthesized RTL.
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

module conv3x3_hwc_channel_dma_agu #(
    parameter int unsigned SRC_ADDR_WIDTH = 32,
    parameter int unsigned ACT_ADDR_WIDTH = 9
)(
    input  logic                         clk_i,
    input  logic                         rst_n,

    // Start/configuration interface.  Config is captured on an accepted start.
    input  logic                         start_i,
    output logic                         start_ready_o,
    input  logic [SRC_ADDR_WIDTH-1:0]    image_base_i,
    input  logic                         tile_y_i,      // 0: outputs 0..15, 1: 16..31
    input  logic                         tile_x_i,      // 0: outputs 0..15, 1: 16..31
    input  logic                         cin_block_i,   // 0: ci 0..7, 1: ci 8..15

    output logic                         busy_o,
    output logic                         done_o,

    // Protocol-neutral eight-channel load-group command.
    output logic                         load_valid_o,
    input  logic                         load_ready_i,
    output logic [SRC_ADDR_WIDTH-1:0]    load_src_addr_o,
    output logic [ACT_ADDR_WIDTH-1:0]    load_dst_addr_o,
    output logic [7:0]                   load_dst_bank_mask_o,
    output logic                         load_zero_fill_o,
    output logic                         load_last_o
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

    // Byte offsets of local patch coordinate (0,0), before channel-block offset.
    // tile 0 starts at global coordinate -1; tile 1 starts at coordinate 15.
    localparam logic [SRC_ADDR_WIDTH-1:0] ORIGIN_00 = -528; // y=-1, x=-1
    localparam logic [SRC_ADDR_WIDTH-1:0] ORIGIN_01 = -272; // y=-1, x=15
    localparam logic [SRC_ADDR_WIDTH-1:0] ORIGIN_10 = 7664; // y=15, x=-1
    localparam logic [SRC_ADDR_WIDTH-1:0] ORIGIN_11 = 7920; // y=15, x=15

    logic                              busy_q;
    logic [LINEAR_COUNT_WIDTH-1:0]     linear_q;
    logic [COORD_WIDTH-1:0]            local_y_q;
    logic [COORD_WIDTH-1:0]            local_x_q;
    logic [SRC_ADDR_WIDTH-1:0]         src_addr_q;
    logic                              tile_y_q;
    logic                              tile_x_q;

    logic [SRC_ADDR_WIDTH-1:0]         origin_offset_d;
    logic [SRC_ADDR_WIDTH-1:0]         channel_offset_d;
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

    // The four supported tiles are all boundary tiles of the 32x32 image.
    assign pad_y = ((!tile_y_q) && (local_y_q == 0)) ||
                   (  tile_y_q  && (local_y_q == LAST_COORD));
    assign pad_x = ((!tile_x_q) && (local_x_q == 0)) ||
                   (  tile_x_q  && (local_x_q == LAST_COORD));

    assign start_ready_o       = ~busy_q;
    assign busy_o              = busy_q;
    assign load_valid_o        = busy_q;
    assign load_zero_fill_o    = pad_y || pad_x;
    assign load_src_addr_o     = load_zero_fill_o ? '0 : src_addr_q;
    assign load_dst_addr_o     = linear_q;
    assign load_dst_bank_mask_o = 8'hff;
    assign load_last_o         = (linear_q == LAST_PIXEL);

    always_ff @(posedge clk_i) begin
        if (!rst_n) begin
            busy_q      <= 1'b0;
            done_o      <= 1'b0;
            linear_q    <= '0;
            local_y_q   <= '0;
            local_x_q   <= '0;
            src_addr_q  <= '0;
            tile_y_q    <= 1'b0;
            tile_x_q    <= 1'b0;
        end else begin
            done_o <= 1'b0;

            if (!busy_q) begin
                if (start_i) begin
                    busy_q     <= 1'b1;
                    linear_q   <= '0;
                    local_y_q  <= '0;
                    local_x_q  <= '0;
                    tile_y_q   <= tile_y_i;
                    tile_x_q   <= tile_x_i;
                    src_addr_q <= image_base_i + origin_offset_d + channel_offset_d;
                end
            end else if (load_ready_i) begin
                if (linear_q == LAST_PIXEL) begin
                    busy_q <= 1'b0;
                    done_o <= 1'b1;
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
    end

endmodule

`default_nettype wire
