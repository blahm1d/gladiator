//============================================================================
// Gladiator (Taito, 1986) for MiSTer
//
// The emu wrapper is an appliance layer. The reconstructed board is contained
// in rtl/gladiator_board.sv and has no dependency on MiSTer services.
//============================================================================

module emu (
    `include "sys/emu_ports.vh"
);

    assign ADC_BUS  = 'Z;
    assign USER_OUT = '1;
    assign {UART_RTS, UART_TXD, UART_DTR} = 3'b000;
    assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

    assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN,
            DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

    // The fixed digital-video build does not use external SDRAM.
    assign SDRAM_CLK  = 1'b0;
    assign SDRAM_CKE  = 1'b0;
    assign SDRAM_A    = 13'd0;
    assign SDRAM_BA   = 2'd0;
    assign SDRAM_DQ   = 16'hzzzz;
    assign SDRAM_DQML = 1'b1;
    assign SDRAM_DQMH = 1'b1;
    assign SDRAM_nCS  = 1'b1;
    assign SDRAM_nWE  = 1'b1;
    assign SDRAM_nRAS = 1'b1;
    assign SDRAM_nCAS = 1'b1;

    assign VGA_F1       = 1'b0;
    assign VGA_SCALER   = 1'b0;
    assign VGA_DISABLE  = 1'b0;
    assign HDMI_BLACKOUT = 1'b0;
    assign HDMI_BOB_DEINT = 1'b0;
    assign HDMI_FREEZE  = 1'b0;
    assign LED_DISK     = 2'b00;
    assign LED_POWER    = 2'b00;
    assign BUTTONS      = 2'b00;
    assign AUDIO_S      = 1'b1;
    assign AUDIO_MIX    = 2'b00;

    assign VIDEO_ARX = 13'd4;
    assign VIDEO_ARY = 13'd3;

    `include "build_id.v"
    localparam CONF_STR = {
        "Gladiator;;",
        "-;",
        "O[6],MAME Sub-IRQ Compatibility,On,Off;",
        "O[7],Derived MCU ROM Repair,On,Raw Archival;",
        "-;",
        "DIP;",
        "-;",
        "O[73:72],Sound Effects,+6 dB,+3 dB,Original,+9 dB;",
        "-;",
        "O[101],CRT Adjust,Off,On;",
        "H1O[100:96],CRT H-Size,",
            "0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,",
            "-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
        "H1O[85:79],CRT H-Position,",
            "0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,",
            "+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,",
            "+32,+33,+34,+35,+36,+37,+38,+39,+40,+41,+42,+43,+44,+45,+46,+47,",
            "+48,+49,+50,+51,+52,+53,+54,+55,+56,+57,+58,+59,+60,+61,+62,",
            "-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,",
            "-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
        "H1O[78:74],CRT V-Shift,",
            "0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,",
            "-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
        "-;",
        "P1,Research;",
        "P1-;",
        "P1-,Compatibility assists are visible in debug signals and can be disabled.;",
        "P1-,MAME is a regression oracle. PCB evidence remains authoritative.;",
        "-;",
        "T[43],Save NVRAM;",
        "T[0],Reset;",
        "v,1;",
        "V,v", `BUILD_DATE
    };

    wire [127:0] status;
    wire [1:0] buttons;
    wire forced_scandoubler;
    wire direct_video;
    wire [21:0] gamma_bus;
    wire [31:0] joystick_0;
    wire [31:0] joystick_1;
    wire [10:0] ps2_key;
    wire ioctl_download;
    wire ioctl_upload;
    wire [15:0] ioctl_index;
    wire ioctl_wr;
    wire [26:0] ioctl_addr;
    wire [7:0] ioctl_dout;
    wire [7:0] ioctl_din;
    wire ioctl_wait = 1'b0;
    reg ioctl_upload_request = 1'b0;

    wire clk_96;
    wire clk_32;
    wire pll_locked;

    (* ASYNC_REG = "TRUE" *) reg [127:0] status_96_meta = 128'd0;
    (* ASYNC_REG = "TRUE" *) reg [127:0] status_96 = 128'd0;
    (* ASYNC_REG = "TRUE" *) reg [1:0] buttons_96_meta = 2'd0;
    (* ASYNC_REG = "TRUE" *) reg [1:0] buttons_96 = 2'd0;
    (* ASYNC_REG = "TRUE" *) reg forced_scandoubler_96_meta = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg forced_scandoubler_96 = 1'b0;

    always_ff @(posedge clk_96) begin
        status_96_meta <= status;
        status_96 <= status_96_meta;
        buttons_96_meta <= buttons;
        buttons_96 <= buttons_96_meta;
        forced_scandoubler_96_meta <= forced_scandoubler;
        forced_scandoubler_96 <= forced_scandoubler_96_meta;
    end

    hps_io #(.CONF_STR(CONF_STR)) hps_io (
        .clk_sys            (clk_32),
        .HPS_BUS            (HPS_BUS),
        .EXT_BUS            (),
        .gamma_bus          (gamma_bus),
        .direct_video       (direct_video),
        .forced_scandoubler (forced_scandoubler),
        .video_rotated      (1'b0),
        .new_vmode          (1'b0),
        .buttons            (buttons),
        .status             (status),
        .status_menumask    ({14'd0, ~status[101], 1'b0}),
        .joystick_0         (joystick_0),
        .joystick_1         (joystick_1),
        .ps2_key            (ps2_key),
        .ioctl_download     (ioctl_download),
        .ioctl_upload       (ioctl_upload),
        .ioctl_upload_req   (ioctl_upload_request),
        .ioctl_upload_index (8'd2),
        .ioctl_index        (ioctl_index),
        .ioctl_wr           (ioctl_wr),
        .ioctl_addr         (ioctl_addr),
        .ioctl_dout         (ioctl_dout),
        .ioctl_din          (ioctl_din),
        .ioctl_wait         (ioctl_wait)
    );

    pll pll (
        .refclk   (CLK_50M),
        .rst      (1'b0),
        .outclk_0 (clk_96),
        .outclk_1 (clk_32),
        .locked   (pll_locked)
    );

    assign CLK_VIDEO = clk_96;

    // Keyboard state supplements normal MiSTer joystick mapping.
    reg key_up = 0, key_down = 0, key_left = 0, key_right = 0;
    reg key_b1 = 0, key_b2 = 0, key_b3 = 0;
    reg key_start1 = 0, key_start2 = 0;
    reg key_coin1 = 0, key_coin2 = 0, key_service = 0;
    wire key_pressed = ps2_key[9];
    wire [7:0] key_code = ps2_key[7:0];

    always_ff @(posedge clk_32) begin
        reg old_key_toggle;
        old_key_toggle <= ps2_key[10];
        if (old_key_toggle != ps2_key[10]) begin
            case (key_code)
                8'h16: key_start1  <= key_pressed; // 1
                8'h1e: key_start2  <= key_pressed; // 2
                8'h2e: key_coin1   <= key_pressed; // 5
                8'h36: key_coin2   <= key_pressed; // 6
                8'h46: key_service <= key_pressed; // 9
                8'h75: key_up      <= key_pressed;
                8'h72: key_down    <= key_pressed;
                8'h6b: key_left    <= key_pressed;
                8'h74: key_right   <= key_pressed;
                8'h14: key_b1      <= key_pressed; // Ctrl
                8'h11: key_b2      <= key_pressed; // Alt
                8'h29: key_b3      <= key_pressed; // Space
            endcase
        end
    end

    wire [7:0] dsw1;
    wire [7:0] dsw2;
    wire [7:0] dsw3;
    gladiator_dip_loader dip_loader (
        .clk        (clk_32),
        .ioctl_wr   (ioctl_wr),
        .ioctl_index(ioctl_index),
        .ioctl_addr (ioctl_addr),
        .ioctl_data (ioctl_dout),
        .dsw1       (dsw1),
        .dsw2       (dsw2),
        .dsw3       (dsw3)
    );

    // Hardware-isolation build: these two active-low cabinet switches are
    // forced to their factory-normal electrical levels after the MiSTer DIP
    // upload. This prevents stale saved settings from selecting monitor
    // reverse or the non-advancing operator test at boot.
    wire [7:0] board_dsw2 = dsw2 | 8'h80;
    wire [7:0] board_dsw3 = dsw3 | 8'h80;

    wire p1_right = joystick_0[0] | key_right;
    wire p1_left  = joystick_0[1] | key_left;
    wire p1_down  = joystick_0[2] | key_down;
    wire p1_up    = joystick_0[3] | key_up;
    wire p1_b1    = joystick_0[4] | key_b1;
    wire p1_b2    = joystick_0[5] | key_b2;
    wire p1_b3    = joystick_0[6] | key_b3;

    wire p2_right = joystick_1[0];
    wire p2_left  = joystick_1[1];
    wire p2_down  = joystick_1[2];
    wire p2_up    = joystick_1[3];
    wire p2_b1    = joystick_1[4];
    wire p2_b2    = joystick_1[5];
    wire p2_b3    = joystick_1[6];

    wire start1 = joystick_0[8] | joystick_1[8] | key_start1;
    wire coin1  = joystick_0[9] | joystick_1[9] | key_coin1;
    wire start2 = joystick_0[10] | joystick_1[10] | key_start2;
    wire coin2  = joystick_0[12] | joystick_1[12] | key_coin2;
    wire service = joystick_0[13] | joystick_1[13] | key_service;

    wire [7:0] player1_n = {
        ~start2, ~start1, ~p1_b2, ~p1_b1,
        ~p1_down, ~p1_up, ~p1_left, ~p1_right
    };
    wire [7:0] player2_n = {
        2'b11, ~p2_b2, ~p2_b1,
        ~p2_down, ~p2_up, ~p2_left, ~p2_right
    };
    wire [3:0] coins_n = {1'b1, ~service, ~coin1, ~coin2};

    wire core_reset = RESET | status_96[0] | buttons_96[1] | !pll_locked |
                      (ioctl_download && (ioctl_index != 16'd0));

    wire rom_ready;
    wire core_ce;
    wire [7:0] core_r, core_g, core_b;
    wire core_hblank, core_vblank, core_hsync, core_vsync;
    wire signed [15:0] core_audio;
    wire [7:0] nvram_data;
    wire nvram_dirty;

    gladiator_board board (
        .clk_96                     (clk_96),
        .reset                      (core_reset),
        .download_active            (ioctl_download &&
                                     (ioctl_index == 16'd0)),
        .download_write             (ioctl_wr &&
                                     (ioctl_index == 16'd0)),
        .download_address           (ioctl_addr[19:0]),
        .download_data              (ioctl_dout),
        .rom_ready                  (rom_ready),
        .dsw1                       (dsw1),
        .dsw2                       (board_dsw2),
        .dsw3                       (board_dsw3),
        .player1_active_low         (player1_n),
        .player2_active_low         (player2_n),
        .player1_button3_active_low (~p1_b3),
        .player2_button3_active_low (~p2_b3),
        .coins_active_low           (coins_n),
        .mame_60hz_timing           (1'b1),
        .enable_mame_sub_irq        (~status_96[6]),
        .enable_bad_mcu_patch       (~status_96[7]),
        .effect_gain                (status_96[73:72]),
        .nvram_host_enable          ((ioctl_download || ioctl_upload) &&
                                     (ioctl_index == 16'd2)),
        .nvram_host_write           (ioctl_wr &&
                                     (ioctl_index == 16'd2)),
        .nvram_host_address         (ioctl_addr[10:0]),
        .nvram_host_data_in         (ioctl_dout),
        .nvram_host_data_out        (nvram_data),
        .nvram_dirty                (nvram_dirty),
        .pixel_ce                   (core_ce),
        .red                        (core_r),
        .green                      (core_g),
        .blue                       (core_b),
        .hblank                     (core_hblank),
        .vblank                     (core_vblank),
        .hsync                      (core_hsync),
        .vsync                      (core_vsync),
        .audio                      (core_audio),
        .raster_h                   (),
        .raster_v                   (),
        .debug_main_address         (),
        .debug_sound_address        (),
        .debug_6809_address         (),
        .debug_sprite_overruns      (),
        .debug_mcu_patch_visible    (),
        .debug_audio_clip           ()
    );

    assign ioctl_din = nvram_data;

    // F000-F7FF is live battery-backed work RAM, not a write-once settings
    // block. The game continues to update it during normal execution, so
    // automatically requesting an upload for every dirty generation creates
    // a permanent save loop. Persistence is therefore explicit: the OSD
    // "Save NVRAM" action is the only source of an upload request.
    reg nvram_save_trigger_d = 1'b0;
    always_ff @(posedge clk_32) begin
        nvram_save_trigger_d <= status[43];
        ioctl_upload_request <= status[43] && !nvram_save_trigger_d;
    end

    // CRT Adjust is a core-side, single-line geometry stage. It never retimes a
    // frame: source line count, refresh, and native sync cadence remain the
    // board's 384x262 timing. Off selects the original path directly.
    assign VGA_SL = 2'b00;

    logic              crt_on = 1'b0;
    logic signed [4:0] crt_hsize = 5'sd0;
    logic        [6:0] crt_hpos_code = 7'd0;
    logic signed [5:0] crt_vshift = 6'sd0;

    always_ff @(posedge clk_96) if (core_ce) begin
        crt_on        <= status_96[101];
        crt_hsize     <= $signed(status_96[100:96]);
        crt_hpos_code <= status_96[85:79];
        crt_vshift    <= $signed(status_96[78:74]);
    end

    // Safe SYNCSHIFT range derived from the real 384-pixel line:
    //   active 0..255, front porch 256..287, HSync 288..319, back porch 320..383.
    // Advancing by 32 places the sync start inside blanking. The module's
    // registered rise detector means +63 flips the bank on active pixel 0, so
    // the safe positive limit is +62. The dense menu is 0,+1..+62,-32..-1.
    wire signed [8:0] crt_hoffset =
        (crt_hpos_code <= 7'd62)
            ? $signed({2'b00, crt_hpos_code})
            : (crt_hpos_code <= 7'd94)
                ? $signed({2'b00, crt_hpos_code}) - 9'sd95
                : 9'sd0;

    wire crt_hs_ref;
    wire crt_ce;
    gladiator_crt_read_ce crt_read_rate (
        .clk       (clk_96),
        .native_ce (core_ce),
        .active    (crt_on),
        .hsize     (crt_hsize),
        .hs_ref    (crt_hs_ref),
        .read_ce   (crt_ce)
    );

    wire [7:0] crt_r;
    wire [7:0] crt_g;
    wire [7:0] crt_b;
    wire       crt_hsync;
    wire       crt_vsync;
    wire       crt_hblank;
    wire       crt_vblank;

    // Gladiator is a narrow 256-pixel image on an asymmetric 384-pixel line.
    // SYNCSHIFT avoids the content-window edge block that mode 1 can produce
    // on this geometry. crt_hs_ref also resets the external read accumulator.
    crt_adjust #(
        .VTOTAL    (262),
        .HTOTAL    (384),
        .HPOS_MODE (0),
        .COLOR_BITS(5)
    ) crt_adjust (
        .clk        (clk_96),
        .pxl_cen    (core_ce),
        .pxl2_cen   (crt_ce),
        .active     (crt_on),
        .hsize      (crt_hsize),
        .hoffset    (crt_hoffset),
        .voffset    (crt_vshift),
        .r_in       (core_r),
        .g_in       (core_g),
        .b_in       (core_b),
        .hs_in      (core_hsync),
        .vs_in      (core_vsync),
        .hb_in      (core_hblank),
        .vb_in      (core_vblank),
        .r_out      (crt_r),
        .g_out      (crt_g),
        .b_out      (crt_b),
        .hs_out     (crt_hsync),
        .vs_out     (crt_vsync),
        .hb_out     (crt_hblank),
        .vb_out     (crt_vblank),
        .hs_ref_out (crt_hs_ref)
    );

    wire video_de;

    video_mixer #(864, 0, 1) video_mixer (
        .CLK_VIDEO  (CLK_VIDEO),
        .CE_PIXEL   (CE_PIXEL),
        .ce_pix     (crt_on ? crt_ce : core_ce),
        .scandoubler(forced_scandoubler_96),
        .hq2x       (1'b0),
        .gamma_bus  (gamma_bus),
        .R          (crt_on ? crt_r : core_r),
        .G          (crt_on ? crt_g : core_g),
        .B          (crt_on ? crt_b : core_b),
        .HBlank     (crt_on ? crt_hblank : core_hblank),
        .VBlank     (crt_on ? crt_vblank : core_vblank),
        .HSync      (crt_on ? crt_hsync : core_hsync),
        .VSync      (crt_on ? crt_vsync : core_vsync),
        .VGA_R      (VGA_R),
        .VGA_G      (VGA_G),
        .VGA_B      (VGA_B),
        .VGA_VS     (VGA_VS),
        .VGA_HS     (VGA_HS),
        .VGA_DE     (video_de),
        .HDMI_FREEZE(HDMI_FREEZE)
    );

    assign VGA_DE = video_de;
    assign AUDIO_L = core_audio;
    assign AUDIO_R = core_audio;
    assign LED_USER = ioctl_download | !rom_ready | nvram_dirty;

endmodule
