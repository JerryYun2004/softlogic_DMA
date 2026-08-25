`timescale 1ns / 1ps
`default_nettype none

// AXI4-Lite configuration wrapper for gemm_tile_dma_agu.
//
// AXI4-Lite carries only CPU configuration/status.  The map_* ready/valid
// stream is the protocol-neutral connection to the future source-memory/NPU
// adapter.  One accepted map command represents eight byte transfers.
//
// Register map:
//   0x00 W: source tile byte address and start the configured operation
//   0x00 R: last accepted source tile byte address
//   0x04 R: status {29'b0, error_sticky, busy, done_sticky}
//   0x08 W/R configuration
//          [0]   load_weight (0: A activation panel, 1: B 8x8 tile)
//          [8:1] activation_last_addr (panel row count minus one)
//   0x0c W/R source row stride in bytes
//
// Program 0x08 and 0x0c first, then write 0x00.  For A, source_base points to
// A[m0][k0] and stride is the A leading dimension in bytes.  For B, source_base
// points to B[k0][n0] and stride is the B leading dimension in bytes.
module gemm_dma_axi_wrapper (
    input  logic        clk,
    input  logic        rstn,

    output logic [31:0] O_top,

    input  logic [9:0]  axil_awaddr,
    input  logic        axil_awvalid,
    output logic        axil_awready,

    input  logic [31:0] axil_wdata,
    input  logic [3:0]  axil_wstrb,
    input  logic        axil_wvalid,
    output logic        axil_wready,

    output logic [1:0]  axil_bresp,
    output logic        axil_bvalid,
    input  logic        axil_bready,

    input  logic [9:0]  axil_araddr,
    input  logic        axil_arvalid,
    output logic        axil_arready,

    output logic [31:0] axil_rdata,
    output logic [1:0]  axil_rresp,
    output logic        axil_rvalid,
    input  logic        axil_rready,

    output logic        map_valid,
    input  logic        map_ready,
    output logic [31:0] map_source_addr,
    output logic [31:0] map_source_stride,
    output logic [8:0]  map_buffer_addr,
    output logic [7:0]  map_bank_mask,
    output logic        map_is_weight,
    output logic        map_zero_fill,
    output logic        map_last,
    output logic        map_weight_swap
);

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;
    localparam logic [1:0] AXI_RESP_DECERR = 2'b11;

    logic [31:0] source_base_reg;
    logic [31:0] source_stride_reg;
    logic [8:0]  config_reg;
    logic        start_pulse;
    logic        done_sticky;
    logic        error_sticky;

    logic        agu_start_ready;
    logic        agu_busy;
    logic        agu_done;

    logic        aw_hold_valid;
    logic [9:0]  awaddr_hold;
    logic        w_hold_valid;
    logic [31:0] wdata_hold;
    logic [3:0]  wstrb_hold;

    logic        aw_accept;
    logic        w_accept;
    logic        write_have_aw;
    logic        write_have_w;
    logic        write_commit;
    logic [9:0]  write_addr;
    logic [31:0] write_data;
    logic [3:0]  write_strb;
    logic [31:0] next_source_base;
    logic [31:0] next_source_stride;
    logic [8:0]  next_config;
    logic        invalid_start_config;

    function automatic logic [31:0] apply_wstrb(
        input logic [31:0] old_value,
        input logic [31:0] new_value,
        input logic [3:0]  strb
    );
        begin
            apply_wstrb = old_value;
            if (strb[0]) apply_wstrb[7:0]   = new_value[7:0];
            if (strb[1]) apply_wstrb[15:8]  = new_value[15:8];
            if (strb[2]) apply_wstrb[23:16] = new_value[23:16];
            if (strb[3]) apply_wstrb[31:24] = new_value[31:24];
        end
    endfunction

    assign O_top[0]    = 1'b1;
    assign O_top[1]    = done_sticky;
    assign O_top[2]    = agu_busy;
    assign O_top[3]    = error_sticky;
    assign O_top[4]    = map_valid;
    assign O_top[5]    = map_zero_fill;
    assign O_top[6]    = map_last;
    assign O_top[7]    = map_is_weight;
    assign O_top[8]    = map_weight_swap;
    assign O_top[31:9] = 23'd0;

    // AXI-Lite write address and write data are legal in either order, so each
    // channel has a one-entry holding register.
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

    assign next_source_base   = apply_wstrb(source_base_reg,
                                             write_data, write_strb);
    assign next_source_stride = apply_wstrb(source_stride_reg,
                                             write_data, write_strb);

    // Only nine configuration bits are implemented.
    assign next_config[7:0] = write_strb[0] ? write_data[7:0]
                                               : config_reg[7:0];
    assign next_config[8]   = write_strb[1] ? write_data[8]
                                               : config_reg[8];

    // A zero row stride would repeatedly fetch the same matrix row and almost
    // always indicates a software programming error.
    assign invalid_start_config = (source_stride_reg == 32'd0);

    always_ff @(posedge clk) begin
        if (!rstn) begin
            source_base_reg   <= 32'd0;
            source_stride_reg <= 32'd0;
            config_reg        <= 9'd0;
            start_pulse       <= 1'b0;
            done_sticky       <= 1'b0;
            error_sticky      <= 1'b0;
            aw_hold_valid     <= 1'b0;
            awaddr_hold       <= 10'd0;
            w_hold_valid      <= 1'b0;
            wdata_hold        <= 32'd0;
            wstrb_hold        <= 4'd0;
            axil_bresp        <= AXI_RESP_OKAY;
            axil_bvalid       <= 1'b0;
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
                            invalid_start_config) begin
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

                    10'h00c: begin
                        if (agu_busy || start_pulse) begin
                            axil_bresp    <= AXI_RESP_SLVERR;
                            error_sticky <= 1'b1;
                        end else begin
                            source_stride_reg <= next_source_stride;
                            axil_bresp        <= AXI_RESP_OKAY;
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

    always_ff @(posedge clk) begin
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
                        axil_rdata <= {23'd0, config_reg};
                        axil_rresp <= AXI_RESP_OKAY;
                    end

                    10'h00c: begin
                        axil_rdata <= source_stride_reg;
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

    gemm_tile_dma_agu #(
        .SRC_ADDR_WIDTH(32),
        .ACT_ADDR_WIDTH(9)
    ) agu_i (
        .clk_i                    (clk),
        .rst_n                    (rstn),
        .start_i                  (start_pulse),
        .start_ready_o            (agu_start_ready),
        .load_weight_i            (config_reg[0]),
        .source_base_i            (source_base_reg),
        .source_row_stride_i      (source_stride_reg),
        .activation_last_addr_i   ({1'b0, config_reg[8:1]}),
        .busy_o                   (agu_busy),
        .done_o                   (agu_done),
        .load_valid_o             (map_valid),
        .load_ready_i             (map_ready),
        .load_src_addr_o          (map_source_addr),
        .load_src_lane_stride_o   (map_source_stride),
        .load_dst_addr_o          (map_buffer_addr),
        .load_dst_bank_mask_o     (map_bank_mask),
        .load_is_weight_o         (map_is_weight),
        .load_zero_fill_o         (map_zero_fill),
        .load_last_o              (map_last),
        .weight_swap_o            (map_weight_swap)
    );

endmodule

`default_nettype wire
