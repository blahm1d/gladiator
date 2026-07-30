`timescale 1ns/1ps

module tb_crt_read_ce;

    logic clk = 1'b0;
    logic native_ce = 1'b0;
    logic active = 1'b0;
    logic signed [4:0] hsize = 5'sd0;
    logic hs_ref = 1'b0;
    logic read_ce;

    gladiator_crt_read_ce dut (
        .clk       (clk),
        .native_ce (native_ce),
        .active    (active),
        .hsize     (hsize),
        .hs_ref    (hs_ref),
        .read_ce   (read_ce)
    );

    always #5 clk = ~clk;

    task automatic pulse_hs_ref;
        begin
            @(negedge clk);
            hs_ref = 1'b1;
            @(negedge clk);
            hs_ref = 1'b0;
        end
    endtask

    task automatic expect_tick_after(input integer expected_cycles);
        integer cycles;
        begin
            cycles = 0;
            do begin
                @(negedge clk);
                cycles = cycles + 1;
            end while (!read_ce && cycles < 100);
            if (cycles != expected_cycles)
                $fatal(1, "read tick after %0d cycles, expected %0d",
                       cycles, expected_cycles);
        end
    endtask

    initial begin
        // Off is a direct native-CE bypass.
        native_ce = 1'b1;
        #1;
        if (!read_ce)
            $fatal(1, "inactive generator did not pass native CE");
        native_ce = 1'b0;
        #1;
        if (read_ce)
            $fatal(1, "inactive generator asserted without native CE");

        // CE is combinationally high during the cycle preceding its consuming
        // edge, so the first observed-high half-cycle follows 15 updates and is
        // consumed on clock 16.
        active = 1'b1;
        pulse_hs_ref();
        expect_tick_after(15);

        // A second reference edge must restart phase even mid-period.
        repeat (5) @(negedge clk);
        pulse_hs_ref();
        expect_tick_after(15);

        // Minimum H-Size period is consumed on clock 12.
        hsize = -5'sd16;
        pulse_hs_ref();
        expect_tick_after(11);

        $display("tb_crt_read_ce PASS");
        $finish;
    end

endmodule
