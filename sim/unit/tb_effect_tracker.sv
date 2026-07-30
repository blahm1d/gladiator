`timescale 1ns/1ps

module tb_effect_tracker;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic sound_command_write = 1'b0;
    logic [7:0] sound_command_data = 8'd0;
    logic ym_write = 1'b0;
    logic ym_address = 1'b0;
    logic [7:0] ym_data = 8'd0;
    logic [2:0] effect_channel_active;
    logic effect_active;

    gladiator_effect_tracker dut (
        .clk                  (clk),
        .reset                (reset),
        .sound_command_write  (sound_command_write),
        .sound_command_data   (sound_command_data),
        .ym_write             (ym_write),
        .ym_address           (ym_address),
        .ym_data              (ym_data),
        .effect_channel_active(effect_channel_active),
        .effect_active        (effect_active)
    );

    always #5 clk = ~clk;

    task automatic submit_command(input logic [7:0] value);
        begin
            @(negedge clk);
            sound_command_data = value;
            sound_command_write = 1'b1;
            @(posedge clk);
            #1 sound_command_write = 1'b0;
        end
    endtask

    task automatic ym_bus_write(
        input logic address,
        input logic [7:0] value
    );
        begin
            @(negedge clk);
            ym_address = address;
            ym_data = value;
            ym_write = 1'b1;
            @(posedge clk);
            #1 ym_write = 1'b0;
        end
    endtask

    task automatic ym_key(input logic [7:0] value);
        begin
            ym_bus_write(1'b0, 8'h28);
            ym_bus_write(1'b1, value);
        end
    endtask

    task automatic expect_state(
        input logic [2:0] channels,
        input string label
    );
        begin
            #1;
            if ((effect_channel_active !== channels) ||
                    (effect_active !== (|channels))) begin
                $error("%s: channels=%b active=%b expected=%b/%b",
                       label, effect_channel_active, effect_active,
                       channels, |channels);
                $fatal(1);
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        #1 reset = 1'b0;
        expect_state(3'b000, "reset");

        // Normal music/control and ADPCM/speech commands must not claim an
        // FM channel even if an unrelated key-on follows.
        submit_command(8'h0f);
        ym_key(8'hf2);
        expect_state(3'b000, "music is not an effect");

        submit_command(8'h72);
        ym_key(8'hf0);
        expect_state(3'b000, "speech is not an effect");

        // Observed gameplay commands: 0x2e keys FM channel 1 and 0x36 keys
        // channel 2. Each remains active until its own key-off.
        submit_command(8'h2e);
        ym_key(8'hf1);
        expect_state(3'b010, "channel 1 effect key-on");

        submit_command(8'h36);
        ym_key(8'hf2);
        expect_state(3'b110, "concurrent channel 2 effect key-on");

        ym_key(8'h01);
        expect_state(3'b100, "channel 1 effect key-off");

        ym_key(8'h02);
        expect_state(3'b000, "channel 2 effect key-off");

        // A later non-effect command cancels an effect awaiting key-on.
        submit_command(8'h40);
        submit_command(8'h68);
        ym_key(8'hf1);
        expect_state(3'b000, "speech cancels pending effect classification");

        $display("PASS tb_effect_tracker");
        $finish;
    end
endmodule
