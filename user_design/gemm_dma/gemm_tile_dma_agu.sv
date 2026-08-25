`timescale 1ns / 1ps
`default_nettype none

// Pointer-and-stride DMA address generator for one tile of an 8x8
// weight-stationary systolic array.
//
// The CPU/software supplies the byte address of the first element of the
// current tile.  Keeping tile-index multiplication in software makes this AGU
// useful for different matrix dimensions without synthesizing multipliers.
//
// Row-major source matrices:
//   A is M x K, address(A[m][k]) = A_base + m*A_row_stride + k
//   B is K x N, address(B[k][n]) = B_base + k*B_row_stride + n
//
// Activation-panel operation (load_weight_i == 0):
//   source_base_i points to A[m0][k0]
//   source_row_stride_i is the byte distance between A rows
//   activation_last_addr_i is panel_rows-1 (0 means one row, 255 means 256)
//   command p loads A[m0+p][k0 + lane] into activation_bank[lane][p]
//
// Weight-tile operation (load_weight_i == 1):
//   source_base_i points to B[k0][n0]
//   source_row_stride_i is the byte distance between B rows
//   exactly eight commands load columns 7,6,...,0, matching the supplied
//   dma_load_weights_slice task.  Lane r reads B[k0+r][n0+column].
//
// One accepted load command represents eight byte reads.  A downstream memory
// adapter may perform those reads in parallel (for a wide/banked memory) or
// serialize them.  load_ready_i must acknowledge the whole eight-byte group;
// for weights it must not acknowledge until the bytes have actually been
// applied to weight_shift_in on a shift clock.
//
// K and N edge tiles must be zero-padded to eight elements by software or the
// memory adapter.  M edge tiles are supported directly through
// activation_last_addr_i.
module gemm_tile_dma_agu #(
    parameter int unsigned SRC_ADDR_WIDTH = 32,
    parameter int unsigned ACT_ADDR_WIDTH = 9
)(
    input  logic                              clk_i,
    input  logic                              rst_n,

    input  logic                              start_i,
    output logic                              start_ready_o,
    input  logic                              load_weight_i,
    input  logic [SRC_ADDR_WIDTH-1:0]         source_base_i,
    input  logic [SRC_ADDR_WIDTH-1:0]         source_row_stride_i,
    input  logic [ACT_ADDR_WIDTH-1:0]         activation_last_addr_i,

    output logic                              busy_o,
    output logic                              done_o,

    output logic                              load_valid_o,
    input  logic                              load_ready_i,
    output logic [SRC_ADDR_WIDTH-1:0]         load_src_addr_o,
    output logic [SRC_ADDR_WIDTH-1:0]         load_src_lane_stride_o,
    output logic [ACT_ADDR_WIDTH-1:0]         load_dst_addr_o,
    output logic [7:0]                        load_dst_bank_mask_o,
    output logic                              load_is_weight_o,
    output logic                              load_zero_fill_o,
    output logic                              load_last_o,
    output logic                              weight_swap_o
);

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_LOAD,
        STATE_WEIGHT_GAP,
        STATE_WEIGHT_SWAP
    } state_t;

    state_t                             state_q;
    logic                               mode_weight_q;
    logic [ACT_ADDR_WIDTH-1:0]          index_q;
    logic [ACT_ADDR_WIDTH-1:0]          activation_last_q;
    logic [2:0]                         weight_shift_q;
    logic [SRC_ADDR_WIDTH-1:0]          src_addr_q;
    logic [SRC_ADDR_WIDTH-1:0]          source_row_stride_q;

    localparam logic [SRC_ADDR_WIDTH-1:0] ONE =
        {{(SRC_ADDR_WIDTH-1){1'b0}}, 1'b1};
    localparam logic [SRC_ADDR_WIDTH-1:0] SEVEN =
        {{(SRC_ADDR_WIDTH-3){1'b0}}, 3'd7};

    assign start_ready_o          = (state_q == STATE_IDLE);
    assign busy_o                 = (state_q != STATE_IDLE);
    assign load_valid_o           = (state_q == STATE_LOAD);
    assign load_src_addr_o        = src_addr_q;
    assign load_src_lane_stride_o = mode_weight_q ? source_row_stride_q : ONE;
    assign load_dst_addr_o        = mode_weight_q
                                  ? {{(ACT_ADDR_WIDTH-3){1'b0}}, weight_shift_q}
                                  : index_q;
    assign load_dst_bank_mask_o   = 8'hff;
    assign load_is_weight_o       = mode_weight_q;
    assign load_zero_fill_o       = 1'b0;
    assign load_last_o            = load_valid_o &&
                                    (mode_weight_q
                                     ? (weight_shift_q == 3'd7)
                                     : (index_q == activation_last_q));
    assign weight_swap_o          = (state_q == STATE_WEIGHT_SWAP);

    always_ff @(posedge clk_i) begin
        if (!rst_n) begin
            state_q            <= STATE_IDLE;
            mode_weight_q      <= 1'b0;
            index_q            <= '0;
            activation_last_q  <= '0;
            weight_shift_q     <= '0;
            src_addr_q         <= '0;
            source_row_stride_q <= '0;
            done_o             <= 1'b0;
        end else begin
            done_o <= 1'b0;

            case (state_q)
                STATE_IDLE: begin
                    if (start_i) begin
                        mode_weight_q       <= load_weight_i;
                        activation_last_q   <= activation_last_addr_i;
                        source_row_stride_q <= source_row_stride_i;
                        index_q             <= '0;
                        weight_shift_q      <= '0;
                        state_q             <= STATE_LOAD;

                        // The supplied NPU weight loader shifts output columns
                        // from 7 down to 0.  Activation panels start exactly at
                        // the software-provided pointer.
                        if (load_weight_i)
                            src_addr_q <= source_base_i + SEVEN;
                        else
                            src_addr_q <= source_base_i;
                    end
                end

                STATE_LOAD: begin
                    if (load_ready_i) begin
                        if (mode_weight_q) begin
                            if (weight_shift_q == 3'd7) begin
                                state_q <= STATE_WEIGHT_GAP;
                            end else begin
                                weight_shift_q <= weight_shift_q + 1'b1;
                                src_addr_q     <= src_addr_q - ONE;
                            end
                        end else begin
                            if (index_q == activation_last_q) begin
                                state_q <= STATE_IDLE;
                                done_o  <= 1'b1;
                            end else begin
                                index_q    <= index_q + 1'b1;
                                src_addr_q <= src_addr_q + source_row_stride_q;
                            end
                        end
                    end
                end

                STATE_WEIGHT_GAP: begin
                    // Match the reference task's disabled shift cycle between
                    // the eighth shift and swap_weights.
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
