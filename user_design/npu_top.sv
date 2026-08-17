module npu_top #(
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

    // Control Signals from AGU (Decoupled per Column)
    input  wire [ARRAY_HEIGHT-1:0][BANK_SEL_WIDTH-1:0]                 crossbar_sel,
    input  wire [ARRAY_WIDTH-1:0]                                      psum_bank_swap, // Per-column ping-pong selector
    input  wire [ARRAY_WIDTH-1:0]                                      psum_write_en,  // Per-column write enable
    input  wire [ARRAY_WIDTH-1:0][PSUM_ADDR_WIDTH-1:0]                 psum_read_addr,  // Per-column read address
    input  wire [ARRAY_WIDTH-1:0][PSUM_ADDR_WIDTH-1:0]                 psum_write_addr, // Per-column write address

    // Horizontal Weight Control Interface (Left-to-Right)
    input  wire [ARRAY_HEIGHT-1:0][WEIGHT_WIDTH-1:0]                    weight_shift_in,
    input  wire                                                        weight_shift_en,
    input  wire                                                        swap_weights,

    // Raw SRAM Interfaces (to Physical Macros)
    input  wire [NUM_ACT_BANKS-1:0][ACTIVATION_WIDTH-1:0]              act_sram_rdata,

    input  wire [NUM_PSUM_BANKS-1:0][PSUM_WIDTH-1:0]                   psum_sram_rdata,
    output logic [NUM_PSUM_BANKS-1:0]                                  psum_sram_we,
    output logic [NUM_PSUM_BANKS-1:0][PSUM_ADDR_WIDTH-1:0]             psum_sram_addr,
    output logic [NUM_PSUM_BANKS-1:0][PSUM_WIDTH-1:0]                  psum_sram_wdata,

    // FULL 16-BANK EXTERNAL FABRIC INTERFACE
    input  wire [NUM_PSUM_BANKS-1:0]                                   ext_psum_we,
    input  wire [NUM_PSUM_BANKS-1:0][PSUM_ADDR_WIDTH-1:0]              ext_psum_addr,
    input  wire [NUM_PSUM_BANKS-1:0][PSUM_WIDTH-1:0]                   ext_psum_wdata,
    output wire [NUM_PSUM_BANKS-1:0][PSUM_WIDTH-1:0]                   ext_psum_rdata
);

    // Internal Signals
    wire  [ARRAY_HEIGHT-1:0][ACTIVATION_WIDTH-1:0] xbar_out;
    logic [ARRAY_WIDTH-1:0][PSUM_WIDTH-1:0]        array_psum_in;
    wire  [ARRAY_WIDTH-1:0][PSUM_WIDTH-1:0]        array_psum_out;

    // Crossbar Instantiation
    npu_crossbar #(
        .ARRAY_HEIGHT    (ARRAY_HEIGHT),
        .ACTIVATION_WIDTH(ACTIVATION_WIDTH)
    ) xbar_inst (
        .in_data     (act_sram_rdata),
        .crossbar_sel(crossbar_sel),
        .out_data    (xbar_out)
    );

    // Systolic Array Instantiation
    systolic_array #(
        .ARRAY_HEIGHT    (ARRAY_HEIGHT),
        .ARRAY_WIDTH     (ARRAY_WIDTH),
        .ACTIVATION_WIDTH(ACTIVATION_WIDTH),
        .WEIGHT_WIDTH    (WEIGHT_WIDTH),
        .PSUM_WIDTH      (PSUM_WIDTH)
    ) array_inst (
        .clk_i           (clk_i),
        .rst_n           (rst_n),
        .array_en        (array_en),
        .act_in          (xbar_out),
        .psum_in         (array_psum_in),
        .psum_out        (array_psum_out),
        .weight_shift_in (weight_shift_in),
        .weight_shift_en (weight_shift_en),
        .swap_weights    (swap_weights)
    );

    // Raw read access for fabric across all 16 banks
    assign ext_psum_rdata = psum_sram_rdata;

    // Per-Column Decoupled Bank Arbitration
    always_comb begin
        for (int c = 0; c < ARRAY_WIDTH; c++) begin
            int bank_a;
            int bank_b;

            // Assign on every combinational evaluation.  Declaration-time
            // initialization gives these block variables static lifetime in
            // Icarus and can leave every column selecting banks 0 and 8.
            bank_a = c;
            bank_b = c + ARRAY_WIDTH;

            // 1. Array PSum In Routing
            array_psum_in[c] = (!psum_bank_swap[c]) ? psum_sram_rdata[bank_a]
                                                    : psum_sram_rdata[bank_b];

            // 2. Local Bank Arbitration (Bank A vs Bank B)
            if (!psum_bank_swap[c]) begin
                // Swap = 0: Bank A is READ, Bank B is WRITE
                if (array_en) begin
                    // Bank A (Read)
                    psum_sram_addr[bank_a]  = psum_read_addr[c];
                    psum_sram_we[bank_a]    = 1'b0;
                    psum_sram_wdata[bank_a] = ext_psum_wdata[bank_a];

                    // Bank B (Write)
                    psum_sram_addr[bank_b]  = psum_write_addr[c];
                    psum_sram_we[bank_b]    = psum_write_en[c];
                    psum_sram_wdata[bank_b] = array_psum_out[c];
                end else begin
                    // Idle: Fabric Access
                    psum_sram_addr[bank_a]  = ext_psum_addr[bank_a];
                    psum_sram_we[bank_a]    = ext_psum_we[bank_a];
                    psum_sram_wdata[bank_a] = ext_psum_wdata[bank_a];

                    psum_sram_addr[bank_b]  = ext_psum_addr[bank_b];
                    psum_sram_we[bank_b]    = ext_psum_we[bank_b];
                    psum_sram_wdata[bank_b] = ext_psum_wdata[bank_b];
                end
            end else begin
                // Swap = 1: Bank B is READ, Bank A is WRITE
                if (array_en) begin
                    // Bank B (Read)
                    psum_sram_addr[bank_b]  = psum_read_addr[c];
                    psum_sram_we[bank_b]    = 1'b0;
                    psum_sram_wdata[bank_b] = ext_psum_wdata[bank_b];

                    // Bank A (Write)
                    psum_sram_addr[bank_a]  = psum_write_addr[c];
                    psum_sram_we[bank_a]    = psum_write_en[c];
                    psum_sram_wdata[bank_a] = array_psum_out[c];
                end else begin
                    // Idle: Fabric Access
                    psum_sram_addr[bank_a]  = ext_psum_addr[bank_a];
                    psum_sram_we[bank_a]    = ext_psum_we[bank_a];
                    psum_sram_wdata[bank_a] = ext_psum_wdata[bank_a];

                    psum_sram_addr[bank_b]  = ext_psum_addr[bank_b];
                    psum_sram_we[bank_b]    = ext_psum_we[bank_b];
                    psum_sram_wdata[bank_b] = ext_psum_wdata[bank_b];
                end
            end
        end
    end

endmodule
