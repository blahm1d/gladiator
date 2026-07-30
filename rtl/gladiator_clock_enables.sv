// CLK-XTAL-001, CLK-MCU-001, CLK-TCLK-001
// All original-board domains are clock enables from a 96 MHz master.
module gladiator_clock_enables (
    input  logic clk_96,
    input  logic reset,
    output logic ce_12m,
    output logic ce_6m,
    output logic ce_3m,
    output logic ce_1m5,
    output logic tclk,
    output logic ce_750k,
    output logic ce_455k
);

    logic [13:0] divider;

    always_ff @(posedge clk_96) begin
        if (reset) begin
            divider <= 14'd0;
            ce_12m  <= 1'b0;
            ce_6m   <= 1'b0;
            ce_3m   <= 1'b0;
            ce_1m5  <= 1'b0;
        end else begin
            divider <= divider + 14'd1;
            ce_12m  <= (divider[2:0] == 3'b111);
            ce_6m   <= (divider[3:0] == 4'b1111);
            ce_3m   <= (divider[4:0] == 5'b1_1111);
            ce_1m5  <= (divider[5:0] == 6'b11_1111);
            // MC6809 (NOT MC6809E) -- MAME's mc6809_device divides its XTAL
            // input by 4 internally, so MC6809(12_MHz_XTAL/4) is a 3 MHz XTAL
            // and a 750 kHz E/Q BUS clock. mc6809i is an E-style core whose
            // cen_E is the bus clock, so it must be fed 750 kHz, not 3 MHz.
            // 96 MHz / 128 = 750 kHz exactly.
            ce_750k <= (divider[6:0] == 7'b111_1111);
        end
    end

    // 96 MHz / 2^14 = 5,859.375 Hz.
    assign tclk = divider[13];

    // AUD-MSM-001: retained as the MSM5205 reference clock observation.
    // External VCLK, not this enable, advances the ADPCM decoder.
    gladiator_nco_ce #(.STEP(32'h0136_9D03)) nco_455k (
        .clk    (clk_96),
        .reset  (reset),
        .enable (1'b1),
        .ce     (ce_455k)
    );

endmodule

