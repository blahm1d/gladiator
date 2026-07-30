`timescale 1ns/1ps

module tb_upi41_dmem_contract;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [7:0] host_data_out;
    logic [7:0] p1_latch_out;
    logic [7:0] p2_latch_out;
    logic [10:0] program_address;

    gladiator_upi41_device dut (
        .clk                (clk),
        .ce_6m              (1'b0),
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
        .t0                 (1'b1),
        .t1                 (1'b1),
        .program_address    (program_address),
        .program_data       (8'h00),
        .debug_dmem_address (),
        .debug_dmem_write   ()
    );

    always #5 clk = ~clk;

    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;
        @(negedge clk);

        // The core normally drives these signals. White-box forcing isolates
        // the wrapper contract: a qualified T48 write must commit on this
        // edge, while the core's registered read input retains the pre-write
        // byte instead of sampling an inferred-RAM collision value.
        dut.dmem[8'h42] = 8'h3c;
        force dut.dmem_address  = 8'h42;
        force dut.dmem_write    = 1'b0;
        @(posedge clk);
        #1;
        if (dut.dmem_data_in !== 8'h3c)
            $fatal(1, "UPI-41 RAM pre-write read got %02x",
                   dut.dmem_data_in);

        force dut.dmem_data_out = 8'ha5;
        force dut.dmem_write    = 1'b1;
        @(posedge clk);
        #1;
        if (dut.dmem[8'h42] !== 8'ha5)
            $fatal(1, "UPI-41 RAM write was delayed: got %02x",
                   dut.dmem[8'h42]);
        if (dut.dmem_data_in !== 8'h3c)
            $fatal(1, "UPI-41 RAM collision did not hold old data: got %02x",
                   dut.dmem_data_in);

        force dut.dmem_write = 1'b0;
        @(posedge clk);
        #1;
        if (dut.dmem_data_in !== 8'ha5)
            $fatal(1, "UPI-41 RAM post-write read got %02x",
                   dut.dmem_data_in);

        release dut.dmem_address;
        release dut.dmem_data_out;
        release dut.dmem_write;
        $display("PASS tb_upi41_dmem_contract");
        $finish;
    end
endmodule
