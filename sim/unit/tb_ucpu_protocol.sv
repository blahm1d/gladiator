`timescale 1ns/1ps

module tb_ucpu_protocol;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic ce_6m = 1'b0;
    logic tclk = 1'b0;

    logic [7:0] ucpu_rom [0:1023];
    logic [7:0] csnd_rom [0:2047];
    logic [7:0] ucpu_program_data = 8'h00;
    logic [7:0] csnd_program_data = 8'h00;
    logic [10:0] ucpu_program_address;
    logic [10:0] csnd_program_address;

    logic ucpu_a0 = 1'b0;
    logic ucpu_cs_n = 1'b1;
    logic ucpu_rd_n = 1'b1;
    logic ucpu_wr_n = 1'b1;
    logic [7:0] ucpu_host_data_in = 8'hff;
    logic [7:0] ucpu_host_data_out;

    logic csnd_a0 = 1'b0;
    logic csnd_cs_n = 1'b1;
    logic csnd_rd_n = 1'b1;
    logic csnd_wr_n = 1'b1;
    logic [7:0] csnd_host_data_in = 8'hff;
    logic [7:0] csnd_host_data_out;

    logic [7:0] ucpu_p1;
    logic [7:0] csnd_p1;
    logic [7:0] unused_ucpu_p2;
    logic [7:0] unused_csnd_p2;
    integer divider = 0;
    integer tclk_divider = 0;

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
        .p1_pin_in({7'h7f, csnd_p1[0]}),
        .p2_pin_in(8'h5a),
        .p1_latch_out(ucpu_p1),
        .p2_latch_out(unused_ucpu_p2),
        .t0(tclk),
        .t1(csnd_p1[1]),
        .program_address(ucpu_program_address),
        .program_data(ucpu_program_data),
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
        .host_data_in(csnd_host_data_in),
        .host_data_out(csnd_host_data_out),
        .p1_pin_in({7'h7f, ucpu_p1[0]}),
        // Cluster wiring: DSW2[2:7], then DSW2[1:0].
        .p2_pin_in(8'hf7),
        .p1_latch_out(csnd_p1),
        .p2_latch_out(unused_csnd_p2),
        .t0(tclk),
        .t1(ucpu_p1[1]),
        .program_address(csnd_program_address),
        .program_data(csnd_program_data),
        .debug_dmem_address(),
        .debug_dmem_write()
    );

    always #5.208 clk = ~clk;

    always @(posedge clk) begin
        if (divider == 1) begin
            divider <= 0;
            ce_6m <= 1'b1;
        end else begin
            divider <= divider + 1;
            ce_6m <= 1'b0;
        end
        if (tclk_divider == 1023) begin
            tclk_divider <= 0;
            tclk <= ~tclk;
        end else begin
            tclk_divider <= tclk_divider + 1;
        end
        ucpu_program_data <= ucpu_rom[ucpu_program_address[9:0]];
        csnd_program_data <= csnd_rom[csnd_program_address];
    end

    task automatic host_write_csnd(
        input logic address_bit,
        input logic [7:0] value
    );
        begin
            @(negedge clk);
            csnd_a0 = address_bit;
            csnd_host_data_in = value;
            csnd_cs_n = 1'b0;
            csnd_wr_n = 1'b0;
            repeat (8) @(negedge clk);
            csnd_cs_n = 1'b1;
            csnd_wr_n = 1'b1;
        end
    endtask

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

    task automatic host_read_csnd(
        input logic address_bit,
        output logic [7:0] value
    );
        begin
            @(negedge clk);
            csnd_a0 = address_bit;
            csnd_cs_n = 1'b0;
            csnd_rd_n = 1'b0;
            repeat (4) @(negedge clk);
            value = csnd_host_data_out;
            repeat (4) @(negedge clk);
            csnd_cs_n = 1'b1;
            csnd_rd_n = 1'b1;
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
            for (polls = 0; polls < 20000; polls = polls + 1) begin
                host_read_ucpu(1'b1, status);
                if ((status & mask) == expected) begin
                    final_status = status;
                    disable wait_loop;
                end
                repeat (8) @(posedge clk);
            end
            $fatal(1, "UCPU status timeout mask=%02x expected=%02x last=%02x ucpu_pc=%03x csnd_pc=%03x p1=%02x/%02x",
                   mask, expected, status, ucpu_program_address,
                   csnd_program_address, ucpu_p1, csnd_p1);
        end
    endtask

    task automatic wait_csnd_status(
        input logic [7:0] mask,
        input logic [7:0] expected,
        output logic [7:0] final_status
    );
        integer polls;
        logic [7:0] csnd_status;
        begin : wait_loop
            final_status = 8'hxx;
            for (polls = 0; polls < 20000; polls = polls + 1) begin
                host_read_csnd(1'b1, csnd_status);
                if ((csnd_status & mask) == expected) begin
                    final_status = csnd_status;
                    disable wait_loop;
                end
                repeat (8) @(posedge clk);
            end
            $fatal(1, "CSND status timeout mask=%02x expected=%02x last=%02x ucpu_pc=%03x csnd_pc=%03x p1=%02x/%02x",
                   mask, expected, csnd_status, ucpu_program_address,
                   csnd_program_address, ucpu_p1, csnd_p1);
        end
    endtask

    integer rom_file;
    integer seek_result;
    integer bytes_read;
    logic [7:0] status;
    logic [7:0] response;

    initial begin
        rom_file = $fopen("sim/out/gladiatr.rom", "rb");
        if (!rom_file)
            $fatal(1, "missing sim/out/gladiatr.rom");
        seek_result = $fseek(rom_file, 20'h6c840, 0);
        if (seek_result != 0)
            $fatal(1, "cannot seek to UCPU ROM");
        bytes_read = $fread(ucpu_rom, rom_file);
        if (bytes_read != 1024)
            $fatal(1, "UCPU ROM read %0d bytes", bytes_read);
        seek_result = $fseek(rom_file, 20'h6cc40, 0);
        if (seek_result != 0)
            $fatal(1, "cannot seek to CSND ROM");
        bytes_read = $fread(csnd_rom, rom_file);
        $fclose(rom_file);
        if (bytes_read != 2048)
            $fatal(1, "CSND ROM read %0d bytes", bytes_read);

        repeat (64) @(posedge clk);
        reset = 1'b0;

        // The sound Z80 performs this CSND control write at the beginning of
        // the real board boot, long before the main Z80 reaches UCPU.
        host_write_csnd(1'b1, 8'hf0);
        repeat (100000) @(posedge clk);
        host_read_csnd(1'b1, status);
        $display("CSND after F0 status=%02x pc=%03x p1=%02x",
                 status, csnd_program_address, csnd_p1);
        if (status != 8'h0d)
            $fatal(1, "CSND status after F0 is %02x, expected 0D", status);
        host_write_csnd(1'b1, 8'h0b);
        host_read_csnd(1'b0, response);
        $display("CSND command 0B response=%02x", response);
        if (response != 8'h08)
            $fatal(1, "CSND command 0B response is %02x, expected 08",
                   response);

        // The sound Z80 later reads the same output byte at 0x04B8 and writes
        // command 0x4A at 0x04BB.  CSND then waits for UCPU on the board's
        // two-wire controller link while the Z80 polls status 0x0E.
        repeat (100000) @(posedge clk);
        host_read_csnd(1'b0, response);
        if (response != 8'h08)
            $fatal(1, "CSND retained command 0B response is %02x, expected 08",
                   response);
        host_write_csnd(1'b1, 8'h4a);
        repeat (100000) @(posedge clk);
        host_read_csnd(1'b1, status);
        $display("CSND link-wait status=%02x pc=%03x p1=%02x",
                 status, csnd_program_address, csnd_p1);
        if (status != 8'h0e)
            $fatal(1, "CSND status while awaiting UCPU is %02x, expected 0E",
                   status);

        // This is the exact main-Z80 CIOM probe at 0x084B. The MAME oracle
        // begins with status 0x01, then performs command 0x0A/data 0x01,
        // command 0x08, and finally command 0x4A expecting a zero reply.
        host_read_ucpu(1'b1, status);
        $display("UCPU initial status=%02x pc=%03x p1=%02x peer_p1=%02x",
                 status, ucpu_program_address, ucpu_p1, csnd_p1);
        if ((status & 8'hf0) != 8'h00)
            $fatal(1, "CIOM initial status high nibble is nonzero: %02x",
                   status);

        host_write_ucpu(1'b1, 8'h0a);
        wait_ucpu_status(8'h02, 8'h00, status);
        host_write_ucpu(1'b0, 8'h01);
        wait_ucpu_status(8'h02, 8'h00, status);
        host_write_ucpu(1'b1, 8'h08);

        // While UCPU sends its five-byte packet, the sound Z80 finishes the
        // pending CSND command 0x4A, reads its zero reply, supplies two zero
        // data bytes, and terminates the host-side block with command 0x08.
        // This is the complete MAME bus sequence at sound PCs 04BD-04B4.
        wait_csnd_status(8'h01, 8'h01, status);
        host_read_csnd(1'b0, response);
        if (response != 8'h00)
            $fatal(1, "CSND command 4A response is %02x, expected 00",
                   response);
        wait_csnd_status(8'h02, 8'h00, status);
        host_write_csnd(1'b0, 8'h00);
        wait_csnd_status(8'h02, 8'h00, status);
        host_write_csnd(1'b0, 8'h00);
        wait_csnd_status(8'h02, 8'h00, status);
        host_write_csnd(1'b1, 8'h08);

        repeat (100000) @(posedge clk);
        host_read_ucpu(1'b1, status);
        $display("UCPU post-link status=%02x ucpu_pc=%03x csnd_pc=%03x p1=%02x/%02x",
                 status, ucpu_program_address, csnd_program_address,
                 ucpu_p1, csnd_p1);
        if (status[2] || ((status & 8'hf0) != 8'h00))
            $fatal(1, "SUB-COMM status failed: %02x", status);

        host_read_ucpu(1'b0, response);
        host_write_ucpu(1'b1, 8'h4a);
        wait_ucpu_status(8'h01, 8'h01, status);
        host_read_ucpu(1'b0, response);
        $display("UCPU command 4A response=%02x", response);
        if (response != 8'h00)
            $fatal(1, "CIOM command 4A response is %02x, expected 00",
                   response);

        $display("PASS tb_ucpu_protocol");
        $finish;
    end
endmodule
