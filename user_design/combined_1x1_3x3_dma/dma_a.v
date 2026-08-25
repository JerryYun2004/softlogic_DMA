`timescale 1ns / 1ps
`default_nettype none

// CPU-facing AXI4-Lite wrapper for combined_hwc_channel_dma_agu.
//
// AXI4-Lite configures and starts the DMA.  The map_* stream remains identical
// to the previously verified standalone 1x1 and 3x3 wrappers, so the existing
// activation-SRAM/weight-shift adapter can be reused unchanged.
//
// Register map:
//   0x00 W: source-base byte address and start the selected operation
//   0x00 R: last accepted source-base byte address
//   0x04 R: status {29'b0, error_sticky, busy, done_sticky}
//   0x08 W/R configuration:
//          [0]   tile_x       (activation mode)
//          [1]   tile_y       (activation mode)
//          [2]   cin_block    (activation and weight modes)
//          [3]   load_weight  (0: activation, 1: 8x8 weight slice)
//          [4]   cout_block   (weight mode)
//          [6:5] kernel_y     (3x3 weight mode, valid values 0..2)
//          [8:7] kernel_x     (3x3 weight mode, valid values 0..2)
//          [9]   conv_1x1     (0: 3x3 schedule, 1: 1x1 schedule)
//          [31:10] reserved, read as zero
//
// Keeping conv_1x1 at zero preserves the original 3x3 programming model.
// For 1x1 operations kernel_y/kernel_x are ignored.  Software writes 0x08,
// then writes the activation or weight base address to 0x00 to launch.
module dma_a (
    input  wire        clk,
    input  wire        rstn,

    output wire [31:0] O_top,

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

    // One accepted command describes eight activation or weight bytes.
    output wire        map_valid,
    input  wire        map_ready,
    output wire [31:0] map_source_addr,
    output wire [4:0]  map_source_stride,
    output wire [8:0]  map_buffer_addr,
    output wire [7:0]  map_bank_mask,
    output wire        map_is_weight,
    output wire        map_zero_fill,
    output wire        map_last,
    output wire        map_weight_swap
);

    localparam [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam [1:0] AXI_RESP_SLVERR = 2'b10;
    localparam [1:0] AXI_RESP_DECERR = 2'b11;

    reg [31:0] source_base_reg;
    reg [9:0]  config_reg;
    reg        start_pulse;
    reg        done_sticky;
    reg        error_sticky;

    wire       agu_start_ready;
    wire       agu_busy;
    wire       agu_done;

    // AXI4-Lite AW and W are independent channels.  Hold either half until
    // both have arrived, then emit exactly one write response.
    reg        aw_hold_valid;
    reg [9:0]  awaddr_hold;
    reg        w_hold_valid;
    reg [31:0] wdata_hold;
    reg [3:0]  wstrb_hold;

    wire        aw_accept;
    wire        w_accept;
    wire        write_have_aw;
    wire        write_have_w;
    wire        write_commit;
    wire [9:0]  write_addr;
    wire [31:0] write_data;
    wire [3:0]  write_strb;
    wire [31:0] next_source_base;
    wire [9:0]  next_config;
    wire        invalid_weight_config;

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

    assign O_top[0]     = 1'b1;
    assign O_top[1]     = done_sticky;
    assign O_top[2]     = agu_busy;
    assign O_top[3]     = error_sticky;
    assign O_top[4]     = map_valid;
    assign O_top[5]     = map_zero_fill;
    assign O_top[6]     = map_last;
    assign O_top[7]     = map_is_weight;
    assign O_top[8]     = map_weight_swap;
    assign O_top[9]     = config_reg[9];
    assign O_top[31:10] = 22'd0;

    assign axil_awready = !aw_hold_valid && !axil_bvalid;
    assign axil_wready  = !w_hold_valid  && !axil_bvalid;

    assign aw_accept     = axil_awvalid && axil_awready;
    assign w_accept      = axil_wvalid  && axil_wready;
    assign write_have_aw = aw_hold_valid || aw_accept;
    assign write_have_w  = w_hold_valid || w_accept;
    assign write_commit  = write_have_aw && write_have_w && !axil_bvalid;

    assign write_addr = aw_hold_valid ? awaddr_hold : axil_awaddr;
    assign write_data = w_hold_valid  ? wdata_hold  : axil_wdata;
    assign write_strb = w_hold_valid  ? wstrb_hold  : axil_wstrb;

    assign next_source_base = apply_wstrb(
        source_base_reg, write_data, write_strb
    );

    // Only byte lanes zero and one contain implemented configuration bits.
    assign next_config[7:0] = write_strb[0]
                            ? write_data[7:0]
                            : config_reg[7:0];
    assign next_config[9:8] = write_strb[1]
                            ? write_data[9:8]
                            : config_reg[9:8];

    // kernel coordinates apply only to 3x3 weight commands.  In 1x1 mode the
    // fields are deliberately ignored, which also permits old/stale values.
    assign invalid_weight_config = !config_reg[9] && config_reg[3] &&
                                   ((config_reg[6:5] == 2'd3) ||
                                    (config_reg[8:7] == 2'd3));

    always @(posedge clk) begin
        if (!rstn) begin
            source_base_reg <= 32'd0;
            config_reg      <= 10'd0;
            start_pulse     <= 1'b0;
            done_sticky     <= 1'b0;
            error_sticky    <= 1'b0;
            aw_hold_valid   <= 1'b0;
            awaddr_hold     <= 10'd0;
            w_hold_valid    <= 1'b0;
            wdata_hold      <= 32'd0;
            wstrb_hold      <= 4'd0;
            axil_bresp      <= AXI_RESP_OKAY;
            axil_bvalid     <= 1'b0;
        end else begin
            start_pulse <= 1'b0;

            if (agu_done)
                done_sticky <= 1'b1;

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

                case (write_addr)
                    10'h000: begin
                        if (agu_busy || !agu_start_ready || start_pulse ||
                            invalid_weight_config) begin
                            axil_bresp    <= AXI_RESP_SLVERR;
                            error_sticky <= 1'b1;
                        end else begin
                            source_base_reg <= next_source_base;
                            start_pulse     <= 1'b1;
                            done_sticky     <= 1'b0;
                            error_sticky    <= 1'b0;
                            axil_bresp      <= AXI_RESP_OKAY;
                        end
                    end

                    10'h008: begin
                        if (agu_busy || start_pulse) begin
                            axil_bresp    <= AXI_RESP_SLVERR;
                            error_sticky <= 1'b1;
                        end else begin
                            config_reg <= next_config;
                            axil_bresp <= AXI_RESP_OKAY;
                        end
                    end

                    default: begin
                        axil_bresp    <= AXI_RESP_DECERR;
                        error_sticky <= 1'b1;
                    end
                endcase
            end
        end
    end

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
                        axil_rdata <= source_base_reg;
                        axil_rresp <= AXI_RESP_OKAY;
                    end
                    10'h004: begin
                        axil_rdata <= {
                            29'd0, error_sticky, agu_busy, done_sticky
                        };
                        axil_rresp <= AXI_RESP_OKAY;
                    end
                    10'h008: begin
                        axil_rdata <= {22'd0, config_reg};
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

    combined_hwc_channel_dma_agu #(
        .SRC_ADDR_WIDTH(32),
        .ACT_ADDR_WIDTH(9)
    ) agu_i (
        .clk_i                  (clk),
        .rst_n                  (rstn),
        .start_i                (start_pulse),
        .start_ready_o          (agu_start_ready),
        .conv_1x1_i             (config_reg[9]),
        .load_weight_i          (config_reg[3]),
        .image_base_i           (source_base_reg),
        .weight_base_i          (source_base_reg),
        .tile_y_i               (config_reg[1]),
        .tile_x_i               (config_reg[0]),
        .cin_block_i            (config_reg[2]),
        .cout_block_i           (config_reg[4]),
        .kernel_y_i             (config_reg[6:5]),
        .kernel_x_i             (config_reg[8:7]),
        .busy_o                 (agu_busy),
        .done_o                 (agu_done),
        .load_valid_o           (map_valid),
        .load_ready_i           (map_ready),
        .load_src_addr_o        (map_source_addr),
        .load_src_lane_stride_o (map_source_stride),
        .load_dst_addr_o        (map_buffer_addr),
        .load_dst_bank_mask_o   (map_bank_mask),
        .load_is_weight_o       (map_is_weight),
        .load_zero_fill_o       (map_zero_fill),
        .load_last_o            (map_last),
        .weight_swap_o          (map_weight_swap)
    );

endmodule

`default_nettype wire
