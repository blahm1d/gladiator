$ErrorActionPreference = "Stop"

$project = Split-Path -Parent $PSScriptRoot
$iverilog = "C:\iverilog\bin\iverilog.exe"
$output = Join-Path $project "sim\out\emu-syntax.vvp"

if (-not (Test-Path $iverilog)) {
    throw "Icarus executable not found: $iverilog"
}

New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force |
    Out-Null
$sources = Get-ChildItem (Join-Path $project "rtl") -Recurse -File |
    Where-Object { $_.Extension -in ".sv", ".v" } |
    ForEach-Object { $_.FullName }

Push-Location $project
try {
    $ErrorActionPreference = "Continue"
    $compileOutput = & $iverilog -g2012 -i -s emu -I. -I.\sys `
        -o $output .\Arcade-Gladiator.sv @sources 2>&1
    $compileExitCode = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    if ($compileExitCode -ne 0) {
        $compileOutput | Write-Host
        throw "MiSTer wrapper syntax integration failed."
    }
    Write-Host "PASS emu SystemVerilog integration syntax"
}
finally {
    Pop-Location
}
