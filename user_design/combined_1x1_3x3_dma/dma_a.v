`timescale 1ns / 1ps
`default_nettype none

// Top-level hierarchy and interconnect for the packed-object read DMA.
//
// Data/control flow:
//
//   CPU AXI4-Lite
//        |
//        v
//   dma_axil_control  -- start/config --> combined_hwc_channel_dma_agu
//                                              |
//                                      row/slice descriptor
//                                              v
//                                       dma_fetch_engine
//                             planner and formatter submodules:
//                         dma_axi_burst_planner    dma_map_datapath
//                                       AXI read + map stream
//
// The control block validates software requests. The AGU expands one accepted
// request into row-level descriptors. The fetch engine executes each descriptor
// through the read-only AXI4 master and converts returned 32-bit words into a
// ready/valid stream for the NPU SRAM adapter.
//
// Scope of this module:
//   * reads packed activation tiles or one packed weight slice from DRAM;
//   * generates 3x3 edge padding locally; and
//   * emits four byte lanes per accepted map beat.
//
// It has no AXI AW/W/B master channels, so it does not write results to DRAM.
// It also does not touch PSUM SRAMs; those ports are outside dma_a.
//
// AXI4-Lite register map:
//   0x00 W: merge byte strobes into the packed-object pointer and start
//   0x00 R: last accepted packed-object pointer
//   0x04 R: status {29'b0, error_sticky, busy, done_sticky}
//   0x08 W/R configuration:
//          [0]   tile_x
//          [1]   tile_y
//          [2]   cin_block       (object selection; no hardware pointer offset)
//          [3]   load_weight
//          [4]   cout_block      (object selection; no hardware pointer offset)
//          [6:5] kernel_y        (selection/validation; no pointer offset)
//          [8:7] kernel_x        (selection/validation; no pointer offset)
//          [9]   conv_1x1 (0: 3x3, 1: 1x1)
//
// Writing the pointer is the start command, not merely a register update. The
// configuration register must therefore be programmed first. The pointer must
// already identify the exact packed object selected by the configuration.
module dma_a #(
    // Source-address/stride outputs are verification metadata only. Disable
    // them in the FPGA build to remove their descriptor copy and per-beat
    // address adder; enable them when a monitor needs to trace source words.
    parameter integer MAP_SOURCE_METADATA = 0
)(
    input  wire        clk,
    input  wire        rstn,

    // Fabric-visible status/debug summary described near the end of the module.
    output wire [31:0] O_top,

    // CPU-facing AXI4-Lite slave.
    input  wire [9:0]  axil_awaddr,
    input  wire        axil_awvalid,
    output wire        axil_awready,
    input  wire [31:0] axil_wdata,
    input  wire [3:0]  axil_wstrb,
    input  wire        axil_wvalid,
    output wire        axil_wready,
    output wire [1:0]  axil_bresp,
    output wire        axil_bvalid,
    input  wire        axil_bready,
    input  wire [9:0]  axil_araddr,
    input  wire        axil_arvalid,
    output wire        axil_arready,
    output wire [31:0] axil_rdata,
    output wire [1:0]  axil_rresp,
    output wire        axil_rvalid,
    input  wire        axil_rready,

    // DRAM-facing read-only AXI4 master. AR carries requests and R returns
    // words; write-address, write-data, and write-response channels are absent.
    output wire [31:0] m_axi_araddr,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready,

    // Four-byte destination stream. A ready/valid handshake transfers a word.
    // map_bank_mask is 8'h0f on the first beat of a group and 8'hf0 on the
    // second. Byte lane n maps to bank n for the low half and bank n+4 for the
    // high half. Both beats use the same map_buffer_addr.
    output wire        map_valid,
    input  wire        map_ready,
    output wire [31:0] map_data,
    output wire [31:0] map_source_addr,
    output wire [4:0]  map_source_stride,
    output wire [8:0]  map_buffer_addr,
    output wire [7:0]  map_bank_mask,
    output wire        map_is_weight,
    output wire        map_zero_fill,
    output wire        map_last,
    output wire        map_weight_swap
);

    // Accepted programming state. source_base changes only when a valid start
    // write is accepted; config_bits changes only on a legal config write.
    wire [31:0] source_base;
    wire [9:0]  config_bits;
    wire        start_pulse;
    wire        done_sticky;
    wire        error_sticky;

    // AGU execution and descriptor stream. agu_load_ready is a descriptor-
    // completion event from the fetch engine, not an immediate capture-ready
    // signal, so the AGU holds all descriptor fields throughout execution.
    wire        agu_start_ready;
    wire        agu_busy;
    wire        agu_done;
    wire        agu_load_valid;
    wire        agu_load_ready;
    wire [31:0] agu_source_addr;
    wire [4:0]  agu_source_stride;
    wire [8:0]  agu_buffer_addr;
    wire [7:0]  agu_bank_mask;
    wire [5:0]  agu_group_count;
    wire        agu_pad_before;
    wire        agu_pad_after;
    wire        agu_is_weight;
    wire        agu_zero_fill;
    wire        agu_last;
    wire        agu_weight_swap;

    // One-cycle execution/error observations returned to the control block.
    wire        axi_read_error_pulse;
    wire        fetch_active;

    // CPU programming front end. It decouples independent AXI-Lite AW/W
    // channels, implements the register map, and produces a one-cycle start.
    dma_axil_control axil_control_i (
        .clk                 (clk),
        .rstn                (rstn),
        .axil_awaddr         (axil_awaddr),
        .axil_awvalid        (axil_awvalid),
        .axil_awready        (axil_awready),
        .axil_wdata          (axil_wdata),
        .axil_wstrb          (axil_wstrb),
        .axil_wvalid         (axil_wvalid),
        .axil_wready         (axil_wready),
        .axil_bresp          (axil_bresp),
        .axil_bvalid         (axil_bvalid),
        .axil_bready         (axil_bready),
        .axil_araddr         (axil_araddr),
        .axil_arvalid        (axil_arvalid),
        .axil_arready        (axil_arready),
        .axil_rdata          (axil_rdata),
        .axil_rresp          (axil_rresp),
        .axil_rvalid         (axil_rvalid),
        .axil_rready         (axil_rready),
        .start_ready_i       (agu_start_ready),
        .busy_i              (agu_busy),
        .done_pulse_i        (agu_done),
        .read_error_pulse_i  (axi_read_error_pulse),
        .source_base_o       (source_base),
        .config_o            (config_bits),
        .start_pulse_o       (start_pulse),
        .done_sticky_o       (done_sticky),
        .error_sticky_o      (error_sticky)
    );

    // Schedule generator. image_base_i and weight_base_i share the one pointer
    // register; config_bits[3] determines which interpretation is active.
    combined_hwc_channel_dma_agu #(
        .SRC_ADDR_WIDTH(32),
        .ACT_ADDR_WIDTH(9)
    ) agu_i (
        .clk_i                  (clk),
        .rst_n                  (rstn),
        .start_i                (start_pulse),
        .start_ready_o          (agu_start_ready),
        .conv_1x1_i             (config_bits[9]),
        .load_weight_i          (config_bits[3]),
        .image_base_i           (source_base),
        .weight_base_i          (source_base),
        .tile_y_i               (config_bits[1]),
        .tile_x_i               (config_bits[0]),
        .cin_block_i            (config_bits[2]),
        .cout_block_i           (config_bits[4]),
        .kernel_y_i             (config_bits[6:5]),
        .kernel_x_i             (config_bits[8:7]),
        .busy_o                 (agu_busy),
        .done_o                 (agu_done),
        .load_valid_o           (agu_load_valid),
        .load_ready_i           (agu_load_ready),
        .load_src_addr_o        (agu_source_addr),
        .load_src_lane_stride_o (agu_source_stride),
        .load_dst_addr_o        (agu_buffer_addr),
        .load_dst_bank_mask_o   (agu_bank_mask),
        .load_group_count_o     (agu_group_count),
        .load_pad_before_o      (agu_pad_before),
        .load_pad_after_o       (agu_pad_after),
        .load_is_weight_o       (agu_is_weight),
        .load_zero_fill_o       (agu_zero_fill),
        .load_last_o            (agu_last),
        .weight_swap_o          (agu_weight_swap)
    );

    // Descriptor executor. This is the only child that drives the DRAM master
    // and map-stream interfaces. Downstream map backpressure reaches AXI RREADY.
    dma_fetch_engine #(
        .MAP_SOURCE_METADATA (MAP_SOURCE_METADATA)
    ) fetch_engine_i (
        .clk                  (clk),
        .rstn                 (rstn),
        .load_valid_i         (agu_load_valid),
        .load_ready_o         (agu_load_ready),
        .load_source_addr_i   (agu_source_addr),
        .load_source_stride_i (agu_source_stride),
        .load_buffer_addr_i   (agu_buffer_addr),
        .load_bank_mask_i     (agu_bank_mask),
        .load_group_count_i   (agu_group_count),
        .load_pad_before_i    (agu_pad_before),
        .load_pad_after_i     (agu_pad_after),
        .load_is_weight_i     (agu_is_weight),
        .load_zero_fill_i     (agu_zero_fill),
        .load_last_i          (agu_last),
        .weight_swap_i        (agu_weight_swap),
        .m_axi_araddr         (m_axi_araddr),
        .m_axi_arlen          (m_axi_arlen),
        .m_axi_arsize         (m_axi_arsize),
        .m_axi_arburst        (m_axi_arburst),
        .m_axi_arvalid        (m_axi_arvalid),
        .m_axi_arready        (m_axi_arready),
        .m_axi_rdata          (m_axi_rdata),
        .m_axi_rresp          (m_axi_rresp),
        .m_axi_rlast          (m_axi_rlast),
        .m_axi_rvalid         (m_axi_rvalid),
        .m_axi_rready         (m_axi_rready),
        .map_valid            (map_valid),
        .map_ready            (map_ready),
        .map_data             (map_data),
        .map_source_addr      (map_source_addr),
        .map_source_stride    (map_source_stride),
        .map_buffer_addr      (map_buffer_addr),
        .map_bank_mask        (map_bank_mask),
        .map_is_weight        (map_is_weight),
        .map_zero_fill        (map_zero_fill),
        .map_last             (map_last),
        .map_weight_swap      (map_weight_swap),
        .read_error_pulse_o   (axi_read_error_pulse),
        .fetch_active_o       (fetch_active)
    );

    // Fabric-visible debug/status word. These are observations only and do not
    // control the DMA:
    //
    //   [0]     constant design-alive marker
    //   [1]     sticky completion status
    //   [2]     AGU busy
    //   [3]     sticky programming/read error
    //   [4]     map beat available
    //   [5]     current map beat is locally generated zero padding
    //   [6]     current map beat is final for the operation
    //   [7]     current map beat targets the weight loader
    //   [8]     weight-bank swap pulse
    //   [9]     configured convolution mode (1=1x1, 0=3x3)
    //   [10]    AXI read-address request valid
    //   [11]    AXI read-data handshake
    //   [12]    fetch engine active
    //   [31:13] zero
    assign O_top[0]     = 1'b1;
    assign O_top[1]     = done_sticky;
    assign O_top[2]     = agu_busy;
    assign O_top[3]     = error_sticky;
    assign O_top[4]     = map_valid;
    assign O_top[5]     = map_zero_fill;
    assign O_top[6]     = map_last;
    assign O_top[7]     = map_is_weight;
    assign O_top[8]     = map_weight_swap;
    assign O_top[9]     = config_bits[9];
    assign O_top[10]    = m_axi_arvalid;
    assign O_top[11]    = m_axi_rvalid && m_axi_rready;
    assign O_top[12]    = fetch_active;
    assign O_top[31:13] = 19'd0;

endmodule

`default_nettype wire
