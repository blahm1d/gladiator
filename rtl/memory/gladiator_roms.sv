// Physical-ROM store. Addresses are the fixed MRA stream documented in the
// specification. Graphics remain in their physical packed form; read adapters
// reproduce MAME's expanded byte views without storing a second copy.
module gladiator_roms (
    input  logic        clk,
    input  logic        reset,
    input  logic        download_active,
    input  logic        download_write,
    input  logic [19:0] download_address,
    input  logic [7:0]  download_data,
    output logic        rom_ready = 1'b0,

    input  logic [16:0] main_address,
    output logic [7:0]  main_data,
    input  logic [13:0] sound_address,
    output logic [7:0]  sound_data,
    input  logic [16:0] adpcm_address,
    output logic [7:0]  adpcm_data,

    input  logic [12:0] text_address,
    output logic [7:0]  text_data,
    input  logic [15:0] bg_plane0_address,
    output logic [7:0]  bg_plane0_data,
    input  logic [15:0] bg_plane12_address,
    output logic [7:0]  bg_plane12_data,
    input  logic [16:0] sprite_plane0_address,
    output logic [7:0]  sprite_plane0_data,
    input  logic [16:0] sprite_plane12_address,
    output logic [7:0]  sprite_plane12_data,

    input  logic [4:0]  prom_address,
    output logic [7:0]  prom_q3_data,
    output logic [7:0]  prom_q4_data,

    input  logic [9:0]  cctl_address,
    output logic [7:0]  cctl_raw_data,
    input  logic [9:0]  ccpu_address,
    output logic [7:0]  ccpu_raw_data,
    input  logic [9:0]  ucpu_address,
    output logic [7:0]  ucpu_raw_data,
    input  logic [10:0] csnd_address,
    output logic [7:0]  csnd_raw_data
);

    localparam logic [19:0] PACK_END = 20'h6_D440;

    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] main_rom   [0:17'h11fff];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] sound_rom  [0:14'h3fff];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] adpcm_rom  [0:17'h17fff];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] text_rom   [0:13'h1fff];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] bg_p3_rom  [0:15'h7fff];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] bg_p12_rom [0:16'hffff];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] sp_p3_rom  [0:16'hbfff];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] sp_p12_rom [0:17'h17fff];
    (* ramstyle = "MLAB, no_rw_check" *) logic [7:0] prom_rom   [0:6'h3f];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] cctl_rom   [0:10'h3ff];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] ccpu_rom   [0:10'h3ff];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] ucpu_rom   [0:10'h3ff];
    (* ramstyle = "M10K, no_rw_check" *) logic [7:0] csnd_rom   [0:11'h7ff];

    logic download_active_d = 1'b0;
    logic [19:0] highest_address = 20'd0;

    always_ff @(posedge clk) begin
        download_active_d <= download_active;

        // ROM is non-volatile from the reconstructed board's point of view.
        // MiSTer may assert reset again while loading index 2 NVRAM or index
        // 254 DIP data after index 0 has completed.  Preserve rom_ready across
        // those appliance transactions; otherwise the board remains in reset
        // forever because there is no second ROM download.
        if (reset && !download_active)
            download_active_d <= 1'b0;

        if (download_active && !download_active_d) begin
            rom_ready       <= 1'b0;
            highest_address <= 20'd0;
        end

        if (download_write && download_active) begin
            if (download_address > highest_address)
                highest_address <= download_address;

            if (download_address < 20'h1_2000)
                main_rom[download_address[16:0]] <= download_data;
            else if (download_address < 20'h1_6000)
                sound_rom[download_address - 20'h1_2000] <= download_data;
            else if (download_address < 20'h2_E000)
                adpcm_rom[download_address - 20'h1_6000] <= download_data;
            else if (download_address < 20'h3_0000)
                text_rom[download_address - 20'h2_E000] <= download_data;
            else if (download_address < 20'h3_8000)
                bg_p3_rom[download_address - 20'h3_0000] <= download_data;
            else if (download_address < 20'h4_8000)
                bg_p12_rom[download_address - 20'h3_8000] <= download_data;
            else if (download_address < 20'h5_4000)
                sp_p3_rom[download_address - 20'h4_8000] <= download_data;
            else if (download_address < 20'h6_C000)
                sp_p12_rom[download_address - 20'h5_4000] <= download_data;
            else if (download_address < 20'h6_C040)
                prom_rom[download_address - 20'h6_C000] <= download_data;
            else if (download_address < 20'h6_C440)
                cctl_rom[download_address - 20'h6_C040] <= download_data;
            else if (download_address < 20'h6_C840)
                ccpu_rom[download_address - 20'h6_C440] <= download_data;
            else if (download_address < 20'h6_CC40)
                ucpu_rom[download_address - 20'h6_C840] <= download_data;
            else if (download_address < PACK_END)
                csnd_rom[download_address - 20'h6_CC40] <= download_data;
        end

        if (!download_active && download_active_d)
            rom_ready <= (highest_address == PACK_END - 20'd1);
    end

    logic [7:0] bg_p3_raw;
    logic       bg_p3_shift;
    logic [1:0] bg_p12_block;
    logic [15:0] bg_p12_physical;

    logic [7:0] sp_p3_raw;
    logic       sp_p3_shift;
    logic [3:0] sp_p12_final_block;
    logic [3:0] sp_p12_original_block;
    logic [16:0] sp_p12_physical;

    always_comb begin
        case (bg_plane12_address[15:14])
            2'd1: bg_p12_block = 2'd2;
            2'd2: bg_p12_block = 2'd1;
            default: bg_p12_block = bg_plane12_address[15:14];
        endcase
        bg_p12_physical = {bg_p12_block, bg_plane12_address[13:0]};

        sp_p12_final_block = sprite_plane12_address[16:13];
        case (sp_p12_final_block)
            4'd0:  sp_p12_original_block = 4'd0;
            4'd1:  sp_p12_original_block = 4'd2;
            4'd2:  sp_p12_original_block = 4'd1;
            4'd3:  sp_p12_original_block = 4'd3;
            4'd4:  sp_p12_original_block = 4'd4;
            4'd5:  sp_p12_original_block = 4'd8;
            4'd6:  sp_p12_original_block = 4'd5;
            4'd7:  sp_p12_original_block = 4'd9;
            4'd8:  sp_p12_original_block = 4'd6;
            4'd9:  sp_p12_original_block = 4'd10;
            4'd10: sp_p12_original_block = 4'd7;
            4'd11: sp_p12_original_block = 4'd11;
            default: sp_p12_original_block = 4'd0;
        endcase
        sp_p12_physical = {sp_p12_original_block, sprite_plane12_address[12:0]};
    end

    always_ff @(posedge clk) begin
        main_data  <= main_rom[main_address];
        sound_data <= sound_rom[sound_address];
        adpcm_data <= adpcm_rom[adpcm_address];
        text_data  <= text_rom[text_address];

        bg_p3_raw   <= bg_p3_rom[{bg_plane0_address[15:14], bg_plane0_address[12:0]}];
        bg_p3_shift <= bg_plane0_address[13];
        bg_plane12_data <= bg_p12_rom[bg_p12_physical];

        sp_p3_raw   <= sp_p3_rom[{sprite_plane0_address[16:14], sprite_plane0_address[12:0]}];
        sp_p3_shift <= sprite_plane0_address[13];
        sprite_plane12_data <= sp_p12_rom[sp_p12_physical];

        prom_q3_data <= prom_rom[{1'b0, prom_address}];
        prom_q4_data <= prom_rom[{1'b1, prom_address}];

        cctl_raw_data <= cctl_rom[cctl_address];
        ccpu_raw_data <= ccpu_rom[ccpu_address];
        ucpu_raw_data <= ucpu_rom[ucpu_address];
        csnd_raw_data <= csnd_rom[csnd_address];
    end

    always_comb begin
        bg_plane0_data     = bg_p3_shift ? {4'h0, bg_p3_raw[7:4]} : bg_p3_raw;
        sprite_plane0_data = sp_p3_shift ? {4'h0, sp_p3_raw[7:4]} : sp_p3_raw;
    end

endmodule
