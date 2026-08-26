`timescale 1ns / 1ps
`default_nettype none

// Row-descriptor generator for the packed 1x1/3x3 DMA source layouts.
//
// The CPU passes a pointer to one already-packed source object at start:
//
//   1x1 activation tile : packed[16][16][8]       = 2048 bytes
//   3x3 activation tile : packed_valid[17][17][8] = 2312 bytes
//   weight slice        : packed_shift[8][8]      =   64 bytes
//
// The 3x3 object contains the 17x17 valid part of the selected 18x18 source
// window. Because this accelerator splits a 32x32 image into four 16x16
// tiles, each window has exactly one exterior padding row and one exterior
// padding column. dma_a inserts those 35 zero groups locally.
//
// One accepted descriptor represents a complete packed activation row or a
// complete packed weight slice. dma_a converts it to a long AXI INCR burst
// and steers each returned 32-bit beat directly to one half of the SRAM banks.
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

    // Internal packed-row descriptor. Every field remains stable until
    // load_ready_i acknowledges the complete row/slice, including delivery
    // of its final map group to the downstream adapter.
    output logic                         load_valid_o,
    input  logic                         load_ready_i,
    output logic [SRC_ADDR_WIDTH-1:0]    load_src_addr_o,
    output logic [4:0]                   load_src_lane_stride_o,
    output logic [ACT_ADDR_WIDTH-1:0]    load_dst_addr_o,
    output logic [7:0]                   load_dst_bank_mask_o,
    output logic [5:0]                   load_group_count_o,
    output logic                         load_pad_before_o,
    output logic                         load_pad_after_o,
    output logic                         load_is_weight_o,
    output logic                         load_zero_fill_o,
    output logic                         load_last_o,
    output logic                         weight_swap_o
);

    localparam logic [SRC_ADDR_WIDTH-1:0] ROW_BYTES_1X1 = 128;
    localparam logic [SRC_ADDR_WIDTH-1:0] ROW_BYTES_3X3 = 136;

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_LOAD,
        STATE_WEIGHT_GAP,
        STATE_WEIGHT_SWAP
    } state_t;

    state_t                    state_q;
    logic                      conv_1x1_q;
    logic                      mode_weight_q;
    logic [4:0]                row_q;
    logic [SRC_ADDR_WIDTH-1:0] src_addr_q;
    logic                      tile_y_q;
    logic                      tile_x_q;

    logic                      pad_row;
    logic                      final_row;
    logic [ACT_ADDR_WIDTH-1:0] destination_row_base;

    // cin/cout/kernel select which packed object software points at. They
    // remain in the programming register for compatibility and diagnostics,
    // but deliberately do not add an offset to the supplied packed pointer.

    always_comb begin
        pad_row = !conv_1x1_q &&
                  (((!tile_y_q) && (row_q == 5'd0)) ||
                   (  tile_y_q  && (row_q == 5'd17)));
        final_row = conv_1x1_q ? (row_q == 5'd15)
                               : (row_q == 5'd17);

        if (conv_1x1_q)
            destination_row_base = {row_q[3:0], 4'b0000};
        else
            // row*18 = row*16 + row*2.
            destination_row_base =
                ({{(ACT_ADDR_WIDTH-5){1'b0}}, row_q} << 4) +
                ({{(ACT_ADDR_WIDTH-5){1'b0}}, row_q} << 1);
    end

    assign start_ready_o          = (state_q == STATE_IDLE);
    assign busy_o                 = (state_q != STATE_IDLE);
    assign load_valid_o           = (state_q == STATE_LOAD);
    assign load_src_addr_o        = src_addr_q;
    assign load_src_lane_stride_o = 5'd1;
    assign load_dst_addr_o        = mode_weight_q ? '0
                                                  : destination_row_base;
    assign load_dst_bank_mask_o   = 8'hff;
    assign load_group_count_o     = mode_weight_q ? 6'd8 :
                                    conv_1x1_q    ? 6'd16 :
                                    pad_row       ? 6'd18 : 6'd17;
    assign load_pad_before_o      = load_valid_o && !mode_weight_q &&
                                    !conv_1x1_q && !pad_row && !tile_x_q;
    assign load_pad_after_o       = load_valid_o && !mode_weight_q &&
                                    !conv_1x1_q && !pad_row && tile_x_q;
    assign load_is_weight_o       = mode_weight_q;
    assign load_zero_fill_o       = load_valid_o && !mode_weight_q && pad_row;
    assign load_last_o            = load_valid_o &&
                                    (mode_weight_q || final_row);
    assign weight_swap_o          = (state_q == STATE_WEIGHT_SWAP);

    always_ff @(posedge clk_i) begin
        if (!rst_n) begin
            state_q         <= STATE_IDLE;
            conv_1x1_q      <= 1'b0;
            mode_weight_q   <= 1'b0;
            row_q           <= 5'd0;
            src_addr_q      <= '0;
            tile_y_q        <= 1'b0;
            tile_x_q        <= 1'b0;
            done_o          <= 1'b0;
        end else begin
            done_o <= 1'b0;

            case (state_q)
                STATE_IDLE: begin
                    if (start_i) begin
                        state_q       <= STATE_LOAD;
                        conv_1x1_q    <= conv_1x1_i;
                        mode_weight_q <= load_weight_i;
                        row_q         <= 5'd0;
                        tile_y_q      <= tile_y_i;
                        tile_x_q      <= tile_x_i;
                        src_addr_q    <= load_weight_i ? weight_base_i
                                                       : image_base_i;
                    end
                end

                STATE_LOAD: begin
                    if (load_ready_i) begin
                        if (mode_weight_q) begin
                            state_q <= STATE_WEIGHT_GAP;
                        end else if (final_row) begin
                            state_q <= STATE_IDLE;
                            done_o  <= 1'b1;
                        end else begin
                            row_q <= row_q + 1'b1;
                            if (!pad_row)
                                src_addr_q <= src_addr_q +
                                              (conv_1x1_q
                                                   ? ROW_BYTES_1X1
                                                   : ROW_BYTES_3X3);
                        end
                    end
                end

                STATE_WEIGHT_GAP: begin
                    state_q <= STATE_WEIGHT_SWAP;
                end

                default: begin
                    // STATE_WEIGHT_SWAP: weight_swap_o is high for one cycle.
                    state_q <= STATE_IDLE;
                    done_o  <= 1'b1;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
