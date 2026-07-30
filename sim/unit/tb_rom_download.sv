`timescale 1ns/1ps

// Replays the exact index 0 byte stream over the same address/data/write
// interface used by hps_io.  This prevents direct $fread tests from hiding
// loader decode, final-address, or post-ROM reset defects.
module tb_rom_download;
    localparam integer PACK_SIZE = 20'h6d440;

    logic clk = 0;
    always #5 clk = ~clk;

    logic reset = 1;
    logic download_active = 0;
    logic download_write = 0;
    logic [19:0] download_address = 0;
    logic [7:0] download_data = 0;
    logic rom_ready;

    logic [16:0] main_address = 0;
    logic [7:0] main_data;
    logic [13:0] sound_address = 0;
    logic [7:0] sound_data;
    logic [16:0] adpcm_address = 0;
    logic [7:0] adpcm_data;
    logic [12:0] text_address = 0;
    logic [7:0] text_data;
    logic [15:0] bg_plane0_address = 0;
    logic [7:0] bg_plane0_data;
    logic [15:0] bg_plane12_address = 0;
    logic [7:0] bg_plane12_data;
    logic [16:0] sprite_plane0_address = 0;
    logic [7:0] sprite_plane0_data;
    logic [16:0] sprite_plane12_address = 0;
    logic [7:0] sprite_plane12_data;
    logic [4:0] prom_address = 0;
    logic [7:0] prom_q3_data, prom_q4_data;
    logic [9:0] cctl_address = 0;
    logic [7:0] cctl_raw_data;
    logic [9:0] ccpu_address = 0;
    logic [7:0] ccpu_raw_data;
    logic [9:0] ucpu_address = 0;
    logic [7:0] ucpu_raw_data;
    logic [10:0] csnd_address = 0;
    logic [7:0] csnd_raw_data;

    logic [7:0] pack [0:PACK_SIZE-1];
    integer rom_file;
    integer bytes_read;
    integer index;

    gladiator_roms dut (.*);

    task automatic settle;
        begin
            repeat (2) @(posedge clk);
            #1;
        end
    endtask

    task automatic expect8(
        input logic [7:0] actual,
        input logic [7:0] expected,
        input string name
    );
        begin
            if (actual !== expected)
                $fatal(1, "%s: got %02x expected %02x",
                       name, actual, expected);
        end
    endtask

    initial begin
        rom_file = $fopen("sim/out/gladiatr.rom", "rb");
        if (!rom_file)
            $fatal(1, "missing sim/out/gladiatr.rom");
        bytes_read = $fread(pack, rom_file);
        $fclose(rom_file);
        if (bytes_read != PACK_SIZE)
            $fatal(1, "ROM pack read %0d bytes, expected %0d",
                   bytes_read, PACK_SIZE);

        repeat (3) @(posedge clk);
        reset = 0;
        @(negedge clk);
        download_active = 1;
        download_write = 1;
        for (index = 0; index < PACK_SIZE; index = index + 1) begin
            download_address = index[19:0];
            download_data = pack[index];
            @(negedge clk);
        end
        download_write = 0;
        download_active = 0;
        settle();

        if (rom_ready !== 1'b1)
            $fatal(1, "serial index 0 stream did not set rom_ready");

        main_address = 17'h00000;
        sound_address = 14'h0000;
        adpcm_address = 17'h00000;
        text_address = 13'h0000;
        prom_address = 5'h00;
        cctl_address = 10'h000;
        ccpu_address = 10'h000;
        ucpu_address = 10'h000;
        csnd_address = 11'h000;
        settle();

        expect8(main_data, pack[20'h00000], "main stream start");
        expect8(sound_data, pack[20'h12000], "sound stream start");
        expect8(adpcm_data, pack[20'h16000], "6809 stream start");
        expect8(text_data, pack[20'h2e000], "text stream start");
        expect8(prom_q3_data, pack[20'h6c000], "Q3 PROM stream start");
        expect8(prom_q4_data, pack[20'h6c020], "Q4 PROM stream start");
        expect8(cctl_raw_data, pack[20'h6c040], "CCTL stream start");
        expect8(ccpu_raw_data, pack[20'h6c440], "CCPU stream start");
        expect8(ucpu_raw_data, pack[20'h6c840], "UCPU stream start");
        expect8(csnd_raw_data, pack[20'h6cc40], "CSND stream start");

        reset = 1;
        repeat (3) @(posedge clk);
        #1;
        if (rom_ready !== 1'b1)
            $fatal(1, "post-ROM NVRAM reset cleared rom_ready");

        $display("PASS tb_rom_download (%0d serial bytes)", PACK_SIZE);
        $finish;
    end
endmodule
