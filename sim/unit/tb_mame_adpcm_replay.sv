`timescale 1ns/1ps

module tb_mame_adpcm_replay;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic ce_455k = 1'b0;
    logic [3:0] nibble = 4'd0;
    logic external_vclk = 1'b0;
    logic chip_reset = 1'b0;
    logic signed [11:0] sound;
    logic decode_strobe;

    integer oracle;
    integer fields;
    integer reset_value;
    integer nibble_value;
    integer expected_sound;
    integer captures;
    integer delay;
    integer nibble_mask;

    gladiator_msm5205 dut (
        .clk           (clk),
        .reset         (reset),
        .ce_455k       (ce_455k),
        .nibble        (nibble),
        .external_vclk (external_vclk),
        .chip_reset    (chip_reset),
        .sound         (sound),
        .decode_strobe (decode_strobe)
    );

    always #5 clk = ~clk;

    task automatic clock_with_ce(input logic enable);
        begin
            ce_455k = enable;
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        oracle = $fopen("sim/out/mame-adpcm-oracle.txt", "r");
        if (oracle == 0)
            $fatal(1, "cannot open MAME MSM5205 oracle");

        repeat (2) @(posedge clk);
        #1 reset = 1'b0;
        captures = 0;
        nibble_mask = 0;

        while (!$feof(oracle)) begin
            fields = $fscanf(
                oracle, "%d %h %d\n",
                reset_value, nibble_value, expected_sound
            );
            if (fields == 3) begin
                chip_reset = reset_value[0];
                nibble = nibble_value[3:0];
                if (!reset_value)
                    nibble_mask = nibble_mask | (1 << nibble_value);

                external_vclk = 1'b1;
                clock_with_ce(1'b0);
                if (decode_strobe)
                    $fatal(1, "capture on MAME VCLK rising edge");

                external_vclk = 1'b0;
                clock_with_ce(1'b0);
                if (decode_strobe)
                    $fatal(1, "capture before the six-clock delay");

                for (delay = 1; delay <= 5; delay = delay + 1) begin
                    clock_with_ce(1'b1);
                    if (decode_strobe)
                        $fatal(
                            1,
                            "capture %0d fired at delay clock %0d",
                            captures,
                            delay
                        );
                end

                clock_with_ce(1'b1);
                if (!decode_strobe)
                    $fatal(1, "capture %0d missing at clock six", captures);
                if ($signed(sound) !== expected_sound)
                    $fatal(
                        1,
                        "capture %0d nibble %x: RTL %0d MAME %0d",
                        captures,
                        nibble_value,
                        $signed(sound),
                        expected_sound
                    );

                clock_with_ce(1'b0);
                if (decode_strobe)
                    $fatal(1, "capture %0d strobe repeated", captures);
                captures = captures + 1;
            end
        end

        $fclose(oracle);
        if (captures < 1000)
            $fatal(1, "only replayed %0d MAME captures", captures);
        if (nibble_mask !== 16'hffff)
            $fatal(1, "MAME replay nibble mask %04x", nibble_mask);

        $display(
            "PASS tb_mame_adpcm_replay: %0d MAME captures",
            captures
        );
        $finish;
    end
endmodule
