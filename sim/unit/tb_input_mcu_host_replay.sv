`timescale 1ns/1ps

// Adaptive host-port replay for the two input-control UPI-41 MCUs.
//
// The MAME capture supplies ordered host writes and fresh response bytes. Its
// exact status-poll count is intentionally not replayed: before writes this
// bench waits for the RTL's IBF to clear, and before fresh reads it waits for
// the RTL's OBF to set. DATA reads not qualified by a preceding MAME status
// with OBF set are retained-latch reads and are skipped.
module tb_input_mcu_host_replay;
    logic clk = 0;
    always #5.208 clk = ~clk;          // 96 MHz

    logic [4:0] divider = 0;
    logic ce_6m;
    integer sim_speed_log2 = 0;
    integer ce_period = 16;
    always_ff @(posedge clk) divider <= divider + 5'd1;
    assign ce_6m = ((divider & (ce_period - 1)) == (ce_period - 1));

    logic reset = 1;
    logic enable_bad_dump_patch = 1;

    logic [7:0] cctl_rom [0:1023];
    logic [7:0] ccpu_rom [0:1023];
    logic [7:0] cctl_raw_data = 0, ccpu_raw_data = 0;
    logic [7:0] cctl_program_data, ccpu_program_data;
    logic [10:0] cctl_program_address, ccpu_program_address;

    logic cctl_a0 = 0, cctl_cs_n = 1, cctl_rd_n = 1, cctl_wr_n = 1;
    logic [7:0] cctl_host_data_in = 0, cctl_host_data_out;
    logic ccpu_a0 = 0, ccpu_cs_n = 1, ccpu_rd_n = 1, ccpu_wr_n = 1;
    logic [7:0] ccpu_host_data_in = 0, ccpu_host_data_out;
    logic cctl_ibf_state, cctl_obf_state;
    logic ccpu_ibf_state, ccpu_obf_state;

    always_ff @(posedge clk) begin
        cctl_raw_data <= cctl_rom[cctl_program_address[9:0]];
        ccpu_raw_data <= ccpu_rom[ccpu_program_address[9:0]];
    end

    gladiator_mcu_rom_adapter cctl_adapter (
        .enable_patch(enable_bad_dump_patch),
        .address(cctl_program_address),
        .raw_data(cctl_raw_data),
        .program_data(cctl_program_data),
        .patch_visible()
    );

    gladiator_mcu_rom_adapter ccpu_adapter (
        .enable_patch(enable_bad_dump_patch),
        .address(ccpu_program_address),
        .raw_data(ccpu_raw_data),
        .program_data(ccpu_program_data),
        .patch_visible()
    );

    gladiator_upi41_device cctl (
        .clk(clk), .ce_6m(ce_6m), .reset(reset),
        .host_a0(cctl_a0), .host_cs_n(cctl_cs_n),
        .host_rd_n(cctl_rd_n), .host_wr_n(cctl_wr_n),
        .host_data_in(cctl_host_data_in),
        .host_data_out(cctl_host_data_out),
        .p1_pin_in(8'hff), .p2_pin_in(8'hff),
        .p1_latch_out(), .p2_latch_out(),
        .t0(1'b1), .t1(1'b1),
        .program_address(cctl_program_address),
        .program_data(cctl_program_data),
        .debug_dmem_address(), .debug_dmem_write()
    );

    gladiator_upi41_device ccpu (
        .clk(clk), .ce_6m(ce_6m), .reset(reset),
        .host_a0(ccpu_a0), .host_cs_n(ccpu_cs_n),
        .host_rd_n(ccpu_rd_n), .host_wr_n(ccpu_wr_n),
        .host_data_in(ccpu_host_data_in),
        .host_data_out(ccpu_host_data_out),
        .p1_pin_in(8'hff), .p2_pin_in(8'hff),
        .p1_latch_out(), .p2_latch_out(),
        .t0(1'b1), .t1(1'b1),
        .program_address(ccpu_program_address),
        .program_data(ccpu_program_data),
        .debug_dmem_address(), .debug_dmem_write()
    );

    assign cctl_ibf_state = cctl.core.bus_ibf_s;
    assign cctl_obf_state = cctl.core.bus_obf_s;
    assign ccpu_ibf_state = ccpu.core.bus_ibf_s;
    assign ccpu_obf_state = ccpu.core.bus_obf_s;

    integer log, rc, rom_file, seek_result, bytes;
    integer t_tick, t_frame, t_a0, t_data, t_pc;
    logic [7:0] t_domain, t_dir;
    logic [8*256-1:0] csv_header;
    integer writes = 0, fresh_reads = 0, checked = 0, mismatches = 0;
    integer cctl_writes = 0, ccpu_writes = 0;
    integer cctl_fresh_reads = 0, ccpu_fresh_reads = 0;
    integer skipped_status = 0, skipped_stale_data = 0;
    integer adaptive_status_polls = 0, payload_ops = 0;
    integer prev_action_tick = 0;
    integer gap_cap, max_payload, poll_limit, strobe, direct_status;

    task automatic host_write(
        input logic target_ccpu,
        input logic a0,
        input logic [7:0] d
    );
        begin
            @(negedge clk);
            if (target_ccpu) begin
                ccpu_a0 = a0; ccpu_host_data_in = d;
                ccpu_cs_n = 0; ccpu_wr_n = 0;
            end else begin
                cctl_a0 = a0; cctl_host_data_in = d;
                cctl_cs_n = 0; cctl_wr_n = 0;
            end
            repeat (strobe) @(negedge clk);
            if (target_ccpu) begin
                ccpu_wr_n = 1; ccpu_cs_n = 1;
            end else begin
                cctl_wr_n = 1; cctl_cs_n = 1;
            end
        end
    endtask

    task automatic host_read(
        input logic target_ccpu,
        input logic a0,
        output logic [7:0] d
    );
        begin
            @(negedge clk);
            if (target_ccpu) begin
                ccpu_a0 = a0; ccpu_cs_n = 0; ccpu_rd_n = 0;
            end else begin
                cctl_a0 = a0; cctl_cs_n = 0; cctl_rd_n = 0;
            end
            repeat (strobe) @(negedge clk);
            if (target_ccpu) begin
                d = ccpu_host_data_out;
                ccpu_rd_n = 1; ccpu_cs_n = 1;
            end else begin
                d = cctl_host_data_out;
                cctl_rd_n = 1; cctl_cs_n = 1;
            end
        end
    endtask

    task automatic wait_ibf_clear(input logic target_ccpu);
        logic [7:0] status;
        integer polls;
        begin
            polls = 0;
            if (direct_status) begin
                while ((target_ccpu ? ccpu_ibf_state :
                        cctl_ibf_state) && polls < poll_limit) begin
                    @(negedge clk);
                    polls = polls + 1;
                end
                status = target_ccpu ?
                    {6'h00, ccpu_ibf_state, ccpu_obf_state} :
                    {6'h00, cctl_ibf_state, cctl_obf_state};
            end else begin
                host_read(target_ccpu, 1'b1, status);
                polls = polls + 1;
                while (status[1] && polls < poll_limit) begin
                    host_read(target_ccpu, 1'b1, status);
                    polls = polls + 1;
                end
            end
            adaptive_status_polls = adaptive_status_polls + polls;
            if (status[1])
                $fatal(
                    1,
                    "adaptive %s host timed out waiting for IBF clear: writes=%0d fresh_reads=%0d frame=%0d pc=%04x next a0=%0d data=%02x status=%02x",
                    target_ccpu ? "CCPU" : "CCTL", writes, fresh_reads,
                    t_frame, t_pc, t_a0, t_data, status);
        end
    endtask

    task automatic wait_obf_set(input logic target_ccpu);
        logic [7:0] status;
        integer polls;
        begin
            polls = 0;
            if (direct_status) begin
                while (!(target_ccpu ? ccpu_obf_state :
                        cctl_obf_state) && polls < poll_limit) begin
                    @(negedge clk);
                    polls = polls + 1;
                end
                status = target_ccpu ?
                    {6'h00, ccpu_ibf_state, ccpu_obf_state} :
                    {6'h00, cctl_ibf_state, cctl_obf_state};
            end else begin
                host_read(target_ccpu, 1'b1, status);
                polls = polls + 1;
                while (!status[0] && polls < poll_limit) begin
                    host_read(target_ccpu, 1'b1, status);
                    polls = polls + 1;
                end
            end
            adaptive_status_polls = adaptive_status_polls + polls;
            if (!status[0])
                $fatal(
                    1,
                    "adaptive %s host timed out waiting for OBF set: writes=%0d fresh_reads=%0d frame=%0d pc=%04x expected=%02x status=%02x",
                    target_ccpu ? "CCPU" : "CCTL", writes, fresh_reads,
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

    logic [10:0] cctl_pc_seen, ccpu_pc_seen;
    integer cctl_pc_changes = 0, ccpu_pc_changes = 0;
    always_ff @(posedge clk) begin
        cctl_pc_seen <= cctl_program_address;
        ccpu_pc_seen <= ccpu_program_address;
        if (cctl_program_address !== cctl_pc_seen)
            cctl_pc_changes <= cctl_pc_changes + 1;
        if (ccpu_program_address !== ccpu_pc_seen)
            ccpu_pc_changes <= ccpu_pc_changes + 1;
    end

    logic [7:0] got;
    integer done;
    integer cctl_mame_status_seen, ccpu_mame_status_seen;
    integer cctl_write_since_status, ccpu_write_since_status;
    integer progress_mark;
    logic [7:0] cctl_mame_last_status, ccpu_mame_last_status;
    logic target_ccpu;

    initial begin
        if (!$value$plusargs("SIM_SPEED_LOG2=%d", sim_speed_log2))
            sim_speed_log2 = 0;
        if (sim_speed_log2 < 0 || sim_speed_log2 > 4)
            $fatal(1, "SIM_SPEED_LOG2 must be in the range 0..4");
        ce_period = 16 >> sim_speed_log2;

        rom_file = $fopen("sim/out/gladiatr.rom", "rb");
        if (!rom_file)
            $fatal(1, "missing sim/out/gladiatr.rom");
        seek_result = $fseek(rom_file, 20'h6c040, 0);
        bytes = $fread(cctl_rom, rom_file);
        if (seek_result != 0 || bytes != 1024)
            $fatal(1, "cannot load CCTL ROM");
        bytes = $fread(ccpu_rom, rom_file);
        $fclose(rom_file);
        if (bytes != 1024)
            $fatal(1, "cannot load CCPU ROM");

        // Positive mutation control: the dumped input-MCU ROMs need MAME's
        // address-zero repair (0x22). Disabling it must stop the replay from
        // reaching the known 0x48/0x66 command responses.
        if ($test$plusargs("DISABLE_BAD_DUMP_PATCH")) begin
            enable_bad_dump_patch = 0;
            $display("MUTATION ACTIVE: input-MCU address-zero patch disabled");
        end

        log = $fopen("sim/out/mame-input-mcu-host.csv", "r");
        if (!log)
            $fatal(1, "missing sim/out/mame-input-mcu-host.csv");
        rc = $fgets(csv_header, log);

        repeat (64 >> sim_speed_log2) @(negedge clk);
        reset = 0;
        repeat (2000 >> sim_speed_log2) @(negedge clk);

        if (!$value$plusargs("STROBE=%d", strobe))
            strobe = 16 >> sim_speed_log2;
        if (!$value$plusargs("GAPCAP=%d", gap_cap))
            gap_cap = 4000;
        if (!$value$plusargs("POLL_LIMIT=%d", poll_limit))
            poll_limit = 200000;
        if (!$value$plusargs("MAXPAYLOAD=%d", max_payload))
            max_payload = 0;
        direct_status = $test$plusargs("DIRECT_STATUS");
        $display(
            "adaptive input-MCU replay: speed=2^%0d ce_period=%0d strobe=%0d gap_cap=%0d poll_limit=%0d max_payload=%0d direct_status=%0d",
            sim_speed_log2, ce_period, strobe, gap_cap, poll_limit,
            max_payload, direct_status);

        done = 0;
        cctl_mame_status_seen = 0;
        ccpu_mame_status_seen = 0;
        cctl_write_since_status = 0;
        ccpu_write_since_status = 0;
        cctl_mame_last_status = 0;
        ccpu_mame_last_status = 0;
        progress_mark = 0;
        while (!$feof(log) && !done &&
                (max_payload == 0 || payload_ops < max_payload)) begin
            rc = $fscanf(log, "%d,%d,%c,%c,%d,%x,%x\n",
                         t_tick, t_frame, t_domain, t_dir,
                         t_a0, t_data, t_pc);
            target_ccpu = t_domain == "P";
            if (rc != 7)
                done = 1;
            else if (t_dir == "R" && t_a0[0]) begin
                if (target_ccpu) begin
                    ccpu_mame_status_seen = 1;
                    ccpu_mame_last_status = t_data[7:0];
                    ccpu_write_since_status = 0;
                end else begin
                    cctl_mame_status_seen = 1;
                    cctl_mame_last_status = t_data[7:0];
                    cctl_write_since_status = 0;
                end
                skipped_status = skipped_status + 1;
            end else if (t_dir == "W") begin
                wait_action_gap(t_tick);
                wait_ibf_clear(target_ccpu);
                host_write(target_ccpu, t_a0[0], t_data[7:0]);
                writes = writes + 1;
                if (target_ccpu)
                    ccpu_writes = ccpu_writes + 1;
                else
                    cctl_writes = cctl_writes + 1;
                if (target_ccpu && ccpu_mame_status_seen)
                    ccpu_write_since_status = 1;
                if (!target_ccpu && cctl_mame_status_seen)
                    cctl_write_since_status = 1;
                payload_ops = payload_ops + 1;
            end else if (
                    (target_ccpu && ccpu_mame_status_seen &&
                        ccpu_mame_last_status[0]) ||
                    (!target_ccpu && cctl_mame_status_seen &&
                        cctl_mame_last_status[0])) begin
                wait_action_gap(t_tick);
                // These input MCUs pipeline commands: MAME deliberately reads
                // the previous OBF response from status 0x0b while the next
                // input byte is still pending in IBF. Requiring IBF clear here
                // would turn that legal overlap into a false timeout.
                wait_obf_set(target_ccpu);
                host_read(target_ccpu, 1'b0, got);
                fresh_reads = fresh_reads + 1;
                if (target_ccpu)
                    ccpu_fresh_reads = ccpu_fresh_reads + 1;
                else
                    cctl_fresh_reads = cctl_fresh_reads + 1;
                checked = checked + 1;
                if (got !== t_data[7:0]) begin
                    if (mismatches < 20)
                        $display(
                            "%s PAYLOAD MISMATCH #%0d frame=%0d pc=%04x RTL=%02x MAME=%02x writes=%0d fresh_reads=%0d",
                            target_ccpu ? "CCPU" : "CCTL", mismatches,
                            t_frame, t_pc, got, t_data[7:0], writes,
                            fresh_reads);
                    mismatches = mismatches + 1;
                end
                payload_ops = payload_ops + 1;
                if (target_ccpu) begin
                    ccpu_mame_status_seen = 0;
                    ccpu_write_since_status = 0;
                end else begin
                    cctl_mame_status_seen = 0;
                    cctl_write_since_status = 0;
                end
            end else begin
                skipped_stale_data = skipped_stale_data + 1;
                if (target_ccpu) begin
                    ccpu_mame_status_seen = 0;
                    ccpu_write_since_status = 0;
                end else begin
                    cctl_mame_status_seen = 0;
                    cctl_write_since_status = 0;
                end
            end

            if (payload_ops >= progress_mark + 5000) begin
                progress_mark = payload_ops;
                $display(
                    "adaptive input-MCU replay: %0d payload ops (%0d writes, %0d fresh reads), %0d mismatches",
                    payload_ops, writes, fresh_reads, mismatches);
                $fflush();
            end
        end
        $fclose(log);

        $display(
            "adaptive input-MCU replay done: %0d payload ops, %0d writes, %0d fresh reads checked, %0d mismatches",
            payload_ops, writes, checked, mismatches);
        $display(
            "  CCTL writes=%0d fresh_reads=%0d | CCPU writes=%0d fresh_reads=%0d",
            cctl_writes, cctl_fresh_reads, ccpu_writes, ccpu_fresh_reads);
        $display(
            "  ignored timing-only observations: %0d MAME status polls, %0d stale DATA latch reads; RTL adaptive polls=%0d",
            skipped_status, skipped_stale_data, adaptive_status_polls);
        $display("LIVENESS: cctl pc changed %0d, ccpu pc changed %0d",
                 cctl_pc_changes, ccpu_pc_changes);
        if (mismatches != 0)
            $fatal(1, "input-MCU host responses diverge from MAME");
        $display("PASS tb_input_mcu_host_replay");
        $finish;
    end
endmodule
