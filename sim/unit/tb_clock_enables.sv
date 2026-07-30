`timescale 1ns/1ps

module tb_clock_enables;
    logic clk_96 = 0;
    always #5 clk_96 = ~clk_96;

    logic reset = 1;
    logic ce_12m, ce_6m, ce_3m, ce_1m5, tclk, ce_455k, ce_750k;
    integer n12 = 0;
    integer n6 = 0;
    integer n3 = 0;
    integer n15 = 0;
    integer n750 = 0;

    gladiator_clock_enables dut (.*);

    always @(posedge clk_96) begin
        if (ce_12m) n12++;
        if (ce_6m) n6++;
        if (ce_3m) n3++;
        if (ce_1m5) n15++;
        if (ce_750k) n750++;
    end

    initial begin
        repeat (4) @(posedge clk_96);
        @(negedge clk_96);
        reset = 0;
        repeat (1920) @(posedge clk_96);
        @(posedge clk_96);
        #1;
        // ce_750k is the MC6809 E/Q BUS clock. MAME's mc6809_device divides
        // its XTAL by 4, so MC6809(12MHz/4) means a 750 kHz bus, not 3 MHz.
        // Over 1920 cycles of 96 MHz that is exactly 15 pulses; the old
        // (wrong) 3 MHz wiring would count 60 and fail here.
        if (n12 != 240 || n6 != 120 || n3 != 60 || n15 != 30 || n750 != 15)
        begin
            $error("enable counts 12=%0d 6=%0d 3=%0d 1.5=%0d 750k=%0d (expect 240/120/60/30/15)", n12, n6, n3, n15, n750);
            $fatal(1);
        end
        $display("PASS tb_clock_enables");
        $finish;
    end
endmodule
