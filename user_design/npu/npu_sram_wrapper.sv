module npu_sram_wrapper #(
    parameter int ARRAY_HEIGHT     = 8,
    parameter int ARRAY_WIDTH      = 8,
    parameter int TILE_SIZE        = 16,
    parameter int ACT_HALO_PAD     = 2,                                      // Factor for activation depth
    parameter int ACTIVATION_WIDTH = 8,
    parameter int WEIGHT_WIDTH     = 8,
    parameter int PSUM_WIDTH       = 32,
    
    localparam int PSUM_WORDS      = TILE_SIZE * TILE_SIZE,                  // 256 words
    localparam int ACT_WORDS       = (TILE_SIZE * TILE_SIZE) * ACT_HALO_PAD, // 512 words
    localparam int PSUM_ADDR_WIDTH = $clog2(PSUM_WORDS),                     // 8 bits
    localparam int ACT_ADDR_WIDTH  = $clog2(ACT_WORDS),                      // 9 bits
    localparam int NUM_ACT_BANKS   = ARRAY_HEIGHT,                           // 8
    localparam int NUM_PSUM_BANKS  = ARRAY_WIDTH * 2,                        // 16
    localparam int BANK_SEL_WIDTH  = $clog2(ARRAY_HEIGHT)                    // 3
)(
    input  wire                                                        clk_i,
    input  wire                                                        rst_n,
    input  wire                                                        array_en,

    input  wire [ARRAY_HEIGHT-1:0][BANK_SEL_WIDTH-1:0]                 crossbar_sel,
    input  wire [ARRAY_WIDTH-1:0]                                      psum_bank_swap,  // Decoupled per column
    input  wire [ARRAY_WIDTH-1:0]                                      psum_write_en,   // Decoupled per column
    input  wire [ARRAY_WIDTH-1:0][PSUM_ADDR_WIDTH-1:0]                 psum_read_addr,  // Decoupled per column
    input  wire [ARRAY_WIDTH-1:0][PSUM_ADDR_WIDTH-1:0]                 psum_write_addr, // Decoupled per column

    input  wire [ARRAY_HEIGHT-1:0][WEIGHT_WIDTH-1:0]                    weight_shift_in,
    input  wire                                                        weight_shift_en,
    input  wire                                                        swap_weights,

    // RAW EXPOSED ACTIVATION SRAM INTERFACES (512 words, 9 bits)
    input  wire [NUM_ACT_BANKS-1:0]                                    ext_act_sram_we,
    input  wire [NUM_ACT_BANKS-1:0][ACT_ADDR_WIDTH-1:0]                 ext_act_sram_addr,
    input  wire [NUM_ACT_BANKS-1:0][ACTIVATION_WIDTH-1:0]              ext_act_sram_wdata,
    output wire [NUM_ACT_BANKS-1:0][ACTIVATION_WIDTH-1:0]              act_sram_rdata,

    // RAW EXPOSED FULL 16-BANK PSUM SRAM INTERFACES (256 words, 8 bits)
    input  wire [NUM_PSUM_BANKS-1:0]                                   ext_psum_we,
    input  wire [NUM_PSUM_BANKS-1:0][PSUM_ADDR_WIDTH-1:0]              ext_psum_addr,
    input  wire [NUM_PSUM_BANKS-1:0][PSUM_WIDTH-1:0]                   ext_psum_wdata,
    output wire [NUM_PSUM_BANKS-1:0][PSUM_WIDTH-1:0]                   ext_psum_rdata
);

    wire [NUM_PSUM_BANKS-1:0]                       npu_psum_we;
    wire [NUM_PSUM_BANKS-1:0][PSUM_ADDR_WIDTH-1:0] npu_psum_addr;
    wire [NUM_PSUM_BANKS-1:0][PSUM_WIDTH-1:0]       npu_psum_wdata;
    wire [NUM_PSUM_BANKS-1:0][PSUM_WIDTH-1:0]       psum_sram_rdata;

    // Instantiate Logic Core
    npu_top #(
        .ARRAY_HEIGHT     (ARRAY_HEIGHT),
        .ARRAY_WIDTH      (ARRAY_WIDTH),
        .TILE_SIZE        (TILE_SIZE),
        .ACT_HALO_PAD     (ACT_HALO_PAD),
        .ACTIVATION_WIDTH (ACTIVATION_WIDTH),
        .WEIGHT_WIDTH     (WEIGHT_WIDTH),
        .PSUM_WIDTH       (PSUM_WIDTH)
    ) npu_logic_core (
        .clk_i           (clk_i),
        .rst_n           (rst_n),
        .array_en        (array_en),
        .crossbar_sel    (crossbar_sel),
        .psum_bank_swap  (psum_bank_swap),
        .psum_write_en   (psum_write_en),
        .psum_read_addr  (psum_read_addr),
        .psum_write_addr (psum_write_addr),
        .weight_shift_in (weight_shift_in),
        .weight_shift_en (weight_shift_en),
        .swap_weights    (swap_weights),
        .act_sram_rdata  (act_sram_rdata),
        .psum_sram_rdata (psum_sram_rdata),
        .psum_sram_we    (npu_psum_we),
        .psum_sram_addr  (npu_psum_addr),
        .psum_sram_wdata (npu_psum_wdata),
        .ext_psum_we     (ext_psum_we),
        .ext_psum_addr   (ext_psum_addr),
        .ext_psum_wdata  (ext_psum_wdata),
        .ext_psum_rdata  (ext_psum_rdata)
    );

    // 8 Activation SRAM Banks (512 words x 8-bit)
    genvar i;
    generate
        for (i = 0; i < NUM_ACT_BANKS; i++) begin : gen_act_srams
            sram_bank #(
                .DATA_WIDTH(ACTIVATION_WIDTH),
                .DEPTH     (ACT_WORDS)
            ) act_sram_inst (
                .clk_i(clk_i),
                .we   (ext_act_sram_we[i]),
                .addr (ext_act_sram_addr[i]),
                .wdata(ext_act_sram_wdata[i]),
                .rdata(act_sram_rdata[i])
            );
        end
    endgenerate

    // 16 Partial Sum SRAM Banks (Strictly 256 words x 32-bit)
    generate
        for (i = 0; i < NUM_PSUM_BANKS; i++) begin : gen_psum_srams
            sram_bank #(
                .DATA_WIDTH(PSUM_WIDTH),
                .DEPTH     (PSUM_WORDS)
            ) psum_sram_inst (
                .clk_i(clk_i),
                .we   (npu_psum_we[i]),
                .addr (npu_psum_addr[i]),
                .wdata(npu_psum_wdata[i]),
                .rdata(psum_sram_rdata[i])
            );
        end
    endgenerate

endmodule