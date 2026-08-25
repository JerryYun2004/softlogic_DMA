`timescale 1ns / 1ps
`default_nettype none

module tb_gemm_dma_unit;

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    logic        clk;
    logic        rstn;
    logic [31:0] O_top;

    logic [9:0]  axil_awaddr;
    logic        axil_awvalid;
    logic        axil_awready;
    logic [31:0] axil_wdata;
    logic [3:0]  axil_wstrb;
    logic        axil_wvalid;
    logic        axil_wready;
    logic [1:0]  axil_bresp;
    logic        axil_bvalid;
    logic        axil_bready;
    logic [9:0]  axil_araddr;
    logic        axil_arvalid;
    logic        axil_arready;
    logic [31:0] axil_rdata;
    logic [1:0]  axil_rresp;
    logic        axil_rvalid;
    logic        axil_rready;

    logic        map_valid;
    logic        map_ready;
    logic [31:0] map_source_addr;
    logic [31:0] map_source_stride;
    logic [8:0]  map_buffer_addr;
    logic [7:0]  map_bank_mask;
    logic        map_is_weight;
    logic        map_zero_fill;
    logic        map_last;
    logic        map_weight_swap;

    integer errors;

    always #5 clk = ~clk;

    gemm_dma_axi_wrapper dut (
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

    task automatic expect_true(
        input logic condition,
        input string message
    );
        begin
            if (!condition) begin
                errors = errors + 1;
                $display("ERROR [%0t]: %s", $time, message);
            end
        end
    endtask

    task automatic axil_write(
        input  logic [9:0]  address,
        input  logic [31:0] data,
        input  logic [3:0]  strobe,
        output logic [1:0]  response
    );
        logic aw_done;
        logic w_done;
        integer timeout;
        begin
            aw_done = 1'b0;
            w_done  = 1'b0;
            timeout = 0;

            @(negedge clk);
            axil_awaddr  = address;
            axil_awvalid = 1'b1;
            axil_wdata   = data;
            axil_wstrb   = strobe;
            axil_wvalid  = 1'b1;

            while (!(aw_done && w_done)) begin
                @(posedge clk);
                if (axil_awvalid && axil_awready)
                    aw_done = 1'b1;
                if (axil_wvalid && axil_wready)
                    w_done = 1'b1;

                @(negedge clk);
                if (aw_done)
                    axil_awvalid = 1'b0;
                if (w_done)
                    axil_wvalid = 1'b0;

                timeout = timeout + 1;
                if (timeout > 20) begin
                    $fatal(1, "AXI write handshake timeout at 0x%03h", address);
                end
            end

            timeout = 0;
            while (!axil_bvalid) begin
                @(negedge clk);
                timeout = timeout + 1;
                if (timeout > 20)
                    $fatal(1, "AXI write response timeout at 0x%03h", address);
            end

            response    = axil_bresp;
            axil_bready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            axil_bready = 1'b0;
        end
    endtask

    task automatic axil_read(
        input  logic [9:0]  address,
        output logic [31:0] data,
        output logic [1:0]  response
    );
        integer timeout;
        begin
            @(negedge clk);
            axil_araddr  = address;
            axil_arvalid = 1'b1;

            timeout = 0;
            while (!axil_arready) begin
                @(negedge clk);
                timeout = timeout + 1;
                if (timeout > 20)
                    $fatal(1, "AXI read-address timeout at 0x%03h", address);
            end

            @(posedge clk);
            @(negedge clk);
            axil_arvalid = 1'b0;

            timeout = 0;
            while (!axil_rvalid) begin
                @(negedge clk);
                timeout = timeout + 1;
                if (timeout > 20)
                    $fatal(1, "AXI read-data timeout at 0x%03h", address);
            end

            data        = axil_rdata;
            response    = axil_rresp;
            axil_rready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            axil_rready = 1'b0;
        end
    endtask

    task automatic check_activation_stream(
        input logic [31:0] expected_base,
        input logic [31:0] expected_row_stride,
        input integer      command_count
    );
        integer accepted;
        integer cycles;
        logic [31:0] expected_addr;
        begin
            accepted = 0;
            cycles   = 0;

            while (accepted < command_count) begin
                @(negedge clk);
                // Repeated stalls check ready/valid state retention.
                map_ready = ((cycles % 4) != 1);

                if (map_valid) begin
                    expected_addr = expected_base + accepted*expected_row_stride;
                    expect_true(map_source_addr == expected_addr,
                                $sformatf("A source address: got 0x%08h expected 0x%08h",
                                          map_source_addr, expected_addr));
                    expect_true(map_source_stride == 32'd1,
                                "A lane stride must be one byte");
                    expect_true(map_buffer_addr == accepted[8:0],
                                "A destination address mismatch");
                    expect_true(map_bank_mask == 8'hff,
                                "A bank mask must select all eight banks");
                    expect_true(!map_is_weight,
                                "A command incorrectly marked as weight");
                    expect_true(!map_zero_fill,
                                "GEMM DMA unexpectedly requested zero fill");
                    expect_true(map_last == (accepted == command_count-1),
                                "A map_last mismatch");

                    if (map_ready)
                        accepted = accepted + 1;
                end

                cycles = cycles + 1;
                if (cycles > 200)
                    $fatal(1, "Activation stream timeout");
            end

            // Allow the final ready/valid transfer to be sampled by the AGU.
            @(posedge clk);
            @(negedge clk);
            map_ready = 1'b0;
            expect_true(!map_valid, "A map_valid remained high after last transfer");
        end
    endtask

    task automatic check_weight_stream(
        input logic [31:0] expected_base,
        input logic [31:0] expected_row_stride
    );
        integer accepted;
        integer cycles;
        logic [31:0] expected_addr;
        begin
            accepted = 0;
            cycles   = 0;

            while (accepted < 8) begin
                @(negedge clk);
                map_ready = ((cycles % 3) != 0);

                if (map_valid) begin
                    expected_addr = expected_base + (7-accepted);
                    expect_true(map_source_addr == expected_addr,
                                $sformatf("B source address: got 0x%08h expected 0x%08h",
                                          map_source_addr, expected_addr));
                    expect_true(map_source_stride == expected_row_stride,
                                "B row/lane stride mismatch");
                    expect_true(map_buffer_addr == accepted[8:0],
                                "B shift index mismatch");
                    expect_true(map_bank_mask == 8'hff,
                                "B lane mask must select all eight rows");
                    expect_true(map_is_weight,
                                "B command not marked as weight");
                    expect_true(!map_zero_fill,
                                "B command unexpectedly requested zero fill");
                    expect_true(map_last == (accepted == 7),
                                "B map_last mismatch");

                    if (map_ready)
                        accepted = accepted + 1;
                end

                cycles = cycles + 1;
                if (cycles > 100)
                    $fatal(1, "Weight stream timeout");
            end

            // Sample the final transfer, then verify the required disabled
            // shift gap and the following one-cycle swap pulse.
            @(posedge clk);
            @(negedge clk);
            map_ready = 1'b0;
            expect_true(!map_valid, "B map_valid remained high after eighth transfer");
            expect_true(!map_weight_swap, "weight swap occurred without gap cycle");

            @(posedge clk);
            @(negedge clk);
            expect_true(map_weight_swap, "missing weight swap pulse");

            @(posedge clk);
            @(negedge clk);
            expect_true(!map_weight_swap, "weight swap pulse lasted more than one cycle");
        end
    endtask

    task automatic wait_done_sticky;
        integer timeout;
        begin
            timeout = 0;
            while (!O_top[1]) begin
                @(negedge clk);
                timeout = timeout + 1;
                if (timeout > 20)
                    $fatal(1, "DMA done-sticky timeout");
            end
        end
    endtask

    initial begin
        logic [1:0]  response;
        logic [1:0]  read_response;
        logic [31:0] read_data;
        logic [31:0] a_base;
        logic [31:0] b_base;

        clk            = 1'b0;
        rstn           = 1'b0;
        axil_awaddr    = '0;
        axil_awvalid   = 1'b0;
        axil_wdata     = '0;
        axil_wstrb     = '0;
        axil_wvalid    = 1'b0;
        axil_bready    = 1'b0;
        axil_araddr    = '0;
        axil_arvalid   = 1'b0;
        axil_rready    = 1'b0;
        map_ready      = 1'b0;
        errors         = 0;
        a_base         = 32'h0000_1005;
        b_base         = 32'h0000_2009;

        repeat (4) @(posedge clk);
        rstn = 1'b1;
        repeat (2) @(posedge clk);

        // A panel: five matrix rows, eight contiguous K values per row.
        axil_write(10'h00c, 32'd37, 4'hf, response);
        expect_true(response == AXI_RESP_OKAY, "A stride write failed");
        axil_write(10'h008, (32'd4 << 1), 4'hf, response);
        expect_true(response == AXI_RESP_OKAY, "A config write failed");
        axil_write(10'h000, a_base, 4'hf, response);
        expect_true(response == AXI_RESP_OKAY, "A start write failed");

        check_activation_stream(a_base, 32'd37, 5);
        wait_done_sticky();

        axil_read(10'h004, read_data, read_response);
        expect_true(read_response == AXI_RESP_OKAY, "status read failed");
        expect_true(read_data[2:0] == 3'b001,
                    "status should report done=1, busy=0, error=0");

        // B tile: exercise a row stride wider than the CNN wrapper's old
        // five-bit stride field.
        axil_write(10'h00c, 32'd53, 4'hf, response);
        expect_true(response == AXI_RESP_OKAY, "B stride write failed");
        axil_write(10'h008, 32'd1, 4'hf, response);
        expect_true(response == AXI_RESP_OKAY, "B config write failed");
        axil_write(10'h000, b_base, 4'hf, response);
        expect_true(response == AXI_RESP_OKAY, "B start write failed");

        check_weight_stream(b_base, 32'd53);
        wait_done_sticky();

        // A zero source stride is rejected and recorded in error_sticky.
        axil_write(10'h00c, 32'd0, 4'hf, response);
        expect_true(response == AXI_RESP_OKAY, "zero-stride register write failed");
        axil_write(10'h000, 32'h0000_3000, 4'hf, response);
        expect_true(response == AXI_RESP_SLVERR,
                    "zero-stride start should return SLVERR");
        expect_true(O_top[3], "zero-stride start did not set error_sticky");
        expect_true(!map_valid, "rejected start emitted a map command");

        if (errors == 0) begin
            $display("PASS: GEMM DMA unit regression completed with no errors");
        end else begin
            $fatal(1, "FAIL: GEMM DMA unit regression found %0d errors", errors);
        end

        $finish;
    end

endmodule

`default_nettype wire
