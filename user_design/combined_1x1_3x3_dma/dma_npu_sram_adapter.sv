`timescale 1ns / 1ps
`default_nettype none

// Synthesizable bridge from dma_a's eight-byte map stream to the ports exposed
// by npu_sram_wrapper.
//
// The activation SRAMs are single-address-port memories: the same address port
// is used for DMA writes and systolic-array reads.  dma_act_port_grant_i gives
// the DMA ownership of those ports.  When the grant is absent, every SRAM bank
// receives its normal compute address and all DMA write enables are forced low.
//
// Weight loading uses a separate eight-lane shift interface.  Its grant is kept
// separate so a weight map cannot be acknowledged by an activation-only grant
// (or vice versa).  array_active_i is a hardware safety interlock: no DMA map is
// accepted, no SRAM is written, and no weight is shifted while the array runs.
module dma_npu_sram_adapter #(
    parameter integer NUM_ACT_BANKS   = 8,
    parameter integer ACT_ADDR_WIDTH  = 9,
    parameter integer ACTIVATION_WIDTH = 8,
    parameter integer WEIGHT_WIDTH     = 8
)(
    // Ownership requests from the accelerator controller/arbiter.
    input  wire dma_act_port_grant_i,
    input  wire dma_weight_port_grant_i,
    input  wire array_active_i,

    // Stream produced by dma_a.
    input  wire                         map_valid_i,
    output wire                         map_ready_o,
    input  wire [63:0]                  map_data_i,
    input  wire [ACT_ADDR_WIDTH-1:0]    map_buffer_addr_i,
    input  wire [NUM_ACT_BANKS-1:0]     map_bank_mask_i,
    input  wire                         map_is_weight_i,
    input  wire                         map_weight_swap_i,

    // Systolic-array activation read addresses.
    input  wire [NUM_ACT_BANKS-1:0][ACT_ADDR_WIDTH-1:0]
                                            act_compute_addr_i,

    // Direct connection to npu_sram_wrapper activation ports.
    output logic [NUM_ACT_BANKS-1:0]         ext_act_sram_we_o,
    output logic [NUM_ACT_BANKS-1:0][ACT_ADDR_WIDTH-1:0]
                                            ext_act_sram_addr_o,
    output logic [NUM_ACT_BANKS-1:0][ACTIVATION_WIDTH-1:0]
                                            ext_act_sram_wdata_o,

    // Direct connection to npu_sram_wrapper weight-loading ports.
    output logic [NUM_ACT_BANKS-1:0][WEIGHT_WIDTH-1:0]
                                            weight_shift_in_o,
    output logic                             weight_shift_en_o,
    output logic                             swap_weights_o
);

    wire act_port_owned;
    wire weight_port_owned;
    wire map_fire;

    // A controller grant is effective only while the array is not computing.
    // This prevents an incorrect control overlap from stealing the activation
    // SRAM address ports or shifting weights into a running array.
    assign act_port_owned    = dma_act_port_grant_i    && !array_active_i;
    assign weight_port_owned = dma_weight_port_grant_i && !array_active_i;
    assign map_ready_o       = map_is_weight_i ? weight_port_owned
                                               : act_port_owned;
    assign map_fire          = map_valid_i && map_ready_o;

    integer bank;
    always_comb begin
        // Compute owns the activation addresses by default.
        ext_act_sram_we_o    = '0;
        ext_act_sram_addr_o  = act_compute_addr_i;
        ext_act_sram_wdata_o = '0;

        weight_shift_in_o = '0;
        weight_shift_en_o = 1'b0;
        swap_weights_o    = weight_port_owned && map_weight_swap_i;

        if (act_port_owned) begin
            for (bank = 0; bank < NUM_ACT_BANKS; bank = bank + 1)
                ext_act_sram_addr_o[bank] = map_buffer_addr_i;
        end

        if (map_fire && map_is_weight_i) begin
            weight_shift_en_o = 1'b1;
            for (bank = 0; bank < NUM_ACT_BANKS; bank = bank + 1) begin
                if (map_bank_mask_i[bank])
                    weight_shift_in_o[bank] =
                        map_data_i[bank*WEIGHT_WIDTH +: WEIGHT_WIDTH];
            end
        end else if (map_fire) begin
            for (bank = 0; bank < NUM_ACT_BANKS; bank = bank + 1) begin
                if (map_bank_mask_i[bank]) begin
                    ext_act_sram_we_o[bank] = 1'b1;
                    ext_act_sram_wdata_o[bank] =
                        map_data_i[bank*ACTIVATION_WIDTH +:
                                   ACTIVATION_WIDTH];
                end
            end
        end
    end

endmodule

`default_nettype wire
