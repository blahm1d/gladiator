param(
    [int] $Frames = 3600,
    [int] $SnapshotPeriod = 60,
    [int] $ScreenshotPeriod = 300,
    [ValidateRange(1, 4)] [int] $StartingStage = 1,
    [int] $TraceUntilFrame = 0,
    # Run the machine's OWN attract cycle: no coin, no start, no play
    # inputs, factory DIPs. The scripted run coins up at frame 360 and
    # so never reaches the title screen.
    [switch] $Attract
)

$ErrorActionPreference = "Stop"

$project = Split-Path -Parent $PSScriptRoot
$mame = "C:\ProgramData\chocolatey\bin\mame.exe"
$out = Join-Path $project "sim\out"
$nvram = Join-Path $out "mame-full-nvram"
$cfg = Join-Path $out "mame-full-cfg"
$snap = Join-Path $out "mame-full-snap"
$stdout = Join-Path $out "mame-full-stdout.log"
$stderr = Join-Path $out "mame-full-stderr.log"
$wav = Join-Path $out "mame-full-audio.wav"

if (-not (Test-Path -LiteralPath $mame)) {
    throw "MAME executable not found: $mame"
}

New-Item -ItemType Directory -Path $out, $nvram, $cfg, $snap -Force |
    Out-Null

foreach ($name in @(
    "mame-full-events.csv",
    "mame-full-frames.csv",
    "mame-sprite-snapshots.csv",
    "mame-state-snapshots.csv",
    "mame-full-audio.wav"
)) {
    $path = Join-Path $out $name
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

$arguments = @(
    "gladiatr",
    "-rompath", "roms",
    "-noreadconfig",
    "-nvram_directory", $nvram,
    "-cfg_directory", $cfg,
    "-snapshot_directory", $snap,
    "-nonvram_save",
    "-video", "none",
    "-sound", "none",
    "-nothrottle",
    "-noplugins",
    "-skip_gameinfo",
    "-autoboot_delay", "0",
    "-autoboot_script", "sim/mame/gladiatr_full_trace.lua",
    "-seconds_to_run", [string] ([Math]::Ceiling($Frames / 60.0) + 10),
    "-wavwrite", $wav
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
    "GLADIATR_TRACE_FRAMES",
    "Process")
$oldSnapshotPeriod = [Environment]::GetEnvironmentVariable(
    "GLADIATR_SNAPSHOT_PERIOD",
    "Process")
$oldScreenshotPeriod = [Environment]::GetEnvironmentVariable(
    "GLADIATR_SCREENSHOT_PERIOD",
    "Process")
$oldStartingStage = [Environment]::GetEnvironmentVariable(
    "GLADIATR_START_STAGE",
    "Process")
$oldTraceUntilFrame = [Environment]::GetEnvironmentVariable(
    "GLADIATR_TRACE_UNTIL_FRAME",
    "Process")
try {
    [Environment]::SetEnvironmentVariable(
        "GLADIATR_ATTRACT",
        $(if ($Attract) { "1" } else { "0" }),
        "Process")
    [Environment]::SetEnvironmentVariable(
        "GLADIATR_TRACE_FRAMES",
        [string] $Frames,
        "Process")
    [Environment]::SetEnvironmentVariable(
        "GLADIATR_SNAPSHOT_PERIOD",
        [string] $SnapshotPeriod,
        "Process")
    [Environment]::SetEnvironmentVariable(
        "GLADIATR_SCREENSHOT_PERIOD",
        [string] $ScreenshotPeriod,
        "Process")
    [Environment]::SetEnvironmentVariable(
        "GLADIATR_START_STAGE",
        [string] $StartingStage,
        "Process")
    [Environment]::SetEnvironmentVariable(
        "GLADIATR_TRACE_UNTIL_FRAME",
        [string] $(if ($TraceUntilFrame -gt 0) {
            $TraceUntilFrame
        } else {
            $Frames
        }),
        "Process")
    if (-not $process.Start()) {
        throw "Failed to start MAME."
    }
}
finally {
    [Environment]::SetEnvironmentVariable(
        "GLADIATR_TRACE_FRAMES",
        $oldTraceFrames,
        "Process")
    [Environment]::SetEnvironmentVariable(
        "GLADIATR_SNAPSHOT_PERIOD",
        $oldSnapshotPeriod,
        "Process")
    [Environment]::SetEnvironmentVariable(
        "GLADIATR_SCREENSHOT_PERIOD",
        $oldScreenshotPeriod,
        "Process")
    [Environment]::SetEnvironmentVariable(
        "GLADIATR_START_STAGE",
        $oldStartingStage,
        "Process")
    [Environment]::SetEnvironmentVariable(
        "GLADIATR_TRACE_UNTIL_FRAME",
        $oldTraceUntilFrame,
        "Process")
}
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()

$timeoutMilliseconds = 60000
if (-not $process.WaitForExit($timeoutMilliseconds)) {
    try {
        $process.Kill()
        $process.WaitForExit()
    }
    finally {
        $process.Dispose()
    }
    throw "Headless MAME full trace exceeded the bounded timeout."
}

$exitCode = $process.ExitCode
[System.IO.File]::WriteAllText($stdout, $stdoutTask.Result)
[System.IO.File]::WriteAllText($stderr, $stderrTask.Result)
$process.Dispose()

if ($exitCode -ne 0) {
    throw "Headless MAME full trace failed. See $stderr"
}

$required = @(
    "mame-full-events.csv",
    "mame-full-frames.csv",
    "mame-sprite-snapshots.csv",
    "mame-state-snapshots.csv",
    "mame-full-audio.wav"
)
foreach ($name in $required) {
    $path = Join-Path $out $name
    if (-not (Test-Path -LiteralPath $path) -or
            (Get-Item -LiteralPath $path).Length -eq 0) {
        throw "MAME full trace did not produce $name"
    }
}

$lastFrame = Import-Csv (Join-Path $out "mame-full-frames.csv") |
    Select-Object -Last 1
if (-not $lastFrame -or [int] $lastFrame.frame -lt
        ($Frames - $SnapshotPeriod)) {
    throw "MAME full trace ended before the requested frame."
}

Write-Host ((
    "PASS MAME deterministic trace through frame {0}: " +
    "{1} board events, {2} sprite snapshots") -f
    $lastFrame.frame,
    ((Get-Content (Join-Path $out "mame-full-events.csv") |
        Measure-Object -Line).Lines - 1),
    ((Get-Content (Join-Path $out "mame-sprite-snapshots.csv") |
        Measure-Object -Line).Lines - 1)
)
