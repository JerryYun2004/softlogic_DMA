`timescale 1ns / 1ps
`default_nettype none

// Self-checking regression for the loop-unrolled 1x1 DMA and its dma_a
// AXI-Lite wrapper. The test follows the 1x1 loop nest in
// tb_npu_top_with_srams.sv and uses the files emitted by
// soft_reference/generate_convolution.py.
module tb_conv1x1_dma;

    localparam logic [31:0] IMAGE_BASE  = 32'h1000_0000;
    localparam logic [31:0] WEIGHT_BASE = 32'h2000_0000;

    localparam int IMAGE_WORDS  = 32 * 32 * 16;
    localparam int WEIGHT_WORDS = 16 * 16;
    localparam int OUTPUT_WORDS = 32 * 32 * 16;

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

    logic [7:0]  input_mem  [0:IMAGE_WORDS-1];
    logic [7:0]  weight_mem [0:WEIGHT_WORDS-1];
    logic [31:0] golden_mem [0:OUTPUT_WORDS-1];

    logic [7:0]  activation_bank [0:7][0:255];
    logic [7:0]  loaded_weight   [0:7][0:7];
    logic [31:0] actual_output   [0:OUTPUT_WORDS-1];
    integer      partial_sum     [0:255][0:7];

    integer errors;
    integer cycle_count;
    integer ready_count;
    integer write_order;
    integer total_commands;

    integer expected_mode;
    integer expected_ty;
    integer expected_tx;
    integer expected_cin;
    integer expected_cout;
    integer command_count;
    integer swap_count;
    integer last_weight_cycle;
    logic   operation_active;

    logic        stalled_q;
    logic [31:0] held_source_addr;
    logic [4:0]  held_source_stride;
    logic [8:0]  held_buffer_addr;
    logic [7:0]  held_bank_mask;
    logic        held_is_weight;
    logic        held_zero_fill;
    logic        held_last;

    integer mon_y;
    integer mon_x;
    integer mon_lane;
    integer mon_index;
    logic [31:0] expected_addr_mon;

    dma_a dut (
        .clk(clk),
        .rstn(rstn),
        .O_top(O_top),
        .axil_awaddr(axil_awaddr),
        .axil_awvalid(axil_awvalid),
        .axil_awready(axil_awready),
        .axil_wdata(axil_wdata),
        .axil_wstrb(axil_wstrb),
        .axil_wvalid(axil_wvalid),
        .axil_wready(axil_wready),
        .axil_bresp(axil_bresp),
        .axil_bvalid(axil_bvalid),
        .axil_bready(axil_bready),
        .axil_araddr(axil_araddr),
        .axil_arvalid(axil_arvalid),
        .axil_arready(axil_arready),
        .axil_rdata(axil_rdata),
        .axil_rresp(axil_rresp),
        .axil_rvalid(axil_rvalid),
        .axil_rready(axil_rready),
        .map_valid(map_valid),
        .map_ready(map_ready),
        .map_source_addr(map_source_addr),
        .map_source_stride(map_source_stride),
        .map_buffer_addr(map_buffer_addr),
        .map_bank_mask(map_bank_mask),
        .map_is_weight(map_is_weight),
        .map_zero_fill(map_zero_fill),
        .map_last(map_last),
        .map_weight_swap(map_weight_swap)
    );

    always #5 clk = ~clk;

    // Deterministic backpressure: four accepted opportunities followed by one
    // stalled cycle. This verifies that every map field is held stable.
    always @(negedge clk) begin
        if (!rstn) begin
            ready_count <= 0;
            map_ready   <= 1'b0;
        end else begin
            ready_count <= ready_count + 1;
            map_ready   <= ((ready_count % 5) != 4);
        end
    end

    task automatic record_error(input string message);
        begin
            errors = errors + 1;
            if (errors <= 40)
                $display("ERROR cycle=%0d: %s", cycle_count, message);
        end
    endtask

    // Command checker and a behavioral model of the downstream eight-lane
    // memory adapter.
    always @(posedge clk) begin
        if (!rstn) begin
            cycle_count        = 0;
            total_commands     = 0;
            stalled_q          = 1'b0;
            held_source_addr   = 32'd0;
            held_source_stride = 5'd0;
            held_buffer_addr   = 9'd0;
            held_bank_mask     = 8'd0;
            held_is_weight     = 1'b0;
            held_zero_fill     = 1'b0;
            held_last          = 1'b0;
        end else begin
            cycle_count = cycle_count + 1;

            if (stalled_q) begin
                if (!map_valid) begin
                    record_error("map_valid dropped while a command was stalled");
                end else if ((map_source_addr   !== held_source_addr)   ||
                             (map_source_stride !== held_source_stride) ||
                             (map_buffer_addr   !== held_buffer_addr)   ||
                             (map_bank_mask     !== held_bank_mask)     ||
                             (map_is_weight     !== held_is_weight)     ||
                             (map_zero_fill     !== held_zero_fill)     ||
                             (map_last          !== held_last)) begin
                    record_error("map command changed under backpressure");
                end
            end

            if (map_valid && !map_ready) begin
                if (!stalled_q) begin
                    held_source_addr   = map_source_addr;
                    held_source_stride = map_source_stride;
                    held_buffer_addr   = map_buffer_addr;
                    held_bank_mask     = map_bank_mask;
                    held_is_weight     = map_is_weight;
                    held_zero_fill     = map_zero_fill;
                    held_last          = map_last;
                end
                stalled_q = 1'b1;
            end else begin
                stalled_q = 1'b0;
            end

            if (map_valid && map_ready) begin
                total_commands = total_commands + 1;

                if (!operation_active) begin
                    record_error("map command observed without an active test operation");
                end else if (expected_mode == 0) begin
                    mon_y = expected_ty * 16 + (command_count / 16);
                    mon_x = expected_tx * 16 + (command_count % 16);
                    expected_addr_mon = IMAGE_BASE +
                                        (mon_y * 32 * 16) +
                                        (mon_x * 16) +
                                        (expected_cin * 8);

                    if (map_is_weight !== 1'b0)
                        record_error("activation command marked as a weight command");
                    if (map_source_addr !== expected_addr_mon)
                        record_error("activation source address mismatch");
                    if (map_source_stride !== 5'd1)
                        record_error("activation lane stride must be one byte");
                    if (map_buffer_addr !== command_count[8:0])
                        record_error("activation buffer address mismatch");
                    if (map_bank_mask !== 8'hff)
                        record_error("activation bank mask must select all eight banks");
                    if (map_zero_fill !== 1'b0)
                        record_error("1x1 activation command must not request halo zero-fill");
                    if (map_last !== (command_count == 255))
                        record_error("activation last flag mismatch");

                    for (mon_lane = 0; mon_lane < 8; mon_lane = mon_lane + 1) begin
                        mon_index = (map_source_addr - IMAGE_BASE) + mon_lane;
                        if ((mon_index < 0) || (mon_index >= IMAGE_WORDS)) begin
                            record_error("activation memory address is outside the input tensor");
                        end else begin
                            activation_bank[mon_lane][command_count] = input_mem[mon_index];
                        end
                    end
                end else begin
                    expected_addr_mon = WEIGHT_BASE +
                                        (expected_cin * 8 * 16) +
                                        (expected_cout * 8) +
                                        (7 - command_count);

                    if (map_is_weight !== 1'b1)
                        record_error("weight command not marked as a weight command");
                    if (map_source_addr !== expected_addr_mon)
                        record_error("weight source address mismatch");
                    if (map_source_stride !== 5'd16)
                        record_error("weight lane stride must be 16 bytes");
                    if (map_buffer_addr !== command_count[8:0])
                        record_error("weight shift index mismatch");
                    if (map_bank_mask !== 8'hff)
                        record_error("weight command bank mask must be 8'hff");
                    if (map_zero_fill !== 1'b0)
                        record_error("weight command asserted zero-fill");
                    if (map_last !== (command_count == 7))
                        record_error("weight last flag mismatch");

                    for (mon_lane = 0; mon_lane < 8; mon_lane = mon_lane + 1) begin
                        mon_index = (map_source_addr - WEIGHT_BASE) +
                                    mon_lane * map_source_stride;
                        if ((mon_index < 0) || (mon_index >= WEIGHT_WORDS)) begin
                            record_error("weight memory address is outside the weight tensor");
                        end else begin
                            loaded_weight[mon_lane][7-command_count] = weight_mem[mon_index];
                        end
                    end

                    if (command_count == 7)
                        last_weight_cycle = cycle_count;
                end

                command_count = command_count + 1;
            end

            if (map_weight_swap) begin
                swap_count = swap_count + 1;
                if (!operation_active || (expected_mode != 1))
                    record_error("weight-swap pulse occurred outside a weight operation");
                if (map_valid)
                    record_error("weight-swap pulse overlapped a load command");
                if (cycle_count != (last_weight_cycle + 2))
                    record_error("weight-swap pulse did not follow one disabled shift cycle");
            end
        end
    end

    task automatic send_aw(input logic [9:0] address);
        integer accepted;
        begin
            accepted = 0;
            @(negedge clk);
            axil_awaddr  = address;
            axil_awvalid = 1'b1;
            while (accepted == 0) begin
                @(posedge clk);
                if (axil_awvalid && axil_awready)
                    accepted = 1;
            end
            @(negedge clk);
            axil_awvalid = 1'b0;
        end
    endtask

    task automatic send_w(input logic [31:0] data, input logic [3:0] strb);
        integer accepted;
        begin
            accepted = 0;
            @(negedge clk);
            axil_wdata  = data;
            axil_wstrb  = strb;
            axil_wvalid = 1'b1;
            while (accepted == 0) begin
                @(posedge clk);
                if (axil_wvalid && axil_wready)
                    accepted = 1;
            end
            @(negedge clk);
            axil_wvalid = 1'b0;
        end
    endtask

    task automatic axil_write(
        input logic [9:0]  address,
        input logic [31:0] data,
        input integer      order
    );
        begin
            case (order)
                0: begin
                    fork
                        send_aw(address);
                        send_w(data, 4'hf);
                    join
                end
                1: begin
                    send_aw(address);
                    send_w(data, 4'hf);
                end
                default: begin
                    send_w(data, 4'hf);
                    send_aw(address);
                end
            endcase

            wait (axil_bvalid === 1'b1);
            #1;
            if (axil_bresp !== 2'b00)
                record_error("AXI-Lite write returned a non-OKAY response");
            wait (axil_bvalid === 1'b0);
        end
    endtask

    task automatic axil_read_check(
        input logic [9:0]  address,
        input logic [31:0] expected_data
    );
        integer accepted;
        begin
            accepted = 0;
            @(negedge clk);
            axil_araddr  = address;
            axil_arvalid = 1'b1;
            while (accepted == 0) begin
                @(posedge clk);
                if (axil_arvalid && axil_arready)
                    accepted = 1;
            end
            @(negedge clk);
            axil_arvalid = 1'b0;

            wait (axil_rvalid === 1'b1);
            #1;
            if (axil_rresp !== 2'b00)
                record_error("AXI-Lite read returned a non-OKAY response");
            if (axil_rdata !== expected_data)
                record_error("AXI-Lite read data mismatch");
            wait (axil_rvalid === 1'b0);
        end
    endtask

    task automatic wait_for_done(input integer timeout_cycles);
        integer waited;
        begin
            waited = 0;
            while ((O_top[1] !== 1'b1) && (waited < timeout_cycles)) begin
                @(posedge clk);
                waited = waited + 1;
            end
            if (O_top[1] !== 1'b1)
                record_error("DMA operation timed out");
        end
    endtask

    task automatic run_activation(
        input integer ty,
        input integer tx,
        input integer cin_blk
    );
        integer m;
        integer r;
        integer source_index;
        logic [31:0] config_word;
        begin
            expected_mode = 0;
            expected_ty   = ty;
            expected_tx   = tx;
            expected_cin  = cin_blk;
            expected_cout = 0;
            command_count = 0;
            swap_count    = 0;
            last_weight_cycle = -1000;

            for (r = 0; r < 8; r = r + 1)
                for (m = 0; m < 256; m = m + 1)
                    activation_bank[r][m] = 8'hxx;

            config_word = (tx << 0) | (ty << 1) | (cin_blk << 2);
            axil_write(10'h008, config_word, write_order);
            write_order = (write_order + 1) % 3;

            operation_active = 1'b1;
            axil_write(10'h000, IMAGE_BASE, write_order);
            write_order = (write_order + 1) % 3;
            wait_for_done(2000);
            operation_active = 1'b0;

            if (command_count != 256)
                record_error("activation operation did not emit exactly 256 commands");
            if (swap_count != 0)
                record_error("activation operation emitted a weight-swap pulse");

            for (m = 0; m < 256; m = m + 1) begin
                mon_y = ty * 16 + (m / 16);
                mon_x = tx * 16 + (m % 16);
                for (r = 0; r < 8; r = r + 1) begin
                    source_index = (mon_y * 32 * 16) +
                                   (mon_x * 16) +
                                   (cin_blk * 8) + r;
                    if (activation_bank[r][m] !== input_mem[source_index])
                        record_error("loaded activation-bank data mismatch");
                end
            end
        end
    endtask

    task automatic run_weight(
        input integer cin_blk,
        input integer cout_blk
    );
        integer r;
        integer c;
        integer source_index;
        logic [31:0] config_word;
        begin
            expected_mode = 1;
            expected_ty   = 0;
            expected_tx   = 0;
            expected_cin  = cin_blk;
            expected_cout = cout_blk;
            command_count = 0;
            swap_count    = 0;
            last_weight_cycle = -1000;

            for (r = 0; r < 8; r = r + 1)
                for (c = 0; c < 8; c = c + 1)
                    loaded_weight[r][c] = 8'hxx;

            config_word = (cin_blk << 2) | (1 << 3) | (cout_blk << 4);
            axil_write(10'h008, config_word, write_order);
            write_order = (write_order + 1) % 3;

            operation_active = 1'b1;
            axil_write(10'h000, WEIGHT_BASE, write_order);
            write_order = (write_order + 1) % 3;
            wait_for_done(200);
            operation_active = 1'b0;

            if (command_count != 8)
                record_error("weight operation did not emit exactly eight commands");
            if (swap_count != 1)
                record_error("weight operation did not emit exactly one swap pulse");

            for (r = 0; r < 8; r = r + 1) begin
                for (c = 0; c < 8; c = c + 1) begin
                    source_index = ((cin_blk * 8 + r) * 16) +
                                   (cout_blk * 8 + c);
                    if (loaded_weight[r][c] !== weight_mem[source_index])
                        record_error("loaded 8x8 weight-slice data mismatch");
                end
            end
        end
    endtask

    integer init_index;
    integer ty;
    integer tx;
    integer cout_blk;
    integer cin_blk;
    integer m;
    integer c;
    integer r;
    integer output_y;
    integer output_x;
    integer output_index;
    integer golden_errors;

    initial begin
        clk             = 1'b0;
        rstn            = 1'b0;
        axil_awaddr     = 10'd0;
        axil_awvalid    = 1'b0;
        axil_wdata      = 32'd0;
        axil_wstrb      = 4'd0;
        axil_wvalid     = 1'b0;
        axil_bready     = 1'b1;
        axil_araddr     = 10'd0;
        axil_arvalid    = 1'b0;
        axil_rready     = 1'b1;
        map_ready       = 1'b0;
        errors          = 0;
        write_order     = 0;
        operation_active = 1'b0;
        expected_mode   = 0;
        expected_ty     = 0;
        expected_tx     = 0;
        expected_cin    = 0;
        expected_cout   = 0;
        command_count   = 0;
        swap_count      = 0;
        last_weight_cycle = -1000;

        $readmemh("../soft_reference/yolo_conv1_in.mem", input_mem);
        $readmemh("../soft_reference/yolo_conv1_w.mem", weight_mem);
        $readmemh("../soft_reference/golden_conv1.mem", golden_mem);

        for (init_index = 0; init_index < OUTPUT_WORDS; init_index = init_index + 1)
            actual_output[init_index] = 32'd0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;
        repeat (2) @(posedge clk);

        // Check the reset-visible configuration register before launching work.
        axil_read_check(10'h008, 32'd0);

        // Exact loop nest used by the supplied 1x1 CNN testbench:
        // tile_y, tile_x, cout_block, then two cin accumulation passes.
        for (ty = 0; ty < 2; ty = ty + 1) begin
            for (tx = 0; tx < 2; tx = tx + 1) begin
                for (cout_blk = 0; cout_blk < 2; cout_blk = cout_blk + 1) begin
                    for (m = 0; m < 256; m = m + 1)
                        for (c = 0; c < 8; c = c + 1)
                            partial_sum[m][c] = 0;

                    for (cin_blk = 0; cin_blk < 2; cin_blk = cin_blk + 1) begin
                        run_activation(ty, tx, cin_blk);
                        run_weight(cin_blk, cout_blk);

                        for (m = 0; m < 256; m = m + 1) begin
                            for (c = 0; c < 8; c = c + 1) begin
                                for (r = 0; r < 8; r = r + 1) begin
                                    partial_sum[m][c] = partial_sum[m][c] +
                                                        activation_bank[r][m] *
                                                        loaded_weight[r][c];
                                end
                            end
                        end
                    end

                    for (m = 0; m < 256; m = m + 1) begin
                        output_y = ty * 16 + (m / 16);
                        output_x = tx * 16 + (m % 16);
                        for (c = 0; c < 8; c = c + 1) begin
                            output_index = (output_y * 32 * 16) +
                                           (output_x * 16) +
                                           (cout_blk * 8 + c);
                            actual_output[output_index] = partial_sum[m][c];
                        end
                    end
                end
            end
        end

        golden_errors = 0;
        for (init_index = 0; init_index < OUTPUT_WORDS; init_index = init_index + 1) begin
            if (actual_output[init_index] !== golden_mem[init_index]) begin
                golden_errors = golden_errors + 1;
                if (golden_errors <= 10)
                    $display("GOLDEN MISMATCH index=%0d actual=%08x expected=%08x",
                             init_index, actual_output[init_index], golden_mem[init_index]);
            end
        end

        if (golden_errors != 0) begin
            errors = errors + golden_errors;
            $display("1x1 golden-model mismatches: %0d", golden_errors);
        end

        if (total_commands != ((16 * 256) + (16 * 8))) begin
            record_error("full workload command count was not 4224");
        end

        if (errors == 0) begin
            $display("PASS: loop-unrolled 1x1 DMA generated 4224 exact commands");
            $display("PASS: all 16384 CNN outputs match golden_conv1.mem");
        end else begin
            $fatal(1, "FAIL: 1x1 DMA regression found %0d errors", errors);
        end

        #20;
        $finish;
    end

endmodule

`default_nettype wire
