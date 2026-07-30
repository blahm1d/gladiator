// AUD-MIX-001, AUD-FILT-001
// Fixed-point MAME-compatibility mix. PCB filter controls remain observable but
// have no transfer function until component values are established.
module gladiator_audio_mixer (
    input  logic               clk,
    input  logic               reset,
    input  logic               sample_enable,
    input  logic [7:0]         psg_a,
    input  logic [7:0]         psg_b,
    input  logic [7:0]         psg_c,
    input  logic signed [15:0] fm,
    input  logic signed [11:0] adpcm,
    input  logic               effect_active,
    input  logic [1:0]         effect_gain,
    input  logic [7:0]         filter_latch,
    output logic signed [15:0] mono,
    output logic               clip
);

    logic [7:0]         psg_a_q;
    logic [7:0]         psg_b_q;
    logic [7:0]         psg_c_q;
    logic signed [15:0] fm_q;
    logic signed [11:0] adpcm_q;

    logic signed [19:0] psg_sum_q;
    logic signed [19:0] fm_scaled_q;
    logic signed [19:0] adpcm_scaled_q;
    logic signed [21:0] mixed_q;
    logic signed [19:0] fm_extended;

    assign fm_extended = {{4{fm_q[15]}}, fm_q};

    logic input_valid;
    logic scale_valid;
    logic mix_valid;

    always_ff @(posedge clk) begin
        if (reset) begin
            psg_a_q       <= 8'd0;
            psg_b_q       <= 8'd0;
            psg_c_q       <= 8'd0;
            fm_q          <= 16'sd0;
            adpcm_q       <= 12'sd0;
            psg_sum_q     <= 20'sd0;
            fm_scaled_q   <= 20'sd0;
            adpcm_scaled_q <= 20'sd0;
            mixed_q       <= 22'sd0;
            input_valid   <= 1'b0;
            scale_valid   <= 1'b0;
            mix_valid     <= 1'b0;
            mono          <= 16'sd0;
            clip          <= 1'b0;
        end else begin
            // The source devices and this mixer share clk. Capture their
            // outputs only at the board's audio sample strobe, then pipeline
            // the fixed-point work at the master rate. This preserves the
            // sampled arithmetic while avoiding a source-to-output path that
            // spans the complete PSG scale, sum, saturation, and mux.
            input_valid <= sample_enable;
            scale_valid <= input_valid;
            mix_valid   <= scale_valid;

            if (sample_enable) begin
                psg_a_q <= psg_a;
                psg_b_q <= psg_b;
                psg_c_q <= psg_c;
                fm_q    <= fm;
                adpcm_q <= adpcm;
            end

            if (input_valid) begin
                // Each unsigned PSG channel has zero as silence. Scale 8-bit
                // channel amplitude into the 16-bit mix, then apply
                // approximately 0.60. These expressions intentionally match
                // the pre-pipeline fixed-point widths and signed operations.
                psg_sum_q <= (($signed({1'b0, psg_a_q}) +
                               $signed({1'b0, psg_b_q}) +
                               $signed({1'b0, psg_c_q})) * 20'sd77) >>> 1;
                // Original FM route is 0.50. During a firmware-classified
                // effect voice, offer cabinet-selectable relative boosts:
                //   00 +6 dB (new default), 01 +3 dB,
                //   10 original,             11 +9 dB.
                // Speech/ADPCM and PSG arithmetic never enter this branch.
                if (!effect_active) begin
                    fm_scaled_q <= $signed(fm_q) >>> 1;
                end else begin
                    case (effect_gain)
                        2'b00:
                            fm_scaled_q <= fm_extended;
                        2'b01:
                            fm_scaled_q <=
                                (fm_extended >>> 1) +
                                (fm_extended >>> 3) +
                                (fm_extended >>> 4) +
                                (fm_extended >>> 6) +
                                (fm_extended >>> 8);
                        2'b10:
                            fm_scaled_q <= $signed(fm_q) >>> 1;
                        default:
                            fm_scaled_q <=
                                fm_extended +
                                (fm_extended >>> 2) +
                                (fm_extended >>> 3) +
                                (fm_extended >>> 5) +
                                (fm_extended >>> 7);
                    endcase
                end
                adpcm_scaled_q <= ($signed(adpcm_q) * 20'sd77) >>> 3;
            end

            if (scale_valid) begin
                mixed_q <= psg_sum_q + fm_scaled_q + adpcm_scaled_q;
            end

            if (mix_valid) begin
                clip <= 1'b0;
                if (mixed_q > 22'sd32767) begin
                    mono <= 16'sh7fff;
                    clip <= 1'b1;
                end else if (mixed_q < -22'sd32768) begin
                    mono <= -16'sh8000;
                    clip <= 1'b1;
                end else begin
                    mono <= mixed_q[15:0];
                end
            end
        end
    end

    logic unused_filter;
    assign unused_filter = ^filter_latch;

endmodule
