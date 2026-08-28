`timescale 1ns / 1ps
`default_nettype none

// Descriptor/AXI-beat to NPU destination-stream formatter.
//
// dma_fetch_engine supplies a stable descriptor context, its current group
// index, a low/high-half flag, and one active transfer phase. From that
// information this combinational block produces one 32-bit map-stream beat:
//
//   * DRAM data during phase_read_i;
//   * locally generated zero data during prefix, zero-row, or suffix phases;
//   * the activation/weight destination address and four-bank write mask;
//   * optional source-address metadata for simulation/debug monitors; and
//   * final-beat events used to retire a descriptor.
//
// There are no registers in this module. It does not issue AXI transactions,
// count beats, or write SRAM directly; those jobs belong to the fetch engine
// and the downstream SRAM adapter.
module dma_map_datapath #(
    // Source address/stride fields are observational only. Setting this to
    // zero ties those outputs low and avoids synthesizing their address adders.
    parameter integer MAP_SOURCE_METADATA = 0
)(
    // Current fetch phase. dma_fetch_engine makes these mutually exclusive.
    input  wire        phase_prefix_i,
    input  wire        phase_zero_i,
    input  wire        phase_read_i,
    input  wire        phase_suffix_i,

    // Current descriptor context. These fields remain stable until the final
    // map beat for the descriptor has been accepted.
    input  wire [31:0] command_source_i,
    input  wire [4:0]  command_stride_i,
    input  wire [8:0]  command_buffer_i,
    input  wire [7:0]  command_bank_mask_i,
    input  wire [5:0]  command_group_count_i,
    input  wire        command_pad_before_i,
    input  wire        command_pad_after_i,
    input  wire        command_is_weight_i,
    input  wire        command_last_i,

    // Fetch progress. One logical eight-channel group consists of a low and a
    // high 32-bit beat at the same group_index_i.
    input  wire [6:0]  row_beats_remaining_i,
    input  wire [5:0]  group_index_i,
    input  wire        beat_high_i,

    // AXI read data and destination backpressure. A transfer occurs only when
    // both map_valid_o and map_ready_i are high.
    input  wire [31:0] m_axi_rdata_i,
    input  wire [1:0]  m_axi_rresp_i,
    input  wire        m_axi_rvalid_i,
    input  wire        map_ready_i,
    input  wire        weight_swap_i,

    // Destination stream. map_weight_swap_o is a control pulse and is not
    // itself qualified by map_valid_o.
    output wire        map_valid_o,
    output wire [31:0] map_data_o,
    output wire [31:0] map_source_addr_o,
    output wire [4:0]  map_source_stride_o,
    output wire [8:0]  map_buffer_addr_o,
    output wire [7:0]  map_bank_mask_o,
    output wire        map_is_weight_o,
    output wire        map_zero_fill_o,
    output wire        map_last_o,
    output wire        map_weight_swap_o,

    // Events consumed by the fetch FSM and AGU handshake.
    output wire        map_fire_o,
    output wire        descriptor_complete_fire_o
);

    localparam [1:0] AXI_RESP_OKAY = 2'b00;

    wire [8:0]  prefix_buffer_addr;
    wire [8:0]  indexed_buffer_addr;
    wire [8:0]  fetched_buffer_addr;
    wire [8:0]  suffix_buffer_addr;
    wire [1:0]  map_addr_select;

    wire        map_uses_axi_data;
    wire [7:0]  low_bank_mask;
    wire [7:0]  high_bank_mask;

    // Local-padding phases always have a word available. The read phase has a
    // word available only when the AXI slave asserts RVALID.
    assign map_valid_o = phase_prefix_i || phase_zero_i || phase_suffix_i ||
                         (phase_read_i && m_axi_rvalid_i);
    assign map_fire_o  = map_valid_o && map_ready_i;

    // Only an OKAY read response is forwarded. A failing AXI response is
    // represented as zero on the map stream while dma_fetch_engine separately
    // raises its error pulse; this prevents unknown/bad data entering SRAM.
    assign map_uses_axi_data = phase_read_i &&
                               (m_axi_rresp_i == AXI_RESP_OKAY);
    assign map_data_o = map_uses_axi_data ? m_axi_rdata_i : 32'd0;

    // Source address/stride are monitor-only metadata. When enabled, the byte
    // address identifies the exact 32-bit word represented by this map beat:
    //
    //   source + group_index*8 + (beat_high ? 4 : 0)
    //
    // Prefix uses group zero; suffix uses group_count. When disabled, the
    // outputs are constants and none of this per-beat arithmetic is hardware.
    generate
        if (MAP_SOURCE_METADATA != 0) begin : gen_source_metadata
            wire [31:0] beat_byte_offset;
            wire [31:0] indexed_source_addr;
            wire [31:0] suffix_source_addr;

            assign beat_byte_offset = beat_high_i ? 32'd4 : 32'd0;
            assign indexed_source_addr = command_source_i +
                                         {23'd0, group_index_i, 3'b000} +
                                         beat_byte_offset;
            assign suffix_source_addr = command_source_i +
                                         {23'd0, command_group_count_i,
                                          3'b000} + beat_byte_offset;

            assign map_source_addr_o = (map_addr_select == 2'b00)
                                       ? command_source_i + beat_byte_offset
                                       : (map_addr_select == 2'b11)
                                         ? suffix_source_addr
                                         : indexed_source_addr;
            assign map_source_stride_o = command_stride_i;
        end else begin : gen_no_source_metadata
            assign map_source_addr_o   = 32'd0;
            assign map_source_stride_o = 5'd0;
        end
    endgenerate

    // Destination SRAM address equations. Each address stores all eight
    // channels of one logical group across banks 0..7; the two 32-bit halves
    // use the same address but different bank masks.
    //
    //   prefix : base
    //   zero   : base + group_index
    //   fetched: base + pad_before + group_index
    //   suffix : base + group_count
    assign prefix_buffer_addr  = command_buffer_i;
    assign indexed_buffer_addr = command_buffer_i + group_index_i;
    assign fetched_buffer_addr = command_buffer_i +
                                  (command_pad_before_i ? 1'b1 : 1'b0) +
                                  group_index_i;
    assign suffix_buffer_addr  = command_buffer_i + command_group_count_i;

    // Compact phase encoding used by both the destination and optional source
    // address multiplexers: 00 prefix, 01 zero row, 10 fetched, 11 suffix.
    assign map_addr_select[0] = phase_zero_i || phase_suffix_i;
    assign map_addr_select[1] = phase_read_i || phase_suffix_i;

    assign map_buffer_addr_o = (map_addr_select == 2'b00)
                               ? prefix_buffer_addr
                               : (map_addr_select == 2'b01)
                                 ? indexed_buffer_addr
                                 : (map_addr_select == 2'b10)
                                   ? fetched_buffer_addr
                                   : suffix_buffer_addr;

    // A logical group has eight one-byte channels. The low beat writes banks
    // 0..3 and the high beat writes banks 4..7. The descriptor mask can still
    // suppress individual banks within either half.
    assign low_bank_mask  = command_bank_mask_i & 8'h0f;
    assign high_bank_mask = command_bank_mask_i & 8'hf0;
    assign map_bank_mask_o = beat_high_i ? high_bank_mask : low_bank_mask;

    // These fields describe the current output beat. map_zero_fill_o allows a
    // monitor to distinguish locally generated halo data from DRAM data.
    assign map_is_weight_o     = command_is_weight_i;
    assign map_zero_fill_o     = phase_prefix_i || phase_zero_i ||
                                 phase_suffix_i;
    // map_last_o marks the final accepted-data position of the entire DMA
    // operation, not the end of every row. It can only be asserted on the high
    // half because that half completes an eight-channel group.
    assign map_last_o = beat_high_i && command_last_i &&
                        ((phase_zero_i &&
                          (group_index_i == command_group_count_i - 1'b1)) ||
                         (phase_read_i && !command_pad_after_i &&
                          (group_index_i == command_group_count_i - 1'b1)) ||
                         phase_suffix_i);
    // Weight swap occurs after the weight descriptor has retired. It travels
    // beside the data stream as a separate one-cycle control indication.
    assign map_weight_swap_o = weight_swap_i;

    // Retire the descriptor on its final *accepted* high-bank beat:
    //
    //   * a locally generated zero row retires at its final group;
    //   * a fetched row without a suffix retires when one AXI beat remains;
    //   * a right-padding descriptor retires after its two-beat suffix.
    //
    // Qualifying with map_fire_o means downstream backpressure cannot advance
    // the AGU early. The weight path consequently gets its required disabled
    // cycle between the final shift and the separate swap pulse.
    assign descriptor_complete_fire_o = map_fire_o && beat_high_i &&
        ((phase_zero_i &&
          (group_index_i == command_group_count_i - 1'b1)) ||
         (phase_read_i &&
          (row_beats_remaining_i == 7'd1) && !command_pad_after_i) ||
         phase_suffix_i);

endmodule

`default_nettype wire
