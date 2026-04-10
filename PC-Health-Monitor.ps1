# PC-Health-Monitor.ps1
# Full Windows Forms GUI -- Dark Theme -- Live Auto-Refresh

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# -- Color Palette -------------------------------------------------------
$C = @{
    BgBase   = [Drawing.Color]::FromArgb(24,  24,  37)
    BgCard   = [Drawing.Color]::FromArgb(36,  36,  54)
    BgCard2  = [Drawing.Color]::FromArgb(49,  50,  68)
    Blue     = [Drawing.Color]::FromArgb(137, 180, 250)
    Green    = [Drawing.Color]::FromArgb(166, 227, 161)
    Red      = [Drawing.Color]::FromArgb(243, 139, 168)
    Yellow   = [Drawing.Color]::FromArgb(249, 226, 175)
    Purple   = [Drawing.Color]::FromArgb(203, 166, 247)
    Text     = [Drawing.Color]::FromArgb(205, 214, 244)
    SubText  = [Drawing.Color]::FromArgb(147, 153, 178)
    White    = [Drawing.Color]::White
    DarkRed  = [Drawing.Color]::FromArgb(180, 80,  100)
    DarkGreen= [Drawing.Color]::FromArgb(60,  140, 80)
}

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
    $b.Font   = New-Object Drawing.Font("Segoe UI", 9, [Drawing.FontStyle]::Bold)
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
    $g.GridColor          = $C.BgCard2
    $g.BorderStyle        = [Windows.Forms.BorderStyle]::None
    $g.RowHeadersVisible  = $false
    $g.ReadOnly           = $true
    $g.AllowUserToAddRows = $false
    $g.AllowUserToDeleteRows = $false
    $g.SelectionMode      = [Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $g.ColumnHeadersDefaultCellStyle.BackColor  = $C.BgCard2
    $g.ColumnHeadersDefaultCellStyle.ForeColor  = $C.Blue
    $g.ColumnHeadersDefaultCellStyle.Font       = New-Object Drawing.Font("Segoe UI", 9, [Drawing.FontStyle]::Bold)
    $g.ColumnHeadersHeightSizeMode = [Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::DisableResizing
    $g.ColumnHeadersHeight = 32
    $g.DefaultCellStyle.BackColor          = $C.BgCard
    $g.DefaultCellStyle.ForeColor          = $C.Text
    $g.DefaultCellStyle.SelectionBackColor = $C.BgCard2
    $g.DefaultCellStyle.SelectionForeColor = $C.White
    $g.DefaultCellStyle.Padding            = New-Object Windows.Forms.Padding(4,0,4,0)
    $g.AlternatingRowsDefaultCellStyle.BackColor = $C.BgCard2
    $g.Font = New-Object Drawing.Font("Segoe UI", 9)
    $g.RowTemplate.Height = 28
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

# -- Color helper for pct values -----------------------------------------
function Pct-Color($pct) {
    if ($pct -gt 85) { return $C.Red }
    elseif ($pct -gt 65) { return $C.Yellow }
    else { return $C.Green }
}

# -- Initial data collection ---------------------------------------------
$os       = Get-CimInstance Win32_OperatingSystem
$cpuInfo  = Get-CimInstance Win32_Processor
$totalRAM = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)

function Get-LiveData {
    $osNow  = Get-CimInstance Win32_OperatingSystem
    $cpuNow = Get-CimInstance Win32_Processor
    $diskC  = Get-PSDrive C

    $freeRAM = [math]::Round($osNow.FreePhysicalMemory / 1MB, 1)
    $usedRAM = [math]::Round($script:totalRAM - $freeRAM, 1)
    $ramPct  = [math]::Round(($usedRAM / $script:totalRAM) * 100)

    $dUsed = [math]::Round($diskC.Used / 1GB, 1)
    $dFree = [math]::Round($diskC.Free / 1GB, 1)
    $dTotal= [math]::Round(($diskC.Used + $diskC.Free) / 1GB, 1)
    $dPct  = [math]::Round(($dUsed / $dTotal) * 100)

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

# Junk files
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

# -- MAIN FORM -----------------------------------------------------------
$form = New-Object Windows.Forms.Form
$form.Text          = "PC Health Monitor - $env:COMPUTERNAME"
$form.Size          = [Drawing.Size]::new(980, 720)
$form.MinimumSize   = [Drawing.Size]::new(980, 720)
$form.BackColor     = $C.BgBase
$form.ForeColor     = $C.Text
$form.StartPosition = "CenterScreen"
$form.Font          = New-Object Drawing.Font("Segoe UI", 9)
try { $form.Icon = [Drawing.Icon]::ExtractAssociatedIcon("$env:SystemRoot\System32\perfmon.exe") } catch {}

# -- Title Bar -----------------------------------------------------------
$titlePnl = New-Pnl 0 0 980 64 $C.BgCard
$titlePnl.Controls.Add((New-Lbl "  PC Health Monitor" 12 8 500 32 15 $true $C.Blue))
$titlePnl.Controls.Add((New-Lbl "  $env:COMPUTERNAME   |   $($os.Caption)" 14 42 700 18 8 $false $C.SubText))

# Last-updated timestamp label
$lastUpdLbl = New-Lbl "Updated: just now" 700 48 250 16 7 $false $C.SubText
$titlePnl.Controls.Add($lastUpdLbl)

$refreshBtn = New-Btn "Refresh" 880 15 80 34 $C.BgCard2 $C.Blue
$titlePnl.Controls.Add($refreshBtn)
$form.Controls.Add($titlePnl)

# -- Tab Control ---------------------------------------------------------
$tabs = New-Object Windows.Forms.TabControl
$tabs.Location  = [Drawing.Point]::new(0, 64)
$tabs.Size      = [Drawing.Size]::new(980, 658)
$tabs.BackColor = $C.BgBase
$tabs.ForeColor = $C.Text
$tabs.Font      = New-Object Drawing.Font("Segoe UI", 10)
$form.Controls.Add($tabs)

# ========================================================================
# TAB 1 -- DASHBOARD
# ========================================================================
$tab1 = New-Object Windows.Forms.TabPage
$tab1.Text      = "   Dashboard   "
$tab1.BackColor = $C.BgBase

# -- Stat cards -- store references for live updates --------------------
$UI = @{}   # holds all updateable controls

$cardDefs = @(
    @{Key="Cpu";  Title="CPU Load";   X=15;  Color=$C.Blue;   Val="$($live.CpuPct)%";                                     Pct=$live.CpuPct},
    @{Key="Ram";  Title="RAM Usage";  X=338; Color=$C.Purple; Val="$($live.UsedRAM) GB / $totalRAM GB";                   Pct=$live.RamPct},
    @{Key="Disk"; Title="Disk C:";    X=661; Color=$C.Yellow; Val="$($live.DUsed) GB used  |  $($live.DFree) GB free";    Pct=$live.DPct}
)

foreach ($cd in $cardDefs) {
    $cp = New-Pnl $cd.X 15 298 118 $C.BgCard

    $topBar = New-Pnl 0 0 298 4 $cd.Color
    $cp.Controls.Add($topBar)
    $cp.Controls.Add((New-Lbl $cd.Title 14 12 270 22 9 $false $C.SubText))

    $valLbl = New-Lbl $cd.Val 14 36 270 30 12 $true $cd.Color
    $cp.Controls.Add($valLbl)
    $UI[$cd.Key + "ValLbl"] = $valLbl

    $pct = [math]::Min([math]::Max($cd.Pct, 0), 100)
    $pb = New-Object Windows.Forms.ProgressBar
    $pb.Location = [Drawing.Point]::new(14, 82)
    $pb.Size     = [Drawing.Size]::new(256, 10)
    $pb.Minimum  = 0; $pb.Maximum = 100; $pb.Value = $pct
    $pb.Style    = [Windows.Forms.ProgressBarStyle]::Continuous
    $cp.Controls.Add($pb)
    $UI[$cd.Key + "Pb"] = $pb

    $pctLbl = New-Lbl "$pct%" 274 76 34 18 8 $true (Pct-Color $pct)
    $cp.Controls.Add($pctLbl)
    $UI[$cd.Key + "PctLbl"] = $pctLbl

    $tab1.Controls.Add($cp)
}

# -- Process list -------------------------------------------------------
$tab1.Controls.Add((New-Lbl "  Top 25 Processes by RAM" 15 145 500 26 11 $true $C.Text))

$pGrid = New-Object Windows.Forms.DataGridView
$pGrid.Location = [Drawing.Point]::new(15, 174)
$pGrid.Location = [Drawing.Point]::new(15, 174)
$pGrid.Size     = [Drawing.Size]::new(940, 420)
Style-Grid $pGrid
Add-Col $pGrid "Process Name" 220
Add-Col $pGrid "RAM (MB)"      80
Add-Col $pGrid "CPU (sec)"     80
Add-Col $pGrid "PID"           60

function Refresh-ProcessGrid {
    $procs = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 25 `
        Name, Id,
        @{N="RAM MB"; E={[math]::Round($_.WorkingSet64/1MB,1)}},
        @{N="CPU sec";E={[math]::Round($_.CPU,1)}}

    $pGrid.SuspendLayout()
    $pGrid.Rows.Clear()
    foreach ($p in $procs) {
        $ri = $pGrid.Rows.Add($p.Name, $p.'RAM MB', $p.'CPU sec', $p.Id)
        if ($p.'RAM MB' -gt 500)     { $pGrid.Rows[$ri].DefaultCellStyle.ForeColor = $C.Red }
        elseif ($p.'RAM MB' -gt 200) { $pGrid.Rows[$ri].DefaultCellStyle.ForeColor = $C.Yellow }
    }
    $pGrid.ResumeLayout()
}
Refresh-ProcessGrid

$tab1.Controls.Add($pGrid)
$tabs.TabPages.Add($tab1)

# ========================================================================
# TAB 2 -- STARTUP PROGRAMS
# ========================================================================
$tab2 = New-Object Windows.Forms.TabPage
$tab2.Text      = "   Startup Programs   "
$tab2.BackColor = $C.BgBase

$tab2.Controls.Add((New-Lbl "  Programs that launch automatically on boot" 15 15 700 26 11 $true $C.Text))
$tab2.Controls.Add((New-Lbl "  Disabling a User item removes it from the registry. System items require admin rights." 15 43 900 18 8 $false $C.SubText))
$tab2.Controls.Add((New-Lbl "  Found $($startups.Count) startup items" 15 63 400 20 9 $false $C.Yellow))

$sGrid = New-Object Windows.Forms.DataGridView
$sGrid.Location = [Drawing.Point]::new(15, 90)
$sGrid.Size     = [Drawing.Size]::new(940, 520)
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
$disableCol.DefaultCellStyle.Font      = New-Object Drawing.Font("Segoe UI", 9, [Drawing.FontStyle]::Bold)
$disableCol.DefaultCellStyle.Alignment = [Windows.Forms.DataGridViewContentAlignment]::MiddleCenter
[void]$sGrid.Columns.Add($disableCol)

# Custom paint Action column -- identical look on every row regardless of selection
$sGrid.Add_CellPainting({
    param($s2, $ep)
    if ($ep.RowIndex -lt 0 -or $ep.ColumnIndex -lt 0) { return }
    if ($sGrid.Columns[$ep.ColumnIndex].Name -ne "Action")  { return }
    $ep.Handled = $true

    $cellVal  = if ($ep.Value) { $ep.Value.ToString() } else { "Disable" }
    $btnColor = if ($cellVal -eq "Disabled!") { $C.DarkGreen } else { $C.DarkRed }

    # Row background (match alternating style)
    $rowBg = if ($ep.RowIndex % 2 -eq 0) { $C.BgCard } else { $C.BgCard2 }
    $ep.Graphics.FillRectangle((New-Object Drawing.SolidBrush($rowBg)), $ep.CellBounds)

    # Button rectangle with small padding
    $rect = [Drawing.Rectangle]::new(
        $ep.CellBounds.X + 6,
        $ep.CellBounds.Y + 4,
        $ep.CellBounds.Width - 12,
        $ep.CellBounds.Height - 8)
    $ep.Graphics.FillRectangle((New-Object Drawing.SolidBrush($btnColor)), $rect)

    # Centered text
    $sf = New-Object Drawing.StringFormat
    $sf.Alignment     = [Drawing.StringAlignment]::Center
    $sf.LineAlignment = [Drawing.StringAlignment]::Center
    $font = New-Object Drawing.Font("Segoe UI", 9, [Drawing.FontStyle]::Bold)
    $ep.Graphics.DrawString($cellVal, $font, (New-Object Drawing.SolidBrush($C.White)), ([Drawing.RectangleF]$rect), $sf)
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
$tab3.Text      = "   Cleanup   "
$tab3.BackColor = $C.BgBase

$tab3.Controls.Add((New-Lbl "  Junk Files - Recoverable Space" 15 15 500 28 12 $true $C.Text))
$tab3.Controls.Add((New-Lbl "  Total found: $totalJunkGB GB across $($junkItems.Count) locations" 15 45 600 22 9 $false $C.Red))

$hdrPnl = New-Pnl 15 72 940 28 $C.BgCard2
$hdrPnl.Controls.Add((New-Lbl "Location"  10  5 230 18 9 $true $C.Blue))
$hdrPnl.Controls.Add((New-Lbl "Size"     248  5 100 18 9 $true $C.Blue))
$hdrPnl.Controls.Add((New-Lbl "Files"    355  5  60 18 9 $true $C.Blue))
$hdrPnl.Controls.Add((New-Lbl "Path"     422  5 310 18 9 $true $C.Blue))
$tab3.Controls.Add($hdrPnl)

$logBox = New-Object Windows.Forms.RichTextBox
$logBox.Location    = [Drawing.Point]::new(15, 540)
$logBox.Size        = [Drawing.Size]::new(940, 90)
$logBox.BackColor   = $C.BgCard
$logBox.ForeColor   = $C.Green
$logBox.Font        = New-Object Drawing.Font("Consolas", 9)
$logBox.ReadOnly    = $true
$logBox.BorderStyle = [Windows.Forms.BorderStyle]::None
$logBox.Text        = "Ready. Use the Clean buttons to remove junk files."
$tab3.Controls.Add($logBox)

$rY = 103
foreach ($ji in $junkItems) {
    $rPnl  = New-Pnl 15 $rY 940 56 $C.BgCard
    $sColor = if ($ji.SizeMB -gt 500) {$C.Red} elseif ($ji.SizeMB -gt 100) {$C.Yellow} else {$C.Green}

    $rPnl.Controls.Add((New-Lbl $ji.Name           8   8 230 20 10 $true  $C.Text))
    $rPnl.Controls.Add((New-Lbl "$($ji.SizeMB) MB" 246  8 100 20 10 $true  $sColor))
    $rPnl.Controls.Add((New-Lbl "$($ji.Files) files" 353  8  70 20  9 $false $C.SubText))
    $rPnl.Controls.Add((New-Lbl $ji.Path           8  32 560 16  7 $false $C.SubText))

    $cleanBtn = New-Btn "Clean" 740 10 100 36 $C.DarkRed  $C.White
    $skipBtn  = New-Btn "Skip"  848 10  80 36 $C.BgCard2  $C.SubText
    $cleanBtn.Tag = $ji.Path

    $cleanBtn.Add_Click({
        param($sender, $e)
        $targetPath      = $sender.Tag
        $sender.Enabled  = $false
        $sender.Text     = "..."
        $sender.BackColor = $C.SubText
        $logBox.AppendText("`nCleaning: $targetPath")
        [Windows.Forms.Application]::DoEvents()
        $del=0; $err=0
        Get-ChildItem $targetPath -Recurse -Force -EA SilentlyContinue | ForEach-Object {
            try   { Remove-Item $_.FullName -Force -Recurse -EA Stop; $del++ }
            catch { $err++ }
        }
        $sender.Text      = "Done"
        $sender.BackColor = $C.DarkGreen
        $logBox.AppendText("  Done - removed $del items ($err locked/skipped)")
        $logBox.ScrollToCaret()
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

$cleanAllBtn = New-Btn "Clean All" 810 638 120 36 $C.DarkRed $C.White
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
            $logBox.AppendText("`nCleaning: $($ji2.Path)")
            [Windows.Forms.Application]::DoEvents()
            $del=0; $err=0
            Get-ChildItem $ji2.Path -Recurse -Force -EA SilentlyContinue | ForEach-Object {
                try   { Remove-Item $_.FullName -Force -Recurse -EA Stop; $del++ }
                catch { $err++ }
            }
            $logBox.AppendText("  -> $del removed, $err skipped")
        }
        $logBox.AppendText("`n--- DONE ---")
        $logBox.ScrollToCaret()
    }
})

$tabs.TabPages.Add($tab3)

# ========================================================================
# LIVE REFRESH LOGIC
# ========================================================================
$script:tickCount = 0

function Do-Refresh {
    try {
        $d = Get-LiveData

        # CPU card
        $UI["CpuValLbl"].Text  = "$($d.CpuPct)%"
        $UI["CpuPb"].Value     = [math]::Min($d.CpuPct, 100)
        $UI["CpuPctLbl"].Text  = "$($d.CpuPct)%"
        $UI["CpuPctLbl"].ForeColor = Pct-Color $d.CpuPct

        # RAM card
        $UI["RamValLbl"].Text  = "$($d.UsedRAM) GB / $script:totalRAM GB"
        $UI["RamPb"].Value     = [math]::Min($d.RamPct, 100)
        $UI["RamPctLbl"].Text  = "$($d.RamPct)%"
        $UI["RamPctLbl"].ForeColor = Pct-Color $d.RamPct

        # Disk card (every 5 ticks = ~15 sec)
        if ($script:tickCount % 5 -eq 0) {
            $UI["DiskValLbl"].Text = "$($d.DUsed) GB used  |  $($d.DFree) GB free"
            $UI["DiskPb"].Value    = [math]::Min($d.DPct, 100)
            $UI["DiskPctLbl"].Text = "$($d.DPct)%"
            $UI["DiskPctLbl"].ForeColor = Pct-Color $d.DPct
        }

        # Process grid (every 2 ticks = ~6 sec)
        if ($script:tickCount % 2 -eq 0) {
            Refresh-ProcessGrid
        }

        $lastUpdLbl.Text = "Updated: $(Get-Date -Format 'HH:mm:ss')"
        $script:tickCount++
    } catch {}
}

# Timer: fires every 3 seconds
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ Do-Refresh })
$timer.Start()

# Refresh button: immediate refresh
$refreshBtn.Add_Click({ Do-Refresh })

# Stop timer when form closes
$form.Add_FormClosing({ $timer.Stop(); $timer.Dispose() })

# -- Launch --------------------------------------------------------------
[void]$form.ShowDialog()
