// AUD-MSM-001
// External-clock MSM5205 mode, following the pinned MAME device model and the
// OKI capture timing. The MSM5205 begins capture on VCLK's falling edge (the
// MSM6585 uses the opposite edge), then samples the live data pins six
// master-clock periods later. Its ADPCM state is 12-bit internally, while the
// MSM5205 package exposes a 10-bit DAC; the low two output bits are discarded.
module gladiator_msm5205 (
    input  logic               clk,
    input  logic               reset,
    input  logic               ce_455k,
    input  logic [3:0]         nibble,
    input  logic               external_vclk,
    input  logic               chip_reset,
    output logic signed [11:0] sound,
    output logic               decode_strobe
);

    logic external_vclk_d;
    logic capture_pending;
    logic [2:0] capture_clocks;
    logic capture_fire;
    logic signed [12:0] signal;
    logic [5:0] step_index;
    logic [10:0] step;
    logic [12:0] magnitude;
    logic signed [13:0] candidate;
    logic signed [11:0] next_signal;
    logic signed [7:0] next_index_unclamped;
    logic [5:0] next_index;

    assign capture_fire = capture_pending && ce_455k &&
                          (capture_clocks == 3'd1);

    function automatic logic [10:0] step_value(input logic [5:0] index);
        case (index)
            6'd0:  step_value = 11'd16;
            6'd1:  step_value = 11'd17;
            6'd2:  step_value = 11'd19;
            6'd3:  step_value = 11'd21;
            6'd4:  step_value = 11'd23;
            6'd5:  step_value = 11'd25;
            6'd6:  step_value = 11'd28;
            6'd7:  step_value = 11'd31;
            6'd8:  step_value = 11'd34;
            6'd9:  step_value = 11'd37;
            6'd10: step_value = 11'd41;
            6'd11: step_value = 11'd45;
            6'd12: step_value = 11'd50;
            6'd13: step_value = 11'd55;
            6'd14: step_value = 11'd60;
            6'd15: step_value = 11'd66;
            6'd16: step_value = 11'd73;
            6'd17: step_value = 11'd80;
            6'd18: step_value = 11'd88;
            6'd19: step_value = 11'd97;
            6'd20: step_value = 11'd107;
            6'd21: step_value = 11'd118;
            6'd22: step_value = 11'd130;
            6'd23: step_value = 11'd143;
            6'd24: step_value = 11'd157;
            6'd25: step_value = 11'd173;
            6'd26: step_value = 11'd190;
            6'd27: step_value = 11'd209;
            6'd28: step_value = 11'd230;
            6'd29: step_value = 11'd253;
            6'd30: step_value = 11'd279;
            6'd31: step_value = 11'd307;
            6'd32: step_value = 11'd337;
            6'd33: step_value = 11'd371;
            6'd34: step_value = 11'd408;
            6'd35: step_value = 11'd449;
            6'd36: step_value = 11'd494;
            6'd37: step_value = 11'd544;
            6'd38: step_value = 11'd598;
            6'd39: step_value = 11'd658;
            6'd40: step_value = 11'd724;
            6'd41: step_value = 11'd796;
            6'd42: step_value = 11'd876;
            6'd43: step_value = 11'd963;
            6'd44: step_value = 11'd1060;
            6'd45: step_value = 11'd1166;
            6'd46: step_value = 11'd1282;
            6'd47: step_value = 11'd1411;
            default: step_value = 11'd1552;
        endcase
    endfunction

    function automatic logic signed [7:0] index_delta(
        input logic [2:0] code
    );
        case (code)
            3'd0, 3'd1, 3'd2, 3'd3: index_delta = -8'sd1;
            3'd4: index_delta = 8'sd2;
            3'd5: index_delta = 8'sd4;
            3'd6: index_delta = 8'sd6;
            default: index_delta = 8'sd8;
        endcase
    endfunction

    always_comb begin
        step = step_value(step_index);
        magnitude = {2'b00, step} >> 3;
        if (nibble[0])
            magnitude = magnitude + ({2'b00, step} >> 2);
        if (nibble[1])
            magnitude = magnitude + ({2'b00, step} >> 1);
        if (nibble[2])
            magnitude = magnitude + {2'b00, step};

        if (nibble[3])
            candidate = signal - $signed({1'b0, magnitude});
        else
            candidate = signal + $signed({1'b0, magnitude});

        if (candidate > 14'sd2047)
            next_signal = 12'sd2047;
        else if (candidate < -14'sd2048)
            next_signal = -12'sd2048;
        else
            next_signal = candidate[11:0];

        next_index_unclamped =
            $signed({1'b0, step_index}) + index_delta(nibble[2:0]);
        if (next_index_unclamped < 0)
            next_index = 6'd0;
        else if (next_index_unclamped > 48)
            next_index = 6'd48;
        else
            next_index = next_index_unclamped[5:0];
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            external_vclk_d <= 1'b0;
            capture_pending <= 1'b0;
            capture_clocks  <= 3'd0;
            decode_strobe   <= 1'b0;
            signal          <= 13'sd0;
            step_index      <= 6'd0;
            sound           <= 12'sd0;
        end else begin
            external_vclk_d <= external_vclk;
            decode_strobe   <= capture_fire;

            if (!external_vclk && external_vclk_d) begin
                capture_pending <= 1'b1;
                capture_clocks  <= 3'd6;
            end else if (capture_pending && ce_455k) begin
                if (capture_clocks == 3'd1) begin
                    capture_pending <= 1'b0;
                    capture_clocks  <= 3'd0;
                end else begin
                    capture_clocks <= capture_clocks - 3'd1;
                end
            end

            if (capture_fire) begin
                if (chip_reset) begin
                    signal     <= 13'sd0;
                    step_index <= 6'd0;
                    sound      <= 12'sd0;
                end else begin
                    signal     <= {{1{next_signal[11]}}, next_signal};
                    step_index <= next_index;
                    sound      <= {next_signal[11:2], 2'b00};
                end
            end
        end
    end

endmodule
