$ErrorActionPreference = "Stop"

$IncludeQuartus = $args -contains "-IncludeQuartus"

$tools = @(
    @{
        Name = "Questa"
        Candidates = @(
            "C:\altera\25.1std\questa_fse\win64\vsim.exe",
            "C:\intelFPGA_lite\17.0\modelsim_ase\win32aloem\vsim.exe"
        )
        Args = @("-version")
    },
    @{
        Name = "Icarus"
        Candidates = @("C:\iverilog\bin\iverilog.exe")
        Args = @("-V")
    },
    @{
        Name = "MAME"
        Candidates = @("C:\ProgramData\chocolatey\bin\mame.exe")
        Args = @("-version")
    },
    @{
        Name = "Python"
        Candidates = @("C:\Python314\python.exe", "python.exe")
        Args = @("--version")
    }
)

if ($IncludeQuartus) {
    $tools = @(
        @{
            Name = "Quartus 17.0.2"
            Candidates = @(
                "C:\intelFPGA_lite\17.0\quartus\bin64\quartus_sh.exe",
                "C:\intelFPGA_lite\17.0\quartus\bin\quartus_sh.exe"
            )
            Args = @("--version")
        }
    ) + $tools
}

$failed = $false
foreach ($tool in $tools) {
    $path = $tool.Candidates |
        Where-Object { (Test-Path $_) -or (Get-Command $_ -ErrorAction SilentlyContinue) } |
        Select-Object -First 1

    if (-not $path) {
        Write-Host ("MISSING  {0}" -f $tool.Name)
        $failed = $true
        continue
    }

    $version = (& $path @($tool.Args) 2>&1 | Select-Object -First 1)
    Write-Host ("OK       {0}: {1}" -f $tool.Name, $version)
}

if ($failed) {
    throw "One or more required tools were not found."
}
