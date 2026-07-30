param(
    [string] $PythonExe = "python",
    [string] $From = ""
)

$ErrorActionPreference = "Stop"

$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $project "sim\out"
$iverilog = "C:\iverilog\bin\iverilog.exe"
$vvp = "C:\iverilog\bin\vvp.exe"

New-Item -ItemType Directory -Path $out -Force | Out-Null

$tests = @(
    @{
        Name = "tb_clock_enables"
        Files = @(
            "rtl\gladiator_nco_ce.sv",
            "rtl\gladiator_clock_enables.sv",
            "sim\unit\tb_clock_enables.sv"
        )
    },
    @{
        Name = "tb_dip_loader"
        Files = @(
            "rtl\gladiator_dip_loader.sv",
            "sim\unit\tb_dip_loader.sv"
        )
    },
    @{
        Name = "tb_crt_read_ce"
        Files = @(
            "rtl\video\gladiator_crt_read_ce.sv",
            "sim\unit\tb_crt_read_ce.sv"
        )
    },
    @{
        Name = "tb_crt_adjust_boundaries"
        Files = @(
            "rtl\video\crt_adjust.sv",
            "sim\unit\tb_crt_adjust_boundaries.sv"
        )
    },
    @{
        Name = "tb_effect_tracker"
        Files = @(
            "rtl\audio\gladiator_effect_tracker.sv",
            "sim\unit\tb_effect_tracker.sv"
        )
    },
    @{
        Name = "tb_sound_command_tap"
        Files = @(
            "rtl\memory\gladiator_sound_bus.sv",
            "sim\unit\tb_sound_command_tap.sv"
        )
    },
    @{
        Name = "tb_rom_map"
        Files = @(
            "rtl\memory\gladiator_roms.sv",
            "sim\unit\tb_rom_map.sv"
        )
    },
    @{
        Name = "tb_rom_download"
        Prepare = {
            & $PythonExe (Join-Path $project "scripts\build_rom_port_oracle.py") `
                --zip (Join-Path $project "roms\gladiatr.zip") `
                --out (Join-Path $project "sim\out")
            if ($LASTEXITCODE -ne 0) {
                throw "ROM port oracle generation failed"
            }
        }
        Files = @(
            "rtl\memory\gladiator_roms.sv",
            "sim\unit\tb_rom_download.sv"
        )
    },
    @{
        Name = "tb_nvram_live_upload"
        Files = @(
            "rtl\memory\gladiator_main_bus.sv",
            "sim\unit\tb_nvram_live_upload.sv"
        )
    },
    @{
        Name = "tb_frame_retimer"
        Files = @(
            "rtl\video\gladiator_frame_retimer.sv",
            "sim\unit\tb_frame_retimer.sv"
        )
    },
    @{
        Name = "tb_analog_conditioner"
        Files = @(
            "rtl\video\gladiator_analog_conditioner.sv",
            "sim\unit\tb_analog_conditioner.sv"
        )
    },
    @{
        Name = "tb_gfx_decode"
        Files = @(
            "rtl\video\gladiator_sprite_line.sv",
            "rtl\video\gladiator_video.sv",
            "sim\unit\tb_gfx_decode.sv"
        )
    },
    @{
        Name = "tb_mame_sprite_replay"
        Prepare = {
            $snapshot = Join-Path $project `
                "sim\out\mame-sprite-snapshots.csv"
            if (-not (Test-Path -LiteralPath $snapshot)) {
                & powershell.exe -NoProfile -ExecutionPolicy Bypass `
                    -File (Join-Path $project `
                        "scripts\run-mame-full-trace.ps1") `
                    -Frames 600 -SnapshotPeriod 60 `
                    -ScreenshotPeriod 300 -TraceUntilFrame 600
                if ($LASTEXITCODE -ne 0) {
                    throw "MAME sprite-state capture failed"
                }
            }
            & $PythonExe (Join-Path $project "scripts\build_sprite_oracle.py") `
                --out (Join-Path $project "sim\out") `
                --frame 600
            if ($LASTEXITCODE -ne 0) {
                throw "MAME sprite oracle generation failed"
            }
        }
        Files = @(
            "rtl\memory\gladiator_roms.sv",
            "rtl\video\gladiator_sprite_line.sv",
            "sim\unit\tb_mame_sprite_replay.sv"
        )
    },
    @{
        # Whole-image replay of every captured MAME sprite state.  The
        # single-line bench above covers one scanline of one frame, which
        # cannot reach the 256-line Y wrap, the sprite-bank select, or the
        # 32x32 tile assembly.
        Name = "tb_mame_sprite_frame_replay"
        Prepare = {
            $snapshot = Join-Path $project `
                "sim\out\mame-sprite-snapshots.csv"
            if (-not (Test-Path -LiteralPath $snapshot)) {
                throw "missing sim\out\mame-sprite-snapshots.csv"
            }
            & $PythonExe (Join-Path $project `
                "scripts\build_sprite_frame_oracle.py") `
                --out (Join-Path $project "sim\out")
            if ($LASTEXITCODE -ne 0) {
                throw "MAME sprite frame oracle generation failed"
            }
        }
        Files = @(
            "rtl\memory\gladiator_roms.sv",
            "rtl\video\gladiator_sprite_line.sv",
            "sim\unit\tb_mame_sprite_frame_replay.sv"
        )
    },
    @{
        # Whole COMPOSITE frame (bg + text + sprite + palette + priority) vs
        # MAME. Its oracle self-validates PNG-exact against MAME's own
        # screenshots BEFORE the RTL is compared -- that is what caught the pen
        # bit order the sprite gate could not, because the sprite oracle shared
        # the RTL's inverted convention.
        # KNOWN RED: frame 2400 has 5 mismatching pixels at x=0. Do not cite as
        # green until root-caused; do not trim the frame list to hide it.
        Name = "tb_composite_frame"
        Prepare = {
            & $PythonExe (Join-Path $project "scripts\build_composite_oracle.py") `
                --out (Join-Path $project "sim\out")
            if ($LASTEXITCODE -ne 0) {
                throw "composite oracle generation failed"
            }
        }
        Files = @(
            "rtl\gladiator_nco_ce.sv",
            "rtl\video\gladiator_board_timing.sv",
            "rtl\memory\gladiator_roms.sv",
            "rtl\video\gladiator_sprite_line.sv",
            "rtl\video\gladiator_video.sv",
            "sim\unit\tb_composite_frame.sv"
        )
    },
    @{
        Name = "tb_msm5205"
        Files = @(
            "rtl\audio\gladiator_msm5205.sv",
            "sim\unit\tb_msm5205.sv"
        )
    },
    @{
        Name = "tb_mame_adpcm_replay"
        Prepare = {
            & $PythonExe (Join-Path $project "scripts\build_adpcm_oracle.py") `
                --out (Join-Path $project "sim\out")
            if ($LASTEXITCODE -ne 0) {
                & powershell.exe -NoProfile -ExecutionPolicy Bypass `
                    -File (Join-Path $project `
                        "scripts\run-mame-full-trace.ps1") `
                    -Frames 3600 -SnapshotPeriod 60 `
                    -ScreenshotPeriod 600 -TraceUntilFrame 3600
                if ($LASTEXITCODE -ne 0) {
                    throw "MAME audio-state capture failed"
                }
                & $PythonExe (Join-Path $project `
                    "scripts\build_adpcm_oracle.py") `
                    --out (Join-Path $project "sim\out")
                if ($LASTEXITCODE -ne 0) {
                    throw "MAME MSM5205 oracle generation failed"
                }
            }
        }
        Files = @(
            "rtl\audio\gladiator_msm5205.sv",
            "sim\unit\tb_mame_adpcm_replay.sv"
        )
    },
    @{
        Name = "tb_audio_mixer"
        Files = @(
            "rtl\audio\gladiator_audio_mixer.sv",
            "sim\unit\tb_audio_mixer.sv"
        )
    },
    @{
        Name = "tb_csnd_boot"
        Files = @(
            "rtl\vendor\upi41_core.v",
            "rtl\gladiator_upi41_device.sv",
            "sim\unit\tb_csnd_boot.sv"
        )
    },
    @{
        Name = "tb_upi41_dmem_contract"
        Files = @(
            "rtl\vendor\upi41_core.v",
            "rtl\gladiator_upi41_device.sv",
            "sim\unit\tb_upi41_dmem_contract.sv"
        )
    },
    @{
        Name = "tb_ucpu_protocol"
        Files = @(
            "rtl\vendor\upi41_core.v",
            "rtl\gladiator_upi41_device.sv",
            "sim\unit\tb_ucpu_protocol.sv"
        )
    },
    @{
        Name = "tb_input_mcu_protocol"
        Files = @(
            "rtl\vendor\upi41_core.v",
            "rtl\compat\gladiator_mcu_rom_adapter.sv",
            "rtl\gladiator_upi41_device.sv",
            "sim\unit\tb_input_mcu_protocol.sv"
        )
    }
)

$startIndex = 0
if ($From) {
    $matchingIndex = -1
    for ($i = 0; $i -lt $tests.Count; $i++) {
        if ($tests[$i].Name -eq $From) {
            $matchingIndex = $i
            break
        }
    }
    if ($matchingIndex -lt 0) {
        throw "Unknown test requested by -From: $From"
    }
    $startIndex = $matchingIndex
}

for ($testIndex = $startIndex; $testIndex -lt $tests.Count; $testIndex++) {
    $test = $tests[$testIndex]
    if ($test.Prepare) {
        & $test.Prepare
    }
    $output = Join-Path $out ($test.Name + ".vvp")
    $sources = $test.Files | ForEach-Object { Join-Path $project $_ }
    $ErrorActionPreference = "Continue"
    $compileOutput = & $iverilog -g2012 -s $test.Name -o $output @sources 2>&1
    $compileExitCode = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    if ($compileExitCode -ne 0) {
        $compileOutput | Write-Host
        throw "Icarus compile failed for $($test.Name)"
    }
    & $vvp $output
    if ($LASTEXITCODE -ne 0) {
        throw "Unit test failed: $($test.Name)"
    }
}
