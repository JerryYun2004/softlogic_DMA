`timescale 1ns / 1ps
`default_nettype none

// Synthesizable bridge from dma_a's direct 32-bit map stream to the ports
// exposed by npu_sram_wrapper.
//
// Activations are steered without widening:
//
//   map_bank_mask=8'h0f -> map_data bytes 0..3 write banks 0..3
//   map_bank_mask=8'hf0 -> map_data bytes 0..3 write banks 4..7
//
// The two beats use the same activation SRAM address. Address ownership is
// expressed as ordinary RTL; the FABulous packer may only use a cascade-mux
// BEL when all of that BEL's data inputs are driven by clustered LUT outputs.
//
// The NPU's existing weight loader shifts eight lanes simultaneously. For
// weights only, this adapter retains the low 32-bit beat and combines it with
// the following high beat. This is the only widening register in the path.
//
// The activation SRAMs are single-address-port memories: the same address port
// is used for DMA writes and systolic-array reads. dma_act_port_grant_i gives
// the DMA ownership of those ports. When the grant is absent, every SRAM bank
// receives its normal compute address and all DMA write enables are forced low.
// array_active_i is a safety interlock: no map is accepted, no SRAM is written,
// and no weight is shifted while the array runs.
module dma_npu_sram_adapter #(
    parameter integer NUM_ACT_BANKS    = 8,
    parameter integer ACT_ADDR_WIDTH   = 9,
    parameter integer ACTIVATION_WIDTH = 8,
    parameter integer WEIGHT_WIDTH     = 8
)(
    input  wire clk_i,
    input  wire rst_n,

    // Ownership requests from the accelerator controller/arbiter.
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

    // Systolic-array activation read addresses.
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

    wire act_port_owned;
    wire weight_port_owned;
    wire map_fire;
    wire activation_fire;
    wire weight_fire;
    wire high_half;
    wire low_half;

    reg [31:0] weight_low_half_q;

    // A controller grant is effective only while the array is not computing.
    assign act_port_owned    = dma_act_port_grant_i    && !array_active_i;
    assign weight_port_owned = dma_weight_port_grant_i && !array_active_i;
    assign map_ready_o       = map_is_weight_i
                               ? weight_port_owned : act_port_owned;
    assign map_fire          = map_valid_i && map_ready_o;
    assign activation_fire   = map_fire && !map_is_weight_i;
    assign weight_fire       = map_fire && map_is_weight_i;
    assign low_half          = |map_bank_mask_i[3:0];
    assign high_half         = |map_bank_mask_i[7:4];

    // Compute address when the DMA does not own the activation ports; DMA
    // destination when it does.
    genvar bank_index;
    generate
        for (bank_index = 0; bank_index < NUM_ACT_BANKS;
             bank_index = bank_index + 1) begin : gen_act_addr_mux
            assign ext_act_sram_addr_o[bank_index] = act_port_owned
                ? map_buffer_addr_i : act_compute_addr_i[bank_index];

            assign ext_act_sram_we_o[bank_index] =
                activation_fire && map_bank_mask_i[bank_index];

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

    // Capture only the first half of a weight group. AXI/map backpressure
    // keeps the high half ordered immediately after it, even if ownership is
    // temporarily withdrawn between the two transfers.
    always @(posedge clk_i) begin
        if (!rst_n)
            weight_low_half_q <= 32'd0;
        else if (weight_fire && low_half)
            weight_low_half_q <= map_data_i;
    end

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

    assign weight_shift_en_o = weight_fire && high_half;
    assign swap_weights_o    = weight_port_owned && map_weight_swap_i;

endmodule

`default_nettype wire
