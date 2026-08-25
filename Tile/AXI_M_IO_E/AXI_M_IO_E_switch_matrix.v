 // NumberOfConfigBits: 12
module AXI_M_IO_E_switch_matrix
    #(
        parameter NoConfigBits=12
    )
    (
 //SJUMP inputs from child tiles
        input  AXI_M_IO_E_5_BASE_TO_TOP0,
        input  AXI_M_IO_E_5_BASE_TO_TOP1,
        input  AXI_M_IO_E_5_BASE_TO_TOP2,
        input  AXI_M_IO_E_5_BASE_TO_TOP3,
        input  AXI_M_IO_E_5_BASE_TO_TOP4,
        input  AXI_M_IO_E_5_BASE_TO_TOP5,
        input  AXI_M_IO_E_5_BASE_TO_TOP6,
        input  AXI_M_IO_E_5_BASE_TO_TOP7,
        input  AXI_M_IO_E_5_BASE_TO_TOP8,
        input  AXI_M_IO_E_5_BASE_TO_TOP9,
        input  AXI_M_IO_E_5_BASE_TO_TOP10,
        input  AXI_M_IO_E_5_BASE_TO_TOP11,
        input  AXI_M_IO_E_5_BASE_TO_TOP12,
        input  AXI_M_IO_E_5_BASE_TO_TOP13,
        input  AXI_M_IO_E_5_BASE_TO_TOP14,
        input  AXI_M_IO_E_5_BASE_TO_TOP15,
        input  AXI_M_IO_E_5_BASE_TO_TOP16,
        input  AXI_M_IO_E_5_BASE_TO_TOP17,
        input  AXI_M_IO_E_5_BASE_TO_TOP18,
        input  AXI_M_IO_E_5_BASE_TO_TOP19,
        input  AXI_M_IO_E_5_BASE_TO_TOP20,
        input  AXI_M_IO_E_5_BASE_TO_TOP21,
        input  AXI_M_IO_E_5_BASE_TO_TOP22,
        input  AXI_M_IO_E_5_BASE_TO_TOP23,
        input  AXI_M_IO_E_4_BASE_TO_TOP0,
        input  AXI_M_IO_E_4_BASE_TO_TOP1,
        input  AXI_M_IO_E_4_BASE_TO_TOP2,
        input  AXI_M_IO_E_4_BASE_TO_TOP3,
        input  AXI_M_IO_E_4_BASE_TO_TOP4,
        input  AXI_M_IO_E_4_BASE_TO_TOP5,
        input  AXI_M_IO_E_4_BASE_TO_TOP6,
        input  AXI_M_IO_E_4_BASE_TO_TOP7,
        input  AXI_M_IO_E_4_BASE_TO_TOP8,
        input  AXI_M_IO_E_4_BASE_TO_TOP9,
        input  AXI_M_IO_E_4_BASE_TO_TOP10,
        input  AXI_M_IO_E_4_BASE_TO_TOP11,
        input  AXI_M_IO_E_4_BASE_TO_TOP12,
        input  AXI_M_IO_E_4_BASE_TO_TOP13,
        input  AXI_M_IO_E_4_BASE_TO_TOP14,
        input  AXI_M_IO_E_4_BASE_TO_TOP15,
        input  AXI_M_IO_E_4_BASE_TO_TOP16,
        input  AXI_M_IO_E_4_BASE_TO_TOP17,
        input  AXI_M_IO_E_4_BASE_TO_TOP18,
        input  AXI_M_IO_E_4_BASE_TO_TOP19,
        input  AXI_M_IO_E_4_BASE_TO_TOP20,
        input  AXI_M_IO_E_4_BASE_TO_TOP21,
        input  AXI_M_IO_E_4_BASE_TO_TOP22,
        input  AXI_M_IO_E_4_BASE_TO_TOP23,
        input  AXI_M_IO_E_3_BASE_TO_TOP0,
        input  AXI_M_IO_E_3_BASE_TO_TOP1,
        input  AXI_M_IO_E_3_BASE_TO_TOP2,
        input  AXI_M_IO_E_3_BASE_TO_TOP3,
        input  AXI_M_IO_E_3_BASE_TO_TOP4,
        input  AXI_M_IO_E_3_BASE_TO_TOP5,
        input  AXI_M_IO_E_3_BASE_TO_TOP6,
        input  AXI_M_IO_E_3_BASE_TO_TOP7,
        input  AXI_M_IO_E_3_BASE_TO_TOP8,
        input  AXI_M_IO_E_3_BASE_TO_TOP9,
        input  AXI_M_IO_E_3_BASE_TO_TOP10,
        input  AXI_M_IO_E_3_BASE_TO_TOP11,
        input  AXI_M_IO_E_3_BASE_TO_TOP12,
        input  AXI_M_IO_E_3_BASE_TO_TOP13,
        input  AXI_M_IO_E_3_BASE_TO_TOP14,
        input  AXI_M_IO_E_3_BASE_TO_TOP15,
        input  AXI_M_IO_E_3_BASE_TO_TOP16,
        input  AXI_M_IO_E_3_BASE_TO_TOP17,
        input  AXI_M_IO_E_3_BASE_TO_TOP18,
        input  AXI_M_IO_E_3_BASE_TO_TOP19,
        input  AXI_M_IO_E_3_BASE_TO_TOP20,
        input  AXI_M_IO_E_3_BASE_TO_TOP21,
        input  AXI_M_IO_E_3_BASE_TO_TOP22,
        input  AXI_M_IO_E_3_BASE_TO_TOP23,
        input  AXI_M_IO_E_2_BASE_TO_TOP0,
        input  AXI_M_IO_E_2_BASE_TO_TOP1,
        input  AXI_M_IO_E_2_BASE_TO_TOP2,
        input  AXI_M_IO_E_2_BASE_TO_TOP3,
        input  AXI_M_IO_E_2_BASE_TO_TOP4,
        input  AXI_M_IO_E_2_BASE_TO_TOP5,
        input  AXI_M_IO_E_2_BASE_TO_TOP6,
        input  AXI_M_IO_E_2_BASE_TO_TOP7,
        input  AXI_M_IO_E_2_BASE_TO_TOP8,
        input  AXI_M_IO_E_2_BASE_TO_TOP9,
        input  AXI_M_IO_E_2_BASE_TO_TOP10,
        input  AXI_M_IO_E_2_BASE_TO_TOP11,
        input  AXI_M_IO_E_2_BASE_TO_TOP12,
        input  AXI_M_IO_E_2_BASE_TO_TOP13,
        input  AXI_M_IO_E_2_BASE_TO_TOP14,
        input  AXI_M_IO_E_2_BASE_TO_TOP15,
        input  AXI_M_IO_E_2_BASE_TO_TOP16,
        input  AXI_M_IO_E_2_BASE_TO_TOP17,
        input  AXI_M_IO_E_2_BASE_TO_TOP18,
        input  AXI_M_IO_E_2_BASE_TO_TOP19,
        input  AXI_M_IO_E_2_BASE_TO_TOP20,
        input  AXI_M_IO_E_2_BASE_TO_TOP21,
        input  AXI_M_IO_E_2_BASE_TO_TOP22,
        input  AXI_M_IO_E_2_BASE_TO_TOP23,
        input  AXI_M_IO_E_1_BASE_TO_TOP0,
        input  AXI_M_IO_E_1_BASE_TO_TOP1,
        input  AXI_M_IO_E_1_BASE_TO_TOP2,
        input  AXI_M_IO_E_1_BASE_TO_TOP3,
        input  AXI_M_IO_E_1_BASE_TO_TOP4,
        input  AXI_M_IO_E_1_BASE_TO_TOP5,
        input  AXI_M_IO_E_1_BASE_TO_TOP6,
        input  AXI_M_IO_E_1_BASE_TO_TOP7,
        input  AXI_M_IO_E_1_BASE_TO_TOP8,
        input  AXI_M_IO_E_1_BASE_TO_TOP9,
        input  AXI_M_IO_E_1_BASE_TO_TOP10,
        input  AXI_M_IO_E_1_BASE_TO_TOP11,
        input  AXI_M_IO_E_1_BASE_TO_TOP12,
        input  AXI_M_IO_E_1_BASE_TO_TOP13,
        input  AXI_M_IO_E_1_BASE_TO_TOP14,
        input  AXI_M_IO_E_1_BASE_TO_TOP15,
        input  AXI_M_IO_E_1_BASE_TO_TOP16,
        input  AXI_M_IO_E_1_BASE_TO_TOP17,
        input  AXI_M_IO_E_1_BASE_TO_TOP18,
        input  AXI_M_IO_E_1_BASE_TO_TOP19,
        input  AXI_M_IO_E_1_BASE_TO_TOP20,
        input  AXI_M_IO_E_1_BASE_TO_TOP21,
        input  AXI_M_IO_E_1_BASE_TO_TOP22,
        input  AXI_M_IO_E_1_BASE_TO_TOP23,
        input  AXI_M_IO_E_0_BASE_TO_TOP0,
        input  AXI_M_IO_E_0_BASE_TO_TOP1,
        input  AXI_M_IO_E_0_BASE_TO_TOP2,
        input  AXI_M_IO_E_0_BASE_TO_TOP3,
        input  AXI_M_IO_E_0_BASE_TO_TOP4,
        input  AXI_M_IO_E_0_BASE_TO_TOP5,
        input  AXI_M_IO_E_0_BASE_TO_TOP6,
        input  AXI_M_IO_E_0_BASE_TO_TOP7,
        input  AXI_M_IO_E_0_BASE_TO_TOP8,
        input  AXI_M_IO_E_0_BASE_TO_TOP9,
        input  AXI_M_IO_E_0_BASE_TO_TOP10,
        input  AXI_M_IO_E_0_BASE_TO_TOP11,
        input  AXI_M_IO_E_0_BASE_TO_TOP12,
        input  AXI_M_IO_E_0_BASE_TO_TOP13,
        input  AXI_M_IO_E_0_BASE_TO_TOP14,
        input  AXI_M_IO_E_0_BASE_TO_TOP15,
        input  AXI_M_IO_E_0_BASE_TO_TOP16,
        input  AXI_M_IO_E_0_BASE_TO_TOP17,
        input  AXI_M_IO_E_0_BASE_TO_TOP18,
        input  AXI_M_IO_E_0_BASE_TO_TOP19,
        input  AXI_M_IO_E_0_BASE_TO_TOP20,
        input  AXI_M_IO_E_0_BASE_TO_TOP21,
        input  AXI_M_IO_E_0_BASE_TO_TOP22,
        input  AXI_M_IO_E_0_BASE_TO_TOP23,
 //BEL input ports (SM outputs)
        output  AXI_M_FAB_AWADDR0,
        output  AXI_M_FAB_AWADDR1,
        output  AXI_M_FAB_AWADDR2,
        output  AXI_M_FAB_AWADDR3,
        output  AXI_M_FAB_AWADDR4,
        output  AXI_M_FAB_AWADDR5,
        output  AXI_M_FAB_AWADDR6,
        output  AXI_M_FAB_AWADDR7,
        output  AXI_M_FAB_AWADDR8,
        output  AXI_M_FAB_AWADDR9,
        output  AXI_M_FAB_AWADDR10,
        output  AXI_M_FAB_AWADDR11,
        output  AXI_M_FAB_AWADDR12,
        output  AXI_M_FAB_AWADDR13,
        output  AXI_M_FAB_AWADDR14,
        output  AXI_M_FAB_AWADDR15,
        output  AXI_M_FAB_AWADDR16,
        output  AXI_M_FAB_AWADDR17,
        output  AXI_M_FAB_AWADDR18,
        output  AXI_M_FAB_AWADDR19,
        output  AXI_M_FAB_AWADDR20,
        output  AXI_M_FAB_AWADDR21,
        output  AXI_M_FAB_AWADDR22,
        output  AXI_M_FAB_AWADDR23,
        output  AXI_M_FAB_AWADDR24,
        output  AXI_M_FAB_AWADDR25,
        output  AXI_M_FAB_AWADDR26,
        output  AXI_M_FAB_AWADDR27,
        output  AXI_M_FAB_AWADDR28,
        output  AXI_M_FAB_AWADDR29,
        output  AXI_M_FAB_AWADDR30,
        output  AXI_M_FAB_AWADDR31,
        output  AXI_M_FAB_AWLEN0,
        output  AXI_M_FAB_AWLEN1,
        output  AXI_M_FAB_AWLEN2,
        output  AXI_M_FAB_AWLEN3,
        output  AXI_M_FAB_AWLEN4,
        output  AXI_M_FAB_AWLEN5,
        output  AXI_M_FAB_AWLEN6,
        output  AXI_M_FAB_AWLEN7,
        output  AXI_M_FAB_AWSIZE0,
        output  AXI_M_FAB_AWSIZE1,
        output  AXI_M_FAB_AWSIZE2,
        output  AXI_M_FAB_AWBURST0,
        output  AXI_M_FAB_AWBURST1,
        output  AXI_M_FAB_AWVALID,
        output  AXI_M_FAB_WDATA0,
        output  AXI_M_FAB_WDATA1,
        output  AXI_M_FAB_WDATA2,
        output  AXI_M_FAB_WDATA3,
        output  AXI_M_FAB_WDATA4,
        output  AXI_M_FAB_WDATA5,
        output  AXI_M_FAB_WDATA6,
        output  AXI_M_FAB_WDATA7,
        output  AXI_M_FAB_WDATA8,
        output  AXI_M_FAB_WDATA9,
        output  AXI_M_FAB_WDATA10,
        output  AXI_M_FAB_WDATA11,
        output  AXI_M_FAB_WDATA12,
        output  AXI_M_FAB_WDATA13,
        output  AXI_M_FAB_WDATA14,
        output  AXI_M_FAB_WDATA15,
        output  AXI_M_FAB_WDATA16,
        output  AXI_M_FAB_WDATA17,
        output  AXI_M_FAB_WDATA18,
        output  AXI_M_FAB_WDATA19,
        output  AXI_M_FAB_WDATA20,
        output  AXI_M_FAB_WDATA21,
        output  AXI_M_FAB_WDATA22,
        output  AXI_M_FAB_WDATA23,
        output  AXI_M_FAB_WDATA24,
        output  AXI_M_FAB_WDATA25,
        output  AXI_M_FAB_WDATA26,
        output  AXI_M_FAB_WDATA27,
        output  AXI_M_FAB_WDATA28,
        output  AXI_M_FAB_WDATA29,
        output  AXI_M_FAB_WDATA30,
        output  AXI_M_FAB_WDATA31,
        output  AXI_M_FAB_WSTRB0,
        output  AXI_M_FAB_WSTRB1,
        output  AXI_M_FAB_WSTRB2,
        output  AXI_M_FAB_WSTRB3,
        output  AXI_M_FAB_WLAST,
        output  AXI_M_FAB_WVALID,
        output  AXI_M_FAB_BREADY,
        output  AXI_M_FAB_ARADDR0,
        output  AXI_M_FAB_ARADDR1,
        output  AXI_M_FAB_ARADDR2,
        output  AXI_M_FAB_ARADDR3,
        output  AXI_M_FAB_ARADDR4,
        output  AXI_M_FAB_ARADDR5,
        output  AXI_M_FAB_ARADDR6,
        output  AXI_M_FAB_ARADDR7,
        output  AXI_M_FAB_ARADDR8,
        output  AXI_M_FAB_ARADDR9,
        output  AXI_M_FAB_ARADDR10,
        output  AXI_M_FAB_ARADDR11,
        output  AXI_M_FAB_ARADDR12,
        output  AXI_M_FAB_ARADDR13,
        output  AXI_M_FAB_ARADDR14,
        output  AXI_M_FAB_ARADDR15,
        output  AXI_M_FAB_ARADDR16,
        output  AXI_M_FAB_ARADDR17,
        output  AXI_M_FAB_ARADDR18,
        output  AXI_M_FAB_ARADDR19,
        output  AXI_M_FAB_ARADDR20,
        output  AXI_M_FAB_ARADDR21,
        output  AXI_M_FAB_ARADDR22,
        output  AXI_M_FAB_ARADDR23,
        output  AXI_M_FAB_ARADDR24,
        output  AXI_M_FAB_ARADDR25,
        output  AXI_M_FAB_ARADDR26,
        output  AXI_M_FAB_ARADDR27,
        output  AXI_M_FAB_ARADDR28,
        output  AXI_M_FAB_ARADDR29,
        output  AXI_M_FAB_ARADDR30,
        output  AXI_M_FAB_ARADDR31,
        output  AXI_M_FAB_ARLEN0,
        output  AXI_M_FAB_ARLEN1,
        output  AXI_M_FAB_ARLEN2,
        output  AXI_M_FAB_ARLEN3,
        output  AXI_M_FAB_ARLEN4,
        output  AXI_M_FAB_ARLEN5,
        output  AXI_M_FAB_ARLEN6,
        output  AXI_M_FAB_ARLEN7,
        output  AXI_M_FAB_ARSIZE0,
        output  AXI_M_FAB_ARSIZE1,
        output  AXI_M_FAB_ARSIZE2,
        output  AXI_M_FAB_ARBURST0,
        output  AXI_M_FAB_ARBURST1,
        output  AXI_M_FAB_ARVALID,
        output  AXI_M_FAB_RREADY,
 //BEL output ports (SM inputs)
        input  AXI_M_FAB_AWREADY,
        input  AXI_M_FAB_WREADY,
        input  AXI_M_FAB_BRESP0,
        input  AXI_M_FAB_BRESP1,
        input  AXI_M_FAB_BVALID,
        input  AXI_M_FAB_ARREADY,
        input  AXI_M_FAB_RDATA0,
        input  AXI_M_FAB_RDATA1,
        input  AXI_M_FAB_RDATA2,
        input  AXI_M_FAB_RDATA3,
        input  AXI_M_FAB_RDATA4,
        input  AXI_M_FAB_RDATA5,
        input  AXI_M_FAB_RDATA6,
        input  AXI_M_FAB_RDATA7,
        input  AXI_M_FAB_RDATA8,
        input  AXI_M_FAB_RDATA9,
        input  AXI_M_FAB_RDATA10,
        input  AXI_M_FAB_RDATA11,
        input  AXI_M_FAB_RDATA12,
        input  AXI_M_FAB_RDATA13,
        input  AXI_M_FAB_RDATA14,
        input  AXI_M_FAB_RDATA15,
        input  AXI_M_FAB_RDATA16,
        input  AXI_M_FAB_RDATA17,
        input  AXI_M_FAB_RDATA18,
        input  AXI_M_FAB_RDATA19,
        input  AXI_M_FAB_RDATA20,
        input  AXI_M_FAB_RDATA21,
        input  AXI_M_FAB_RDATA22,
        input  AXI_M_FAB_RDATA23,
        input  AXI_M_FAB_RDATA24,
        input  AXI_M_FAB_RDATA25,
        input  AXI_M_FAB_RDATA26,
        input  AXI_M_FAB_RDATA27,
        input  AXI_M_FAB_RDATA28,
        input  AXI_M_FAB_RDATA29,
        input  AXI_M_FAB_RDATA30,
        input  AXI_M_FAB_RDATA31,
        input  AXI_M_FAB_RRESP0,
        input  AXI_M_FAB_RRESP1,
        input  AXI_M_FAB_RLAST,
        input  AXI_M_FAB_RVALID,
 //Reverse SJUMP outputs (SM -> child tile)
        output  AXI_M_IO_E_5_TOP_TO_BASE0,
        output  AXI_M_IO_E_5_TOP_TO_BASE1,
        output  AXI_M_IO_E_5_TOP_TO_BASE2,
        output  AXI_M_IO_E_5_TOP_TO_BASE3,
        output  AXI_M_IO_E_5_TOP_TO_BASE4,
        output  AXI_M_IO_E_5_TOP_TO_BASE5,
        output  AXI_M_IO_E_5_TOP_TO_BASE6,
        output  AXI_M_IO_E_5_TOP_TO_BASE7,
        output  AXI_M_IO_E_4_TOP_TO_BASE0,
        output  AXI_M_IO_E_4_TOP_TO_BASE1,
        output  AXI_M_IO_E_4_TOP_TO_BASE2,
        output  AXI_M_IO_E_4_TOP_TO_BASE3,
        output  AXI_M_IO_E_4_TOP_TO_BASE4,
        output  AXI_M_IO_E_4_TOP_TO_BASE5,
        output  AXI_M_IO_E_4_TOP_TO_BASE6,
        output  AXI_M_IO_E_4_TOP_TO_BASE7,
        output  AXI_M_IO_E_3_TOP_TO_BASE0,
        output  AXI_M_IO_E_3_TOP_TO_BASE1,
        output  AXI_M_IO_E_3_TOP_TO_BASE2,
        output  AXI_M_IO_E_3_TOP_TO_BASE3,
        output  AXI_M_IO_E_3_TOP_TO_BASE4,
        output  AXI_M_IO_E_3_TOP_TO_BASE5,
        output  AXI_M_IO_E_3_TOP_TO_BASE6,
        output  AXI_M_IO_E_3_TOP_TO_BASE7,
        output  AXI_M_IO_E_2_TOP_TO_BASE0,
        output  AXI_M_IO_E_2_TOP_TO_BASE1,
        output  AXI_M_IO_E_2_TOP_TO_BASE2,
        output  AXI_M_IO_E_2_TOP_TO_BASE3,
        output  AXI_M_IO_E_2_TOP_TO_BASE4,
        output  AXI_M_IO_E_2_TOP_TO_BASE5,
        output  AXI_M_IO_E_2_TOP_TO_BASE6,
        output  AXI_M_IO_E_2_TOP_TO_BASE7,
        output  AXI_M_IO_E_1_TOP_TO_BASE0,
        output  AXI_M_IO_E_1_TOP_TO_BASE1,
        output  AXI_M_IO_E_1_TOP_TO_BASE2,
        output  AXI_M_IO_E_1_TOP_TO_BASE3,
        output  AXI_M_IO_E_1_TOP_TO_BASE4,
        output  AXI_M_IO_E_1_TOP_TO_BASE5,
        output  AXI_M_IO_E_1_TOP_TO_BASE6,
        output  AXI_M_IO_E_1_TOP_TO_BASE7,
        output  AXI_M_IO_E_0_TOP_TO_BASE0,
        output  AXI_M_IO_E_0_TOP_TO_BASE1,
        output  AXI_M_IO_E_0_TOP_TO_BASE2,
        output  AXI_M_IO_E_0_TOP_TO_BASE3,
        output  AXI_M_IO_E_0_TOP_TO_BASE4,
        output  AXI_M_IO_E_0_TOP_TO_BASE5,
        output  AXI_M_IO_E_0_TOP_TO_BASE6,
        output  AXI_M_IO_E_0_TOP_TO_BASE7,
 //global
        input  [NoConfigBits-1:0] ConfigBits,
        input  [NoConfigBits-1:0] ConfigBits_N
);
parameter GND0 = 1'b0;
parameter GND = 1'b0;
parameter VCC0 = 1'b1;
parameter VCC = 1'b1;
parameter VDD0 = 1'b1;
parameter VDD = 1'b1;

wire[4-1:0] AXI_M_IO_E_0_TOP_TO_BASE5_input;
wire[4-1:0] AXI_M_IO_E_0_TOP_TO_BASE4_input;
wire[4-1:0] AXI_M_IO_E_0_TOP_TO_BASE3_input;
wire[4-1:0] AXI_M_IO_E_0_TOP_TO_BASE2_input;
wire[4-1:0] AXI_M_IO_E_0_TOP_TO_BASE1_input;
wire[4-1:0] AXI_M_IO_E_0_TOP_TO_BASE0_input;
 //The configuration bits (if any) are just a long shift register
 //This shift register is padded to an even number of flops/latches
 //switch matrix multiplexer AXI_M_IO_E_5_TOP_TO_BASE7 MUX-1
assign AXI_M_IO_E_5_TOP_TO_BASE7 = AXI_M_FAB_AWREADY;

 //switch matrix multiplexer AXI_M_IO_E_5_TOP_TO_BASE6 MUX-1
assign AXI_M_IO_E_5_TOP_TO_BASE6 = AXI_M_FAB_WREADY;

 //switch matrix multiplexer AXI_M_IO_E_5_TOP_TO_BASE5 MUX-1
assign AXI_M_IO_E_5_TOP_TO_BASE5 = AXI_M_FAB_BRESP1;

 //switch matrix multiplexer AXI_M_IO_E_5_TOP_TO_BASE4 MUX-1
assign AXI_M_IO_E_5_TOP_TO_BASE4 = AXI_M_FAB_BRESP0;

 //switch matrix multiplexer AXI_M_IO_E_5_TOP_TO_BASE3 MUX-1
assign AXI_M_IO_E_5_TOP_TO_BASE3 = AXI_M_FAB_BVALID;

 //switch matrix multiplexer AXI_M_IO_E_5_TOP_TO_BASE2 MUX-1
assign AXI_M_IO_E_5_TOP_TO_BASE2 = AXI_M_FAB_ARREADY;

 //switch matrix multiplexer AXI_M_IO_E_5_TOP_TO_BASE1 MUX-1
assign AXI_M_IO_E_5_TOP_TO_BASE1 = AXI_M_FAB_RDATA31;

 //switch matrix multiplexer AXI_M_IO_E_5_TOP_TO_BASE0 MUX-1
assign AXI_M_IO_E_5_TOP_TO_BASE0 = AXI_M_FAB_RDATA30;

 //switch matrix multiplexer AXI_M_IO_E_4_TOP_TO_BASE7 MUX-1
assign AXI_M_IO_E_4_TOP_TO_BASE7 = AXI_M_FAB_RDATA29;

 //switch matrix multiplexer AXI_M_IO_E_4_TOP_TO_BASE6 MUX-1
assign AXI_M_IO_E_4_TOP_TO_BASE6 = AXI_M_FAB_RDATA28;

 //switch matrix multiplexer AXI_M_IO_E_4_TOP_TO_BASE5 MUX-1
assign AXI_M_IO_E_4_TOP_TO_BASE5 = AXI_M_FAB_RDATA27;

 //switch matrix multiplexer AXI_M_IO_E_4_TOP_TO_BASE4 MUX-1
assign AXI_M_IO_E_4_TOP_TO_BASE4 = AXI_M_FAB_RDATA26;

 //switch matrix multiplexer AXI_M_IO_E_4_TOP_TO_BASE3 MUX-1
assign AXI_M_IO_E_4_TOP_TO_BASE3 = AXI_M_FAB_RDATA25;

 //switch matrix multiplexer AXI_M_IO_E_4_TOP_TO_BASE2 MUX-1
assign AXI_M_IO_E_4_TOP_TO_BASE2 = AXI_M_FAB_RDATA24;

 //switch matrix multiplexer AXI_M_IO_E_4_TOP_TO_BASE1 MUX-1
assign AXI_M_IO_E_4_TOP_TO_BASE1 = AXI_M_FAB_RDATA23;

 //switch matrix multiplexer AXI_M_IO_E_4_TOP_TO_BASE0 MUX-1
assign AXI_M_IO_E_4_TOP_TO_BASE0 = AXI_M_FAB_RDATA22;

 //switch matrix multiplexer AXI_M_IO_E_3_TOP_TO_BASE7 MUX-1
assign AXI_M_IO_E_3_TOP_TO_BASE7 = AXI_M_FAB_RDATA21;

 //switch matrix multiplexer AXI_M_IO_E_3_TOP_TO_BASE6 MUX-1
assign AXI_M_IO_E_3_TOP_TO_BASE6 = AXI_M_FAB_RDATA20;

 //switch matrix multiplexer AXI_M_IO_E_3_TOP_TO_BASE5 MUX-1
assign AXI_M_IO_E_3_TOP_TO_BASE5 = AXI_M_FAB_RDATA19;

 //switch matrix multiplexer AXI_M_IO_E_3_TOP_TO_BASE4 MUX-1
assign AXI_M_IO_E_3_TOP_TO_BASE4 = AXI_M_FAB_RDATA18;

 //switch matrix multiplexer AXI_M_IO_E_3_TOP_TO_BASE3 MUX-1
assign AXI_M_IO_E_3_TOP_TO_BASE3 = AXI_M_FAB_RDATA17;

 //switch matrix multiplexer AXI_M_IO_E_3_TOP_TO_BASE2 MUX-1
assign AXI_M_IO_E_3_TOP_TO_BASE2 = AXI_M_FAB_RDATA16;

 //switch matrix multiplexer AXI_M_IO_E_3_TOP_TO_BASE1 MUX-1
assign AXI_M_IO_E_3_TOP_TO_BASE1 = AXI_M_FAB_RDATA15;

 //switch matrix multiplexer AXI_M_IO_E_3_TOP_TO_BASE0 MUX-1
assign AXI_M_IO_E_3_TOP_TO_BASE0 = AXI_M_FAB_RDATA14;

 //switch matrix multiplexer AXI_M_IO_E_2_TOP_TO_BASE7 MUX-1
assign AXI_M_IO_E_2_TOP_TO_BASE7 = AXI_M_FAB_RDATA13;

 //switch matrix multiplexer AXI_M_IO_E_2_TOP_TO_BASE6 MUX-1
assign AXI_M_IO_E_2_TOP_TO_BASE6 = AXI_M_FAB_RDATA12;

 //switch matrix multiplexer AXI_M_IO_E_2_TOP_TO_BASE5 MUX-1
assign AXI_M_IO_E_2_TOP_TO_BASE5 = AXI_M_FAB_RDATA11;

 //switch matrix multiplexer AXI_M_IO_E_2_TOP_TO_BASE4 MUX-1
assign AXI_M_IO_E_2_TOP_TO_BASE4 = AXI_M_FAB_RDATA10;

 //switch matrix multiplexer AXI_M_IO_E_2_TOP_TO_BASE3 MUX-1
assign AXI_M_IO_E_2_TOP_TO_BASE3 = AXI_M_FAB_RDATA9;

 //switch matrix multiplexer AXI_M_IO_E_2_TOP_TO_BASE2 MUX-1
assign AXI_M_IO_E_2_TOP_TO_BASE2 = AXI_M_FAB_RDATA8;

 //switch matrix multiplexer AXI_M_IO_E_2_TOP_TO_BASE1 MUX-1
assign AXI_M_IO_E_2_TOP_TO_BASE1 = AXI_M_FAB_RDATA7;

 //switch matrix multiplexer AXI_M_IO_E_2_TOP_TO_BASE0 MUX-1
assign AXI_M_IO_E_2_TOP_TO_BASE0 = AXI_M_FAB_RDATA6;

 //switch matrix multiplexer AXI_M_IO_E_1_TOP_TO_BASE7 MUX-1
assign AXI_M_IO_E_1_TOP_TO_BASE7 = AXI_M_FAB_RDATA5;

 //switch matrix multiplexer AXI_M_IO_E_1_TOP_TO_BASE6 MUX-1
assign AXI_M_IO_E_1_TOP_TO_BASE6 = AXI_M_FAB_RDATA4;

 //switch matrix multiplexer AXI_M_IO_E_1_TOP_TO_BASE5 MUX-1
assign AXI_M_IO_E_1_TOP_TO_BASE5 = AXI_M_FAB_RDATA3;

 //switch matrix multiplexer AXI_M_IO_E_1_TOP_TO_BASE4 MUX-1
assign AXI_M_IO_E_1_TOP_TO_BASE4 = AXI_M_FAB_RDATA2;

 //switch matrix multiplexer AXI_M_IO_E_1_TOP_TO_BASE3 MUX-1
assign AXI_M_IO_E_1_TOP_TO_BASE3 = AXI_M_FAB_RDATA1;

 //switch matrix multiplexer AXI_M_IO_E_1_TOP_TO_BASE2 MUX-1
assign AXI_M_IO_E_1_TOP_TO_BASE2 = AXI_M_FAB_RDATA0;

 //switch matrix multiplexer AXI_M_IO_E_1_TOP_TO_BASE1 MUX-1
assign AXI_M_IO_E_1_TOP_TO_BASE1 = AXI_M_FAB_RRESP1;

 //switch matrix multiplexer AXI_M_IO_E_1_TOP_TO_BASE0 MUX-1
assign AXI_M_IO_E_1_TOP_TO_BASE0 = AXI_M_FAB_RRESP0;

 //switch matrix multiplexer AXI_M_IO_E_0_TOP_TO_BASE7 MUX-1
assign AXI_M_IO_E_0_TOP_TO_BASE7 = AXI_M_FAB_RLAST;

 //switch matrix multiplexer AXI_M_IO_E_0_TOP_TO_BASE6 MUX-1
assign AXI_M_IO_E_0_TOP_TO_BASE6 = AXI_M_FAB_RVALID;

 //switch matrix multiplexer AXI_M_FAB_AWADDR31 MUX-1
assign AXI_M_FAB_AWADDR31 = AXI_M_IO_E_5_BASE_TO_TOP23;

 //switch matrix multiplexer AXI_M_FAB_AWADDR30 MUX-1
assign AXI_M_FAB_AWADDR30 = AXI_M_IO_E_5_BASE_TO_TOP22;

 //switch matrix multiplexer AXI_M_FAB_AWADDR29 MUX-1
assign AXI_M_FAB_AWADDR29 = AXI_M_IO_E_5_BASE_TO_TOP21;

 //switch matrix multiplexer AXI_M_FAB_AWADDR28 MUX-1
assign AXI_M_FAB_AWADDR28 = AXI_M_IO_E_5_BASE_TO_TOP20;

 //switch matrix multiplexer AXI_M_FAB_AWADDR27 MUX-1
assign AXI_M_FAB_AWADDR27 = AXI_M_IO_E_5_BASE_TO_TOP19;

 //switch matrix multiplexer AXI_M_FAB_AWADDR26 MUX-1
assign AXI_M_FAB_AWADDR26 = AXI_M_IO_E_5_BASE_TO_TOP18;

 //switch matrix multiplexer AXI_M_FAB_AWADDR25 MUX-1
assign AXI_M_FAB_AWADDR25 = AXI_M_IO_E_5_BASE_TO_TOP17;

 //switch matrix multiplexer AXI_M_FAB_AWADDR24 MUX-1
assign AXI_M_FAB_AWADDR24 = AXI_M_IO_E_5_BASE_TO_TOP16;

 //switch matrix multiplexer AXI_M_FAB_AWADDR23 MUX-1
assign AXI_M_FAB_AWADDR23 = AXI_M_IO_E_5_BASE_TO_TOP15;

 //switch matrix multiplexer AXI_M_FAB_AWADDR22 MUX-1
assign AXI_M_FAB_AWADDR22 = AXI_M_IO_E_5_BASE_TO_TOP14;

 //switch matrix multiplexer AXI_M_FAB_AWADDR21 MUX-1
assign AXI_M_FAB_AWADDR21 = AXI_M_IO_E_5_BASE_TO_TOP13;

 //switch matrix multiplexer AXI_M_FAB_AWADDR20 MUX-1
assign AXI_M_FAB_AWADDR20 = AXI_M_IO_E_5_BASE_TO_TOP12;

 //switch matrix multiplexer AXI_M_FAB_AWADDR19 MUX-1
assign AXI_M_FAB_AWADDR19 = AXI_M_IO_E_5_BASE_TO_TOP11;

 //switch matrix multiplexer AXI_M_FAB_AWADDR18 MUX-1
assign AXI_M_FAB_AWADDR18 = AXI_M_IO_E_5_BASE_TO_TOP10;

 //switch matrix multiplexer AXI_M_FAB_AWADDR17 MUX-1
assign AXI_M_FAB_AWADDR17 = AXI_M_IO_E_5_BASE_TO_TOP9;

 //switch matrix multiplexer AXI_M_FAB_AWADDR16 MUX-1
assign AXI_M_FAB_AWADDR16 = AXI_M_IO_E_5_BASE_TO_TOP8;

 //switch matrix multiplexer AXI_M_FAB_AWADDR15 MUX-1
assign AXI_M_FAB_AWADDR15 = AXI_M_IO_E_5_BASE_TO_TOP7;

 //switch matrix multiplexer AXI_M_FAB_AWADDR14 MUX-1
assign AXI_M_FAB_AWADDR14 = AXI_M_IO_E_5_BASE_TO_TOP6;

 //switch matrix multiplexer AXI_M_FAB_AWADDR13 MUX-1
assign AXI_M_FAB_AWADDR13 = AXI_M_IO_E_5_BASE_TO_TOP5;

 //switch matrix multiplexer AXI_M_FAB_AWADDR12 MUX-1
assign AXI_M_FAB_AWADDR12 = AXI_M_IO_E_5_BASE_TO_TOP4;

 //switch matrix multiplexer AXI_M_FAB_AWADDR11 MUX-1
assign AXI_M_FAB_AWADDR11 = AXI_M_IO_E_5_BASE_TO_TOP3;

 //switch matrix multiplexer AXI_M_FAB_AWADDR10 MUX-1
assign AXI_M_FAB_AWADDR10 = AXI_M_IO_E_5_BASE_TO_TOP2;

 //switch matrix multiplexer AXI_M_FAB_AWADDR9 MUX-1
assign AXI_M_FAB_AWADDR9 = AXI_M_IO_E_5_BASE_TO_TOP1;

 //switch matrix multiplexer AXI_M_FAB_AWADDR8 MUX-1
assign AXI_M_FAB_AWADDR8 = AXI_M_IO_E_5_BASE_TO_TOP0;

 //switch matrix multiplexer AXI_M_FAB_AWADDR7 MUX-1
assign AXI_M_FAB_AWADDR7 = AXI_M_IO_E_4_BASE_TO_TOP23;

 //switch matrix multiplexer AXI_M_FAB_AWADDR6 MUX-1
assign AXI_M_FAB_AWADDR6 = AXI_M_IO_E_4_BASE_TO_TOP22;

 //switch matrix multiplexer AXI_M_FAB_AWADDR5 MUX-1
assign AXI_M_FAB_AWADDR5 = AXI_M_IO_E_4_BASE_TO_TOP21;

 //switch matrix multiplexer AXI_M_FAB_AWADDR4 MUX-1
assign AXI_M_FAB_AWADDR4 = AXI_M_IO_E_4_BASE_TO_TOP20;

 //switch matrix multiplexer AXI_M_FAB_AWADDR3 MUX-1
assign AXI_M_FAB_AWADDR3 = AXI_M_IO_E_4_BASE_TO_TOP19;

 //switch matrix multiplexer AXI_M_FAB_AWADDR2 MUX-1
assign AXI_M_FAB_AWADDR2 = AXI_M_IO_E_4_BASE_TO_TOP18;

 //switch matrix multiplexer AXI_M_FAB_AWADDR1 MUX-1
assign AXI_M_FAB_AWADDR1 = AXI_M_IO_E_4_BASE_TO_TOP17;

 //switch matrix multiplexer AXI_M_FAB_AWADDR0 MUX-1
assign AXI_M_FAB_AWADDR0 = AXI_M_IO_E_4_BASE_TO_TOP16;

 //switch matrix multiplexer AXI_M_FAB_AWLEN7 MUX-1
assign AXI_M_FAB_AWLEN7 = AXI_M_IO_E_4_BASE_TO_TOP15;

 //switch matrix multiplexer AXI_M_FAB_AWLEN6 MUX-1
assign AXI_M_FAB_AWLEN6 = AXI_M_IO_E_4_BASE_TO_TOP14;

 //switch matrix multiplexer AXI_M_FAB_AWLEN5 MUX-1
assign AXI_M_FAB_AWLEN5 = AXI_M_IO_E_4_BASE_TO_TOP13;

 //switch matrix multiplexer AXI_M_FAB_AWLEN4 MUX-1
assign AXI_M_FAB_AWLEN4 = AXI_M_IO_E_4_BASE_TO_TOP12;

 //switch matrix multiplexer AXI_M_FAB_AWLEN3 MUX-1
assign AXI_M_FAB_AWLEN3 = AXI_M_IO_E_4_BASE_TO_TOP11;

 //switch matrix multiplexer AXI_M_FAB_AWLEN2 MUX-1
assign AXI_M_FAB_AWLEN2 = AXI_M_IO_E_4_BASE_TO_TOP10;

 //switch matrix multiplexer AXI_M_FAB_AWLEN1 MUX-1
assign AXI_M_FAB_AWLEN1 = AXI_M_IO_E_4_BASE_TO_TOP9;

 //switch matrix multiplexer AXI_M_FAB_AWLEN0 MUX-1
assign AXI_M_FAB_AWLEN0 = AXI_M_IO_E_4_BASE_TO_TOP8;

 //switch matrix multiplexer AXI_M_FAB_AWSIZE2 MUX-1
assign AXI_M_FAB_AWSIZE2 = AXI_M_IO_E_4_BASE_TO_TOP7;

 //switch matrix multiplexer AXI_M_FAB_AWSIZE1 MUX-1
assign AXI_M_FAB_AWSIZE1 = AXI_M_IO_E_4_BASE_TO_TOP6;

 //switch matrix multiplexer AXI_M_FAB_AWSIZE0 MUX-1
assign AXI_M_FAB_AWSIZE0 = AXI_M_IO_E_4_BASE_TO_TOP5;

 //switch matrix multiplexer AXI_M_FAB_AWBURST1 MUX-1
assign AXI_M_FAB_AWBURST1 = AXI_M_IO_E_4_BASE_TO_TOP4;

 //switch matrix multiplexer AXI_M_FAB_AWBURST0 MUX-1
assign AXI_M_FAB_AWBURST0 = AXI_M_IO_E_4_BASE_TO_TOP3;

 //switch matrix multiplexer AXI_M_FAB_AWVALID MUX-1
assign AXI_M_FAB_AWVALID = AXI_M_IO_E_4_BASE_TO_TOP2;

 //switch matrix multiplexer AXI_M_FAB_WDATA31 MUX-1
assign AXI_M_FAB_WDATA31 = AXI_M_IO_E_3_BASE_TO_TOP23;

 //switch matrix multiplexer AXI_M_FAB_WDATA30 MUX-1
assign AXI_M_FAB_WDATA30 = AXI_M_IO_E_3_BASE_TO_TOP22;

 //switch matrix multiplexer AXI_M_FAB_WDATA29 MUX-1
assign AXI_M_FAB_WDATA29 = AXI_M_IO_E_3_BASE_TO_TOP21;

 //switch matrix multiplexer AXI_M_FAB_WDATA28 MUX-1
assign AXI_M_FAB_WDATA28 = AXI_M_IO_E_3_BASE_TO_TOP20;

 //switch matrix multiplexer AXI_M_FAB_WDATA27 MUX-1
assign AXI_M_FAB_WDATA27 = AXI_M_IO_E_3_BASE_TO_TOP19;

 //switch matrix multiplexer AXI_M_FAB_WDATA26 MUX-1
assign AXI_M_FAB_WDATA26 = AXI_M_IO_E_3_BASE_TO_TOP18;

 //switch matrix multiplexer AXI_M_FAB_WDATA25 MUX-1
assign AXI_M_FAB_WDATA25 = AXI_M_IO_E_3_BASE_TO_TOP17;

 //switch matrix multiplexer AXI_M_FAB_WDATA24 MUX-1
assign AXI_M_FAB_WDATA24 = AXI_M_IO_E_3_BASE_TO_TOP16;

 //switch matrix multiplexer AXI_M_FAB_WDATA23 MUX-1
assign AXI_M_FAB_WDATA23 = AXI_M_IO_E_3_BASE_TO_TOP15;

 //switch matrix multiplexer AXI_M_FAB_WDATA22 MUX-1
assign AXI_M_FAB_WDATA22 = AXI_M_IO_E_3_BASE_TO_TOP14;

 //switch matrix multiplexer AXI_M_FAB_WDATA21 MUX-1
assign AXI_M_FAB_WDATA21 = AXI_M_IO_E_3_BASE_TO_TOP13;

 //switch matrix multiplexer AXI_M_FAB_WDATA20 MUX-1
assign AXI_M_FAB_WDATA20 = AXI_M_IO_E_3_BASE_TO_TOP12;

 //switch matrix multiplexer AXI_M_FAB_WDATA19 MUX-1
assign AXI_M_FAB_WDATA19 = AXI_M_IO_E_3_BASE_TO_TOP11;

 //switch matrix multiplexer AXI_M_FAB_WDATA18 MUX-1
assign AXI_M_FAB_WDATA18 = AXI_M_IO_E_3_BASE_TO_TOP10;

 //switch matrix multiplexer AXI_M_FAB_WDATA17 MUX-1
assign AXI_M_FAB_WDATA17 = AXI_M_IO_E_3_BASE_TO_TOP9;

 //switch matrix multiplexer AXI_M_FAB_WDATA16 MUX-1
assign AXI_M_FAB_WDATA16 = AXI_M_IO_E_3_BASE_TO_TOP8;

 //switch matrix multiplexer AXI_M_FAB_WDATA15 MUX-1
assign AXI_M_FAB_WDATA15 = AXI_M_IO_E_3_BASE_TO_TOP7;

 //switch matrix multiplexer AXI_M_FAB_WDATA14 MUX-1
assign AXI_M_FAB_WDATA14 = AXI_M_IO_E_3_BASE_TO_TOP6;

 //switch matrix multiplexer AXI_M_FAB_WDATA13 MUX-1
assign AXI_M_FAB_WDATA13 = AXI_M_IO_E_3_BASE_TO_TOP5;

 //switch matrix multiplexer AXI_M_FAB_WDATA12 MUX-1
assign AXI_M_FAB_WDATA12 = AXI_M_IO_E_3_BASE_TO_TOP4;

 //switch matrix multiplexer AXI_M_FAB_WDATA11 MUX-1
assign AXI_M_FAB_WDATA11 = AXI_M_IO_E_3_BASE_TO_TOP3;

 //switch matrix multiplexer AXI_M_FAB_WDATA10 MUX-1
assign AXI_M_FAB_WDATA10 = AXI_M_IO_E_3_BASE_TO_TOP2;

 //switch matrix multiplexer AXI_M_FAB_WDATA9 MUX-1
assign AXI_M_FAB_WDATA9 = AXI_M_IO_E_3_BASE_TO_TOP1;

 //switch matrix multiplexer AXI_M_FAB_WDATA8 MUX-1
assign AXI_M_FAB_WDATA8 = AXI_M_IO_E_3_BASE_TO_TOP0;

 //switch matrix multiplexer AXI_M_FAB_WDATA7 MUX-1
assign AXI_M_FAB_WDATA7 = AXI_M_IO_E_2_BASE_TO_TOP23;

 //switch matrix multiplexer AXI_M_FAB_WDATA6 MUX-1
assign AXI_M_FAB_WDATA6 = AXI_M_IO_E_2_BASE_TO_TOP22;

 //switch matrix multiplexer AXI_M_FAB_WDATA5 MUX-1
assign AXI_M_FAB_WDATA5 = AXI_M_IO_E_2_BASE_TO_TOP21;

 //switch matrix multiplexer AXI_M_FAB_WDATA4 MUX-1
assign AXI_M_FAB_WDATA4 = AXI_M_IO_E_2_BASE_TO_TOP20;

 //switch matrix multiplexer AXI_M_FAB_WDATA3 MUX-1
assign AXI_M_FAB_WDATA3 = AXI_M_IO_E_2_BASE_TO_TOP19;

 //switch matrix multiplexer AXI_M_FAB_WDATA2 MUX-1
assign AXI_M_FAB_WDATA2 = AXI_M_IO_E_2_BASE_TO_TOP18;

 //switch matrix multiplexer AXI_M_FAB_WDATA1 MUX-1
assign AXI_M_FAB_WDATA1 = AXI_M_IO_E_2_BASE_TO_TOP17;

 //switch matrix multiplexer AXI_M_FAB_WDATA0 MUX-1
assign AXI_M_FAB_WDATA0 = AXI_M_IO_E_2_BASE_TO_TOP16;

 //switch matrix multiplexer AXI_M_FAB_WSTRB3 MUX-1
assign AXI_M_FAB_WSTRB3 = AXI_M_IO_E_2_BASE_TO_TOP15;

 //switch matrix multiplexer AXI_M_FAB_WSTRB2 MUX-1
assign AXI_M_FAB_WSTRB2 = AXI_M_IO_E_2_BASE_TO_TOP14;

 //switch matrix multiplexer AXI_M_FAB_WSTRB1 MUX-1
assign AXI_M_FAB_WSTRB1 = AXI_M_IO_E_2_BASE_TO_TOP13;

 //switch matrix multiplexer AXI_M_FAB_WSTRB0 MUX-1
assign AXI_M_FAB_WSTRB0 = AXI_M_IO_E_2_BASE_TO_TOP12;

 //switch matrix multiplexer AXI_M_FAB_WLAST MUX-1
assign AXI_M_FAB_WLAST = AXI_M_IO_E_2_BASE_TO_TOP11;

 //switch matrix multiplexer AXI_M_FAB_WVALID MUX-1
assign AXI_M_FAB_WVALID = AXI_M_IO_E_2_BASE_TO_TOP10;

 //switch matrix multiplexer AXI_M_FAB_BREADY MUX-1
assign AXI_M_FAB_BREADY = AXI_M_IO_E_2_BASE_TO_TOP9;

 //switch matrix multiplexer AXI_M_FAB_ARADDR31 MUX-1
assign AXI_M_FAB_ARADDR31 = AXI_M_IO_E_2_BASE_TO_TOP7;

 //switch matrix multiplexer AXI_M_FAB_ARADDR30 MUX-1
assign AXI_M_FAB_ARADDR30 = AXI_M_IO_E_2_BASE_TO_TOP6;

 //switch matrix multiplexer AXI_M_FAB_ARADDR29 MUX-1
assign AXI_M_FAB_ARADDR29 = AXI_M_IO_E_2_BASE_TO_TOP5;

 //switch matrix multiplexer AXI_M_FAB_ARADDR28 MUX-1
assign AXI_M_FAB_ARADDR28 = AXI_M_IO_E_2_BASE_TO_TOP4;

 //switch matrix multiplexer AXI_M_FAB_ARADDR27 MUX-1
assign AXI_M_FAB_ARADDR27 = AXI_M_IO_E_2_BASE_TO_TOP3;

 //switch matrix multiplexer AXI_M_FAB_ARADDR26 MUX-1
assign AXI_M_FAB_ARADDR26 = AXI_M_IO_E_2_BASE_TO_TOP2;

 //switch matrix multiplexer AXI_M_FAB_ARADDR25 MUX-1
assign AXI_M_FAB_ARADDR25 = AXI_M_IO_E_2_BASE_TO_TOP1;

 //switch matrix multiplexer AXI_M_FAB_ARADDR24 MUX-1
assign AXI_M_FAB_ARADDR24 = AXI_M_IO_E_2_BASE_TO_TOP0;

 //switch matrix multiplexer AXI_M_FAB_ARADDR23 MUX-1
assign AXI_M_FAB_ARADDR23 = AXI_M_IO_E_1_BASE_TO_TOP23;

 //switch matrix multiplexer AXI_M_FAB_ARADDR22 MUX-1
assign AXI_M_FAB_ARADDR22 = AXI_M_IO_E_1_BASE_TO_TOP22;

 //switch matrix multiplexer AXI_M_FAB_ARADDR21 MUX-1
assign AXI_M_FAB_ARADDR21 = AXI_M_IO_E_1_BASE_TO_TOP21;

 //switch matrix multiplexer AXI_M_FAB_ARADDR20 MUX-1
assign AXI_M_FAB_ARADDR20 = AXI_M_IO_E_1_BASE_TO_TOP20;

 //switch matrix multiplexer AXI_M_FAB_ARADDR19 MUX-1
assign AXI_M_FAB_ARADDR19 = AXI_M_IO_E_1_BASE_TO_TOP19;

 //switch matrix multiplexer AXI_M_FAB_ARADDR18 MUX-1
assign AXI_M_FAB_ARADDR18 = AXI_M_IO_E_1_BASE_TO_TOP18;

 //switch matrix multiplexer AXI_M_FAB_ARADDR17 MUX-1
assign AXI_M_FAB_ARADDR17 = AXI_M_IO_E_1_BASE_TO_TOP17;

 //switch matrix multiplexer AXI_M_FAB_ARADDR16 MUX-1
assign AXI_M_FAB_ARADDR16 = AXI_M_IO_E_1_BASE_TO_TOP16;

 //switch matrix multiplexer AXI_M_FAB_ARADDR15 MUX-1
assign AXI_M_FAB_ARADDR15 = AXI_M_IO_E_1_BASE_TO_TOP15;

 //switch matrix multiplexer AXI_M_FAB_ARADDR14 MUX-1
assign AXI_M_FAB_ARADDR14 = AXI_M_IO_E_1_BASE_TO_TOP14;

 //switch matrix multiplexer AXI_M_FAB_ARADDR13 MUX-1
assign AXI_M_FAB_ARADDR13 = AXI_M_IO_E_1_BASE_TO_TOP13;

 //switch matrix multiplexer AXI_M_FAB_ARADDR12 MUX-1
assign AXI_M_FAB_ARADDR12 = AXI_M_IO_E_1_BASE_TO_TOP12;

 //switch matrix multiplexer AXI_M_FAB_ARADDR11 MUX-1
assign AXI_M_FAB_ARADDR11 = AXI_M_IO_E_1_BASE_TO_TOP11;

 //switch matrix multiplexer AXI_M_FAB_ARADDR10 MUX-1
assign AXI_M_FAB_ARADDR10 = AXI_M_IO_E_1_BASE_TO_TOP10;

 //switch matrix multiplexer AXI_M_FAB_ARADDR9 MUX-1
assign AXI_M_FAB_ARADDR9 = AXI_M_IO_E_1_BASE_TO_TOP9;

 //switch matrix multiplexer AXI_M_FAB_ARADDR8 MUX-1
assign AXI_M_FAB_ARADDR8 = AXI_M_IO_E_1_BASE_TO_TOP8;

 //switch matrix multiplexer AXI_M_FAB_ARADDR7 MUX-1
assign AXI_M_FAB_ARADDR7 = AXI_M_IO_E_1_BASE_TO_TOP7;

 //switch matrix multiplexer AXI_M_FAB_ARADDR6 MUX-1
assign AXI_M_FAB_ARADDR6 = AXI_M_IO_E_1_BASE_TO_TOP6;

 //switch matrix multiplexer AXI_M_FAB_ARADDR5 MUX-1
assign AXI_M_FAB_ARADDR5 = AXI_M_IO_E_1_BASE_TO_TOP5;

 //switch matrix multiplexer AXI_M_FAB_ARADDR4 MUX-1
assign AXI_M_FAB_ARADDR4 = AXI_M_IO_E_1_BASE_TO_TOP4;

 //switch matrix multiplexer AXI_M_FAB_ARADDR3 MUX-1
assign AXI_M_FAB_ARADDR3 = AXI_M_IO_E_1_BASE_TO_TOP3;

 //switch matrix multiplexer AXI_M_FAB_ARADDR2 MUX-1
assign AXI_M_FAB_ARADDR2 = AXI_M_IO_E_1_BASE_TO_TOP2;

 //switch matrix multiplexer AXI_M_FAB_ARADDR1 MUX-1
assign AXI_M_FAB_ARADDR1 = AXI_M_IO_E_1_BASE_TO_TOP1;

 //switch matrix multiplexer AXI_M_FAB_ARADDR0 MUX-1
assign AXI_M_FAB_ARADDR0 = AXI_M_IO_E_1_BASE_TO_TOP0;

 //switch matrix multiplexer AXI_M_FAB_ARLEN7 MUX-1
assign AXI_M_FAB_ARLEN7 = AXI_M_IO_E_0_BASE_TO_TOP23;

 //switch matrix multiplexer AXI_M_FAB_ARLEN6 MUX-1
assign AXI_M_FAB_ARLEN6 = AXI_M_IO_E_0_BASE_TO_TOP22;

 //switch matrix multiplexer AXI_M_FAB_ARLEN5 MUX-1
assign AXI_M_FAB_ARLEN5 = AXI_M_IO_E_0_BASE_TO_TOP21;

 //switch matrix multiplexer AXI_M_FAB_ARLEN4 MUX-1
assign AXI_M_FAB_ARLEN4 = AXI_M_IO_E_0_BASE_TO_TOP20;

 //switch matrix multiplexer AXI_M_FAB_ARLEN3 MUX-1
assign AXI_M_FAB_ARLEN3 = AXI_M_IO_E_0_BASE_TO_TOP19;

 //switch matrix multiplexer AXI_M_FAB_ARLEN2 MUX-1
assign AXI_M_FAB_ARLEN2 = AXI_M_IO_E_0_BASE_TO_TOP18;

 //switch matrix multiplexer AXI_M_FAB_ARLEN1 MUX-1
assign AXI_M_FAB_ARLEN1 = AXI_M_IO_E_0_BASE_TO_TOP17;

 //switch matrix multiplexer AXI_M_FAB_ARLEN0 MUX-1
assign AXI_M_FAB_ARLEN0 = AXI_M_IO_E_0_BASE_TO_TOP16;

 //switch matrix multiplexer AXI_M_FAB_ARSIZE2 MUX-1
assign AXI_M_FAB_ARSIZE2 = AXI_M_IO_E_0_BASE_TO_TOP15;

 //switch matrix multiplexer AXI_M_FAB_ARSIZE1 MUX-1
assign AXI_M_FAB_ARSIZE1 = AXI_M_IO_E_0_BASE_TO_TOP14;

 //switch matrix multiplexer AXI_M_FAB_ARSIZE0 MUX-1
assign AXI_M_FAB_ARSIZE0 = AXI_M_IO_E_0_BASE_TO_TOP13;

 //switch matrix multiplexer AXI_M_FAB_ARBURST1 MUX-1
assign AXI_M_FAB_ARBURST1 = AXI_M_IO_E_0_BASE_TO_TOP12;

 //switch matrix multiplexer AXI_M_FAB_ARBURST0 MUX-1
assign AXI_M_FAB_ARBURST0 = AXI_M_IO_E_0_BASE_TO_TOP11;

 //switch matrix multiplexer AXI_M_FAB_ARVALID MUX-1
assign AXI_M_FAB_ARVALID = AXI_M_IO_E_0_BASE_TO_TOP10;

 //switch matrix multiplexer AXI_M_FAB_RREADY MUX-1
assign AXI_M_FAB_RREADY = AXI_M_IO_E_0_BASE_TO_TOP9;

 //switch matrix multiplexer AXI_M_IO_E_0_TOP_TO_BASE5 MUX-4
assign AXI_M_IO_E_0_TOP_TO_BASE5_input = {AXI_M_IO_E_4_BASE_TO_TOP2,AXI_M_IO_E_0_BASE_TO_TOP5,AXI_M_IO_E_0_BASE_TO_TOP2,AXI_M_IO_E_0_BASE_TO_TOP8};
cus_mux41 inst_cus_mux41_AXI_M_IO_E_0_TOP_TO_BASE5 (
    .A0(AXI_M_IO_E_0_TOP_TO_BASE5_input[0]),
    .A1(AXI_M_IO_E_0_TOP_TO_BASE5_input[1]),
    .A2(AXI_M_IO_E_0_TOP_TO_BASE5_input[2]),
    .A3(AXI_M_IO_E_0_TOP_TO_BASE5_input[3]),
    .S0(ConfigBits[0+0]),
    .S0N(ConfigBits_N[0+0]),
    .S1(ConfigBits[0+1]),
    .S1N(ConfigBits_N[0+1]),
    .X(AXI_M_IO_E_0_TOP_TO_BASE5)
);

 //switch matrix multiplexer AXI_M_IO_E_0_TOP_TO_BASE4 MUX-4
assign AXI_M_IO_E_0_TOP_TO_BASE4_input = {AXI_M_IO_E_4_BASE_TO_TOP0,AXI_M_IO_E_0_BASE_TO_TOP4,AXI_M_IO_E_0_BASE_TO_TOP1,AXI_M_IO_E_0_BASE_TO_TOP7};
cus_mux41 inst_cus_mux41_AXI_M_IO_E_0_TOP_TO_BASE4 (
    .A0(AXI_M_IO_E_0_TOP_TO_BASE4_input[0]),
    .A1(AXI_M_IO_E_0_TOP_TO_BASE4_input[1]),
    .A2(AXI_M_IO_E_0_TOP_TO_BASE4_input[2]),
    .A3(AXI_M_IO_E_0_TOP_TO_BASE4_input[3]),
    .S0(ConfigBits[2+0]),
    .S0N(ConfigBits_N[2+0]),
    .S1(ConfigBits[2+1]),
    .S1N(ConfigBits_N[2+1]),
    .X(AXI_M_IO_E_0_TOP_TO_BASE4)
);

 //switch matrix multiplexer AXI_M_IO_E_0_TOP_TO_BASE3 MUX-4
assign AXI_M_IO_E_0_TOP_TO_BASE3_input = {AXI_M_IO_E_2_BASE_TO_TOP8,AXI_M_IO_E_0_BASE_TO_TOP3,AXI_M_IO_E_0_BASE_TO_TOP0,AXI_M_IO_E_0_BASE_TO_TOP6};
cus_mux41 inst_cus_mux41_AXI_M_IO_E_0_TOP_TO_BASE3 (
    .A0(AXI_M_IO_E_0_TOP_TO_BASE3_input[0]),
    .A1(AXI_M_IO_E_0_TOP_TO_BASE3_input[1]),
    .A2(AXI_M_IO_E_0_TOP_TO_BASE3_input[2]),
    .A3(AXI_M_IO_E_0_TOP_TO_BASE3_input[3]),
    .S0(ConfigBits[4+0]),
    .S0N(ConfigBits_N[4+0]),
    .S1(ConfigBits[4+1]),
    .S1N(ConfigBits_N[4+1]),
    .X(AXI_M_IO_E_0_TOP_TO_BASE3)
);

 //switch matrix multiplexer AXI_M_IO_E_0_TOP_TO_BASE2 MUX-4
assign AXI_M_IO_E_0_TOP_TO_BASE2_input = {AXI_M_IO_E_0_BASE_TO_TOP2,AXI_M_IO_E_0_BASE_TO_TOP8,AXI_M_IO_E_4_BASE_TO_TOP1,AXI_M_IO_E_0_BASE_TO_TOP5};
cus_mux41 inst_cus_mux41_AXI_M_IO_E_0_TOP_TO_BASE2 (
    .A0(AXI_M_IO_E_0_TOP_TO_BASE2_input[0]),
    .A1(AXI_M_IO_E_0_TOP_TO_BASE2_input[1]),
    .A2(AXI_M_IO_E_0_TOP_TO_BASE2_input[2]),
    .A3(AXI_M_IO_E_0_TOP_TO_BASE2_input[3]),
    .S0(ConfigBits[6+0]),
    .S0N(ConfigBits_N[6+0]),
    .S1(ConfigBits[6+1]),
    .S1N(ConfigBits_N[6+1]),
    .X(AXI_M_IO_E_0_TOP_TO_BASE2)
);

 //switch matrix multiplexer AXI_M_IO_E_0_TOP_TO_BASE1 MUX-4
assign AXI_M_IO_E_0_TOP_TO_BASE1_input = {AXI_M_IO_E_0_BASE_TO_TOP1,AXI_M_IO_E_0_BASE_TO_TOP7,AXI_M_IO_E_4_BASE_TO_TOP0,AXI_M_IO_E_0_BASE_TO_TOP4};
cus_mux41 inst_cus_mux41_AXI_M_IO_E_0_TOP_TO_BASE1 (
    .A0(AXI_M_IO_E_0_TOP_TO_BASE1_input[0]),
    .A1(AXI_M_IO_E_0_TOP_TO_BASE1_input[1]),
    .A2(AXI_M_IO_E_0_TOP_TO_BASE1_input[2]),
    .A3(AXI_M_IO_E_0_TOP_TO_BASE1_input[3]),
    .S0(ConfigBits[8+0]),
    .S0N(ConfigBits_N[8+0]),
    .S1(ConfigBits[8+1]),
    .S1N(ConfigBits_N[8+1]),
    .X(AXI_M_IO_E_0_TOP_TO_BASE1)
);

 //switch matrix multiplexer AXI_M_IO_E_0_TOP_TO_BASE0 MUX-4
assign AXI_M_IO_E_0_TOP_TO_BASE0_input = {AXI_M_IO_E_0_BASE_TO_TOP0,AXI_M_IO_E_0_BASE_TO_TOP6,AXI_M_IO_E_2_BASE_TO_TOP8,AXI_M_IO_E_0_BASE_TO_TOP3};
cus_mux41 inst_cus_mux41_AXI_M_IO_E_0_TOP_TO_BASE0 (
    .A0(AXI_M_IO_E_0_TOP_TO_BASE0_input[0]),
    .A1(AXI_M_IO_E_0_TOP_TO_BASE0_input[1]),
    .A2(AXI_M_IO_E_0_TOP_TO_BASE0_input[2]),
    .A3(AXI_M_IO_E_0_TOP_TO_BASE0_input[3]),
    .S0(ConfigBits[10+0]),
    .S0N(ConfigBits_N[10+0]),
    .S1(ConfigBits[10+1]),
    .S1N(ConfigBits_N[10+1]),
    .X(AXI_M_IO_E_0_TOP_TO_BASE0)
);

endmodule