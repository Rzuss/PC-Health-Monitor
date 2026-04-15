# Claude Code Task: Complete UI Redesign — PC-Health-Monitor.ps1
# Cyber-HUD Dark Theme — WinForms Production Redesign

## Project Context
File: `PC-Health-Monitor.ps1` (808 lines, PowerShell 5.1, WinForms)
Current state: Catppuccin Mocha theme, flat cards, standard ProgressBars, DataGridView.
Goal: Transform into a premium Cyber-HUD dark interface using GDI+ custom painting.
ALL existing functionality (data, refresh, cleanup, startup, tray) must be preserved exactly.

## CRITICAL RULES (follow exactly)
- ASCII-only characters (NO em-dashes, NO Unicode, NO smart quotes)
- Use Get-CimInstance NOT Get-WmiObject
- PascalCase for all functions and variables
- All custom painting in Try-Catch blocks
- Do NOT modify any data logic, only UI code
- No external dependencies — pure PowerShell + WinForms + GDI+

---

## STEP 1 — New Color Palette

Replace the entire `$C` hashtable (lines 14-28) with this:

```powershell
$C = @{
    BgBase     = [Drawing.Color]::FromArgb(2,   6,   23)   # #020617 obsidian
    BgCard     = [Drawing.Color]::FromArgb(10,  18,  40)   # deep navy card
    BgCard2    = [Drawing.Color]::FromArgb(18,  30,  58)   # hover/alt row
    BgCard3    = [Drawing.Color]::FromArgb(15,  23,  42)   # section header
    Blue       = [Drawing.Color]::FromArgb(56,  189, 248)  # #38bdf8 electric blue
    BlueGlow   = [Drawing.Color]::FromArgb(30,  100, 160)  # blue dim for tracks
    Purple     = [Drawing.Color]::FromArgb(168, 85,  247)  # #a855f7 neon purple
    PurpleGlow = [Drawing.Color]::FromArgb(80,  40,  130)  # purple dim
    Green      = [Drawing.Color]::FromArgb(74,  222, 128)  # #4ade80 neon green
    Yellow     = [Drawing.Color]::FromArgb(250, 204, 21)   # #facc15 amber
    Red        = [Drawing.Color]::FromArgb(248, 113, 113)  # #f87171 rose
    Orange     = [Drawing.Color]::FromArgb(251, 146, 60)   # #fb923c heat orange
    Text       = [Drawing.Color]::FromArgb(226, 232, 240)  # #e2e8f0
    SubText    = [Drawing.Color]::FromArgb(148, 163, 184)  # slate-400
    Dim        = [Drawing.Color]::FromArgb(71,  85,  105)  # slate-600
    White      = [Drawing.Color]::White
    DarkRed    = [Drawing.Color]::FromArgb(185, 40,  60)
    DarkGreen  = [Drawing.Color]::FromArgb(30,  140, 70)
    Border     = [Drawing.Color]::FromArgb(30,  50,  80)   # card border color
}
```

---

## STEP 2 — New Helper Functions

Add these NEW helper functions AFTER the existing `Add-Col` function and BEFORE `Pct-Color`:

### 2a. Draw-CircleGauge — Custom GDI+ circular progress gauge
```powershell
function Draw-CircleGauge {
    param($Graphics, $CenterX, $CenterY, $Radius, $Pct, $Color, $TrackColor, $Thick = 6)
    # Track (background arc)
    $rect = [Drawing.RectangleF]::new($CenterX - $Radius, $CenterY - $Radius, $Radius * 2, $Radius * 2)
    $trackPen = New-Object Drawing.Pen($TrackColor, $Thick)
    $trackPen.StartCap = [Drawing.Drawing2D.LineCap]::Round
    $trackPen.EndCap   = [Drawing.Drawing2D.LineCap]::Round
    $Graphics.DrawArc($trackPen, $rect, -90, 360)
    # Filled arc
    $sweep = [math]::Max(0, [math]::Min(360, ($Pct / 100) * 360))
    if ($sweep -gt 2) {
        $pen = New-Object Drawing.Pen($Color, $Thick)
        $pen.StartCap = [Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap   = [Drawing.Drawing2D.LineCap]::Round
        $Graphics.DrawArc($pen, $rect, -90, $sweep)
    }
    # Center text
    $font = New-Object Drawing.Font("Consolas", 8, [Drawing.FontStyle]::Bold)
    $label = "$([math]::Round($Pct))%"
    $sf = New-Object Drawing.StringFormat
    $sf.Alignment = [Drawing.StringAlignment]::Center
    $sf.LineAlignment = [Drawing.StringAlignment]::Center
    $brush = New-Object Drawing.SolidBrush($Color)
    $textRect = [Drawing.RectangleF]::new($CenterX - $Radius, $CenterY - $Radius, $Radius * 2, $Radius * 2)
    $Graphics.DrawString($label, $font, $brush, $textRect, $sf)
}
```

### 2b. Draw-GlowBorder — Simulates glowing card border with colored top accent
```powershell
function Draw-GlowBorder {
    param($Graphics, $Width, $Height, $AccentColor, $AccentThick = 2)
    # Dark border all around
    $borderPen = New-Object Drawing.Pen($C.Border, 1)
    $Graphics.DrawRectangle($borderPen, 0, 0, $Width - 1, $Height - 1)
    # Bright top accent line
    $accentPen = New-Object Drawing.Pen($AccentColor, $AccentThick)
    $Graphics.DrawLine($accentPen, 0, 0, $Width, 0)
}
```

### 2c. Updated Pct-Color function (replace existing):
```powershell
function Pct-Color($pct) {
    if ($pct -gt 85) { return $C.Red    }
    elseif ($pct -gt 65) { return $C.Yellow }
    else { return $C.Green }
}
```

---

## STEP 3 — Form & Title Bar

### 3a. Update form properties:
```powershell
$form.Size          = [Drawing.Size]::new(1060, 720)
$form.MinimumSize   = [Drawing.Size]::new(1060, 720)
$form.BackColor     = $C.BgBase
$form.Font          = New-Object Drawing.Font("Segoe UI", 9)
```

### 3b. New Title Panel (replace titlePnl block):
- Background: `$C.BgCard`
- Add bottom border line: 1px `$C.Border`
- Title font: **Consolas 14pt Bold**, color `$C.Blue`
- Sub-label font: Segoe UI 8pt, color `$C.Dim`
- Add a small 8x8 circle dot LEFT of the title (drawn via Panel Paint event), color `$C.Blue`
- "Refresh" button: background `$C.BgCard2`, border `$C.Border`, text `$C.Blue`, font Consolas 9pt Bold
- Title panel height stays 64px

### 3c. Admin warning strip:
- Background: `[Drawing.Color]::FromArgb(40, 35, 10)` (dark amber)
- Left border 3px `$C.Yellow`
- Text color: `$C.Yellow`, font Consolas 8pt

---

## STEP 4 — TabControl Styling

Update `$tabs` styling:
```powershell
$tabs.DrawMode = [Windows.Forms.TabDrawMode]::OwnerDrawFixed
$tabs.ItemSize = [Drawing.Size]::new(140, 28)
$tabs.Add_DrawItem({
    param($s2, $de)
    $tab = $tabs.TabPages[$de.Index]
    $isSelected = ($de.Index -eq $tabs.SelectedIndex)
    $bgColor = if ($isSelected) { $C.BgCard2 } else { $C.BgBase }
    $fgColor = if ($isSelected) { $C.Blue    } else { $C.Dim    }
    $de.Graphics.FillRectangle((New-Object Drawing.SolidBrush($bgColor)), $de.Bounds)
    if ($isSelected) {
        $accentPen = New-Object Drawing.Pen($C.Blue, 2)
        $de.Graphics.DrawLine($accentPen, $de.Bounds.Left, $de.Bounds.Bottom - 1,
                              $de.Bounds.Right, $de.Bounds.Bottom - 1)
    }
    $font = New-Object Drawing.Font("Consolas", 9, [Drawing.FontStyle]::Bold)
    $sf = New-Object Drawing.StringFormat
    $sf.Alignment = [Drawing.StringAlignment]::Center
    $sf.LineAlignment = [Drawing.StringAlignment]::Center
    $de.Graphics.DrawString($tab.Text.Trim(), $font,
        (New-Object Drawing.SolidBrush($fgColor)), [Drawing.RectangleF]$de.Bounds, $sf)
})
```

Tab page backgrounds: all tabs `$C.BgBase`
Tab text strings: `"  Dashboard  "`, `"  Startup Programs  "`, `"  Cleanup  "`

---

## STEP 5 — Dashboard Tab Redesign (TAB 1)

### 5a. Stat Cards — replace 3 flat cards with custom-painted panels

Each stat card panel gets an `Add_Paint` event for custom GDI+ rendering:

For each of the 3 cards (CPU, RAM, Disk), add a Paint event:
```powershell
$cp.Add_Paint({
    param($s2, $pe)
    try {
        $g = $pe.Graphics
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        # Background
        $g.FillRectangle((New-Object Drawing.SolidBrush($C.BgCard)), 0, 0, $cp.Width, $cp.Height)
        # Top accent line (2px, card accent color)
        Draw-GlowBorder $g $cp.Width $cp.Height $accentColor 2
        # Circular gauge — drawn at LEFT side of card
        Draw-CircleGauge $g 46 56 32 $pctValue $accentColor $C.BgCard2 5
    } catch {}
})
```

- Card size: `[Drawing.Size]::new(308, 110)` — wider cards to accommodate gauge
- Card X positions: 15, 338, 661 (same as before, form is wider now)
- Remove the old ProgressBar from each card
- Add the CircleGauge painted at position (46, 55) radius 30 inside each card
- Keep the value label (top-right of card, large), SubText title label
- Add a small "progress bar" BELOW the gauge text — thin 4px bar, 200px wide, color-coded

### 5b. CPU Chart

- Update chart BackColor to `$C.BgBase`
- ChartArea BackColor: `$C.BgBase`
- AxisY LabelStyle ForeColor: `$C.Dim`
- AxisY LineColor: `$C.Border`
- AxisY MajorGrid LineColor: `$C.Border`
- Series color: `$C.Blue` (keep same)
- Add a subtle gradient fill under the line:
  ```powershell
  $cpuSeries.ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::SplineArea
  $cpuSeries.Color     = [Drawing.Color]::FromArgb(56, 189, 248)
  $cpuSeries.BackSecondaryColor = [Drawing.Color]::FromArgb(0, 10, 18, 40)
  $cpuSeries.BackGradientStyle = [System.Windows.Forms.DataVisualization.Charting.GradientStyle]::TopBottom
  ```

### 5c. Process Grid (DataGridView)

- BackgroundColor: `$C.BgCard`
- ColumnHeadersDefaultCellStyle.BackColor: `$C.BgCard3`
- ColumnHeadersDefaultCellStyle.ForeColor: `$C.Blue`
- ColumnHeadersDefaultCellStyle.Font: Consolas 9pt Bold
- DefaultCellStyle.BackColor: `$C.BgCard`
- DefaultCellStyle.ForeColor: `$C.Text`
- DefaultCellStyle.Font: Consolas 9pt
- AlternatingRowsDefaultCellStyle.BackColor: `$C.BgCard2`
- GridColor: `$C.Border`
- SelectionBackColor: `$C.BgCard2`
- SelectionForeColor: `$C.Blue`
- RowTemplate.Height: 26
- Add a colored left border to HIGH RAM rows:
  In `Refresh-ProcessGrid`, for rows with RAM > 500: ForeColor = `$C.Red`
  For rows with RAM > 200: ForeColor = `$C.Yellow`

### 5d. Section label "Top 25 Processes by RAM"
- Font: Consolas 11pt Bold, color `$C.Blue`
- Add a small 2px bottom underline using a thin Panel below the label, color `$C.Blue`, width 220px, height 1px

---

## STEP 6 — Startup Programs Tab Redesign (TAB 2)

### 6a. Header labels:
- Title: Consolas 11pt Bold, color `$C.Blue`
- Subtitle: Consolas 8pt, color `$C.Dim`
- Count label: Consolas 9pt, color `$C.Yellow`

### 6b. Startup DataGridView:
Apply same DataGridView styling as Process Grid above.
ColumnHeaders font: Consolas 9pt Bold.

### 6c. Disable button column (CellPainting — update existing event):
- Active "Disable" button: background `$C.DarkRed`, text WHITE, Consolas 9pt Bold
- "Disabled!" state: background `$C.DarkGreen`
- "Admin req." state: background `$C.Dim`
- Add a thin 1px border inside each button rect using `$C.Border` pen

---

## STEP 7 — Cleanup Tab Redesign (TAB 3)

### 7a. Section title: Consolas 12pt Bold, color `$C.Blue`
### 7b. Total label: Consolas 9pt, color `$C.Red`

### 7c. Header panel (hdrPnl):
- BackColor: `$C.BgCard3`
- Labels: Consolas 9pt Bold, color `$C.Blue`
- Add a bottom border line via Paint event

### 7d. Each cleanup row panel (rPnl):
Replace flat panel with custom-painted panel:
```powershell
$rPnl.Add_Paint({
    param($s2, $pe)
    try {
        $g = $pe.Graphics
        $g.FillRectangle((New-Object Drawing.SolidBrush($C.BgCard)), 0, 0, $rPnl.Width, $rPnl.Height)
        # Left accent stripe (4px wide, color based on size)
        $stripeColor = if ($ji.SizeMB -gt 500) { $C.Red } elseif ($ji.SizeMB -gt 100) { $C.Yellow } else { $C.Green }
        $g.FillRectangle((New-Object Drawing.SolidBrush($stripeColor)), 0, 0, 3, $rPnl.Height)
        # Bottom separator
        $g.DrawLine((New-Object Drawing.Pen($C.Border, 1)), 0, $rPnl.Height - 1, $rPnl.Width, $rPnl.Height - 1)
    } catch {}
})
```
- Name label: Consolas 10pt Bold, color `$C.Text`
- Size label: Consolas 10pt Bold, color based on size (Red/Yellow/Green)
- Files label: Consolas 9pt, color `$C.SubText`
- Path label: Consolas 7pt, color `$C.Dim`

### 7e. Clean/Skip buttons:
- Clean button: background `$C.DarkRed`, text `$C.White`, Consolas 9pt Bold, border `$C.Red`
- Skip button: background `$C.BgCard2`, text `$C.Dim`, Consolas 9pt
- "Done" state: background `$C.DarkGreen`, text `$C.White`
- Disabled Clean button: background `$C.Dim`

### 7f. Log box (RichTextBox):
- BackColor: `$C.BgCard`
- ForeColor: `$C.Green`
- Font: Consolas 9pt
- Border: `BorderStyle.None` (keep existing)
- Add a 1px top border via containing panel Paint event

### 7g. Clean All button:
- Background `$C.DarkRed`, text `$C.White`, Consolas 9pt Bold
- Add hover effect via MouseEnter/MouseLeave

---

## STEP 8 — System Tray & Form Closing (no changes)

Keep the System Tray code EXACTLY as-is. Do NOT modify the tray menu,
balloon alerts, form closing handler, or ShowDialog call.

---

## STEP 9 — Timer & Refresh Logic (no changes)

Keep Do-Refresh, Get-LiveData, Refresh-ProcessGrid EXACTLY as-is.
Only the visual rendering changes — all data logic stays identical.

---

## STEP 10 — Font Global Update

At the top of the form setup, after `[System.Windows.Forms.Application]::EnableVisualStyles()`, add:
```powershell
# Set Consolas as fallback for all monospace elements
$script:MonoFont = New-Object Drawing.Font("Consolas", 9)
$script:MonoBold = New-Object Drawing.Font("Consolas", 9, [Drawing.FontStyle]::Bold)
$script:UIFont   = New-Object Drawing.Font("Segoe UI",  9)
```

Use `$script:MonoBold` for all numeric values (CPU%, RAM GB, process names).
Use `$script:UIFont` for descriptive text labels.

---

## STEP 11 — Animated Title Clock

Replace the static `$lastUpdLbl` logic with a version that includes a colored dot indicator:
- Label text: `"  dated: HH:mm:ss"` (keep existing format)
- Font: Consolas 7pt, color `$C.Dim`
- Add a blinking dot panel (4x4px, BackColor `$C.Green`) that toggles opacity via timer

---

## Quality Checklist (verify before saving)

1. File parses without errors: `powershell -NoProfile -Command "& { . '.\PC-Health-Monitor.ps1' }"`
2. No ASCII violations (check with: `Select-String -Path '.\PC-Health-Monitor.ps1' -Pattern '[^\x00-\x7F]'` — must return nothing)
3. All 3 tabs render correctly: Dashboard, Startup Programs, Cleanup
4. System tray still works
5. Refresh button updates data
6. CircleGauge appears on all 3 stat cards
7. Custom tab drawing (OwnerDrawFixed) renders without flicker
8. DataGridView alternating row colors visible
9. Cleanup row left accent stripe visible
10. No white/default-colored panels remaining — every panel has explicit BackColor

---

## Deliverable

The complete modified `PC-Health-Monitor.ps1` with all UI changes applied.
Do NOT rewrite data logic. Only modify visual/layout code.
The result must feel like a premium Cyber-HUD dark application.
