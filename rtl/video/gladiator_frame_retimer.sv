// MiSTer monitor-safe frame retimer.
//
// This is not part of the emulated Taito board. It captures the board's
// 256x224 active picture into three external-SDRAM banks and presents the
// newest complete frame on a user-selected, monitor-standard raster.
module gladiator_frame_retimer (
    input  logic        clk,
    input  logic        reset,

    input  logic        source_pixel_ce,
    input  logic [8:0]  source_h,
    input  logic [8:0]  source_v,
    input  logic [14:0] source_rgb555,

    input  logic [2:0]  profile,
    input  logic [4:0]  refresh_trim,

    output logic [25:0] write_address,
    output logic [15:0] write_data,
    output logic [1:0]  write_byte_enable,
    output logic        write_request,
    input  logic        write_ready,

    output logic [25:0] read_address,
    output logic        read_request,
    input  logic [63:0] read_data,
    input  logic        read_ready,

    output logic        pixel_ce,
    output logic [9:0]  h_count,
    output logic [9:0]  v_count,
    output logic [7:0]  red,
    output logic [7:0]  green,
    output logic [7:0]  blue,
    output logic        hblank,
    output logic        vblank,

    output logic [9:0]  h_total,
    output logic [9:0]  v_total,
    output logic [9:0]  default_hsync_start,
    output logic [9:0]  default_vsync_start,
    output logic [9:0]  default_hsync_width,
    output logic [3:0]  default_vsync_width,
    output logic [9:0]  content_x_start,
    output logic [9:0]  content_x_end,
    output logic [9:0]  content_y_start,
    output logic [9:0]  content_y_end,

    output logic        frame_available,
    output logic        writer_overrun,
    output logic        reader_underrun
);

    localparam logic [17:0] FRAME_WORDS = 18'h0e000;

    function automatic logic [17:0] bank_base(input logic [1:0] bank);
        case (bank)
            2'd0: bank_base = 18'h00000;
            2'd1: bank_base = 18'h0e000;
            default: bank_base = 18'h1c000;
        endcase
    endfunction

    function automatic logic [1:0] next_bank_avoiding (
        input logic [1:0] current,
        input logic [1:0] avoid
    );
        logic [1:0] candidate;
        begin
            candidate = (current == 2'd2) ? 2'd0 : current + 2'd1;
            if (candidate == avoid)
                candidate = (candidate == 2'd2) ? 2'd0 :
                            candidate + 2'd1;
            next_bank_avoiding = candidate;
        end
    endfunction

    // ------------------------------------------------------------------
    // Source-frame writer
    // ------------------------------------------------------------------

    logic [1:0] write_bank;
    logic [1:0] read_bank;
    logic [1:0] latest_bank;
    logic write_pending;
    logic write_inflight;
    logic write_is_last;
    logic [25:0] pending_address;
    logic [15:0] pending_data;

    logic [17:0] source_word;
    always_comb begin
        source_word = bank_base(write_bank) +
                      ({9'd0, source_v} - 18'd16) * 18'd256 +
                      {9'd0, source_h};
    end

    always_ff @(posedge clk) begin
        write_request <= 1'b0;

        if (reset) begin
            write_bank       <= 2'd0;
            latest_bank      <= 2'd0;
            write_pending    <= 1'b0;
            write_inflight   <= 1'b0;
            write_is_last    <= 1'b0;
            write_address    <= 26'd0;
            write_data       <= 16'd0;
            write_byte_enable <= 2'b11;
            frame_available  <= 1'b0;
            writer_overrun   <= 1'b0;
        end else begin
            if (source_pixel_ce && (source_h < 9'd256) &&
                (source_v >= 9'd16) && (source_v < 9'd240)) begin
                if (!write_pending && !write_inflight) begin
                    pending_address <= {8'd0, source_word};
                    pending_data    <= {1'b0, source_rgb555};
                    write_is_last   <= (source_h == 9'd255) &&
                                       (source_v == 9'd239);
                    write_pending   <= 1'b1;
                end else begin
                    writer_overrun <= 1'b1;
                end
            end

            if (write_pending && !write_inflight) begin
                write_address     <= pending_address;
                write_data        <= pending_data;
                write_byte_enable <= 2'b11;
                write_request     <= 1'b1;
                write_pending     <= 1'b0;
                write_inflight    <= 1'b1;
            end

            if (write_inflight && write_ready) begin
                write_inflight <= 1'b0;
                if (write_is_last) begin
                    latest_bank     <= write_bank;
                    frame_available <= 1'b1;
                    write_bank      <= next_bank_avoiding(write_bank,
                                                          read_bank);
                    write_is_last   <= 1'b0;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Output raster profiles
    // ------------------------------------------------------------------

    logic [31:0] base_step;
    logic signed [31:0] signed_trim;
    logic [31:0] selected_step;
    logic [31:0] phase_accumulator;
    logic [2:0] profile_d;
    logic [9:0] active_width;
    logic [9:0] active_height;
    logic doubled;

    always_comb begin
        base_step           = 32'h101c_a495;
        h_total             = 10'd384;
        v_total             = 10'd262;
        active_width        = 10'd320;
        active_height       = 10'd240;
        default_hsync_start = 10'd328;
        default_vsync_start = 10'd244;
        default_hsync_width = 10'd32;
        default_vsync_width = 4'd3;
        content_x_start     = 10'd32;
        content_x_end       = 10'd288;
        content_y_start     = 10'd8;
        content_y_end       = 10'd232;
        doubled             = 1'b0;

        case (profile)
            3'd1: begin // 15.734264 kHz, 60.0544 Hz
                base_step = 32'h101c_a495;
            end
            3'd2: begin // exact 59.94 Hz on 384x262
                base_step = 32'h1014_c864;
            end
            3'd3: begin // 15.625 kHz PAL-family 288p, 50.0801 Hz
                base_step           = 32'h1000_0000;
                v_total             = 10'd312;
                active_width        = 10'd288;
                active_height       = 10'd288;
                default_hsync_start = 10'd304;
                default_vsync_start = 10'd300;
                content_x_start     = 10'd16;
                content_x_end       = 10'd272;
                content_y_start     = 10'd32;
                content_y_end       = 10'd256;
            end
            3'd4: begin // VGA 640x480 at 59.94 Hz
                base_step           = 32'h4322_2222;
                h_total             = 10'd800;
                v_total             = 10'd525;
                active_width        = 10'd640;
                active_height       = 10'd480;
                default_hsync_start = 10'd656;
                default_vsync_start = 10'd490;
                default_hsync_width = 10'd96;
                default_vsync_width = 4'd2;
                content_x_start     = 10'd64;
                content_x_end       = 10'd576;
                content_y_start     = 10'd16;
                content_y_end       = 10'd464;
                doubled             = 1'b1;
            end
            3'd5: begin // VGA 640x480 at 60.00 Hz
                base_step           = 32'h4333_3333;
                h_total             = 10'd800;
                v_total             = 10'd525;
                active_width        = 10'd640;
                active_height       = 10'd480;
                default_hsync_start = 10'd656;
                default_vsync_start = 10'd490;
                default_hsync_width = 10'd96;
                default_vsync_width = 4'd2;
                content_x_start     = 10'd64;
                content_x_end       = 10'd576;
                content_y_start     = 10'd16;
                content_y_end       = 10'd464;
                doubled             = 1'b1;
            end
            3'd6: begin // VGA 720x576 at 50.00 Hz
                base_step           = 32'h4800_0000;
                h_total             = 10'd864;
                v_total             = 10'd625;
                active_width        = 10'd720;
                active_height       = 10'd576;
                default_hsync_start = 10'd732;
                default_vsync_start = 10'd581;
                default_hsync_width = 10'd64;
                default_vsync_width = 4'd5;
                content_x_start     = 10'd104;
                content_x_end       = 10'd616;
                content_y_start     = 10'd64;
                content_y_end       = 10'd512;
                doubled             = 1'b1;
            end
            3'd7: begin // fixed 60.000 Hz 384x262 service profile
                base_step = 32'h1018_e758;
            end
            default: ;
        endcase

        signed_trim = $signed({{27{refresh_trim[4]}}, refresh_trim}) *
                      32'sd45000;
        selected_step = base_step + signed_trim;
        hblank = h_count >= active_width;
        vblank = v_count >= active_height;
    end

    always_ff @(posedge clk) begin
        {pixel_ce, phase_accumulator} <=
            {1'b0, phase_accumulator} + {1'b0, selected_step};

        if (reset) begin
            phase_accumulator <= 32'd0;
            pixel_ce          <= 1'b0;
            h_count           <= 10'd0;
            v_count           <= 10'd0;
            profile_d         <= profile;
        end else if (profile != profile_d) begin
            profile_d <= profile;
            h_count   <= 10'd0;
            v_count   <= 10'd0;
        end else if (pixel_ce) begin
            if (h_count == h_total - 10'd1) begin
                h_count <= 10'd0;
                if (v_count == v_total - 10'd1)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 10'd1;
            end else begin
                h_count <= h_count + 10'd1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Four-pixel line fetcher
    // ------------------------------------------------------------------

    logic [15:0] line_buffer [0:255];
    logic [7:0] loaded_source_y;
    logic line_valid;
    logic read_inflight;
    logic [5:0] read_chunk;
    logic [7:0] requested_source_y;
    logic prefetch_pending;
    logic [7:0] prefetch_source_y;
    logic reader_active;

    logic current_content;
    logic [8:0] current_source_x;
    logic [7:0] current_source_y;
    logic last_content_pixel;

    always_comb begin
        current_content = (h_count >= content_x_start) &&
                          (h_count < content_x_end) &&
                          (v_count >= content_y_start) &&
                          (v_count < content_y_end);
        if (doubled) begin
            current_source_x = (h_count - content_x_start) >> 1;
            current_source_y = (v_count - content_y_start) >> 1;
        end else begin
            current_source_x = h_count - content_x_start;
            current_source_y = v_count - content_y_start;
        end
        last_content_pixel = current_content &&
                             (h_count == content_x_end - 10'd1);
    end

    always_ff @(posedge clk) begin
        read_request <= 1'b0;

        if (reset) begin
            read_bank          <= 2'd1;
            read_address       <= 26'd0;
            read_inflight      <= 1'b0;
            read_chunk         <= 6'd0;
            requested_source_y <= 8'd0;
            prefetch_pending   <= 1'b0;
            prefetch_source_y  <= 8'd0;
            loaded_source_y    <= 8'd0;
            line_valid         <= 1'b0;
            reader_active      <= 1'b0;
            reader_underrun    <= 1'b0;
        end else begin
            if (profile != profile_d) begin
                line_valid         <= 1'b0;
                reader_active      <= 1'b0;
                prefetch_pending   <= 1'b1;
                prefetch_source_y  <= 8'd0;
            end

            if (pixel_ce && (h_count == 10'd0) && (v_count == 10'd0) &&
                frame_available) begin
                read_bank         <= latest_bank;
                reader_active     <= 1'b1;
                line_valid        <= 1'b0;
                prefetch_pending  <= 1'b1;
                prefetch_source_y <= 8'd0;
            end

            if (pixel_ce && last_content_pixel) begin
                if ((!doubled || v_count[0]) &&
                    (current_source_y < 8'd223)) begin
                    prefetch_pending  <= 1'b1;
                    prefetch_source_y <= current_source_y + 8'd1;
                end
            end

            if (prefetch_pending && !read_inflight) begin
                requested_source_y <= prefetch_source_y;
                read_chunk         <= 6'd0;
                line_valid         <= 1'b0;
                prefetch_pending   <= 1'b0;
                read_address <= {8'd0, bank_base(read_bank) +
                                 ({10'd0, prefetch_source_y} * 18'd256)};
                read_request  <= 1'b1;
                read_inflight <= 1'b1;
            end

            if (read_inflight && read_ready) begin
                line_buffer[{read_chunk, 2'b00} + 8'd0] <= read_data[15:0];
                line_buffer[{read_chunk, 2'b00} + 8'd1] <= read_data[31:16];
                line_buffer[{read_chunk, 2'b00} + 8'd2] <= read_data[47:32];
                line_buffer[{read_chunk, 2'b00} + 8'd3] <= read_data[63:48];
                read_inflight <= 1'b0;

                if (read_chunk == 6'd63) begin
                    loaded_source_y <= requested_source_y;
                    line_valid      <= 1'b1;
                end else begin
                    read_chunk  <= read_chunk + 6'd1;
                    read_address <= read_address + 26'd4;
                    read_request <= 1'b1;
                    read_inflight <= 1'b1;
                end
            end

            if (pixel_ce && reader_active && current_content &&
                (!line_valid || loaded_source_y != current_source_y))
                reader_underrun <= 1'b1;
        end
    end

    logic [14:0] output_rgb555;
    always_comb begin
        output_rgb555 = 15'd0;
        if (current_content && line_valid &&
            (loaded_source_y == current_source_y))
            output_rgb555 = line_buffer[current_source_x[7:0]][14:0];

        red   = {output_rgb555[14:10], output_rgb555[14:12]};
        green = {output_rgb555[9:5],   output_rgb555[9:7]};
        blue  = {output_rgb555[4:0],   output_rgb555[4:2]};
    end

endmodule
