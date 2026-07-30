# Root and PLL clocks are declared by sys/sys_top.sdc.
#
# The 6809 is implemented with E and Q clock-enable pulses on the 96 MHz
# master clock. Each phase repeats once every 32 master cycles. Relax only
# paths whose launch and latch registers use the same phase; cross-phase and
# board-interface paths deliberately retain their normal single-cycle checks.
set m6809_all_regs [get_registers -nowarn {*mc6809i:audio_cpu|* *gladiator_board:board|cpu6809_vma}]
set m6809_q_regs [get_registers -nowarn {*mc6809i:audio_cpu|last_NMISample2 *mc6809i:audio_cpu|last_wNMIClear *mc6809i:audio_cpu|NMILatched *mc6809i:audio_cpu|NMISample *mc6809i:audio_cpu|IRQSample *mc6809i:audio_cpu|FIRQSample *mc6809i:audio_cpu|HALTSample *mc6809i:audio_cpu|DMABREQSample}]
set m6809_e_regs [remove_from_collection $m6809_all_regs $m6809_q_regs]

set_multicycle_path -setup 32 -from $m6809_e_regs -to $m6809_e_regs
set_multicycle_path -hold  31 -from $m6809_e_regs -to $m6809_e_regs
set_multicycle_path -setup 32 -from $m6809_q_regs -to $m6809_q_regs
set_multicycle_path -hold  31 -from $m6809_q_regs -to $m6809_q_regs

# ROM download writes and board execution cannot overlap: download_active is
# part of board_reset. Ignore only the inferred ADPCM RAM write-enable state
# feeding the E-phase CPU registers. Address-driven runtime reads remain timed.
set adpcm_download_regs [get_registers -nowarn {*gladiator_roms:roms|*adpcm_rom_rtl_0*PORT_B_WRITE_ENABLE_REG}]
if {[get_collection_size $adpcm_download_regs] > 0} {
    set_false_path -from $adpcm_download_regs -to $m6809_e_regs
}

# The synchronous ADPCM ROM read registers update after the E-phase address
# changes and are then stable until the next E pulse.
set adpcm_read_regs [get_registers -nowarn {*gladiator_roms:roms|*adpcm_rom_rtl_0*}]
set_multicycle_path -setup 31 -from $adpcm_read_regs -to $m6809_e_regs
set_multicycle_path -hold  30 -from $adpcm_read_regs -to $m6809_e_regs

# Each UPI-41 execution engine advances from the 6 MHz enable. The generated
# core contains deliberately full-rate host edge/input state and five
# clock-control pin registers (ALE/PSEN/PROG/RD/WR). Decoder F1 is also
# host-writable between MCU enables. Exclude those exact registers from the
# engine collection so their host-originating paths retain single-cycle timing.
set mcu_core_regs [get_registers -nowarn {*gladiator_upi41_device:*|upi41_core:core|*}]
set mcu_full_rate_regs [get_registers -nowarn {
    *upi41_core:core|upi41_db_bus_1:db_bus_b|n1147_q*
    *upi41_core:core|upi41_db_bus_1:db_bus_b|n1148_q*
    *upi41_core:core|upi41_db_bus_1:db_bus_b|n1149_q*
    *upi41_core:core|upi41_db_bus_1:db_bus_b|n1150_q*
    *upi41_core:core|upi41_db_bus_1:db_bus_b|n1151_q*
    *upi41_core:core|upi41_db_bus_1:db_bus_b|n1152_q*
    *upi41_core:core|upi41_db_bus_1:db_bus_b|n1153_q*
    *upi41_core:core|upi41_db_bus_1:db_bus_b|n1162_q*
    *upi41_core:core|upi41_db_bus_1:db_bus_b|n1163_q*
    *upi41_core:core|t48_decoder_1_1_1:decoder_b|n4585_q*
    *upi41_core:core|t48_clock_ctrl_1:clock_ctrl_b|n889_q*
    *upi41_core:core|t48_clock_ctrl_1:clock_ctrl_b|n890_q*
    *upi41_core:core|t48_clock_ctrl_1:clock_ctrl_b|n891_q*
    *upi41_core:core|t48_clock_ctrl_1:clock_ctrl_b|n892_q*
    *upi41_core:core|t48_clock_ctrl_1:clock_ctrl_b|n893_q*
}]
set mcu_engine_regs [remove_from_collection $mcu_core_regs $mcu_full_rate_regs]

set_multicycle_path -setup 16 -from $mcu_engine_regs -to $mcu_engine_regs
set_multicycle_path -hold  15 -from $mcu_engine_regs -to $mcu_engine_regs

# IBF, OBF, interrupt and DRQ registers also react to the asynchronous host
# interface, so they are not engine registers. Their dependence on engine
# state is selected only while en_clk_i is asserted, however; constrain just
# that source direction and leave all host-source paths at one cycle.
set mcu_mixed_host_regs [get_registers -nowarn {
    *upi41_core:core|upi41_db_bus_1:db_bus_b|n1151_q*
    *upi41_core:core|upi41_db_bus_1:db_bus_b|n1152_q*
    *upi41_core:core|upi41_db_bus_1:db_bus_b|n1162_q*
    *upi41_core:core|upi41_db_bus_1:db_bus_b|n1163_q*
}]
set_multicycle_path -setup 16 -from $mcu_engine_regs -to $mcu_mixed_host_regs
set_multicycle_path -hold  15 -from $mcu_engine_regs -to $mcu_mixed_host_regs

# The scratchpad read path may settle during the intervening master clocks;
# the execution engine cannot consume it until a later enable.
set mcu_dmem_read_regs [get_registers -nowarn {
    *gladiator_upi41_device:*|dmem_data_in*
    *gladiator_upi41_device:*|altdpram:dmem_rtl_0|*OBSERVABLEPORTAADDRESSREGOUT*
}]
set_multicycle_path -setup 16 -from $mcu_engine_regs -to $mcu_dmem_read_regs
set_multicycle_path -hold  15 -from $mcu_engine_regs -to $mcu_dmem_read_regs

# The T48 wrapper commits scratchpad writes on the core-enable edge, matching
# JTFRAME's canonical i8742 integration. The inferred MLAB input registers
# therefore receive address, data, and write-enable directly from the
# enable-gated execution engine and have the same 16-cycle relationship.
set mcu_dmem_regs [get_registers -nowarn {
    *gladiator_upi41_device:*|altdpram:dmem_rtl_0|*
}]
set_multicycle_path -setup 16 -from $mcu_engine_regs -to $mcu_dmem_regs
set_multicycle_path -hold  15 -from $mcu_engine_regs -to $mcu_dmem_regs

# The two T80 instances are synchronous clock-enable implementations, not
# divided-clock domains. T80s and the T80/T80_Reg datapath registers advance
# only when CEN/ClkEn is asserted: every 16 master clocks for the 6 MHz main
# CPU and every 32 master clocks for the 3 MHz sound CPU. NMI_s and the
# synthesized OldNMI_n edge-history register are intentionally removed
# because they sample the NMI input on every 96 MHz edge.
set main_z80_regs [get_registers -nowarn {*T80s:main_cpu|*}]
# The main CPU NMI pin is tied inactive, so Quartus removes both edge-capture
# registers. Every surviving register in this instance is CEN-gated.
set main_z80_cen_regs $main_z80_regs

set_multicycle_path -setup 16 -from $main_z80_cen_regs -to $main_z80_cen_regs
set_multicycle_path -hold  15 -from $main_z80_cen_regs -to $main_z80_cen_regs

set sound_z80_regs [get_registers -nowarn {*T80s:sound_cpu|*}]
set sound_z80_nmi_regs [get_registers -nowarn {*T80s:sound_cpu|T80:u0|NMI_s *T80s:sound_cpu|T80:u0|OldNMI_n*}]
set sound_z80_cen_regs [remove_from_collection $sound_z80_regs $sound_z80_nmi_regs]

set_multicycle_path -setup 32 -from $sound_z80_cen_regs -to $sound_z80_cen_regs
set_multicycle_path -hold  31 -from $sound_z80_cen_regs -to $sound_z80_cen_regs

# JT03's YM2203 phase-generator input and phase-pad shift registers both
# advance only on ce_1m5. gladiator_clock_enables derives that enable as an
# exact divide by 64 from clk_96. Constrain only the audited phase-increment
# and detune launch registers to the CE-gated pad registers; host-interface
# and other YM paths retain ordinary single-cycle checks.
set ym_pg_source_regs [get_registers -nowarn {
    *gladiator_ym2203:ym2203|jt12_top:ym|jt12_pg:u_pg|phinc_II*
    *gladiator_ym2203:ym2203|jt12_top:ym|jt12_pg:u_pg|detune_mod_II*
}]
set ym_pg_phase_shift_regs [get_registers -nowarn {
    *gladiator_ym2203:ym2203|jt12_top:ym|jt12_pg:u_pg|jt12_sh_rst:u_pad|bits*
    *gladiator_ym2203:ym2203|jt12_top:ym|jt12_pg:u_pg|jt12_sh_rst:u_phsh|bits*
}]
set_multicycle_path -setup 64 -from $ym_pg_source_regs -to $ym_pg_phase_shift_regs
set_multicycle_path -hold  63 -from $ym_pg_source_regs -to $ym_pg_phase_shift_regs

# The JT12 register scanner's current-channel counter and the phase-generator
# input registers also advance only on JT12's internal clk_en, which cannot
# occur more often than the external divide-by-64 enable. This exact
# source/destination pair is the frequency/detune selection path.
set ym_reg_channel_regs [get_registers -nowarn {
    *gladiator_ym2203:ym2203|jt12_top:ym|jt12_mmr:u_mmr|jt12_reg:u_reg|cur_ch*
}]
set_multicycle_path -setup 64 -from $ym_reg_channel_regs -to $ym_pg_source_regs
set_multicycle_path -hold  63 -from $ym_reg_channel_regs -to $ym_pg_source_regs

# First stages of the explicit clk_32-to-clk_96 control synchronizers.
set_false_path -to [get_registers -nowarn {*emu|status_96_meta* *emu|buttons_96_meta* *emu|forced_scandoubler_96_meta*}]
