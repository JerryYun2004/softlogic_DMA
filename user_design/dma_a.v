`timescale 1ns / 1ps

module dma_a (
    input wire clk,
    input wire rstn,

    output wire [31:0] O_top,

    // AXIL Slave
    input  wire [9:0]  axil_awaddr, input wire axil_awvalid, output reg axil_awready,
    input  wire [31:0] axil_wdata,  input wire [3:0] axil_wstrb, input wire axil_wvalid, output reg axil_wready,
    output reg  [1:0]  axil_bresp,  output reg axil_bvalid,  input wire axil_bready,
    input  wire [9:0]  axil_araddr, input wire axil_arvalid, output reg axil_arready,
    output reg  [31:0] axil_rdata,  output reg [1:0] axil_rresp, output reg axil_rvalid, input wire axil_rready,

    // AXI Master
    output wire [31:0] axi_awaddr, output wire [7:0] axi_awlen, output wire [2:0] axi_awsize, output wire [1:0] axi_awburst, output reg axi_awvalid, input wire axi_awready,
    output wire [31:0] axi_wdata,  output wire [3:0] axi_wstrb, output wire axi_wlast, output reg axi_wvalid, input wire axi_wready,
    input  wire [1:0]  axi_bresp,  input  wire axi_bvalid,  output wire axi_bready,
    output wire [31:0] axi_araddr, output wire [7:0] axi_arlen, output wire [2:0] axi_arsize, output wire [1:0] axi_arburst, output wire axi_arvalid, input wire axi_arready,
    input  wire [31:0] axi_rdata,  output wire [1:0] axi_rresp, input wire axi_rlast, input wire axi_rvalid, output wire axi_rready
);

    // ========================================================
    // TIE OFFS (AXI Master configuration for 1-beat 32-bit write)
    // ========================================================
    assign axi_araddr  = 32'd0;
    assign axi_awlen   = 8'd0;
    assign axi_awsize  = 3'b010;
    assign axi_awburst = 2'b01;
    assign axi_wstrb   = 4'hF;
    assign axi_wlast   = 1'b1;
    assign axi_arvalid = 1'b0;
    assign axi_rready  = 1'b1;
    assign axi_bready  = 1'b1;
    assign axi_arlen   = 8'd0;
    assign axi_arsize  = 3'b010;
    assign axi_arburst = 2'b01;

    // ========================================================
    // STATE & CONTROL REGISTERS
    // ========================================================
    reg [31:0] target_dma_addr;
    reg        trigger_dma;
    reg        dma_done;

    // ========================================================
    // O_top CONFIGURATION
    // ========================================================
    assign O_top[0]    = 1'b1;      // Bit 0: Hard 1 (proves bitstream is loaded)
    assign O_top[1]    = dma_done;  // Bit 1: DMA completion flag
    assign O_top[31:2] = 30'd0;     // Tie off the rest

    // ========================================================
    // AXI-Lite Slave Interface
    // ========================================================
    reg w_state;
    reg r_state;

    always @(posedge clk) begin
        if (!rstn) begin
            axil_awready    <= 1'b0; 
            axil_wready     <= 1'b0; 
            axil_bvalid     <= 1'b0; 
            axil_bresp      <= 2'b00;
            axil_arready    <= 1'b0; 
            axil_rvalid     <= 1'b0; 
            axil_rresp      <= 2'b00; 
            axil_rdata      <= 32'h0;
            w_state         <= 1'b0;
            r_state         <= 1'b0;
            trigger_dma     <= 1'b0;
            target_dma_addr <= 32'd0;
        end else begin
            if (trigger_dma) trigger_dma <= 1'b0;
            
            // --- WRITE CHANNEL (Single-Cycle Simultaneous Handshake) ---
            case (w_state)
                1'b0: begin                    
                    if (axil_awvalid && axil_wvalid) begin
                        // Single-cycle data capture & trigger
                        axil_awready <= 1'b1;
                        axil_wready  <= 1'b1;
                        axil_bvalid  <= 1'b1;         // Fire bvalid on the very next cycle
                        axil_bresp   <= 2'b00;        // OKAY response
                        w_state      <= 1'b1;
                        
                        if (axil_awaddr[7:0] == 8'h00) begin
                            target_dma_addr <= axil_wdata;
                            trigger_dma     <= 1'b1;
                        end
                    end
                end
                
                1'b1: begin
                    // Ensure readies are off while waiting for response acknowledgment
                    axil_awready <= 1'b0;
                    axil_wready  <= 1'b0;
                    
                    if (axil_bready && axil_bvalid) begin
                        axil_bvalid <= 1'b0;
                        w_state     <= 1'b0;
                    end
                end
            endcase
            
            // --- READ CHANNEL (Offset 0x04 returns status) ---
            case (r_state)
                1'b0: begin
                    axil_arready <= 1'b1;
                    if (axil_arvalid && axil_arready) begin
                        axil_arready <= 1'b0;
                        axil_rvalid  <= 1'b1;
                        axil_rresp   <= 2'b00; // OKAY response
                        
                        if (axil_araddr[7:0] == 8'h04) begin
                            axil_rdata <= {31'd0, dma_done};
                        end else begin
                            axil_rdata <= 32'hDEADBEEF;
                        end
                        
                        r_state <= 1'b1;
                    end
                end
                1'b1: begin
                    if (axil_rready && axil_rvalid) begin
                        axil_rvalid <= 1'b0;
                        r_state     <= 1'b0;
                    end
                end
            endcase
        end
    end

    // ========================================================
    // AXI-Full Master Write State Machine
    // ========================================================
    reg [1:0] dma_state;
    localparam IDLE = 2'd0, REQ = 2'd1, WAIT_B = 2'd2;

    assign axi_awaddr = target_dma_addr;
    assign axi_wdata  = 32'hDEADBEEF;

    always @(posedge clk) begin
        if (!rstn) begin
            dma_state   <= IDLE;
            axi_awvalid <= 1'b0;
            axi_wvalid  <= 1'b0;
            dma_done    <= 1'b0;
        end else begin
            case (dma_state)
                IDLE: begin
                    dma_done <= 1'b0;
                    if (trigger_dma) begin
                        axi_awvalid <= 1'b1;
                        axi_wvalid  <= 1'b1;
                        dma_state   <= REQ;
                    end
                end
                
                REQ: begin
                    if (axi_awvalid && axi_awready) axi_awvalid <= 1'b0;
                    if (axi_wvalid && axi_wready)   axi_wvalid  <= 1'b0;
                    
                    if (!axi_awvalid && !axi_wvalid) begin
                        dma_state <= WAIT_B;
                    end
                end
                
                WAIT_B: begin
                    if (axi_bvalid && axi_bready) begin
                        dma_done  <= 1'b1;
                        dma_state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule