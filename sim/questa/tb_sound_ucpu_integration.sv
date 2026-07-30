`timescale 1ns/1ps

module tb_sound_ucpu_integration;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [13:0] divider = 14'd0;
    // Accelerate every clock domain by 16 while retaining the board ratios:
    // sound Z80 3 MHz, UPI crystal 6 MHz, TCLK 5,859.375 Hz.
    wire ce_6m = 1'b1;
    wire ce_3m = divider[0];
    wire tclk = divider[9];

    always #5.208 clk = ~clk;
    always_ff @(posedge clk) begin
        if (reset)
            divider <= 14'd0;
        else
            divider <= divider + 14'd1;
    end

    logic [7:0] sound_rom [0:16'h3fff];
    logic [7:0] ucpu_rom [0:10'h3ff];
    logic [7:0] csnd_rom [0:11'h7ff];
    logic [7:0] sound_rom_data = 8'h00;
    logic [7:0] ucpu_rom_data = 8'h00;
    logic [7:0] csnd_rom_data = 8'h00;
    logic [13:0] sound_rom_address;
    logic [10:0] ucpu_program_address;
    logic [10:0] csnd_program_address;
    wire [9:0] ucpu_rom_address = ucpu_program_address[9:0];
    logic [10:0] csnd_rom_address;

    always_ff @(posedge clk) begin
        sound_rom_data <= sound_rom[sound_rom_address];
        ucpu_rom_data <= ucpu_rom[ucpu_rom_address];
        csnd_rom_data <= csnd_rom[csnd_rom_address];
    end

    logic sound_m1_n;
    logic sound_mreq_n;
    logic sound_iorq_n;
    logic sound_rd_n;
    logic sound_wr_n;
    logic [15:0] sound_address;
    logic [7:0] sound_data_in;
    logic [7:0] sound_data_out;
    logic [211:0] sound_registers;

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

    logic ym_cs_n;
    logic ym_address;
    logic ym_wr_n;
    logic [7:0] ym_data_out;
    logic [7:0] ym_register = 8'h00;
    logic [7:0] ym_port_a = 8'h00;

    // The boot path only needs the YM2203 register interface and PSG port A.
    // Register 0x0E releases CCTL/CCPU exactly as the physical board does.
    always_ff @(posedge clk) begin
        if (reset) begin
            ym_register <= 8'h00;
            ym_port_a <= 8'h00;
        end else if (!ym_cs_n && !ym_wr_n) begin
            if (!ym_address)
                ym_register <= ym_data_out;
            else if (ym_register == 8'h0e)
                ym_port_a <= ym_data_out;
        end
    end

    logic csnd_cs_n;
    logic csnd_a0;
    logic csnd_rd_n;
    logic csnd_wr_n;
    logic [7:0] csnd_host_out;
    logic [7:0] csnd_host_in;
    logic cctl_cs_n;
    logic cctl_a0;
    logic cctl_rd_n;
    logic cctl_wr_n;
    logic [7:0] cctl_host_out;
    logic [7:0] cctl_host_in = 8'h01;
    logic ccpu_cs_n;
    logic ccpu_a0;
    logic ccpu_rd_n;
    logic ccpu_wr_n;
    logic [7:0] ccpu_host_out;
    logic [7:0] ccpu_host_in = 8'h01;

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
        .ym_cs_n        (ym_cs_n),
        .ym_address     (ym_address),
        .ym_wr_n        (ym_wr_n),
        .ym_data_out    (ym_data_out),
        .ym_data_in     (8'h00),
        .csnd_cs_n      (csnd_cs_n),
        .csnd_a0        (csnd_a0),
        .csnd_rd_n      (csnd_rd_n),
        .csnd_wr_n      (csnd_wr_n),
        .csnd_data_out  (csnd_host_out),
        .csnd_data_in   (csnd_host_in),
        .cctl_cs_n      (cctl_cs_n),
        .cctl_a0        (cctl_a0),
        .cctl_rd_n      (cctl_rd_n),
        .cctl_wr_n      (cctl_wr_n),
        .cctl_data_out  (cctl_host_out),
        .cctl_data_in   (cctl_host_in),
        .ccpu_cs_n      (ccpu_cs_n),
        .ccpu_a0        (ccpu_a0),
        .ccpu_rd_n      (ccpu_rd_n),
        .ccpu_wr_n      (ccpu_wr_n),
        .ccpu_data_out  (ccpu_host_out),
        .ccpu_data_in   (ccpu_host_in),
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

    logic ucpu_a0 = 1'b0;
    logic ucpu_cs_n = 1'b1;
    logic ucpu_rd_n = 1'b1;
    logic ucpu_wr_n = 1'b1;
    logic [7:0] ucpu_host_data_in = 8'hff;
    logic [7:0] ucpu_host_data_out;
    logic [7:0] ucpu_p1_out;
    logic [7:0] csnd_p1_out;

    // CCTL and CCPU are independent of the UCPU/CSND serial link under test.
    // Replaying their observed MAME host behavior lets this test retain the
    // real sound program and bus without spending simulation time on two
    // unrelated UPI cores.
    logic [3:0] cctl_phase = 4'd0;
    logic [3:0] ccpu_phase = 4'd0;
    integer cctl_status_reads = 0;
    integer ccpu_status_reads = 0;
    logic previous_cctl_read = 1'b0;
    logic previous_cctl_write = 1'b0;
    logic previous_ccpu_read = 1'b0;
    logic previous_ccpu_write = 1'b0;

    always_ff @(posedge clk) begin
        previous_cctl_read <= !cctl_cs_n && !cctl_rd_n;
        previous_cctl_write <= !cctl_cs_n && !cctl_wr_n;
        previous_ccpu_read <= !ccpu_cs_n && !ccpu_rd_n;
        previous_ccpu_write <= !ccpu_cs_n && !ccpu_wr_n;

        if (reset || !ym_port_a[7]) begin
            cctl_phase <= 4'd0;
            ccpu_phase <= 4'd0;
            cctl_status_reads <= 0;
            ccpu_status_reads <= 0;
            cctl_host_in <= 8'h01;
            ccpu_host_in <= 8'h01;
        end else begin
            if (!cctl_cs_n && !cctl_rd_n && !previous_cctl_read) begin
                if (!cctl_a0)
                    cctl_host_in <= (cctl_phase == 4'd6) ?
                                    8'h48 : 8'h00;
                else begin
                    case (cctl_phase)
                        4'd2: begin
                            cctl_host_in <= (cctl_status_reads < 12) ?
                                            8'h0b : 8'h09;
                            cctl_status_reads <= cctl_status_reads + 1;
                        end
                        4'd3, 4'd4: cctl_host_in <= 8'h09;
                        4'd6: begin
                            cctl_host_in <= (cctl_status_reads < 2) ?
                                            8'h0a : 8'h0b;
                            cctl_status_reads <= cctl_status_reads + 1;
                        end
                        default: cctl_host_in <= 8'h01;
                    endcase
                end
            end

            if (!ccpu_cs_n && !ccpu_rd_n && !previous_ccpu_read) begin
                if (!ccpu_a0)
                    ccpu_host_in <= 8'h00;
                else begin
                    case (ccpu_phase)
                        4'd2: begin
                            ccpu_host_in <= (ccpu_status_reads < 11) ?
                                            8'h0b : 8'h09;
                            ccpu_status_reads <= ccpu_status_reads + 1;
                        end
                        default: ccpu_host_in <= 8'h01;
                    endcase
                end
            end

            if (!cctl_cs_n && !cctl_wr_n && !previous_cctl_write) begin
                case (cctl_phase)
                    4'd0: begin
                        if (cctl_a0 || cctl_host_out != 8'h60)
                            $fatal(1, "CCTL oracle expected DATA 60, got %s %02x",
                                   cctl_a0 ? "CMD" : "DATA", cctl_host_out);
                        cctl_phase <= 4'd1;
                    end
                    4'd1: begin
                        if (!cctl_a0 || cctl_host_out != 8'he1)
                            $fatal(1, "CCTL oracle expected CMD E1");
                        cctl_phase <= 4'd2;
                        cctl_status_reads <= 0;
                    end
                    4'd2: begin
                        if (!cctl_a0 || cctl_host_out != 8'h1f)
                            $fatal(1, "CCTL oracle expected CMD 1F");
                        cctl_phase <= 4'd3;
                    end
                    4'd3: begin
                        if (!cctl_a0 || cctl_host_out != 8'h3f)
                            $fatal(1, "CCTL oracle expected CMD 3F");
                        cctl_phase <= 4'd4;
                    end
                    4'd4: begin
                        if (cctl_a0 || cctl_host_out != 8'h01)
                            $fatal(1, "CCTL oracle expected DATA 01");
                        cctl_phase <= 4'd5;
                    end
                    4'd5: begin
                        if (!cctl_a0 || cctl_host_out != 8'h81)
                            $fatal(1, "CCTL oracle expected CMD 81");
                        cctl_phase <= 4'd6;
                        cctl_status_reads <= 0;
                    end
                    default: $fatal(1, "unexpected CCTL write %s %02x",
                                    cctl_a0 ? "CMD" : "DATA", cctl_host_out);
                endcase
            end

            if (!ccpu_cs_n && !ccpu_wr_n && !previous_ccpu_write) begin
                case (ccpu_phase)
                    4'd0: begin
                        if (ccpu_a0 || ccpu_host_out != 8'h60)
                            $fatal(1, "CCPU oracle expected DATA 60");
                        ccpu_phase <= 4'd1;
                    end
                    4'd1: begin
                        if (!ccpu_a0 || ccpu_host_out != 8'he1)
                            $fatal(1, "CCPU oracle expected CMD E1");
                        ccpu_phase <= 4'd2;
                        ccpu_status_reads <= 0;
                    end
                    4'd2: begin
                        if (!ccpu_a0 || ccpu_host_out != 8'h1f)
                            $fatal(1, "CCPU oracle expected CMD 1F");
                        ccpu_phase <= 4'd3;
                    end
                    4'd3: begin
                        if (!ccpu_a0 || ccpu_host_out != 8'h3f)
                            $fatal(1, "CCPU oracle expected CMD 3F");
                        ccpu_phase <= 4'd4;
                    end
                    4'd4: begin
                        if (!ccpu_a0 || ccpu_host_out != 8'h81)
                            $fatal(1, "CCPU oracle expected CMD 81");
                        ccpu_phase <= 4'd5;
                    end
                    4'd5: begin
                        if (!ccpu_a0 || ccpu_host_out != 8'h62)
                            $fatal(1, "CCPU oracle expected CMD 62");
                        ccpu_phase <= 4'd6;
                    end
                    4'd6: begin
                        if (ccpu_a0 || ccpu_host_out != 8'h01)
                            $fatal(1, "CCPU oracle expected DATA 01");
                        ccpu_phase <= 4'd7;
                    end
                    default: $fatal(1, "unexpected CCPU write %s %02x",
                                    ccpu_a0 ? "CMD" : "DATA", ccpu_host_out);
                endcase
            end
        end
    end

    gladiator_upi41_device ucpu (
        .clk(clk),
        .ce_6m(ce_6m),
        .reset(reset),
        .host_a0(ucpu_a0),
        .host_cs_n(ucpu_cs_n),
        .host_rd_n(ucpu_rd_n),
        .host_wr_n(ucpu_wr_n),
        .host_data_in(ucpu_host_data_in),
        .host_data_out(ucpu_host_data_out),
        .p1_pin_in({7'h7f, csnd_p1_out[0]}),
        .p2_pin_in(8'h5a),
        .p1_latch_out(ucpu_p1_out),
        .p2_latch_out(),
        .t0(tclk),
        .t1(csnd_p1_out[1]),
        .program_address(ucpu_program_address),
        .program_data(ucpu_rom_data),
        .debug_dmem_address(),
        .debug_dmem_write()
    );

    gladiator_upi41_device csnd (
        .clk(clk),
        .ce_6m(ce_6m),
        .reset(reset),
        .host_a0(csnd_a0),
        .host_cs_n(csnd_cs_n),
        .host_rd_n(csnd_rd_n),
        .host_wr_n(csnd_wr_n),
        .host_data_in(csnd_host_out),
        .host_data_out(csnd_host_in),
        .p1_pin_in({7'h7f, ucpu_p1_out[0]}),
        .p2_pin_in(8'hf7),
        .p1_latch_out(csnd_p1_out),
        .p2_latch_out(),
        .t0(tclk),
        .t1(ucpu_p1_out[1]),
        .program_address(csnd_program_address),
        .program_data(csnd_rom_data),
        .debug_dmem_address(),
        .debug_dmem_write()
    );

    assign csnd_rom_address = csnd_program_address;

    task automatic host_write_ucpu(
        input logic address_bit,
        input logic [7:0] value
    );
        begin
            @(negedge clk);
            ucpu_a0 = address_bit;
            ucpu_host_data_in = value;
            ucpu_cs_n = 1'b0;
            ucpu_wr_n = 1'b0;
            repeat (8) @(negedge clk);
            ucpu_cs_n = 1'b1;
            ucpu_wr_n = 1'b1;
        end
    endtask

    task automatic host_read_ucpu(
        input logic address_bit,
        output logic [7:0] value
    );
        begin
            @(negedge clk);
            ucpu_a0 = address_bit;
            ucpu_cs_n = 1'b0;
            ucpu_rd_n = 1'b0;
            repeat (4) @(negedge clk);
            value = ucpu_host_data_out;
            repeat (4) @(negedge clk);
            ucpu_cs_n = 1'b1;
            ucpu_rd_n = 1'b1;
        end
    endtask

    task automatic wait_ucpu_status(
        input logic [7:0] mask,
        input logic [7:0] expected,
        output logic [7:0] final_status
    );
        integer polls;
        logic [7:0] status;
        begin : wait_loop
            final_status = 8'hxx;
            for (polls = 0; polls < 30000; polls = polls + 1) begin
                host_read_ucpu(1'b1, status);
                if ((status & mask) == expected) begin
                    final_status = status;
                    disable wait_loop;
                end
                repeat (8) @(posedge clk);
            end
            $fatal(1, "UCPU status timeout last=%02x sound=%04x ucpu=%03x csnd=%03x",
                   status, sound_address, ucpu_rom_address,
                   csnd_rom_address);
        end
    endtask

    logic previous_csnd_write = 1'b0;
    integer csnd_write_count = 0;
    logic csnd_4a_seen = 1'b0;
    logic csnd_08_seen = 1'b0;

    always_ff @(posedge clk) begin
        previous_csnd_write <= !csnd_cs_n && !csnd_wr_n;
        if (reset) begin
            previous_csnd_write <= 1'b0;
            csnd_write_count <= 0;
            csnd_4a_seen <= 1'b0;
            csnd_08_seen <= 1'b0;
        end else if (!csnd_cs_n && !csnd_wr_n && !previous_csnd_write) begin
            csnd_write_count <= csnd_write_count + 1;
            $display("SOUND->CSND %s %02x sound_bus=%04x csnd_pc=%03x",
                     csnd_a0 ? "CMD" : "DATA", csnd_host_out,
                     sound_address, csnd_rom_address);
            if (csnd_a0 && csnd_host_out == 8'h4a) begin
                csnd_4a_seen <= 1'b1;
            end
            if (csnd_a0 && csnd_host_out == 8'h08)
                csnd_08_seen <= 1'b1;
        end
    end

    integer rom_file;
    integer seek_result;
    integer bytes_read;
    integer timeout_cycles;
    logic [7:0] status;
    logic [7:0] response;

    initial begin
        rom_file = $fopen("sim/out/gladiatr.rom", "rb");
        if (!rom_file)
            $fatal(1, "missing sim/out/gladiatr.rom");
        seek_result = $fseek(rom_file, 20'h12000, 0);
        bytes_read = $fread(sound_rom, rom_file);
        if (seek_result != 0 || bytes_read != 16'h4000)
            $fatal(1, "cannot load sound ROM");
        // tb_sound_ram_boot separately proves the destructive 0x0800 RAM
        // march. Skip only that loop here so this protocol test reaches the
        // MAME-observed UPI transactions without re-simulating it.
        if (sound_rom[16'h009b] != 8'hc3 ||
                sound_rom[16'h009c] != 8'h00 ||
                sound_rom[16'h009d] != 8'h08)
            $fatal(1, "unexpected sound RAM-test jump encoding");
        sound_rom[16'h009c] = 8'h9e;
        sound_rom[16'h009d] = 8'h00;
        seek_result = $fseek(rom_file, 20'h6c840, 0);
        bytes_read = $fread(ucpu_rom, rom_file);
        if (seek_result != 0 || bytes_read != 1024)
            $fatal(1, "cannot load UCPU ROM");
        bytes_read = $fread(csnd_rom, rom_file);
        $fclose(rom_file);
        if (bytes_read != 2048)
            $fatal(1, "cannot load CSND ROM");

        repeat (64) @(posedge clk);
        reset = 1'b0;

        begin : wait_for_4a
            for (timeout_cycles = 0; timeout_cycles < 8000000;
                    timeout_cycles = timeout_cycles + 1) begin
                @(posedge clk);
                if (csnd_4a_seen)
                    disable wait_for_4a;
            end
            $fatal(1, "sound Z80 did not write CSND command 4A; writes=%0d sound=%04x csnd=%03x ymA=%02x",
                   csnd_write_count, sound_address, csnd_rom_address,
                   ym_port_a);
        end

        // Main-Z80 UCPU probe from 0x084B, timed after the sound side has
        // entered its command-0x4A wait just as on the physical board.
        repeat (50000) @(posedge clk);
        host_write_ucpu(1'b1, 8'h0a);
        wait_ucpu_status(8'h02, 8'h00, status);
        host_write_ucpu(1'b0, 8'h01);
        wait_ucpu_status(8'h02, 8'h00, status);
        host_write_ucpu(1'b1, 8'h08);

        begin : wait_for_08
            for (timeout_cycles = 0; timeout_cycles < 4000000;
                    timeout_cycles = timeout_cycles + 1) begin
                @(posedge clk);
                if (csnd_08_seen)
                    disable wait_for_08;
            end
            $fatal(1, "sound Z80 did not complete CSND 00,00,08 sequence; writes=%0d sound=%04x csnd=%03x",
                   csnd_write_count, sound_address, csnd_rom_address);
        end

        repeat (100000) @(posedge clk);
        host_read_ucpu(1'b1, status);
        if (status[2] || ((status & 8'hf0) != 8'h00))
            $fatal(1, "UCPU post-link status failed: %02x", status);
        host_read_ucpu(1'b0, response);
        host_write_ucpu(1'b1, 8'h4a);
        wait_ucpu_status(8'h01, 8'h01, status);
        host_read_ucpu(1'b0, response);
        if (response != 8'h00)
            $fatal(1, "UCPU command 4A response is %02x", response);

        $display("PASS tb_sound_ucpu_integration writes=%0d",
                 csnd_write_count);
        $finish;
    end
endmodule
