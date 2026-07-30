// MCU-ROM-001
// Keeps MAME's derived-ROM repair outside the MCU implementation. A future
// verified MCU dump bypasses this module by clearing enable_patch.
module gladiator_mcu_rom_adapter (
    input  logic        enable_patch,
    input  logic [10:0] address,
    input  logic [7:0]  raw_data,
    output logic [7:0]  program_data,
    output logic        patch_visible
);

    always_comb begin
        patch_visible = enable_patch && (address == 11'd0);
        program_data  = patch_visible ? 8'h22 : raw_data;
    end

endmodule

