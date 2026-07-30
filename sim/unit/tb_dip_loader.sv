`timescale 1ns/1ps

module tb_dip_loader;
    logic clk = 1'b0;
    logic ioctl_wr = 1'b0;
    logic [15:0] ioctl_index = 16'd0;
    logic [26:0] ioctl_addr = 27'd0;
    logic [7:0] ioctl_data = 8'd0;
    logic [7:0] dsw1;
    logic [7:0] dsw2;
    logic [7:0] dsw3;

    always #5 clk = ~clk;

    gladiator_dip_loader dut (
        .clk(clk),
        .ioctl_wr(ioctl_wr),
        .ioctl_index(ioctl_index),
        .ioctl_addr(ioctl_addr),
        .ioctl_data(ioctl_data),
        .dsw1(dsw1),
        .dsw2(dsw2),
        .dsw3(dsw3)
    );

    task automatic send_byte(
        input logic [15:0] index,
        input logic [26:0] address,
        input logic [7:0] data
    );
        begin
            @(negedge clk);
            ioctl_index = index;
            ioctl_addr = address;
            ioctl_data = data;
            ioctl_wr = 1'b1;
            @(negedge clk);
            ioctl_wr = 1'b0;
        end
    endtask

    initial begin
        #1;
        if ({dsw1, dsw2, dsw3} !== 24'h5abfff)
            $fatal(1, "wrong power-up DIPs: %02x %02x %02x",
                   dsw1, dsw2, dsw3);

        // The real Main_MiSTer loader sends all eight bytes of its uint64_t
        // dip_cur value. Only addresses 0..2 belong to this board.
        send_byte(16'd254, 27'd0, 8'h9a);
        send_byte(16'd254, 27'd1, 8'hef);
        send_byte(16'd254, 27'd2, 8'hf7);
        send_byte(16'd254, 27'd3, 8'h33);
        send_byte(16'd254, 27'd4, 8'h00);
        send_byte(16'd254, 27'd5, 8'h00);
        send_byte(16'd254, 27'd6, 8'h00);
        send_byte(16'd254, 27'd7, 8'h00);

        if ({dsw1, dsw2, dsw3} !== 24'h9aeff7)
            $fatal(1,
                   "trailing DIP bytes aliased physical banks: %02x %02x %02x",
                   dsw1, dsw2, dsw3);

        // A non-DIP transfer must not mutate the banks either.
        send_byte(16'd0, 27'd0, 8'h00);
        if ({dsw1, dsw2, dsw3} !== 24'h9aeff7)
            $fatal(1, "non-DIP transfer mutated banks: %02x %02x %02x",
                   dsw1, dsw2, dsw3);

        $display("PASS tb_dip_loader");
        $finish;
    end
endmodule
