$ErrorActionPreference = "Stop"

$project = Split-Path -Parent $PSScriptRoot
$mame = "C:\ProgramData\chocolatey\bin\mame.exe"
$out = Join-Path $project "sim\out"
$state = Join-Path $out "mame-first-sprite-pass-state.txt"
$stdout = Join-Path $out "mame-first-sprite-pass-stdout.log"
$stderr = Join-Path $out "mame-first-sprite-pass-stderr.log"
$nvram = Join-Path $out "mame-first-sprite-pass-nvram"
$cfg = Join-Path $out "mame-first-sprite-pass-cfg"

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
    "-autoboot_script", "sim/mame/gladiatr_first_sprite_pass_state.lua",
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
    throw "Headless MAME first-sprite-pass capture exceeded 60 seconds."
}
$exitCode = $process.ExitCode
[System.IO.File]::WriteAllText($stdout, $stdoutTask.Result)
[System.IO.File]::WriteAllText($stderr, $stderrTask.Result)
$process.Dispose()

if ($exitCode -ne 0) {
    throw "Headless MAME first-sprite-pass capture failed. See $stderr"
}
if (-not (Test-Path -LiteralPath $state) -or
        (Get-Item -LiteralPath $state).Length -lt 26000) {
    throw "MAME did not produce a complete first-sprite-pass state capture."
}

$metadata = Get-Content -LiteralPath $state -TotalCount 11
Write-Host "PASS MAME first complete C000-CBFF sprite-RAM sweep capture"
$metadata | Where-Object { $_ -notmatch "^(sprite|state)_" } |
    ForEach-Object { Write-Host "  $_" }
