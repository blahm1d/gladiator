`timescale 1ns/1ps

module tb_input_mcu_protocol;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic ce_6m = 1'b0;
    integer divider = 0;

    logic [7:0] cctl_rom [0:1023];
    logic [7:0] ccpu_rom [0:1023];
    logic [7:0] cctl_raw_data = 8'h00;
    logic [7:0] ccpu_raw_data = 8'h00;
    logic [7:0] cctl_program_data;
    logic [7:0] ccpu_program_data;
    logic [10:0] cctl_program_address;
    logic [10:0] ccpu_program_address;

    logic cctl_a0 = 1'b0;
    logic cctl_cs_n = 1'b1;
    logic cctl_rd_n = 1'b1;
    logic cctl_wr_n = 1'b1;
    logic [7:0] cctl_host_data_in = 8'hff;
    logic [7:0] cctl_host_data_out;

    logic ccpu_a0 = 1'b0;
    logic ccpu_cs_n = 1'b1;
    logic ccpu_rd_n = 1'b1;
    logic ccpu_wr_n = 1'b1;
    logic [7:0] ccpu_host_data_in = 8'hff;
    logic [7:0] ccpu_host_data_out;

    logic [7:0] cctl_p1;
    logic [7:0] cctl_p2;
    logic [7:0] ccpu_p1;
    logic [7:0] ccpu_p2;

    gladiator_mcu_rom_adapter cctl_adapter (
        .enable_patch (1'b1),
        .address      (cctl_program_address),
        .raw_data     (cctl_raw_data),
        .program_data (cctl_program_data),
        .patch_visible()
    );

    gladiator_mcu_rom_adapter ccpu_adapter (
        .enable_patch (1'b1),
        .address      (ccpu_program_address),
        .raw_data     (ccpu_raw_data),
        .program_data (ccpu_program_data),
        .patch_visible()
    );

    gladiator_upi41_device cctl (
        .clk(clk),
        .ce_6m(ce_6m),
        .reset(reset),
        .host_a0(cctl_a0),
        .host_cs_n(cctl_cs_n),
        .host_rd_n(cctl_rd_n),
        .host_wr_n(cctl_wr_n),
        .host_data_in(cctl_host_data_in),
        .host_data_out(cctl_host_data_out),
        .p1_pin_in(8'hff),
        .p2_pin_in(8'hff),
        .p1_latch_out(cctl_p1),
        .p2_latch_out(cctl_p2),
        .t0(1'b1),
        .t1(1'b1),
        .program_address(cctl_program_address),
        .program_data(cctl_program_data),
        .debug_dmem_address(),
        .debug_dmem_write()
    );

    gladiator_upi41_device ccpu (
        .clk(clk),
        .ce_6m(ce_6m),
        .reset(reset),
        .host_a0(ccpu_a0),
        .host_cs_n(ccpu_cs_n),
        .host_rd_n(ccpu_rd_n),
        .host_wr_n(ccpu_wr_n),
        .host_data_in(ccpu_host_data_in),
        .host_data_out(ccpu_host_data_out),
        .p1_pin_in(8'hff),
        .p2_pin_in(8'hff),
        .p1_latch_out(ccpu_p1),
        .p2_latch_out(ccpu_p2),
        .t0(1'b1),
        .t1(1'b1),
        .program_address(ccpu_program_address),
        .program_data(ccpu_program_data),
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
        cctl_raw_data <= cctl_rom[cctl_program_address[9:0]];
        ccpu_raw_data <= ccpu_rom[ccpu_program_address[9:0]];
    end

    task automatic cctl_write(
        input logic address_bit,
        input logic [7:0] value
    );
        begin
            @(negedge clk);
            cctl_a0 = address_bit;
            cctl_host_data_in = value;
            cctl_cs_n = 1'b0;
            cctl_wr_n = 1'b0;
            repeat (8) @(negedge clk);
            cctl_cs_n = 1'b1;
            cctl_wr_n = 1'b1;
        end
    endtask

    task automatic cctl_read(
        input logic address_bit,
        output logic [7:0] value
    );
        begin
            @(negedge clk);
            cctl_a0 = address_bit;
            cctl_cs_n = 1'b0;
            cctl_rd_n = 1'b0;
            repeat (4) @(negedge clk);
            value = cctl_host_data_out;
            repeat (4) @(negedge clk);
            cctl_cs_n = 1'b1;
            cctl_rd_n = 1'b1;
        end
    endtask

    task automatic ccpu_write(
        input logic address_bit,
        input logic [7:0] value
    );
        begin
            @(negedge clk);
            ccpu_a0 = address_bit;
            ccpu_host_data_in = value;
            ccpu_cs_n = 1'b0;
            ccpu_wr_n = 1'b0;
            repeat (8) @(negedge clk);
            ccpu_cs_n = 1'b1;
            ccpu_wr_n = 1'b1;
        end
    endtask

    task automatic ccpu_read(
        input logic address_bit,
        output logic [7:0] value
    );
        begin
            @(negedge clk);
            ccpu_a0 = address_bit;
            ccpu_cs_n = 1'b0;
            ccpu_rd_n = 1'b0;
            repeat (4) @(negedge clk);
            value = ccpu_host_data_out;
            repeat (4) @(negedge clk);
            ccpu_cs_n = 1'b1;
            ccpu_rd_n = 1'b1;
        end
    endtask

    task automatic cctl_wait_status(
        input logic [7:0] expected_status
    );
        integer polls;
        logic [7:0] status;
        begin : wait_loop
            for (polls = 0; polls < 20000; polls = polls + 1) begin
                cctl_read(1'b1, status);
                if (status == expected_status)
                    disable wait_loop;
                repeat (8) @(posedge clk);
            end
            $fatal(1, "CCTL step %0d status timeout got=%02x expected=%02x pc=%03x",
                   cctl_step, status, expected_status,
                   cctl_program_address);
        end
    endtask

    task automatic ccpu_wait_status(
        input logic [7:0] expected_status
    );
        integer polls;
        logic [7:0] status;
        begin : wait_loop
            for (polls = 0; polls < 20000; polls = polls + 1) begin
                ccpu_read(1'b1, status);
                if (status == expected_status)
                    disable wait_loop;
                repeat (8) @(posedge clk);
            end
            $fatal(1, "CCPU step %0d status timeout got=%02x expected=%02x pc=%03x",
                   ccpu_step, status, expected_status,
                   ccpu_program_address);
        end
    endtask

    integer rom_file;
    integer seek_result;
    integer bytes_read;
    logic [7:0] status;
    logic [7:0] response;
    integer cctl_step = 0;
    integer ccpu_step = 0;

    initial begin
        rom_file = $fopen("sim/out/gladiatr.rom", "rb");
        if (!rom_file)
            $fatal(1, "missing sim/out/gladiatr.rom");
        seek_result = $fseek(rom_file, 20'h6c040, 0);
        bytes_read = $fread(cctl_rom, rom_file);
        if (seek_result != 0 || bytes_read != 1024)
            $fatal(1, "cannot load CCTL ROM");
        bytes_read = $fread(ccpu_rom, rom_file);
        $fclose(rom_file);
        if (bytes_read != 1024)
            $fatal(1, "cannot load CCPU ROM");

        repeat (64) @(posedge clk);
        reset = 1'b0;
        repeat (100000) @(posedge clk);

        // MAME sound-Z80 trace, PCs 0950-0997.
        ccpu_read(1'b1, status);
        if (status != 8'h01)
            $fatal(1, "CCPU initial status %02x", status);
        ccpu_write(1'b0, 8'h60);
        ccpu_step = 1;
        ccpu_wait_status(8'h01);
        ccpu_write(1'b1, 8'he1);
        ccpu_step = 2;
        ccpu_wait_status(8'h09);
        ccpu_write(1'b1, 8'h1f);
        ccpu_step = 3;
        ccpu_wait_status(8'h01);
        ccpu_write(1'b1, 8'h3f);
        ccpu_step = 4;
        ccpu_wait_status(8'h01);
        ccpu_write(1'b1, 8'h81);
        ccpu_step = 5;
        ccpu_wait_status(8'h01);
        ccpu_write(1'b1, 8'h62);
        ccpu_step = 6;
        ccpu_wait_status(8'h01);
        ccpu_write(1'b0, 8'h01);
        ccpu_step = 7;

        // MAME sound-Z80 trace, PCs 09B5-09E4.
        cctl_read(1'b1, status);
        if (status != 8'h01)
            $fatal(1, "CCTL initial status %02x", status);
        cctl_write(1'b0, 8'h60);
        cctl_step = 1;
        cctl_wait_status(8'h01);
        cctl_write(1'b1, 8'he1);
        cctl_step = 2;
        cctl_wait_status(8'h09);
        cctl_write(1'b1, 8'h1f);
        cctl_step = 3;
        cctl_wait_status(8'h09);
        cctl_write(1'b1, 8'h3f);
        cctl_step = 4;
        cctl_wait_status(8'h09);
        cctl_write(1'b0, 8'h01);
        cctl_step = 5;

        // The real sound program performs the complete CSND/UCPU link test
        // between initialization above and these input-MCU data reads.
        repeat (200000) @(posedge clk);
        ccpu_read(1'b0, response);
        if (response != 8'h00)
            $fatal(1, "CCPU response %02x, expected 00", response);
        cctl_read(1'b0, response);
        if (response != 8'h00)
            $fatal(1, "CCTL initial response %02x, expected 00", response);

        // MAME sound-Z80 trace, PCs 0336-0344.
        cctl_write(1'b1, 8'h81);
        cctl_step = 6;
        cctl_wait_status(8'h0b);
        cctl_read(1'b0, response);
        if (response != 8'h48)
            $fatal(1, "CCTL command 81 response %02x, expected 48",
                   response);

        $display("PASS tb_input_mcu_protocol");
        $finish;
    end
endmodule
