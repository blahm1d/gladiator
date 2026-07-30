// IRQ-SUB-001
// MAME-compatible held interrupt. This is deliberately not part of the
// physical address decoder; replace it when the real board source is measured.
module gladiator_mame_irq (
    input  logic clk,
    input  logic reset,
    input  logic enable,
    input  logic set,
    input  logic acknowledge,
    output logic irq_n,
    output logic pending
);

    always_ff @(posedge clk) begin
        if (reset || !enable)
            pending <= 1'b0;
        else begin
            if (set)
                pending <= 1'b1;
            if (acknowledge)
                pending <= 1'b0;
        end
    end

    assign irq_n = !pending;

endmodule

