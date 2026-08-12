module eFPGA_top
    #(
        parameter include_eFPGA=1,
        parameter NumberOfRows=10,
        parameter NumberOfCols=12,
        parameter FrameBitsPerRow=32,
        parameter MaxFramesPerCol=20,
        parameter desync_flag=20,
        parameter FrameSelectWidth=5,
        parameter RowSelectWidth=5
    )
    (
        //External IO port
        input  [9:0] AXIL_S_SOC_ARADDR,
        output  [0:0] AXIL_S_SOC_ARREADY,
        input  [0:0] AXIL_S_SOC_ARVALID,
        input  [9:0] AXIL_S_SOC_AWADDR,
        output  [0:0] AXIL_S_SOC_AWREADY,
        input  [0:0] AXIL_S_SOC_AWVALID,
        input  [0:0] AXIL_S_SOC_BREADY,
        output  [1:0] AXIL_S_SOC_BRESP,
        output  [0:0] AXIL_S_SOC_BVALID,
        output  [31:0] AXIL_S_SOC_RDATA,
        input  [0:0] AXIL_S_SOC_RREADY,
        output  [1:0] AXIL_S_SOC_RRESP,
        output  [0:0] AXIL_S_SOC_RVALID,
        input  [31:0] AXIL_S_SOC_WDATA,
        output  [0:0] AXIL_S_SOC_WREADY,
        input  [3:0] AXIL_S_SOC_WSTRB,
        input  [0:0] AXIL_S_SOC_WVALID,
        output  [31:0] AXI_M_SOC_ARADDR,
        output  [1:0] AXI_M_SOC_ARBURST,
        output  [7:0] AXI_M_SOC_ARLEN,
        input  [0:0] AXI_M_SOC_ARREADY,
        output  [2:0] AXI_M_SOC_ARSIZE,
        output  [0:0] AXI_M_SOC_ARVALID,
        output  [31:0] AXI_M_SOC_AWADDR,
        output  [1:0] AXI_M_SOC_AWBURST,
        output  [7:0] AXI_M_SOC_AWLEN,
        input  [0:0] AXI_M_SOC_AWREADY,
        output  [2:0] AXI_M_SOC_AWSIZE,
        output  [0:0] AXI_M_SOC_AWVALID,
        output  [0:0] AXI_M_SOC_BREADY,
        input  [1:0] AXI_M_SOC_BRESP,
        input  [0:0] AXI_M_SOC_BVALID,
        input  [31:0] AXI_M_SOC_RDATA,
        input  [0:0] AXI_M_SOC_RLAST,
        output  [0:0] AXI_M_SOC_RREADY,
        input  [1:0] AXI_M_SOC_RRESP,
        input  [0:0] AXI_M_SOC_RVALID,
        output  [31:0] AXI_M_SOC_WDATA,
        output  [0:0] AXI_M_SOC_WLAST,
        input  [0:0] AXI_M_SOC_WREADY,
        output  [3:0] AXI_M_SOC_WSTRB,
        output  [0:0] AXI_M_SOC_WVALID,
        output  [39:0] A_config_C,
        output  [39:0] B_config_C,
        output  [19:0] I_top,
        input  [19:0] O_top,
        output  [19:0] T_top,
        //Config related ports
        input  CLK,
        input  resetn,
        input  SelfWriteStrobe,
        input  [31:0] SelfWriteData,
        input  Rx,
        output  ComActive,
        output  ReceiveLED,
        input  s_clk,
        input  s_data
);

 //Signal declarations
wire[(NumberOfRows*FrameBitsPerRow)-1:0] FrameRegister;
wire[(MaxFramesPerCol*NumberOfCols)-1:0] FrameSelect;
wire[(FrameBitsPerRow*(NumberOfRows+2))-1:0] FrameData;
wire[FrameBitsPerRow-1:0] FrameAddressRegister;
wire LongFrameStrobe;
wire[31:0] LocalWriteData;
wire LocalWriteStrobe;
wire[RowSelectWidth-1:0] RowSelect;
`ifndef EMULATION

eFPGA_Config
    #(
    .RowSelectWidth(RowSelectWidth),
    .NumberOfRows(NumberOfRows),
    .desync_flag(desync_flag),
    .FrameBitsPerRow(FrameBitsPerRow)
    )
    eFPGA_Config_inst
    (
    .CLK(CLK),
    .resetn(resetn),
    .Rx(Rx),
    .ComActive(ComActive),
    .ReceiveLED(ReceiveLED),
    .s_clk(s_clk),
    .s_data(s_data),
    .SelfWriteData(SelfWriteData),
    .SelfWriteStrobe(SelfWriteStrobe),
    .ConfigWriteData(LocalWriteData),
    .ConfigWriteStrobe(LocalWriteStrobe),
    .FrameAddressRegister(FrameAddressRegister),
    .LongFrameStrobe(LongFrameStrobe),
    .RowSelect(RowSelect)
);


Frame_Data_Reg
    #(
    .FrameBitsPerRow(FrameBitsPerRow),
    .RowSelectWidth(RowSelectWidth),
    .Row(1)
    )
    inst_Frame_Data_Reg_0
    (
    .FrameData_I(LocalWriteData),
    .FrameData_O(FrameRegister[0*FrameBitsPerRow+FrameBitsPerRow-1:0*FrameBitsPerRow]),
    .RowSelect(RowSelect),
    .CLK(CLK)
);

Frame_Data_Reg
    #(
    .FrameBitsPerRow(FrameBitsPerRow),
    .RowSelectWidth(RowSelectWidth),
    .Row(2)
    )
    inst_Frame_Data_Reg_1
    (
    .FrameData_I(LocalWriteData),
    .FrameData_O(FrameRegister[1*FrameBitsPerRow+FrameBitsPerRow-1:1*FrameBitsPerRow]),
    .RowSelect(RowSelect),
    .CLK(CLK)
);

Frame_Data_Reg
    #(
    .FrameBitsPerRow(FrameBitsPerRow),
    .RowSelectWidth(RowSelectWidth),
    .Row(3)
    )
    inst_Frame_Data_Reg_2
    (
    .FrameData_I(LocalWriteData),
    .FrameData_O(FrameRegister[2*FrameBitsPerRow+FrameBitsPerRow-1:2*FrameBitsPerRow]),
    .RowSelect(RowSelect),
    .CLK(CLK)
);

Frame_Data_Reg
    #(
    .FrameBitsPerRow(FrameBitsPerRow),
    .RowSelectWidth(RowSelectWidth),
    .Row(4)
    )
    inst_Frame_Data_Reg_3
    (
    .FrameData_I(LocalWriteData),
    .FrameData_O(FrameRegister[3*FrameBitsPerRow+FrameBitsPerRow-1:3*FrameBitsPerRow]),
    .RowSelect(RowSelect),
    .CLK(CLK)
);

Frame_Data_Reg
    #(
    .FrameBitsPerRow(FrameBitsPerRow),
    .RowSelectWidth(RowSelectWidth),
    .Row(5)
    )
    inst_Frame_Data_Reg_4
    (
    .FrameData_I(LocalWriteData),
    .FrameData_O(FrameRegister[4*FrameBitsPerRow+FrameBitsPerRow-1:4*FrameBitsPerRow]),
    .RowSelect(RowSelect),
    .CLK(CLK)
);

Frame_Data_Reg
    #(
    .FrameBitsPerRow(FrameBitsPerRow),
    .RowSelectWidth(RowSelectWidth),
    .Row(6)
    )
    inst_Frame_Data_Reg_5
    (
    .FrameData_I(LocalWriteData),
    .FrameData_O(FrameRegister[5*FrameBitsPerRow+FrameBitsPerRow-1:5*FrameBitsPerRow]),
    .RowSelect(RowSelect),
    .CLK(CLK)
);

Frame_Data_Reg
    #(
    .FrameBitsPerRow(FrameBitsPerRow),
    .RowSelectWidth(RowSelectWidth),
    .Row(7)
    )
    inst_Frame_Data_Reg_6
    (
    .FrameData_I(LocalWriteData),
    .FrameData_O(FrameRegister[6*FrameBitsPerRow+FrameBitsPerRow-1:6*FrameBitsPerRow]),
    .RowSelect(RowSelect),
    .CLK(CLK)
);

Frame_Data_Reg
    #(
    .FrameBitsPerRow(FrameBitsPerRow),
    .RowSelectWidth(RowSelectWidth),
    .Row(8)
    )
    inst_Frame_Data_Reg_7
    (
    .FrameData_I(LocalWriteData),
    .FrameData_O(FrameRegister[7*FrameBitsPerRow+FrameBitsPerRow-1:7*FrameBitsPerRow]),
    .RowSelect(RowSelect),
    .CLK(CLK)
);

Frame_Data_Reg
    #(
    .FrameBitsPerRow(FrameBitsPerRow),
    .RowSelectWidth(RowSelectWidth),
    .Row(9)
    )
    inst_Frame_Data_Reg_8
    (
    .FrameData_I(LocalWriteData),
    .FrameData_O(FrameRegister[8*FrameBitsPerRow+FrameBitsPerRow-1:8*FrameBitsPerRow]),
    .RowSelect(RowSelect),
    .CLK(CLK)
);

Frame_Data_Reg
    #(
    .FrameBitsPerRow(FrameBitsPerRow),
    .RowSelectWidth(RowSelectWidth),
    .Row(10)
    )
    inst_Frame_Data_Reg_9
    (
    .FrameData_I(LocalWriteData),
    .FrameData_O(FrameRegister[9*FrameBitsPerRow+FrameBitsPerRow-1:9*FrameBitsPerRow]),
    .RowSelect(RowSelect),
    .CLK(CLK)
);


Frame_Select
    #(
    .MaxFramesPerCol(MaxFramesPerCol),
    .FrameSelectWidth(FrameSelectWidth),
    .Col(0)
    )
    inst_Frame_Select_0
    (
    .FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
    .FrameStrobe_O(FrameSelect[0*MaxFramesPerCol+MaxFramesPerCol-1:0*MaxFramesPerCol]),
    .FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-FrameSelectWidth]),
    .FrameStrobe(LongFrameStrobe)
);

Frame_Select
    #(
    .MaxFramesPerCol(MaxFramesPerCol),
    .FrameSelectWidth(FrameSelectWidth),
    .Col(1)
    )
    inst_Frame_Select_1
    (
    .FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
    .FrameStrobe_O(FrameSelect[1*MaxFramesPerCol+MaxFramesPerCol-1:1*MaxFramesPerCol]),
    .FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-FrameSelectWidth]),
    .FrameStrobe(LongFrameStrobe)
);

Frame_Select
    #(
    .MaxFramesPerCol(MaxFramesPerCol),
    .FrameSelectWidth(FrameSelectWidth),
    .Col(2)
    )
    inst_Frame_Select_2
    (
    .FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
    .FrameStrobe_O(FrameSelect[2*MaxFramesPerCol+MaxFramesPerCol-1:2*MaxFramesPerCol]),
    .FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-FrameSelectWidth]),
    .FrameStrobe(LongFrameStrobe)
);

Frame_Select
    #(
    .MaxFramesPerCol(MaxFramesPerCol),
    .FrameSelectWidth(FrameSelectWidth),
    .Col(3)
    )
    inst_Frame_Select_3
    (
    .FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
    .FrameStrobe_O(FrameSelect[3*MaxFramesPerCol+MaxFramesPerCol-1:3*MaxFramesPerCol]),
    .FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-FrameSelectWidth]),
    .FrameStrobe(LongFrameStrobe)
);

Frame_Select
    #(
    .MaxFramesPerCol(MaxFramesPerCol),
    .FrameSelectWidth(FrameSelectWidth),
    .Col(4)
    )
    inst_Frame_Select_4
    (
    .FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
    .FrameStrobe_O(FrameSelect[4*MaxFramesPerCol+MaxFramesPerCol-1:4*MaxFramesPerCol]),
    .FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-FrameSelectWidth]),
    .FrameStrobe(LongFrameStrobe)
);

Frame_Select
    #(
    .MaxFramesPerCol(MaxFramesPerCol),
    .FrameSelectWidth(FrameSelectWidth),
    .Col(5)
    )
    inst_Frame_Select_5
    (
    .FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
    .FrameStrobe_O(FrameSelect[5*MaxFramesPerCol+MaxFramesPerCol-1:5*MaxFramesPerCol]),
    .FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-FrameSelectWidth]),
    .FrameStrobe(LongFrameStrobe)
);

Frame_Select
    #(
    .MaxFramesPerCol(MaxFramesPerCol),
    .FrameSelectWidth(FrameSelectWidth),
    .Col(6)
    )
    inst_Frame_Select_6
    (
    .FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
    .FrameStrobe_O(FrameSelect[6*MaxFramesPerCol+MaxFramesPerCol-1:6*MaxFramesPerCol]),
    .FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-FrameSelectWidth]),
    .FrameStrobe(LongFrameStrobe)
);

Frame_Select
    #(
    .MaxFramesPerCol(MaxFramesPerCol),
    .FrameSelectWidth(FrameSelectWidth),
    .Col(7)
    )
    inst_Frame_Select_7
    (
    .FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
    .FrameStrobe_O(FrameSelect[7*MaxFramesPerCol+MaxFramesPerCol-1:7*MaxFramesPerCol]),
    .FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-FrameSelectWidth]),
    .FrameStrobe(LongFrameStrobe)
);

Frame_Select
    #(
    .MaxFramesPerCol(MaxFramesPerCol),
    .FrameSelectWidth(FrameSelectWidth),
    .Col(8)
    )
    inst_Frame_Select_8
    (
    .FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
    .FrameStrobe_O(FrameSelect[8*MaxFramesPerCol+MaxFramesPerCol-1:8*MaxFramesPerCol]),
    .FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-FrameSelectWidth]),
    .FrameStrobe(LongFrameStrobe)
);

Frame_Select
    #(
    .MaxFramesPerCol(MaxFramesPerCol),
    .FrameSelectWidth(FrameSelectWidth),
    .Col(9)
    )
    inst_Frame_Select_9
    (
    .FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
    .FrameStrobe_O(FrameSelect[9*MaxFramesPerCol+MaxFramesPerCol-1:9*MaxFramesPerCol]),
    .FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-FrameSelectWidth]),
    .FrameStrobe(LongFrameStrobe)
);

Frame_Select
    #(
    .MaxFramesPerCol(MaxFramesPerCol),
    .FrameSelectWidth(FrameSelectWidth),
    .Col(10)
    )
    inst_Frame_Select_10
    (
    .FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
    .FrameStrobe_O(FrameSelect[10*MaxFramesPerCol+MaxFramesPerCol-1:10*MaxFramesPerCol]),
    .FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-FrameSelectWidth]),
    .FrameStrobe(LongFrameStrobe)
);

Frame_Select
    #(
    .MaxFramesPerCol(MaxFramesPerCol),
    .FrameSelectWidth(FrameSelectWidth),
    .Col(11)
    )
    inst_Frame_Select_11
    (
    .FrameStrobe_I(FrameAddressRegister[MaxFramesPerCol-1:0]),
    .FrameStrobe_O(FrameSelect[11*MaxFramesPerCol+MaxFramesPerCol-1:11*MaxFramesPerCol]),
    .FrameSelect(FrameAddressRegister[FrameBitsPerRow-1:FrameBitsPerRow-FrameSelectWidth]),
    .FrameStrobe(LongFrameStrobe)
);


`endif
eFPGA eFPGA_inst (
    .Tile_X11Y7_AXIL_S_SOC_ARADDR0(AXIL_S_SOC_ARADDR[0]),
    .Tile_X11Y7_AXIL_S_SOC_ARADDR1(AXIL_S_SOC_ARADDR[1]),
    .Tile_X11Y7_AXIL_S_SOC_ARADDR2(AXIL_S_SOC_ARADDR[2]),
    .Tile_X11Y7_AXIL_S_SOC_ARADDR3(AXIL_S_SOC_ARADDR[3]),
    .Tile_X11Y7_AXIL_S_SOC_ARADDR4(AXIL_S_SOC_ARADDR[4]),
    .Tile_X11Y7_AXIL_S_SOC_ARADDR5(AXIL_S_SOC_ARADDR[5]),
    .Tile_X11Y7_AXIL_S_SOC_ARADDR6(AXIL_S_SOC_ARADDR[6]),
    .Tile_X11Y7_AXIL_S_SOC_ARADDR7(AXIL_S_SOC_ARADDR[7]),
    .Tile_X11Y7_AXIL_S_SOC_ARADDR8(AXIL_S_SOC_ARADDR[8]),
    .Tile_X11Y7_AXIL_S_SOC_ARADDR9(AXIL_S_SOC_ARADDR[9]),
    .Tile_X11Y7_AXIL_S_SOC_ARREADY(AXIL_S_SOC_ARREADY[0]),
    .Tile_X11Y7_AXIL_S_SOC_ARVALID(AXIL_S_SOC_ARVALID[0]),
    .Tile_X11Y7_AXIL_S_SOC_AWADDR0(AXIL_S_SOC_AWADDR[0]),
    .Tile_X11Y7_AXIL_S_SOC_AWADDR1(AXIL_S_SOC_AWADDR[1]),
    .Tile_X11Y7_AXIL_S_SOC_AWADDR2(AXIL_S_SOC_AWADDR[2]),
    .Tile_X11Y7_AXIL_S_SOC_AWADDR3(AXIL_S_SOC_AWADDR[3]),
    .Tile_X11Y7_AXIL_S_SOC_AWADDR4(AXIL_S_SOC_AWADDR[4]),
    .Tile_X11Y7_AXIL_S_SOC_AWADDR5(AXIL_S_SOC_AWADDR[5]),
    .Tile_X11Y7_AXIL_S_SOC_AWADDR6(AXIL_S_SOC_AWADDR[6]),
    .Tile_X11Y7_AXIL_S_SOC_AWADDR7(AXIL_S_SOC_AWADDR[7]),
    .Tile_X11Y7_AXIL_S_SOC_AWADDR8(AXIL_S_SOC_AWADDR[8]),
    .Tile_X11Y7_AXIL_S_SOC_AWADDR9(AXIL_S_SOC_AWADDR[9]),
    .Tile_X11Y7_AXIL_S_SOC_AWREADY(AXIL_S_SOC_AWREADY[0]),
    .Tile_X11Y7_AXIL_S_SOC_AWVALID(AXIL_S_SOC_AWVALID[0]),
    .Tile_X11Y7_AXIL_S_SOC_BREADY(AXIL_S_SOC_BREADY[0]),
    .Tile_X11Y7_AXIL_S_SOC_BRESP0(AXIL_S_SOC_BRESP[0]),
    .Tile_X11Y7_AXIL_S_SOC_BRESP1(AXIL_S_SOC_BRESP[1]),
    .Tile_X11Y7_AXIL_S_SOC_BVALID(AXIL_S_SOC_BVALID[0]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA0(AXIL_S_SOC_RDATA[0]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA1(AXIL_S_SOC_RDATA[1]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA2(AXIL_S_SOC_RDATA[2]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA3(AXIL_S_SOC_RDATA[3]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA4(AXIL_S_SOC_RDATA[4]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA5(AXIL_S_SOC_RDATA[5]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA6(AXIL_S_SOC_RDATA[6]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA7(AXIL_S_SOC_RDATA[7]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA8(AXIL_S_SOC_RDATA[8]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA9(AXIL_S_SOC_RDATA[9]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA10(AXIL_S_SOC_RDATA[10]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA11(AXIL_S_SOC_RDATA[11]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA12(AXIL_S_SOC_RDATA[12]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA13(AXIL_S_SOC_RDATA[13]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA14(AXIL_S_SOC_RDATA[14]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA15(AXIL_S_SOC_RDATA[15]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA16(AXIL_S_SOC_RDATA[16]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA17(AXIL_S_SOC_RDATA[17]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA18(AXIL_S_SOC_RDATA[18]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA19(AXIL_S_SOC_RDATA[19]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA20(AXIL_S_SOC_RDATA[20]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA21(AXIL_S_SOC_RDATA[21]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA22(AXIL_S_SOC_RDATA[22]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA23(AXIL_S_SOC_RDATA[23]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA24(AXIL_S_SOC_RDATA[24]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA25(AXIL_S_SOC_RDATA[25]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA26(AXIL_S_SOC_RDATA[26]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA27(AXIL_S_SOC_RDATA[27]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA28(AXIL_S_SOC_RDATA[28]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA29(AXIL_S_SOC_RDATA[29]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA30(AXIL_S_SOC_RDATA[30]),
    .Tile_X11Y7_AXIL_S_SOC_RDATA31(AXIL_S_SOC_RDATA[31]),
    .Tile_X11Y7_AXIL_S_SOC_RREADY(AXIL_S_SOC_RREADY[0]),
    .Tile_X11Y7_AXIL_S_SOC_RRESP0(AXIL_S_SOC_RRESP[0]),
    .Tile_X11Y7_AXIL_S_SOC_RRESP1(AXIL_S_SOC_RRESP[1]),
    .Tile_X11Y7_AXIL_S_SOC_RVALID(AXIL_S_SOC_RVALID[0]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA0(AXIL_S_SOC_WDATA[0]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA1(AXIL_S_SOC_WDATA[1]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA2(AXIL_S_SOC_WDATA[2]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA3(AXIL_S_SOC_WDATA[3]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA4(AXIL_S_SOC_WDATA[4]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA5(AXIL_S_SOC_WDATA[5]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA6(AXIL_S_SOC_WDATA[6]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA7(AXIL_S_SOC_WDATA[7]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA8(AXIL_S_SOC_WDATA[8]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA9(AXIL_S_SOC_WDATA[9]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA10(AXIL_S_SOC_WDATA[10]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA11(AXIL_S_SOC_WDATA[11]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA12(AXIL_S_SOC_WDATA[12]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA13(AXIL_S_SOC_WDATA[13]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA14(AXIL_S_SOC_WDATA[14]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA15(AXIL_S_SOC_WDATA[15]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA16(AXIL_S_SOC_WDATA[16]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA17(AXIL_S_SOC_WDATA[17]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA18(AXIL_S_SOC_WDATA[18]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA19(AXIL_S_SOC_WDATA[19]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA20(AXIL_S_SOC_WDATA[20]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA21(AXIL_S_SOC_WDATA[21]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA22(AXIL_S_SOC_WDATA[22]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA23(AXIL_S_SOC_WDATA[23]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA24(AXIL_S_SOC_WDATA[24]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA25(AXIL_S_SOC_WDATA[25]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA26(AXIL_S_SOC_WDATA[26]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA27(AXIL_S_SOC_WDATA[27]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA28(AXIL_S_SOC_WDATA[28]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA29(AXIL_S_SOC_WDATA[29]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA30(AXIL_S_SOC_WDATA[30]),
    .Tile_X11Y7_AXIL_S_SOC_WDATA31(AXIL_S_SOC_WDATA[31]),
    .Tile_X11Y7_AXIL_S_SOC_WREADY(AXIL_S_SOC_WREADY[0]),
    .Tile_X11Y7_AXIL_S_SOC_WSTRB0(AXIL_S_SOC_WSTRB[0]),
    .Tile_X11Y7_AXIL_S_SOC_WSTRB1(AXIL_S_SOC_WSTRB[1]),
    .Tile_X11Y7_AXIL_S_SOC_WSTRB2(AXIL_S_SOC_WSTRB[2]),
    .Tile_X11Y7_AXIL_S_SOC_WSTRB3(AXIL_S_SOC_WSTRB[3]),
    .Tile_X11Y7_AXIL_S_SOC_WVALID(AXIL_S_SOC_WVALID[0]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR0(AXI_M_SOC_ARADDR[0]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR1(AXI_M_SOC_ARADDR[1]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR2(AXI_M_SOC_ARADDR[2]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR3(AXI_M_SOC_ARADDR[3]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR4(AXI_M_SOC_ARADDR[4]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR5(AXI_M_SOC_ARADDR[5]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR6(AXI_M_SOC_ARADDR[6]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR7(AXI_M_SOC_ARADDR[7]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR8(AXI_M_SOC_ARADDR[8]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR9(AXI_M_SOC_ARADDR[9]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR10(AXI_M_SOC_ARADDR[10]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR11(AXI_M_SOC_ARADDR[11]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR12(AXI_M_SOC_ARADDR[12]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR13(AXI_M_SOC_ARADDR[13]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR14(AXI_M_SOC_ARADDR[14]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR15(AXI_M_SOC_ARADDR[15]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR16(AXI_M_SOC_ARADDR[16]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR17(AXI_M_SOC_ARADDR[17]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR18(AXI_M_SOC_ARADDR[18]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR19(AXI_M_SOC_ARADDR[19]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR20(AXI_M_SOC_ARADDR[20]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR21(AXI_M_SOC_ARADDR[21]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR22(AXI_M_SOC_ARADDR[22]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR23(AXI_M_SOC_ARADDR[23]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR24(AXI_M_SOC_ARADDR[24]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR25(AXI_M_SOC_ARADDR[25]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR26(AXI_M_SOC_ARADDR[26]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR27(AXI_M_SOC_ARADDR[27]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR28(AXI_M_SOC_ARADDR[28]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR29(AXI_M_SOC_ARADDR[29]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR30(AXI_M_SOC_ARADDR[30]),
    .Tile_X11Y1_AXI_M_SOC_ARADDR31(AXI_M_SOC_ARADDR[31]),
    .Tile_X11Y1_AXI_M_SOC_ARBURST0(AXI_M_SOC_ARBURST[0]),
    .Tile_X11Y1_AXI_M_SOC_ARBURST1(AXI_M_SOC_ARBURST[1]),
    .Tile_X11Y1_AXI_M_SOC_ARLEN0(AXI_M_SOC_ARLEN[0]),
    .Tile_X11Y1_AXI_M_SOC_ARLEN1(AXI_M_SOC_ARLEN[1]),
    .Tile_X11Y1_AXI_M_SOC_ARLEN2(AXI_M_SOC_ARLEN[2]),
    .Tile_X11Y1_AXI_M_SOC_ARLEN3(AXI_M_SOC_ARLEN[3]),
    .Tile_X11Y1_AXI_M_SOC_ARLEN4(AXI_M_SOC_ARLEN[4]),
    .Tile_X11Y1_AXI_M_SOC_ARLEN5(AXI_M_SOC_ARLEN[5]),
    .Tile_X11Y1_AXI_M_SOC_ARLEN6(AXI_M_SOC_ARLEN[6]),
    .Tile_X11Y1_AXI_M_SOC_ARLEN7(AXI_M_SOC_ARLEN[7]),
    .Tile_X11Y1_AXI_M_SOC_ARREADY(AXI_M_SOC_ARREADY[0]),
    .Tile_X11Y1_AXI_M_SOC_ARSIZE0(AXI_M_SOC_ARSIZE[0]),
    .Tile_X11Y1_AXI_M_SOC_ARSIZE1(AXI_M_SOC_ARSIZE[1]),
    .Tile_X11Y1_AXI_M_SOC_ARSIZE2(AXI_M_SOC_ARSIZE[2]),
    .Tile_X11Y1_AXI_M_SOC_ARVALID(AXI_M_SOC_ARVALID[0]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR0(AXI_M_SOC_AWADDR[0]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR1(AXI_M_SOC_AWADDR[1]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR2(AXI_M_SOC_AWADDR[2]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR3(AXI_M_SOC_AWADDR[3]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR4(AXI_M_SOC_AWADDR[4]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR5(AXI_M_SOC_AWADDR[5]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR6(AXI_M_SOC_AWADDR[6]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR7(AXI_M_SOC_AWADDR[7]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR8(AXI_M_SOC_AWADDR[8]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR9(AXI_M_SOC_AWADDR[9]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR10(AXI_M_SOC_AWADDR[10]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR11(AXI_M_SOC_AWADDR[11]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR12(AXI_M_SOC_AWADDR[12]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR13(AXI_M_SOC_AWADDR[13]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR14(AXI_M_SOC_AWADDR[14]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR15(AXI_M_SOC_AWADDR[15]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR16(AXI_M_SOC_AWADDR[16]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR17(AXI_M_SOC_AWADDR[17]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR18(AXI_M_SOC_AWADDR[18]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR19(AXI_M_SOC_AWADDR[19]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR20(AXI_M_SOC_AWADDR[20]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR21(AXI_M_SOC_AWADDR[21]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR22(AXI_M_SOC_AWADDR[22]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR23(AXI_M_SOC_AWADDR[23]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR24(AXI_M_SOC_AWADDR[24]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR25(AXI_M_SOC_AWADDR[25]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR26(AXI_M_SOC_AWADDR[26]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR27(AXI_M_SOC_AWADDR[27]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR28(AXI_M_SOC_AWADDR[28]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR29(AXI_M_SOC_AWADDR[29]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR30(AXI_M_SOC_AWADDR[30]),
    .Tile_X11Y1_AXI_M_SOC_AWADDR31(AXI_M_SOC_AWADDR[31]),
    .Tile_X11Y1_AXI_M_SOC_AWBURST0(AXI_M_SOC_AWBURST[0]),
    .Tile_X11Y1_AXI_M_SOC_AWBURST1(AXI_M_SOC_AWBURST[1]),
    .Tile_X11Y1_AXI_M_SOC_AWLEN0(AXI_M_SOC_AWLEN[0]),
    .Tile_X11Y1_AXI_M_SOC_AWLEN1(AXI_M_SOC_AWLEN[1]),
    .Tile_X11Y1_AXI_M_SOC_AWLEN2(AXI_M_SOC_AWLEN[2]),
    .Tile_X11Y1_AXI_M_SOC_AWLEN3(AXI_M_SOC_AWLEN[3]),
    .Tile_X11Y1_AXI_M_SOC_AWLEN4(AXI_M_SOC_AWLEN[4]),
    .Tile_X11Y1_AXI_M_SOC_AWLEN5(AXI_M_SOC_AWLEN[5]),
    .Tile_X11Y1_AXI_M_SOC_AWLEN6(AXI_M_SOC_AWLEN[6]),
    .Tile_X11Y1_AXI_M_SOC_AWLEN7(AXI_M_SOC_AWLEN[7]),
    .Tile_X11Y1_AXI_M_SOC_AWREADY(AXI_M_SOC_AWREADY[0]),
    .Tile_X11Y1_AXI_M_SOC_AWSIZE0(AXI_M_SOC_AWSIZE[0]),
    .Tile_X11Y1_AXI_M_SOC_AWSIZE1(AXI_M_SOC_AWSIZE[1]),
    .Tile_X11Y1_AXI_M_SOC_AWSIZE2(AXI_M_SOC_AWSIZE[2]),
    .Tile_X11Y1_AXI_M_SOC_AWVALID(AXI_M_SOC_AWVALID[0]),
    .Tile_X11Y1_AXI_M_SOC_BREADY(AXI_M_SOC_BREADY[0]),
    .Tile_X11Y1_AXI_M_SOC_BRESP0(AXI_M_SOC_BRESP[0]),
    .Tile_X11Y1_AXI_M_SOC_BRESP1(AXI_M_SOC_BRESP[1]),
    .Tile_X11Y1_AXI_M_SOC_BVALID(AXI_M_SOC_BVALID[0]),
    .Tile_X11Y1_AXI_M_SOC_RDATA0(AXI_M_SOC_RDATA[0]),
    .Tile_X11Y1_AXI_M_SOC_RDATA1(AXI_M_SOC_RDATA[1]),
    .Tile_X11Y1_AXI_M_SOC_RDATA2(AXI_M_SOC_RDATA[2]),
    .Tile_X11Y1_AXI_M_SOC_RDATA3(AXI_M_SOC_RDATA[3]),
    .Tile_X11Y1_AXI_M_SOC_RDATA4(AXI_M_SOC_RDATA[4]),
    .Tile_X11Y1_AXI_M_SOC_RDATA5(AXI_M_SOC_RDATA[5]),
    .Tile_X11Y1_AXI_M_SOC_RDATA6(AXI_M_SOC_RDATA[6]),
    .Tile_X11Y1_AXI_M_SOC_RDATA7(AXI_M_SOC_RDATA[7]),
    .Tile_X11Y1_AXI_M_SOC_RDATA8(AXI_M_SOC_RDATA[8]),
    .Tile_X11Y1_AXI_M_SOC_RDATA9(AXI_M_SOC_RDATA[9]),
    .Tile_X11Y1_AXI_M_SOC_RDATA10(AXI_M_SOC_RDATA[10]),
    .Tile_X11Y1_AXI_M_SOC_RDATA11(AXI_M_SOC_RDATA[11]),
    .Tile_X11Y1_AXI_M_SOC_RDATA12(AXI_M_SOC_RDATA[12]),
    .Tile_X11Y1_AXI_M_SOC_RDATA13(AXI_M_SOC_RDATA[13]),
    .Tile_X11Y1_AXI_M_SOC_RDATA14(AXI_M_SOC_RDATA[14]),
    .Tile_X11Y1_AXI_M_SOC_RDATA15(AXI_M_SOC_RDATA[15]),
    .Tile_X11Y1_AXI_M_SOC_RDATA16(AXI_M_SOC_RDATA[16]),
    .Tile_X11Y1_AXI_M_SOC_RDATA17(AXI_M_SOC_RDATA[17]),
    .Tile_X11Y1_AXI_M_SOC_RDATA18(AXI_M_SOC_RDATA[18]),
    .Tile_X11Y1_AXI_M_SOC_RDATA19(AXI_M_SOC_RDATA[19]),
    .Tile_X11Y1_AXI_M_SOC_RDATA20(AXI_M_SOC_RDATA[20]),
    .Tile_X11Y1_AXI_M_SOC_RDATA21(AXI_M_SOC_RDATA[21]),
    .Tile_X11Y1_AXI_M_SOC_RDATA22(AXI_M_SOC_RDATA[22]),
    .Tile_X11Y1_AXI_M_SOC_RDATA23(AXI_M_SOC_RDATA[23]),
    .Tile_X11Y1_AXI_M_SOC_RDATA24(AXI_M_SOC_RDATA[24]),
    .Tile_X11Y1_AXI_M_SOC_RDATA25(AXI_M_SOC_RDATA[25]),
    .Tile_X11Y1_AXI_M_SOC_RDATA26(AXI_M_SOC_RDATA[26]),
    .Tile_X11Y1_AXI_M_SOC_RDATA27(AXI_M_SOC_RDATA[27]),
    .Tile_X11Y1_AXI_M_SOC_RDATA28(AXI_M_SOC_RDATA[28]),
    .Tile_X11Y1_AXI_M_SOC_RDATA29(AXI_M_SOC_RDATA[29]),
    .Tile_X11Y1_AXI_M_SOC_RDATA30(AXI_M_SOC_RDATA[30]),
    .Tile_X11Y1_AXI_M_SOC_RDATA31(AXI_M_SOC_RDATA[31]),
    .Tile_X11Y1_AXI_M_SOC_RLAST(AXI_M_SOC_RLAST[0]),
    .Tile_X11Y1_AXI_M_SOC_RREADY(AXI_M_SOC_RREADY[0]),
    .Tile_X11Y1_AXI_M_SOC_RRESP0(AXI_M_SOC_RRESP[0]),
    .Tile_X11Y1_AXI_M_SOC_RRESP1(AXI_M_SOC_RRESP[1]),
    .Tile_X11Y1_AXI_M_SOC_RVALID(AXI_M_SOC_RVALID[0]),
    .Tile_X11Y1_AXI_M_SOC_WDATA0(AXI_M_SOC_WDATA[0]),
    .Tile_X11Y1_AXI_M_SOC_WDATA1(AXI_M_SOC_WDATA[1]),
    .Tile_X11Y1_AXI_M_SOC_WDATA2(AXI_M_SOC_WDATA[2]),
    .Tile_X11Y1_AXI_M_SOC_WDATA3(AXI_M_SOC_WDATA[3]),
    .Tile_X11Y1_AXI_M_SOC_WDATA4(AXI_M_SOC_WDATA[4]),
    .Tile_X11Y1_AXI_M_SOC_WDATA5(AXI_M_SOC_WDATA[5]),
    .Tile_X11Y1_AXI_M_SOC_WDATA6(AXI_M_SOC_WDATA[6]),
    .Tile_X11Y1_AXI_M_SOC_WDATA7(AXI_M_SOC_WDATA[7]),
    .Tile_X11Y1_AXI_M_SOC_WDATA8(AXI_M_SOC_WDATA[8]),
    .Tile_X11Y1_AXI_M_SOC_WDATA9(AXI_M_SOC_WDATA[9]),
    .Tile_X11Y1_AXI_M_SOC_WDATA10(AXI_M_SOC_WDATA[10]),
    .Tile_X11Y1_AXI_M_SOC_WDATA11(AXI_M_SOC_WDATA[11]),
    .Tile_X11Y1_AXI_M_SOC_WDATA12(AXI_M_SOC_WDATA[12]),
    .Tile_X11Y1_AXI_M_SOC_WDATA13(AXI_M_SOC_WDATA[13]),
    .Tile_X11Y1_AXI_M_SOC_WDATA14(AXI_M_SOC_WDATA[14]),
    .Tile_X11Y1_AXI_M_SOC_WDATA15(AXI_M_SOC_WDATA[15]),
    .Tile_X11Y1_AXI_M_SOC_WDATA16(AXI_M_SOC_WDATA[16]),
    .Tile_X11Y1_AXI_M_SOC_WDATA17(AXI_M_SOC_WDATA[17]),
    .Tile_X11Y1_AXI_M_SOC_WDATA18(AXI_M_SOC_WDATA[18]),
    .Tile_X11Y1_AXI_M_SOC_WDATA19(AXI_M_SOC_WDATA[19]),
    .Tile_X11Y1_AXI_M_SOC_WDATA20(AXI_M_SOC_WDATA[20]),
    .Tile_X11Y1_AXI_M_SOC_WDATA21(AXI_M_SOC_WDATA[21]),
    .Tile_X11Y1_AXI_M_SOC_WDATA22(AXI_M_SOC_WDATA[22]),
    .Tile_X11Y1_AXI_M_SOC_WDATA23(AXI_M_SOC_WDATA[23]),
    .Tile_X11Y1_AXI_M_SOC_WDATA24(AXI_M_SOC_WDATA[24]),
    .Tile_X11Y1_AXI_M_SOC_WDATA25(AXI_M_SOC_WDATA[25]),
    .Tile_X11Y1_AXI_M_SOC_WDATA26(AXI_M_SOC_WDATA[26]),
    .Tile_X11Y1_AXI_M_SOC_WDATA27(AXI_M_SOC_WDATA[27]),
    .Tile_X11Y1_AXI_M_SOC_WDATA28(AXI_M_SOC_WDATA[28]),
    .Tile_X11Y1_AXI_M_SOC_WDATA29(AXI_M_SOC_WDATA[29]),
    .Tile_X11Y1_AXI_M_SOC_WDATA30(AXI_M_SOC_WDATA[30]),
    .Tile_X11Y1_AXI_M_SOC_WDATA31(AXI_M_SOC_WDATA[31]),
    .Tile_X11Y1_AXI_M_SOC_WLAST(AXI_M_SOC_WLAST[0]),
    .Tile_X11Y1_AXI_M_SOC_WREADY(AXI_M_SOC_WREADY[0]),
    .Tile_X11Y1_AXI_M_SOC_WSTRB0(AXI_M_SOC_WSTRB[0]),
    .Tile_X11Y1_AXI_M_SOC_WSTRB1(AXI_M_SOC_WSTRB[1]),
    .Tile_X11Y1_AXI_M_SOC_WSTRB2(AXI_M_SOC_WSTRB[2]),
    .Tile_X11Y1_AXI_M_SOC_WSTRB3(AXI_M_SOC_WSTRB[3]),
    .Tile_X11Y1_AXI_M_SOC_WVALID(AXI_M_SOC_WVALID[0]),
    .Tile_X0Y10_A_config_C_bit0(A_config_C[0]),
    .Tile_X0Y10_A_config_C_bit1(A_config_C[1]),
    .Tile_X0Y10_A_config_C_bit2(A_config_C[2]),
    .Tile_X0Y10_A_config_C_bit3(A_config_C[3]),
    .Tile_X0Y9_A_config_C_bit0(A_config_C[4]),
    .Tile_X0Y9_A_config_C_bit1(A_config_C[5]),
    .Tile_X0Y9_A_config_C_bit2(A_config_C[6]),
    .Tile_X0Y9_A_config_C_bit3(A_config_C[7]),
    .Tile_X0Y8_A_config_C_bit0(A_config_C[8]),
    .Tile_X0Y8_A_config_C_bit1(A_config_C[9]),
    .Tile_X0Y8_A_config_C_bit2(A_config_C[10]),
    .Tile_X0Y8_A_config_C_bit3(A_config_C[11]),
    .Tile_X0Y7_A_config_C_bit0(A_config_C[12]),
    .Tile_X0Y7_A_config_C_bit1(A_config_C[13]),
    .Tile_X0Y7_A_config_C_bit2(A_config_C[14]),
    .Tile_X0Y7_A_config_C_bit3(A_config_C[15]),
    .Tile_X0Y6_A_config_C_bit0(A_config_C[16]),
    .Tile_X0Y6_A_config_C_bit1(A_config_C[17]),
    .Tile_X0Y6_A_config_C_bit2(A_config_C[18]),
    .Tile_X0Y6_A_config_C_bit3(A_config_C[19]),
    .Tile_X0Y5_A_config_C_bit0(A_config_C[20]),
    .Tile_X0Y5_A_config_C_bit1(A_config_C[21]),
    .Tile_X0Y5_A_config_C_bit2(A_config_C[22]),
    .Tile_X0Y5_A_config_C_bit3(A_config_C[23]),
    .Tile_X0Y4_A_config_C_bit0(A_config_C[24]),
    .Tile_X0Y4_A_config_C_bit1(A_config_C[25]),
    .Tile_X0Y4_A_config_C_bit2(A_config_C[26]),
    .Tile_X0Y4_A_config_C_bit3(A_config_C[27]),
    .Tile_X0Y3_A_config_C_bit0(A_config_C[28]),
    .Tile_X0Y3_A_config_C_bit1(A_config_C[29]),
    .Tile_X0Y3_A_config_C_bit2(A_config_C[30]),
    .Tile_X0Y3_A_config_C_bit3(A_config_C[31]),
    .Tile_X0Y2_A_config_C_bit0(A_config_C[32]),
    .Tile_X0Y2_A_config_C_bit1(A_config_C[33]),
    .Tile_X0Y2_A_config_C_bit2(A_config_C[34]),
    .Tile_X0Y2_A_config_C_bit3(A_config_C[35]),
    .Tile_X0Y1_A_config_C_bit0(A_config_C[36]),
    .Tile_X0Y1_A_config_C_bit1(A_config_C[37]),
    .Tile_X0Y1_A_config_C_bit2(A_config_C[38]),
    .Tile_X0Y1_A_config_C_bit3(A_config_C[39]),
    .Tile_X0Y10_B_config_C_bit0(B_config_C[0]),
    .Tile_X0Y10_B_config_C_bit1(B_config_C[1]),
    .Tile_X0Y10_B_config_C_bit2(B_config_C[2]),
    .Tile_X0Y10_B_config_C_bit3(B_config_C[3]),
    .Tile_X0Y9_B_config_C_bit0(B_config_C[4]),
    .Tile_X0Y9_B_config_C_bit1(B_config_C[5]),
    .Tile_X0Y9_B_config_C_bit2(B_config_C[6]),
    .Tile_X0Y9_B_config_C_bit3(B_config_C[7]),
    .Tile_X0Y8_B_config_C_bit0(B_config_C[8]),
    .Tile_X0Y8_B_config_C_bit1(B_config_C[9]),
    .Tile_X0Y8_B_config_C_bit2(B_config_C[10]),
    .Tile_X0Y8_B_config_C_bit3(B_config_C[11]),
    .Tile_X0Y7_B_config_C_bit0(B_config_C[12]),
    .Tile_X0Y7_B_config_C_bit1(B_config_C[13]),
    .Tile_X0Y7_B_config_C_bit2(B_config_C[14]),
    .Tile_X0Y7_B_config_C_bit3(B_config_C[15]),
    .Tile_X0Y6_B_config_C_bit0(B_config_C[16]),
    .Tile_X0Y6_B_config_C_bit1(B_config_C[17]),
    .Tile_X0Y6_B_config_C_bit2(B_config_C[18]),
    .Tile_X0Y6_B_config_C_bit3(B_config_C[19]),
    .Tile_X0Y5_B_config_C_bit0(B_config_C[20]),
    .Tile_X0Y5_B_config_C_bit1(B_config_C[21]),
    .Tile_X0Y5_B_config_C_bit2(B_config_C[22]),
    .Tile_X0Y5_B_config_C_bit3(B_config_C[23]),
    .Tile_X0Y4_B_config_C_bit0(B_config_C[24]),
    .Tile_X0Y4_B_config_C_bit1(B_config_C[25]),
    .Tile_X0Y4_B_config_C_bit2(B_config_C[26]),
    .Tile_X0Y4_B_config_C_bit3(B_config_C[27]),
    .Tile_X0Y3_B_config_C_bit0(B_config_C[28]),
    .Tile_X0Y3_B_config_C_bit1(B_config_C[29]),
    .Tile_X0Y3_B_config_C_bit2(B_config_C[30]),
    .Tile_X0Y3_B_config_C_bit3(B_config_C[31]),
    .Tile_X0Y2_B_config_C_bit0(B_config_C[32]),
    .Tile_X0Y2_B_config_C_bit1(B_config_C[33]),
    .Tile_X0Y2_B_config_C_bit2(B_config_C[34]),
    .Tile_X0Y2_B_config_C_bit3(B_config_C[35]),
    .Tile_X0Y1_B_config_C_bit0(B_config_C[36]),
    .Tile_X0Y1_B_config_C_bit1(B_config_C[37]),
    .Tile_X0Y1_B_config_C_bit2(B_config_C[38]),
    .Tile_X0Y1_B_config_C_bit3(B_config_C[39]),
    .Tile_X0Y10_B_I_top(I_top[0]),
    .Tile_X0Y10_A_I_top(I_top[1]),
    .Tile_X0Y9_B_I_top(I_top[2]),
    .Tile_X0Y9_A_I_top(I_top[3]),
    .Tile_X0Y8_B_I_top(I_top[4]),
    .Tile_X0Y8_A_I_top(I_top[5]),
    .Tile_X0Y7_B_I_top(I_top[6]),
    .Tile_X0Y7_A_I_top(I_top[7]),
    .Tile_X0Y6_B_I_top(I_top[8]),
    .Tile_X0Y6_A_I_top(I_top[9]),
    .Tile_X0Y5_B_I_top(I_top[10]),
    .Tile_X0Y5_A_I_top(I_top[11]),
    .Tile_X0Y4_B_I_top(I_top[12]),
    .Tile_X0Y4_A_I_top(I_top[13]),
    .Tile_X0Y3_B_I_top(I_top[14]),
    .Tile_X0Y3_A_I_top(I_top[15]),
    .Tile_X0Y2_B_I_top(I_top[16]),
    .Tile_X0Y2_A_I_top(I_top[17]),
    .Tile_X0Y1_B_I_top(I_top[18]),
    .Tile_X0Y1_A_I_top(I_top[19]),
    .Tile_X0Y10_B_O_top(O_top[0]),
    .Tile_X0Y10_A_O_top(O_top[1]),
    .Tile_X0Y9_B_O_top(O_top[2]),
    .Tile_X0Y9_A_O_top(O_top[3]),
    .Tile_X0Y8_B_O_top(O_top[4]),
    .Tile_X0Y8_A_O_top(O_top[5]),
    .Tile_X0Y7_B_O_top(O_top[6]),
    .Tile_X0Y7_A_O_top(O_top[7]),
    .Tile_X0Y6_B_O_top(O_top[8]),
    .Tile_X0Y6_A_O_top(O_top[9]),
    .Tile_X0Y5_B_O_top(O_top[10]),
    .Tile_X0Y5_A_O_top(O_top[11]),
    .Tile_X0Y4_B_O_top(O_top[12]),
    .Tile_X0Y4_A_O_top(O_top[13]),
    .Tile_X0Y3_B_O_top(O_top[14]),
    .Tile_X0Y3_A_O_top(O_top[15]),
    .Tile_X0Y2_B_O_top(O_top[16]),
    .Tile_X0Y2_A_O_top(O_top[17]),
    .Tile_X0Y1_B_O_top(O_top[18]),
    .Tile_X0Y1_A_O_top(O_top[19]),
    .Tile_X0Y10_B_T_top(T_top[0]),
    .Tile_X0Y10_A_T_top(T_top[1]),
    .Tile_X0Y9_B_T_top(T_top[2]),
    .Tile_X0Y9_A_T_top(T_top[3]),
    .Tile_X0Y8_B_T_top(T_top[4]),
    .Tile_X0Y8_A_T_top(T_top[5]),
    .Tile_X0Y7_B_T_top(T_top[6]),
    .Tile_X0Y7_A_T_top(T_top[7]),
    .Tile_X0Y6_B_T_top(T_top[8]),
    .Tile_X0Y6_A_T_top(T_top[9]),
    .Tile_X0Y5_B_T_top(T_top[10]),
    .Tile_X0Y5_A_T_top(T_top[11]),
    .Tile_X0Y4_B_T_top(T_top[12]),
    .Tile_X0Y4_A_T_top(T_top[13]),
    .Tile_X0Y3_B_T_top(T_top[14]),
    .Tile_X0Y3_A_T_top(T_top[15]),
    .Tile_X0Y2_B_T_top(T_top[16]),
    .Tile_X0Y2_A_T_top(T_top[17]),
    .Tile_X0Y1_B_T_top(T_top[18]),
    .Tile_X0Y1_A_T_top(T_top[19]),
    .UserCLK(CLK),
    .FrameData(FrameData),
    .FrameStrobe(FrameSelect)
);


assign FrameData = {32'h12345678,FrameRegister,32'h12345678};
endmodule