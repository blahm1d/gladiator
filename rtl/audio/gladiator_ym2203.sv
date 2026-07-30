// AUD-YM-001
// JT03 integration exposing the YM2203's PSG port-A output, which controls
// reset to the two input MCUs on the Gladiator board.
module gladiator_ym2203 (
    input  logic               clk,
    input  logic               ce_1m5,
    input  logic               reset,
    input  logic [7:0]         bus_data_in,
    input  logic               bus_address,
    input  logic               bus_cs_n,
    input  logic               bus_wr_n,
    output logic [7:0]         bus_data_out,
    output logic               irq_n,
    input  logic [7:0]         dsw3,
    output logic [7:0]         port_a_out,
    output logic [7:0]         port_b_out,
    output logic [7:0]         psg_a,
    output logic [7:0]         psg_b,
    output logic [7:0]         psg_c,
    output logic signed [15:0] fm,
    output logic               sample
);

    jt12_top #(
        .use_lfo(0),
        .use_ssg(1),
        .num_ch(3),
        .use_pcm(0),
        .use_adpcm(0),
        .mask_div(0)
    ) ym (
        .rst          (reset),
        .clk          (clk),
        .cen          (ce_1m5),
        .din          (bus_data_in),
        .addr         ({1'b0, bus_address}),
        .cs_n         (bus_cs_n),
        .wr_n         (bus_wr_n),
        .dout         (bus_data_out),
        .irq_n        (irq_n),
        .en_hifi_pcm  (1'b0),
        .adpcma_addr  (),
        .adpcma_bank  (),
        .adpcma_roe_n (),
        .adpcma_data  (8'd0),
        .adpcmb_addr  (),
        .adpcmb_data  (8'd0),
        .adpcmb_roe_n (),
        .IOA_in       (8'hff),
        .IOB_in       (dsw3),
        .IOA_out      (port_a_out),
        .IOB_out      (port_b_out),
        .psg_A        (psg_a),
        .psg_B        (psg_b),
        .psg_C        (psg_c),
        .fm_snd_left  (fm),
        .fm_snd_right (),
        .adpcmA_l     (),
        .adpcmA_r     (),
        .adpcmB_l     (),
        .adpcmB_r     (),
        .psg_snd      (),
        .snd_right    (),
        .snd_left     (),
        .snd_sample   (sample),
        .debug_bus    (8'd0),
        .debug_view   ()
    );

endmodule

