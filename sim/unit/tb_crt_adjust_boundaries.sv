`timescale 1ns/1ps

module tb_crt_adjust_boundaries;

    localparam integer H_TOTAL = 384;
    localparam integer H_ACTIVE = 256;

    logic clk = 1'b0;
    logic [8:0] h_count = 9'd0;
    logic [8:0] sampled_h = 9'd0;
    logic signed [8:0] hoffset = 9'sd0;
    logic previous_bank;
    logic monitoring = 1'b0;
    integer bank_flips = 0;
    integer sync_low_pixels = 0;
    integer monitored_lines = 0;

    wire hblank = h_count >= H_ACTIVE;
    wire hsync = !((h_count >= 9'd288) && (h_count < 9'd320));
    wire hs_ref;

    always #5 clk = ~clk;

    always @(posedge clk) begin
        sampled_h <= h_count;
        if (h_count == H_TOTAL - 1)
            h_count <= 9'd0;
        else
            h_count <= h_count + 9'd1;
    end

    crt_adjust #(
        .VTOTAL    (262),
        .HTOTAL    (H_TOTAL),
        .HPOS_MODE (0),
        .COLOR_BITS(5)
    ) dut (
        .clk        (clk),
        .pxl_cen    (1'b1),
        .pxl2_cen   (1'b1),
        .active     (1'b1),
        .hsize      (5'sd0),
        .hoffset    (hoffset),
        .voffset    (6'sd0),
        .r_in       (8'd0),
        .g_in       (8'd0),
        .b_in       (8'd0),
        .hs_in      (hsync),
        .vs_in      (1'b1),
        .hb_in      (hblank),
        .vb_in      (1'b0),
        .r_out      (),
        .g_out      (),
        .b_out      (),
        .hs_out     (),
        .vs_out     (),
        .hb_out     (),
        .vb_out     (),
        .hs_ref_out (hs_ref)
    );

    always @(negedge clk) begin
        if (monitoring) begin
            if (sampled_h < H_ACTIVE && !hs_ref)
                $fatal(1,
                    "shifted HSync overlaps active video: offset=%0d h=%0d",
                    hoffset, sampled_h);

            if (dut.bank != previous_bank) begin
                bank_flips = bank_flips + 1;
                if (sampled_h < H_ACTIVE)
                    $fatal(1,
                        "line-buffer bank flipped during active capture: offset=%0d h=%0d",
                        hoffset, sampled_h);
            end

            if (!hs_ref)
                sync_low_pixels = sync_low_pixels + 1;
            if (sampled_h == H_TOTAL - 1)
                monitored_lines = monitored_lines + 1;
        end
        previous_bank = dut.bank;
    end

    task automatic wait_lines(input integer count);
        integer seen;
        begin
            seen = 0;
            while (seen < count) begin
                @(negedge clk);
                if (sampled_h == H_TOTAL - 1)
                    seen = seen + 1;
            end
        end
    endtask

    task automatic check_boundary(input logic signed [8:0] offset);
        begin
            monitoring = 1'b0;
            hoffset = offset;
            wait_lines(3);

            bank_flips = 0;
            sync_low_pixels = 0;
            monitored_lines = 0;
            previous_bank = dut.bank;
            monitoring = 1'b1;
            wait_lines(4);
            monitoring = 1'b0;

            if (monitored_lines != 4)
                $fatal(1, "did not monitor four complete lines");
            if (bank_flips != 4)
                $fatal(1,
                    "expected one blanking-time bank flip per line: offset=%0d flips=%0d",
                    offset, bank_flips);
            if (sync_low_pixels != 4 * 32)
                $fatal(1,
                    "shift changed HSync width: offset=%0d low_pixels=%0d",
                    offset, sync_low_pixels);
        end
    endtask

    initial begin
        if (dut.expand_color(5'b10101) !== 8'b10101_101)
            $fatal(1, "RGB555 red expansion is not bit-exact");
        if (dut.expand_color(5'b01010) !== 8'b01010_010)
            $fatal(1, "RGB555 green expansion is not bit-exact");
        if (dut.expand_color(5'b11100) !== 8'b11100_111)
            $fatal(1, "RGB555 blue expansion is not bit-exact");
        previous_bank = dut.bank;
        check_boundary(-9'sd32);
        check_boundary(9'sd62);
        $display("tb_crt_adjust_boundaries PASS");
        $finish;
    end

endmodule
