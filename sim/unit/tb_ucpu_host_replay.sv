`timescale 1ns/1ps

// ADAPTIVE ucpu HOST-PORT REPLAY against MAME.
//
// MAME supplies the ordered host writes and fresh output payloads, but not the
// timing of status polling. Before every write this bench polls the RTL's own
// status until IBF clears. A MAME data read is treated as a fresh payload only
// when its immediately preceding status sequence ended with OBF set; the bench
// then polls the RTL until its own OBF sets and compares the data bytes.
//
// MAME status reads are never compared. Data-port reads made with OBF clear (or
// with no preceding status check) are stale-latch rereads, not new payloads;
// they are skipped so a faster or slower MCU cannot consume a response early
// and manufacture a downstream desynchronization.
//
// This is deliberately different from the old fixed replay, which forced all
// of MAME's surplus polls into a faster RTL MCU and reported timing differences
// as functional mismatches.
//
// Why this bench exists: during attract, the main CPU's ONLY external I/O is
// C09E/C09F -- the ucpu UPI-41 host ports. Measured over a full attract run:
// 36,060 reads of C09E and 99,102 of C09F, and nothing else at all. So the
// ucpu decides everything the game does, including whether it ever reaches the
// title screen and which stage it starts on. C09E returns 130 distinct values
// including 0xA5 five thousand times, i.e. a real handshake protocol rather
// than plain input polling.
//
// Reaching the title screen (frame 4819 = tick 972,474,200) by simulating the
// whole board is 103 HOURS at the measured 2,618 cycles/sec. This bench tests
// the same decision-making component in minutes by replaying MAME's ordered
// transaction stream into our MCU cluster and diffing the responses.
//
// The oracle is captured from MAME, independently of our RTL -- the same shape
// as the composite gate that found four video bugs, and deliberately NOT the
// self-consistent shape that let the pen-order inversion survive 75,008
// "exact" scanlines.
module tb_ucpu_host_replay;
    logic clk = 0;
    always #5.208 clk = ~clk;          // 96 MHz

    logic [13:0] divider = 0;
    logic ce_6m, tclk;
    integer sim_speed_log2 = 0;
    integer ce_period = 16;
    integer tclk_bit = 13;
    always_ff @(posedge clk) divider <= divider + 14'd1;
    assign ce_6m = ((divider & (ce_period - 1)) == (ce_period - 1));
    assign tclk  = divider[tclk_bit];

    logic reset = 1;

    logic       ucpu_a0 = 0, ucpu_cs_n = 1, ucpu_rd_n = 1, ucpu_wr_n = 1;
    logic [7:0] ucpu_host_data_in = 8'h00;
    logic [7:0] ucpu_host_data_out;
    logic       csnd_a0 = 0, csnd_cs_n = 1, csnd_rd_n = 1, csnd_wr_n = 1;
    logic [7:0] csnd_host_data_in = 8'h00;
    logic [7:0] csnd_host_data_out;

    logic [9:0]  cctl_rom_address, ccpu_rom_address, ucpu_rom_address;
    logic [10:0] csnd_rom_address;
    logic [7:0]  cctl_rom_data, ccpu_rom_data, ucpu_rom_data, csnd_rom_data;
    logic [10:0] ucpu_program_address_seen;
    logic [7:0]  ucpu_p1_out_seen, csnd_p1_out_seen;
    logic        ucpu_ibf_state, ucpu_obf_state;
    logic        csnd_ibf_state, csnd_obf_state;

    gladiator_roms roms (
        .clk(clk), .reset(reset),
        .download_active(1'b0), .download_write(1'b0),
        .download_address(20'd0), .download_data(8'd0), .rom_ready(),
        .main_address(17'd0), .main_data(),
        .sound_address(14'd0), .sound_data(),
        .adpcm_address(17'd0), .adpcm_data(),
        .text_address(13'd0), .text_data(),
        .bg_plane0_address(16'd0), .bg_plane0_data(),
        .bg_plane12_address(16'd0), .bg_plane12_data(),
        .sprite_plane0_address(17'd0), .sprite_plane0_data(),
        .sprite_plane12_address(17'd0), .sprite_plane12_data(),
        .prom_address(5'd0), .prom_q3_data(), .prom_q4_data(),
        .cctl_address(cctl_rom_address), .cctl_raw_data(cctl_rom_data),
        .ccpu_address(ccpu_rom_address), .ccpu_raw_data(ccpu_rom_data),
        .ucpu_address(ucpu_rom_address), .ucpu_raw_data(ucpu_rom_data),
        .csnd_address(csnd_rom_address), .csnd_raw_data(csnd_rom_data)
    );

`ifndef UCPU_REPLAY_LEAN
    gladiator_mcu_cluster dut (
        .clk(clk), .ce_6m(ce_6m), .reset(reset),
        .peripheral_reset(1'b0), .tclk(tclk),
        .enable_bad_dump_patch(1'b1),
        .dsw1(8'h5a), .dsw2(8'hbf),
        .player1_active_low(8'hff), .player2_active_low(8'hff),
        .player1_button3_active_low(1'b1), .player2_button3_active_low(1'b1),
        .coins_active_low(4'hf),
        .ucpu_a0(ucpu_a0), .ucpu_cs_n(ucpu_cs_n),
        .ucpu_rd_n(ucpu_rd_n), .ucpu_wr_n(ucpu_wr_n),
        .ucpu_host_data_in(ucpu_host_data_in),
        .ucpu_host_data_out(ucpu_host_data_out),
        .csnd_a0(csnd_a0), .csnd_cs_n(csnd_cs_n),
        .csnd_rd_n(csnd_rd_n), .csnd_wr_n(csnd_wr_n),
        .csnd_host_data_in(csnd_host_data_in),
        .csnd_host_data_out(csnd_host_data_out),
        .cctl_a0(1'b0), .cctl_cs_n(1'b1), .cctl_rd_n(1'b1), .cctl_wr_n(1'b1),
        .cctl_host_data_in(8'h00), .cctl_host_data_out(),
        .ccpu_a0(1'b0), .ccpu_cs_n(1'b1), .ccpu_rd_n(1'b1), .ccpu_wr_n(1'b1),
        .ccpu_host_data_in(8'h00), .ccpu_host_data_out(),
        .cctl_rom_address(cctl_rom_address), .cctl_raw_rom_data(cctl_rom_data),
        .ccpu_rom_address(ccpu_rom_address), .ccpu_raw_rom_data(ccpu_rom_data),
        .ucpu_rom_address(ucpu_rom_address), .ucpu_raw_rom_data(ucpu_rom_data),
        .csnd_rom_address(csnd_rom_address), .csnd_raw_rom_data(csnd_rom_data),
        .cctl_p1_out(), .cctl_p2_out(), .ccpu_p1_out(), .ccpu_p2_out(),
        .ucpu_p1_out(), .csnd_p1_out(),
        .coin_counter_active_low(), .bad_dump_patch_visible()
    );

    assign ucpu_program_address_seen = dut.ucpu_program_address;
    assign ucpu_p1_out_seen = dut.ucpu_p1_out;
    assign csnd_p1_out_seen = dut.csnd_p1_out;
    assign ucpu_ibf_state = dut.ucpu.core.bus_ibf_s;
    assign ucpu_obf_state = dut.ucpu.core.bus_obf_s;
    assign csnd_ibf_state = dut.csnd.core.bus_ibf_s;
    assign csnd_obf_state = dut.csnd.core.bus_obf_s;
`else
    // The replay needs only the mutually coupled UCPU and CSND devices. The
    // two unrelated control MCUs are omitted in this simulator-only build to
    // cut full-attract runtime without changing either tested device.
    logic [10:0] ucpu_program_address_full;
    logic [7:0]  ucpu_p2_unused, csnd_p2_unused;

    assign ucpu_rom_address = ucpu_program_address_full[9:0];
    assign ucpu_program_address_seen = ucpu_program_address_full;

    gladiator_upi41_device ucpu_dev (
        .clk(clk), .ce_6m(ce_6m), .reset(reset),
        .host_a0(ucpu_a0), .host_cs_n(ucpu_cs_n),
        .host_rd_n(ucpu_rd_n), .host_wr_n(ucpu_wr_n),
        .host_data_in(ucpu_host_data_in),
        .host_data_out(ucpu_host_data_out),
        .p1_pin_in({7'h7f, csnd_p1_out_seen[0]}),
        .p2_pin_in(8'h5a),
        .p1_latch_out(ucpu_p1_out_seen),
        .p2_latch_out(ucpu_p2_unused),
        .t0(tclk), .t1(csnd_p1_out_seen[1]),
        .program_address(ucpu_program_address_full),
        .program_data(ucpu_rom_data),
        .debug_dmem_address(), .debug_dmem_write()
    );

    gladiator_upi41_device csnd_dev (
        .clk(clk), .ce_6m(ce_6m), .reset(reset),
        .host_a0(csnd_a0), .host_cs_n(csnd_cs_n),
        .host_rd_n(csnd_rd_n), .host_wr_n(csnd_wr_n),
        .host_data_in(csnd_host_data_in),
        .host_data_out(csnd_host_data_out),
        .p1_pin_in({7'h7f, ucpu_p1_out_seen[0]}),
        .p2_pin_in(8'hf7),
        .p1_latch_out(csnd_p1_out_seen),
        .p2_latch_out(csnd_p2_unused),
        .t0(tclk), .t1(ucpu_p1_out_seen[1]),
        .program_address(csnd_rom_address),
        .program_data(csnd_rom_data),
        .debug_dmem_address(), .debug_dmem_write()
    );

    assign ucpu_ibf_state = ucpu_dev.core.bus_ibf_s;
    assign ucpu_obf_state = ucpu_dev.core.bus_obf_s;
    assign csnd_ibf_state = csnd_dev.core.bus_ibf_s;
    assign csnd_obf_state = csnd_dev.core.bus_obf_s;
`endif

    // ---- oracle ----
    integer log, rc, rom_file, bytes;
    integer t_tick, t_frame, t_a0, t_data, t_pc;
    logic [7:0] t_domain, t_dir;
    logic [8*256-1:0] csv_header;
    integer n_w = 0, fresh_reads = 0, mismatches = 0, checked = 0;
    integer ucpu_writes = 0, csnd_writes = 0;
    integer ucpu_fresh_reads = 0, csnd_fresh_reads = 0;
    integer skipped_status = 0, skipped_stale_data = 0;
    integer adaptive_status_polls = 0, payload_ops = 0;
    integer prev_action_tick = 0;
    integer gap_cap, max_payload, poll_limit;
    integer strobe;
    integer direct_status;

    task automatic host_write(
        input logic target_csnd,
        input logic a0,
        input logic [7:0] d
    );
        begin
            @(negedge clk);
            if (target_csnd) begin
                csnd_a0 = a0; csnd_host_data_in = d;
                csnd_cs_n = 0; csnd_wr_n = 0;
            end else begin
                ucpu_a0 = a0; ucpu_host_data_in = d;
                ucpu_cs_n = 0; ucpu_wr_n = 0;
            end
            repeat (strobe) @(negedge clk);   // host strobe width
            if (target_csnd) begin
                csnd_wr_n = 1; csnd_cs_n = 1;
            end else begin
                ucpu_wr_n = 1; ucpu_cs_n = 1;
            end
        end
    endtask

    task automatic host_read(
        input logic target_csnd,
        input logic a0,
        output logic [7:0] d
    );
        begin
            @(negedge clk);
            if (target_csnd) begin
                csnd_a0 = a0; csnd_cs_n = 0; csnd_rd_n = 0;
            end else begin
                ucpu_a0 = a0; ucpu_cs_n = 0; ucpu_rd_n = 0;
            end
            repeat (strobe) @(negedge clk);
            if (target_csnd) begin
                d = csnd_host_data_out;
                csnd_rd_n = 1; csnd_cs_n = 1;
            end else begin
                d = ucpu_host_data_out;
                ucpu_rd_n = 1; ucpu_cs_n = 1;
            end
        end
    endtask

    task automatic wait_ibf_clear(input logic target_csnd);
        logic [7:0] status;
        integer polls;
        begin
            polls = 0;
            if (direct_status) begin
                while ((target_csnd ? csnd_ibf_state :
                        ucpu_ibf_state) && polls < poll_limit) begin
                    @(negedge clk);
                    polls = polls + 1;
                end
                status = target_csnd ?
                    {6'h00, csnd_ibf_state, csnd_obf_state} :
                    {6'h00, ucpu_ibf_state, ucpu_obf_state};
            end else begin
                host_read(target_csnd, 1'b1, status);
                polls = polls + 1;
                while (status[1] && polls < poll_limit) begin
                    host_read(target_csnd, 1'b1, status);
                    polls = polls + 1;
                end
            end
            adaptive_status_polls = adaptive_status_polls + polls;
            if (status[1])
                $fatal(
                    1,
                    "adaptive %s host timed out waiting for IBF clear: writes=%0d fresh_reads=%0d frame=%0d pc=%04x next a0=%0d data=%02x status=%02x",
                    target_csnd ? "CSND" : "UCPU", n_w, fresh_reads,
                    t_frame, t_pc, t_a0, t_data, status);
        end
    endtask

    task automatic wait_obf_set(input logic target_csnd);
        logic [7:0] status;
        integer polls;
        begin
            polls = 0;
            if (direct_status) begin
                while (!(target_csnd ? csnd_obf_state :
                        ucpu_obf_state) && polls < poll_limit) begin
                    @(negedge clk);
                    polls = polls + 1;
                end
                status = target_csnd ?
                    {6'h00, csnd_ibf_state, csnd_obf_state} :
                    {6'h00, ucpu_ibf_state, ucpu_obf_state};
            end else begin
                host_read(target_csnd, 1'b1, status);
                polls = polls + 1;
                while (!status[0] && polls < poll_limit) begin
                    host_read(target_csnd, 1'b1, status);
                    polls = polls + 1;
                end
            end
            adaptive_status_polls = adaptive_status_polls + polls;
            if (!status[0])
                $fatal(
                    1,
                    "adaptive %s host timed out waiting for OBF set: writes=%0d fresh_reads=%0d frame=%0d pc=%04x expected=%02x status=%02x",
                    target_csnd ? "CSND" : "UCPU", n_w, fresh_reads,
                    t_frame, t_pc, t_data, status);
        end
    endtask

    task automatic wait_action_gap(input integer action_tick);
        longint unsigned logical_cycles, wait_cycles;
        begin
            logical_cycles = 0;
            wait_cycles = 0;
            if (prev_action_tick != 0)
                logical_cycles = (action_tick - prev_action_tick) * 8;
            if (logical_cycles > gap_cap)
                logical_cycles = gap_cap;
            wait_cycles = logical_cycles >> sim_speed_log2;
            if (logical_cycles != 0 && wait_cycles == 0)
                wait_cycles = 1;
            repeat (wait_cycles) @(negedge clk);
            prev_action_tick = action_tick;
        end
    endtask

    // Is the ucpu actually EXECUTING, and is the csnd link alive? A stalled
    // MCU and a miscomputing one look identical from the host port.
    logic [10:0] ucpu_pc_seen;
    integer      ucpu_pc_changes = 0;
    logic [7:0]  csnd_p1_seen;
    integer      csnd_p1_changes = 0;
    logic [10:0] csnd_pc_seen;
    integer      csnd_pc_changes = 0;
    always_ff @(posedge clk) begin
        ucpu_pc_seen <= ucpu_program_address_seen;
        if (ucpu_program_address_seen !== ucpu_pc_seen)
            ucpu_pc_changes <= ucpu_pc_changes + 1;
        csnd_pc_seen <= csnd_rom_address;
        if (csnd_rom_address !== csnd_pc_seen)
            csnd_pc_changes <= csnd_pc_changes + 1;
        csnd_p1_seen <= csnd_p1_out_seen;
        if (csnd_p1_out_seen !== csnd_p1_seen)
            csnd_p1_changes <= csnd_p1_changes + 1;
    end

    logic [7:0] got;
    integer done;
    integer ucpu_mame_status_seen, csnd_mame_status_seen;
    integer ucpu_write_since_status, csnd_write_since_status;
    integer progress_mark;
    logic [7:0] ucpu_mame_last_status, csnd_mame_last_status;
    logic target_csnd;

    initial begin
        if (!$value$plusargs("SIM_SPEED_LOG2=%d", sim_speed_log2))
            sim_speed_log2 = 0;
        if (sim_speed_log2 < 0 || sim_speed_log2 > 4)
            $fatal(1, "SIM_SPEED_LOG2 must be in the range 0..4");
        ce_period = 16 >> sim_speed_log2;
        tclk_bit = 13 - sim_speed_log2;

        rom_file = $fopen("sim/out/gladiatr.rom", "rb");
        if (!rom_file) $fatal(1, "missing sim/out/gladiatr.rom");
        bytes = $fread(roms.main_rom, rom_file);
        bytes = $fread(roms.sound_rom, rom_file);
        bytes = $fread(roms.adpcm_rom, rom_file);
        bytes = $fread(roms.text_rom, rom_file);
        bytes = $fread(roms.bg_p3_rom, rom_file);
        bytes = $fread(roms.bg_p12_rom, rom_file);
        bytes = $fread(roms.sp_p3_rom, rom_file);
        bytes = $fread(roms.sp_p12_rom, rom_file);
        bytes = $fread(roms.prom_rom, rom_file);
        bytes = $fread(roms.cctl_rom, rom_file);
        bytes = $fread(roms.ccpu_rom, rom_file);
        bytes = $fread(roms.ucpu_rom, rom_file);
        bytes = $fread(roms.csnd_rom, rom_file);
        $fclose(rom_file);

        // Positive mutation control: address 0x01f is the immediate byte in
        // "xrl a,#0x4a", the first coupled command comparison exercised by
        // this replay. Flipping it must prevent or corrupt the 0x4a response.
        if ($test$plusargs("MUTATE_UCPU_4A_COMPARE")) begin
            roms.ucpu_rom[10'h01f] =
                roms.ucpu_rom[10'h01f] ^ 8'h01;
            $display("MUTATION ACTIVE: UCPU 0x4a compare byte flipped");
        end

        log = $fopen("sim/out/mame-mcu-dual-host.csv", "r");
        if (!log) $fatal(1, "missing sim/out/mame-mcu-dual-host.csv");
        rc = $fgets(csv_header, log);              // header

        repeat (64 >> sim_speed_log2) @(negedge clk);
        reset = 0;
        repeat (2000 >> sim_speed_log2) @(negedge clk);

        // iverilog does not support break; use an explicit sentinel.
        if (!$value$plusargs("STROBE=%d", strobe))
            strobe = 16 >> sim_speed_log2;
        if (!$value$plusargs("GAPCAP=%d", gap_cap)) gap_cap = 4000;
        if (!$value$plusargs("POLL_LIMIT=%d", poll_limit))
            poll_limit = 200000;
        direct_status = $test$plusargs("DIRECT_STATUS");
        if (!$value$plusargs("MAXPAYLOAD=%d", max_payload)) begin
            // Backward-compatible spelling for the old positive-control runs.
            if (!$value$plusargs("MAXTX=%d", max_payload))
                max_payload = 0;
        end
        $display(
            "adaptive dual replay: speed=2^%0d ce_period=%0d tclk_bit=%0d strobe=%0d gap_cap=%0d poll_limit=%0d max_payload=%0d direct_status=%0d",
            sim_speed_log2, ce_period, tclk_bit, strobe, gap_cap,
            poll_limit, max_payload, direct_status);
        // Is the core actually running free, or does it stall? Sample the pc
        // at intervals BEFORE any host traffic, so the answer is not confounded
        // by the replay itself.
        fork begin
            integer k;
            for (k = 0; k < 6; k = k + 1) begin
                repeat (200000) @(posedge clk);
                $display("  t=%0t ucpu_pc=%03x changes=%0d | csnd_pc=%03x changes=%0d",
                         $time, ucpu_program_address_seen, ucpu_pc_changes,
                         csnd_rom_address, csnd_pc_changes);
            end
        end join_none
        done = 0;
        ucpu_mame_status_seen = 0;
        csnd_mame_status_seen = 0;
        ucpu_write_since_status = 0;
        csnd_write_since_status = 0;
        ucpu_mame_last_status = 8'h00;
        csnd_mame_last_status = 8'h00;
        progress_mark = 0;
        while (!$feof(log) && !done &&
                (max_payload == 0 || payload_ops < max_payload)) begin
            rc = $fscanf(log, "%d,%d,%c,%c,%d,%x,%x\n",
                         t_tick, t_frame, t_domain, t_dir,
                         t_a0, t_data, t_pc);
            target_csnd = t_domain == "C";
            if (rc != 7) done = 1;
            else if (t_dir == "R" && t_a0[0]) begin
                // MAME's exact poll count is a timing observation, not a
                // functional oracle. Retain only its final status value to
                // identify whether a following DATA read was OBF-qualified.
                if (target_csnd) begin
                    csnd_mame_status_seen = 1;
                    csnd_mame_last_status = t_data[7:0];
                    csnd_write_since_status = 0;
                end else begin
                    ucpu_mame_status_seen = 1;
                    ucpu_mame_last_status = t_data[7:0];
                    ucpu_write_since_status = 0;
                end
                skipped_status = skipped_status + 1;
            end else if (t_dir == "W") begin
                wait_action_gap(t_tick);
                wait_ibf_clear(target_csnd);
                host_write(target_csnd, t_a0[0], t_data[7:0]);
                n_w = n_w + 1;
                if (target_csnd)
                    csnd_writes = csnd_writes + 1;
                else
                    ucpu_writes = ucpu_writes + 1;
                if (target_csnd && csnd_mame_status_seen)
                    csnd_write_since_status = 1;
                if (!target_csnd && ucpu_mame_status_seen)
                    ucpu_write_since_status = 1;
                payload_ops = payload_ops + 1;
            end else if (
                    (target_csnd && csnd_mame_status_seen &&
                        csnd_mame_last_status[0]) ||
                    (!target_csnd && ucpu_mame_status_seen &&
                        ucpu_mame_last_status[0])) begin
                // Fresh MAME payload: follow the RTL's handshake adaptively,
                // then compare the payload byte. Every fresh MAME read is
                // preceded by status 0x09: the prior host input has been
                // consumed (IBF clear) and output is ready (OBF set). The one
                // CSND startup read instead consumes an OBF that was observed
                // immediately before its next write; in that case MAME does
                // not wait for the new IBF to clear before reading the old
                // pending output.
                wait_action_gap(t_tick);
                if ((target_csnd && !csnd_write_since_status) ||
                        (!target_csnd && !ucpu_write_since_status))
                    wait_ibf_clear(target_csnd);
                wait_obf_set(target_csnd);
                host_read(target_csnd, 1'b0, got);
                fresh_reads = fresh_reads + 1;
                if (target_csnd)
                    csnd_fresh_reads = csnd_fresh_reads + 1;
                else
                    ucpu_fresh_reads = ucpu_fresh_reads + 1;
                checked = checked + 1;
                if (got !== t_data[7:0]) begin
                    if (mismatches < 20)
                        $display(
                            "%s PAYLOAD MISMATCH #%0d frame=%0d pc=%04x RTL=%02x MAME=%02x writes=%0d fresh_reads=%0d",
                            target_csnd ? "CSND" : "UCPU", mismatches,
                            t_frame, t_pc, got, t_data[7:0], n_w,
                            fresh_reads);
                    mismatches = mismatches + 1;
                end
                payload_ops = payload_ops + 1;
                if (target_csnd)
                    csnd_mame_status_seen = 0;
                else
                    ucpu_mame_status_seen = 0;
                if (target_csnd)
                    csnd_write_since_status = 0;
                else
                    ucpu_write_since_status = 0;
            end else begin
                // Reading DBBOUT with OBF clear only returns its retained
                // latch. It is not a new MCU payload and its exact timing is
                // not portable between MAME and RTL.
                skipped_stale_data = skipped_stale_data + 1;
                if (target_csnd)
                    csnd_mame_status_seen = 0;
                else
                    ucpu_mame_status_seen = 0;
                if (target_csnd)
                    csnd_write_since_status = 0;
                else
                    ucpu_write_since_status = 0;
            end

            if (payload_ops >= progress_mark + 5000) begin
                progress_mark = payload_ops;
                $display(
                    "adaptive ucpu replay: %0d payload ops (%0d writes, %0d fresh reads), %0d mismatches",
                    payload_ops, n_w, fresh_reads, mismatches);
                $fflush();
            end
        end
        $fclose(log);

        $display(
            "adaptive ucpu replay done: %0d payload ops, %0d writes, %0d fresh reads checked, %0d mismatches",
            payload_ops, n_w, checked, mismatches);
        $display(
            "  UCPU writes=%0d fresh_reads=%0d | CSND writes=%0d fresh_reads=%0d",
            ucpu_writes, ucpu_fresh_reads, csnd_writes, csnd_fresh_reads);
        $display(
            "  ignored timing-only observations: %0d MAME status polls, %0d stale DATA latch reads; RTL adaptive polls=%0d",
            skipped_status, skipped_stale_data, adaptive_status_polls);
        $display("LIVENESS: ucpu pc changed %0d, csnd pc changed %0d, csnd_p1 changed %0d",
                 ucpu_pc_changes, csnd_pc_changes, csnd_p1_changes);
        $display("  ucpu_p1_out=%02x  csnd_p1_out=%02x  (link: ucpu.t1<=csnd_p1[1], csnd.t1<=ucpu_p1[1])",
                  ucpu_p1_out_seen, csnd_p1_out_seen);
        if (mismatches != 0)
            $fatal(1, "ucpu host responses diverge from MAME");
        $display("PASS tb_ucpu_host_replay");
        $finish;
    end
endmodule
