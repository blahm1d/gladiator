param(
    [string] $ReleaseBaseName = "Gladiator_DipCrtFxBoost_20260729",
    [ValidateRange(1, 9999)] [int] $FitterSeed = 10
)

$ErrorActionPreference = "Stop"

$project = Split-Path -Parent $PSScriptRoot
$quartusBin = "C:\intelFPGA_lite\17.0\quartus\bin64"
$quartusMap = Join-Path $quartusBin "quartus_map.exe"
$quartusFit = Join-Path $quartusBin "quartus_fit.exe"
$quartusAsm = Join-Path $quartusBin "quartus_asm.exe"
$quartusSta = Join-Path $quartusBin "quartus_sta.exe"
$revision = "Arcade-Gladiator"

function Invoke-QuartusStage {
    param(
        [Parameter(Mandatory = $true)] [string] $Tool,
        [Parameter(Mandatory = $true)] [string] $Stage,
        [Parameter(Mandatory = $true)] [string[]] $Arguments
    )

    if (-not (Test-Path -LiteralPath $Tool)) {
        throw "Missing Quartus $Stage tool: $Tool"
    }

    Write-Host "[build-quartus] starting $Stage"
    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Quartus $Stage failed with exit code $LASTEXITCODE."
    }
}

function Assert-LineBuffersUseMlab {
    param([Parameter(Mandatory = $true)] [string] $Report)

    if (-not (Test-Path -LiteralPath $Report)) {
        throw "Quartus map did not produce the expected report: $Report"
    }

    # Require the actual memory-implementation table rows, not only an HDL
    # attribute or an inference message. The old broken build carried an MLAB
    # attribute but implemented both buffers as ~5,120 registers plus 256:1
    # muxes, so a source-text or parameter-only check would be vacuous.
    #
    # The RTL interface is 10 bits wide, but sprite palette indices are either
    # transparent zero or 0x100..0x1ff. Bit 9 is therefore provably zero and
    # Quartus 17 legitimately removes it, reporting a physical 256x9 MLAB.
    foreach ($buffer in @("line_buffer0", "line_buffer1")) {
        $pattern = (
            "gladiator_sprite_line:sprite_line.*{0}.*;" +
            "\s*MLAB\s*;\s*Simple Dual Port\s*;\s*256\s*;\s*9\s*;"
        ) -f $buffer
        $implemented = Select-String -LiteralPath $Report -Pattern $pattern
        if (-not $implemented) {
            throw (
                "$buffer did not map as a 256x9 simple-dual-port MLAB. " +
                "Aborting before fit; inspect $Report."
            )
        }
        Write-Host "[build-quartus] verified $buffer -> 256x9 MLAB"
    }
}

function Assert-CrtAdjustSourceContract {
    param(
        [Parameter(Mandatory = $true)] [string] $TopSource,
        [Parameter(Mandatory = $true)] [string] $ReadCeSource,
        [Parameter(Mandatory = $true)] [string] $QipSource
    )

    $top = Get-Content -LiteralPath $TopSource -Raw
    $readCe = Get-Content -LiteralPath $ReadCeSource -Raw
    $qip = Get-Content -LiteralPath $QipSource -Raw

    if ($top -notmatch "\.HPOS_MODE\s*\(\s*0\s*\)") {
        throw "Gladiator CRT Adjust must use SYNCSHIFT for its narrow raster."
    }
    if ($top -notmatch "\.COLOR_BITS\s*\(\s*5\s*\)") {
        throw "Gladiator CRT buffer must preserve its native RGB555 channels."
    }
    if ($top -notmatch "crt_hpos_code\s*<=\s*7'd62" -or
        $top -notmatch "crt_hpos_code\s*<=\s*7'd94" -or
        $top -notmatch "9'sd95") {
        throw "Gladiator CRT H-position is no longer clamped to safe -32..+62."
    }
    if ($top -notmatch "\.hs_ref_out\s*\(\s*crt_hs_ref\s*\)" -or
        $top -notmatch "\.hs_ref\s*\(\s*crt_hs_ref\s*\)") {
        throw "CRT read-rate reset is not wired from crt_adjust.hs_ref_out."
    }
    if ($readCe -notmatch "if\s*\(\s*hs_ref_rise\s*\)\s*\r?\n\s*accumulator\s*<=\s*8'd0") {
        throw "CRT read-rate accumulator no longer resets on hs_ref_out rise."
    }
    if ($qip -notmatch "rtl/video/crt_adjust\.sv" -or
        $qip -notmatch "rtl/video/gladiator_crt_read_ce\.sv") {
        throw "CRT Adjust synthesis sources are missing from files.qip."
    }
    if ($top -match "\bgladiator_frame_retimer\s+\w+\s*\(") {
        throw "A full-frame retimer was reintroduced into the Gladiator top."
    }

    Write-Host "[build-quartus] CRT source contract: native-frame core-side path"
}

function Assert-CrtBufferUsesM10k {
    param([Parameter(Mandatory = $true)] [string] $Report)

    $pattern = (
        "crt_adjust:crt_adjust.*mem_rtl_0.*;" +
        "\s*M10K block\s*;\s*Simple Dual Port\s*;" +
        "\s*1024\s*;\s*15\s*;"
    )
    if (-not (Select-String -LiteralPath $Report -Pattern $pattern)) {
        throw "CRT Adjust buffer did not map as a 1024x15 simple-dual-port M10K."
    }
    Write-Host "[build-quartus] CRT buffer implementation: 1024x15 M10K"
}

function Assert-EffectsMixSourceContract {
    param(
        [Parameter(Mandatory = $true)] [string] $TopSource,
        [Parameter(Mandatory = $true)] [string] $QipSource,
        [Parameter(Mandatory = $true)] [string] $BusSource,
        [Parameter(Mandatory = $true)] [string] $TrackerSource,
        [Parameter(Mandatory = $true)] [string] $MixerSource
    )

    $top = Get-Content -LiteralPath $TopSource -Raw
    $qip = Get-Content -LiteralPath $QipSource -Raw
    $bus = Get-Content -LiteralPath $BusSource -Raw
    $tracker = Get-Content -LiteralPath $TrackerSource -Raw
    $mixer = Get-Content -LiteralPath $MixerSource -Raw

    if ($top -notmatch
            "O\[73:72\],Sound Effects,\+6 dB,\+3 dB,Original,\+9 dB") {
        throw "Effects-level OSD option/default is absent from the top source."
    }
    if ($qip -notmatch "rtl/audio/gladiator_effect_tracker\.sv") {
        throw "Effects tracker synthesis source is missing from files.qip."
    }
    if ($bus -notmatch
            "mem_write_pulse\s*&&\s*cpu_address\s*==\s*16'h8002") {
        throw "Sound-ROM decoded-command tap is absent from the sound bus."
    }
    if ($tracker -notmatch "sound_command_data\s*>=\s*8'h10" -or
        $tracker -notmatch "sound_command_data\s*<\s*8'h60" -or
        $tracker -notmatch "ym_register\s*==\s*8'h28") {
        throw "FM-effect command/key-state classification contract is absent."
    }
    if ($mixer -notmatch "if\s*\(\s*!effect_active\s*\)" -or
        $mixer -notmatch "adpcm_scaled_q\s*<=") {
        throw "Effects-only mixer gain contract is absent."
    }

    Write-Host (
        "[build-quartus] effects mix contract: FM key-state boost, " +
        "speech path unchanged"
    )
}

function Assert-McuDmemGuard {
    param(
        [Parameter(Mandatory = $true)] [string] $Report,
        [Parameter(Mandatory = $true)] [string] $Source
    )

    $sourceText = Get-Content -LiteralPath $Source -Raw
    if ($sourceText -notmatch
            "if\s*\(\s*!dmem_write\s*\)\s*dmem_data_in\s*<=\s*dmem\[dmem_address\]") {
        throw (
            "MCU RAM write-edge hold guard is absent from $Source. " +
            "Aborting before fit."
        )
    }

    foreach ($mcu in @("cctl", "ccpu", "ucpu", "csnd")) {
        $pattern = (
            "gladiator_upi41_device:{0}.*dmem_rtl_0.*;" +
            "\s*MLAB\s*;\s*Simple Dual Port\s*;\s*256\s*;\s*8\s*;"
        ) -f $mcu
        $implemented = Select-String -LiteralPath $Report -Pattern $pattern
        if (-not $implemented) {
            throw (
                "$mcu dmem did not map as a 256x8 simple-dual-port MLAB. " +
                "Aborting before fit; inspect $Report."
            )
        }
        Write-Host "[build-quartus] verified $mcu dmem -> 256x8 MLAB"
    }
    Write-Host "[build-quartus] verified MCU dmem write-edge hold guard"
}

function Assert-DipLoaderGuard {
    param([Parameter(Mandatory = $true)] [string] $Source)

    $sourceText = Get-Content -LiteralPath $Source -Raw
    if ($sourceText -notmatch
            "ioctl_index\s*==\s*16'd254[\s\S]*!ioctl_addr\[26:2\]") {
        throw (
            "DIP transfer high-address guard is absent from $Source. " +
            "Main_MiSTer's eight-byte DIP payload would alias DSW1/2/3."
        )
    }
    Write-Host (
        "[build-quartus] verified DIP loader rejects addresses 4..7"
    )
}

function Assert-TimingClean {
    param([Parameter(Mandatory = $true)] [string] $Summary)

    if (-not (Test-Path -LiteralPath $Summary)) {
        throw "Quartus STA did not produce the expected summary: $Summary"
    }

    $slacks = @(
        Select-String -LiteralPath $Summary `
            -Pattern "^\s*Slack\s*:\s*(-?[0-9]+(?:\.[0-9]+)?)" |
            ForEach-Object { [double] $_.Matches[0].Groups[1].Value }
    )
    $tnsValues = @(
        Select-String -LiteralPath $Summary `
            -Pattern "^\s*TNS\s*:\s*(-?[0-9]+(?:\.[0-9]+)?)" |
            ForEach-Object { [double] $_.Matches[0].Groups[1].Value }
    )

    if ($slacks.Count -eq 0 -or $tnsValues.Count -eq 0) {
        throw "Could not parse slack/TNS from $Summary"
    }
    if (@($slacks | Where-Object { $_ -lt 0.0 }).Count -ne 0) {
        $summaryText = Get-Content -LiteralPath $Summary -Raw
        $detail = "negative slack"
        if ($summaryText -match (
                "(?ms)Type\s*:\s*Setup\s+'([^']+)'\s*" +
                "Slack\s*:\s*(-?[0-9]+(?:\.[0-9]+)?)"
            )) {
            $detail = "setup clock '$($Matches[1])' slack $($Matches[2]) ns"
        }
        throw "Timing failed: $detail."
    }
    if (@($tnsValues | Where-Object { $_ -ne 0.0 }).Count -ne 0) {
        throw "Timing failed: $Summary contains non-zero TNS."
    }

    $worstSlack = ($slacks | Measure-Object -Minimum).Minimum
    Write-Host "[build-quartus] timing clean: worst reported slack $worstSlack ns, all TNS 0"
}

Push-Location $project
try {
    Assert-CrtAdjustSourceContract `
        -TopSource (Join-Path $project "Arcade-Gladiator.sv") `
        -ReadCeSource (Join-Path $project "rtl\video\gladiator_crt_read_ce.sv") `
        -QipSource (Join-Path $project "files.qip")
    Assert-EffectsMixSourceContract `
        -TopSource (Join-Path $project "Arcade-Gladiator.sv") `
        -QipSource (Join-Path $project "files.qip") `
        -BusSource (Join-Path $project "rtl\memory\gladiator_sound_bus.sv") `
        -TrackerSource (Join-Path $project "rtl\audio\gladiator_effect_tracker.sv") `
        -MixerSource (Join-Path $project "rtl\audio\gladiator_audio_mixer.sv")

    # quartus_sh --flow compile normally runs sys/build_id.tcl before mapping.
    # This staged flow maps first so it can fail fast on RAM inference, so
    # preserve the only build-affecting pre-flow result explicitly.
    $buildDate = Get-Date -Format "yyMMdd"
    $buildIdFile = Join-Path $project "build_id.v"
    Set-Content -LiteralPath $buildIdFile -Encoding Ascii -NoNewline `
        -Value ('`define BUILD_DATE "{0}"' -f $buildDate)
    Write-Host "[build-quartus] build date: $buildDate"

    Invoke-QuartusStage -Tool $quartusMap -Stage "map" -Arguments @(
        $revision,
        "--read_settings_files=on",
        "--write_settings_files=off"
    )

    $mapReport = Join-Path $project "output_files\$revision.map.rpt"
    Assert-LineBuffersUseMlab -Report $mapReport
    Assert-CrtBufferUsesM10k -Report $mapReport
    Assert-McuDmemGuard -Report $mapReport -Source (
        Join-Path $project "rtl\gladiator_upi41_device.sv"
    )
    Assert-DipLoaderGuard -Source (
        Join-Path $project "rtl\gladiator_dip_loader.sv"
    )

    Invoke-QuartusStage -Tool $quartusFit -Stage "fit" -Arguments @(
        $revision,
        "--seed=$FitterSeed",
        "--read_settings_files=off",
        "--write_settings_files=off"
    )
    Invoke-QuartusStage -Tool $quartusAsm -Stage "assembly" -Arguments @(
        $revision
    )
    Invoke-QuartusStage -Tool $quartusSta -Stage "timing analysis" -Arguments @(
        $revision
    )

    $staSummary = Join-Path $project "output_files\$revision.sta.summary"
    Assert-TimingClean -Summary $staSummary

    $compiledRbf = Join-Path $project "output_files\$revision.rbf"
    $releaseRbf = Join-Path $project "output_files\Gladiator.rbf"
    $candidateRbf = Join-Path $project "output_files\$ReleaseBaseName.rbf"
    if (-not (Test-Path -LiteralPath $compiledRbf)) {
        throw "Quartus did not produce the expected RBF: $compiledRbf"
    }

    Copy-Item -LiteralPath $compiledRbf -Destination $releaseRbf -Force
    Copy-Item -LiteralPath $compiledRbf -Destination $candidateRbf -Force
    $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidateRbf).Hash.ToLowerInvariant()
    $shaFile = "$candidateRbf.sha256"
    Set-Content -LiteralPath $shaFile -Encoding Ascii `
        -Value ("{0}  {1}" -f $sha256, (Split-Path -Leaf $candidateRbf))
    Write-Host "[build-quartus] candidate: $candidateRbf"
    Write-Host "[build-quartus] sha256: $sha256"
    Write-Host "[build-quartus] checksum file: $shaFile"
}
finally {
    Pop-Location
}
