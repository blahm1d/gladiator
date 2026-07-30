`timescale 1ns/1ps

module tb_audio_mixer;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic sample_enable = 1'b0;
    logic [7:0] psg_a = 8'd0;
    logic [7:0] psg_b = 8'd0;
    logic [7:0] psg_c = 8'd0;
    logic signed [15:0] fm = 16'sd0;
    logic signed [11:0] adpcm = 12'sd0;
    logic effect_active = 1'b0;
    logic [1:0] effect_gain = 2'b00;
    logic [7:0] filter_latch = 8'd0;
    logic signed [15:0] mono;
    logic clip;

    gladiator_audio_mixer dut (
        .clk           (clk),
        .reset         (reset),
        .sample_enable (sample_enable),
        .psg_a         (psg_a),
        .psg_b         (psg_b),
        .psg_c         (psg_c),
        .fm            (fm),
        .adpcm         (adpcm),
        .effect_active (effect_active),
        .effect_gain   (effect_gain),
        .filter_latch  (filter_latch),
        .mono          (mono),
        .clip          (clip)
    );

    always #5 clk = ~clk;

    task automatic submit_and_expect(
        input logic [7:0] test_psg_a,
        input logic [7:0] test_psg_b,
        input logic [7:0] test_psg_c,
        input logic signed [15:0] test_fm,
        input logic signed [11:0] test_adpcm,
        input logic test_effect_active,
        input logic [1:0] test_effect_gain,
        input logic signed [15:0] expected_mono,
        input logic expected_clip,
        input string label
    );
        begin
            @(negedge clk);
            psg_a = test_psg_a;
            psg_b = test_psg_b;
            psg_c = test_psg_c;
            fm = test_fm;
            adpcm = test_adpcm;
            effect_active = test_effect_active;
            effect_gain = test_effect_gain;
            sample_enable = 1'b1;

            @(posedge clk);
            #1;
            sample_enable = 1'b0;

            // Input capture, scale, mix, then saturation/output.
            repeat (3) @(posedge clk);
            #1;
            if ((mono !== expected_mono) || (clip !== expected_clip)) begin
                $error("%s: mono=%0d clip=%b expected mono=%0d clip=%b",
                       label, mono, clip, expected_mono, expected_clip);
                $fatal(1);
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        #1 reset = 1'b0;

        submit_and_expect(8'd0, 8'd0, 8'd0, 16'sd0, 12'sd0, 1'b0, 2'b00,
                          16'sd0, 1'b0, "silence");
        submit_and_expect(8'd10, 8'd20, 8'd30, -16'sd1000, 12'sd80,
                          1'b0, 2'b00,
                          16'sd2580, 1'b0, "signed fixed-point mix");
        submit_and_expect(8'd10, 8'd20, 8'd30, -16'sd1000, 12'sd80,
                          1'b1, 2'b00,
                          16'sd2080, 1'b0, "effects-only +6 dB");
        submit_and_expect(8'd10, 8'd20, 8'd30, -16'sd1000, 12'sd80,
                          1'b1, 2'b10,
                          16'sd2580, 1'b0, "effects original gain");
        submit_and_expect(8'd0, 8'd0, 8'd0, 16'sd0, 12'sd80,
                          1'b1, 2'b11,
                          16'sd770, 1'b0, "speech unaffected by effects gain");
        submit_and_expect(8'd255, 8'd255, 8'd255, 16'sd32767, 12'sd2047,
                          1'b1, 2'b11,
                          16'sd32767, 1'b1, "positive saturation");
        submit_and_expect(8'd0, 8'd0, 8'd0, -16'sd32768, -12'sd2048,
                          1'b1, 2'b11,
                          -16'sd32768, 1'b1, "negative saturation");

        $display("PASS tb_audio_mixer");
        $finish;
    end
endmodule
