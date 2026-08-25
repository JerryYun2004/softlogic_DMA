`timescale 1ns / 1ps

module tb_npu_yolo_regression;

    // -------------------------------------------------------------------------
    // Architecture Parameters
    // -------------------------------------------------------------------------
    parameter int ARRAY_HEIGHT     = 8;
    parameter int ARRAY_WIDTH      = 8;
    parameter int TILE_SIZE        = 16;                                     // 256 words
    parameter int ACT_HALO_PAD     = 2;                                      // 512 words
    parameter int ACTIVATION_WIDTH = 8;
    parameter int WEIGHT_WIDTH     = 8;
    parameter int PSUM_WIDTH       = 32;

    localparam int PSUM_WORDS      = TILE_SIZE * TILE_SIZE;                  // 256
    localparam int ACT_WORDS       = (TILE_SIZE * TILE_SIZE) * ACT_HALO_PAD; // 512
    localparam int PSUM_ADDR_WIDTH = $clog2(PSUM_WORDS);                     // 8 bits
    localparam int ACT_ADDR_WIDTH  = $clog2(ACT_WORDS);                      // 9 bits
    localparam int NUM_ACT_BANKS   = ARRAY_HEIGHT;                           // 8
    localparam int NUM_PSUM_BANKS  = ARRAY_WIDTH * 2;                        // 16
    localparam int BANK_SEL_WIDTH  = $clog2(ARRAY_HEIGHT);                   // 3

    // -------------------------------------------------------------------------
    // DUT Interface Signals
    // -------------------------------------------------------------------------
    logic clk_i;
    logic rst_n;
    logic array_en;
    logic [ARRAY_HEIGHT-1:0][BANK_SEL_WIDTH-1:0] crossbar_sel;

    logic [ARRAY_WIDTH-1:0]                      psum_bank_swap;
    logic [ARRAY_WIDTH-1:0]                      psum_write_en;
    logic [ARRAY_WIDTH-1:0][PSUM_ADDR_WIDTH-1:0] psum_read_addr;
    logic [ARRAY_WIDTH-1:0][PSUM_ADDR_WIDTH-1:0] psum_write_addr;

    logic [ARRAY_HEIGHT-1:0][WEIGHT_WIDTH-1:0]   weight_shift_in;
    logic                                        weight_shift_en;
    logic                                        swap_weights;

    logic [NUM_ACT_BANKS-1:0]                    ext_act_sram_we;
    logic [NUM_ACT_BANKS-1:0][ACT_ADDR_WIDTH-1:0] ext_act_sram_addr;
    logic [NUM_ACT_BANKS-1:0][ACTIVATION_WIDTH-1:0] ext_act_sram_wdata;
    wire  [NUM_ACT_BANKS-1:0][ACTIVATION_WIDTH-1:0] act_sram_rdata;

    logic [NUM_PSUM_BANKS-1:0]                   ext_psum_we;
    logic [NUM_PSUM_BANKS-1:0][PSUM_ADDR_WIDTH-1:0] ext_psum_addr;
    logic [NUM_PSUM_BANKS-1:0][PSUM_WIDTH-1:0]   ext_psum_wdata;
    wire  [NUM_PSUM_BANKS-1:0][PSUM_WIDTH-1:0]   ext_psum_rdata;

    // -------------------------------------------------------------------------
    // Raw Problem Storage from Disk (.mem files)
    // -------------------------------------------------------------------------
    // Suite 1: GEMM (1024x32 @ 32x32 -> 1024x32)
    logic [ACTIVATION_WIDTH-1:0] raw_gemm_A_flat    [1024 * 32];
    logic [WEIGHT_WIDTH-1:0]     raw_gemm_B_flat    [32 * 32];
    logic [PSUM_WIDTH-1:0]       golden_gemm_flat   [1024 * 32];
    logic [PSUM_WIDTH-1:0]       actual_gemm        [1024][32];

    // Suite 2: YOLO 1x1 Conv (32x32x16 -> 32x32x16)
    logic [ACTIVATION_WIDTH-1:0] raw_conv1_in_flat  [32 * 32 * 16];
    logic [WEIGHT_WIDTH-1:0]     raw_conv1_w_flat   [16 * 16];
    logic [PSUM_WIDTH-1:0]       golden_conv1_flat  [32 * 32 * 16];
    logic [PSUM_WIDTH-1:0]       actual_conv1       [32][32][16];

    // Suite 3: YOLO 3x3 Conv (32x32x16 -> 32x32x16 with SAME Padding)
    logic [ACTIVATION_WIDTH-1:0] raw_image_3x3_flat   [32 * 32 * 16];
    logic [WEIGHT_WIDTH-1:0]     raw_weights_3x3_flat [3 * 3 * 16 * 16];
    logic [PSUM_WIDTH-1:0]       golden_conv3_flat    [32 * 32 * 16];
    logic [PSUM_WIDTH-1:0]       actual_conv3         [32][32][16];

    // -------------------------------------------------------------------------
    // Performance & Cycle Profiling Counters
    // -------------------------------------------------------------------------
    longint total_cycles          = 0;
    longint dma_act_cycles        = 0;
    longint weight_load_cycles    = 0;
    longint compute_active_cycles = 0;
    longint drain_cycles          = 0;
    longint init_cycles           = 0;

    int gemm_errors    = 0;
    int conv1x1_errors = 0;
    int conv3x3_errors = 0;

    // Clock Generator (10 MHz) & Monotonic Cycle Tracker
    always #50 begin
        clk_i = ~clk_i;
        if (clk_i) total_cycles++;
    end

    // DUT Instantiation
    npu_sram_wrapper #(
        .ARRAY_HEIGHT     (ARRAY_HEIGHT),
        .ARRAY_WIDTH      (ARRAY_WIDTH),
        .TILE_SIZE        (TILE_SIZE),
        .ACT_HALO_PAD     (ACT_HALO_PAD),
        .ACTIVATION_WIDTH (ACTIVATION_WIDTH),
        .WEIGHT_WIDTH     (WEIGHT_WIDTH),
        .PSUM_WIDTH       (PSUM_WIDTH)
    ) dut (
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

    // =========================================================================
    // PROFILED HARDWARE CONTROLLER TASKS
    // =========================================================================

    // Task: Reset Set 0 Bias
    task automatic dma_init_bias_zero();
        longint start_c = total_cycles;
        @(negedge clk_i);
        ext_psum_we = 16'h00FF; // Set 0 Banks 0..7
        for (int b = 0; b < ARRAY_WIDTH; b++) begin
            ext_psum_addr[b]  = '0;
            ext_psum_wdata[b] = 32'd0;
        end
        @(negedge clk_i);
        ext_psum_we = '0;
        init_cycles += (total_cycles - start_c);
    endtask

    // Task: Shift an 8x8 weight slice (measures 8 cycles)
    task automatic dma_load_weights_slice(input logic [WEIGHT_WIDTH-1:0] w[8][8]);
        longint start_c = total_cycles;
        @(negedge clk_i);
        weight_shift_en = 1;
        for (int s = 0; s < 8; s++) begin
            for (int r = 0; r < 8; r++) begin
                weight_shift_in[r] = w[r][7 - s];
            end
            @(negedge clk_i);
        end
        weight_shift_en = 0;
        @(negedge clk_i); swap_weights = 1; 
        @(negedge clk_i); swap_weights = 0;
        weight_load_cycles += (total_cycles - start_c);
    endtask

    // Task: DMA GEMM Activation Loader
    task automatic dma_load_gemm_activations(input int m_t, input int k_t);
        longint start_c = total_cycles;
        for (int m = 0; m < 256; m++) begin
            @(negedge clk_i);
            ext_act_sram_we = 8'hFF;
            for (int r = 0; r < 8; r++) begin
                int flat_a = (m_t * 256 + m) * 32 + (k_t * 8 + r);
                ext_act_sram_addr[r]  = (ACT_ADDR_WIDTH)'(m);
                ext_act_sram_wdata[r] = raw_gemm_A_flat[flat_a];
            end
        end
        @(negedge clk_i);
        ext_act_sram_we = '0;
        dma_act_cycles += (total_cycles - start_c);
    endtask

    // Task: DMA 1x1 Conv Activation Loader
    task automatic dma_load_1x1_activations(input int ty, input int tx, input int cin_blk);
        longint start_c = total_cycles;
        for (int m = 0; m < 256; m++) begin
            int py = ty * 16 + (m / 16);
            int px = tx * 16 + (m % 16);
            @(negedge clk_i);
            ext_act_sram_we = 8'hFF;
            for (int r = 0; r < 8; r++) begin
                int flat_in = (py * 32 * 16) + (px * 16) + (cin_blk * 8 + r);
                ext_act_sram_addr[r]  = (ACT_ADDR_WIDTH)'(m);
                ext_act_sram_wdata[r] = raw_conv1_in_flat[flat_in];
            end
        end
        @(negedge clk_i);
        ext_act_sram_we = '0;
        dma_act_cycles += (total_cycles - start_c);
    endtask

    // Task: DMA 3x3 Halo & Padding Extractor (Fetches 18x18 patch with boundary pad=0)
    task automatic dma_load_yolo_halo_patch(input int tile_y, input int tile_x, input int cin_blk);
        longint start_c = total_cycles;
        int y_base = tile_y * 16;
        int x_base = tile_x * 16;

        for (int ly = 0; ly < 18; ly++) begin
            for (int lx = 0; lx < 18; lx++) begin
                int sram_addr = ly * 18 + lx;
                int gy = y_base + ly - 1; // Global image coordinate (-1 to 32)
                int gx = x_base + lx - 1;

                @(negedge clk_i);
                ext_act_sram_we = 8'hFF;

                for (int r = 0; r < 8; r++) begin
                    int ch_idx = cin_blk * 8 + r;
                    ext_act_sram_addr[r] = (ACT_ADDR_WIDTH)'(sram_addr);

                    // Zero-Padding Check (Out of image bounds = 0)
                    if (gy < 0 || gy >= 32 || gx < 0 || gx >= 32) begin
                        ext_act_sram_wdata[r] = 8'd0;
                    end else begin
                        int flat_idx = (gy * 32 * 16) + (gx * 16) + ch_idx;
                        ext_act_sram_wdata[r] = raw_image_3x3_flat[flat_idx];
                    end
                end
            end
        end
        @(negedge clk_i);
        ext_act_sram_we = '0;
        dma_act_cycles += (total_cycles - start_c);
    endtask

    // Task: Linear 1D Execution Pass (256 vectors + 16 pipeline cycles = 272 cycles)
    task automatic agu_run_linear_pass(input logic [7:0] swap_mode, input logic hold_zero);
        longint start_c = total_cycles;
        int total_pass_cycles = 256 + ARRAY_HEIGHT + ARRAY_WIDTH; // 272

        @(negedge clk_i);
        array_en = 1;

        for (int k = 0; k < total_pass_cycles; k++) begin
            @(negedge clk_i);

            for (int r = 0; r < ARRAY_HEIGHT; r++) begin
                if ((k >= r) && ((k - r) < 256)) ext_act_sram_addr[r] = (ACT_ADDR_WIDTH)'(k - r);
                else                             ext_act_sram_addr[r] = '0;
            end

            for (int c = 0; c < ARRAY_WIDTH; c++) begin
                psum_bank_swap[c] = swap_mode[c];

                if (hold_zero) begin
                    psum_read_addr[c] = '0;
                end else begin
                    if ((k >= c) && ((k - c) < 256)) psum_read_addr[c] = (PSUM_ADDR_WIDTH)'(k - c);
                    else                             psum_read_addr[c] = '0;
                end

                if ((k >= (9 + c)) && ((k - (9 + c)) < 256)) begin
                    psum_write_addr[c] = (PSUM_ADDR_WIDTH)'(k - 9 - c);
                    psum_write_en[c]   = 1'b1;
                end else begin
                    psum_write_addr[c] = '0;
                    psum_write_en[c]   = 1'b0;
                end
            end
        end

        @(negedge clk_i);
        array_en      = 0;
        psum_write_en = '0;
        compute_active_cycles += (total_cycles - start_c);
    endtask

    // Task: 2D Spatial Conv Pass (256 vectors = 272 cycles)
    task automatic agu_run_conv3x3_pass(input int ky, input int kx, input logic [7:0] swap_mode, input logic hold_zero);
        longint start_c = total_cycles;
        int total_pass_cycles = 256 + ARRAY_HEIGHT + ARRAY_WIDTH; // 272

        @(negedge clk_i);
        array_en = 1;

        for (int k = 0; k < total_pass_cycles; k++) begin
            @(negedge clk_i);

            for (int r = 0; r < ARRAY_HEIGHT; r++) begin
                if ((k >= r) && ((k - r) < 256)) begin
                    int m = k - r;
                    int y = m / 16;
                    int x = m % 16;
                    ext_act_sram_addr[r] = (ACT_ADDR_WIDTH)'((y + ky) * 18 + (x + kx));
                end else begin
                    ext_act_sram_addr[r] = '0;
                end
            end

            for (int c = 0; c < ARRAY_WIDTH; c++) begin
                psum_bank_swap[c] = swap_mode[c];

                if (hold_zero) begin
                    psum_read_addr[c] = '0;
                end else begin
                    if ((k >= c) && ((k - c) < 256)) psum_read_addr[c] = (PSUM_ADDR_WIDTH)'(k - c);
                    else                             psum_read_addr[c] = '0;
                end

                if ((k >= (9 + c)) && ((k - (9 + c)) < 256)) begin
                    psum_write_addr[c] = (PSUM_ADDR_WIDTH)'(k - 9 - c);
                    psum_write_en[c]   = 1'b1;
                end else begin
                    psum_write_addr[c] = '0;
                    psum_write_en[c]   = 1'b0;
                end
            end
        end

        @(negedge clk_i);
        array_en      = 0;
        psum_write_en = '0;
        compute_active_cycles += (total_cycles - start_c);
    endtask

    // -------------------------------------------------------------------------
    // Parallel 8-Bank Wide Drain Tasks (256 cycles per tile)
    // -------------------------------------------------------------------------
    task automatic dma_parallel_drain_gemm(input int m_t, input int n_t, input int bank_base);
        longint start_c = total_cycles;
        int m_base = m_t * 256;
        int n_base = n_t * 8;

        for (int m = 0; m < 256; m++) begin
            @(negedge clk_i);
            for (int c = 0; c < 8; c++) begin
                ext_psum_addr[bank_base + c] = (PSUM_ADDR_WIDTH)'(m);
            end
            @(posedge clk_i);
            #1;
            for (int c = 0; c < 8; c++) begin
                actual_gemm[m_base + m][n_base + c] = ext_psum_rdata[bank_base + c];
            end
        end
        drain_cycles += (total_cycles - start_c);
    endtask

    task automatic dma_parallel_drain_1x1(input int ty, input int tx, input int cout_blk, input int bank_base);
        longint start_c = total_cycles;
        for (int m = 0; m < 256; m++) begin
            int py = ty * 16 + (m / 16);
            int px = tx * 16 + (m % 16);
            @(negedge clk_i);
            for (int c = 0; c < 8; c++) begin
                ext_psum_addr[bank_base + c] = (PSUM_ADDR_WIDTH)'(m);
            end
            @(posedge clk_i);
            #1;
            for (int c = 0; c < 8; c++) begin
                actual_conv1[py][px][cout_blk * 8 + c] = ext_psum_rdata[bank_base + c];
            end
        end
        drain_cycles += (total_cycles - start_c);
    endtask

    task automatic dma_parallel_drain_3x3(input int ty, input int tx, input int cout_blk, input int bank_base);
        longint start_c = total_cycles;
        int y_base = ty * 16;
        int x_base = tx * 16;

        for (int m = 0; m < 256; m++) begin
            int y = m / 16;
            int x = m % 16;
            @(negedge clk_i);
            for (int c = 0; c < 8; c++) begin
                ext_psum_addr[bank_base + c] = (PSUM_ADDR_WIDTH)'(m);
            end
            @(posedge clk_i);
            #1;
            for (int c = 0; c < 8; c++) begin
                actual_conv3[y_base + y][x_base + x][cout_blk * 8 + c] = ext_psum_rdata[bank_base + c];
            end
        end
        drain_cycles += (total_cycles - start_c);
    endtask

    // =========================================================================
    // MAIN BENCHMARK & REGRESSION ENGINE
    // =========================================================================
    initial begin
        longint misc_cycles;
        real pass_compute_eff, system_eff;

        $display("===================================================================");
        $display("   NPU HARDWARE PERFORMANCE BENCHMARK & MULTI-TILE REGRESSION      ");
        $display("===================================================================");

        // Load Raw Disk Problem Files
        $readmemh("yolo_gemm_A.mem",      raw_gemm_A_flat);
        $readmemh("yolo_gemm_B.mem",      raw_gemm_B_flat);
        $readmemh("golden_gemm.mem",      golden_gemm_flat);

        $readmemh("yolo_conv1_in.mem",    raw_conv1_in_flat);
        $readmemh("yolo_conv1_w.mem",     raw_conv1_w_flat);
        $readmemh("golden_conv1.mem",     golden_conv1_flat);

        $readmemh("yolo_image_3x3.mem",   raw_image_3x3_flat);
        $readmemh("yolo_weights_3x3.mem", raw_weights_3x3_flat);
        $readmemh("golden_conv3.mem",     golden_conv3_flat);

        // Hardware Reset
        clk_i = 0; rst_n = 0; array_en = 0; crossbar_sel = '0;
        psum_bank_swap = '0; psum_write_en = '0; psum_read_addr = '0; psum_write_addr = '0;
        weight_shift_in = '0; weight_shift_en = 0; swap_weights = 0;
        ext_act_sram_we = '0; ext_act_sram_addr = '0; ext_act_sram_wdata = '0;
        ext_psum_we = '0; ext_psum_addr = '0; ext_psum_wdata = '0;

        #200; rst_n = 1; #100;
        for (int r = 0; r < ARRAY_HEIGHT; r++) crossbar_sel[r] = r[2:0];

        // =====================================================================
        // BENCHMARK 1: LARGE 3D TILED GEMM (1024x32 @ 32x32)
        // 4 M-Tiles x 4 N-Tiles x 4 K-Passes = 64 Passes (1,048,576 MACs)
        // =====================================================================
        $display("\n===================================================================");
        $display(">>> BENCHMARK 1: 3D TILED GEMM (1024x32 @ 32x32 -> 1024x32) <<<");
        $display("===================================================================");

        for (int m_t = 0; m_t < 4; m_t++) begin
            for (int n_t = 0; n_t < 4; n_t++) begin
                dma_init_bias_zero();

                for (int k_t = 0; k_t < 4; k_t++) begin
                    logic [7:0] swap_mode = (k_t == 0) ? 8'h00 : ((k_t % 2 == 1) ? 8'hFF : 8'h00);
                    logic       hold_zero = (k_t == 0);
                    logic [7:0] w_slice[8][8];

                    dma_load_gemm_activations(m_t, k_t);

                    for (int r = 0; r < 8; r++)
                        for (int c = 0; c < 8; c++)
                            w_slice[r][c] = raw_gemm_B_flat[(k_t * 8 + r) * 32 + (n_t * 8 + c)];
                    dma_load_weights_slice(w_slice);

                    agu_run_linear_pass(swap_mode, hold_zero);
                end

                // Drain from Set 0 (4 even passes) in parallel (256 cycles)
                dma_parallel_drain_gemm(m_t, n_t, 0);
            end
        end

        // Verify GEMM
        for (int m = 0; m < 1024; m++) begin
            for (int n = 0; n < 32; n++) begin
                int flat_idx = m * 32 + n;
                if (actual_gemm[m][n] !== golden_gemm_flat[flat_idx]) gemm_errors++;
            end
        end
        $display(">>> GEMM Result: %s (%0d mismatches out of 32,768 values) <<<", 
                 (gemm_errors == 0) ? "PASSED [100%]" : "FAILED", gemm_errors);

        // =====================================================================
        // BENCHMARK 2: YOLO 1x1 CONVOLUTION (32x32 Image = 1024 Pixels, 16->16 Ch)
        // 4 Spatial Tiles x 2 Cout Blocks x 2 Cin Blocks = 16 Passes (262,144 MACs)
        // =====================================================================
        $display("\n===================================================================");
        $display(">>> BENCHMARK 2: YOLO 1x1 POINTWISE CONV (32x32x16 -> 32x32x16) <<<");
        $display("===================================================================");

        for (int ty = 0; ty < 2; ty++) begin
            for (int tx = 0; tx < 2; tx++) begin
                for (int cout_blk = 0; cout_blk < 2; cout_blk++) begin
                    dma_init_bias_zero();

                    for (int cin_blk = 0; cin_blk < 2; cin_blk++) begin
                        logic [7:0] swap_mode = (cin_blk == 0) ? 8'h00 : 8'hFF;
                        logic       hold_zero = (cin_blk == 0);
                        logic [7:0] w_slice[8][8];

                        dma_load_1x1_activations(ty, tx, cin_blk);

                        for (int r = 0; r < 8; r++)
                            for (int c = 0; c < 8; c++)
                                w_slice[r][c] = raw_conv1_w_flat[(cin_blk * 8 + r) * 16 + (cout_blk * 8 + c)];
                        dma_load_weights_slice(w_slice);

                        agu_run_linear_pass(swap_mode, hold_zero);
                    end

                    // Drain in parallel (256 cycles)
                    dma_parallel_drain_1x1(ty, tx, cout_blk, 0);
                end
            end
        end

        // Verify 1x1 Conv
        for (int y = 0; y < 32; y++) begin
            for (int x = 0; x < 32; x++) begin
                for (int co = 0; co < 16; co++) begin
                    int flat_idx = (y * 32 * 16) + (x * 16) + co;
                    if (actual_conv1[y][x][co] !== golden_conv1_flat[flat_idx]) conv1x1_errors++;
                end
            end
        end
        $display(">>> YOLO 1x1 Conv Result: %s (%0d mismatches out of 16,384 values) <<<", 
                 (conv1x1_errors == 0) ? "PASSED [100%]" : "FAILED", conv1x1_errors);

        // =====================================================================
        // BENCHMARK 3: YOLO 3x3 CONVOLUTION WITH SAME PADDING (32x32x16 -> 32x32x16)
        // 4 Spatial Tiles x 2 Cout Blocks x [2 Cin Blocks x 9 Taps] = 144 Passes (2,359,296 MACs)
        // =====================================================================
        $display("\n===================================================================");
        $display(">>> BENCHMARK 3: YOLO 3x3 SPATIAL CONV WITH HALO TILING (144 PASSES) <<<");
        $display("===================================================================");

        for (int ty = 0; ty < 2; ty++) begin
            for (int tx = 0; tx < 2; tx++) begin
                $display("[%0t ns] Processing YOLO Spatial Tile (Ty=%0d, Tx=%0d)...", $time, ty, tx);

                for (int cout_blk = 0; cout_blk < 2; cout_blk++) begin
                    int pass_idx = 0;
                    dma_init_bias_zero();

                    for (int cin_blk = 0; cin_blk < 2; cin_blk++) begin
                        // DMA extracts 18x18 halo patch with zero-padding on external borders
                        dma_load_yolo_halo_patch(ty, tx, cin_blk);

                        // 9 Spatial Taps
                        for (int ky = 0; ky < 3; ky++) begin
                            for (int kx = 0; kx < 3; kx++) begin
                                logic [7:0] swap_mode = (pass_idx == 0) ? 8'h00 : ((pass_idx % 2 == 1) ? 8'hFF : 8'h00);
                                logic       hold_zero = (pass_idx == 0);
                                logic [7:0] w_slice[8][8];

                                for (int r = 0; r < 8; r++) begin
                                    for (int c = 0; c < 8; c++) begin
                                        int flat_w = (ky * 3 * 16 * 16) + (kx * 16 * 16) + 
                                                     ((cin_blk * 8 + r) * 16) + (cout_blk * 8 + c);
                                        w_slice[r][c] = raw_weights_3x3_flat[flat_w];
                                    end
                                end
                                dma_load_weights_slice(w_slice);

                                agu_run_conv3x3_pass(ky, kx, swap_mode, hold_zero);
                                pass_idx++;
                            end
                        end
                    end

                    // Drain in parallel from Set 0 (18 even passes) in 256 cycles
                    dma_parallel_drain_3x3(ty, tx, cout_blk, 0);
                end
            end
        end

        // Verify 3x3 Conv
        for (int y = 0; y < 32; y++) begin
            for (int x = 0; x < 32; x++) begin
                for (int co = 0; co < 16; co++) begin
                    int flat_idx = (y * 32 * 16) + (x * 16) + co;
                    if (actual_conv3[y][x][co] !== golden_conv3_flat[flat_idx]) conv3x3_errors++;
                end
            end
        end
        $display(">>> YOLO 3x3 Conv Result: %s (%0d mismatches out of 16,384 values) <<<", 
                 (conv3x3_errors == 0) ? "PASSED [100%]" : "FAILED", conv3x3_errors);

        // =====================================================================
        // COMPREHENSIVE PERFORMANCE & UTILIZATION REPORT
        // =====================================================================
        misc_cycles      = total_cycles - (dma_act_cycles + weight_load_cycles + compute_active_cycles + drain_cycles + init_cycles);
        pass_compute_eff = (256.0 / 272.0) * 100.0; // 256 valid / 272 wave cycles
        system_eff       = ((3670016.0 / 64.0) / real'(total_cycles)) * 100.0;

        $display("\n===================================================================");
        $display("                NPU HARDWARE PERFORMANCE REPORT                    ");
        $display("===================================================================");
        $display(" Total Simulation Clock Cycles    : %12d cycles (100.0%%)", total_cycles);
        $display(" ??? Compute Pass Active Cycles   : %12d cycles (%5.1f%%)", compute_active_cycles, (real'(compute_active_cycles)/total_cycles)*100);
        $display(" ??? DMA Activation Load Cycles   : %12d cycles (%5.1f%%)", dma_act_cycles, (real'(dma_act_cycles)/total_cycles)*100);
        $display(" ??? PSum Parallel Drain Cycles   : %12d cycles (%5.1f%%)", drain_cycles, (real'(drain_cycles)/total_cycles)*100);
        $display(" ??? PE Weight Shift Cycles       : %12d cycles (%5.1f%%)", weight_load_cycles, (real'(weight_load_cycles)/total_cycles)*100);
        $display(" ??? SRAM Zero-Init Cycles        : %12d cycles (%5.1f%%)", init_cycles, (real'(init_cycles)/total_cycles)*100);
        $display(" ??? Reset / Inter-Pass Latency   : %12d cycles (%5.1f%%)", misc_cycles, (real'(misc_cycles)/total_cycles)*100);
        $display("-------------------------------------------------------------------");
        $display(" MAC UTILIZATION METRICS:");
        $display(" • Total Mathematical MACs Executed: 3,670,016 MAC operations");
        $display(" • In-Pass Systolic PE Efficiency  : %5.2f%% (256 valid / 272 wave cycles)", pass_compute_eff);
        $display(" • End-to-End System MAC Efficiency: %5.2f%% of theoretical peak", system_eff);
        $display("===================================================================\n");

        if ((gemm_errors + conv1x1_errors + conv3x3_errors) == 0) begin
            $display(">>> ALL WORKLOADS PASSED 100%% WITH EXACT MATHEMATICAL CONVERGENCE! <<<");
        end else begin
            $display(">>> BENCHMARK ENCOUNTERED %0d TOTAL MISMATCHES <<<", 
                     gemm_errors + conv1x1_errors + conv3x3_errors);
        end
        $display("===================================================================\n");

        #200;
        $finish;
    end

endmodule