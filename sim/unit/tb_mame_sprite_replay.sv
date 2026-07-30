`timescale 1ns/1ps

module tb_mame_sprite_replay;
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
    logic [9:0] expected_line [0:255];
    integer oracle_file;
    integer value;
    integer frame_number;
    integer line_number;
    integer buffer_number;
    integer bank_number;
    integer nonzero_pixels;
    integer rom_file;
    integer bytes_read;
    integer index;

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

    task automatic wait_idle;
        integer timeout;
        begin
            timeout = 0;
            while (busy && timeout < 10000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout == 10000)
                $fatal(1, "MAME sprite replay renderer timed out");
        end
    endtask

    initial begin
        $readmemh("sim/out/mame-sprite-ram.hex", sprite_ram);
        $readmemh("sim/out/mame-sprite-line.hex", expected_line);

        oracle_file = $fopen("sim/out/mame-sprite-oracle.txt", "r");
        if (!oracle_file)
            $fatal(1, "missing MAME sprite oracle metadata");
        if ($fscanf(oracle_file, "frame=%d\n", frame_number) != 1 ||
                $fscanf(oracle_file, "line=%d\n", line_number) != 1 ||
                $fscanf(oracle_file, "sprite_buffer=%d\n",
                        buffer_number) != 1 ||
                $fscanf(oracle_file, "sprite_bank=%d\n", bank_number) != 1 ||
                $fscanf(oracle_file, "nonzero_pixels=%d\n",
                        nonzero_pixels) != 1)
            $fatal(1, "invalid MAME sprite oracle metadata");
        $fclose(oracle_file);

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

        target_line = line_number[8:0];
        sprite_buffer = buffer_number[0];
        sprite_bank_base = bank_number[2:0];
        repeat (4) @(posedge clk);
        reset <= 1'b0;

        pulse_start();
        wait_idle();
        pulse_start();

        value = 0;
        for (index = 0; index < 256; index = index + 1) begin
            display_x = index[7:0];
            @(posedge clk);
            #1;
            if (display_palette_index !== expected_line[index])
                $fatal(
                    1,
                    "MAME sprite replay mismatch frame=%0d line=%0d x=%0d: RTL=%03x MAME=%03x",
                    frame_number,
                    line_number,
                    index,
                    display_palette_index,
                    expected_line[index]
                );
            if (display_palette_index != 0)
                value = value + 1;
        end
        if (value != nonzero_pixels)
            $fatal(
                1,
                "MAME sprite replay nonzero count %0d != %0d",
                value,
                nonzero_pixels
            );
        if (overrun_count != 0)
            $fatal(1, "MAME sprite replay overran line budget");

        $display(
            "PASS tb_mame_sprite_replay frame=%0d line=%0d pixels=%0d",
            frame_number,
            line_number,
            value
        );
        $finish;
    end
endmodule
