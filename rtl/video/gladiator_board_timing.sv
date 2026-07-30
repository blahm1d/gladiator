// VID-RAW-001, VID-MAME-001
// Board-domain raster candidates. Monitor-safe retiming belongs downstream.
module gladiator_board_timing (
    input  logic       clk,
    input  logic       reset,
    input  logic       ce_6m,
    input  logic       mame_60hz,
    output logic       pixel_ce,
    output logic [8:0] h_count,
    output logic [8:0] v_count,
    output logic       hblank,
    output logic       vblank,
    output logic       hsync,
    output logic       vsync,
    output logic       vblank_rise
);

    logic ce_mame;
    logic selected_ce;
    logic [8:0] v_total;

    gladiator_nco_ce #(.STEP(32'h1018_e758)) mame_pixel_nco (
        .clk    (clk),
        .reset  (reset),
        .enable (1'b1),
        .ce     (ce_mame)
    );

    always_comb begin
        selected_ce = mame_60hz ? ce_mame : ce_6m;
        v_total     = mame_60hz ? 9'd262 : 9'd264;
        pixel_ce    = selected_ce;
        hblank      = h_count >= 9'd256;
        vblank      = (v_count < 9'd16) || (v_count >= 9'd240);
        // Candidate sync positions are deliberately downstream-adjustable.
        hsync       = !((h_count >= 9'd288) && (h_count < 9'd320));
        vsync       = !((v_count >= 9'd244) && (v_count < 9'd247));
        vblank_rise = selected_ce && (h_count == 9'd383) &&
                      (v_count == 9'd239);
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            h_count <= 9'd0;
            v_count <= 9'd0;
        end else if (selected_ce) begin
            if (h_count == 9'd383) begin
                h_count <= 9'd0;
                if (v_count == v_total - 9'd1)
                    v_count <= 9'd0;
                else
                    v_count <= v_count + 9'd1;
            end else begin
                h_count <= h_count + 9'd1;
            end
        end
    end

endmodule

