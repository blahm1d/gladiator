// MAP-SUB-001
module gladiator_sound_bus (
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

    output logic [13:0] rom_address,
    input  logic [7:0]  rom_data,

    output logic        interrupt_ack,

    output logic        ym_cs_n,
    output logic        ym_address,
    output logic        ym_wr_n,
    output logic [7:0]  ym_data_out,
    input  logic [7:0]  ym_data_in,

    output logic        csnd_cs_n,
    output logic        csnd_a0,
    output logic        csnd_rd_n,
    output logic        csnd_wr_n,
    output logic [7:0]  csnd_data_out,
    input  logic [7:0]  csnd_data_in,

    output logic        cctl_cs_n,
    output logic        cctl_a0,
    output logic        cctl_rd_n,
    output logic        cctl_wr_n,
    output logic [7:0]  cctl_data_out,
    input  logic [7:0]  cctl_data_in,

    output logic        ccpu_cs_n,
    output logic        ccpu_a0,
    output logic        ccpu_rd_n,
    output logic        ccpu_wr_n,
    output logic [7:0]  ccpu_data_out,
    input  logic [7:0]  ccpu_data_in,

    output logic        command_write,
    output logic [7:0]  command_data,
    output logic        sound_command_write,
    output logic [7:0]  sound_command_data,
    output logic [7:0]  filter_latch,

    output logic        trace_mem_read,
    output logic        trace_mem_write,
    output logic        trace_io_read,
    output logic        trace_io_write
);

    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] work_ram [0:10'h3ff];
    logic [7:0] ram_q;

    logic mem_read_level, mem_write_level, io_read_level, io_write_level;
    logic mem_read_d, mem_write_d, io_read_d, io_write_d;
    logic mem_read_pulse, mem_write_pulse, io_read_pulse, io_write_pulse;
    logic [7:0] port;

    assign port = cpu_address[7:0];
    assign rom_address = cpu_address[13:0];

    assign mem_read_level  = !cpu_mreq_n && !cpu_rd_n;
    assign mem_write_level = !cpu_mreq_n && !cpu_wr_n;
    assign io_read_level   = !cpu_iorq_n && !cpu_rd_n && cpu_m1_n;
    assign io_write_level  = !cpu_iorq_n && !cpu_wr_n && cpu_m1_n;

    assign mem_read_pulse  = mem_read_level  && !mem_read_d;
    assign mem_write_pulse = mem_write_level && !mem_write_d;
    assign io_read_pulse   = io_read_level   && !io_read_d;
    assign io_write_pulse  = io_write_level  && !io_write_d;
    assign interrupt_ack   = !cpu_m1_n && !cpu_iorq_n;

    assign trace_mem_read  = mem_read_pulse;
    assign trace_mem_write = mem_write_pulse;
    assign trace_io_read   = io_read_pulse;
    assign trace_io_write  = io_write_pulse;

    assign ym_cs_n       = !((io_read_level || io_write_level) &&
                             (port[7:1] == 7'h00));
    assign ym_address    = port[0];
    assign ym_wr_n       = !(io_write_level && !ym_cs_n);
    assign ym_data_out   = cpu_data_out;

    assign csnd_cs_n     = !((io_read_level || io_write_level) &&
                             (port[7:1] == 7'h10));
    assign csnd_a0       = port[0];
    assign csnd_rd_n     = !(io_read_level && !csnd_cs_n);
    assign csnd_wr_n     = !(io_write_level && !csnd_cs_n);
    assign csnd_data_out = cpu_data_out;

    assign cctl_cs_n     = !((io_read_level || io_write_level) &&
                             (port[7:1] == 7'h30));
    assign cctl_a0       = port[0];
    assign cctl_rd_n     = !(io_read_level && !cctl_cs_n);
    assign cctl_wr_n     = !(io_write_level && !cctl_cs_n);
    assign cctl_data_out = cpu_data_out;

    assign ccpu_cs_n     = !((io_read_level || io_write_level) &&
                             (port[7:1] == 7'h40));
    assign ccpu_a0       = port[0];
    assign ccpu_rd_n     = !(io_read_level && !ccpu_cs_n);
    assign ccpu_wr_n     = !(io_write_level && !ccpu_cs_n);
    assign ccpu_data_out = cpu_data_out;

    always_comb begin
        cpu_data_in = 8'hff;
        if (mem_read_level) begin
            if (cpu_address < 16'h4000)
                cpu_data_in = rom_data;
            else if (cpu_address >= 16'h8000 && cpu_address <= 16'h83ff)
                cpu_data_in = ram_q;
        end else if (io_read_level) begin
            if (!ym_cs_n)
                cpu_data_in = ym_data_in;
            else if (!csnd_cs_n)
                cpu_data_in = csnd_data_in;
            else if (!cctl_cs_n)
                cpu_data_in = cctl_data_in;
            else if (!ccpu_cs_n)
                cpu_data_in = ccpu_data_in;
        end
    end

    always_ff @(posedge clk) begin
        mem_read_d  <= mem_read_level;
        mem_write_d <= mem_write_level;
        io_read_d   <= io_read_level;
        io_write_d  <= io_write_level;
        ram_q       <= work_ram[cpu_address[9:0]];
        command_write <= 1'b0;
        sound_command_write <= 1'b0;

        if (reset) begin
            mem_read_d    <= 1'b0;
            mem_write_d   <= 1'b0;
            io_read_d     <= 1'b0;
            io_write_d    <= 1'b0;
            filter_latch  <= 8'd0;
            command_data  <= 8'd0;
            sound_command_data <= 8'd0;
        end else begin
            if (mem_write_pulse && cpu_address >= 16'h8000 &&
                    cpu_address <= 16'h83ff)
                work_ram[cpu_address[9:0]] <= cpu_data_out;

            // $8002 is the decoded command byte written by the sound-ROM
            // dispatcher. It separates FM effects (0x10..0x5f) from the
            // ADPCM/speech range (0x60..0x7f).
            if (mem_write_pulse && cpu_address == 16'h8002) begin
                sound_command_data  <= cpu_data_out;
                sound_command_write <= 1'b1;
            end

            if (io_write_pulse && port >= 8'ha0 && port <= 8'ha7)
                filter_latch[port[2:0]] <= cpu_data_out[0];

            if (io_write_pulse && port == 8'he0) begin
                command_data  <= cpu_data_out;
                command_write <= 1'b1;
            end
        end
    end

endmodule
