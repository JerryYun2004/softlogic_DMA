`timescale 1ns / 1ps
`default_nettype none

// Row/slice descriptor execution engine for dma_a.
//
// For each stable AGU descriptor this module:
//
//   1. captures the destination/mode context;
//   2. optionally emits a two-beat zero prefix for a left halo column;
//   3. either emits a complete local-zero row or reads packed words from DRAM;
//   4. splits AXI INCR requests at 4-KiB boundaries when necessary;
//   5. converts every pair of 32-bit words into one eight-channel map group;
//   6. optionally emits a two-beat zero suffix for a right halo column; and
//   7. acknowledges the descriptor only when its final map beat is accepted.
//
// State and AXI progress are owned here. dma_axi_burst_planner performs the
// combinational page-boundary calculation, while dma_map_datapath formats the
// output beat and detects final accepted beats. This block has no data FIFO:
// map_ready directly backpressures AXI RREADY, preserving ordering and avoiding
// extra storage.
module dma_fetch_engine #(
    // Enables observational source address/stride reconstruction. It does not
    // change read addresses, destinations, or transfer scheduling.
    parameter integer MAP_SOURCE_METADATA = 0
)(
    input  wire        clk,
    input  wire        rstn,

    // Stable AGU descriptor stream. load_ready_o is asserted at descriptor
    // completion, so the AGU keeps these inputs unchanged during all phases.
    input  wire        load_valid_i,
    output wire        load_ready_o,
    input  wire [31:0] load_source_addr_i,
    input  wire [4:0]  load_source_stride_i,
    input  wire [8:0]  load_buffer_addr_i,
    input  wire [7:0]  load_bank_mask_i,
    input  wire [5:0]  load_group_count_i,
    input  wire        load_pad_before_i,
    input  wire        load_pad_after_i,
    input  wire        load_is_weight_i,
    input  wire        load_zero_fill_i,
    input  wire        load_last_i,
    input  wire        weight_swap_i,

    // DRAM-facing read-only AXI4 master. Each beat is four bytes and all bursts
    // use incrementing addresses.
    output wire [31:0] m_axi_araddr,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready,

    // NPU destination stream. map_valid/map_ready is the only data-transfer
    // handshake; all map payload fields describe that same beat.
    output wire        map_valid,
    input  wire        map_ready,
    output wire [31:0] map_data,
    output wire [31:0] map_source_addr,
    output wire [4:0]  map_source_stride,
    output wire [8:0]  map_buffer_addr,
    output wire [7:0]  map_bank_mask,
    output wire        map_is_weight,
    output wire        map_zero_fill,
    output wire        map_last,
    output wire        map_weight_swap,

    // Status/debug events. read_error_pulse_o lasts one cycle for each detected
    // bad RRESP or RLAST-position mismatch; the control block makes it sticky.
    output reg         read_error_pulse_o,
    output wire        fetch_active_o
);

    localparam [1:0] AXI_RESP_OKAY = 2'b00;

    // Fetch-state roles:
    //   IDLE   capture one descriptor
    //   PREFIX emit one local zero group before fetched data
    //   ZERO   emit an entire descriptor using local zeros, with no AXI read
    //   AR     present the next AXI read-address request
    //   R      consume read data for the current burst
    //   SUFFIX emit one local zero group after fetched data
    localparam [2:0] FETCH_IDLE   = 3'd0;
    localparam [2:0] FETCH_PREFIX = 3'd1;
    localparam [2:0] FETCH_ZERO   = 3'd2;
    localparam [2:0] FETCH_AR     = 3'd3;
    localparam [2:0] FETCH_R      = 3'd4;
    localparam [2:0] FETCH_SUFFIX = 3'd5;

    // Current row/slice descriptor. Functional source address is held
    // separately in read_addr_q because it advances after each accepted word.
    reg [2:0]  fetch_state_q;
    reg [8:0]  command_buffer_q;
    reg [7:0]  command_bank_mask_q;
    reg [5:0]  command_group_count_q;
    reg        command_pad_before_q;
    reg        command_pad_after_q;
    reg        command_is_weight_q;
    reg        command_last_q;

    // AXI burst tracking:
    //   read_addr_q             byte address of the next unread word
    //   row_beats_remaining_q   unread words in the complete descriptor
    //   burst_beats_left_q      unread words in the current AXI burst
    //
    // The two counters differ when a descriptor is split at a 4-KiB boundary.
    // burst_beats_left_q is also the expected-position reference for RLAST.
    reg [31:0] read_addr_q;
    reg [6:0]  row_beats_remaining_q;
    reg [6:0]  burst_beats_left_q;

    // Direct steering state. beat_high_q=0 selects banks 0..3; the following
    // accepted beat sets beat_high_q=1 and selects banks 4..7 at the same group
    // address. group_index_q advances only after that high half is accepted.
    reg [5:0] group_index_q;
    reg       beat_high_q;

    wire phase_prefix;
    wire phase_zero;
    wire phase_ar;
    wire phase_read;
    wire phase_suffix;
    wire map_fire;
    wire r_fire;
    wire [10:0] next_burst_beats;
    wire [31:0] metadata_source;
    wire [4:0]  metadata_stride;

    // One-hot phase decode passed to the combinational map formatter.
    assign phase_prefix = (fetch_state_q == FETCH_PREFIX);
    assign phase_zero   = (fetch_state_q == FETCH_ZERO);
    assign phase_ar     = (fetch_state_q == FETCH_AR);
    assign phase_read   = (fetch_state_q == FETCH_R);
    assign phase_suffix = (fetch_state_q == FETCH_SUFFIX);

    assign fetch_active_o = (fetch_state_q != FETCH_IDLE);

    // Choose min(words remaining in descriptor, words before next 4-KiB page).
    // next_burst_beats fits in seven bits because all current descriptors have
    // at most 36 beats, even though the planner uses wider generic arithmetic.
    dma_axi_burst_planner burst_planner_i (
        .read_addr_i           (read_addr_q),
        .row_beats_remaining_i (row_beats_remaining_q),
        .next_burst_beats_o    (next_burst_beats),
        .arlen_o               (m_axi_arlen)
    );

    // AXI request attributes are fixed: 4-byte transfers and INCR bursts.
    // ARVALID remains asserted throughout FETCH_AR until ARREADY completes it.
    assign m_axi_araddr  = read_addr_q;
    assign m_axi_arsize  = 3'b010;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arvalid = phase_ar;

    // There is no activation-data widening register or FIFO to fill. If the
    // SRAM adapter withdraws map_ready, RREADY falls and the AXI slave must hold
    // RDATA/RRESP/RLAST stable. r_fire is therefore both the AXI acceptance and
    // the corresponding map-stream acceptance during FETCH_R.
    assign m_axi_rready = phase_read && map_ready;
    assign r_fire       = m_axi_rvalid && m_axi_rready;

    // Source metadata is not consumed by the NPU SRAM adapter. The optional
    // context registers preserve the descriptor's original base and stride for
    // a monitor while read_addr_q advances. With metadata disabled, constants
    // replace both registers and the map datapath's source-address arithmetic.
    generate
        if (MAP_SOURCE_METADATA != 0) begin : gen_source_metadata_context
            reg [31:0] command_source_q;
            reg [4:0]  command_stride_q;

            always @(posedge clk) begin
                if (!rstn) begin
                    command_source_q <= 32'd0;
                    command_stride_q <= 5'd0;
                end else if ((fetch_state_q == FETCH_IDLE) && load_valid_i) begin
                    command_source_q <= load_source_addr_i;
                    command_stride_q <= load_source_stride_i;
                end
            end

            assign metadata_source = command_source_q;
            assign metadata_stride = command_stride_q;
        end else begin : gen_no_source_metadata_context
            assign metadata_source = 32'd0;
            assign metadata_stride = 5'd0;
        end
    endgenerate

    // Combinational output formatter and completion detector. Its
    // descriptor_complete_fire_o drives load_ready_o directly: completion is
    // intentionally coupled to acceptance of the last high-bank beat.
    dma_map_datapath #(
        .MAP_SOURCE_METADATA (MAP_SOURCE_METADATA)
    ) map_datapath_i (
        .phase_prefix_i              (phase_prefix),
        .phase_zero_i                (phase_zero),
        .phase_read_i                (phase_read),
        .phase_suffix_i              (phase_suffix),
        .command_source_i            (metadata_source),
        .command_stride_i            (metadata_stride),
        .command_buffer_i            (command_buffer_q),
        .command_bank_mask_i         (command_bank_mask_q),
        .command_group_count_i       (command_group_count_q),
        .command_pad_before_i        (command_pad_before_q),
        .command_pad_after_i         (command_pad_after_q),
        .command_is_weight_i         (command_is_weight_q),
        .command_last_i              (command_last_q),
        .row_beats_remaining_i       (row_beats_remaining_q),
        .group_index_i               (group_index_q),
        .beat_high_i                 (beat_high_q),
        .m_axi_rdata_i               (m_axi_rdata),
        .m_axi_rresp_i               (m_axi_rresp),
        .m_axi_rvalid_i              (m_axi_rvalid),
        .map_ready_i                 (map_ready),
        .weight_swap_i               (weight_swap_i),
        .map_valid_o                 (map_valid),
        .map_data_o                  (map_data),
        .map_source_addr_o           (map_source_addr),
        .map_source_stride_o         (map_source_stride),
        .map_buffer_addr_o           (map_buffer_addr),
        .map_bank_mask_o             (map_bank_mask),
        .map_is_weight_o             (map_is_weight),
        .map_zero_fill_o             (map_zero_fill),
        .map_last_o                  (map_last),
        .map_weight_swap_o           (map_weight_swap),
        .map_fire_o                  (map_fire),
        .descriptor_complete_fire_o  (load_ready_o)
    );

    // Fetch sequencer. Payload/counter state changes only on the relevant
    // ready/valid handshake, so all externally visible values remain stable
    // through backpressure.
    always @(posedge clk) begin
        if (!rstn) begin
            fetch_state_q         <= FETCH_IDLE;
            command_buffer_q      <= 9'd0;
            command_bank_mask_q   <= 8'd0;
            command_group_count_q <= 6'd0;
            command_pad_before_q  <= 1'b0;
            command_pad_after_q   <= 1'b0;
            command_is_weight_q   <= 1'b0;
            command_last_q        <= 1'b0;
            read_addr_q           <= 32'd0;
            row_beats_remaining_q <= 7'd0;
            burst_beats_left_q    <= 7'd0;
            group_index_q         <= 6'd0;
            beat_high_q           <= 1'b0;
            read_error_pulse_o    <= 1'b0;
        end else begin
            read_error_pulse_o <= 1'b0;

            case (fetch_state_q)
                FETCH_IDLE: begin
                    // Capture one descriptor. group_count is converted from
                    // eight-byte groups to four-byte AXI beats by appending 0:
                    // row_beats = group_count * 2.
                    if (load_valid_i) begin
                        command_buffer_q      <= load_buffer_addr_i;
                        command_bank_mask_q   <= load_bank_mask_i;
                        command_group_count_q <= load_group_count_i;
                        command_pad_before_q  <= load_pad_before_i;
                        command_pad_after_q   <= load_pad_after_i;
                        command_is_weight_q   <= load_is_weight_i;
                        command_last_q        <= load_last_i;
                        read_addr_q           <= load_source_addr_i;
                        row_beats_remaining_q <= {load_group_count_i, 1'b0};
                        burst_beats_left_q    <= 7'd0;
                        group_index_q         <= 6'd0;
                        beat_high_q           <= 1'b0;

                        // A vertical halo row needs no AXI transaction. A left
                        // halo column is emitted before reading; other fetched
                        // rows can request AXI immediately.
                        if (load_zero_fill_i)
                            fetch_state_q <= FETCH_ZERO;
                        else if (load_pad_before_i)
                            fetch_state_q <= FETCH_PREFIX;
                        else
                            fetch_state_q <= FETCH_AR;
                    end
                end

                FETCH_PREFIX: begin
                    // Emit exactly two accepted zero beats at destination base:
                    // low banks first, then high banks. Fetched group zero will
                    // subsequently be offset by pad_before in dma_map_datapath.
                    if (map_fire) begin
                        if (beat_high_q) begin
                            beat_high_q   <= 1'b0;
                            fetch_state_q <= FETCH_AR;
                        end else begin
                            beat_high_q <= 1'b1;
                        end
                    end
                end

                FETCH_ZERO: begin
                    // Generate group_count all-zero groups locally. Neither
                    // read_addr_q nor the AXI beat counters are consumed here.
                    if (map_fire) begin
                        if (beat_high_q) begin
                            beat_high_q <= 1'b0;
                            if (group_index_q ==
                                command_group_count_q - 1'b1) begin
                                fetch_state_q <= FETCH_IDLE;
                            end else begin
                                group_index_q <= group_index_q + 1'b1;
                            end
                        end else begin
                            beat_high_q <= 1'b1;
                        end
                    end
                end

                FETCH_AR: begin
                    // phase_ar already holds ARVALID high, so ARREADY denotes
                    // the address handshake. Remember this request's length for
                    // RLAST checking, then move to its data phase.
                    if (m_axi_arready) begin
                        burst_beats_left_q <= next_burst_beats[6:0];
                        fetch_state_q      <= FETCH_R;
                    end
                end

                FETCH_R: begin
                    // Every accepted AXI word is also accepted by the map
                    // stream. Bad responses are converted to zero downstream
                    // and reported here; they do not stop counter progression.
                    if (r_fire) begin
                        if (m_axi_rresp != AXI_RESP_OKAY)
                            read_error_pulse_o <= 1'b1;
                        if (m_axi_rlast != (burst_beats_left_q == 7'd1))
                            read_error_pulse_o <= 1'b1;

                        // Advance by one 32-bit word in the packed object and
                        // retire one word from both descriptor and burst counts.
                        read_addr_q           <= read_addr_q + 4;
                        row_beats_remaining_q <= row_beats_remaining_q - 1'b1;
                        burst_beats_left_q    <= burst_beats_left_q - 1'b1;

                        // Two accepted words complete one logical group.
                        if (beat_high_q) begin
                            beat_high_q   <= 1'b0;
                            group_index_q <= group_index_q + 1'b1;
                        end else begin
                            beat_high_q <= 1'b1;
                        end

                        // Pre-decrement value one means this was the descriptor's
                        // final DRAM word. A right halo still needs its local
                        // suffix; otherwise the descriptor is finished.
                        if (row_beats_remaining_q == 7'd1) begin
                            if (command_pad_after_q)
                                fetch_state_q <= FETCH_SUFFIX;
                            else
                                fetch_state_q <= FETCH_IDLE;
                        end else if (m_axi_rlast ||
                                     (burst_beats_left_q == 7'd1)) begin
                            // More row data remains but this burst ended. This
                            // is normally a planned 4-KiB split. An early RLAST
                            // also takes this recovery path after flagging error.
                            fetch_state_q <= FETCH_AR;
                        end
                    end
                end

                FETCH_SUFFIX: begin
                    // Emit one final two-beat zero group at base+group_count.
                    // The high half accepts/retire event acknowledges the AGU.
                    if (map_fire) begin
                        if (beat_high_q) begin
                            beat_high_q   <= 1'b0;
                            fetch_state_q <= FETCH_IDLE;
                        end else begin
                            beat_high_q <= 1'b1;
                        end
                    end
                end

                default: begin
                    // Defensive recovery for an illegal state encoding. No
                    // map or AXI phase signal is asserted for unknown encodings.
                    fetch_state_q <= FETCH_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
