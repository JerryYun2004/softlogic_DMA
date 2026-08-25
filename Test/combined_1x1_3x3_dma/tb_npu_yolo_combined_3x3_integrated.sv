`timescale 1ns / 1ps
`default_nettype none

`ifndef YOLO_IMAGE_MEM
`define YOLO_IMAGE_MEM "yolo_image_3x3.mem"
`endif

`ifndef YOLO_WEIGHTS_MEM
`define YOLO_WEIGHTS_MEM "yolo_weights_3x3.mem"
`endif

`ifndef YOLO_GOLDEN_MEM
`define YOLO_GOLDEN_MEM "golden_conv3.mem"
`endif

// Combined YOLO 3x3 regression:
//   * The CPU selects 3x3 mode through the combined dma_a AXI4-Lite wrapper.
//   * combined_hwc_channel_dma_agu loads activations and 8x8 weight slices.
//   * The original convolution-pass and psum-drain schedules are preserved.
//   * All 32x32x16 results are compared with golden_conv3.mem.
//
// The map_* adapter below is deliberately a simulation memory model.  An
// activation group reads eight contiguous HWC bytes and writes eight activation
// banks.  A weight group reads eight bytes separated by the DMA-provided stride
// and applies one weight-shift cycle.  This verifies address/control integration
// with the NPU, but it is not the future physical SRAM datapath.
module tb_npu_yolo_combined_3x3_integrated;

    parameter int ARRAY_HEIGHT     = 8;
    parameter int ARRAY_WIDTH      = 8;
    parameter int TILE_SIZE        = 16;
    parameter int ACT_HALO_PAD     = 2;
    parameter int ACTIVATION_WIDTH = 8;
    parameter int WEIGHT_WIDTH     = 8;
    parameter int PSUM_WIDTH       = 32;

    localparam int PSUM_WORDS      = TILE_SIZE * TILE_SIZE;
    localparam int ACT_WORDS       = (TILE_SIZE * TILE_SIZE) * ACT_HALO_PAD;
    localparam int PSUM_ADDR_WIDTH = $clog2(PSUM_WORDS);
    localparam int ACT_ADDR_WIDTH  = $clog2(ACT_WORDS);
    localparam int NUM_ACT_BANKS   = ARRAY_HEIGHT;
    localparam int NUM_PSUM_BANKS  = ARRAY_WIDTH * 2;
    localparam int BANK_SEL_WIDTH  = $clog2(ARRAY_HEIGHT);

    localparam int IMAGE_HEIGHT       = 32;
    localparam int IMAGE_WIDTH        = 32;
    localparam int INPUT_CHANNELS     = 16;
    localparam int OUTPUT_CHANNELS    = 16;
    localparam int IMAGE_BYTES        = IMAGE_HEIGHT * IMAGE_WIDTH * INPUT_CHANNELS;
    localparam int WEIGHT_BYTES       = 3 * 3 * INPUT_CHANNELS * OUTPUT_CHANNELS;
    localparam int OUTPUT_WORDS       = IMAGE_HEIGHT * IMAGE_WIDTH * OUTPUT_CHANNELS;
    localparam int GROUPS_PER_LOAD    = 18 * 18;
    localparam int EXPECTED_DMA_LOADS = 2 * 2 * 2 * 2;
    localparam int EXPECTED_GROUPS    = EXPECTED_DMA_LOADS * GROUPS_PER_LOAD;
    localparam int EXPECTED_ZERO_GROUPS = EXPECTED_DMA_LOADS * (GROUPS_PER_LOAD - 17 * 17);
    localparam int EXPECTED_WEIGHT_LOADS = 2 * 2 * 2 * 2 * 3 * 3;
    localparam int EXPECTED_WEIGHT_GROUPS = EXPECTED_WEIGHT_LOADS * 8;
    localparam int EXPECTED_WEIGHT_BYTES  = EXPECTED_WEIGHT_GROUPS * 8;

    // A non-zero base checks that the adapter interprets DMA byte addresses,
    // rather than accidentally treating them as raw_image array indices.
    localparam logic [31:0] IMAGE_BASE = 32'h1000_0000;
    localparam logic [31:0] WEIGHT_BASE = 32'h2000_0000;
    localparam logic [1:0] AXI_RESP_OKAY = 2'b00;

    logic clk_i;
    logic rst_n;

    // ---------------------------------------------------------------------
    // NPU control and raw SRAM ports
    // ---------------------------------------------------------------------
    logic array_en;
    logic [ARRAY_HEIGHT-1:0][BANK_SEL_WIDTH-1:0] crossbar_sel;

    logic [ARRAY_WIDTH-1:0]                      psum_bank_swap;
    logic [ARRAY_WIDTH-1:0]                      psum_write_en;
    logic [ARRAY_WIDTH-1:0][PSUM_ADDR_WIDTH-1:0] psum_read_addr;
    logic [ARRAY_WIDTH-1:0][PSUM_ADDR_WIDTH-1:0] psum_write_addr;

    logic [ARRAY_HEIGHT-1:0][WEIGHT_WIDTH-1:0] weight_shift_in;
    logic                                       weight_shift_en;
    logic                                       swap_weights;

    logic [NUM_ACT_BANKS-1:0]                       ext_act_sram_we;
    logic [NUM_ACT_BANKS-1:0][ACT_ADDR_WIDTH-1:0]  ext_act_sram_addr;
    logic [NUM_ACT_BANKS-1:0][ACTIVATION_WIDTH-1:0] ext_act_sram_wdata;
    wire  [NUM_ACT_BANKS-1:0][ACTIVATION_WIDTH-1:0] act_sram_rdata;

    logic [NUM_ACT_BANKS-1:0][ACT_ADDR_WIDTH-1:0] act_compute_addr;

    logic [NUM_PSUM_BANKS-1:0]                       ext_psum_we;
    logic [NUM_PSUM_BANKS-1:0][PSUM_ADDR_WIDTH-1:0] ext_psum_addr;
    logic [NUM_PSUM_BANKS-1:0][PSUM_WIDTH-1:0]      ext_psum_wdata;
    wire  [NUM_PSUM_BANKS-1:0][PSUM_WIDTH-1:0]      ext_psum_rdata;

    // ---------------------------------------------------------------------
    // AXI4-Lite interface to the combined dma_a wrapper
    // ---------------------------------------------------------------------
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

    wire [31:0] dma_status;

    wire        map_valid;
    wire        map_ready;
    wire [31:0] map_source_addr;
    wire [4:0]  map_source_stride;
    wire [8:0]  map_buffer_addr;
    wire [7:0]  map_bank_mask;
    wire        map_is_weight;
    wire        map_zero_fill;
    wire        map_last;
    wire        map_weight_swap;

    logic dma_port_enable;
    integer dma_source_offset;
    integer dma_weight_source_offset;

    // ---------------------------------------------------------------------
    // Problem data and scoreboards
    // ---------------------------------------------------------------------
    logic [ACTIVATION_WIDTH-1:0] raw_image_3x3_flat   [0:IMAGE_BYTES-1];
    logic [WEIGHT_WIDTH-1:0]     raw_weights_3x3_flat [0:WEIGHT_BYTES-1];
    logic [PSUM_WIDTH-1:0]       golden_conv3_flat    [0:OUTPUT_WORDS-1];
    logic [PSUM_WIDTH-1:0]       actual_conv3         [0:31][0:31][0:15];

    longint total_cycles;
    longint dma_act_cycles;
    longint weight_load_cycles;
    longint compute_active_cycles;
    longint drain_cycles;

    integer errors;
    integer axi_write_count;
    integer dma_load_count;
    integer dma_total_groups;
    integer dma_total_zero_groups;
    integer dma_total_weight_groups;
    integer dma_total_weight_bytes;
    integer dma_total_weight_swaps;
    integer dma_groups_this_load;
    integer dma_last_this_load;
    integer dma_swap_this_load;
    integer weight_load_count;
    integer compute_pass_count;

    string image_mem_path;
    string weights_mem_path;
    string golden_mem_path;
    string vcd_path;

    // 10 MHz simulation clock, matching the original NPU regression.
    always #50 clk_i = ~clk_i;

    always @(posedge clk_i) begin
        if (!rst_n)
            total_cycles <= 0;
        else
            total_cycles <= total_cycles + 1;
    end

    // ---------------------------------------------------------------------
    // DUTs
    // ---------------------------------------------------------------------
    npu_sram_wrapper #(
        .ARRAY_HEIGHT     (ARRAY_HEIGHT),
        .ARRAY_WIDTH      (ARRAY_WIDTH),
        .TILE_SIZE        (TILE_SIZE),
        .ACT_HALO_PAD     (ACT_HALO_PAD),
        .ACTIVATION_WIDTH (ACTIVATION_WIDTH),
        .WEIGHT_WIDTH     (WEIGHT_WIDTH),
        .PSUM_WIDTH       (PSUM_WIDTH)
    ) npu_dut (
        .clk_i              (clk_i),
        .rst_n              (rst_n),
        .array_en           (array_en),
        .crossbar_sel       (crossbar_sel),
        .psum_bank_swap     (psum_bank_swap),
        .psum_write_en      (psum_write_en),
        .psum_read_addr     (psum_read_addr),
        .psum_write_addr    (psum_write_addr),
        .weight_shift_in    (weight_shift_in),
        .weight_shift_en    (weight_shift_en),
        .swap_weights       (swap_weights),
        .ext_act_sram_we    (ext_act_sram_we),
        .ext_act_sram_addr  (ext_act_sram_addr),
        .ext_act_sram_wdata (ext_act_sram_wdata),
        .act_sram_rdata     (act_sram_rdata),
        .ext_psum_we        (ext_psum_we),
        .ext_psum_addr      (ext_psum_addr),
        .ext_psum_wdata     (ext_psum_wdata),
        .ext_psum_rdata     (ext_psum_rdata)
    );

    dma_a dma_dut (
        .clk               (clk_i),
        .rstn              (rst_n),
        .O_top             (dma_status),
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

    // ---------------------------------------------------------------------
    // Simulation-only SRAM/weight-to-NPU adapter
    // ---------------------------------------------------------------------
    // The adapter owns the raw activation ports during an activation load and
    // the NPU weight-shift inputs during a weight load.  During compute, the
    // original per-row activation read-address schedule owns the SRAM addresses.
    assign map_ready = dma_port_enable;

    always_comb begin
        ext_act_sram_we    = '0;
        ext_act_sram_addr  = act_compute_addr;
        ext_act_sram_wdata = '0;
        weight_shift_in    = '0;
        weight_shift_en    = 1'b0;
        swap_weights       = dma_port_enable && map_weight_swap;
        dma_source_offset  = 0;
        dma_weight_source_offset = 0;

        if (dma_port_enable) begin
            if (map_valid && map_is_weight) begin
                weight_shift_en = 1'b1;
                for (int r = 0; r < ARRAY_HEIGHT; r++) begin
                    if (map_bank_mask[r] &&
                        (map_source_addr >= WEIGHT_BASE) &&
                        (map_source_addr + 7*map_source_stride <
                         WEIGHT_BASE + WEIGHT_BYTES)) begin
                        dma_weight_source_offset =
                            (map_source_addr - WEIGHT_BASE) +
                            r*map_source_stride;
                        weight_shift_in[r] =
                            raw_weights_3x3_flat[dma_weight_source_offset];
                    end else begin
                        weight_shift_in[r] = 'x;
                    end
                end
            end else begin
                for (int r = 0; r < NUM_ACT_BANKS; r++) begin
                    ext_act_sram_addr[r] = map_buffer_addr;

                    if (map_valid && map_bank_mask[r]) begin
                        ext_act_sram_we[r] = 1'b1;

                        if (map_zero_fill) begin
                            ext_act_sram_wdata[r] = '0;
                        end else if ((map_source_addr >= IMAGE_BASE) &&
                                     (map_source_addr + 7*map_source_stride <
                                      IMAGE_BASE + IMAGE_BYTES)) begin
                            dma_source_offset =
                                (map_source_addr - IMAGE_BASE) +
                                r*map_source_stride;
                            ext_act_sram_wdata[r] =
                                raw_image_3x3_flat[dma_source_offset];
                        end else begin
                            ext_act_sram_wdata[r] = 'x;
                        end
                    end
                end
            end
        end
    end

    // Monitor every command actually accepted by the SRAM adapter.
    always @(posedge clk_i) begin
        if (!rst_n) begin
            dma_total_groups      <= 0;
            dma_total_zero_groups <= 0;
            dma_total_weight_groups <= 0;
            dma_total_weight_bytes  <= 0;
            dma_total_weight_swaps  <= 0;
            dma_groups_this_load  <= 0;
            dma_last_this_load    <= 0;
            dma_swap_this_load    <= 0;
        end else begin
            if (map_valid && map_ready) begin
                dma_groups_this_load <= dma_groups_this_load + 1;

                if (map_last)
                    dma_last_this_load <= dma_last_this_load + 1;

                if (map_buffer_addr !== dma_groups_this_load[8:0]) begin
                    $display("ERROR: DMA destination/shift sequence got=%0d expected=%0d",
                             map_buffer_addr, dma_groups_this_load);
                    errors = errors + 1;
                end

                if (map_bank_mask !== 8'hff) begin
                    $display("ERROR: DMA bank/lane mask got=%02h expected=ff",
                             map_bank_mask);
                    errors = errors + 1;
                end

                if (map_is_weight) begin
                    dma_total_weight_groups <= dma_total_weight_groups + 1;
                    dma_total_weight_bytes  <= dma_total_weight_bytes + 8;

                    if (map_source_stride !== 5'd16) begin
                        $display("ERROR: DMA weight stride got=%0d expected=16",
                                 map_source_stride);
                        errors = errors + 1;
                    end
                    if (map_zero_fill) begin
                        $display("ERROR: DMA weight command requested zero fill");
                        errors = errors + 1;
                    end
                    if (!((map_source_addr >= WEIGHT_BASE) &&
                          (map_source_addr + 7*map_source_stride <
                           WEIGHT_BASE + WEIGHT_BYTES))) begin
                        $display("ERROR: DMA source address out of weight range: %08h",
                                 map_source_addr);
                        errors = errors + 1;
                    end
                end else begin
                    dma_total_groups <= dma_total_groups + 1;

                    if (map_source_stride !== 5'd1) begin
                        $display("ERROR: DMA activation stride got=%0d expected=1",
                                 map_source_stride);
                        errors = errors + 1;
                    end
                    if (map_zero_fill)
                        dma_total_zero_groups <= dma_total_zero_groups + 1;
                    if (!map_zero_fill &&
                        !((map_source_addr >= IMAGE_BASE) &&
                          (map_source_addr + 7*map_source_stride <
                           IMAGE_BASE + IMAGE_BYTES))) begin
                        $display("ERROR: DMA source address out of image range: %08h",
                                 map_source_addr);
                        errors = errors + 1;
                    end
                end
            end

            if (map_weight_swap) begin
                dma_total_weight_swaps <= dma_total_weight_swaps + 1;
                dma_swap_this_load     <= dma_swap_this_load + 1;

                if (map_valid || !map_is_weight) begin
                    $display("ERROR: DMA weight swap overlaps an invalid command state");
                    errors = errors + 1;
                end
            end
        end
    end

    // AW and W are tracked independently so this driver also checks the
    // wrapper's decoupled AXI4-Lite write channels.
    task automatic axil_write(input logic [9:0]  addr,
                              input logic [31:0] data,
                              input logic [3:0]  strb,
                              input logic [1:0]  expected_resp);
        bit aw_done;
        bit w_done;
        begin
            aw_done = 1'b0;
            w_done  = 1'b0;

            @(negedge clk_i);
            axil_awaddr  = addr;
            axil_awvalid = 1'b1;
            axil_wdata   = data;
            axil_wstrb   = strb;
            axil_wvalid  = 1'b1;

            while (!(aw_done && w_done)) begin
                @(posedge clk_i);
                if (!aw_done && axil_awvalid && axil_awready)
                    aw_done = 1'b1;
                if (!w_done && axil_wvalid && axil_wready)
                    w_done = 1'b1;

                @(negedge clk_i);
                if (aw_done)
                    axil_awvalid = 1'b0;
                if (w_done)
                    axil_wvalid = 1'b0;
            end

            while (axil_bvalid !== 1'b1)
                @(negedge clk_i);

            if (axil_bresp !== expected_resp) begin
                $display("ERROR: AXI write addr=%03h data=%08h BRESP=%0b expected=%0b",
                         addr, data, axil_bresp, expected_resp);
                errors = errors + 1;
            end
            axi_write_count = axi_write_count + 1;

            @(posedge clk_i);
            #1;
        end
    endtask

    // One call is the integrated replacement for the original procedural
    // dma_load_yolo_halo_patch task.
    task automatic dma_load_yolo_halo_patch(input int tile_y,
                                             input int tile_x,
                                             input int cin_block);
        logic [31:0] config_word;
        longint start_cycle;
        begin
            start_cycle = total_cycles;
            config_word = 32'd0;
            config_word[0] = tile_x[0];
            config_word[1] = tile_y[0];
            config_word[2] = cin_block[0];
            config_word[3] = 1'b0;
            config_word[9] = 1'b0; // CPU selects the 3x3 schedule.

            dma_groups_this_load = 0;
            dma_last_this_load   = 0;
            dma_swap_this_load   = 0;
            dma_port_enable      = 1'b1;

            axil_write(10'h008, config_word, 4'hf, AXI_RESP_OKAY);
            axil_write(10'h000, IMAGE_BASE, 4'hf, AXI_RESP_OKAY);

            wait (dma_status[2] === 1'b1);
            wait (dma_status[1] === 1'b1);
            @(negedge clk_i);

            dma_port_enable = 1'b0;
            dma_load_count  = dma_load_count + 1;
            dma_act_cycles  = dma_act_cycles + (total_cycles - start_cycle);

            if (dma_groups_this_load != GROUPS_PER_LOAD) begin
                $display("ERROR: DMA load ty=%0d tx=%0d cin=%0d emitted %0d groups, expected %0d",
                         tile_y, tile_x, cin_block,
                         dma_groups_this_load, GROUPS_PER_LOAD);
                errors = errors + 1;
            end

            if (dma_last_this_load != 1) begin
                $display("ERROR: DMA load ty=%0d tx=%0d cin=%0d emitted map_last %0d times",
                         tile_y, tile_x, cin_block, dma_last_this_load);
                errors = errors + 1;
            end
            if (dma_swap_this_load != 0) begin
                $display("ERROR: activation DMA load emitted %0d weight swaps",
                         dma_swap_this_load);
                errors = errors + 1;
            end
            if (dma_status[3]) begin
                $display("ERROR: combined DMA wrapper reported an activation error");
                errors = errors + 1;
            end
        end
    endtask

    // ---------------------------------------------------------------------
    // DMA weight loading plus original NPU compute and drain scheduling
    // ---------------------------------------------------------------------
    task automatic dma_init_bias_zero;
        begin
            @(negedge clk_i);
            ext_psum_we = 16'h00ff;
            for (int b = 0; b < ARRAY_WIDTH; b++) begin
                ext_psum_addr[b]  = '0;
                ext_psum_wdata[b] = 32'd0;
            end
            @(negedge clk_i);
            ext_psum_we = '0;
        end
    endtask

    task automatic dma_load_weights_slice(input int kernel_y,
                                          input int kernel_x,
                                          input int cin_block,
                                          input int cout_block);
        logic [31:0] config_word;
        longint start_cycle;
        begin
            start_cycle = total_cycles;
            config_word = 32'd0;
            config_word[2]   = cin_block[0];
            config_word[3]   = 1'b1;
            config_word[4]   = cout_block[0];
            config_word[6:5] = kernel_y[1:0];
            config_word[8:7] = kernel_x[1:0];
            config_word[9]   = 1'b0; // CPU selects the 3x3 schedule.

            dma_groups_this_load = 0;
            dma_last_this_load   = 0;
            dma_swap_this_load   = 0;
            dma_port_enable      = 1'b1;

            axil_write(10'h008, config_word, 4'hf, AXI_RESP_OKAY);
            axil_write(10'h000, WEIGHT_BASE, 4'hf, AXI_RESP_OKAY);

            wait (dma_status[2] === 1'b1);
            wait (dma_status[1] === 1'b1);
            @(negedge clk_i);
            dma_port_enable = 1'b0;

            weight_load_count  = weight_load_count + 1;
            weight_load_cycles = weight_load_cycles +
                                 (total_cycles - start_cycle);

            if (dma_groups_this_load != 8) begin
                $display("ERROR: weight DMA ky=%0d kx=%0d cin=%0d cout=%0d emitted %0d groups, expected 8",
                         kernel_y, kernel_x, cin_block, cout_block,
                         dma_groups_this_load);
                errors = errors + 1;
            end
            if (dma_last_this_load != 1) begin
                $display("ERROR: weight DMA ky=%0d kx=%0d cin=%0d cout=%0d emitted map_last %0d times",
                         kernel_y, kernel_x, cin_block, cout_block,
                         dma_last_this_load);
                errors = errors + 1;
            end
            if (dma_swap_this_load != 1) begin
                $display("ERROR: weight DMA ky=%0d kx=%0d cin=%0d cout=%0d emitted swap %0d times",
                         kernel_y, kernel_x, cin_block, cout_block,
                         dma_swap_this_load);
                errors = errors + 1;
            end
            if (dma_status[3]) begin
                $display("ERROR: combined DMA wrapper reported a weight error");
                errors = errors + 1;
            end
        end
    endtask

    task automatic run_conv3x3_pass(input int ky,
                                     input int kx,
                                     input logic [7:0] swap_mode,
                                     input logic hold_zero);
        int total_pass_cycles;
        longint start_cycle;
        begin
            start_cycle = total_cycles;
            total_pass_cycles = 256 + ARRAY_HEIGHT + ARRAY_WIDTH;

            @(negedge clk_i);
            array_en = 1'b1;

            for (int k = 0; k < total_pass_cycles; k++) begin
                @(negedge clk_i);

                for (int r = 0; r < ARRAY_HEIGHT; r++) begin
                    if ((k >= r) && ((k-r) < 256)) begin
                        int m;
                        int y;
                        int x;
                        m = k-r;
                        y = m/16;
                        x = m%16;
                        act_compute_addr[r] =
                            (ACT_ADDR_WIDTH)'((y+ky)*18 + (x+kx));
                    end else begin
                        act_compute_addr[r] = '0;
                    end
                end

                for (int c = 0; c < ARRAY_WIDTH; c++) begin
                    psum_bank_swap[c] = swap_mode[c];

                    if (hold_zero) begin
                        psum_read_addr[c] = '0;
                    end else if ((k >= c) && ((k-c) < 256)) begin
                        psum_read_addr[c] = (PSUM_ADDR_WIDTH)'(k-c);
                    end else begin
                        psum_read_addr[c] = '0;
                    end

                    if ((k >= (9+c)) && ((k-(9+c)) < 256)) begin
                        psum_write_addr[c] = (PSUM_ADDR_WIDTH)'(k-9-c);
                        psum_write_en[c]   = 1'b1;
                    end else begin
                        psum_write_addr[c] = '0;
                        psum_write_en[c]   = 1'b0;
                    end
                end
            end

            @(negedge clk_i);
            array_en      = 1'b0;
            psum_write_en = '0;

            compute_pass_count    = compute_pass_count + 1;
            compute_active_cycles = compute_active_cycles +
                                    (total_cycles - start_cycle);
        end
    endtask

    task automatic drain_conv3x3(input int tile_y,
                                  input int tile_x,
                                  input int cout_block,
                                  input int bank_base);
        int y_base;
        int x_base;
        longint start_cycle;
        begin
            start_cycle = total_cycles;
            y_base = tile_y*16;
            x_base = tile_x*16;

            for (int m = 0; m < 256; m++) begin
                int y;
                int x;
                y = m/16;
                x = m%16;

                @(negedge clk_i);
                for (int c = 0; c < 8; c++)
                    ext_psum_addr[bank_base+c] = (PSUM_ADDR_WIDTH)'(m);

                @(posedge clk_i);
                #1;
                for (int c = 0; c < 8; c++) begin
                    actual_conv3[y_base+y][x_base+x][cout_block*8+c] =
                        ext_psum_rdata[bank_base+c];
                end
            end

            drain_cycles = drain_cycles + (total_cycles - start_cycle);
        end
    endtask

    // ---------------------------------------------------------------------
    // Combined YOLO regression
    // ---------------------------------------------------------------------
    initial begin : main_test
        clk_i          = 1'b0;
        rst_n          = 1'b0;
        array_en       = 1'b0;
        crossbar_sel   = '0;
        psum_bank_swap = '0;
        psum_write_en  = '0;
        psum_read_addr = '0;
        psum_write_addr = '0;
        act_compute_addr = '0;
        ext_psum_we      = '0;
        ext_psum_addr    = '0;
        ext_psum_wdata   = '0;

        axil_awaddr      = '0;
        axil_awvalid     = 1'b0;
        axil_wdata       = '0;
        axil_wstrb       = '0;
        axil_wvalid      = 1'b0;
        axil_bready      = 1'b1;
        axil_araddr      = '0;
        axil_arvalid     = 1'b0;
        axil_rready      = 1'b1;

        dma_port_enable       = 1'b0;
        total_cycles          = 0;
        dma_act_cycles        = 0;
        weight_load_cycles    = 0;
        compute_active_cycles = 0;
        drain_cycles          = 0;
        errors                = 0;
        axi_write_count       = 0;
        dma_load_count        = 0;
        dma_total_groups      = 0;
        dma_total_zero_groups = 0;
        dma_total_weight_groups = 0;
        dma_total_weight_bytes  = 0;
        dma_total_weight_swaps  = 0;
        dma_groups_this_load  = 0;
        dma_last_this_load    = 0;
        dma_swap_this_load    = 0;
        weight_load_count     = 0;
        compute_pass_count    = 0;

        if (!$value$plusargs("IMAGE_MEM=%s", image_mem_path))
            image_mem_path = `YOLO_IMAGE_MEM;
        if (!$value$plusargs("WEIGHTS_MEM=%s", weights_mem_path))
            weights_mem_path = `YOLO_WEIGHTS_MEM;
        if (!$value$plusargs("GOLDEN_MEM=%s", golden_mem_path))
            golden_mem_path = `YOLO_GOLDEN_MEM;

        $display("Loading image   : %s", image_mem_path);
        $display("Loading weights : %s", weights_mem_path);
        $display("Loading golden  : %s", golden_mem_path);
        $readmemh(image_mem_path,   raw_image_3x3_flat);
        $readmemh(weights_mem_path, raw_weights_3x3_flat);
        $readmemh(golden_mem_path,  golden_conv3_flat);

        repeat (5) @(posedge clk_i);
        @(negedge clk_i);
        rst_n = 1'b1;

        // The YOLO mapping uses a static identity bank-to-PE-row selection.
        for (int r = 0; r < ARRAY_HEIGHT; r++)
            crossbar_sel[r] = r[BANK_SEL_WIDTH-1:0];

        $display("===================================================================");
        $display(" YOLO 3x3 COMBINED TEST: RTL DMA ACTIVATIONS + RTL DMA WEIGHTS");
        $display("===================================================================");

        for (int ty = 0; ty < 2; ty++) begin
            for (int tx = 0; tx < 2; tx++) begin
                $display("[%0t] tile ty=%0d tx=%0d", $time, ty, tx);

                for (int cout_block = 0; cout_block < 2; cout_block++) begin
                    int pass_idx;
                    pass_idx = 0;
                    dma_init_bias_zero();

                    for (int cin_block = 0; cin_block < 2; cin_block++) begin
                        // Activations now come from the real RTL DMA.
                        dma_load_yolo_halo_patch(ty, tx, cin_block);

                        for (int ky = 0; ky < 3; ky++) begin
                            for (int kx = 0; kx < 3; kx++) begin
                                logic [7:0] swap_mode;
                                logic hold_zero;

                                swap_mode = (pass_idx == 0) ? 8'h00 :
                                            ((pass_idx % 2) ? 8'hff : 8'h00);
                                hold_zero = (pass_idx == 0);

                                // The updated DMA emits the same c=7..0 shift
                                // order formerly generated by the testbench.
                                dma_load_weights_slice(ky, kx,
                                                       cin_block, cout_block);
                                run_conv3x3_pass(ky, kx, swap_mode, hold_zero);
                                pass_idx = pass_idx + 1;
                            end
                        end
                    end

                    drain_conv3x3(ty, tx, cout_block, 0);
                end
            end
        end

        for (int y = 0; y < IMAGE_HEIGHT; y++) begin
            for (int x = 0; x < IMAGE_WIDTH; x++) begin
                for (int co = 0; co < OUTPUT_CHANNELS; co++) begin
                    int flat_index;
                    flat_index = (y*IMAGE_WIDTH*OUTPUT_CHANNELS) +
                                 (x*OUTPUT_CHANNELS) + co;
                    if (actual_conv3[y][x][co] !==
                        golden_conv3_flat[flat_index]) begin
                        if (errors < 20) begin
                            $display("ERROR output y=%0d x=%0d co=%0d got=%08h expected=%08h",
                                     y, x, co, actual_conv3[y][x][co],
                                     golden_conv3_flat[flat_index]);
                        end
                        errors = errors + 1;
                    end
                end
            end
        end

        if (dma_load_count != EXPECTED_DMA_LOADS) begin
            $display("ERROR: DMA loads=%0d expected=%0d",
                     dma_load_count, EXPECTED_DMA_LOADS);
            errors = errors + 1;
        end
        if (dma_total_groups != EXPECTED_GROUPS) begin
            $display("ERROR: DMA groups=%0d expected=%0d",
                     dma_total_groups, EXPECTED_GROUPS);
            errors = errors + 1;
        end
        if (dma_total_zero_groups != EXPECTED_ZERO_GROUPS) begin
            $display("ERROR: DMA zero groups=%0d expected=%0d",
                     dma_total_zero_groups, EXPECTED_ZERO_GROUPS);
            errors = errors + 1;
        end
        if (weight_load_count != EXPECTED_WEIGHT_LOADS) begin
            $display("ERROR: DMA weight loads=%0d expected=%0d",
                     weight_load_count, EXPECTED_WEIGHT_LOADS);
            errors = errors + 1;
        end
        if (dma_total_weight_groups != EXPECTED_WEIGHT_GROUPS) begin
            $display("ERROR: DMA weight groups=%0d expected=%0d",
                     dma_total_weight_groups, EXPECTED_WEIGHT_GROUPS);
            errors = errors + 1;
        end
        if (dma_total_weight_bytes != EXPECTED_WEIGHT_BYTES) begin
            $display("ERROR: DMA weight bytes=%0d expected=%0d",
                     dma_total_weight_bytes, EXPECTED_WEIGHT_BYTES);
            errors = errors + 1;
        end
        if (dma_total_weight_swaps != EXPECTED_WEIGHT_LOADS) begin
            $display("ERROR: DMA weight swaps=%0d expected=%0d",
                     dma_total_weight_swaps, EXPECTED_WEIGHT_LOADS);
            errors = errors + 1;
        end
        if (compute_pass_count != EXPECTED_WEIGHT_LOADS) begin
            $display("ERROR: compute passes=%0d expected=%0d",
                     compute_pass_count, EXPECTED_WEIGHT_LOADS);
            errors = errors + 1;
        end

        $display("-------------------------------------------------------------------");
        $display("DMA activation loads       : %0d", dma_load_count);
        $display("DMA activation groups      : %0d", dma_total_groups);
        $display("DMA expanded bank writes   : %0d", dma_total_groups*8);
        $display("DMA weight-slice loads     : %0d", weight_load_count);
        $display("DMA weight groups          : %0d", dma_total_weight_groups);
        $display("DMA weight bytes           : %0d", dma_total_weight_bytes);
        $display("DMA weight swaps           : %0d", dma_total_weight_swaps);
        $display("NPU convolution passes     : %0d", compute_pass_count);
        $display("Total simulation cycles    : %0d", total_cycles);
        $display("-------------------------------------------------------------------");

        if (errors == 0) begin
            $display("PASS: RTL DMA-loaded activations and weights produced all 16,384 golden YOLO 3x3 outputs");
            $finish;
        end else begin
            $fatal(1, "FAIL: combined DMA/NPU regression found %0d errors", errors);
        end
    end

    initial begin : optional_waveform
        if ($value$plusargs("VCD=%s", vcd_path)) begin
            $dumpfile(vcd_path);
            $dumpvars(0, tb_npu_yolo_combined_3x3_integrated);
        end
    end

    initial begin : timeout_watchdog
        repeat (200000) @(posedge clk_i);
        $fatal(1, "FAIL: combined DMA/NPU simulation timeout");
    end

endmodule

`default_nettype wire
