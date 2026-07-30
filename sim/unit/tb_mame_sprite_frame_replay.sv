`timescale 1ns/1ps

// Full-frame sprite replay.
//
// tb_mame_sprite_replay compares one scanline of one MAME frame.  This bench
// replays every captured MAME sprite-RAM state and compares all 256 scanlines
// of each resulting image, so a renderer defect that only shows on a sprite
// size, bank, flip, wrap or overlap combination absent from that one line is
// caught.
//
// It also measures the real per-line build cost.  The single-line bench only
// checked overrun_count while restarting the builder after idle, so that
// counter could never increment and the check could never fail.  Here the
// measured worst-case build length is compared against the physical scanline
// budget: 384 board pixels at ce_6m on the 96 MHz master clock.
module tb_mame_sprite_frame_replay;
    localparam int LINE_BUDGET_CYCLES = 384 * 16;

    logic clk = 0;
    always #5 clk = ~clk;

    logic reset = 1;
    logic swap_display = 0;
    logic start_line = 0;
    logic [8:0] target_line = 0;
    logic sprite_buffer = 0;
    logic [2:0] sprite_bank_base = 0;
    logic [11:0] sprite_ram_address;
    logic [7:0] sprite_ram_data;
    logic [16:0] sprite_plane0_address;
    logic [7:0] sprite_plane0_data;
    logic [16:0] sprite_plane12_address;
    logic [7:0] sprite_plane12_data;
    logic [7:0] display_x = 0;
    logic [9:0] display_palette_index;
    logic busy;
    logic [15:0] overrun_count;

    logic [7:0] sprite_ram [0:3071];
    logic [9:0] expected_image [0:65535];

    integer index_file;
    integer frame_count;
    integer frame_limit;
    integer frame_number;
    integer buffer_number;
    integer bank_number;
    integer expected_nonzero;
    integer frame_index;
    integer line;
    integer x;
    integer rom_file;
    integer bytes_read;
    integer mismatches;
    integer frame_mismatches;
    integer observed_nonzero;
    integer max_build_cycles;
    integer build_cycles;
    integer total_lines;
    string  ram_path;
    string  image_path;
    string  frame_dir;
    string  index_path;
    integer buffer0_frames;
    integer buffer1_frames;

    always_ff @(posedge clk)
        sprite_ram_data <= sprite_ram[sprite_ram_address];

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
        .text_address(13'd0),
        .text_data(),
        .bg_plane0_address(16'd0),
        .bg_plane0_data(),
        .bg_plane12_address(16'd0),
        .bg_plane12_data(),
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

    gladiator_sprite_line dut (
        .clk(clk),
        .reset(reset),
        .start_line(start_line),
        .swap_display(swap_display),
        .target_line(target_line),
        .sprite_buffer(sprite_buffer),
        .sprite_bank_base(sprite_bank_base),
        .flip_screen(1'b0),
        .sprite_ram_address(sprite_ram_address),
        .sprite_ram_data(sprite_ram_data),
        .sprite_plane0_address(sprite_plane0_address),
        .sprite_plane0_data(sprite_plane0_data),
        .sprite_plane12_address(sprite_plane12_address),
        .sprite_plane12_data(sprite_plane12_data),
        .display_x(display_x),
        .display_palette_index(display_palette_index),
        .busy(busy),
        .overrun_count(overrun_count)
    );

    task automatic pulse_start;
        begin
            // swap_display pulses one edge BEFORE start_line, mirroring the
            // board where it fires at h==383 and start_line at h==0.
            @(negedge clk);
            swap_display <= 1'b1;
            @(negedge clk);
            swap_display <= 1'b0;
            start_line <= 1'b1;
            @(negedge clk);
            start_line <= 1'b0;
        end
    endtask

    // Measures how long the builder actually holds the line, so the physical
    // scanline budget becomes a gate that can fail.
    task automatic wait_idle;
        begin
            build_cycles = 0;
            while (busy && build_cycles < LINE_BUDGET_CYCLES * 4) begin
                @(posedge clk);
                build_cycles = build_cycles + 1;
            end
            if (build_cycles >= LINE_BUDGET_CYCLES * 4)
                $fatal(1, "sprite builder never returned to idle");
            if (build_cycles > max_build_cycles)
                max_build_cycles = build_cycles;
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
        bytes_read = $fread(roms.bg_p3_rom, rom_file);
        bytes_read = $fread(roms.bg_p12_rom, rom_file);
        bytes_read = $fread(roms.sp_p3_rom, rom_file);
        if (bytes_read != 17'h0c000)
            $fatal(1, "short sprite plane-3 ROM read");
        bytes_read = $fread(roms.sp_p12_rom, rom_file);
        if (bytes_read != 17'h18000)
            $fatal(1, "short sprite plane-1/2 ROM read");
        $fclose(rom_file);

        // The oracle directory is selectable so a capture taken with a
        // different snapshot stride (or a deliberately mutated oracle) can be
        // replayed without disturbing the shared sim/out capture.
        if (!$value$plusargs("FRAMEDIR=%s", frame_dir))
            frame_dir = "sim/out/sprite-frames";
        index_path = $sformatf("%0s/index.txt", frame_dir);
        index_file = $fopen(index_path, "r");
        if (!index_file)
            $fatal(1, "missing sprite frame oracle index %0s", index_path);
        if ($fscanf(index_file, "%d\n", frame_count) != 1 || frame_count < 1)
            $fatal(1, "invalid sprite frame oracle index");

        // Mutation runs only need enough frames to reach a kill; the full
        // sweep leaves this unset and covers every captured frame.
        if ($value$plusargs("FRAMES=%d", frame_limit) && frame_limit > 0 &&
                frame_limit < frame_count)
            frame_count = frame_limit;

        mismatches = 0;
        max_build_cycles = 0;
        total_lines = 0;
        buffer0_frames = 0;
        buffer1_frames = 0;

        for (frame_index = 0; frame_index < frame_count;
                frame_index = frame_index + 1) begin
            if ($fscanf(index_file, "%d %d %d %d\n", frame_number,
                        buffer_number, bank_number, expected_nonzero) != 4)
                $fatal(1, "truncated sprite frame oracle index");

            if (buffer_number == 0)
                buffer0_frames = buffer0_frames + 1;
            else
                buffer1_frames = buffer1_frames + 1;

            ram_path = $sformatf(
                "%0s/frame-%0d-ram.hex", frame_dir, frame_number);
            image_path = $sformatf(
                "%0s/frame-%0d-image.hex", frame_dir, frame_number);
            $readmemh(ram_path, sprite_ram);
            $readmemh(image_path, expected_image);

            sprite_buffer = buffer_number[0];
            sprite_bank_base = bank_number[2:0];

            reset <= 1'b1;
            repeat (4) @(posedge clk);
            reset <= 1'b0;
            @(posedge clk);

            frame_mismatches = 0;
            observed_nonzero = 0;

            for (line = 0; line < 256; line = line + 1) begin
                target_line = line[8:0];
                // Build the line, then start the next build so the completed
                // buffer is the one presented on display_x.
                pulse_start();
                wait_idle();
                pulse_start();

                for (x = 0; x < 256; x = x + 1) begin
                    display_x = x[7:0];
                    @(posedge clk);
                    #1;
                    if (display_palette_index !== expected_image[line * 256 + x])
                    begin
                        if (frame_mismatches < 8)
                            $display(
                                "MISMATCH frame=%0d line=%0d x=%0d RTL=%03x MAME=%03x",
                                frame_number, line, x,
                                display_palette_index,
                                expected_image[line * 256 + x]);
                        frame_mismatches = frame_mismatches + 1;
                    end
                    if (display_palette_index != 10'd0)
                        observed_nonzero = observed_nonzero + 1;
                end

                wait_idle();
                total_lines = total_lines + 1;
            end

            mismatches = mismatches + frame_mismatches;
            if (frame_mismatches == 0 && observed_nonzero != expected_nonzero)
            begin
                $display(
                    "MISMATCH frame=%0d nonzero RTL=%0d MAME=%0d",
                    frame_number, observed_nonzero, expected_nonzero);
                mismatches = mismatches + 1;
            end
            $display(
                "frame %0d: lines=256 pixels=%0d mismatches=%0d",
                frame_number, observed_nonzero, frame_mismatches);
        end
        $fclose(index_file);

        if (max_build_cycles > LINE_BUDGET_CYCLES)
            $fatal(1,
                "sprite builder needs %0d cycles, scanline budget is %0d",
                max_build_cycles, LINE_BUDGET_CYCLES);

        if (mismatches != 0)
            $fatal(1, "MAME sprite frame replay: %0d mismatching pixels",
                   mismatches);

        // Coverage, not correctness: an oracle whose frames are all one
        // sprite_buffer phase cannot exercise the descriptor-half select at
        // all, so a passing run over such a set is not evidence about it.
        $display("MIX sprite_buffer frames: buffer0=%0d buffer1=%0d",
                 buffer0_frames, buffer1_frames);
        if (buffer0_frames == 0 || buffer1_frames == 0) begin
            if ($test$plusargs("REQUIRE_BOTH_BUFFERS"))
                $fatal(1,
                    "sprite_buffer coverage hole: buffer0=%0d buffer1=%0d",
                    buffer0_frames, buffer1_frames);
            $display(
                "WARNING sprite_buffer coverage hole: buffer0=%0d buffer1=%0d",
                buffer0_frames, buffer1_frames);
        end

        $display(
            "PASS tb_mame_sprite_frame_replay frames=%0d lines=%0d buffer0=%0d buffer1=%0d worst_build=%0d/%0d cycles",
            frame_count, total_lines, buffer0_frames, buffer1_frames,
            max_build_cycles, LINE_BUDGET_CYCLES);
        $finish;
    end
endmodule
