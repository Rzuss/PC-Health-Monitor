# PC-Cleanup-Rotem.ps1
# Performance scan and cleanup script
# Run with PowerShell as Administrator for best results

$ErrorActionPreference = "SilentlyContinue"
$ReportPath = "$env:USERPROFILE\Desktop\PC-Report-$(Get-Date -Format 'yyyy-MM-dd_HH-mm').txt"
$report = @()

function Write-Header($text) {
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
}

function Write-Section($text) {
    Write-Host "`n--- $text ---" -ForegroundColor Yellow
}

function Ask-Confirm($question) {
    Write-Host "`n$question" -ForegroundColor Magenta
    Write-Host "[Y] Yes   [N] No   [S] Stop all" -ForegroundColor White
    $answer = Read-Host "Choice"
    return $answer.ToUpper()
}

# ============================================================
# 1. System Overview
# ============================================================
Write-Header "1. SYSTEM OVERVIEW"

$os     = Get-CimInstance Win32_OperatingSystem
$cpu    = Get-CimInstance Win32_Processor
$totalRAM = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
$freeRAM  = [math]::Round($os.FreePhysicalMemory  / 1MB, 2)
$usedRAM  = [math]::Round($totalRAM - $freeRAM, 2)
$ramPct   = [math]::Round(($usedRAM / $totalRAM) * 100, 1)

Write-Host "  OS           : $($os.Caption)" -ForegroundColor White
Write-Host "  CPU          : $($cpu.Name)" -ForegroundColor White
Write-Host "  Total RAM    : $totalRAM GB" -ForegroundColor White
$ramColor = if ($ramPct -gt 80) {"Red"} elseif ($ramPct -gt 60) {"Yellow"} else {"Green"}
Write-Host "  RAM Used     : $usedRAM GB ($ramPct pct)" -ForegroundColor $ramColor

$report += "PC Performance Report - $env:COMPUTERNAME - $(Get-Date)"
$report += "=" * 60
$report += "OS: $($os.Caption)"
$report += "CPU: $($cpu.Name)"
$report += "RAM Used: $usedRAM GB / $totalRAM GB ($ramPct pct)"

Write-Section "Disk Usage"
$disks = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 }
foreach ($disk in $disks) {
    $used  = [math]::Round($disk.Used / 1GB, 1)
    $free  = [math]::Round($disk.Free / 1GB, 1)
    $total = $used + $free
    $pct   = if ($total -gt 0) { [math]::Round(($used / $total) * 100, 1) } else { 0 }
    $diskColor = if ($pct -gt 90) {"Red"} elseif ($pct -gt 75) {"Yellow"} else {"Green"}
    Write-Host "  Drive $($disk.Name): $used GB / $total GB used ($pct pct full)" -ForegroundColor $diskColor
    $report += "Drive $($disk.Name): $used/$total GB ($pct pct)"
}

# ============================================================
# 2. Top CPU and RAM Processes
# ============================================================
Write-Header "2. TOP PROCESSES"

Write-Section "Top 15 by CPU"
$topCPU = Get-Process | Sort-Object CPU -Descending | Select-Object -First 15 `
    Name, Id,
    @{N="CPU_sec";  E={[math]::Round($_.CPU, 1)}},
    @{N="RAM_MB";   E={[math]::Round($_.WorkingSet64 / 1MB, 1)}}

$topCPU | Format-Table -AutoSize | Out-Host
$report += "`n[Top 15 by CPU]"
$report += ($topCPU | Format-Table -AutoSize | Out-String)

Write-Section "Top 15 by RAM"
$topRAM = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 `
    Name, Id,
    @{N="RAM_MB";  E={[math]::Round($_.WorkingSet64 / 1MB, 1)}},
    @{N="CPU_sec"; E={[math]::Round($_.CPU, 1)}}

$topRAM | Format-Table -AutoSize | Out-Host
$report += "`n[Top 15 by RAM]"
$report += ($topRAM | Format-Table -AutoSize | Out-String)

# ============================================================
# 3. Startup Programs
# ============================================================
Write-Header "3. STARTUP PROGRAMS"

$startupItems = @()

$regHKCU = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" 2>$null
if ($regHKCU) {
    $regHKCU.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" } | ForEach-Object {
        $startupItems += [PSCustomObject]@{ Source="HKCU"; Name=$_.Name; Path=$_.Value }
    }
}

$regHKLM = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" 2>$null
if ($regHKLM) {
    $regHKLM.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" } | ForEach-Object {
        $startupItems += [PSCustomObject]@{ Source="HKLM"; Name=$_.Name; Path=$_.Value }
    }
}

$startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
Get-ChildItem $startupFolder -ErrorAction SilentlyContinue | ForEach-Object {
    $startupItems += [PSCustomObject]@{ Source="Folder"; Name=$_.Name; Path=$_.FullName }
}

if ($startupItems.Count -gt 0) {
    $startupItems | Format-Table Source, Name, Path -AutoSize -Wrap | Out-Host
    Write-Host "  Total startup items: $($startupItems.Count)" -ForegroundColor Yellow
} else {
    Write-Host "  No startup items found." -ForegroundColor Green
}

$report += "`n[Startup Programs]"
$report += ($startupItems | Format-Table Source, Name, Path -AutoSize | Out-String)

# ============================================================
# 4. Junk / Temp Files Scan
# ============================================================
Write-Header "4. JUNK FILE SCAN"

$junkPaths = @(
    @{ Label="User Temp";        Path=$env:TEMP },
    @{ Label="Windows Temp";     Path="C:\Windows\Temp" },
    @{ Label="Prefetch";         Path="C:\Windows\Prefetch" },
    @{ Label="IE/Edge Cache";    Path="$env:LOCALAPPDATA\Microsoft\Windows\INetCache" },
    @{ Label="Recycle Bin";      Path="C:\`$Recycle.Bin" },
    @{ Label="WU Download";      Path="C:\Windows\SoftwareDistribution\Download" },
    @{ Label="Thumbnail Cache";  Path="$env:LOCALAPPDATA\Microsoft\Windows\Explorer" }
)

$totalJunkMB = 0

foreach ($item in $junkPaths) {
    $sizeMB = 0
    $count  = 0
    if (Test-Path $item.Path) {
        $files  = Get-ChildItem $item.Path -Recurse -Force -ErrorAction SilentlyContinue
        $count  = $files.Count
        $sizeMB = [math]::Round(($files | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB, 1)
        $totalJunkMB += $sizeMB
    }
    $junkColor = if ($sizeMB -gt 500) {"Red"} elseif ($sizeMB -gt 100) {"Yellow"} else {"Green"}
    Write-Host ("  {0,-20} : {1,8} MB  ({2} files)" -f $item.Label, $sizeMB, $count) -ForegroundColor $junkColor
    $report += ("{0,-20} : {1} MB  ({2} files)" -f $item.Label, $sizeMB, $count)
}

$totalJunkGB = [math]::Round($totalJunkMB / 1024, 2)
Write-Host "`n  >>> TOTAL JUNK: $totalJunkGB GB <<<" -ForegroundColor Red
$report += "TOTAL JUNK: $totalJunkGB GB"

# ============================================================
# 5. Largest Files on C:
# ============================================================
Write-Header "5. LARGEST FILES ON C:"
Write-Host "  Scanning... (may take a few seconds)" -ForegroundColor Gray

$bigFiles = Get-ChildItem "C:\" -Recurse -Force -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -gt 100MB } |
    Sort-Object Length -Descending |
    Select-Object -First 20 `
        @{N="Size_GB"; E={[math]::Round($_.Length/1GB,2)}},
        @{N="Name";    E={$_.Name}},
        @{N="Folder";  E={$_.DirectoryName}}

if ($bigFiles) {
    $bigFiles | Format-Table -AutoSize | Out-Host
} else {
    Write-Host "  No files larger than 100MB found." -ForegroundColor Green
}

$report += "`n[Files larger than 100MB]"
$report += ($bigFiles | Format-Table -AutoSize | Out-String)

# ============================================================
# 6. Save Report
# ============================================================
Write-Header "6. SAVING REPORT"
$report | Out-File $ReportPath -Encoding UTF8
Write-Host "  Report saved to: $ReportPath" -ForegroundColor Green

# ============================================================
# 7. Cleanup Actions (ask before each)
# ============================================================
Write-Header "7. CLEANUP ACTIONS"

Write-Host "`n  The script will ask for approval before each action." -ForegroundColor White
Write-Host "  Choose Y (yes), N (no), or S (stop all).`n" -ForegroundColor White

# Action 1: User Temp
$ans = Ask-Confirm "Action 1: Delete User Temp files?`n  Path: $env:TEMP`n  [Safe - old temporary files]"
if ($ans -eq "Y") {
    $deleted = 0; $errors = 0
    Get-ChildItem $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-Item $_.FullName -Force -Recurse -ErrorAction Stop; $deleted++ }
        catch { $errors++ }
    }
    Write-Host "  Deleted: $deleted items | Skipped (in use): $errors" -ForegroundColor Green
} elseif ($ans -eq "S") { Write-Host "  Stopping." -ForegroundColor Gray; Read-Host "Press Enter to exit"; exit }
else { Write-Host "  Skipped." -ForegroundColor Gray }

# Action 2: Windows Temp
$ans = Ask-Confirm "Action 2: Delete Windows Temp files?`n  Path: C:\Windows\Temp`n  [Requires Admin]"
if ($ans -eq "Y") {
    $deleted = 0; $errors = 0
    Get-ChildItem "C:\Windows\Temp" -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-Item $_.FullName -Force -Recurse -ErrorAction Stop; $deleted++ }
        catch { $errors++ }
    }
    Write-Host "  Deleted: $deleted items | Skipped: $errors" -ForegroundColor Green
} elseif ($ans -eq "S") { Read-Host "Press Enter to exit"; exit }
else { Write-Host "  Skipped." -ForegroundColor Gray }

# Action 3: Internet Cache
$ans = Ask-Confirm "Action 3: Clear Internet Cache?`n  Path: INetCache`n  [Safe]"
if ($ans -eq "Y") {
    $deleted = 0; $errors = 0
    Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\INetCache" -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-Item $_.FullName -Force -Recurse -ErrorAction Stop; $deleted++ }
        catch { $errors++ }
    }
    Write-Host "  Deleted: $deleted items | Skipped: $errors" -ForegroundColor Green
} elseif ($ans -eq "S") { Read-Host "Press Enter to exit"; exit }
else { Write-Host "  Skipped." -ForegroundColor Gray }

# Action 4: Windows Update Cache
$ans = Ask-Confirm "Action 4: Clear Windows Update Download Cache?`n  [Can free 2-10 GB | Requires Admin]"
if ($ans -eq "Y") {
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $deleted = 0; $errors = 0
    Get-ChildItem "C:\Windows\SoftwareDistribution\Download" -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-Item $_.FullName -Force -Recurse -ErrorAction Stop; $deleted++ }
        catch { $errors++ }
    }
    Start-Service wuauserv -ErrorAction SilentlyContinue
    Write-Host "  Deleted: $deleted items | Skipped: $errors" -ForegroundColor Green
} elseif ($ans -eq "S") { Read-Host "Press Enter to exit"; exit }
else { Write-Host "  Skipped." -ForegroundColor Gray }

# Action 5: Recycle Bin
$ans = Ask-Confirm "Action 5: Empty the Recycle Bin?`n  [IRREVERSIBLE]"
if ($ans -eq "Y") {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Write-Host "  Recycle Bin emptied." -ForegroundColor Green
} elseif ($ans -eq "S") { Read-Host "Press Enter to exit"; exit }
else { Write-Host "  Skipped." -ForegroundColor Gray }

# Action 6: Disk Cleanup GUI
$ans = Ask-Confirm "Action 6: Open Windows Disk Cleanup (cleanmgr)?`n  [Opens a graphical window for you to choose]"
if ($ans -eq "Y") {
    Start-Process cleanmgr -ArgumentList "/d C:" -Wait
    Write-Host "  Disk Cleanup launched." -ForegroundColor Green
} elseif ($ans -eq "S") { Read-Host "Press Enter to exit"; exit }
else { Write-Host "  Skipped." -ForegroundColor Gray }

# ============================================================
# Done
# ============================================================
Write-Header "DONE"
Write-Host "`n  Cleanup complete." -ForegroundColor Green
Write-Host "  Full report saved to your Desktop:" -ForegroundColor White
Write-Host "  $ReportPath" -ForegroundColor Cyan
Write-Host "`n  Tip: Open Task Manager -> Startup tab to disable unnecessary programs." -ForegroundColor White

Read-Host "`nPress Enter to exit"
