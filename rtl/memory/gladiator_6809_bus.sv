// MAP-6809-001, AUD-MSM-001
module gladiator_6809_bus (
    input  logic        clk,
    input  logic        reset,
    input  logic [15:0] cpu_address,
    input  logic [7:0]  cpu_data_out,
    output logic [7:0]  cpu_data_in,
    input  logic        cpu_rnw,
    input  logic        cpu_avma,

    output logic [16:0] rom_address,
    input  logic [7:0]  rom_data,

    input  logic        command_write,
    input  logic [7:0]  command_data,
    output logic        nmi_n,

    output logic [3:0]  adpcm_nibble,
    output logic        adpcm_vclk,
    output logic        adpcm_reset,
    output logic        adpcm_bank,
    output logic        adpcm_control_write,

    output logic        trace_read,
    output logic        trace_write
);

    logic [7:0] command_latch;
    logic nmi_pending;
    logic read_level, write_level, read_d, write_d;
    logic read_pulse, write_pulse;

    assign read_level  = cpu_avma && cpu_rnw;
    assign write_level = cpu_avma && !cpu_rnw;
    assign read_pulse  = read_level && !read_d;
    assign write_pulse = write_level && !write_d;
    assign trace_read  = read_pulse;
    assign trace_write = write_pulse;
    assign nmi_n       = !nmi_pending;

    always_comb begin
        if (cpu_address < 16'h8000)
            rom_address = {1'b0, adpcm_bank, cpu_address[13:0]};
        else if (cpu_address < 16'hc000)
            rom_address = 17'h08000 + {adpcm_bank, 14'd0} +
                          (cpu_address - 16'h8000);
        else
            rom_address = 17'h10000 + {adpcm_bank, 14'd0} +
                          (cpu_address - 16'hc000);
    end

    always_comb begin
        cpu_data_in = 8'hff;
        if (read_level) begin
            if (cpu_address >= 16'h2000 && cpu_address <= 16'h2fff)
                cpu_data_in = command_latch;
            else if (cpu_address >= 16'h4000)
                cpu_data_in = rom_data;
        end
    end

    always_ff @(posedge clk) begin
        read_d  <= read_level;
        write_d <= write_level;
        adpcm_control_write <= 1'b0;

        if (reset) begin
            read_d         <= 1'b0;
            write_d        <= 1'b0;
            command_latch  <= 8'd0;
            nmi_pending    <= 1'b0;
            adpcm_nibble   <= 4'd0;
            adpcm_vclk     <= 1'b0;
            adpcm_reset    <= 1'b1;
            adpcm_bank     <= 1'b0;
        end else begin
            if (command_write) begin
                command_latch <= command_data;
                nmi_pending   <= 1'b1;
            end

            if (read_pulse && cpu_address >= 16'h2000 &&
                    cpu_address <= 16'h2fff)
                nmi_pending <= 1'b0;

            if (write_pulse && cpu_address >= 16'h1000 &&
                    cpu_address <= 16'h1fff) begin
                adpcm_nibble <= cpu_data_out[3:0];
                adpcm_vclk   <= cpu_data_out[4];
                adpcm_reset  <= cpu_data_out[5];
                adpcm_bank   <= cpu_data_out[6];
                adpcm_control_write <= 1'b1;
            end
        end
    end

endmodule

