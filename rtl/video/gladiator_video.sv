// VID-COMP-001, VID-PAL-001, VID-SCROLL-001
module gladiator_video (
    input  logic        clk,
    input  logic        reset,
    input  logic        pixel_ce,
    input  logic [8:0]  h_count,
    input  logic [8:0]  v_count,
    input  logic        hblank_in,
    input  logic        vblank_in,
    input  logic        hsync_in,
    input  logic        vsync_in,

    input  logic        flip_screen,
    input  logic [7:0]  fg_scrolly,
    input  logic [7:0]  fg_scrollx,
    input  logic [7:0]  bg_scrolly,
    input  logic [7:0]  bg_scrollx,
    input  logic [7:0]  video_attributes,

    output logic [10:0] video_bg_address,
    input  logic [7:0]  video_bg_code,
    input  logic [7:0]  video_bg_attr,
    output logic [10:0] video_fg_address,
    input  logic [7:0]  video_fg_code,
    output logic [9:0]  video_palette_address,
    input  logic [7:0]  video_palette_low,
    input  logic [7:0]  video_palette_ext,

    output logic [12:0] text_rom_address,
    input  logic [7:0]  text_rom_data,
    output logic [15:0] bg_plane0_address,
    input  logic [7:0]  bg_plane0_data,
    output logic [15:0] bg_plane12_address,
    input  logic [7:0]  bg_plane12_data,

    input  logic [9:0]  sprite_palette_index,

    output logic [14:0] rgb555,
    output logic        hblank,
    output logic        vblank,
    output logic        hsync,
    output logic        vsync,
    output logic        valid_pixel,
    output logic        pixel_strobe,
    output logic [8:0]  output_h_count,
    output logic [8:0]  output_v_count
);

    logic [8:0] screen_x, screen_y;
    logic [9:0] bg_world_x, fg_world_x;
    logic [8:0] bg_world_y, fg_world_y;
    logic [8:0] bg_scroll, fg_scroll;

    logic [2:0] s0_bg_x;
    logic [2:0] s0_bg_y;
    logic [2:0] s0_fg_x;
    logic [2:0] s0_fg_y;
    logic [9:0] s0_sprite_index;
    logic s0_display;
    logic s0_hblank, s0_vblank, s0_hsync, s0_vsync;
    logic [8:0] s0_h_count, s0_v_count;
    logic pipeline_valid_0, pipeline_valid_1, pipeline_valid_2;
    logic pipeline_valid_3;

    logic [11:0] bg_tile_code;
    logic [9:0]  fg_tile_code;
    logic [15:0] bg_byte_address;
    logic [12:0] fg_byte_address;
    logic [2:0] bg_pen;
    logic fg_pen;
    logic [4:0] bg_color;
    logic [4:0] s0_bg_color;
    logic [9:0] selected_palette_index;
    logic [14:0] decoded_rgb;

    always_comb begin
        screen_x = flip_screen ? (9'd255 - h_count) : h_count;
        screen_y = flip_screen ? (9'd255 - v_count) : v_count;
        bg_scroll = {video_attributes[2], bg_scrollx};
        fg_scroll = {video_attributes[3], fg_scrollx};
        if (flip_screen) begin
            bg_scroll = bg_scroll ^ 9'h00f;
            fg_scroll = fg_scroll ^ 9'h00f;
            bg_world_x = {1'b0, screen_x} + {1'b0, bg_scroll} - 10'h12f;
            fg_world_x = {1'b0, screen_x} + {1'b0, fg_scroll} - 10'h12f;
        end else begin
            bg_world_x = {1'b0, screen_x} + {1'b0, bg_scroll} + 10'h030;
            fg_world_x = {1'b0, screen_x} + {1'b0, fg_scroll} + 10'h030;
        end
        bg_world_y = screen_y + bg_scrolly;
        fg_world_y = screen_y + fg_scrolly;

        video_bg_address = {bg_world_y[7:3], bg_world_x[8:3]};
        video_fg_address = {fg_world_y[7:3], fg_world_x[8:3]};

        bg_tile_code = {video_attributes[4], video_bg_attr[2:0],
                        video_bg_code};
        fg_tile_code = {video_attributes[1:0], video_fg_code};
        bg_byte_address = {bg_tile_code, 4'b0000} +
                          {13'd0, s0_bg_y} +
                          (s0_bg_x[2] ? 16'd8 : 16'd0);
        fg_byte_address = {fg_tile_code, 3'b000} + {10'd0, s0_fg_y};
        bg_plane0_address  = bg_byte_address;
        bg_plane12_address = bg_byte_address;
        text_rom_address   = fg_byte_address;

        bg_pen = {
            bg_plane0_data[3 - s0_bg_x[1:0]],
            bg_plane12_data[7 - s0_bg_x[1:0]],
            bg_plane12_data[3 - s0_bg_x[1:0]]
        };
        // MAME gfx-layout bit offsets are MSB-first inside each byte.
        // Convert them explicitly to Verilog's [7:0] numbering.
        fg_pen = text_rom_data[7 - s0_fg_x];
        bg_color = video_bg_attr[7:3] ^ 5'h1f;

        selected_palette_index = {2'b00, s0_bg_color, bg_pen};
        if (s0_sprite_index != 10'd0)
            selected_palette_index = s0_sprite_index;
        if (fg_pen)
            selected_palette_index = 10'h201;
        if (!s0_display)
            selected_palette_index = 10'd0;
        video_palette_address = selected_palette_index;

        decoded_rgb = {
            video_palette_low[3:0], video_palette_ext[4],
            video_palette_low[7:4], video_palette_ext[5],
            video_palette_ext[3:0], video_palette_ext[6]
        };
    end

    always_ff @(posedge clk) begin
        pipeline_valid_0 <= pixel_ce;
        pipeline_valid_1 <= pipeline_valid_0;
        pipeline_valid_2 <= pipeline_valid_1;
        pipeline_valid_3 <= pipeline_valid_2;
        pixel_strobe     <= pipeline_valid_3;

        if (pixel_ce) begin
            // The pen is addressed by the REGISTERED s0_bg_x/y, so the tile
            // attribute must be delayed to match. Used live it advances to the
            // next tile one pixel early, colouring x%8==7 of every column wrong.
            s0_bg_color <= bg_color;
            s0_bg_x <= bg_world_x[2:0];
            s0_bg_y <= bg_world_y[2:0];
            s0_fg_x <= fg_world_x[2:0];
            s0_fg_y <= fg_world_y[2:0];
            s0_sprite_index <= sprite_palette_index;
            s0_display <= video_attributes[5] && !hblank_in && !vblank_in;
            s0_hblank <= hblank_in;
            s0_vblank <= vblank_in;
            s0_hsync  <= hsync_in;
            s0_vsync  <= vsync_in;
            s0_h_count <= h_count;
            s0_v_count <= v_count;
        end

        if (reset) begin
            rgb555          <= 15'd0;
            hblank          <= 1'b1;
            vblank          <= 1'b1;
            hsync           <= 1'b1;
            vsync           <= 1'b1;
            valid_pixel     <= 1'b0;
            output_h_count   <= 9'd0;
            output_v_count   <= 9'd0;
            pipeline_valid_0 <= 1'b0;
            pipeline_valid_1 <= 1'b0;
            pipeline_valid_2 <= 1'b0;
            pipeline_valid_3 <= 1'b0;
            pixel_strobe     <= 1'b0;
        end else if (pipeline_valid_2) begin
            rgb555      <= s0_display ? decoded_rgb : 15'd0;
            hblank      <= s0_hblank;
            vblank      <= s0_vblank;
            hsync       <= s0_hsync;
            vsync       <= s0_vsync;
            valid_pixel <= s0_display;
            output_h_count <= s0_h_count;
            output_v_count <= s0_v_count;
        end
    end

endmodule
