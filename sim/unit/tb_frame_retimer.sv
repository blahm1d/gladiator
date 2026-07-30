`timescale 1ns/1ps

module tb_frame_retimer;
    logic clk = 0;
    always #5 clk = ~clk;

    logic reset = 1;
    logic source_pixel_ce = 0;
    logic [8:0] source_h = 0;
    logic [8:0] source_v = 9'd16;
    logic [14:0] source_rgb555 = 0;
    logic [2:0] profile = 3'd1;
    logic [4:0] refresh_trim = 5'd0;

    logic [25:0] write_address;
    logic [15:0] write_data;
    logic [1:0] write_byte_enable;
    logic write_request, write_ready = 0;
    logic [25:0] read_address;
    logic read_request, read_ready = 0;
    logic [63:0] read_data = 0;
    logic pixel_ce;
    logic [9:0] h_count, v_count;
    logic [7:0] red, green, blue;
    logic hblank, vblank;
    logic [9:0] h_total, v_total;
    logic [9:0] default_hsync_start, default_vsync_start;
    logic [9:0] default_hsync_width;
    logic [3:0] default_vsync_width;
    logic [9:0] content_x_start, content_x_end;
    logic [9:0] content_y_start, content_y_end;
    logic frame_available, writer_overrun, reader_underrun;

    gladiator_frame_retimer dut (.*);

    logic [15:0] memory [0:18'h2a000-1];
    integer write_delay = -1;
    integer read_delay = -1;
    logic [25:0] saved_write_address;
    logic [15:0] saved_write_data;
    logic [25:0] saved_read_address;

    always_ff @(posedge clk) begin
        write_ready <= 1'b0;
        read_ready <= 1'b0;

        if (write_request) begin
            if (write_delay >= 0)
                $fatal(1, "overlapping write request");
            saved_write_address <= write_address;
            saved_write_data <= write_data;
            write_delay <= 2;
        end
        if (write_delay == 0) begin
            memory[saved_write_address] <= saved_write_data;
            write_ready <= 1'b1;
            write_delay <= -1;
        end else if (write_delay > 0) begin
            write_delay <= write_delay - 1;
        end

        if (read_request) begin
            if (read_delay >= 0)
                $fatal(1, "overlapping read request");
            saved_read_address <= read_address;
            read_delay <= 6;
        end
        if (read_delay == 0) begin
            read_data <= {
                memory[saved_read_address + 3],
                memory[saved_read_address + 2],
                memory[saved_read_address + 1],
                memory[saved_read_address + 0]
            };
            read_ready <= 1'b1;
            read_delay <= -1;
        end else if (read_delay > 0) begin
            read_delay <= read_delay - 1;
        end
    end

    function automatic logic [14:0] test_pixel (
        input logic [7:0] x,
        input logic [7:0] y
    );
        test_pixel = {x[4:0], y[4:0], (x[4:0] ^ y[4:0])};
    endfunction

    task automatic send_source_frame;
        integer x;
        integer y;
        integer gap;
        begin
            for (y = 0; y < 224; y = y + 1) begin
                for (x = 0; x < 256; x = x + 1) begin
                    @(negedge clk);
                    source_h <= x[8:0];
                    source_v <= y[8:0] + 9'd16;
                    source_rgb555 <= test_pixel(x[7:0], y[7:0]);
                    source_pixel_ce <= 1'b1;
                    @(negedge clk);
                    source_pixel_ce <= 1'b0;
                    for (gap = 0; gap < 14; gap = gap + 1)
                        @(negedge clk);
                end
            end
        end
    endtask

    task automatic check_profile (
        input logic [2:0] requested_profile,
        input logic [9:0] expected_h_total,
        input logic [9:0] expected_v_total
    );
        begin
            profile <= requested_profile;
            repeat (3) @(posedge clk);
            if (h_total !== expected_h_total || v_total !== expected_v_total)
                $fatal(1, "profile %0d totals %0dx%0d, expected %0dx%0d",
                       requested_profile, h_total, v_total,
                       expected_h_total, expected_v_total);
        end
    endtask

    task automatic wait_output_pixel (
        input logic [9:0] wanted_h,
        input logic [9:0] wanted_v,
        input integer limit
    );
        integer count;
        begin
            count = 0;
            while (!(pixel_ce && h_count == wanted_h &&
                     v_count == wanted_v) && count < limit) begin
                @(posedge clk);
                count = count + 1;
            end
            if (count == limit)
                $fatal(1, "timed out waiting for output pixel %0d,%0d",
                       wanted_h, wanted_v);
        end
    endtask

    task automatic expect_output_pixel (
        input logic [7:0] source_x,
        input logic [7:0] source_y
    );
        logic [14:0] sampled;
        begin
            sampled = {red[7:3], green[7:3], blue[7:3]};
            if (sampled !== test_pixel(source_x, source_y))
                $fatal(1, "retimed pixel %h, expected source %0d,%0d = %h",
                       sampled, source_x, source_y,
                       test_pixel(source_x, source_y));
        end
    endtask

    integer timeout;
    logic [14:0] observed_rgb;
    initial begin
        repeat (8) @(posedge clk);
        reset <= 1'b0;

        send_source_frame();
        timeout = 0;
        while (!frame_available && timeout < 1000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!frame_available)
            $fatal(1, "source frame never committed");
        if (writer_overrun)
            $fatal(1, "writer overrun with two-cycle memory");

        // Wait for the first displayed source pixel in a complete retimed
        // output frame.
        timeout = 0;
        while (!(pixel_ce && h_count == 10'd32 && v_count == 10'd8) &&
               timeout < 3000000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout == 3000000)
            $fatal(1, "timed out waiting for retimed content");
        observed_rgb = {red[7:3], green[7:3], blue[7:3]};
        if (observed_rgb !== test_pixel(8'd0, 8'd0))
            $fatal(1, "first retimed pixel %h, expected %h",
                   observed_rgb, test_pixel(8'd0, 8'd0));
        if (reader_underrun)
            $fatal(1, "reader underrun with six-cycle memory");

        wait_output_pixel(10'd287, 10'd8, 100000);
        expect_output_pixel(8'd255, 8'd0);
        wait_output_pixel(10'd32, 10'd9, 100000);
        expect_output_pixel(8'd0, 8'd1);

        check_profile(3'd2, 10'd384, 10'd262);
        check_profile(3'd3, 10'd384, 10'd312);
        check_profile(3'd4, 10'd800, 10'd525);

        // The VGA path doubles pixels and lines without modifying the stored
        // board-domain frame.
        wait_output_pixel(10'd64, 10'd16, 3000000);
        expect_output_pixel(8'd0, 8'd0);
        wait_output_pixel(10'd65, 10'd16, 1000);
        expect_output_pixel(8'd0, 8'd0);
        wait_output_pixel(10'd66, 10'd16, 1000);
        expect_output_pixel(8'd1, 8'd0);
        wait_output_pixel(10'd64, 10'd17, 100000);
        expect_output_pixel(8'd0, 8'd0);
        wait_output_pixel(10'd64, 10'd18, 100000);
        expect_output_pixel(8'd0, 8'd1);
        if (reader_underrun)
            $fatal(1, "VGA reader underrun with six-cycle memory");

        check_profile(3'd5, 10'd800, 10'd525);
        check_profile(3'd6, 10'd864, 10'd625);
        check_profile(3'd7, 10'd384, 10'd262);

        $display("PASS tb_frame_retimer");
        $finish;
    end
endmodule
