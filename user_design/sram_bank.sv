module sram_bank #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 512,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
)(
    input  wire                  clk_i,
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [DATA_WIDTH-1:0] wdata,
    output reg  [DATA_WIDTH-1:0] rdata
);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk_i) begin
        if (we) begin
            mem[addr] <= wdata;
        end
        rdata <= mem[addr];
    end

endmodule