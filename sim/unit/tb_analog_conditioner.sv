`timescale 1ns/1ps

module tb_analog_conditioner;
    logic clk = 0;
    always #5 clk = ~clk;

    logic reset = 1;
    logic pixel_ce = 1;
    logic [9:0] h_count = 0;
    logic [9:0] v_count = 0;
    logic [9:0] h_total = 10'd800;
    logic [9:0] v_total = 10'd525;
    logic [9:0] default_hsync_start = 10'd656;
    logic [9:0] default_vsync_start = 10'd490;
    logic [9:0] default_hsync_width = 10'd96;
    logic [3:0] default_vsync_width = 4'd2;
    logic [9:0] content_x_start = 10'd64;
    logic [9:0] content_x_end = 10'd576;
    logic [9:0] content_y_start = 10'd16;
    logic [9:0] content_y_end = 10'd464;
    logic [7:0] red_in = 8'ha5;
    logic [7:0] green_in = 8'h5a;
    logic [7:0] blue_in = 8'hff;
    logic hblank_in = 0;
    logic vblank_in = 0;
    logic [4:0] h_position = 0;
    logic [4:0] v_position = 0;
    logic [3:0] hsync_width_adjust = 0;
    logic [1:0] vsync_width_adjust = 0;
    logic hsync_positive = 0;
    logic vsync_positive = 0;
    logic [3:0] crop_horizontal = 0;
    logic [3:0] crop_vertical = 0;
    logic [7:0] red, green, blue;
    logic hblank, vblank, hsync, vsync;

    gladiator_analog_conditioner dut (.*);

    task automatic sample_at (
        input logic [9:0] x,
        input logic [9:0] y
    );
        begin
            @(negedge clk);
            h_count <= x;
            v_count <= y;
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        reset <= 0;

        sample_at(10'd655, 10'd100);
        if (hsync !== 1'b1) $fatal(1, "hsync asserted early");
        sample_at(10'd656, 10'd100);
        if (hsync !== 1'b0) $fatal(1, "negative hsync did not assert");
        sample_at(10'd751, 10'd100);
        if (hsync !== 1'b0) $fatal(1, "hsync width too short");
        sample_at(10'd752, 10'd100);
        if (hsync !== 1'b1) $fatal(1, "hsync width too long");

        h_position <= 5'd2;
        sample_at(10'd656, 10'd100);
        if (hsync !== 1'b1) $fatal(1, "positive h-position ignored");
        sample_at(10'd658, 10'd100);
        if (hsync !== 1'b0) $fatal(1, "positive h-position wrong");

        h_position <= 5'd0;
        hsync_width_adjust <= 4'hf; // -1
        sample_at(10'd750, 10'd100);
        if (hsync !== 1'b0) $fatal(1, "negative width trim too short");
        sample_at(10'd751, 10'd100);
        if (hsync !== 1'b1) $fatal(1, "negative width trim ignored");

        hsync_positive <= 1;
        sample_at(10'd656, 10'd100);
        if (hsync !== 1'b1) $fatal(1, "positive hsync polarity wrong");
        sample_at(10'd100, 10'd100);
        if (hsync !== 1'b0) $fatal(1, "positive hsync idle wrong");

        vsync_positive <= 0;
        sample_at(10'd100, 10'd490);
        if (vsync !== 1'b0) $fatal(1, "negative vsync did not assert");
        sample_at(10'd100, 10'd492);
        if (vsync !== 1'b1) $fatal(1, "negative vsync width wrong");

        crop_horizontal <= 4'd2;
        crop_vertical <= 4'd2;
        sample_at(10'd64, 10'd100);
        if (!hblank || red != 0) $fatal(1, "left crop missing");
        sample_at(10'd66, 10'd100);
        if (hblank || red != red_in) $fatal(1, "left crop too wide");
        sample_at(10'd575, 10'd100);
        if (!hblank || red != 0) $fatal(1, "right crop missing");
        sample_at(10'd100, 10'd16);
        if (!vblank || green != 0) $fatal(1, "top crop missing");
        sample_at(10'd100, 10'd18);
        if (vblank || green != green_in) $fatal(1, "top crop too wide");

        $display("PASS tb_analog_conditioner");
        $finish;
    end
endmodule
