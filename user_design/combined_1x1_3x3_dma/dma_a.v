`timescale 1ns / 1ps
`default_nettype none

// Combined packed-tile 1x1/3x3 CNN DMA.
//
//   * axil_* is the CPU-facing AXI4-Lite register slave.
//   * m_axi_* is a read-only, 32-bit AXI4 master connected to DRAM.
//   * map_* is a direct 32-bit destination stream connected to the
//     activation-bank / weight-shift adapter.
//
// The CPU supplies a pointer to exactly one packed source object:
//
//   1x1 activation : 16 rows, 16 pixels/row, 8 bytes/pixel
//   3x3 activation : 17 valid rows, 17 pixels/row, 8 bytes/pixel
//   weight slice   : 8 shift groups, 8 bytes/group
//
// One 1x1 row is fetched with a 32-beat burst (ARLEN=31), one 3x3 valid
// row with a 34-beat burst (ARLEN=33), and one packed 8x8 weight slice with
// a 16-beat burst (ARLEN=15). If an activation row would cross an AXI 4 KiB
// boundary it is safely split into two bursts. A 64-byte-aligned weight
// pointer guarantees that the weight slice always uses exactly one burst.
//
// Direct 32-bit steering:
//
//   beat 0 -> banks 0..3 at one destination address
//   beat 1 -> banks 4..7 at the same destination address
//
// The destination address advances only after beat 1. There is no 64-bit
// widening/output register and no activation half-word register. AXI R is
// backpressured directly when the NPU-side owner deasserts map_ready. Only
// the NPU adapter retains one 32-bit half-word for the existing eight-lane
// weight-shift interface.
//
// AXI4-Lite register map:
//   0x00 W: packed-object byte pointer and start the selected operation
//   0x00 R: last accepted packed-object pointer
//   0x04 R: status {29'b0, error_sticky, busy, done_sticky}
//   0x08 W/R configuration:
//          [0]   tile_x
//          [1]   tile_y
//          [2]   cin_block       (software bookkeeping; no pointer offset)
//          [3]   load_weight
//          [4]   cout_block      (software bookkeeping; no pointer offset)
//          [6:5] kernel_y        (validation/bookkeeping; no pointer offset)
//          [8:7] kernel_x        (validation/bookkeeping; no pointer offset)
//          [9]   conv_1x1 (0: 3x3, 1: 1x1)
module dma_a (
    input  wire        clk,
    input  wire        rstn,

    output wire [31:0] O_top,

    // CPU-facing AXI4-Lite slave.
    input  wire [9:0]  axil_awaddr,
    input  wire        axil_awvalid,
    output wire        axil_awready,
    input  wire [31:0] axil_wdata,
    input  wire [3:0]  axil_wstrb,
    input  wire        axil_wvalid,
    output wire        axil_wready,
    output reg  [1:0]  axil_bresp,
    output reg         axil_bvalid,
    input  wire        axil_bready,
    input  wire [9:0]  axil_araddr,
    input  wire        axil_arvalid,
    output wire        axil_arready,
    output reg  [31:0] axil_rdata,
    output reg  [1:0]  axil_rresp,
    output reg         axil_rvalid,
    input  wire        axil_rready,

    // DRAM-facing read-only AXI4 master.
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

    // Four-byte destination stream. map_bank_mask is 8'h0f on the first beat
    // of a group and 8'hf0 on the second. Byte lane n in map_data maps to bank
    // n for the low half and bank n+4 for the high half.
    //
    // map_ready must come from the NPU-side port arbiter and may be asserted
    // only when the DMA owns the destination. With no internal output FIFO,
    // map_ready directly controls AXI RREADY during a DRAM-backed transfer.
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
    output wire        map_weight_swap
);

    localparam [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam [1:0] AXI_RESP_SLVERR = 2'b10;
    localparam [1:0] AXI_RESP_DECERR = 2'b11;

    localparam [2:0] FETCH_IDLE   = 3'd0;
    localparam [2:0] FETCH_PREFIX = 3'd1;
    localparam [2:0] FETCH_ZERO   = 3'd2;
    localparam [2:0] FETCH_AR     = 3'd3;
    localparam [2:0] FETCH_R      = 3'd4;
    localparam [2:0] FETCH_SUFFIX = 3'd5;

    reg [31:0] source_base_reg;
    reg [9:0]  config_reg;
    reg        start_pulse;
    reg        done_sticky;
    reg        error_sticky;

    wire       agu_start_ready;
    wire       agu_busy;
    wire       agu_done;

    // Internal packed-row descriptor stream.
    wire        agu_load_valid;
    wire        agu_load_ready;
    wire [31:0] agu_source_addr;
    wire [4:0]  agu_source_stride;
    wire [8:0]  agu_buffer_addr;
    wire [7:0]  agu_bank_mask;
    wire [5:0]  agu_group_count;
    wire        agu_pad_before;
    wire        agu_pad_after;
    wire        agu_is_weight;
    wire        agu_zero_fill;
    wire        agu_last;
    wire        agu_weight_swap;

    // AXI4-Lite AW and W are independent channels.
    reg        aw_hold_valid;
    reg [9:0]  awaddr_hold;
    reg        w_hold_valid;
    reg [31:0] wdata_hold;
    reg [3:0]  wstrb_hold;

    wire        aw_accept;
    wire        w_accept;
    wire        write_have_aw;
    wire        write_have_w;
    wire        write_commit;
    wire [9:0]  write_addr;
    wire [31:0] write_data;
    wire [3:0]  write_strb;
    wire [31:0] next_source_base;
    wire [9:0]  next_config;
    wire        invalid_weight_config;
    wire        invalid_activation_alignment;
    wire        invalid_weight_alignment;
    wire        invalid_source_alignment;

    // Current row/slice descriptor.
    reg [2:0]  fetch_state_q;
    reg [31:0] command_source_q;
    reg [4:0]  command_stride_q;
    reg [8:0]  command_buffer_q;
    reg [7:0]  command_bank_mask_q;
    reg [5:0]  command_group_count_q;
    reg        command_pad_before_q;
    reg        command_pad_after_q;
    reg        command_is_weight_q;
    reg        command_last_q;

    // AXI burst tracking. row_beats_remaining_q counts all unread beats in
    // the descriptor. burst_beats_left_q checks RLAST for the current AR.
    reg [31:0] read_addr_q;
    reg [6:0]  row_beats_remaining_q;
    reg [6:0]  burst_beats_left_q;

    // Direct steering state. beat_high_q=0 selects banks 0..3; one accepted
    // beat later beat_high_q=1 selects banks 4..7 at the same group address.
    reg [5:0] group_index_q;
    reg       beat_high_q;

    reg        axi_read_error_pulse;

    wire        map_fire;
    wire        r_fire;
    wire        descriptor_complete_fire;
    wire [12:0] bytes_to_4k;
    wire [10:0] beats_to_4k;
    wire [10:0] row_beats_wide;
    wire        row_finishes_before_4k;
    wire [10:0] next_burst_beats;

    wire [31:0] axil_status_word;
    wire [31:0] axil_config_word;
    wire [31:0] axil_read_mux_data;
    wire [31:0] axil_read_data;
    wire [1:0]  axil_read_resp;
    wire        axil_read_addr_valid;

    wire [8:0]  prefix_buffer_addr;
    wire [8:0]  indexed_buffer_addr;
    wire [8:0]  fetched_buffer_addr;
    wire [8:0]  suffix_buffer_addr;
    wire [1:0]  map_addr_select;

    wire [31:0] beat_byte_offset;
    wire [31:0] indexed_source_addr;
    wire [31:0] suffix_source_addr;
    wire        map_uses_axi_data;
    wire [7:0]  low_bank_mask;
    wire [7:0]  high_bank_mask;

    // These are ordinary RTL choices. FABulous cascade-mux BELs cannot be
    // driven directly from registers or I/O signals; nextpnr requires each
    // data input of FABULOUS_MUX2/4/8 to be a LUT O output in the same cluster.
    assign write_addr = aw_hold_valid ? awaddr_hold : axil_awaddr;
    assign write_data = w_hold_valid  ? wdata_hold  : axil_wdata;
    assign write_strb = w_hold_valid  ? wstrb_hold  : axil_wstrb;

    genvar byte_index;
    generate
        for (byte_index = 0; byte_index < 4;
             byte_index = byte_index + 1) begin : gen_source_wstrb_mux
            assign next_source_base[byte_index*8 +: 8] =
                write_strb[byte_index]
                    ? write_data[byte_index*8 +: 8]
                    : source_base_reg[byte_index*8 +: 8];
        end
    endgenerate

    assign next_config[7:0] = write_strb[0]
                              ? write_data[7:0] : config_reg[7:0];
    assign next_config[9:8] = write_strb[1]
                              ? write_data[9:8] : config_reg[9:8];

    assign O_top[0]     = 1'b1;
    assign O_top[1]     = done_sticky;
    assign O_top[2]     = agu_busy;
    assign O_top[3]     = error_sticky;
    assign O_top[4]     = map_valid;
    assign O_top[5]     = map_zero_fill;
    assign O_top[6]     = map_last;
    assign O_top[7]     = map_is_weight;
    assign O_top[8]     = map_weight_swap;
    assign O_top[9]     = config_reg[9];
    assign O_top[10]    = m_axi_arvalid;
    assign O_top[11]    = m_axi_rvalid && m_axi_rready;
    assign O_top[12]    = (fetch_state_q != FETCH_IDLE);
    assign O_top[31:13] = 19'd0;

    assign axil_awready = !aw_hold_valid && !axil_bvalid;
    assign axil_wready  = !w_hold_valid  && !axil_bvalid;
    assign aw_accept     = axil_awvalid && axil_awready;
    assign w_accept      = axil_wvalid  && axil_wready;
    assign write_have_aw = aw_hold_valid || aw_accept;
    assign write_have_w  = w_hold_valid || w_accept;
    assign write_commit  = write_have_aw && write_have_w && !axil_bvalid;

    assign invalid_weight_config = !config_reg[9] && config_reg[3] &&
                                   ((config_reg[6:5] == 2'd3) ||
                                    (config_reg[8:7] == 2'd3));
    // Packed activation groups are eight-byte aligned. Packed weight slices
    // require 64-byte alignment so their 16-beat request cannot cross 4 KiB.
    assign invalid_activation_alignment = |next_source_base[2:0];
    assign invalid_weight_alignment     = |next_source_base[5:0];
    assign invalid_source_alignment = config_reg[3]
                                      ? invalid_weight_alignment
                                      : invalid_activation_alignment;

    always @(posedge clk) begin
        if (!rstn) begin
            source_base_reg <= 32'd0;
            config_reg      <= 10'd0;
            start_pulse     <= 1'b0;
            done_sticky     <= 1'b0;
            error_sticky    <= 1'b0;
            aw_hold_valid   <= 1'b0;
            awaddr_hold     <= 10'd0;
            w_hold_valid    <= 1'b0;
            wdata_hold      <= 32'd0;
            wstrb_hold      <= 4'd0;
            axil_bresp      <= AXI_RESP_OKAY;
            axil_bvalid     <= 1'b0;
        end else begin
            start_pulse <= 1'b0;
            if (agu_done)
                done_sticky <= 1'b1;
            if (axi_read_error_pulse)
                error_sticky <= 1'b1;

            if (axil_bvalid && axil_bready)
                axil_bvalid <= 1'b0;
            if (aw_accept && !write_commit) begin
                aw_hold_valid <= 1'b1;
                awaddr_hold   <= axil_awaddr;
            end
            if (w_accept && !write_commit) begin
                w_hold_valid <= 1'b1;
                wdata_hold   <= axil_wdata;
                wstrb_hold   <= axil_wstrb;
            end

            if (write_commit) begin
                aw_hold_valid <= 1'b0;
                w_hold_valid  <= 1'b0;
                axil_bvalid   <= 1'b1;
                case (write_addr)
                    10'h000: begin
                        if (agu_busy || !agu_start_ready || start_pulse ||
                            invalid_weight_config ||
                            invalid_source_alignment) begin
                            axil_bresp    <= AXI_RESP_SLVERR;
                            error_sticky <= 1'b1;
                        end else begin
                            source_base_reg <= next_source_base;
                            start_pulse     <= 1'b1;
                            done_sticky     <= 1'b0;
                            error_sticky    <= 1'b0;
                            axil_bresp      <= AXI_RESP_OKAY;
                        end
                    end
                    10'h008: begin
                        if (agu_busy || start_pulse) begin
                            axil_bresp    <= AXI_RESP_SLVERR;
                            error_sticky <= 1'b1;
                        end else begin
                            config_reg <= next_config;
                            axil_bresp <= AXI_RESP_OKAY;
                        end
                    end
                    default: begin
                        axil_bresp    <= AXI_RESP_DECERR;
                        error_sticky <= 1'b1;
                    end
                endcase
            end
        end
    end

    // Exact-address validation returns zero/DECERR for aliases or unsupported
    // offsets. Leave mux implementation to synthesis so every packed cell is
    // legal for the selected FABulous tile architecture.
    assign axil_status_word = {
        29'd0, error_sticky, agu_busy, done_sticky
    };
    assign axil_config_word = {22'd0, config_reg};
    assign axil_read_addr_valid = (axil_araddr == 10'h000) ||
                                  (axil_araddr == 10'h004) ||
                                  (axil_araddr == 10'h008);

    assign axil_read_mux_data = (axil_araddr[4:2] == 3'd0)
                                ? source_base_reg
                                : (axil_araddr[4:2] == 3'd1)
                                  ? axil_status_word
                                  : (axil_araddr[4:2] == 3'd2)
                                    ? axil_config_word : 32'd0;
    assign axil_read_data = axil_read_addr_valid
                            ? axil_read_mux_data : 32'd0;
    assign axil_read_resp = axil_read_addr_valid
                            ? AXI_RESP_OKAY : AXI_RESP_DECERR;

    assign axil_arready = !axil_rvalid;
    always @(posedge clk) begin
        if (!rstn) begin
            axil_rdata  <= 32'd0;
            axil_rresp  <= AXI_RESP_OKAY;
            axil_rvalid <= 1'b0;
        end else begin
            if (axil_rvalid && axil_rready)
                axil_rvalid <= 1'b0;
            if (axil_arvalid && axil_arready) begin
                axil_rdata  <= axil_read_data;
                axil_rresp  <= axil_read_resp;
                axil_rvalid <= 1'b1;
            end
        end
    end

    // AXI bursts are clipped at the 4 KiB boundary.
    assign bytes_to_4k      = 13'd4096 - {1'b0, read_addr_q[11:0]};
    assign beats_to_4k      = bytes_to_4k[12:2];
    assign row_beats_wide   = {4'd0, row_beats_remaining_q};
    assign row_finishes_before_4k = row_beats_wide < beats_to_4k;
    assign next_burst_beats = row_finishes_before_4k
                              ? row_beats_wide : beats_to_4k;

    assign m_axi_araddr  = read_addr_q;
    assign m_axi_arlen   = next_burst_beats[7:0] - 8'd1;
    assign m_axi_arsize  = 3'b010;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arvalid = (fetch_state_q == FETCH_AR);

    // With direct steering there is no widening register to fill. Ownership
    // backpressure is propagated directly to the AXI R channel.
    assign m_axi_rready = (fetch_state_q == FETCH_R) && map_ready;
    assign r_fire       = m_axi_rvalid && m_axi_rready;

    assign map_valid = (fetch_state_q == FETCH_PREFIX) ||
                       (fetch_state_q == FETCH_ZERO)   ||
                       (fetch_state_q == FETCH_SUFFIX) ||
                       ((fetch_state_q == FETCH_R) && m_axi_rvalid);
    assign map_fire  = map_valid && map_ready;

    assign map_uses_axi_data = (fetch_state_q == FETCH_R) &&
                               (m_axi_rresp == AXI_RESP_OKAY);
    assign map_data = map_uses_axi_data ? m_axi_rdata : 32'd0;

    // Source metadata names the exact four-byte beat. The destination names
    // the shared eight-channel group and therefore remains unchanged across
    // its low and high halves.
    assign beat_byte_offset    = beat_high_q ? 32'd4 : 32'd0;
    assign indexed_source_addr = command_source_q +
                                 {23'd0, group_index_q, 3'b000} +
                                 beat_byte_offset;
    assign suffix_source_addr  = command_source_q +
                                 {23'd0, command_group_count_q, 3'b000} +
                                 beat_byte_offset;

    assign prefix_buffer_addr  = command_buffer_q;
    assign indexed_buffer_addr = command_buffer_q + group_index_q;
    assign fetched_buffer_addr = command_buffer_q +
                                  (command_pad_before_q ? 1'b1 : 1'b0) +
                                  group_index_q;
    assign suffix_buffer_addr  = command_buffer_q + command_group_count_q;

    // 00 prefix, 01 local-zero descriptor, 10 fetched data, 11 suffix.
    assign map_addr_select[0] = (fetch_state_q == FETCH_ZERO) ||
                                (fetch_state_q == FETCH_SUFFIX);
    assign map_addr_select[1] = (fetch_state_q == FETCH_R) ||
                                (fetch_state_q == FETCH_SUFFIX);

    assign map_buffer_addr = (map_addr_select == 2'b00)
                             ? prefix_buffer_addr
                             : (map_addr_select == 2'b01)
                               ? indexed_buffer_addr
                               : (map_addr_select == 2'b10)
                                 ? fetched_buffer_addr
                                 : suffix_buffer_addr;
    assign map_source_addr = (map_addr_select == 2'b00)
                             ? command_source_q + beat_byte_offset
                             : (map_addr_select == 2'b11)
                               ? suffix_source_addr
                               : indexed_source_addr;

    assign low_bank_mask  = command_bank_mask_q & 8'h0f;
    assign high_bank_mask = command_bank_mask_q & 8'hf0;
    assign map_bank_mask = beat_high_q ? high_bank_mask : low_bank_mask;

    assign map_source_stride = command_stride_q;
    assign map_is_weight     = command_is_weight_q;
    assign map_zero_fill     = (fetch_state_q == FETCH_PREFIX) ||
                               (fetch_state_q == FETCH_ZERO) ||
                               (fetch_state_q == FETCH_SUFFIX);
    assign map_last = beat_high_q && command_last_q &&
                      (((fetch_state_q == FETCH_ZERO) &&
                        (group_index_q == command_group_count_q - 1'b1)) ||
                       ((fetch_state_q == FETCH_R) &&
                        !command_pad_after_q &&
                        (group_index_q == command_group_count_q - 1'b1)) ||
                       (fetch_state_q == FETCH_SUFFIX));
    assign map_weight_swap = agu_weight_swap;

    // Retire the descriptor on its final accepted high-bank beat. This keeps
    // the original one-disabled-cycle weight-shift/swap timing even though the
    // old registered 64-bit map stage no longer exists.
    assign descriptor_complete_fire = map_fire && beat_high_q &&
        (((fetch_state_q == FETCH_ZERO) &&
          (group_index_q == command_group_count_q - 1'b1)) ||
         ((fetch_state_q == FETCH_R) &&
          (row_beats_remaining_q == 7'd1) && !command_pad_after_q) ||
         (fetch_state_q == FETCH_SUFFIX));
    assign agu_load_ready = descriptor_complete_fire;

    always @(posedge clk) begin
        if (!rstn) begin
            fetch_state_q          <= FETCH_IDLE;
            command_source_q       <= 32'd0;
            command_stride_q       <= 5'd0;
            command_buffer_q       <= 9'd0;
            command_bank_mask_q    <= 8'd0;
            command_group_count_q  <= 6'd0;
            command_pad_before_q   <= 1'b0;
            command_pad_after_q    <= 1'b0;
            command_is_weight_q    <= 1'b0;
            command_last_q         <= 1'b0;
            read_addr_q            <= 32'd0;
            row_beats_remaining_q  <= 7'd0;
            burst_beats_left_q     <= 7'd0;
            group_index_q          <= 6'd0;
            beat_high_q            <= 1'b0;
            axi_read_error_pulse   <= 1'b0;
        end else begin
            axi_read_error_pulse <= 1'b0;

            case (fetch_state_q)
                FETCH_IDLE: begin
                    if (agu_load_valid) begin
                        command_source_q      <= agu_source_addr;
                        command_stride_q      <= agu_source_stride;
                        command_buffer_q      <= agu_buffer_addr;
                        command_bank_mask_q   <= agu_bank_mask;
                        command_group_count_q <= agu_group_count;
                        command_pad_before_q  <= agu_pad_before;
                        command_pad_after_q   <= agu_pad_after;
                        command_is_weight_q   <= agu_is_weight;
                        command_last_q        <= agu_last;
                        read_addr_q           <= agu_source_addr;
                        row_beats_remaining_q <= {agu_group_count, 1'b0};
                        burst_beats_left_q    <= 7'd0;
                        group_index_q         <= 6'd0;
                        beat_high_q           <= 1'b0;

                        if (agu_zero_fill)
                            fetch_state_q <= FETCH_ZERO;
                        else if (agu_pad_before)
                            fetch_state_q <= FETCH_PREFIX;
                        else
                            fetch_state_q <= FETCH_AR;
                    end
                end

                FETCH_PREFIX: begin
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
                    if (m_axi_arready) begin
                        burst_beats_left_q <= next_burst_beats[6:0];
                        fetch_state_q      <= FETCH_R;
                    end
                end

                FETCH_R: begin
                    if (r_fire) begin
                        if (m_axi_rresp != AXI_RESP_OKAY)
                            axi_read_error_pulse <= 1'b1;
                        if (m_axi_rlast != (burst_beats_left_q == 7'd1))
                            axi_read_error_pulse <= 1'b1;

                        read_addr_q           <= read_addr_q + 4;
                        row_beats_remaining_q <= row_beats_remaining_q - 1'b1;
                        burst_beats_left_q    <= burst_beats_left_q - 1'b1;

                        if (beat_high_q) begin
                            beat_high_q   <= 1'b0;
                            group_index_q <= group_index_q + 1'b1;
                        end else begin
                            beat_high_q <= 1'b1;
                        end

                        if (row_beats_remaining_q == 7'd1) begin
                            if (command_pad_after_q)
                                fetch_state_q <= FETCH_SUFFIX;
                            else
                                fetch_state_q <= FETCH_IDLE;
                        end else if (m_axi_rlast ||
                                     (burst_beats_left_q == 7'd1)) begin
                            // Normal page-boundary split, or recovery from an
                            // illegally early RLAST response.
                            fetch_state_q <= FETCH_AR;
                        end
                    end
                end

                FETCH_SUFFIX: begin
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
                    fetch_state_q <= FETCH_IDLE;
                end
            endcase
        end
    end

    combined_hwc_channel_dma_agu #(
        .SRC_ADDR_WIDTH(32),
        .ACT_ADDR_WIDTH(9)
    ) agu_i (
        .clk_i                  (clk),
        .rst_n                  (rstn),
        .start_i                (start_pulse),
        .start_ready_o          (agu_start_ready),
        .conv_1x1_i             (config_reg[9]),
        .load_weight_i          (config_reg[3]),
        .image_base_i           (source_base_reg),
        .weight_base_i          (source_base_reg),
        .tile_y_i               (config_reg[1]),
        .tile_x_i               (config_reg[0]),
        .cin_block_i            (config_reg[2]),
        .cout_block_i           (config_reg[4]),
        .kernel_y_i             (config_reg[6:5]),
        .kernel_x_i             (config_reg[8:7]),
        .busy_o                 (agu_busy),
        .done_o                 (agu_done),
        .load_valid_o           (agu_load_valid),
        .load_ready_i           (agu_load_ready),
        .load_src_addr_o        (agu_source_addr),
        .load_src_lane_stride_o (agu_source_stride),
        .load_dst_addr_o        (agu_buffer_addr),
        .load_dst_bank_mask_o   (agu_bank_mask),
        .load_group_count_o     (agu_group_count),
        .load_pad_before_o      (agu_pad_before),
        .load_pad_after_o       (agu_pad_after),
        .load_is_weight_o       (agu_is_weight),
        .load_zero_fill_o       (agu_zero_fill),
        .load_last_o            (agu_last),
        .weight_swap_o          (agu_weight_swap)
    );

endmodule

`default_nettype wire
