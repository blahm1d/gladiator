// CLK-MCU-001, CLK-TCLK-001, MCU-LINK-001, IO-CCTL-001
module gladiator_mcu_cluster (
    input  logic        clk,
    input  logic        ce_6m,
    input  logic        reset,
    input  logic        peripheral_reset,
    input  logic        tclk,
    input  logic        enable_bad_dump_patch,

    input  logic [7:0]  dsw1,
    input  logic [7:0]  dsw2,
    input  logic [7:0]  player1_active_low,
    input  logic [7:0]  player2_active_low,
    input  logic        player1_button3_active_low,
    input  logic        player2_button3_active_low,
    input  logic [3:0]  coins_active_low,

    input  logic        ucpu_a0,
    input  logic        ucpu_cs_n,
    input  logic        ucpu_rd_n,
    input  logic        ucpu_wr_n,
    input  logic [7:0]  ucpu_host_data_in,
    output logic [7:0]  ucpu_host_data_out,

    input  logic        csnd_a0,
    input  logic        csnd_cs_n,
    input  logic        csnd_rd_n,
    input  logic        csnd_wr_n,
    input  logic [7:0]  csnd_host_data_in,
    output logic [7:0]  csnd_host_data_out,

    input  logic        cctl_a0,
    input  logic        cctl_cs_n,
    input  logic        cctl_rd_n,
    input  logic        cctl_wr_n,
    input  logic [7:0]  cctl_host_data_in,
    output logic [7:0]  cctl_host_data_out,

    input  logic        ccpu_a0,
    input  logic        ccpu_cs_n,
    input  logic        ccpu_rd_n,
    input  logic        ccpu_wr_n,
    input  logic [7:0]  ccpu_host_data_in,
    output logic [7:0]  ccpu_host_data_out,

    output logic [9:0]  cctl_rom_address,
    input  logic [7:0]  cctl_raw_rom_data,
    output logic [9:0]  ccpu_rom_address,
    input  logic [7:0]  ccpu_raw_rom_data,
    output logic [9:0]  ucpu_rom_address,
    input  logic [7:0]  ucpu_raw_rom_data,
    output logic [10:0] csnd_rom_address,
    input  logic [7:0]  csnd_raw_rom_data,

    output logic [7:0]  cctl_p1_out,
    output logic [7:0]  cctl_p2_out,
    output logic [7:0]  ccpu_p1_out,
    output logic [7:0]  ccpu_p2_out,
    output logic [7:0]  ucpu_p1_out,
    output logic [7:0]  csnd_p1_out,
    output logic [1:0]  coin_counter_active_low,
    output logic [1:0]  bad_dump_patch_visible
);

    function automatic logic [7:0] reverse8(input logic [7:0] value);
        integer bit_index;
        begin
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                reverse8[bit_index] = value[7-bit_index];
        end
    endfunction

    logic [7:0] cctl_external_p1;
    logic [7:0] cctl_external_p2;
    logic p1_button1_d, p2_button1_d;

    logic [10:0] cctl_program_address;
    logic [10:0] ccpu_program_address;
    logic [10:0] ucpu_program_address;
    logic [7:0] cctl_program_data;
    logic [7:0] ccpu_program_data;

    logic [7:0] unused_p2;
    logic [7:0] ucpu_p2_out;
    logic [7:0] csnd_p2_out;

    assign cctl_rom_address = cctl_program_address[9:0];
    assign ccpu_rom_address = ccpu_program_address[9:0];
    assign ucpu_rom_address = ucpu_program_address[9:0];
    assign coin_counter_active_low = ccpu_p2_out[7:6];

    gladiator_mcu_rom_adapter cctl_adapter (
        .enable_patch (enable_bad_dump_patch),
        .address      (cctl_program_address),
        .raw_data     (cctl_raw_rom_data),
        .program_data (cctl_program_data),
        .patch_visible(bad_dump_patch_visible[0])
    );

    gladiator_mcu_rom_adapter ccpu_adapter (
        .enable_patch (enable_bad_dump_patch),
        .address      (ccpu_program_address),
        .raw_data     (ccpu_raw_rom_data),
        .program_data (ccpu_program_data),
        .patch_visible(bad_dump_patch_visible[1])
    );

    // External button latch behavior currently inferred from MAME callbacks.
    always_ff @(posedge clk) begin
        if (reset) begin
            cctl_external_p1 <= 8'hff;
            cctl_external_p2 <= 8'hff;
            p1_button1_d <= 1'b1;
            p2_button1_d <= 1'b1;
        end else begin
            p1_button1_d <= player1_active_low[4];
            p2_button1_d <= player2_active_low[4];

            cctl_external_p1[0] <= !player1_active_low[5];
            cctl_external_p2[0] <= !player2_active_low[5];

            if (p1_button1_d && !player1_active_low[4])
                cctl_external_p1[1] <= cctl_external_p1[0];
            if (p2_button1_d && !player2_active_low[4])
                cctl_external_p2[1] <= cctl_external_p2[0];
        end
    end

    gladiator_upi41_device cctl (
        .clk            (clk),
        .ce_6m          (ce_6m),
        .reset          (reset || peripheral_reset),
        .host_a0        (cctl_a0),
        .host_cs_n      (cctl_cs_n),
        .host_rd_n      (cctl_rd_n),
        .host_wr_n      (cctl_wr_n),
        .host_data_in   (cctl_host_data_in),
        .host_data_out  (cctl_host_data_out),
        .p1_pin_in      (cctl_external_p1 &
                         {player2_button3_active_low,
                          player1_button3_active_low, 6'h3f}),
        .p2_pin_in      (cctl_external_p2),
        .p1_latch_out   (cctl_p1_out),
        .p2_latch_out   (cctl_p2_out),
        .t0             (coins_active_low[3]),
        .t1             (coins_active_low[2]),
        .program_address(cctl_program_address),
        .program_data   (cctl_program_data),
        .debug_dmem_address(),
        .debug_dmem_write()
    );

    gladiator_upi41_device ccpu (
        .clk            (clk),
        .ce_6m          (ce_6m),
        .reset          (reset || peripheral_reset),
        .host_a0        (ccpu_a0),
        .host_cs_n      (ccpu_cs_n),
        .host_rd_n      (ccpu_rd_n),
        .host_wr_n      (ccpu_wr_n),
        .host_data_in   (ccpu_host_data_in),
        .host_data_out  (ccpu_host_data_out),
        .p1_pin_in      (player1_active_low),
        .p2_pin_in      (player2_active_low),
        .p1_latch_out   (ccpu_p1_out),
        .p2_latch_out   (ccpu_p2_out),
        .t0             (coins_active_low[1]),
        .t1             (coins_active_low[0]),
        .program_address(ccpu_program_address),
        .program_data   (ccpu_program_data),
        .debug_dmem_address(),
        .debug_dmem_write()
    );

    gladiator_upi41_device ucpu (
        .clk            (clk),
        .ce_6m          (ce_6m),
        .reset          (reset),
        .host_a0        (ucpu_a0),
        .host_cs_n      (ucpu_cs_n),
        .host_rd_n      (ucpu_rd_n),
        .host_wr_n      (ucpu_wr_n),
        .host_data_in   (ucpu_host_data_in),
        .host_data_out  (ucpu_host_data_out),
        .p1_pin_in      ({7'h7f, csnd_p1_out[0]}),
        .p2_pin_in      (reverse8(dsw1)),
        .p1_latch_out   (ucpu_p1_out),
        .p2_latch_out   (ucpu_p2_out),
        .t0             (tclk),
        .t1             (csnd_p1_out[1]),
        .program_address(ucpu_program_address),
        .program_data   (ucpu_raw_rom_data),
        .debug_dmem_address(),
        .debug_dmem_write()
    );

    gladiator_upi41_device csnd (
        .clk            (clk),
        .ce_6m          (ce_6m),
        .reset          (reset),
        .host_a0        (csnd_a0),
        .host_cs_n      (csnd_cs_n),
        .host_rd_n      (csnd_rd_n),
        .host_wr_n      (csnd_wr_n),
        .host_data_in   (csnd_host_data_in),
        .host_data_out  (csnd_host_data_out),
        .p1_pin_in      ({7'h7f, ucpu_p1_out[0]}),
        .p2_pin_in      ({dsw2[2], dsw2[3], dsw2[4], dsw2[5],
                          dsw2[6], dsw2[7], dsw2[1], dsw2[0]}),
        .p1_latch_out   (csnd_p1_out),
        .p2_latch_out   (csnd_p2_out),
        .t0             (tclk),
        .t1             (ucpu_p1_out[1]),
        .program_address(csnd_rom_address),
        .program_data   (csnd_raw_rom_data),
        .debug_dmem_address(),
        .debug_dmem_write()
    );

endmodule
