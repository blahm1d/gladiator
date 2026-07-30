// Quarter-cycle read-rate generator for the optional CRT Adjust line buffer.
// The accumulator deliberately resets from crt_adjust.hs_ref_out, which may be
// shifted relative to the board's raw HSync in HPOS_SYNCSHIFT mode.
module gladiator_crt_read_ce (
    input  logic              clk,
    input  logic              native_ce,
    input  logic              active,
    input  logic signed [4:0] hsize,
    input  logic              hs_ref,
    output logic              read_ce
);

    logic       hs_ref_d = 1'b0;
    logic [7:0] accumulator = 8'd0;
    wire        hs_ref_rise = hs_ref && !hs_ref_d;
    wire [7:0]  period = 8'd64 + {{3{hsize[4]}}, hsize};
    wire        tick = (accumulator + 8'd4) >= period;

    always_ff @(posedge clk) begin
        hs_ref_d <= hs_ref;
        if (hs_ref_rise)
            accumulator <= 8'd0;
        else if (tick)
            accumulator <= accumulator + 8'd4 - period;
        else
            accumulator <= accumulator + 8'd4;
    end

    always_comb
        read_ce = active ? tick : native_ce;

endmodule
