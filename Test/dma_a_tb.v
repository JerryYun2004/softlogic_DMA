`timescale 1ns / 1ps
`default_nettype none

module dma_a_tb;

    localparam [31:0] TILE_BASE   = 32'h0000_0100;
    localparam [31:0] IMAGE_WIDTH = 32'd64;

    reg clk;
    reg rstn;

    wire [31:0] O_top;

    reg  [9:0]  axil_awaddr;
    reg          axil_awvalid;
    wire         axil_awready;
    reg  [31:0] axil_wdata;
    reg  [3:0]  axil_wstrb;
    reg          axil_wvalid;
    wire         axil_wready;
    wire [1:0]  axil_bresp;
    wire         axil_bvalid;
    reg          axil_bready;
    reg  [9:0]  axil_araddr;
    reg          axil_arvalid;
    wire         axil_arready;
    wire [31:0] axil_rdata;
    wire [1:0]  axil_rresp;
    wire         axil_rvalid;
    reg          axil_rready;

    wire [31:0] axi_awaddr;
    wire [7:0]  axi_awlen;
    wire [2:0]  axi_awsize;
    wire [1:0]  axi_awburst;
    wire         axi_awvalid;
    reg          axi_awready;
    wire [31:0] axi_wdata;
    wire [3:0]  axi_wstrb;
    wire         axi_wlast;
    wire         axi_wvalid;
    reg          axi_wready;
    reg  [1:0]  axi_bresp;
    reg          axi_bvalid;
    wire         axi_bready;

    wire [31:0] axi_araddr;
    wire [7:0]  axi_arlen;
    wire [2:0]  axi_arsize;
    wire [1:0]  axi_arburst;
    wire         axi_arvalid;
    reg          axi_arready;
    reg  [31:0] axi_rdata;
    reg  [1:0]  axi_rresp;
    reg          axi_rlast;
    reg          axi_rvalid;
    wire         axi_rready;

    wire         rowbuf_wr_valid;
    reg          rowbuf_wr_ready;
    wire [7:0]  rowbuf_wr_mask;
    wire [7:0]  rowbuf_wr_addr;
    wire [7:0]  rowbuf_wr_data;
    wire         rowbuf_wr_pass;
    wire         pass_loaded_valid;
    reg          pass_loaded_ready;
    wire         pass_loaded_id;

    reg [7:0] rowbuf_model [0:7][0:255];

    integer cycle_count;
    integer axi_read_count;
    integer clear_command_count;
    integer pass0_group_count;
    integer pass1_group_count;
    integer pass0_mask_bit_count;
    integer pass1_mask_bit_count;
    integer r;
    integer d;
    integer m;
    integer oy;
    integer ox;
    integer ky;
    integer kx;
    integer errors;

    reg        read_pending;
    reg [31:0] pending_read_addr;
    integer    read_delay;

    reg        held_rowbuf_valid;
    reg [7:0]  held_rowbuf_mask;
    reg [7:0]  held_rowbuf_addr;
    reg [7:0]  held_rowbuf_data;
    reg        held_rowbuf_pass;

    reg        held_arvalid;
    reg [31:0] held_araddr;

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
        .axi_rready(axi_rready),

        .rowbuf_wr_valid(rowbuf_wr_valid),
        .rowbuf_wr_ready(rowbuf_wr_ready),
        .rowbuf_wr_mask(rowbuf_wr_mask),
        .rowbuf_wr_addr(rowbuf_wr_addr),
        .rowbuf_wr_data(rowbuf_wr_data),
        .rowbuf_wr_pass(rowbuf_wr_pass),
        .pass_loaded_valid(pass_loaded_valid),
        .pass_loaded_ready(pass_loaded_ready),
        .pass_loaded_id(pass_loaded_id)
    );

    always #5 clk = ~clk;

    function [7:0] memory_byte;
        input [31:0] byte_addr;
        begin
            memory_byte = byte_addr[7:0] ^ byte_addr[15:8] ^ 8'hA5;
        end
    endfunction

    function [31:0] memory_word;
        input [31:0] aligned_addr;
        begin
            memory_word = {
                memory_byte(aligned_addr + 32'd3),
                memory_byte(aligned_addr + 32'd2),
                memory_byte(aligned_addr + 32'd1),
                memory_byte(aligned_addr)
            };
        end
    endfunction

    function integer popcount8;
        input [7:0] value;
        integer i;
        begin
            popcount8 = 0;
            for (i = 0; i < 8; i = i + 1)
                popcount8 = popcount8 + value[i];
        end
    endfunction

    task axil_write_okay;
        input [9:0]  addr;
        input [31:0] data;
        integer aw_done;
        integer w_done;
        begin
            @(negedge clk);
            axil_awaddr  <= addr;
            axil_awvalid <= 1'b1;
            axil_wdata   <= data;
            axil_wstrb   <= 4'hF;
            axil_wvalid  <= 1'b1;
            aw_done = 0;
            w_done  = 0;

            while (!aw_done || !w_done) begin
                @(posedge clk);
                if (!aw_done && axil_awvalid && axil_awready) begin
                    axil_awvalid <= 1'b0;
                    aw_done = 1;
                end
                if (!w_done && axil_wvalid && axil_wready) begin
                    axil_wvalid <= 1'b0;
                    w_done = 1;
                end
            end

            while (!axil_bvalid)
                @(negedge clk);

            if (axil_bresp !== 2'b00) begin
                $display("ERROR: AXI-Lite write 0x%03h returned BRESP=%b",
                         addr, axil_bresp);
                errors = errors + 1;
            end

            @(posedge clk);
            @(negedge clk);
        end
    endtask

    task axil_read;
        input  [9:0]  addr;
        output [31:0] data;
        output [1:0]  resp;
        integer ar_done;
        begin
            @(negedge clk);
            axil_araddr  <= addr;
            axil_arvalid <= 1'b1;
            ar_done = 0;

            while (!ar_done) begin
                @(posedge clk);
                if (axil_arvalid && axil_arready) begin
                    axil_arvalid <= 1'b0;
                    ar_done = 1;
                end
            end

            while (!axil_rvalid)
                @(negedge clk);

            data = axil_rdata;
            resp = axil_rresp;
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    task verify_pass0;
        reg [7:0] expected;
        reg [31:0] source_addr;
        begin
            for (r = 0; r < 8; r = r + 1) begin
                for (d = 0; d <= 202; d = d + 1) begin
                    m = d - r;
                    if ((m >= 0) && (m < 196)) begin
                        oy = m / 14;
                        ox = m % 14;
                        ky = r / 3;
                        kx = r % 3;
                        source_addr = TILE_BASE +
                                      ((oy + ky) * IMAGE_WIDTH) +
                                      (ox + kx);
                        expected = memory_byte(source_addr);
                    end else begin
                        expected = 8'd0;
                    end

                    if (rowbuf_model[r][d] !== expected) begin
                        $display("ERROR P0: row=%0d addr=%0d got=%02h exp=%02h",
                                 r, d, rowbuf_model[r][d], expected);
                        errors = errors + 1;
                    end
                end
            end

            if (clear_command_count != 203) begin
                $display("ERROR: clear commands=%0d expected=203",
                         clear_command_count);
                errors = errors + 1;
            end
            if (pass0_group_count != 658) begin
                $display("ERROR: pass0 group commands=%0d expected=658",
                         pass0_group_count);
                errors = errors + 1;
            end
            if (pass0_mask_bit_count != 1568) begin
                $display("ERROR: pass0 selected-row writes=%0d expected=1568",
                         pass0_mask_bit_count);
                errors = errors + 1;
            end
            if (axi_read_count != 64) begin
                $display("ERROR: pass0 AXI word reads=%0d expected=64",
                         axi_read_count);
                errors = errors + 1;
            end
        end
    endtask

    task verify_pass1;
        reg [7:0] expected;
        reg [31:0] source_addr;
        begin
            for (d = 0; d < 196; d = d + 1) begin
                oy = d / 14;
                ox = d % 14;
                source_addr = TILE_BASE +
                              ((oy + 2) * IMAGE_WIDTH) +
                              (ox + 2);
                expected = memory_byte(source_addr);
                if (rowbuf_model[0][d] !== expected) begin
                    $display("ERROR P1: row=0 addr=%0d got=%02h exp=%02h",
                             d, rowbuf_model[0][d], expected);
                    errors = errors + 1;
                end
            end

            if (pass1_group_count != 196) begin
                $display("ERROR: pass1 group commands=%0d expected=196",
                         pass1_group_count);
                errors = errors + 1;
            end
            if (pass1_mask_bit_count != 196) begin
                $display("ERROR: pass1 selected-row writes=%0d expected=196",
                         pass1_mask_bit_count);
                errors = errors + 1;
            end
            if (axi_read_count != 120) begin
                $display("ERROR: total AXI word reads=%0d expected=120",
                         axi_read_count);
                errors = errors + 1;
            end
        end
    endtask

    // AXI source-memory model with deterministic request and response stalls.
    always @(posedge clk) begin
        if (!rstn) begin
            cycle_count       <= 0;
            axi_arready       <= 1'b0;
            axi_rdata         <= 32'd0;
            axi_rresp         <= 2'b00;
            axi_rlast         <= 1'b1;
            axi_rvalid        <= 1'b0;
            read_pending      <= 1'b0;
            pending_read_addr <= 32'd0;
            read_delay        <= 0;
            axi_read_count    <= 0;
        end else begin
            cycle_count <= cycle_count + 1;

            axi_arready <= !read_pending && !axi_rvalid &&
                           ((cycle_count % 4) != 0);

            if (axi_arvalid && axi_arready) begin
                if (axi_araddr[1:0] != 2'b00 || axi_arlen != 8'd0 ||
                    axi_arsize != 3'b010 || axi_arburst != 2'b01) begin
                    $display("ERROR: illegal AXI read request at cycle %0d",
                             cycle_count);
                    errors = errors + 1;
                end
                read_pending      <= 1'b1;
                pending_read_addr <= axi_araddr;
                read_delay        <= 1 + (cycle_count % 3);
                axi_read_count    <= axi_read_count + 1;
            end

            if (read_pending) begin
                if (read_delay == 0) begin
                    axi_rdata    <= memory_word(pending_read_addr);
                    axi_rresp    <= 2'b00;
                    axi_rlast    <= 1'b1;
                    axi_rvalid   <= 1'b1;
                    read_pending <= 1'b0;
                end else begin
                    read_delay <= read_delay - 1;
                end
            end

            if (axi_rvalid && axi_rready)
                axi_rvalid <= 1'b0;
        end
    end

    // Apply row-buffer backpressure, capture successful writes, and verify
    // that VALID payloads remain stable while stalled.
    always @(negedge clk) begin
        if (!rstn) begin
            rowbuf_wr_ready <= 1'b0;
        end else begin
            rowbuf_wr_ready <= ((cycle_count % 5) != 0);
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            clear_command_count <= 0;
            pass0_group_count   <= 0;
            pass1_group_count   <= 0;
            pass0_mask_bit_count <= 0;
            pass1_mask_bit_count <= 0;
            held_rowbuf_valid   <= 1'b0;
        end else begin
            if (held_rowbuf_valid) begin
                if (!rowbuf_wr_valid || rowbuf_wr_mask !== held_rowbuf_mask ||
                    rowbuf_wr_addr !== held_rowbuf_addr ||
                    rowbuf_wr_data !== held_rowbuf_data ||
                    rowbuf_wr_pass !== held_rowbuf_pass) begin
                    $display("ERROR: row-buffer VALID payload changed under stall");
                    errors = errors + 1;
                end
            end

            held_rowbuf_valid <= rowbuf_wr_valid && !rowbuf_wr_ready;
            if (rowbuf_wr_valid && !rowbuf_wr_ready) begin
                held_rowbuf_mask <= rowbuf_wr_mask;
                held_rowbuf_addr <= rowbuf_wr_addr;
                held_rowbuf_data <= rowbuf_wr_data;
                held_rowbuf_pass <= rowbuf_wr_pass;
            end

            if (rowbuf_wr_valid && rowbuf_wr_ready) begin
                if (rowbuf_wr_mask == 8'd0) begin
                    $display("ERROR: zero row-buffer mask on accepted command");
                    errors = errors + 1;
                end

                for (r = 0; r < 8; r = r + 1) begin
                    if (rowbuf_wr_mask[r])
                        rowbuf_model[r][rowbuf_wr_addr] <= rowbuf_wr_data;
                end

                if (!rowbuf_wr_pass && (rowbuf_wr_mask == 8'hFF)) begin
                    clear_command_count <= clear_command_count + 1;
                end else if (!rowbuf_wr_pass) begin
                    pass0_group_count <= pass0_group_count + 1;
                    pass0_mask_bit_count <= pass0_mask_bit_count +
                                            popcount8(rowbuf_wr_mask);
                end else begin
                    if (rowbuf_wr_mask != 8'b00000001) begin
                        $display("ERROR: pass1 mask=%02h expected=01",
                                 rowbuf_wr_mask);
                        errors = errors + 1;
                    end
                    pass1_group_count <= pass1_group_count + 1;
                    pass1_mask_bit_count <= pass1_mask_bit_count +
                                            popcount8(rowbuf_wr_mask);
                end
            end
        end
    end

    // AXI AR payload must remain stable while stalled.
    always @(posedge clk) begin
        if (!rstn) begin
            held_arvalid <= 1'b0;
            held_araddr  <= 32'd0;
        end else begin
            if (held_arvalid && (!axi_arvalid || axi_araddr !== held_araddr)) begin
                $display("ERROR: AXI ARVALID payload changed under stall");
                errors = errors + 1;
            end
            held_arvalid <= axi_arvalid && !axi_arready;
            if (axi_arvalid && !axi_arready)
                held_araddr <= axi_araddr;
        end
    end

    reg [31:0] status_data;
    reg [1:0]  status_resp;

    initial begin
        clk               = 1'b0;
        rstn              = 1'b0;
        axil_awaddr       = 10'd0;
        axil_awvalid      = 1'b0;
        axil_wdata        = 32'd0;
        axil_wstrb        = 4'd0;
        axil_wvalid       = 1'b0;
        axil_bready       = 1'b1;
        axil_araddr       = 10'd0;
        axil_arvalid      = 1'b0;
        axil_rready       = 1'b1;
        axi_awready       = 1'b0;
        axi_wready        = 1'b0;
        axi_bresp         = 2'b00;
        axi_bvalid        = 1'b0;
        pass_loaded_ready = 1'b0;
        errors            = 0;

        for (r = 0; r < 8; r = r + 1)
            for (d = 0; d < 256; d = d + 1)
                rowbuf_model[r][d] = 8'hCC;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;

        // Preserve the dummy DMA's start convention: configure width first,
        // then write tile_base to 0x00 to launch.
        axil_write_okay(10'h004, IMAGE_WIDTH);
        axil_write_okay(10'h000, TILE_BASE);

        // Wait for pass 0, then verify while deliberately withholding buffer
        // ownership from pass 1 for several cycles.
        wait (pass_loaded_valid && !pass_loaded_id);
        @(negedge clk);
        verify_pass0();
        repeat (4) begin
            @(posedge clk);
            if (axi_arvalid || rowbuf_wr_valid) begin
                $display("ERROR: DMA modified/fetched data while pass0 was owned");
                errors = errors + 1;
            end
        end

        @(negedge clk);
        pass_loaded_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        pass_loaded_ready = 1'b0;

        wait (pass_loaded_valid && pass_loaded_id);
        @(negedge clk);
        verify_pass1();
        repeat (3) @(posedge clk);

        @(negedge clk);
        pass_loaded_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        pass_loaded_ready = 1'b0;

        wait (O_top[1] && !O_top[2]);
        axil_read(10'h004, status_data, status_resp);
        if ((status_resp != 2'b00) || (status_data[2:0] != 3'b001)) begin
            $display("ERROR: final status data=%08h resp=%b",
                     status_data, status_resp);
            errors = errors + 1;
        end

        if (axi_awvalid || axi_wvalid || axi_bready) begin
            $display("ERROR: unused AXI write channel was active");
            errors = errors + 1;
        end

        if (clear_command_count + pass0_group_count + pass1_group_count !=
            1057) begin
            $display("ERROR: total row-buffer commands=%0d expected=1057",
                     clear_command_count + pass0_group_count +
                     pass1_group_count);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: grouped 3x3 DMA schedule verified; 203 clears, 658 pass0 groups, 196 pass1 groups, 120 cached AXI reads");
        else
            $display("FAIL: %0d errors", errors);

        $finish;
    end

    initial begin
        repeat (100000) @(posedge clk);
        $display("FAIL: simulation timeout");
        $finish;
    end

endmodule

`default_nettype wire
