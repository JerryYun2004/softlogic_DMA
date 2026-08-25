`timescale 1ns / 1ps
`default_nettype none

// Self-contained regression for the combined AXI4-Lite DMA.  It checks every
// supported activation tile/channel block, all 3x3 weight taps, all 1x1 weight
// slices, immediate mode switching, AXI AW/W ordering, partial configuration
// writes, invalid accesses, busy rejection, command stability under
// backpressure, halo zero-fill, lane stride, destination placement, last, and
// weight-swap timing.
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

    wire         map_valid;
    logic        map_ready;
    wire [31:0]  map_source_addr;
    wire [4:0]   map_source_stride;
    wire [8:0]   map_buffer_addr;
    wire [7:0]   map_bank_mask;
    wire         map_is_weight;
    wire         map_zero_fill;
    wire         map_last;
    wire         map_weight_swap;

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
    integer mon_expected_zero;
    logic [31:0] mon_expected_addr;

    dma_a dut (
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
        .map_valid         (map_valid),
        .map_ready         (map_ready),
        .map_source_addr   (map_source_addr),
        .map_source_stride (map_source_stride),
        .map_buffer_addr   (map_buffer_addr),
        .map_bank_mask     (map_bank_mask),
        .map_is_weight     (map_is_weight),
        .map_zero_fill     (map_zero_fill),
        .map_last          (map_last),
        .map_weight_swap   (map_weight_swap)
    );

    always #5 clk = ~clk;

    function automatic [7:0] memory_byte(input logic [31:0] address);
        begin
            memory_byte = address[7:0] ^ address[15:8] ^
                          address[23:16] ^ address[31:24];
        end
    endfunction

    task automatic record_error(input string message);
        begin
            errors = errors + 1;
            if (errors <= 30)
                $display("ERROR [%0t]: %s", $time, message);
        end
    endtask

    // Deterministic backpressure produces one- and multi-cycle stalls without
    // making the regression dependent on a random seed.
    always @(negedge clk) begin
        if (!rstn)
            map_ready <= 1'b0;
        else
            map_ready <= ((cycle_count % 7) != 1) &&
                         ((cycle_count % 11) != 4);
    end

    // Command-level reference model and a behavioral eight-lane destination.
    always @(posedge clk) begin
        if (!rstn) begin
            cycle_count       = 0;
            stalled_command   = 1'b0;
            total_commands    = 0;
            total_zero_commands = 0;
            total_swaps       = 0;
        end else begin
            cycle_count = cycle_count + 1;

            if (stalled_command) begin
                if (!map_valid)
                    record_error("map_valid dropped while a command was stalled");
                if ((map_source_addr   !== held_source_addr)   ||
                    (map_source_stride !== held_source_stride) ||
                    (map_buffer_addr   !== held_buffer_addr)   ||
                    (map_bank_mask     !== held_bank_mask)     ||
                    (map_is_weight     !== held_is_weight)     ||
                    (map_zero_fill     !== held_zero_fill)     ||
                    (map_last          !== held_last))
                    record_error("a map command changed under backpressure");
            end

            if (map_valid && !map_ready) begin
                if (!stalled_command) begin
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
                    record_error("map command occurred outside an active operation");
                end else begin
                    if (map_bank_mask !== 8'hff)
                        record_error("map_bank_mask must select all eight banks");
                    if (map_is_weight !== exp_weight)
                        record_error("map_is_weight does not match the CPU command");

                    if (exp_weight) begin
                        mon_tap = exp_conv_1x1 ? 0 : (exp_ky * 3 + exp_kx);
                        mon_expected_addr = exp_base + mon_tap * 256 +
                                            exp_cin * 128 + exp_cout * 8 +
                                            (7 - command_count);

                        if (map_source_addr !== mon_expected_addr)
                            record_error("weight source address mismatch");
                        if (map_source_stride !== 5'd16)
                            record_error("weight source lane stride must be 16");
                        if (map_buffer_addr !== command_count[8:0])
                            record_error("weight shift index mismatch");
                        if (map_zero_fill !== 1'b0)
                            record_error("weight command asserted zero fill");
                        if (map_last !== (command_count == 7))
                            record_error("weight last flag mismatch");

                        for (mon_lane = 0; mon_lane < 8;
                             mon_lane = mon_lane + 1) begin
                            loaded_weight[mon_lane][7-command_count] =
                                memory_byte(map_source_addr +
                                            mon_lane * map_source_stride);
                        end
                    end else begin
                        if (exp_conv_1x1) begin
                            mon_ly = command_count / 16;
                            mon_lx = command_count % 16;
                            mon_gy = exp_tile_y * 16 + mon_ly;
                            mon_gx = exp_tile_x * 16 + mon_lx;
                        end else begin
                            mon_ly = command_count / 18;
                            mon_lx = command_count % 18;
                            mon_gy = exp_tile_y * 16 + mon_ly - 1;
                            mon_gx = exp_tile_x * 16 + mon_lx - 1;
                        end

                        mon_offset = ((mon_gy * 32 + mon_gx) * 16) +
                                     exp_cin * 8;
                        mon_expected_addr = exp_base + mon_offset;
                        mon_expected_zero = !exp_conv_1x1 &&
                                            ((mon_gy < 0) || (mon_gy >= 32) ||
                                             (mon_gx < 0) || (mon_gx >= 32));

                        if (map_source_addr !== mon_expected_addr)
                            record_error("activation source address mismatch");
                        if (map_source_stride !== 5'd1)
                            record_error("activation source lane stride must be one");
                        if (map_buffer_addr !== command_count[8:0])
                            record_error("activation destination address mismatch");
                        if (map_zero_fill !== (mon_expected_zero != 0))
                            record_error("activation halo zero-fill mismatch");
                        if (map_last !== (command_count == exp_commands-1))
                            record_error("activation last flag mismatch");

                        if (map_zero_fill) begin
                            zero_count = zero_count + 1;
                            total_zero_commands = total_zero_commands + 1;
                        end

                        for (mon_lane = 0; mon_lane < 8;
                             mon_lane = mon_lane + 1) begin
                            if (map_zero_fill)
                                activation_bank[mon_lane][command_count] = 8'd0;
                            else
                                activation_bank[mon_lane][command_count] =
                                    memory_byte(map_source_addr + mon_lane);
                        end
                    end

                    if (map_last)
                        last_count = last_count + 1;
                    if (exp_weight && (command_count == 7))
                        last_weight_cycle = cycle_count;

                    command_count = command_count + 1;
                    total_commands = total_commands + 1;
                end
            end

            if (map_weight_swap) begin
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
            operation_active  = 1'b1;

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
            if (last_count != 1)
                record_error("operation did not emit exactly one last flag");
            if (swap_count != (exp_weight ? 1 : 0))
                record_error("operation weight-swap count mismatch");
            if (zero_count != ((!exp_weight && !exp_conv_1x1) ? 35 : 0))
                record_error("operation zero-fill command count mismatch");

            if (exp_weight) begin
                tap = exp_conv_1x1 ? 0 : (exp_ky * 3 + exp_kx);
                for (r = 0; r < 8; r = r + 1) begin
                    for (p = 0; p < 8; p = p + 1) begin
                        address = exp_base + tap * 256 + exp_cin * 128 +
                                  exp_cout * 8 + r * 16 + p;
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
                        gy = exp_tile_y * 16 + ly;
                        gx = exp_tile_x * 16 + lx;
                    end else begin
                        ly = p / 18;
                        lx = p % 18;
                        gy = exp_tile_y * 16 + ly - 1;
                        gx = exp_tile_x * 16 + lx - 1;
                    end
                    offset = ((gy * 32 + gx) * 16) + exp_cin * 8;
                    address = exp_base + offset;
                    expected_zero = !exp_conv_1x1 &&
                                    ((gy < 0) || (gy >= 32) ||
                                     (gx < 0) || (gx >= 32));

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
            base_address = load_weight ? WEIGHT_BASE : IMAGE_BASE;
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

            wait_for_busy_then_done(2000);
            @(negedge clk);
            verify_operation_data();
            if (O_top[3] !== 1'b0)
                record_error("successful operation left error_sticky set");

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

            wait_for_busy_then_done(2000);
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
        map_ready    = 1'b0;

        errors          = 0;
        cycle_count     = 0;
        operation_count = 0;
        command_count   = 0;
        last_count      = 0;
        swap_count      = 0;
        zero_count      = 0;
        last_weight_cycle = -1000;
        operation_active = 1'b0;

        total_commands            = 0;
        total_zero_commands       = 0;
        total_swaps               = 0;
        expected_total_commands   = 0;
        expected_total_zero_commands = 0;
        expected_total_swaps      = 0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;

        $display("============================================================");
        $display(" COMBINED 1x1 / 3x3 DMA AXI + LOADING-ALGORITHM REGRESSION");
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

        // Explicitly switch 3x3 -> 1x1 -> 3x3 -> 1x1 without reset or
        // reconfiguration of the fabric.
        $display("Checking immediate CPU-selected mode switching...");
        run_operation(0, 0, 0, 0, 0, 0, 0, 0);
        run_operation(1, 0, 1, 1, 1, 0, 0, 0);
        run_operation(0, 1, 0, 0, 1, 1, 2, 2);
        run_operation(1, 1, 0, 0, 0, 1, 0, 0);

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
        $display("3x3 zero-fill commands   : %0d", total_zero_commands);
        $display("Weight swaps checked     : %0d", total_swaps);
        $display("Simulation cycles        : %0d", cycle_count);

        if (errors == 0) begin
            $display("PASS: combined DMA matches all 1x1 and 3x3 loading schedules");
            $finish;
        end else begin
            $display("FAIL: %0d errors", errors);
            $fatal(1);
        end
    end

    initial begin : timeout_watchdog
        repeat (100000) @(posedge clk);
        $fatal(1, "FAIL: combined DMA regression timed out");
    end

endmodule

`default_nettype wire
