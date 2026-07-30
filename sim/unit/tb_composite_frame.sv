`timescale 1ns/1ps

// Full COMPOSITE-frame replay against MAME.
//
// Every other video gate in this tree compares ONE plane.  tb_mame_sprite_
// frame_replay drives gladiator_sprite_line with a bench-local sprite RAM and
// compares the sprite line buffer only; nothing has ever compared what
// gladiator_video.sv actually emits -- background tilemap, sprite plane, fg
// overlay, layer priority and the palette lookup, composited.
//
// This bench instantiates the real raster timing, the real sprite builder, the
// real renderer and the real ROM store, loads one captured MAME hardware state
// into bench copies of the video RAMs (byte-for-byte what gladiator_main_bus
// presents on its video read ports, same one-cycle synchronous latency), runs a
// whole frame, and compares BOTH the selected palette index and the emitted
// rgb555 for all 256x224 visible pixels against scripts/build_composite_oracle.py.
//
// The oracle is not derived from this RTL: it is transcribed from the MAME
// gospel and is separately proven pixel-exact against MAME's own screenshots.
module tb_composite_frame;

    localparam int VIS_Y0 = 16;
    localparam int VIS_Y1 = 239;
    localparam int VIS_PIXELS = 256 * (VIS_Y1 - VIS_Y0 + 1);

    logic clk = 0;
    always #5 clk = ~clk;

    logic reset = 1;

    // Board pixel clock enable: ce_6m on the 96 MHz master clock.
    logic [3:0] ce_divider = 4'd0;
    logic ce_6m;
    always_ff @(posedge clk) begin
        if (reset)
            ce_divider <= 4'd0;
        else
            ce_divider <= ce_divider + 4'd1;
    end
    assign ce_6m = !reset && (ce_divider == 4'd15);

    // ---------------------------------------------------------------------
    // Raster timing (the real board module)
    // ---------------------------------------------------------------------
    logic pixel_ce;
    logic [8:0] board_h, board_v;
    logic board_hblank, board_vblank, board_hsync, board_vsync, vblank_rise;

    gladiator_board_timing timing (
        .clk(clk),
        .reset(reset),
        .ce_6m(ce_6m),
        .mame_60hz(1'b0),
        .pixel_ce(pixel_ce),
        .h_count(board_h),
        .v_count(board_v),
        .hblank(board_hblank),
        .vblank(board_vblank),
        .hsync(board_hsync),
        .vsync(board_vsync),
        .vblank_rise(vblank_rise)
    );

    logic [8:0] next_line;
    always_comb next_line = (board_v == 9'd263) ? 9'd0 : board_v + 9'd1;

    // ---------------------------------------------------------------------
    // Captured MAME state: bench copies of the video-side RAM read ports.
    // gladiator_main_bus.sv presents all of these with one clocked read.
    // ---------------------------------------------------------------------
    logic [7:0] bg_code_ram  [0:2047];
    logic [7:0] bg_attr_ram  [0:2047];
    logic [7:0] fg_code_ram  [0:2047];
    logic [7:0] palette_lo   [0:1023];
    logic [7:0] palette_ex   [0:1023];
    logic [7:0] sprite_ram   [0:3071];

    logic [10:0] video_bg_address;
    logic [10:0] video_fg_address;
    logic [9:0]  video_palette_address;
    logic [11:0] video_sprite_address;
    logic [7:0]  video_bg_code, video_bg_attr, video_fg_code;
    logic [7:0]  video_palette_low, video_palette_ext;
    logic [7:0]  video_sprite_data;

    always_ff @(posedge clk) begin
        video_bg_code     <= bg_code_ram[video_bg_address];
        video_bg_attr     <= bg_attr_ram[video_bg_address];
        video_fg_code     <= fg_code_ram[video_fg_address];
        video_palette_low <= palette_lo[video_palette_address];
        video_palette_ext <= palette_ex[video_palette_address];
        video_sprite_data <= sprite_ram[video_sprite_address];
    end

    // ---------------------------------------------------------------------
    // Video registers replayed from the capture
    // ---------------------------------------------------------------------
    logic [7:0] video_attributes = 8'h00;
    logic [7:0] fg_scrollx = 8'h00, fg_scrolly = 8'h00;
    logic [7:0] bg_scrollx = 8'h00, bg_scrolly = 8'h00;
    logic       flip_screen = 1'b0;
    logic       sprite_buffer = 1'b0;
    logic [2:0] sprite_bank_base = 3'd2;

    // ---------------------------------------------------------------------
    // Graphics ROM store
    // ---------------------------------------------------------------------
    logic [12:0] text_rom_address;
    logic [7:0]  text_rom_data;
    logic [15:0] bg_plane0_address, bg_plane12_address;
    logic [7:0]  bg_plane0_data, bg_plane12_data;
    logic [16:0] sprite_plane0_address, sprite_plane12_address;
    logic [7:0]  sprite_plane0_data, sprite_plane12_data;

    gladiator_roms roms (
        .clk(clk),
        .reset(reset),
        .download_active(1'b0),
        .download_write(1'b0),
        .download_address(20'd0),
        .download_data(8'd0),
        .rom_ready(),
        .main_address(17'd0),
        .main_data(),
        .sound_address(14'd0),
        .sound_data(),
        .adpcm_address(17'd0),
        .adpcm_data(),
        .text_address(text_rom_address),
        .text_data(text_rom_data),
        .bg_plane0_address(bg_plane0_address),
        .bg_plane0_data(bg_plane0_data),
        .bg_plane12_address(bg_plane12_address),
        .bg_plane12_data(bg_plane12_data),
        .sprite_plane0_address(sprite_plane0_address),
        .sprite_plane0_data(sprite_plane0_data),
        .sprite_plane12_address(sprite_plane12_address),
        .sprite_plane12_data(sprite_plane12_data),
        .prom_address(5'd0),
        .prom_q3_data(),
        .prom_q4_data(),
        .cctl_address(10'd0),
        .cctl_raw_data(),
        .ccpu_address(10'd0),
        .ccpu_raw_data(),
        .ucpu_address(10'd0),
        .ucpu_raw_data(),
        .csnd_address(11'd0),
        .csnd_raw_data()
    );

    // ---------------------------------------------------------------------
    // The two devices under test, wired exactly as gladiator_board.sv wires
    // them.
    // ---------------------------------------------------------------------
    logic [9:0] sprite_palette_index;
    logic sprite_builder_busy;
    logic [15:0] sprite_overruns;

    gladiator_sprite_line sprite_line (
        .clk(clk),
        .reset(reset),
        .start_line(pixel_ce && board_h == 9'd0),
        .swap_display(pixel_ce && board_h == 9'd383),
        .target_line(next_line),
        .sprite_buffer(sprite_buffer),
        .sprite_bank_base(sprite_bank_base),
        .flip_screen(flip_screen),
        .sprite_ram_address(video_sprite_address),
        .sprite_ram_data(video_sprite_data),
        .sprite_plane0_address(sprite_plane0_address),
        .sprite_plane0_data(sprite_plane0_data),
        .sprite_plane12_address(sprite_plane12_address),
        .sprite_plane12_data(sprite_plane12_data),
        .display_x(board_h[7:0]),
        .display_palette_index(sprite_palette_index),
        .busy(sprite_builder_busy),
        .overrun_count(sprite_overruns)
    );

    logic [14:0] rgb555;
    logic hblank, vblank, hsync, vsync, renderer_valid, pixel_strobe;
    logic [8:0] rendered_h, rendered_v;

    gladiator_video video (
        .clk(clk),
        .reset(reset),
        .pixel_ce(pixel_ce),
        .h_count(board_h),
        .v_count(board_v),
        .hblank_in(board_hblank),
        .vblank_in(board_vblank),
        .hsync_in(board_hsync),
        .vsync_in(board_vsync),
        .flip_screen(flip_screen),
        .fg_scrolly(fg_scrolly),
        .fg_scrollx(fg_scrollx),
        .bg_scrolly(bg_scrolly),
        .bg_scrollx(bg_scrollx),
        .video_attributes(video_attributes),
        .video_bg_address(video_bg_address),
        .video_bg_code(video_bg_code),
        .video_bg_attr(video_bg_attr),
        .video_fg_address(video_fg_address),
        .video_fg_code(video_fg_code),
        .video_palette_address(video_palette_address),
        .video_palette_low(video_palette_low),
        .video_palette_ext(video_palette_ext),
        .text_rom_address(text_rom_address),
        .text_rom_data(text_rom_data),
        .bg_plane0_address(bg_plane0_address),
        .bg_plane0_data(bg_plane0_data),
        .bg_plane12_address(bg_plane12_address),
        .bg_plane12_data(bg_plane12_data),
        .sprite_palette_index(sprite_palette_index),
        .rgb555(rgb555),
        .hblank(hblank),
        .vblank(vblank),
        .hsync(hsync),
        .vsync(vsync),
        .valid_pixel(renderer_valid),
        .pixel_strobe(pixel_strobe),
        .output_h_count(rendered_h),
        .output_v_count(rendered_v)
    );

    // ---------------------------------------------------------------------
    // Capture.  video_palette_address is combinational; it is valid for the
    // pixel in flight on the cycle the palette RAM samples it, which is the
    // cycle pipeline_valid_1 is asserted.  rgb555/output_h/output_v are
    // registered one stage later and are stable when pixel_strobe fires.
    // ---------------------------------------------------------------------
    logic [9:0] palette_index_q;
    logic capture_enable = 1'b0;

    logic [14:0] captured_rgb [0:VIS_PIXELS-1];
    logic [9:0]  captured_idx [0:VIS_PIXELS-1];
    logic        captured_seen [0:VIS_PIXELS-1];
    integer      captured_count;

    logic [14:0] expected_rgb [0:VIS_PIXELS-1];
    logic [9:0]  expected_idx [0:VIS_PIXELS-1];

    integer slot;

    always_ff @(posedge clk) begin
        if (video.pipeline_valid_1)
            palette_index_q <= video_palette_address;
        if (capture_enable && pixel_strobe &&
                rendered_h < 9'd256 &&
                rendered_v >= VIS_Y0[8:0] && rendered_v <= VIS_Y1[8:0]) begin
            slot = (rendered_v - VIS_Y0) * 256 + rendered_h;
            captured_rgb[slot]  <= rgb555;
            captured_idx[slot]  <= palette_index_q;
            captured_seen[slot] <= 1'b1;
            captured_count      <= captured_count + 1;
        end
    end

    // ---------------------------------------------------------------------
    integer index_file, rom_file, bytes_read;
    integer frame_count, frame_limit, frame_index, start_index, skip_index;
    integer frame_number, attributes_in, fgx, fgy, bgx, bgy;
    integer flip_in, buffer_in, bank_in, distinct_in;
    integer mismatches, frame_mismatches, idx_mismatches, rgb_mismatches;
    integer total_mismatches, total_pixels, missing;
    integer pixel, expected_sprite, observed_sprite;
    string  frame_dir, index_path, path;

    task automatic run_frame;
        begin
            // Reset restarts the raster at (h=0, v=0).  The sprite builder
            // fills the line-1 buffer during line 0, so every compared line
            // (v >= 16) is presented from a completed build.
            reset <= 1'b1;
            repeat (8) @(posedge clk);
            reset <= 1'b0;
            @(posedge clk);

            // Arm at the first pixel of the frame.
            do @(posedge clk);
            while (!(pixel_ce && board_h == 9'd0 && board_v == 9'd0));
            capture_enable <= 1'b1;

            // Run until the visible region has fully drained out of the
            // renderer pipeline.
            do @(posedge clk);
            while (!(pixel_ce && board_h == 9'd8 && board_v == 9'd240));
            capture_enable <= 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        rom_file = $fopen("sim/out/gladiatr.rom", "rb");
        if (!rom_file)
            $fatal(1, "missing sim/out/gladiatr.rom");
        bytes_read = $fread(roms.main_rom, rom_file);
        bytes_read = $fread(roms.sound_rom, rom_file);
        bytes_read = $fread(roms.adpcm_rom, rom_file);
        bytes_read = $fread(roms.text_rom, rom_file);
        if (bytes_read != 32'h2000)
            $fatal(1, "short text ROM read");
        bytes_read = $fread(roms.bg_p3_rom, rom_file);
        if (bytes_read != 16'h8000)
            $fatal(1, "short background plane-3 ROM read");
        bytes_read = $fread(roms.bg_p12_rom, rom_file);
        if (bytes_read != 17'h10000)
            $fatal(1, "short background plane-1/2 ROM read");
        bytes_read = $fread(roms.sp_p3_rom, rom_file);
        if (bytes_read != 17'h0c000)
            $fatal(1, "short sprite plane-3 ROM read");
        bytes_read = $fread(roms.sp_p12_rom, rom_file);
        if (bytes_read != 17'h18000)
            $fatal(1, "short sprite plane-1/2 ROM read");
        $fclose(rom_file);

        if (!$value$plusargs("FRAMEDIR=%s", frame_dir))
            frame_dir = "sim/out/composite-frames";
        index_path = $sformatf("%0s/index.txt", frame_dir);
        index_file = $fopen(index_path, "r");
        if (!index_file)
            $fatal(1, "missing composite oracle index %0s", index_path);
        if ($fscanf(index_file, "%d\n", frame_count) != 1 || frame_count < 1)
            $fatal(1, "invalid composite oracle index");
        if ($value$plusargs("FRAMES=%d", frame_limit) && frame_limit > 0 &&
                frame_limit < frame_count)
            frame_count = frame_limit;
        if (!$value$plusargs("START_INDEX=%d", start_index))
            start_index = 0;
        if (start_index < 0 || start_index >= frame_count)
            $fatal(1, "START_INDEX %0d outside 0..%0d",
                start_index, frame_count - 1);

        // Allows a long exhaustive gate to be sharded without regenerating or
        // weakening the oracle. The skipped index records are consumed only;
        // each shard still runs complete frames through the production RTL.
        for (skip_index = 0; skip_index < start_index;
                skip_index = skip_index + 1) begin
            if ($fscanf(index_file, "%d %d %d %d %d %d %d %d %d %d\n",
                        frame_number, attributes_in, fgx, fgy, bgx, bgy,
                        flip_in, buffer_in, bank_in, distinct_in) != 10)
                $fatal(1, "truncated composite oracle index while skipping");
        end

        total_mismatches = 0;
        total_pixels = 0;

        for (frame_index = start_index; frame_index < frame_count;
                frame_index = frame_index + 1) begin
            if ($fscanf(index_file, "%d %d %d %d %d %d %d %d %d %d\n",
                        frame_number, attributes_in, fgx, fgy, bgx, bgy,
                        flip_in, buffer_in, bank_in, distinct_in) != 10)
                $fatal(1, "truncated composite oracle index");
            if (flip_in != 0)
                $fatal(1, "frame %0d is flipped; oracle scope is normal orientation", frame_number);

            path = $sformatf("%0s/frame-%0d-bgcode.hex", frame_dir, frame_number);
            $readmemh(path, bg_code_ram);
            path = $sformatf("%0s/frame-%0d-bgattr.hex", frame_dir, frame_number);
            $readmemh(path, bg_attr_ram);
            path = $sformatf("%0s/frame-%0d-fgcode.hex", frame_dir, frame_number);
            $readmemh(path, fg_code_ram);
            path = $sformatf("%0s/frame-%0d-pallo.hex", frame_dir, frame_number);
            $readmemh(path, palette_lo);
            path = $sformatf("%0s/frame-%0d-palex.hex", frame_dir, frame_number);
            $readmemh(path, palette_ex);
            path = $sformatf("%0s/frame-%0d-sprite.hex", frame_dir, frame_number);
            $readmemh(path, sprite_ram);
            path = $sformatf("%0s/frame-%0d-idx.hex", frame_dir, frame_number);
            $readmemh(path, expected_idx);
            path = $sformatf("%0s/frame-%0d-rgb.hex", frame_dir, frame_number);
            $readmemh(path, expected_rgb);

            video_attributes = attributes_in[7:0];
            fg_scrollx = fgx[7:0];
            fg_scrolly = fgy[7:0];
            bg_scrollx = bgx[7:0];
            bg_scrolly = bgy[7:0];
            flip_screen = 1'b0;
            sprite_buffer = buffer_in[0];
            sprite_bank_base = bank_in[2:0];

            for (pixel = 0; pixel < VIS_PIXELS; pixel = pixel + 1) begin
                captured_seen[pixel] = 1'b0;
                captured_rgb[pixel] = 15'h7fff;
                captured_idx[pixel] = 10'h3ff;
            end
            captured_count = 0;

            run_frame();

            frame_mismatches = 0;
            idx_mismatches = 0;
            rgb_mismatches = 0;
            missing = 0;
            expected_sprite = 0;
            observed_sprite = 0;
            for (pixel = 0; pixel < VIS_PIXELS; pixel = pixel + 1) begin
                if (!captured_seen[pixel])
                    missing = missing + 1;
                else begin
                if (expected_idx[pixel] >= 10'h100 &&
                        expected_idx[pixel] < 10'h200)
                    expected_sprite = expected_sprite + 1;
                if (captured_idx[pixel] >= 10'h100 &&
                        captured_idx[pixel] < 10'h200)
                    observed_sprite = observed_sprite + 1;
                if (captured_idx[pixel] !== expected_idx[pixel]) begin
                    idx_mismatches = idx_mismatches + 1;
                    if (frame_mismatches < 40000)
                        $display(
                            "MISMATCH frame=%0d x=%0d y=%0d index RTL=%03x MAME=%03x",
                            frame_number, pixel % 256, (pixel / 256) + VIS_Y0,
                            captured_idx[pixel], expected_idx[pixel]);
                    frame_mismatches = frame_mismatches + 1;
                end
                if (captured_rgb[pixel] !== expected_rgb[pixel]) begin
                    rgb_mismatches = rgb_mismatches + 1;
                    if (frame_mismatches < 6)
                        $display(
                            "MISMATCH frame=%0d x=%0d y=%0d rgb555 RTL=%04x MAME=%04x",
                            frame_number, pixel % 256, (pixel / 256) + VIS_Y0,
                            captured_rgb[pixel], expected_rgb[pixel]);
                    frame_mismatches = frame_mismatches + 1;
                end
                end
            end

            if (missing != 0)
                $fatal(1,
                    "frame %0d: renderer emitted only %0d of %0d visible pixels",
                    frame_number, VIS_PIXELS - missing, VIS_PIXELS);
            if (sprite_overruns != 16'd0)
                $fatal(1, "frame %0d: sprite builder overran %0d lines",
                    frame_number, sprite_overruns);

            $display(
                "frame %0d: pixels=%0d index_mismatches=%0d rgb_mismatches=%0d sprite_pixels RTL=%0d MAME=%0d",
                frame_number, VIS_PIXELS, idx_mismatches, rgb_mismatches,
                observed_sprite, expected_sprite);

            total_mismatches = total_mismatches + idx_mismatches +
                               rgb_mismatches;
            total_pixels = total_pixels + VIS_PIXELS;
        end
        $fclose(index_file);

        if (total_mismatches != 0) begin
            $display(
                "FAIL composite frame replay: %0d mismatches over %0d frames / %0d pixels",
                total_mismatches, frame_count - start_index, total_pixels);
            $fatal(1, "composite frame replay diverged from MAME");
        end
        $display(
            "PASS composite frame replay: %0d frames, %0d pixels, palette index and rgb555 exact",
            frame_count - start_index, total_pixels);
        $finish;
    end

endmodule
