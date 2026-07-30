`timescale 1ns/1ps

module tb_sound_command_tap;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [15:0] cpu_address = 16'd0;
    logic [7:0] cpu_data_out = 8'd0;
    logic [7:0] cpu_data_in;
    logic cpu_m1_n = 1'b1;
    logic cpu_mreq_n = 1'b1;
    logic cpu_iorq_n = 1'b1;
    logic cpu_rd_n = 1'b1;
    logic cpu_wr_n = 1'b1;
    logic sound_command_write;
    logic [7:0] sound_command_data;

    gladiator_sound_bus dut (
        .clk                (clk),
        .reset              (reset),
        .cpu_address        (cpu_address),
        .cpu_data_out       (cpu_data_out),
        .cpu_data_in        (cpu_data_in),
        .cpu_m1_n           (cpu_m1_n),
        .cpu_mreq_n         (cpu_mreq_n),
        .cpu_iorq_n         (cpu_iorq_n),
        .cpu_rd_n           (cpu_rd_n),
        .cpu_wr_n           (cpu_wr_n),
        .rom_address        (),
        .rom_data           (8'hff),
        .interrupt_ack      (),
        .ym_cs_n            (),
        .ym_address         (),
        .ym_wr_n            (),
        .ym_data_out        (),
        .ym_data_in         (8'hff),
        .csnd_cs_n          (),
        .csnd_a0            (),
        .csnd_rd_n          (),
        .csnd_wr_n          (),
        .csnd_data_out      (),
        .csnd_data_in       (8'hff),
        .cctl_cs_n          (),
        .cctl_a0            (),
        .cctl_rd_n          (),
        .cctl_wr_n          (),
        .cctl_data_out      (),
        .cctl_data_in       (8'hff),
        .ccpu_cs_n          (),
        .ccpu_a0            (),
        .ccpu_rd_n          (),
        .ccpu_wr_n          (),
        .ccpu_data_out      (),
        .ccpu_data_in       (8'hff),
        .command_write      (),
        .command_data       (),
        .sound_command_write(sound_command_write),
        .sound_command_data (sound_command_data),
        .filter_latch       (),
        .trace_mem_read     (),
        .trace_mem_write    (),
        .trace_io_read      (),
        .trace_io_write     ()
    );

    always #5 clk = ~clk;

    task automatic write_memory(
        input logic [15:0] address,
        input logic [7:0] data,
        input logic expect_command
    );
        begin
            @(negedge clk);
            cpu_address = address;
            cpu_data_out = data;
            cpu_mreq_n = 1'b0;
            cpu_wr_n = 1'b0;
            @(posedge clk);
            #1;
            if (sound_command_write !== expect_command) begin
                $error("write %04x: command_write=%b expected=%b",
                       address, sound_command_write, expect_command);
                $fatal(1);
            end
            if (expect_command && sound_command_data !== data) begin
                $error("write %04x: command_data=%02x expected=%02x",
                       address, sound_command_data, data);
                $fatal(1);
            end

            // Holding the bus level cannot emit a duplicate pulse.
            @(posedge clk);
            #1;
            if (sound_command_write !== 1'b0)
                $fatal(1, "held write emitted a duplicate command");

            @(negedge clk);
            cpu_mreq_n = 1'b1;
            cpu_wr_n = 1'b1;
            @(posedge clk);
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        #1 reset = 1'b0;

        write_memory(16'h8001, 8'h2e, 1'b0);
        write_memory(16'h8002, 8'h2e, 1'b1);
        write_memory(16'h8003, 8'h36, 1'b0);
        write_memory(16'h8002, 8'h68, 1'b1);

        $display("PASS tb_sound_command_tap");
        $finish;
    end
endmodule
