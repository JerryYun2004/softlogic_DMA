`timescale 1ns / 1ps
`default_nettype none

// CPU-facing AXI4-Lite programming and status block for dma_a.
//
// Register map (exact 10-bit byte addresses):
//
//   0x000 write  Merge WSTRB-selected bytes into the source pointer and start
//                the operation described by the current configuration.
//   0x000 read   Return the most recently accepted source pointer.
//   0x004 read   Return {29'd0, error_sticky, busy, done_sticky}.
//   0x008 write  Merge configuration bits [9:0] using WSTRB[1:0].
//   0x008 read   Return the configuration in bits [9:0].
//
// Any other exact address receives DECERR. A valid pointer/start write can
// receive SLVERR when the engine is busy, the AGU is not ready, the current
// configuration is illegal, or the supplied packed-object pointer is
// misaligned. Configuration writes are rejected with SLVERR while an operation
// is active.
//
// AXI-Lite AW and W are independent channels and may arrive in either order.
// This block holds one unmatched address or data item, commits only after both
// halves are present, and allows one outstanding B response. The read side also
// allows one outstanding R response and holds it stable until RREADY.
//
// This module does not generate row addresses or AXI4 memory reads. Its output
// to the datapath is the accepted configuration plus a one-cycle start pulse.
module dma_axil_control (
    input  wire        clk,
    input  wire        rstn,

    // CPU-facing AXI4-Lite slave write-address, write-data, write-response,
    // read-address, and read-data channels.
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
    output wire [1:0]  axil_rresp,
    output reg         axil_rvalid,
    input  wire        axil_rready,

    // DMA execution status used for admission control and sticky reporting.
    input  wire        start_ready_i,
    input  wire        busy_i,
    input  wire        done_pulse_i,
    input  wire        read_error_pulse_i,

    // Accepted programming state presented to the AGU. start_pulse_o is high
    // for one clock after a legal 0x000 write commits.
    output reg  [31:0] source_base_o,
    output reg  [9:0]  config_o,
    output reg         start_pulse_o,
    output reg         done_sticky_o,
    output reg         error_sticky_o
);

    // AXI response encodings used by this slave. SLVERR means a recognized
    // operation failed validation; DECERR means the address is unsupported.
    localparam [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam [1:0] AXI_RESP_SLVERR = 2'b10;
    localparam [1:0] AXI_RESP_DECERR = 2'b11;

    // Store a decoded write operation rather than the full AW address while
    // waiting for W. This keeps the holding register small.
    localparam [1:0] WRITE_POINTER = 2'd0;
    localparam [1:0] WRITE_CONFIG  = 2'd1;
    localparam [1:0] WRITE_INVALID = 2'd2;

    // AXI4-Lite AW and W are independent channels, so each can be held until
    // the other half of the write arrives. Only one write transaction may be
    // assembled or awaiting a B-channel response at a time.
    reg        aw_hold_valid;
    reg [1:0]  awsel_hold;
    reg        w_hold_valid;
    reg [31:0] wdata_hold;
    reg [3:0]  wstrb_hold;

    // A read response needs only one stored error bit because this slave
    // returns either OKAY (2'b00) or DECERR (2'b11).
    reg        read_error_q;

    wire        aw_accept;
    wire        w_accept;
    wire        write_have_aw;
    wire        write_have_w;
    wire        write_commit;
    wire [1:0]  write_select;
    wire [31:0] write_data;
    wire [3:0]  write_strb;
    wire [31:0] next_source_base;
    wire [9:0]  next_config;
    wire        invalid_weight_config;
    wire        invalid_activation_alignment;
    wire        invalid_weight_alignment;
    wire        invalid_source_alignment;

    wire [31:0] status_word;
    wire [31:0] config_word;
    wire [31:0] read_mux_data;
    wire [31:0] read_data;
    wire        read_addr_valid;

    // Exact decode intentionally rejects aliases that happen to share low
    // address bits with a valid register.
    function [1:0] decode_write_address;
        input [9:0] address;
        begin
            case (address)
                10'h000: decode_write_address = WRITE_POINTER;
                10'h008: decode_write_address = WRITE_CONFIG;
                default: decode_write_address = WRITE_INVALID;
            endcase
        end
    endfunction
    // Select held values when one channel arrived earlier; otherwise use the
    // channel being accepted in the current cycle. This also supports AW and W
    // arriving together with no extra assembly cycle.
    assign write_select = aw_hold_valid
                          ? awsel_hold
                          : decode_write_address(axil_awaddr);
    assign write_data = w_hold_valid  ? wdata_hold  : axil_wdata;
    assign write_strb = w_hold_valid  ? wstrb_hold  : axil_wstrb;

    // AXI byte strobes update the pointer one byte at a time. Unstrobed bytes
    // retain the last accepted pointer value.
    genvar byte_index;
    generate
        for (byte_index = 0; byte_index < 4;
             byte_index = byte_index + 1) begin : gen_source_wstrb_mux
            assign next_source_base[byte_index*8 +: 8] =
                write_strb[byte_index]
                    ? write_data[byte_index*8 +: 8]
                    : source_base_o[byte_index*8 +: 8];
        end
    endgenerate

    // Only ten configuration bits exist: byte lane zero controls [7:0], and
    // byte lane one controls [9:8]. WSTRB[3:2] have no configuration bits.
    assign next_config[7:0] = write_strb[0]
                              ? write_data[7:0] : config_o[7:0];
    assign next_config[9:8] = write_strb[1]
                              ? write_data[9:8] : config_o[9:8];

    // Channel assembly handshake. READY is suppressed once that half is held
    // and while the previous write response is waiting for BREADY.
    assign axil_awready = !aw_hold_valid && !axil_bvalid;
    assign axil_wready  = !w_hold_valid  && !axil_bvalid;
    assign aw_accept     = axil_awvalid && axil_awready;
    assign w_accept      = axil_wvalid  && axil_wready;
    assign write_have_aw = aw_hold_valid || aw_accept;
    assign write_have_w  = w_hold_valid || w_accept;
    assign write_commit  = write_have_aw && write_have_w && !axil_bvalid;

    // In 3x3 weight mode each kernel coordinate must be 0, 1, or 2. Kernel
    // coordinates are not constrained for 1x1 or activation operations here.
    assign invalid_weight_config = !config_o[9] && config_o[3] &&
                                   ((config_o[6:5] == 2'd3) ||
                                    (config_o[8:7] == 2'd3));

    // Packed activation groups are eight bytes, so activation pointers require
    // bits [2:0]=0. A packed weight slice is 64 bytes and requires bits [5:0]=0;
    // besides matching its object size, this guarantees its 16-beat read does
    // not cross a 4-KiB boundary. Validation uses the WSTRB-merged pointer.
    assign invalid_activation_alignment = |next_source_base[2:0];
    assign invalid_weight_alignment     = |next_source_base[5:0];
    assign invalid_source_alignment = config_o[3]
                                      ? invalid_weight_alignment
                                      : invalid_activation_alignment;

    // Write/control state. Status inputs set sticky flags asynchronously with
    // respect to software transactions (but synchronously to clk). A legal new
    // start clears both flags, making them describe the new operation.
    always @(posedge clk) begin
        if (!rstn) begin
            source_base_o  <= 32'd0;
            config_o       <= 10'd0;
            start_pulse_o  <= 1'b0;
            done_sticky_o  <= 1'b0;
            error_sticky_o <= 1'b0;
            aw_hold_valid  <= 1'b0;
            awsel_hold     <= WRITE_INVALID;
            w_hold_valid   <= 1'b0;
            wdata_hold     <= 32'd0;
            wstrb_hold     <= 4'd0;
            axil_bresp     <= AXI_RESP_OKAY;
            axil_bvalid    <= 1'b0;
        end else begin
            // Default-low assignment makes every accepted start exactly one
            // cycle wide unless reset is asserted.
            start_pulse_o <= 1'b0;
            if (done_pulse_i)
                done_sticky_o <= 1'b1;
            if (read_error_pulse_i)
                error_sticky_o <= 1'b1;

            // Complete the previous B response, then capture any unmatched AW
            // or W half of the next transaction.
            if (axil_bvalid && axil_bready)
                axil_bvalid <= 1'b0;
            if (aw_accept && !write_commit) begin
                aw_hold_valid <= 1'b1;
                awsel_hold    <= decode_write_address(axil_awaddr);
            end
            if (w_accept && !write_commit) begin
                w_hold_valid <= 1'b1;
                wdata_hold   <= axil_wdata;
                wstrb_hold   <= axil_wstrb;
            end

            // Commit consumes both assembled halves and creates one B response.
            // write_select identifies whether this is start, config, or bad
            // address; write_data/write_strb already select held/current inputs.
            if (write_commit) begin
                aw_hold_valid <= 1'b0;
                w_hold_valid  <= 1'b0;
                axil_bvalid   <= 1'b1;
                case (write_select)
                    WRITE_POINTER: begin
                        // Pointer writes are also start commands. Configuration
                        // is read from config_o, so software programs 0x008 first.
                        if (busy_i || !start_ready_i || start_pulse_o ||
                            invalid_weight_config ||
                            invalid_source_alignment) begin
                            axil_bresp     <= AXI_RESP_SLVERR;
                            error_sticky_o <= 1'b1;
                        end else begin
                            source_base_o  <= next_source_base;
                            start_pulse_o  <= 1'b1;
                            done_sticky_o  <= 1'b0;
                            error_sticky_o <= 1'b0;
                            axil_bresp     <= AXI_RESP_OKAY;
                        end
                    end
                    WRITE_CONFIG: begin
                        // Configuration remains stable for the full operation.
                        // Field legality needed by a start is checked when the
                        // pointer command arrives, not at configuration time.
                        if (busy_i || start_pulse_o) begin
                            axil_bresp     <= AXI_RESP_SLVERR;
                            error_sticky_o <= 1'b1;
                        end else begin
                            config_o   <= next_config;
                            axil_bresp <= AXI_RESP_OKAY;
                        end
                    end
                    default: begin
                        // Unsupported write address: no programming register is
                        // modified, and software receives a decode error.
                        axil_bresp     <= AXI_RESP_DECERR;
                        error_sticky_o <= 1'b1;
                    end
                endcase
            end
        end
    end

    // Read data construction. Exact-address validation returns zero/DECERR for
    // aliases or unsupported offsets rather than exposing a mirrored register.
    assign status_word = {
        29'd0, error_sticky_o, busy_i, done_sticky_o
    };
    assign config_word = {22'd0, config_o};
    assign read_addr_valid = (axil_araddr == 10'h000) ||
                             (axil_araddr == 10'h004) ||
                             (axil_araddr == 10'h008);

    // The compact mux uses word-offset bits; read_addr_valid separately proves
    // that upper/lower address bits identify one of the three exact registers.
    assign read_mux_data = (axil_araddr[4:2] == 3'd0)
                           ? source_base_o
                           : (axil_araddr[4:2] == 3'd1)
                             ? status_word
                             : (axil_araddr[4:2] == 3'd2)
                               ? config_word : 32'd0;
    assign read_data = read_addr_valid ? read_mux_data : 32'd0;
    assign axil_rresp = read_error_q ? AXI_RESP_DECERR : AXI_RESP_OKAY;

    // One-entry read response register. Once accepted, RDATA/RRESP remain in
    // their registers and RVALID remains asserted until the CPU raises RREADY.
    assign axil_arready = !axil_rvalid;
    always @(posedge clk) begin
        if (!rstn) begin
            axil_rdata  <= 32'd0;
            read_error_q <= 1'b0;
            axil_rvalid <= 1'b0;
        end else begin
            if (axil_rvalid && axil_rready)
                axil_rvalid <= 1'b0;
            if (axil_arvalid && axil_arready) begin
                axil_rdata  <= read_data;
                read_error_q <= !read_addr_valid;
                axil_rvalid <= 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
