// Pin-level wrapper around the T48 UPI-41 core. Program storage remains in the
// physical ROM subsystem so raw and derived MCU images can be compared.
module gladiator_upi41_device (
    input  logic        clk,
    input  logic        ce_6m,
    input  logic        reset,

    input  logic        host_a0,
    input  logic        host_cs_n,
    input  logic        host_rd_n,
    input  logic        host_wr_n,
    input  logic [7:0]  host_data_in,
    output logic [7:0]  host_data_out,

    input  logic [7:0]  p1_pin_in,
    input  logic [7:0]  p2_pin_in,
    output logic [7:0]  p1_latch_out,
    output logic [7:0]  p2_latch_out,
    input  logic        t0,
    input  logic        t1,

    output logic [10:0] program_address,
    input  logic [7:0]  program_data,

    output logic [7:0]  debug_dmem_address,
    output logic        debug_dmem_write
);

    // MiSTer's inferred FPGA RAM has a deterministic zero power-up image.
    // Do not clear it on MCU reset: MCS-48 reset does not represent a RAM
    // erase. The explicit image also matches MAME and JTFRAME simulation.
    (* ramstyle = "MLAB, no_rw_check" *) logic [7:0] dmem [0:255];
    logic [7:0] dmem_data_in;
    logic [7:0] dmem_data_out;
    logic [7:0] dmem_address;
    logic dmem_write;
    logic core_cen;

    integer dmem_init_index;
    initial begin
        for (dmem_init_index = 0; dmem_init_index < 256;
                dmem_init_index = dmem_init_index + 1)
            dmem[dmem_init_index] = 8'h00;
    end

    always @(posedge clk) begin
        if (reset) begin
            dmem_data_in <= 8'h00;
        end else begin
            // Quartus implements this array as an MLAB with same-address
            // read/write set to DONT_CARE. The address is stable for many
            // master clocks before a core-qualified write, so dmem_data_in
            // already holds that address's pre-write value. Hold it across
            // the write edge instead of sampling the MLAB's undefined
            // collision output. This preserves the OpenCores/JTFRAME
            // old-data contract in both RTL and silicon.
            if (!dmem_write)
                dmem_data_in <= dmem[dmem_address];

            // dmem_write is already qualified by the core enable; commit the
            // internal-RAM transaction on this same master edge.
            if (dmem_write)
                dmem[dmem_address] <= dmem_data_out;
        end
    end

    assign debug_dmem_address = dmem_address;
    assign debug_dmem_write   = dmem_write;

    upi41_core core (
        .xtal_i         (clk),
        .xtal_en_i      (ce_6m),
        .reset_i        (!reset),
        .t0_i           (t0),
        .cs_n_i         (host_cs_n),
        .rd_n_i         (host_rd_n),
        .a0_i           (host_a0),
        .wr_n_i         (host_wr_n),
        .db_i           (host_data_in),
        .t1_i           (t1),
        .p2_i           (p2_pin_in & p2_latch_out),
        .p1_i           (p1_pin_in & p1_latch_out),
        .clk_i          (clk),
        .en_clk_i       (core_cen),
        .dmem_data_i    (dmem_data_in),
        .pmem_data_i    (program_data),
        .sync_o         (),
        .db_o           (host_data_out),
        .db_dir_o       (),
        .p2_o           (p2_latch_out),
        .p2l_low_imp_o  (),
        .p2h_low_imp_o  (),
        .p1_o           (p1_latch_out),
        .p1_low_imp_o   (),
        .prog_n_o       (),
        .xtal3_o        (core_cen),
        .dmem_addr_o    (dmem_address),
        .dmem_we_o      (dmem_write),
        .dmem_data_o    (dmem_data_out),
        .pmem_addr_o    (program_address)
    );

endmodule
