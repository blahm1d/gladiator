`timescale 1ns/1ps

module tb_gfx_decode;
    logic clk = 0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // Tile/text bit-order check
    // ------------------------------------------------------------------
    logic video_reset = 1;
    logic pixel_ce = 0;
    logic [8:0] h_count = 0, v_count = 9'd16;
    logic [7:0] video_attributes = 8'h20;
    logic [7:0] video_bg_attr = 8'h00;
    logic [7:0] text_rom_data = 8'h00;
    logic [7:0] bg_plane0_data = 8'b0000_1010;
    logic [7:0] bg_plane12_data = 8'b1100_0110;
    logic [10:0] video_bg_address, video_fg_address;
    logic [9:0] video_palette_address;
    logic [12:0] text_rom_address;
    logic [15:0] bg_plane0_address, bg_plane12_address;
    logic [14:0] rgb555;
    logic vhblank, vvblank, vhsync, vvsync, valid_pixel, pixel_strobe;
    logic [8:0] output_h_count, output_v_count;

    gladiator_video video_dut (
        .clk(clk),
        .reset(video_reset),
        .pixel_ce(pixel_ce),
        .h_count(h_count),
        .v_count(v_count),
        .hblank_in(1'b0),
        .vblank_in(1'b0),
        .hsync_in(1'b1),
        .vsync_in(1'b1),
        .flip_screen(1'b0),
        .fg_scrolly(8'd0),
        .fg_scrollx(8'd0),
        .bg_scrolly(8'd0),
        .bg_scrollx(8'd0),
        .video_attributes(video_attributes),
        .video_bg_address(video_bg_address),
        .video_bg_code(8'd0),
        .video_bg_attr(video_bg_attr),
        .video_fg_address(video_fg_address),
        .video_fg_code(8'd0),
        .video_palette_address(video_palette_address),
        .video_palette_low(8'd0),
        .video_palette_ext(8'd0),
        .text_rom_address(text_rom_address),
        .text_rom_data(text_rom_data),
        .bg_plane0_address(bg_plane0_address),
        .bg_plane0_data(bg_plane0_data),
        .bg_plane12_address(bg_plane12_address),
        .bg_plane12_data(bg_plane12_data),
        .sprite_palette_index(10'd0),
        .rgb555(rgb555),
        .hblank(vhblank),
        .vblank(vvblank),
        .hsync(vhsync),
        .vsync(vvsync),
        .valid_pixel(valid_pixel),
        .pixel_strobe(pixel_strobe),
        .output_h_count(output_h_count),
        .output_v_count(output_v_count)
    );

    function automatic logic [2:0] expected_pen(input integer x);
        integer bit_in_group;
        begin
            bit_in_group = x & 3;
            // DERIVED FROM THE GOSPEL, NOT FROM THE RTL.  This function used
            // to be a verbatim copy of gladiator_video.sv's bg_pen expression,
            // so it could only ever confirm the RTL matched itself -- and it
            // passed for the life of the project while the pen order was
            // INVERTED.  MAME's gfx decoder maps planeoffset[0] to the MOST
            // significant pen bit (planebit = 1 << (planes-1-plane)), and
            // tilelayout's planeoffset is { 4, RGN_FRAC(1,2), RGN_FRAC(1,2)+4 }:
            //   plane 0 -> pen[2]: FIRST half,  +4 -> plane0 low nibble
            //   plane 1 -> pen[1]: SECOND half, +0 -> plane12 high nibble
            //   plane 2 -> pen[0]: SECOND half, +4 -> plane12 low nibble
            // Confirmed independently by build_composite_oracle.py, which is
            // validated pixel-exact against MAME's own PNG screenshots.
            expected_pen = {
                bg_plane0_data[3-bit_in_group],
                bg_plane12_data[7-bit_in_group],
                bg_plane12_data[3-bit_in_group]
            };
        end
    endfunction

    task automatic issue_video_x(input integer x);
        begin
            @(negedge clk);
            h_count <= x[8:0];
            pixel_ce <= 1'b1;
            @(posedge clk);
            #1;
            pixel_ce <= 1'b0;
        end
    endtask

    // ------------------------------------------------------------------
    // Sprite bit-order check
    // ------------------------------------------------------------------
    logic sprite_reset = 1;
    logic swap_display = 0;
    logic start_line = 0;
    logic [11:0] sprite_ram_address;
    logic [7:0] sprite_ram_data;
    logic [16:0] sprite_plane0_address, sprite_plane12_address;
    logic [7:0] sprite_plane0_data = 8'b0000_1010;
    logic [7:0] sprite_plane12_data = 8'b1100_0110;
    logic [7:0] display_x = 0;
    logic [9:0] display_palette_index;
    logic sprite_busy;
    logic [15:0] overrun_count;
    logic [7:0] sprite_mem [0:3071];
    integer index;

    always_ff @(posedge clk)
        sprite_ram_data <= sprite_mem[sprite_ram_address];

    gladiator_sprite_line sprite_dut (
        .clk(clk),
        .reset(sprite_reset),
        .start_line(start_line),
        .swap_display(swap_display),
        .target_line(9'd100),
        .sprite_buffer(1'b0),
        .sprite_bank_base(3'd2),
        .flip_screen(1'b0),
        .sprite_ram_address(sprite_ram_address),
        .sprite_ram_data(sprite_ram_data),
        .sprite_plane0_address(sprite_plane0_address),
        .sprite_plane0_data(sprite_plane0_data),
        .sprite_plane12_address(sprite_plane12_address),
        .sprite_plane12_data(sprite_plane12_data),
        .display_x(display_x),
        .display_palette_index(display_palette_index),
        .busy(sprite_busy),
        .overrun_count(overrun_count)
    );

    task automatic pulse_start_line;
        begin
            @(negedge clk);
            start_line <= 1'b1;
            @(negedge clk);
            start_line <= 1'b0;
        end
    endtask

    task automatic wait_sprite_idle;
        integer timeout;
        begin
            timeout = 0;
            while (sprite_busy && timeout < 5000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 5000)
                $fatal(1, "sprite renderer failed to finish");
        end
    endtask

    initial begin
        for (index = 0; index < 3072; index = index + 1)
            sprite_mem[index] = 8'd0;

        // First descriptor: 16x16 sprite at x=0 covering target y=100.
        sprite_mem[12'h000] = 8'h00;
        sprite_mem[12'h001] = 8'h00;
        sprite_mem[12'h400] = 8'd140;
        sprite_mem[12'h401] = 8'd56;
        sprite_mem[12'h800] = 8'h00;
        sprite_mem[12'h801] = 8'h00;

        repeat (4) @(posedge clk);
        video_reset <= 1'b0;
        sprite_reset <= 1'b0;

        text_rom_data <= 8'h00;
        for (index = 0; index < 8; index = index + 1) begin
            issue_video_x(index);
            if (video_dut.selected_palette_index[2:0] !==
                    expected_pen(index))
                $fatal(1, "background bit order wrong at x=%0d: %0d != %0d",
                       index, video_dut.selected_palette_index[2:0],
                       expected_pen(index));
        end

        text_rom_data <= 8'b1010_0101;
        for (index = 0; index < 8; index = index + 1) begin
            issue_video_x(index);
            if (text_rom_data[7-index]) begin
                if (video_dut.selected_palette_index !== 10'h201)
                    $fatal(1, "text MSB-first bit missing at x=%0d", index);
            end else if (video_dut.selected_palette_index[2:0] !==
                         expected_pen(index)) begin
                $fatal(1, "transparent text altered background at x=%0d",
                       index);
            end
        end

        repeat (8) @(posedge clk);
        issue_video_x(123);
        while (!pixel_strobe)
            @(posedge clk);
        #1;
        if (output_h_count != 9'd123 || output_v_count != 9'd16)
            $fatal(1, "rendered coordinate did not track delayed RGB");

        pulse_start_line();
        wait_sprite_idle();
        pulse_start_line();
        for (index = 0; index < 16; index = index + 1) begin
            display_x = index[7:0];
            // The line-buffer read is now REGISTERED (it has to be, for the
            // fitter to infer memory instead of 5,120 discrete registers and a
            // pair of 256:1 muxes). Settle a clock edge before sampling.
            // gladiator_video does the same thing implicitly: display_x only
            // moves on pixel_ce, 16 clocks apart.
            @(posedge clk);
            #1;
            if (display_palette_index !==
                    (expected_pen(index) == 0 ? 10'd0 :
                     10'h100 + expected_pen(index)))
                $fatal(1, "sprite bit order wrong at x=%0d: %03x != %03x",
                       index, display_palette_index,
                       expected_pen(index) == 0 ? 10'd0 :
                       10'h100 + expected_pen(index));
        end
        if (overrun_count != 0)
            $fatal(1, "sprite renderer overran in focused decode test");

        $display("PASS tb_gfx_decode");
        $finish;
    end
endmodule
