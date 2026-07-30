// AUD-FX-001
// The sound ROM classifies 0x10..0x5f as FM-effect commands and 0x60..0x7f
// as ADPCM/speech commands. Track the FM channel claimed by each effect from
// the YM2203 register-0x28 key-on/key-off stream so mixer gain can change only
// while an effect voice is active.
module gladiator_effect_tracker (
    input  logic       clk,
    input  logic       reset,
    input  logic       sound_command_write,
    input  logic [7:0] sound_command_data,
    input  logic       ym_write,
    input  logic       ym_address,
    input  logic [7:0] ym_data,
    output logic [2:0] effect_channel_active,
    output logic       effect_active
);

    logic [7:0] ym_register;
    logic       effect_pending;

    assign effect_active = |effect_channel_active;

    always_ff @(posedge clk) begin
        if (reset) begin
            ym_register          <= 8'd0;
            effect_pending       <= 1'b0;
            effect_channel_active <= 3'b000;
        end else begin
            if (sound_command_write)
                effect_pending <= (sound_command_data >= 8'h10) &&
                                  (sound_command_data < 8'h60);

            if (ym_write) begin
                if (!ym_address) begin
                    ym_register <= ym_data;
                end else if ((ym_register == 8'h28) &&
                             (ym_data[1:0] != 2'b11)) begin
                    if (|ym_data[7:4]) begin
                        effect_channel_active[ym_data[1:0]] <=
                            effect_pending;
                        effect_pending <= 1'b0;
                    end else begin
                        effect_channel_active[ym_data[1:0]] <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
