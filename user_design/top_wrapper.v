`timescale 1ns / 1ps

module top_wrapper;

    wire clk;
    (* keep *) Global_Clock clk_i (.CLK(clk));

    // ========================================================================
    // Fabric 20-bit GPIO (Column X=0, Rows Y=10 down to Y=1)
    // ========================================================================
    wire [19:0] io_in;  
    wire [31:0] fabric_debug_out; // Full 32-bit bus from your user logic
    
    // Direct 1-to-1 mapping. No shifting.
    wire [19:0] io_out = fabric_debug_out[19:0]; 
    wire [19:0] io_oeb = 20'b0; // Ignored by the hardwired integration

    wire sys_rstn = io_in[0];

    (* keep, BEL="X0Y10.B" *) IO_1_bidirectional_frame_config_pass io0_i  (.O(io_in[0]),  .I(io_out[0]),  .T(io_oeb[0]));
    (* keep, BEL="X0Y10.A" *) IO_1_bidirectional_frame_config_pass io1_i  (.O(io_in[1]),  .I(io_out[1]),  .T(io_oeb[1]));
    (* keep, BEL="X0Y9.B" *)  IO_1_bidirectional_frame_config_pass io2_i  (.O(io_in[2]),  .I(io_out[2]),  .T(io_oeb[2]));
    (* keep, BEL="X0Y9.A" *)  IO_1_bidirectional_frame_config_pass io3_i  (.O(io_in[3]),  .I(io_out[3]),  .T(io_oeb[3]));
    (* keep, BEL="X0Y8.B" *)  IO_1_bidirectional_frame_config_pass io4_i  (.O(io_in[4]),  .I(io_out[4]),  .T(io_oeb[4]));
    (* keep, BEL="X0Y8.A" *)  IO_1_bidirectional_frame_config_pass io5_i  (.O(io_in[5]),  .I(io_out[5]),  .T(io_oeb[5]));
    (* keep, BEL="X0Y7.B" *)  IO_1_bidirectional_frame_config_pass io6_i  (.O(io_in[6]),  .I(io_out[6]),  .T(io_oeb[6]));
    (* keep, BEL="X0Y7.A" *)  IO_1_bidirectional_frame_config_pass io7_i  (.O(io_in[7]),  .I(io_out[7]),  .T(io_oeb[7]));
    (* keep, BEL="X0Y6.B" *)  IO_1_bidirectional_frame_config_pass io8_i  (.O(io_in[8]),  .I(io_out[8]),  .T(io_oeb[8]));
    (* keep, BEL="X0Y6.A" *)  IO_1_bidirectional_frame_config_pass io9_i  (.O(io_in[9]),  .I(io_out[9]),  .T(io_oeb[9]));
    (* keep, BEL="X0Y5.B" *)  IO_1_bidirectional_frame_config_pass io10_i (.O(io_in[10]), .I(io_out[10]), .T(io_oeb[10]));
    (* keep, BEL="X0Y5.A" *)  IO_1_bidirectional_frame_config_pass io11_i (.O(io_in[11]), .I(io_out[11]), .T(io_oeb[11]));
    (* keep, BEL="X0Y4.B" *)  IO_1_bidirectional_frame_config_pass io12_i (.O(io_in[12]), .I(io_out[12]), .T(io_oeb[12]));
    (* keep, BEL="X0Y4.A" *)  IO_1_bidirectional_frame_config_pass io13_i (.O(io_in[13]), .I(io_out[13]), .T(io_oeb[13]));
    (* keep, BEL="X0Y3.B" *)  IO_1_bidirectional_frame_config_pass io14_i (.O(io_in[14]), .I(io_out[14]), .T(io_oeb[14]));
    (* keep, BEL="X0Y3.A" *)  IO_1_bidirectional_frame_config_pass io15_i (.O(io_in[15]), .I(io_out[15]), .T(io_oeb[15]));
    (* keep, BEL="X0Y2.B" *)  IO_1_bidirectional_frame_config_pass io16_i (.O(io_in[16]), .I(io_out[16]), .T(io_oeb[16]));
    (* keep, BEL="X0Y2.A" *)  IO_1_bidirectional_frame_config_pass io17_i (.O(io_in[17]), .I(io_out[17]), .T(io_oeb[17]));
    (* keep, BEL="X0Y1.B" *)  IO_1_bidirectional_frame_config_pass io18_i (.O(io_in[18]), .I(io_out[18]), .T(io_oeb[18]));
    (* keep, BEL="X0Y1.A" *)  IO_1_bidirectional_frame_config_pass io19_i (.O(io_in[19]), .I(io_out[19]), .T(io_oeb[19]));


    // ========================================================================
    // Internal Fabric AXI Wires
    // ========================================================================
    wire [9:0]  axil_awaddr; wire axil_awvalid; wire axil_awready;
    wire [31:0] axil_wdata;  wire [3:0] axil_wstrb; wire axil_wvalid; wire axil_wready;
    wire [1:0]  axil_bresp;  wire axil_bvalid;  wire axil_bready;
    wire [9:0]  axil_araddr; wire axil_arvalid; wire axil_arready;
    wire [31:0] axil_rdata;  wire [1:0] axil_rresp; wire axil_rvalid; wire axil_rready;

    wire [31:0] axi_awaddr; wire [7:0] axi_awlen; wire [2:0] axi_awsize; wire [1:0] axi_awburst; wire axi_awvalid; wire axi_awready;
    wire [31:0] axi_wdata;  wire [3:0] axi_wstrb; wire axi_wlast; wire axi_wvalid; wire axi_wready;
    wire [1:0]  axi_bresp;  wire axi_bvalid;  wire axi_bready;
    wire [31:0] axi_araddr; wire [7:0] axi_arlen; wire [2:0] axi_arsize; wire [1:0] axi_arburst; wire axi_arvalid; wire axi_arready;
    wire [31:0] axi_rdata;  wire [1:0] axi_rresp; wire axi_rlast; wire axi_rvalid; wire axi_rready;

    // ========================================================================
    // BEL Instantiations (SOC pins omitted, FAB pins flattened to match .list)
    // ========================================================================
    (* keep, BEL="X11Y10.A" *) AXIL_S_BEL axil_bel_inst (

        .FAB_AWREADY(axil_awready), .FAB_WREADY(axil_wready),
        .FAB_BRESP1(axil_bresp[1]), .FAB_BRESP0(axil_bresp[0]), .FAB_BVALID(axil_bvalid),
        .FAB_ARREADY(axil_arready), 
        .FAB_RDATA31(axil_rdata[31]), .FAB_RDATA30(axil_rdata[30]), .FAB_RDATA29(axil_rdata[29]), .FAB_RDATA28(axil_rdata[28]),
        .FAB_RDATA27(axil_rdata[27]), .FAB_RDATA26(axil_rdata[26]), .FAB_RDATA25(axil_rdata[25]), .FAB_RDATA24(axil_rdata[24]),
        .FAB_RDATA23(axil_rdata[23]), .FAB_RDATA22(axil_rdata[22]), .FAB_RDATA21(axil_rdata[21]), .FAB_RDATA20(axil_rdata[20]),
        .FAB_RDATA19(axil_rdata[19]), .FAB_RDATA18(axil_rdata[18]), .FAB_RDATA17(axil_rdata[17]), .FAB_RDATA16(axil_rdata[16]),
        .FAB_RDATA15(axil_rdata[15]), .FAB_RDATA14(axil_rdata[14]), .FAB_RDATA13(axil_rdata[13]), .FAB_RDATA12(axil_rdata[12]),
        .FAB_RDATA11(axil_rdata[11]), .FAB_RDATA10(axil_rdata[10]), .FAB_RDATA9(axil_rdata[9]),   .FAB_RDATA8(axil_rdata[8]),
        .FAB_RDATA7(axil_rdata[7]),   .FAB_RDATA6(axil_rdata[6]),   .FAB_RDATA5(axil_rdata[5]),   .FAB_RDATA4(axil_rdata[4]),
        .FAB_RDATA3(axil_rdata[3]),   .FAB_RDATA2(axil_rdata[2]),   .FAB_RDATA1(axil_rdata[1]),   .FAB_RDATA0(axil_rdata[0]),
        .FAB_RRESP1(axil_rresp[1]), .FAB_RRESP0(axil_rresp[0]), .FAB_RVALID(axil_rvalid),

        .FAB_AWADDR9(axil_awaddr[9]), .FAB_AWADDR8(axil_awaddr[8]), .FAB_AWADDR7(axil_awaddr[7]), .FAB_AWADDR6(axil_awaddr[6]),
        .FAB_AWADDR5(axil_awaddr[5]), .FAB_AWADDR4(axil_awaddr[4]), .FAB_AWADDR3(axil_awaddr[3]), .FAB_AWADDR2(axil_awaddr[2]),
        .FAB_AWADDR1(axil_awaddr[1]), .FAB_AWADDR0(axil_awaddr[0]), .FAB_AWVALID(axil_awvalid),
        .FAB_WDATA31(axil_wdata[31]), .FAB_WDATA30(axil_wdata[30]), .FAB_WDATA29(axil_wdata[29]), .FAB_WDATA28(axil_wdata[28]),
        .FAB_WDATA27(axil_wdata[27]), .FAB_WDATA26(axil_wdata[26]), .FAB_WDATA25(axil_wdata[25]), .FAB_WDATA24(axil_wdata[24]),
        .FAB_WDATA23(axil_wdata[23]), .FAB_WDATA22(axil_wdata[22]), .FAB_WDATA21(axil_wdata[21]), .FAB_WDATA20(axil_wdata[20]),
        .FAB_WDATA19(axil_wdata[19]), .FAB_WDATA18(axil_wdata[18]), .FAB_WDATA17(axil_wdata[17]), .FAB_WDATA16(axil_wdata[16]),
        .FAB_WDATA15(axil_wdata[15]), .FAB_WDATA14(axil_wdata[14]), .FAB_WDATA13(axil_wdata[13]), .FAB_WDATA12(axil_wdata[12]),
        .FAB_WDATA11(axil_wdata[11]), .FAB_WDATA10(axil_wdata[10]), .FAB_WDATA9(axil_wdata[9]),   .FAB_WDATA8(axil_wdata[8]),
        .FAB_WDATA7(axil_wdata[7]),   .FAB_WDATA6(axil_wdata[6]),   .FAB_WDATA5(axil_wdata[5]),   .FAB_WDATA4(axil_wdata[4]),
        .FAB_WDATA3(axil_wdata[3]),   .FAB_WDATA2(axil_wdata[2]),   .FAB_WDATA1(axil_wdata[1]),   .FAB_WDATA0(axil_wdata[0]),
        .FAB_WSTRB3(axil_wstrb[3]), .FAB_WSTRB2(axil_wstrb[2]), .FAB_WSTRB1(axil_wstrb[1]), .FAB_WSTRB0(axil_wstrb[0]),
        .FAB_WVALID(axil_wvalid), .FAB_BREADY(axil_bready),
        .FAB_ARADDR9(axil_araddr[9]), .FAB_ARADDR8(axil_araddr[8]), .FAB_ARADDR7(axil_araddr[7]), .FAB_ARADDR6(axil_araddr[6]),
        .FAB_ARADDR5(axil_araddr[5]), .FAB_ARADDR4(axil_araddr[4]), .FAB_ARADDR3(axil_araddr[3]), .FAB_ARADDR2(axil_araddr[2]),
        .FAB_ARADDR1(axil_araddr[1]), .FAB_ARADDR0(axil_araddr[0]), .FAB_ARVALID(axil_arvalid), .FAB_RREADY(axil_rready)
    );

    (* keep, BEL="X11Y6.A" *) AXI_M_BEL #(
        // Configure your tie-offs here (1 = enabled, 0 = disabled)
        .TIE_OFF_AWLEN(1),
        .TIE_OFF_AWSIZE(1),
        .TIE_OFF_AWBURST(1),
        .TIE_OFF_WSTRB(1),
        .TIE_OFF_WLAST(1),
        .TIE_OFF_ARLEN(1),
        .TIE_OFF_ARSIZE(1),
        .TIE_OFF_ARBURST(1)
    ) axif_bel_inst (

        .FAB_AWREADY(axi_awready), .FAB_WREADY(axi_wready), 
        .FAB_BRESP1(axi_bresp[1]), .FAB_BRESP0(axi_bresp[0]), .FAB_BVALID(axi_bvalid),
        .FAB_ARREADY(axi_arready), 
        .FAB_RDATA31(axi_rdata[31]), .FAB_RDATA30(axi_rdata[30]), .FAB_RDATA29(axi_rdata[29]), .FAB_RDATA28(axi_rdata[28]),
        .FAB_RDATA27(axi_rdata[27]), .FAB_RDATA26(axi_rdata[26]), .FAB_RDATA25(axi_rdata[25]), .FAB_RDATA24(axi_rdata[24]),
        .FAB_RDATA23(axi_rdata[23]), .FAB_RDATA22(axi_rdata[22]), .FAB_RDATA21(axi_rdata[21]), .FAB_RDATA20(axi_rdata[20]),
        .FAB_RDATA19(axi_rdata[19]), .FAB_RDATA18(axi_rdata[18]), .FAB_RDATA17(axi_rdata[17]), .FAB_RDATA16(axi_rdata[16]),
        .FAB_RDATA15(axi_rdata[15]), .FAB_RDATA14(axi_rdata[14]), .FAB_RDATA13(axi_rdata[13]), .FAB_RDATA12(axi_rdata[12]),
        .FAB_RDATA11(axi_rdata[11]), .FAB_RDATA10(axi_rdata[10]), .FAB_RDATA9(axi_rdata[9]),   .FAB_RDATA8(axi_rdata[8]),
        .FAB_RDATA7(axi_rdata[7]),   .FAB_RDATA6(axi_rdata[6]),   .FAB_RDATA5(axi_rdata[5]),   .FAB_RDATA4(axi_rdata[4]),
        .FAB_RDATA3(axi_rdata[3]),   .FAB_RDATA2(axi_rdata[2]),   .FAB_RDATA1(axi_rdata[1]),   .FAB_RDATA0(axi_rdata[0]),
        .FAB_RRESP1(axi_rresp[1]), .FAB_RRESP0(axi_rresp[0]), .FAB_RLAST(axi_rlast), .FAB_RVALID(axi_rvalid),

        .FAB_AWADDR31(axi_awaddr[31]), .FAB_AWADDR30(axi_awaddr[30]), .FAB_AWADDR29(axi_awaddr[29]), .FAB_AWADDR28(axi_awaddr[28]),
        .FAB_AWADDR27(axi_awaddr[27]), .FAB_AWADDR26(axi_awaddr[26]), .FAB_AWADDR25(axi_awaddr[25]), .FAB_AWADDR24(axi_awaddr[24]),
        .FAB_AWADDR23(axi_awaddr[23]), .FAB_AWADDR22(axi_awaddr[22]), .FAB_AWADDR21(axi_awaddr[21]), .FAB_AWADDR20(axi_awaddr[20]),
        .FAB_AWADDR19(axi_awaddr[19]), .FAB_AWADDR18(axi_awaddr[18]), .FAB_AWADDR17(axi_awaddr[17]), .FAB_AWADDR16(axi_awaddr[16]),
        .FAB_AWADDR15(axi_awaddr[15]), .FAB_AWADDR14(axi_awaddr[14]), .FAB_AWADDR13(axi_awaddr[13]), .FAB_AWADDR12(axi_awaddr[12]),
        .FAB_AWADDR11(axi_awaddr[11]), .FAB_AWADDR10(axi_awaddr[10]), .FAB_AWADDR9(axi_awaddr[9]),   .FAB_AWADDR8(axi_awaddr[8]),
        .FAB_AWADDR7(axi_awaddr[7]),   .FAB_AWADDR6(axi_awaddr[6]),   .FAB_AWADDR5(axi_awaddr[5]),   .FAB_AWADDR4(axi_awaddr[4]),
        .FAB_AWADDR3(axi_awaddr[3]),   .FAB_AWADDR2(axi_awaddr[2]),   .FAB_AWADDR1(axi_awaddr[1]),   .FAB_AWADDR0(axi_awaddr[0]),
        .FAB_AWLEN7(axi_awlen[7]), .FAB_AWLEN6(axi_awlen[6]), .FAB_AWLEN5(axi_awlen[5]), .FAB_AWLEN4(axi_awlen[4]),
        .FAB_AWLEN3(axi_awlen[3]), .FAB_AWLEN2(axi_awlen[2]), .FAB_AWLEN1(axi_awlen[1]), .FAB_AWLEN0(axi_awlen[0]),
        .FAB_AWSIZE2(axi_awsize[2]), .FAB_AWSIZE1(axi_awsize[1]), .FAB_AWSIZE0(axi_awsize[0]),
        .FAB_AWBURST1(axi_awburst[1]), .FAB_AWBURST0(axi_awburst[0]), .FAB_AWVALID(axi_awvalid),
        
        .FAB_WDATA31(axi_wdata[31]), .FAB_WDATA30(axi_wdata[30]), .FAB_WDATA29(axi_wdata[29]), .FAB_WDATA28(axi_wdata[28]),
        .FAB_WDATA27(axi_wdata[27]), .FAB_WDATA26(axi_wdata[26]), .FAB_WDATA25(axi_wdata[25]), .FAB_WDATA24(axi_wdata[24]),
        .FAB_WDATA23(axi_wdata[23]), .FAB_WDATA22(axi_wdata[22]), .FAB_WDATA21(axi_wdata[21]), .FAB_WDATA20(axi_wdata[20]),
        .FAB_WDATA19(axi_wdata[19]), .FAB_WDATA18(axi_wdata[18]), .FAB_WDATA17(axi_wdata[17]), .FAB_WDATA16(axi_wdata[16]),
        .FAB_WDATA15(axi_wdata[15]), .FAB_WDATA14(axi_wdata[14]), .FAB_WDATA13(axi_wdata[13]), .FAB_WDATA12(axi_wdata[12]),
        .FAB_WDATA11(axi_wdata[11]), .FAB_WDATA10(axi_wdata[10]), .FAB_WDATA9(axi_wdata[9]),   .FAB_WDATA8(axi_wdata[8]),
        .FAB_WDATA7(axi_wdata[7]),   .FAB_WDATA6(axi_wdata[6]),   .FAB_WDATA5(axi_wdata[5]),   .FAB_WDATA4(axi_wdata[4]),
        .FAB_WDATA3(axi_wdata[3]),   .FAB_WDATA2(axi_wdata[2]),   .FAB_WDATA1(axi_wdata[1]),   .FAB_WDATA0(axi_wdata[0]),
        .FAB_WSTRB3(axi_wstrb[3]), .FAB_WSTRB2(axi_wstrb[2]), .FAB_WSTRB1(axi_wstrb[1]), .FAB_WSTRB0(axi_wstrb[0]),
        .FAB_WLAST(axi_wlast), .FAB_WVALID(axi_wvalid), .FAB_BREADY(axi_bready),
        
        .FAB_ARADDR31(axi_araddr[31]), .FAB_ARADDR30(axi_araddr[30]), .FAB_ARADDR29(axi_araddr[29]), .FAB_ARADDR28(axi_araddr[28]),
        .FAB_ARADDR27(axi_araddr[27]), .FAB_ARADDR26(axi_araddr[26]), .FAB_ARADDR25(axi_araddr[25]), .FAB_ARADDR24(axi_araddr[24]),
        .FAB_ARADDR23(axi_araddr[23]), .FAB_ARADDR22(axi_araddr[22]), .FAB_ARADDR21(axi_araddr[21]), .FAB_ARADDR20(axi_araddr[20]),
        .FAB_ARADDR19(axi_araddr[19]), .FAB_ARADDR18(axi_araddr[18]), .FAB_ARADDR17(axi_araddr[17]), .FAB_ARADDR16(axi_araddr[16]),
        .FAB_ARADDR15(axi_araddr[15]), .FAB_ARADDR14(axi_araddr[14]), .FAB_ARADDR13(axi_araddr[13]), .FAB_ARADDR12(axi_araddr[12]),
        .FAB_ARADDR11(axi_araddr[11]), .FAB_ARADDR10(axi_araddr[10]), .FAB_ARADDR9(axi_araddr[9]),   .FAB_ARADDR8(axi_araddr[8]),
        .FAB_ARADDR7(axi_araddr[7]),   .FAB_ARADDR6(axi_araddr[6]),   .FAB_ARADDR5(axi_araddr[5]),   .FAB_ARADDR4(axi_araddr[4]),
        .FAB_ARADDR3(axi_araddr[3]),   .FAB_ARADDR2(axi_araddr[2]),   .FAB_ARADDR1(axi_araddr[1]),   .FAB_ARADDR0(axi_araddr[0]),
        .FAB_ARLEN7(axi_arlen[7]), .FAB_ARLEN6(axi_arlen[6]), .FAB_ARLEN5(axi_arlen[5]), .FAB_ARLEN4(axi_arlen[4]),
        .FAB_ARLEN3(axi_arlen[3]), .FAB_ARLEN2(axi_arlen[2]), .FAB_ARLEN1(axi_arlen[1]), .FAB_ARLEN0(axi_arlen[0]),
        .FAB_ARSIZE2(axi_arsize[2]), .FAB_ARSIZE1(axi_arsize[1]), .FAB_ARSIZE0(axi_arsize[0]),
        .FAB_ARBURST1(axi_arburst[1]), .FAB_ARBURST0(axi_arburst[0]), .FAB_ARVALID(axi_arvalid), .FAB_RREADY(axi_rready)
    );

    // ========================================================================
    // User Design Payload
    // ========================================================================
    dma_a user_logic (
        .clk(clk),
        .rstn(sys_rstn),
        .O_top(fabric_debug_out),

        // AXI-Lite
        .axil_awaddr(axil_awaddr), .axil_awvalid(axil_awvalid), .axil_awready(axil_awready),
        .axil_wdata(axil_wdata),   .axil_wstrb(axil_wstrb),     .axil_wvalid(axil_wvalid),   .axil_wready(axil_wready),
        .axil_bresp(axil_bresp),   .axil_bvalid(axil_bvalid),   .axil_bready(axil_bready),
        .axil_araddr(axil_araddr), .axil_arvalid(axil_arvalid), .axil_arready(axil_arready),
        .axil_rdata(axil_rdata),   .axil_rresp(axil_rresp),     .axil_rvalid(axil_rvalid),   .axil_rready(axil_rready),

        // AXI-Full Master
        .axi_awaddr(axi_awaddr), .axi_awlen(axi_awlen), .axi_awsize(axi_awsize), .axi_awburst(axi_awburst), .axi_awvalid(axi_awvalid), .axi_awready(axi_awready),
        .axi_wdata(axi_wdata),   .axi_wstrb(axi_wstrb), .axi_wlast(axi_wlast),   .axi_wvalid(axi_wvalid),   .axi_wready(axi_wready),
        .axi_bresp(axi_bresp),   .axi_bvalid(axi_bvalid), .axi_bready(axi_bready),
        .axi_araddr(axi_araddr), .axi_arlen(axi_arlen), .axi_arsize(axi_arsize), .axi_arburst(axi_arburst), .axi_arvalid(axi_arvalid), .axi_arready(axi_arready),
        .axi_rdata(axi_rdata),   .axi_rresp(axi_rresp), .axi_rlast(axi_rlast),   .axi_rvalid(axi_rvalid),   .axi_rready(axi_rready)
    );

endmodule