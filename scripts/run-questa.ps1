param(
    [switch] $FastStartup,
    [switch] $GoldenSpritePass,
    [switch] $WriteScoreboard,
    [int] $BootCycles = 0
)

$ErrorActionPreference = "Stop"

$project = Split-Path -Parent $PSScriptRoot
$questa = "C:\altera\25.1std\questa_fse\win64"
$work = Join-Path $project "sim\out\questa-work"

$vlib = Join-Path $questa "vlib.exe"
$vmap = Join-Path $questa "vmap.exe"
$vcom = Join-Path $questa "vcom.exe"
$vlog = Join-Path $questa "vlog.exe"
$vsim = Join-Path $questa "vsim.exe"

foreach ($tool in @($vlib, $vmap, $vcom, $vlog, $vsim)) {
    if (-not (Test-Path $tool)) {
        throw "Missing Questa executable: $tool"
    }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $work) -Force |
    Out-Null
if (-not (Test-Path $work)) {
    & $vlib $work
    if ($LASTEXITCODE -ne 0) { throw "vlib failed" }
}

Push-Location $project
try {
    & $vmap work $work
    if ($LASTEXITCODE -ne 0) { throw "vmap failed" }

    $t80 = @(
        "rtl\vendor\t80\T80pa.vhd",
        "rtl\vendor\t80\T80s.vhd",
        "rtl\vendor\t80\T80_Reg.vhd",
        "rtl\vendor\t80\T80_MCode.vhd",
        "rtl\vendor\t80\T80_ALU.vhd",
        "rtl\vendor\t80\T80.vhd"
    )
    & $vcom -2008 @t80
    if ($LASTEXITCODE -ne 0) { throw "T80 VHDL compile failed" }

    $sources = @(
        "rtl\vendor\upi41_core.v",
        "rtl\vendor\mc6809i.v",
        "rtl\vendor\jt5205.v",
        "rtl\vendor\jt5205_adpcm.v",
        "rtl\vendor\jt5205_interpol2x.v",
        "rtl\vendor\jt5205_timing.v"
    )
    $sources += Get-ChildItem "rtl\vendor\jt03" -Filter "*.v" |
        ForEach-Object { $_.FullName }
    $sources += @(
        "rtl\gladiator_nco_ce.sv",
        "rtl\gladiator_clock_enables.sv",
        "rtl\compat\gladiator_mcu_rom_adapter.sv",
        "rtl\compat\gladiator_mame_irq.sv",
        "rtl\memory\gladiator_roms.sv",
        "rtl\memory\gladiator_main_bus.sv",
        "rtl\memory\gladiator_sound_bus.sv",
        "rtl\memory\gladiator_6809_bus.sv",
        "rtl\gladiator_upi41_device.sv",
        "rtl\gladiator_mcu_cluster.sv",
        "rtl\audio\gladiator_ym2203.sv",
        "rtl\audio\gladiator_msm5205.sv",
        "rtl\audio\gladiator_audio_mixer.sv",
        "rtl\video\gladiator_board_timing.sv",
        "rtl\video\gladiator_sprite_line.sv",
        "rtl\video\gladiator_video.sv",
        "rtl\gladiator_board.sv",
        "sim\questa\tb_board_boot.sv"
    )

    & $vlog -sv @sources
    if ($LASTEXITCODE -ne 0) { throw "SystemVerilog compile failed" }

    $questaLog = if ($GoldenSpritePass) {
        "sim\out\questa-golden-sprite-pass.log"
    } elseif ($FastStartup) {
        "sim\out\questa-fast-startup.log"
    } else {
        "sim\out\questa-boot.log"
    }
    $simArgs = @("-c", "-l", $questaLog)
    if ($GoldenSpritePass) {
        # The golden harness deposits deterministic FPGA/MAME power-up bytes
        # before reset release. Questa reports those testbench deposits as a
        # suppressible second writer to always_ff RAM processes.
        $simArgs += @("-suppress", "7061")
    }
    if (-not $FastStartup -and -not $GoldenSpritePass) {
        $simArgs += "-voptargs=+acc"
    }
    $simArgs += "work.tb_board_boot"
    if ($GoldenSpritePass) {
        $simArgs += "+GOLDEN_SPRITE_PASS"
        if ($BootCycles -gt 0) {
            $simArgs += "+BOOT_CYCLES=$BootCycles"
        }
    } elseif ($FastStartup) {
        $simArgs += "+FAST_STARTUP"
        if ($BootCycles -gt 0) {
            $simArgs += "+BOOT_CYCLES=$BootCycles"
        }
    }
    if ($WriteScoreboard) {
        $simArgs += "+WRITE_SCOREBOARD"
    }
    $simArgs += @("-do", "run -all; quit -f")
    & $vsim @simArgs
    if ($LASTEXITCODE -ne 0) { throw "Questa boot simulation failed" }
    $passMarker = if ($GoldenSpritePass) {
        "PASS RTL golden sprite-pass state"
    } else {
        "PASS tb_board_boot"
    }
    if (-not (Select-String -Path $questaLog -Pattern $passMarker -Quiet)) {
        throw "Questa completed without the expected PASS marker."
    }
}
finally {
    Pop-Location
}
