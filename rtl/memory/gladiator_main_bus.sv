// MAP-MAIN-001, PROM-DEC-001, LATCH-5L-001, IRQ-MAIN-001
// Main-Z80 board bus, RAMs, video registers, and the physical 5L LS259.
module gladiator_main_bus (
    input  logic        clk,
    input  logic        reset,

    input  logic [15:0] cpu_address,
    input  logic [7:0]  cpu_data_out,
    output logic [7:0]  cpu_data_in,
    input  logic        cpu_m1_n,
    input  logic        cpu_mreq_n,
    input  logic        cpu_iorq_n,
    input  logic        cpu_rd_n,
    input  logic        cpu_wr_n,

    output logic [16:0] rom_address,
    input  logic [7:0]  rom_data,

    input  logic        vblank_irq_set,
    output logic        main_int_n,

    output logic        ucpu_cs_n,
    output logic        ucpu_a0,
    output logic        ucpu_rd_n,
    output logic        ucpu_wr_n,
    output logic [7:0]  ucpu_data_out,
    input  logic [7:0]  ucpu_data_in,

    output logic        compat_sub_irq_set,
    output logic        sub_reset,

    output logic        sprite_buffer,
    output logic [2:0]  sprite_bank_base,
    output logic        program_bank,
    output logic        flip_screen,
    output logic [7:0]  unknown_latch_bits,

    output logic [7:0]  fg_scrolly,
    output logic [7:0]  fg_scrollx,
    output logic [7:0]  bg_scrolly,
    output logic [7:0]  bg_scrollx,
    output logic [7:0]  video_attributes,

    input  logic [10:0] video_bg_address,
    output logic [7:0]  video_bg_code,
    output logic [7:0]  video_bg_attr,
    input  logic [10:0] video_fg_address,
    output logic [7:0]  video_fg_code,
    input  logic [9:0]  video_palette_address,
    output logic [7:0]  video_palette_low,
    output logic [7:0]  video_palette_ext,
    input  logic [11:0] video_sprite_address,
    output logic [7:0]  video_sprite_data,

    input  logic        nvram_host_enable,
    input  logic        nvram_host_write,
    input  logic [10:0] nvram_host_address,
    input  logic [7:0]  nvram_host_data_in,
    output logic [7:0]  nvram_host_data_out,
    output logic        nvram_dirty,

    output logic        trace_mem_read,
    output logic        trace_mem_write,
    output logic        trace_io_read,
    output logic        trace_io_write
);

    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] sprite_ram [0:12'hbff];
    // REVERTED 2026-07-27 -- the fix does not fit this device.
    // Dropping no_rw_check forces READ_DURING_WRITE_MODE_MIXED_PORTS = OLD_DATA,
    // which Cyclone V cannot do natively in simple-dual-port M10K, so the fitter
    // pulled these arrays OUT of block RAM into logic: registers 21,006 ->
    // 71,459 and the fit died needing 4,347 LABs against 4,191 available. With
    // RAM blocks already at 544/553 there was no headroom for the fallback.
    // T-unit warned that dropping the hint can flip inference between M10K and
    // registers, and WOLF declined to touch wolf_mem.sv's pal for this reason.
    //
    // The DEFECT IS STILL REAL: these arrays are read by the video port every
    // cycle while the CPU writes the same addresses (measured 84-86% of writes
    // during ACTIVE display), and DONT_CARE output is documented UNDEFINED.
    // The correct fix keeps M10K and removes the collision instead of the hint:
    // add an explicit read-during-write bypass in RTL (compare the write address
    // to the read address and forward the old value), which makes DONT_CARE safe
    // by construction at a cost of a comparator and a mux rather than the whole
    // array. Deferred: it is unproven inference, the pen-order bugs in 5ac54947
    // are sim-proven and explain the symptom, and this build is scarce.
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] palette_lo [0:10'h3ff];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] palette_ex [0:10'h3ff];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] bg_code_ram[0:11'h7ff];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] bg_attr_ram[0:11'h7ff];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] fg_code_ram[0:11'h7ff];
    // Port enumeration (the audit recipe: list EVERY port, then name the port
    // the justification covers -- a hint justified against one consumer gets
    // silently inherited by the next one added).
    //   :221 CPU read    nvram[cpu_address]
    //   :222 host read   nvram[nvram_host_address]   <- added for OSD upload
    //   :299 host WRITE  nvram[nvram_host_address]   <- index-2 restore
    //   :301 CPU write   nvram[cpu_address]
    // FOUR ports, not three: 2W2R cannot fit one DUAL_PORT altsyncram, which is
    // why the fitter emits two replicas (nvram_rtl_0/1, each 2048x8 DONT_CARE).
    // The replicas CANNOT diverge -- :298/:300 are if/else-if, so the two writes
    // are mutually exclusive and get muxed into one write port that feeds both.
    // The else-if does let a host write block a CPU write, which would silently
    // drop a game NVRAM write; that is unreachable because host WRITES only
    // occur during the index-2 restore while board_reset is held and no CPU is
    // executing.  The upload that overlaps live play only READS -- and that read
    // vs the CPU write is the actual collision this ramstyle change addresses.
    // No justification was ever written for this array, and the host read port
    // was added later specifically so an upload would stop stealing the CPU's
    // port.  F000-F7FF is LIVE battery-backed work RAM that the game writes
    // during normal execution -- that is the documented cause of the save loop.
    // So an OSD save sweeps all 2048 addresses via the host port while the CPU
    // is actively writing them: host-read vs CPU-write collision, DONT_CARE,
    // undefined byte, corrupt saved NVRAM.  Lower stakes than the video path
    // (a bad saved byte, not a bad frame) but the same defect.
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] nvram      [0:11'h7ff];

    logic [7:0] sprite_cpu_q;
    logic [7:0] palette_lo_cpu_q;
    logic [7:0] palette_ex_cpu_q;
    logic [7:0] bg_code_cpu_q;
    logic [7:0] bg_attr_cpu_q;
    logic [7:0] fg_code_cpu_q;
    logic [7:0] nvram_cpu_q;
    logic [7:0] nvram_host_q;
    logic nvram_cpu_write;
    logic nvram_host_enable_d;

    logic [7:0] latch_q;
    logic irq_pending;
    logic mem_read_level, mem_write_level, io_read_level, io_write_level;
    logic mem_read_d, mem_write_d, io_read_d, io_write_d;
    logic mem_read_pulse, mem_write_pulse, io_read_pulse, io_write_pulse;
    logic int_ack;

    assign mem_read_level  = !cpu_mreq_n && !cpu_rd_n;
    assign mem_write_level = !cpu_mreq_n && !cpu_wr_n;
    assign io_read_level   = !cpu_iorq_n && !cpu_rd_n && cpu_m1_n;
    assign io_write_level  = !cpu_iorq_n && !cpu_wr_n && cpu_m1_n;
    assign int_ack         = !cpu_m1_n && !cpu_iorq_n;

    assign mem_read_pulse  = mem_read_level  && !mem_read_d;
    assign mem_write_pulse = mem_write_level && !mem_write_d;
    assign io_read_pulse   = io_read_level   && !io_read_d;
    assign io_write_pulse  = io_write_level  && !io_write_d;

    assign trace_mem_read  = mem_read_pulse;
    assign trace_mem_write = mem_write_pulse;
    assign trace_io_read   = io_read_pulse;
    assign trace_io_write  = io_write_pulse;

    assign main_int_n = !irq_pending;

    // The physical board has a single battery SRAM port.  The appliance-side
    // persistence reader must not steal it while the reconstructed board is
    // running: this RAM is also the game's live work/state memory.  Infer an
    // independent FPGA read port so a MiSTer upload cannot substitute its
    // address on CPU reads or suppress game-state writes.
    assign nvram_host_data_out = nvram_host_q;
    assign nvram_cpu_write = mem_write_pulse &&
                             cpu_address >= 16'hf000 &&
                             cpu_address <= 16'hf7ff;

    assign sprite_buffer   = latch_q[0];
    assign sprite_bank_base = latch_q[1] ? 3'd4 : 3'd2;
    assign program_bank    = latch_q[2];
    assign sub_reset       = latch_q[4];
    assign flip_screen     = latch_q[7];
    assign unknown_latch_bits = latch_q;

    assign ucpu_cs_n      = !(cpu_address[15:1] == 15'h604f) ||
                            !(io_read_level || io_write_level);
    assign ucpu_a0        = cpu_address[0];
    assign ucpu_rd_n      = !(!ucpu_cs_n && io_read_level);
    assign ucpu_wr_n      = !(!ucpu_cs_n && io_write_level);
    assign ucpu_data_out  = cpu_data_out;

    always_comb begin
        if (cpu_address < 16'h6000)
            rom_address = {1'b0, cpu_address};
        else if (cpu_address < 16'h8000)
            rom_address = 17'h06000 + {program_bank, 13'd0} +
                          (cpu_address - 16'h6000);
        else
            rom_address = 17'h0a000 + {program_bank, 14'd0} +
                          (cpu_address - 16'h8000);
    end

    always_comb begin
        cpu_data_in = 8'hff;
        if (mem_read_level) begin
            casez (cpu_address)
                16'b0???_????_????_????,
                16'b10??_????_????_????,
                16'b011?_????_????_????: cpu_data_in = rom_data;
                16'hc000: cpu_data_in = sprite_cpu_q;
                default: begin
                    if (cpu_address >= 16'hc000 && cpu_address <= 16'hcbff)
                        cpu_data_in = sprite_cpu_q;
                    else if (cpu_address >= 16'hd000 && cpu_address <= 16'hd3ff)
                        cpu_data_in = palette_lo_cpu_q;
                    else if (cpu_address >= 16'hd400 && cpu_address <= 16'hd7ff)
                        cpu_data_in = palette_ex_cpu_q;
                    else if (cpu_address >= 16'hd800 && cpu_address <= 16'hdfff)
                        cpu_data_in = bg_code_cpu_q;
                    else if (cpu_address >= 16'he000 && cpu_address <= 16'he7ff)
                        cpu_data_in = bg_attr_cpu_q;
                    else if (cpu_address >= 16'he800 && cpu_address <= 16'hefff)
                        cpu_data_in = fg_code_cpu_q;
                    else if (cpu_address >= 16'hf000 && cpu_address <= 16'hf7ff)
                        cpu_data_in = nvram_cpu_q;
                end
            endcase
        end else if (io_read_level && !ucpu_cs_n) begin
            cpu_data_in = ucpu_data_in;
        end
    end

    always_ff @(posedge clk) begin
        mem_read_d  <= mem_read_level;
        mem_write_d <= mem_write_level;
        io_read_d   <= io_read_level;
        io_write_d  <= io_write_level;

        sprite_cpu_q    <= sprite_ram[cpu_address[11:0]];
        palette_lo_cpu_q <= palette_lo[cpu_address[9:0]];
        palette_ex_cpu_q <= palette_ex[cpu_address[9:0]];
        bg_code_cpu_q   <= bg_code_ram[cpu_address[10:0]];
        bg_attr_cpu_q   <= bg_attr_ram[cpu_address[10:0]];
        fg_code_cpu_q   <= fg_code_ram[cpu_address[10:0]];
        nvram_cpu_q     <= nvram[cpu_address[10:0]];
        nvram_host_q    <= nvram[nvram_host_address];
        nvram_host_enable_d <= nvram_host_enable;

        video_sprite_data <= sprite_ram[video_sprite_address];
        video_palette_low <= palette_lo[video_palette_address];
        video_palette_ext <= palette_ex[video_palette_address];
        video_bg_code     <= bg_code_ram[video_bg_address];
        video_bg_attr     <= bg_attr_ram[video_bg_address];
        video_fg_code     <= fg_code_ram[video_fg_address];

        compat_sub_irq_set <= 1'b0;

        if (reset) begin
            latch_q          <= 8'd0;
            irq_pending      <= 1'b0;
            fg_scrolly       <= 8'd0;
            fg_scrollx       <= 8'd0;
            bg_scrolly       <= 8'd0;
            bg_scrollx       <= 8'd0;
            video_attributes <= 8'd0;
            nvram_dirty      <= 1'b0;
            nvram_host_enable_d <= 1'b0;
            mem_read_d       <= 1'b0;
            mem_write_d      <= 1'b0;
            io_read_d        <= 1'b0;
            io_write_d       <= 1'b0;
        end else begin
            if (vblank_irq_set)
                irq_pending <= 1'b1;
            if (int_ack)
                irq_pending <= 1'b0;

            if (mem_write_pulse) begin
                if (cpu_address >= 16'hc000 && cpu_address <= 16'hcbff)
                    sprite_ram[cpu_address[11:0]] <= cpu_data_out;
                else if (cpu_address >= 16'hd000 && cpu_address <= 16'hd3ff)
                    palette_lo[cpu_address[9:0]] <= cpu_data_out;
                else if (cpu_address >= 16'hd400 && cpu_address <= 16'hd7ff)
                    palette_ex[cpu_address[9:0]] <= cpu_data_out;
                else if (cpu_address >= 16'hd800 && cpu_address <= 16'hdfff)
                    bg_code_ram[cpu_address[10:0]] <= cpu_data_out;
                else if (cpu_address >= 16'he000 && cpu_address <= 16'he7ff)
                    bg_attr_ram[cpu_address[10:0]] <= cpu_data_out;
                else if (cpu_address >= 16'he800 && cpu_address <= 16'hefff)
                    fg_code_ram[cpu_address[10:0]] <= cpu_data_out;
                else if (cpu_address >= 16'hf000 && cpu_address <= 16'hf7ff)
                    nvram_dirty <= 1'b1;
            end

            if (mem_write_pulse && cpu_address >= 16'hcc00 &&
                    cpu_address <= 16'hcfff) begin
                case (cpu_address)
                    16'hcc00: fg_scrolly       <= cpu_data_out;
                    16'hcc80: video_attributes <= cpu_data_out;
                    16'hcd00: fg_scrollx       <= cpu_data_out;
                    16'hce00: bg_scrolly       <= cpu_data_out;
                    16'hcf00: bg_scrollx       <= cpu_data_out;
                    default: ;
                endcase
            end

            if (io_write_pulse && cpu_address >= 16'hc000 &&
                    cpu_address <= 16'hc007) begin
                latch_q[cpu_address[2:0]] <= cpu_data_out[0];
                if (cpu_address == 16'hc004)
                    compat_sub_irq_set <= 1'b1;
            end
        end

        // MiSTer downloads are performed while the board is reset. Uploads
        // may overlap live play, so acknowledge the saved generation only
        // once at transaction start. A later CPU write creates a new dirty
        // generation even if the upload is still in progress.
        if (nvram_host_enable && !nvram_host_enable_d)
            nvram_dirty <= 1'b0;

        if (nvram_host_enable && nvram_host_write) begin
            nvram[nvram_host_address] <= nvram_host_data_in;
        end else if (nvram_cpu_write) begin
            nvram[cpu_address[10:0]] <= cpu_data_out;
            nvram_dirty <= 1'b1;
        end
    end

endmodule
