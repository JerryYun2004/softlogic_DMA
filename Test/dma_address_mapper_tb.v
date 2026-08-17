`timescale 1ns / 1ps
`default_nettype none

`ifndef YOLO_IMAGE_MEM
`define YOLO_IMAGE_MEM "yolo_image_3x3.mem"
`endif

// Regression for the AXI wrapper plus conv3x3_hwc_channel_dma_agu.
//
// The loop nesting below intentionally matches BENCHMARK 3 in
// tb_npu_top_with_srams.sv:
//
//   tile_y, tile_x, cout_block, cin_block, local_y, local_x, bank
//
// cout_block is not an AGU address input, but the original NPU testbench reloads
// the same activation patch for each of its two output-channel blocks.  Running
// both cout_block iterations here therefore verifies the same number of copies,
// not only the same final contents.
module dma_address_mapper_tb;

    localparam [31:0] IMAGE_BASE = 32'h1000_0000;
    localparam integer IMAGE_H = 32;
    localparam integer IMAGE_W = 32;
    localparam integer CHANNELS = 16;
    localparam integer BANKS = 8;
    localparam integer PATCH_SIDE = 18;
    localparam integer GROUPS_PER_LOAD = PATCH_SIDE * PATCH_SIDE; // 324
    localparam integer LOADS = 2 * 2 * 2 * 2;                    // 16
    localparam integer TOTAL_GROUP_COMMANDS = LOADS * GROUPS_PER_LOAD;
    localparam integer TOTAL_BANK_WRITES = TOTAL_GROUP_COMMANDS * BANKS;
    localparam integer ZERO_GROUPS_PER_LOAD = GROUPS_PER_LOAD - 17 * 17;
    localparam integer TOTAL_ZERO_GROUPS = LOADS * ZERO_GROUPS_PER_LOAD;

    localparam [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam [1:0] AXI_RESP_SLVERR = 2'b10;
    localparam [1:0] AXI_RESP_DECERR = 2'b11;

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

    wire         map_valid;
    reg          map_ready;
    wire [31:0] map_source_addr;
    wire [8:0]  map_buffer_addr;
    wire [7:0]  map_bank_mask;
    wire         map_zero_fill;
    wire         map_last;

    reg [7:0] raw_image [0:IMAGE_H*IMAGE_W*CHANNELS-1];
    reg [7:0] loaded_bank [0:BANKS-1][0:GROUPS_PER_LOAD-1];

    integer errors;
    integer cycle_count;
    integer accepted_groups;
    integer accepted_zero_groups;
    integer current_group_count;
    integer current_last_count;
    integer current_tile_y;
    integer current_tile_x;
    integer current_cout_block;
    integer current_cin_block;

    reg        held_map_valid;
    reg [31:0] held_source;
    reg [8:0]  held_buffer;
    reg [7:0]  held_mask;
    reg        held_zero;
    reg        held_last;

    integer score_p;
    integer score_ly;
    integer score_lx;
    integer score_gy;
    integer score_gx;
    integer score_bank;
    integer score_flat_base;
    reg        score_zero;
    reg [31:0] score_source;

    reg [31:0] read_data;
    reg [1:0]  read_resp;
    string     image_mem_path;

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
        .map_buffer_addr(map_buffer_addr),
        .map_bank_mask(map_bank_mask),
        .map_zero_fill(map_zero_fill),
        .map_last(map_last)
    );

    always #5 clk = ~clk;

    task clear_loaded_banks;
        integer bank;
        integer p;
        begin
            for (bank = 0; bank < BANKS; bank = bank + 1)
                for (p = 0; p < GROUPS_PER_LOAD; p = p + 1)
                    loaded_bank[bank][p] = 8'hx;
        end
    endtask

    // mode 0: AW and W together; mode 1: AW first; mode 2: W first.
    task axil_write_expect;
        input [9:0]  addr;
        input [31:0] data;
        input integer mode;
        input [1:0] expected_resp;
        integer aw_done;
        integer w_done;
        begin
            aw_done = 0;
            w_done  = 0;

            @(negedge clk);
            axil_awaddr = addr;
            axil_wdata  = data;
            axil_wstrb  = 4'hf;
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

            while (!axil_bvalid)
                @(negedge clk);

            if (axil_bresp !== expected_resp) begin
                $display("ERROR: AXI write addr=%03h response=%b expected=%b",
                         addr, axil_bresp, expected_resp);
                errors = errors + 1;
            end

            @(posedge clk);
            @(negedge clk);
        end
    endtask

    task axil_read_expect;
        input [9:0] addr;
        input [1:0] expected_resp;
        output [31:0] data;
        integer ar_done;
        begin
            ar_done = 0;
            @(negedge clk);
            axil_araddr  = addr;
            axil_arvalid = 1'b1;

            while (!ar_done) begin
                @(posedge clk);
                if (axil_arvalid && axil_arready)
                    ar_done = 1;
                @(negedge clk);
                if (ar_done)
                    axil_arvalid = 1'b0;
            end

            while (!axil_rvalid)
                @(negedge clk);

            data = axil_rdata;
            if (axil_rresp !== expected_resp) begin
                $display("ERROR: AXI read addr=%03h response=%b expected=%b",
                         addr, axil_rresp, expected_resp);
                errors = errors + 1;
            end

            @(posedge clk);
            @(negedge clk);
        end
    endtask

    task verify_loaded_banks;
        integer bank;
        integer p;
        integer ly;
        integer lx;
        integer gy;
        integer gx;
        integer flat_index;
        reg [7:0] expected_data;
        begin
            for (p = 0; p < GROUPS_PER_LOAD; p = p + 1) begin
                ly = p / PATCH_SIDE;
                lx = p % PATCH_SIDE;
                gy = current_tile_y * 16 + ly - 1;
                gx = current_tile_x * 16 + lx - 1;

                for (bank = 0; bank < BANKS; bank = bank + 1) begin
                    if ((gy < 0) || (gy >= IMAGE_H) ||
                        (gx < 0) || (gx >= IMAGE_W)) begin
                        expected_data = 8'd0;
                    end else begin
                        flat_index = ((gy * IMAGE_W + gx) * CHANNELS) +
                                     current_cin_block * BANKS + bank;
                        expected_data = raw_image[flat_index];
                    end

                    if (loaded_bank[bank][p] !== expected_data) begin
                        if (errors < 20)
                            $display("ERROR data: ty=%0d tx=%0d cout=%0d cin=%0d bank=%0d p=%0d got=%02h expected=%02h",
                                     current_tile_y, current_tile_x,
                                     current_cout_block, current_cin_block,
                                     bank, p, loaded_bank[bank][p],
                                     expected_data);
                        errors = errors + 1;
                    end
                end
            end
        end
    endtask

    task run_halo_load;
        input integer tile_y;
        input integer tile_x;
        input integer cout_block;
        input integer cin_block;
        input integer load_index;
        reg [31:0] config_word;
        begin
            current_tile_y      = tile_y;
            current_tile_x      = tile_x;
            current_cout_block  = cout_block;
            current_cin_block   = cin_block;
            current_group_count = 0;
            current_last_count  = 0;
            clear_loaded_banks();

            config_word = (cin_block << 2) | (tile_y << 1) | tile_x;
            axil_write_expect(10'h008, config_word,
                              load_index % 3, AXI_RESP_OKAY);
            axil_write_expect(10'h000, IMAGE_BASE,
                              (load_index + 1) % 3, AXI_RESP_OKAY);

            wait (O_top[2] === 1'b1);
            wait ((O_top[2] === 1'b0) && (O_top[1] === 1'b1));
            @(negedge clk);

            if (current_group_count != GROUPS_PER_LOAD) begin
                $display("ERROR: ty=%0d tx=%0d cout=%0d cin=%0d groups=%0d expected=%0d",
                         tile_y, tile_x, cout_block, cin_block,
                         current_group_count, GROUPS_PER_LOAD);
                errors = errors + 1;
            end

            if (current_last_count != 1) begin
                $display("ERROR: ty=%0d tx=%0d cout=%0d cin=%0d last_count=%0d",
                         tile_y, tile_x, cout_block, cin_block,
                         current_last_count);
                errors = errors + 1;
            end

            verify_loaded_banks();

            axil_read_expect(10'h004, AXI_RESP_OKAY, read_data);
            if (read_data[2:0] !== 3'b001) begin
                $display("ERROR: final status for load %0d is %08h",
                         load_index, read_data);
                errors = errors + 1;
            end
        end
    endtask

    // Backpressure verifies that a command and its eight-bank interpretation
    // remain stable until the downstream adapter accepts the group.
    always @(negedge clk) begin
        if (!rstn)
            map_ready <= 1'b0;
        else
            map_ready <= ((cycle_count % 7) != 0) &&
                         ((cycle_count % 11) != 0);
    end

    always @(posedge clk) begin
        if (!rstn) begin
            cycle_count         <= 0;
            accepted_groups      <= 0;
            accepted_zero_groups <= 0;
            held_map_valid       <= 1'b0;
        end else begin
            cycle_count <= cycle_count + 1;

            if (held_map_valid) begin
                if (!map_valid ||
                    (map_source_addr !== held_source) ||
                    (map_buffer_addr !== held_buffer) ||
                    (map_bank_mask !== held_mask) ||
                    (map_zero_fill !== held_zero) ||
                    (map_last !== held_last)) begin
                    $display("ERROR: map payload changed while stalled");
                    errors = errors + 1;
                end
            end

            held_map_valid <= map_valid && !map_ready;
            if (map_valid && !map_ready) begin
                held_source <= map_source_addr;
                held_buffer <= map_buffer_addr;
                held_mask   <= map_bank_mask;
                held_zero   <= map_zero_fill;
                held_last   <= map_last;
            end

            if (map_valid && map_ready) begin
                score_p  = current_group_count;
                score_ly = score_p / PATCH_SIDE;
                score_lx = score_p % PATCH_SIDE;
                score_gy = current_tile_y * 16 + score_ly - 1;
                score_gx = current_tile_x * 16 + score_lx - 1;
                score_zero = (score_gy < 0) || (score_gy >= IMAGE_H) ||
                             (score_gx < 0) || (score_gx >= IMAGE_W);

                if (score_zero) begin
                    score_source = 32'd0;
                    score_flat_base = 0;
                end else begin
                    score_flat_base =
                        ((score_gy * IMAGE_W + score_gx) * CHANNELS) +
                        current_cin_block * BANKS;
                    score_source = IMAGE_BASE + score_flat_base;
                end

                if ((score_p >= GROUPS_PER_LOAD) ||
                    (map_source_addr !== score_source) ||
                    (map_buffer_addr !== score_p[8:0]) ||
                    (map_bank_mask !== 8'hff) ||
                    (map_zero_fill !== score_zero) ||
                    (map_last !== (score_p == GROUPS_PER_LOAD - 1))) begin
                    $display("ERROR command: ty=%0d tx=%0d cout=%0d cin=%0d p=%0d src=%08h/%08h dst=%0d/%0d mask=%02h zero=%b/%b last=%b/%b",
                             current_tile_y, current_tile_x,
                             current_cout_block, current_cin_block, score_p,
                             map_source_addr, score_source,
                             map_buffer_addr, score_p, map_bank_mask,
                             map_zero_fill, score_zero, map_last,
                             (score_p == GROUPS_PER_LOAD - 1));
                    errors = errors + 1;
                end

                for (score_bank = 0; score_bank < BANKS;
                     score_bank = score_bank + 1) begin
                    if (score_zero)
                        loaded_bank[score_bank][score_p] <= 8'd0;
                    else
                        loaded_bank[score_bank][score_p] <=
                            raw_image[score_flat_base + score_bank];
                end

                accepted_groups <= accepted_groups + 1;
                current_group_count <= current_group_count + 1;
                if (score_zero)
                    accepted_zero_groups <= accepted_zero_groups + 1;
                if (map_last)
                    current_last_count <= current_last_count + 1;
            end
        end
    end

    initial begin
        integer tile_y;
        integer tile_x;
        integer cout_block;
        integer cin_block;
        integer load_index;

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
        errors       = 0;
        current_group_count = 0;
        current_last_count  = 0;

        if (!$value$plusargs("IMAGE_MEM=%s", image_mem_path))
            image_mem_path = `YOLO_IMAGE_MEM;
        $display("Loading activation data from %s", image_mem_path);
        $readmemh(image_mem_path, raw_image);

        repeat (5) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;

        // Confirm address decoding before running the trace comparison.
        axil_write_expect(10'h00c, 32'hdead_beef, 0, AXI_RESP_DECERR);
        axil_read_expect(10'h004, AXI_RESP_OKAY, read_data);
        if (read_data[2] !== 1'b1) begin
            $display("ERROR: decode error was not reflected in status");
            errors = errors + 1;
        end

        load_index = 0;
        for (tile_y = 0; tile_y < 2; tile_y = tile_y + 1) begin
            for (tile_x = 0; tile_x < 2; tile_x = tile_x + 1) begin
                for (cout_block = 0; cout_block < 2;
                     cout_block = cout_block + 1) begin
                    for (cin_block = 0; cin_block < 2;
                         cin_block = cin_block + 1) begin
                        run_halo_load(tile_y, tile_x, cout_block,
                                      cin_block, load_index);
                        load_index = load_index + 1;
                    end
                end
            end
        end

        axil_read_expect(10'h000, AXI_RESP_OKAY, read_data);
        if (read_data !== IMAGE_BASE) begin
            $display("ERROR: image base readback=%08h expected=%08h",
                     read_data, IMAGE_BASE);
            errors = errors + 1;
        end

        if (accepted_groups != TOTAL_GROUP_COMMANDS) begin
            $display("ERROR: accepted groups=%0d expected=%0d",
                     accepted_groups, TOTAL_GROUP_COMMANDS);
            errors = errors + 1;
        end

        if (accepted_zero_groups != TOTAL_ZERO_GROUPS) begin
            $display("ERROR: zero-fill groups=%0d expected=%0d",
                     accepted_zero_groups, TOTAL_ZERO_GROUPS);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: exact tb_npu halo-load pattern verified");
            $display("      16 loads x 324 groups = %0d group commands",
                     TOTAL_GROUP_COMMANDS);
            $display("      %0d expanded bank writes (%0d zero, %0d SRAM reads)",
                     TOTAL_BANK_WRITES, TOTAL_ZERO_GROUPS * BANKS,
                     TOTAL_BANK_WRITES - TOTAL_ZERO_GROUPS * BANKS);
        end else begin
            $display("FAIL: %0d errors", errors);
        end

        $finish;
    end

    initial begin
        repeat (100000) @(posedge clk);
        $display("FAIL: simulation timeout");
        $finish;
    end

endmodule

`default_nettype wire
