`timescale 1ns / 1ps
`default_nettype none

// Synthesizable integration of the packed-object DMA with the NPU SRAM wrapper.
//
// The module joins three independently understandable blocks:
//
//   dma_a
//     CPU-programmed, read-only DRAM DMA. Produces a 32-bit map stream.
//
//   dma_npu_sram_adapter
//     Converts accepted map beats into activation-bank writes or eight-lane
//     weight shifts, subject to controller ownership grants.
//
//   npu_sram_wrapper
//     Owns the activation, weight, and partial-sum memories used by the array.
//
// Platform logic should place this integration below its AXI endpoint/BEL
// wrappers and supply the controller/grant signals. The end-to-end read path is
// DRAM -> dma_a -> adapter -> activation SRAM or weight loader. PSUM ports pass
// directly between the platform/controller and npu_sram_wrapper; the DMA is not
// on that path. There are no AXI master write channels in this integration.
module combined_dma_npu_sram_top #(
    // Array/SRAM geometry. Defaults describe an 8x8 array, byte-wide
    // activations and weights, and 32-bit partial sums.
    parameter integer ARRAY_HEIGHT     = 8,
    parameter integer ARRAY_WIDTH      = 8,
    parameter integer TILE_SIZE        = 16,
    parameter integer ACT_HALO_PAD     = 2,
    parameter integer ACTIVATION_WIDTH = 8,
    parameter integer WEIGHT_WIDTH     = 8,
    parameter integer PSUM_WIDTH       = 32,
    // Activation storage includes ACT_HALO_PAD copies of a TILE_SIZE^2 region.
    parameter integer ACT_WORDS        =
        (TILE_SIZE * TILE_SIZE) * ACT_HALO_PAD,
    parameter integer PSUM_WORDS       = TILE_SIZE * TILE_SIZE,
    parameter integer ACT_ADDR_WIDTH   = $clog2(ACT_WORDS),
    parameter integer PSUM_ADDR_WIDTH  = $clog2(PSUM_WORDS),
    parameter integer BANK_SEL_WIDTH   = $clog2(ARRAY_HEIGHT),
    parameter integer NUM_PSUM_BANKS   = ARRAY_WIDTH * 2,
    // Set to one only when a simulation/debug monitor inspects source metadata.
    // The SRAM adapter does not use these fields; zero removes their adder.
    parameter integer DMA_MAP_SOURCE_METADATA = 0
)(
    input  wire clk_i,
    input  wire rst_n,

    // Compact status/debug word exported by dma_a.
    output wire [31:0] dma_status_o,

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

    // DRAM-facing read-only AXI4 master. The integration initiates reads only.
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

    // DMA/NPU port arbitration. The controller must grant activation ports for
    // activation loads or the weight port for weight loads, and retain that
    // grant through completion. array_en below independently blocks DMA access.
    input  wire dma_act_port_grant_i,
    input  wire dma_weight_port_grant_i,

    // NPU compute-controller interface. These signals control the systolic
    // array, input crossbar, and ping-pong partial-sum banks; they bypass dma_a.
    input  wire array_en,
    input  wire [ARRAY_HEIGHT-1:0][BANK_SEL_WIDTH-1:0] crossbar_sel,
    input  wire [ARRAY_WIDTH-1:0] psum_bank_swap,
    input  wire [ARRAY_WIDTH-1:0] psum_write_en,
    input  wire [ARRAY_WIDTH-1:0][PSUM_ADDR_WIDTH-1:0]
                                                psum_read_addr,
    input  wire [ARRAY_WIDTH-1:0][PSUM_ADDR_WIDTH-1:0]
                                                psum_write_addr,
    input  wire [ARRAY_HEIGHT-1:0][ACT_ADDR_WIDTH-1:0]
                                                act_compute_addr,

    // External PSUM access passes straight to npu_sram_wrapper. In particular,
    // this top does not serialize completed sums or send them back to DRAM.
    input  wire [NUM_PSUM_BANKS-1:0] ext_psum_we,
    input  wire [NUM_PSUM_BANKS-1:0][PSUM_ADDR_WIDTH-1:0]
                                                ext_psum_addr,
    input  wire [NUM_PSUM_BANKS-1:0][PSUM_WIDTH-1:0]
                                                ext_psum_wdata,
    output wire [NUM_PSUM_BANKS-1:0][PSUM_WIDTH-1:0]
                                                ext_psum_rdata,
    output wire [ARRAY_HEIGHT-1:0][ACTIVATION_WIDTH-1:0]
                                                act_sram_rdata,

    // Read-only visibility of the internal map stream for debug/verification.
    // These outputs tap the same nets consumed by the adapter and add no second
    // data path. map_source_* are zero when metadata is disabled.
    output wire        map_valid_o,
    output wire        map_ready_o,
    output wire [31:0] map_data_o,
    output wire [31:0] map_source_addr_o,
    output wire [4:0]  map_source_stride_o,
    output wire [ACT_ADDR_WIDTH-1:0] map_buffer_addr_o,
    output wire [ARRAY_HEIGHT-1:0] map_bank_mask_o,
    output wire        map_is_weight_o,
    output wire        map_zero_fill_o,
    output wire        map_last_o,
    output wire        map_weight_swap_o
);

    // Private adapter-to-SRAM wiring. Activation ports are byte-wide and
    // banked; the weight interface shifts all ARRAY_HEIGHT lanes together.
    wire [ARRAY_HEIGHT-1:0] ext_act_sram_we;
    wire [ARRAY_HEIGHT-1:0][ACT_ADDR_WIDTH-1:0] ext_act_sram_addr;
    wire [ARRAY_HEIGHT-1:0][ACTIVATION_WIDTH-1:0]
                                                ext_act_sram_wdata;
    wire [ARRAY_HEIGHT-1:0][WEIGHT_WIDTH-1:0] weight_shift_in;
    wire weight_shift_en;
    wire swap_weights;

    // Read DMA: AXI-Lite control, packed-object AGU, AXI read engine, and map
    // formatter. The public map outputs are also the adapter inputs below.
    dma_a #(
        .MAP_SOURCE_METADATA (DMA_MAP_SOURCE_METADATA)
    ) dma_i (
        .clk               (clk_i),
        .rstn              (rst_n),
        .O_top             (dma_status_o),
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
        .m_axi_araddr      (m_axi_araddr),
        .m_axi_arlen       (m_axi_arlen),
        .m_axi_arsize      (m_axi_arsize),
        .m_axi_arburst     (m_axi_arburst),
        .m_axi_arvalid     (m_axi_arvalid),
        .m_axi_arready     (m_axi_arready),
        .m_axi_rdata       (m_axi_rdata),
        .m_axi_rresp       (m_axi_rresp),
        .m_axi_rlast       (m_axi_rlast),
        .m_axi_rvalid      (m_axi_rvalid),
        .m_axi_rready      (m_axi_rready),
        .map_valid         (map_valid_o),
        .map_ready         (map_ready_o),
        .map_data          (map_data_o),
        .map_source_addr   (map_source_addr_o),
        .map_source_stride (map_source_stride_o),
        .map_buffer_addr   (map_buffer_addr_o),
        .map_bank_mask     (map_bank_mask_o),
        .map_is_weight     (map_is_weight_o),
        .map_zero_fill     (map_zero_fill_o),
        .map_last          (map_last_o),
        .map_weight_swap   (map_weight_swap_o)
    );

    // SRAM adapter: enforces ownership, steers four map bytes to the selected
    // bank half, and joins two weight beats into one eight-lane shift.
    dma_npu_sram_adapter #(
        .NUM_ACT_BANKS    (ARRAY_HEIGHT),
        .ACT_ADDR_WIDTH   (ACT_ADDR_WIDTH),
        .ACTIVATION_WIDTH (ACTIVATION_WIDTH),
        .WEIGHT_WIDTH     (WEIGHT_WIDTH)
    ) adapter_i (
        .clk_i                    (clk_i),
        .rst_n                    (rst_n),
        .dma_act_port_grant_i    (dma_act_port_grant_i),
        .dma_weight_port_grant_i (dma_weight_port_grant_i),
        .array_active_i          (array_en),
        .map_valid_i             (map_valid_o),
        .map_ready_o             (map_ready_o),
        .map_data_i              (map_data_o),
        .map_buffer_addr_i       (map_buffer_addr_o),
        .map_bank_mask_i         (map_bank_mask_o),
        .map_is_weight_i         (map_is_weight_o),
        .map_weight_swap_i       (map_weight_swap_o),
        .act_compute_addr_i      (act_compute_addr),
        .ext_act_sram_we_o       (ext_act_sram_we),
        .ext_act_sram_addr_o     (ext_act_sram_addr),
        .ext_act_sram_wdata_o    (ext_act_sram_wdata),
        .weight_shift_in_o       (weight_shift_in),
        .weight_shift_en_o       (weight_shift_en),
        .swap_weights_o          (swap_weights)
    );

    // NPU memory subsystem. DMA-generated activation/weight signals enter here;
    // compute-control and PSUM signals retain their direct controller paths.
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

endmodule

`default_nettype wire
