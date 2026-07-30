$ErrorActionPreference = "Stop"

$project = Split-Path -Parent $PSScriptRoot

Push-Location $project
try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File .\scripts\run-mame-full-trace.ps1 `
        -Frames 18000 -SnapshotPeriod 60 -ScreenshotPeriod 600 `
        -StartingStage 1 -TraceUntilFrame 3600
    & python .\scripts\check_mame_progression.py
    if ($LASTEXITCODE -ne 0) {
        throw "MAME deterministic progression regression failed."
    }
    & python .\scripts\check_mame_audio_trace.py
    if ($LASTEXITCODE -ne 0) {
        throw "MAME audio-oracle regression failed."
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File .\scripts\run-unit.ps1
    & powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File .\scripts\run-mame.ps1
    & powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File .\scripts\run-mame-first-video.ps1
    & powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File .\scripts\run-questa.ps1
    & python .\scripts\compare_boot_traces.py
    if ($LASTEXITCODE -ne 0) {
        throw "MAME/RTL instruction comparison failed."
    }
    & python .\scripts\compare_bus_traces.py
    if ($LASTEXITCODE -ne 0) {
        throw "MAME/RTL ordered write comparison failed."
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File .\scripts\check-emu-syntax.ps1
    Write-Host "PASS complete non-Quartus regression"
}
finally {
    Pop-Location
}
