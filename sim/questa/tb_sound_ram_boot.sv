`timescale 1ns/1ps

module tb_sound_ram_boot;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [2:0] divider = 3'd0;
    wire ce_3m = &divider[1:0];

    always #5.208 clk = ~clk;
    always_ff @(posedge clk) begin
        if (reset)
            divider <= 3'd0;
        else
            divider <= divider + 3'd1;
    end

    logic [7:0] sound_rom [0:16'h3fff];
    logic [7:0] sound_rom_data = 8'h00;
    logic [13:0] sound_rom_address;
    logic sound_m1_n;
    logic sound_mreq_n;
    logic sound_iorq_n;
    logic sound_rd_n;
    logic sound_wr_n;
    logic [15:0] sound_address;
    logic [7:0] sound_data_in;
    logic [7:0] sound_data_out;
    logic [211:0] sound_registers;

    always_ff @(posedge clk)
        sound_rom_data <= sound_rom[sound_rom_address];

    T80s sound_cpu (
        .RESET_n (!reset),
        .CLK     (clk),
        .CEN     (ce_3m),
        .WAIT_n  (1'b1),
        .INT_n   (1'b1),
        .NMI_n   (1'b1),
        .BUSRQ_n (1'b1),
        .M1_n    (sound_m1_n),
        .MREQ_n  (sound_mreq_n),
        .IORQ_n  (sound_iorq_n),
        .RD_n    (sound_rd_n),
        .WR_n    (sound_wr_n),
        .RFSH_n  (),
        .HALT_n  (),
        .BUSAK_n (),
        .OUT0    (1'b0),
        .A       (sound_address),
        .DI      (sound_data_in),
        .DO      (sound_data_out),
        .REG     (sound_registers)
    );

    gladiator_sound_bus sound_bus (
        .clk            (clk),
        .reset          (reset),
        .cpu_address    (sound_address),
        .cpu_data_out   (sound_data_out),
        .cpu_data_in    (sound_data_in),
        .cpu_m1_n       (sound_m1_n),
        .cpu_mreq_n     (sound_mreq_n),
        .cpu_iorq_n     (sound_iorq_n),
        .cpu_rd_n       (sound_rd_n),
        .cpu_wr_n       (sound_wr_n),
        .rom_address    (sound_rom_address),
        .rom_data       (sound_rom_data),
        .interrupt_ack  (),
        .ym_cs_n        (),
        .ym_address     (),
        .ym_wr_n        (),
        .ym_data_out    (),
        .ym_data_in     (8'h00),
        .csnd_cs_n      (),
        .csnd_a0        (),
        .csnd_rd_n      (),
        .csnd_wr_n      (),
        .csnd_data_out  (),
        .csnd_data_in   (8'h0d),
        .cctl_cs_n      (),
        .cctl_a0        (),
        .cctl_rd_n      (),
        .cctl_wr_n      (),
        .cctl_data_out  (),
        .cctl_data_in   (8'h00),
        .ccpu_cs_n      (),
        .ccpu_a0        (),
        .ccpu_rd_n      (),
        .ccpu_wr_n      (),
        .ccpu_data_out  (),
        .ccpu_data_in   (8'h00),
        .command_write  (),
        .command_data   (),
        .sound_command_write(),
        .sound_command_data(),
        .filter_latch   (),
        .trace_mem_read (),
        .trace_mem_write(),
        .trace_io_read  (),
        .trace_io_write ()
    );

    integer rom_file;
    integer seek_result;
    integer bytes_read;
    integer cycles;
    logic reached_post_ram = 1'b0;
    logic reached_ram_error = 1'b0;

    always_ff @(posedge clk) begin
        if (!reset && !sound_m1_n && !sound_mreq_n && !sound_rd_n) begin
            if (sound_address == 16'h009e)
                reached_post_ram <= 1'b1;
            if (sound_address == 16'h0a10)
                reached_ram_error <= 1'b1;
        end
    end

    initial begin
        rom_file = $fopen("sim/out/gladiatr.rom", "rb");
        if (!rom_file)
            $fatal(1, "missing sim/out/gladiatr.rom");
        seek_result = $fseek(rom_file, 20'h12000, 0);
        bytes_read = $fread(sound_rom, rom_file);
        $fclose(rom_file);
        if (seek_result != 0 || bytes_read != 16'h4000)
            $fatal(1, "cannot load sound ROM");

        repeat (64) @(posedge clk);
        reset = 1'b0;

        begin : wait_for_result
            for (cycles = 0; cycles < 8000000; cycles = cycles + 1) begin
                @(posedge clk);
                if (reached_post_ram || reached_ram_error)
                    disable wait_for_result;
            end
            $fatal(1, "sound RAM test timed out PC=%04x bus=%04x",
                   sound_registers[79:64], sound_address);
        end

        if (reached_ram_error)
            $fatal(1, "sound RAM test took MAME failure PC 0A10; PC=%04x bus=%04x",
                   sound_registers[79:64], sound_address);
        $display("PASS tb_sound_ram_boot reached PC 009E");
        $finish;
    end
endmodule
