module gladiator_board (
    input  logic               clk_96,
    input  logic               reset,

    input  logic               download_active,
    input  logic               download_write,
    input  logic [19:0]        download_address,
    input  logic [7:0]         download_data,
    output logic               rom_ready,

    input  logic [7:0]         dsw1,
    input  logic [7:0]         dsw2,
    input  logic [7:0]         dsw3,
    input  logic [7:0]         player1_active_low,
    input  logic [7:0]         player2_active_low,
    input  logic               player1_button3_active_low,
    input  logic               player2_button3_active_low,
    input  logic [3:0]         coins_active_low,

    input  logic               mame_60hz_timing,
    input  logic               enable_mame_sub_irq,
    input  logic               enable_bad_mcu_patch,
    input  logic [1:0]         effect_gain,

    input  logic               nvram_host_enable,
    input  logic               nvram_host_write,
    input  logic [10:0]        nvram_host_address,
    input  logic [7:0]         nvram_host_data_in,
    output logic [7:0]         nvram_host_data_out,
    output logic               nvram_dirty,

    output logic               pixel_ce,
    output logic [7:0]         red,
    output logic [7:0]         green,
    output logic [7:0]         blue,
    output logic               hblank,
    output logic               vblank,
    output logic               hsync,
    output logic               vsync,
    output logic signed [15:0] audio,
    output logic [8:0]         raster_h,
    output logic [8:0]         raster_v,

    output logic [15:0]        debug_main_address,
    output logic [15:0]        debug_sound_address,
    output logic [15:0]        debug_6809_address,
    output logic [15:0]        debug_sprite_overruns,
    output logic [1:0]         debug_mcu_patch_visible,
    output logic               debug_audio_clip
);

    logic ce_12m, ce_6m, ce_3m, ce_1m5, tclk, ce_455k, ce_750k;
    logic board_reset;

    assign board_reset = reset || download_active || !rom_ready;

    gladiator_clock_enables clock_enables (
        .clk_96  (clk_96),
        .reset   (reset),
        .ce_12m  (ce_12m),
        .ce_6m   (ce_6m),
        .ce_3m   (ce_3m),
        .ce_1m5  (ce_1m5),
        .tclk    (tclk),
        .ce_750k (ce_750k),
        .ce_455k (ce_455k)
    );

    logic [8:0] board_h, board_v;
    logic board_pixel_ce;
    logic board_hblank, board_vblank, board_hsync, board_vsync;
    logic vblank_irq_set;

    gladiator_board_timing timing (
        .clk          (clk_96),
        .reset        (board_reset),
        .ce_6m        (ce_6m),
        .mame_60hz    (mame_60hz_timing),
        .pixel_ce     (board_pixel_ce),
        .h_count      (board_h),
        .v_count      (board_v),
        .hblank       (board_hblank),
        .vblank       (board_vblank),
        .hsync        (board_hsync),
        .vsync        (board_vsync),
        .vblank_rise  (vblank_irq_set)
    );

    // ---------------------------------------------------------------------
    // Physical ROM ports
    // ---------------------------------------------------------------------

    logic [16:0] main_rom_address;
    logic [7:0] main_rom_data;
    logic [13:0] sound_rom_address;
    logic [7:0] sound_rom_data;
    logic [16:0] adpcm_rom_address;
    logic [7:0] adpcm_rom_data;
    logic [12:0] text_rom_address;
    logic [7:0] text_rom_data;
    logic [15:0] bg_plane0_address, bg_plane12_address;
    logic [7:0] bg_plane0_data, bg_plane12_data;
    logic [16:0] sprite_plane0_address, sprite_plane12_address;
    logic [7:0] sprite_plane0_data, sprite_plane12_data;
    logic [4:0] prom_address;
    logic [7:0] prom_q3_data, prom_q4_data;
    logic [9:0] cctl_rom_address, ccpu_rom_address, ucpu_rom_address;
    logic [10:0] csnd_rom_address;
    logic [7:0] cctl_raw_rom_data, ccpu_raw_rom_data;
    logic [7:0] ucpu_raw_rom_data, csnd_raw_rom_data;

    assign prom_address = debug_main_address[14:10];

    gladiator_roms roms (
        .clk                    (clk_96),
        .reset                  (reset),
        .download_active        (download_active),
        .download_write         (download_write),
        .download_address       (download_address),
        .download_data          (download_data),
        .rom_ready              (rom_ready),
        .main_address           (main_rom_address),
        .main_data              (main_rom_data),
        .sound_address          (sound_rom_address),
        .sound_data             (sound_rom_data),
        .adpcm_address          (adpcm_rom_address),
        .adpcm_data             (adpcm_rom_data),
        .text_address           (text_rom_address),
        .text_data              (text_rom_data),
        .bg_plane0_address      (bg_plane0_address),
        .bg_plane0_data         (bg_plane0_data),
        .bg_plane12_address     (bg_plane12_address),
        .bg_plane12_data        (bg_plane12_data),
        .sprite_plane0_address  (sprite_plane0_address),
        .sprite_plane0_data     (sprite_plane0_data),
        .sprite_plane12_address (sprite_plane12_address),
        .sprite_plane12_data    (sprite_plane12_data),
        .prom_address           (prom_address),
        .prom_q3_data           (prom_q3_data),
        .prom_q4_data           (prom_q4_data),
        .cctl_address           (cctl_rom_address),
        .cctl_raw_data          (cctl_raw_rom_data),
        .ccpu_address           (ccpu_rom_address),
        .ccpu_raw_data          (ccpu_raw_rom_data),
        .ucpu_address           (ucpu_rom_address),
        .ucpu_raw_data          (ucpu_raw_rom_data),
        .csnd_address           (csnd_rom_address),
        .csnd_raw_data          (csnd_raw_rom_data)
    );

    // ---------------------------------------------------------------------
    // Main Z80 and board bus
    // ---------------------------------------------------------------------

    logic [15:0] main_a;
    logic [7:0] main_di, main_do;
    logic main_m1_n, main_mreq_n, main_iorq_n, main_rd_n, main_wr_n;
    logic main_int_n;
    logic [211:0] main_registers;
    logic main_ucpu_cs_n, main_ucpu_a0, main_ucpu_rd_n, main_ucpu_wr_n;
    logic [7:0] main_ucpu_data_out, main_ucpu_data_in;
    logic compat_sub_irq_set, sub_reset;
    logic sprite_buffer, program_bank, flip_screen;
    logic [2:0] sprite_bank_base;
    logic [7:0] latch_debug;
    logic [7:0] fg_scrolly, fg_scrollx, bg_scrolly, bg_scrollx;
    logic [7:0] video_attributes;

    T80s main_cpu (
        .RESET_n (!board_reset),
        .CLK     (clk_96),
        .CEN     (ce_6m),
        .WAIT_n  (1'b1),
        .INT_n   (main_int_n),
        .NMI_n   (1'b1),
        .BUSRQ_n (1'b1),
        .M1_n    (main_m1_n),
        .MREQ_n  (main_mreq_n),
        .IORQ_n  (main_iorq_n),
        .RD_n    (main_rd_n),
        .WR_n    (main_wr_n),
        .RFSH_n  (),
        .HALT_n  (),
        .BUSAK_n (),
        .OUT0    (1'b0),
        .A       (main_a),
        .DI      (main_di),
        .DO      (main_do),
        .REG     (main_registers)
    );

    assign debug_main_address = main_a;

    logic [10:0] video_bg_address;
    logic [7:0] video_bg_code, video_bg_attr;
    logic [10:0] video_fg_address;
    logic [7:0] video_fg_code;
    logic [9:0] video_palette_address;
    logic [7:0] video_palette_low, video_palette_ext;
    logic [11:0] video_sprite_address;
    logic [7:0] video_sprite_data;

    gladiator_main_bus main_bus (
        .clk                    (clk_96),
        .reset                  (board_reset),
        .cpu_address            (main_a),
        .cpu_data_out           (main_do),
        .cpu_data_in            (main_di),
        .cpu_m1_n               (main_m1_n),
        .cpu_mreq_n             (main_mreq_n),
        .cpu_iorq_n             (main_iorq_n),
        .cpu_rd_n               (main_rd_n),
        .cpu_wr_n               (main_wr_n),
        .rom_address            (main_rom_address),
        .rom_data               (main_rom_data),
        .vblank_irq_set         (vblank_irq_set),
        .main_int_n             (main_int_n),
        .ucpu_cs_n              (main_ucpu_cs_n),
        .ucpu_a0                (main_ucpu_a0),
        .ucpu_rd_n              (main_ucpu_rd_n),
        .ucpu_wr_n              (main_ucpu_wr_n),
        .ucpu_data_out          (main_ucpu_data_out),
        .ucpu_data_in           (main_ucpu_data_in),
        .compat_sub_irq_set     (compat_sub_irq_set),
        .sub_reset              (sub_reset),
        .sprite_buffer          (sprite_buffer),
        .sprite_bank_base       (sprite_bank_base),
        .program_bank           (program_bank),
        .flip_screen            (flip_screen),
        .unknown_latch_bits     (latch_debug),
        .fg_scrolly             (fg_scrolly),
        .fg_scrollx             (fg_scrollx),
        .bg_scrolly             (bg_scrolly),
        .bg_scrollx             (bg_scrollx),
        .video_attributes       (video_attributes),
        .video_bg_address       (video_bg_address),
        .video_bg_code          (video_bg_code),
        .video_bg_attr          (video_bg_attr),
        .video_fg_address       (video_fg_address),
        .video_fg_code          (video_fg_code),
        .video_palette_address  (video_palette_address),
        .video_palette_low      (video_palette_low),
        .video_palette_ext      (video_palette_ext),
        .video_sprite_address   (video_sprite_address),
        .video_sprite_data      (video_sprite_data),
        .nvram_host_enable      (nvram_host_enable),
        .nvram_host_write       (nvram_host_write),
        .nvram_host_address     (nvram_host_address),
        .nvram_host_data_in     (nvram_host_data_in),
        .nvram_host_data_out    (nvram_host_data_out),
        .nvram_dirty            (nvram_dirty),
        .trace_mem_read         (),
        .trace_mem_write        (),
        .trace_io_read          (),
        .trace_io_write         ()
    );

    // ---------------------------------------------------------------------
    // Sound Z80, UPI-41 complex, and YM2203
    // ---------------------------------------------------------------------

    logic [15:0] sound_a;
    logic [7:0] sound_di, sound_do;
    logic sound_m1_n, sound_mreq_n, sound_iorq_n, sound_rd_n, sound_wr_n;
    logic sound_irq_n, sound_irq_pending, sound_int_ack;
    logic [211:0] sound_registers;

    gladiator_mame_irq compat_sound_irq (
        .clk        (clk_96),
        .reset      (board_reset || sub_reset),
        .enable     (enable_mame_sub_irq),
        .set        (compat_sub_irq_set),
        .acknowledge(sound_int_ack),
        .irq_n      (sound_irq_n),
        .pending    (sound_irq_pending)
    );

    logic ym_irq_n;

    T80s sound_cpu (
        .RESET_n (!(board_reset || sub_reset)),
        .CLK     (clk_96),
        .CEN     (ce_3m),
        .WAIT_n  (1'b1),
        .INT_n   (sound_irq_n),
        .NMI_n   (ym_irq_n),
        .BUSRQ_n (1'b1),
        .M1_n    (sound_m1_n),
        .MREQ_n  (sound_mreq_n),
        .IORQ_n  (sound_iorq_n),
        .RD_n    (sound_rd_n),
        .WR_n    (sound_wr_n),
        .RFSH_n  (),
        .HALT_n  (),
        .BUSAK_n (),
        .OUT0    (1'b0),
        .A       (sound_a),
        .DI      (sound_di),
        .DO      (sound_do),
        .REG     (sound_registers)
    );

    assign debug_sound_address = sound_a;

    logic ym_cs_n, ym_address, ym_wr_n;
    logic [7:0] ym_data_out, ym_data_in;
    logic csnd_cs_n, csnd_a0, csnd_rd_n, csnd_wr_n;
    logic cctl_cs_n, cctl_a0, cctl_rd_n, cctl_wr_n;
    logic ccpu_cs_n, ccpu_a0, ccpu_rd_n, ccpu_wr_n;
    logic [7:0] csnd_host_out, csnd_host_in;
    logic [7:0] cctl_host_out, cctl_host_in;
    logic [7:0] ccpu_host_out, ccpu_host_in;
    logic command_write;
    logic [7:0] command_data, filter_latch;
    logic sound_command_write;
    logic [7:0] sound_command_data;

    gladiator_sound_bus sound_bus (
        .clk            (clk_96),
        .reset          (board_reset || sub_reset),
        .cpu_address    (sound_a),
        .cpu_data_out   (sound_do),
        .cpu_data_in    (sound_di),
        .cpu_m1_n       (sound_m1_n),
        .cpu_mreq_n     (sound_mreq_n),
        .cpu_iorq_n     (sound_iorq_n),
        .cpu_rd_n       (sound_rd_n),
        .cpu_wr_n       (sound_wr_n),
        .rom_address    (sound_rom_address),
        .rom_data       (sound_rom_data),
        .interrupt_ack  (sound_int_ack),
        .ym_cs_n        (ym_cs_n),
        .ym_address     (ym_address),
        .ym_wr_n        (ym_wr_n),
        .ym_data_out    (ym_data_out),
        .ym_data_in     (ym_data_in),
        .csnd_cs_n      (csnd_cs_n),
        .csnd_a0        (csnd_a0),
        .csnd_rd_n      (csnd_rd_n),
        .csnd_wr_n      (csnd_wr_n),
        .csnd_data_out  (csnd_host_out),
        .csnd_data_in   (csnd_host_in),
        .cctl_cs_n      (cctl_cs_n),
        .cctl_a0        (cctl_a0),
        .cctl_rd_n      (cctl_rd_n),
        .cctl_wr_n      (cctl_wr_n),
        .cctl_data_out  (cctl_host_out),
        .cctl_data_in   (cctl_host_in),
        .ccpu_cs_n      (ccpu_cs_n),
        .ccpu_a0        (ccpu_a0),
        .ccpu_rd_n      (ccpu_rd_n),
        .ccpu_wr_n      (ccpu_wr_n),
        .ccpu_data_out  (ccpu_host_out),
        .ccpu_data_in   (ccpu_host_in),
        .command_write  (command_write),
        .command_data   (command_data),
        .sound_command_write(sound_command_write),
        .sound_command_data(sound_command_data),
        .filter_latch   (filter_latch),
        .trace_mem_read (),
        .trace_mem_write(),
        .trace_io_read  (),
        .trace_io_write ()
    );

    logic [7:0] ym_port_a, ym_port_b;
    logic [7:0] psg_a, psg_b, psg_c;
    logic signed [15:0] ym_fm;
    logic ym_sample;
    logic ym_wr_n_d;
    logic [2:0] effect_channel_active;
    logic effect_active;

    always_ff @(posedge clk_96) begin
        if (board_reset || sub_reset)
            ym_wr_n_d <= 1'b1;
        else
            ym_wr_n_d <= ym_wr_n;
    end

    gladiator_effect_tracker effect_tracker (
        .clk                  (clk_96),
        .reset                (board_reset || sub_reset),
        .sound_command_write  (sound_command_write),
        .sound_command_data   (sound_command_data),
        .ym_write             (ym_wr_n_d && !ym_wr_n),
        .ym_address           (ym_address),
        .ym_data              (ym_data_out),
        .effect_channel_active(effect_channel_active),
        .effect_active        (effect_active)
    );

    gladiator_ym2203 ym2203 (
        .clk          (clk_96),
        .ce_1m5      (ce_1m5),
        .reset        (board_reset || sub_reset),
        .bus_data_in  (ym_data_out),
        .bus_address  (ym_address),
        .bus_cs_n     (ym_cs_n),
        .bus_wr_n     (ym_wr_n),
        .bus_data_out (ym_data_in),
        .irq_n        (ym_irq_n),
        .dsw3         (dsw3),
        .port_a_out   (ym_port_a),
        .port_b_out   (ym_port_b),
        .psg_a        (psg_a),
        .psg_b        (psg_b),
        .psg_c        (psg_c),
        .fm           (ym_fm),
        .sample       (ym_sample)
    );

    logic [7:0] cctl_p1_out, cctl_p2_out;
    logic [7:0] ccpu_p1_out, ccpu_p2_out;
    logic [7:0] ucpu_p1_out, csnd_p1_out;
    logic [1:0] coin_counter_active_low;

    gladiator_mcu_cluster mcu_cluster (
        .clk                    (clk_96),
        .ce_6m                  (ce_6m),
        .reset                  (board_reset),
        .peripheral_reset       (!ym_port_a[7]),
        .tclk                   (tclk),
        .enable_bad_dump_patch  (enable_bad_mcu_patch),
        .dsw1                   (dsw1),
        .dsw2                   (dsw2),
        .player1_active_low     (player1_active_low),
        .player2_active_low     (player2_active_low),
        .player1_button3_active_low(player1_button3_active_low),
        .player2_button3_active_low(player2_button3_active_low),
        .coins_active_low       (coins_active_low),
        .ucpu_a0                (main_ucpu_a0),
        .ucpu_cs_n              (main_ucpu_cs_n),
        .ucpu_rd_n              (main_ucpu_rd_n),
        .ucpu_wr_n              (main_ucpu_wr_n),
        .ucpu_host_data_in      (main_ucpu_data_out),
        .ucpu_host_data_out     (main_ucpu_data_in),
        .csnd_a0                (csnd_a0),
        .csnd_cs_n              (csnd_cs_n),
        .csnd_rd_n              (csnd_rd_n),
        .csnd_wr_n              (csnd_wr_n),
        .csnd_host_data_in      (csnd_host_out),
        .csnd_host_data_out     (csnd_host_in),
        .cctl_a0                (cctl_a0),
        .cctl_cs_n              (cctl_cs_n),
        .cctl_rd_n              (cctl_rd_n),
        .cctl_wr_n              (cctl_wr_n),
        .cctl_host_data_in      (cctl_host_out),
        .cctl_host_data_out     (cctl_host_in),
        .ccpu_a0                (ccpu_a0),
        .ccpu_cs_n              (ccpu_cs_n),
        .ccpu_rd_n              (ccpu_rd_n),
        .ccpu_wr_n              (ccpu_wr_n),
        .ccpu_host_data_in      (ccpu_host_out),
        .ccpu_host_data_out     (ccpu_host_in),
        .cctl_rom_address       (cctl_rom_address),
        .cctl_raw_rom_data      (cctl_raw_rom_data),
        .ccpu_rom_address       (ccpu_rom_address),
        .ccpu_raw_rom_data      (ccpu_raw_rom_data),
        .ucpu_rom_address       (ucpu_rom_address),
        .ucpu_raw_rom_data      (ucpu_raw_rom_data),
        .csnd_rom_address       (csnd_rom_address),
        .csnd_raw_rom_data      (csnd_raw_rom_data),
        .cctl_p1_out            (cctl_p1_out),
        .cctl_p2_out            (cctl_p2_out),
        .ccpu_p1_out            (ccpu_p1_out),
        .ccpu_p2_out            (ccpu_p2_out),
        .ucpu_p1_out            (ucpu_p1_out),
        .csnd_p1_out            (csnd_p1_out),
        .coin_counter_active_low(coin_counter_active_low),
        .bad_dump_patch_visible (debug_mcu_patch_visible)
    );

    // ---------------------------------------------------------------------
    // 6809 and externally-clocked MSM5205
    // ---------------------------------------------------------------------

    logic [15:0] cpu6809_a;
    logic [7:0] cpu6809_di, cpu6809_do;
    logic cpu6809_rnw, cpu6809_avma, cpu6809_vma, cpu6809_op;
    logic cpu6809_nmi_n;
    logic ce_6809_q;
    logic [111:0] cpu6809_registers;
    logic [3:0] adpcm_nibble;
    logic adpcm_vclk, adpcm_reset, adpcm_bank, adpcm_control_write;

    always_ff @(posedge clk_96)
        ce_6809_q <= ce_750k;

    // AVMA announces that the following 6809 bus cycle is valid. The board
    // latches it on E, matching the external VMA latch used with a 6809E.
    // Decoding raw AVMA shifts reads/writes one cycle and corrupts operands.
    always_ff @(posedge clk_96) begin
        if (board_reset)
            cpu6809_vma <= 1'b0;
        else if (ce_750k)
            cpu6809_vma <= cpu6809_avma;
    end

    mc6809i audio_cpu (
        .D        (cpu6809_di),
        .DOut     (cpu6809_do),
        .ADDR     (cpu6809_a),
        .RnW      (cpu6809_rnw),
        .clk      (clk_96),
        .cen_E    (ce_750k),
        .cen_Q    (ce_6809_q),
        .BS       (),
        .BA       (),
        .nIRQ     (1'b1),
        .nFIRQ    (1'b1),
        .nNMI     (cpu6809_nmi_n),
        .AVMA     (cpu6809_avma),
        .BUSY     (),
        .LIC      (),
        .nHALT    (1'b1),
        .nRESET   (!board_reset),
        .nDMABREQ (1'b1),
        .OP       (cpu6809_op),
        .RegData  (cpu6809_registers)
    );

    assign debug_6809_address = cpu6809_a;

    gladiator_6809_bus bus6809 (
        .clk                  (clk_96),
        .reset                (board_reset),
        .cpu_address          (cpu6809_a),
        .cpu_data_out         (cpu6809_do),
        .cpu_data_in          (cpu6809_di),
        .cpu_rnw              (cpu6809_rnw),
        .cpu_avma             (cpu6809_vma),
        .rom_address          (adpcm_rom_address),
        .rom_data             (adpcm_rom_data),
        .command_write        (command_write),
        .command_data         (command_data),
        .nmi_n                (cpu6809_nmi_n),
        .adpcm_nibble         (adpcm_nibble),
        .adpcm_vclk           (adpcm_vclk),
        .adpcm_reset          (adpcm_reset),
        .adpcm_bank           (adpcm_bank),
        .adpcm_control_write  (adpcm_control_write),
        .trace_read           (),
        .trace_write          ()
    );

    logic signed [11:0] adpcm_sound;
    logic adpcm_decode_strobe;

    gladiator_msm5205 msm5205 (
        .clk           (clk_96),
        .reset         (board_reset),
        .ce_455k       (ce_455k),
        .nibble        (adpcm_nibble),
        .external_vclk (adpcm_vclk),
        .chip_reset    (adpcm_reset),
        .sound         (adpcm_sound),
        .decode_strobe (adpcm_decode_strobe)
    );

    gladiator_audio_mixer audio_mixer (
        .clk           (clk_96),
        .reset         (board_reset),
        .sample_enable (ce_455k),
        .psg_a         (psg_a),
        .psg_b         (psg_b),
        .psg_c         (psg_c),
        .fm            (ym_fm),
        .adpcm         (adpcm_sound),
        .effect_active (effect_active),
        .effect_gain   (effect_gain),
        .filter_latch  (filter_latch),
        .mono          (audio),
        .clip          (debug_audio_clip)
    );

    // ---------------------------------------------------------------------
    // Board raster renderer
    // ---------------------------------------------------------------------

    logic [9:0] sprite_palette_index;
    logic sprite_builder_busy;
    logic [8:0] next_line;

    always_comb begin
        if (mame_60hz_timing)
            next_line = (board_v == 9'd261) ? 9'd0 : board_v + 9'd1;
        else
            next_line = (board_v == 9'd263) ? 9'd0 : board_v + 9'd1;
    end

    gladiator_sprite_line sprite_line (
        .clk                    (clk_96),
        .reset                  (board_reset),
        .start_line             (board_pixel_ce && board_h == 9'd0),
        .swap_display           (board_pixel_ce && board_h == 9'd383),
        .target_line            (next_line),
        .sprite_buffer          (sprite_buffer),
        .sprite_bank_base       (sprite_bank_base),
        .flip_screen            (flip_screen),
        .sprite_ram_address     (video_sprite_address),
        .sprite_ram_data        (video_sprite_data),
        .sprite_plane0_address  (sprite_plane0_address),
        .sprite_plane0_data     (sprite_plane0_data),
        .sprite_plane12_address (sprite_plane12_address),
        .sprite_plane12_data    (sprite_plane12_data),
        .display_x              (board_h[7:0]),
        .display_palette_index  (sprite_palette_index),
        .busy                   (sprite_builder_busy),
        .overrun_count          (debug_sprite_overruns)
    );

    logic [14:0] rgb555;
    logic renderer_valid;
    logic [8:0] rendered_h, rendered_v;

    gladiator_video video (
        .clk                   (clk_96),
        .reset                 (board_reset),
        .pixel_ce              (board_pixel_ce),
        .h_count               (board_h),
        .v_count               (board_v),
        .hblank_in             (board_hblank),
        .vblank_in             (board_vblank),
        .hsync_in              (board_hsync),
        .vsync_in              (board_vsync),
        .flip_screen           (flip_screen),
        .fg_scrolly            (fg_scrolly),
        .fg_scrollx            (fg_scrollx),
        .bg_scrolly            (bg_scrolly),
        .bg_scrollx            (bg_scrollx),
        .video_attributes      (video_attributes),
        .video_bg_address      (video_bg_address),
        .video_bg_code         (video_bg_code),
        .video_bg_attr         (video_bg_attr),
        .video_fg_address      (video_fg_address),
        .video_fg_code         (video_fg_code),
        .video_palette_address (video_palette_address),
        .video_palette_low     (video_palette_low),
        .video_palette_ext     (video_palette_ext),
        .text_rom_address      (text_rom_address),
        .text_rom_data         (text_rom_data),
        .bg_plane0_address     (bg_plane0_address),
        .bg_plane0_data        (bg_plane0_data),
        .bg_plane12_address    (bg_plane12_address),
        .bg_plane12_data       (bg_plane12_data),
        .sprite_palette_index  (sprite_palette_index),
        .rgb555                (rgb555),
        .hblank                (hblank),
        .vblank                (vblank),
        .hsync                 (hsync),
        .vsync                 (vsync),
        .valid_pixel           (renderer_valid),
        .pixel_strobe          (pixel_ce),
        .output_h_count        (rendered_h),
        .output_v_count        (rendered_v)
    );

    assign raster_h = rendered_h;
    assign raster_v = rendered_v;
    assign red   = {rgb555[14:10], rgb555[14:12]};
    assign green = {rgb555[9:5],   rgb555[9:7]};
    assign blue  = {rgb555[4:0],   rgb555[4:2]};

endmodule
