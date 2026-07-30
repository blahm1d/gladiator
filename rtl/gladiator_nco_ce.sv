// Fractional clock-enable generator. The accumulator runs in the 96 MHz
// board-master domain; no fabric-generated clock is used.
module gladiator_nco_ce #(
    parameter logic [31:0] STEP = 32'h1000_0000
) (
    input  logic clk,
    input  logic reset,
    input  logic enable,
    output logic ce
);

    logic [32:0] sum;
    logic [31:0] phase;

    always_comb sum = {1'b0, phase} + {1'b0, STEP};

    always_ff @(posedge clk) begin
        if (reset) begin
            phase <= 32'd0;
            ce    <= 1'b0;
        end else begin
            ce <= 1'b0;
            if (enable) begin
                phase <= sum[31:0];
                ce    <= sum[32];
            end
        end
    end

endmodule

