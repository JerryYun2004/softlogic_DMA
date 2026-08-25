`timescale 1ns / 1ps
`default_nettype none

// Fixed-function, loop-unrolled DMA address generator for the supplied YOLO
// 1x1 workload:
//
//   input  X[32][32][16], byte-addressed HWC
//   weight W[16][16],     byte-addressed CI-major/CO-minor
//   output Y[32][32][16]
//   spatial tile = 16x16, channel block = 8
//
// The loop over the eight input-channel lanes is unrolled into one map command.
// An accepted activation command represents:
//
//   for r = 0..7:
//     activation_bank[r][load_dst_addr_o] <-
//         memory[load_src_addr_o + r]
//
// The loop over the eight PE rows is also unrolled for a weight command:
//
//   for r = 0..7:
//     weight_shift_in[r] <-
//         memory[load_src_addr_o + r * load_src_lane_stride_o]
//
// One activation start emits 256 commands, matching
// dma_load_1x1_activations(ty, tx, cin_blk) in tb_npu_top_with_srams.sv.
// One weight start emits eight commands in output-column order 7,6,...,0,
// matching dma_load_weights_slice(w_slice), followed by one disabled shift
// cycle and a one-cycle weight_swap_o pulse.
module conv1x1_hwc_channel_dma_agu #(
    parameter int unsigned SRC_ADDR_WIDTH = 32,
    parameter int unsigned ACT_ADDR_WIDTH = 9
)(
    input  logic                         clk_i,
    input  logic                         rst_n,

    // Configuration is sampled when start_i is accepted in the idle state.
    input  logic                         start_i,
    output logic                         start_ready_o,
    input  logic                         load_weight_i,
    input  logic [SRC_ADDR_WIDTH-1:0]    image_base_i,
    input  logic [SRC_ADDR_WIDTH-1:0]    weight_base_i,
    input  logic                         tile_y_i,
    input  logic                         tile_x_i,
    input  logic                         cin_block_i,
    input  logic                         cout_block_i,

    output logic                         busy_o,
    output logic                         done_o,

    // Protocol-neutral eight-lane load-group stream. All command fields remain
    // stable while load_valid_o is asserted and load_ready_i is deasserted.
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

    // X[y][x][ci] is flattened as ((y * 32 + x) * 16) + ci.
    // Moving to the next pixel in one 16-pixel tile advances by 16 bytes.
    // Moving from tile-local x=15 to x=0 of the next image row advances by
    // 512 - 15*16 = 272 bytes.
    localparam logic [SRC_ADDR_WIDTH-1:0] ACT_PIXEL_STEP = 16;
    localparam logic [SRC_ADDR_WIDTH-1:0] ACT_ROW_STEP   = 272;

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_LOAD,
        STATE_WEIGHT_GAP,
        STATE_WEIGHT_SWAP
    } state_t;

    state_t                        state_q;
    logic                          mode_weight_q;
    logic [3:0]                    act_y_q;
    logic [3:0]                    act_x_q;
    logic                          act_row_end_q;
    logic [2:0]                    weight_shift_q;
    logic [SRC_ADDR_WIDTH-1:0]     src_addr_q;

    logic [SRC_ADDR_WIDTH-1:0]     activation_start_offset_d;
    logic [SRC_ADDR_WIDTH-1:0]     weight_start_offset_d;
    logic                          activation_last;

    // 16 rows * 32 pixels/row * 16 channels = 8192 bytes per tile_y.
    // 16 pixels * 16 channels = 256 bytes per tile_x.
    // One channel block contains eight bytes.
    // The three fields occupy disjoint bit positions, so concatenation avoids
    // a tree of full-width adders.
    assign activation_start_offset_d = {
        {(SRC_ADDR_WIDTH-14){1'b0}},
        tile_y_i, 4'b0000, tile_x_i, 4'b0000, cin_block_i, 3'b000
    };

    // W[ci][co] is flattened as ci*16 + co.  Start at output column 7 of the
    // selected 8x8 slice; subsequent commands decrement the column address.
    // offset = cin_block*128 + cout_block*8 + 7.
    assign weight_start_offset_d = {
        {(SRC_ADDR_WIDTH-8){1'b0}},
        cin_block_i, 3'b000, cout_block_i, 3'b111
    };

    assign activation_last       = (&act_y_q) && (&act_x_q);

    assign start_ready_o         = (state_q == STATE_IDLE);
    assign busy_o                = (state_q != STATE_IDLE);
    assign load_valid_o          = (state_q == STATE_LOAD);
    assign load_src_addr_o       = src_addr_q;
    assign load_src_lane_stride_o = mode_weight_q ? 5'd16 : 5'd1;
    assign load_dst_addr_o       = mode_weight_q
                                 ? {{(ACT_ADDR_WIDTH-3){1'b0}}, weight_shift_q}
                                 : {{(ACT_ADDR_WIDTH-8){1'b0}}, act_y_q, act_x_q};
    assign load_dst_bank_mask_o  = 8'hff;
    assign load_is_weight_o      = mode_weight_q;
    assign load_zero_fill_o      = 1'b0;
    assign load_last_o           = load_valid_o &&
                                   (mode_weight_q
                                       ? (weight_shift_q == 3'd7)
                                       : activation_last);
    assign weight_swap_o         = (state_q == STATE_WEIGHT_SWAP);

    always_ff @(posedge clk_i) begin
        if (!rst_n) begin
            state_q          <= STATE_IDLE;
            mode_weight_q    <= 1'b0;
            act_y_q          <= 4'd0;
            act_x_q          <= 4'd0;
            act_row_end_q    <= 1'b0;
            weight_shift_q   <= 3'd0;
            src_addr_q       <= '0;
            done_o           <= 1'b0;
        end else begin
            done_o <= 1'b0;

            case (state_q)
                STATE_IDLE: begin
                    if (start_i) begin
                        state_q        <= STATE_LOAD;
                        mode_weight_q  <= load_weight_i;
                        act_y_q        <= 4'd0;
                        act_x_q        <= 4'd0;
                        act_row_end_q  <= 1'b0;
                        weight_shift_q <= 3'd0;

                        if (load_weight_i)
                            src_addr_q <= weight_base_i + weight_start_offset_d;
                        else
                            src_addr_q <= image_base_i + activation_start_offset_d;
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
                        end else begin
                            if (activation_last) begin
                                state_q <= STATE_IDLE;
                                done_o  <= 1'b1;
                            end else begin
                                src_addr_q <= src_addr_q +
                                              (act_row_end_q
                                                  ? ACT_ROW_STEP
                                                  : ACT_PIXEL_STEP);

                                // Arm the row-end decision one command early so
                                // the 32-bit incrementer is driven by a register,
                                // rather than by a comparator on its critical path.
                                if (act_row_end_q) begin
                                    act_y_q       <= act_y_q + 1'b1;
                                    act_x_q       <= 4'd0;
                                    act_row_end_q <= 1'b0;
                                end else begin
                                    act_x_q       <= act_x_q + 1'b1;
                                    act_row_end_q <= (act_x_q == 4'd14);
                                end
                            end
                        end
                    end
                end

                STATE_WEIGHT_GAP: begin
                    // Match the reference task's disabled shift cycle before
                    // swap_weights is asserted.
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
