// MiSTer-side analog output conditioner.
//
// This block is deliberately downstream of gladiator_board. It changes only
// the monitor-facing blanking/sync presentation and never feeds timing back
// into the reconstructed arcade board.
module gladiator_analog_conditioner (
    input  logic       clk,
    input  logic       reset,
    input  logic       pixel_ce,
    input  logic [9:0] h_count,
    input  logic [9:0] v_count,
    input  logic [9:0] h_total,
    input  logic [9:0] v_total,
    input  logic [9:0] default_hsync_start,
    input  logic [9:0] default_vsync_start,
    input  logic [9:0] default_hsync_width,
    input  logic [3:0] default_vsync_width,
    input  logic [9:0] content_x_start,
    input  logic [9:0] content_x_end,
    input  logic [9:0] content_y_start,
    input  logic [9:0] content_y_end,
    input  logic [7:0] red_in,
    input  logic [7:0] green_in,
    input  logic [7:0] blue_in,
    input  logic       hblank_in,
    input  logic       vblank_in,

    input  logic [4:0] h_position,
    input  logic [4:0] v_position,
    input  logic [3:0] hsync_width_adjust,
    input  logic [1:0] vsync_width_adjust,
    input  logic       hsync_positive,
    input  logic       vsync_positive,
    input  logic [3:0] crop_horizontal,
    input  logic [3:0] crop_vertical,

    output logic [7:0] red,
    output logic [7:0] green,
    output logic [7:0] blue,
    output logic       hblank,
    output logic       vblank,
    output logic       hsync,
    output logic       vsync
);

    logic signed [10:0] h_start_signed;
    logic signed [10:0] v_start_signed;
    logic [9:0] h_start;
    logic [9:0] v_start;
    logic [9:0] h_end;
    logic [9:0] v_end;
    logic hsync_asserted;
    logic vsync_asserted;
    logic crop_blank;
    logic signed [10:0] h_width_signed;
    logic signed [4:0] v_width_signed;
    logic [9:0] h_width;
    logic [3:0] v_width;

    function automatic logic in_wrapped_window (
        input logic [9:0] value,
        input logic [9:0] start_value,
        input logic [9:0] end_value
    );
        begin
            if (end_value >= start_value)
                in_wrapped_window = (value >= start_value) &&
                                    (value < end_value);
            else
                in_wrapped_window = (value >= start_value) ||
                                    (value < end_value);
        end
    endfunction

    always_comb begin
        h_start_signed = $signed({1'b0, default_hsync_start}) +
                         $signed({{6{h_position[4]}}, h_position});
        if (h_start_signed < 0)
            h_start = h_start_signed + $signed({1'b0, h_total});
        else if (h_start_signed >= $signed({1'b0, h_total}))
            h_start = h_start_signed - $signed({1'b0, h_total});
        else
            h_start = h_start_signed[9:0];

        v_start_signed = $signed({1'b0, default_vsync_start}) +
                         $signed({{6{v_position[4]}}, v_position});
        if (v_start_signed < 0)
            v_start = v_start_signed + $signed({1'b0, v_total});
        else if (v_start_signed >= $signed({1'b0, v_total}))
            v_start = v_start_signed - $signed({1'b0, v_total});
        else
            v_start = v_start_signed[9:0];

        h_width_signed = $signed({1'b0, default_hsync_width}) +
                         $signed({{7{hsync_width_adjust[3]}},
                                  hsync_width_adjust});
        v_width_signed = $signed({1'b0, default_vsync_width}) +
                         $signed({{3{vsync_width_adjust[1]}},
                                  vsync_width_adjust});
        h_width = (h_width_signed < 1) ? 10'd1 :
                  h_width_signed[9:0];
        v_width = (v_width_signed < 1) ? 4'd1 :
                  v_width_signed[3:0];

        h_end = h_start + h_width;
        if (h_end >= h_total)
            h_end = h_end - h_total;
        v_end = v_start + {6'd0, v_width};
        if (v_end >= v_total)
            v_end = v_end - v_total;

        hsync_asserted = in_wrapped_window(h_count, h_start, h_end);
        vsync_asserted = in_wrapped_window(v_count, v_start, v_end);

        crop_blank =
            ((h_count >= content_x_start) &&
             (h_count < content_x_start + {6'd0, crop_horizontal})) ||
            ((h_count < content_x_end) &&
             (h_count >= content_x_end - {6'd0, crop_horizontal})) ||
            ((v_count >= content_y_start) &&
             (v_count < content_y_start + {6'd0, crop_vertical})) ||
            ((v_count < content_y_end) &&
             (v_count >= content_y_end - {6'd0, crop_vertical}));
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            red    <= 8'd0;
            green  <= 8'd0;
            blue   <= 8'd0;
            hblank <= 1'b1;
            vblank <= 1'b1;
            hsync  <= 1'b1;
            vsync  <= 1'b1;
        end else if (pixel_ce) begin
            red    <= crop_blank ? 8'd0 : red_in;
            green  <= crop_blank ? 8'd0 : green_in;
            blue   <= crop_blank ? 8'd0 : blue_in;
            hblank <= hblank_in || crop_blank;
            vblank <= vblank_in || crop_blank;
            hsync  <= hsync_positive ? hsync_asserted : !hsync_asserted;
            vsync  <= vsync_positive ? vsync_asserted : !vsync_asserted;
        end
    end

endmodule
