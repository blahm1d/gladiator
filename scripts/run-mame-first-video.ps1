$ErrorActionPreference = "Stop"

$project = Split-Path -Parent $PSScriptRoot
$mame = "C:\ProgramData\chocolatey\bin\mame.exe"
$debugLog = Join-Path $project "debug.log"
$resultLog = Join-Path $project "sim\out\mame-first-video.log"

if (-not (Test-Path $mame)) {
    throw "MAME executable not found: $mame"
}

$arguments = @(
    "gladiatr",
    "-rompath", "roms",
    "-noreadconfig",
    "-nvram_directory", "sim/out/mame-nvram",
    "-cfg_directory", "sim/out/mame-cfg",
    "-nonvram_save",
    "-debug",
    "-debugger", "windows",
    "-debuglog",
    "-debugscript", "sim/mame/gladiatr_first_video.cmd",
    "-video", "none",
    "-sound", "none",
    "-nothrottle",
    "-noplugins",
    "-skip_gameinfo"
)

$quotedArguments = ($arguments | ForEach-Object {
    '"' + ([string]$_).Replace('"', '\"') + '"'
}) -join ' '
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $mame
$startInfo.Arguments = $quotedArguments
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
    throw "Headless MAME first-video probe exceeded 60 seconds."
}
$exitCode = $process.ExitCode
$process.Dispose()

if ($exitCode -ne 0) {
    throw "Headless MAME first-video probe failed: $($stderrTask.Result)"
}
if (-not (Test-Path $debugLog)) {
    throw "MAME did not produce debug.log."
}

$debugText = [System.IO.File]::ReadAllText($debugLog)
[System.IO.File]::WriteAllText($resultLog, $debugText)
if ($debugText -notmatch "FIRST_VIDEO_ENABLE pc=04CB data=2C") {
    throw "MAME did not reach the expected first visible-display write."
}

$timeMatch = [regex]::Match(
    $debugText,
    "(?m)^([0-9]+\.[0-9]+)\s*$"
)
if (-not $timeMatch.Success) {
    throw "MAME first-video probe did not report emulated time."
}

Write-Host (
    "PASS MAME first video enable: CC80=2C at " +
    $timeMatch.Groups[1].Value + " s"
)
