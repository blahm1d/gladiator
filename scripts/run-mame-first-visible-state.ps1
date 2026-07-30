$ErrorActionPreference = "Stop"

$project = Split-Path -Parent $PSScriptRoot
$mame = "C:\ProgramData\chocolatey\bin\mame.exe"
$out = Join-Path $project "sim\out"
$state = Join-Path $out "mame-first-visible-state.txt"
$stdout = Join-Path $out "mame-first-visible-stdout.log"
$stderr = Join-Path $out "mame-first-visible-stderr.log"
$nvram = Join-Path $out "mame-first-visible-nvram"
$cfg = Join-Path $out "mame-first-visible-cfg"

if (-not (Test-Path -LiteralPath $mame)) {
    throw "MAME executable not found: $mame"
}

New-Item -ItemType Directory -Path $out, $nvram, $cfg -Force | Out-Null
if (Test-Path -LiteralPath $state) {
    Remove-Item -LiteralPath $state -Force
}

$arguments = @(
    "gladiatr",
    "-rompath", "roms",
    "-noreadconfig",
    "-nvram_directory", $nvram,
    "-cfg_directory", $cfg,
    "-nonvram_save",
    "-video", "none",
    "-sound", "none",
    "-nothrottle",
    "-noplugins",
    "-skip_gameinfo",
    "-autoboot_delay", "0",
    "-autoboot_script", "sim/mame/gladiatr_first_visible_state.lua",
    "-seconds_to_run", "10"
)

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $mame
$startInfo.Arguments = ($arguments | ForEach-Object {
    '"' + ([string] $_).Replace('"', '\"') + '"'
}) -join ' '
$startInfo.WorkingDirectory = $project
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
if (-not $process.Start()) {
    throw "Failed to start MAME."
}
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
if (-not $process.WaitForExit(60000)) {
    try {
        $process.Kill()
        $process.WaitForExit()
    }
    finally {
        $process.Dispose()
    }
    throw "Headless MAME first-visible capture exceeded 60 seconds."
}
$exitCode = $process.ExitCode
[System.IO.File]::WriteAllText($stdout, $stdoutTask.Result)
[System.IO.File]::WriteAllText($stderr, $stderrTask.Result)
$process.Dispose()

if ($exitCode -ne 0) {
    throw "Headless MAME first-visible capture failed. See $stderr"
}
if (-not (Test-Path -LiteralPath $state) -or
        (Get-Item -LiteralPath $state).Length -lt 26000) {
    throw "MAME did not produce a complete first-visible state capture."
}

$metadata = Get-Content -LiteralPath $state -TotalCount 10
Write-Host "PASS MAME first-visible board-state capture"
$metadata | Where-Object { $_ -notmatch "^(sprite|state)_" } |
    ForEach-Object { Write-Host "  $_" }
