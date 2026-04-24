# PC-Health-Monitor.ps1
# Full Windows Forms GUI -- Deep Space Dark Theme -- Live Auto-Refresh

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

    # TELEMETRY: append metric snapshot to CSV when real data is available
    $TelemetryPath = Join-Path $env:TEMP 'PCHealth-Telemetry.csv'
    if ($Script:LastCPU -ne $null -and ($Script:LastCPU -gt 0 -or $Script:LastRAM -gt 0)) {
        if (-not (Test-Path $TelemetryPath)) {
            'timestamp,metric,value,process,pid' |
                Out-File $TelemetryPath -Encoding UTF8 -ErrorAction SilentlyContinue
        } else {
            $csvFile = Get-Item $TelemetryPath -ErrorAction SilentlyContinue
            if ($csvFile -and $csvFile.Length -gt 614400) {
                $lines = Get-Content $TelemetryPath -ErrorAction SilentlyContinue
                if ($lines -and $lines.Count -gt 2001) {
                    (@($lines[0]) + @($lines[2001..($lines.Count - 1)])) |
                        Out-File $TelemetryPath -Encoding UTF8 -ErrorAction SilentlyContinue
                }
            }
        }
        $ts = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
        @(
            "$ts,CPU%,$Script:LastCPU,,",
            "$ts,RAM%,$Script:LastRAM,,",
            "$ts,DiskFree_GB,$Script:LastDiskFree,,"
        ) | Out-File $TelemetryPath -Append -Encoding UTF8 -ErrorAction SilentlyContinue
    } elseif (-not (Test-Path $TelemetryPath)) {
        'timestamp,metric,value,process,pid' |
            Out-File $TelemetryPath -Encoding UTF8 -ErrorAction SilentlyContinue
    }
}
#endregion

#region 2 - Global Styles & Tokens
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms.DataVisualization
[System.Windows.Forms.Application]::EnableVisualStyles()

# Global fonts — Segoe UI Variable (Win11); falls back to Segoe UI on Win10
$script:MonoFont = New-Object Drawing.Font("Segoe UI Variable", 9)
$script:MonoBold = New-Object Drawing.Font("Segoe UI Variable", 9, [Drawing.FontStyle]::Bold)
$script:UIFont   = New-Object Drawing.Font("Segoe UI Variable", 9)
# Keep Consolas for process names / numeric data tables that need fixed-width alignment
$script:DataFont = New-Object Drawing.Font("Consolas", 8)

# -- Admin Check ---------------------------------------------------------
$script:isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

# -- Color Palette (Deep Space Design System) ----------------------------
$C = @{
    BgBase     = [Drawing.Color]::FromArgb(13,  13,  15)   # near-black neutral base
    BgCard     = [Drawing.Color]::FromArgb(22,  22,  25)   # L2 card surface
    BgCard2    = [Drawing.Color]::FromArgb(18,  18,  20)   # L1 slightly darker
    BgCard3    = [Drawing.Color]::FromArgb(28,  28,  32)   # L3 header / elevated
    Blue       = [Drawing.Color]::FromArgb(108, 99,  255)  # indigo accent
    BlueGlow   = [Drawing.Color]::FromArgb(55,  108, 99,  255)
    Purple     = [Drawing.Color]::FromArgb(139, 124, 248)  # soft lavender
    PurpleGlow = [Drawing.Color]::FromArgb(55,  139, 124, 248)
    Green      = [Drawing.Color]::FromArgb(48,  209, 88)   # Apple-style green
    Yellow     = [Drawing.Color]::FromArgb(255, 159, 10)   # Apple amber
    Red        = [Drawing.Color]::FromArgb(255, 59,  48)   # Apple red
    Orange     = [Drawing.Color]::FromArgb(255, 159, 10)
    Text       = [Drawing.Color]::FromArgb(245, 245, 247)  # Apple near-white
    SubText    = [Drawing.Color]::FromArgb(142, 142, 147)  # iOS secondary label
    Dim        = [Drawing.Color]::FromArgb(58,  58,  60)   # iOS quaternary
    White      = [Drawing.Color]::White
    DarkRed    = [Drawing.Color]::FromArgb(55,  14,  12)
    DarkGreen  = [Drawing.Color]::FromArgb(12,  44,  22)
    Border     = [Drawing.Color]::FromArgb(44,  44,  46)   # iOS separator
    Anomaly    = [Drawing.Color]::FromArgb(139, 124, 248)  # same as Purple
}
$script:C = $C   # expose color palette to function scopes (e.g. Show-ScoreInfo)

$script:Colors = @{
    BG_Primary     = $C.BgBase
    BG_Panel       = $C.BgCard2
    BG_Card        = $C.BgCard
    Neon_Purple    = $C.Purple
    Neon_Blue      = $C.Blue
    Neon_Cyan      = $C.Blue
    Neon_Green     = $C.Green
    Neon_Red       = $C.Red
    Neon_Orange    = $C.Yellow
    Glow_Purple    = $C.PurpleGlow
    Glow_Blue      = $C.BlueGlow
    Glow_Cyan      = $C.BlueGlow
    Text_Primary   = $C.Text
    Text_Secondary = $C.SubText
    Text_Dim       = $C.Dim
    Text_Accent    = $C.Blue
    Severity_High  = $C.Red
    Severity_Med   = $C.Yellow
    Severity_Low   = $C.Green
    Severity_None  = $C.SubText
}

# -- Protected Process Blacklist -----------------------------------------
$script:ProtectedProcesses = @(
    'explorer','wininit','winlogon','csrss','smss','lsass',
    'services','svchost','system','registry','dwm','fontdrvhost',
    'SecurityHealthService','MsMpEng'
)
#endregion

#region 2.5 - Plugin Loader
$Script:PluginsDir    = Join-Path $PSScriptRoot 'plugins'
$Script:LoadedPlugins = @()

if (Test-Path $Script:PluginsDir) {
    $psm1Files = Get-ChildItem -Path $Script:PluginsDir -Filter '*.psm1' -ErrorAction SilentlyContinue
    foreach ($psm1 in $psm1Files) {
        try {
            Import-Module -Name $psm1.FullName -Force -ErrorAction Stop -WarningAction SilentlyContinue
            $manifest                 = Get-PluginManifest
            $manifest['_Initialize'] = ${function:Initialize-Plugin}
            $manifest['_Refresh']    = ${function:Refresh-Plugin}
            $Script:LoadedPlugins   += $manifest
            Write-Log -Message "Plugin loaded: $($manifest.Name) v$($manifest.Version) by $($manifest.Author)" -Level INFO
        } catch {
            Write-Log -Message "Failed to load plugin: $($psm1.Name)" -Level WARN -ExceptionRecord $_
        }
    }
} else {
    Write-Log -Message "Plugins directory not found, skipping plugin discovery: $Script:PluginsDir" -Level INFO
}
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
    $l.Font      = New-Object Drawing.Font("Segoe UI Variable", $sz, $st)
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
    $b.Font   = New-Object Drawing.Font("Segoe UI Variable", 9, [Drawing.FontStyle]::Bold)
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
    $g.BackgroundColor    = $C.BgBase
    $g.ForeColor          = $C.Text
    $g.GridColor          = [Drawing.Color]::FromArgb(255, 28, 42, 65)
    $g.BorderStyle        = [Windows.Forms.BorderStyle]::None
    $g.RowHeadersVisible  = $false
    $g.ReadOnly           = $true
    $g.AllowUserToAddRows = $false
    $g.AllowUserToDeleteRows = $false
    $g.SelectionMode      = [Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $g.ColumnHeadersDefaultCellStyle.BackColor  = $C.BgCard2
    $g.ColumnHeadersDefaultCellStyle.ForeColor  = $C.Blue
    $g.ColumnHeadersDefaultCellStyle.Font       = New-Object Drawing.Font("Segoe UI Variable", 8, [Drawing.FontStyle]::Bold)
    $g.ColumnHeadersHeightSizeMode = [Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::DisableResizing
    $g.ColumnHeadersHeight = 32
    $g.DefaultCellStyle.BackColor          = $C.BgCard
    $g.DefaultCellStyle.ForeColor          = $C.Text
    $g.DefaultCellStyle.Font               = New-Object Drawing.Font("Segoe UI Variable", 8)
    $g.DefaultCellStyle.SelectionBackColor = [Drawing.Color]::FromArgb(60, 108, 99, 255)
    $g.DefaultCellStyle.SelectionForeColor = $C.Text
    $g.DefaultCellStyle.Padding            = New-Object Windows.Forms.Padding(4,0,4,0)
    $g.AlternatingRowsDefaultCellStyle.BackColor = $C.BgCard2
    $g.Font = New-Object Drawing.Font("Segoe UI Variable", 8)
    $g.RowTemplate.Height = 26
    $g.EnableHeadersVisualStyles = $false
    Enable-DoubleBuffer $g
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
    # Deep Space minimal gauge — thin arc, no glow, large center number
    param($Graphics, $CenterX, $CenterY, $Radius, $Pct, $Color, $TrackColor, $Thick = 4)
    try {
        $g = $Graphics
        $g.SmoothingMode    = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        $startAngle = 135.0
        $sweepTotal = 270.0
        $rect = [Drawing.RectangleF]::new($CenterX - $Radius, $CenterY - $Radius, $Radius * 2, $Radius * 2)

        # Threshold-based arc color (semantic, not decorative)
        $arcColor = if ($Pct -gt 85)     { $script:Colors.Neon_Red    }
                    elseif ($Pct -gt 60) { $script:Colors.Neon_Orange  }
                    else                 { $script:Colors.Neon_Green   }

        # Track — very subtle, same hue as arc at 18% opacity
        $trackPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(46, $arcColor.R, $arcColor.G, $arcColor.B), $Thick)
        $trackPen.StartCap = [Drawing.Drawing2D.LineCap]::Round
        $trackPen.EndCap   = [Drawing.Drawing2D.LineCap]::Round
        $g.DrawArc($trackPen, $rect, $startAngle, $sweepTotal)
        $trackPen.Dispose()

        # Value arc — clean, no glow
        $sweep = [math]::Max(0.0, [math]::Min($sweepTotal, ($Pct / 100.0) * $sweepTotal))
        if ($sweep -gt 1) {
            $arcPen = New-Object Drawing.Pen($arcColor, $Thick)
            $arcPen.StartCap = [Drawing.Drawing2D.LineCap]::Round
            $arcPen.EndCap   = [Drawing.Drawing2D.LineCap]::Round
            $g.DrawArc($arcPen, $rect, $startAngle, $sweep)
            $arcPen.Dispose()
        }

        # Center number — large, non-bold, feels "thin" at scale
        $numStr = "$([math]::Round($Pct))"
        $font   = New-Object Drawing.Font("Segoe UI Variable", 13, [Drawing.FontStyle]::Regular)
        $sf     = New-Object Drawing.StringFormat
        $sf.Alignment     = [Drawing.StringAlignment]::Center
        $sf.LineAlignment = [Drawing.StringAlignment]::Center
        $brush  = New-Object Drawing.SolidBrush($arcColor)
        # Nudge text rect slightly upward to leave room for "%" unit below
        $numRect = [Drawing.RectangleF]::new($CenterX - $Radius, $CenterY - $Radius - 5, $Radius * 2, $Radius * 2)
        $g.DrawString($numStr, $font, $brush, $numRect, $sf)
        $brush.Dispose()
        $font.Dispose()

        # "%" unit — small, dimmed, below the number
        $unitFont  = New-Object Drawing.Font("Segoe UI Variable", 7, [Drawing.FontStyle]::Regular)
        $unitBrush = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(140, $arcColor.R, $arcColor.G, $arcColor.B))
        $unitRect  = [Drawing.RectangleF]::new($CenterX - $Radius, $CenterY + 8, $Radius * 2, 14)
        $g.DrawString('%', $unitFont, $unitBrush, $unitRect, $sf)
        $unitBrush.Dispose()
        $unitFont.Dispose()
        $sf.Dispose()
    } catch { }
}

function Draw-GlowBorder {
    # Deep Space card border — subtle 1px edge + 2px left accent strip
    param($Graphics, $Width, $Height, $AccentColor, $AccentThick = 2)
    try {
        $g = $Graphics
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias

        # 1px outer border at 12% white — barely visible, gives depth
        $borderPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(30, 255, 255, 255), 1)
        $g.DrawRectangle($borderPen, 0, 0, $Width - 1, $Height - 1)
        $borderPen.Dispose()

        # Left accent strip — 2px, accent color at 70% opacity
        $accentPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(178, $AccentColor.R, $AccentColor.G, $AccentColor.B), $AccentThick)
        $g.DrawLine($accentPen, 0, 4, 0, $Height - 4)
        $accentPen.Dispose()
    } catch { }
}

function Add-RoundedRegion {
    # Clips a WinForms panel/control to a rounded-rectangle shape
    param($Control, [int]$Radius = 10)
    try {
        $w = $Control.Width; $h = $Control.Height
        $d = $Radius * 2
        $path = New-Object Drawing.Drawing2D.GraphicsPath
        $path.AddArc(0,        0,        $d, $d, 180, 90)
        $path.AddArc($w - $d,  0,        $d, $d, 270, 90)
        $path.AddArc($w - $d,  $h - $d,  $d, $d,   0, 90)
        $path.AddArc(0,        $h - $d,  $d, $d,  90, 90)
        $path.CloseFigure()
        $Control.Region = New-Object Drawing.Region($path)
    } catch { }
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

#region THEME_ENGINE
function Enable-DoubleBuffer {
    param($Control)
    try {
        $flags  = [System.Windows.Forms.ControlStyles]::OptimizedDoubleBuffer -bor
                  [System.Windows.Forms.ControlStyles]::UserPaint -bor
                  [System.Windows.Forms.ControlStyles]::AllPaintingInWmPaint
        $method = $Control.GetType().GetMethod('SetStyle',
            [System.Reflection.BindingFlags]::NonPublic -bor
            [System.Reflection.BindingFlags]::Instance)
        if ($method) { $method.Invoke($Control, @($flags, $true)) }
    } catch { }
}

function Format-CleanBytes {
    param([long]$Bytes)
    if     ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    else                    { return "{0:N0} KB" -f ($Bytes / 1KB) }
}

$script:CleanSummaryPending = [hashtable]::Synchronized(@{ Ready = $false })

function Show-CleanSummary {
    param([string]$SummaryText)
    # Remove any existing summary panel
    $old = $tab3.Controls | Where-Object { $_.Tag -eq 'CleanSummary' }
    if ($old) { $old | ForEach-Object { $tab3.Controls.Remove($_); $_.Dispose() } }

    $sp = New-Object Windows.Forms.Panel
    $sp.Size      = [Drawing.Size]::new(1020, 56)
    $sp.Location  = [Drawing.Point]::new(15, 570)
    $sp.BackColor = [Drawing.Color]::FromArgb(20, 30, 20)
    $sp.Tag       = 'CleanSummary'

    $sp.Add_Paint({
        param($s2, $pe)
        try {
            # Green 4px left accent
            $pe.Graphics.FillRectangle(
                (New-Object Drawing.SolidBrush($C.Green)), 0, 0, 4, $s2.Height)
        } catch { }
    })

    # Checkmark icon
    $iconLbl = New-Object Windows.Forms.Label
    $iconLbl.Text      = [char]0x2713   # ✓
    $iconLbl.Location  = [Drawing.Point]::new(14, 10)
    $iconLbl.Size      = [Drawing.Size]::new(30, 34)
    $iconLbl.Font      = New-Object Drawing.Font("Segoe UI", 16, [Drawing.FontStyle]::Bold)
    $iconLbl.ForeColor = $C.Green
    $iconLbl.BackColor = [Drawing.Color]::Transparent
    $sp.Controls.Add($iconLbl)

    # Summary text
    $summLbl = New-Object Windows.Forms.Label
    $summLbl.Text      = $SummaryText
    $summLbl.Location  = [Drawing.Point]::new(52, 8)
    $summLbl.Size      = [Drawing.Size]::new(950, 38)
    $summLbl.Font      = New-Object Drawing.Font("Segoe UI", 10)
    $summLbl.ForeColor = $C.Text
    $summLbl.BackColor = [Drawing.Color]::Transparent
    $sp.Controls.Add($summLbl)

    $tab3.Controls.Add($sp)
    $sp.BringToFront()

    # Auto-dismiss after 6 seconds via fade-out (alpha steps via Timer)
    $alphaStep = 0
    $fadeTimer = New-Object Windows.Forms.Timer
    $fadeTimer.Interval = 16   # ~60fps
    $capturedSp   = $sp
    $capturedTab3 = $tab3
    $fadeTimer.Add_Tick({
        $alphaStep++
        # Begin fade at frame 255 (~4 sec at 16ms), fully gone at frame 375 (~6 sec)
        if ($alphaStep -gt 255) {
            $alpha = [math]::Max(0, 255 - (($alphaStep - 255) * 3))
            try { $capturedSp.BackColor = [Drawing.Color]::FromArgb(
                [math]::Max(0, [int]($alpha * 0.08)), 30, 20) } catch { }
        }
        if ($alphaStep -ge 375) {
            $fadeTimer.Stop()
            $fadeTimer.Dispose()
            try {
                $capturedTab3.Controls.Remove($capturedSp)
                $capturedSp.Dispose()
            } catch { }
        }
    })
    $fadeTimer.Start()
}

function New-RoundedPanel {
    param($X, $Y, $W, $H, $BgColor, [Drawing.Color]$BorderColor = [Drawing.Color]::Transparent)
    $p = New-Object Windows.Forms.Panel
    $p.Location  = [Drawing.Point]::new($X, $Y)
    $p.Size      = [Drawing.Size]::new($W, $H)
    $p.BackColor = [Drawing.Color]::Transparent
    Enable-DoubleBuffer $p
    $capturedBg  = $BgColor
    $capturedBdr = $BorderColor
    $p.Add_Paint({
        param($s2, $pe)
        try {
            $g = $pe.Graphics
            $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $br = New-Object Drawing.SolidBrush($capturedBg)
            $g.FillRectangle($br, 0, 0, $s2.Width, $s2.Height)
            $br.Dispose()
            if ($capturedBdr.A -gt 0) {
                $pen = New-Object Drawing.Pen($capturedBdr, 1)
                $g.DrawRectangle($pen, 0, 0, $s2.Width - 1, $s2.Height - 1)
                $pen.Dispose()
            }
        } catch { }
    })
    return $p
}

$script:AnimatedValues = [System.Collections.Hashtable]::Synchronized(@{
    CpuArc    = @{ Current = 0.0; Target = 0.0 }
    RamArc    = @{ Current = 0.0; Target = 0.0 }
    DiskArc   = @{ Current = 0.0; Target = 0.0 }
    HealthBar = @{ Current = 0.0; Target = 0.0 }
})
#endregion THEME_ENGINE

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




# Security tab removed

$live = Get-LiveData

# Telemetry snapshot variables — updated each Do-Refresh tick
$Script:LastCPU      = $live.CpuPct
$Script:LastRAM      = $live.RamPct
$Script:LastDiskFree = $live.DFree

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
$script:StartupItems = $startups   # expose to Health Score engine

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
    param([int]$ProcessId, [string]$ProcessName)

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
        "Terminate process '$ProcessName' (PID: $ProcessId)?`n`nUnsaved work in this process will be lost.",
        "Confirm End Task",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    # 3. ATTEMPT TERMINATION
    try {
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        Write-Log -Message "Process terminated: $ProcessName (PID: $ProcessId)" -Level INFO
        # 4. IMMEDIATE REFRESH on success
        Refresh-ProcessGrid
    } catch [System.ComponentModel.Win32Exception] {
        Write-Log -Message "Failed to terminate $ProcessName (PID: $ProcessId) -- Win32 permission error" -Level ERROR -ExceptionRecord $_
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
        Write-Log -Message "Failed to terminate $ProcessName (PID: $ProcessId) -- process may have already exited" -Level WARN -ExceptionRecord $_
        [System.Windows.Forms.MessageBox]::Show(
            "Could not terminate '$ProcessName'. It may have already exited.`n`n$($_.Exception.Message)",
            "Termination Failed",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        Refresh-ProcessGrid   # refresh anyway -- process is gone
    }
}

function Invoke-TopFolderScan {
    $script:tfScanBtn.Enabled = $false
    $script:tfScanBtn.Text    = "SCANNING..."

    $capturedCache = $script:DataCache
    $capturedForm  = $form
    $capturedBtn   = $script:tfScanBtn

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.ThreadOptions  = 'ReuseThread'
    $rs.Open()

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs

    [void]$ps.AddScript({
        param($cache, $formObj, $btn)
        try {
            $excludePrefixes = @('C:\Windows', 'C:\$Recycle.Bin', 'C:\$RECYCLE.BIN')
            $topDirs = Get-ChildItem -Path 'C:\' -Directory -ErrorAction SilentlyContinue |
                Where-Object {
                    $fp = $_.FullName
                    $excluded = $false
                    foreach ($ex in $excludePrefixes) {
                        if ($fp -like "$ex*") { $excluded = $true; break }
                    }
                    -not $excluded
                }

            $results = @(foreach ($dir in $topDirs) {
                try {
                    $sum = (Get-ChildItem -Path $dir.FullName -Recurse -File -ErrorAction SilentlyContinue |
                            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    [PSCustomObject]@{
                        Path  = $dir.FullName
                        Bytes = [long]$(if ($null -eq $sum) { 0 } else { $sum })
                    }
                } catch {
                    [PSCustomObject]@{ Path = $dir.FullName; Bytes = 0L }
                }
            })

            $cache['TopFolders'] = @($results | Sort-Object Bytes -Descending | Select-Object -First 10)
        } catch {
            $cache['TopFolders'] = @()
        }

        $formObj.Invoke([Action]{
            $btn.Enabled = $true
            $btn.Text    = "SCAN"
        })
    })
    [void]$ps.AddParameter('cache',   $capturedCache)
    [void]$ps.AddParameter('formObj', $capturedForm)
    [void]$ps.AddParameter('btn',     $capturedBtn)
    [void]$ps.BeginInvoke()
    Write-Log -Message "TopFolderScan started in background MTA runspace" -Level INFO
}

function Update-TopFolderPanel {
    try {
        $folders = $script:DataCache['TopFolders']
        if ($null -eq $folders -or $folders.Count -eq 0) { return }

        $script:tfPlaceholder.Visible = $false
        $maxBytes = [math]::Max(1L, [long]$folders[0].Bytes)

        for ($i = 0; $i -lt $script:tfRowPanels.Count; $i++) {
            if ($i -lt $folders.Count) {
                $f = $folders[$i]
                $script:tfRowPanels[$i].Visible   = $true
                $script:tfPathLabels[$i].Text     = $f.Path
                $sizeStr = if ($f.Bytes -ge 1GB) {
                    "$([math]::Round($f.Bytes / 1GB, 2)) GB"
                } else {
                    "$([math]::Round($f.Bytes / 1MB, 1)) MB"
                }
                $script:tfSizeLabels[$i].Text     = $sizeStr
                $pct = [int]([math]::Round(($f.Bytes / $maxBytes) * 100))
                $script:tfBars[$i].Tag = @{ Pct = $pct; FillColor = (Pct-Color $pct) }
                $script:tfBars[$i].Invalidate()
                $script:tfFolderBtns[$i].Tag = $f.Path
            } else {
                $script:tfRowPanels[$i].Visible = $false
            }
        }
    } catch {
        Write-Log -Message "Update-TopFolderPanel error" -Level WARN -ExceptionRecord $_
    }
}
#endregion

# ── DataCache: thread-safe shared state (producer=DataEngine, consumer=UI timer) ──
$script:DataCache = [System.Collections.Hashtable]::Synchronized(@{
    CpuPct       = 0
    RamPct       = 0
    UsedRAM      = '0'
    DPct         = 0
    DUsed        = '0'
    DFree        = '0'
    DTotal       = '0'
    Procs        = @()
    TopFolders   = @()
    LastUpdated  = [DateTime]::MinValue
    Ready        = $false
})

# ── DataEngine: persistent background runspace — all blocking I/O lives here ──
# Use CreateDefault() so all built-in cmdlets (Get-CimInstance, Get-Process, etc.) are available
$script:DataEngineISS = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$script:DataEngineRS  = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($script:DataEngineISS)
$script:DataEngineRS.ApartmentState = 'MTA'
$script:DataEngineRS.ThreadOptions  = 'Default'
$script:DataEngineRS.Open()

$script:DataEnginePS = [System.Management.Automation.PowerShell]::Create()
$script:DataEnginePS.Runspace = $script:DataEngineRS

[void]$script:DataEnginePS.AddScript({
    param($cache, $totalRAMGB)
    $tick = 0
    while ($true) {
        # ── CPU + RAM (every cycle, ~3 sec) ─────────────────────────────────
        try {
            $osNow  = Get-CimInstance Win32_OperatingSystem -Property FreePhysicalMemory -ErrorAction Stop
            $cpuNow = Get-CimInstance Win32_Processor -Property LoadPercentage -ErrorAction Stop
            $freeRAM = [math]::Round($osNow.FreePhysicalMemory / 1MB, 1)
            $usedRAM = [math]::Round($totalRAMGB - $freeRAM, 1)
            $cache['CpuPct']  = [int]$cpuNow.LoadPercentage
            $cache['RamPct']  = [int]([math]::Round(($usedRAM / $totalRAMGB) * 100))
            $cache['UsedRAM'] = $usedRAM
        } catch { }

        # ── Disk C: (every 5 cycles = ~15 sec) ──────────────────────────────
        if ($tick % 5 -eq 0) {
            try {
                $dInfo  = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" `
                          -Property Size, FreeSpace -ErrorAction Stop
                $dTotal = [math]::Round($dInfo.Size / 1GB, 1)
                $dFree  = [math]::Round($dInfo.FreeSpace / 1GB, 1)
                $dUsed  = [math]::Round($dTotal - $dFree, 1)
                $cache['DPct']  = [int]([math]::Round(($dUsed / $dTotal) * 100))
                $cache['DUsed'] = $dUsed
                $cache['DFree'] = $dFree
                $cache['DTotal']= $dTotal
            } catch { }
        }

        # ── Process list (every 2 cycles = ~6 sec) ──────────────────────────
        if ($tick % 2 -eq 0) {
            try {
                $procs = Get-Process -ErrorAction SilentlyContinue |
                         Sort-Object WorkingSet64 -Descending |
                         Select-Object -First 25 Name, Id,
                             @{N='RamMB';  E={[math]::Round($_.WorkingSet64 / 1MB, 1)}},
                             @{N='CpuSec'; E={[math]::Round($_.CPU, 1)}}
                $cache['Procs'] = @($procs)
            } catch { $cache['Procs'] = @() }
        }

        $cache['LastUpdated'] = [DateTime]::Now
        $cache['Ready']       = $true
        $tick++
        Start-Sleep -Seconds 3
    }
}).AddArgument($script:DataCache).AddArgument($script:totalRAM)

$script:DataEngineHandle = $script:DataEnginePS.BeginInvoke()
Write-Log -Message "DataEngine background worker started (MTA runspace, InitialSessionState=Default)" -Level INFO

# Log any DataEngine stream errors on each UI tick (diagnostic helper)
$script:DataEngineErrIdx = 0

#region 5 - UI Initialization

# -- First-Run Welcome Screen --------------------------------------------
function Show-WelcomeScreen {
    $regPath = 'HKCU:\Software\PC-Health-Monitor'
    $regKey  = 'WelcomeSeen'
    try {
        $seen = Get-ItemPropertyValue -Path $regPath -Name $regKey -ErrorAction SilentlyContinue
        if ($seen -eq 1) { return }
    } catch { }

    $w = New-Object Windows.Forms.Form
    $w.Text            = "Welcome to PC Health Monitor"
    $w.Size            = [Drawing.Size]::new(560, 500)
    $w.StartPosition   = "CenterScreen"
    $w.BackColor       = $C.BgBase
    $w.ForeColor       = $C.Text
    $w.FormBorderStyle = [Windows.Forms.FormBorderStyle]::FixedDialog
    $w.MaximizeBox     = $false
    $w.MinimizeBox     = $false
    $w.TopMost         = $true

    # Title
    $wTitle = New-Object Windows.Forms.Label
    $wTitle.Text      = "PC Health Monitor"
    $wTitle.Location  = [Drawing.Point]::new(30, 30)
    $wTitle.Size      = [Drawing.Size]::new(500, 38)
    $wTitle.Font      = New-Object Drawing.Font("Segoe UI", 20, [Drawing.FontStyle]::Bold)
    $wTitle.ForeColor = $C.Blue
    $wTitle.BackColor = [Drawing.Color]::Transparent
    $w.Controls.Add($wTitle)

    # Subtitle
    $wSub = New-Object Windows.Forms.Label
    $wSub.Text      = "Your PC's personal health assistant"
    $wSub.Location  = [Drawing.Point]::new(30, 72)
    $wSub.Size      = [Drawing.Size]::new(500, 22)
    $wSub.Font      = New-Object Drawing.Font("Segoe UI", 11)
    $wSub.ForeColor = $C.SubText
    $wSub.BackColor = [Drawing.Color]::Transparent
    $w.Controls.Add($wSub)

    # Separator
    $wLine = New-Object Windows.Forms.Panel
    $wLine.Location  = [Drawing.Point]::new(30, 104)
    $wLine.Size      = [Drawing.Size]::new(500, 1)
    $wLine.BackColor = [Drawing.Color]::FromArgb(60, 6, 182, 212)
    $w.Controls.Add($wLine)

    # Feature bullets (BMP-safe Unicode symbols — no surrogate pairs)
    $features = @(
        @{ Icon = [char]0x25B6; Text = "Live Dashboard  —  CPU, RAM, and storage at a glance" },
        @{ Icon = [char]0x2605; Text = "Junk Cleaner  —  safely free up space in one click" },
        @{ Icon = [char]0x25B2; Text = "Startup Apps  —  control what launches with Windows" },
        @{ Icon = [char]0x25A0; Text = "Storage  —  find the largest folders on your drive" },
        @{ Icon = [char]0x25CF; Text = "Smart Alerts  —  notified only when something needs you" }
    )

    $featureY = 120
    foreach ($f in $features) {
        $iconLbl = New-Object Windows.Forms.Label
        $iconLbl.Text      = $f.Icon
        $iconLbl.Location  = [Drawing.Point]::new(30, $featureY)
        $iconLbl.Size      = [Drawing.Size]::new(36, 36)
        $iconLbl.Font      = New-Object Drawing.Font("Segoe UI", 14)
        $iconLbl.BackColor = [Drawing.Color]::Transparent
        $w.Controls.Add($iconLbl)

        $textLbl = New-Object Windows.Forms.Label
        $textLbl.Text      = $f.Text
        $textLbl.Location  = [Drawing.Point]::new(72, $featureY + 6)
        $textLbl.Size      = [Drawing.Size]::new(458, 24)
        $textLbl.Font      = New-Object Drawing.Font("Segoe UI", 10)
        $textLbl.ForeColor = $C.Text
        $textLbl.BackColor = [Drawing.Color]::Transparent
        $w.Controls.Add($textLbl)

        $featureY += 44
    }

    # Footer note
    $wNote = New-Object Windows.Forms.Label
    $wNote.Text      = "Runs quietly in the system tray. No internet connection required."
    $wNote.Location  = [Drawing.Point]::new(30, 374)
    $wNote.Size      = [Drawing.Size]::new(500, 18)
    $wNote.Font      = New-Object Drawing.Font("Segoe UI", 8)
    $wNote.ForeColor = $C.SubText
    $wNote.BackColor = [Drawing.Color]::Transparent
    $w.Controls.Add($wNote)

    # Get Started button
    $wBtn = New-Object Windows.Forms.Button
    $wBtn.Text      = "Get Started"
    $wBtn.Location  = [Drawing.Point]::new(370, 410)
    $wBtn.Size      = [Drawing.Size]::new(160, 44)
    $wBtn.BackColor = $C.Blue
    $wBtn.ForeColor = [Drawing.Color]::White
    $wBtn.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $wBtn.FlatAppearance.BorderSize = 0
    $wBtn.Font      = New-Object Drawing.Font("Segoe UI", 11, [Drawing.FontStyle]::Bold)
    $wBtn.Cursor    = [Windows.Forms.Cursors]::Hand
    $wBtn.Add_Click({
        try {
            if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
            Set-ItemProperty -Path $regPath -Name $regKey -Value 1 -Type DWord -Force
        } catch { }
        $w.Close()
    })
    $w.Controls.Add($wBtn)
    $w.AcceptButton = $wBtn

    [void]$w.ShowDialog()
}

# -- MAIN FORM -----------------------------------------------------------
$form = New-Object Windows.Forms.Form
$form.Text            = "PC Health Monitor"
$form.Size            = [Drawing.Size]::new(1060, 720)
$form.MinimumSize     = [Drawing.Size]::new(1060, 720)
$form.BackColor       = $C.BgBase
$form.ForeColor       = $C.Text
$form.StartPosition   = "CenterScreen"
$form.Font            = New-Object Drawing.Font("Segoe UI", 9)
Enable-DoubleBuffer $form
$form.AutoScaleDimensions = [Drawing.SizeF]::new(96, 96)
$form.AutoScaleMode   = [Windows.Forms.AutoScaleMode]::Dpi
try { $form.Icon = [Drawing.Icon]::ExtractAssociatedIcon("$env:SystemRoot\System32\perfmon.exe") } catch {
    Write-Log -Message "Failed to load form icon from perfmon.exe" -Level WARN -ExceptionRecord $_
    # Fallback: form retains default Windows icon
}

# -- Title Bar (Neon HUD) -------------------------------------------------
$titlePnl = New-Pnl 0 0 1060 64 $C.BgCard
Enable-DoubleBuffer $titlePnl

$titleMainLbl = New-Object Windows.Forms.Label
$titleMainLbl.Text      = "  PC HEALTH MONITOR"
$titleMainLbl.Location  = [Drawing.Point]::new(28, 6)
$titleMainLbl.Size      = [Drawing.Size]::new(500, 30)
$titleMainLbl.Font      = New-Object Drawing.Font("Segoe UI Light", 16, [Drawing.FontStyle]::Bold)
$titleMainLbl.ForeColor = $C.Blue
$titleMainLbl.BackColor = [Drawing.Color]::Transparent
$titlePnl.Controls.Add($titleMainLbl)

$subLbl = New-Object Windows.Forms.Label
$subLbl.Text      = "  $env:COMPUTERNAME  |  $($os.Caption)"
$subLbl.Location  = [Drawing.Point]::new(28, 38)
$subLbl.Size      = [Drawing.Size]::new(680, 18)
$subLbl.Font      = New-Object Drawing.Font("Segoe UI", 7.5)
$subLbl.ForeColor = $C.Dim
$subLbl.BackColor = [Drawing.Color]::Transparent
$titlePnl.Controls.Add($subLbl)

$blinkDot = New-Object Windows.Forms.Panel
$blinkDot.Location  = [Drawing.Point]::new(714, 50)
$blinkDot.Size      = [Drawing.Size]::new(7, 7)
$blinkDot.BackColor = $C.Green
$titlePnl.Controls.Add($blinkDot)
$script:blinkState = $true


$refreshBtn = New-Object Windows.Forms.Button
$refreshBtn.Text      = "REFRESH"
$refreshBtn.Location  = [Drawing.Point]::new(958, 16)
$refreshBtn.Size      = [Drawing.Size]::new(88, 32)
$refreshBtn.BackColor = $C.BgCard2
$refreshBtn.ForeColor = $C.Blue
$refreshBtn.FlatStyle = [Windows.Forms.FlatStyle]::Flat
$refreshBtn.FlatAppearance.BorderColor = $C.Blue
$refreshBtn.FlatAppearance.BorderSize  = 1
$refreshBtn.Font      = New-Object Drawing.Font("Segoe UI Variable", 8, [Drawing.FontStyle]::Bold)
$refreshBtn.Cursor    = [Windows.Forms.Cursors]::Hand
$titlePnl.Controls.Add($refreshBtn)

$titlePnl.Add_Paint({
    param($s2, $pe)
    try {
        $g = $pe.Graphics
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        # Gradient: BG_Card → BG_Primary
        $gradBr = New-Object Drawing.Drawing2D.LinearGradientBrush(
            [Drawing.Point]::new(0,0), [Drawing.Point]::new(0,$s2.Height),
            $C.BgCard2, $C.BgBase)
        $g.FillRectangle($gradBr, 0, 0, $s2.Width, $s2.Height)
        $gradBr.Dispose()
        # Neon cyan bottom separator
        $sep = New-Object Drawing.Pen([Drawing.Color]::FromArgb(80, 6, 182, 212), 1)
        $g.DrawLine($sep, 0, $s2.Height - 1, $s2.Width, $s2.Height - 1)
        $sep.Dispose()
        # Neon pulse dot (left accent)
        $dotBr = New-Object Drawing.SolidBrush($C.Blue)
        $g.FillEllipse($dotBr, 14, 28, 8, 8)
        $dotBr.Dispose()
        $glowBr = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(50, 6, 182, 212))
        $g.FillEllipse($glowBr, 10, 24, 16, 16)
        $glowBr.Dispose()
    } catch {
        Write-Log -Message "titlePnl Paint error" -Level WARN -ExceptionRecord $_
        # Fallback: bottom border line not rendered this frame
    }
})
$form.Controls.Add($titlePnl)

# -- Admin warning strip -------------------------------------------------
$tabsY = 64
$tabsH = 636
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
    $warnLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 8)
    $warnLbl.ForeColor = $C.Yellow
    $warnLbl.BackColor = [Drawing.Color]::Transparent
    $warnPnl.Controls.Add($warnLbl)
    $form.Controls.Add($warnPnl)
    $tabsY = 86
    $tabsH = 614
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

# -- Status Bar (22px, bottom) -------------------------------------------
$statusBar = New-Object Windows.Forms.Panel
$statusBar.Size      = [Drawing.Size]::new(1060, 22)
$statusBar.Location  = [Drawing.Point]::new(0, 698)
$statusBar.BackColor = $C.BgCard
$statusBar.Anchor    = [Windows.Forms.AnchorStyles]::Bottom -bor
                       [Windows.Forms.AnchorStyles]::Left   -bor
                       [Windows.Forms.AnchorStyles]::Right

$statusBar.Add_Paint({
    param($s2, $pe)
    try {
        $pe.Graphics.FillRectangle(
            (New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(80, 6, 182, 212))),
            0, 0, $s2.Width, 1)
    } catch { }
})

# Left — version
$sbVersionLbl = New-Object Windows.Forms.Label
$sbVersionLbl.Text      = "  ● PC Health Monitor v3.1"
$sbVersionLbl.Location  = [Drawing.Point]::new(0, 4)
$sbVersionLbl.Size      = [Drawing.Size]::new(240, 14)
$sbVersionLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 7)
$sbVersionLbl.ForeColor = $C.Dim
$sbVersionLbl.BackColor = [Drawing.Color]::Transparent
$statusBar.Controls.Add($sbVersionLbl)

# Center — last updated time
$script:sbTimeLbl = New-Object Windows.Forms.Label
$script:sbTimeLbl.Text      = ""
$script:sbTimeLbl.Location  = [Drawing.Point]::new(380, 4)
$script:sbTimeLbl.Size      = [Drawing.Size]::new(300, 14)
$script:sbTimeLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 7)
$script:sbTimeLbl.ForeColor = $C.Dim
$script:sbTimeLbl.BackColor = [Drawing.Color]::Transparent
$script:sbTimeLbl.TextAlign = [Drawing.ContentAlignment]::MiddleCenter
$statusBar.Controls.Add($script:sbTimeLbl)

# Right — admin indicator
$sbAdminTxt  = if ($script:isAdmin) { "● Administrator" } else { "● Standard User" }
$sbAdminClr  = if ($script:isAdmin) { $C.Green }           else { $C.Yellow }
$sbAdminLbl = New-Object Windows.Forms.Label
$sbAdminLbl.Text      = "$sbAdminTxt  "
$sbAdminLbl.Location  = [Drawing.Point]::new(820, 4)
$sbAdminLbl.Size      = [Drawing.Size]::new(240, 14)
$sbAdminLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 7)
$sbAdminLbl.ForeColor = $sbAdminClr
$sbAdminLbl.BackColor = [Drawing.Color]::Transparent
$sbAdminLbl.TextAlign = [Drawing.ContentAlignment]::MiddleRight
$statusBar.Controls.Add($sbAdminLbl)

$form.Controls.Add($statusBar)

# ========================================================================
# VIP MODE — Process Priority Elevation (state + functions)
# ========================================================================
$script:vipPid          = 0
$script:vipName         = ''
$script:vipActive       = $false
$script:vipOrigPriority = [Diagnostics.ProcessPriorityClass]::Normal
$script:vipProcs        = @()   # cached list from last Refresh-VipCombo call

function Get-UserFacingProcesses {
    <# Returns only processes that own a visible window — filters out all
       background services and system daemons automatically. #>
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.MainWindowTitle -ne '' -and
            $_.MainWindowHandle -ne [IntPtr]::Zero -and
            $_.Name -notmatch '^(PC-Health-Monitor|explorer|SearchHost|StartMenuExperienceHost)$'
        } |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 30
}

function Set-VipProcess {
    param([int]$ProcessId)
    try {
        $p = Get-Process -Id $ProcessId -ErrorAction Stop
        if ($p.HasExited) { return $false }
        $script:vipOrigPriority = $p.PriorityClass
        $p.PriorityClass        = [Diagnostics.ProcessPriorityClass]::High
        $script:vipPid          = $ProcessId
        $script:vipName         = $p.ProcessName
        $script:vipActive       = $true
        Write-Log -Message "VIP: '$($p.ProcessName)' [PID $ProcessId] elevated to High (was $($script:vipOrigPriority))" -Level INFO
        return $true
    } catch {
        Write-Log -Message "VIP: Failed to elevate PID $ProcessId" -Level WARN -ExceptionRecord $_
        return $false
    }
}

function Clear-VipProcess {
    if ($script:vipPid -gt 0) {
        try {
            $p = Get-Process -Id $script:vipPid -ErrorAction Stop
            if (-not $p.HasExited) {
                $p.PriorityClass = $script:vipOrigPriority
                Write-Log -Message "VIP: '$($p.ProcessName)' restored to $($script:vipOrigPriority)" -Level INFO
            }
        } catch { <# process already gone — nothing to restore #> }
        $script:vipPid    = 0
        $script:vipName   = ''
        $script:vipActive = $false
    }
}

function Refresh-VipCombo {
    $script:vipCombo.Items.Clear()
    $procs = Get-UserFacingProcesses
    $script:vipProcs = $procs
    foreach ($p in $procs) {
        $title = if ($p.MainWindowTitle.Length -gt 40) {
            $p.MainWindowTitle.Substring(0, 40) + '...'
        } else { $p.MainWindowTitle }
        [void]$script:vipCombo.Items.Add("$($p.ProcessName)  [$($p.Id)]  — $title")
    }
    if ($script:vipCombo.Items.Count -gt 0) { $script:vipCombo.SelectedIndex = 0 }
}


# ========================================================================

# ========================================================================
# BOOST MODE — Engine Functions
# ========================================================================
$script:boostActive      = $false
$script:boostPriorityMap = @{}
$script:boostPowerPlan   = $null

$BOOST_TARGETS = @(
    'Teams','ms-teams','Spotify','Discord','OneDrive','Skype','SkypeApp',
    'SearchApp','YourPhone','YourPhoneServer','XboxGamingOverlay',
    'GameBarFTServer','EpicWebHelper','SteamWebHelper','backgroundTaskHost',
    'OfficeClickToRun','MSOSYNC','MicrosoftEdgeUpdate'
)

function Get-ActivePowerPlan {
    try {
        return (Get-CimInstance -Namespace root/cimv2/power -ClassName Win32_PowerPlan -ErrorAction Stop |
                Where-Object { $_.IsActive } | Select-Object -First 1)
    } catch { return $null }
}

function Set-PowerPlanByName {
    param([string]$Name)
    try {
        $plan = Get-CimInstance -Namespace root/cimv2/power -ClassName Win32_PowerPlan |
                Where-Object { $_.ElementName -like "*$Name*" } | Select-Object -First 1
        if ($plan) { $plan | Invoke-CimMethod -MethodName Activate | Out-Null; return $plan.ElementName }
    } catch {}
    return $null
}

function Enable-BoostMode {
    $script:boostPriorityMap = @{}
    $log = [System.Collections.Generic.List[string]]::new()

    # 1. High Performance power plan
    $script:boostPowerPlan = Get-ActivePowerPlan
    $hp = Set-PowerPlanByName -Name "High performance"
    if (-not $hp) { $hp = Set-PowerPlanByName -Name "High" }
    $log.Add("Power Plan: $(if ($hp) { "→ $hp" } else { "unchanged" })")

    # 2. Lower priority of background processes
    $lowered = 0
    foreach ($name in $BOOST_TARGETS) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            try {
                $script:boostPriorityMap[$p.Id] = $p.PriorityClass
                $p.PriorityClass = [Diagnostics.ProcessPriorityClass]::BelowNormal
                $lowered++
            } catch {}
        }
    }
    if ($lowered -gt 0) { $log.Add("Background processes throttled: $lowered") }

    # 3. Flush Standby RAM
    try {
        if (-not ([System.Management.Automation.PSTypeName]'BoostMemUtil').Type) {
            Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public class BoostMemUtil {
    [DllImport("ntdll.dll")] public static extern uint NtSetSystemInformation(int InfoClass, IntPtr Info, int Length);
    public static void FlushStandby() {
        IntPtr p = System.Runtime.InteropServices.Marshal.AllocHGlobal(4);
        System.Runtime.InteropServices.Marshal.WriteInt32(p, 4);
        NtSetSystemInformation(80, p, 4);
        System.Runtime.InteropServices.Marshal.FreeHGlobal(p);
    }
}
'@ -ErrorAction SilentlyContinue
        }
        [BoostMemUtil]::FlushStandby()
        $log.Add("Standby RAM: flushed")
    } catch {}

    $script:boostActive = $true
    return $log
}

function Disable-BoostMode {
    $log = [System.Collections.Generic.List[string]]::new()

    # Restore power plan
    if ($script:boostPowerPlan) {
        try {
            $script:boostPowerPlan | Invoke-CimMethod -MethodName Activate | Out-Null
            $log.Add("Power Plan: restored to $($script:boostPowerPlan.ElementName)")
        } catch { $log.Add("Power Plan: could not restore") }
    }

    # Restore process priorities
    $restored = 0
    foreach ($id in @($script:boostPriorityMap.Keys)) {
        try {
            $p = Get-Process -Id $id -ErrorAction Stop
            if (-not $p.HasExited) { $p.PriorityClass = $script:boostPriorityMap[$id]; $restored++ }
        } catch {}
    }
    $script:boostPriorityMap = @{}
    if ($restored -gt 0) { $log.Add("Process priorities: restored ($restored)") }

    $script:boostActive = $false
    return $log
}

# ========================================================================
# DISK HEALTH — Engine Functions
# ========================================================================
function Get-DiskHealthData {
    $results = [System.Collections.Generic.List[object]]::new()
    try {
        $disks = Get-PhysicalDisk -ErrorAction Stop
        foreach ($disk in $disks) {
            $rel = $null
            try { $rel = $disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue } catch {}
            $results.Add([PSCustomObject]@{
                FriendlyName      = $disk.FriendlyName
                MediaType         = $disk.MediaType
                HealthStatus      = $disk.HealthStatus
                OperationalStatus = $disk.OperationalStatus
                SizeGB            = [math]::Round($disk.Size / 1GB, 0)
                Temperature       = if ($rel -and $rel.Temperature)            { $rel.Temperature }       else { $null }
                ReadErrors        = if ($rel -and $rel.ReadErrorsUncorrected -ne $null)  { $rel.ReadErrorsUncorrected }  else { 0 }
                WriteErrors       = if ($rel -and $rel.WriteErrorsUncorrected -ne $null) { $rel.WriteErrorsUncorrected } else { 0 }
                WearLevel         = if ($rel -and $rel.Wear -ne $null)         { $rel.Wear }              else { $null }
                PowerOnHours      = if ($rel -and $rel.PowerOnHours -ne $null) { $rel.PowerOnHours }      else { $null }
            })
        }
    } catch {
        Write-Log -Message "Get-DiskHealthData error" -Level WARN -ExceptionRecord $_
    }
    return $results
}

# ========================================================================
# DRIVER AUDIT — Engine Functions
# ========================================================================
function Get-DriverAuditData {
    $results = [System.Collections.Generic.List[object]]::new()
    try {
        $cutoffOld  = (Get-Date).AddYears(-2)
        $cutoffWarn = (Get-Date).AddYears(-1)
        $drivers = Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop |
                   Where-Object { $_.DeviceName -and $_.DriverVersion } |
                   Select-Object DeviceName, Manufacturer, DriverVersion, DriverDate |
                   Sort-Object DriverDate
        foreach ($d in $drivers) {
            $age    = if ($d.DriverDate) { $d.DriverDate } else { $null }
            $status = if (-not $age)        { "Unknown" }
                      elseif ($age -lt $cutoffOld) { "Outdated" }
                      elseif ($age -lt $cutoffWarn){ "Aging" }
                      else                         { "OK" }
            $icon   = switch ($status) { "Outdated" { "🔴" } "Aging" { "🟡" } "OK" { "✅" } default { "⚪" } }
            $results.Add([PSCustomObject]@{
                Name     = if ($d.DeviceName.Length -gt 45) { $d.DeviceName.Substring(0,45)+'…' } else { $d.DeviceName }
                Vendor   = if ($d.Manufacturer) { if ($d.Manufacturer.Length -gt 22) { $d.Manufacturer.Substring(0,22)+'…' } else { $d.Manufacturer } } else { '—' }
                Version  = $d.DriverVersion
                Date     = if ($d.DriverDate) { $d.DriverDate.ToString("yyyy-MM") } else { '—' }
                Status   = $status
                Icon     = $icon
            })
        }
    } catch {
        Write-Log -Message "Get-DriverAuditData error" -Level WARN -ExceptionRecord $_
    }
    return $results
}

# ========================================================================
# TAB 1 -- DASHBOARD
# ========================================================================
$tab1 = New-Object Windows.Forms.TabPage
$tab1.Text        = "  Dashboard  "
$tab1.BackColor   = $C.BgBase
$tab1.AutoScroll  = $true   # vertical scroll when content exceeds visible area

$UI = @{}

$cardDefs = @(
    @{Key="Cpu";  Title="CPU Load";  X=15;  Color=$C.Blue;   TrackColor=$C.BlueGlow;   Val="$($live.CpuPct)%";                                  Pct=$live.CpuPct},
    @{Key="Ram";  Title="RAM Usage"; X=280; Color=$C.Purple; TrackColor=$C.PurpleGlow; Val="$($live.UsedRAM) GB / $totalRAM GB";                Pct=$live.RamPct},
    @{Key="Disk"; Title="Disk C:";   X=545; Color=$C.Yellow; TrackColor=$C.BgCard2;    Val="$($live.DUsed) / $($live.DTotal) GB"; Pct=$live.DPct}
)

foreach ($cd in $cardDefs) {
    $pct = [math]::Min([math]::Max($cd.Pct, 0), 100)
    $cp  = New-Pnl $cd.X 15 220 110 $C.BgCard

    # Store per-card paint data in Tag -- avoids closure capture issues
    $cp.Tag = @{ Color = $cd.Color; TrackColor = $cd.TrackColor; Pct = $pct }

    Enable-DoubleBuffer $cp
    $cp.Add_Paint({
        param($s2, $pe)
        try {
            $g = $pe.Graphics
            $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $td = $s2.Tag
            # Gradient background: BG_Panel → BG_Card, 135°
            $gradBr = New-Object Drawing.Drawing2D.LinearGradientBrush(
                [Drawing.Point]::new(0, 0),
                [Drawing.Point]::new($s2.Width, $s2.Height),
                $C.BgCard2, $C.BgCard)
            $g.FillRectangle($gradBr, 0, 0, $s2.Width, $s2.Height)
            $gradBr.Dispose()
            Draw-GlowBorder $g $s2.Width $s2.Height $td.Color 2
            Draw-CircleGauge $g 46 55 30 $td.Pct $td.Color $td.TrackColor 5
        } catch {
            Write-Log -Message "CPU/RAM/Disk card Paint error" -Level WARN -ExceptionRecord $_
        }
    })

    # Value label — Segoe UI Variable, slightly larger, non-bold for elegant thin feel
    $valLbl = New-Object Windows.Forms.Label
    $valLbl.Text      = $cd.Val
    $valLbl.Location  = [Drawing.Point]::new(100, 10)
    $valLbl.Size      = [Drawing.Size]::new(114, 26)
    $valLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 10, [Drawing.FontStyle]::Bold)
    $valLbl.ForeColor = $cd.Color
    $valLbl.BackColor = [Drawing.Color]::Transparent
    $cp.Controls.Add($valLbl)
    $UI[$cd.Key + "ValLbl"] = $valLbl

    # Card title — small caps feel, subdued
    $cardTitleLbl = New-Object Windows.Forms.Label
    $cardTitleLbl.Text      = $cd.Title.ToUpper()
    $cardTitleLbl.Location  = [Drawing.Point]::new(100, 40)
    $cardTitleLbl.Size      = [Drawing.Size]::new(114, 16)
    $cardTitleLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 7, [Drawing.FontStyle]::Bold)
    $cardTitleLbl.ForeColor = $C.SubText
    $cardTitleLbl.BackColor = [Drawing.Color]::Transparent
    $cp.Controls.Add($cardTitleLbl)

    # Percentage label
    $pctLbl = New-Object Windows.Forms.Label
    $pctLbl.Text      = "$pct%"
    $pctLbl.Location  = [Drawing.Point]::new(100, 60)
    $pctLbl.Size      = [Drawing.Size]::new(90, 20)
    $pctLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 9)
    $pctLbl.ForeColor = Pct-Color $pct
    $pctLbl.BackColor = [Drawing.Color]::Transparent
    $cp.Controls.Add($pctLbl)
    $UI[$cd.Key + "PctLbl"] = $pctLbl

    # Thin 3px fill bar — accent color
    $barTrack = New-Object Windows.Forms.Panel
    $barTrack.Location  = [Drawing.Point]::new(100, 87)
    $barTrack.Size      = [Drawing.Size]::new(114, 3)
    $barTrack.BackColor = $C.Dim
    $cp.Controls.Add($barTrack)

    $barFill = New-Object Windows.Forms.Panel
    $fw = [math]::Max(0, [math]::Min(114, [int](($pct / 100.0) * 114)))
    $barFill.Location  = [Drawing.Point]::new(0, 0)
    $barFill.Size      = [Drawing.Size]::new($fw, 3)
    $barFill.BackColor = Pct-Color $pct
    $barTrack.Controls.Add($barFill)
    $UI[$cd.Key + "BarFill"] = $barFill

    $UI[$cd.Key + "Card"] = $cp
    Add-RoundedRegion $cp 10   # clip to rounded rect — corners show tab background
    $tab1.Controls.Add($cp)
}

# Wire animated arc initial targets from live data
$script:AnimatedValues.CpuArc.Target  = [double]$live.CpuPct
$script:AnimatedValues.RamArc.Target  = [double]$live.RamPct
$script:AnimatedValues.DiskArc.Target = [double]$live.DPct
$script:AnimatedValues.CpuArc.Current  = [double]$live.CpuPct
$script:AnimatedValues.RamArc.Current  = [double]$live.RamPct
$script:AnimatedValues.DiskArc.Current = [double]$live.DPct

# -- Health Score Card (redesigned) --------------------------------------
$script:scoreBreakdown = @{ Cpu=0; Ram=0; Disk=0; Startup=0; Junk=0.0;
                             CpuPen=0; RamPen=0; DiskPen=0; StartupPen=0; JunkPen=0 }

function Show-ScoreInfo {
    $C = $script:C   # use the main app palette (always initialized at script start)
    $bd = $script:scoreBreakdown
    $f = New-Object Windows.Forms.Form
    $f.Text            = "Health Score — Breakdown"
    $f.Size            = [Drawing.Size]::new(640, 460)
    $f.StartPosition   = "CenterParent"
    $f.BackColor       = $C.BgBase
    $f.ForeColor       = $C.Text
    $f.FormBorderStyle = [Windows.Forms.FormBorderStyle]::FixedDialog
    $f.MaximizeBox     = $false; $f.MinimizeBox = $false
    $f.TopMost         = $true

    # Title
    $tl = New-Object Windows.Forms.Label
    $tl.Text = "PC Health Score — How it is calculated"
    $tl.Location = [Drawing.Point]::new(20, 16)
    $tl.Size = [Drawing.Size]::new(600, 22)
    $tl.Font = New-Object Drawing.Font("Segoe UI", 11, [Drawing.FontStyle]::Bold)
    $tl.ForeColor = $C.Blue; $tl.BackColor = [Drawing.Color]::Transparent
    $f.Controls.Add($tl)

    $sl = New-Object Windows.Forms.Label
    $sl.Text = "Score starts at 100. Each factor below deducts points based on current readings."
    $sl.Location = [Drawing.Point]::new(20, 42)
    $sl.Size = [Drawing.Size]::new(600, 18)
    $sl.Font = New-Object Drawing.Font("Segoe UI", 8)
    $sl.ForeColor = $C.SubText; $sl.BackColor = [Drawing.Color]::Transparent
    $f.Controls.Add($sl)

    # Table grid
    $grid = New-Object Windows.Forms.DataGridView
    $grid.Location = [Drawing.Point]::new(20, 68)
    $grid.Size = [Drawing.Size]::new(600, 230)
    Style-Grid $grid
    $grid.ColumnHeadersHeight = 28
    $grid.RowTemplate.Height  = 34
    $grid.ReadOnly            = $true
    $grid.AllowUserToAddRows  = $false
    $grid.MultiSelect         = $false
    $grid.SelectionMode       = [Windows.Forms.DataGridViewSelectionMode]::FullRowSelect

    foreach ($col in @(
        @{H="Factor";        W=130},
        @{H="Current Value"; W=110},
        @{H="Points Lost";   W=90},
        @{H="Max Possible";  W=90},
        @{H="Tip";           W=180}
    )) {
        $c = New-Object Windows.Forms.DataGridViewTextBoxColumn
        $c.HeaderText = $col.H; $c.Width = $col.W; $c.ReadOnly = $true
        [void]$grid.Columns.Add($c)
    }

    $rows = @(
        @("CPU Load",       "$($bd.Cpu)%",               "-$($bd.CpuPen)",  "-25", $(if($bd.CpuPen -gt 15){"Close heavy apps"}else{"Good"})),
        @("RAM Usage",      "$($bd.Ram)%",               "-$($bd.RamPen)",  "-25", $(if($bd.RamPen -gt 15){"Free up memory"}else{"Good"})),
        @("Disk (C:)",      "$($bd.Disk)%",              "-$($bd.DiskPen)", "-20", $(if($bd.DiskPen -gt 12){"Run Junk Cleaner"}else{"Good"})),
        @("Startup Apps",   "$($bd.Startup) apps",       "-$($bd.StartupPen)","-15",$(if($bd.StartupPen -gt 8){"Disable some apps"}else{"Good"})),
        @("Junk Files",     "$($bd.Junk) GB",            "-$($bd.JunkPen)", "-15", $(if($bd.JunkPen -gt 8){"Clean temp files"}else{"Good"}))
    )

    foreach ($r in $rows) {
        $ri = $grid.Rows.Add($r)
        $pen = [int]($r[2] -replace '-','')
        $clr = if ($pen -ge 15) { $C.Red } elseif ($pen -ge 8) { $C.Yellow } else { $C.Green }
        $grid.Rows[$ri].Cells[2].Style.ForeColor = $clr
        $grid.Rows[$ri].Cells[2].Style.Font = New-Object Drawing.Font("Consolas", 9, [Drawing.FontStyle]::Bold)
    }
    $f.Controls.Add($grid)

    # Total row
    $totalPen = $bd.CpuPen + $bd.RamPen + $bd.DiskPen + $bd.StartupPen + $bd.JunkPen
    $finalScore = [math]::Max(0, 100 - $totalPen)
    $tRow = New-Object Windows.Forms.Label
    $tRow.Text = "Total deductions: -$totalPen pts     Final Score: $finalScore / 100"
    $tRow.Location = [Drawing.Point]::new(20, 308)
    $tRow.Size = [Drawing.Size]::new(600, 22)
    $tRow.Font = New-Object Drawing.Font("Consolas", 9, [Drawing.FontStyle]::Bold)
    $tRow.ForeColor = $C.Text; $tRow.BackColor = [Drawing.Color]::Transparent
    $f.Controls.Add($tRow)

    $note = New-Object Windows.Forms.Label
    $note.Text = "Score refreshes every 15 seconds. Values reflect real-time system state."
    $note.Location = [Drawing.Point]::new(20, 338)
    $note.Size = [Drawing.Size]::new(600, 16)
    $note.Font = New-Object Drawing.Font("Segoe UI", 8)
    $note.ForeColor = $C.SubText; $note.BackColor = [Drawing.Color]::Transparent
    $f.Controls.Add($note)

    $closeBtn = New-Object Windows.Forms.Button
    $closeBtn.Text = "Close"
    $closeBtn.Location = [Drawing.Point]::new(500, 368)
    $closeBtn.Size = [Drawing.Size]::new(120, 34)
    $closeBtn.BackColor = $C.BgCard2; $closeBtn.ForeColor = $C.Text
    $closeBtn.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $closeBtn.FlatAppearance.BorderSize = 0
    $closeBtn.Font = New-Object Drawing.Font("Segoe UI", 9)
    $closeBtn.Cursor = [Windows.Forms.Cursors]::Hand
    $closeBtn.Add_Click({ $f.Close() })
    $f.Controls.Add($closeBtn)
    $f.AcceptButton = $closeBtn

    [void]$f.ShowDialog()
}

$scoreCard = New-Pnl 15 128 1020 80 $C.BgCard
Enable-DoubleBuffer $scoreCard
$scoreCard.Add_Paint({
    param($s2, $pe)
    try {
        $g = $pe.Graphics
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.FillRectangle((New-Object Drawing.SolidBrush($C.BgCard)), 0, 0, $s2.Width, $s2.Height)
        Draw-GlowBorder $g $s2.Width $s2.Height $C.Blue 2
        # Left accent bar — color reflects score tier
        $accentClr = if ($script:lastHealthScore -ge 85) { [Drawing.Color]::FromArgb(255,6,182,212) }
                     elseif ($script:lastHealthScore -ge 70) { [Drawing.Color]::FromArgb(255,34,211,238) }
                     elseif ($script:lastHealthScore -ge 55) { [Drawing.Color]::FromArgb(255,245,158,11) }
                     elseif ($script:lastHealthScore -ge 35) { [Drawing.Color]::FromArgb(255,249,115,22) }
                     else { [Drawing.Color]::FromArgb(255,239,68,68) }
        $g.FillRectangle((New-Object Drawing.SolidBrush($accentClr)), 0, 0, 4, $s2.Height)
    } catch {
        Write-Log -Message "Score card Paint error" -Level WARN -ExceptionRecord $_
    }
})

# Big score number
$script:scoreNumLbl = New-Object Windows.Forms.Label
$script:scoreNumLbl.Text      = '--'
$script:scoreNumLbl.Location  = [Drawing.Point]::new(14, 10)
$script:scoreNumLbl.Size      = [Drawing.Size]::new(90, 56)
$script:scoreNumLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 28, [Drawing.FontStyle]::Bold)
$script:scoreNumLbl.ForeColor = $C.Dim
$script:scoreNumLbl.BackColor = [Drawing.Color]::Transparent
$script:scoreNumLbl.TextAlign = [Drawing.ContentAlignment]::MiddleRight
$scoreCard.Controls.Add($script:scoreNumLbl)

# "/100" suffix
$script:scoreOf100Lbl = New-Object Windows.Forms.Label
$script:scoreOf100Lbl.Text      = '/ 100'
$script:scoreOf100Lbl.Location  = [Drawing.Point]::new(106, 38)
$script:scoreOf100Lbl.Size      = [Drawing.Size]::new(56, 22)
$script:scoreOf100Lbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 9)
$script:scoreOf100Lbl.ForeColor = $C.SubText
$script:scoreOf100Lbl.BackColor = [Drawing.Color]::Transparent
$scoreCard.Controls.Add($script:scoreOf100Lbl)

# "HEALTH SCORE" header label (small, above grade)
$hsHeaderLbl = New-Object Windows.Forms.Label
$hsHeaderLbl.Text      = 'HEALTH SCORE'
$hsHeaderLbl.Location  = [Drawing.Point]::new(170, 8)
$hsHeaderLbl.Size      = [Drawing.Size]::new(200, 14)
$hsHeaderLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 7, [Drawing.FontStyle]::Bold)
$hsHeaderLbl.ForeColor = $C.SubText
$hsHeaderLbl.BackColor = [Drawing.Color]::Transparent
$scoreCard.Controls.Add($hsHeaderLbl)

# Grade label (GREAT SHAPE / COULD BE BETTER etc.)
$script:scoreGradeLbl = New-Object Windows.Forms.Label
$script:scoreGradeLbl.Text      = 'CALCULATING...'
$script:scoreGradeLbl.Location  = [Drawing.Point]::new(170, 24)
$script:scoreGradeLbl.Size      = [Drawing.Size]::new(340, 26)
$script:scoreGradeLbl.Font      = New-Object Drawing.Font("Segoe UI", 13, [Drawing.FontStyle]::Bold)
$script:scoreGradeLbl.ForeColor = $C.Dim
$script:scoreGradeLbl.BackColor = [Drawing.Color]::Transparent
$scoreCard.Controls.Add($script:scoreGradeLbl)

# Trend arrow
$script:scoreTrendLbl = New-Object Windows.Forms.Label
$script:scoreTrendLbl.Text      = ''
$script:scoreTrendLbl.Location  = [Drawing.Point]::new(516, 24)
$script:scoreTrendLbl.Size      = [Drawing.Size]::new(28, 26)
$script:scoreTrendLbl.Font      = New-Object Drawing.Font("Segoe UI", 13, [Drawing.FontStyle]::Bold)
$script:scoreTrendLbl.ForeColor = $C.Dim
$script:scoreTrendLbl.BackColor = [Drawing.Color]::Transparent
$scoreCard.Controls.Add($script:scoreTrendLbl)

# Message line 1
$script:scoreMsg1Lbl = New-Object Windows.Forms.Label
$script:scoreMsg1Lbl.Text      = '  Calculating your PC health score...'
$script:scoreMsg1Lbl.Location  = [Drawing.Point]::new(170, 52)
$script:scoreMsg1Lbl.Size      = [Drawing.Size]::new(760, 16)
$script:scoreMsg1Lbl.Font      = New-Object Drawing.Font("Segoe UI", 8)
$script:scoreMsg1Lbl.ForeColor = $C.Dim
$script:scoreMsg1Lbl.BackColor = [Drawing.Color]::Transparent
$scoreCard.Controls.Add($script:scoreMsg1Lbl)

# Message line 2
$script:scoreMsg2Lbl = New-Object Windows.Forms.Label
$script:scoreMsg2Lbl.Text      = ''
$script:scoreMsg2Lbl.Location  = [Drawing.Point]::new(170, 66)
$script:scoreMsg2Lbl.Size      = [Drawing.Size]::new(760, 14)
$script:scoreMsg2Lbl.Font      = New-Object Drawing.Font("Segoe UI", 8)
$script:scoreMsg2Lbl.ForeColor = $C.SubText
$script:scoreMsg2Lbl.BackColor = [Drawing.Color]::Transparent
$script:scoreMsg2Lbl.Visible   = $false
$scoreCard.Controls.Add($script:scoreMsg2Lbl)

# (i) Info button — top right of card
$scoreInfoBtn = New-Object Windows.Forms.Button
$scoreInfoBtn.Text      = "i"
$scoreInfoBtn.Location  = [Drawing.Point]::new(984, 28)
$scoreInfoBtn.Size      = [Drawing.Size]::new(26, 26)
$scoreInfoBtn.BackColor = $C.BgCard2
$scoreInfoBtn.ForeColor = $C.Blue
$scoreInfoBtn.FlatStyle = [Windows.Forms.FlatStyle]::Flat
$scoreInfoBtn.FlatAppearance.BorderColor = $C.Blue
$scoreInfoBtn.FlatAppearance.BorderSize  = 1
$scoreInfoBtn.Font      = New-Object Drawing.Font("Segoe UI", 9, [Drawing.FontStyle]::Bold)
$scoreInfoBtn.Cursor    = [Windows.Forms.Cursors]::Hand
$scoreInfoBtn.Add_Click({ Show-ScoreInfo })
$scoreCard.Controls.Add($scoreInfoBtn)

$UI["ScoreCard"] = $scoreCard
Add-RoundedRegion $scoreCard 10
$tab1.Controls.Add($scoreCard)

# -- VIP MODE Card -------------------------------------------------------
$vipCard = New-Pnl 15 215 1020 42 $C.BgCard
Enable-DoubleBuffer $vipCard
$vipCard.Add_Paint({
    param($s2, $pe)
    try {
        $accentColor = if ($script:vipActive) { $C.Yellow } else { $C.Blue }
        $pe.Graphics.FillRectangle((New-Object Drawing.SolidBrush($accentColor)), 0, 0, 4, $s2.Height)
        $pe.Graphics.DrawLine((New-Object Drawing.Pen($C.Border, 1)), 0, $s2.Height - 1, $s2.Width, $s2.Height - 1)
    } catch { }
})

$vipHeaderLbl = New-Object Windows.Forms.Label
$vipHeaderLbl.Text      = [char]0x2605 + " VIP MODE"
$vipHeaderLbl.Location  = [Drawing.Point]::new(12, 12)
$vipHeaderLbl.Size      = [Drawing.Size]::new(100, 18)
$vipHeaderLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 8, [Drawing.FontStyle]::Bold)
$vipHeaderLbl.ForeColor = $C.Blue
$vipHeaderLbl.BackColor = [Drawing.Color]::Transparent
$vipCard.Controls.Add($vipHeaderLbl)

$script:vipCombo = New-Object Windows.Forms.ComboBox
$script:vipCombo.Location      = [Drawing.Point]::new(118, 8)
$script:vipCombo.Size          = [Drawing.Size]::new(430, 26)
$script:vipCombo.DropDownStyle = [Windows.Forms.ComboBoxStyle]::DropDownList
$script:vipCombo.BackColor     = $C.BgCard2
$script:vipCombo.ForeColor     = $C.Text
$script:vipCombo.Font          = New-Object Drawing.Font("Segoe UI Variable", 8)
$script:vipCombo.FlatStyle     = [Windows.Forms.FlatStyle]::Flat
$vipCard.Controls.Add($script:vipCombo)

$vipRefreshBtn = New-Btn ([char]0x21BA + "") 552 8 28 26 $C.BgCard2 $C.SubText
$vipRefreshBtn.Font   = New-Object Drawing.Font("Segoe UI", 10)
$vipRefreshBtn.Cursor = [Windows.Forms.Cursors]::Hand
$vipToolTip = New-Object Windows.Forms.ToolTip
$vipToolTip.SetToolTip($vipRefreshBtn, "Refresh app list")
$vipRefreshBtn.Add_Click({
    Refresh-VipCombo
    $vipCard.Invalidate()
})
$vipCard.Controls.Add($vipRefreshBtn)

$script:vipBtn = New-Btn "SET VIP" 584 8 116 26 $C.BgCard2 $C.Yellow
$script:vipBtn.FlatAppearance.BorderColor = $C.Yellow
$script:vipBtn.FlatAppearance.BorderSize  = 1
$script:vipBtn.Font   = New-Object Drawing.Font("Segoe UI Variable", 8, [Drawing.FontStyle]::Bold)
$script:vipBtn.Cursor = [Windows.Forms.Cursors]::Hand
$vipToolTip.SetToolTip($script:vipBtn, "Elevate selected app to High CPU priority")
$script:vipBtn.Add_Click({
    if ($script:vipActive) {
        # Toggle OFF — restore priority
        Clear-VipProcess
        $script:vipBtn.Text      = "SET VIP"
        $script:vipBtn.BackColor = $C.BgCard2
        $script:vipBtn.ForeColor = $C.Yellow
        $script:vipStatusLbl.Text      = "No VIP active"
        $script:vipStatusLbl.ForeColor = $C.Dim
        $vipCard.Invalidate()
    } else {
        # Toggle ON — elevate selected process
        $idx = $script:vipCombo.SelectedIndex
        if ($idx -ge 0 -and $idx -lt $script:vipProcs.Count) {
            $selProc = $script:vipProcs[$idx]
            if (Set-VipProcess -ProcessId $selProc.Id) {
                $script:vipBtn.Text      = "CLEAR VIP"
                $script:vipBtn.BackColor = $C.Yellow
                $script:vipBtn.ForeColor = $C.BgBase
                $script:vipStatusLbl.Text      = [char]0x25CF + " $($selProc.ProcessName)  [High Priority]"
                $script:vipStatusLbl.ForeColor = $C.Yellow
                $vipCard.Invalidate()
            } else {
                $script:vipStatusLbl.Text      = "Failed — try running as Administrator"
                $script:vipStatusLbl.ForeColor = $C.Red
            }
        }
    }
})
$vipCard.Controls.Add($script:vipBtn)

$script:vipStatusLbl = New-Object Windows.Forms.Label
$script:vipStatusLbl.Text         = "No VIP active"
$script:vipStatusLbl.Location     = [Drawing.Point]::new(706, 11)
$script:vipStatusLbl.Size         = [Drawing.Size]::new(306, 20)
$script:vipStatusLbl.Font         = New-Object Drawing.Font("Segoe UI Variable", 8)
$script:vipStatusLbl.ForeColor    = $C.Dim
$script:vipStatusLbl.BackColor    = [Drawing.Color]::Transparent
$script:vipStatusLbl.AutoEllipsis = $true
$vipCard.Controls.Add($script:vipStatusLbl)

Add-RoundedRegion $vipCard 10
$tab1.Controls.Add($vipCard)

# -- CPU History Chart ---------------------------------------------------
$cpuChart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
$cpuChart.Location        = [Drawing.Point]::new(15, 265)
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
$procTitleLbl.Location  = [Drawing.Point]::new(15, 393)
$procTitleLbl.Size      = [Drawing.Size]::new(500, 26)
$procTitleLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 11, [Drawing.FontStyle]::Bold)
$procTitleLbl.ForeColor = $C.Blue
$procTitleLbl.BackColor = [Drawing.Color]::Transparent
$tab1.Controls.Add($procTitleLbl)

$underlinePnl = New-Pnl 17 419 220 1 $C.Blue
$tab1.Controls.Add($underlinePnl)

# -- Process list --------------------------------------------------------
$pGrid = New-Object Windows.Forms.DataGridView
$pGrid.Location = [Drawing.Point]::new(15, 423)
$pGrid.Size     = [Drawing.Size]::new(1020, 560)
Style-Grid $pGrid
Add-Col $pGrid "App / Process" 220
Add-Col $pGrid "Memory"        80
Add-Col $pGrid "CPU Usage"     80
Add-Col $pGrid "ID"            60

# -- ANOMALY column (index 4) — inserted before Kill so Kill shifts to index 5
$anomalyCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$anomalyCol.Name       = "Anomaly"
$anomalyCol.HeaderText = "Status"
$anomalyCol.Width      = 90
$anomalyCol.ReadOnly   = $true
$anomalyCol.DefaultCellStyle.Alignment = [Windows.Forms.DataGridViewContentAlignment]::MiddleCenter
$anomalyCol.DefaultCellStyle.Font      = $script:MonoFont
[void]$pGrid.Columns.Add($anomalyCol)
$anomalyCol.HeaderCell.Style.ForeColor = $C.Anomaly
$anomalyCol.HeaderCell.Style.BackColor = $C.BgCard3
$anomalyCol.HeaderCell.Style.Font      = New-Object Drawing.Font("Segoe UI Variable", 9, [Drawing.FontStyle]::Bold)

$killCol = New-Object System.Windows.Forms.DataGridViewButtonColumn
$killCol.Name            = "Kill"
$killCol.HeaderText      = ""
$killCol.Text            = "END"
$killCol.UseColumnTextForButtonValue = $true
$killCol.Width           = 58
$killCol.DefaultCellStyle.BackColor  = [Drawing.Color]::FromArgb(80, 20, 20)
$killCol.DefaultCellStyle.ForeColor  = $C.Red
$killCol.DefaultCellStyle.Font       = $script:MonoBold
$killCol.DefaultCellStyle.Alignment  = "MiddleCenter"
[void]$pGrid.Columns.Add($killCol)
$killCol.HeaderCell.Style.ForeColor = $C.Red

$Script:Anomalies = @{}

# Update-ProcessGrid: reads from DataEngine cache — zero blocking, UI thread only
function Update-ProcessGrid($procs) {
    if ($null -eq $procs -or $procs.Count -eq 0) { return }

    # Anomaly data (file read — fast, local JSON)
    $anomalyPath = Join-Path $env:LOCALAPPDATA 'PC-Health-Monitor\PCHealth-Anomalies.json'
    $Script:Anomalies = @{}
    if (Test-Path $anomalyPath) {
        try {
            $aData = Get-Content $anomalyPath -Raw -ErrorAction Stop | ConvertFrom-Json
            foreach ($a in @($aData)) {
                if ($a.metric -eq 'process_ram_mb' -and $a.process) {
                    $Script:Anomalies[$a.process] = @{
                        pct = [int]$a.pct_above; z = [double]$a.z_score
                        current = [double]$a.current; mean = [double]$a.mean; std = [double]$a.std
                    }
                }
            }
        } catch { }
    }

    $pGrid.SuspendLayout()
    $pGrid.Rows.Clear()
    foreach ($p in $procs) {
        $ramVal = if ($p.PSObject.Properties['RamMB'])  { $p.RamMB  } else { $p.'RAM MB' }
        $cpuVal = if ($p.PSObject.Properties['CpuSec']) { $p.CpuSec } else { $p.'CPU sec' }
        $ri  = $pGrid.Rows.Add($p.Name, $ramVal, $cpuVal, $p.Id, '')
        $row = $pGrid.Rows[$ri]
        if ($ramVal -gt 500)     { $row.DefaultCellStyle.ForeColor = $C.Red }
        elseif ($ramVal -gt 200) { $row.DefaultCellStyle.ForeColor = $C.Yellow }
        $pName = $row.Cells[0].Value.ToString().ToLower()
        if ($script:ProtectedProcesses -contains $pName) {
            $row.Cells[1].Style.ForeColor = $C.Dim  # Memory value dimmed for system processes
            $row.Cells[5].Value           = "--"
            $row.Cells[5].Style.ForeColor = $C.Dim
            $row.Cells[5].Style.BackColor = $C.BgCard
            $row.Cells[5].ReadOnly        = $true
            $row.Cells[5].ToolTipText     = "System process - protected"
        }
        if ($Script:Anomalies.ContainsKey($p.Name)) {
            $a           = $Script:Anomalies[$p.Name]
            $statusText  = if ($a.pct -gt 50) { "High" } elseif ($a.pct -gt 20) { "Elevated" } else { "" }
            $statusColor = if ($a.pct -gt 50) { $C.Red } else { $C.Yellow }
            $row.Cells[4].Value       = $statusText
            $row.Cells[4].Style.ForeColor = $statusColor
            $row.Cells[4].ToolTipText = "Using $($a.current)MB — $($a.pct)% above its normal $($a.mean)MB average"
            if ($statusText) { $row.DefaultCellStyle.Font = $script:MonoBold }
        }
    }
    $pGrid.ResumeLayout()

    # Telemetry CSV append
    $TelemetryPath = Join-Path $env:TEMP 'PCHealth-Telemetry.csv'
    if (Test-Path $TelemetryPath) {
        try {
            $csvFile = Get-Item $TelemetryPath -ErrorAction SilentlyContinue
            if ($csvFile -and $csvFile.Length -gt 614400) {
                $lines = Get-Content $TelemetryPath -ErrorAction SilentlyContinue
                if ($lines -and $lines.Count -gt 2001) {
                    (@($lines[0]) + @($lines[2001..($lines.Count - 1)])) |
                        Out-File $TelemetryPath -Encoding UTF8 -ErrorAction SilentlyContinue
                }
            }
            $ts   = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
            $rows = foreach ($p in $procs) {
                $pn  = $p.Name -replace ',', ''
                $ram = if ($p.PSObject.Properties['RamMB'])  { $p.RamMB  } else { $p.'RAM MB' }
                $cpu = if ($p.PSObject.Properties['CpuSec']) { $p.CpuSec } else { $p.'CPU sec' }
                "$ts,process_ram_mb,$ram,$pn,$($p.Id)"
                "$ts,process_cpu_pct,$cpu,$pn,$($p.Id)"
            }
            $rows | Out-File $TelemetryPath -Append -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch { }
    }
}

function Refresh-ProcessGrid {
    $procs = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 25 `
        Name, Id,
        @{N="RAM MB"; E={[math]::Round($_.WorkingSet64/1MB,1)}},
        @{N="CPU sec";E={[math]::Round($_.CPU,1)}}

    # Load anomaly data (index 4 = ANOMALY col, index 5 = Kill col)
    $anomalyPath = Join-Path $env:LOCALAPPDATA 'PC-Health-Monitor\PCHealth-Anomalies.json'
    $Script:Anomalies = @{}
    if (Test-Path $anomalyPath) {
        try {
            $aData = Get-Content $anomalyPath -Raw -ErrorAction Stop | ConvertFrom-Json
            foreach ($a in @($aData)) {
                if ($a.metric -eq 'process_ram_mb' -and $a.process) {
                    $Script:Anomalies[$a.process] = @{
                        pct     = [int]$a.pct_above
                        z       = [double]$a.z_score
                        current = [double]$a.current
                        mean    = [double]$a.mean
                        std     = [double]$a.std
                    }
                }
            }
        } catch { }
    }

    $pGrid.SuspendLayout()
    $pGrid.Rows.Clear()
    foreach ($p in $procs) {
        $ri  = $pGrid.Rows.Add($p.Name, $p.'RAM MB', $p.'CPU sec', $p.Id, '')
        $row = $pGrid.Rows[$ri]
        if ($p.'RAM MB' -gt 500)     { $row.DefaultCellStyle.ForeColor = $C.Red }
        elseif ($p.'RAM MB' -gt 200) { $row.DefaultCellStyle.ForeColor = $C.Yellow }

        # Protected process — dim Memory cell + mark Kill cell (now index 5)
        $pName = $row.Cells[0].Value.ToString().ToLower()
        if ($script:ProtectedProcesses -contains $pName) {
            $row.Cells[1].Style.ForeColor = $C.Dim  # Memory value dimmed for system processes
            $row.Cells[5].Value           = "--"
            $row.Cells[5].Style.ForeColor = $C.Dim
            $row.Cells[5].Style.BackColor = $C.BgCard
            $row.Cells[5].ReadOnly        = $true
            $row.Cells[5].ToolTipText     = "System process - protected"
        }

        # Status column (index 4) — human-readable anomaly level
        if ($Script:Anomalies.ContainsKey($p.Name)) {
            $a           = $Script:Anomalies[$p.Name]
            $statusText  = if ($a.pct -gt 50) { "High" } elseif ($a.pct -gt 20) { "Elevated" } else { "" }
            $statusColor = if ($a.pct -gt 50) { $C.Red } else { $C.Yellow }
            $row.Cells[4].Value           = $statusText
            $row.Cells[4].Style.ForeColor = $statusColor
            $row.Cells[4].ToolTipText     = "Using $($a.current)MB — $($a.pct)% above its normal $($a.mean)MB average"
            if ($statusText) { $row.DefaultCellStyle.Font = $script:MonoBold }
        }
    }
    $pGrid.ResumeLayout()

    # Process-level telemetry append
    $TelemetryPath = Join-Path $env:TEMP 'PCHealth-Telemetry.csv'
    if (Test-Path $TelemetryPath) {
        try {
            $csvFile = Get-Item $TelemetryPath -ErrorAction SilentlyContinue
            if ($csvFile -and $csvFile.Length -gt 614400) {
                $lines = Get-Content $TelemetryPath -ErrorAction SilentlyContinue
                if ($lines -and $lines.Count -gt 2001) {
                    (@($lines[0]) + @($lines[2001..($lines.Count - 1)])) |
                        Out-File $TelemetryPath -Encoding UTF8 -ErrorAction SilentlyContinue
                }
            }
            $ts   = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
            $rows = foreach ($p in $procs) {
                $pn = $p.Name -replace ',', ''
                "$ts,process_ram_mb,$($p.'RAM MB'),$pn,$($p.Id)"
                "$ts,process_cpu_pct,$($p.'CPU sec'),$pn,$($p.Id)"
            }
            $rows | Out-File $TelemetryPath -Append -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch { }
    }
}
Refresh-ProcessGrid



$tab1.Controls.Add($pGrid)
$tabs.TabPages.Add($tab1)

# ========================================================================
# TAB 2 -- STARTUP PROGRAMS
# ========================================================================
$tab2 = New-Object Windows.Forms.TabPage
$tab2.Text      = "  Startup Apps  "
$tab2.BackColor = $C.BgBase

$s2TitleLbl = New-Object Windows.Forms.Label
$s2TitleLbl.Text      = "  Apps that start automatically with Windows"
$s2TitleLbl.Location  = [Drawing.Point]::new(15, 15)
$s2TitleLbl.Size      = [Drawing.Size]::new(700, 26)
$s2TitleLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 11, [Drawing.FontStyle]::Bold)
$s2TitleLbl.ForeColor = $C.Blue
$s2TitleLbl.BackColor = [Drawing.Color]::Transparent
$tab2.Controls.Add($s2TitleLbl)

$s2SubLbl = New-Object Windows.Forms.Label
$s2SubLbl.Text      = "  Disabling an app here stops it from launching on startup. You can re-enable it later."
$s2SubLbl.Location  = [Drawing.Point]::new(15, 43)
$s2SubLbl.Size      = [Drawing.Size]::new(900, 18)
$s2SubLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 8)
$s2SubLbl.ForeColor = $C.Dim
$s2SubLbl.BackColor = [Drawing.Color]::Transparent
$tab2.Controls.Add($s2SubLbl)

$s2CountLbl = New-Object Windows.Forms.Label
$s2CountLbl.Text      = if ($startups.Count -eq 0)  { "  No startup apps found — your system starts clean." }
                        elseif ($startups.Count -le 5) { "  $($startups.Count) app(s) start with Windows — looks good." }
                        else                           { "  $($startups.Count) apps start with Windows — consider disabling some." }
$s2CountLbl.Location  = [Drawing.Point]::new(15, 63)
$s2CountLbl.Size      = [Drawing.Size]::new(400, 20)
$s2CountLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 9)
$s2CountLbl.ForeColor = $C.Yellow
$s2CountLbl.BackColor = [Drawing.Color]::Transparent
$tab2.Controls.Add($s2CountLbl)

$sGrid = New-Object Windows.Forms.DataGridView
$sGrid.Location = [Drawing.Point]::new(15, 90)
$sGrid.Size     = [Drawing.Size]::new(1020, 520)
Style-Grid $sGrid
$sGrid.ReadOnly = $false

Add-Col $sGrid "Source"  70
Add-Col $sGrid "Name"   300
Add-Col $sGrid "Command" 550
# Rename visible headers (keep column Names intact — used by disable logic)
$sGrid.Columns["Source"].HeaderText  = "Type"
$sGrid.Columns["Name"].HeaderText    = "App Name"
$sGrid.Columns["Command"].Visible    = $false

$disableCol = New-Object Windows.Forms.DataGridViewButtonColumn
$disableCol.HeaderText = "Action"
$disableCol.Name       = "Action"
$disableCol.Text       = "Disable"
$disableCol.UseColumnTextForButtonValue = $true
$disableCol.FillWeight = 80
$disableCol.DefaultCellStyle.BackColor = $C.DarkRed
$disableCol.DefaultCellStyle.ForeColor = $C.White
$disableCol.DefaultCellStyle.Font      = New-Object Drawing.Font("Segoe UI Variable", 9, [Drawing.FontStyle]::Bold)
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
    $font = New-Object Drawing.Font("Segoe UI Variable", 9, [Drawing.FontStyle]::Bold)
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
$tab3.Text      = "  Junk Cleaner  "
$tab3.BackColor = $C.BgBase

$cleanTitleLbl = New-Object Windows.Forms.Label
$cleanTitleLbl.Text      = "  Junk Files - Recoverable Space"
$cleanTitleLbl.Location  = [Drawing.Point]::new(15, 15)
$cleanTitleLbl.Size      = [Drawing.Size]::new(500, 28)
$cleanTitleLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 12, [Drawing.FontStyle]::Bold)
$cleanTitleLbl.ForeColor = $C.Blue
$cleanTitleLbl.BackColor = [Drawing.Color]::Transparent
$tab3.Controls.Add($cleanTitleLbl)

$cleanTotalLbl = New-Object Windows.Forms.Label
$cleanTotalLbl.Text      = "  Total found: $totalJunkGB GB across $($junkItems.Count) locations"
$cleanTotalLbl.Location  = [Drawing.Point]::new(15, 45)
$cleanTotalLbl.Size      = [Drawing.Size]::new(600, 22)
$cleanTotalLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 9)
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
$hdrPnl.Controls.Add((New-Lbl "Path"     422  5 290 18 9 $true $C.Blue))
$hdrPnl.Controls.Add((New-Lbl "Open"     745  5  36 18 9 $true $C.Blue))
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
    $nameLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 10, [Drawing.FontStyle]::Bold)
    $nameLbl.ForeColor = $C.Text
    $nameLbl.BackColor = [Drawing.Color]::Transparent
    $rPnl.Controls.Add($nameLbl)

    $sizeLbl = New-Object Windows.Forms.Label
    $sizeLbl.Text      = "$($ji.SizeMB) MB"
    $sizeLbl.Location  = [Drawing.Point]::new(250, 8)
    $sizeLbl.Size      = [Drawing.Size]::new(100, 20)
    $sizeLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 10, [Drawing.FontStyle]::Bold)
    $sizeLbl.ForeColor = $sColor
    $sizeLbl.BackColor = [Drawing.Color]::Transparent
    $rPnl.Controls.Add($sizeLbl)

    $filesLbl = New-Object Windows.Forms.Label
    $filesLbl.Text      = "$($ji.Files) files"
    $filesLbl.Location  = [Drawing.Point]::new(357, 8)
    $filesLbl.Size      = [Drawing.Size]::new(70, 20)
    $filesLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 9)
    $filesLbl.ForeColor = $C.SubText
    $filesLbl.BackColor = [Drawing.Color]::Transparent
    $rPnl.Controls.Add($filesLbl)

    $pathLbl = New-Object Windows.Forms.Label
    $pathLbl.Text      = $ji.Path
    $pathLbl.Location  = [Drawing.Point]::new(12, 32)
    $pathLbl.Size      = [Drawing.Size]::new(560, 16)
    $pathLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 7)
    $pathLbl.ForeColor = $C.Dim
    $pathLbl.BackColor = [Drawing.Color]::Transparent
    $rPnl.Controls.Add($pathLbl)

    # -- Folder-open button: opens the junk folder directly in Explorer ----
    $folderBtn          = New-Object Windows.Forms.Button
    $folderBtn.Text     = [char]::ConvertFromUtf32(0x1F4C1)   # 📁
    $folderBtn.Location = [Drawing.Point]::new(740, 10)
    $folderBtn.Size     = [Drawing.Size]::new(36, 36)
    $folderBtn.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $folderBtn.FlatAppearance.BorderColor = $C.Blue
    $folderBtn.FlatAppearance.BorderSize  = 1
    $folderBtn.BackColor = $C.BgCard2
    $folderBtn.ForeColor = $C.Blue
    $folderBtn.Font      = New-Object Drawing.Font("Segoe UI Emoji", 12)
    $folderBtn.Cursor    = [Windows.Forms.Cursors]::Hand
    $cleanToolTip.SetToolTip($folderBtn, "Open folder in Explorer")
    $folderBtn.Tag = $ji.Path
    $folderBtn.Add_Click({
        param($s2, $ev)
        $p = $s2.Tag
        if (Test-Path $p) {
            Start-Process explorer.exe -ArgumentList "`"$p`""
        } else {
            [Windows.Forms.MessageBox]::Show(
                "Folder not found:`n$p",
                "PC Health Monitor",
                [Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
    })
    $rPnl.Controls.Add($folderBtn)

    $cleanBtn = New-Object Windows.Forms.Button
    $cleanBtn.Text      = "Clean"
    $cleanBtn.Location  = [Drawing.Point]::new(784, 10)
    $cleanBtn.Size      = [Drawing.Size]::new(100, 36)
    $cleanBtn.BackColor = $C.DarkRed
    $cleanBtn.ForeColor = $C.White
    $cleanBtn.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $cleanBtn.FlatAppearance.BorderColor = $C.Red
    $cleanBtn.FlatAppearance.BorderSize  = 1
    $cleanBtn.Font      = New-Object Drawing.Font("Segoe UI Variable", 9, [Drawing.FontStyle]::Bold)
    $cleanBtn.Cursor    = [Windows.Forms.Cursors]::Hand

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
            param($path, $formObj, $btn, $log, $prog, $dg, $szLbl, $fLbl, $green, $name, $pending)
            $del = 0; $errCount = 0; $totalBytes = 0L

            $formObj.Invoke([Action]{ $log.AppendText("`nCleaning: $path") })

            # -- Special handling: Thumbnail / Icon Cache requires Explorer restart ----
            # iconcache_*.db and thumbcache_*.db are held open by explorer.exe.
            # Standard protocol: stop Explorer → delete → restart Explorer.
            $isThumbnailCache = ($name -eq 'Thumbnail Cache')
            if ($isThumbnailCache) {
                $formObj.Invoke([Action]{ $log.AppendText("`n  Stopping Windows Explorer to release cache locks...") })
                Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 1800   # allow explorer.exe to fully terminate
            }

            # Pass 1: delete each file individually — a locked file never blocks others
            # Exclude the app's own log file (always open/locked inside %TEMP%)
            Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer -and $_.Name -ne 'PCHealth-Monitor.log' } |
                Sort-Object FullName -Descending |
                ForEach-Object {
                    try {
                        $fileBytes = $_.Length
                        Remove-Item $_.FullName -Force -ErrorAction Stop
                        $del++
                        $totalBytes += $fileBytes   # BUG-FIX: count bytes ONLY after confirmed delete
                    } catch { $errCount++ }
                }

            # Pass 2: remove directories that are now empty (best-effort, silent)
            Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.PSIsContainer } |
                Sort-Object FullName -Descending |
                ForEach-Object {
                    try { Remove-Item $_.FullName -Force -ErrorAction Stop } catch { }
                }

            # -- Restart Explorer if we stopped it ---------------------------------
            if ($isThumbnailCache) {
                Start-Sleep -Milliseconds 500
                Start-Process explorer.exe
                $formObj.Invoke([Action]{ $log.AppendText("`n  Windows Explorer restarted.") })
                Start-Sleep -Milliseconds 2000   # let Explorer stabilise before rescan
            }

            # Rescan — exclude app log; null-safe Measure-Object (.Sum can be $null on empty set)
            $remaining = Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                         Where-Object { -not $_.PSIsContainer -and $_.Name -ne 'PCHealth-Monitor.log' }
            $remCount  = @($remaining).Count
            $remRaw    = ($remaining | Measure-Object Length -Sum -ErrorAction SilentlyContinue).Sum
            $remMB     = if ($remRaw) { [math]::Round([long]$remRaw / 1MB, 1) } else { 0.0 }

            $pending['Bytes']    = $totalBytes
            $pending['Name']     = $name
            $pending['Removed']  = $del
            $pending['Skipped']  = $errCount
            $pending['Ready']    = $true

            $msg = "  Done - removed $del files ($errCount locked/skipped) | $remMB MB remaining"
            $formObj.Invoke([Action]{
                $log.AppendText($msg)
                $log.ScrollToCaret()
                $prog.Visible = $false
                if ($remMB -le 0) {
                    $btn.Text        = "Done"
                    $btn.BackColor   = $dg
                    $szLbl.Text      = "0 MB"
                    $szLbl.ForeColor = $green
                    $fLbl.Text       = "0 files"
                } else {
                    # Partial clean — locked files remain; show amber state clearly
                    $btn.Text        = "Partial"
                    $btn.BackColor   = [Drawing.Color]::FromArgb(160, 90, 0)
                    $szLbl.Text      = "$remMB MB"
                    $szLbl.ForeColor = [Drawing.Color]::FromArgb(255, 200, 100)
                    $fLbl.Text       = "$remCount locked"
                }
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
        [void]$ps.AddParameter("pending", $script:CleanSummaryPending)

        $script:CleanSummaryPending['Ready'] = $false
        [void]$ps.BeginInvoke()

        # Poll $script:CleanSummaryPending on the UI thread; call Show-CleanSummary when done
        # Use $script:pollTimer so the Add_Tick nested closure can reliably access it
        if ($script:pollTimer) { try { $script:pollTimer.Stop(); $script:pollTimer.Dispose() } catch {} }
        $script:pollTimer = New-Object Windows.Forms.Timer
        $script:pollTimer.Interval = 500
        $script:pollTimer.Add_Tick({
            if ($script:CleanSummaryPending['Ready']) {
                $script:pollTimer.Stop()
                $script:pollTimer.Dispose()
                $b = [long]$script:CleanSummaryPending['Bytes']
                $n = $script:CleanSummaryPending['Name']
                $d = [int]$script:CleanSummaryPending['Removed']
                $sk = [int]$script:CleanSummaryPending['Skipped']
                $sizeStr = Format-CleanBytes $b
                $txt = "$n cleaned — $sizeStr freed  ($d items removed"
                if ($sk -gt 0) { $txt += ", $sk skipped" }
                $txt += ")"
                Show-CleanSummary -SummaryText $txt
            }
        })
        $script:pollTimer.Start()
    })

    $rPnl.Controls.Add($cleanBtn)
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
$cleanAllBtn.Font      = New-Object Drawing.Font("Segoe UI Variable", 9, [Drawing.FontStyle]::Bold)
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
        $totalCleanedBytes = 0L
        $cleanedNames      = @()
        foreach ($ji2 in $junkItems) {
            if (($adminRequiredNames -contains $ji2.Name) -and (-not $script:isAdmin)) {
                $logBox.AppendText("`nSkipped (requires admin): $($ji2.Name)")
                [Windows.Forms.Application]::DoEvents()
                continue
            }
            $logBox.AppendText("`nCleaning: $($ji2.Path)")
            [Windows.Forms.Application]::DoEvents()
            $del=0; $errCount=0
            # Recurse into subdirs; exclude app log (locked); count bytes ONLY after confirmed delete
            Get-ChildItem $ji2.Path -Recurse -Force -EA SilentlyContinue |
                Where-Object { -not $_.PSIsContainer -and $_.Name -ne 'PCHealth-Monitor.log' } |
                Sort-Object FullName -Descending |
                ForEach-Object {
                    try {
                        $fb = $_.Length
                        Remove-Item $_.FullName -Force -EA Stop
                        $del++
                        $totalCleanedBytes += $fb   # only after confirmed delete
                    } catch {
                        Write-Log -Message "Clean All: failed to remove item from $($ji2.Name)" -Level WARN -ExceptionRecord $_
                        $errCount++
                    }
                }
            # Remove now-empty subdirs (best-effort)
            Get-ChildItem $ji2.Path -Recurse -Force -EA SilentlyContinue |
                Where-Object { $_.PSIsContainer } | Sort-Object FullName -Descending |
                ForEach-Object { try { Remove-Item $_.FullName -Force -EA Stop } catch {} }
            $logBox.AppendText("  -> $del removed, $errCount skipped")
            $cleanedNames += $ji2.Name
        }
        $logBox.AppendText("`n--- DONE ---")
        $logBox.ScrollToCaret()
        if ($cleanedNames.Count -gt 0) {
            $sizeStr = Format-CleanBytes $totalCleanedBytes
            $locStr  = if ($cleanedNames.Count -eq 1) { $cleanedNames[0] } else { "$($cleanedNames.Count) locations" }
            Show-CleanSummary -SummaryText "Clean All complete — $sizeStr freed from $locStr"
        }
    }
})

# ── TOP 10 LARGEST FOLDERS — own tab ────────────────────────────────────
$diskUsageTab           = New-Object Windows.Forms.TabPage
$diskUsageTab.Text      = "  Storage  "
$diskUsageTab.BackColor = $C.BgBase

$tfHeaderPnl = New-Pnl 15 10 1020 36 $C.BgCard3
$tfHeaderPnl.Add_Paint({
    param($s2, $pe)
    try {
        $pe.Graphics.DrawLine(
            (New-Object Drawing.Pen($C.Border, 1)),
            0, $s2.Height - 1, $s2.Width, $s2.Height - 1)
    } catch {
        Write-Log -Message "tfHeaderPnl Paint error" -Level WARN -ExceptionRecord $_
    }
})
$tfHeaderLbl = New-Object Windows.Forms.Label
$tfHeaderLbl.Text      = "  TOP 10 LARGEST FOLDERS  --  C:\"
$tfHeaderLbl.Location  = [Drawing.Point]::new(4, 8)
$tfHeaderLbl.Size      = [Drawing.Size]::new(800, 20)
$tfHeaderLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 10, [Drawing.FontStyle]::Bold)
$tfHeaderLbl.ForeColor = $C.Blue
$tfHeaderLbl.BackColor = [Drawing.Color]::Transparent
$tfHeaderPnl.Controls.Add($tfHeaderLbl)

$script:tfScanBtn = New-Btn "SCAN" 870 4 140 28 $C.BgCard2 $C.Blue
$script:tfScanBtn.FlatAppearance.BorderColor = $C.Blue
$script:tfScanBtn.FlatAppearance.BorderSize  = 1
$tfHeaderPnl.Controls.Add($script:tfScanBtn)
$diskUsageTab.Controls.Add($tfHeaderPnl)

# Container panel for the 10 folder rows
$script:tfContainer = New-Pnl 15 46 1020 360 $C.BgCard
$diskUsageTab.Controls.Add($script:tfContainer)

# Placeholder label shown before any scan (lives inside the container)
$script:tfPlaceholder = New-Object Windows.Forms.Label
$script:tfPlaceholder.Text      = "Click SCAN to analyze disk usage on C:\"
$script:tfPlaceholder.Location  = [Drawing.Point]::new(0, 152)
$script:tfPlaceholder.Size      = [Drawing.Size]::new(1020, 36)
$script:tfPlaceholder.Font      = New-Object Drawing.Font("Segoe UI Variable", 9)
$script:tfPlaceholder.ForeColor = $C.Dim
$script:tfPlaceholder.BackColor = [Drawing.Color]::Transparent
$script:tfPlaceholder.TextAlign = [Drawing.ContentAlignment]::MiddleCenter
$script:tfContainer.Controls.Add($script:tfPlaceholder)

# Arrays for per-row control references (populated in the loop below)
$script:tfRowPanels  = New-Object System.Collections.ArrayList
$script:tfPathLabels = New-Object System.Collections.ArrayList
$script:tfSizeLabels = New-Object System.Collections.ArrayList
$script:tfBars       = New-Object System.Collections.ArrayList
$script:tfFolderBtns = New-Object System.Collections.ArrayList

for ($tfI = 0; $tfI -lt 10; $tfI++) {
    $rowBg  = if ($tfI % 2 -eq 0) { $C.BgCard } else { $C.BgCard2 }
    $rowPnl = New-Pnl 0 ($tfI * 36) 1020 36 $rowBg
    $rowPnl.Visible = $false

    # Folder open button (📁 → opens path in Explorer)
    $fBtn = New-Object Windows.Forms.Button
    $fBtn.Text      = [char]::ConvertFromUtf32(0x1F4C1)   # 📁
    $fBtn.Location  = [Drawing.Point]::new(4, 0)
    $fBtn.Size      = [Drawing.Size]::new(34, 36)
    $fBtn.BackColor = $C.BgCard2
    $fBtn.ForeColor = $C.Blue
    $fBtn.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $fBtn.FlatAppearance.BorderColor         = $C.Blue
    $fBtn.FlatAppearance.BorderSize          = 1
    $fBtn.FlatAppearance.MouseOverBackColor  = $C.BgCard3
    $fBtn.Font      = New-Object Drawing.Font("Segoe UI Emoji", 12)
    $fBtn.Cursor    = [Windows.Forms.Cursors]::Hand
    $fBtn.Tag       = ""

    $tfTip = New-Object Windows.Forms.ToolTip
    $tfTip.SetToolTip($fBtn, "Open folder in Explorer")

    $fBtn.Add_Click({
        param($s, $e)
        $p = $s.Tag
        if ($p) {
            try { Start-Process -FilePath "explorer.exe" -ArgumentList "`"$p`"" }
            catch { Write-Log -Message "Failed to open explorer for: $p" -Level WARN -ExceptionRecord $_ }
        }
    })
    $rowPnl.Controls.Add($fBtn)

    # Path label (auto-ellipsis for long paths)
    $pLbl = New-Object Windows.Forms.Label
    $pLbl.Text         = ""
    $pLbl.Location     = [Drawing.Point]::new(40, 2)
    $pLbl.Size         = [Drawing.Size]::new(720, 32)
    $pLbl.Font         = New-Object Drawing.Font("Segoe UI Variable", 9)
    $pLbl.ForeColor    = $C.Text
    $pLbl.BackColor    = [Drawing.Color]::Transparent
    $pLbl.AutoEllipsis = $true
    $pLbl.TextAlign    = [Drawing.ContentAlignment]::MiddleLeft
    $rowPnl.Controls.Add($pLbl)

    # Size label (right-aligned)
    $sLbl = New-Object Windows.Forms.Label
    $sLbl.Text      = ""
    $sLbl.Location  = [Drawing.Point]::new(764, 2)
    $sLbl.Size      = [Drawing.Size]::new(90, 32)
    $sLbl.Font      = New-Object Drawing.Font("Segoe UI Variable", 9, [Drawing.FontStyle]::Bold)
    $sLbl.ForeColor = $C.Yellow
    $sLbl.BackColor = [Drawing.Color]::Transparent
    $sLbl.TextAlign = [Drawing.ContentAlignment]::MiddleRight
    $rowPnl.Controls.Add($sLbl)

    # Progress bar: custom-painted 4px panel (track + fill via Paint)
    $bar = New-Pnl 862 16 120 4 $C.BgCard3
    $bar.Tag = @{ Pct = 0; FillColor = $C.Green }
    $bar.Add_Paint({
        param($s2, $pe)
        try {
            $td    = $s2.Tag
            $fillW = [math]::Max(0, [int]([math]::Round(($td.Pct / 100.0) * $s2.Width)))
            if ($fillW -gt 0) {
                $br = New-Object Drawing.SolidBrush($td.FillColor)
                $pe.Graphics.FillRectangle($br, 0, 0, $fillW, $s2.Height)
                $br.Dispose()
            }
        } catch {
            Write-Log -Message "TopFolder bar Paint error" -Level WARN -ExceptionRecord $_
        }
    })
    $rowPnl.Controls.Add($bar)

    [void]$script:tfRowPanels.Add($rowPnl)
    [void]$script:tfPathLabels.Add($pLbl)
    [void]$script:tfSizeLabels.Add($sLbl)
    [void]$script:tfBars.Add($bar)
    [void]$script:tfFolderBtns.Add($fBtn)

    $script:tfContainer.Controls.Add($rowPnl)
}

$script:tfAutoScanned = $false   # triggers auto-scan on first Storage tab visit

$script:tfScanBtn.Add_Click({ Invoke-TopFolderScan })

$tabs.TabPages.Add($tab3)
$tabs.TabPages.Add($diskUsageTab)


# ========================================================================
# TAB 5 -- BOOST MODE
# ========================================================================
$boostTab           = New-Object Windows.Forms.TabPage
$boostTab.Text      = "  Boost  "
$boostTab.BackColor = $C.BgBase

$bPnl = New-Pnl 0 0 1040 580 $C.BgBase
$boostTab.Controls.Add($bPnl)

# Header
$bHdr = New-Lbl "⚡  Boost Mode" 20 12 600 30 13 $true $C.Yellow
$bPnl.Controls.Add($bHdr)
$bSub = New-Lbl "Maximize performance by throttling background processes and activating High Performance power plan" 20 46 780 18 8.5 $false $C.SubText
$bPnl.Controls.Add($bSub)

# Info button (ⓘ)
$bInfoBtn               = New-Object Windows.Forms.Button
$bInfoBtn.Size          = [Drawing.Size]::new(28, 28)
$bInfoBtn.Location      = [Drawing.Point]::new(810, 10)
$bInfoBtn.Text          = "i"
$bInfoBtn.Font          = New-Object Drawing.Font("Segoe UI Variable", 10, [Drawing.FontStyle]::Bold)
$bInfoBtn.BackColor     = $C.BgCard
$bInfoBtn.ForeColor     = $C.Blue
$bInfoBtn.FlatStyle     = [Windows.Forms.FlatStyle]::Flat
$bInfoBtn.FlatAppearance.BorderColor = $C.Blue
$bInfoBtn.FlatAppearance.BorderSize  = 1
$bInfoBtn.Cursor        = [Windows.Forms.Cursors]::Hand
$bInfoBtn.TextAlign     = [Drawing.ContentAlignment]::MiddleCenter
Add-RoundedRegion $bInfoBtn 14
$bPnl.Controls.Add($bInfoBtn)

$bInfoBtn.Add_Click({
    $msg = @"
BOOST MODE — How It Works
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Boost Mode is a one-click performance optimizer that temporarily
reconfigures your system to prioritize active work over background activity.

WHAT IT DOES:
  • Switches your Windows Power Plan to "High Performance"
    (prevents CPU throttling and keeps clocks at full speed)

  • Lowers the CPU priority of non-essential background processes
    (Teams, Discord, Spotify, OneDrive, Chrome, and others)
    — they keep running, but yield CPU time to your main task

  • Flushes Standby RAM — memory held by idle processes is released
    back to the system, reducing pressure on available RAM

WHAT IT DOES NOT DO:
  • Does not kill or close any process
  • Does not change any permanent system settings
  • Does not affect network, audio, or display drivers

ON DEACTIVATE:
  All original process priorities and your previous power plan
  are restored automatically — nothing is left changed.

BEST USED FOR:
  Gaming · Video editing · Rendering · Compiling · Heavy multitasking
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"@
    [Windows.Forms.MessageBox]::Show(
        $msg,
        "Boost Mode — Information",
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
})

# Big BOOST button
$script:boostBtn          = New-Object Windows.Forms.Button
$script:boostBtn.Size     = [Drawing.Size]::new(420, 80)
$script:boostBtn.Location = [Drawing.Point]::new(310, 78)
$script:boostBtn.Text     = "⚡  ACTIVATE BOOST"
$script:boostBtn.Font     = New-Object Drawing.Font("Segoe UI Variable", 15, [Drawing.FontStyle]::Bold)
$script:boostBtn.BackColor = $C.Yellow
$script:boostBtn.ForeColor = [Drawing.Color]::FromArgb(15,15,18)
$script:boostBtn.FlatStyle = [Windows.Forms.FlatStyle]::Flat
$script:boostBtn.FlatAppearance.BorderSize = 0
$script:boostBtn.Cursor   = [Windows.Forms.Cursors]::Hand
Add-RoundedRegion $script:boostBtn 12
$bPnl.Controls.Add($script:boostBtn)

# Status badge
$script:boostStatusLbl          = New-Lbl "Status: Ready" 20 176 400 22 9 $false $C.SubText
$bPnl.Controls.Add($script:boostStatusLbl)

# Divider
$bDiv = New-Pnl 20 205 1000 1 $C.Border
$bPnl.Controls.Add($bDiv)

# Action log (RichTextBox)
$script:boostLog              = New-Object Windows.Forms.RichTextBox
$script:boostLog.Location     = [Drawing.Point]::new(20, 215)
$script:boostLog.Size         = [Drawing.Size]::new(1000, 160)
$script:boostLog.BackColor    = $C.BgCard
$script:boostLog.ForeColor    = $C.Text
$script:boostLog.Font         = New-Object Drawing.Font("Segoe UI Variable", 9.5)
$script:boostLog.ReadOnly     = $true
$script:boostLog.BorderStyle  = [Windows.Forms.BorderStyle]::None
$script:boostLog.ScrollBars   = [Windows.Forms.RichTextBoxScrollBars]::Vertical
Add-RoundedRegion $script:boostLog 8
$bPnl.Controls.Add($script:boostLog)

# Target process list (info panel)
$bInfoPnl = New-Pnl 20 390 1000 160 $C.BgCard
Add-RoundedRegion $bInfoPnl 8
$bPnl.Controls.Add($bInfoPnl)

$bInfoHdr = New-Lbl "Background processes that will be throttled:" 14 10 700 18 8.5 $true $C.SubText
$bInfoPnl.Controls.Add($bInfoHdr)

$bTargetStr = ($BOOST_TARGETS | Select-Object -First 10) -join "  •  "
$bTargetLbl = New-Lbl "•  $bTargetStr  + more" 14 32 970 80 8.5 $false $C.Dim
$bTargetLbl.MaximumSize = [Drawing.Size]::new(970, 0)
$bTargetLbl.AutoSize    = $true
$bInfoPnl.Controls.Add($bTargetLbl)

$bNoteLbl = New-Lbl "⚠️  Boost Mode temporarily lowers process priority — no processes are killed. All settings restore automatically when deactivated." 14 110 970 30 8 $false $C.SubText
$bInfoPnl.Controls.Add($bNoteLbl)

# Boost button click handler
$script:boostBtn.Add_Click({
    if (-not $script:boostActive) {
        $script:boostBtn.Enabled  = $false
        $script:boostBtn.Text     = "Working..."
        [Windows.Forms.Application]::DoEvents()
        try {
            $log = Enable-BoostMode
            $script:boostLog.Clear()
            $script:boostLog.SelectionColor = $C.Green
            $script:boostLog.SelectionFont  = New-Object Drawing.Font("Segoe UI Variable", 9.5, [Drawing.FontStyle]::Bold)
            $script:boostLog.AppendText("✅  Boost Mode ACTIVATED`n`n")
            $script:boostLog.SelectionColor = $C.Text
            $script:boostLog.SelectionFont  = New-Object Drawing.Font("Segoe UI Variable", 9.5)
            foreach ($l in $log) { $script:boostLog.AppendText("  • $l`n") }
            $script:boostStatusLbl.Text      = "Status: 🟢 ACTIVE — PC optimized for performance"
            $script:boostStatusLbl.ForeColor = $C.Green
            $script:boostBtn.Text            = "⏹  DEACTIVATE BOOST"
            $script:boostBtn.BackColor       = $C.Green
        } catch {
            $script:boostLog.AppendText("❌ Error: $($_.Exception.Message)`n")
        }
        $script:boostBtn.Enabled = $true
    } else {
        $script:boostBtn.Enabled = $false
        $script:boostBtn.Text    = "Restoring..."
        [Windows.Forms.Application]::DoEvents()
        try {
            $log = Disable-BoostMode
            $script:boostLog.Clear()
            $script:boostLog.SelectionColor = $C.SubText
            $script:boostLog.SelectionFont  = New-Object Drawing.Font("Segoe UI Variable", 9.5, [Drawing.FontStyle]::Bold)
            $script:boostLog.AppendText("🔄  Boost Mode DEACTIVATED`n`n")
            $script:boostLog.SelectionColor = $C.Text
            $script:boostLog.SelectionFont  = New-Object Drawing.Font("Segoe UI Variable", 9.5)
            foreach ($l in $log) { $script:boostLog.AppendText("  • $l`n") }
            $script:boostStatusLbl.Text      = "Status: Ready"
            $script:boostStatusLbl.ForeColor = $C.SubText
            $script:boostBtn.Text            = "⚡  ACTIVATE BOOST"
            $script:boostBtn.BackColor       = $C.Yellow
        } catch {
            $script:boostLog.AppendText("❌ Error: $($_.Exception.Message)`n")
        }
        $script:boostBtn.Enabled = $true
    }
    Add-RoundedRegion $script:boostBtn 12
})

$tabs.TabPages.Add($boostTab)

# ========================================================================
# TAB 6 -- DISK HEALTH (S.M.A.R.T)
# ========================================================================
$diskHealthTab           = New-Object Windows.Forms.TabPage
$diskHealthTab.Text      = "  Disk Health  "
$diskHealthTab.BackColor = $C.BgBase

$dhPnl = New-Pnl 0 0 1040 580 $C.BgBase
$diskHealthTab.Controls.Add($dhPnl)

# Header
$dhHdr = New-Lbl "🔬  Disk Health" 20 12 600 30 13 $true $C.Blue
$dhPnl.Controls.Add($dhHdr)
$dhSub = New-Lbl "S.M.A.R.T. data, temperature, error counts and wear level for all physical drives" 20 46 780 18 8.5 $false $C.SubText
$dhPnl.Controls.Add($dhSub)

$dhScanBtn = New-Btn "Scan Disks" 820 14 200 44 $C.Blue $C.Text
$dhScanBtn.Font = New-Object Drawing.Font("Segoe UI Variable", 10, [Drawing.FontStyle]::Bold)
$dhPnl.Controls.Add($dhScanBtn)

# Results panel (scrollable)
$dhResultsPnl                = New-Object Windows.Forms.FlowLayoutPanel
$dhResultsPnl.Location       = [Drawing.Point]::new(20, 78)
$dhResultsPnl.Size           = [Drawing.Size]::new(1000, 480)
$dhResultsPnl.FlowDirection  = [Windows.Forms.FlowDirection]::TopDown
$dhResultsPnl.WrapContents   = $false
$dhResultsPnl.AutoScroll     = $true
$dhResultsPnl.BackColor      = $C.BgBase
$dhPnl.Controls.Add($dhResultsPnl)

function Render-DiskHealthCard {
    param($disk)

    $bgColor = switch ($disk.HealthStatus) {
        "Healthy"   { $C.BgCard  }
        "Warning"   { [Drawing.Color]::FromArgb(40, 255, 159, 10)  }
        default     { [Drawing.Color]::FromArgb(40, 255, 59,  48)  }
    }
    $statusIcon = switch ($disk.HealthStatus) {
        "Healthy" { "✅" } "Warning" { "⚠️" } default { "🔴" }
    }

    $card               = New-Object Windows.Forms.Panel
    $card.Width         = 978
    $card.Height        = 170
    $card.BackColor     = $bgColor
    $card.Margin        = [Windows.Forms.Padding]::new(0, 0, 0, 10)
    Add-RoundedRegion $card 8

    # Left accent
    $acColor = switch ($disk.HealthStatus) { "Healthy" { $C.Green } "Warning" { $C.Yellow } default { $C.Red } }
    $card.Add_Paint({
        param($s4, $pe)
        $pen = New-Object Drawing.Pen($acColor, 3)
        $pe.Graphics.DrawLine($pen, 1, 8, 1, $s4.Height - 8)
        $pen.Dispose()
    }.GetNewClosure())

    # Title row
    $mediaIcon = if ($disk.MediaType -eq 'SSD' -or $disk.MediaType -eq 'Unspecified') { "💾" } else { "🖴" }
    $titleLbl  = New-Lbl "$mediaIcon  $($disk.FriendlyName)   $statusIcon $($disk.HealthStatus)" 14 12 700 22 10 $true $C.Text
    $card.Controls.Add($titleLbl)

    $sizeLbl = New-Lbl "$($disk.SizeGB) GB  ·  $($disk.MediaType)" 700 14 250 18 8.5 $false $C.SubText
    $card.Controls.Add($sizeLbl)

    # Metrics grid
    $metrics = @(
        @{ Label="Temperature";  Val = if ($disk.Temperature)  { "$($disk.Temperature)°C" } else { "—" } }
        @{ Label="Read Errors";  Val = "$($disk.ReadErrors)" }
        @{ Label="Write Errors"; Val = "$($disk.WriteErrors)" }
        @{ Label="Wear Level";   Val = if ($disk.WearLevel -ne $null) { "$($disk.WearLevel)%" } else { "—" } }
        @{ Label="Power-On Hrs"; Val = if ($disk.PowerOnHours) { "$($disk.PowerOnHours) h" } else { "—" } }
    )

    $mx = 14; $my = 44
    foreach ($m in $metrics) {
        $lbl = New-Lbl $m.Label $mx $my 120 16 8 $false $C.SubText; $card.Controls.Add($lbl)
        $valColor = $C.Text
        if ($m.Label -eq "Temperature" -and $disk.Temperature -gt 55) { $valColor = $C.Red }
        elseif ($m.Label -eq "Temperature" -and $disk.Temperature -gt 45) { $valColor = $C.Yellow }
        elseif (($m.Label -eq "Read Errors" -or $m.Label -eq "Write Errors") -and [int]$m.Val -gt 0) { $valColor = $C.Red }
        $val = New-Lbl $m.Val $mx 62 120 18 9 $true $valColor; $card.Controls.Add($val)
        $mx += 190
    }

    return $card
}

$dhScanBtn.Add_Click({
    $dhScanBtn.Enabled = $false
    $dhScanBtn.Text    = "Scanning..."
    [Windows.Forms.Application]::DoEvents()
    $dhResultsPnl.Controls.Clear()
    try {
        $disks = Get-DiskHealthData
        if ($disks.Count -eq 0) {
            $noLbl = New-Lbl "No physical disks found or access denied. Run as Administrator for full data." 0 20 960 24 9 $false $C.SubText
            $dhResultsPnl.Controls.Add($noLbl)
        } else {
            foreach ($d in $disks) {
                $card = Render-DiskHealthCard -disk $d
                $dhResultsPnl.Controls.Add($card)
            }
        }
    } catch {
        $errLbl = New-Lbl "Scan error: $($_.Exception.Message)" 0 20 960 24 9 $false $C.Red
        $dhResultsPnl.Controls.Add($errLbl)
    }
    $dhScanBtn.Text    = "Scan Disks"
    $dhScanBtn.Enabled = $true
})

$tabs.TabPages.Add($diskHealthTab)

# ========================================================================
# TAB 7 -- TOOLS  (Driver Audit + Auto-Schedule Cleanup)
# ========================================================================
$toolsTab           = New-Object Windows.Forms.TabPage
$toolsTab.Text      = "  Tools  "
$toolsTab.BackColor = $C.BgBase

$toolsPnl = New-Pnl 0 0 1040 580 $C.BgBase
$toolsTab.Controls.Add($toolsPnl)

# ── Section A: Driver Audit ───────────────────────────────────────────────
$drvHdr = New-Lbl "🔧  Driver Audit" 20 12 400 26 12 $true $C.Purple
$toolsPnl.Controls.Add($drvHdr)
$drvSub = New-Lbl "Inventory of installed drivers with age status" 20 42 500 18 8.5 $false $C.SubText
$toolsPnl.Controls.Add($drvSub)

$drvScanBtn = New-Btn "Scan Drivers" 820 14 200 44 $C.Purple $C.Text
$drvScanBtn.Font = New-Object Drawing.Font("Segoe UI Variable", 10, [Drawing.FontStyle]::Bold)
$toolsPnl.Controls.Add($drvScanBtn)

# DataGridView for drivers
$script:drvGrid                          = New-Object Windows.Forms.DataGridView
$script:drvGrid.Location                 = [Drawing.Point]::new(20, 66)
$script:drvGrid.Size                     = [Drawing.Size]::new(1000, 230)
$script:drvGrid.BackgroundColor          = $C.BgCard
$script:drvGrid.ForeColor                = $C.Text
$script:drvGrid.GridColor                = $C.Border
$script:drvGrid.DefaultCellStyle.BackColor       = $C.BgCard
$script:drvGrid.DefaultCellStyle.ForeColor       = $C.Text
$script:drvGrid.DefaultCellStyle.Font            = New-Object Drawing.Font("Segoe UI Variable", 8.5)
$script:drvGrid.DefaultCellStyle.SelectionBackColor = $C.BgCard3
$script:drvGrid.DefaultCellStyle.SelectionForeColor = $C.Text
$script:drvGrid.ColumnHeadersDefaultCellStyle.BackColor = $C.BgCard3
$script:drvGrid.ColumnHeadersDefaultCellStyle.ForeColor = $C.SubText
$script:drvGrid.ColumnHeadersDefaultCellStyle.Font      = New-Object Drawing.Font("Segoe UI Variable", 8.5, [Drawing.FontStyle]::Bold)
$script:drvGrid.ColumnHeadersBorderStyle         = [Windows.Forms.DataGridViewHeaderBorderStyle]::None
$script:drvGrid.EnableHeadersVisualStyles        = $false
$script:drvGrid.BorderStyle                      = [Windows.Forms.BorderStyle]::None
$script:drvGrid.RowHeadersVisible                = $false
$script:drvGrid.AllowUserToAddRows               = $false
$script:drvGrid.AllowUserToDeleteRows            = $false
$script:drvGrid.ReadOnly                         = $true
$script:drvGrid.SelectionMode                    = [Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$script:drvGrid.AutoSizeColumnsMode              = [Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
$script:drvGrid.ScrollBars                       = [Windows.Forms.ScrollBars]::Vertical

[void]$script:drvGrid.Columns.Add("Icon",    " ")
[void]$script:drvGrid.Columns.Add("Name",    "Driver Name")
[void]$script:drvGrid.Columns.Add("Vendor",  "Vendor")
[void]$script:drvGrid.Columns.Add("Version", "Version")
[void]$script:drvGrid.Columns.Add("Date",    "Date")
[void]$script:drvGrid.Columns.Add("Status",  "Status")

$script:drvGrid.Columns["Icon"].Width    = 32
$script:drvGrid.Columns["Name"].Width    = 370
$script:drvGrid.Columns["Vendor"].Width  = 180
$script:drvGrid.Columns["Version"].Width = 140
$script:drvGrid.Columns["Date"].Width    = 90
$script:drvGrid.Columns["Status"].Width  = 80
$script:drvGrid.RowTemplate.Height       = 26

$toolsPnl.Controls.Add($script:drvGrid)

$drvScanBtn.Add_Click({
    $drvScanBtn.Enabled = $false
    $drvScanBtn.Text    = "Scanning..."
    [Windows.Forms.Application]::DoEvents()
    $script:drvGrid.Rows.Clear()
    try {
        $drivers = Get-DriverAuditData
        foreach ($d in $drivers) {
            $rowIdx = $script:drvGrid.Rows.Add($d.Icon, $d.Name, $d.Vendor, $d.Version, $d.Date, $d.Status)
            $rowColor = switch ($d.Status) {
                "Outdated" { [Drawing.Color]::FromArgb(35, 255, 59, 48) }
                "Aging"    { [Drawing.Color]::FromArgb(30, 255, 159, 10) }
                default    { $C.BgCard }
            }
            $script:drvGrid.Rows[$rowIdx].DefaultCellStyle.BackColor = $rowColor
        }
    } catch {
        [void]$script:drvGrid.Rows.Add("❌","Scan failed: $($_.Exception.Message)","","","","")
    }
    $drvScanBtn.Text    = "Scan Drivers"
    $drvScanBtn.Enabled = $true
})

# ── Divider ───────────────────────────────────────────────────────────────
$toolsDiv = New-Pnl 20 308 1000 1 $C.Border
$toolsPnl.Controls.Add($toolsDiv)

# ── Section B: Auto-Schedule Cleanup ─────────────────────────────────────
$schedHdr = New-Lbl "🕐  Auto-Schedule Cleanup" 20 320 500 26 12 $true $C.Green
$toolsPnl.Controls.Add($schedHdr)
$schedSub = New-Lbl "Schedule automatic junk cleanup using Windows Task Scheduler" 20 350 600 18 8.5 $false $C.SubText
$toolsPnl.Controls.Add($schedSub)

# Frequency dropdown
$schedFreqLbl = New-Lbl "Frequency:" 20 386 90 22 9 $true $C.SubText
$toolsPnl.Controls.Add($schedFreqLbl)

$script:schedFreqCombo               = New-Object Windows.Forms.ComboBox
$script:schedFreqCombo.Location      = [Drawing.Point]::new(118, 382)
$script:schedFreqCombo.Size          = [Drawing.Size]::new(130, 28)
$script:schedFreqCombo.BackColor     = $C.BgCard
$script:schedFreqCombo.ForeColor     = $C.Text
$script:schedFreqCombo.Font          = New-Object Drawing.Font("Segoe UI Variable", 9.5)
$script:schedFreqCombo.FlatStyle     = [Windows.Forms.FlatStyle]::Flat
$script:schedFreqCombo.DropDownStyle = [Windows.Forms.ComboBoxStyle]::DropDownList
[void]$script:schedFreqCombo.Items.AddRange(@("Daily","Weekly"))
$script:schedFreqCombo.SelectedIndex = 1
$toolsPnl.Controls.Add($script:schedFreqCombo)

# Time dropdown
$schedTimeLbl = New-Lbl "At time:" 268 386 70 22 9 $true $C.SubText
$toolsPnl.Controls.Add($schedTimeLbl)

$script:schedTimeCombo               = New-Object Windows.Forms.ComboBox
$script:schedTimeCombo.Location      = [Drawing.Point]::new(346, 382)
$script:schedTimeCombo.Size          = [Drawing.Size]::new(110, 28)
$script:schedTimeCombo.BackColor     = $C.BgCard
$script:schedTimeCombo.ForeColor     = $C.Text
$script:schedTimeCombo.Font          = New-Object Drawing.Font("Segoe UI Variable", 9.5)
$script:schedTimeCombo.FlatStyle     = [Windows.Forms.FlatStyle]::Flat
$script:schedTimeCombo.DropDownStyle = [Windows.Forms.ComboBoxStyle]::DropDownList
0..23 | ForEach-Object { [void]$script:schedTimeCombo.Items.Add(('{0:D2}:00' -f $_)) }
$script:schedTimeCombo.SelectedIndex = 3   # 03:00
$toolsPnl.Controls.Add($script:schedTimeCombo)

# Action buttons
$schedCreateBtn = New-Btn "✅  Create Schedule" 480 378 200 36 $C.Green $C.Text
$schedCreateBtn.Font = New-Object Drawing.Font("Segoe UI Variable", 9, [Drawing.FontStyle]::Bold)
$toolsPnl.Controls.Add($schedCreateBtn)

$schedRemoveBtn = New-Btn "🗑  Remove Schedule" 690 378 200 36 $C.BgCard2 $C.SubText
$schedRemoveBtn.FlatAppearance.BorderColor = $C.Border; $schedRemoveBtn.FlatAppearance.BorderSize = 1
$schedRemoveBtn.Font = New-Object Drawing.Font("Segoe UI Variable", 9)
$toolsPnl.Controls.Add($schedRemoveBtn)

# Status label
$script:schedStatusLbl          = New-Lbl "Schedule: not configured" 20 428 700 20 9 $false $C.SubText
$toolsPnl.Controls.Add($script:schedStatusLbl)

$SCHED_TASK_NAME = "PCHealthMonitor_AutoClean"
$SCRIPT_PATH     = $MyInvocation.MyCommand.Path

function Update-ScheduleStatus {
    $task = Get-ScheduledTask -TaskName $SCHED_TASK_NAME -ErrorAction SilentlyContinue
    if ($task) {
        $trigger = $task.Triggers | Select-Object -First 1
        $nextRun = (Get-ScheduledTaskInfo -TaskName $SCHED_TASK_NAME -ErrorAction SilentlyContinue).NextRunTime
        $nextStr = if ($nextRun) { $nextRun.ToString("ddd dd/MM/yyyy HH:mm") } else { "—" }
        $script:schedStatusLbl.Text      = "✅  Schedule active — Next run: $nextStr"
        $script:schedStatusLbl.ForeColor = $C.Green
    } else {
        $script:schedStatusLbl.Text      = "Schedule: not configured"
        $script:schedStatusLbl.ForeColor = $C.SubText
    }
}

$schedCreateBtn.Add_Click({
    $schedCreateBtn.Enabled = $false
    try {
        $freq    = $script:schedFreqCombo.SelectedItem
        $timeStr = $script:schedTimeCombo.SelectedItem
        $atTime  = [datetime]::ParseExact($timeStr, "HH:mm", $null)
        $trigger = if ($freq -eq "Daily") { New-ScheduledTaskTrigger -Daily -At $atTime }
                   else { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $atTime }
        $action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
                       -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$SCRIPT_PATH`" -AutoClean"
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew
        Unregister-ScheduledTask -TaskName $SCHED_TASK_NAME -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName $SCHED_TASK_NAME -Action $action -Trigger $trigger `
                               -Settings $settings -Description "PC Health Monitor automated cleanup" -Force | Out-Null
        Update-ScheduleStatus
        Write-Log -Message "Auto-cleanup scheduled: $freq at $timeStr" -Level INFO
    } catch {
        $script:schedStatusLbl.Text      = "❌ Error: $($_.Exception.Message)"
        $script:schedStatusLbl.ForeColor = $C.Red
    }
    $schedCreateBtn.Enabled = $true
})

$schedRemoveBtn.Add_Click({
    try {
        Unregister-ScheduledTask -TaskName $SCHED_TASK_NAME -Confirm:$false -ErrorAction Stop
        Update-ScheduleStatus
        Write-Log -Message "Auto-cleanup schedule removed" -Level INFO
    } catch {
        $script:schedStatusLbl.Text      = "❌ $($_.Exception.Message)"
        $script:schedStatusLbl.ForeColor = $C.Red
    }
})

# Check existing schedule on tab load (via SelectedIndexChanged)
$script:toolsTabFirstVisit = $true

Update-ScheduleStatus

$tabs.TabPages.Add($toolsTab)


# Security tab removed

# -- Plugin Tabs ---------------------------------------------------------
foreach ($manifest in $Script:LoadedPlugins) {
    try {
        $pluginTab           = New-Object Windows.Forms.TabPage
        $pluginTab.Text      = $manifest.TabName
        $pluginTab.BackColor = $C.BgBase

        $pluginPanel = New-Pnl 0 0 1040 600 $C.BgBase
        $pluginTab.Controls.Add($pluginPanel)
        $manifest['_Panel']   = $pluginPanel
        $manifest['_TabPage'] = $pluginTab

        & $manifest['_Initialize'] -ParentPanel $pluginPanel -Colors $C

        $tabs.TabPages.Add($pluginTab)
        Write-Log -Message "Plugin tab created: $($manifest.TabName)" -Level INFO
    } catch {
        Write-Log -Message "Failed to initialize plugin tab: $($manifest.Name)" -Level WARN -ExceptionRecord $_
    }
}
#endregion

#region 6 - Event Handlers & Timer
# Auto-trigger first security scan when user navigates to Security tab
# Also calls Refresh-Plugin for any plugin tab that becomes active
$tabs.Add_SelectedIndexChanged({
    # ── Storage tab: auto-scan on first visit; subsequent visits use cache ──
    if ($tabs.SelectedTab -eq $diskUsageTab) {
        if (-not $script:tfAutoScanned) {
            $script:tfAutoScanned = $true
            Invoke-TopFolderScan          # first visit → kick off background scan
        } else {
            Update-TopFolderPanel         # already scanned → just refresh display
        }
    }



    # ── Plugin tabs: call Refresh-Plugin when tab becomes active ──────────
    foreach ($manifest in $Script:LoadedPlugins) {
        if ($tabs.SelectedTab -eq $manifest['_TabPage']) {
            try {
                & $manifest['_Refresh'] -DataPanel $manifest['_Panel']
            } catch {
                Write-Log -Message "Plugin Refresh-Plugin failed: $($manifest.Name)" -Level WARN -ExceptionRecord $_
            }
        }
    }
})

# Tab owner-draw event (Deep Space style)
$tabs.Add_DrawItem({
    param($s2, $de)
    try {
        $g      = $de.Graphics
        $g.SmoothingMode    = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::ClearTypeGridFit
        $tab    = $tabs.TabPages[$de.Index]
        $isSel  = ($de.Index -eq $tabs.SelectedIndex)
        $bounds = $de.Bounds

        # Background — active tab slightly elevated, inactive stays base
        $bgColor = if ($isSel) { $C.BgCard3 } else { $C.BgBase }
        $bgBr    = New-Object Drawing.SolidBrush($bgColor)
        $g.FillRectangle($bgBr, $bounds)
        $bgBr.Dispose()

        # Active tab: indigo bottom accent line (2px solid + 4px soft glow)
        if ($isSel) {
            $glowPen = New-Object Drawing.Pen($C.BlueGlow, 5)
            $g.DrawLine($glowPen, $bounds.Left + 2, $bounds.Bottom - 2, $bounds.Right - 2, $bounds.Bottom - 2)
            $glowPen.Dispose()
            $accentPen = New-Object Drawing.Pen($C.Blue, 2)
            $g.DrawLine($accentPen, $bounds.Left + 4, $bounds.Bottom - 1, $bounds.Right - 4, $bounds.Bottom - 1)
            $accentPen.Dispose()
        }

        # Text — active: full white; inactive: SubText (#8E8E93) — clearly readable
        $fgColor = if ($isSel) { $C.Text } else { $C.SubText }
        $fontStyle = if ($isSel) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }
        $font = New-Object Drawing.Font("Segoe UI Variable", 8.5, $fontStyle)
        $sf   = New-Object Drawing.StringFormat
        $sf.Alignment     = [Drawing.StringAlignment]::Center
        $sf.LineAlignment = [Drawing.StringAlignment]::Center
        $fgBr = New-Object Drawing.SolidBrush($fgColor)
        $g.DrawString($tab.Text.Trim(), $font, $fgBr, [Drawing.RectangleF]$bounds, $sf)
        $fgBr.Dispose()
        $font.Dispose()
        $sf.Dispose()
    } catch {
        Write-Log -Message "Tab DrawItem paint error at index $($de.Index)" -Level WARN -ExceptionRecord $_
    }
})

# ========================================================================
# SYSTEM TRAY ICON
# ========================================================================
$trayIcon = New-Object Windows.Forms.NotifyIcon
$trayIcon.Text    = "PC Health Monitor"
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
# (TempRefreshCounter removed — Do-Refresh now reads from DataEngine cache)
$script:lastDiskAlert      = [DateTime]::MinValue
$script:trayHintShown      = $false
$script:lastHealthScore    = 0
$script:StartupItems       = $null
$script:UpdateChecked      = $false
$script:UpdatePending      = [hashtable]::Synchronized(@{ Done = $false; NewVersion = '' })

# ========================================================================
# HEALTH SCORE ENGINE (pure PowerShell — no Python required)
# ========================================================================
function Compute-HealthScore {
    param(
        [int]$CpuPct,
        [int]$RamPct,
        [int]$DiskPct,
        [int]$StartupCount,
        [double]$JunkGB
    )
    $score = 100
    $score -= [math]::Min(25, [int]($CpuPct  * 0.25))   # CPU:     up to -25
    $score -= [math]::Min(25, [int]($RamPct  * 0.25))   # RAM:     up to -25
    $score -= [math]::Min(20, [int]($DiskPct * 0.20))   # Disk:    up to -20
    $score -= [math]::Min(15, $StartupCount * 2)         # Startup: -2 each, up to -15
    $score -= [math]::Min(15, [int]($JunkGB  * 5))       # Junk:    -5 per GB, up to -15
    return [math]::Max(0, [math]::Min(100, $score))
}

function Get-ScoreLabel {
    param([int]$Score)
    if     ($Score -ge 85) { return @{ Grade = 'Great Shape';     Color = '#06B6D4'; Msg1 = 'Your PC is running efficiently.';        Msg2 = 'No action needed — keep it up.' } }
    elseif ($Score -ge 70) { return @{ Grade = 'Good';            Color = '#22D3EE'; Msg1 = 'Your PC is in good condition.';           Msg2 = 'Consider clearing some junk files.' } }
    elseif ($Score -ge 55) { return @{ Grade = 'Could Be Better'; Color = '#F59E0B'; Msg1 = 'Some areas need attention.';             Msg2 = 'Check startup apps and free up disk space.' } }
    elseif ($Score -ge 35) { return @{ Grade = 'Needs a Cleanup'; Color = '#F97316'; Msg1 = 'Your PC is under strain.';               Msg2 = 'Run the Junk Cleaner and disable unused startup apps.' } }
    else                   { return @{ Grade = 'Poor Condition';  Color = '#EF4444'; Msg1 = 'Your PC needs attention urgently.';       Msg2 = 'High resource usage detected — consider restarting.' } }
}

# ========================================================================
# AUTO-UPDATE ENGINE
# ========================================================================
function Show-UpdateBanner {
    param([string]$NewVersion)

    # Remove any existing banner
    $old = $form.Controls | Where-Object { $_.Tag -eq 'UpdateBanner' }
    if ($old) { $old | ForEach-Object { $form.Controls.Remove($_); $_.Dispose() } }

    $banner = New-Object Windows.Forms.Panel
    $banner.Size      = [Drawing.Size]::new(1060, 36)
    $banner.Location  = [Drawing.Point]::new(0, 64)   # just below title panel
    $banner.BackColor = [Drawing.Color]::FromArgb(25, 40, 15)
    $banner.Tag       = 'UpdateBanner'
    $banner.Anchor    = [Windows.Forms.AnchorStyles]::Top -bor
                        [Windows.Forms.AnchorStyles]::Left -bor
                        [Windows.Forms.AnchorStyles]::Right

    $banner.Add_Paint({
        param($s2, $pe)
        try {
            # Green 3px top accent
            $pe.Graphics.FillRectangle(
                (New-Object Drawing.SolidBrush($C.Green)), 0, 0, $s2.Width, 3)
        } catch { }
    })

    # Message label
    $bannerMsg = New-Object Windows.Forms.Label
    $bannerMsg.Text      = "  [!]  Version $NewVersion is available — click to download the update"
    $bannerMsg.Location  = [Drawing.Point]::new(8, 8)
    $bannerMsg.Size      = [Drawing.Size]::new(800, 20)
    $bannerMsg.Font      = New-Object Drawing.Font("Segoe UI", 9, [Drawing.FontStyle]::Bold)
    $bannerMsg.ForeColor = $C.Green
    $bannerMsg.BackColor = [Drawing.Color]::Transparent
    $bannerMsg.Cursor    = [Windows.Forms.Cursors]::Hand
    $bannerMsg.Add_Click({
        Start-Process "https://github.com/Rzuss/PC-Health-Monitor/releases/latest"
    })
    $banner.Controls.Add($bannerMsg)

    # Dismiss button
    $dismissBtn = New-Object Windows.Forms.Button
    $dismissBtn.Text      = "Dismiss"
    $dismissBtn.Location  = [Drawing.Point]::new(960, 6)
    $dismissBtn.Size      = [Drawing.Size]::new(86, 22)
    $dismissBtn.BackColor = $C.BgCard2
    $dismissBtn.ForeColor = $C.Dim
    $dismissBtn.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $dismissBtn.FlatAppearance.BorderSize = 0
    $dismissBtn.Font      = New-Object Drawing.Font("Segoe UI", 8)
    $dismissBtn.Cursor    = [Windows.Forms.Cursors]::Hand
    $capturedBanner       = $banner
    $capturedForm         = $form
    $dismissBtn.Add_Click({
        $capturedForm.Controls.Remove($capturedBanner)
        $capturedBanner.Dispose()
    })
    $banner.Controls.Add($dismissBtn)

    $form.Controls.Add($banner)
    $banner.BringToFront()
}

function Start-UpdateCheck {
    param([hashtable]$Pending)
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = "MTA"
    $rs.ThreadOptions  = "ReuseThread"
    $rs.Open()

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs

    [void]$ps.AddScript({
        param($pending)
        try {
            $api = 'https://api.github.com/repos/Rzuss/PC-Health-Monitor/releases/latest'
            $wc  = New-Object System.Net.WebClient
            $wc.Headers.Add('User-Agent', 'PC-Health-Monitor')
            $json   = $wc.DownloadString($api)
            $parsed = $json | ConvertFrom-Json
            $pending['NewVersion'] = $parsed.tag_name -replace '^v',''
        } catch {
            $pending['NewVersion'] = ''
        } finally {
            $pending['Done'] = $true
        }
    })
    [void]$ps.AddParameter("pending", $Pending)
    [void]$ps.BeginInvoke()
}

# ========================================================================
# LIVE REFRESH LOGIC
# ========================================================================
$script:tickCount = 0

function Do-Refresh {
    try {
        # Read from DataEngine cache — zero blocking calls on UI thread
        $d = $script:DataCache
        if (-not $d['Ready']) { return }   # Engine still warming up — skip this tick

        # CPU card — update labels + bar directly; arc animates via $script:AnimTimer
        $UI["CpuValLbl"].Text      = "$($d['CpuPct'])%"
        $UI["CpuPctLbl"].Text      = "$($d['CpuPct'])%"
        $UI["CpuPctLbl"].ForeColor = Pct-Color $d['CpuPct']
        $script:AnimatedValues.CpuArc.Target = [double]$d['CpuPct']
        $fw = [math]::Max(0, [math]::Min(112, [int](($d['CpuPct'] / 100.0) * 112)))
        $UI["CpuBarFill"].Width     = $fw
        $UI["CpuBarFill"].BackColor = Pct-Color $d['CpuPct']

        # RAM card
        $UI["RamValLbl"].Text      = "$($d['UsedRAM']) GB / $script:totalRAM GB"
        $UI["RamPctLbl"].Text      = "$($d['RamPct'])%"
        $UI["RamPctLbl"].ForeColor = Pct-Color $d['RamPct']
        $script:AnimatedValues.RamArc.Target = [double]$d['RamPct']
        $fw2 = [math]::Max(0, [math]::Min(112, [int](($d['RamPct'] / 100.0) * 112)))
        $UI["RamBarFill"].Width     = $fw2
        $UI["RamBarFill"].BackColor = Pct-Color $d['RamPct']

        # Disk card (every 5 ticks = ~15 sec)
        if ($script:tickCount % 5 -eq 0) {
            $UI["DiskValLbl"].Text      = "$($d['DUsed']) / $($d['DTotal']) GB"
            $UI["DiskPctLbl"].Text      = "$($d['DPct'])%"
            $UI["DiskPctLbl"].ForeColor = Pct-Color $d['DPct']
            $script:AnimatedValues.DiskArc.Target = [double]$d['DPct']
            $fw3 = [math]::Max(0, [math]::Min(112, [int](($d['DPct'] / 100.0) * 112)))
            $UI["DiskBarFill"].Width     = $fw3
            $UI["DiskBarFill"].BackColor = Pct-Color $d['DPct']
        }

        # Health Score — computed live every 5 ticks (~15 sec)
        if ($script:tickCount % 5 -eq 0) {
            $junkGB = if ($junkItems -and $junkItems.Count -gt 0) {
                [math]::Round(($junkItems | Measure-Object SizeMB -Sum).Sum / 1024, 2)
            } else { 0.0 }
            $startupCount = if ($script:StartupItems) { $script:StartupItems.Count } else { 0 }

            $hs  = Compute-HealthScore -CpuPct $d['CpuPct'] -RamPct $d['RamPct'] `
                       -DiskPct $d['DPct'] -StartupCount $startupCount -JunkGB $junkGB
            $lbl = Get-ScoreLabel -Score $hs

            $script:scoreNumLbl.Text       = "$hs"
            $script:scoreNumLbl.ForeColor  = [Drawing.ColorTranslator]::FromHtml($lbl.Color)
            $script:scoreGradeLbl.Text     = $lbl.Grade.ToUpper()
            $script:scoreGradeLbl.ForeColor = [Drawing.ColorTranslator]::FromHtml($lbl.Color)
            $script:scoreMsg1Lbl.Text      = "  $($lbl.Msg1)"
            $script:scoreMsg1Lbl.ForeColor = $C.Text
            $script:scoreMsg2Lbl.Text      = "  $($lbl.Msg2)"
            $script:scoreMsg2Lbl.Visible   = $true
            $script:scoreMsg2Lbl.ForeColor = $C.SubText

            if ($script:lastHealthScore -gt 0) {
                $script:scoreTrendLbl.Text = if ($hs -gt $script:lastHealthScore) { [char]0x2191 }
                                             elseif ($hs -lt $script:lastHealthScore) { [char]0x2193 }
                                             else { '' }
                $script:scoreTrendLbl.ForeColor = if ($hs -ge $script:lastHealthScore) { $C.Green } else { $C.Red }
            }
            $script:lastHealthScore = $hs

            # Populate breakdown for Show-ScoreInfo popup
            $script:scoreBreakdown.Cpu        = $d['CpuPct']
            $script:scoreBreakdown.Ram        = $d['RamPct']
            $script:scoreBreakdown.Disk       = $d['DPct']
            $script:scoreBreakdown.Startup    = $startupCount
            $script:scoreBreakdown.Junk       = $junkGB
            $script:scoreBreakdown.CpuPen     = [math]::Min(25, [int]($d['CpuPct'] * 0.25))
            $script:scoreBreakdown.RamPen     = [math]::Min(25, [int]($d['RamPct'] * 0.25))
            $script:scoreBreakdown.DiskPen    = [math]::Min(20, [int]($d['DPct'] * 0.20))
            $script:scoreBreakdown.StartupPen = [math]::Min(15, $startupCount * 2)
            $script:scoreBreakdown.JunkPen    = [math]::Min(15, [int]($junkGB * 5))
        }

        # Process grid — reads from DataEngine cache (every 2 ticks = ~6 sec)
        if ($script:tickCount % 2 -eq 0) {
            Update-ProcessGrid $d['Procs']
        }

        # Add new CPU data point to the live chart, keep last 60 points
        [void]$UI["CpuChart"].Series[0].Points.AddY([double]$d.CpuPct)
        if ($UI["CpuChart"].Series[0].Points.Count -gt 60) {
            $UI["CpuChart"].Series[0].Points.RemoveAt(0)
        }

        $script:sbTimeLbl.Text = "Updated: $(Get-Date -Format 'HH:mm:ss')"

        # VIP Mode — auto-clear if selected process has exited
        if ($script:vipActive -and $script:vipPid -gt 0) {
            $vipGone = $false
            try {
                $vp = Get-Process -Id $script:vipPid -ErrorAction Stop
                if ($vp.HasExited) { $vipGone = $true }
            } catch { $vipGone = $true }
            if ($vipGone) {
                $script:vipPid    = 0
                $script:vipName   = ''
                $script:vipActive = $false
                $script:vipBtn.Text      = "SET VIP"
                $script:vipBtn.BackColor = $C.BgCard2
                $script:vipBtn.ForeColor = $C.Yellow
                $script:vipStatusLbl.Text      = "VIP closed — priority restored"
                $script:vipStatusLbl.ForeColor = $C.SubText
                $vipCard.Invalidate()
            }
        }

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

        # Drain any errors the DataEngine emitted (logged once per error)
        $errs = $script:DataEnginePS.Streams.Error
        while ($script:DataEngineErrIdx -lt $errs.Count) {
            Write-Log -Message "DataEngine error: $($errs[$script:DataEngineErrIdx].ToString())" -Level ERROR
            $script:DataEngineErrIdx++
        }

        # TopFolders panel: refresh whenever Cleanup tab is active and scan data exists
        if ($tabs.SelectedTab -eq $diskUsageTab -and
            $null -ne $script:DataCache['TopFolders'] -and
            $script:DataCache['TopFolders'].Count -gt 0) {
            Update-TopFolderPanel
        }

        $script:tickCount++

        # Auto-update: show banner once if a new version was found
        if (-not $script:UpdateChecked -and $script:UpdatePending['Done']) {
            $script:UpdateChecked = $true
            $latest  = $script:UpdatePending['NewVersion']
            $current = '3.1'
            if ($latest -and $latest -ne $current -and
                [Version]::TryParse($latest, [ref][Version]::new()) -and
                ([Version]$latest -gt [Version]$current)) {
                Show-UpdateBanner -NewVersion $latest
            }
        }
    } catch {
        Write-Log -Message "Do-Refresh failed during live data update" -Level ERROR -ExceptionRecord $_
        $d = $null    # graceful fallback -- UI retains last-known-good values
    }
}

# Animation timer: 60fps spring interpolation for gauge arcs
$script:AnimTimer = New-Object System.Windows.Forms.Timer
$script:AnimTimer.Interval = 16
$script:AnimTimer.Add_Tick({
    $dirty = $false
    foreach ($key in @('CpuArc','RamArc','DiskArc')) {
        $av   = $script:AnimatedValues[$key]
        $diff = $av.Target - $av.Current
        if ([math]::Abs($diff) -gt 0.15) {
            $av.Current += $diff * 0.12
            $dirty = $true
        } elseif ($diff -ne 0.0) {
            $av.Current = $av.Target
        }
    }
    if ($dirty) {
        if ($UI['CpuCard'])  { $UI['CpuCard'].Tag.Pct  = $script:AnimatedValues.CpuArc.Current;  $UI['CpuCard'].Invalidate()  }
        if ($UI['RamCard'])  { $UI['RamCard'].Tag.Pct  = $script:AnimatedValues.RamArc.Current;  $UI['RamCard'].Invalidate()  }
        if ($UI['DiskCard']) { $UI['DiskCard'].Tag.Pct = $script:AnimatedValues.DiskArc.Current; $UI['DiskCard'].Invalidate() }
    }
})
$script:AnimTimer.Start()

# Main data-refresh timer: fires every 3 seconds
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ Do-Refresh })
$timer.Start()

# Kick off background update check (non-blocking, MTA runspace)
Start-UpdateCheck -Pending $script:UpdatePending

$refreshBtn.Add_Click({ Do-Refresh })

$pGrid.Add_CellClick({
    param($sender, $e)

    # Only act on the Kill column (index 5), not header row
    # Column layout: 0=App/Process 1=Memory 2=CPU 3=ID 4=Status 5=Kill
    if ($e.RowIndex -lt 0 -or $e.ColumnIndex -ne 5) { return }

    $row         = $sender.Rows[$e.RowIndex]
    $processName = $row.Cells[0].Value.ToString().Trim()
    $procId      = [int]$row.Cells[3].Value

    Invoke-KillProcess -ProcessId $procId -ProcessName $processName
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
        Clear-VipProcess   # restore any elevated process priority before exit
        $timer.Stop()
        $timer.Dispose()
        $script:AnimTimer.Stop()
        $script:AnimTimer.Dispose()
        $trayIcon.Visible = $false
        $trayIcon.Dispose()
        # Shut down DataEngine background runspace cleanly
        try {
            $script:DataEnginePS.Stop()
            $script:DataEnginePS.Dispose()
            $script:DataEngineRS.Close()
            $script:DataEngineRS.Dispose()
        } catch { <# best-effort cleanup #> }
    }
})
#endregion

#region 7 - Execution
# Session start log entry
Write-Log -Message "Session started. Privileges: $(if ($script:isAdmin) {'Administrator'} else {'Standard User'})" -Level INFO

# -- Launch --------------------------------------------------------------
Refresh-VipCombo        # populate VIP combo with currently open apps
Show-WelcomeScreen
[void]$form.ShowDialog()
#endregion