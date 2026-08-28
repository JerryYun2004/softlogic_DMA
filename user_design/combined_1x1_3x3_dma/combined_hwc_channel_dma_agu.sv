`timescale 1ns / 1ps
`default_nettype none

// Address-generation unit (AGU) for packed activation objects and weights.
//
// Software starts one operation by supplying a pointer to exactly one packed
// source object:
//
//   1x1 activation tile : packed[16][16][8]       = 2048 bytes
//   3x3 activation tile : packed_valid[17][17][8] = 2312 bytes
//   weight slice        : packed_shift[8][8]      =   64 bytes
//
// Each bracketed [8] entry is an eight-channel group occupying eight
// consecutive bytes (two 32-bit AXI beats). This AGU assumes that software has
// already chosen and packed the object; it does not de-interleave a raw HWC16
// tensor and does not calculate a channel-block offset from a larger tensor.
//
// A 3x3 operation presents an 18x18 logical activation window to the SRAMs.
// The packed object contains its 17x17 non-padding region. Since a 32x32 image
// is split into four 16x16 tiles, tile_y selects whether the missing row is at
// the top or bottom, and tile_x selects whether the missing column is at the
// left or right. Padding groups are generated locally downstream and consume
// no DRAM bytes.
//
// One load_valid_o descriptor represents one complete activation row, one
// complete all-zero padding row, or one 64-byte weight slice. The descriptor
// remains unchanged until load_ready_i reports that its final high-half map
// beat reached the SRAM adapter. The fetch engine may split a descriptor into
// multiple AXI bursts at a 4-KiB boundary without involving this AGU.
//
// This module generates read descriptors only. It does not own the AXI bus,
// store returned data, arbitrate SRAM ports, or write NPU results to DRAM.
module combined_hwc_channel_dma_agu #(
    parameter int unsigned SRC_ADDR_WIDTH = 32,
    parameter int unsigned ACT_ADDR_WIDTH = 9
)(
    input  logic                         clk_i,
    input  logic                         rst_n,

    // A start request is accepted while start_ready_o is high. The operation
    // mode and pointer are captured at that time and held internally.
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

    // Packed row sizes: 16 or 17 groups multiplied by eight bytes per group.
    localparam logic [SRC_ADDR_WIDTH-1:0] ROW_BYTES_1X1 = 128;
    localparam logic [SRC_ADDR_WIDTH-1:0] ROW_BYTES_3X3 = 136;

    // STATE_LOAD exposes and holds the current descriptor. Weight loading has
    // two additional timing states: one inactive gap cycle after the final
    // weight shift, followed by one cycle that asserts weight_swap_o.
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

    // Values derived combinationally from the captured mode and row index.
    logic                      pad_row;
    logic                      final_row;
    logic [ACT_ADDR_WIDTH-1:0] destination_row_base;

    // cin_block_i, cout_block_i, kernel_y_i, and kernel_x_i do not participate
    // in an address equation inside this AGU. They identify which object
    // software selected; software expresses that selection by passing the
    // corresponding packed-object pointer in image_base_i/weight_base_i.

    always_comb begin
        // 1x1 has no local halo row. For 3x3, the upper tile receives a top
        // zero row and the lower tile receives a bottom zero row.
        pad_row = !conv_1x1_q &&
                  (((!tile_y_q) && (row_q == 5'd0)) ||
                   (  tile_y_q  && (row_q == 5'd17)));
        final_row = conv_1x1_q ? (row_q == 5'd15)
                               : (row_q == 5'd17);

        // Destination SRAM rows are linearized in row-major order:
        //   1x1: destination = row*16
        //   3x3: destination = row*18
        if (conv_1x1_q)
            destination_row_base = {row_q[3:0], 4'b0000};
        else
            // row*18 = row*16 + row*2.
            destination_row_base =
                ({{(ACT_ADDR_WIDTH-5){1'b0}}, row_q} << 4) +
                ({{(ACT_ADDR_WIDTH-5){1'b0}}, row_q} << 1);
    end

    // Operation-level handshake/status.
    assign start_ready_o          = (state_q == STATE_IDLE);
    assign busy_o                 = (state_q != STATE_IDLE);
    assign load_valid_o           = (state_q == STATE_LOAD);
    // Descriptor contents. Source stride is metadata expressed in byte lanes;
    // the functional fetch path reads consecutive 32-bit AXI words.
    assign load_src_addr_o        = src_addr_q;
    assign load_src_lane_stride_o = 5'd1;
    assign load_dst_addr_o        = mode_weight_q ? '0
                                                  : destination_row_base;
    assign load_dst_bank_mask_o   = 8'hff;
    // Group counts describe useful/local groups, not AXI beats. Each group is
    // delivered as two beats. A padding row spans all 18 destination columns;
    // a normal 3x3 row fetches 17 groups and adds one local edge group.
    assign load_group_count_o     = mode_weight_q ? 6'd8 :
                                    conv_1x1_q    ? 6'd16 :
                                    pad_row       ? 6'd18 : 6'd17;
    // Horizontal halo placement: tile_x=0 adds the missing group before the
    // 17 fetched groups, while tile_x=1 adds it after them. A pad row uses the
    // zero-fill descriptor instead and therefore needs no prefix/suffix.
    assign load_pad_before_o      = load_valid_o && !mode_weight_q &&
                                    !conv_1x1_q && !pad_row && !tile_x_q;
    assign load_pad_after_o       = load_valid_o && !mode_weight_q &&
                                    !conv_1x1_q && !pad_row && tile_x_q;
    assign load_is_weight_o       = mode_weight_q;
    assign load_zero_fill_o       = load_valid_o && !mode_weight_q && pad_row;
    // load_last_o marks the final descriptor of the operation. A weight load
    // consists of one descriptor; activation loads contain one per row.
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
                    // Capture all fields that affect the descriptor schedule.
                    // The pointer is already the base of the selected object.
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
                    // Do not advance the row or source address until the fetch
                    // engine has delivered the entire descriptor downstream.
                    if (load_ready_i) begin
                        if (mode_weight_q) begin
                            state_q <= STATE_WEIGHT_GAP;
                        end else if (final_row) begin
                            state_q <= STATE_IDLE;
                            done_o  <= 1'b1;
                        end else begin
                            row_q <= row_q + 1'b1;
                            // A locally generated padding row consumes no
                            // source bytes, so its successor reuses src_addr_q.
                            if (!pad_row)
                                src_addr_q <= src_addr_q +
                                              (conv_1x1_q
                                                   ? ROW_BYTES_1X1
                                                   : ROW_BYTES_3X3);
                        end
                    end
                end

                STATE_WEIGHT_GAP: begin
                    // One cycle with load_valid_o=0 and weight_swap_o=0 keeps
                    // the final shift and bank swap as distinct operations.
                    state_q <= STATE_WEIGHT_SWAP;
                end

                default: begin
                    // STATE_WEIGHT_SWAP: weight_swap_o is high for this cycle;
                    // completion is reported as the AGU returns to idle.
                    state_q <= STATE_IDLE;
                    done_o  <= 1'b1;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
