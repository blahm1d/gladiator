`timescale 1ns/1ps

module tb_rom_map;
    logic clk = 0;
    always #5 clk = ~clk;

    logic reset = 1;
    logic download_active = 0;
    logic download_write = 0;
    logic [19:0] download_address;
    logic [7:0] download_data;
    logic rom_ready;

    logic [16:0] main_address;
    logic [7:0] main_data;
    logic [13:0] sound_address;
    logic [7:0] sound_data;
    logic [16:0] adpcm_address;
    logic [7:0] adpcm_data;
    logic [12:0] text_address;
    logic [7:0] text_data;
    logic [15:0] bg_plane0_address;
    logic [7:0] bg_plane0_data;
    logic [15:0] bg_plane12_address;
    logic [7:0] bg_plane12_data;
    logic [16:0] sprite_plane0_address;
    logic [7:0] sprite_plane0_data;
    logic [16:0] sprite_plane12_address;
    logic [7:0] sprite_plane12_data;
    logic [4:0] prom_address;
    logic [7:0] prom_q3_data, prom_q4_data;
    logic [9:0] cctl_address, ccpu_address, ucpu_address;
    logic [10:0] csnd_address;
    logic [7:0] cctl_raw_data, ccpu_raw_data, ucpu_raw_data, csnd_raw_data;

    gladiator_roms dut (.*);

    task automatic put(input logic [19:0] a, input logic [7:0] d);
        begin
            @(negedge clk);
            download_address = a;
            download_data = d;
            download_write = 1;
            @(negedge clk);
            download_write = 0;
        end
    endtask

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
            if (actual !== expected) begin
                $error("%s: got %02x expected %02x", name, actual, expected);
                $fatal(1);
            end
        end
    endtask

    initial begin
        main_address = 0;
        sound_address = 0;
        adpcm_address = 0;
        text_address = 0;
        bg_plane0_address = 0;
        bg_plane12_address = 0;
        sprite_plane0_address = 0;
        sprite_plane12_address = 0;
        prom_address = 0;
        cctl_address = 0;
        ccpu_address = 0;
        ucpu_address = 0;
        csnd_address = 0;

        repeat (3) @(posedge clk);
        reset = 0;
        download_active = 1;

        put(20'h00010, 8'h11);
        put(20'h12020, 8'h22);
        put(20'h16030, 8'h33);
        put(20'h2e040, 8'h44);

        // BG packed plane 3: physical block 1, byte 0x345.
        put(20'h32345, 8'hab);
        // BG plane 1/2: pre-swap 0x14001 -> final 0x18001.
        put(20'h3c001, 8'h5a);

        // Sprite packed plane 3: physical block 4, byte 0x123.
        put(20'h50123, 8'hc7);
        // Sprite plane 1/2: original relative block 8 becomes final block 5.
        put(20'h64123, 8'h9d);

        put(20'h6c003, 8'h66);
        put(20'h6c023, 8'h77);
        put(20'h6c045, 8'h88);
        put(20'h6c446, 8'h99);
        put(20'h6c847, 8'haa);
        put(20'h6cc48, 8'hbb);
        put(20'h6d43f, 8'hcc);

        main_address = 17'h10;
        sound_address = 14'h20;
        adpcm_address = 17'h30;
        text_address = 13'h40;
        bg_plane0_address = 16'h4345;
        bg_plane12_address = 16'h8001;
        sprite_plane0_address = 17'h10123;
        sprite_plane12_address = 17'h0a123;
        prom_address = 5'h03;
        cctl_address = 10'h005;
        ccpu_address = 10'h006;
        ucpu_address = 10'h007;
        csnd_address = 11'h008;
        settle();

        expect8(main_data, 8'h11, "main");
        expect8(sound_data, 8'h22, "sound");
        expect8(adpcm_data, 8'h33, "adpcm");
        expect8(text_data, 8'h44, "text");
        expect8(bg_plane0_data, 8'hab, "bg plane 3 even");
        expect8(bg_plane12_data, 8'h5a, "bg plane 1/2 permutation");
        expect8(sprite_plane0_data, 8'hc7, "sprite plane 3 even");
        expect8(sprite_plane12_data, 8'h9d, "sprite plane 1/2 permutation");
        expect8(prom_q3_data, 8'h66, "prom q3");
        expect8(prom_q4_data, 8'h77, "prom q4");
        expect8(cctl_raw_data, 8'h88, "cctl");
        expect8(ccpu_raw_data, 8'h99, "ccpu");
        expect8(ucpu_raw_data, 8'haa, "ucpu");
        expect8(csnd_raw_data, 8'hbb, "csnd");

        bg_plane0_address = 16'h6345;
        sprite_plane0_address = 17'h12123;
        settle();
        expect8(bg_plane0_data, 8'h0a, "bg packed high nibble");
        expect8(sprite_plane0_data, 8'h0c, "sprite packed high nibble");

        // Reproduce MiSTer's actual transaction order: ROM index 0 ends,
        // then an index 2 NVRAM transfer holds the board in reset.  ROM
        // completion must survive that later appliance reset.
        @(negedge clk);
        download_active = 0;
        settle();
        if (rom_ready !== 1'b1)
            $fatal(1, "complete index 0 download did not set rom_ready");

        reset = 1;
        repeat (3) @(posedge clk);
        #1;
        if (rom_ready !== 1'b1)
            $fatal(1, "index 2 reset incorrectly cleared rom_ready");
        reset = 0;

        // A new index 0 transaction is the only event that invalidates the
        // preceding ROM image.
        @(negedge clk);
        download_active = 1;
        settle();
        if (rom_ready !== 1'b0)
            $fatal(1, "new index 0 download did not clear rom_ready");

        $display("PASS tb_rom_map");
        $finish;
    end
endmodule
