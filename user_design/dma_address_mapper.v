`timescale 1ns / 1ps
`default_nettype none

// Protocol-neutral address mapper for a fixed CNN input/weight schedule:
//   * 16x16 INT8 input tile
//   * valid 3x3 convolution, stride 1
//   * 14x14 output positions
//   * 8 physical PE rows / input row buffers
//   * 8 physical PE columns / input column buffers
//   * weight-stationary, no internal input-lane skew
//   * q=0..7 in pass 0, q=8 on physical row 0 in pass 1
//   * 9x8 INT8 weights stored tap-major as W[q][k]
//
// This module does not read an SRAM and does not write an input buffer.  It
// only emits the mapping between an external byte address and one or more
// physical input-buffer destinations:
//
//   {cmd_source_addr, cmd_buffer_addr, cmd_row_mask, cmd_is_weight, cmd_pass}
//
// cmd_is_weight=0: mask bit r selects physical row buffer / PE row r.
// cmd_is_weight=1: mask bit k selects physical column buffer / PE column k;
//                  cmd_buffer_addr is the flattened tap q (0..8).
//
// The port retains the legacy name cmd_row_mask for compatibility, but it is
// a generic physical-buffer mask when cmd_is_weight=1.  The same source pixel
// can produce several consecutive activation commands because destination
// addresses differ between kernel rows.  cmd_source_first/cmd_source_last
// delimit those commands so a later SRAM adapter can read the source once and
// hold the byte.
module dma_address_mapper (
    input  wire        clk,
    input  wire        rstn,

    input  wire        start,
    input  wire        start_weights,
    input  wire [31:0] tile_base_addr,
    input  wire [31:0] image_width_bytes,
    input  wire [31:0] weight_base_addr,

    output reg         busy,
    output reg         done,
    output reg         error,

    output reg         cmd_valid,
    input  wire        cmd_ready,
    output reg  [31:0] cmd_source_addr,
    output reg  [7:0]  cmd_buffer_addr,
    output reg  [7:0]  cmd_row_mask,
    output reg         cmd_is_weight,
    output reg         cmd_pass,
    output reg         cmd_source_first,
    output reg         cmd_source_last,
    output reg         cmd_pass_last,

    // The scheduler pauses after each reduction pass.  The eventual
    // array/buffer controller asserts ready only after that pass is consumed.
    output wire        pass_complete_valid,
    input  wire        pass_complete_ready,
    output wire        pass_complete_id
);

    localparam [2:0] STATE_IDLE       = 3'd0;
    localparam [2:0] STATE_WEIGHTS    = 3'd1;
    localparam [2:0] STATE_PASS0      = 3'd2;
    localparam [2:0] STATE_WAIT_PASS0 = 3'd3;
    localparam [2:0] STATE_PASS1      = 3'd4;
    localparam [2:0] STATE_WAIT_PASS1 = 3'd5;

    reg [2:0] state;

    // Configuration is latched on start so CPU writes cannot change an
    // active schedule.
    reg [31:0] active_tile_base;
    reg [31:0] active_image_width;

    // Weight preload.  External SRAM layout is tap-major:
    //   address(W[q][k]) = weight_base_addr + 8*q + k
    // Each column buffer k stores W[q][k] at address q.
    reg [31:0] weight_source_addr;
    reg [3:0]  weight_q;
    reg [2:0]  weight_col;

    // Pass-0 source scan. p0_linear = 14*tile_row + tile_col.
    reg [3:0]  p0_tile_row;
    reg [3:0]  p0_tile_col;
    reg [7:0]  p0_linear;
    reg [31:0] p0_source_row_base;
    reg [31:0] p0_source_addr;
    reg [1:0]  p0_group_sel;
    reg        p0_source_first_reg;

    // Pass-1 q=8 scan over tile-local [2..15][2..15].
    reg [3:0]  p1_output_row;
    reg [3:0]  p1_output_col;
    reg [7:0]  p1_buffer_index;
    reg [31:0] p1_source_row_base;
    reg [31:0] p1_source_addr;

    reg [2:0] horizontal_mask;
    wire [7:0] p0_group0_mask;
    wire [7:0] p0_group1_mask;
    wire [7:0] p0_group2_mask;
    wire [7:0] p0_group0_addr;
    wire [7:0] p0_group1_addr;
    wire [7:0] p0_group2_addr;
    reg        p0_group_is_last;
    reg [1:0]  p0_next_group;
    wire       p0_last_source_pixel;

    function [1:0] first_group_for_row;
        input [3:0] tile_row;
        begin
            if (tile_row <= 4'd13)
                first_group_for_row = 2'd0;
            else if (tile_row == 4'd14)
                first_group_for_row = 2'd1;
            else
                first_group_for_row = 2'd2;
        end
    endfunction

    // Valid kernel-column mask for a source tile column b.
    always @* begin
        if (p0_tile_col == 4'd0)
            horizontal_mask = 3'b001;
        else if (p0_tile_col == 4'd1)
            horizontal_mask = 3'b011;
        else if (p0_tile_col <= 4'd13)
            horizontal_mask = 3'b111;
        else if (p0_tile_col == 4'd14)
            horizontal_mask = 3'b110;
        else
            horizontal_mask = 3'b100;
    end

    // For one source X[a,b], all valid kx values for the same ky share the
    // destination address 14*a+b-11*ky.  This is why one row mask can replace
    // up to three individual row-buffer writes.
    assign p0_group0_mask = (p0_tile_row <= 4'd13) ?
                            {5'b00000, horizontal_mask} : 8'd0;
    assign p0_group1_mask = ((p0_tile_row >= 4'd1) &&
                             (p0_tile_row <= 4'd14)) ?
                            {2'b00, horizontal_mask, 3'b000} : 8'd0;
    // q=8 is deferred to pass 1, so group 2 contains only q=6 and q=7.
    assign p0_group2_mask = (p0_tile_row >= 4'd2) ?
                            {horizontal_mask[1:0], 6'b000000} : 8'd0;

    assign p0_group0_addr = p0_linear;
    assign p0_group1_addr = p0_linear - 8'd11;
    assign p0_group2_addr = p0_linear - 8'd22;

    assign p0_last_source_pixel = (p0_tile_row == 4'd15) &&
                                  (p0_tile_col == 4'd14);

    // Determine the next nonempty group using only comparisons and muxes.
    always @* begin
        p0_group_is_last = 1'b1;
        p0_next_group    = p0_group_sel;

        case (p0_group_sel)
            2'd0: begin
                if (p0_group1_mask != 8'd0) begin
                    p0_group_is_last = 1'b0;
                    p0_next_group    = 2'd1;
                end else if (p0_group2_mask != 8'd0) begin
                    p0_group_is_last = 1'b0;
                    p0_next_group    = 2'd2;
                end
            end

            2'd1: begin
                if (p0_group2_mask != 8'd0) begin
                    p0_group_is_last = 1'b0;
                    p0_next_group    = 2'd2;
                end
            end

            default: begin
                p0_group_is_last = 1'b1;
            end
        endcase
    end

    // Protocol-neutral mapping command. State/counter registers do not move
    // while cmd_ready is low, so every output remains stable under stall.
    always @* begin
        cmd_valid        = 1'b0;
        cmd_source_addr  = 32'd0;
        cmd_buffer_addr  = 8'd0;
        cmd_row_mask     = 8'd0;
        cmd_is_weight    = 1'b0;
        cmd_pass         = 1'b0;
        cmd_source_first = 1'b0;
        cmd_source_last  = 1'b0;
        cmd_pass_last    = 1'b0;

        case (state)
            STATE_WEIGHTS: begin
                cmd_valid        = 1'b1;
                cmd_source_addr  = weight_source_addr;
                cmd_buffer_addr  = {4'd0, weight_q};
                cmd_row_mask     = 8'b00000001 << weight_col;
                cmd_is_weight    = 1'b1;
                cmd_pass         = (weight_q == 4'd8);
                cmd_source_first = 1'b1;
                cmd_source_last  = 1'b1;
                cmd_pass_last    = (weight_col == 3'd7) &&
                                   ((weight_q == 4'd7) ||
                                    (weight_q == 4'd8));
            end

            STATE_PASS0: begin
                cmd_valid        = 1'b1;
                cmd_source_addr  = p0_source_addr;
                cmd_pass         = 1'b0;
                cmd_source_first = p0_source_first_reg;
                cmd_source_last  = p0_group_is_last;
                cmd_pass_last    = p0_last_source_pixel &&
                                   p0_group_is_last;

                case (p0_group_sel)
                    2'd0: begin
                        cmd_buffer_addr = p0_group0_addr;
                        cmd_row_mask    = p0_group0_mask;
                    end
                    2'd1: begin
                        cmd_buffer_addr = p0_group1_addr;
                        cmd_row_mask    = p0_group1_mask;
                    end
                    default: begin
                        cmd_buffer_addr = p0_group2_addr;
                        cmd_row_mask    = p0_group2_mask;
                    end
                endcase
            end

            STATE_PASS1: begin
                cmd_valid        = 1'b1;
                cmd_source_addr  = p1_source_addr;
                cmd_buffer_addr  = p1_buffer_index;
                cmd_row_mask     = 8'b00000001;
                cmd_pass         = 1'b1;
                cmd_source_first = 1'b1;
                cmd_source_last  = 1'b1;
                cmd_pass_last    = (p1_buffer_index == 8'd195);
            end

            default: begin
                cmd_valid = 1'b0;
            end
        endcase
    end

    assign pass_complete_valid = (state == STATE_WAIT_PASS0) ||
                                 (state == STATE_WAIT_PASS1);
    assign pass_complete_id    = (state == STATE_WAIT_PASS1);

    always @(posedge clk) begin
        if (!rstn) begin
            state                 <= STATE_IDLE;
            active_tile_base      <= 32'd0;
            active_image_width    <= 32'd0;
            weight_source_addr    <= 32'd0;
            weight_q              <= 4'd0;
            weight_col            <= 3'd0;
            busy                  <= 1'b0;
            done                  <= 1'b0;
            error                 <= 1'b0;
            p0_tile_row           <= 4'd0;
            p0_tile_col           <= 4'd0;
            p0_linear             <= 8'd0;
            p0_source_row_base    <= 32'd0;
            p0_source_addr        <= 32'd0;
            p0_group_sel          <= 2'd0;
            p0_source_first_reg   <= 1'b0;
            p1_output_row         <= 4'd0;
            p1_output_col         <= 4'd0;
            p1_buffer_index       <= 8'd0;
            p1_source_row_base    <= 32'd0;
            p1_source_addr        <= 32'd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    busy <= 1'b0;

                    if (start && start_weights) begin
                        done  <= 1'b1;
                        error <= 1'b1;
                    end else if (start_weights) begin
                        done               <= 1'b0;
                        error              <= 1'b0;
                        busy               <= 1'b1;
                        weight_source_addr <= weight_base_addr;
                        weight_q           <= 4'd0;
                        weight_col         <= 3'd0;
                        state              <= STATE_WEIGHTS;
                    end else if (start) begin
                        done  <= 1'b0;
                        error <= 1'b0;

                        if (image_width_bytes < 32'd16) begin
                            done  <= 1'b1;
                            error <= 1'b1;
                        end else begin
                            active_tile_base    <= tile_base_addr;
                            active_image_width  <= image_width_bytes;
                            busy                <= 1'b1;
                            p0_tile_row         <= 4'd0;
                            p0_tile_col         <= 4'd0;
                            p0_linear           <= 8'd0;
                            p0_source_row_base  <= tile_base_addr;
                            p0_source_addr      <= tile_base_addr;
                            p0_group_sel        <= 2'd0;
                            p0_source_first_reg <= 1'b1;
                            state               <= STATE_PASS0;
                        end
                    end
                end

                STATE_WEIGHTS: begin
                    if (cmd_valid && cmd_ready) begin
                        if ((weight_q == 4'd8) &&
                            (weight_col == 3'd7)) begin
                            busy  <= 1'b0;
                            done  <= 1'b1;
                            error <= 1'b0;
                            state <= STATE_IDLE;
                        end else begin
                            weight_source_addr <= weight_source_addr + 32'd1;

                            if (weight_col == 3'd7) begin
                                weight_col <= 3'd0;
                                weight_q   <= weight_q + 4'd1;
                            end else begin
                                weight_col <= weight_col + 3'd1;
                            end
                        end
                    end
                end

                STATE_PASS0: begin
                    if (cmd_valid && cmd_ready) begin
                        if (!p0_group_is_last) begin
                            p0_group_sel        <= p0_next_group;
                            p0_source_first_reg <= 1'b0;
                        end else if (p0_last_source_pixel) begin
                            state <= STATE_WAIT_PASS0;
                        end else begin
                            p0_source_first_reg <= 1'b1;

                            if (p0_tile_col == 4'd15) begin
                                p0_tile_row        <= p0_tile_row + 4'd1;
                                p0_tile_col        <= 4'd0;
                                p0_linear          <= p0_linear - 8'd1;
                                p0_source_row_base <= p0_source_row_base +
                                                      active_image_width;
                                p0_source_addr     <= p0_source_row_base +
                                                      active_image_width;
                                p0_group_sel       <= first_group_for_row(
                                    p0_tile_row + 4'd1
                                );
                            end else begin
                                p0_tile_col   <= p0_tile_col + 4'd1;
                                p0_linear     <= p0_linear + 8'd1;
                                p0_source_addr <= p0_source_addr + 32'd1;
                                p0_group_sel  <= first_group_for_row(
                                    p0_tile_row
                                );
                            end
                        end
                    end
                end

                STATE_WAIT_PASS0: begin
                    if (pass_complete_valid && pass_complete_ready) begin
                        p1_output_row       <= 4'd0;
                        p1_output_col       <= 4'd0;
                        p1_buffer_index     <= 8'd0;
                        p1_source_row_base  <= active_tile_base +
                                               (active_image_width << 1) +
                                               32'd2;
                        p1_source_addr      <= active_tile_base +
                                               (active_image_width << 1) +
                                               32'd2;
                        state               <= STATE_PASS1;
                    end
                end

                STATE_PASS1: begin
                    if (cmd_valid && cmd_ready) begin
                        if (p1_buffer_index == 8'd195) begin
                            state <= STATE_WAIT_PASS1;
                        end else begin
                            p1_buffer_index <= p1_buffer_index + 8'd1;

                            if (p1_output_col == 4'd13) begin
                                p1_output_row      <= p1_output_row + 4'd1;
                                p1_output_col      <= 4'd0;
                                p1_source_row_base <= p1_source_row_base +
                                                      active_image_width;
                                p1_source_addr     <= p1_source_row_base +
                                                      active_image_width;
                            end else begin
                                p1_output_col  <= p1_output_col + 4'd1;
                                p1_source_addr <= p1_source_addr + 32'd1;
                            end
                        end
                    end
                end

                STATE_WAIT_PASS1: begin
                    if (pass_complete_valid && pass_complete_ready) begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        error <= 1'b0;
                        state <= STATE_IDLE;
                    end
                end

                default: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    error <= 1'b1;
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
