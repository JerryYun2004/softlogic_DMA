`timescale 1ns / 1ps
`default_nettype none

// One-word AXI write engine.
//
// Programming model (AXI4-Lite slave):
//   0x00 W: destination address and start
//   0x00 R: last accepted destination address
//   0x04 R: status {29'b0, error, busy, done}
//
// Each accepted command produces one 32-bit AXI4 write of 32'hDEADBEEF.
// Only one command can be active at a time. A command written while busy is
// rejected with an AXI4-Lite SLVERR response.
module dma_a (
    input  wire        clk,
    input  wire        rstn,

    output wire [31:0] O_top,

    // AXI4-Lite slave: CPU control/status interface
    input  wire [9:0]  axil_awaddr,
    input  wire        axil_awvalid,
    output wire        axil_awready,

    input  wire [31:0] axil_wdata,
    input  wire [3:0]  axil_wstrb,
    input  wire        axil_wvalid,
    output wire        axil_wready,

    output reg  [1:0]  axil_bresp,
    output reg         axil_bvalid,
    input  wire        axil_bready,

    input  wire [9:0]  axil_araddr,
    input  wire        axil_arvalid,
    output wire        axil_arready,

    output reg  [31:0] axil_rdata,
    output reg  [1:0]  axil_rresp,
    output reg         axil_rvalid,
    input  wire        axil_rready,

    // AXI4 master: one-beat write interface
    output wire [31:0] axi_awaddr,
    output wire [7:0]  axi_awlen,
    output wire [2:0]  axi_awsize,
    output wire [1:0]  axi_awburst,
    output reg         axi_awvalid,
    input  wire        axi_awready,

    output wire [31:0] axi_wdata,
    output wire [3:0]  axi_wstrb,
    output wire        axi_wlast,
    output reg         axi_wvalid,
    input  wire        axi_wready,

    input  wire [1:0]  axi_bresp,
    input  wire        axi_bvalid,
    output wire        axi_bready,

    // AXI4 read channels are unused by this one-word write engine.
    output wire [31:0] axi_araddr,
    output wire [7:0]  axi_arlen,
    output wire [2:0]  axi_arsize,
    output wire [1:0]  axi_arburst,
    output wire        axi_arvalid,
    input  wire        axi_arready,

    input  wire [31:0] axi_rdata,
    input  wire [1:0]  axi_rresp,
    input  wire        axi_rlast,
    input  wire        axi_rvalid,
    output wire        axi_rready
);

    localparam [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam [1:0] AXI_RESP_SLVERR = 2'b10;
    localparam [1:0] AXI_RESP_DECERR = 2'b11;

    localparam [1:0] DMA_IDLE   = 2'd0;
    localparam [1:0] DMA_SEND   = 2'd1;
    localparam [1:0] DMA_WAIT_B = 2'd2;

    reg [31:0] target_dma_addr;
    reg [31:0] axi_awaddr_reg;
    reg        trigger_dma;
    reg        dma_done;
    reg        dma_busy;
    reg        dma_error;
    reg [1:0]  dma_state;

    // AXI4-Lite write-channel holding registers. AXI permits AW and W to
    // arrive independently, so each channel is captured separately.
    reg        aw_hold_valid;
    reg [9:0]  awaddr_hold;
    reg        w_hold_valid;
    reg [31:0] wdata_hold;
    reg [3:0]  wstrb_hold;

    wire aw_accept;
    wire w_accept;
    wire write_have_aw;
    wire write_have_w;
    wire write_commit;
    wire [9:0]  write_addr;
    wire [31:0] write_data;
    wire [3:0]  write_strb;

    function [31:0] apply_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  strb;
        begin
            apply_wstrb = old_value;
            if (strb[0]) apply_wstrb[7:0]   = new_value[7:0];
            if (strb[1]) apply_wstrb[15:8]  = new_value[15:8];
            if (strb[2]) apply_wstrb[23:16] = new_value[23:16];
            if (strb[3]) apply_wstrb[31:24] = new_value[31:24];
        end
    endfunction

    // Debug outputs: configured marker, completion, busy, and error.
    assign O_top[0]    = 1'b1;
    assign O_top[1]    = dma_done;
    assign O_top[2]    = dma_busy;
    assign O_top[3]    = dma_error;
    assign O_top[31:4] = 28'd0;

    // ---------------------------------------------------------------------
    // AXI4-Lite slave write interface
    // ---------------------------------------------------------------------
    assign axil_awready = !aw_hold_valid && !axil_bvalid;
    assign axil_wready  = !w_hold_valid  && !axil_bvalid;

    assign aw_accept = axil_awvalid && axil_awready;
    assign w_accept  = axil_wvalid  && axil_wready;

    assign write_have_aw = aw_hold_valid || aw_accept;
    assign write_have_w  = w_hold_valid  || w_accept;
    assign write_commit  = write_have_aw && write_have_w && !axil_bvalid;

    assign write_addr = aw_hold_valid ? awaddr_hold : axil_awaddr;
    assign write_data = w_hold_valid  ? wdata_hold  : axil_wdata;
    assign write_strb = w_hold_valid  ? wstrb_hold  : axil_wstrb;

    always @(posedge clk) begin
        if (!rstn) begin
            aw_hold_valid  <= 1'b0;
            awaddr_hold    <= 10'd0;
            w_hold_valid   <= 1'b0;
            wdata_hold     <= 32'd0;
            wstrb_hold     <= 4'd0;
            axil_bresp     <= AXI_RESP_OKAY;
            axil_bvalid    <= 1'b0;
            target_dma_addr <= 32'd0;
            trigger_dma    <= 1'b0;
        end else begin
            // trigger_dma is a one-cycle request pulse consumed by the DMA FSM.
            trigger_dma <= 1'b0;

            if (axil_bvalid && axil_bready)
                axil_bvalid <= 1'b0;

            if (aw_accept && !write_commit) begin
                aw_hold_valid <= 1'b1;
                awaddr_hold   <= axil_awaddr;
            end

            if (w_accept && !write_commit) begin
                w_hold_valid <= 1'b1;
                wdata_hold   <= axil_wdata;
                wstrb_hold   <= axil_wstrb;
            end

            if (write_commit) begin
                aw_hold_valid <= 1'b0;
                w_hold_valid  <= 1'b0;
                axil_bvalid   <= 1'b1;

                if (write_addr == 10'h000) begin
                    if (dma_busy || trigger_dma) begin
                        // Do not overwrite the active command.
                        axil_bresp <= AXI_RESP_SLVERR;
                    end else begin
                        target_dma_addr <= apply_wstrb(
                            target_dma_addr, write_data, write_strb
                        );
                        trigger_dma <= 1'b1;
                        axil_bresp  <= AXI_RESP_OKAY;
                    end
                end else begin
                    axil_bresp <= AXI_RESP_DECERR;
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // AXI4-Lite slave read interface
    // ---------------------------------------------------------------------
    assign axil_arready = !axil_rvalid;

    always @(posedge clk) begin
        if (!rstn) begin
            axil_rdata  <= 32'd0;
            axil_rresp  <= AXI_RESP_OKAY;
            axil_rvalid <= 1'b0;
        end else begin
            if (axil_rvalid && axil_rready)
                axil_rvalid <= 1'b0;

            if (axil_arvalid && axil_arready) begin
                axil_rvalid <= 1'b1;
                case (axil_araddr)
                    10'h000: begin
                        axil_rdata <= target_dma_addr;
                        axil_rresp <= AXI_RESP_OKAY;
                    end
                    10'h004: begin
                        axil_rdata <= {29'd0, dma_error, dma_busy, dma_done};
                        axil_rresp <= AXI_RESP_OKAY;
                    end
                    default: begin
                        axil_rdata <= 32'd0;
                        axil_rresp <= AXI_RESP_DECERR;
                    end
                endcase
            end
        end
    end

    // ---------------------------------------------------------------------
    // AXI4 master: fixed attributes for one 32-bit INCR write beat
    // ---------------------------------------------------------------------
    assign axi_awaddr  = axi_awaddr_reg;
    assign axi_awlen   = 8'd0;
    assign axi_awsize  = 3'b010;
    assign axi_awburst = 2'b01;

    assign axi_wdata = 32'hDEADBEEF;
    assign axi_wstrb = 4'hF;
    assign axi_wlast = 1'b1;

    // Accept a write response only after both AW and W have completed.
    assign axi_bready = (dma_state == DMA_WAIT_B);

    // Unused AXI read channel tie-offs.
    assign axi_araddr  = 32'd0;
    assign axi_arlen   = 8'd0;
    assign axi_arsize  = 3'b010;
    assign axi_arburst = 2'b01;
    assign axi_arvalid = 1'b0;
    assign axi_rready  = 1'b0;

    always @(posedge clk) begin
        if (!rstn) begin
            dma_state     <= DMA_IDLE;
            axi_awaddr_reg <= 32'd0;
            axi_awvalid   <= 1'b0;
            axi_wvalid    <= 1'b0;
            dma_done      <= 1'b0;
            dma_busy      <= 1'b0;
            dma_error     <= 1'b0;
        end else begin
            case (dma_state)
                DMA_IDLE: begin
                    axi_awvalid <= 1'b0;
                    axi_wvalid  <= 1'b0;
                    dma_busy    <= 1'b0;

                    if (trigger_dma) begin
                        // Latch the command so AWADDR remains stable if stalled.
                        axi_awaddr_reg <= target_dma_addr;
                        axi_awvalid    <= 1'b1;
                        axi_wvalid     <= 1'b1;
                        dma_done       <= 1'b0;
                        dma_error      <= 1'b0;
                        dma_busy       <= 1'b1;
                        dma_state      <= DMA_SEND;
                    end
                end

                DMA_SEND: begin
                    if (axi_awvalid && axi_awready)
                        axi_awvalid <= 1'b0;

                    if (axi_wvalid && axi_wready)
                        axi_wvalid <= 1'b0;

                    // Include handshakes occurring on this edge when deciding
                    // whether both independent channels have completed.
                    if ((!axi_awvalid || axi_awready) &&
                        (!axi_wvalid  || axi_wready)) begin
                        dma_state <= DMA_WAIT_B;
                    end
                end

                DMA_WAIT_B: begin
                    if (axi_bvalid && axi_bready) begin
                        dma_done  <= 1'b1;
                        dma_busy  <= 1'b0;
                        dma_error <= (axi_bresp != AXI_RESP_OKAY);
                        dma_state <= DMA_IDLE;
                    end
                end

                default: begin
                    dma_state   <= DMA_IDLE;
                    axi_awvalid <= 1'b0;
                    axi_wvalid  <= 1'b0;
                    dma_busy    <= 1'b0;
                    dma_done    <= 1'b0;
                    dma_error   <= 1'b1;
                end
            endcase
        end
    end

    // The one-word engine intentionally does not consume these read inputs.
    // They remain in the interface so dma_a stays compatible with top_wrapper.
    wire unused_axi_read_inputs;
    assign unused_axi_read_inputs = axi_arready ^ axi_rdata[0] ^
                                    axi_rresp[0] ^ axi_rlast ^ axi_rvalid;

endmodule

`default_nettype wire
