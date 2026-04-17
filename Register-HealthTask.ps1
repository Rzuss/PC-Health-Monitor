# Register-HealthTask.ps1
# Registers two daily Windows Scheduled Tasks:
#   PC-Health-Monitor Analytics  — health_analyzer.py  at 03:00 AM
#   PC-Health-Monitor Baseline   — baseline_engine.py  at 03:05 AM

$ErrorActionPreference = 'Stop'

try {
    # Locate Python executable
    $PythonCmd = Get-Command python -ErrorAction Stop
    $PythonPath = $PythonCmd.Source

    $InstallDir  = Join-Path $env:LOCALAPPDATA 'PC-Health-Monitor'
    $ScriptDest  = Join-Path $InstallDir 'health_analyzer.py'

    # Ensure install dir exists
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    # Copy health_analyzer.py from script's own directory if not yet in install dir
    $SourceScript = Join-Path $PSScriptRoot 'health_analyzer.py'
    if ((Test-Path $SourceScript) -and (-not (Test-Path $ScriptDest))) {
        Copy-Item -Path $SourceScript -Destination $ScriptDest -Force
        Write-Host "  [COPY] health_analyzer.py -> $ScriptDest" -ForegroundColor Gray
    }

    # Build task components
    $Action = New-ScheduledTaskAction `
        -Execute        $PythonPath `
        -Argument       'health_analyzer.py' `
        -WorkingDirectory $InstallDir

    $Trigger = New-ScheduledTaskTrigger -Daily -At '03:00'

    $Settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit        (New-TimeSpan -Minutes 10) `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable:$false `
        -MultipleInstances         IgnoreNew

    $Principal = New-ScheduledTaskPrincipal `
        -UserId    $env:USERNAME `
        -LogonType Interactive `
        -RunLevel  Limited

    $Task = New-ScheduledTask `
        -Action      $Action `
        -Trigger     $Trigger `
        -Settings    $Settings `
        -Principal   $Principal `
        -Description 'PC Health Monitor predictive analytics -- generates health_report.json'

    Register-ScheduledTask `
        -TaskName   'PC-Health-Monitor Analytics' `
        -InputObject $Task `
        -Force | Out-Null

    # ----------------------------------------------------------------
    # Task 2 — Baseline Engine (03:05 AM, 5 minutes after analytics)
    # ----------------------------------------------------------------
    $BaselineSrc  = Join-Path $PSScriptRoot 'baseline_engine.py'
    $BaselineDest = Join-Path $InstallDir   'baseline_engine.py'
    if ((Test-Path $BaselineSrc) -and (-not (Test-Path $BaselineDest))) {
        Copy-Item -Path $BaselineSrc -Destination $BaselineDest -Force
        Write-Host "  [COPY] baseline_engine.py -> $BaselineDest" -ForegroundColor Gray
    }

    $Action2 = New-ScheduledTaskAction `
        -Execute          $PythonPath `
        -Argument         'baseline_engine.py' `
        -WorkingDirectory $InstallDir

    $Trigger2 = New-ScheduledTaskTrigger -Daily -At '03:05'

    $Task2 = New-ScheduledTask `
        -Action      $Action2 `
        -Trigger     $Trigger2 `
        -Settings    $Settings `
        -Principal   $Principal `
        -Description 'PC Health Monitor behavioral baseline engine -- detects process anomalies'

    Register-ScheduledTask `
        -TaskName    'PC-Health-Monitor Baseline' `
        -InputObject $Task2 `
        -Force | Out-Null

    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor DarkCyan
    Write-Host "   Scheduled tasks registered successfully!"    -ForegroundColor Green
    Write-Host ""
    Write-Host "   [1] PC-Health-Monitor Analytics"             -ForegroundColor Cyan
    Write-Host "       Schedule : Daily at 03:00 AM"            -ForegroundColor Cyan
    Write-Host "       Script   : $ScriptDest"                  -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   [2] PC-Health-Monitor Baseline"              -ForegroundColor Cyan
    Write-Host "       Schedule : Daily at 03:05 AM"            -ForegroundColor Cyan
    Write-Host "       Script   : $BaselineDest"                -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   Python : $PythonPath"                        -ForegroundColor Gray
    Write-Host "  ============================================" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Run now to build first baseline:" -ForegroundColor Gray
    Write-Host "    python `"$BaselineDest`"" -ForegroundColor White
    Write-Host ""

} catch [System.Management.Automation.CommandNotFoundException] {
    Write-Host ""
    Write-Host "  [ERROR] Python not found on PATH." -ForegroundColor Red
    Write-Host "          Install Python 3.x and ensure it is added to PATH." -ForegroundColor Yellow
    Write-Host "          Download: https://www.python.org/downloads/"        -ForegroundColor Yellow
    Write-Host ""
    exit 1
} catch {
    Write-Host ""
    Write-Host "  [ERROR] Failed to register scheduled task:" -ForegroundColor Red
    Write-Host "          $_" -ForegroundColor Red
    Write-Host "          Try running this script as Administrator."           -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
