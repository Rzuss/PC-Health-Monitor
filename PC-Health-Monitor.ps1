# PC-Health-Monitor.ps1
# Full Windows Forms GUI -- Cyber-HUD Dark Theme -- Live Auto-Refresh

# CATCH BLOCK AUDIT: Found 9 empty catch blocks on the main thread
# Runspace catch blocks: 1 (inside $cleanBtn.Add_Click Runspace -- handled via $errCount counter, Write-Log not callable from Runspace)
# Main thread catch blocks: 9 empty (all refactored with Write-Log) + 2 with existing logic (augmented with Write-Log)

#region 1 - Logging Engine
$script:LogPath = "$env:TEMP\PCHealth-Monitor.log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO',
        [System.Management.Automation.ErrorRecord]$ExceptionRecord = $null
    )

    # ROTATION: if log > 512KB, archive it before writing
    if (Test-Path $script:LogPath) {
        $logFile = Get-Item $script:LogPath -ErrorAction SilentlyContinue
        if ($logFile -and $logFile.Length -gt 524288) {
            $archiveName = "$env:TEMP\PCHealth-Monitor-$(Get-Date -Format 'yyyyMMdd').log"
            Rename-Item -Path $script:LogPath -NewName $archiveName -Force -ErrorAction SilentlyContinue
        }
    }

    # SESSION HEADER: if log file does not exist yet, write a header line
    if (-not (Test-Path $script:LogPath)) {
        $header = "=== PC Health Monitor | Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | OS: $([System.Environment]::OSVersion.VersionString) | PS: $($PSVersionTable.PSVersion) ==="
        $header | Out-File -FilePath $script:LogPath -Encoding UTF8 -ErrorAction SilentlyContinue
    }

    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"

    if ($ExceptionRecord) {
        $entry += " | Exception: $($ExceptionRecord.Exception.Message)"
        $entry += " | At: $($ExceptionRecord.InvocationInfo.ScriptName):$($ExceptionRecord.InvocationInfo.ScriptLineNumber)"
    }

    $entry | Out-File -FilePath $script:LogPath -Append -Encoding UTF8 -ErrorAction SilentlyContinue
}
#endregion

#region 2 - Global Styles & Tokens
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms.DataVisualization
[System.Windows.Forms.Application]::EnableVisualStyles()

# Global monospace fonts
$script:MonoFont = New-Object Drawing.Font("Consolas", 9)
$script:MonoBold = New-Object Drawing.Font("Consolas", 9, [Drawing.FontStyle]::Bold)
$script:UIFont   = New-Object Drawing.Font("Segoe UI",  9)

# -- Admin Check ---------------------------------------------------------
$script:isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

# -- Color Palette -------------------------------------------------------
$C = @{
    BgBase     = [Drawing.Color]::FromArgb(2,   6,   23)
    BgCard     = [Drawing.Color]::FromArgb(10,  18,  40)
    BgCard2    = [Drawing.Color]::FromArgb(18,  30,  58)
    BgCard3    = [Drawing.Color]::FromArgb(15,  23,  42)
    Blue       = [Drawing.Color]::FromArgb(56,  189, 248)
    BlueGlow   = [Drawing.Color]::FromArgb(30,  100, 160)
    Purple     = [Drawing.Color]::FromArgb(168, 85,  247)
    PurpleGlow = [Drawing.Color]::FromArgb(80,  40,  130)
    Green      = [Drawing.Color]::FromArgb(74,  222, 128)
    Yellow     = [Drawing.Color]::FromArgb(250, 204, 21)
    Red        = [Drawing.Color]::FromArgb(248, 113, 113)
    Orange     = [Drawing.Color]::FromArgb(251, 146, 60)
    Text       = [Drawing.Color]::FromArgb(226, 232, 240)
    SubText    = [Drawing.Color]::FromArgb(148, 163, 184)
    Dim        = [Drawing.Color]::FromArgb(71,  85,  105)
    White      = [Drawing.Color]::White
    DarkRed    = [Drawing.Color]::FromArgb(185, 40,  60)
    DarkGreen  = [Drawing.Color]::FromArgb(30,  140, 70)
    Border     = [Drawing.Color]::FromArgb(30,  50,  80)
}

# -- Protected Process Blacklist -----------------------------------------
$script:ProtectedProcesses = @(
    'explorer','wininit','winlogon','csrss','smss','lsass',
    'services','svchost','system','registry','dwm','fontdrvhost',
    'SecurityHealthService','MsMpEng'
)
#endregion

#region 3 - UI Helper Functions
# -- Helper Functions ----------------------------------------------------
function New-Lbl($txt, $x, $y, $w, $h, $sz=9, $bold=$false, $col=$null) {
    $l = New-Object Windows.Forms.Label
    $l.Text      = $txt
    $l.Location  = [Drawing.Point]::new($x, $y)
    $l.Size      = [Drawing.Size]::new($w, $h)
    $l.FlatStyle = "Flat"
    $st = if ($bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }
    $l.Font      = New-Object Drawing.Font("Segoe UI", $sz, $st)
    $l.ForeColor = if ($col) { $col } else { $C.Text }
    $l.BackColor = [Drawing.Color]::Transparent
    return $l
}

function New-Btn($txt, $x, $y, $w, $h, $bg, $fg) {
    $b = New-Object Windows.Forms.Button
    $b.Text      = $txt
    $b.Location  = [Drawing.Point]::new($x, $y)
    $b.Size      = [Drawing.Size]::new($w, $h)
    $b.BackColor = $bg
    $b.ForeColor = $fg
    $b.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(
        [math]::Min($bg.R+30,255), [math]::Min($bg.G+30,255), [math]::Min($bg.B+30,255))
    $b.Font   = New-Object Drawing.Font("Consolas", 9, [Drawing.FontStyle]::Bold)
    $b.Cursor = [Windows.Forms.Cursors]::Hand
    return $b
}

function New-Pnl($x, $y, $w, $h, $col) {
    $p = New-Object Windows.Forms.Panel
    $p.Location  = [Drawing.Point]::new($x, $y)
    $p.Size      = [Drawing.Size]::new($w, $h)
    $p.BackColor = $col
    return $p
}

function Style-Grid($g) {
    $g.BackgroundColor    = $C.BgCard
    $g.ForeColor          = $C.Text
    $g.GridColor          = $C.Border
    $g.BorderStyle        = [Windows.Forms.BorderStyle]::None
    $g.RowHeadersVisible  = $false
    $g.ReadOnly           = $true
    $g.AllowUserToAddRows = $false
    $g.AllowUserToDeleteRows = $false
    $g.SelectionMode      = [Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $g.ColumnHeadersDefaultCellStyle.BackColor  = $C.BgCard3
    $g.ColumnHeadersDefaultCellStyle.ForeColor  = $C.Blue
    $g.ColumnHeadersDefaultCellStyle.Font       = New-Object Drawing.Font("Consolas", 9, [Drawing.FontStyle]::Bold)
    $g.ColumnHeadersHeightSizeMode = [Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::DisableResizing
    $g.ColumnHeadersHeight = 32
    $g.DefaultCellStyle.BackColor          = $C.BgCard
    $g.DefaultCellStyle.ForeColor          = $C.Text
    $g.DefaultCellStyle.Font               = New-Object Drawing.Font("Consolas", 9)
    $g.DefaultCellStyle.SelectionBackColor = $C.BgCard2
    $g.DefaultCellStyle.SelectionForeColor = $C.Blue
    $g.DefaultCellStyle.Padding            = New-Object Windows.Forms.Padding(4,0,4,0)
    $g.AlternatingRowsDefaultCellStyle.BackColor = $C.BgCard2
    $g.Font = New-Object Drawing.Font("Consolas", 9)
    $g.RowTemplate.Height = 26
    $g.EnableHeadersVisualStyles = $false
}

function Add-Col($grid, $header, $fillW=100) {
    $col = New-Object Windows.Forms.DataGridViewTextBoxColumn
    $col.HeaderText = $header
    $col.Name       = $header
    $col.FillWeight = $fillW
    $col.ReadOnly   = $true
    [void]$grid.Columns.Add($col)
}

# -- GDI+ Helpers --------------------------------------------------------
function Draw-CircleGauge {
    param($Graphics, $CenterX, $CenterY, $Radius, $Pct, $Color, $TrackColor, $Thick = 6)
    $rect = [Drawing.RectangleF]::new($CenterX - $Radius, $CenterY - $Radius, $Radius * 2, $Radius * 2)
    $trackPen = New-Object Drawing.Pen($TrackColor, $Thick)
    $trackPen.StartCap = [Drawing.Drawing2D.LineCap]::Round
    $trackPen.EndCap   = [Drawing.Drawing2D.LineCap]::Round
    $Graphics.DrawArc($trackPen, $rect, -90, 360)
    $sweep = [math]::Max(0, [math]::Min(360, ($Pct / 100) * 360))
    if ($sweep -gt 2) {
        $pen = New-Object Drawing.Pen($Color, $Thick)
        $pen.StartCap = [Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap   = [Drawing.Drawing2D.LineCap]::Round
        $Graphics.DrawArc($pen, $rect, -90, $sweep)
    }
    $font  = New-Object Drawing.Font("Consolas", 8, [Drawing.FontStyle]::Bold)
    $label = "$([math]::Round($Pct))%"
    $sf = New-Object Drawing.StringFormat
    $sf.Alignment      = [Drawing.StringAlignment]::Center
    $sf.LineAlignment  = [Drawing.StringAlignment]::Center
    $brush    = New-Object Drawing.SolidBrush($Color)
    $textRect = [Drawing.RectangleF]::new($CenterX - $Radius, $CenterY - $Radius, $Radius * 2, $Radius * 2)
    $Graphics.DrawString($label, $font, $brush, $textRect, $sf)
}

function Draw-GlowBorder {
    param($Graphics, $Width, $Height, $AccentColor, $AccentThick = 2)
    $borderPen = New-Object Drawing.Pen($C.Border, 1)
    $Graphics.DrawRectangle($borderPen, 0, 0, $Width - 1, $Height - 1)
    $accentPen = New-Object Drawing.Pen($AccentColor, $AccentThick)
    $Graphics.DrawLine($accentPen, 0, 0, $Width, 0)
}

# -- Color helper for pct values -----------------------------------------
function Pct-Color($pct) {
    if ($pct -gt 85) { return $C.Red    }
    elseif ($pct -gt 65) { return $C.Yellow }
    else { return $C.Green }
}

function Temp-Color($temp) {
    if ($null -eq $temp) { return $C.SubText }
    if ($temp -ge 80)    { return $C.Red     }
    if ($temp -ge 60)    { return $C.Yellow  }
    return $C.Green
}
#endregion

#region 4 - Core Logic & Telemetry
# -- Initial data collection ---------------------------------------------
$os       = Get-CimInstance Win32_OperatingSystem
$cpuInfo  = Get-CimInstance Win32_Processor
$totalRAM = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)

function Get-LiveData {
    $osNow  = Get-CimInstance Win32_OperatingSystem -Property FreePhysicalMemory
    $cpuNow = Get-CimInstance Win32_Processor -Property LoadPercentage
    $diskC  = Get-PSDrive C

    $freeRAM = [math]::Round($osNow.FreePhysicalMemory / 1MB, 1)
    $usedRAM = [math]::Round($script:totalRAM - $freeRAM, 1)
    $ramPct  = [math]::Round(($usedRAM / $script:totalRAM) * 100)

    $dUsed  = [math]::Round($diskC.Used / 1GB, 1)
    $dFree  = [math]::Round($diskC.Free / 1GB, 1)
    $dTotal = [math]::Round(($diskC.Used + $diskC.Free) / 1GB, 1)
    $dPct   = [math]::Round(($dUsed / $dTotal) * 100)

    return @{
        CpuPct  = [int]$cpuNow.LoadPercentage
        UsedRAM = $usedRAM
        RamPct  = $ramPct
        DUsed   = $dUsed
        DFree   = $dFree
        DTotal  = $dTotal
        DPct    = $dPct
    }
}

function Get-HardwareTemps {
    # Queries LibreHardwareMonitor WMI namespace (LHM must be running).
    # Returns @{Available=$false} gracefully when LHM is not running or not installed.
    try {
        $sensors = Get-CimInstance -Namespace root\LibreHardwareMonitor `
                                  -ClassName Sensor -Filter "SensorType='Temperature'" `
                                  -ErrorAction Stop
        if (-not $sensors) { return @{Available=$false; CPU=$null; GPU=$null} }

        $cpu = $sensors | Where-Object { $_.Name -match 'CPU' } |
               Sort-Object Value -Descending | Select-Object -First 1
        $gpu = $sensors | Where-Object { $_.Name -match 'GPU' } |
               Sort-Object Value -Descending | Select-Object -First 1

        return @{
            Available = $true
            CPU       = if ($cpu) { [math]::Round($cpu.Value, 1) } else { $null }
            GPU       = if ($gpu) { [math]::Round($gpu.Value, 1) } else { $null }
        }
    } catch {
        Write-Log -Message 'LHM WMI not available' -Level WARN -ExceptionRecord $_
        return @{Available=$false; CPU=$null; GPU=$null}
    }
}

function Get-NetworkConnections {
    try {
        $conns = Get-NetTCPConnection -ErrorAction Stop
        $procs = Get-Process -ErrorAction SilentlyContinue | Select-Object Id, ProcessName
        $procMap = @{}
        foreach ($p in $procs) { $procMap[$p.Id] = $p.ProcessName }

        $result = foreach ($c in $conns) {
            [PSCustomObject]@{
                Process   = if ($procMap[$c.OwningProcess]) { $procMap[$c.OwningProcess] } else { 'System' }
                PID       = $c.OwningProcess
                LocalPort = $c.LocalPort
                RemoteIP  = if ($c.RemoteAddress) { $c.RemoteAddress.ToString() } else { '--' }
                State     = $c.State.ToString()
                IsSuspect = ($c.State -ne 'Listen') -and
                            ($c.RemoteAddress -notmatch
                            '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.|::1|$)')
            }
        }
        return $result |
               Sort-Object @{E={if ($_.State -eq 'Established') {0} else {1}}}, Process |
               Select-Object -First 50
    } catch {
        Write-Log 'Failed to query network connections' -Level ERROR -ExceptionRecord $_
        return @()
    }
}

function Get-BandwidthStats {
    # Queries network bytes/sec via Performance Counters. Graceful locale fallback.
    try {
        $sentSamples = (Get-Counter '\Network Interface(*)\Bytes Sent/sec' -ErrorAction Stop).CounterSamples
        $recvSamples = (Get-Counter '\Network Interface(*)\Bytes Received/sec' -ErrorAction Stop).CounterSamples
        $sent = ($sentSamples | Measure-Object -Property CookedValue -Sum).Sum
        $recv = ($recvSamples | Measure-Object -Property CookedValue -Sum).Sum
        return @{
            Available = $true
            SentKBps  = [math]::Round($sent / 1KB, 1)
            RecvKBps  = [math]::Round($recv / 1KB, 1)
        }
    } catch {
        return @{Available=$false; SentKBps=0; RecvKBps=0}
    }
}

function Get-SecurityAudit {
    $audit = @{ Defender = @{}; Firewall = @{}; Updates = 0; Ports = @() }

    # Defender
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $audit.Defender = @{
            Enabled      = $mp.AntivirusEnabled
            LastScan     = $mp.QuickScanEndTime
            SignatureAge = $mp.AntivirusSignatureAge
        }
    } catch { Write-Log -Message 'Defender query failed' -Level ERROR -ExceptionRecord $_ }

    # Firewall (stores boolean Enabled per profile)
    try {
        $fw = Get-NetFirewallProfile -ErrorAction Stop
        foreach ($p in $fw) { $audit.Firewall[$p.Name] = $p.Enabled }
    } catch { Write-Log -Message 'Firewall query failed' -Level ERROR -ExceptionRecord $_ }

    # Pending Updates via COM (may be slow; wrapped in try/catch)
    try {
        $searcher = New-Object -ComObject Microsoft.Update.Searcher -ErrorAction Stop
        $result   = $searcher.Search('IsInstalled=0 and Type=Software')
        $audit.Updates = $result.Updates.Count
    } catch { Write-Log -Message 'Windows Update query failed' -Level WARN -ExceptionRecord $_ }

    # Listening Ports (top 30, sorted by port)
    try {
        $listeners = Get-NetTCPConnection -State Listen -ErrorAction Stop
        $procs = Get-Process | Select-Object Id, ProcessName
        $pm = @{}; foreach ($p in $procs) { $pm[$p.Id] = $p.ProcessName }
        $audit.Ports = $listeners |
            Select-Object LocalPort,
                @{N='Process'; E={if ($pm[$_.OwningProcess]) { $pm[$_.OwningProcess] } else { 'System' }}},
                @{N='PID';     E={$_.OwningProcess}} |
            Sort-Object LocalPort | Select-Object -First 30
    } catch { Write-Log -Message 'Listening ports query failed' -Level WARN -ExceptionRecord $_ }

    return $audit
}

function Export-SystemReport {
    $ts   = Get-Date -Format 'yyyy-MM-dd_HH-mm'
    $path = Join-Path $env:USERPROFILE "Desktop\PCHealth-Report-$ts.html"
    $live = Get-LiveData
    $sec  = Get-SecurityAudit
    $portsHtml = ($sec.Ports | ForEach-Object {
        "<tr><td>$($_.LocalPort)</td><td>$($_.Process)</td><td>$($_.PID)</td></tr>"
    }) -join "`n"
    $html = @"
<!DOCTYPE html><html><head><meta charset='utf-8'>
<title>PC Health Report</title>
<style>body{background:#020617;color:#e2e8f0;font-family:Consolas,monospace;padding:20px}
h1{color:#38bdf8}h2{color:#a855f7;border-bottom:1px solid #1e3250;padding-bottom:4px}
table{border-collapse:collapse;width:100%;margin-bottom:20px}
th{background:#0a1228;color:#38bdf8;padding:8px;text-align:left}
td{padding:6px;border-bottom:1px solid #1e3250}
.ok{color:#4ade80}.warn{color:#facc15}.crit{color:#f87171}</style></head>
<body><h1>PC Health Monitor - System Report</h1>
<p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Host: $env:COMPUTERNAME</p>
<h2>System Overview</h2><table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>CPU Usage</td><td>$($live.CpuPct)%</td></tr>
<tr><td>RAM Usage</td><td>$($live.RamPct)%</td></tr>
<tr><td>Disk Usage</td><td>$($live.DPct)%</td></tr>
</table>
<h2>Security Status</h2><table>
$(if ($sec.Defender.Enabled) {'<tr><td>Defender</td><td class=ok>PROTECTED</td></tr>'} else {'<tr><td>Defender</td><td class=crit>DISABLED</td></tr>'})
<tr><td>Pending Updates</td><td>$($sec.Updates)</td></tr>
<tr><td>Firewall (Domain)</td><td $(if ($sec.Firewall.Domain)  {'class=ok>ON'} else {'class=crit>OFF'})></td></tr>
<tr><td>Firewall (Private)</td><td $(if ($sec.Firewall.Private) {'class=ok>ON'} else {'class=crit>OFF'})></td></tr>
<tr><td>Firewall (Public)</td><td $(if ($sec.Firewall.Public)  {'class=ok>ON'} else {'class=crit>OFF'})></td></tr>
</table>
<h2>Open Listening Ports</h2><table>
<tr><th>PORT</th><th>PROCESS</th><th>PID</th></tr>$portsHtml
</table>
<div style='color:#475569;font-size:0.8em;margin-top:24px'>PC Health Monitor -- https://github.com/Rzuss/PC-Health-Monitor</div>
</body></html>
"@
    try {
        $html | Out-File $path -Encoding UTF8 -ErrorAction Stop
        [System.Windows.Forms.MessageBox]::Show(
            "Report saved to Desktop:`n$path", 'Export Complete',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } catch {
        Write-Log -Message 'Export failed' -Level ERROR -ExceptionRecord $_
        [System.Windows.Forms.MessageBox]::Show(
            "Export failed: $($_.Exception.Message)", 'Error',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}

$live = Get-LiveData

# Startup items
$startups = @()
$runPaths = @(
    @{Hive="HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"; Source="User"},
    @{Hive="HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"; Source="System"}
)
foreach ($rp in $runPaths) {
    $reg = Get-ItemProperty $rp.Hive -EA SilentlyContinue
    if ($reg) {
        $reg.PSObject.Properties | Where-Object {$_.Name -notmatch "^PS"} | ForEach-Object {
            $startups += [PSCustomObject]@{Source=$rp.Source; Name=$_.Name; Command=$_.Value; RegPath=$rp.Hive}
        }
    }
}

# Junk file locations
$junkDefs = @(
    @{Name="User Temp Files";   Path=$env:TEMP},
    @{Name="Windows Temp";      Path="C:\Windows\Temp"},
    @{Name="Internet Cache";    Path="$env:LOCALAPPDATA\Microsoft\Windows\INetCache"},
    @{Name="Recycle Bin";       Path="C:\`$Recycle.Bin"},
    @{Name="WU Download Cache"; Path="C:\Windows\SoftwareDistribution\Download"},
    @{Name="Thumbnail Cache";   Path="$env:LOCALAPPDATA\Microsoft\Windows\Explorer"}
)
$junkItems = foreach ($j in $junkDefs) {
    $sz=0; $cnt=0
    if (Test-Path $j.Path) {
        $f   = Get-ChildItem $j.Path -Recurse -Force -EA SilentlyContinue
        $cnt = $f.Count
        $sz  = [math]::Round(($f | Measure-Object Length -Sum -EA SilentlyContinue).Sum / 1MB, 1)
    }
    [PSCustomObject]@{Name=$j.Name; SizeMB=$sz; Files=$cnt; Path=$j.Path}
}
$totalJunkGB = [math]::Round(($junkItems | Measure-Object SizeMB -Sum).Sum / 1024, 2)

# Cleanup locations that require administrator rights
$adminRequiredNames = @("Windows Temp", "WU Download Cache")

function Invoke-KillProcess {
    param([int]$Pid, [string]$ProcessName)

    # 1. BLACKLIST CHECK
    if ($script:ProtectedProcesses -contains $ProcessName.ToLower()) {
        [System.Windows.Forms.MessageBox]::Show(
            "'$ProcessName' is a critical system process and cannot be terminated.",
            "Protected Process",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    # 2. CONFIRMATION DIALOG (default button = No)
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Terminate process '$ProcessName' (PID: $Pid)?`n`nUnsaved work in this process will be lost.",
        "Confirm End Task",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    # 3. ATTEMPT TERMINATION
    try {
        Stop-Process -Id $Pid -Force -ErrorAction Stop
        Write-Log -Message "Process terminated: $ProcessName (PID: $Pid)" -Level INFO
        # 4. IMMEDIATE REFRESH on success
        Refresh-ProcessGrid
    } catch [System.ComponentModel.Win32Exception] {
        Write-Log -Message "Failed to terminate $ProcessName (PID: $Pid) -- Win32 permission error" -Level ERROR -ExceptionRecord $_
        $msg = if (-not $script:isAdmin) {
            "Cannot terminate '$ProcessName'.`n`nReason: Insufficient privileges.`nTip: Restart PC Health Monitor as Administrator."
        } else {
            "Cannot terminate '$ProcessName'.`n`nSystem error: $($_.Exception.Message)"
        }
        [System.Windows.Forms.MessageBox]::Show(
            $msg, "Termination Failed",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } catch {
        Write-Log -Message "Failed to terminate $ProcessName (PID: $Pid) -- process may have already exited" -Level WARN -ExceptionRecord $_
        [System.Windows.Forms.MessageBox]::Show(
            "Could not terminate '$ProcessName'. It may have already exited.`n`n$($_.Exception.Message)",
            "Termination Failed",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        Refresh-ProcessGrid   # refresh anyway -- process is gone
    }
}
#endregion

#region 5 - UI Initialization
# -- MAIN FORM -----------------------------------------------------------
$form = New-Object Windows.Forms.Form
$form.Text          = "PC Health Monitor - $env:COMPUTERNAME"
$form.Size          = [Drawing.Size]::new(1060, 720)
$form.MinimumSize   = [Drawing.Size]::new(1060, 720)
$form.BackColor     = $C.BgBase
$form.ForeColor     = $C.Text
$form.StartPosition = "CenterScreen"
$form.Font          = New-Object Drawing.Font("Segoe UI", 9)
try { $form.Icon = [Drawing.Icon]::ExtractAssociatedIcon("$env:SystemRoot\System32\perfmon.exe") } catch {
    Write-Log -Message "Failed to load form icon from perfmon.exe" -Level WARN -ExceptionRecord $_
    # Fallback: form retains default Windows icon
}

# -- Title Bar -----------------------------------------------------------
$titlePnl = New-Pnl 0 0 1060 64 $C.BgCard

$dotPnl = New-Object Windows.Forms.Panel
$dotPnl.Location  = [Drawing.Point]::new(12, 22)
$dotPnl.Size      = [Drawing.Size]::new(10, 10)
$dotPnl.BackColor = [Drawing.Color]::Transparent
$dotPnl.Add_Paint({
    param($s2, $pe)
    try {
        $pe.Graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $pe.Graphics.FillEllipse((New-Object Drawing.SolidBrush($C.Blue)), 0, 0, 8, 8)
    } catch {
        Write-Log -Message "dotPnl Paint error" -Level WARN -ExceptionRecord $_
        # Fallback: dot not rendered this frame
    }
})
$titlePnl.Controls.Add($dotPnl)

$titleMainLbl = New-Object Windows.Forms.Label
$titleMainLbl.Text      = "  PC Health Monitor"
$titleMainLbl.Location  = [Drawing.Point]::new(18, 6)
$titleMainLbl.Size      = [Drawing.Size]::new(500, 34)
$titleMainLbl.Font      = New-Object Drawing.Font("Consolas", 14, [Drawing.FontStyle]::Bold)
$titleMainLbl.ForeColor = $C.Blue
$titleMainLbl.BackColor = [Drawing.Color]::Transparent
$titlePnl.Controls.Add($titleMainLbl)

$subLbl = New-Object Windows.Forms.Label
$subLbl.Text      = "  $env:COMPUTERNAME   |   $($os.Caption)"
$subLbl.Location  = [Drawing.Point]::new(14, 42)
$subLbl.Size      = [Drawing.Size]::new(700, 18)
$subLbl.Font      = New-Object Drawing.Font("Segoe UI", 8)
$subLbl.ForeColor = $C.Dim
$subLbl.BackColor = [Drawing.Color]::Transparent
$titlePnl.Controls.Add($subLbl)

$lastUpdLbl = New-Object Windows.Forms.Label
$lastUpdLbl.Text      = "  Updated: just now"
$lastUpdLbl.Location  = [Drawing.Point]::new(706, 48)
$lastUpdLbl.Size      = [Drawing.Size]::new(250, 16)
$lastUpdLbl.Font      = New-Object Drawing.Font("Consolas", 7)
$lastUpdLbl.ForeColor = $C.Dim
$lastUpdLbl.BackColor = [Drawing.Color]::Transparent
$titlePnl.Controls.Add($lastUpdLbl)

$blinkDot = New-Object Windows.Forms.Panel
$blinkDot.Location  = [Drawing.Point]::new(690, 52)
$blinkDot.Size      = [Drawing.Size]::new(6, 6)
$blinkDot.BackColor = $C.Green
$titlePnl.Controls.Add($blinkDot)
$script:blinkState = $true

$refreshBtn = New-Object Windows.Forms.Button
$refreshBtn.Text      = "Refresh"
$refreshBtn.Location  = [Drawing.Point]::new(960, 15)
$refreshBtn.Size      = [Drawing.Size]::new(85, 34)
$refreshBtn.BackColor = $C.BgCard2
$refreshBtn.ForeColor = $C.Blue
$refreshBtn.FlatStyle = [Windows.Forms.FlatStyle]::Flat
$refreshBtn.FlatAppearance.BorderColor = $C.Border
$refreshBtn.FlatAppearance.BorderSize  = 1
$refreshBtn.Font      = New-Object Drawing.Font("Consolas", 9, [Drawing.FontStyle]::Bold)
$refreshBtn.Cursor    = [Windows.Forms.Cursors]::Hand
$titlePnl.Controls.Add($refreshBtn)

$titlePnl.Add_Paint({
    param($s2, $pe)
    try {
        $pe.Graphics.DrawLine(
            (New-Object Drawing.Pen($C.Border, 1)),
            0, $titlePnl.Height - 1, $titlePnl.Width, $titlePnl.Height - 1)
    } catch {
        Write-Log -Message "titlePnl Paint error" -Level WARN -ExceptionRecord $_
        # Fallback: bottom border line not rendered this frame
    }
})
$form.Controls.Add($titlePnl)

# -- Admin warning strip -------------------------------------------------
$tabsY = 64
$tabsH = 658
if (-not $script:isAdmin) {
    $warnPnl = New-Pnl 0 64 1060 22 ([Drawing.Color]::FromArgb(40, 35, 10))
    $warnPnl.Add_Paint({
        param($s2, $pe)
        try {
            $pe.Graphics.FillRectangle(
                (New-Object Drawing.SolidBrush($C.Yellow)), 0, 0, 3, $warnPnl.Height)
        } catch {
            Write-Log -Message "warnPnl Paint error" -Level WARN -ExceptionRecord $_
            # Fallback: yellow accent stripe not rendered this frame
        }
    })
    $warnLbl = New-Object Windows.Forms.Label
    $warnLbl.Text      = "   Running without Administrator rights - some features may be limited"
    $warnLbl.Location  = [Drawing.Point]::new(6, 3)
    $warnLbl.Size      = [Drawing.Size]::new(900, 16)
    $warnLbl.Font      = New-Object Drawing.Font("Consolas", 8)
    $warnLbl.ForeColor = $C.Yellow
    $warnLbl.BackColor = [Drawing.Color]::Transparent
    $warnPnl.Controls.Add($warnLbl)
    $form.Controls.Add($warnPnl)
    $tabsY = 86
    $tabsH = 636
}

# -- Tab Control ---------------------------------------------------------
$tabs = New-Object Windows.Forms.TabControl
$tabs.Location  = [Drawing.Point]::new(0, $tabsY)
$tabs.Size      = [Drawing.Size]::new(1060, $tabsH)
$tabs.BackColor = $C.BgBase
$tabs.ForeColor = $C.Text
$tabs.Font      = New-Object Drawing.Font("Segoe UI", 10)
$tabs.DrawMode  = [Windows.Forms.TabDrawMode]::OwnerDrawFixed
$tabs.ItemSize  = [Drawing.Size]::new(140, 28)
$form.Controls.Add($tabs)

# ========================================================================
# TAB 1 -- DASHBOARD
# ========================================================================
$tab1 = New-Object Windows.Forms.TabPage
$tab1.Text      = "  Dashboard  "
$tab1.BackColor = $C.BgBase

$UI = @{}

$cardDefs = @(
    @{Key="Cpu";  Title="CPU Load";  X=15;  Color=$C.Blue;   TrackColor=$C.BlueGlow;   Val="$($live.CpuPct)%";                                  Pct=$live.CpuPct},
    @{Key="Ram";  Title="RAM Usage"; X=280; Color=$C.Purple; TrackColor=$C.PurpleGlow; Val="$($live.UsedRAM) GB / $totalRAM GB";                Pct=$live.RamPct},
    @{Key="Disk"; Title="Disk C:";   X=545; Color=$C.Yellow; TrackColor=$C.BgCard2;    Val="$($live.DUsed) GB used  |  $($live.DFree) GB free"; Pct=$live.DPct}
)

foreach ($cd in $cardDefs) {
    $pct = [math]::Min([math]::Max($cd.Pct, 0), 100)
    $cp  = New-Pnl $cd.X 15 220 110 $C.BgCard

    # Store per-card paint data in Tag -- avoids closure capture issues
    $cp.Tag = @{ Color = $cd.Color; TrackColor = $cd.TrackColor; Pct = $pct }

    $cp.Add_Paint({
        param($s2, $pe)
        try {
            $g = $pe.Graphics
            $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.FillRectangle((New-Object Drawing.SolidBrush($C.BgCard)), 0, 0, $s2.Width, $s2.Height)
            $td = $s2.Tag
            Draw-GlowBorder $g $s2.Width $s2.Height $td.Color 2
            Draw-CircleGauge $g 46 55 30 $td.Pct $td.Color $td.TrackColor 5
        } catch {
            Write-Log -Message "CPU/RAM/Disk card Paint error" -Level WARN -ExceptionRecord $_
            # Fallback: card not rendered this frame
        }
    })

    $valLbl = New-Object Windows.Forms.Label
    $valLbl.Text      = $cd.Val
    $valLbl.Location  = [Drawing.Point]::new(100, 12)
    $valLbl.Size      = [Drawing.Size]::new(112, 26)
    $valLbl.Font      = New-Object Drawing.Font("Consolas", 10, [Drawing.FontStyle]::Bold)
    $valLbl.ForeColor = $cd.Color
    $valLbl.BackColor = [Drawing.Color]::Transparent
    $cp.Controls.Add($valLbl)
    $UI[$cd.Key + "ValLbl"] = $valLbl

    $cardTitleLbl = New-Object Windows.Forms.Label
    $cardTitleLbl.Text      = $cd.Title
    $cardTitleLbl.Location  = [Drawing.Point]::new(100, 42)
    $cardTitleLbl.Size      = [Drawing.Size]::new(112, 18)
    $cardTitleLbl.Font      = New-Object Drawing.Font("Segoe UI", 8)
    $cardTitleLbl.ForeColor = $C.SubText
    $cardTitleLbl.BackColor = [Drawing.Color]::Transparent
    $cp.Controls.Add($cardTitleLbl)

    $pctLbl = New-Object Windows.Forms.Label
    $pctLbl.Text      = "$pct%"
    $pctLbl.Location  = [Drawing.Point]::new(100, 64)
    $pctLbl.Size      = [Drawing.Size]::new(90, 20)
    $pctLbl.Font      = New-Object Drawing.Font("Consolas", 9, [Drawing.FontStyle]::Bold)
    $pctLbl.ForeColor = Pct-Color $pct
    $pctLbl.BackColor = [Drawing.Color]::Transparent
    $cp.Controls.Add($pctLbl)
    $UI[$cd.Key + "PctLbl"] = $pctLbl

    # Thin 4px fill bar
    $barTrack = New-Object Windows.Forms.Panel
    $barTrack.Location  = [Drawing.Point]::new(100, 88)
    $barTrack.Size      = [Drawing.Size]::new(112, 4)
    $barTrack.BackColor = $C.BgCard2
    $cp.Controls.Add($barTrack)

    $barFill = New-Object Windows.Forms.Panel
    $fw = [math]::Max(0, [math]::Min(112, [int](($pct / 100.0) * 112)))
    $barFill.Location  = [Drawing.Point]::new(0, 0)
    $barFill.Size      = [Drawing.Size]::new($fw, 4)
    $barFill.BackColor = Pct-Color $pct
    $barTrack.Controls.Add($barFill)
    $UI[$cd.Key + "BarFill"] = $barFill

    $UI[$cd.Key + "Card"] = $cp
    $tab1.Controls.Add($cp)
}

# -- Temperature Card (Sprint 2 - LHM WMI) ------------------------------
$tempCard = New-Pnl 810 15 220 110 $C.BgCard

$tempCard.Add_Paint({
    param($s2, $pe)
    try {
        $g = $pe.Graphics
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.FillRectangle((New-Object Drawing.SolidBrush($C.BgCard)), 0, 0, $s2.Width, $s2.Height)
        Draw-GlowBorder $g $s2.Width $s2.Height $C.Orange 2
    } catch {
        Write-Log -Message "Temp card Paint error" -Level WARN -ExceptionRecord $_
    }
})

$tempTitleLbl = New-Object Windows.Forms.Label
$tempTitleLbl.Text      = "TEMPS"
$tempTitleLbl.Location  = [Drawing.Point]::new(12, 12)
$tempTitleLbl.Size      = [Drawing.Size]::new(196, 18)
$tempTitleLbl.Font      = New-Object Drawing.Font("Consolas", 9, [Drawing.FontStyle]::Bold)
$tempTitleLbl.ForeColor = $C.Orange
$tempTitleLbl.BackColor = [Drawing.Color]::Transparent
$tempCard.Controls.Add($tempTitleLbl)

$script:tempCPULbl = New-Object Windows.Forms.Label
$script:tempCPULbl.Text      = "CPU: --"
$script:tempCPULbl.Location  = [Drawing.Point]::new(12, 34)
$script:tempCPULbl.Size      = [Drawing.Size]::new(196, 22)
$script:tempCPULbl.Font      = New-Object Drawing.Font("Consolas", 11, [Drawing.FontStyle]::Bold)
$script:tempCPULbl.ForeColor = $C.SubText
$script:tempCPULbl.BackColor = [Drawing.Color]::Transparent
$tempCard.Controls.Add($script:tempCPULbl)

$script:tempGPULbl = New-Object Windows.Forms.Label
$script:tempGPULbl.Text      = "GPU: --"
$script:tempGPULbl.Location  = [Drawing.Point]::new(12, 58)
$script:tempGPULbl.Size      = [Drawing.Size]::new(196, 20)
$script:tempGPULbl.Font      = New-Object Drawing.Font("Consolas", 10, [Drawing.FontStyle]::Regular)
$script:tempGPULbl.ForeColor = $C.SubText
$script:tempGPULbl.BackColor = [Drawing.Color]::Transparent
$tempCard.Controls.Add($script:tempGPULbl)

$script:tempStatus = New-Object Windows.Forms.Label
$script:tempStatus.Text      = "Install LibreHardwareMonitor"
$script:tempStatus.Location  = [Drawing.Point]::new(12, 82)
$script:tempStatus.Size      = [Drawing.Size]::new(196, 16)
$script:tempStatus.Font      = New-Object Drawing.Font("Segoe UI", 7)
$script:tempStatus.ForeColor = $C.Dim
$script:tempStatus.BackColor = [Drawing.Color]::Transparent
$script:tempStatus.Visible   = $true
$tempCard.Controls.Add($script:tempStatus)

$UI["TempCard"] = $tempCard
$tab1.Controls.Add($tempCard)

# -- CPU History Chart ---------------------------------------------------
$cpuChart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
$cpuChart.Location        = [Drawing.Point]::new(15, 140)
$cpuChart.Size            = [Drawing.Size]::new(1020, 120)
$cpuChart.BackColor       = $C.BgBase
$cpuChart.BorderlineColor = [Drawing.Color]::Transparent
$cpuChart.BorderSkin.SkinStyle = [System.Windows.Forms.DataVisualization.Charting.BorderSkinStyle]::None

$chartArea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea "ChartArea1"
$chartArea.BackColor                   = $C.BgBase
$chartArea.BorderColor                 = [Drawing.Color]::Transparent
$chartArea.AxisX.Enabled               = [System.Windows.Forms.DataVisualization.Charting.AxisEnabled]::False
$chartArea.AxisX.MajorGrid.Enabled     = $false
$chartArea.AxisX.MinorGrid.Enabled     = $false
$chartArea.AxisY.Minimum               = 0
$chartArea.AxisY.Maximum               = 100
$chartArea.AxisY.Interval              = 25
$chartArea.AxisY.LabelStyle.ForeColor  = $C.Dim
$chartArea.AxisY.LabelStyle.Font       = New-Object Drawing.Font("Segoe UI", 7)
$chartArea.AxisY.LineColor             = $C.Border
$chartArea.AxisY.MajorGrid.LineColor   = $C.Border
$chartArea.AxisY.MajorTickMark.Enabled = $false
[void]$cpuChart.ChartAreas.Add($chartArea)

$cpuSeries = New-Object System.Windows.Forms.DataVisualization.Charting.Series "CPU"
$cpuSeries.ChartType          = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::SplineArea
$cpuSeries.Color              = [Drawing.Color]::FromArgb(56, 189, 248)
$cpuSeries.BackSecondaryColor = [Drawing.Color]::FromArgb(0, 10, 18, 40)
$cpuSeries.BackGradientStyle  = [System.Windows.Forms.DataVisualization.Charting.GradientStyle]::TopBottom
$cpuSeries.BorderWidth        = 2
$cpuSeries.ChartArea          = "ChartArea1"
$cpuSeries.IsVisibleInLegend  = $false

for ($i = 0; $i -lt 60; $i++) { [void]$cpuSeries.Points.AddY(0.0) }
[void]$cpuChart.Series.Add($cpuSeries)
$UI["CpuChart"] = $cpuChart
$tab1.Controls.Add($cpuChart)

# -- Section label + underline -------------------------------------------
$procTitleLbl = New-Object Windows.Forms.Label
$procTitleLbl.Text      = "  Top 25 Processes by RAM"
$procTitleLbl.Location  = [Drawing.Point]::new(15, 268)
$procTitleLbl.Size      = [Drawing.Size]::new(500, 26)
$procTitleLbl.Font      = New-Object Drawing.Font("Consolas", 11, [Drawing.FontStyle]::Bold)
$procTitleLbl.ForeColor = $C.Blue
$procTitleLbl.BackColor = [Drawing.Color]::Transparent
$tab1.Controls.Add($procTitleLbl)

$underlinePnl = New-Pnl 17 294 220 1 $C.Blue
$tab1.Controls.Add($underlinePnl)

# -- Process list --------------------------------------------------------
$pGrid = New-Object Windows.Forms.DataGridView
$pGrid.Location = [Drawing.Point]::new(15, 298)
$pGrid.Size     = [Drawing.Size]::new(1020, 300)
Style-Grid $pGrid
Add-Col $pGrid "Process Name" 220
Add-Col $pGrid "RAM (MB)"      80
Add-Col $pGrid "CPU (sec)"     80
Add-Col $pGrid "PID"           60

$killCol = New-Object System.Windows.Forms.DataGridViewButtonColumn
$killCol.Name            = "Kill"
$killCol.HeaderText      = "ACTION"
$killCol.Text            = "END"
$killCol.UseColumnTextForButtonValue = $true
$killCol.Width           = 58
$killCol.DefaultCellStyle.BackColor  = [Drawing.Color]::FromArgb(80, 20, 20)
$killCol.DefaultCellStyle.ForeColor  = $C.Red
$killCol.DefaultCellStyle.Font       = $script:MonoBold
$killCol.DefaultCellStyle.Alignment  = "MiddleCenter"
[void]$pGrid.Columns.Add($killCol)
$killCol.HeaderCell.Style.ForeColor = $C.Red

function Refresh-ProcessGrid {
    $procs = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 25 `
        Name, Id,
        @{N="RAM MB"; E={[math]::Round($_.WorkingSet64/1MB,1)}},
        @{N="CPU sec";E={[math]::Round($_.CPU,1)}}

    $pGrid.SuspendLayout()
    $pGrid.Rows.Clear()
    foreach ($p in $procs) {
        $ri  = $pGrid.Rows.Add($p.Name, $p.'RAM MB', $p.'CPU sec', $p.Id)
        $row = $pGrid.Rows[$ri]
        if ($p.'RAM MB' -gt 500)     { $row.DefaultCellStyle.ForeColor = $C.Red }
        elseif ($p.'RAM MB' -gt 200) { $row.DefaultCellStyle.ForeColor = $C.Yellow }
        $pName = $row.Cells[0].Value.ToString().ToLower()
        if ($script:ProtectedProcesses -contains $pName) {
            $row.Cells[4].Value           = "--"
            $row.Cells[4].Style.ForeColor = $C.Dim
            $row.Cells[4].Style.BackColor = $C.BgCard
            $row.Cells[4].ReadOnly        = $true
            $row.Cells[4].ToolTipText     = "System process - protected"
        }
    }
    $pGrid.ResumeLayout()
}
Refresh-ProcessGrid

function Refresh-NetGrid {
    $conns = Get-NetworkConnections
    $script:netGrid.SuspendLayout()
    $script:netGrid.Rows.Clear()
    foreach ($c in $conns) {
        $idx = $script:netGrid.Rows.Add(
            $c.Process, $c.PID, $c.LocalPort, $c.RemoteIP, $c.State)
        $row = $script:netGrid.Rows[$idx]
        $stateColor = switch ($c.State) {
            'Established' { $C.Blue   }
            'Listen'      { $C.Green  }
            'CloseWait'   { $C.Yellow }
            'TimeWait'    { $C.Dim    }
            default       { $C.SubText }
        }
        $row.Cells[4].Style.ForeColor = $stateColor
        if ($c.IsSuspect) {
            $row.DefaultCellStyle.ForeColor = $C.Orange
        }
    }
    $script:netGrid.ResumeLayout()
}

function Update-SecurityCards($audit) {
    # Defender card
    if ($audit.Defender.Enabled -eq $true) {
        $script:defStatusLbl.Text      = 'PROTECTED'
        $script:defStatusLbl.ForeColor = $C.Green
    } else {
        $script:defStatusLbl.Text      = 'DISABLED'
        $script:defStatusLbl.ForeColor = $C.Red
    }
    $scanDate = if ($audit.Defender.LastScan) {
        $audit.Defender.LastScan.ToString('yyyy-MM-dd HH:mm') } else { 'Unknown' }
    $script:defScanLbl.Text = "Last scan: $scanDate"

    # Updates card
    $upd = $audit.Updates
    $script:updCountLbl.Text      = $upd.ToString()
    $script:updCountLbl.ForeColor = if ($upd -eq 0) { $C.Green }
                                    elseif ($upd -le 5) { $C.Yellow }
                                    else { $C.Red }

    # Firewall card labels (Domain / Private / Public)
    foreach ($profile in @('Domain', 'Private', 'Public')) {
        $lbl = $script:fwLabels[$profile]
        $on  = $audit.Firewall[$profile]
        $lbl.Text      = "$profile : $(if ($on) {'ON'} else {'OFF'})"
        $lbl.ForeColor = if ($on) { $C.Green } else { $C.Red }
    }

    # Ports grid
    $script:portsGrid.Rows.Clear()
    foreach ($p in $audit.Ports) {
        $script:portsGrid.Rows.Add($p.LocalPort, $p.Process, $p.PID)
    }
}

$tab1.Controls.Add($pGrid)
$tabs.TabPages.Add($tab1)

# ========================================================================
# TAB 2 -- STARTUP PROGRAMS
# ========================================================================
$tab2 = New-Object Windows.Forms.TabPage
$tab2.Text      = "  Startup Programs  "
$tab2.BackColor = $C.BgBase

$s2TitleLbl = New-Object Windows.Forms.Label
$s2TitleLbl.Text      = "  Programs that launch automatically on boot"
$s2TitleLbl.Location  = [Drawing.Point]::new(15, 15)
$s2TitleLbl.Size      = [Drawing.Size]::new(700, 26)
$s2TitleLbl.Font      = New-Object Drawing.Font("Consolas", 11, [Drawing.FontStyle]::Bold)
$s2TitleLbl.ForeColor = $C.Blue
$s2TitleLbl.BackColor = [Drawing.Color]::Transparent
$tab2.Controls.Add($s2TitleLbl)

$s2SubLbl = New-Object Windows.Forms.Label
$s2SubLbl.Text      = "  Disabling a User item removes it from the registry. System items require admin rights."
$s2SubLbl.Location  = [Drawing.Point]::new(15, 43)
$s2SubLbl.Size      = [Drawing.Size]::new(900, 18)
$s2SubLbl.Font      = New-Object Drawing.Font("Consolas", 8)
$s2SubLbl.ForeColor = $C.Dim
$s2SubLbl.BackColor = [Drawing.Color]::Transparent
$tab2.Controls.Add($s2SubLbl)

$s2CountLbl = New-Object Windows.Forms.Label
$s2CountLbl.Text      = "  Found $($startups.Count) startup items"
$s2CountLbl.Location  = [Drawing.Point]::new(15, 63)
$s2CountLbl.Size      = [Drawing.Size]::new(400, 20)
$s2CountLbl.Font      = New-Object Drawing.Font("Consolas", 9)
$s2CountLbl.ForeColor = $C.Yellow
$s2CountLbl.BackColor = [Drawing.Color]::Transparent
$tab2.Controls.Add($s2CountLbl)

$sGrid = New-Object Windows.Forms.DataGridView
$sGrid.Location = [Drawing.Point]::new(15, 90)
$sGrid.Size     = [Drawing.Size]::new(1020, 520)
Style-Grid $sGrid
$sGrid.ReadOnly = $false

Add-Col $sGrid "Source"  70
Add-Col $sGrid "Name"   150
Add-Col $sGrid "Command" 550

$disableCol = New-Object Windows.Forms.DataGridViewButtonColumn
$disableCol.HeaderText = "Action"
$disableCol.Name       = "Action"
$disableCol.Text       = "Disable"
$disableCol.UseColumnTextForButtonValue = $true
$disableCol.FillWeight = 80
$disableCol.DefaultCellStyle.BackColor = $C.DarkRed
$disableCol.DefaultCellStyle.ForeColor = $C.White
$disableCol.DefaultCellStyle.Font      = New-Object Drawing.Font("Consolas", 9, [Drawing.FontStyle]::Bold)
$disableCol.DefaultCellStyle.Alignment = [Windows.Forms.DataGridViewContentAlignment]::MiddleCenter
[void]$sGrid.Columns.Add($disableCol)

$sGrid.Add_CellPainting({
    param($s2, $ep)
    if ($ep.RowIndex -lt 0 -or $ep.ColumnIndex -lt 0) { return }
    if ($sGrid.Columns[$ep.ColumnIndex].Name -ne "Action") { return }
    $ep.Handled = $true

    $cellVal = if ($ep.Value) { $ep.Value.ToString() } else { "Disable" }
    $srcVal  = $sGrid.Rows[$ep.RowIndex].Cells["Source"].Value

    $noAdminSystem = (-not $script:isAdmin -and $srcVal -eq "System")
    $btnColor = if ($noAdminSystem) { $C.Dim }
                elseif ($cellVal -eq "Disabled!") { $C.DarkGreen }
                else { $C.DarkRed }

    $rowBg = if ($ep.RowIndex % 2 -eq 0) { $C.BgCard } else { $C.BgCard2 }
    $ep.Graphics.FillRectangle((New-Object Drawing.SolidBrush($rowBg)), $ep.CellBounds)

    $rect = [Drawing.Rectangle]::new(
        $ep.CellBounds.X + 6,
        $ep.CellBounds.Y + 4,
        $ep.CellBounds.Width - 12,
        $ep.CellBounds.Height - 8)
    $ep.Graphics.FillRectangle((New-Object Drawing.SolidBrush($btnColor)), $rect)
    $ep.Graphics.DrawRectangle((New-Object Drawing.Pen($C.Border, 1)), $rect)

    $displayText = if ($noAdminSystem) { "Admin req." } else { $cellVal }
    $sf = New-Object Drawing.StringFormat
    $sf.Alignment     = [Drawing.StringAlignment]::Center
    $sf.LineAlignment = [Drawing.StringAlignment]::Center
    $font = New-Object Drawing.Font("Consolas", 9, [Drawing.FontStyle]::Bold)
    $ep.Graphics.DrawString($displayText, $font, (New-Object Drawing.SolidBrush($C.White)), ([Drawing.RectangleF]$rect), $sf)
})

if ($startups.Count -gt 0) {
    foreach ($s in $startups) { [void]$sGrid.Rows.Add($s.Source, $s.Name, $s.Command, "Disable") }
} else {
    [void]$sGrid.Rows.Add("--", "No startup items found", "", "")
}

$sGrid.Add_CellContentClick({
    param($sender, $e)
    if ($e.ColumnIndex -eq $sGrid.Columns["Action"].Index -and $e.RowIndex -ge 0) {
        $row  = $sGrid.Rows[$e.RowIndex]
        $name = $row.Cells["Name"].Value
        if ($name -eq "No startup items found") { return }

        $item = $startups[$e.RowIndex]
        if (-not $item) { return }

        if (-not $script:isAdmin -and $item.Source -eq "System") {
            [Windows.Forms.MessageBox]::Show(
                "Disabling System startup items requires Administrator rights.`nRestart the app as Administrator to use this feature.",
                "Administrator Required",
                [Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        $confirm = [Windows.Forms.MessageBox]::Show(
            "Disable '$($item.Name)' from startup?`n`nThis removes it from the registry.`nYou can re-enable it later from Task Manager.",
            "Confirm Disable",
            [Windows.Forms.MessageBoxButtons]::YesNo,
            [Windows.Forms.MessageBoxIcon]::Warning)

        if ($confirm -eq [Windows.Forms.DialogResult]::Yes) {
            $regPath = $item.RegPath -replace "^HKCU:\\","HKCU\" -replace "^HKLM:\\","HKLM\"
            $output  = & reg delete $regPath /v $item.Name /f 2>&1
            if ($LASTEXITCODE -eq 0) {
                $row.DefaultCellStyle.BackColor      = $C.DarkGreen
                $row.DefaultCellStyle.ForeColor      = $C.White
                $row.Cells["Action"].Value           = "Disabled!"
                $row.Cells["Action"].Style.BackColor = $C.DarkGreen
                $row.Cells["Action"].Style.ForeColor = $C.White
                [Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 700
                $sGrid.Rows.RemoveAt($e.RowIndex)
            } else {
                [Windows.Forms.MessageBox]::Show(
                    "Could not disable '$($item.Name)'.`n`n$output`n`nTip: right-click the shortcut and Run as Administrator.",
                    "Error",
                    [Windows.Forms.MessageBoxButtons]::OK,
                    [Windows.Forms.MessageBoxIcon]::Error)
            }
        }
    }
})

$tab2.Controls.Add($sGrid)
$tabs.TabPages.Add($tab2)

# ========================================================================
# TAB 3 -- CLEANUP
# ========================================================================
$tab3 = New-Object Windows.Forms.TabPage
$tab3.Text      = "  Cleanup  "
$tab3.BackColor = $C.BgBase

$cleanTitleLbl = New-Object Windows.Forms.Label
$cleanTitleLbl.Text      = "  Junk Files - Recoverable Space"
$cleanTitleLbl.Location  = [Drawing.Point]::new(15, 15)
$cleanTitleLbl.Size      = [Drawing.Size]::new(500, 28)
$cleanTitleLbl.Font      = New-Object Drawing.Font("Consolas", 12, [Drawing.FontStyle]::Bold)
$cleanTitleLbl.ForeColor = $C.Blue
$cleanTitleLbl.BackColor = [Drawing.Color]::Transparent
$tab3.Controls.Add($cleanTitleLbl)

$cleanTotalLbl = New-Object Windows.Forms.Label
$cleanTotalLbl.Text      = "  Total found: $totalJunkGB GB across $($junkItems.Count) locations"
$cleanTotalLbl.Location  = [Drawing.Point]::new(15, 45)
$cleanTotalLbl.Size      = [Drawing.Size]::new(600, 22)
$cleanTotalLbl.Font      = New-Object Drawing.Font("Consolas", 9)
$cleanTotalLbl.ForeColor = $C.Red
$cleanTotalLbl.BackColor = [Drawing.Color]::Transparent
$tab3.Controls.Add($cleanTotalLbl)

$hdrPnl = New-Pnl 15 72 1020 28 $C.BgCard3
$hdrPnl.Add_Paint({
    param($s2, $pe)
    try {
        $pe.Graphics.DrawLine(
            (New-Object Drawing.Pen($C.Border, 1)),
            0, $hdrPnl.Height - 1, $hdrPnl.Width, $hdrPnl.Height - 1)
    } catch {
        Write-Log -Message "hdrPnl Paint error" -Level WARN -ExceptionRecord $_
        # Fallback: header border line not rendered this frame
    }
})
$hdrPnl.Controls.Add((New-Lbl "Location"  10  5 230 18 9 $true $C.Blue))
$hdrPnl.Controls.Add((New-Lbl "Size"     248  5 100 18 9 $true $C.Blue))
$hdrPnl.Controls.Add((New-Lbl "Files"    355  5  60 18 9 $true $C.Blue))
$hdrPnl.Controls.Add((New-Lbl "Path"     422  5 310 18 9 $true $C.Blue))
$tab3.Controls.Add($hdrPnl)

$logBox = New-Object Windows.Forms.RichTextBox
$logBox.Location    = [Drawing.Point]::new(15, 540)
$logBox.Size        = [Drawing.Size]::new(1020, 90)
$logBox.BackColor   = $C.BgCard
$logBox.ForeColor   = $C.Green
$logBox.Font        = New-Object Drawing.Font("Consolas", 9)
$logBox.ReadOnly    = $true
$logBox.BorderStyle = [Windows.Forms.BorderStyle]::None
$logBox.Text        = "Ready. Use the Clean buttons to remove junk files."
$tab3.Controls.Add($logBox)

$cleanProgress = New-Object Windows.Forms.ProgressBar
$cleanProgress.Location              = [Drawing.Point]::new(15, 524)
$cleanProgress.Size                  = [Drawing.Size]::new(1020, 12)
$cleanProgress.Style                 = [Windows.Forms.ProgressBarStyle]::Marquee
$cleanProgress.MarqueeAnimationSpeed = 30
$cleanProgress.Visible               = $false
$tab3.Controls.Add($cleanProgress)

$cleanToolTip = New-Object Windows.Forms.ToolTip

$rY = 103
foreach ($ji in $junkItems) {
    $sColor = if ($ji.SizeMB -gt 500) {$C.Red} elseif ($ji.SizeMB -gt 100) {$C.Yellow} else {$C.Green}
    $rPnl   = New-Pnl 15 $rY 1020 56 $C.BgCard

    # Store junk item reference in Tag for paint closure
    $rPnl.Tag = @{ SizeMB = $ji.SizeMB; SColor = $sColor }

    $rPnl.Add_Paint({
        param($s2, $pe)
        try {
            $g = $pe.Graphics
            $g.FillRectangle((New-Object Drawing.SolidBrush($C.BgCard)), 0, 0, $s2.Width, $s2.Height)
            $stripeColor = $s2.Tag.SColor
            $g.FillRectangle((New-Object Drawing.SolidBrush($stripeColor)), 0, 0, 3, $s2.Height)
            $g.DrawLine((New-Object Drawing.Pen($C.Border, 1)), 0, $s2.Height - 1, $s2.Width, $s2.Height - 1)
        } catch {
            Write-Log -Message "Junk item row panel Paint error" -Level WARN -ExceptionRecord $_
            # Fallback: row panel not rendered this frame
        }
    })

    $nameLbl = New-Object Windows.Forms.Label
    $nameLbl.Text      = $ji.Name
    $nameLbl.Location  = [Drawing.Point]::new(12, 8)
    $nameLbl.Size      = [Drawing.Size]::new(230, 20)
    $nameLbl.Font      = New-Object Drawing.Font("Consolas", 10, [Drawing.FontStyle]::Bold)
    $nameLbl.ForeColor = $C.Text
    $nameLbl.BackColor = [Drawing.Color]::Transparent
    $rPnl.Controls.Add($nameLbl)

    $sizeLbl = New-Object Windows.Forms.Label
    $sizeLbl.Text      = "$($ji.SizeMB) MB"
    $sizeLbl.Location  = [Drawing.Point]::new(250, 8)
    $sizeLbl.Size      = [Drawing.Size]::new(100, 20)
    $sizeLbl.Font      = New-Object Drawing.Font("Consolas", 10, [Drawing.FontStyle]::Bold)
    $sizeLbl.ForeColor = $sColor
    $sizeLbl.BackColor = [Drawing.Color]::Transparent
    $rPnl.Controls.Add($sizeLbl)

    $filesLbl = New-Object Windows.Forms.Label
    $filesLbl.Text      = "$($ji.Files) files"
    $filesLbl.Location  = [Drawing.Point]::new(357, 8)
    $filesLbl.Size      = [Drawing.Size]::new(70, 20)
    $filesLbl.Font      = New-Object Drawing.Font("Consolas", 9)
    $filesLbl.ForeColor = $C.SubText
    $filesLbl.BackColor = [Drawing.Color]::Transparent
    $rPnl.Controls.Add($filesLbl)

    $pathLbl = New-Object Windows.Forms.Label
    $pathLbl.Text      = $ji.Path
    $pathLbl.Location  = [Drawing.Point]::new(12, 32)
    $pathLbl.Size      = [Drawing.Size]::new(560, 16)
    $pathLbl.Font      = New-Object Drawing.Font("Consolas", 7)
    $pathLbl.ForeColor = $C.Dim
    $pathLbl.BackColor = [Drawing.Color]::Transparent
    $rPnl.Controls.Add($pathLbl)

    $cleanBtn = New-Object Windows.Forms.Button
    $cleanBtn.Text      = "Clean"
    $cleanBtn.Location  = [Drawing.Point]::new(820, 10)
    $cleanBtn.Size      = [Drawing.Size]::new(100, 36)
    $cleanBtn.BackColor = $C.DarkRed
    $cleanBtn.ForeColor = $C.White
    $cleanBtn.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $cleanBtn.FlatAppearance.BorderColor = $C.Red
    $cleanBtn.FlatAppearance.BorderSize  = 1
    $cleanBtn.Font      = New-Object Drawing.Font("Consolas", 9, [Drawing.FontStyle]::Bold)
    $cleanBtn.Cursor    = [Windows.Forms.Cursors]::Hand

    $skipBtn = New-Object Windows.Forms.Button
    $skipBtn.Text      = "Skip"
    $skipBtn.Location  = [Drawing.Point]::new(928, 10)
    $skipBtn.Size      = [Drawing.Size]::new(80, 36)
    $skipBtn.BackColor = $C.BgCard2
    $skipBtn.ForeColor = $C.Dim
    $skipBtn.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $skipBtn.FlatAppearance.BorderSize = 0
    $skipBtn.Font      = New-Object Drawing.Font("Consolas", 9)
    $skipBtn.Cursor    = [Windows.Forms.Cursors]::Hand

    $cleanBtn.Tag = @{ Path = $ji.Path; Name = $ji.Name; SizeLbl = $sizeLbl; FilesLbl = $filesLbl }

    $needsAdmin = $adminRequiredNames -contains $ji.Name
    if ($needsAdmin -and -not $script:isAdmin) {
        $cleanBtn.Enabled   = $false
        $cleanBtn.BackColor = $C.Dim
        $cleanToolTip.SetToolTip($cleanBtn, "Requires Administrator")
    }

    $cleanBtn.Add_Click({
        param($s, $e)
        $tagData    = $s.Tag
        $targetPath = $tagData.Path

        $s.Enabled   = $false
        $s.Text      = "..."
        $s.BackColor = $C.Dim
        $cleanProgress.Style   = [Windows.Forms.ProgressBarStyle]::Marquee
        $cleanProgress.Visible = $true
        [Windows.Forms.Application]::DoEvents()

        $capturedPath     = $targetPath
        $capturedForm     = $form
        $capturedSender   = $s
        $capturedLog      = $logBox
        $capturedProgress = $cleanProgress
        $capturedDG       = $C.DarkGreen
        $capturedSizeLbl  = $tagData.SizeLbl
        $capturedFilesLbl = $tagData.FilesLbl
        $capturedGreen    = $C.Green
        $capturedName     = $tagData.Name

        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $rs.ApartmentState = "STA"
        $rs.ThreadOptions  = "ReuseThread"
        $rs.Open()

        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs

        [void]$ps.AddScript({
            param($path, $formObj, $btn, $log, $prog, $dg, $szLbl, $fLbl, $green, $name)
            $del = 0; $errCount = 0

            $formObj.Invoke([Action]{ $log.AppendText("`nCleaning: $path") })

            Get-ChildItem $path -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try   { Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop; $del++ }
                catch { $errCount++ }
                # NOTE: Write-Log cannot be called here -- this runs inside a Runspace
                # which does not share $script: scope. Error count is surfaced via UI message below.
            }

            $msg = "  Done - removed $del items ($errCount locked/skipped)"
            $formObj.Invoke([Action]{
                $btn.Text        = "Done"
                $btn.BackColor   = $dg
                $log.AppendText($msg)
                $log.ScrollToCaret()
                $prog.Visible    = $false
                $szLbl.Text      = "0 MB"
                $szLbl.ForeColor = $green
                $fLbl.Text       = "0 files"
                [System.Windows.Forms.MessageBox]::Show(
                    "All files in '$name' have been successfully removed.",
                    "Cleanup Complete",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information)
            })
        })
        [void]$ps.AddParameter("path",    $capturedPath)
        [void]$ps.AddParameter("formObj", $capturedForm)
        [void]$ps.AddParameter("btn",     $capturedSender)
        [void]$ps.AddParameter("log",     $capturedLog)
        [void]$ps.AddParameter("prog",    $capturedProgress)
        [void]$ps.AddParameter("dg",      $capturedDG)
        [void]$ps.AddParameter("szLbl",   $capturedSizeLbl)
        [void]$ps.AddParameter("fLbl",    $capturedFilesLbl)
        [void]$ps.AddParameter("green",   $capturedGreen)
        [void]$ps.AddParameter("name",    $capturedName)

        [void]$ps.BeginInvoke()
    })

    $skipBtn.Add_Click({
        param($sender, $e)
        $sender.Enabled = $false
        $sender.Text    = "Skipped"
        $logBox.AppendText("`nSkipped.")
        $logBox.ScrollToCaret()
    })

    $rPnl.Controls.AddRange(@($cleanBtn, $skipBtn))
    $tab3.Controls.Add($rPnl)
    $rY += 62
}

$cleanAllBtn = New-Object Windows.Forms.Button
$cleanAllBtn.Text      = "Clean All"
$cleanAllBtn.Location  = [Drawing.Point]::new(890, 638)
$cleanAllBtn.Size      = [Drawing.Size]::new(120, 36)
$cleanAllBtn.BackColor = $C.DarkRed
$cleanAllBtn.ForeColor = $C.White
$cleanAllBtn.FlatStyle = [Windows.Forms.FlatStyle]::Flat
$cleanAllBtn.FlatAppearance.BorderSize = 0
$cleanAllBtn.Font      = New-Object Drawing.Font("Consolas", 9, [Drawing.FontStyle]::Bold)
$cleanAllBtn.Cursor    = [Windows.Forms.Cursors]::Hand
$cleanAllBtn.Add_MouseEnter({ $cleanAllBtn.BackColor = [Drawing.Color]::FromArgb(215, 60, 80) })
$cleanAllBtn.Add_MouseLeave({ $cleanAllBtn.BackColor = $C.DarkRed })
$tab3.Controls.Add($cleanAllBtn)

$cleanAllBtn.Add_Click({
    $r = [Windows.Forms.MessageBox]::Show(
        "This will clean ALL junk locations at once.`nAre you sure?",
        "Confirm Clean All",
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Warning)
    if ($r -eq [Windows.Forms.DialogResult]::Yes) {
        $logBox.AppendText("`n--- CLEAN ALL STARTED ---")
        foreach ($ji2 in $junkItems) {
            if (($adminRequiredNames -contains $ji2.Name) -and (-not $script:isAdmin)) {
                $logBox.AppendText("`nSkipped (requires admin): $($ji2.Name)")
                [Windows.Forms.Application]::DoEvents()
                continue
            }
            $logBox.AppendText("`nCleaning: $($ji2.Path)")
            [Windows.Forms.Application]::DoEvents()
            $del=0; $errCount=0
            Get-ChildItem $ji2.Path -Force -EA SilentlyContinue | ForEach-Object {
                try   { Remove-Item $_.FullName -Force -Recurse -EA Stop; $del++ }
                catch {
                    Write-Log -Message "Clean All: failed to remove item from $($ji2.Name)" -Level WARN -ExceptionRecord $_
                    $errCount++
                }
            }
            $logBox.AppendText("  -> $del removed, $errCount skipped")
        }
        $logBox.AppendText("`n--- DONE ---")
        $logBox.ScrollToCaret()
    }
})

$tabs.TabPages.Add($tab3)

# ========================================================================
# TAB 4 -- NETWORK INTELLIGENCE (Sprint 3 official)
# ========================================================================
$netTab = New-Object Windows.Forms.TabPage
$netTab.Text      = "  NET  "
$netTab.BackColor = $C.BgBase

# -- Bandwidth banner panel (36px) ---------------------------------------
$netBandwidthPanel = New-Pnl 0 0 1060 36 $C.BgCard

$script:netSentLbl = New-Object Windows.Forms.Label
$script:netSentLbl.Text      = "OUT: 0.0 KB/s"
$script:netSentLbl.Location  = [Drawing.Point]::new(15, 7)
$script:netSentLbl.Size      = [Drawing.Size]::new(210, 22)
$script:netSentLbl.Font      = New-Object Drawing.Font("Consolas", 10, [Drawing.FontStyle]::Bold)
$script:netSentLbl.ForeColor = $C.Purple
$script:netSentLbl.BackColor = [Drawing.Color]::Transparent
$netBandwidthPanel.Controls.Add($script:netSentLbl)

$script:netRecvLbl = New-Object Windows.Forms.Label
$script:netRecvLbl.Text      = "IN: 0.0 KB/s"
$script:netRecvLbl.Location  = [Drawing.Point]::new(240, 7)
$script:netRecvLbl.Size      = [Drawing.Size]::new(210, 22)
$script:netRecvLbl.Font      = New-Object Drawing.Font("Consolas", 10, [Drawing.FontStyle]::Bold)
$script:netRecvLbl.ForeColor = $C.Blue
$script:netRecvLbl.BackColor = [Drawing.Color]::Transparent
$netBandwidthPanel.Controls.Add($script:netRecvLbl)

$netLegendLbl = New-Object Windows.Forms.Label
$netLegendLbl.Text      = "ESTAB  LISTEN  CLOSE_WAIT  TIME_WAIT  [orange] = external IP"
$netLegendLbl.Location  = [Drawing.Point]::new(670, 10)
$netLegendLbl.Size      = [Drawing.Size]::new(370, 16)
$netLegendLbl.Font      = New-Object Drawing.Font("Consolas", 7)
$netLegendLbl.ForeColor = $C.Dim
$netLegendLbl.BackColor = [Drawing.Color]::Transparent
$netBandwidthPanel.Controls.Add($netLegendLbl)

$netTab.Controls.Add($netBandwidthPanel)

# -- Connection DataGridView (5 cols, AutoSizeColumnsMode = Fill) ---------
$script:netGrid = New-Object Windows.Forms.DataGridView
$script:netGrid.Location            = [Drawing.Point]::new(0, 38)
$script:netGrid.Size                = [Drawing.Size]::new(1040, 552)
$script:netGrid.AutoSizeColumnsMode = [Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
Style-Grid $script:netGrid
$script:netGrid.ColumnHeadersHeight = 28
$script:netGrid.RowTemplate.Height  = 22
$script:netGrid.DoubleBuffered      = $true

foreach ($nc in @(
    @{Name="Process";  Header="PROCESS";   FillWeight=20},
    @{Name="PID";      Header="PID";       FillWeight=8 },
    @{Name="Port";     Header="PORT";      FillWeight=8 },
    @{Name="RemoteIP"; Header="REMOTE IP"; FillWeight=20},
    @{Name="State";    Header="STATE";     FillWeight=14}
)) {
    $col = New-Object Windows.Forms.DataGridViewTextBoxColumn
    $col.Name       = $nc.Name
    $col.HeaderText = $nc.Header
    $col.FillWeight = $nc.FillWeight
    $col.SortMode   = [Windows.Forms.DataGridViewColumnSortMode]::NotSortable
    [void]$script:netGrid.Columns.Add($col)
}

$netTab.Controls.Add($script:netGrid)
$tabs.TabPages.Add($netTab)

# ========================================================================
# TAB 5 -- SECURITY AUDIT (Sprint 4 official)
# ========================================================================
$secTab = New-Object Windows.Forms.TabPage
$secTab.Text      = "  Security  "
$secTab.BackColor = $C.BgBase

# -- 3 top cards (200px wide each) ---------------------------------------
# Defender Card
$defCard = New-Pnl 15 10 200 130 $C.BgCard
$defCard.Controls.Add((New-Lbl "DEFENDER" 10 8 178 16 8 $false $C.SubText))
$script:defStatusLbl = New-Lbl "--" 10 28 178 30 13 $true $C.SubText
$defCard.Controls.Add($script:defStatusLbl)
$script:defScanLbl = New-Lbl "Last scan: --" 10 64 178 16 7 $false $C.Dim
$defCard.Controls.Add($script:defScanLbl)
$secTab.Controls.Add($defCard)

# Updates Card
$updCard = New-Pnl 230 10 200 130 $C.BgCard
$updCard.Controls.Add((New-Lbl "UPDATES" 10 8 178 16 8 $false $C.SubText))
$script:updCountLbl = New-Lbl "--" 10 28 178 48 22 $true $C.SubText
$secTab.Controls.Add($updCard)
$updCard.Controls.Add($script:updCountLbl)
$updCard.Controls.Add((New-Lbl "pending updates" 10 80 178 16 7 $false $C.Dim))

# Firewall Card
$fwCard = New-Pnl 445 10 200 130 $C.BgCard
$fwCard.Controls.Add((New-Lbl "FIREWALL" 10 8 178 16 8 $false $C.SubText))
$script:fwLabels = @{}
$script:fwLabels['Domain']  = New-Lbl "Domain : --"  10 32 178 18 9 $false $C.SubText
$script:fwLabels['Private'] = New-Lbl "Private : --" 10 54 178 18 9 $false $C.SubText
$script:fwLabels['Public']  = New-Lbl "Public : --"  10 76 178 18 9 $false $C.SubText
$fwCard.Controls.AddRange(@($script:fwLabels['Domain'], $script:fwLabels['Private'], $script:fwLabels['Public']))
$secTab.Controls.Add($fwCard)

# -- Open Ports DataGridView ---------------------------------------------
$secTab.Controls.Add((New-Lbl "  Open Listening Ports" 15 150 400 22 10 $true $C.Blue))
$secTab.Controls.Add((New-Pnl 17 172 200 1 $C.Blue))

$script:portsGrid = New-Object Windows.Forms.DataGridView
$script:portsGrid.Location = [Drawing.Point]::new(15, 176)
$script:portsGrid.Size     = [Drawing.Size]::new(1020, 315)
Style-Grid $script:portsGrid
$script:portsGrid.ColumnHeadersHeight = 28
$script:portsGrid.RowTemplate.Height  = 22
foreach ($spc in @(
    @{N="Port";    H="PORT";    W=80 },
    @{N="Process"; H="PROCESS"; W=180},
    @{N="PID";     H="PID";     W=60 }
)) {
    $sc = New-Object Windows.Forms.DataGridViewTextBoxColumn
    $sc.Name = $spc.N; $sc.HeaderText = $spc.H; $sc.Width = $spc.W
    $sc.SortMode = [Windows.Forms.DataGridViewColumnSortMode]::NotSortable
    [void]$script:portsGrid.Columns.Add($sc)
}
$secTab.Controls.Add($script:portsGrid)

# -- Bottom button row ---------------------------------------------------
$scanNowBtn = New-Btn "SCAN NOW"      15  502 140 36 $C.BgCard2 $C.Blue
$exportBtn  = New-Btn "EXPORT REPORT" 875 502 160 36 $C.Purple  $C.White

$scanNowBtn.Add_Click({ Update-SecurityCards (Get-SecurityAudit) })
$exportBtn.Add_Click({  Export-SystemReport })

$secTab.Controls.AddRange(@($scanNowBtn, $exportBtn))
$tabs.TabPages.Add($secTab)
#endregion

#region 6 - Event Handlers & Timer
# Auto-trigger first security scan when user navigates to Security tab
$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $netTab) { Refresh-NetGrid }
})

# Tab owner-draw event (added after all tabs are registered)
$tabs.Add_DrawItem({
    param($s2, $de)
    try {
        $tab      = $tabs.TabPages[$de.Index]
        $isSel    = ($de.Index -eq $tabs.SelectedIndex)
        $bgColor  = if ($isSel) { $C.BgCard2 } else { $C.BgBase }
        $fgColor  = if ($isSel) { $C.Blue    } else { $C.Dim    }
        $de.Graphics.FillRectangle((New-Object Drawing.SolidBrush($bgColor)), $de.Bounds)
        if ($isSel) {
            $accentPen = New-Object Drawing.Pen($C.Blue, 2)
            $de.Graphics.DrawLine($accentPen,
                $de.Bounds.Left, $de.Bounds.Bottom - 1,
                $de.Bounds.Right, $de.Bounds.Bottom - 1)
        }
        $font = New-Object Drawing.Font("Consolas", 9, [Drawing.FontStyle]::Bold)
        $sf   = New-Object Drawing.StringFormat
        $sf.Alignment      = [Drawing.StringAlignment]::Center
        $sf.LineAlignment  = [Drawing.StringAlignment]::Center
        $de.Graphics.DrawString($tab.Text.Trim(), $font,
            (New-Object Drawing.SolidBrush($fgColor)), [Drawing.RectangleF]$de.Bounds, $sf)
    } catch {
        Write-Log -Message "Tab DrawItem paint error at index $($de.Index)" -Level WARN -ExceptionRecord $_
        # Fallback: tab label not rendered this frame
    }
})

# ========================================================================
# SYSTEM TRAY ICON
# ========================================================================
$trayIcon = New-Object Windows.Forms.NotifyIcon
$trayIcon.Text    = "PC Health Monitor"
$trayIcon.Visible = $true
try   { $trayIcon.Icon = [Drawing.Icon]::ExtractAssociatedIcon("$env:SystemRoot\System32\perfmon.exe") }
catch {
    Write-Log -Message "Failed to load tray icon from perfmon.exe, using system default" -Level WARN -ExceptionRecord $_
    $trayIcon.Icon = [Drawing.SystemIcons]::Application
}

$trayMenu = New-Object Windows.Forms.ContextMenuStrip
$trayMenu.BackColor = $C.BgCard
$trayMenu.ForeColor = $C.Text

$trayOpen = New-Object Windows.Forms.ToolStripMenuItem "Open"
$trayOpen.BackColor = $C.BgCard
$trayOpen.ForeColor = $C.Blue

$traySep  = New-Object Windows.Forms.ToolStripSeparator

$trayExit = New-Object Windows.Forms.ToolStripMenuItem "Exit"
$trayExit.BackColor = $C.BgCard
$trayExit.ForeColor = $C.Red

[void]$trayMenu.Items.Add($trayOpen)
[void]$trayMenu.Items.Add($traySep)
[void]$trayMenu.Items.Add($trayExit)
$trayIcon.ContextMenuStrip = $trayMenu

$trayIcon.Add_DoubleClick({
    $form.Show()
    $form.WindowState = [Windows.Forms.FormWindowState]::Normal
    $form.Activate()
})

$trayOpen.Add_Click({
    $form.Show()
    $form.WindowState = [Windows.Forms.FormWindowState]::Normal
    $form.Activate()
})

$trayExit.Add_Click({
    $script:realExit = $true
    $form.Close()
})

# -- Alert state variables -----------------------------------------------
$script:cpuHighTicks       = 0
$script:cpuAlertFired      = $false
$script:lastRamAlert       = [DateTime]::MinValue
$script:TempRefreshCounter = 0
$script:NetRefreshCounter  = 0
$script:lastDiskAlert = [DateTime]::MinValue
$script:trayHintShown = $false

# ========================================================================
# LIVE REFRESH LOGIC
# ========================================================================
$script:tickCount = 0

function Do-Refresh {
    try {
        $d = Get-LiveData

        # CPU card
        $UI["CpuValLbl"].Text      = "$($d.CpuPct)%"
        $UI["CpuPctLbl"].Text      = "$($d.CpuPct)%"
        $UI["CpuPctLbl"].ForeColor = Pct-Color $d.CpuPct
        $UI["CpuCard"].Tag.Pct     = $d.CpuPct
        $UI["CpuCard"].Invalidate()
        $fw = [math]::Max(0, [math]::Min(112, [int](($d.CpuPct / 100.0) * 112)))
        $UI["CpuBarFill"].Width     = $fw
        $UI["CpuBarFill"].BackColor = Pct-Color $d.CpuPct

        # RAM card
        $UI["RamValLbl"].Text      = "$($d.UsedRAM) GB / $script:totalRAM GB"
        $UI["RamPctLbl"].Text      = "$($d.RamPct)%"
        $UI["RamPctLbl"].ForeColor = Pct-Color $d.RamPct
        $UI["RamCard"].Tag.Pct     = $d.RamPct
        $UI["RamCard"].Invalidate()
        $fw2 = [math]::Max(0, [math]::Min(112, [int](($d.RamPct / 100.0) * 112)))
        $UI["RamBarFill"].Width     = $fw2
        $UI["RamBarFill"].BackColor = Pct-Color $d.RamPct

        # Disk card (every 5 ticks = ~15 sec)
        if ($script:tickCount % 5 -eq 0) {
            $UI["DiskValLbl"].Text      = "$($d.DUsed) GB used  |  $($d.DFree) GB free"
            $UI["DiskPctLbl"].Text      = "$($d.DPct)%"
            $UI["DiskPctLbl"].ForeColor = Pct-Color $d.DPct
            $UI["DiskCard"].Tag.Pct     = $d.DPct
            $UI["DiskCard"].Invalidate()
            $fw3 = [math]::Max(0, [math]::Min(112, [int](($d.DPct / 100.0) * 112)))
            $UI["DiskBarFill"].Width     = $fw3
            $UI["DiskBarFill"].BackColor = Pct-Color $d.DPct
        }

        # Temp card (every 2 ticks = ~6 sec, independent TempRefreshCounter)
        $script:TempRefreshCounter++
        if ($script:TempRefreshCounter % 2 -eq 0) {
            $temps = Get-HardwareTemps
            if ($temps.Available) {
                $script:tempStatus.Visible = $false
                $cVal = $temps.CPU
                $gVal = $temps.GPU
                $script:tempCPULbl.Text = if ($cVal) { "CPU: $cVal deg C" } else { 'CPU: N/A' }
                $script:tempCPULbl.ForeColor = if ($cVal -ge 80)   { $C.Red    }
                                               elseif ($cVal -ge 60){ $C.Yellow }
                                               else                  { $C.Green  }
                $script:tempGPULbl.Text = if ($gVal) { "GPU: $gVal deg C" } else { 'GPU: N/A' }
                $script:tempGPULbl.ForeColor = if ($gVal -ge 80)   { $C.Red    }
                                               elseif ($gVal -ge 60){ $C.Yellow }
                                               else                  { $C.Green  }
            } else {
                $script:tempCPULbl.Text      = ''
                $script:tempGPULbl.Text      = ''
                $script:tempStatus.Text      = 'Install LibreHardwareMonitor'
                $script:tempStatus.ForeColor = $C.Dim
                $script:tempStatus.Visible   = $true
            }
        }

        # Net tab (every 2 ticks = ~6 sec, only when tab is visible)
        $script:NetRefreshCounter++
        if ($script:NetRefreshCounter % 2 -eq 0 -and $script:tabs.SelectedTab -eq $netTab) {
            Refresh-NetGrid
        }

        # Security tab (every 10 ticks = ~30 sec, only when tab is visible)
        if ($script:tickCount % 10 -eq 0 -and $script:tabs.SelectedTab -eq $secTab) {
            Update-SecurityCards (Get-SecurityAudit)
        }

        # Process grid (every 2 ticks = ~6 sec)
        if ($script:tickCount % 2 -eq 0) {
            Refresh-ProcessGrid
        }

        # Add new CPU data point to the live chart, keep last 60 points
        [void]$UI["CpuChart"].Series[0].Points.AddY([double]$d.CpuPct)
        if ($UI["CpuChart"].Series[0].Points.Count -gt 60) {
            $UI["CpuChart"].Series[0].Points.RemoveAt(0)
        }

        $lastUpdLbl.Text = "  Updated: $(Get-Date -Format 'HH:mm:ss')"

        # Blinking dot
        $script:blinkState = -not $script:blinkState
        $blinkDot.BackColor = if ($script:blinkState) { $C.Green } else { $C.BgCard }

        # CPU alert: balloon after ~12 seconds of sustained load above 85%
        if ($d.CpuPct -gt 85) {
            $script:cpuHighTicks++
            if ($script:cpuHighTicks -ge 4 -and -not $script:cpuAlertFired) {
                $script:cpuAlertFired = $true
                $trayIcon.ShowBalloonTip(6000, "High CPU Usage",
                    "CPU has been above 85% for over 10 seconds ($($d.CpuPct)%)",
                    [Windows.Forms.ToolTipIcon]::Warning)
            }
        } else {
            $script:cpuHighTicks  = 0
            $script:cpuAlertFired = $false
        }

        # RAM alert: balloon when above 85%, cooldown 5 minutes
        if ($d.RamPct -gt 85) {
            if (([DateTime]::Now - $script:lastRamAlert).TotalMinutes -gt 5) {
                $script:lastRamAlert = [DateTime]::Now
                $trayIcon.ShowBalloonTip(6000, "High RAM Usage",
                    "RAM usage is at $($d.RamPct)% ($($d.UsedRAM) GB / $script:totalRAM GB)",
                    [Windows.Forms.ToolTipIcon]::Warning)
            }
        }

        # Disk alert: balloon when above 90%, cooldown 10 minutes
        if ($d.DPct -gt 90) {
            if (([DateTime]::Now - $script:lastDiskAlert).TotalMinutes -gt 10) {
                $script:lastDiskAlert = [DateTime]::Now
                $trayIcon.ShowBalloonTip(6000, "Low Disk Space",
                    "Drive C: is $($d.DPct)% full - only $($d.DFree) GB free",
                    [Windows.Forms.ToolTipIcon]::Warning)
            }
        }

        $script:tickCount++
    } catch {
        Write-Log -Message "Do-Refresh failed during live data update" -Level ERROR -ExceptionRecord $_
        $d = $null    # graceful fallback -- UI retains last-known-good values
    }
}

# Timer: fires every 3 seconds
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ Do-Refresh })
$timer.Start()

$refreshBtn.Add_Click({ Do-Refresh })

$pGrid.Add_CellClick({
    param($sender, $e)

    # Only act on the Kill column (index 4), not header row
    if ($e.RowIndex -lt 0 -or $e.ColumnIndex -ne 4) { return }

    $row         = $sender.Rows[$e.RowIndex]
    $processName = $row.Cells[0].Value.ToString().Trim()
    $pid         = [int]$row.Cells[3].Value

    Invoke-KillProcess -Pid $pid -ProcessName $processName
})

$script:realExit = $false

$form.Add_FormClosing({
    param($sender, $e)
    if (-not $script:realExit) {
        $e.Cancel = $true
        $form.Hide()
        if (-not $script:trayHintShown) {
            $script:trayHintShown = $true
            $trayIcon.ShowBalloonTip(3000, "PC Health Monitor",
                "Still running in the background. Right-click the tray icon to restore or exit.",
                [Windows.Forms.ToolTipIcon]::Info)
        }
    } else {
        $timer.Stop()
        $timer.Dispose()
        $trayIcon.Visible = $false
        $trayIcon.Dispose()
    }
})
#endregion

#region 7 - Execution
# Session start log entry
Write-Log -Message "Session started. Privileges: $(if ($script:isAdmin) {'Administrator'} else {'Standard User'})" -Level INFO

# -- Launch --------------------------------------------------------------
[void]$form.ShowDialog()
#endregion
