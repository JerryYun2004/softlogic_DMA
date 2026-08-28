`timescale 1ns / 1ps
`default_nettype none

// Self-contained regression for the combined AXI4-Lite + AXI4-read DMA. It
// checks every supported activation tile/channel block, all 3x3 weight taps,
// all 1x1 weight slices, immediate mode switching, AXI AW/W ordering, partial
// configuration writes, invalid accesses, busy rejection, command stability
// under backpressure, local halo zero-fill, packed-source addressing, long
// 32-bit bursts, DRAM stalls, direct four-bank steering, destination placement,
// last, and weight-swap timing.
module tb_combined_dma;

    localparam logic [31:0] IMAGE_BASE  = 32'h1000_0000;
    localparam logic [31:0] WEIGHT_BASE = 32'h2000_0000;

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;
    localparam logic [1:0] AXI_RESP_DECERR = 2'b11;

    logic clk;
    logic rstn;

    wire [31:0] O_top;

    logic [9:0]  axil_awaddr;
    logic        axil_awvalid;
    wire         axil_awready;
    logic [31:0] axil_wdata;
    logic [3:0]  axil_wstrb;
    logic        axil_wvalid;
    wire         axil_wready;
    wire [1:0]   axil_bresp;
    wire         axil_bvalid;
    logic        axil_bready;

    logic [9:0]  axil_araddr;
    logic        axil_arvalid;
    wire         axil_arready;
    wire [31:0]  axil_rdata;
    wire [1:0]   axil_rresp;
    wire         axil_rvalid;
    logic        axil_rready;

    wire [31:0]  m_axi_araddr;
    wire [7:0]   m_axi_arlen;
    wire [2:0]   m_axi_arsize;
    wire [1:0]   m_axi_arburst;
    wire         m_axi_arvalid;
    logic        m_axi_arready;
    logic [31:0] m_axi_rdata;
    logic [1:0]  m_axi_rresp;
    logic        m_axi_rlast;
    logic        m_axi_rvalid;
    wire         m_axi_rready;

    wire         map_valid;
    wire         map_ready;
    wire [31:0]  map_data;
    wire [31:0]  map_source_addr;
    wire [4:0]   map_source_stride;
    wire [8:0]   map_buffer_addr;
    wire [7:0]   map_bank_mask;
    wire         map_is_weight;
    wire         map_zero_fill;
    wire         map_last;
    wire         map_weight_swap;

    // Synthesizable NPU-side adapter signals.  The unit regression uses
    // behavioral SRAM contents below, but drives them only from the exact ports
    // that connect to npu_sram_wrapper in hardware.
    logic        dma_act_port_grant;
    logic        dma_weight_port_grant;
    logic        array_active;
    logic [7:0][8:0] act_compute_addr;
    wire  [7:0]      ext_act_sram_we;
    wire  [7:0][8:0] ext_act_sram_addr;
    wire  [7:0][7:0] ext_act_sram_wdata;
    wire  [7:0][7:0] weight_shift_in;
    wire             weight_shift_en;
    wire             swap_weights;

    integer errors;
    integer cycle_count;
    integer operation_count;
    integer command_count;
    integer last_count;
    integer swap_count;
    integer zero_count;
    integer last_weight_cycle;

    integer total_commands;
    integer total_zero_commands;
    integer total_swaps;
    integer expected_total_commands;
    integer expected_total_zero_commands;
    integer expected_total_swaps;

    logic        operation_active;
    logic        exp_conv_1x1;
    logic        exp_weight;
    logic        exp_tile_y;
    logic        exp_tile_x;
    logic        exp_cin;
    logic        exp_cout;
    logic [1:0]  exp_ky;
    logic [1:0]  exp_kx;
    logic [31:0] exp_base;
    integer      exp_commands;

    logic [7:0] activation_bank [0:7][0:323];
    logic [7:0] loaded_weight   [0:7][0:7];

    logic        stalled_command;
    logic [31:0] held_data;
    logic [31:0] held_source_addr;
    logic [4:0]  held_source_stride;
    logic [8:0]  held_buffer_addr;
    logic [7:0]  held_bank_mask;
    logic        held_is_weight;
    logic        held_zero_fill;
    logic        held_last;

    integer mon_ly;
    integer mon_lx;
    integer mon_gy;
    integer mon_gx;
    integer mon_offset;
    integer mon_tap;
    integer mon_lane;
    integer mon_bank_base;
    integer mon_source_lane;
    integer mon_expected_zero;
    logic [31:0] mon_expected_addr;
    logic        expected_high_half;

    localparam integer DRAM_GAP_CYCLES = 6;
    logic        dram_active_q;
    logic [31:0] dram_addr_q;
    integer      dram_beats_left_q;
    integer      dram_gap_q;
    integer      operation_axi_bursts;
    integer      operation_axi_beats;
    integer      expected_operation_axi_bursts;
    integer      expected_operation_axi_beats;
    integer      expected_row_beats_remaining;
    integer      expected_rows_remaining;
    logic [31:0] expected_next_araddr;
    integer      mon_beats_to_4k;
    integer      mon_expected_burst_beats;
    integer      total_axi_bursts;
    integer      total_axi_beats;

    dma_a #(
        .MAP_SOURCE_METADATA (1)
    ) dut (
        .clk               (clk),
        .rstn              (rstn),
        .O_top             (O_top),
        .axil_awaddr       (axil_awaddr),
        .axil_awvalid      (axil_awvalid),
        .axil_awready      (axil_awready),
        .axil_wdata        (axil_wdata),
        .axil_wstrb        (axil_wstrb),
        .axil_wvalid       (axil_wvalid),
        .axil_wready       (axil_wready),
        .axil_bresp        (axil_bresp),
        .axil_bvalid       (axil_bvalid),
        .axil_bready       (axil_bready),
        .axil_araddr       (axil_araddr),
        .axil_arvalid      (axil_arvalid),
        .axil_arready      (axil_arready),
        .axil_rdata        (axil_rdata),
        .axil_rresp        (axil_rresp),
        .axil_rvalid       (axil_rvalid),
        .axil_rready       (axil_rready),
        .m_axi_araddr      (m_axi_araddr),
        .m_axi_arlen       (m_axi_arlen),
        .m_axi_arsize      (m_axi_arsize),
        .m_axi_arburst     (m_axi_arburst),
        .m_axi_arvalid     (m_axi_arvalid),
        .m_axi_arready     (m_axi_arready),
        .m_axi_rdata       (m_axi_rdata),
        .m_axi_rresp       (m_axi_rresp),
        .m_axi_rlast       (m_axi_rlast),
        .m_axi_rvalid      (m_axi_rvalid),
        .m_axi_rready      (m_axi_rready),
        .map_valid         (map_valid),
        .map_ready         (map_ready),
        .map_data          (map_data),
        .map_source_addr   (map_source_addr),
        .map_source_stride (map_source_stride),
        .map_buffer_addr   (map_buffer_addr),
        .map_bank_mask     (map_bank_mask),
        .map_is_weight     (map_is_weight),
        .map_zero_fill     (map_zero_fill),
        .map_last          (map_last),
        .map_weight_swap   (map_weight_swap)
    );

    dma_npu_sram_adapter adapter_dut (
        .clk_i                    (clk),
        .rst_n                    (rstn),
        .dma_act_port_grant_i    (dma_act_port_grant),
        .dma_weight_port_grant_i (dma_weight_port_grant),
        .array_active_i          (array_active),
        .map_valid_i             (map_valid),
        .map_ready_o             (map_ready),
        .map_data_i              (map_data),
        .map_buffer_addr_i       (map_buffer_addr),
        .map_bank_mask_i         (map_bank_mask),
        .map_is_weight_i         (map_is_weight),
        .map_weight_swap_i       (map_weight_swap),
        .act_compute_addr_i      (act_compute_addr),
        .ext_act_sram_we_o       (ext_act_sram_we),
        .ext_act_sram_addr_o     (ext_act_sram_addr),
        .ext_act_sram_wdata_o    (ext_act_sram_wdata),
        .weight_shift_in_o       (weight_shift_in),
        .weight_shift_en_o       (weight_shift_en),
        .swap_weights_o          (swap_weights)
    );

    always #5 clk = ~clk;

    function automatic [7:0] memory_byte(input logic [31:0] address);
        begin
            memory_byte = address[7:0] ^ address[15:8] ^
                          address[23:16] ^ address[31:24];
        end
    endfunction

    function automatic [31:0] memory_word(input logic [31:0] address);
        begin
            memory_word = {
                memory_byte(address + 3), memory_byte(address + 2),
                memory_byte(address + 1), memory_byte(address)
            };
        end
    endfunction

    task automatic record_error(input string message);
        begin
            errors = errors + 1;
            if (errors <= 30)
                $display("ERROR [%0t]: %s", $time, message);
        end
    endtask

    // Deterministic ownership changes produce one- and multi-cycle stalls
    // without making the regression dependent on a random seed.  array_active
    // occasionally overlaps a requested grant to check the safety interlock.
    always @(negedge clk) begin
        if (!rstn) begin
            dma_act_port_grant    <= 1'b0;
            dma_weight_port_grant <= 1'b0;
            array_active          <= 1'b0;
        end else if (operation_active) begin
            // A swap is a non-stream sideband pulse.  The controller contract
            // retains weight ownership through DMA done; force that condition
            // here while still stalling ordinary weight groups above.
            if (map_weight_swap) begin
                dma_act_port_grant    <= 1'b0;
                dma_weight_port_grant <= 1'b1;
                array_active          <= 1'b0;
            end else begin
                array_active <= ((cycle_count % 17) == 3);
                if (exp_weight) begin
                    dma_act_port_grant <= 1'b0;
                    dma_weight_port_grant <=
                        ((cycle_count % 7) != 1) &&
                        ((cycle_count % 11) != 4);
                end else begin
                    dma_act_port_grant <=
                        ((cycle_count % 7) != 1) &&
                        ((cycle_count % 11) != 4);
                    dma_weight_port_grant <= 1'b0;
                end
            end
        end else begin
            dma_act_port_grant    <= 1'b0;
            dma_weight_port_grant <= 1'b0;
            array_active          <= 1'b0;
        end
    end

    // 32-bit AXI DRAM model. Once a burst begins, R beats are consecutive
    // whenever RREADY remains asserted; six idle cycles are inserted only
    // between bursts. This makes a packed row amortize the request latency.
    always @(posedge clk) begin
        if (!rstn) begin
            m_axi_arready    <= 1'b0;
            m_axi_rdata      <= 32'd0;
            m_axi_rresp      <= AXI_RESP_OKAY;
            m_axi_rlast      <= 1'b0;
            m_axi_rvalid     <= 1'b0;
            dram_active_q    <= 1'b0;
            dram_addr_q      <= 32'd0;
            dram_beats_left_q <= 0;
            dram_gap_q       <= 0;
            operation_axi_bursts <= 0;
            operation_axi_beats  <= 0;
            total_axi_bursts <= 0;
            total_axi_beats  <= 0;
        end else begin
            m_axi_arready <= !dram_active_q && !m_axi_rvalid &&
                             (dram_gap_q == 0);

            if (dram_gap_q > 0)
                dram_gap_q <= dram_gap_q - 1;

            if (m_axi_arvalid && m_axi_arready) begin
                if (m_axi_araddr[1:0] != 2'b00)
                    record_error("AXI ARADDR was not 32-bit aligned");
                if (m_axi_arsize != 3'b010)
                    record_error("AXI ARSIZE was not four bytes");
                if (m_axi_arburst != 2'b01)
                    record_error("AXI ARBURST was not INCR");
                mon_beats_to_4k =
                    (4096 - expected_next_araddr[11:0]) / 4;
                mon_expected_burst_beats =
                    (expected_row_beats_remaining < mon_beats_to_4k)
                        ? expected_row_beats_remaining : mon_beats_to_4k;
                if (m_axi_araddr != expected_next_araddr)
                    record_error("packed row/slice burst address mismatch");
                if ((m_axi_arlen + 1) != mon_expected_burst_beats)
                    record_error("packed row/slice burst length mismatch");
                if (({1'b0, m_axi_araddr[11:0]} +
                     (({5'd0, m_axi_arlen} + 13'd1) << 2)) > 13'd4096)
                    record_error("AXI burst crossed a 4 KiB boundary");

                expected_next_araddr = expected_next_araddr +
                                       mon_expected_burst_beats * 4;
                if (expected_row_beats_remaining ==
                    mon_expected_burst_beats) begin
                    expected_rows_remaining = expected_rows_remaining - 1;
                    if (expected_rows_remaining > 0)
                        expected_row_beats_remaining = exp_weight ? 0 :
                            (exp_conv_1x1 ? 32 : 34);
                    else
                        expected_row_beats_remaining = 0;
                end else begin
                    expected_row_beats_remaining =
                        expected_row_beats_remaining -
                        mon_expected_burst_beats;
                end

                dram_active_q     <= 1'b1;
                dram_addr_q       <= m_axi_araddr;
                dram_beats_left_q <= m_axi_arlen + 1;
                m_axi_arready     <= 1'b0;
                operation_axi_bursts <= operation_axi_bursts + 1;
                total_axi_bursts  <= total_axi_bursts + 1;
            end

            if (dram_active_q && !m_axi_rvalid) begin
                m_axi_rdata  <= memory_word(dram_addr_q);
                m_axi_rresp  <= AXI_RESP_OKAY;
                m_axi_rlast  <= (dram_beats_left_q == 1);
                m_axi_rvalid <= 1'b1;
            end

            if (m_axi_rvalid && m_axi_rready) begin
                operation_axi_beats <= operation_axi_beats + 1;
                total_axi_beats     <= total_axi_beats + 1;

                if (dram_beats_left_q == 1) begin
                    m_axi_rvalid      <= 1'b0;
                    m_axi_rlast       <= 1'b0;
                    dram_active_q     <= 1'b0;
                    dram_beats_left_q <= 0;
                    dram_gap_q        <= DRAM_GAP_CYCLES;
                end else begin
                    dram_addr_q       <= dram_addr_q + 4;
                    dram_beats_left_q <= dram_beats_left_q - 1;
                    m_axi_rdata       <= memory_word(dram_addr_q + 4);
                    m_axi_rlast       <= (dram_beats_left_q == 2);
                    m_axi_rvalid      <= 1'b1;
                end
            end
        end
    end

    // Direct 32-bit steering reference model. Each accepted map beat writes
    // four activation banks. A completed low/high pair counts as one original
    // eight-channel group. Destination data is sampled from the adapter's
    // actual activation-SRAM and weight-shift output ports.
    always @(posedge clk) begin
        if (!rstn) begin
            cycle_count       = 0;
            stalled_command   = 1'b0;
            total_commands    = 0;
            total_zero_commands = 0;
            total_swaps       = 0;
            expected_high_half = 1'b0;
        end else begin
            cycle_count = cycle_count + 1;

            if (map_ready !==
                (map_is_weight
                    ? (dma_weight_port_grant && !array_active)
                    : (dma_act_port_grant && !array_active)))
                record_error("map_ready did not match ownership of the relevant NPU port");

            if (m_axi_rvalid && map_ready && !m_axi_rready)
                record_error("direct 32-bit datapath inserted an AXI R bubble while its destination was ready");

            if (swap_weights !==
                (dma_weight_port_grant && !array_active &&
                 map_weight_swap))
                record_error("weight swap was not ownership-qualified");

            for (mon_lane = 0; mon_lane < 8;
                 mon_lane = mon_lane + 1) begin
                if (dma_act_port_grant && !array_active) begin
                    if (ext_act_sram_addr[mon_lane] !== map_buffer_addr)
                        record_error("DMA did not own an activation SRAM address port after grant");
                end else if (ext_act_sram_addr[mon_lane] !==
                             act_compute_addr[mon_lane]) begin
                    record_error("compute address was not restored when DMA lacked activation ownership");
                end
            end

            if (!(map_valid && map_ready)) begin
                if (ext_act_sram_we !== 8'h00)
                    record_error("activation SRAM write occurred without a map handshake");
                if (weight_shift_en)
                    record_error("weight shift occurred without a map handshake");
            end

            if (stalled_command) begin
                if (!map_valid)
                    record_error("map_valid dropped while a command was stalled");
                if ((map_data          !== held_data)          ||
                    (map_source_addr   !== held_source_addr)   ||
                    (map_source_stride !== held_source_stride) ||
                    (map_buffer_addr   !== held_buffer_addr)   ||
                    (map_bank_mask     !== held_bank_mask)     ||
                    (map_is_weight     !== held_is_weight)     ||
                    (map_zero_fill     !== held_zero_fill)     ||
                    (map_last          !== held_last))
                    record_error("a direct map beat changed under backpressure");
            end

            if (map_valid && !map_ready) begin
                if (!stalled_command) begin
                    held_data          = map_data;
                    held_source_addr   = map_source_addr;
                    held_source_stride = map_source_stride;
                    held_buffer_addr   = map_buffer_addr;
                    held_bank_mask     = map_bank_mask;
                    held_is_weight     = map_is_weight;
                    held_zero_fill     = map_zero_fill;
                    held_last          = map_last;
                end
                stalled_command = 1'b1;
            end else begin
                stalled_command = 1'b0;
            end

            if (map_valid && map_ready) begin
                if (!operation_active) begin
                    record_error("map beat occurred outside an active operation");
                end else begin
                    if (map_bank_mask !==
                        (expected_high_half ? 8'hf0 : 8'h0f))
                        record_error("32-bit map bank-half sequence mismatch");
                    if (map_is_weight !== exp_weight)
                        record_error("map_is_weight does not match the CPU command");

                    mon_bank_base = expected_high_half ? 4 : 0;

                    if (exp_weight) begin
                        mon_expected_addr = exp_base + command_count * 8 +
                                            (expected_high_half ? 4 : 0);

                        if (map_source_addr !== mon_expected_addr)
                            record_error("weight source address mismatch");
                        if (map_source_stride !== 5'd1)
                            record_error("packed weight lane stride must be one");
                        if (map_buffer_addr !== command_count[8:0])
                            record_error("weight shift index mismatch");
                        if (map_zero_fill !== 1'b0)
                            record_error("weight command asserted zero fill");
                        if (map_last !==
                            (expected_high_half && (command_count == 7)))
                            record_error("weight last flag mismatch");
                        if (weight_shift_en !== expected_high_half)
                            record_error("weight shifter did not pulse only on the high 32-bit half");
                        if (ext_act_sram_we !== 8'h00)
                            record_error("weight map incorrectly wrote an activation SRAM");

                        if (expected_high_half) begin
                            for (mon_lane = 0; mon_lane < 8;
                                 mon_lane = mon_lane + 1) begin
                                loaded_weight[mon_lane][7-command_count] =
                                    weight_shift_in[mon_lane];
                                if (weight_shift_in[mon_lane] !==
                                    memory_byte(exp_base + command_count*8 +
                                                mon_lane))
                                    record_error("NPU weight-shift lane data mismatch");
                            end
                        end
                    end else begin
                        if (exp_conv_1x1) begin
                            mon_ly = command_count / 16;
                            mon_lx = command_count % 16;
                            mon_expected_zero = 0;
                            mon_expected_addr = exp_base + command_count * 8 +
                                                (expected_high_half ? 4 : 0);
                        end else begin
                            mon_ly = command_count / 18;
                            mon_lx = command_count % 18;
                            mon_expected_zero =
                                ((!exp_tile_y && (mon_ly == 0)) ||
                                 ( exp_tile_y && (mon_ly == 17)) ||
                                 (!exp_tile_x && (mon_lx == 0)) ||
                                 ( exp_tile_x && (mon_lx == 17)));
                            mon_gy = mon_ly - (exp_tile_y ? 0 : 1);
                            mon_gx = mon_lx - (exp_tile_x ? 0 : 1);
                            mon_expected_addr = exp_base +
                                                ((mon_gy * 17 + mon_gx) * 8) +
                                                (expected_high_half ? 4 : 0);
                        end

                        // Zero groups do not access DRAM, so their source
                        // metadata is informational. Every fetched group must
                        // point to its packed eight-byte location exactly.
                        if (!mon_expected_zero &&
                            (map_source_addr !== mon_expected_addr))
                            record_error("activation source address mismatch");
                        if (map_source_stride !== 5'd1)
                            record_error("activation source lane stride must be one");
                        if (map_buffer_addr !== command_count[8:0])
                            record_error("activation destination address mismatch");
                        if (map_zero_fill !== (mon_expected_zero != 0))
                            record_error("activation halo zero-fill mismatch");
                        if (map_last !==
                            (expected_high_half &&
                             (command_count == exp_commands-1)))
                            record_error("activation last flag mismatch");
                        if (ext_act_sram_we !== map_bank_mask)
                            record_error("activation SRAM write enables did not match the bank mask");
                        if (weight_shift_en)
                            record_error("activation map incorrectly enabled the weight shifter");

                        if (map_zero_fill && expected_high_half) begin
                            zero_count = zero_count + 1;
                            total_zero_commands = total_zero_commands + 1;
                        end

                        for (mon_lane = 0; mon_lane < 4;
                             mon_lane = mon_lane + 1) begin
                            mon_source_lane = mon_bank_base + mon_lane;
                            activation_bank[mon_source_lane][command_count] =
                                ext_act_sram_wdata[mon_source_lane];
                            if (ext_act_sram_wdata[mon_source_lane] !==
                                (map_zero_fill
                                    ? 8'd0
                                    : memory_byte(map_source_addr + mon_lane)))
                                record_error("activation SRAM write-data mismatch");
                        end
                    end

                    for (mon_lane = 0; mon_lane < 4;
                         mon_lane = mon_lane + 1) begin
                        if (map_data[mon_lane*8 +: 8] !==
                            (map_zero_fill
                                ? 8'd0
                                : memory_byte(map_source_addr + mon_lane)))
                            record_error("direct 32-bit map byte-lane mismatch");
                    end

                    if (map_last)
                        last_count = last_count + 1;
                    if (expected_high_half) begin
                        if (exp_weight && (command_count == 7))
                            last_weight_cycle = cycle_count;
                        command_count = command_count + 1;
                        total_commands = total_commands + 1;
                    end
                    expected_high_half = !expected_high_half;
                end
            end

            if (swap_weights) begin
                swap_count = swap_count + 1;
                total_swaps = total_swaps + 1;
                if (!operation_active || !exp_weight)
                    record_error("weight swap occurred outside a weight operation");
                if (map_valid)
                    record_error("weight swap overlapped a load command");
                if (cycle_count != (last_weight_cycle + 2))
                    record_error("weight swap did not follow one disabled cycle");
            end
        end
    end

    // mode 0: AW and W together; mode 1: AW first; mode 2: W first.
    task automatic axil_write_expect(
        input logic [9:0]  address,
        input logic [31:0] data,
        input logic [3:0]  strb,
        input integer      mode,
        input logic [1:0]  expected_resp
    );
        integer aw_done;
        integer w_done;
        begin
            aw_done = 0;
            w_done  = 0;

            @(negedge clk);
            axil_awaddr  = address;
            axil_wdata   = data;
            axil_wstrb   = strb;
            axil_awvalid = (mode != 2);
            axil_wvalid  = (mode != 1);

            while (!aw_done || !w_done) begin
                @(posedge clk);
                if (!aw_done && axil_awvalid && axil_awready)
                    aw_done = 1;
                if (!w_done && axil_wvalid && axil_wready)
                    w_done = 1;

                @(negedge clk);
                if (aw_done)
                    axil_awvalid = 1'b0;
                if (w_done)
                    axil_wvalid = 1'b0;
                if ((mode == 1) && aw_done && !w_done)
                    axil_wvalid = 1'b1;
                if ((mode == 2) && w_done && !aw_done)
                    axil_awvalid = 1'b1;
            end

            while (axil_bvalid !== 1'b1)
                @(negedge clk);

            if (axil_bresp !== expected_resp) begin
                $display("ERROR: AXI write addr=%03h response=%b expected=%b",
                         address, axil_bresp, expected_resp);
                errors = errors + 1;
            end

            @(posedge clk);
            @(negedge clk);
        end
    endtask

    task automatic axil_read_expect(
        input  logic [9:0] address,
        input  logic [1:0] expected_resp,
        input  logic [31:0] expected_data
    );
        integer ar_done;
        begin
            ar_done = 0;
            @(negedge clk);
            axil_araddr  = address;
            axil_arvalid = 1'b1;

            while (!ar_done) begin
                @(posedge clk);
                if (axil_arvalid && axil_arready)
                    ar_done = 1;
                @(negedge clk);
                if (ar_done)
                    axil_arvalid = 1'b0;
            end

            while (axil_rvalid !== 1'b1)
                @(negedge clk);

            if (axil_rresp !== expected_resp)
                record_error("AXI read response mismatch");
            if (axil_rdata !== expected_data)
                record_error("AXI read data mismatch");

            @(posedge clk);
            @(negedge clk);
        end
    endtask

    task automatic wait_for_busy_then_done(input integer timeout_cycles);
        integer waited;
        begin
            waited = 0;
            while ((O_top[2] !== 1'b1) && (waited < timeout_cycles)) begin
                @(posedge clk);
                waited = waited + 1;
            end
            if (O_top[2] !== 1'b1)
                record_error("DMA never asserted busy");

            while ((O_top[1] !== 1'b1) && (waited < timeout_cycles)) begin
                @(posedge clk);
                waited = waited + 1;
            end
            if (O_top[1] !== 1'b1)
                record_error("DMA operation timed out");
        end
    endtask

    task automatic prepare_operation(
        input integer conv_1x1,
        input integer load_weight,
        input integer tile_y,
        input integer tile_x,
        input integer cin_block,
        input integer cout_block,
        input integer kernel_y,
        input integer kernel_x,
        input logic [31:0] base_address
    );
        integer r;
        integer p;
        integer calc_rows;
        integer calc_row_beats;
        integer calc_beats_left;
        integer calc_beats_to_4k;
        integer calc_burst_beats;
        logic [31:0] calc_addr;
        begin
            exp_conv_1x1 = conv_1x1[0];
            exp_weight   = load_weight[0];
            exp_tile_y   = tile_y[0];
            exp_tile_x   = tile_x[0];
            exp_cin      = cin_block[0];
            exp_cout     = cout_block[0];
            exp_ky       = kernel_y[1:0];
            exp_kx       = kernel_x[1:0];
            exp_base     = base_address;
            exp_commands = load_weight ? 8 : (conv_1x1 ? 256 : 324);

            command_count     = 0;
            last_count        = 0;
            swap_count        = 0;
            zero_count        = 0;
            last_weight_cycle = -1000;
            expected_high_half = 1'b0;
            operation_active  = 1'b1;
            operation_axi_bursts = 0;
            operation_axi_beats  = 0;
            expected_operation_axi_bursts = 0;
            expected_operation_axi_beats = load_weight ? 16 :
                                           (conv_1x1 ? 512 : 578);
            expected_next_araddr = base_address;
            expected_rows_remaining = load_weight ? 1 :
                                      (conv_1x1 ? 16 : 17);
            expected_row_beats_remaining = load_weight ? 16 :
                                           (conv_1x1 ? 32 : 34);

            // Count the exact legal bursts, including any activation row
            // divided at a 4 KiB boundary.
            calc_rows = expected_rows_remaining;
            calc_row_beats = expected_row_beats_remaining;
            calc_addr = base_address;
            for (r = 0; r < calc_rows; r = r + 1) begin
                calc_beats_left = calc_row_beats;
                while (calc_beats_left > 0) begin
                    calc_beats_to_4k =
                        (4096 - calc_addr[11:0]) / 4;
                    calc_burst_beats =
                        (calc_beats_left < calc_beats_to_4k)
                            ? calc_beats_left : calc_beats_to_4k;
                    expected_operation_axi_bursts =
                        expected_operation_axi_bursts + 1;
                    calc_addr = calc_addr + calc_burst_beats * 4;
                    calc_beats_left = calc_beats_left - calc_burst_beats;
                end
            end

            if (load_weight) begin
                for (r = 0; r < 8; r = r + 1)
                    for (p = 0; p < 8; p = p + 1)
                        loaded_weight[r][p] = 8'hxx;
            end else begin
                for (r = 0; r < 8; r = r + 1)
                    for (p = 0; p < 324; p = p + 1)
                        activation_bank[r][p] = 8'hxx;
            end

            expected_total_commands = expected_total_commands + exp_commands;
            if (!load_weight && !conv_1x1)
                expected_total_zero_commands =
                    expected_total_zero_commands + 35;
            if (load_weight)
                expected_total_swaps = expected_total_swaps + 1;
        end
    endtask

    task automatic verify_operation_data;
        integer r;
        integer p;
        integer ly;
        integer lx;
        integer gy;
        integer gx;
        integer offset;
        integer tap;
        integer expected_zero;
        logic [31:0] address;
        logic [7:0] expected_data;
        begin
            if (command_count != exp_commands)
                record_error("operation command count mismatch");
            if (expected_high_half !== 1'b0)
                record_error("operation ended between low/high 32-bit halves");
            if (last_count != 1)
                record_error("operation did not emit exactly one last flag");
            if (swap_count != (exp_weight ? 1 : 0))
                record_error("operation weight-swap count mismatch");
            if (zero_count != ((!exp_weight && !exp_conv_1x1) ? 35 : 0))
                record_error("operation zero-fill command count mismatch");

            if (operation_axi_bursts != expected_operation_axi_bursts)
                record_error("operation AXI burst count mismatch");
            if (operation_axi_beats != expected_operation_axi_beats)
                record_error("operation AXI beat count mismatch");
            if ((expected_rows_remaining != 0) ||
                (expected_row_beats_remaining != 0))
                record_error("AXI row/slice burst scoreboard did not finish");

            if (exp_weight) begin
                for (r = 0; r < 8; r = r + 1) begin
                    for (p = 0; p < 8; p = p + 1) begin
                        // Packed group zero is output column seven, followed
                        // by columns six through zero.
                        address = exp_base + (7-p) * 8 + r;
                        expected_data = memory_byte(address);
                        if (loaded_weight[r][p] !== expected_data)
                            record_error("loaded 8x8 weight data mismatch");
                    end
                end
            end else begin
                for (p = 0; p < exp_commands; p = p + 1) begin
                    if (exp_conv_1x1) begin
                        ly = p / 16;
                        lx = p % 16;
                        expected_zero = 0;
                        address = exp_base + p * 8;
                    end else begin
                        ly = p / 18;
                        lx = p % 18;
                        expected_zero =
                            ((!exp_tile_y && (ly == 0)) ||
                             ( exp_tile_y && (ly == 17)) ||
                             (!exp_tile_x && (lx == 0)) ||
                             ( exp_tile_x && (lx == 17)));
                        gy = ly - (exp_tile_y ? 0 : 1);
                        gx = lx - (exp_tile_x ? 0 : 1);
                        address = exp_base + ((gy * 17 + gx) * 8);
                    end

                    for (r = 0; r < 8; r = r + 1) begin
                        expected_data = expected_zero
                                      ? 8'd0
                                      : memory_byte(address + r);
                        if (activation_bank[r][p] !== expected_data)
                            record_error("loaded activation-bank data mismatch");
                    end
                end
            end
        end
    endtask

    task automatic run_operation(
        input integer conv_1x1,
        input integer load_weight,
        input integer tile_y,
        input integer tile_x,
        input integer cin_block,
        input integer cout_block,
        input integer kernel_y,
        input integer kernel_x
    );
        logic [31:0] config_word;
        logic [31:0] base_address;
        integer order;
        begin
            config_word = 32'd0;
            config_word[0]   = tile_x[0];
            config_word[1]   = tile_y[0];
            config_word[2]   = cin_block[0];
            config_word[3]   = load_weight[0];
            config_word[4]   = cout_block[0];
            config_word[6:5] = kernel_y[1:0];
            config_word[8:7] = kernel_x[1:0];
            config_word[9]   = conv_1x1[0];
            // Every operation receives its own packed pointer. Activation
            // objects are page-spaced; weight objects are 64-byte aligned.
            base_address = (load_weight ? WEIGHT_BASE : IMAGE_BASE) +
                           operation_count * 32'h0000_1000;
            order = operation_count % 3;

            prepare_operation(conv_1x1, load_weight, tile_y, tile_x,
                              cin_block, cout_block, kernel_y, kernel_x,
                              base_address);

            axil_write_expect(10'h008, config_word, 4'hf,
                              order, AXI_RESP_OKAY);
            if (O_top[9] !== conv_1x1[0])
                record_error("O_top convolution-mode indicator mismatch");
            axil_write_expect(10'h000, base_address, 4'hf,
                              (order + 1) % 3, AXI_RESP_OKAY);

            wait_for_busy_then_done(10000);
            @(negedge clk);
            verify_operation_data();
            if (O_top[3] !== 1'b0)
                record_error("successful operation left error_sticky set");

            operation_active = 1'b0;
            operation_count = operation_count + 1;
        end
    endtask

    task automatic test_4k_boundary_split;
        logic [31:0] config_word;
        logic [31:0] split_base;
        begin
            $display("Checking an activation row split at the AXI 4 KiB boundary...");
            config_word = 32'd0;
            config_word[9] = 1'b1;
            split_base = IMAGE_BASE + 32'h0000_0fc0;

            prepare_operation(1, 0, 0, 0, 0, 0, 0, 0, split_base);
            axil_write_expect(10'h008, config_word, 4'hf,
                              0, AXI_RESP_OKAY);
            axil_write_expect(10'h000, split_base, 4'hf,
                              1, AXI_RESP_OKAY);
            wait_for_busy_then_done(10000);
            @(negedge clk);
            verify_operation_data();
            if (expected_operation_axi_bursts != 17)
                record_error("4 KiB split test did not predict 17 bursts");
            if (O_top[3] !== 1'b0)
                record_error("4 KiB split operation set error_sticky");

            operation_active = 1'b0;
            operation_count = operation_count + 1;
        end
    endtask

    task automatic test_busy_rejection;
        logic [31:0] config_word;
        begin
            $display("Checking writes while busy are rejected without corrupting the active command...");
            config_word = 32'd0;
            config_word[0] = 1'b1;
            config_word[1] = 1'b0;
            config_word[2] = 1'b1;
            config_word[9] = 1'b0;

            prepare_operation(0, 0, 0, 1, 1, 0, 0, 0, IMAGE_BASE);
            axil_write_expect(10'h008, config_word, 4'hf, 0, AXI_RESP_OKAY);
            axil_write_expect(10'h000, IMAGE_BASE, 4'hf, 1, AXI_RESP_OKAY);

            while (O_top[2] !== 1'b1)
                @(posedge clk);

            axil_write_expect(10'h008, 32'h0000_0200, 4'hf,
                              2, AXI_RESP_SLVERR);
            axil_write_expect(10'h000, 32'hdead_beef, 4'hf,
                              0, AXI_RESP_SLVERR);

            wait_for_busy_then_done(10000);
            @(negedge clk);
            verify_operation_data();
            if (O_top[3] !== 1'b1)
                record_error("rejected busy write did not set error_sticky");
            operation_active = 1'b0;
            operation_count = operation_count + 1;
        end
    endtask

    task automatic test_mode_specific_kernel_validation;
        logic [31:0] config_word;
        begin
            $display("Checking 3x3 kernel validation and 1x1 kernel-field ignore behavior...");
            config_word = 32'd0;
            config_word[3]   = 1'b1;
            config_word[6:5] = 2'd3;
            config_word[8:7] = 2'd3;
            config_word[9]   = 1'b0;

            axil_write_expect(10'h008, config_word, 4'hf, 1, AXI_RESP_OKAY);
            axil_write_expect(10'h000, WEIGHT_BASE, 4'hf,
                              2, AXI_RESP_SLVERR);
            if (O_top[2] !== 1'b0)
                record_error("invalid 3x3 kernel unexpectedly started the DMA");
            if (O_top[3] !== 1'b1)
                record_error("invalid 3x3 kernel did not set error_sticky");

            // The identical ky/kx values are legal and ignored in 1x1 mode.
            run_operation(1, 1, 0, 0, 1, 1, 3, 3);
        end
    endtask

    initial begin : main_test
        integer ty;
        integer tx;
        integer ci;
        integer co;
        integer ky;
        integer kx;

        clk          = 1'b0;
        rstn         = 1'b0;
        axil_awaddr  = 10'd0;
        axil_awvalid = 1'b0;
        axil_wdata   = 32'd0;
        axil_wstrb   = 4'd0;
        axil_wvalid  = 1'b0;
        axil_bready  = 1'b1;
        axil_araddr  = 10'd0;
        axil_arvalid = 1'b0;
        axil_rready  = 1'b1;
        dma_act_port_grant    = 1'b0;
        dma_weight_port_grant = 1'b0;
        array_active          = 1'b0;
        for (ty = 0; ty < 8; ty = ty + 1)
            act_compute_addr[ty] = 9'h100 + ty;

        errors          = 0;
        cycle_count     = 0;
        operation_count = 0;
        command_count   = 0;
        last_count      = 0;
        swap_count      = 0;
        zero_count      = 0;
        last_weight_cycle = -1000;
        operation_active = 1'b0;
        expected_high_half = 1'b0;

        total_commands            = 0;
        total_zero_commands       = 0;
        total_swaps               = 0;
        expected_total_commands   = 0;
        expected_total_zero_commands = 0;
        expected_total_swaps      = 0;
        expected_operation_axi_bursts = 0;
        expected_operation_axi_beats = 0;
        expected_row_beats_remaining = 0;
        expected_rows_remaining = 0;
        expected_next_araddr = 32'd0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;

        $display("============================================================");
        $display(" PACKED 1x1 / 3x3 DIRECT-32 LONG-BURST DMA REGRESSION");
        $display("============================================================");

        axil_read_expect(10'h000, AXI_RESP_OKAY, 32'd0);
        axil_read_expect(10'h004, AXI_RESP_OKAY, 32'd0);
        axil_read_expect(10'h008, AXI_RESP_OKAY, 32'd0);
        axil_read_expect(10'h00c, AXI_RESP_DECERR, 32'd0);
        axil_write_expect(10'h00c, 32'hdead_beef, 4'hf,
                          0, AXI_RESP_DECERR);

        // Confirm byte-strobe behavior across config bits [9:8] and [7:0].
        axil_write_expect(10'h008, 32'h0000_005a, 4'b0001,
                          1, AXI_RESP_OKAY);
        axil_write_expect(10'h008, 32'h0000_0300, 4'b0010,
                          2, AXI_RESP_OKAY);
        axil_read_expect(10'h008, AXI_RESP_OKAY, 32'h0000_035a);
        axil_write_expect(10'h008, 32'd0, 4'hf, 0, AXI_RESP_OKAY);

        // Packed activation pointers must be eight-byte aligned. The DMA
        // splits a row only when necessary to obey AXI's 4 KiB rule.
        axil_write_expect(10'h000, IMAGE_BASE + 1, 4'hf,
                          1, AXI_RESP_SLVERR);
        if (O_top[2] !== 1'b0)
            record_error("misaligned source base unexpectedly started DMA");
        axil_write_expect(10'h000, IMAGE_BASE + 4, 4'hf,
                          2, AXI_RESP_SLVERR);

        // A packed 64-byte weight slice is required to be 64-byte aligned so
        // it is always fetched by exactly one 16-beat burst.
        axil_write_expect(10'h008, 32'h0000_0208, 4'hf,
                          0, AXI_RESP_OKAY);
        axil_write_expect(10'h000, WEIGHT_BASE + 8, 4'hf,
                          1, AXI_RESP_SLVERR);
        if (O_top[2] !== 1'b0)
            record_error("misaligned packed weight pointer started DMA");
        axil_write_expect(10'h008, 32'd0, 4'hf, 2, AXI_RESP_OKAY);

        // Explicitly switch 3x3 -> 1x1 -> 3x3 -> 1x1 without reset or
        // reconfiguration of the fabric.
        $display("Checking immediate CPU-selected mode switching...");
        run_operation(0, 0, 0, 0, 0, 0, 0, 0);
        run_operation(1, 0, 1, 1, 1, 0, 0, 0);
        run_operation(0, 1, 0, 0, 1, 1, 2, 2);
        run_operation(1, 1, 0, 0, 0, 1, 0, 0);

        test_4k_boundary_split();
        test_busy_rejection();
        test_mode_specific_kernel_validation();

        $display("Checking all 3x3 activation configurations...");
        for (ty = 0; ty < 2; ty = ty + 1)
            for (tx = 0; tx < 2; tx = tx + 1)
                for (ci = 0; ci < 2; ci = ci + 1)
                    run_operation(0, 0, ty, tx, ci, 0, 0, 0);

        $display("Checking all 3x3 weight configurations...");
        for (ky = 0; ky < 3; ky = ky + 1)
            for (kx = 0; kx < 3; kx = kx + 1)
                for (ci = 0; ci < 2; ci = ci + 1)
                    for (co = 0; co < 2; co = co + 1)
                        run_operation(0, 1, 0, 0, ci, co, ky, kx);

        $display("Checking all 1x1 activation configurations...");
        for (ty = 0; ty < 2; ty = ty + 1)
            for (tx = 0; tx < 2; tx = tx + 1)
                for (ci = 0; ci < 2; ci = ci + 1)
                    run_operation(1, 0, ty, tx, ci, 0, 0, 0);

        $display("Checking all 1x1 weight configurations...");
        for (ci = 0; ci < 2; ci = ci + 1)
            for (co = 0; co < 2; co = co + 1)
                run_operation(1, 1, 0, 0, ci, co, 0, 0);

        if (total_commands != expected_total_commands)
            record_error("aggregate accepted-command count mismatch");
        if (total_zero_commands != expected_total_zero_commands)
            record_error("aggregate zero-fill count mismatch");
        if (total_swaps != expected_total_swaps)
            record_error("aggregate weight-swap count mismatch");

        $display("------------------------------------------------------------");
        $display("Operations checked       : %0d", operation_count);
        $display("Map commands checked     : %0d", total_commands);
        $display("AXI read bursts checked  : %0d", total_axi_bursts);
        $display("AXI read beats checked   : %0d", total_axi_beats);
        $display("3x3 zero-fill commands   : %0d", total_zero_commands);
        $display("Weight swaps checked     : %0d", total_swaps);
        $display("Simulation cycles        : %0d", cycle_count);

        if (errors == 0) begin
            $display("PASS: packed DMA and ownership-qualified NPU SRAM adapter match all schedules");
            $finish;
        end else begin
            $display("FAIL: %0d errors", errors);
            $fatal(1);
        end
    end

    initial begin : timeout_watchdog
        repeat (250000) @(posedge clk);
        $fatal(1, "FAIL: combined DMA regression timed out");
    end

endmodule

`default_nettype wire
