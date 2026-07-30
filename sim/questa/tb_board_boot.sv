`timescale 1ns/1ps

module tb_board_boot;
    logic clk_96 = 0;
    always #5.208 clk_96 = ~clk_96;

    logic reset = 1;
    logic download_active = 0;
    logic download_write = 0;
    logic [19:0] download_address = 0;
    logic [7:0] download_data = 0;
    logic [7:0] dsw1 = 8'h5a;
    logic [7:0] dsw2 = 8'hbf;
    logic [7:0] dsw3 = 8'hff;
    logic [7:0] player1_active_low = 8'hff;
    logic [7:0] player2_active_low = 8'hff;
    logic player1_button3_active_low = 1;
    logic player2_button3_active_low = 1;
    logic [3:0] coins_active_low = 4'hf;
    logic mame_60hz_timing = 1;
    logic enable_mame_sub_irq = 1;
    logic enable_bad_mcu_patch = 1;
    logic [1:0] effect_gain = 2'b00;
    logic nvram_host_enable = 0;
    logic nvram_host_write = 0;
    logic [10:0] nvram_host_address = 0;
    logic [7:0] nvram_host_data_in = 0;

    logic rom_ready;
    logic [7:0] nvram_host_data_out;
    logic nvram_dirty;
    logic pixel_ce;
    logic [7:0] red, green, blue;
    logic hblank, vblank, hsync, vsync;
    logic signed [15:0] audio;
    logic [8:0] raster_h, raster_v;
    logic [15:0] debug_main_address;
    logic [15:0] debug_sound_address;
    logic [15:0] debug_6809_address;
    logic [15:0] debug_sprite_overruns;
    logic [1:0] debug_mcu_patch_visible;
    logic debug_audio_clip;

    gladiator_board dut (.*);

    integer trace_file;
    integer main_opcode_file;
    integer sound_opcode_file;
    integer cpu6809_opcode_file;
    integer main_reads = 0;
    integer main_writes = 0;
    integer main_io_reads = 0;
    integer main_io_writes = 0;
    integer sound_reads = 0;
    integer sound_writes = 0;
    integer sound_io_reads = 0;
    integer sound_io_writes = 0;
    integer cpu6809_reads = 0;
    integer cpu6809_writes = 0;
    integer ucpu_host_cycles = 0;
    integer cctl_host_cycles = 0;
    integer ccpu_host_cycles = 0;
    integer csnd_host_cycles = 0;
    // Ordered main-board write scoreboard.
    //
    // Waiting for a state hash at a distant checkpoint tells you only that
    // something diverged somewhere.  This compares every main-board memory
    // and I/O write against MAME's ordered stream and stops on the first
    // wrong transaction, so the failure is reported where it happens.
    //
    // SCOPE: the oracle stream covers ticks 0..30M, which is boot plus the
    // C000-CBFF RAM sweep.  MAME writes no gameplay sprite descriptors in
    // that range, so a green run here is a boot/bus result and NOT evidence
    // about sprite generation.
    localparam int WRITE_ORACLE_MAX = 200000;
    logic        write_scoreboard_enabled = 1'b0;
    byte         write_oracle_kind [0:WRITE_ORACLE_MAX-1];
    logic [15:0] write_oracle_address [0:WRITE_ORACLE_MAX-1];
    logic [7:0]  write_oracle_data [0:WRITE_ORACLE_MAX-1];
    integer      write_oracle_count = 0;
    integer      write_oracle_index = 0;
    integer      write_oracle_file;
    integer      write_oracle_scanned;
    string       write_oracle_kind_text;
    integer      write_oracle_address_value;
    integer      write_oracle_data_value;

    integer main_address_changes = 0;
    integer sound_address_changes = 0;
    integer cpu6809_address_changes = 0;
    integer cctl_address_changes = 0;
    integer ccpu_address_changes = 0;
    integer ucpu_address_changes = 0;
    integer csnd_address_changes = 0;
    logic csnd_unknown_seen = 1'b0;
    logic [1:0] mcu_patch_seen = 2'b00;
    logic [15:0] previous_main_address;
    logic [15:0] previous_sound_address;
    logic [15:0] previous_6809_address;
    logic [9:0] previous_cctl_address;
    logic [9:0] previous_ccpu_address;
    logic [9:0] previous_ucpu_address;
    logic [10:0] previous_csnd_address;
    logic main_fetch_active = 0;
    logic sound_fetch_active = 0;
    logic cpu6809_fetch_active = 0;
    logic previous_rom_ready = 0;
    logic previous_board_reset = 1;
    logic fast_startup = 1'b0;
    logic legacy_fast_startup = 1'b0;
    logic golden_sprite_pass = 1'b0;
    integer boot_cycles = 500000;
    logic [14:0] fast_divider = 15'd0;
    logic [31:0] fast_video_phase = 32'd0;
    logic [31:0] fast_adpcm_phase = 32'd0;
    logic fast_video_ce = 1'b0;
    logic fast_adpcm_ce = 1'b0;
    wire [32:0] fast_video_sum =
        {1'b0, fast_video_phase} + {1'b0, 32'h80c7_3ac0};
    wire [32:0] fast_adpcm_sum =
        {1'b0, fast_adpcm_phase} + {1'b0, 32'h09b4_e818};
    wire fast_ce_6m = fast_divider[0];
    wire fast_ce_3m = &fast_divider[1:0];
    wire fast_ce_1m5 = &fast_divider[2:0];
    // ce_6m is accelerated by 8 here (one active edge in two instead of
    // one in sixteen). Keep the TCLK/MCU-crystal ratio at the board value:
    // divider[10] is likewise 8 times faster than production divider[13].
    wire fast_tclk = fast_divider[10];
    wire fast_vblank_irq = (&fast_divider[10:0]);
    integer golden_sprite_writes = 0;
    integer golden_logical_cycles = 0;
    logic golden_sprite_pass_reached = 1'b0;
    logic golden_first_video_reached = 1'b0;
    logic golden_first_video_dumped = 1'b0;

    always_ff @(posedge clk_96) begin
        if (reset) begin
            fast_divider <= 15'd0;
            fast_video_phase <= 32'd0;
            fast_adpcm_phase <= 32'd0;
            fast_video_ce <= 1'b0;
            fast_adpcm_ce <= 1'b0;
        end else begin
            fast_divider <= fast_divider + 15'd1;
            fast_video_phase <= fast_video_sum[31:0];
            fast_adpcm_phase <= fast_adpcm_sum[31:0];
            fast_video_ce <= fast_video_sum[32];
            fast_adpcm_ce <= fast_adpcm_sum[32];
        end
    end

    always_ff @(posedge clk_96) begin
        if (dut.board_reset) begin
            golden_sprite_writes <= 0;
            golden_sprite_pass_reached <= 1'b0;
            golden_first_video_reached <= 1'b0;
        end else if (golden_sprite_pass &&
                dut.main_bus.trace_mem_write &&
                dut.main_a >= 16'hc000 && dut.main_a <= 16'hcbff) begin
            golden_sprite_writes <= golden_sprite_writes + 1;
            if (dut.main_a == 16'hcbff)
                golden_sprite_pass_reached <= 1'b1;
        end
        if (!dut.board_reset && golden_sprite_pass &&
                dut.main_bus.trace_mem_write &&
                dut.main_a == 16'hcc80 && dut.main_do[5])
            golden_first_video_reached <= 1'b1;
    end

    task automatic check_main_write (
        input byte         kind,
        input logic [15:0] address,
        input logic [7:0]  data
    );
        begin
            if (write_scoreboard_enabled) begin
                if (write_oracle_index >= write_oracle_count) begin
                    $display("SCOREBOARD: RTL ran past the oracle at index %0d",
                             write_oracle_index);
                end else if (kind !== write_oracle_kind[write_oracle_index] ||
                        address !== write_oracle_address[write_oracle_index] ||
                        data !== write_oracle_data[write_oracle_index]) begin
                    $display("SCOREBOARD MISMATCH at write index %0d, time %0t",
                             write_oracle_index, $time);
                    $display("  RTL  : %c %04x %02x", kind, address, data);
                    $display("  MAME : %c %04x %02x",
                             write_oracle_kind[write_oracle_index],
                             write_oracle_address[write_oracle_index],
                             write_oracle_data[write_oracle_index]);
                    $fatal(1, "ordered main-board write divergence");
                end else begin
                    write_oracle_index = write_oracle_index + 1;
                    if (write_oracle_index % 10000 == 0)
                        $display("SCOREBOARD: %0d/%0d main writes match",
                                 write_oracle_index, write_oracle_count);
                end
            end
        end
    endtask

    task automatic load_write_oracle;
        begin
            write_oracle_file = $fopen(
                "sim/out/mame-main-write-oracle.txt", "r");
            if (!write_oracle_file)
                $fatal(1, "missing sim/out/mame-main-write-oracle.txt");
            while (write_oracle_count < WRITE_ORACLE_MAX) begin
                write_oracle_scanned = $fscanf(
                    write_oracle_file, "%s %x %x\n",
                    write_oracle_kind_text,
                    write_oracle_address_value,
                    write_oracle_data_value);
                if (write_oracle_scanned != 3)
                    break;
                write_oracle_kind[write_oracle_count] =
                    byte'(write_oracle_kind_text.getc(0));
                write_oracle_address[write_oracle_count] =
                    write_oracle_address_value[15:0];
                write_oracle_data[write_oracle_count] =
                    write_oracle_data_value[7:0];
                write_oracle_count = write_oracle_count + 1;
            end
            $fclose(write_oracle_file);
            if (write_oracle_count < 10000)
                $fatal(1, "short main-write oracle: %0d entries",
                       write_oracle_count);
            $display("SCOREBOARD: loaded %0d ordered MAME main writes",
                     write_oracle_count);
        end
    endtask

    task automatic report_write_scoreboard;
        begin
            if (write_scoreboard_enabled)
                $display(
                    "SCOREBOARD: %0d of %0d ordered MAME main writes matched",
                    write_oracle_index, write_oracle_count);
        end
    endtask

    task automatic trace_event (
        input string domain,
        input string kind,
        input logic [15:0] address,
        input logic [7:0] data
    );
        $fwrite(trace_file, "%0t,%s,%s,%04x,%02x\n",
                $time, domain, kind, address, data);
    endtask

    always_ff @(posedge clk_96) begin
        previous_main_address <= debug_main_address;
        previous_sound_address <= debug_sound_address;
        previous_6809_address <= debug_6809_address;
        previous_cctl_address <= dut.cctl_rom_address;
        previous_ccpu_address <= dut.ccpu_rom_address;
        previous_ucpu_address <= dut.ucpu_rom_address;
        previous_csnd_address <= dut.csnd_rom_address;
        previous_rom_ready <= rom_ready;
        previous_board_reset <= dut.board_reset;
        mcu_patch_seen <= mcu_patch_seen | debug_mcu_patch_visible;
        main_fetch_active <= !dut.main_m1_n && !dut.main_mreq_n &&
                             !dut.main_rd_n;
        sound_fetch_active <= !dut.sound_m1_n && !dut.sound_mreq_n &&
                              !dut.sound_rd_n;
        cpu6809_fetch_active <= dut.cpu6809_op && dut.cpu6809_vma &&
                                dut.cpu6809_rnw;

        if (rom_ready != previous_rom_ready)
            trace_event("system", "rom_ready", 16'd0,
                        {7'd0, rom_ready});
        if (dut.board_reset != previous_board_reset)
            trace_event("system", "board_reset", 16'd0,
                        {7'd0, dut.board_reset});

        if (!fast_startup && !dut.board_reset &&
                !dut.main_m1_n && !dut.main_mreq_n &&
                !dut.main_rd_n && !main_fetch_active)
            $fwrite(main_opcode_file, "%04x,%02x\n", dut.main_a,
                    dut.main_di);
        if (!fast_startup && !dut.board_reset &&
                !dut.sound_m1_n && !dut.sound_mreq_n &&
                !dut.sound_rd_n && !sound_fetch_active)
            $fwrite(sound_opcode_file, "%04x,%02x\n", dut.sound_a,
                    dut.sound_di);
        if (!fast_startup && !dut.board_reset &&
                dut.cpu6809_op && dut.cpu6809_vma &&
                dut.cpu6809_rnw && !cpu6809_fetch_active)
            $fwrite(cpu6809_opcode_file, "%04x,%02x\n", dut.cpu6809_a,
                    dut.cpu6809_di);

        if (!dut.board_reset && debug_main_address != previous_main_address)
            main_address_changes <= main_address_changes + 1;
        if (!dut.board_reset && debug_sound_address != previous_sound_address)
            sound_address_changes <= sound_address_changes + 1;
        if (!dut.board_reset && debug_6809_address != previous_6809_address)
            cpu6809_address_changes <= cpu6809_address_changes + 1;
        if (!dut.board_reset &&
                dut.cctl_rom_address != previous_cctl_address)
            cctl_address_changes <= cctl_address_changes + 1;
        if (!dut.board_reset &&
                dut.ccpu_rom_address != previous_ccpu_address)
            ccpu_address_changes <= ccpu_address_changes + 1;
        if (!dut.board_reset &&
                dut.ucpu_rom_address != previous_ucpu_address)
            ucpu_address_changes <= ucpu_address_changes + 1;
        if (!dut.board_reset &&
                dut.csnd_rom_address != previous_csnd_address)
            csnd_address_changes <= csnd_address_changes + 1;
        if (!dut.board_reset && !csnd_unknown_seen &&
                $isunknown(dut.csnd_rom_address)) begin
            csnd_unknown_seen <= 1'b1;
            $display("CSND first unknown t=%0t prev=%03x dmem_a=%02x dmem_i=%02x dmem_o=%02x dmem_we=%b pmem_d=%02x",
                     $time, previous_csnd_address,
                     dut.mcu_cluster.csnd.dmem_address,
                     dut.mcu_cluster.csnd.dmem_data_in,
                     dut.mcu_cluster.csnd.dmem_data_out,
                     dut.mcu_cluster.csnd.dmem_write,
                     dut.csnd_raw_rom_data);
        end

        if (!fast_startup && !dut.board_reset &&
                dut.main_bus.trace_mem_read) begin
            main_reads <= main_reads + 1;
            trace_event("main", "mem_r", dut.main_a, dut.main_di);
        end
        if (!fast_startup && !dut.board_reset &&
                dut.main_bus.trace_mem_write) begin
            main_writes <= main_writes + 1;
            trace_event("main", "mem_w", dut.main_a, dut.main_do);
        end
        // Scoreboard hooks are deliberately independent of fast_startup:
        // the write stream must be checked even when tracing is throttled.
        if (!dut.board_reset && dut.main_bus.trace_mem_write)
            check_main_write("M", dut.main_a, dut.main_do);
        if (!dut.board_reset && dut.main_bus.trace_io_read) begin
            main_io_reads <= main_io_reads + 1;
            trace_event("main", "io_r", dut.main_a, dut.main_di);
        end
        if (!dut.board_reset && dut.main_bus.trace_io_write) begin
            main_io_writes <= main_io_writes + 1;
            trace_event("main", "io_w", dut.main_a, dut.main_do);
        end
        if (!dut.board_reset && dut.main_bus.trace_io_write)
            check_main_write("I", dut.main_a, dut.main_do);

        if (!fast_startup && !dut.board_reset &&
                dut.sound_bus.trace_mem_read) begin
            sound_reads <= sound_reads + 1;
            trace_event("sound", "mem_r", dut.sound_a, dut.sound_di);
        end
        if (!fast_startup && !dut.board_reset &&
                dut.sound_bus.trace_mem_write) begin
            sound_writes <= sound_writes + 1;
            trace_event("sound", "mem_w", dut.sound_a, dut.sound_do);
        end
        if (!dut.board_reset && dut.sound_bus.trace_io_read) begin
            sound_io_reads <= sound_io_reads + 1;
            trace_event("sound", "io_r", dut.sound_a, dut.sound_di);
        end
        if (!dut.board_reset && dut.sound_bus.trace_io_write) begin
            sound_io_writes <= sound_io_writes + 1;
            trace_event("sound", "io_w", dut.sound_a, dut.sound_do);
        end

        if (!fast_startup && !dut.board_reset && dut.bus6809.trace_read) begin
            cpu6809_reads <= cpu6809_reads + 1;
            trace_event("6809", "mem_r", dut.cpu6809_a, dut.cpu6809_di);
        end
        if (!fast_startup && !dut.board_reset &&
                dut.bus6809.trace_write) begin
            cpu6809_writes <= cpu6809_writes + 1;
            trace_event("6809", "mem_w", dut.cpu6809_a, dut.cpu6809_do);
        end

        if (!dut.board_reset && !dut.main_ucpu_cs_n)
            ucpu_host_cycles <= ucpu_host_cycles + 1;
        if (!dut.board_reset && !dut.cctl_cs_n)
            cctl_host_cycles <= cctl_host_cycles + 1;
        if (!dut.board_reset && !dut.ccpu_cs_n)
            ccpu_host_cycles <= ccpu_host_cycles + 1;
        if (!dut.board_reset && !dut.csnd_cs_n)
            csnd_host_cycles <= csnd_host_cycles + 1;
    end

    integer rom_file;
    integer bytes_read;
    integer total_read;
    integer index;

    task automatic read_region (
        input string name,
        input integer actual,
        input integer expected
    );
        begin
            if (actual != expected)
                $fatal(1, "%s read %0d bytes, expected %0d",
                       name, actual, expected);
            total_read = total_read + actual;
        end
    endtask

    task automatic dump_golden_state(input string output_path);
        integer state_file;
        integer i;
        integer adler_a;
        integer adler_b;
        logic [31:0] sprite_hash;
        logic [31:0] state_hash;
        begin
            state_file = $fopen(output_path, "w");
            if (!state_file)
                $fatal(1, "cannot create RTL sprite-pass state");

            adler_a = 1;
            adler_b = 0;
            for (i = 0; i < 3072; i = i + 1) begin
                adler_a = (adler_a + dut.main_bus.sprite_ram[i]) % 65521;
                adler_b = (adler_b + adler_a) % 65521;
            end
            sprite_hash = {adler_b[15:0], adler_a[15:0]};

            adler_a = 1;
            adler_b = 0;
            for (i = 0; i < 1024; i = i + 1) begin
                adler_a = (adler_a + dut.main_bus.palette_lo[i]) % 65521;
                adler_b = (adler_b + adler_a) % 65521;
            end
            for (i = 0; i < 1024; i = i + 1) begin
                adler_a = (adler_a + dut.main_bus.palette_ex[i]) % 65521;
                adler_b = (adler_b + adler_a) % 65521;
            end
            for (i = 0; i < 2048; i = i + 1) begin
                adler_a = (adler_a + dut.main_bus.bg_code_ram[i]) % 65521;
                adler_b = (adler_b + adler_a) % 65521;
            end
            for (i = 0; i < 2048; i = i + 1) begin
                adler_a = (adler_a + dut.main_bus.bg_attr_ram[i]) % 65521;
                adler_b = (adler_b + adler_a) % 65521;
            end
            for (i = 0; i < 2048; i = i + 1) begin
                adler_a = (adler_a + dut.main_bus.fg_code_ram[i]) % 65521;
                adler_b = (adler_b + adler_a) % 65521;
            end
            for (i = 0; i < 2048; i = i + 1) begin
                adler_a = (adler_a + dut.main_bus.nvram[i]) % 65521;
                adler_b = (adler_b + adler_a) % 65521;
            end
            state_hash = {adler_b[15:0], adler_a[15:0]};

            $fwrite(state_file,
                    "logical_cycles=%0d\nmain_address=%04X\n",
                    golden_logical_cycles, dut.main_a);
            $fwrite(state_file,
                    "sprite_writes=%0d\nvideo_attributes=%02X\n",
                    golden_sprite_writes, dut.video_attributes);
            $fwrite(state_file,
                    "latch=%02X\nsprite_buffer=%0d\nsprite_bank=%0d\n",
                    dut.latch_debug, dut.sprite_buffer,
                    dut.sprite_bank_base);
            $fwrite(state_file,
                    "sprite_hash=%08X\nstate_hash=%08X\n",
                    sprite_hash, state_hash);

            $fwrite(state_file, "sprite_c000_cbff=");
            for (i = 0; i < 3072; i = i + 1)
                $fwrite(state_file, "%02X", dut.main_bus.sprite_ram[i]);
            $fwrite(state_file, "\nstate_d000_f7ff=");
            for (i = 0; i < 1024; i = i + 1)
                $fwrite(state_file, "%02X", dut.main_bus.palette_lo[i]);
            for (i = 0; i < 1024; i = i + 1)
                $fwrite(state_file, "%02X", dut.main_bus.palette_ex[i]);
            for (i = 0; i < 2048; i = i + 1)
                $fwrite(state_file, "%02X", dut.main_bus.bg_code_ram[i]);
            for (i = 0; i < 2048; i = i + 1)
                $fwrite(state_file, "%02X", dut.main_bus.bg_attr_ram[i]);
            for (i = 0; i < 2048; i = i + 1)
                $fwrite(state_file, "%02X", dut.main_bus.fg_code_ram[i]);
            for (i = 0; i < 2048; i = i + 1)
                $fwrite(state_file, "%02X", dut.main_bus.nvram[i]);
            $fwrite(state_file, "\n");
            $fclose(state_file);
        end
    endtask

    always @(negedge clk_96) begin
        if (golden_sprite_pass && golden_first_video_reached &&
                !golden_first_video_dumped) begin
            dump_golden_state("sim/out/rtl-first-visible-state.txt");
            golden_first_video_dumped = 1'b1;
            $display(
                "GOLDEN first-video state cycles=%0d writes=%0d",
                golden_logical_cycles, golden_sprite_writes);
        end
    end

    initial begin
        legacy_fast_startup = $test$plusargs("FAST_STARTUP");
        golden_sprite_pass = $test$plusargs("GOLDEN_SPRITE_PASS");
        write_scoreboard_enabled = $test$plusargs("WRITE_SCOREBOARD");
        if (write_scoreboard_enabled)
            load_write_oracle();
        fast_startup = legacy_fast_startup || golden_sprite_pass;
        if (!$value$plusargs("BOOT_CYCLES=%d", boot_cycles))
            boot_cycles = golden_sprite_pass ? 35000000 :
                          (legacy_fast_startup ? 2000000 : 500000);
        if (golden_sprite_pass) begin
            // One simulator edge represents one 12 MHz board tick. Multiply
            // each production 96 MHz fractional-N step by eight and preserve
            // every CPU, MCU, video and ADPCM ratio. Vblank comes only from
            // the real raster timing in this mode.
            force dut.ce_12m = 1'b1;
            force dut.ce_6m = fast_ce_6m;
            force dut.ce_3m = fast_ce_3m;
            force dut.ce_1m5 = fast_ce_1m5;
            force dut.tclk = fast_tclk;
            force dut.ce_455k = fast_adpcm_ce;
            force dut.timing.ce_mame = fast_video_ce;
        end else if (legacy_fast_startup) begin
            // Preserve every board-domain frequency ratio while removing
            // seven idle 96 MHz clocks out of eight. Vblank is separately
            // accelerated because the boot self-test deliberately waits
            // dozens of frames before polling the MCU complex.
            force dut.ce_12m = 1'b1;
            force dut.ce_6m = fast_ce_6m;
            force dut.ce_3m = fast_ce_3m;
            force dut.ce_1m5 = fast_ce_1m5;
            force dut.tclk = fast_tclk;
            force dut.vblank_irq_set = fast_vblank_irq;
        end

        trace_file = $fopen("sim/out/board-boot-trace.csv", "w");
        if (!trace_file)
            $fatal(1, "cannot create board boot trace");
        $fwrite(trace_file, "time_ps,domain,kind,address,data\n");
        main_opcode_file = $fopen("sim/out/board-main-opcodes.csv", "w");
        sound_opcode_file = $fopen("sim/out/board-sound-opcodes.csv", "w");
        cpu6809_opcode_file = $fopen("sim/out/board-6809-opcodes.csv", "w");
        if (!main_opcode_file || !sound_opcode_file || !cpu6809_opcode_file)
            $fatal(1, "cannot create board opcode traces");
        $fwrite(main_opcode_file, "address,opcode\n");
        $fwrite(sound_opcode_file, "address,opcode\n");
        $fwrite(cpu6809_opcode_file, "address,opcode\n");

        rom_file = $fopen("sim/out/gladiatr.rom", "rb");
        if (!rom_file)
            $fatal(1, "missing sim/out/gladiatr.rom");
        total_read = 0;
        bytes_read = $fread(dut.roms.main_rom, rom_file);
        read_region("main", bytes_read, 16'hffff + 1 + 16'h2000);
        bytes_read = $fread(dut.roms.sound_rom, rom_file);
        read_region("sound", bytes_read, 16'h4000);
        bytes_read = $fread(dut.roms.adpcm_rom, rom_file);
        read_region("adpcm", bytes_read, 17'h18000);
        bytes_read = $fread(dut.roms.text_rom, rom_file);
        read_region("text", bytes_read, 16'h2000);
        bytes_read = $fread(dut.roms.bg_p3_rom, rom_file);
        read_region("bg-p3", bytes_read, 16'h8000);
        bytes_read = $fread(dut.roms.bg_p12_rom, rom_file);
        read_region("bg-p12", bytes_read, 17'h10000);
        bytes_read = $fread(dut.roms.sp_p3_rom, rom_file);
        read_region("sprite-p3", bytes_read, 17'h0c000);
        bytes_read = $fread(dut.roms.sp_p12_rom, rom_file);
        read_region("sprite-p12", bytes_read, 17'h18000);
        bytes_read = $fread(dut.roms.prom_rom, rom_file);
        read_region("proms", bytes_read, 64);
        bytes_read = $fread(dut.roms.cctl_rom, rom_file);
        read_region("cctl", bytes_read, 1024);
        bytes_read = $fread(dut.roms.ccpu_rom, rom_file);
        read_region("ccpu", bytes_read, 1024);
        bytes_read = $fread(dut.roms.ucpu_rom, rom_file);
        read_region("ucpu", bytes_read, 1024);
        bytes_read = $fread(dut.roms.csnd_rom, rom_file);
        read_region("csnd", bytes_read, 2048);
        $fclose(rom_file);
        if (total_read != 20'h6d440)
            $fatal(1, "loaded %0d bytes, expected 0x6d440", total_read);

        // MAME allocates these RAM shares as zeroed memory, and MiSTer's
        // inferred FPGA RAM has a deterministic zero configuration image.
        // Seed only the oracle harness so four-state simulation does not
        // manufacture X-byte differences before the board diagnostics write
        // every location. This does not modify the hardware-facing RTL.
        if (golden_sprite_pass) begin
            for (index = 0; index < 3072; index = index + 1)
                dut.main_bus.sprite_ram[index] = 8'h00;
            for (index = 0; index < 1024; index = index + 1) begin
                dut.main_bus.palette_lo[index] = 8'h00;
                dut.main_bus.palette_ex[index] = 8'h00;
                dut.sound_bus.work_ram[index] = 8'h00;
            end
            for (index = 0; index < 2048; index = index + 1) begin
                dut.main_bus.bg_code_ram[index] = 8'h00;
                dut.main_bus.bg_attr_ram[index] = 8'h00;
                dut.main_bus.fg_code_ram[index] = 8'h00;
                dut.main_bus.nvram[index] = 8'h00;
            end
        end

        // Exercise the normal ROM loader completion contract without
        // serially replaying bytes already loaded by $fread.
        @(negedge clk_96);
        reset = 1'b0;
        download_active = 1'b1;
        repeat (2) @(negedge clk_96);
        download_address = 20'h6d43f;
        download_data = dut.roms.csnd_rom[2047];
        download_write = 1'b1;
        @(negedge clk_96);
        download_write = 1'b0;
        @(negedge clk_96);
        download_active = 1'b0;
        repeat (4) @(posedge clk_96);
        if (!rom_ready)
            $fatal(1, "ROM ready handshake failed");

        // Match MiSTer's transaction order: index 2 NVRAM is transferred
        // after index 0 ROM and holds the board in reset.  This used to clear
        // rom_ready and leave every board CPU permanently reset.
        @(negedge clk_96);
        reset = 1'b1;
        nvram_host_enable = 1'b1;
        nvram_host_write = 1'b1;
        nvram_host_data_in = 8'h00;
        for (index = 0; index < 2048; index = index + 1) begin
            @(negedge clk_96);
            nvram_host_address = index[10:0];
        end
        @(negedge clk_96);
        nvram_host_write = 1'b0;
        nvram_host_address = 11'h123;
        repeat (2) @(negedge clk_96);
        if (nvram_host_data_out !== 8'h00)
            $fatal(1, "first-run NVRAM host readback failed");
        if (!rom_ready)
            $fatal(1, "NVRAM transaction cleared ROM readiness");
        nvram_host_enable = 1'b0;
        reset = 1'b0;
        repeat (4) @(posedge clk_96);
        if (dut.board_reset)
            $fatal(1, "board reset did not release after ROM plus NVRAM");

        if (golden_sprite_pass) begin
            while (!golden_sprite_pass_reached &&
                    golden_logical_cycles < boot_cycles) begin
                @(posedge clk_96);
                golden_logical_cycles = golden_logical_cycles + 1;
                if ((golden_logical_cycles % 1000000) == 0)
                    $display(
                        "GOLDEN progress cycles=%0d sprite_writes=%0d main=%04x video=%02x",
                        golden_logical_cycles, golden_sprite_writes,
                        dut.main_a, dut.video_attributes);
            end
            if (!golden_sprite_pass_reached)
                $fatal(1,
                       "RTL did not reach first CBFF write in %0d logical cycles",
                       boot_cycles);
            @(negedge clk_96);
            dump_golden_state(
                "sim/out/rtl-first-sprite-pass-state.txt");
            $fclose(trace_file);
            $fclose(main_opcode_file);
            $fclose(sound_opcode_file);
            $fclose(cpu6809_opcode_file);
            $display(
                "PASS RTL golden sprite-pass state cycles=%0d writes=%0d hash file complete",
                golden_logical_cycles, golden_sprite_writes);
            report_write_scoreboard();
            $finish;
        end

        repeat (boot_cycles) @(posedge clk_96);

        $display("BOOT main=%04x sound=%04x 6809=%04x",
                 debug_main_address, debug_sound_address,
                 debug_6809_address);
        $display("TRACE main r/w/io=%0d/%0d/%0d/%0d sound=%0d/%0d/%0d/%0d 6809=%0d/%0d",
                 main_reads, main_writes, main_io_reads, main_io_writes,
                 sound_reads, sound_writes, sound_io_reads, sound_io_writes,
                 cpu6809_reads, cpu6809_writes);
        $display("MCU host cycles ucpu/cctl/ccpu/csnd=%0d/%0d/%0d/%0d",
                 ucpu_host_cycles, cctl_host_cycles,
                 ccpu_host_cycles, csnd_host_cycles);
        $display("MCU program address changes cctl/ccpu/ucpu/csnd=%0d/%0d/%0d/%0d",
                 cctl_address_changes, ccpu_address_changes,
                 ucpu_address_changes, csnd_address_changes);
        $display("MCU final program addresses cctl/ccpu/ucpu/csnd=%03x/%03x/%03x/%03x",
                 dut.cctl_rom_address, dut.ccpu_rom_address,
                 dut.ucpu_rom_address, dut.csnd_rom_address);
        if (fast_startup)
            $display("FAST_STARTUP latch=%02x video=%02x ymA=%02x ymB=%02x NVRAMdirty=%b",
                     dut.latch_debug, dut.video_attributes,
                     dut.ym_port_a, dut.ym_port_b, nvram_dirty);

        if (!fast_startup &&
                (main_reads < 100 || main_address_changes < 100))
            $fatal(1, "main Z80 failed boot smoke test");
        if (!fast_startup &&
                (sound_reads < 50 || sound_address_changes < 50))
            $fatal(1, "sound Z80 failed boot smoke test");
        if (!fast_startup &&
                (cpu6809_reads < 50 || cpu6809_address_changes < 50))
            $fatal(1, "6809 failed boot smoke test");
        if (mcu_patch_seen != 2'b11)
            $fatal(1, "derived MCU repair was not exercised");
        if (cctl_address_changes < 100 || ccpu_address_changes < 100 ||
                ucpu_address_changes < 100)
            $fatal(1, "one or more active UPI-41 firmware instances did not execute");
        // A separate isolated test proves the no-command 0x050 IBF loop.
        // Here the real sound Z80 has already accessed CSND, so require
        // continued defined execution and a real host transaction.
        if (csnd_unknown_seen || $isunknown(dut.csnd_rom_address) ||
                csnd_address_changes < 100 || csnd_host_cycles == 0)
            $fatal(1, "CSND MCU execution or host interface failed");
        if (debug_sprite_overruns != 0)
            $fatal(1, "sprite line builder overran during boot");
        if (!nvram_dirty)
            $fatal(1, "main CPU did not dirty initialized battery RAM");

        // Model the beginning of a MiSTer upload and prove that it
        // acknowledges the current dirty generation without writing RAM.
        @(negedge clk_96);
        nvram_host_enable = 1'b1;
        nvram_host_write = 1'b0;
        repeat (2) @(negedge clk_96);
        if (nvram_dirty)
            $fatal(1, "NVRAM upload did not clear dirty state");
        nvram_host_enable = 1'b0;

        $fclose(trace_file);
        $fclose(main_opcode_file);
        $fclose(sound_opcode_file);
        $fclose(cpu6809_opcode_file);
        report_write_scoreboard();
        $display("PASS tb_board_boot");
        $finish;
    end
endmodule
