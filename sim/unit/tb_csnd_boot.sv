`timescale 1ns/1ps

module tb_csnd_boot;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic ce_6m = 1'b0;
    logic [7:0] program_rom [0:2047];
    logic [7:0] program_data = 8'h00;
    logic [10:0] program_address;
    logic [7:0] host_data_out;
    logic [7:0] p1_latch_out;
    logic [7:0] p2_latch_out;
    logic [7:0] debug_dmem_address;
    logic debug_dmem_write;

    integer clock_divider = 0;
    integer wait_loop_entries = 0;
    logic previous_at_wait = 1'b0;

    gladiator_upi41_device dut (
        .clk                (clk),
        .ce_6m              (ce_6m),
        .reset              (reset),
        .host_a0            (1'b0),
        .host_cs_n          (1'b1),
        .host_rd_n          (1'b1),
        .host_wr_n          (1'b1),
        .host_data_in       (8'hff),
        .host_data_out      (host_data_out),
        .p1_pin_in          (8'hff),
        .p2_pin_in          (8'hff),
        .p1_latch_out       (p1_latch_out),
        .p2_latch_out       (p2_latch_out),
        .t0                 (1'b0),
        .t1                 (1'b1),
        .program_address    (program_address),
        .program_data       (program_data),
        .debug_dmem_address (debug_dmem_address),
        .debug_dmem_write   (debug_dmem_write)
    );

    always #5.208 clk = ~clk;

    always @(posedge clk) begin
        if (clock_divider == 15) begin
            clock_divider <= 0;
            ce_6m <= 1'b1;
        end else begin
            clock_divider <= clock_divider + 1;
            ce_6m <= 1'b0;
        end
        program_data <= program_rom[program_address];

        if (reset) begin
            previous_at_wait <= 1'b0;
        end else if (ce_6m) begin
            if ($isunknown(program_address))
                $fatal(1, "CSND program address became unknown");
            if (program_address == 11'h050 && !previous_at_wait)
                wait_loop_entries <= wait_loop_entries + 1;
            previous_at_wait <= program_address == 11'h050;
        end
    end

    integer rom_file;
    integer seek_result;
    integer bytes_read;

    initial begin
        rom_file = $fopen("sim/out/gladiatr.rom", "rb");
        if (!rom_file)
            $fatal(1, "missing sim/out/gladiatr.rom");
        seek_result = $fseek(rom_file, 20'h6cc40, 0);
        if (seek_result != 0)
            $fatal(1, "cannot seek to CSND ROM region");
        bytes_read = $fread(program_rom, rom_file);
        $fclose(rom_file);
        if (bytes_read != 2048)
            $fatal(1, "CSND ROM read %0d bytes, expected 2048", bytes_read);

        repeat (64) @(posedge clk);
        reset = 1'b0;

        fork
            begin
                wait (wait_loop_entries >= 16);
                $display("PASS tb_csnd_boot");
                $finish;
            end
            begin
                repeat (2500000) @(posedge clk);
                $fatal(1, "CSND did not repeatedly execute JNIBF at 0x050");
            end
        join
    end
endmodule
