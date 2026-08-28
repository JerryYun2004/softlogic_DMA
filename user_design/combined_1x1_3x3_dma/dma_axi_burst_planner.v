`timescale 1ns / 1ps
`default_nettype none

// AXI4 read-burst length planner.
//
// This block is deliberately combinational: it examines the address of the
// next unread 32-bit word and the number of words still required by the
// descriptor, then returns the largest legal burst that can be issued without
// crossing a 4-KiB address boundary.
//
// AXI4 rule enforced here:
//
//   next_burst_beats = min(row_beats_remaining,
//                          (4096 - read_addr[11:0]) / 4)
//   ARLEN            = next_burst_beats - 1
//
// The fetch engine owns all state. If a row reaches a 4-KiB boundary before it
// is complete, the engine consumes this burst, updates its address/counters,
// and calls this planner again for the remaining words. This module does not
// issue AXI requests, advance an address, or store any descriptor state.
module dma_axi_burst_planner (
    // Byte address of the next 32-bit word to read. The DMA supplies a
    // word-aligned address, so the division by four below is exact.
    input  wire [31:0] read_addr_i,

    // Total 32-bit words still unread in the current row or weight slice.
    input  wire [6:0]  row_beats_remaining_i,

    // Number of words in the next request and its AXI-encoded counterpart.
    output wire [10:0] next_burst_beats_o,
    output wire [7:0]  arlen_o
);

    wire [12:0] bytes_to_4k;
    wire [10:0] beats_to_4k;
    wire [10:0] row_beats_wide;
    wire        row_finishes_before_4k;

    // The low twelve address bits are the byte position within the current
    // 4-KiB page. A page-aligned address therefore has 4096 bytes available,
    // rather than zero bytes, before the next boundary.
    assign bytes_to_4k    = 13'd4096 - {1'b0, read_addr_i[11:0]};

    // Each AXI beat is four bytes (ARSIZE=2 in dma_fetch_engine).
    assign beats_to_4k    = bytes_to_4k[12:2];
    assign row_beats_wide = {4'd0, row_beats_remaining_i};

    // When the two quantities are equal either selection is equivalent. The
    // strict comparison lets the boundary-limited value win in that case.
    assign row_finishes_before_4k = row_beats_wide < beats_to_4k;
    assign next_burst_beats_o = row_finishes_before_4k
                                ? row_beats_wide : beats_to_4k;

    // AXI encodes a burst of N transfers as ARLEN=N-1. Descriptors generated
    // by the AGU always contain at least one group, so this input is nonzero
    // whenever the fetch engine enters its address-request state.
    assign arlen_o = next_burst_beats_o[7:0] - 8'd1;

endmodule

`default_nettype wire
