`timescale 1ns / 1ps
`default_nettype none

module dma_a_tb;

    localparam [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam [1:0] AXI_RESP_SLVERR = 2'b10;
    localparam [1:0] AXI_RESP_DECERR = 2'b11;

    reg clk;
    reg rstn;

    wire [31:0] O_top;

    // AXI4-Lite CPU-side stimulus
    reg  [9:0]  axil_awaddr;
    reg         axil_awvalid;
    wire        axil_awready;
    reg  [31:0] axil_wdata;
    reg  [3:0]  axil_wstrb;
    reg         axil_wvalid;
    wire        axil_wready;
    wire [1:0]  axil_bresp;
    wire        axil_bvalid;
    reg         axil_bready;
    reg  [9:0]  axil_araddr;
    reg         axil_arvalid;
    wire        axil_arready;
    wire [31:0] axil_rdata;
    wire [1:0]  axil_rresp;
    wire        axil_rvalid;
    reg         axil_rready;

    // AXI4 destination-slave model connections
    wire [31:0] axi_awaddr;
    wire [7:0]  axi_awlen;
    wire [2:0]  axi_awsize;
    wire [1:0]  axi_awburst;
    wire        axi_awvalid;
    reg         axi_awready;
    wire [31:0] axi_wdata;
    wire [3:0]  axi_wstrb;
    wire        axi_wlast;
    wire        axi_wvalid;
    reg         axi_wready;
    reg  [1:0]  axi_bresp;
    reg         axi_bvalid;
    wire        axi_bready;

    wire [31:0] axi_araddr;
    wire [7:0]  axi_arlen;
    wire [2:0]  axi_arsize;
    wire [1:0]  axi_arburst;
    wire        axi_arvalid;
    reg         axi_arready;
    reg  [31:0] axi_rdata;
    reg  [1:0]  axi_rresp;
    reg         axi_rlast;
    reg         axi_rvalid;
    wire        axi_rready;

    integer aw_count;
    integer w_count;
    integer b_count;

    reg        aw_was_stalled;
    reg [31:0] stalled_awaddr;
    reg        w_was_stalled;
    reg [31:0] stalled_wdata;
    reg [3:0]  stalled_wstrb;
    reg        stalled_wlast;

    reg [1:0]  response_1;
    reg [1:0]  response_2;
    reg [1:0]  response_3;
    reg [1:0]  response_4;
    reg [1:0]  response_busy;
    reg [1:0]  response_invalid;
    reg [31:0] read_data;
    reg [1:0]  read_response;

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

        .axi_awaddr(axi_awaddr),
        .axi_awlen(axi_awlen),
        .axi_awsize(axi_awsize),
        .axi_awburst(axi_awburst),
        .axi_awvalid(axi_awvalid),
        .axi_awready(axi_awready),
        .axi_wdata(axi_wdata),
        .axi_wstrb(axi_wstrb),
        .axi_wlast(axi_wlast),
        .axi_wvalid(axi_wvalid),
        .axi_wready(axi_wready),
        .axi_bresp(axi_bresp),
        .axi_bvalid(axi_bvalid),
        .axi_bready(axi_bready),
        .axi_araddr(axi_araddr),
        .axi_arlen(axi_arlen),
        .axi_arsize(axi_arsize),
        .axi_arburst(axi_arburst),
        .axi_arvalid(axi_arvalid),
        .axi_arready(axi_arready),
        .axi_rdata(axi_rdata),
        .axi_rresp(axi_rresp),
        .axi_rlast(axi_rlast),
        .axi_rvalid(axi_rvalid),
        .axi_rready(axi_rready)
    );

    always #5 clk = ~clk;

    task automatic expect_true;
        input condition;
        input [8*120-1:0] message;
        begin
            if (!condition) begin
                $display("FAIL: %0s", message);
                $fatal(1);
            end
        end
    endtask

    // AXI4-Lite write with independently selectable AW and W launch delays.
    task automatic axil_write;
        input [9:0]  address;
        input [31:0] data;
        input [3:0]  strb;
        input integer aw_delay;
        input integer w_delay;
        output [1:0] response;
        begin
            fork
                begin
                    repeat (aw_delay) @(posedge clk);
                    @(negedge clk);
                    axil_awaddr  = address;
                    axil_awvalid = 1'b1;
                    @(posedge clk);
                    while (!(axil_awvalid && axil_awready))
                        @(posedge clk);
                    @(negedge clk);
                    axil_awvalid = 1'b0;
                end

                begin
                    repeat (w_delay) @(posedge clk);
                    @(negedge clk);
                    axil_wdata  = data;
                    axil_wstrb  = strb;
                    axil_wvalid = 1'b1;
                    @(posedge clk);
                    while (!(axil_wvalid && axil_wready))
                        @(posedge clk);
                    @(negedge clk);
                    axil_wvalid = 1'b0;
                end
            join

            @(negedge clk);
            axil_bready = 1'b1;
            @(posedge clk);
            while (!axil_bvalid)
                @(posedge clk);
            response = axil_bresp;
            @(negedge clk);
            axil_bready = 1'b0;
        end
    endtask

    task automatic axil_read;
        input [9:0] address;
        output [31:0] data;
        output [1:0] response;
        begin
            @(negedge clk);
            axil_araddr  = address;
            axil_arvalid = 1'b1;
            @(posedge clk);
            while (!(axil_arvalid && axil_arready))
                @(posedge clk);
            @(negedge clk);
            axil_arvalid = 1'b0;
            axil_rready  = 1'b1;
            @(posedge clk);
            while (!axil_rvalid)
                @(posedge clk);
            data     = axil_rdata;
            response = axil_rresp;
            @(negedge clk);
            axil_rready = 1'b0;
        end
    endtask

    // Model one AXI4 slave write. Address and data READY can be delayed
    // independently to verify that the master holds each channel correctly.
    task automatic service_axi_write;
        input [31:0] expected_address;
        input integer aw_delay;
        input integer w_delay;
        input integer b_delay;
        input [1:0] response;
        begin
            fork
                begin
                    repeat (aw_delay) @(posedge clk);
                    @(negedge clk);
                    axi_awready = 1'b1;
                    @(posedge clk);
                    while (!(axi_awvalid && axi_awready))
                        @(posedge clk);

                    expect_true(axi_awaddr  === expected_address,
                                "AXI AWADDR does not match the programmed destination");
                    expect_true(axi_awlen   === 8'd0,
                                "AXI AWLEN must describe one beat");
                    expect_true(axi_awsize  === 3'b010,
                                "AXI AWSIZE must describe four bytes");
                    expect_true(axi_awburst === 2'b01,
                                "AXI AWBURST must be INCR");
                    @(negedge clk);
                    axi_awready = 1'b0;
                end

                begin
                    repeat (w_delay) @(posedge clk);
                    @(negedge clk);
                    axi_wready = 1'b1;
                    @(posedge clk);
                    while (!(axi_wvalid && axi_wready))
                        @(posedge clk);

                    expect_true(axi_wdata === 32'hDEADBEEF,
                                "AXI WDATA must be 32'hDEADBEEF");
                    expect_true(axi_wstrb === 4'hF,
                                "AXI WSTRB must enable all four bytes");
                    expect_true(axi_wlast === 1'b1,
                                "AXI WLAST must be asserted for the only beat");
                    @(negedge clk);
                    axi_wready = 1'b0;
                end
            join

            repeat (b_delay) @(posedge clk);
            @(negedge clk);
            axi_bresp  = response;
            axi_bvalid = 1'b1;
            @(posedge clk);
            while (!(axi_bvalid && axi_bready))
                @(posedge clk);
            @(negedge clk);
            axi_bvalid = 1'b0;
            axi_bresp  = AXI_RESP_OKAY;
        end
    endtask

    // Count completed master-channel handshakes.
    always @(posedge clk) begin
        if (!rstn) begin
            aw_count <= 0;
            w_count  <= 0;
            b_count  <= 0;
        end else begin
            if (axi_awvalid && axi_awready) aw_count <= aw_count + 1;
            if (axi_wvalid  && axi_wready)  w_count  <= w_count + 1;
            if (axi_bvalid  && axi_bready)  b_count  <= b_count + 1;
        end
    end

    // Protocol checks: payload and VALID must remain stable while stalled.
    always @(posedge clk) begin
        if (!rstn) begin
            aw_was_stalled <= 1'b0;
            w_was_stalled  <= 1'b0;
            stalled_awaddr <= 32'd0;
            stalled_wdata  <= 32'd0;
            stalled_wstrb  <= 4'd0;
            stalled_wlast  <= 1'b0;
        end else begin
            if (aw_was_stalled) begin
                expect_true(axi_awvalid === 1'b1,
                            "AXI AWVALID dropped before AWREADY");
                expect_true(axi_awaddr === stalled_awaddr,
                            "AXI AWADDR changed while stalled");
            end

            if (w_was_stalled) begin
                expect_true(axi_wvalid === 1'b1,
                            "AXI WVALID dropped before WREADY");
                expect_true(axi_wdata === stalled_wdata,
                            "AXI WDATA changed while stalled");
                expect_true(axi_wstrb === stalled_wstrb,
                            "AXI WSTRB changed while stalled");
                expect_true(axi_wlast === stalled_wlast,
                            "AXI WLAST changed while stalled");
            end

            aw_was_stalled <= axi_awvalid && !axi_awready;
            w_was_stalled  <= axi_wvalid  && !axi_wready;

            if (axi_awvalid && !axi_awready)
                stalled_awaddr <= axi_awaddr;

            if (axi_wvalid && !axi_wready) begin
                stalled_wdata <= axi_wdata;
                stalled_wstrb <= axi_wstrb;
                stalled_wlast <= axi_wlast;
            end
        end
    end

    initial begin
        clk          = 1'b0;
        rstn         = 1'b0;
        axil_awaddr  = 10'd0;
        axil_awvalid = 1'b0;
        axil_wdata   = 32'd0;
        axil_wstrb   = 4'd0;
        axil_wvalid  = 1'b0;
        axil_bready  = 1'b0;
        axil_araddr  = 10'd0;
        axil_arvalid = 1'b0;
        axil_rready  = 1'b0;

        axi_awready = 1'b0;
        axi_wready  = 1'b0;
        axi_bresp   = AXI_RESP_OKAY;
        axi_bvalid  = 1'b0;
        axi_arready = 1'b0;
        axi_rdata   = 32'd0;
        axi_rresp   = AXI_RESP_OKAY;
        axi_rlast   = 1'b0;
        axi_rvalid  = 1'b0;

        $dumpfile("build/dma_a_tb.vcd");
        $dumpvars(0, dma_a_tb);

        repeat (5) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;
        repeat (2) @(posedge clk);

        expect_true(axi_awvalid === 1'b0,
                    "AWVALID must be low after reset");
        expect_true(axi_wvalid === 1'b0,
                    "WVALID must be low after reset");
        expect_true(axi_arvalid === 1'b0 && axi_rready === 1'b0,
                    "unused AXI read channels must remain inactive");
        expect_true(O_top[3:1] === 3'b000,
                    "done, busy, and error must clear on reset");

        $display("TEST 1: AXI-Lite AW first; independently stalled AXI AW/W");
        fork
            axil_write(10'h000, 32'h00000100, 4'hF, 0, 3, response_1);
            service_axi_write(32'h00000100, 5, 8, 2, AXI_RESP_OKAY);
        join
        expect_true(response_1 === AXI_RESP_OKAY,
                    "first AXI-Lite command was not accepted");
        axil_read(10'h004, read_data, read_response);
        expect_true(read_response === AXI_RESP_OKAY,
                    "status read returned an AXI-Lite error");
        expect_true(read_data[2:0] === 3'b001,
                    "successful completion must report done=1, busy=0, error=0");

        $display("TEST 2: AXI-Lite W first; completion flag clears on restart");
        fork
            axil_write(10'h000, 32'h00000200, 4'hF, 4, 0, response_2);
            service_axi_write(32'h00000200, 7, 2, 1, AXI_RESP_OKAY);
            begin
                wait (O_top[2] === 1'b1);
                expect_true(O_top[1] === 1'b0,
                            "done must clear when a new command starts");
            end
        join
        expect_true(response_2 === AXI_RESP_OKAY,
                    "second AXI-Lite command was not accepted");
        axil_read(10'h004, read_data, read_response);
        expect_true(read_data[2:0] === 3'b001,
                    "second successful completion reported incorrect status");

        $display("TEST 3: AXI write response error propagation");
        fork
            axil_write(10'h000, 32'h00000300, 4'hF, 0, 0, response_3);
            service_axi_write(32'h00000300, 1, 4, 1, AXI_RESP_SLVERR);
        join
        expect_true(response_3 === AXI_RESP_OKAY,
                    "accepted command should receive AXI-Lite OKAY");
        axil_read(10'h004, read_data, read_response);
        expect_true(read_data[2:0] === 3'b101,
                    "failed AXI write must report done=1, busy=0, error=1");

        $display("TEST 4: reject a second command while the DMA is busy");
        fork
            begin
                axil_write(10'h000, 32'h00000400, 4'hF, 0, 0, response_4);
                expect_true(response_4 === AXI_RESP_OKAY,
                            "fourth command was not accepted");
                wait (O_top[2] === 1'b1);
                axil_write(10'h000, 32'h00000444, 4'hF, 0, 2,
                           response_busy);
                expect_true(response_busy === AXI_RESP_SLVERR,
                            "command issued while busy must receive SLVERR");
            end
            service_axi_write(32'h00000400, 14, 17, 2, AXI_RESP_OKAY);
        join
        axil_read(10'h004, read_data, read_response);
        expect_true(read_data[2:0] === 3'b001,
                    "successful transfer after busy rejection has bad status");

        $display("TEST 5: unmapped AXI-Lite address returns DECERR");
        axil_write(10'h008, 32'h12345678, 4'hF, 0, 0,
                   response_invalid);
        expect_true(response_invalid === AXI_RESP_DECERR,
                    "unmapped AXI-Lite write must receive DECERR");

        repeat (3) @(posedge clk);
        expect_true(aw_count == 4,
                    "unexpected number of AXI write-address transactions");
        expect_true(w_count == 4,
                    "unexpected number of AXI write-data transactions");
        expect_true(b_count == 4,
                    "unexpected number of AXI write responses");
        expect_true(axi_arvalid === 1'b0 && axi_rready === 1'b0,
                    "one-word write engine unexpectedly used AXI read channels");

        $display("PASS: one-word 32'hDEADBEEF AXI write engine verified");
        $finish;
    end

    initial begin
        #20000;
        $display("FAIL: testbench timeout");
        $fatal(1);
    end

endmodule

`default_nettype wire
