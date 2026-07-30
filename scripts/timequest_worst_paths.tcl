# Preservation report: keep the worst paths visible without requiring the
# Quartus GUI. Quartus invokes this after its normal TimeQuest reports.

set report_dir "output_files"
set report_file [file join $report_dir "timequest_worst_setup_paths.rpt"]

file mkdir $report_dir
if {[file exists $report_file]} {
  file delete $report_file
}

proc append_line {text} {
  global report_file
  set fp [open $report_file a]
  puts $fp $text
  close $fp
}

proc report_setup_paths {label clock_check from_clock to_clock} {
  global report_file

  append_line ""
  append_line "============================================================"
  append_line $label
  append_line "============================================================"

  if {[string length $clock_check] != 0} {
    set clocks [get_clocks $clock_check]
    if {[llength $clocks] == 0} {
      append_line "Clock not found: $clock_check"
      return
    }
  }

  set cmd [list report_timing \
    -setup \
    -npaths 25 \
    -detail full_path \
    -panel_name $label \
    -file $report_file \
    -append]

  if {[string length $from_clock] != 0} {
    lappend cmd -from_clock $from_clock
  }

  if {[string length $to_clock] != 0} {
    lappend cmd -to_clock $to_clock
  }

  if {[catch {eval $cmd} err]} {
    append_line "report_timing failed: $err"
  }
}

set core96_clock {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}

append_line "Arcade Gladiator custom TimeQuest worst setup path report"

report_setup_paths \
  "Worst setup paths - all clocks" \
  "" \
  "" \
  ""

report_setup_paths \
  "Worst setup paths ending at 96 MHz core clock" \
  $core96_clock \
  "" \
  $core96_clock

report_setup_paths \
  "Worst setup paths - 96 MHz core clock to itself" \
  $core96_clock \
  $core96_clock \
  $core96_clock

append_line ""
append_line "============================================================"
append_line "Worst setup paths - Gladiator custom logic only"
append_line "============================================================"

set gladiator_regs [get_registers -nowarn {
  *gladiator_board:board|*
}]

if {[llength $gladiator_regs] == 0} {
  append_line "No Gladiator custom-logic registers found."
} elseif {[catch {
  report_timing \
    -setup \
    -from $gladiator_regs \
    -to $gladiator_regs \
    -npaths 25 \
    -detail full_path \
    -panel_name {Worst setup paths - Gladiator custom logic only} \
    -file $report_file \
    -append
} err]} {
  append_line "report_timing failed: $err"
}
unset gladiator_regs

append_line ""
append_line "============================================================"
append_line "MCU engine to scratchpad RAM constraint audit"
append_line "============================================================"

set mcu_core_regs [get_registers -nowarn {
  *gladiator_upi41_device:*|upi41_core:core|*
}]
set mcu_full_rate_regs [get_registers -nowarn {
  *upi41_core:core|upi41_db_bus_1:db_bus_b|n1147_q*
  *upi41_core:core|upi41_db_bus_1:db_bus_b|n1148_q*
  *upi41_core:core|t48_clock_ctrl_1:clock_ctrl_b|n893_q*
}]
set mcu_engine_regs [remove_from_collection $mcu_core_regs $mcu_full_rate_regs]
set mcu_dmem_regs [get_registers -nowarn {
  *gladiator_upi41_device:*|altdpram:dmem_rtl_0|*
}]

set mcu_core_count [get_collection_size $mcu_core_regs]
set mcu_engine_count [get_collection_size $mcu_engine_regs]
set mcu_dmem_count [get_collection_size $mcu_dmem_regs]

append_line "MCU core registers matched: $mcu_core_count"
append_line "MCU enable-gated engine registers matched: $mcu_engine_count"
append_line "MCU scratchpad RAM registers matched: $mcu_dmem_count"

if {$mcu_engine_count == 0 || $mcu_dmem_count == 0} {
  append_line "ERROR: MCU timing collections are empty."
} elseif {[catch {
  report_timing \
    -setup \
    -from $mcu_engine_regs \
    -to $mcu_dmem_regs \
    -npaths 25 \
    -detail full_path \
    -panel_name {MCU engine to scratchpad RAM constraint audit} \
    -file $report_file \
    -append
} err]} {
  append_line "report_timing failed: $err"
}

unset mcu_core_regs
unset mcu_full_rate_regs
unset mcu_engine_regs
unset mcu_dmem_regs
unset mcu_core_count
unset mcu_engine_count
unset mcu_dmem_count

append_line ""
append_line "End of custom TimeQuest report."
