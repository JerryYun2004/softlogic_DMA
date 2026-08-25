module pe #(
    parameter int ACTIVATION_WIDTH = 8,
    parameter int WEIGHT_WIDTH     = 8,
    parameter int PSUM_WIDTH       = 32
)(
    input  wire                        clk_i,
    input  wire                        rst_n,
    input  wire                        array_en,
    
    // Compute Data Stream
    input  wire [ACTIVATION_WIDTH-1:0] act_in,
    input  wire [PSUM_WIDTH-1:0]       psum_in,
    output reg  [ACTIVATION_WIDTH-1:0] act_out,
    output reg  [PSUM_WIDTH-1:0]       psum_out,
    
    // Weight Shadow Shift Chain & Swap
    input  wire [WEIGHT_WIDTH-1:0]     weight_shift_in,
    output wire [WEIGHT_WIDTH-1:0]     weight_shift_out,
    input  wire                        weight_shift_en,
    input  wire                        swap_weights
);

    reg [WEIGHT_WIDTH-1:0] shadow_weight;
    reg [WEIGHT_WIDTH-1:0] active_weight;

    // Shift new weight into shadow register
    always_ff @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            shadow_weight <= '0;
        end else if (weight_shift_en) begin
            shadow_weight <= weight_shift_in;
        end
    end

    assign weight_shift_out = shadow_weight;

    // Weight swap & compute pipeline
    always_ff @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            active_weight <= '0;
            act_out       <= '0;
            psum_out      <= '0;
        end else begin
            if (swap_weights) begin
                active_weight <= shadow_weight;
            end
            
            if (array_en) begin
                act_out  <= act_in;
                psum_out <= psum_in + ($signed(act_in) * $signed(active_weight));
            end
        end
    end

endmodule