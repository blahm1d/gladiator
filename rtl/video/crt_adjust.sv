//============================================================================
//  CRT Adjust - core-side analog CRT geometry for MiSTer arcade cores.
//
//  Copyright (C) 2026 Umberto Parisi (rmonic79).
//  Distributed under GNU GPL v3 or later.
//
//  Vendored from:
//    https://github.com/rmonic79/MiSTer-CRT-Adjust
//  Upstream file:
//    rtl/crt_adjust.sv
//
//  The line buffer changes horizontal read spacing without changing the
//  source frame cadence. In HPOS_SYNCSHIFT mode, hs_ref_out is the shifted
//  HSync reference and the external read-rate accumulator must reset on its
//  rising edge.
//============================================================================

`ifndef HPOS_SYNCSHIFT
`define HPOS_SYNCSHIFT    0
`define HPOS_CONTENTSHIFT 1
`endif

module crt_adjust #(
    parameter VTOTAL    = 263,
    parameter HTOTAL    = 384,
    parameter HPOS_MODE = `HPOS_CONTENTSHIFT,
    parameter integer COLOR_BITS = 8
) (
    input                    clk,
    input                    pxl_cen,
    input                    pxl2_cen,
    input                    active,
    input       signed [4:0] hsize,
    input       signed [8:0] hoffset,
    input       signed [5:0] voffset,
    input              [7:0] r_in,
    input              [7:0] g_in,
    input              [7:0] b_in,
    input                    hs_in,
    input                    vs_in,
    input                    hb_in,
    input                    vb_in,
    output reg         [7:0] r_out,
    output reg         [7:0] g_out,
    output reg         [7:0] b_out,
    output reg               hs_out,
    output reg               vs_out,
    output reg               hb_out,
    output reg               vb_out,
    output wire              hs_ref_out
);

    localparam integer AW = 10;
    localparam integer MEM_BITS = 3 * COLOR_BITS;
    localparam signed [9:0] HTOTAL_S = HTOTAL;
    localparam signed [8:0] VTOTAL_S = VTOTAL;

    // Gladiator's board output is RGB555 expanded as {channel,channel[4:2]}.
    // COLOR_BITS=5 therefore stores every source pixel losslessly while using
    // two M10Ks instead of three. Keep 8 as the generic upstream-compatible
    // default for cores whose source really contains eight independent bits.
    function automatic [7:0] expand_color(
        input [COLOR_BITS-1:0] color
    );
        begin
            if (COLOR_BITS == 5)
                expand_color = {color[4:0], color[4:2]};
            else
                expand_color = color[7:0];
        end
    endfunction

    reg [7:0] r_in_q = 8'd0;
    reg [7:0] g_in_q = 8'd0;
    reg [7:0] b_in_q = 8'd0;
    reg       hs_in_q = 1'b0;
    reg       hb_in_q = 1'b1;
    reg       vs_in_q = 1'b0;
    reg       vb_in_q = 1'b0;

    always @(posedge clk) if (pxl_cen) begin
        r_in_q  <= r_in;
        g_in_q  <= g_in;
        b_in_q  <= b_in;
        hs_in_q <= hs_in;
        hb_in_q <= hb_in;
        vs_in_q <= vs_in;
        vb_in_q <= vb_in;
    end

    // HPOS_SYNCSHIFT delays or advances HSync in native-pixel units.
    wire signed [9:0] hshift_tap = hoffset[8]
        ? HTOTAL_S + $signed({hoffset[8], hoffset})
        : $signed({1'b0, hoffset});
    reg [HTOTAL-1:0] hsync_pix_shreg = {HTOTAL{1'b0}};
    reg              hs_shifted = 1'b0;

    always @(posedge clk) if (pxl_cen) begin
        hsync_pix_shreg <= {hsync_pix_shreg[HTOTAL-2:0], hs_in};
        hs_shifted <= (hshift_tap == 10'sd0)
            ? hs_in
            : hsync_pix_shreg[hshift_tap - 10'sd1];
    end

    wire hs_read_ref = (HPOS_MODE == `HPOS_SYNCSHIFT)
        ? hs_shifted
        : hs_in;
    assign hs_ref_out = hs_read_ref;

    reg hs_ref_d1 = 1'b0;
    always @(posedge clk) if (pxl_cen)
        hs_ref_d1 <= hs_read_ref;
    wire hs_rise_in = pxl_cen && hs_read_ref && !hs_ref_d1;

    // One packed-RGB, two-bank line buffer. The current line is written into
    // one half while the previous complete line is read from the other.
    (* ramstyle = "no_rw_check, M10K" *)
    reg [MEM_BITS-1:0] mem [0:(1<<AW)-1];
    integer ii;
    initial for (ii = 0; ii < (1<<AW); ii = ii + 1)
        mem[ii] = {MEM_BITS{1'b0}};

    reg [AW-1:0] wrp = {AW{1'b0}};
    reg [AW-1:0] hb0 = {AW{1'b0}};
    reg [AW-1:0] hb1 = {AW{1'b0}};
    reg          lhb_l = 1'b0;
    reg          bank = 1'b0;
    wire         lhb = ~hb_in;

    always @(posedge clk) if (pxl_cen) begin
        lhb_l <= lhb;
        mem[{bank, wrp[AW-2:0]}] <= {
            r_in[7 -: COLOR_BITS],
            g_in[7 -: COLOR_BITS],
            b_in[7 -: COLOR_BITS]
        };
        if (hs_rise_in) begin
            wrp  <= {AW{1'b0}};
            bank <= ~bank;
        end else begin
            wrp <= wrp + 1'b1;
        end
        if (lhb && !lhb_l)
            hb1 <= wrp;
        if (!lhb && lhb_l)
            hb0 <= wrp;
    end

    // Detect the shared HSync reference at full clock rate so a read-enable
    // pulse cannot miss the line boundary.
    reg [AW-1:0] rdcnt = {AW{1'b0}};
    reg          hs_in_d2 = 1'b0;
    reg          hs_rise_pending = 1'b0;

    always @(posedge clk) begin
        hs_in_d2 <= hs_read_ref;
        if (hs_read_ref && !hs_in_d2)
            hs_rise_pending <= 1'b1;
        else if (pxl2_cen)
            hs_rise_pending <= 1'b0;
    end

    always @(posedge clk) if (pxl2_cen) begin
        if (hs_rise_pending)
            rdcnt <= {AW{1'b0}};
        else
            rdcnt <= rdcnt + 1'b1;
    end

    // The read bank is one complete source line behind the write side. Delay
    // true vertical blank by one line to avoid clipping the last active row.
    reg vb_line = 1'b0;
    reg vb_active = 1'b0;
    always @(posedge clk) if (hs_rise_in) begin
        vb_line   <= vb_in;
        vb_active <= vb_line;
    end

    wire signed [AW+1:0] hoff_s =
        (HPOS_MODE == `HPOS_CONTENTSHIFT)
            ? {{(AW-7){hoffset[8]}}, hoffset}
            : {(AW+2){1'b0}};
    wire signed [AW+1:0] rdcnt_s = $signed({2'b0, rdcnt});
    wire signed [AW+1:0] hb1_s   = $signed({2'b0, hb1});
    wire signed [AW+1:0] hb0_s   = $signed({2'b0, hb0});
    wire        [AW-1:0] rd_addr = rdcnt_s - hoff_s;

    reg [MEM_BITS-1:0] rd_data = {MEM_BITS{1'b0}};
    reg        pass_q = 1'b0;
    always @(posedge clk) if (pxl2_cen) begin
        rd_data <= mem[{~bank, rd_addr[AW-2:0]}];
        pass_q <= (rdcnt_s >= (hb1_s + hoff_s)) &&
                  (rdcnt_s <  (hb0_s + hoff_s)) &&
                  !vb_active;
    end

    // Vertical position shifts VSync by whole source lines. Frame length and
    // line cadence remain native.
    wire signed [8:0] vshift_tap = voffset[5]
        ? VTOTAL_S + $signed({{3{voffset[5]}}, voffset})
        : $signed({3'b000, voffset});
    reg [VTOTAL-1:0] vsync_line_shreg = {VTOTAL{1'b0}};
    reg              vs_shifted = 1'b0;

    always @(posedge clk) if (hs_rise_in) begin
        vsync_line_shreg <= {vsync_line_shreg[VTOTAL-2:0], vs_in};
        vs_shifted <= (vshift_tap == 9'sd0)
            ? vs_in
            : vsync_line_shreg[vshift_tap - 9'sd1];
    end

    wire hs_pos_out = (HPOS_MODE == `HPOS_SYNCSHIFT)
        ? hs_shifted
        : hs_in_q;

    initial begin
        r_out = 8'd0;
        g_out = 8'd0;
        b_out = 8'd0;
        hs_out = 1'b0;
        vs_out = 1'b0;
        hb_out = 1'b1;
        vb_out = 1'b0;
    end

    always @(posedge clk) begin
        if (!active) begin
            if (pxl_cen) begin
                r_out  <= r_in_q;
                g_out  <= g_in_q;
                b_out  <= b_in_q;
                hb_out <= hb_in_q;
                hs_out <= hs_in_q;
                vs_out <= vs_in_q;
                vb_out <= vb_in_q;
            end
        end else if (pxl2_cen) begin
            if (pass_q) begin
                r_out <= expand_color(
                    rd_data[(3*COLOR_BITS)-1 -: COLOR_BITS]
                );
                g_out <= expand_color(
                    rd_data[(2*COLOR_BITS)-1 -: COLOR_BITS]
                );
                b_out <= expand_color(rd_data[COLOR_BITS-1:0]);
            end else begin
                r_out <= 8'd0;
                g_out <= 8'd0;
                b_out <= 8'd0;
            end
            hb_out <= ~pass_q;
            hs_out <= hs_pos_out;
            vs_out <= vs_shifted;
            vb_out <= vb_in_q;
        end
    end

endmodule
