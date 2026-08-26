`timescale 1ns / 1ps
`default_nettype none

// Combined packed-tile 1x1/3x3 CNN DMA.
//
//   * axil_* is the CPU-facing AXI4-Lite register slave.
//   * m_axi_* is a read-only, 32-bit AXI4 master connected to DRAM.
//   * map_* is the fetched eight-byte destination stream connected to the
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
// Returned R beats are accepted on consecutive cycles whenever the
// destination is able to keep up. A one-word half-group register plus one
// complete 64-bit output register decouple the 32-bit AXI stream from the
// eight-bank adapter. Only one AXI burst is outstanding at a time.
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

    // Eight-byte destination stream. Byte lane r maps to bank/PE row r.
    // map_ready must come from the NPU-side port arbiter: it may be asserted
    // only when the DMA owns the activation SRAM ports for an activation map,
    // or the weight-shift port for a weight map. dma_a retains the complete
    // map and backpressures AXI R while map_ready is low.
    output wire        map_valid,
    input  wire        map_ready,
    output wire [63:0] map_data,
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
    localparam [2:0] FETCH_DRAIN  = 3'd6;

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
    reg        command_zero_fill_q;
    reg        command_last_q;

    // AXI burst tracking. row_beats_remaining_q counts all unread beats in
    // the descriptor. burst_beats_left_q checks RLAST for the current AR.
    reg [31:0] read_addr_q;
    reg [6:0]  row_beats_remaining_q;
    reg [6:0]  burst_beats_left_q;

    // 32-to-64-bit stream assembly and complete-group output register.
    reg [31:0] half_word_q;
    reg        half_valid_q;
    reg [5:0]  group_index_q;
    reg [63:0] map_data_q;
    reg [31:0] map_source_addr_q;
    reg [4:0]  map_source_stride_q;
    reg [8:0]  map_buffer_addr_q;
    reg [7:0]  map_bank_mask_q;
    reg        map_is_weight_q;
    reg        map_zero_fill_q;
    reg        map_last_q;
    reg        map_valid_q;

    reg        axi_read_error_pulse;

    wire [31:0] accepted_rdata;
    wire        map_fire;
    wire        output_slot_available;
    wire        r_fire;
    wire [12:0] bytes_to_4k;
    wire [10:0] beats_to_4k;
    wire [10:0] row_beats_wide;
    wire [10:0] next_burst_beats;

    function [31:0] apply_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  strb;
        begin
            apply_wstrb = old_value;
            if (strb[0]) apply_wstrb[7:0]   = new_value[7:0];
            if (strb[1]) apply_wstrb[15:8]  = new_value[15:8];
            if (strb[2]) apply_wstrb[23:16] = new_value[23:16];
            if (strb[3]) apply_wstrb[31:24] = new_value[31:24];
        end
    endfunction

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
    assign write_addr = aw_hold_valid ? awaddr_hold : axil_awaddr;
    assign write_data = w_hold_valid  ? wdata_hold  : axil_wdata;
    assign write_strb = w_hold_valid  ? wstrb_hold  : axil_wstrb;

    assign next_source_base = apply_wstrb(
        source_base_reg, write_data, write_strb
    );
    assign next_config[7:0] = write_strb[0]
                            ? write_data[7:0]
                            : config_reg[7:0];
    assign next_config[9:8] = write_strb[1]
                            ? write_data[9:8]
                            : config_reg[9:8];
    assign invalid_weight_config = !config_reg[9] && config_reg[3] &&
                                   ((config_reg[6:5] == 2'd3) ||
                                    (config_reg[8:7] == 2'd3));
    // Packed activation groups are eight-byte aligned. Packed weight slices
    // require 64-byte alignment so their 16-beat request cannot cross 4 KiB.
    assign invalid_source_alignment = config_reg[3]
                                    ? |next_source_base[5:0]
                                    : |next_source_base[2:0];

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
                axil_rvalid <= 1'b1;
                case (axil_araddr)
                    10'h000: begin
                        axil_rdata <= source_base_reg;
                        axil_rresp <= AXI_RESP_OKAY;
                    end
                    10'h004: begin
                        axil_rdata <= {
                            29'd0, error_sticky, agu_busy, done_sticky
                        };
                        axil_rresp <= AXI_RESP_OKAY;
                    end
                    10'h008: begin
                        axil_rdata <= {22'd0, config_reg};
                        axil_rresp <= AXI_RESP_OKAY;
                    end
                    default: begin
                        axil_rdata <= 32'd0;
                        axil_rresp <= AXI_RESP_DECERR;
                    end
                endcase
            end
        end
    end

    assign map_valid         = map_valid_q;
    assign map_data          = map_data_q;
    assign map_source_addr   = map_source_addr_q;
    assign map_source_stride = map_source_stride_q;
    assign map_buffer_addr   = map_buffer_addr_q;
    assign map_bank_mask     = map_bank_mask_q;
    assign map_is_weight     = map_is_weight_q;
    assign map_zero_fill     = map_zero_fill_q;
    assign map_last          = map_last_q;
    assign map_weight_swap   = agu_weight_swap;

    assign map_fire              = map_valid_q && map_ready;
    assign output_slot_available = !map_valid_q || map_ready;
    assign agu_load_ready        = (fetch_state_q == FETCH_DRAIN) && map_fire;

    // AXI bursts are clipped at the 4 KiB boundary. The largest row is only
    // 34 beats, so ARLEN remains comfortably below its 256-beat limit.
    assign bytes_to_4k     = 13'd4096 - {1'b0, read_addr_q[11:0]};
    assign beats_to_4k     = bytes_to_4k[12:2];
    assign row_beats_wide  = {4'd0, row_beats_remaining_q};
    assign next_burst_beats = (row_beats_wide < beats_to_4k)
                            ? row_beats_wide : beats_to_4k;

    assign m_axi_araddr  = read_addr_q;
    assign m_axi_arlen   = (next_burst_beats == 0)
                         ? 8'd0 : next_burst_beats[7:0] - 1'b1;
    assign m_axi_arsize  = 3'b010;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arvalid = (fetch_state_q == FETCH_AR);

    // A first word can be retained even while the previous complete group is
    // stalled. A second word is accepted only when the complete-group output
    // register is empty or is being consumed on this cycle.
    assign m_axi_rready = (fetch_state_q == FETCH_R) &&
                          (!half_valid_q || output_slot_available);
    assign r_fire = m_axi_rvalid && m_axi_rready;
    assign accepted_rdata = (m_axi_rresp == AXI_RESP_OKAY)
                          ? m_axi_rdata : 32'd0;

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
            command_zero_fill_q    <= 1'b0;
            command_last_q         <= 1'b0;
            read_addr_q            <= 32'd0;
            row_beats_remaining_q  <= 7'd0;
            burst_beats_left_q     <= 7'd0;
            half_word_q            <= 32'd0;
            half_valid_q           <= 1'b0;
            group_index_q          <= 6'd0;
            map_data_q             <= 64'd0;
            map_source_addr_q      <= 32'd0;
            map_source_stride_q    <= 5'd0;
            map_buffer_addr_q      <= 9'd0;
            map_bank_mask_q        <= 8'd0;
            map_is_weight_q        <= 1'b0;
            map_zero_fill_q        <= 1'b0;
            map_last_q             <= 1'b0;
            map_valid_q            <= 1'b0;
            axi_read_error_pulse   <= 1'b0;
        end else begin
            axi_read_error_pulse <= 1'b0;

            // Unless a new group is written below, a successful handshake
            // frees the complete-group output register.
            if (map_fire)
                map_valid_q <= 1'b0;

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
                        command_zero_fill_q   <= agu_zero_fill;
                        command_last_q        <= agu_last;
                        read_addr_q           <= agu_source_addr;
                        row_beats_remaining_q <= {agu_group_count, 1'b0};
                        burst_beats_left_q    <= 7'd0;
                        half_valid_q          <= 1'b0;
                        group_index_q         <= 6'd0;

                        if (agu_zero_fill)
                            fetch_state_q <= FETCH_ZERO;
                        else if (agu_pad_before)
                            fetch_state_q <= FETCH_PREFIX;
                        else
                            fetch_state_q <= FETCH_AR;
                    end
                end

                FETCH_PREFIX: begin
                    if (output_slot_available) begin
                        map_data_q          <= 64'd0;
                        map_source_addr_q   <= command_source_q;
                        map_source_stride_q <= command_stride_q;
                        map_buffer_addr_q   <= command_buffer_q;
                        map_bank_mask_q     <= command_bank_mask_q;
                        map_is_weight_q     <= command_is_weight_q;
                        map_zero_fill_q     <= 1'b1;
                        map_last_q          <= 1'b0;
                        map_valid_q         <= 1'b1;
                        fetch_state_q       <= FETCH_AR;
                    end
                end

                FETCH_ZERO: begin
                    if (output_slot_available) begin
                        map_data_q          <= 64'd0;
                        map_source_addr_q   <= command_source_q +
                                               {group_index_q, 3'b000};
                        map_source_stride_q <= command_stride_q;
                        map_buffer_addr_q   <= command_buffer_q + group_index_q;
                        map_bank_mask_q     <= command_bank_mask_q;
                        map_is_weight_q     <= 1'b0;
                        map_zero_fill_q     <= command_zero_fill_q;
                        map_last_q          <= command_last_q &&
                                               (group_index_q ==
                                                command_group_count_q - 1'b1);
                        map_valid_q         <= 1'b1;

                        if (group_index_q == command_group_count_q - 1'b1)
                            fetch_state_q <= FETCH_DRAIN;
                        else
                            group_index_q <= group_index_q + 1'b1;
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

                        if (!half_valid_q) begin
                            half_word_q  <= accepted_rdata;
                            half_valid_q <= 1'b1;
                        end else begin
                            map_data_q          <= {accepted_rdata, half_word_q};
                            map_source_addr_q   <= command_source_q +
                                                   {group_index_q, 3'b000};
                            map_source_stride_q <= command_stride_q;
                            map_buffer_addr_q   <= command_buffer_q +
                                                   (command_pad_before_q ? 1'b1
                                                                         : 1'b0) +
                                                   group_index_q;
                            map_bank_mask_q     <= command_bank_mask_q;
                            map_is_weight_q     <= command_is_weight_q;
                            map_zero_fill_q     <= 1'b0;
                            map_last_q          <= command_last_q &&
                                                   !command_pad_after_q &&
                                                   (group_index_q ==
                                                    command_group_count_q - 1'b1);
                            map_valid_q         <= 1'b1;
                            half_valid_q        <= 1'b0;
                            group_index_q       <= group_index_q + 1'b1;
                        end

                        if (row_beats_remaining_q == 7'd1) begin
                            if (command_pad_after_q)
                                fetch_state_q <= FETCH_SUFFIX;
                            else
                                fetch_state_q <= FETCH_DRAIN;
                        end else if (m_axi_rlast ||
                                     (burst_beats_left_q == 7'd1)) begin
                            // Normal page-boundary split, or recovery from an
                            // illegally early RLAST response.
                            fetch_state_q <= FETCH_AR;
                        end
                    end
                end

                FETCH_SUFFIX: begin
                    if (output_slot_available) begin
                        map_data_q          <= 64'd0;
                        map_source_addr_q   <= command_source_q +
                                               {command_group_count_q, 3'b000};
                        map_source_stride_q <= command_stride_q;
                        map_buffer_addr_q   <= command_buffer_q +
                                               command_group_count_q;
                        map_bank_mask_q     <= command_bank_mask_q;
                        map_is_weight_q     <= 1'b0;
                        map_zero_fill_q     <= 1'b1;
                        map_last_q          <= command_last_q;
                        map_valid_q         <= 1'b1;
                        fetch_state_q       <= FETCH_DRAIN;
                    end
                end

                default: begin // FETCH_DRAIN
                    if (map_fire)
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
