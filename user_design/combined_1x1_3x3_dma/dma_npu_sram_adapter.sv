`timescale 1ns / 1ps
`default_nettype none

// Bridge between dma_a's 32-bit map stream and npu_sram_wrapper.
//
// Activation data arrives as two ordered beats for each eight-channel group:
//
//   map_bank_mask=8'h0f -> map_data bytes 0..3 write banks 0..3
//   map_bank_mask=8'hf0 -> map_data bytes 0..3 write banks 4..7
//
// Both beats use the same activation SRAM address. The bank mask makes each
// 32-bit word update only its corresponding four byte-wide SRAM banks.
//
// The weight loader consumes all eight lanes simultaneously. For weight data,
// this adapter stores the low 32-bit beat, combines it with the following high
// beat, and enables one eight-lane shift only when that high beat is accepted.
// The low-half register is the only data-width conversion storage here.
//
// Activation SRAMs have one shared address per bank: compute reads and DMA
// writes cannot use it simultaneously. dma_act_port_grant_i selects the DMA
// address; otherwise each bank receives its compute address. array_active_i is
// a safety interlock that cancels either DMA grant while the array is running.
// The resulting map_ready_o backpressures the complete fetch path and AXI R
// channel, so data is never dropped when ownership is unavailable.
//
// This module does not access DRAM, generate DMA addresses, or read/write PSUM
// banks. It only adapts accepted map beats to activation and weight-load ports.
module dma_npu_sram_adapter #(
    parameter integer NUM_ACT_BANKS    = 8,
    parameter integer ACT_ADDR_WIDTH   = 9,
    parameter integer ACTIVATION_WIDTH = 8,
    parameter integer WEIGHT_WIDTH     = 8
)(
    input  wire clk_i,
    input  wire rst_n,

    // Ownership decisions from the accelerator controller/arbiter. Software
    // or the controller must retain the relevant grant for the DMA operation.
    input  wire dma_act_port_grant_i,
    input  wire dma_weight_port_grant_i,
    input  wire array_active_i,

    // Stream produced by dma_a.
    input  wire                         map_valid_i,
    output wire                         map_ready_o,
    input  wire [31:0]                  map_data_i,
    input  wire [ACT_ADDR_WIDTH-1:0]    map_buffer_addr_i,
    input  wire [NUM_ACT_BANKS-1:0]     map_bank_mask_i,
    input  wire                         map_is_weight_i,
    input  wire                         map_weight_swap_i,

    // Systolic-array activation read addresses used whenever DMA ownership is
    // not effective.
    input  wire [NUM_ACT_BANKS-1:0][ACT_ADDR_WIDTH-1:0]
                                            act_compute_addr_i,

    // Direct connection to npu_sram_wrapper activation ports.
    output wire [NUM_ACT_BANKS-1:0]         ext_act_sram_we_o,
    output wire [NUM_ACT_BANKS-1:0][ACT_ADDR_WIDTH-1:0]
                                            ext_act_sram_addr_o,
    output wire [NUM_ACT_BANKS-1:0][ACTIVATION_WIDTH-1:0]
                                            ext_act_sram_wdata_o,

    // Direct connection to npu_sram_wrapper weight-loading ports.
    output wire [NUM_ACT_BANKS-1:0][WEIGHT_WIDTH-1:0]
                                            weight_shift_in_o,
    output wire                             weight_shift_en_o,
    output wire                             swap_weights_o
);

    // Qualified ownership and ready/valid handshake events.
    wire act_port_owned;
    wire weight_port_owned;
    wire map_fire;
    wire activation_fire;
    wire weight_fire;
    wire high_half;
    wire low_half;

    // Holds channels 0..3 until channels 4..7 arrive on the next accepted beat.
    reg [31:0] weight_low_half_q;

    // A controller grant is effective only while the array is not computing.
    // map_ready_o selects the required resource from the beat's type, so an
    // activation grant cannot accidentally accept a weight beat or vice versa.
    assign act_port_owned    = dma_act_port_grant_i    && !array_active_i;
    assign weight_port_owned = dma_weight_port_grant_i && !array_active_i;
    assign map_ready_o       = map_is_weight_i
                               ? weight_port_owned : act_port_owned;
    assign map_fire          = map_valid_i && map_ready_o;
    assign activation_fire   = map_fire && !map_is_weight_i;
    assign weight_fire       = map_fire && map_is_weight_i;
    // The fetch datapath normally produces exactly 8'h0f or 8'hf0. Reduction
    // OR keeps the phase test valid even if a descriptor masks individual banks.
    assign low_half          = |map_bank_mask_i[3:0];
    assign high_half         = |map_bank_mask_i[7:4];

    // Each SRAM bank receives the compute address when the array/controller
    // owns the port, or the common DMA destination address when DMA owns it.
    // Write enables remain low unless an activation beat is actually accepted.
    genvar bank_index;
    generate
        for (bank_index = 0; bank_index < NUM_ACT_BANKS;
             bank_index = bank_index + 1) begin : gen_act_addr_mux
            assign ext_act_sram_addr_o[bank_index] = act_port_owned
                ? map_buffer_addr_i : act_compute_addr_i[bank_index];

            assign ext_act_sram_we_o[bank_index] =
                activation_fire && map_bank_mask_i[bank_index];

            // The same four byte lanes are reused on both beats. The bank index
            // determines whether byte n feeds bank n or bank n+4.
            if (bank_index < 4) begin : gen_low_lane_data
                assign ext_act_sram_wdata_o[bank_index] =
                    map_data_i[bank_index*ACTIVATION_WIDTH +:
                               ACTIVATION_WIDTH];
            end else begin : gen_high_lane_data
                assign ext_act_sram_wdata_o[bank_index] =
                    map_data_i[(bank_index-4)*ACTIVATION_WIDTH +:
                               ACTIVATION_WIDTH];
            end
        end
    endgenerate

    // Capture only the first half of a weight group. Ready/valid backpressure
    // keeps the high half ordered after it, even if ownership is temporarily
    // withdrawn between transfers. The register therefore never needs a FIFO.
    always @(posedge clk_i) begin
        if (!rst_n)
            weight_low_half_q <= 32'd0;
        else if (weight_fire && low_half)
            weight_low_half_q <= map_data_i;
    end

    // Form the eight parallel weight lanes. Low lanes come from the stored
    // first beat; high lanes come directly from the current second beat.
    genvar weight_bank_index;
    generate
        for (weight_bank_index = 0; weight_bank_index < NUM_ACT_BANKS;
             weight_bank_index = weight_bank_index + 1) begin : gen_weight_lanes
            if (weight_bank_index < 4) begin : gen_weight_low_lane
                assign weight_shift_in_o[weight_bank_index] =
                    weight_low_half_q[weight_bank_index*WEIGHT_WIDTH +:
                                      WEIGHT_WIDTH];
            end else begin : gen_weight_high_lane
                assign weight_shift_in_o[weight_bank_index] =
                    map_data_i[(weight_bank_index-4)*WEIGHT_WIDTH +:
                               WEIGHT_WIDTH];
            end
        end
    endgenerate

    // Shift exactly once per complete eight-byte group. The swap indication is
    // a separate post-descriptor pulse and is allowed through only while the
    // controller still grants the weight port.
    assign weight_shift_en_o = weight_fire && high_half;
    assign swap_weights_o    = weight_port_owned && map_weight_swap_i;

endmodule

`default_nettype wire
