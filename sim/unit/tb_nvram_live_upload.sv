`timescale 1ns/1ps

module tb_nvram_live_upload;
    logic clk = 0;
    always #5 clk = ~clk;

    logic reset = 1;
    logic [15:0] cpu_address = 0;
    logic [7:0] cpu_data_out = 0;
    logic [7:0] cpu_data_in;
    logic cpu_m1_n = 1;
    logic cpu_mreq_n = 1;
    logic cpu_iorq_n = 1;
    logic cpu_rd_n = 1;
    logic cpu_wr_n = 1;
    logic [16:0] rom_address;
    logic [7:0] ucpu_data_out;
    logic [7:0] nvram_host_data_out;
    logic nvram_dirty;
    logic nvram_host_enable = 0;
    logic nvram_host_write = 0;
    logic [10:0] nvram_host_address = 0;
    logic [7:0] nvram_host_data_in = 0;

    gladiator_main_bus dut (
        .clk(clk),
        .reset(reset),
        .cpu_address(cpu_address),
        .cpu_data_out(cpu_data_out),
        .cpu_data_in(cpu_data_in),
        .cpu_m1_n(cpu_m1_n),
        .cpu_mreq_n(cpu_mreq_n),
        .cpu_iorq_n(cpu_iorq_n),
        .cpu_rd_n(cpu_rd_n),
        .cpu_wr_n(cpu_wr_n),
        .rom_address(rom_address),
        .rom_data(8'hff),
        .vblank_irq_set(1'b0),
        .main_int_n(),
        .ucpu_cs_n(),
        .ucpu_a0(),
        .ucpu_rd_n(),
        .ucpu_wr_n(),
        .ucpu_data_out(ucpu_data_out),
        .ucpu_data_in(8'hff),
        .compat_sub_irq_set(),
        .sub_reset(),
        .sprite_buffer(),
        .sprite_bank_base(),
        .program_bank(),
        .flip_screen(),
        .unknown_latch_bits(),
        .fg_scrolly(),
        .fg_scrollx(),
        .bg_scrolly(),
        .bg_scrollx(),
        .video_attributes(),
        .video_bg_address(11'd0),
        .video_bg_code(),
        .video_bg_attr(),
        .video_fg_address(11'd0),
        .video_fg_code(),
        .video_palette_address(10'd0),
        .video_palette_low(),
        .video_palette_ext(),
        .video_sprite_address(12'd0),
        .video_sprite_data(),
        .nvram_host_enable(nvram_host_enable),
        .nvram_host_write(nvram_host_write),
        .nvram_host_address(nvram_host_address),
        .nvram_host_data_in(nvram_host_data_in),
        .nvram_host_data_out(nvram_host_data_out),
        .nvram_dirty(nvram_dirty),
        .trace_mem_read(),
        .trace_mem_write(),
        .trace_io_read(),
        .trace_io_write()
    );

    task automatic cpu_write(
        input logic [10:0] address,
        input logic [7:0] data
    );
        begin
            @(negedge clk);
            cpu_address = 16'hf000 + address;
            cpu_data_out = data;
            cpu_mreq_n = 1'b0;
            cpu_wr_n = 1'b0;
            @(negedge clk);
            cpu_mreq_n = 1'b1;
            cpu_wr_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic expect_cpu_read(
        input logic [10:0] address,
        input logic [7:0] expected,
        input string label
    );
        begin
            @(negedge clk);
            cpu_address = 16'hf000 + address;
            cpu_mreq_n = 1'b0;
            cpu_rd_n = 1'b0;
            repeat (2) @(posedge clk);
            #1;
            if (cpu_data_in !== expected)
                $fatal(
                    1,
                    "%s: CPU read %02x, expected %02x",
                    label,
                    cpu_data_in,
                    expected
                );
            @(negedge clk);
            cpu_mreq_n = 1'b1;
            cpu_rd_n = 1'b1;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);

        // Appliance download while the reconstructed board is reset.
        nvram_host_enable = 1'b1;
        nvram_host_write = 1'b1;
        nvram_host_address = 11'h123;
        nvram_host_data_in = 8'haa;
        repeat (2) @(posedge clk);
        nvram_host_write = 1'b0;
        nvram_host_enable = 1'b0;
        reset = 1'b0;
        repeat (3) @(posedge clk);

        cpu_write(11'h000, 8'h11);
        if (!nvram_dirty)
            $fatal(1, "CPU write did not dirty NVRAM");

        // Start a live MiSTer upload at an unrelated address. It acknowledges
        // the old generation but must not replace the CPU's read address.
        @(negedge clk);
        nvram_host_enable = 1'b1;
        nvram_host_address = 11'h123;
        repeat (2) @(posedge clk);
        #1;
        if (nvram_host_data_out !== 8'haa)
            $fatal(1, "host upload readback failed");
        if (nvram_dirty)
            $fatal(1, "upload start did not acknowledge dirty generation");
        expect_cpu_read(
            11'h000,
            8'h11,
            "live upload stole CPU NVRAM address"
        );

        // A write made after upload start belongs to a new generation. It
        // must commit and remain dirty while host reads continue.
        cpu_write(11'h001, 8'h22);
        if (!nvram_dirty)
            $fatal(1, "live CPU write was not retained as a new generation");
        nvram_host_address = 11'h123;
        expect_cpu_read(
            11'h001,
            8'h22,
            "live upload suppressed CPU NVRAM write"
        );
        if (!nvram_dirty)
            $fatal(1, "ongoing upload cleared a later dirty generation");

        nvram_host_enable = 1'b0;
        repeat (2) @(posedge clk);
        expect_cpu_read(11'h000, 8'h11, "first CPU state byte changed");
        expect_cpu_read(11'h001, 8'h22, "second CPU state byte changed");

        $display("PASS tb_nvram_live_upload");
        $finish;
    end
endmodule
