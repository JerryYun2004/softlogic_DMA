 // NumberOfConfigBits: 0
module AXIL_S_IO_switch_matrix
    (
 //SJUMP inputs from child tiles
        input  AXIL_S_IO_3_BASE_TO_TOP0,
        input  AXIL_S_IO_3_BASE_TO_TOP1,
        input  AXIL_S_IO_3_BASE_TO_TOP2,
        input  AXIL_S_IO_3_BASE_TO_TOP3,
        input  AXIL_S_IO_3_BASE_TO_TOP4,
        input  AXIL_S_IO_3_BASE_TO_TOP5,
        input  AXIL_S_IO_3_BASE_TO_TOP6,
        input  AXIL_S_IO_3_BASE_TO_TOP7,
        input  AXIL_S_IO_3_BASE_TO_TOP8,
        input  AXIL_S_IO_3_BASE_TO_TOP9,
        input  AXIL_S_IO_3_BASE_TO_TOP10,
        input  AXIL_S_IO_3_BASE_TO_TOP11,
        input  AXIL_S_IO_2_BASE_TO_TOP0,
        input  AXIL_S_IO_2_BASE_TO_TOP1,
        input  AXIL_S_IO_2_BASE_TO_TOP2,
        input  AXIL_S_IO_2_BASE_TO_TOP3,
        input  AXIL_S_IO_2_BASE_TO_TOP4,
        input  AXIL_S_IO_2_BASE_TO_TOP5,
        input  AXIL_S_IO_2_BASE_TO_TOP6,
        input  AXIL_S_IO_2_BASE_TO_TOP7,
        input  AXIL_S_IO_2_BASE_TO_TOP8,
        input  AXIL_S_IO_2_BASE_TO_TOP9,
        input  AXIL_S_IO_2_BASE_TO_TOP10,
        input  AXIL_S_IO_2_BASE_TO_TOP11,
        input  AXIL_S_IO_1_BASE_TO_TOP0,
        input  AXIL_S_IO_1_BASE_TO_TOP1,
        input  AXIL_S_IO_1_BASE_TO_TOP2,
        input  AXIL_S_IO_1_BASE_TO_TOP3,
        input  AXIL_S_IO_1_BASE_TO_TOP4,
        input  AXIL_S_IO_1_BASE_TO_TOP5,
        input  AXIL_S_IO_1_BASE_TO_TOP6,
        input  AXIL_S_IO_1_BASE_TO_TOP7,
        input  AXIL_S_IO_1_BASE_TO_TOP8,
        input  AXIL_S_IO_1_BASE_TO_TOP9,
        input  AXIL_S_IO_1_BASE_TO_TOP10,
        input  AXIL_S_IO_1_BASE_TO_TOP11,
        input  AXIL_S_IO_0_BASE_TO_TOP0,
        input  AXIL_S_IO_0_BASE_TO_TOP1,
        input  AXIL_S_IO_0_BASE_TO_TOP2,
        input  AXIL_S_IO_0_BASE_TO_TOP3,
        input  AXIL_S_IO_0_BASE_TO_TOP4,
        input  AXIL_S_IO_0_BASE_TO_TOP5,
        input  AXIL_S_IO_0_BASE_TO_TOP6,
        input  AXIL_S_IO_0_BASE_TO_TOP7,
        input  AXIL_S_IO_0_BASE_TO_TOP8,
        input  AXIL_S_IO_0_BASE_TO_TOP9,
        input  AXIL_S_IO_0_BASE_TO_TOP10,
        input  AXIL_S_IO_0_BASE_TO_TOP11,
 //BEL input ports (SM outputs)
        output  AXIL_S_FAB_AWREADY,
        output  AXIL_S_FAB_WREADY,
        output  AXIL_S_FAB_BRESP0,
        output  AXIL_S_FAB_BRESP1,
        output  AXIL_S_FAB_BVALID,
        output  AXIL_S_FAB_ARREADY,
        output  AXIL_S_FAB_RDATA0,
        output  AXIL_S_FAB_RDATA1,
        output  AXIL_S_FAB_RDATA2,
        output  AXIL_S_FAB_RDATA3,
        output  AXIL_S_FAB_RDATA4,
        output  AXIL_S_FAB_RDATA5,
        output  AXIL_S_FAB_RDATA6,
        output  AXIL_S_FAB_RDATA7,
        output  AXIL_S_FAB_RDATA8,
        output  AXIL_S_FAB_RDATA9,
        output  AXIL_S_FAB_RDATA10,
        output  AXIL_S_FAB_RDATA11,
        output  AXIL_S_FAB_RDATA12,
        output  AXIL_S_FAB_RDATA13,
        output  AXIL_S_FAB_RDATA14,
        output  AXIL_S_FAB_RDATA15,
        output  AXIL_S_FAB_RDATA16,
        output  AXIL_S_FAB_RDATA17,
        output  AXIL_S_FAB_RDATA18,
        output  AXIL_S_FAB_RDATA19,
        output  AXIL_S_FAB_RDATA20,
        output  AXIL_S_FAB_RDATA21,
        output  AXIL_S_FAB_RDATA22,
        output  AXIL_S_FAB_RDATA23,
        output  AXIL_S_FAB_RDATA24,
        output  AXIL_S_FAB_RDATA25,
        output  AXIL_S_FAB_RDATA26,
        output  AXIL_S_FAB_RDATA27,
        output  AXIL_S_FAB_RDATA28,
        output  AXIL_S_FAB_RDATA29,
        output  AXIL_S_FAB_RDATA30,
        output  AXIL_S_FAB_RDATA31,
        output  AXIL_S_FAB_RRESP0,
        output  AXIL_S_FAB_RRESP1,
        output  AXIL_S_FAB_RVALID,
 //BEL output ports (SM inputs)
        input  AXIL_S_FAB_AWADDR0,
        input  AXIL_S_FAB_AWADDR1,
        input  AXIL_S_FAB_AWADDR2,
        input  AXIL_S_FAB_AWADDR3,
        input  AXIL_S_FAB_AWADDR4,
        input  AXIL_S_FAB_AWADDR5,
        input  AXIL_S_FAB_AWADDR6,
        input  AXIL_S_FAB_AWADDR7,
        input  AXIL_S_FAB_AWADDR8,
        input  AXIL_S_FAB_AWADDR9,
        input  AXIL_S_FAB_AWVALID,
        input  AXIL_S_FAB_WDATA0,
        input  AXIL_S_FAB_WDATA1,
        input  AXIL_S_FAB_WDATA2,
        input  AXIL_S_FAB_WDATA3,
        input  AXIL_S_FAB_WDATA4,
        input  AXIL_S_FAB_WDATA5,
        input  AXIL_S_FAB_WDATA6,
        input  AXIL_S_FAB_WDATA7,
        input  AXIL_S_FAB_WDATA8,
        input  AXIL_S_FAB_WDATA9,
        input  AXIL_S_FAB_WDATA10,
        input  AXIL_S_FAB_WDATA11,
        input  AXIL_S_FAB_WDATA12,
        input  AXIL_S_FAB_WDATA13,
        input  AXIL_S_FAB_WDATA14,
        input  AXIL_S_FAB_WDATA15,
        input  AXIL_S_FAB_WDATA16,
        input  AXIL_S_FAB_WDATA17,
        input  AXIL_S_FAB_WDATA18,
        input  AXIL_S_FAB_WDATA19,
        input  AXIL_S_FAB_WDATA20,
        input  AXIL_S_FAB_WDATA21,
        input  AXIL_S_FAB_WDATA22,
        input  AXIL_S_FAB_WDATA23,
        input  AXIL_S_FAB_WDATA24,
        input  AXIL_S_FAB_WDATA25,
        input  AXIL_S_FAB_WDATA26,
        input  AXIL_S_FAB_WDATA27,
        input  AXIL_S_FAB_WDATA28,
        input  AXIL_S_FAB_WDATA29,
        input  AXIL_S_FAB_WDATA30,
        input  AXIL_S_FAB_WDATA31,
        input  AXIL_S_FAB_WSTRB0,
        input  AXIL_S_FAB_WSTRB1,
        input  AXIL_S_FAB_WSTRB2,
        input  AXIL_S_FAB_WSTRB3,
        input  AXIL_S_FAB_WVALID,
        input  AXIL_S_FAB_BREADY,
        input  AXIL_S_FAB_ARADDR0,
        input  AXIL_S_FAB_ARADDR1,
        input  AXIL_S_FAB_ARADDR2,
        input  AXIL_S_FAB_ARADDR3,
        input  AXIL_S_FAB_ARADDR4,
        input  AXIL_S_FAB_ARADDR5,
        input  AXIL_S_FAB_ARADDR6,
        input  AXIL_S_FAB_ARADDR7,
        input  AXIL_S_FAB_ARADDR8,
        input  AXIL_S_FAB_ARADDR9,
        input  AXIL_S_FAB_ARVALID,
        input  AXIL_S_FAB_RREADY,
 //Reverse SJUMP outputs (SM -> child tile)
        output  AXIL_S_IO_3_TOP_TO_BASE0,
        output  AXIL_S_IO_3_TOP_TO_BASE1,
        output  AXIL_S_IO_3_TOP_TO_BASE2,
        output  AXIL_S_IO_3_TOP_TO_BASE3,
        output  AXIL_S_IO_3_TOP_TO_BASE4,
        output  AXIL_S_IO_3_TOP_TO_BASE5,
        output  AXIL_S_IO_3_TOP_TO_BASE6,
        output  AXIL_S_IO_3_TOP_TO_BASE7,
        output  AXIL_S_IO_3_TOP_TO_BASE8,
        output  AXIL_S_IO_3_TOP_TO_BASE9,
        output  AXIL_S_IO_3_TOP_TO_BASE10,
        output  AXIL_S_IO_3_TOP_TO_BASE11,
        output  AXIL_S_IO_3_TOP_TO_BASE12,
        output  AXIL_S_IO_3_TOP_TO_BASE13,
        output  AXIL_S_IO_3_TOP_TO_BASE14,
        output  AXIL_S_IO_3_TOP_TO_BASE15,
        output  AXIL_S_IO_2_TOP_TO_BASE0,
        output  AXIL_S_IO_2_TOP_TO_BASE1,
        output  AXIL_S_IO_2_TOP_TO_BASE2,
        output  AXIL_S_IO_2_TOP_TO_BASE3,
        output  AXIL_S_IO_2_TOP_TO_BASE4,
        output  AXIL_S_IO_2_TOP_TO_BASE5,
        output  AXIL_S_IO_2_TOP_TO_BASE6,
        output  AXIL_S_IO_2_TOP_TO_BASE7,
        output  AXIL_S_IO_2_TOP_TO_BASE8,
        output  AXIL_S_IO_2_TOP_TO_BASE9,
        output  AXIL_S_IO_2_TOP_TO_BASE10,
        output  AXIL_S_IO_2_TOP_TO_BASE11,
        output  AXIL_S_IO_2_TOP_TO_BASE12,
        output  AXIL_S_IO_2_TOP_TO_BASE13,
        output  AXIL_S_IO_2_TOP_TO_BASE14,
        output  AXIL_S_IO_2_TOP_TO_BASE15,
        output  AXIL_S_IO_1_TOP_TO_BASE0,
        output  AXIL_S_IO_1_TOP_TO_BASE1,
        output  AXIL_S_IO_1_TOP_TO_BASE2,
        output  AXIL_S_IO_1_TOP_TO_BASE3,
        output  AXIL_S_IO_1_TOP_TO_BASE4,
        output  AXIL_S_IO_1_TOP_TO_BASE5,
        output  AXIL_S_IO_1_TOP_TO_BASE6,
        output  AXIL_S_IO_1_TOP_TO_BASE7,
        output  AXIL_S_IO_1_TOP_TO_BASE8,
        output  AXIL_S_IO_1_TOP_TO_BASE9,
        output  AXIL_S_IO_1_TOP_TO_BASE10,
        output  AXIL_S_IO_1_TOP_TO_BASE11,
        output  AXIL_S_IO_1_TOP_TO_BASE12,
        output  AXIL_S_IO_1_TOP_TO_BASE13,
        output  AXIL_S_IO_1_TOP_TO_BASE14,
        output  AXIL_S_IO_1_TOP_TO_BASE15,
        output  AXIL_S_IO_0_TOP_TO_BASE0,
        output  AXIL_S_IO_0_TOP_TO_BASE1,
        output  AXIL_S_IO_0_TOP_TO_BASE2,
        output  AXIL_S_IO_0_TOP_TO_BASE3,
        output  AXIL_S_IO_0_TOP_TO_BASE4,
        output  AXIL_S_IO_0_TOP_TO_BASE5,
        output  AXIL_S_IO_0_TOP_TO_BASE6,
        output  AXIL_S_IO_0_TOP_TO_BASE7,
        output  AXIL_S_IO_0_TOP_TO_BASE8,
        output  AXIL_S_IO_0_TOP_TO_BASE9,
        output  AXIL_S_IO_0_TOP_TO_BASE10,
        output  AXIL_S_IO_0_TOP_TO_BASE11,
        output  AXIL_S_IO_0_TOP_TO_BASE12,
        output  AXIL_S_IO_0_TOP_TO_BASE13,
        output  AXIL_S_IO_0_TOP_TO_BASE14,
        output  AXIL_S_IO_0_TOP_TO_BASE15
 //global
);
parameter GND0 = 1'b0;
parameter GND = 1'b0;
parameter VCC0 = 1'b1;
parameter VCC = 1'b1;
parameter VDD0 = 1'b1;
parameter VDD = 1'b1;

 //The configuration bits (if any) are just a long shift register
 //This shift register is padded to an even number of flops/latches
 //switch matrix multiplexer AXIL_S_FAB_AWREADY MUX-1
assign AXIL_S_FAB_AWREADY = AXIL_S_IO_3_BASE_TO_TOP11;

 //switch matrix multiplexer AXIL_S_FAB_WREADY MUX-1
assign AXIL_S_FAB_WREADY = AXIL_S_IO_3_BASE_TO_TOP10;

 //switch matrix multiplexer AXIL_S_FAB_BRESP1 MUX-1
assign AXIL_S_FAB_BRESP1 = AXIL_S_IO_3_BASE_TO_TOP9;

 //switch matrix multiplexer AXIL_S_FAB_BRESP0 MUX-1
assign AXIL_S_FAB_BRESP0 = AXIL_S_IO_3_BASE_TO_TOP8;

 //switch matrix multiplexer AXIL_S_FAB_BVALID MUX-1
assign AXIL_S_FAB_BVALID = AXIL_S_IO_3_BASE_TO_TOP7;

 //switch matrix multiplexer AXIL_S_FAB_ARREADY MUX-1
assign AXIL_S_FAB_ARREADY = AXIL_S_IO_3_BASE_TO_TOP6;

 //switch matrix multiplexer AXIL_S_FAB_RRESP1 MUX-1
assign AXIL_S_FAB_RRESP1 = AXIL_S_IO_3_BASE_TO_TOP5;

 //switch matrix multiplexer AXIL_S_FAB_RRESP0 MUX-1
assign AXIL_S_FAB_RRESP0 = AXIL_S_IO_3_BASE_TO_TOP4;

 //switch matrix multiplexer AXIL_S_FAB_RVALID MUX-1
assign AXIL_S_FAB_RVALID = AXIL_S_IO_3_BASE_TO_TOP3;

 //switch matrix multiplexer AXIL_S_FAB_RDATA31 MUX-1
assign AXIL_S_FAB_RDATA31 = AXIL_S_IO_2_BASE_TO_TOP11;

 //switch matrix multiplexer AXIL_S_FAB_RDATA30 MUX-1
assign AXIL_S_FAB_RDATA30 = AXIL_S_IO_2_BASE_TO_TOP10;

 //switch matrix multiplexer AXIL_S_FAB_RDATA29 MUX-1
assign AXIL_S_FAB_RDATA29 = AXIL_S_IO_2_BASE_TO_TOP9;

 //switch matrix multiplexer AXIL_S_FAB_RDATA28 MUX-1
assign AXIL_S_FAB_RDATA28 = AXIL_S_IO_2_BASE_TO_TOP8;

 //switch matrix multiplexer AXIL_S_FAB_RDATA27 MUX-1
assign AXIL_S_FAB_RDATA27 = AXIL_S_IO_2_BASE_TO_TOP7;

 //switch matrix multiplexer AXIL_S_FAB_RDATA26 MUX-1
assign AXIL_S_FAB_RDATA26 = AXIL_S_IO_2_BASE_TO_TOP6;

 //switch matrix multiplexer AXIL_S_FAB_RDATA25 MUX-1
assign AXIL_S_FAB_RDATA25 = AXIL_S_IO_2_BASE_TO_TOP5;

 //switch matrix multiplexer AXIL_S_FAB_RDATA24 MUX-1
assign AXIL_S_FAB_RDATA24 = AXIL_S_IO_2_BASE_TO_TOP4;

 //switch matrix multiplexer AXIL_S_FAB_RDATA23 MUX-1
assign AXIL_S_FAB_RDATA23 = AXIL_S_IO_2_BASE_TO_TOP3;

 //switch matrix multiplexer AXIL_S_FAB_RDATA22 MUX-1
assign AXIL_S_FAB_RDATA22 = AXIL_S_IO_2_BASE_TO_TOP2;

 //switch matrix multiplexer AXIL_S_FAB_RDATA21 MUX-1
assign AXIL_S_FAB_RDATA21 = AXIL_S_IO_2_BASE_TO_TOP1;

 //switch matrix multiplexer AXIL_S_FAB_RDATA20 MUX-1
assign AXIL_S_FAB_RDATA20 = AXIL_S_IO_2_BASE_TO_TOP0;

 //switch matrix multiplexer AXIL_S_FAB_RDATA19 MUX-1
assign AXIL_S_FAB_RDATA19 = AXIL_S_IO_1_BASE_TO_TOP11;

 //switch matrix multiplexer AXIL_S_FAB_RDATA18 MUX-1
assign AXIL_S_FAB_RDATA18 = AXIL_S_IO_1_BASE_TO_TOP10;

 //switch matrix multiplexer AXIL_S_FAB_RDATA17 MUX-1
assign AXIL_S_FAB_RDATA17 = AXIL_S_IO_1_BASE_TO_TOP9;

 //switch matrix multiplexer AXIL_S_FAB_RDATA16 MUX-1
assign AXIL_S_FAB_RDATA16 = AXIL_S_IO_1_BASE_TO_TOP8;

 //switch matrix multiplexer AXIL_S_FAB_RDATA15 MUX-1
assign AXIL_S_FAB_RDATA15 = AXIL_S_IO_1_BASE_TO_TOP7;

 //switch matrix multiplexer AXIL_S_FAB_RDATA14 MUX-1
assign AXIL_S_FAB_RDATA14 = AXIL_S_IO_1_BASE_TO_TOP6;

 //switch matrix multiplexer AXIL_S_FAB_RDATA13 MUX-1
assign AXIL_S_FAB_RDATA13 = AXIL_S_IO_1_BASE_TO_TOP5;

 //switch matrix multiplexer AXIL_S_FAB_RDATA12 MUX-1
assign AXIL_S_FAB_RDATA12 = AXIL_S_IO_1_BASE_TO_TOP4;

 //switch matrix multiplexer AXIL_S_FAB_RDATA11 MUX-1
assign AXIL_S_FAB_RDATA11 = AXIL_S_IO_1_BASE_TO_TOP3;

 //switch matrix multiplexer AXIL_S_FAB_RDATA10 MUX-1
assign AXIL_S_FAB_RDATA10 = AXIL_S_IO_1_BASE_TO_TOP2;

 //switch matrix multiplexer AXIL_S_FAB_RDATA9 MUX-1
assign AXIL_S_FAB_RDATA9 = AXIL_S_IO_1_BASE_TO_TOP1;

 //switch matrix multiplexer AXIL_S_FAB_RDATA8 MUX-1
assign AXIL_S_FAB_RDATA8 = AXIL_S_IO_1_BASE_TO_TOP0;

 //switch matrix multiplexer AXIL_S_FAB_RDATA7 MUX-1
assign AXIL_S_FAB_RDATA7 = AXIL_S_IO_0_BASE_TO_TOP11;

 //switch matrix multiplexer AXIL_S_FAB_RDATA6 MUX-1
assign AXIL_S_FAB_RDATA6 = AXIL_S_IO_0_BASE_TO_TOP10;

 //switch matrix multiplexer AXIL_S_FAB_RDATA5 MUX-1
assign AXIL_S_FAB_RDATA5 = AXIL_S_IO_0_BASE_TO_TOP9;

 //switch matrix multiplexer AXIL_S_FAB_RDATA4 MUX-1
assign AXIL_S_FAB_RDATA4 = AXIL_S_IO_0_BASE_TO_TOP8;

 //switch matrix multiplexer AXIL_S_FAB_RDATA3 MUX-1
assign AXIL_S_FAB_RDATA3 = AXIL_S_IO_0_BASE_TO_TOP7;

 //switch matrix multiplexer AXIL_S_FAB_RDATA2 MUX-1
assign AXIL_S_FAB_RDATA2 = AXIL_S_IO_0_BASE_TO_TOP6;

 //switch matrix multiplexer AXIL_S_FAB_RDATA1 MUX-1
assign AXIL_S_FAB_RDATA1 = AXIL_S_IO_0_BASE_TO_TOP5;

 //switch matrix multiplexer AXIL_S_FAB_RDATA0 MUX-1
assign AXIL_S_FAB_RDATA0 = AXIL_S_IO_0_BASE_TO_TOP4;

 //switch matrix multiplexer AXIL_S_IO_3_TOP_TO_BASE15 MUX-1
assign AXIL_S_IO_3_TOP_TO_BASE15 = AXIL_S_FAB_AWADDR9;

 //switch matrix multiplexer AXIL_S_IO_3_TOP_TO_BASE14 MUX-1
assign AXIL_S_IO_3_TOP_TO_BASE14 = AXIL_S_FAB_AWADDR8;

 //switch matrix multiplexer AXIL_S_IO_3_TOP_TO_BASE13 MUX-1
assign AXIL_S_IO_3_TOP_TO_BASE13 = AXIL_S_FAB_AWADDR7;

 //switch matrix multiplexer AXIL_S_IO_3_TOP_TO_BASE12 MUX-1
assign AXIL_S_IO_3_TOP_TO_BASE12 = AXIL_S_FAB_AWADDR6;

 //switch matrix multiplexer AXIL_S_IO_3_TOP_TO_BASE11 MUX-1
assign AXIL_S_IO_3_TOP_TO_BASE11 = AXIL_S_FAB_AWADDR5;

 //switch matrix multiplexer AXIL_S_IO_3_TOP_TO_BASE10 MUX-1
assign AXIL_S_IO_3_TOP_TO_BASE10 = AXIL_S_FAB_AWADDR4;

 //switch matrix multiplexer AXIL_S_IO_3_TOP_TO_BASE9 MUX-1
assign AXIL_S_IO_3_TOP_TO_BASE9 = AXIL_S_FAB_AWADDR3;

 //switch matrix multiplexer AXIL_S_IO_3_TOP_TO_BASE8 MUX-1
assign AXIL_S_IO_3_TOP_TO_BASE8 = AXIL_S_FAB_AWADDR2;

 //switch matrix multiplexer AXIL_S_IO_3_TOP_TO_BASE7 MUX-1
assign AXIL_S_IO_3_TOP_TO_BASE7 = AXIL_S_FAB_AWADDR1;

 //switch matrix multiplexer AXIL_S_IO_3_TOP_TO_BASE6 MUX-1
assign AXIL_S_IO_3_TOP_TO_BASE6 = AXIL_S_FAB_AWADDR0;

 //switch matrix multiplexer AXIL_S_IO_3_TOP_TO_BASE5 MUX-1
assign AXIL_S_IO_3_TOP_TO_BASE5 = AXIL_S_FAB_AWVALID;

 //switch matrix multiplexer AXIL_S_IO_3_TOP_TO_BASE4 MUX-1
assign AXIL_S_IO_3_TOP_TO_BASE4 = AXIL_S_FAB_WSTRB3;

 //switch matrix multiplexer AXIL_S_IO_3_TOP_TO_BASE3 MUX-1
assign AXIL_S_IO_3_TOP_TO_BASE3 = AXIL_S_FAB_WSTRB2;

 //switch matrix multiplexer AXIL_S_IO_3_TOP_TO_BASE2 MUX-1
assign AXIL_S_IO_3_TOP_TO_BASE2 = AXIL_S_FAB_WSTRB1;

 //switch matrix multiplexer AXIL_S_IO_3_TOP_TO_BASE1 MUX-1
assign AXIL_S_IO_3_TOP_TO_BASE1 = AXIL_S_FAB_WSTRB0;

 //switch matrix multiplexer AXIL_S_IO_3_TOP_TO_BASE0 MUX-1
assign AXIL_S_IO_3_TOP_TO_BASE0 = AXIL_S_FAB_WVALID;

 //switch matrix multiplexer AXIL_S_IO_2_TOP_TO_BASE15 MUX-1
assign AXIL_S_IO_2_TOP_TO_BASE15 = AXIL_S_FAB_WDATA31;

 //switch matrix multiplexer AXIL_S_IO_2_TOP_TO_BASE14 MUX-1
assign AXIL_S_IO_2_TOP_TO_BASE14 = AXIL_S_FAB_WDATA30;

 //switch matrix multiplexer AXIL_S_IO_2_TOP_TO_BASE13 MUX-1
assign AXIL_S_IO_2_TOP_TO_BASE13 = AXIL_S_FAB_WDATA29;

 //switch matrix multiplexer AXIL_S_IO_2_TOP_TO_BASE12 MUX-1
assign AXIL_S_IO_2_TOP_TO_BASE12 = AXIL_S_FAB_WDATA28;

 //switch matrix multiplexer AXIL_S_IO_2_TOP_TO_BASE11 MUX-1
assign AXIL_S_IO_2_TOP_TO_BASE11 = AXIL_S_FAB_WDATA27;

 //switch matrix multiplexer AXIL_S_IO_2_TOP_TO_BASE10 MUX-1
assign AXIL_S_IO_2_TOP_TO_BASE10 = AXIL_S_FAB_WDATA26;

 //switch matrix multiplexer AXIL_S_IO_2_TOP_TO_BASE9 MUX-1
assign AXIL_S_IO_2_TOP_TO_BASE9 = AXIL_S_FAB_WDATA25;

 //switch matrix multiplexer AXIL_S_IO_2_TOP_TO_BASE8 MUX-1
assign AXIL_S_IO_2_TOP_TO_BASE8 = AXIL_S_FAB_WDATA24;

 //switch matrix multiplexer AXIL_S_IO_2_TOP_TO_BASE7 MUX-1
assign AXIL_S_IO_2_TOP_TO_BASE7 = AXIL_S_FAB_WDATA23;

 //switch matrix multiplexer AXIL_S_IO_2_TOP_TO_BASE6 MUX-1
assign AXIL_S_IO_2_TOP_TO_BASE6 = AXIL_S_FAB_WDATA22;

 //switch matrix multiplexer AXIL_S_IO_2_TOP_TO_BASE5 MUX-1
assign AXIL_S_IO_2_TOP_TO_BASE5 = AXIL_S_FAB_WDATA21;

 //switch matrix multiplexer AXIL_S_IO_2_TOP_TO_BASE4 MUX-1
assign AXIL_S_IO_2_TOP_TO_BASE4 = AXIL_S_FAB_WDATA20;

 //switch matrix multiplexer AXIL_S_IO_2_TOP_TO_BASE3 MUX-1
assign AXIL_S_IO_2_TOP_TO_BASE3 = AXIL_S_FAB_WDATA19;

 //switch matrix multiplexer AXIL_S_IO_2_TOP_TO_BASE2 MUX-1
assign AXIL_S_IO_2_TOP_TO_BASE2 = AXIL_S_FAB_WDATA18;

 //switch matrix multiplexer AXIL_S_IO_2_TOP_TO_BASE1 MUX-1
assign AXIL_S_IO_2_TOP_TO_BASE1 = AXIL_S_FAB_WDATA17;

 //switch matrix multiplexer AXIL_S_IO_2_TOP_TO_BASE0 MUX-1
assign AXIL_S_IO_2_TOP_TO_BASE0 = AXIL_S_FAB_WDATA16;

 //switch matrix multiplexer AXIL_S_IO_1_TOP_TO_BASE15 MUX-1
assign AXIL_S_IO_1_TOP_TO_BASE15 = AXIL_S_FAB_WDATA15;

 //switch matrix multiplexer AXIL_S_IO_1_TOP_TO_BASE14 MUX-1
assign AXIL_S_IO_1_TOP_TO_BASE14 = AXIL_S_FAB_WDATA14;

 //switch matrix multiplexer AXIL_S_IO_1_TOP_TO_BASE13 MUX-1
assign AXIL_S_IO_1_TOP_TO_BASE13 = AXIL_S_FAB_WDATA13;

 //switch matrix multiplexer AXIL_S_IO_1_TOP_TO_BASE12 MUX-1
assign AXIL_S_IO_1_TOP_TO_BASE12 = AXIL_S_FAB_WDATA12;

 //switch matrix multiplexer AXIL_S_IO_1_TOP_TO_BASE11 MUX-1
assign AXIL_S_IO_1_TOP_TO_BASE11 = AXIL_S_FAB_WDATA11;

 //switch matrix multiplexer AXIL_S_IO_1_TOP_TO_BASE10 MUX-1
assign AXIL_S_IO_1_TOP_TO_BASE10 = AXIL_S_FAB_WDATA10;

 //switch matrix multiplexer AXIL_S_IO_1_TOP_TO_BASE9 MUX-1
assign AXIL_S_IO_1_TOP_TO_BASE9 = AXIL_S_FAB_WDATA9;

 //switch matrix multiplexer AXIL_S_IO_1_TOP_TO_BASE8 MUX-1
assign AXIL_S_IO_1_TOP_TO_BASE8 = AXIL_S_FAB_WDATA8;

 //switch matrix multiplexer AXIL_S_IO_1_TOP_TO_BASE7 MUX-1
assign AXIL_S_IO_1_TOP_TO_BASE7 = AXIL_S_FAB_WDATA7;

 //switch matrix multiplexer AXIL_S_IO_1_TOP_TO_BASE6 MUX-1
assign AXIL_S_IO_1_TOP_TO_BASE6 = AXIL_S_FAB_WDATA6;

 //switch matrix multiplexer AXIL_S_IO_1_TOP_TO_BASE5 MUX-1
assign AXIL_S_IO_1_TOP_TO_BASE5 = AXIL_S_FAB_WDATA5;

 //switch matrix multiplexer AXIL_S_IO_1_TOP_TO_BASE4 MUX-1
assign AXIL_S_IO_1_TOP_TO_BASE4 = AXIL_S_FAB_WDATA4;

 //switch matrix multiplexer AXIL_S_IO_1_TOP_TO_BASE3 MUX-1
assign AXIL_S_IO_1_TOP_TO_BASE3 = AXIL_S_FAB_WDATA3;

 //switch matrix multiplexer AXIL_S_IO_1_TOP_TO_BASE2 MUX-1
assign AXIL_S_IO_1_TOP_TO_BASE2 = AXIL_S_FAB_WDATA2;

 //switch matrix multiplexer AXIL_S_IO_1_TOP_TO_BASE1 MUX-1
assign AXIL_S_IO_1_TOP_TO_BASE1 = AXIL_S_FAB_WDATA1;

 //switch matrix multiplexer AXIL_S_IO_1_TOP_TO_BASE0 MUX-1
assign AXIL_S_IO_1_TOP_TO_BASE0 = AXIL_S_FAB_WDATA0;

 //switch matrix multiplexer AXIL_S_IO_0_TOP_TO_BASE15 MUX-1
assign AXIL_S_IO_0_TOP_TO_BASE15 = AXIL_S_FAB_BREADY;

 //switch matrix multiplexer AXIL_S_IO_0_TOP_TO_BASE14 MUX-1
assign AXIL_S_IO_0_TOP_TO_BASE14 = AXIL_S_FAB_ARADDR9;

 //switch matrix multiplexer AXIL_S_IO_0_TOP_TO_BASE13 MUX-1
assign AXIL_S_IO_0_TOP_TO_BASE13 = AXIL_S_FAB_ARADDR8;

 //switch matrix multiplexer AXIL_S_IO_0_TOP_TO_BASE12 MUX-1
assign AXIL_S_IO_0_TOP_TO_BASE12 = AXIL_S_FAB_ARADDR7;

 //switch matrix multiplexer AXIL_S_IO_0_TOP_TO_BASE11 MUX-1
assign AXIL_S_IO_0_TOP_TO_BASE11 = AXIL_S_FAB_ARADDR6;

 //switch matrix multiplexer AXIL_S_IO_0_TOP_TO_BASE10 MUX-1
assign AXIL_S_IO_0_TOP_TO_BASE10 = AXIL_S_FAB_ARADDR5;

 //switch matrix multiplexer AXIL_S_IO_0_TOP_TO_BASE9 MUX-1
assign AXIL_S_IO_0_TOP_TO_BASE9 = AXIL_S_FAB_ARADDR4;

 //switch matrix multiplexer AXIL_S_IO_0_TOP_TO_BASE8 MUX-1
assign AXIL_S_IO_0_TOP_TO_BASE8 = AXIL_S_FAB_ARADDR3;

 //switch matrix multiplexer AXIL_S_IO_0_TOP_TO_BASE7 MUX-1
assign AXIL_S_IO_0_TOP_TO_BASE7 = AXIL_S_FAB_ARADDR2;

 //switch matrix multiplexer AXIL_S_IO_0_TOP_TO_BASE6 MUX-1
assign AXIL_S_IO_0_TOP_TO_BASE6 = AXIL_S_FAB_ARADDR1;

 //switch matrix multiplexer AXIL_S_IO_0_TOP_TO_BASE5 MUX-1
assign AXIL_S_IO_0_TOP_TO_BASE5 = AXIL_S_FAB_ARADDR0;

 //switch matrix multiplexer AXIL_S_IO_0_TOP_TO_BASE4 MUX-1
assign AXIL_S_IO_0_TOP_TO_BASE4 = AXIL_S_FAB_ARVALID;

 //switch matrix multiplexer AXIL_S_IO_0_TOP_TO_BASE3 MUX-1
assign AXIL_S_IO_0_TOP_TO_BASE3 = AXIL_S_FAB_RREADY;

endmodule