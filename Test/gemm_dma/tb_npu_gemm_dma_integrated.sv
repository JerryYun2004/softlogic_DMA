`timescale 1ns / 1ps
`default_nettype none

// Full GEMM integration regression based on tb_npu_top_with_srams.sv.
//
// The original procedural dma_load_gemm_activations and
// dma_load_weights_slice tasks are replaced by:
//   CPU AXI4-Lite writes -> gemm_dma_axi_wrapper -> map_* command stream
//   -> simulation-only source-memory adapter -> NPU activation SRAMs / weights
//
// The execution, psum ping-pong, and drain schedules intentionally remain the
// same as the supplied NPU testbench.  The source adapter is not production
// RTL; it models the future memory-width-specific adapter and accepts one
// complete eight-byte command per cycle.
module tb_npu_gemm_dma_integrated;

    parameter int ARRAY_HEIGHT     = 8;
    parameter int ARRAY_WIDTH      = 8;
    parameter int TILE_SIZE        = 16;
    parameter int ACT_HALO_PAD     = 2;
    parameter int ACTIVATION_WIDTH = 8;
    parameter int WEIGHT_WIDTH     = 8;
    parameter int PSUM_WIDTH       = 32;

    localparam int GEMM_M          = 1024;
    localparam int GEMM_K          = 32;
    localparam int GEMM_N          = 32;
    localparam int M_TILE_ROWS     = 256;
    localparam int K_TILE_LANES    = 8;
    localparam int N_TILE_COLS     = 8;

    localparam int PSUM_WORDS      = TILE_SIZE * TILE_SIZE;
    localparam int ACT_WORDS       = (TILE_SIZE * TILE_SIZE) * ACT_HALO_PAD;
    localparam int PSUM_ADDR_WIDTH = $clog2(PSUM_WORDS);
    localparam int ACT_ADDR_WIDTH  = $clog2(ACT_WORDS);
    localparam int NUM_ACT_BANKS   = ARRAY_HEIGHT;
    localparam int NUM_PSUM_BANKS  = ARRAY_WIDTH * 2;
    localparam int BANK_SEL_WIDTH  = $clog2(ARRAY_HEIGHT);

    localparam logic [31:0] A_BASE = 32'h0010_0000;
    localparam logic [31:0] B_BASE = 32'h0020_0000;
    localparam int A_BYTES = GEMM_M * GEMM_K;
    localparam int B_BYTES = GEMM_K * GEMM_N;

    logic clk_i;
    logic rst_n;

    // NPU controller interface.
    logic                                        array_en;
    logic [ARRAY_HEIGHT-1:0][BANK_SEL_WIDTH-1:0] crossbar_sel;
    logic [ARRAY_WIDTH-1:0]                      psum_bank_swap;
    logic [ARRAY_WIDTH-1:0]                      psum_write_en;
    logic [ARRAY_WIDTH-1:0][PSUM_ADDR_WIDTH-1:0] psum_read_addr;
    logic [ARRAY_WIDTH-1:0][PSUM_ADDR_WIDTH-1:0] psum_write_addr;
    logic [ARRAY_HEIGHT-1:0][WEIGHT_WIDTH-1:0]   weight_shift_in;
    logic                                        weight_shift_en;
    logic                                        swap_weights;

    logic [NUM_ACT_BANKS-1:0]                       ext_act_sram_we;
    logic [NUM_ACT_BANKS-1:0][ACT_ADDR_WIDTH-1:0]   ext_act_sram_addr;
    logic [NUM_ACT_BANKS-1:0][ACTIVATION_WIDTH-1:0] ext_act_sram_wdata;
    wire  [NUM_ACT_BANKS-1:0][ACTIVATION_WIDTH-1:0] act_sram_rdata;

    logic [NUM_PSUM_BANKS-1:0]                       ext_psum_we;
    logic [NUM_PSUM_BANKS-1:0][PSUM_ADDR_WIDTH-1:0] ext_psum_addr;
    logic [NUM_PSUM_BANKS-1:0][PSUM_WIDTH-1:0]      ext_psum_wdata;
    wire  [NUM_PSUM_BANKS-1:0][PSUM_WIDTH-1:0]      ext_psum_rdata;

    // Compute-controller activation addresses are multiplexed with the DMA
    // write addresses below.
    logic [NUM_ACT_BANKS-1:0][ACT_ADDR_WIDTH-1:0] ctrl_act_sram_addr;
    logic [NUM_ACT_BANKS-1:0]                     dma_act_sram_we;
    logic [NUM_ACT_BANKS-1:0][ACT_ADDR_WIDTH-1:0] dma_act_sram_addr;
    logic [NUM_ACT_BANKS-1:0][ACTIVATION_WIDTH-1:0]
                                                       dma_act_sram_wdata;

    // AXI4-Lite signals.
    logic [31:0] dma_debug;
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

    // Protocol-neutral DMA command stream.
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

    logic [ACTIVATION_WIDTH-1:0] raw_a [0:A_BYTES-1];
    logic [WEIGHT_WIDTH-1:0]     raw_b [0:B_BYTES-1];
    logic [PSUM_WIDTH-1:0]       golden_c [0:GEMM_M*GEMM_N-1];
    logic [PSUM_WIDTH-1:0]       actual_c [0:GEMM_M*GEMM_N-1];

    integer errors;
    integer activation_command_count;
    integer weight_command_count;
    integer weight_swap_count;

    always #5 clk_i = ~clk_i;

    npu_sram_wrapper #(
        .ARRAY_HEIGHT     (ARRAY_HEIGHT),
        .ARRAY_WIDTH      (ARRAY_WIDTH),
        .TILE_SIZE        (TILE_SIZE),
        .ACT_HALO_PAD     (ACT_HALO_PAD),
        .ACTIVATION_WIDTH (ACTIVATION_WIDTH),
        .WEIGHT_WIDTH     (WEIGHT_WIDTH),
        .PSUM_WIDTH       (PSUM_WIDTH)
    ) npu_i (
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

    gemm_dma_axi_wrapper dma_i (
        .clk               (clk_i),
        .rstn              (rst_n),
        .O_top             (dma_debug),
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

    function automatic logic [7:0] source_byte(
        input logic [31:0] byte_address
    );
        integer source_index;
        begin
            source_byte = 8'hxx;
            if ((byte_address >= A_BASE) &&
                (byte_address < A_BASE + A_BYTES)) begin
                source_index = byte_address - A_BASE;
                source_byte  = raw_a[source_index];
            end else if ((byte_address >= B_BASE) &&
                         (byte_address < B_BASE + B_BYTES)) begin
                source_index = byte_address - B_BASE;
                source_byte  = raw_b[source_index];
            end
        end
    endfunction

    // Simulation-only, eight-lane-wide source-memory adapter.  Combinational
    // drive lets the NPU sample the returned bytes on the same rising edge on
    // which map_ready acknowledges the command, matching the reference tasks.
    always_comb begin
        dma_act_sram_we    = '0;
        dma_act_sram_addr  = '0;
        dma_act_sram_wdata = '0;
        weight_shift_in    = '0;
        weight_shift_en    = 1'b0;

        if (map_valid && !map_is_weight) begin
            dma_act_sram_we = map_bank_mask;
            for (int r = 0; r < ARRAY_HEIGHT; r++) begin
                dma_act_sram_addr[r]  = map_buffer_addr;
                dma_act_sram_wdata[r] = source_byte(
                    map_source_addr + r*map_source_stride
                );
            end
        end

        if (map_valid && map_is_weight) begin
            weight_shift_en = 1'b1;
            for (int r = 0; r < ARRAY_HEIGHT; r++) begin
                weight_shift_in[r] = source_byte(
                    map_source_addr + r*map_source_stride
                );
            end
        end
    end

    always_comb begin
        ext_act_sram_we    = dma_act_sram_we;
        ext_act_sram_wdata = dma_act_sram_wdata;
        for (int r = 0; r < ARRAY_HEIGHT; r++) begin
            if (dma_act_sram_we[r])
                ext_act_sram_addr[r] = dma_act_sram_addr[r];
            else
                ext_act_sram_addr[r] = ctrl_act_sram_addr[r];
        end
    end

    assign map_ready    = 1'b1;
    assign swap_weights = map_weight_swap;

    always_ff @(posedge clk_i) begin
        if (!rst_n) begin
            activation_command_count <= 0;
            weight_command_count     <= 0;
            weight_swap_count        <= 0;
        end else begin
            if (map_valid && map_ready) begin
                if (map_bank_mask != 8'hff)
                    $fatal(1, "GEMM command did not select all eight lanes");

                if (map_is_weight) begin
                    weight_command_count <= weight_command_count + 1;
                    if (map_source_stride != GEMM_N)
                        $fatal(1, "B command used unexpected row stride %0d",
                               map_source_stride);
                end else begin
                    activation_command_count <= activation_command_count + 1;
                    if (map_source_stride != 32'd1)
                        $fatal(1, "A command lane stride was not one byte");
                    if (map_buffer_addr >= M_TILE_ROWS)
                        $fatal(1, "A command exceeded the 256-row tile");
                end

                if (map_zero_fill)
                    $fatal(1, "GEMM stream unexpectedly asserted map_zero_fill");
            end

            if (map_weight_swap)
                weight_swap_count <= weight_swap_count + 1;
        end
    end

    task automatic axil_write(
        input logic [9:0]  address,
        input logic [31:0] data
    );
        logic aw_done;
        logic w_done;
        integer timeout;
        begin
            aw_done = 1'b0;
            w_done  = 1'b0;
            timeout = 0;

            @(negedge clk_i);
            axil_awaddr  = address;
            axil_awvalid = 1'b1;
            axil_wdata   = data;
            axil_wstrb   = 4'hf;
            axil_wvalid  = 1'b1;

            while (!(aw_done && w_done)) begin
                @(posedge clk_i);
                if (axil_awvalid && axil_awready)
                    aw_done = 1'b1;
                if (axil_wvalid && axil_wready)
                    w_done = 1'b1;

                @(negedge clk_i);
                if (aw_done)
                    axil_awvalid = 1'b0;
                if (w_done)
                    axil_wvalid = 1'b0;

                timeout = timeout + 1;
                if (timeout > 20)
                    $fatal(1, "AXI write handshake timeout at 0x%03h", address);
            end

            timeout = 0;
            while (!axil_bvalid) begin
                @(negedge clk_i);
                timeout = timeout + 1;
                if (timeout > 20)
                    $fatal(1, "AXI write response timeout at 0x%03h", address);
            end

            if (axil_bresp != 2'b00)
                $fatal(1, "AXI write at 0x%03h returned response %02b",
                       address, axil_bresp);

            axil_bready = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            axil_bready = 1'b0;
        end
    endtask

    task automatic wait_dma_done;
        integer timeout;
        begin
            timeout = 0;
            while (!dma_debug[1]) begin
                @(negedge clk_i);
                timeout = timeout + 1;
                if (timeout > 600)
                    $fatal(1, "DMA operation timeout");
            end

            if (dma_debug[3])
                $fatal(1, "DMA error_sticky asserted");
        end
    endtask

    task automatic dma_load_a_panel(
        input integer m_tile,
        input integer k_tile
    );
        logic [31:0] tile_pointer;
        begin
            tile_pointer = A_BASE +
                           (m_tile*M_TILE_ROWS*GEMM_K) +
                           (k_tile*K_TILE_LANES);

            axil_write(10'h00c, GEMM_K);
            axil_write(10'h008, ((M_TILE_ROWS-1) << 1));
            axil_write(10'h000, tile_pointer);
            wait_dma_done();
        end
    endtask

    task automatic dma_load_b_tile(
        input integer k_tile,
        input integer n_tile
    );
        logic [31:0] tile_pointer;
        begin
            tile_pointer = B_BASE +
                           (k_tile*K_TILE_LANES*GEMM_N) +
                           (n_tile*N_TILE_COLS);

            axil_write(10'h00c, GEMM_N);
            axil_write(10'h008, 32'd1);
            axil_write(10'h000, tile_pointer);
            wait_dma_done();
        end
    endtask

    task automatic init_bias_zero;
        begin
            @(negedge clk_i);
            ext_psum_we = 16'h00ff;
            for (int bank = 0; bank < ARRAY_WIDTH; bank++) begin
                ext_psum_addr[bank]  = '0;
                ext_psum_wdata[bank] = 32'd0;
            end
            @(negedge clk_i);
            ext_psum_we = '0;
        end
    endtask

    task automatic run_linear_pass(
        input logic [7:0] swap_mode,
        input logic       hold_zero
    );
        integer total_pass_cycles;
        begin
            total_pass_cycles = M_TILE_ROWS + ARRAY_HEIGHT + ARRAY_WIDTH;

            @(negedge clk_i);
            array_en = 1'b1;

            for (int wave = 0; wave < total_pass_cycles; wave++) begin
                @(negedge clk_i);

                for (int r = 0; r < ARRAY_HEIGHT; r++) begin
                    if ((wave >= r) && ((wave-r) < M_TILE_ROWS))
                        ctrl_act_sram_addr[r] = wave-r;
                    else
                        ctrl_act_sram_addr[r] = '0;
                end

                for (int c = 0; c < ARRAY_WIDTH; c++) begin
                    psum_bank_swap[c] = swap_mode[c];

                    if (hold_zero) begin
                        psum_read_addr[c] = '0;
                    end else if ((wave >= c) && ((wave-c) < M_TILE_ROWS)) begin
                        psum_read_addr[c] = wave-c;
                    end else begin
                        psum_read_addr[c] = '0;
                    end

                    if ((wave >= (9+c)) && ((wave-(9+c)) < M_TILE_ROWS)) begin
                        psum_write_addr[c] = wave-9-c;
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
        end
    endtask

    task automatic drain_c_tile(
        input integer m_tile,
        input integer n_tile,
        input integer bank_base
    );
        integer m_base;
        integer n_base;
        begin
            m_base = m_tile*M_TILE_ROWS;
            n_base = n_tile*N_TILE_COLS;

            for (int m = 0; m < M_TILE_ROWS; m++) begin
                @(negedge clk_i);
                for (int c = 0; c < ARRAY_WIDTH; c++) begin
                    ext_psum_addr[bank_base+c] = m;
                end
                @(posedge clk_i);
                #1;
                for (int c = 0; c < ARRAY_WIDTH; c++) begin
                    actual_c[(m_base+m)*GEMM_N + n_base+c] =
                        ext_psum_rdata[bank_base+c];
                end
            end
        end
    endtask

    initial begin
        integer m;
        integer k;
        integer n;
        integer m_tile;
        integer k_tile;
        integer n_tile;
        integer accumulator;
        integer flat_index;
        logic [7:0] swap_mode;
        logic       hold_zero;

        clk_i          = 1'b0;
        rst_n          = 1'b0;
        array_en       = 1'b0;
        crossbar_sel   = '0;
        psum_bank_swap = '0;
        psum_write_en  = '0;
        psum_read_addr = '0;
        psum_write_addr = '0;
        ctrl_act_sram_addr = '0;
        ext_psum_we    = '0;
        ext_psum_addr  = '0;
        ext_psum_wdata = '0;

        axil_awaddr  = '0;
        axil_awvalid = 1'b0;
        axil_wdata   = '0;
        axil_wstrb   = '0;
        axil_wvalid  = 1'b0;
        axil_bready  = 1'b0;
        axil_araddr  = '0;
        axil_arvalid = 1'b0;
        axil_rready  = 1'b0;

        errors = 0;

        // Deterministic positive 8-bit matrices avoid external .mem files and
        // work for signed or unsigned PE datapaths.
        for (m = 0; m < GEMM_M; m = m+1) begin
            for (k = 0; k < GEMM_K; k = k+1) begin
                raw_a[m*GEMM_K+k] = ((m*3 + k*2 + 1) % 5) + 1;
            end
        end

        for (k = 0; k < GEMM_K; k = k+1) begin
            for (n = 0; n < GEMM_N; n = n+1) begin
                raw_b[k*GEMM_N+n] = ((k*4 + n*3 + 2) % 5) + 1;
            end
        end

        for (m = 0; m < GEMM_M; m = m+1) begin
            for (n = 0; n < GEMM_N; n = n+1) begin
                accumulator = 0;
                for (k = 0; k < GEMM_K; k = k+1) begin
                    accumulator = accumulator +
                                  raw_a[m*GEMM_K+k] * raw_b[k*GEMM_N+n];
                end
                golden_c[m*GEMM_N+n] = accumulator;
                actual_c[m*GEMM_N+n] = '0;
            end
        end

        repeat (5) @(posedge clk_i);
        rst_n = 1'b1;
        repeat (3) @(posedge clk_i);

        for (int r = 0; r < ARRAY_HEIGHT; r++)
            crossbar_sel[r] = r;

        $display("Running DMA-integrated GEMM: %0dx%0d @ %0dx%0d",
                 GEMM_M, GEMM_K, GEMM_K, GEMM_N);

        for (m_tile = 0; m_tile < GEMM_M/M_TILE_ROWS; m_tile = m_tile+1) begin
            for (n_tile = 0; n_tile < GEMM_N/N_TILE_COLS; n_tile = n_tile+1) begin
                init_bias_zero();

                for (k_tile = 0; k_tile < GEMM_K/K_TILE_LANES; k_tile = k_tile+1) begin
                    if (k_tile == 0) begin
                        swap_mode = 8'h00;
                        hold_zero = 1'b1;
                    end else if ((k_tile % 2) == 1) begin
                        swap_mode = 8'hff;
                        hold_zero = 1'b0;
                    end else begin
                        swap_mode = 8'h00;
                        hold_zero = 1'b0;
                    end

                    dma_load_a_panel(m_tile, k_tile);
                    dma_load_b_tile(k_tile, n_tile);
                    run_linear_pass(swap_mode, hold_zero);
                end

                // Four K passes leave the final result in psum set 0.
                drain_c_tile(m_tile, n_tile, 0);
            end
        end

        for (m = 0; m < GEMM_M; m = m+1) begin
            for (n = 0; n < GEMM_N; n = n+1) begin
                flat_index = m*GEMM_N+n;
                if (actual_c[flat_index] !== golden_c[flat_index]) begin
                    if (errors < 12) begin
                        $display("Mismatch C[%0d][%0d]: got %0d expected %0d",
                                 m, n, actual_c[flat_index],
                                 golden_c[flat_index]);
                    end
                    errors = errors + 1;
                end
            end
        end

        if (activation_command_count != 64*M_TILE_ROWS) begin
            $display("Activation command count %0d, expected %0d",
                     activation_command_count, 64*M_TILE_ROWS);
            errors = errors + 1;
        end

        if (weight_command_count != 64*8) begin
            $display("Weight command count %0d, expected %0d",
                     weight_command_count, 64*8);
            errors = errors + 1;
        end

        if (weight_swap_count != 64) begin
            $display("Weight swap count %0d, expected 64", weight_swap_count);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: DMA-integrated 1024x32 @ 32x32 GEMM matched all 32768 outputs");
        end else begin
            $fatal(1, "FAIL: integrated GEMM regression found %0d errors", errors);
        end

        $finish;
    end

endmodule

`default_nettype wire
