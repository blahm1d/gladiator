`timescale 1ns/1ps

module tb_msm5205;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic ce_455k = 1'b1;
    logic [3:0] nibble = 4'h5;
    logic external_vclk = 1'b0;
    logic chip_reset = 1'b0;
    logic signed [11:0] sound;
    logic decode_strobe;

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

    task automatic clock_and_expect(input logic expected, input string label);
        begin
            @(posedge clk);
            #1;
            if (decode_strobe !== expected) begin
                $error("%s: decode_strobe=%b expected=%b",
                       label, decode_strobe, expected);
                $fatal(1);
            end
        end
    endtask

    task automatic expect_delayed_capture(input string label);
        integer delay;
        begin
            for (delay = 1; delay <= 5; delay = delay + 1)
                clock_and_expect(
                    1'b0,
                    $sformatf("%s delay clock %0d", label, delay)
                );
            clock_and_expect(1'b1, {label, " capture clock 6"});
            clock_and_expect(1'b0, {label, " one-shot"});
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        #1 reset = 1'b0;

        external_vclk = 1'b1;
        clock_and_expect(1'b0, "rising edge must not decode");
        clock_and_expect(1'b0, "high level must not repeat");

        external_vclk = 1'b0;
        clock_and_expect(1'b0, "falling edge starts delayed capture");
        nibble = 4'ha;
        expect_delayed_capture("first falling edge");

        external_vclk = 1'b1;
        clock_and_expect(1'b0, "second rising edge must not decode");
        external_vclk = 1'b0;
        clock_and_expect(1'b0, "second falling edge starts delayed capture");
        expect_delayed_capture("second falling edge");

        $display("PASS tb_msm5205");
        $finish;
    end
endmodule
