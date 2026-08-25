module systolic_array #(
    parameter int ARRAY_HEIGHT     = 8,
    parameter int ARRAY_WIDTH      = 8,
    parameter int ACTIVATION_WIDTH = 8,
    parameter int WEIGHT_WIDTH     = 8,
    parameter int PSUM_WIDTH       = 32
)(
    input  wire                                                 clk_i,
    input  wire                                                 rst_n,
    input  wire                                                 array_en,
    
    // Compute Data Stream
    input  wire [ARRAY_HEIGHT-1:0][ACTIVATION_WIDTH-1:0]        act_in,
    input  wire [ARRAY_WIDTH-1:0][PSUM_WIDTH-1:0]               psum_in,
    output wire [ARRAY_WIDTH-1:0][PSUM_WIDTH-1:0]               psum_out,
    
    // Horizontal Weight Control (1 chain per ROW, shifts left to right)
    input  wire [ARRAY_HEIGHT-1:0][WEIGHT_WIDTH-1:0]            weight_shift_in,
    input  wire                                                 weight_shift_en,
    input  wire                                                 swap_weights
);

    wire [ACTIVATION_WIDTH-1:0] act_wire [ARRAY_HEIGHT][ARRAY_WIDTH+1];
    wire [PSUM_WIDTH-1:0]       psum_wire[ARRAY_HEIGHT+1][ARRAY_WIDTH];
    wire [WEIGHT_WIDTH-1:0]     w_chain  [ARRAY_HEIGHT][ARRAY_WIDTH+1]; // Horizontal chain

    genvar r, c;
    generate
        // Connect Activation Inputs (Left) and Horizontal Weight Inputs (Left)
        for (r = 0; r < ARRAY_HEIGHT; r++) begin : gen_row_io
            assign act_wire[r][0] = act_in[r];
            assign w_chain[r][0]  = weight_shift_in[r];
        end

        // Connect Partial Sum Inputs (Top) and Outputs (Bottom)
        for (c = 0; c < ARRAY_WIDTH; c++) begin : gen_col_io
            assign psum_wire[0][c] = psum_in[c];
            assign psum_out[c]     = psum_wire[ARRAY_HEIGHT][c];
        end
    endgenerate

    // 2D PE Mesh Instantiation
    generate
        for (r = 0; r < ARRAY_HEIGHT; r++) begin : gen_row
            for (c = 0; c < ARRAY_WIDTH; c++) begin : gen_col
                pe #(
                    .ACTIVATION_WIDTH(ACTIVATION_WIDTH),
                    .WEIGHT_WIDTH(WEIGHT_WIDTH),
                    .PSUM_WIDTH(PSUM_WIDTH)
                ) pe_inst (
                    .clk_i           (clk_i),
                    .rst_n           (rst_n),
                    .array_en        (array_en),
                    .act_in          (act_wire[r][c]),
                    .psum_in         (psum_wire[r][c]),
                    .act_out         (act_wire[r][c+1]),
                    .psum_out        (psum_wire[r+1][c]),
                    .weight_shift_in (w_chain[r][c]),   // Shift from left PE
                    .weight_shift_out(w_chain[r][c+1]), // Shift to right PE
                    .weight_shift_en (weight_shift_en),
                    .swap_weights    (swap_weights)
                );
            end
        end
    endgenerate

endmodule