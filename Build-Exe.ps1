# Build-Exe.ps1 -- Compiles PC-Health-Monitor.ps1 into a standalone .exe
# Requires PS2EXE module. Run from the repo root.

$ErrorActionPreference = 'Stop'

# Step 1 -- Ensure PS2EXE is available
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "[INFO] ps2exe not found. Installing..." -ForegroundColor Cyan
    try {
        Install-Module ps2exe -Scope CurrentUser -Force
    } catch {
        Write-Host "[ERROR] Failed to install ps2exe: $_" -ForegroundColor Red
        exit 1
    }
}

# Step 2 -- Create output directory
$DistDir = Join-Path $PSScriptRoot 'dist'
if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
}

$InputFile  = Join-Path $PSScriptRoot 'PC-Health-Monitor.ps1'
$OutputFile = Join-Path $DistDir 'PC-Health-Monitor.exe'
$IconFile   = Join-Path $PSScriptRoot 'assets\icon.ico'

# Step 3 -- Build parameters
$ps2exeParams = @{
    InputFile  = $InputFile
    OutputFile = $OutputFile
    NoConsole  = $true
    Title      = 'PC Health Monitor'
    Version    = '1.0.0'
}

if (Test-Path $IconFile) {
    $ps2exeParams['IconFile'] = $IconFile
    Write-Host "[INFO] Using icon: $IconFile" -ForegroundColor Gray
}

# Step 4 -- Compile
Write-Host "[INFO] Compiling $InputFile..." -ForegroundColor Cyan
try {
    Invoke-PS2EXE @ps2exeParams
    Write-Host "[OK]  Output: $OutputFile" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Compilation failed: $_" -ForegroundColor Red
    exit 1
}
