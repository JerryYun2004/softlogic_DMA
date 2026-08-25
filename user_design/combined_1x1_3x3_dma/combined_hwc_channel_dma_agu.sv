`timescale 1ns / 1ps
`default_nettype none

// Shared address generator for the supplied 32x32x16 YOLO 1x1 and 3x3
// convolution schedules.  The convolution mode is sampled together with the
// rest of the command configuration when start_i is accepted.
//
// One accepted activation map command represents eight byte transfers:
//
//   for lane r = 0..7:
//     activation_bank[r][load_dst_addr_o] <-
//       load_zero_fill_o ? 0 : memory[load_src_addr_o + r]
//
// One accepted weight map command represents one weight-shift cycle:
//
//   for PE row r = 0..7:
//     weight_shift_in[r] <-
//       memory[load_src_addr_o + r * load_src_lane_stride_o]
//
// Tensor layouts (byte addressed):
//   activation X[y][x][ci]      : ((y * 32 + x) * 16) + ci
//   1x1 weight W[ci][co]        : (ci * 16) + co
//   3x3 weight W[ky][kx][ci][co]:
//                                  (((ky * 3 + kx) * 16 + ci) * 16) + co
//
// Activation schedules:
//   conv_1x1_i = 1: 16x16 tile, 256 map commands, no halo/zero fill
//   conv_1x1_i = 0: 18x18 tile, 324 map commands, one-pixel zero-padded halo
//
// Both weight schedules emit eight commands in output-column order 7..0,
// followed by one disabled shift cycle and a one-cycle weight_swap_o pulse.
module combined_hwc_channel_dma_agu #(
    parameter int unsigned SRC_ADDR_WIDTH = 32,
    parameter int unsigned ACT_ADDR_WIDTH = 9
)(
    input  logic                         clk_i,
    input  logic                         rst_n,

    input  logic                         start_i,
    output logic                         start_ready_o,
    input  logic                         conv_1x1_i,
    input  logic                         load_weight_i,
    input  logic [SRC_ADDR_WIDTH-1:0]    image_base_i,
    input  logic [SRC_ADDR_WIDTH-1:0]    weight_base_i,
    input  logic                         tile_y_i,
    input  logic                         tile_x_i,
    input  logic                         cin_block_i,
    input  logic                         cout_block_i,
    input  logic [1:0]                   kernel_y_i,
    input  logic [1:0]                   kernel_x_i,

    output logic                         busy_o,
    output logic                         done_o,

    // Protocol-neutral eight-lane load-group stream.  Every command field is
    // held stable while load_valid_o is high and load_ready_i is low.
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

    localparam logic [8:0] LAST_1X1_PIXEL = 9'd255;
    localparam logic [8:0] LAST_3X3_PIXEL = 9'd323;

    localparam logic [SRC_ADDR_WIDTH-1:0] PIXEL_STEP   = 16;
    localparam logic [SRC_ADDR_WIDTH-1:0] ROW_STEP_1X1 = 272;
    localparam logic [SRC_ADDR_WIDTH-1:0] ROW_STEP_3X3 = 240;

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_LOAD,
        STATE_WEIGHT_GAP,
        STATE_WEIGHT_SWAP
    } state_t;

    state_t                        state_q;
    logic                          conv_1x1_q;
    logic                          mode_weight_q;
    logic [8:0]                    linear_q;
    logic [4:0]                    local_y_q;
    logic [4:0]                    local_x_q;
    logic                          row_end_q;
    logic [2:0]                    weight_shift_q;
    logic [SRC_ADDR_WIDTH-1:0]     src_addr_q;
    logic                          tile_y_q;
    logic                          tile_x_q;

    logic [SRC_ADDR_WIDTH-1:0]     activation_offset_1x1_d;
    logic [SRC_ADDR_WIDTH-1:0]     activation_offset_3x3_d;
    logic [SRC_ADDR_WIDTH-1:0]     activation_start_offset_d;
    logic [3:0]                    weight_tap_index_d;
    logic [SRC_ADDR_WIDTH-1:0]     weight_start_offset_d;
    logic                          activation_last;
    logic                          row_end_arm;
    logic                          pad_y;
    logic                          pad_x;

    // 1x1 activation offset = tile_y*8192 + tile_x*256 + cin_block*8.
    // The fields occupy disjoint bit positions, avoiding a wide adder tree.
    assign activation_offset_1x1_d = {
        {(SRC_ADDR_WIDTH-14){1'b0}},
        tile_y_i, 4'b0000, tile_x_i, 4'b0000, cin_block_i, 3'b000
    };

    // 3x3 starts at global (tile_y*16-1, tile_x*16-1).  Negative offsets are
    // intentional for top/left halo commands; load_zero_fill_o tells the
    // adapter not to access memory for those commands.
    always_comb begin
        case ({tile_y_i, tile_x_i, cin_block_i})
            3'b000: activation_offset_3x3_d = -528;
            3'b001: activation_offset_3x3_d = -520;
            3'b010: activation_offset_3x3_d = -272;
            3'b011: activation_offset_3x3_d = -264;
            3'b100: activation_offset_3x3_d = 7664;
            3'b101: activation_offset_3x3_d = 7672;
            3'b110: activation_offset_3x3_d = 7920;
            default: activation_offset_3x3_d = 7928;
        endcase
    end

    assign activation_start_offset_d = conv_1x1_i
                                     ? activation_offset_1x1_d
                                     : activation_offset_3x3_d;

    // A 1x1 command has only tap zero.  A 3x3 command selects one of nine
    // compile-time tap offsets without a general multiplier.
    always_comb begin
        if (conv_1x1_i) begin
            weight_tap_index_d = 4'd0;
        end else begin
            case ({kernel_y_i, kernel_x_i})
                4'b0000: weight_tap_index_d = 4'd0;
                4'b0001: weight_tap_index_d = 4'd1;
                4'b0010: weight_tap_index_d = 4'd2;
                4'b0100: weight_tap_index_d = 4'd3;
                4'b0101: weight_tap_index_d = 4'd4;
                4'b0110: weight_tap_index_d = 4'd5;
                4'b1000: weight_tap_index_d = 4'd6;
                4'b1001: weight_tap_index_d = 4'd7;
                4'b1010: weight_tap_index_d = 4'd8;
                default: weight_tap_index_d = 4'd0;
            endcase
        end
    end

    // offset = tap*256 + cin_block*128 + cout_block*8 + 7.
    assign weight_start_offset_d = {
        {(SRC_ADDR_WIDTH-12){1'b0}}, weight_tap_index_d,
        cin_block_i, 3'b000, cout_block_i, 3'b111
    };

    assign activation_last = conv_1x1_q
                           ? (linear_q == LAST_1X1_PIXEL)
                           : (linear_q == LAST_3X3_PIXEL);

    assign row_end_arm = conv_1x1_q
                       ? (local_x_q == 5'd14)
                       : (local_x_q == 5'd16);

    // All four 3x3 tiles touch two image boundaries.  The first/last local
    // row or column is padding according to the selected tile coordinate.
    assign pad_y = ((!tile_y_q) && (local_y_q == 5'd0)) ||
                   (  tile_y_q  && (local_y_q == 5'd17));
    assign pad_x = ((!tile_x_q) && (local_x_q == 5'd0)) ||
                   (  tile_x_q  && (local_x_q == 5'd17));

    assign start_ready_o          = (state_q == STATE_IDLE);
    assign busy_o                 = (state_q != STATE_IDLE);
    assign load_valid_o           = (state_q == STATE_LOAD);
    assign load_src_addr_o        = src_addr_q;
    assign load_src_lane_stride_o = mode_weight_q ? 5'd16 : 5'd1;
    assign load_dst_addr_o        = mode_weight_q
                                  ? {{(ACT_ADDR_WIDTH-3){1'b0}}, weight_shift_q}
                                  : linear_q;
    assign load_dst_bank_mask_o   = 8'hff;
    assign load_is_weight_o       = mode_weight_q;
    assign load_zero_fill_o       = load_valid_o && !mode_weight_q &&
                                    !conv_1x1_q && (pad_y || pad_x);
    assign load_last_o            = load_valid_o &&
                                    (mode_weight_q
                                        ? (weight_shift_q == 3'd7)
                                        : activation_last);
    assign weight_swap_o          = (state_q == STATE_WEIGHT_SWAP);

    always_ff @(posedge clk_i) begin
        if (!rst_n) begin
            state_q          <= STATE_IDLE;
            conv_1x1_q       <= 1'b0;
            mode_weight_q    <= 1'b0;
            linear_q         <= 9'd0;
            local_y_q        <= 5'd0;
            local_x_q        <= 5'd0;
            row_end_q        <= 1'b0;
            weight_shift_q   <= 3'd0;
            src_addr_q       <= '0;
            tile_y_q         <= 1'b0;
            tile_x_q         <= 1'b0;
            done_o           <= 1'b0;
        end else begin
            done_o <= 1'b0;

            case (state_q)
                STATE_IDLE: begin
                    if (start_i) begin
                        state_q        <= STATE_LOAD;
                        conv_1x1_q     <= conv_1x1_i;
                        mode_weight_q  <= load_weight_i;
                        linear_q       <= 9'd0;
                        local_y_q      <= 5'd0;
                        local_x_q      <= 5'd0;
                        row_end_q      <= 1'b0;
                        weight_shift_q <= 3'd0;
                        tile_y_q       <= tile_y_i;
                        tile_x_q       <= tile_x_i;

                        if (load_weight_i)
                            src_addr_q <= weight_base_i + weight_start_offset_d;
                        else
                            src_addr_q <= image_base_i +
                                          activation_start_offset_d;
                    end
                end

                STATE_LOAD: begin
                    if (load_ready_i) begin
                        if (mode_weight_q) begin
                            if (weight_shift_q == 3'd7) begin
                                state_q <= STATE_WEIGHT_GAP;
                            end else begin
                                weight_shift_q <= weight_shift_q + 1'b1;
                                src_addr_q     <= src_addr_q - 1'b1;
                            end
                        end else if (activation_last) begin
                            state_q <= STATE_IDLE;
                            done_o  <= 1'b1;
                        end else begin
                            linear_q <= linear_q + 1'b1;
                            src_addr_q <= src_addr_q +
                                          (row_end_q
                                              ? (conv_1x1_q
                                                    ? ROW_STEP_1X1
                                                    : ROW_STEP_3X3)
                                              : PIXEL_STEP);

                            // row_end_q is armed one command before the end of
                            // a row so it directly controls the wide incrementer.
                            if (row_end_q) begin
                                local_y_q <= local_y_q + 1'b1;
                                local_x_q <= 5'd0;
                                row_end_q <= 1'b0;
                            end else begin
                                local_x_q <= local_x_q + 1'b1;
                                row_end_q <= row_end_arm;
                            end
                        end
                    end
                end

                STATE_WEIGHT_GAP: begin
                    state_q <= STATE_WEIGHT_SWAP;
                end

                default: begin
                    // STATE_WEIGHT_SWAP: weight_swap_o is high for this cycle.
                    state_q <= STATE_IDLE;
                    done_o  <= 1'b1;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
