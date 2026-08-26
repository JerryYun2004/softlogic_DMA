`timescale 1ns / 1ps
`default_nettype none

`ifndef YOLO_CONV3_IMAGE_MEM
`define YOLO_CONV3_IMAGE_MEM "yolo_image_3x3.mem"
`endif

`ifndef YOLO_CONV3_WEIGHTS_MEM
`define YOLO_CONV3_WEIGHTS_MEM "yolo_weights_3x3.mem"
`endif

`ifndef YOLO_CONV3_GOLDEN_MEM
`define YOLO_CONV3_GOLDEN_MEM "golden_conv3.mem"
`endif

`ifndef YOLO_CONV1_IMAGE_MEM
`define YOLO_CONV1_IMAGE_MEM "yolo_conv1_in.mem"
`endif

`ifndef YOLO_CONV1_WEIGHTS_MEM
`define YOLO_CONV1_WEIGHTS_MEM "yolo_conv1_w.mem"
`endif

`ifndef YOLO_CONV1_GOLDEN_MEM
`define YOLO_CONV1_GOLDEN_MEM "golden_conv1.mem"
`endif

// Same-instance mode-transition regression:
//   * Reset is asserted/deasserted exactly once.
//   * One dma_a and one npu_sram_wrapper compute the complete YOLO 3x3 layer.
//   * The simulated CPU changes AXI configuration bit 9 from 0 to 1.
//   * The same live DMA/NPU/SRAM instances then compute the complete 1x1 layer.
//   * Both 32x32x16 result tensors are checked against their golden memories.
//
// The workloads use independent source/golden vectors.  This test validates
// the live hardware transition; it does not feed the 3x3 result to the 1x1
// input as a model-level layer dependency.
//
// The DRAM model below presents software-packed activation tiles and weight
// slices through the DMA's real 32-bit AXI4 read master. It returns consecutive
// beats within each long row/slice burst and inserts gaps only between bursts.
// The synthesizable combined_dma_npu_sram_top owns the map adapter and connects
// each beat directly to four activation banks, or pairs two beats for the
// existing eight-lane weight shifter. No write mux is testbench-only logic.
module tb_npu_yolo_combined_sequential_integrated;

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
    localparam int IMAGE_BYTES        =
        IMAGE_HEIGHT * IMAGE_WIDTH * INPUT_CHANNELS;
    localparam int WEIGHT3_BYTES      =
        3 * 3 * INPUT_CHANNELS * OUTPUT_CHANNELS;
    localparam int WEIGHT1_BYTES      = INPUT_CHANNELS * OUTPUT_CHANNELS;
    localparam int OUTPUT_WORDS       =
        IMAGE_HEIGHT * IMAGE_WIDTH * OUTPUT_CHANNELS;

    localparam int GROUPS_PER_3X3_ACT_LOAD = 18 * 18;
    localparam int GROUPS_PER_1X1_ACT_LOAD = 16 * 16;

    localparam int EXPECTED_3X3_DMA_LOADS = 2 * 2 * 2 * 2;
    localparam int EXPECTED_3X3_ACT_GROUPS =
        EXPECTED_3X3_DMA_LOADS * GROUPS_PER_3X3_ACT_LOAD;
    localparam int EXPECTED_3X3_ZERO_GROUPS =
        EXPECTED_3X3_DMA_LOADS * (GROUPS_PER_3X3_ACT_LOAD - 17 * 17);
    localparam int EXPECTED_3X3_WEIGHT_LOADS = 2 * 2 * 2 * 2 * 3 * 3;
    localparam int EXPECTED_3X3_WEIGHT_GROUPS =
        EXPECTED_3X3_WEIGHT_LOADS * 8;
    localparam int EXPECTED_3X3_WEIGHT_BYTES =
        EXPECTED_3X3_WEIGHT_GROUPS * 8;
    localparam int EXPECTED_3X3_ACT_BURSTS =
        EXPECTED_3X3_DMA_LOADS * 17;
    localparam int EXPECTED_3X3_WEIGHT_BURSTS =
        EXPECTED_3X3_WEIGHT_LOADS;
    localparam int EXPECTED_3X3_AXI_WRITES =
        2 * (EXPECTED_3X3_DMA_LOADS + EXPECTED_3X3_WEIGHT_LOADS);

    localparam int EXPECTED_1X1_DMA_LOADS = 2 * 2 * 2 * 2;
    localparam int EXPECTED_1X1_ACT_GROUPS =
        EXPECTED_1X1_DMA_LOADS * GROUPS_PER_1X1_ACT_LOAD;
    localparam int EXPECTED_1X1_WEIGHT_LOADS = 2 * 2 * 2 * 2;
    localparam int EXPECTED_1X1_WEIGHT_GROUPS =
        EXPECTED_1X1_WEIGHT_LOADS * 8;
    localparam int EXPECTED_1X1_WEIGHT_BYTES =
        EXPECTED_1X1_WEIGHT_GROUPS * 8;
    localparam int EXPECTED_1X1_ACT_BURSTS =
        EXPECTED_1X1_DMA_LOADS * 16;
    localparam int EXPECTED_1X1_WEIGHT_BURSTS =
        EXPECTED_1X1_WEIGHT_LOADS;
    localparam int EXPECTED_1X1_AXI_WRITES =
        2 * (EXPECTED_1X1_DMA_LOADS + EXPECTED_1X1_WEIGHT_LOADS);

    // Every activation object occupies a page-spaced address slot. The useful
    // bytes are 2048 (1x1) or 2312 (3x3); page spacing also keeps the normal
    // row bursts away from AXI's 4 KiB boundary. Weight slices are 64-byte
    // aligned and packed in their actual shift order.
    localparam logic [31:0] PACKED_ACT3_BASE = 32'h1000_0000;
    localparam logic [31:0] PACKED_ACT1_BASE = 32'h1100_0000;
    localparam logic [31:0] PACKED_WGT3_BASE = 32'h2000_0000;
    localparam logic [31:0] PACKED_WGT1_BASE = 32'h2100_0000;
    localparam int PACKED_OBJECT_STRIDE = 4096;
    localparam int PACKED_ACT3_BYTES = 17 * 17 * 8;
    localparam int PACKED_ACT1_BYTES = 16 * 16 * 8;
    localparam int PACKED_WEIGHT_BYTES = 8 * 8;
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

    wire [31:0] dma_status;

    wire        map_valid;
    wire        map_ready;
    wire [31:0] map_data;
    wire [31:0] map_source_addr;
    wire [4:0]  map_source_stride;
    wire [8:0]  map_buffer_addr;
    wire [7:0]  map_bank_mask;
    wire        map_is_weight;
    wire        map_zero_fill;
    wire        map_last;
    wire        map_weight_swap;

    logic dma_act_port_grant;
    logic dma_weight_port_grant;
    wire  dma_port_enable = dma_act_port_grant ||
                            dma_weight_port_grant;

    localparam int DRAM_GAP_CYCLES = 6;
    logic        dram_active_q;
    logic [31:0] dram_addr_q;
    integer      dram_beats_left_q;
    integer      dram_gap_q;
    longint      dram_read_bursts;
    longint      dram_read_beats;
    longint      dram_activation_bursts;
    longint      dram_weight_bursts;
    logic [31:0] dma_current_source_base;
    integer      dma_current_source_bytes;

    // ---------------------------------------------------------------------
    // Problem data and scoreboards
    // ---------------------------------------------------------------------
    logic [ACTIVATION_WIDTH-1:0] raw_image_3x3_flat
        [0:IMAGE_BYTES-1];
    logic [WEIGHT_WIDTH-1:0] raw_weights_3x3_flat
        [0:WEIGHT3_BYTES-1];
    logic [PSUM_WIDTH-1:0] golden_conv3_flat
        [0:OUTPUT_WORDS-1];
    logic [PSUM_WIDTH-1:0] actual_conv3
        [0:IMAGE_HEIGHT-1][0:IMAGE_WIDTH-1][0:OUTPUT_CHANNELS-1];

    logic [ACTIVATION_WIDTH-1:0] raw_image_1x1_flat
        [0:IMAGE_BYTES-1];
    logic [WEIGHT_WIDTH-1:0] raw_weights_1x1_flat
        [0:WEIGHT1_BYTES-1];
    logic [PSUM_WIDTH-1:0] golden_conv1_flat
        [0:OUTPUT_WORDS-1];
    logic [PSUM_WIDTH-1:0] actual_conv1
        [0:IMAGE_HEIGHT-1][0:IMAGE_WIDTH-1][0:OUTPUT_CHANNELS-1];

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
    logic   dma_expected_high_half;
    integer weight_load_count;
    integer compute_pass_count;

    integer reset_release_count;
    integer mode_transition_count;
    logic   previous_conv_1x1;

    integer errors_after_3x3;
    integer axi_writes_after_3x3;
    integer dma_loads_after_3x3;
    integer act_groups_after_3x3;
    integer zero_groups_after_3x3;
    integer weight_loads_after_3x3;
    integer weight_groups_after_3x3;
    integer weight_bytes_after_3x3;
    integer weight_swaps_after_3x3;
    integer compute_passes_after_3x3;

    string conv3_image_mem_path;
    string conv3_weights_mem_path;
    string conv3_golden_mem_path;
    string conv1_image_mem_path;
    string conv1_weights_mem_path;
    string conv1_golden_mem_path;
    string vcd_path;

    // 10 MHz simulation clock, matching the original NPU regression.
    always #50 clk_i = ~clk_i;

    always @(posedge clk_i) begin
        if (!rst_n)
            total_cycles <= 0;
        else
            total_cycles <= total_cycles + 1;
    end

    // This count makes the no-reset-between-layers requirement explicit.
    always @(posedge rst_n)
        reset_release_count = reset_release_count + 1;

    // Count every observed change of the CPU-selected convolution mode.
    always @(posedge clk_i) begin
        if (!rst_n) begin
            previous_conv_1x1 <= 1'b0;
            mode_transition_count <= 0;
        end else if (dma_status[9] !== previous_conv_1x1) begin
            previous_conv_1x1 <= dma_status[9];
            mode_transition_count <= mode_transition_count + 1;
        end
    end

    // ---------------------------------------------------------------------
    // Synthesizable combined DMA + ownership adapter + NPU/SRAM subsystem.
    // There is no testbench-only write mux in this revision.
    // ---------------------------------------------------------------------
    combined_dma_npu_sram_top #(
        .ARRAY_HEIGHT     (ARRAY_HEIGHT),
        .ARRAY_WIDTH      (ARRAY_WIDTH),
        .TILE_SIZE        (TILE_SIZE),
        .ACT_HALO_PAD     (ACT_HALO_PAD),
        .ACTIVATION_WIDTH (ACTIVATION_WIDTH),
        .WEIGHT_WIDTH     (WEIGHT_WIDTH),
        .PSUM_WIDTH       (PSUM_WIDTH)
    ) subsystem_dut (
        .clk_i              (clk_i),
        .rst_n              (rst_n),
        .dma_status_o       (dma_status),
        .axil_awaddr        (axil_awaddr),
        .axil_awvalid       (axil_awvalid),
        .axil_awready       (axil_awready),
        .axil_wdata         (axil_wdata),
        .axil_wstrb         (axil_wstrb),
        .axil_wvalid        (axil_wvalid),
        .axil_wready        (axil_wready),
        .axil_bresp         (axil_bresp),
        .axil_bvalid        (axil_bvalid),
        .axil_bready        (axil_bready),
        .axil_araddr        (axil_araddr),
        .axil_arvalid       (axil_arvalid),
        .axil_arready       (axil_arready),
        .axil_rdata         (axil_rdata),
        .axil_rresp         (axil_rresp),
        .axil_rvalid        (axil_rvalid),
        .axil_rready        (axil_rready),
        .m_axi_araddr       (m_axi_araddr),
        .m_axi_arlen        (m_axi_arlen),
        .m_axi_arsize       (m_axi_arsize),
        .m_axi_arburst      (m_axi_arburst),
        .m_axi_arvalid      (m_axi_arvalid),
        .m_axi_arready      (m_axi_arready),
        .m_axi_rdata        (m_axi_rdata),
        .m_axi_rresp        (m_axi_rresp),
        .m_axi_rlast        (m_axi_rlast),
        .m_axi_rvalid       (m_axi_rvalid),
        .m_axi_rready       (m_axi_rready),
        .dma_act_port_grant_i    (dma_act_port_grant),
        .dma_weight_port_grant_i (dma_weight_port_grant),
        .array_en           (array_en),
        .crossbar_sel       (crossbar_sel),
        .psum_bank_swap     (psum_bank_swap),
        .psum_write_en      (psum_write_en),
        .psum_read_addr     (psum_read_addr),
        .psum_write_addr    (psum_write_addr),
        .act_compute_addr   (act_compute_addr),
        .act_sram_rdata     (act_sram_rdata),
        .ext_psum_we        (ext_psum_we),
        .ext_psum_addr      (ext_psum_addr),
        .ext_psum_wdata     (ext_psum_wdata),
        .ext_psum_rdata     (ext_psum_rdata),
        .map_valid_o        (map_valid),
        .map_ready_o        (map_ready),
        .map_data_o         (map_data),
        .map_source_addr_o  (map_source_addr),
        .map_source_stride_o(map_source_stride),
        .map_buffer_addr_o  (map_buffer_addr),
        .map_bank_mask_o    (map_bank_mask),
        .map_is_weight_o    (map_is_weight),
        .map_zero_fill_o    (map_zero_fill),
        .map_last_o         (map_last),
        .map_weight_swap_o  (map_weight_swap)
    );

    // ---------------------------------------------------------------------
    // Simulation-only off-chip DRAM AXI4 read slave
    // ---------------------------------------------------------------------
    function automatic [31:0] packed_act3_pointer(input integer tile_y,
                                                   input integer tile_x,
                                                   input integer cin_block);
        integer object_index;
        begin
            object_index = ((tile_y * 2 + tile_x) * 2) + cin_block;
            packed_act3_pointer = PACKED_ACT3_BASE +
                                  object_index * PACKED_OBJECT_STRIDE;
        end
    endfunction

    function automatic [31:0] packed_act1_pointer(input integer tile_y,
                                                   input integer tile_x,
                                                   input integer cin_block);
        integer object_index;
        begin
            object_index = ((tile_y * 2 + tile_x) * 2) + cin_block;
            packed_act1_pointer = PACKED_ACT1_BASE +
                                  object_index * PACKED_OBJECT_STRIDE;
        end
    endfunction

    function automatic [31:0] packed_wgt3_pointer(input integer kernel_y,
                                                   input integer kernel_x,
                                                   input integer cin_block,
                                                   input integer cout_block);
        integer slice_index;
        begin
            slice_index = ((((kernel_y * 3) + kernel_x) * 2 + cin_block)
                           * 2) + cout_block;
            packed_wgt3_pointer = PACKED_WGT3_BASE +
                                  slice_index * PACKED_WEIGHT_BYTES;
        end
    endfunction

    function automatic [31:0] packed_wgt1_pointer(input integer cin_block,
                                                   input integer cout_block);
        integer slice_index;
        begin
            slice_index = cin_block * 2 + cout_block;
            packed_wgt1_pointer = PACKED_WGT1_BASE +
                                  slice_index * PACKED_WEIGHT_BYTES;
        end
    endfunction

    // Translate a packed DRAM byte address back to the original test vector.
    // Weight group g contains output column (7-g), with input-channel lane r
    // in byte r, exactly matching the NPU's eight weight-shift inputs.
    function automatic [7:0] dram_byte(input logic [31:0] address);
        integer relative;
        integer object_index;
        integer object_offset;
        integer packed_pixel;
        integer packed_y;
        integer packed_x;
        integer lane;
        integer tile_y;
        integer tile_x;
        integer cin_block;
        integer cout_block;
        integer kernel_tap;
        integer group_index;
        integer global_y;
        integer global_x;
        integer raw_index;
        begin
            dram_byte = 'x;

            if ((address >= PACKED_ACT3_BASE) &&
                (address < PACKED_ACT3_BASE + 8*PACKED_OBJECT_STRIDE)) begin
                relative     = address - PACKED_ACT3_BASE;
                object_index = relative / PACKED_OBJECT_STRIDE;
                object_offset = relative % PACKED_OBJECT_STRIDE;
                if (object_offset < PACKED_ACT3_BYTES) begin
                    cin_block  = object_index % 2;
                    tile_x     = (object_index / 2) % 2;
                    tile_y     = (object_index / 4) % 2;
                    packed_pixel = object_offset / 8;
                    lane         = object_offset % 8;
                    packed_y     = packed_pixel / 17;
                    packed_x     = packed_pixel % 17;
                    global_y     = tile_y * 15 + packed_y;
                    global_x     = tile_x * 15 + packed_x;
                    raw_index = ((global_y * IMAGE_WIDTH + global_x) *
                                 INPUT_CHANNELS) + cin_block * 8 + lane;
                    dram_byte = raw_image_3x3_flat[raw_index];
                end
            end else if ((address >= PACKED_ACT1_BASE) &&
                         (address < PACKED_ACT1_BASE +
                                    8*PACKED_OBJECT_STRIDE)) begin
                relative      = address - PACKED_ACT1_BASE;
                object_index  = relative / PACKED_OBJECT_STRIDE;
                object_offset = relative % PACKED_OBJECT_STRIDE;
                if (object_offset < PACKED_ACT1_BYTES) begin
                    cin_block  = object_index % 2;
                    tile_x     = (object_index / 2) % 2;
                    tile_y     = (object_index / 4) % 2;
                    packed_pixel = object_offset / 8;
                    lane         = object_offset % 8;
                    packed_y     = packed_pixel / 16;
                    packed_x     = packed_pixel % 16;
                    global_y     = tile_y * 16 + packed_y;
                    global_x     = tile_x * 16 + packed_x;
                    raw_index = ((global_y * IMAGE_WIDTH + global_x) *
                                 INPUT_CHANNELS) + cin_block * 8 + lane;
                    dram_byte = raw_image_1x1_flat[raw_index];
                end
            end else if ((address >= PACKED_WGT3_BASE) &&
                         (address < PACKED_WGT3_BASE + WEIGHT3_BYTES)) begin
                relative      = address - PACKED_WGT3_BASE;
                object_index  = relative / PACKED_WEIGHT_BYTES;
                object_offset = relative % PACKED_WEIGHT_BYTES;
                cout_block    = object_index % 2;
                cin_block     = (object_index / 2) % 2;
                kernel_tap    = object_index / 4;
                group_index   = object_offset / 8;
                lane          = object_offset % 8;
                raw_index = kernel_tap * INPUT_CHANNELS * OUTPUT_CHANNELS +
                            (cin_block * 8 + lane) * OUTPUT_CHANNELS +
                            cout_block * 8 + (7-group_index);
                dram_byte = raw_weights_3x3_flat[raw_index];
            end else if ((address >= PACKED_WGT1_BASE) &&
                         (address < PACKED_WGT1_BASE + WEIGHT1_BYTES)) begin
                relative      = address - PACKED_WGT1_BASE;
                object_index  = relative / PACKED_WEIGHT_BYTES;
                object_offset = relative % PACKED_WEIGHT_BYTES;
                cout_block    = object_index % 2;
                cin_block     = (object_index / 2) % 2;
                group_index   = object_offset / 8;
                lane          = object_offset % 8;
                raw_index = (cin_block * 8 + lane) * OUTPUT_CHANNELS +
                            cout_block * 8 + (7-group_index);
                dram_byte = raw_weights_1x1_flat[raw_index];
            end
        end
    endfunction

    function automatic [31:0] dram_word(input logic [31:0] address);
        begin
            dram_word = {
                dram_byte(address + 3), dram_byte(address + 2),
                dram_byte(address + 1), dram_byte(address)
            };
        end
    endfunction

    // R beats remain consecutive inside each long burst. The inter-burst gap
    // models DRAM/interconnect request latency, which is now amortized across
    // a complete packed row or weight slice.
    always @(posedge clk_i) begin
        if (!rst_n) begin
            m_axi_arready     <= 1'b0;
            m_axi_rdata       <= 32'd0;
            m_axi_rresp       <= AXI_RESP_OKAY;
            m_axi_rlast       <= 1'b0;
            m_axi_rvalid      <= 1'b0;
            dram_active_q     <= 1'b0;
            dram_addr_q       <= 32'd0;
            dram_beats_left_q <= 0;
            dram_gap_q        <= 0;
            dram_read_bursts  <= 0;
            dram_read_beats   <= 0;
            dram_activation_bursts <= 0;
            dram_weight_bursts     <= 0;
        end else begin
            m_axi_arready <= !dram_active_q && !m_axi_rvalid &&
                             (dram_gap_q == 0);

            if (dram_gap_q > 0)
                dram_gap_q <= dram_gap_q - 1;

            // The relevant ownership grant remains high throughout each DMA
            // load, so the packed half-word/output pipeline must accept every
            // returned beat without inserting an R-channel bubble.
            if (dma_port_enable && m_axi_rvalid && !m_axi_rready) begin
                $display("ERROR: DMA stalled a packed AXI R stream while map_ready was high");
                errors = errors + 1;
            end

            if (m_axi_arvalid && m_axi_arready) begin
                if (m_axi_araddr[1:0] != 2'b00) begin
                    $display("ERROR: DRAM AXI ARADDR is unaligned: %08h",
                             m_axi_araddr);
                    errors = errors + 1;
                end
                if ((m_axi_arsize != 3'b010) ||
                    (m_axi_arburst != 2'b01)) begin
                    $display("ERROR: invalid AXI read attributes size=%0d burst=%0b",
                             m_axi_arsize, m_axi_arburst);
                    errors = errors + 1;
                end

                if (m_axi_araddr >= PACKED_WGT3_BASE) begin
                    if (m_axi_arlen != 8'd15) begin
                        $display("ERROR: packed weight read ARLEN=%0d expected=15",
                                 m_axi_arlen);
                        errors = errors + 1;
                    end
                    dram_weight_bursts <= dram_weight_bursts + 1;
                end else begin
                    if (dma_status[9] && (m_axi_arlen != 8'd31)) begin
                        $display("ERROR: packed 1x1 row ARLEN=%0d expected=31",
                                 m_axi_arlen);
                        errors = errors + 1;
                    end else if (!dma_status[9] &&
                                 (m_axi_arlen != 8'd33)) begin
                        $display("ERROR: packed 3x3 row ARLEN=%0d expected=33",
                                 m_axi_arlen);
                        errors = errors + 1;
                    end
                    dram_activation_bursts <=
                        dram_activation_bursts + 1;
                end

                if (({1'b0, m_axi_araddr[11:0]} +
                     (({5'd0, m_axi_arlen} + 13'd1) << 2)) > 13'd4096) begin
                    $display("ERROR: AXI burst crosses 4 KiB boundary addr=%08h len=%0d",
                             m_axi_araddr, m_axi_arlen);
                    errors = errors + 1;
                end

                dram_active_q     <= 1'b1;
                dram_addr_q       <= m_axi_araddr;
                dram_beats_left_q <= m_axi_arlen + 1;
                m_axi_arready     <= 1'b0;
                dram_read_bursts  <= dram_read_bursts + 1;
            end

            if (dram_active_q && !m_axi_rvalid) begin
                m_axi_rdata  <= dram_word(dram_addr_q);
                m_axi_rresp  <= AXI_RESP_OKAY;
                m_axi_rlast  <= (dram_beats_left_q == 1);
                m_axi_rvalid <= 1'b1;
            end

            if (m_axi_rvalid && m_axi_rready) begin
                dram_read_beats <= dram_read_beats + 1;
                if (dram_beats_left_q == 1) begin
                    m_axi_rvalid      <= 1'b0;
                    m_axi_rlast       <= 1'b0;
                    dram_active_q     <= 1'b0;
                    dram_beats_left_q <= 0;
                    dram_gap_q        <= DRAM_GAP_CYCLES;
                end else begin
                    dram_addr_q       <= dram_addr_q + 4;
                    dram_beats_left_q <= dram_beats_left_q - 1;
                    m_axi_rdata       <= dram_word(dram_addr_q + 4);
                    m_axi_rlast       <= (dram_beats_left_q == 2);
                    m_axi_rvalid      <= 1'b1;
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // DMA/NPU ownership assertions
    // ---------------------------------------------------------------------
    // The write/address mux is now synthesizable RTL inside subsystem_dut.
    // Check its external handshake contract throughout the full regression.
    always @(posedge clk_i) begin
        if (rst_n) begin
            if (array_en && dma_act_port_grant) begin
                $display("ERROR: activation DMA ownership overlapped systolic-array reads");
                errors = errors + 1;
            end
            if (array_en && dma_weight_port_grant) begin
                $display("ERROR: weight DMA ownership overlapped array execution");
                errors = errors + 1;
            end
            if (map_ready !==
                (map_is_weight
                    ? (dma_weight_port_grant && !array_en)
                    : (dma_act_port_grant && !array_en))) begin
                $display("ERROR: map_ready did not select the relevant granted NPU port");
                errors = errors + 1;
            end
        end
    end

    // Monitor every direct 32-bit beat accepted by the SRAM adapter. A low/high
    // pair counts as one eight-channel activation or weight group so the
    // aggregate counters retain their original architectural meaning.
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
            dma_expected_high_half <= 1'b0;
        end else begin
            if (map_valid && map_ready) begin
                if (map_last)
                    dma_last_this_load <= dma_last_this_load + 1;

                if (map_buffer_addr !== dma_groups_this_load[8:0]) begin
                    $display("ERROR: DMA destination/shift sequence got=%0d expected=%0d",
                             map_buffer_addr, dma_groups_this_load);
                    errors = errors + 1;
                end

                if (map_bank_mask !==
                    (dma_expected_high_half ? 8'hf0 : 8'h0f)) begin
                    $display("ERROR: DMA bank-half mask got=%02h expected=%02h",
                             map_bank_mask,
                             dma_expected_high_half ? 8'hf0 : 8'h0f);
                    errors = errors + 1;
                end

                for (int r = 0; r < 4; r++) begin
                    if (map_data[r*8 +: 8] !==
                        (map_zero_fill
                            ? 8'd0
                            : dram_byte(map_source_addr +
                                        r*map_source_stride))) begin
                        $display("ERROR: fetched map byte lane=%0d src=%08h got=%02h expected=%02h",
                                 r,
                                 map_source_addr + r*map_source_stride,
                                 map_data[r*8 +: 8],
                                 map_zero_fill
                                    ? 8'd0
                                    : dram_byte(map_source_addr +
                                                r*map_source_stride));
                        errors = errors + 1;
                    end
                end

                if (map_is_weight) begin
                    dma_total_weight_bytes <= dma_total_weight_bytes + 4;
                    if (dma_expected_high_half)
                        dma_total_weight_groups <=
                            dma_total_weight_groups + 1;

                    if (map_source_stride !== 5'd1) begin
                        $display("ERROR: packed DMA weight stride got=%0d expected=1",
                                 map_source_stride);
                        errors = errors + 1;
                    end
                    if (map_zero_fill) begin
                        $display("ERROR: DMA weight command requested zero fill");
                        errors = errors + 1;
                    end
                    if (!((map_source_addr >= dma_current_source_base) &&
                          (map_source_addr + 3 <
                           dma_current_source_base +
                           dma_current_source_bytes))) begin
                        $display("ERROR: DMA source address out of weight range: %08h",
                                 map_source_addr);
                        errors = errors + 1;
                    end
                end else begin
                    if (dma_expected_high_half)
                        dma_total_groups <= dma_total_groups + 1;

                    if (map_source_stride !== 5'd1) begin
                        $display("ERROR: DMA activation stride got=%0d expected=1",
                                 map_source_stride);
                        errors = errors + 1;
                    end
                    if (map_zero_fill && dma_expected_high_half)
                        dma_total_zero_groups <= dma_total_zero_groups + 1;
                    if (dma_status[9] && map_zero_fill) begin
                        $display("ERROR: 1x1 activation DMA requested zero fill");
                        errors = errors + 1;
                    end
                    if (!map_zero_fill &&
                        !((map_source_addr >= dma_current_source_base) &&
                          (map_source_addr + 3 <
                           dma_current_source_base +
                           dma_current_source_bytes))) begin
                        $display("ERROR: DMA source address out of image range: %08h",
                                 map_source_addr);
                        errors = errors + 1;
                    end
                end

                if (map_last && !dma_expected_high_half) begin
                    $display("ERROR: map_last asserted on the low 32-bit half");
                    errors = errors + 1;
                end

                if (dma_expected_high_half)
                    dma_groups_this_load <= dma_groups_this_load + 1;
                dma_expected_high_half <= !dma_expected_high_half;
            end

            if (map_weight_swap) begin
                dma_total_weight_swaps <= dma_total_weight_swaps + 1;
                dma_swap_this_load     <= dma_swap_this_load + 1;

                if (map_valid || !map_is_weight) begin
                    $display("ERROR: DMA weight swap overlaps an invalid command state");
                    errors = errors + 1;
                end
                if (!dma_weight_port_grant || array_en) begin
                    $display("ERROR: DMA weight swap occurred without exclusive weight-port ownership");
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

    // One call replaces the original procedural 3x3 halo-patch loader.
    task automatic dma_load_3x3_activations(input int tile_y,
                                            input int tile_x,
                                            input int cin_block);
        logic [31:0] config_word;
        logic [31:0] source_pointer;
        longint start_cycle;
        begin
            start_cycle = total_cycles;
            source_pointer = packed_act3_pointer(tile_y, tile_x, cin_block);
            config_word = 32'd0;
            config_word[0] = tile_x[0];
            config_word[1] = tile_y[0];
            config_word[2] = cin_block[0];
            config_word[3] = 1'b0;
            config_word[9] = 1'b0; // CPU selects the 3x3 schedule.

            dma_groups_this_load = 0;
            dma_last_this_load   = 0;
            dma_swap_this_load   = 0;
            dma_expected_high_half = 1'b0;
            dma_act_port_grant    = 1'b1;
            dma_weight_port_grant = 1'b0;
            dma_current_source_base  = source_pointer;
            dma_current_source_bytes = PACKED_ACT3_BYTES;

            axil_write(10'h008, config_word, 4'hf, AXI_RESP_OKAY);
            if (dma_status[9] !== 1'b0) begin
                $display("ERROR: CPU selected 3x3 mode but DMA status bit 9 is %b",
                         dma_status[9]);
                errors = errors + 1;
            end
            axil_write(10'h000, source_pointer, 4'hf, AXI_RESP_OKAY);

            wait (dma_status[2] === 1'b1);
            wait (dma_status[1] === 1'b1);
            @(negedge clk_i);

            dma_act_port_grant = 1'b0;
            dma_load_count  = dma_load_count + 1;
            dma_act_cycles  = dma_act_cycles + (total_cycles - start_cycle);

            if (dma_expected_high_half !== 1'b0) begin
                $display("ERROR: 3x3 activation load ended between 32-bit halves");
                errors = errors + 1;
            end

            if (dma_groups_this_load != GROUPS_PER_3X3_ACT_LOAD) begin
                $display("ERROR: DMA load ty=%0d tx=%0d cin=%0d emitted %0d groups, expected %0d",
                         tile_y, tile_x, cin_block,
                         dma_groups_this_load, GROUPS_PER_3X3_ACT_LOAD);
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

    task automatic dma_load_3x3_weights_slice(input int kernel_y,
                                              input int kernel_x,
                                              input int cin_block,
                                              input int cout_block);
        logic [31:0] config_word;
        logic [31:0] source_pointer;
        longint start_cycle;
        begin
            start_cycle = total_cycles;
            source_pointer = packed_wgt3_pointer(
                kernel_y, kernel_x, cin_block, cout_block
            );
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
            dma_expected_high_half = 1'b0;
            dma_act_port_grant    = 1'b0;
            dma_weight_port_grant = 1'b1;
            dma_current_source_base  = source_pointer;
            dma_current_source_bytes = PACKED_WEIGHT_BYTES;

            axil_write(10'h008, config_word, 4'hf, AXI_RESP_OKAY);
            if (dma_status[9] !== 1'b0) begin
                $display("ERROR: CPU selected 3x3 mode but DMA status bit 9 is %b",
                         dma_status[9]);
                errors = errors + 1;
            end
            axil_write(10'h000, source_pointer, 4'hf, AXI_RESP_OKAY);

            wait (dma_status[2] === 1'b1);
            wait (dma_status[1] === 1'b1);
            @(negedge clk_i);
            dma_weight_port_grant = 1'b0;

            weight_load_count  = weight_load_count + 1;
            weight_load_cycles = weight_load_cycles +
                                 (total_cycles - start_cycle);

            if (dma_expected_high_half !== 1'b0) begin
                $display("ERROR: 3x3 weight load ended between 32-bit halves");
                errors = errors + 1;
            end

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
    // 1x1 DMA loading plus NPU compute and drain scheduling
    // ---------------------------------------------------------------------
    task automatic dma_load_1x1_activations(input int tile_y,
                                            input int tile_x,
                                            input int cin_block);
        logic [31:0] config_word;
        logic [31:0] source_pointer;
        longint start_cycle;
        begin
            start_cycle = total_cycles;
            source_pointer = packed_act1_pointer(tile_y, tile_x, cin_block);
            config_word = 32'd0;
            config_word[0] = tile_x[0];
            config_word[1] = tile_y[0];
            config_word[2] = cin_block[0];
            config_word[3] = 1'b0;
            config_word[4] = 1'b0;
            config_word[9] = 1'b1;

            dma_groups_this_load = 0;
            dma_last_this_load   = 0;
            dma_swap_this_load   = 0;
            dma_expected_high_half = 1'b0;
            dma_act_port_grant    = 1'b1;
            dma_weight_port_grant = 1'b0;
            dma_current_source_base  = source_pointer;
            dma_current_source_bytes = PACKED_ACT1_BYTES;

            // This first configuration write is the actual live 3x3-to-1x1
            // mode transition.  There is deliberately no reset around it.
            axil_write(10'h008, config_word, 4'hf, AXI_RESP_OKAY);
            if (dma_status[9] !== 1'b1) begin
                $display("ERROR: CPU selected 1x1 mode but DMA status bit 9 is %b",
                         dma_status[9]);
                errors = errors + 1;
            end
            axil_write(10'h000, source_pointer, 4'hf, AXI_RESP_OKAY);

            wait (dma_status[2] === 1'b1);
            wait (dma_status[1] === 1'b1);
            @(negedge clk_i);

            dma_act_port_grant = 1'b0;
            dma_load_count  = dma_load_count + 1;
            dma_act_cycles  = dma_act_cycles + (total_cycles - start_cycle);

            if (dma_expected_high_half !== 1'b0) begin
                $display("ERROR: 1x1 activation load ended between 32-bit halves");
                errors = errors + 1;
            end

            if (dma_status[3]) begin
                $display("ERROR: DMA wrapper error after 1x1 activation load ty=%0d tx=%0d cin=%0d",
                         tile_y, tile_x, cin_block);
                errors = errors + 1;
            end
            if (dma_groups_this_load != GROUPS_PER_1X1_ACT_LOAD) begin
                $display("ERROR: 1x1 activation DMA ty=%0d tx=%0d cin=%0d emitted %0d groups, expected %0d",
                         tile_y, tile_x, cin_block,
                         dma_groups_this_load, GROUPS_PER_1X1_ACT_LOAD);
                errors = errors + 1;
            end
            if (dma_last_this_load != 1) begin
                $display("ERROR: 1x1 activation DMA ty=%0d tx=%0d cin=%0d emitted map_last %0d times",
                         tile_y, tile_x, cin_block, dma_last_this_load);
                errors = errors + 1;
            end
            if (dma_swap_this_load != 0) begin
                $display("ERROR: 1x1 activation DMA emitted %0d weight swaps",
                         dma_swap_this_load);
                errors = errors + 1;
            end
        end
    endtask

    task automatic dma_load_1x1_weights_slice(input int cin_block,
                                              input int cout_block);
        logic [31:0] config_word;
        logic [31:0] source_pointer;
        longint start_cycle;
        begin
            start_cycle = total_cycles;
            source_pointer = packed_wgt1_pointer(cin_block, cout_block);
            config_word = 32'd0;
            config_word[2] = cin_block[0];
            config_word[3] = 1'b1;
            config_word[4] = cout_block[0];
            config_word[9] = 1'b1;

            dma_groups_this_load = 0;
            dma_last_this_load   = 0;
            dma_swap_this_load   = 0;
            dma_expected_high_half = 1'b0;
            dma_act_port_grant    = 1'b0;
            dma_weight_port_grant = 1'b1;
            dma_current_source_base  = source_pointer;
            dma_current_source_bytes = PACKED_WEIGHT_BYTES;

            axil_write(10'h008, config_word, 4'hf, AXI_RESP_OKAY);
            if (dma_status[9] !== 1'b1) begin
                $display("ERROR: CPU selected 1x1 mode but DMA status bit 9 is %b",
                         dma_status[9]);
                errors = errors + 1;
            end
            axil_write(10'h000, source_pointer, 4'hf, AXI_RESP_OKAY);

            wait (dma_status[2] === 1'b1);
            wait (dma_status[1] === 1'b1);
            @(negedge clk_i);

            dma_weight_port_grant = 1'b0;
            weight_load_count  = weight_load_count + 1;
            weight_load_cycles = weight_load_cycles +
                                 (total_cycles - start_cycle);

            if (dma_expected_high_half !== 1'b0) begin
                $display("ERROR: 1x1 weight load ended between 32-bit halves");
                errors = errors + 1;
            end

            if (dma_status[3]) begin
                $display("ERROR: DMA wrapper error after 1x1 weight load cin=%0d cout=%0d",
                         cin_block, cout_block);
                errors = errors + 1;
            end
            if (dma_groups_this_load != 8) begin
                $display("ERROR: 1x1 weight DMA cin=%0d cout=%0d emitted %0d groups, expected 8",
                         cin_block, cout_block, dma_groups_this_load);
                errors = errors + 1;
            end
            if (dma_last_this_load != 1) begin
                $display("ERROR: 1x1 weight DMA cin=%0d cout=%0d emitted map_last %0d times",
                         cin_block, cout_block, dma_last_this_load);
                errors = errors + 1;
            end
            if (dma_swap_this_load != 1) begin
                $display("ERROR: 1x1 weight DMA cin=%0d cout=%0d emitted swap %0d times",
                         cin_block, cout_block, dma_swap_this_load);
                errors = errors + 1;
            end
        end
    endtask

    // The 1x1 activation SRAM uses addresses 0..255 directly.  Row r receives
    // pixel m at cycle m+r, preserving the original systolic row skew.
    task automatic run_conv1x1_pass(input logic [7:0] swap_mode,
                                    input logic       hold_zero);
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
                        act_compute_addr[r] =
                            (ACT_ADDR_WIDTH)'(k-r);
                    end else begin
                        act_compute_addr[r] = '0;
                    end
                end

                for (int c = 0; c < ARRAY_WIDTH; c++) begin
                    psum_bank_swap[c] = swap_mode[c];

                    if (hold_zero) begin
                        psum_read_addr[c] = '0;
                    end else if ((k >= c) && ((k-c) < 256)) begin
                        psum_read_addr[c] =
                            (PSUM_ADDR_WIDTH)'(k-c);
                    end else begin
                        psum_read_addr[c] = '0;
                    end

                    if ((k >= (9+c)) && ((k-(9+c)) < 256)) begin
                        psum_write_addr[c] =
                            (PSUM_ADDR_WIDTH)'(k-9-c);
                        psum_write_en[c] = 1'b1;
                    end else begin
                        psum_write_addr[c] = '0;
                        psum_write_en[c] = 1'b0;
                    end
                end
            end

            @(negedge clk_i);
            array_en      = 1'b0;
            psum_write_en = '0;

            compute_pass_count = compute_pass_count + 1;
            compute_active_cycles = compute_active_cycles +
                                    (total_cycles - start_cycle);
        end
    endtask

    task automatic drain_conv1x1(input int tile_y,
                                 input int tile_x,
                                 input int cout_block,
                                 input int bank_base);
        int y_base;
        int x_base;
        longint start_cycle;
        begin
            start_cycle = total_cycles;
            y_base = tile_y * 16;
            x_base = tile_x * 16;

            for (int m = 0; m < 256; m++) begin
                int y;
                int x;
                y = m / 16;
                x = m % 16;

                @(negedge clk_i);
                for (int c = 0; c < 8; c++) begin
                    ext_psum_addr[bank_base+c] =
                        (PSUM_ADDR_WIDTH)'(m);
                end

                @(posedge clk_i);
                #1;
                for (int c = 0; c < 8; c++) begin
                    actual_conv1[y_base+y][x_base+x]
                                [cout_block*8+c] =
                        ext_psum_rdata[bank_base+c];
                end
            end

            drain_cycles = drain_cycles + (total_cycles - start_cycle);
        end
    endtask

    // ---------------------------------------------------------------------
    // Same-instance 3x3 -> 1x1 YOLO regression
    // ---------------------------------------------------------------------
    initial begin : main_test
        clk_i            = 1'b0;
        rst_n            = 1'b0;
        array_en         = 1'b0;
        crossbar_sel     = '0;
        psum_bank_swap   = '0;
        psum_write_en    = '0;
        psum_read_addr   = '0;
        psum_write_addr  = '0;
        act_compute_addr = '0;
        ext_psum_we      = '0;
        ext_psum_addr    = '0;
        ext_psum_wdata   = '0;

        axil_awaddr  = '0;
        axil_awvalid = 1'b0;
        axil_wdata   = '0;
        axil_wstrb   = '0;
        axil_wvalid  = 1'b0;
        axil_bready  = 1'b1;
        axil_araddr  = '0;
        axil_arvalid = 1'b0;
        axil_rready  = 1'b1;

        dma_act_port_grant      = 1'b0;
        dma_weight_port_grant   = 1'b0;
        dma_current_source_base = 32'd0;
        dma_current_source_bytes = 0;
        dma_expected_high_half   = 1'b0;
        total_cycles            = 0;
        dma_act_cycles          = 0;
        weight_load_cycles      = 0;
        compute_active_cycles   = 0;
        drain_cycles            = 0;
        errors                  = 0;
        axi_write_count         = 0;
        dma_load_count          = 0;
        dma_total_groups        = 0;
        dma_total_zero_groups   = 0;
        dma_total_weight_groups = 0;
        dma_total_weight_bytes  = 0;
        dma_total_weight_swaps  = 0;
        dma_groups_this_load    = 0;
        dma_last_this_load      = 0;
        dma_swap_this_load      = 0;
        weight_load_count       = 0;
        compute_pass_count      = 0;
        reset_release_count     = 0;
        mode_transition_count   = 0;
        previous_conv_1x1       = 1'b0;

        errors_after_3x3          = 0;
        axi_writes_after_3x3      = 0;
        dma_loads_after_3x3       = 0;
        act_groups_after_3x3      = 0;
        zero_groups_after_3x3     = 0;
        weight_loads_after_3x3    = 0;
        weight_groups_after_3x3   = 0;
        weight_bytes_after_3x3    = 0;
        weight_swaps_after_3x3    = 0;
        compute_passes_after_3x3  = 0;

        if (!$value$plusargs("CONV3_IMAGE_MEM=%s", conv3_image_mem_path))
            conv3_image_mem_path = `YOLO_CONV3_IMAGE_MEM;
        if (!$value$plusargs("CONV3_WEIGHTS_MEM=%s",
                             conv3_weights_mem_path))
            conv3_weights_mem_path = `YOLO_CONV3_WEIGHTS_MEM;
        if (!$value$plusargs("CONV3_GOLDEN_MEM=%s", conv3_golden_mem_path))
            conv3_golden_mem_path = `YOLO_CONV3_GOLDEN_MEM;

        if (!$value$plusargs("CONV1_IMAGE_MEM=%s", conv1_image_mem_path))
            conv1_image_mem_path = `YOLO_CONV1_IMAGE_MEM;
        if (!$value$plusargs("CONV1_WEIGHTS_MEM=%s",
                             conv1_weights_mem_path))
            conv1_weights_mem_path = `YOLO_CONV1_WEIGHTS_MEM;
        if (!$value$plusargs("CONV1_GOLDEN_MEM=%s", conv1_golden_mem_path))
            conv1_golden_mem_path = `YOLO_CONV1_GOLDEN_MEM;

        $display("Loading 3x3 image   : %s", conv3_image_mem_path);
        $display("Loading 3x3 weights : %s", conv3_weights_mem_path);
        $display("Loading 3x3 golden  : %s", conv3_golden_mem_path);
        $readmemh(conv3_image_mem_path, raw_image_3x3_flat);
        $readmemh(conv3_weights_mem_path, raw_weights_3x3_flat);
        $readmemh(conv3_golden_mem_path, golden_conv3_flat);

        $display("Loading 1x1 image   : %s", conv1_image_mem_path);
        $display("Loading 1x1 weights : %s", conv1_weights_mem_path);
        $display("Loading 1x1 golden  : %s", conv1_golden_mem_path);
        $readmemh(conv1_image_mem_path, raw_image_1x1_flat);
        $readmemh(conv1_weights_mem_path, raw_weights_1x1_flat);
        $readmemh(conv1_golden_mem_path, golden_conv1_flat);

        // The only DUT reset release in the entire simulation.
        repeat (5) @(posedge clk_i);
        @(negedge clk_i);
        rst_n = 1'b1;

        // Static identity activation-bank-to-PE-row selection.
        for (int r = 0; r < ARRAY_HEIGHT; r++)
            crossbar_sel[r] = r[BANK_SEL_WIDTH-1:0];

        $display("===================================================================");
        $display(" PHASE 1: COMPLETE YOLO 3x3 LAYER ON SHARED DMA/NPU/SRAM");
        $display("===================================================================");

        for (int ty = 0; ty < 2; ty++) begin
            for (int tx = 0; tx < 2; tx++) begin
                $display("[%0t] 3x3 tile ty=%0d tx=%0d", $time, ty, tx);

                for (int cout_block = 0; cout_block < 2; cout_block++) begin
                    int pass_idx;
                    pass_idx = 0;
                    dma_init_bias_zero();

                    for (int cin_block = 0; cin_block < 2; cin_block++) begin
                        dma_load_3x3_activations(ty, tx, cin_block);

                        for (int ky = 0; ky < 3; ky++) begin
                            for (int kx = 0; kx < 3; kx++) begin
                                logic [7:0] swap_mode;
                                logic hold_zero;

                                swap_mode = (pass_idx == 0) ? 8'h00 :
                                            ((pass_idx % 2) ?
                                             8'hff : 8'h00);
                                hold_zero = (pass_idx == 0);

                                dma_load_3x3_weights_slice(
                                    ky, kx, cin_block, cout_block
                                );
                                run_conv3x3_pass(
                                    ky, kx, swap_mode, hold_zero
                                );
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
                    flat_index = (y * IMAGE_WIDTH * OUTPUT_CHANNELS) +
                                 (x * OUTPUT_CHANNELS) + co;
                    if (actual_conv3[y][x][co] !==
                        golden_conv3_flat[flat_index]) begin
                        if (errors < 20) begin
                            $display("ERROR 3x3 output y=%0d x=%0d co=%0d got=%08h expected=%08h",
                                     y, x, co, actual_conv3[y][x][co],
                                     golden_conv3_flat[flat_index]);
                        end
                        errors = errors + 1;
                    end
                end
            end
        end

        if (dma_load_count != EXPECTED_3X3_DMA_LOADS) begin
            $display("ERROR: 3x3 activation loads=%0d expected=%0d",
                     dma_load_count, EXPECTED_3X3_DMA_LOADS);
            errors = errors + 1;
        end
        if (dma_total_groups != EXPECTED_3X3_ACT_GROUPS) begin
            $display("ERROR: 3x3 activation groups=%0d expected=%0d",
                     dma_total_groups, EXPECTED_3X3_ACT_GROUPS);
            errors = errors + 1;
        end
        if (dma_total_zero_groups != EXPECTED_3X3_ZERO_GROUPS) begin
            $display("ERROR: 3x3 zero groups=%0d expected=%0d",
                     dma_total_zero_groups, EXPECTED_3X3_ZERO_GROUPS);
            errors = errors + 1;
        end
        if (weight_load_count != EXPECTED_3X3_WEIGHT_LOADS) begin
            $display("ERROR: 3x3 weight loads=%0d expected=%0d",
                     weight_load_count, EXPECTED_3X3_WEIGHT_LOADS);
            errors = errors + 1;
        end
        if (dma_total_weight_groups !=
            EXPECTED_3X3_WEIGHT_GROUPS) begin
            $display("ERROR: 3x3 weight groups=%0d expected=%0d",
                     dma_total_weight_groups,
                     EXPECTED_3X3_WEIGHT_GROUPS);
            errors = errors + 1;
        end
        if (dma_total_weight_bytes != EXPECTED_3X3_WEIGHT_BYTES) begin
            $display("ERROR: 3x3 weight bytes=%0d expected=%0d",
                     dma_total_weight_bytes, EXPECTED_3X3_WEIGHT_BYTES);
            errors = errors + 1;
        end
        if (dma_total_weight_swaps != EXPECTED_3X3_WEIGHT_LOADS) begin
            $display("ERROR: 3x3 weight swaps=%0d expected=%0d",
                     dma_total_weight_swaps, EXPECTED_3X3_WEIGHT_LOADS);
            errors = errors + 1;
        end
        if (compute_pass_count != EXPECTED_3X3_WEIGHT_LOADS) begin
            $display("ERROR: 3x3 compute passes=%0d expected=%0d",
                     compute_pass_count, EXPECTED_3X3_WEIGHT_LOADS);
            errors = errors + 1;
        end
        if (axi_write_count != EXPECTED_3X3_AXI_WRITES) begin
            $display("ERROR: 3x3 AXI writes=%0d expected=%0d",
                     axi_write_count, EXPECTED_3X3_AXI_WRITES);
            errors = errors + 1;
        end
        if (dma_status[9] !== 1'b0) begin
            $display("ERROR: DMA did not remain in 3x3 mode through phase 1");
            errors = errors + 1;
        end
        if (mode_transition_count != 0) begin
            $display("ERROR: observed %0d mode changes before phase boundary",
                     mode_transition_count);
            errors = errors + 1;
        end
        if (reset_release_count != 1) begin
            $display("ERROR: reset releases=%0d expected=1 after 3x3 phase",
                     reset_release_count);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PHASE PASS: all 16,384 golden YOLO 3x3 outputs match");
        end else begin
            $display("PHASE FAIL: 3x3 phase has %0d accumulated errors",
                     errors);
        end

        // Snapshot every aggregate counter.  The 1x1 phase is checked using
        // deltas, so it cannot pass by reusing the 3x3 phase's activity.
        errors_after_3x3         = errors;
        axi_writes_after_3x3     = axi_write_count;
        dma_loads_after_3x3      = dma_load_count;
        act_groups_after_3x3     = dma_total_groups;
        zero_groups_after_3x3    = dma_total_zero_groups;
        weight_loads_after_3x3   = weight_load_count;
        weight_groups_after_3x3  = dma_total_weight_groups;
        weight_bytes_after_3x3   = dma_total_weight_bytes;
        weight_swaps_after_3x3   = dma_total_weight_swaps;
        compute_passes_after_3x3 = compute_pass_count;

        // Explicit idle boundary.  This changes only testbench-owned controls;
        // rst_n stays high and both DUT instances retain their internal state.
        @(negedge clk_i);
        dma_act_port_grant    = 1'b0;
        dma_weight_port_grant = 1'b0;
        array_en         = 1'b0;
        psum_write_en    = '0;
        ext_psum_we      = '0;
        act_compute_addr = '0;

        if (dma_status[2] !== 1'b0) begin
            $display("ERROR: DMA busy at the 3x3-to-1x1 phase boundary");
            errors = errors + 1;
        end
        if (rst_n !== 1'b1) begin
            $display("ERROR: reset is not deasserted at the phase boundary");
            errors = errors + 1;
        end

        $display("===================================================================");
        $display(" LIVE TRANSITION: CPU WRITES AXI CONFIG BIT 9 FROM 0 TO 1");
        $display(" NO DMA, NPU, OR SRAM RESET IS ASSERTED");
        $display("===================================================================");

        $display("===================================================================");
        $display(" PHASE 2: COMPLETE YOLO 1x1 LAYER ON THE SAME LIVE INSTANCES");
        $display("===================================================================");

        for (int ty = 0; ty < 2; ty++) begin
            for (int tx = 0; tx < 2; tx++) begin
                $display("[%0t] 1x1 tile ty=%0d tx=%0d", $time, ty, tx);

                for (int cout_block = 0; cout_block < 2; cout_block++) begin
                    int pass_idx;
                    pass_idx = 0;
                    dma_init_bias_zero();

                    for (int cin_block = 0; cin_block < 2; cin_block++) begin
                        logic [7:0] swap_mode;
                        logic hold_zero;

                        swap_mode = (pass_idx == 0) ? 8'h00 :
                                    ((pass_idx % 2) ? 8'hff : 8'h00);
                        hold_zero = (pass_idx == 0);

                        dma_load_1x1_activations(ty, tx, cin_block);
                        dma_load_1x1_weights_slice(
                            cin_block, cout_block
                        );
                        run_conv1x1_pass(swap_mode, hold_zero);
                        pass_idx = pass_idx + 1;
                    end

                    drain_conv1x1(ty, tx, cout_block, 0);
                end
            end
        end

        for (int y = 0; y < IMAGE_HEIGHT; y++) begin
            for (int x = 0; x < IMAGE_WIDTH; x++) begin
                for (int co = 0; co < OUTPUT_CHANNELS; co++) begin
                    int flat_index;
                    flat_index = (y * IMAGE_WIDTH * OUTPUT_CHANNELS) +
                                 (x * OUTPUT_CHANNELS) + co;
                    if (actual_conv1[y][x][co] !==
                        golden_conv1_flat[flat_index]) begin
                        if ((errors - errors_after_3x3) < 20) begin
                            $display("ERROR 1x1 output y=%0d x=%0d co=%0d got=%08h expected=%08h",
                                     y, x, co, actual_conv1[y][x][co],
                                     golden_conv1_flat[flat_index]);
                        end
                        errors = errors + 1;
                    end
                end
            end
        end

        if ((dma_load_count - dma_loads_after_3x3) !=
            EXPECTED_1X1_DMA_LOADS) begin
            $display("ERROR: 1x1 activation loads=%0d expected=%0d",
                     dma_load_count - dma_loads_after_3x3,
                     EXPECTED_1X1_DMA_LOADS);
            errors = errors + 1;
        end
        if ((dma_total_groups - act_groups_after_3x3) !=
            EXPECTED_1X1_ACT_GROUPS) begin
            $display("ERROR: 1x1 activation groups=%0d expected=%0d",
                     dma_total_groups - act_groups_after_3x3,
                     EXPECTED_1X1_ACT_GROUPS);
            errors = errors + 1;
        end
        if ((dma_total_zero_groups - zero_groups_after_3x3) != 0) begin
            $display("ERROR: 1x1 zero groups=%0d expected=0",
                     dma_total_zero_groups - zero_groups_after_3x3);
            errors = errors + 1;
        end
        if ((weight_load_count - weight_loads_after_3x3) !=
            EXPECTED_1X1_WEIGHT_LOADS) begin
            $display("ERROR: 1x1 weight loads=%0d expected=%0d",
                     weight_load_count - weight_loads_after_3x3,
                     EXPECTED_1X1_WEIGHT_LOADS);
            errors = errors + 1;
        end
        if ((dma_total_weight_groups - weight_groups_after_3x3) !=
            EXPECTED_1X1_WEIGHT_GROUPS) begin
            $display("ERROR: 1x1 weight groups=%0d expected=%0d",
                     dma_total_weight_groups - weight_groups_after_3x3,
                     EXPECTED_1X1_WEIGHT_GROUPS);
            errors = errors + 1;
        end
        if ((dma_total_weight_bytes - weight_bytes_after_3x3) !=
            EXPECTED_1X1_WEIGHT_BYTES) begin
            $display("ERROR: 1x1 weight bytes=%0d expected=%0d",
                     dma_total_weight_bytes - weight_bytes_after_3x3,
                     EXPECTED_1X1_WEIGHT_BYTES);
            errors = errors + 1;
        end
        if ((dma_total_weight_swaps - weight_swaps_after_3x3) !=
            EXPECTED_1X1_WEIGHT_LOADS) begin
            $display("ERROR: 1x1 weight swaps=%0d expected=%0d",
                     dma_total_weight_swaps - weight_swaps_after_3x3,
                     EXPECTED_1X1_WEIGHT_LOADS);
            errors = errors + 1;
        end
        if ((compute_pass_count - compute_passes_after_3x3) !=
            EXPECTED_1X1_WEIGHT_LOADS) begin
            $display("ERROR: 1x1 compute passes=%0d expected=%0d",
                     compute_pass_count - compute_passes_after_3x3,
                     EXPECTED_1X1_WEIGHT_LOADS);
            errors = errors + 1;
        end
        if ((axi_write_count - axi_writes_after_3x3) !=
            EXPECTED_1X1_AXI_WRITES) begin
            $display("ERROR: 1x1 AXI writes=%0d expected=%0d",
                     axi_write_count - axi_writes_after_3x3,
                     EXPECTED_1X1_AXI_WRITES);
            errors = errors + 1;
        end

        if (dma_status[9] !== 1'b1) begin
            $display("ERROR: DMA is not in CPU-selected 1x1 mode at completion");
            errors = errors + 1;
        end
        if (mode_transition_count != 1) begin
            $display("ERROR: mode transitions=%0d expected exactly one 0-to-1 change",
                     mode_transition_count);
            errors = errors + 1;
        end
        if (reset_release_count != 1) begin
            $display("ERROR: reset releases=%0d expected exactly one",
                     reset_release_count);
            errors = errors + 1;
        end
        if (rst_n !== 1'b1) begin
            $display("ERROR: reset was not held deasserted through completion");
            errors = errors + 1;
        end

        if (dram_activation_bursts !=
            EXPECTED_3X3_ACT_BURSTS + EXPECTED_1X1_ACT_BURSTS) begin
            $display("ERROR: AXI activation bursts=%0d expected=%0d",
                     dram_activation_bursts,
                     EXPECTED_3X3_ACT_BURSTS + EXPECTED_1X1_ACT_BURSTS);
            errors = errors + 1;
        end
        if (dram_weight_bursts !=
            EXPECTED_3X3_WEIGHT_BURSTS + EXPECTED_1X1_WEIGHT_BURSTS) begin
            $display("ERROR: AXI weight bursts=%0d expected=%0d",
                     dram_weight_bursts,
                     EXPECTED_3X3_WEIGHT_BURSTS +
                     EXPECTED_1X1_WEIGHT_BURSTS);
            errors = errors + 1;
        end
        if (dram_read_beats !=
            34*EXPECTED_3X3_ACT_BURSTS +
            32*EXPECTED_1X1_ACT_BURSTS +
            16*(EXPECTED_3X3_WEIGHT_BURSTS +
                EXPECTED_1X1_WEIGHT_BURSTS)) begin
            $display("ERROR: AXI read beats=%0d expected=%0d",
                     dram_read_beats,
                     34*EXPECTED_3X3_ACT_BURSTS +
                     32*EXPECTED_1X1_ACT_BURSTS +
                     16*(EXPECTED_3X3_WEIGHT_BURSTS +
                         EXPECTED_1X1_WEIGHT_BURSTS));
            errors = errors + 1;
        end

        if (errors == errors_after_3x3) begin
            $display("PHASE PASS: all 16,384 golden YOLO 1x1 outputs match");
        end else begin
            $display("PHASE FAIL: 1x1 phase added %0d errors",
                     errors - errors_after_3x3);
        end

        $display("-------------------------------------------------------------------");
        $display("DUT reset releases          : %0d", reset_release_count);
        $display("DMA mode transitions        : %0d", mode_transition_count);
        $display("AXI-Lite writes, total      : %0d", axi_write_count);
        $display("DMA activation loads, total : %0d", dma_load_count);
        $display("DMA activation groups,total : %0d", dma_total_groups);
        $display("DMA zero-fill groups, total : %0d",
                 dma_total_zero_groups);
        $display("DMA weight loads, total     : %0d", weight_load_count);
        $display("DMA weight groups, total    : %0d",
                 dma_total_weight_groups);
        $display("DMA weight bytes, total     : %0d",
                 dma_total_weight_bytes);
        $display("DMA weight swaps, total     : %0d",
                 dma_total_weight_swaps);
        $display("AXI4 read bursts, total      : %0d", dram_read_bursts);
        $display("AXI4 read beats, total       : %0d", dram_read_beats);
        $display("NPU convolution passes,total: %0d", compute_pass_count);
        $display("Golden outputs checked      : %0d", 2 * OUTPUT_WORDS);
        $display("Total simulation cycles     : %0d", total_cycles);
        $display("-------------------------------------------------------------------");

        if (errors == 0) begin
            $display("PASS: complete 3x3 then 1x1 workloads ran on one DMA/NPU/SRAM instance without reset");
            $finish;
        end else begin
            $fatal(1,
                   "FAIL: same-instance sequential regression found %0d errors",
                   errors);
        end
    end

    initial begin : optional_waveform
        if ($value$plusargs("VCD=%s", vcd_path)) begin
            $dumpfile(vcd_path);
            $dumpvars(0, tb_npu_yolo_combined_sequential_integrated);
        end
    end

    initial begin : timeout_watchdog
        repeat (500000) @(posedge clk_i);
        $fatal(1, "FAIL: same-instance sequential DMA/NPU simulation timeout");
    end

endmodule

`default_nettype wire
