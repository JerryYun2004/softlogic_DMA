`timescale 1ns / 1ps

module AXIL_S_BEL(
    // input  wire [2:0]                SOC_AWPROT,
    // input  wire [2:0]                SOC_ARPROT,
    // output wire [2:0]             FAB_AWPROT,
    // output wire [2:0]             FAB_ARPROT,
    (* FABulous, EXTERNAL *) input  wire [9:0]                SOC_AWADDR,
    (* FABulous, EXTERNAL *) input  wire                      SOC_AWVALID,
    (* FABulous, EXTERNAL *) input  wire [31:0]               SOC_WDATA,
    (* FABulous, EXTERNAL *) input  wire [3:0]                SOC_WSTRB,
    (* FABulous, EXTERNAL *) input  wire                      SOC_WVALID,
    (* FABulous, EXTERNAL *) input  wire                      SOC_BREADY,
    (* FABulous, EXTERNAL *) input  wire [9:0]                SOC_ARADDR,
    (* FABulous, EXTERNAL *) input  wire                      SOC_ARVALID,
    (* FABulous, EXTERNAL *) input  wire                      SOC_RREADY,
    (* FABulous, EXTERNAL *) output wire                      SOC_AWREADY,
    (* FABulous, EXTERNAL *) output wire                      SOC_WREADY,
    (* FABulous, EXTERNAL *) output wire [1:0]                SOC_BRESP,
    (* FABulous, EXTERNAL *) output wire                      SOC_BVALID,
    (* FABulous, EXTERNAL *) output wire                      SOC_ARREADY,
    (* FABulous, EXTERNAL *) output wire [31:0]               SOC_RDATA,
    (* FABulous, EXTERNAL *) output wire [1:0]                SOC_RRESP,
    (* FABulous, EXTERNAL *) output wire                      SOC_RVALID,

    input  wire                      FAB_AWREADY,
    input  wire                      FAB_WREADY,
    input  wire [1:0]                FAB_BRESP,
    input  wire                      FAB_BVALID,
    input  wire                      FAB_ARREADY,
    input  wire [31:0]               FAB_RDATA,
    input  wire [1:0]                FAB_RRESP,
    input  wire                      FAB_RVALID,
    output wire [9:0]                FAB_AWADDR,
    output wire                      FAB_AWVALID,
    output wire [31:0]               FAB_WDATA,
    output wire [3:0]                FAB_WSTRB,
    output wire                      FAB_WVALID,
    output wire                      FAB_BREADY,
    output wire [9:0]                FAB_ARADDR,
    output wire                      FAB_ARVALID,
    output wire                      FAB_RREADY
);

    // ==========================================
    // SOC -> FABRIC
    // ==========================================
    assign FAB_AWADDR  = SOC_AWADDR;
    // assign FAB_AWPROT  = SOC_AWPROT;
    assign FAB_AWVALID = SOC_AWVALID;
    assign FAB_WDATA   = SOC_WDATA;
    assign FAB_WSTRB   = SOC_WSTRB;
    assign FAB_WVALID  = SOC_WVALID;
    assign FAB_BREADY  = SOC_BREADY;
    assign FAB_ARADDR  = SOC_ARADDR;
    // assign FAB_ARPROT  = SOC_ARPROT;
    assign FAB_ARVALID = SOC_ARVALID;
    assign FAB_RREADY  = SOC_RREADY;

    // ==========================================
    // FABRIC -> SOC
    // ==========================================
    assign SOC_AWREADY = FAB_AWREADY;
    assign SOC_WREADY  = FAB_WREADY;

    assign SOC_BRESP   = FAB_BRESP;
    assign SOC_BVALID  = FAB_BVALID;

    assign SOC_ARREADY = FAB_ARREADY;
    assign SOC_RDATA   = FAB_RDATA;

    assign SOC_RRESP   = FAB_RRESP;
    assign SOC_RVALID  = FAB_RVALID;

endmodule
