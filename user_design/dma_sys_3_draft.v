// AXI4 interface receive external RAM address for the start of the load


// Based on the address for the start of the load, calculate the address 
// for each input's source location in the external RAM (for both pixels
// and weights), also calculate the corresponding destinations in the input
// buffers.




// Algorithm


// 8x8 systolic array
// no internal cycle skewing
// weight stationary
// 8 row input buffers
// 8 column input buffers
// 256 byte each input buffer, addressable, not FIFO
// 3x3 convolution window flattened to 1x9
// large input image tiled down to 16x16
// assume input image stored in 2D array


// 16x16 with 3x3 window
// O_w = O_h = 16 - 3 + 1 = 14
// Matrix size M = 14x14 = 196
// Minimum buffer size = M + (number_of_rows - 1) = 196 + 7 = 203


// SRAM Address (external) for a tile-local pixel (y, x)
// tile_base_address -> address of the image's top-left pixel
// src_pitch_bytes -> P -> full image row pitch in bytes
    // How wide the image is? (Can be a fixed number)
// assume each pixel is 1 byte
// SRAM Address = tile_base_address + y * P + x


// Let q be the flattened convolution window
    // q [0, 1, 2, 3, 4, 5, 6, 7, 8]
    // written in k_x, k_y form -> C[k_x, k_y]
    // q = 3 * k_y + k_x

// o_y -> row in 14x14 output tile 0 <= o_y < 14
// o_x -> column in 14x14 output tile 0 <= o_x < 14

// Input Pixel = X[o_y + k_y][o_x + k_x]
// source_address = tile_base_address + (o_y + k_y) * src_pitch_bytes + (o_x + k_x)

// Output index m = 14 * o_y + o_x
// 


// Mechanism
// Read:
    // external SRAM[tile_base + input_col*pitch + input_row]

// Write:
    // row_buffer[physical_PE_row][output_index + physical_PE_row]


kernel_index = q;
kernel_row   = q / 3;
kernel_col   = q % 3;

output_index = output_row * 14 + output_col;

input_row = output_row + kernel_row;
input_col = output_col + kernel_col;

source_address =
    tile_base_addr
    + input_row * src_pitch_bytes
    + input_col;

destination_buffer = physical_pe_row;
destination_address =
    output_index + physical_pe_row;



Inputs:
    tile_base       SRAM byte address of tile-local X[0,0]
    image_width     width of the complete image in pixels

Constants:
    OUTPUT_WIDTH  = 14
    OUTPUT_HEIGHT = 14
    NUM_PE_ROWS   = 8
    NUM_TAPS      = 9

Output command:
    DMA_TRANSFER(src_addr, physical_PE_row, buffer_index)


for pass = 0 to 1:

    for physical_PE_row = 0 to 7:

        q = pass*8 + physical_PE_row

        if q >= 9:
            continue

        kernel_row = q / 3
        kernel_col = q % 3

        source_row_base =
            tile_base
            + kernel_row*image_width
            + kernel_col

        buffer_index = physical_PE_row

        for output_row = 0 to 13:

            source_address = source_row_base

            for output_col = 0 to 13:

                DMA_TRANSFER(
                    source_address,
                    physical_PE_row,
                    buffer_index
                )

                source_address = source_address + 1
                buffer_index   = buffer_index + 1

            source_row_base = source_row_base + image_width

module dma_sys_3 (
    input   wire        clk;
    input   wire        rstn,

//    output  wire 


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


    // AXI4 reach channels

);

