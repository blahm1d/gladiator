$ErrorActionPreference = "Stop"

$project = Split-Path -Parent $PSScriptRoot
$mame = "C:\ProgramData\chocolatey\bin\mame.exe"

if (-not (Test-Path $mame)) {
    throw "MAME executable not found: $mame"
}

$nvram = Join-Path $project "sim\out\mame-nvram"
$cfg = Join-Path $project "sim\out\mame-cfg"
New-Item -ItemType Directory -Path $nvram, $cfg -Force | Out-Null

function Invoke-MameTrace {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Script,
        [Parameter(Mandatory)] [string] $Trace
    )

    $tracePath = Join-Path $project $Trace
    if (Test-Path -LiteralPath $tracePath) {
        Remove-Item -LiteralPath $tracePath -Force
    }

    $arguments = @(
        "gladiatr",
        "-rompath", "roms",
        "-noreadconfig",
        "-nvram_directory", $nvram,
        "-cfg_directory", $cfg,
        "-nonvram_save",
        "-debug",
        "-debugger", "windows",
        "-debuglog",
        "-debugscript", $Script,
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
        throw "Headless MAME trace exceeded 60 seconds."
    }
    $exitCode = $process.ExitCode
    [System.IO.File]::WriteAllText(
        (Join-Path $project "sim\out\mame-$Name-stdout.log"),
        $stdoutTask.Result
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $project "sim\out\mame-$Name-stderr.log"),
        $stderrTask.Result
    )
    $process.Dispose()

    if ($exitCode -ne 0) {
        throw "Headless MAME trace failed for $Name."
    }

    if (-not (Test-Path -LiteralPath $tracePath) -or
        (Get-Item -LiteralPath $tracePath).Length -eq 0) {
        throw "MAME did not produce trace: $Trace"
    }
    $traceLines = (Get-Content -LiteralPath $tracePath |
        Measure-Object -Line).Lines
    if ($traceLines -ne 10000) {
        throw "MAME $Name trace has $traceLines instructions, expected 10000."
    }

    # Watchpoint actions emit normalized write events to MAME's debugger log.
    # Preserve them beside the instruction trace before the next CPU-domain
    # invocation overwrites debug.log.
    $eventPath = Join-Path $project "sim\out\mame-$Name-bus-events.csv"
    $eventRows = @()
    $debugLog = Join-Path $project "debug.log"
    if (Test-Path -LiteralPath $debugLog) {
        $eventRows = @(Get-Content -LiteralPath $debugLog |
            Where-Object { $_.StartsWith("BUS,") } |
            ForEach-Object { $_.Substring(4) })
    }
    [System.IO.File]::WriteAllLines(
        $eventPath,
        @("domain,kind,address,data") + $eventRows
    )
}

Push-Location $project
try {
    Invoke-MameTrace -Name "main" `
        -Script "sim/mame/gladiatr_boot.cmd" `
        -Trace "sim/out/mame-main.tr"
    Invoke-MameTrace -Name "sound" `
        -Script "sim/mame/gladiatr_sound_boot.cmd" `
        -Trace "sim/out/mame-sound.tr"
    Invoke-MameTrace -Name "6809" `
        -Script "sim/mame/gladiatr_6809_boot.cmd" `
        -Trace "sim/out/mame-6809.tr"
    Invoke-MameTrace -Name "csnd" `
        -Script "sim/mame/gladiatr_csnd_boot.cmd" `
        -Trace "sim/out/mame-csnd.tr"

    $csndTrace = Get-Content -LiteralPath (
        Join-Path $project "sim\out\mame-csnd.tr"
    )
    if ($csndTrace[0] -notmatch '^001:' -or
            $csndTrace[-1] -notmatch '^050:\s+jnibf\s+\$050') {
        throw "MAME CSND trace did not enter the expected IBF wait state."
    }
}
finally {
    Pop-Location
}
