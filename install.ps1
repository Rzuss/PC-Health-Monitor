# install.ps1 -- PC Health Monitor one-liner installer
# Usage: irm https://raw.githubusercontent.com/Rzuss/PC-Health-Monitor/main/install.ps1 | iex

$ErrorActionPreference = 'Stop'

# -- ExecutionPolicy check -----------------------------------------------
# irm ... | iex runs in-memory and bypasses file-based policy restrictions,
# so the installer itself will run fine. However, we verify the policy so
# the shortcut we create can always launch the .ps1 on disk without friction.
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -eq 'Restricted' -or $policy -eq 'AllSigned') {
    Write-Host ""
    Write-Host "  [INFO] ExecutionPolicy is '$policy' for your user account." -ForegroundColor Yellow
    Write-Host "         Setting it to RemoteSigned so the shortcut can launch the app." -ForegroundColor Yellow
    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Write-Host "  [OK]  ExecutionPolicy set to RemoteSigned (CurrentUser)." -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] Could not change ExecutionPolicy: $_" -ForegroundColor Yellow
        Write-Host "         The Desktop shortcut uses -ExecutionPolicy Bypass and will still work." -ForegroundColor Gray
    }
}
# ------------------------------------------------------------------------

$InstallDir  = Join-Path $env:LOCALAPPDATA 'PC-Health-Monitor'
$ScriptUrl   = 'https://raw.githubusercontent.com/Rzuss/PC-Health-Monitor/main/PC-Health-Monitor.ps1'
$ScriptDest  = Join-Path $InstallDir 'PC-Health-Monitor.ps1'
$ShortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'PC Health Monitor.lnk'

# Step 1 -- Create install directory
try {
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
} catch {
    Write-Host "[ERROR] Failed to create install directory: $_" -ForegroundColor Red
    exit 1
}

# Step 2 -- Download main script
try {
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($ScriptUrl, $ScriptDest)
} catch {
    Write-Host "[ERROR] Failed to download script: $_" -ForegroundColor Red
    if (Test-Path $ScriptDest) { Remove-Item $ScriptDest -Force -ErrorAction SilentlyContinue }
    exit 1
}

# Step 2.5 -- Install Python analytics dependencies (optional)
try {
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        & python -m pip install pandas numpy --quiet --exists-action i 2>&1 | Out-Null
        Write-Host "  [OK] Python + pandas + numpy ready for health analytics." -ForegroundColor Cyan
    } else {
        Write-Host "  [SKIP] Python not found -- Health Score card will show pending state." -ForegroundColor Yellow
        Write-Host "         Install Python from https://www.python.org to enable analytics." -ForegroundColor Gray
    }
} catch {
    Write-Host "  [WARN] Could not verify Python packages: $_" -ForegroundColor Yellow
}

# Step 3 -- Create Desktop shortcut
try {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath  = 'powershell.exe'
    $Shortcut.Arguments   = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptDest`""
    $Shortcut.WorkingDirectory = $InstallDir
    $Shortcut.IconLocation = "$env:SystemRoot\System32\perfmon.exe,0"
    $Shortcut.Description  = 'PC Health Monitor - Live System Dashboard'
    $Shortcut.Save()
} catch {
    Write-Host "[ERROR] Failed to create Desktop shortcut: $_" -ForegroundColor Red
    exit 1
}

# Step 4 -- Print success banner
Write-Host ""
Write-Host "  ======================================" -ForegroundColor DarkCyan
Write-Host "   PC Health Monitor installed!" -ForegroundColor Green
Write-Host "   Shortcut created on Desktop." -ForegroundColor Cyan
Write-Host "   Run as Administrator for full" -ForegroundColor Gray
Write-Host "   cleanup access." -ForegroundColor Gray
Write-Host "  ======================================" -ForegroundColor DarkCyan
Write-Host ""
