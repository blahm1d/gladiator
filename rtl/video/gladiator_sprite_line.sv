// VID-SPR-001
// Builds the next scanline from the physical sprite list while the current
// line is displayed. Ascending entries and non-zero pen overwrite reproduce
// the board/MAME priority convention.
module gladiator_sprite_line (
    input  logic        clk,
    input  logic        reset,
    input  logic        start_line,
    // Pulsed at the END of the previous line. start_line fires at h==0,
    // the same edge the x=0 pixel is sampled, so swapping the display
    // buffer there makes x=0 read the PREVIOUS line -- measured as 20
    // stale pixels, all at x==0, across frames 180 and 2400. Swapping a
    // pixel earlier lets x=0 see the line that was just built.
    input  logic        swap_display,
    input  logic [8:0]  target_line,
    input  logic        sprite_buffer,
    input  logic [2:0]  sprite_bank_base,
    input  logic        flip_screen,

    output logic [11:0] sprite_ram_address,
    input  logic [7:0]  sprite_ram_data,
    output logic [16:0] sprite_plane0_address,
    input  logic [7:0]  sprite_plane0_data,
    output logic [16:0] sprite_plane12_address,
    input  logic [7:0]  sprite_plane12_data,

    input  logic [7:0]  display_x,
    output logic [9:0]  display_palette_index,
    output logic        busy,
    output logic [15:0] overrun_count
);

    typedef enum logic [3:0] {
        IDLE,
        CLEAR,
        FETCH,
        FETCH_DRAIN,
        EVALUATE,
        EVALUATE_BOUNDS,
        EVALUATE_COMMIT,
        RENDER,
        RENDER_DRAIN,
        RENDER_DRAIN_2
    } state_t;

    state_t state;
    // MLAB, not M10K: the device is at 544/553 M10K blocks but only 44% ALMs,
    // so the line buffers go in ALM memory where there is headroom.
    //
    // These were previously read ASYNCHRONOUSLY (display_palette_index was a
    // combinational index), which M10K/MLAB cannot do -- the fitter built them
    // as ~5,120 discrete registers plus two 256:1 muxes feeding the video path.
    // map.rpt confirms it: no inferred RAM instance for line_buffer at all.
    // That is the project rule against async multi-read windows, broken in the
    // one subsystem that renders correctly in simulation and fails on the cab.
    //
    // no_rw_check is NOT used here even though a collision is structurally
    // impossible (an array is either the build target or the display source,
    // never both, because display_select and build_select are always opposite).
    // Today's fit failure was caused by getting that attribute wrong, so the
    // safer default is to let the fitter choose.
    (* ramstyle = "MLAB" *) logic [9:0] line_buffer0 [0:255];
    (* ramstyle = "MLAB" *) logic [9:0] line_buffer1 [0:255];
    logic [9:0] display_q0, display_q1;
    logic display_select, build_select;
    logic line_write_enable;
    logic [7:0] line_write_address;
    logic [9:0] line_write_data;
    logic [7:0] clear_x;
    logic [6:0] entry_offset;
    logic [2:0] fetch_phase;
    logic       fetch_valid_d;
    logic [2:0] fetch_tag_d;

    logic [7:0] desc_code;
    logic [7:0] desc_color;
    logic [7:0] desc_y;
    logic [7:0] desc_x;
    logic [7:0] desc_attr;
    logic [7:0] desc_xhi;

    logic [8:0] line_latched;
    logic [5:0] issue_pixel;
    logic [5:0] sprite_width;
    logic [5:0] source_y;
    logic signed [10:0] sprite_x;
    logic [10:0] tile_base;
    logic x_flip, y_flip;
    logic [4:0] color_group;
    logic signed [10:0] evaluated_sy;
    logic [5:0] evaluated_width;
    logic [2:0] evaluated_bank;
    logic       evaluated_hit;
    logic [5:0] evaluated_source_y;

    logic render_issue;
    logic render_valid_d;
    logic [7:0] render_x_d;
    logic [1:0] render_bit_d;
    logic [9:0] render_palette_base_d;
    logic [2:0] render_pen;
    logic       render_commit_valid;
    logic [7:0] render_commit_x;
    logic [9:0] render_commit_palette_base;
    logic [2:0] render_commit_pen;

    logic [5:0] source_x_now;
    logic [5:0] source_y_now;
    logic [1:0] tile_offset_now;
    logic [11:0] tile_number_now;
    logic [16:0] sprite_byte_now;
    logic signed [11:0] screen_x_now;

    // Registered read so this infers real memory.  Behaviourally identical to
    // the old combinational index: display_x only changes on pixel_ce (every 16
    // clk cycles), and gladiator_video samples sprite_palette_index on that same
    // pixel_ce edge -- so the registered value it sees is the one addressed by
    // the pre-edge display_x, exactly as before.
    always_ff @(posedge clk) begin
        display_q0 <= line_buffer0[display_x];
        display_q1 <= line_buffer1[display_x];
    end
    assign display_palette_index = display_select ? display_q1 : display_q0;
    assign busy = state != IDLE;

    always_comb begin
        // One physical write port per array. Keeping CLEAR and RENDER as
        // separate nonblocking assignments made Quartus treat each buffer as
        // a multi-write structure and implement it in logic despite the MLAB
        // attribute. These operations are state-exclusive; encode that fact
        // before the memory write so inference sees one enable/address/data.
        line_write_enable = 1'b0;
        line_write_address = 8'd0;
        line_write_data = 10'd0;
        if (state == CLEAR) begin
            line_write_enable = 1'b1;
            line_write_address = clear_x;
        end else if (render_commit_valid && render_commit_pen != 3'd0) begin
            line_write_enable = 1'b1;
            line_write_address = render_commit_x;
            line_write_data = render_commit_palette_base + render_commit_pen;
        end

        sprite_ram_address = 12'd0;
        if (state == FETCH) begin
            case (fetch_phase)
                3'd0: sprite_ram_address = {5'd0, entry_offset} +
                                              (sprite_buffer ? 12'h080 : 12'h000);
                3'd1: sprite_ram_address = {5'd0, entry_offset} +
                                              (sprite_buffer ? 12'h081 : 12'h001);
                3'd2: sprite_ram_address = 12'h400 + {5'd0, entry_offset} +
                                              (sprite_buffer ? 12'h080 : 12'h000);
                3'd3: sprite_ram_address = 12'h400 + {5'd0, entry_offset} +
                                              (sprite_buffer ? 12'h081 : 12'h001);
                3'd4: sprite_ram_address = 12'h800 + {5'd0, entry_offset} +
                                              (sprite_buffer ? 12'h080 : 12'h000);
                default: sprite_ram_address = 12'h800 + {5'd0, entry_offset} +
                                              (sprite_buffer ? 12'h081 : 12'h001);
            endcase
        end

        screen_x_now = sprite_x + $signed({1'b0, issue_pixel});
        source_x_now = x_flip ? (sprite_width - 6'd1 - issue_pixel) :
                                issue_pixel;
        source_y_now = y_flip ? (sprite_width - 6'd1 - source_y) : source_y;
        tile_offset_now = {source_y_now[4], source_x_now[4]};
        tile_number_now = tile_base + tile_offset_now;
        sprite_byte_now = {tile_number_now[10:0], 6'd0} +
                          (source_y_now[3] ? 17'd32 : 17'd0) +
                          {11'd0, source_y_now[2:0]} +
                          ({15'd0, source_x_now[3:2]} << 3);

        render_issue = (state == RENDER) &&
                       (issue_pixel < sprite_width) &&
                       (screen_x_now >= 0) && (screen_x_now < 256);
        sprite_plane0_address  = sprite_byte_now;
        sprite_plane12_address = sprite_byte_now;
        render_pen = {
            sprite_plane0_data[3 - render_bit_d],
            sprite_plane12_data[7 - render_bit_d],
            sprite_plane12_data[3 - render_bit_d]
        };
    end

    always_ff @(posedge clk) begin
        fetch_valid_d <= state == FETCH;
        fetch_tag_d   <= fetch_phase;
        render_valid_d <= render_issue;
        render_x_d <= screen_x_now[7:0];
        render_bit_d <= source_x_now[1:0];
        render_palette_base_d <= 10'h100 + {color_group, 3'b000};
        render_commit_valid <= render_valid_d;
        render_commit_x <= render_x_d;
        render_commit_palette_base <= render_palette_base_d;
        render_commit_pen <= render_pen;

        // Keep the synchronous sprite ROM output off the high-fanout
        // line-buffer enables. This commit stage is a physical pipeline
        // register; RENDER_DRAIN_2 accounts for its added cycle.
        if (line_write_enable) begin
            if (build_select)
                line_buffer1[line_write_address] <= line_write_data;
            else
                line_buffer0[line_write_address] <= line_write_data;
        end

        if (fetch_valid_d) begin
            case (fetch_tag_d)
                3'd0: desc_code  <= sprite_ram_data;
                3'd1: desc_color <= sprite_ram_data;
                3'd2: desc_y     <= sprite_ram_data;
                3'd3: desc_x     <= sprite_ram_data;
                3'd4: desc_attr  <= sprite_ram_data;
                3'd5: desc_xhi   <= sprite_ram_data;
                default: ;
            endcase
        end

        if (reset) begin
            state           <= IDLE;
            display_select  <= 1'b0;
            build_select    <= 1'b1;
            overrun_count   <= 16'd0;
            render_valid_d  <= 1'b0;
            render_commit_valid <= 1'b0;
            fetch_valid_d   <= 1'b0;
        end else begin
            if (swap_display)
                display_select <= build_select;

            if (start_line) begin
                if (state != IDLE)
                    overrun_count <= overrun_count + 16'd1;
                build_select   <= !build_select;
                line_latched   <= target_line;
                clear_x        <= 8'd0;
                state          <= CLEAR;
                render_valid_d <= 1'b0;
                render_commit_valid <= 1'b0;
                fetch_valid_d  <= 1'b0;
            end else begin
                case (state)
                    IDLE: ;

                    CLEAR: begin
                        if (clear_x == 8'hff) begin
                            entry_offset <= 7'd0;
                            fetch_phase  <= 3'd0;
                            state        <= FETCH;
                        end else begin
                            clear_x <= clear_x + 8'd1;
                        end
                    end

                    FETCH: begin
                        if (fetch_phase == 3'd5)
                            state <= FETCH_DRAIN;
                        else
                            fetch_phase <= fetch_phase + 3'd1;
                    end

                    FETCH_DRAIN: begin
                        fetch_valid_d <= 1'b0;
                        state <= EVALUATE;
                    end

                    // Descriptor evaluation is deliberately staged. The
                    // physical list scanner has ample blanking time, while a
                    // one-cycle range/coordinate/commit expression creates a
                    // long combinational path at the 96 MHz master rate.
                    EVALUATE: begin
                        evaluated_width <= desc_attr[4] ? 6'd32 : 6'd16;
                        evaluated_sy <= 11'sd240 -
                                        $signed({3'd0, desc_y}) -
                                        (desc_attr[4] ? 11'sd16 : 11'sd0);
                        evaluated_bank <= desc_attr[1] ?
                                          (sprite_bank_base + desc_attr[0]) :
                                          {2'd0, desc_attr[0]};
                        state <= EVALUATE_BOUNDS;
                    end

                    EVALUATE_BOUNDS: begin : evaluate_sprite_bounds
                        integer signed sy;
                        integer signed rel;
                        integer signed width_i;
                        sy = $signed(evaluated_sy);
                        width_i = evaluated_width;
                        rel = -1;
                        if (($signed({1'b0, line_latched}) >= sy) &&
                            ($signed({1'b0, line_latched}) < sy + width_i))
                            rel = $signed({1'b0, line_latched}) - sy;
                        else if (($signed({1'b0, line_latched}) >= sy + 256) &&
                                 ($signed({1'b0, line_latched}) < sy + 256 + width_i))
                            rel = $signed({1'b0, line_latched}) - (sy + 256);

                        evaluated_hit <= rel >= 0;
                        evaluated_source_y <= rel[5:0];
                        state <= EVALUATE_COMMIT;
                    end

                    EVALUATE_COMMIT: begin
                        if (evaluated_hit) begin
                            sprite_width <= evaluated_width;
                            source_y     <= evaluated_source_y;
                            sprite_x     <= $signed({3'd0, desc_x}) +
                                            (desc_xhi[0] ? 11'sd256 : 11'sd0) -
                                            11'sd56;
                            tile_base    <= {evaluated_bank, desc_code};
                            x_flip       <= desc_attr[2] ^ flip_screen;
                            y_flip       <= desc_attr[3] ^ flip_screen;
                            color_group  <= desc_color[4:0];
                            issue_pixel  <= 6'd0;
                            state        <= RENDER;
                        end else if (entry_offset == 7'h7e) begin
                            state <= IDLE;
                        end else begin
                            entry_offset <= entry_offset + 7'd2;
                            fetch_phase  <= 3'd0;
                            state        <= FETCH;
                        end
                    end

                    RENDER: begin
                        if (issue_pixel == sprite_width - 6'd1)
                            state <= RENDER_DRAIN;
                        else
                            issue_pixel <= issue_pixel + 6'd1;
                    end

                    RENDER_DRAIN: begin
                        render_valid_d <= 1'b0;
                        state <= RENDER_DRAIN_2;
                    end

                    RENDER_DRAIN_2: begin
                        if (entry_offset == 7'h7e) begin
                            state <= IDLE;
                        end else begin
                            entry_offset <= entry_offset + 7'd2;
                            fetch_phase  <= 3'd0;
                            state        <= FETCH;
                        end
                    end

                    default: state <= IDLE;
                endcase
            end
        end
    end

endmodule
