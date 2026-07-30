param(
    [int] $Frames = 5400
)

$ErrorActionPreference = "Stop"

$project = Split-Path -Parent $PSScriptRoot
$mame = "C:\ProgramData\chocolatey\bin\mame.exe"
$out = Join-Path $project "sim\out"
$nvram = Join-Path $out "mame-mcu-dual-nvram"
$cfg = Join-Path $out "mame-mcu-dual-cfg"
$output = Join-Path $out "mame-mcu-dual-host.csv"
$stdout = Join-Path $out "mame-mcu-dual-stdout.log"
$stderr = Join-Path $out "mame-mcu-dual-stderr.log"

if (-not (Test-Path -LiteralPath $mame)) {
    throw "MAME executable not found: $mame"
}

New-Item -ItemType Directory -Path $out, $nvram, $cfg -Force | Out-Null
if (Test-Path -LiteralPath $output) {
    Remove-Item -LiteralPath $output -Force
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
    "-autoboot_script", "sim/mame/gladiatr_mcu_dual_host.lua",
    "-seconds_to_run", [string] ([Math]::Ceiling($Frames / 60.0) + 10)
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
$oldTraceFrames = [Environment]::GetEnvironmentVariable(
    "GLADIATR_MCU_TRACE_FRAMES",
    "Process")
try {
    [Environment]::SetEnvironmentVariable(
        "GLADIATR_MCU_TRACE_FRAMES",
        [string] $Frames,
        "Process")
    if (-not $process.Start()) {
        throw "Failed to start MAME."
    }
}
finally {
    [Environment]::SetEnvironmentVariable(
        "GLADIATR_MCU_TRACE_FRAMES",
        $oldTraceFrames,
        "Process")
}
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()

if (-not $process.WaitForExit(120000)) {
    try {
        $process.Kill()
        $process.WaitForExit()
    }
    finally {
        $process.Dispose()
    }
    throw "Headless MAME MCU capture exceeded the bounded timeout."
}

$exitCode = $process.ExitCode
[System.IO.File]::WriteAllText($stdout, $stdoutTask.Result)
[System.IO.File]::WriteAllText($stderr, $stderrTask.Result)
$process.Dispose()

if ($exitCode -ne 0) {
    throw "Headless MAME MCU capture failed. See $stderr"
}
if (-not (Test-Path -LiteralPath $output) -or
        (Get-Item -LiteralPath $output).Length -eq 0) {
    throw "MAME did not produce $output"
}

$rows = Import-Csv -LiteralPath $output
$last = $rows | Select-Object -Last 1
if (-not $last -or [int] $last.frame -lt ($Frames - 2)) {
    throw "MAME MCU capture ended before the requested frame."
}
$ucpu = @($rows | Where-Object { $_.domain -eq "U" }).Count
$csnd = @($rows | Where-Object { $_.domain -eq "C" }).Count
if ($ucpu -eq 0 -or $csnd -eq 0) {
    throw "MAME MCU capture missed a required host domain."
}

Write-Host (
    "PASS dual MCU host capture through frame {0}: UCPU={1}, CSND={2}" -f
    $last.frame, $ucpu, $csnd)
