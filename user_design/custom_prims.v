
//Warning: The primitive InPass4_frame_config_mux was added by FABulous automatically.
(* blackbox, keep *)
module InPass4_frame_config_mux (
    output O0,
    output O1,
    output O2,
    output O3,
    (* iopad_external_pin *)
    input I0,
    (* iopad_external_pin *)
    input I1,
    (* iopad_external_pin *)
    input I2,
    (* iopad_external_pin *)
    input I3,
    input CLK
);
    parameter I0_reg = 0;
    parameter I1_reg = 0;
    parameter I2_reg = 0;
    parameter I3_reg = 0;
endmodule

//Warning: The primitive OutPass4_frame_config_mux was added by FABulous automatically.
(* blackbox, keep *)
module OutPass4_frame_config_mux (
    input I0,
    input I1,
    input I2,
    input I3,
    (* iopad_external_pin *)
    output O0,
    (* iopad_external_pin *)
    output O1,
    (* iopad_external_pin *)
    output O2,
    (* iopad_external_pin *)
    output O3,
    input CLK
);
    parameter I0_reg = 0;
    parameter I1_reg = 0;
    parameter I2_reg = 0;
    parameter I3_reg = 0;
endmodule

// =====================================================================
// Custom AXI BEL Blackboxes for User Design Synthesis
// =====================================================================

(* blackbox, keep *)
module AXIL_S_BEL (
    // --- External Pins (Vector arrays are fine here since they leave the fabric) ---
    (* iopad_external_pin *) input  wire [9:0]  SOC_AWADDR,
    (* iopad_external_pin *) input  wire        SOC_AWVALID,
    (* iopad_external_pin *) output wire        SOC_AWREADY,
    (* iopad_external_pin *) input  wire [31:0] SOC_WDATA,
    (* iopad_external_pin *) input  wire [3:0]  SOC_WSTRB,
    (* iopad_external_pin *) input  wire        SOC_WVALID,
    (* iopad_external_pin *) output wire        SOC_WREADY,
    (* iopad_external_pin *) output wire [1:0]  SOC_BRESP,
    (* iopad_external_pin *) output wire        SOC_BVALID,
    (* iopad_external_pin *) input  wire        SOC_BREADY,
    (* iopad_external_pin *) input  wire [9:0]  SOC_ARADDR,
    (* iopad_external_pin *) input  wire        SOC_ARVALID,
    (* iopad_external_pin *) output wire        SOC_ARREADY,
    (* iopad_external_pin *) output wire [31:0] SOC_RDATA,
    (* iopad_external_pin *) output wire [1:0]  SOC_RRESP,
    (* iopad_external_pin *) output wire        SOC_RVALID,
    (* iopad_external_pin *) input  wire        SOC_RREADY,

    // --- Internal Pins (Flattened to strictly match NextPNR .list database) ---
    input  wire FAB_AWREADY,
    input  wire FAB_WREADY,
    input  wire FAB_BRESP1, FAB_BRESP0,
    input  wire FAB_BVALID,
    input  wire FAB_ARREADY,
    input  wire FAB_RDATA31, FAB_RDATA30, FAB_RDATA29, FAB_RDATA28, FAB_RDATA27, FAB_RDATA26, FAB_RDATA25, FAB_RDATA24,
    input  wire FAB_RDATA23, FAB_RDATA22, FAB_RDATA21, FAB_RDATA20, FAB_RDATA19, FAB_RDATA18, FAB_RDATA17, FAB_RDATA16,
    input  wire FAB_RDATA15, FAB_RDATA14, FAB_RDATA13, FAB_RDATA12, FAB_RDATA11, FAB_RDATA10, FAB_RDATA9,  FAB_RDATA8,
    input  wire FAB_RDATA7,  FAB_RDATA6,  FAB_RDATA5,  FAB_RDATA4,  FAB_RDATA3,  FAB_RDATA2,  FAB_RDATA1,  FAB_RDATA0,
    input  wire FAB_RRESP1,  FAB_RRESP0,
    input  wire FAB_RVALID,

    output wire FAB_AWADDR9, FAB_AWADDR8, FAB_AWADDR7, FAB_AWADDR6, FAB_AWADDR5, FAB_AWADDR4, FAB_AWADDR3, FAB_AWADDR2, FAB_AWADDR1, FAB_AWADDR0,
    output wire FAB_AWVALID,
    output wire FAB_WDATA31, FAB_WDATA30, FAB_WDATA29, FAB_WDATA28, FAB_WDATA27, FAB_WDATA26, FAB_WDATA25, FAB_WDATA24,
    output wire FAB_WDATA23, FAB_WDATA22, FAB_WDATA21, FAB_WDATA20, FAB_WDATA19, FAB_WDATA18, FAB_WDATA17, FAB_WDATA16,
    output wire FAB_WDATA15, FAB_WDATA14, FAB_WDATA13, FAB_WDATA12, FAB_WDATA11, FAB_WDATA10, FAB_WDATA9,  FAB_WDATA8,
    output wire FAB_WDATA7,  FAB_WDATA6,  FAB_WDATA5,  FAB_WDATA4,  FAB_WDATA3,  FAB_WDATA2,  FAB_WDATA1,  FAB_WDATA0,
    output wire FAB_WSTRB3, FAB_WSTRB2, FAB_WSTRB1, FAB_WSTRB0,
    output wire FAB_WVALID,
    output wire FAB_BREADY,
    output wire FAB_ARADDR9, FAB_ARADDR8, FAB_ARADDR7, FAB_ARADDR6, FAB_ARADDR5, FAB_ARADDR4, FAB_ARADDR3, FAB_ARADDR2, FAB_ARADDR1, FAB_ARADDR0,
    output wire FAB_ARVALID,
    output wire FAB_RREADY
);
endmodule

(* blackbox, keep *)
module AXI_M_BEL (
    // --- External Pins ---
    (* iopad_external_pin *) output wire [31:0] SOC_AWADDR,
    (* iopad_external_pin *) output wire [7:0]  SOC_AWLEN,
    (* iopad_external_pin *) output wire [2:0]  SOC_AWSIZE,
    (* iopad_external_pin *) output wire [1:0]  SOC_AWBURST,
    (* iopad_external_pin *) output wire        SOC_AWVALID,
    (* iopad_external_pin *) input  wire        SOC_AWREADY,
    (* iopad_external_pin *) output wire [31:0] SOC_WDATA,
    (* iopad_external_pin *) output wire [3:0]  SOC_WSTRB,
    (* iopad_external_pin *) output wire        SOC_WLAST,
    (* iopad_external_pin *) output wire        SOC_WVALID,
    (* iopad_external_pin *) input  wire        SOC_WREADY,
    (* iopad_external_pin *) input  wire [1:0]  SOC_BRESP,
    (* iopad_external_pin *) input  wire        SOC_BVALID,
    (* iopad_external_pin *) output wire        SOC_BREADY,
    (* iopad_external_pin *) output wire [31:0] SOC_ARADDR,
    (* iopad_external_pin *) output wire [7:0]  SOC_ARLEN,
    (* iopad_external_pin *) output wire [2:0]  SOC_ARSIZE,
    (* iopad_external_pin *) output wire [1:0]  SOC_ARBURST,
    (* iopad_external_pin *) output wire        SOC_ARVALID,
    (* iopad_external_pin *) input  wire        SOC_ARREADY,
    (* iopad_external_pin *) input  wire [31:0] SOC_RDATA,
    (* iopad_external_pin *) input  wire [1:0]  SOC_RRESP,
    (* iopad_external_pin *) input  wire        SOC_RLAST,
    (* iopad_external_pin *) input  wire        SOC_RVALID,
    (* iopad_external_pin *) output wire        SOC_RREADY,

    // --- Internal Pins (Flattened to strictly match NextPNR .list database) ---
    input  wire FAB_AWADDR31, FAB_AWADDR30, FAB_AWADDR29, FAB_AWADDR28, FAB_AWADDR27, FAB_AWADDR26, FAB_AWADDR25, FAB_AWADDR24,
    input  wire FAB_AWADDR23, FAB_AWADDR22, FAB_AWADDR21, FAB_AWADDR20, FAB_AWADDR19, FAB_AWADDR18, FAB_AWADDR17, FAB_AWADDR16,
    input  wire FAB_AWADDR15, FAB_AWADDR14, FAB_AWADDR13, FAB_AWADDR12, FAB_AWADDR11, FAB_AWADDR10, FAB_AWADDR9,  FAB_AWADDR8,
    input  wire FAB_AWADDR7,  FAB_AWADDR6,  FAB_AWADDR5,  FAB_AWADDR4,  FAB_AWADDR3,  FAB_AWADDR2,  FAB_AWADDR1,  FAB_AWADDR0,
    input  wire FAB_AWLEN7, FAB_AWLEN6, FAB_AWLEN5, FAB_AWLEN4, FAB_AWLEN3, FAB_AWLEN2, FAB_AWLEN1, FAB_AWLEN0,
    input  wire FAB_AWSIZE2, FAB_AWSIZE1, FAB_AWSIZE0,
    input  wire FAB_AWBURST1, FAB_AWBURST0,
    input  wire FAB_AWVALID,
    
    input  wire FAB_WDATA31, FAB_WDATA30, FAB_WDATA29, FAB_WDATA28, FAB_WDATA27, FAB_WDATA26, FAB_WDATA25, FAB_WDATA24,
    input  wire FAB_WDATA23, FAB_WDATA22, FAB_WDATA21, FAB_WDATA20, FAB_WDATA19, FAB_WDATA18, FAB_WDATA17, FAB_WDATA16,
    input  wire FAB_WDATA15, FAB_WDATA14, FAB_WDATA13, FAB_WDATA12, FAB_WDATA11, FAB_WDATA10, FAB_WDATA9,  FAB_WDATA8,
    input  wire FAB_WDATA7,  FAB_WDATA6,  FAB_WDATA5,  FAB_WDATA4,  FAB_WDATA3,  FAB_WDATA2,  FAB_WDATA1,  FAB_WDATA0,
    input  wire FAB_WSTRB3, FAB_WSTRB2, FAB_WSTRB1, FAB_WSTRB0,
    input  wire FAB_WLAST,
    input  wire FAB_WVALID,
    input  wire FAB_BREADY,
    
    input  wire FAB_ARADDR31, FAB_ARADDR30, FAB_ARADDR29, FAB_ARADDR28, FAB_ARADDR27, FAB_ARADDR26, FAB_ARADDR25, FAB_ARADDR24,
    input  wire FAB_ARADDR23, FAB_ARADDR22, FAB_ARADDR21, FAB_ARADDR20, FAB_ARADDR19, FAB_ARADDR18, FAB_ARADDR17, FAB_ARADDR16,
    input  wire FAB_ARADDR15, FAB_ARADDR14, FAB_ARADDR13, FAB_ARADDR12, FAB_ARADDR11, FAB_ARADDR10, FAB_ARADDR9,  FAB_ARADDR8,
    input  wire FAB_ARADDR7,  FAB_ARADDR6,  FAB_ARADDR5,  FAB_ARADDR4,  FAB_ARADDR3,  FAB_ARADDR2,  FAB_ARADDR1,  FAB_ARADDR0,
    input  wire FAB_ARLEN7, FAB_ARLEN6, FAB_ARLEN5, FAB_ARLEN4, FAB_ARLEN3, FAB_ARLEN2, FAB_ARLEN1, FAB_ARLEN0,
    input  wire FAB_ARSIZE2, FAB_ARSIZE1, FAB_ARSIZE0,
    input  wire FAB_ARBURST1, FAB_ARBURST0,
    input  wire FAB_ARVALID,
    input  wire FAB_RREADY,

    output wire FAB_AWREADY,
    output wire FAB_WREADY,
    output wire FAB_BRESP1, FAB_BRESP0,
    output wire FAB_BVALID,
    output wire FAB_ARREADY,
    output wire FAB_RDATA31, FAB_RDATA30, FAB_RDATA29, FAB_RDATA28, FAB_RDATA27, FAB_RDATA26, FAB_RDATA25, FAB_RDATA24,
    output wire FAB_RDATA23, FAB_RDATA22, FAB_RDATA21, FAB_RDATA20, FAB_RDATA19, FAB_RDATA18, FAB_RDATA17, FAB_RDATA16,
    output wire FAB_RDATA15, FAB_RDATA14, FAB_RDATA13, FAB_RDATA12, FAB_RDATA11, FAB_RDATA10, FAB_RDATA9,  FAB_RDATA8,
    output wire FAB_RDATA7,  FAB_RDATA6,  FAB_RDATA5,  FAB_RDATA4,  FAB_RDATA3,  FAB_RDATA2,  FAB_RDATA1,  FAB_RDATA0,
    output wire FAB_RRESP1, FAB_RRESP0,
    output wire FAB_RLAST,
    output wire FAB_RVALID
);
    parameter TIE_OFF_AWLEN = 0;
    parameter TIE_OFF_AWSIZE = 0;
    parameter TIE_OFF_AWBURST = 0;
    parameter TIE_OFF_WSTRB = 0;
    parameter TIE_OFF_WLAST = 0;
    parameter TIE_OFF_ARLEN = 0;
    parameter TIE_OFF_ARSIZE = 0;
    parameter TIE_OFF_ARBURST = 0;
endmodule


// Dedicated FABulous clock-network source used by top_wrapper.
(* blackbox *)
module Global_Clock (
    output wire CLK
);
endmodule