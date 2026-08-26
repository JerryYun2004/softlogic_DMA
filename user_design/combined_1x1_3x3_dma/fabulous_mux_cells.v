`ifndef FABULOUS_MUX_CELLS_V
`define FABULOUS_MUX_CELLS_V

`timescale 1ns / 1ps
`default_nettype none

// Width-parameterized wrappers around the dedicated FABulous data-mux BELs.
//
// The explicit primitive instances prevent ordinary RTL selections from being
// absorbed into FABULOUS_LC LUTs.  Yosys' FABulous primitive library supplies
// these three cell types during synthesis.  The behavioral definitions at the
// bottom of this file are compiled only by RTL simulators.

module fabulous_mux2_bus #(
    parameter integer WIDTH = 1
)(
    input  wire [WIDTH-1:0] i0,
    input  wire [WIDTH-1:0] i1,
    input  wire             s0,
    output wire [WIDTH-1:0] o
);
    genvar bit_index;
    generate
        for (bit_index = 0; bit_index < WIDTH;
             bit_index = bit_index + 1) begin : gen_mux2
            (* keep *) FABULOUS_MUX2 mux_i (
                .I0(i0[bit_index]),
                .I1(i1[bit_index]),
                .S0(s0),
                .O (o[bit_index])
            );
        end
    endgenerate
endmodule

module fabulous_mux4_bus #(
    parameter integer WIDTH = 1
)(
    input  wire [WIDTH-1:0] i0,
    input  wire [WIDTH-1:0] i1,
    input  wire [WIDTH-1:0] i2,
    input  wire [WIDTH-1:0] i3,
    input  wire             s0,
    input  wire             s1,
    output wire [WIDTH-1:0] o
);
    genvar bit_index;
    generate
        for (bit_index = 0; bit_index < WIDTH;
             bit_index = bit_index + 1) begin : gen_mux4
            (* keep *) FABULOUS_MUX4 mux_i (
                .I0(i0[bit_index]),
                .I1(i1[bit_index]),
                .I2(i2[bit_index]),
                .I3(i3[bit_index]),
                .S0(s0),
                .S1(s1),
                .O (o[bit_index])
            );
        end
    endgenerate
endmodule

module fabulous_mux8_bus #(
    parameter integer WIDTH = 1
)(
    input  wire [WIDTH-1:0] i0,
    input  wire [WIDTH-1:0] i1,
    input  wire [WIDTH-1:0] i2,
    input  wire [WIDTH-1:0] i3,
    input  wire [WIDTH-1:0] i4,
    input  wire [WIDTH-1:0] i5,
    input  wire [WIDTH-1:0] i6,
    input  wire [WIDTH-1:0] i7,
    input  wire             s0,
    input  wire             s1,
    input  wire             s2,
    output wire [WIDTH-1:0] o
);
    genvar bit_index;
    generate
        for (bit_index = 0; bit_index < WIDTH;
             bit_index = bit_index + 1) begin : gen_mux8
            (* keep *) FABULOUS_MUX8 mux_i (
                .I0(i0[bit_index]),
                .I1(i1[bit_index]),
                .I2(i2[bit_index]),
                .I3(i3[bit_index]),
                .I4(i4[bit_index]),
                .I5(i5[bit_index]),
                .I6(i6[bit_index]),
                .I7(i7[bit_index]),
                .S0(s0),
                .S1(s1),
                .S2(s2),
                .O (o[bit_index])
            );
        end
    endgenerate
endmodule

// Yosys automatically defines SYNTHESIS and uses the FABulous primitive
// library.  These models make the same source directly simulatable in Icarus,
// Verilator, and other RTL simulators without introducing synthesis modules
// that could conflict with the toolchain's primitive definitions.
`ifndef SYNTHESIS
module FABULOUS_MUX2(
    input  wire I0,
    input  wire I1,
    input  wire S0,
    output wire O
);
    assign O = S0 ? I1 : I0;
endmodule

module FABULOUS_MUX4(
    input  wire I0,
    input  wire I1,
    input  wire I2,
    input  wire I3,
    input  wire S0,
    input  wire S1,
    output wire O
);
    wire low_pair;
    wire high_pair;
    assign low_pair  = S0 ? I1 : I0;
    assign high_pair = S0 ? I3 : I2;
    assign O         = S1 ? high_pair : low_pair;
endmodule

module FABULOUS_MUX8(
    input  wire I0,
    input  wire I1,
    input  wire I2,
    input  wire I3,
    input  wire I4,
    input  wire I5,
    input  wire I6,
    input  wire I7,
    input  wire S0,
    input  wire S1,
    input  wire S2,
    output wire O
);
    wire low_group;
    wire high_group;
    assign low_group = S1 ? (S0 ? I3 : I2) : (S0 ? I1 : I0);
    assign high_group = S1 ? (S0 ? I7 : I6) : (S0 ? I5 : I4);
    assign O = S2 ? high_group : low_group;
endmodule
`endif

`default_nettype wire
`endif
