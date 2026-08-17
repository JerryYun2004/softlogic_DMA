module npu_crossbar #(
    parameter int ARRAY_HEIGHT     = 8,
    parameter int ACTIVATION_WIDTH = 8,
    localparam int SEL_WIDTH       = $clog2(ARRAY_HEIGHT)
)(
    input  wire [ARRAY_HEIGHT-1:0][ACTIVATION_WIDTH-1:0] in_data,
    input  wire [ARRAY_HEIGHT-1:0][SEL_WIDTH-1:0]        crossbar_sel, // Bank select per row
    output reg  [ARRAY_HEIGHT-1:0][ACTIVATION_WIDTH-1:0] out_data
);

    genvar r;
    generate
        for (r = 0; r < ARRAY_HEIGHT; r++) begin : gen_row_mux
            assign out_data[r] = in_data[crossbar_sel[r]];
        end
    endgenerate

endmodule