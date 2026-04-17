# smart-disk.psm1 — S.M.A.R.T. Disk Health Plugin for PC-Health-Monitor

$Script:DiskGrid   = $null
$Script:DiskColors = $null

function Get-PluginManifest {
    return @{
        Name        = 'SMART Disk Health'
        TabName     = "$([char]::ConvertFromUtf32(0x1F4BE)) Disk Health"
        Version     = '1.0'
        Author      = 'Rotem'
        Description = 'S.M.A.R.T. drive status via WMI'
    }
}

function Initialize-Plugin {
    param(
        [System.Windows.Forms.Panel]$ParentPanel,
        [hashtable]$Colors
    )

    $Script:DiskColors = $Colors

    $Script:DiskGrid          = New-Object System.Windows.Forms.DataGridView
    $Script:DiskGrid.Location = [System.Drawing.Point]::new(15, 15)
    $Script:DiskGrid.Size     = [System.Drawing.Size]::new(
        $ParentPanel.Width - 30,
        $ParentPanel.Height - 30)
    $Script:DiskGrid.Anchor   = (
        [System.Windows.Forms.AnchorStyles]::Top   -bor
        [System.Windows.Forms.AnchorStyles]::Left  -bor
        [System.Windows.Forms.AnchorStyles]::Right -bor
        [System.Windows.Forms.AnchorStyles]::Bottom)

    # Styling — identical to the existing process grid (Style-Grid pattern)
    $Script:DiskGrid.BackgroundColor             = $Colors.BgCard
    $Script:DiskGrid.ForeColor                   = $Colors.Text
    $Script:DiskGrid.GridColor                   = $Colors.Border
    $Script:DiskGrid.BorderStyle                 = [System.Windows.Forms.BorderStyle]::None
    $Script:DiskGrid.RowHeadersVisible           = $false
    $Script:DiskGrid.ReadOnly                    = $true
    $Script:DiskGrid.AllowUserToAddRows          = $false
    $Script:DiskGrid.AllowUserToDeleteRows       = $false
    $Script:DiskGrid.SelectionMode               = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $Script:DiskGrid.EnableHeadersVisualStyles   = $false
    $Script:DiskGrid.Font                        = New-Object System.Drawing.Font('Consolas', 9)
    $Script:DiskGrid.RowTemplate.Height          = 26

    $Script:DiskGrid.ColumnHeadersDefaultCellStyle.BackColor = $Colors.BgCard3
    $Script:DiskGrid.ColumnHeadersDefaultCellStyle.ForeColor = $Colors.Blue
    $Script:DiskGrid.ColumnHeadersDefaultCellStyle.Font      = New-Object System.Drawing.Font('Consolas', 9, [System.Drawing.FontStyle]::Bold)
    $Script:DiskGrid.ColumnHeadersHeightSizeMode             = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::DisableResizing
    $Script:DiskGrid.ColumnHeadersHeight                     = 32

    $Script:DiskGrid.DefaultCellStyle.BackColor          = $Colors.BgCard
    $Script:DiskGrid.DefaultCellStyle.ForeColor          = $Colors.Text
    $Script:DiskGrid.DefaultCellStyle.Font               = New-Object System.Drawing.Font('Consolas', 9)
    $Script:DiskGrid.DefaultCellStyle.SelectionBackColor = $Colors.BgCard2
    $Script:DiskGrid.DefaultCellStyle.SelectionForeColor = $Colors.Blue
    $Script:DiskGrid.DefaultCellStyle.Padding            = New-Object System.Windows.Forms.Padding(4, 0, 4, 0)
    $Script:DiskGrid.AlternatingRowsDefaultCellStyle.BackColor = $Colors.BgCard2

    # Columns: Drive, Model, Size, Status, Temperature
    foreach ($colDef in @(
        @{ Name = 'Drive';       Header = 'Drive';      Fill = 80  },
        @{ Name = 'Model';       Header = 'Model';      Fill = 280 },
        @{ Name = 'Size';        Header = 'Size (GB)';  Fill = 80  },
        @{ Name = 'Status';      Header = 'Status';     Fill = 100 },
        @{ Name = 'Temperature'; Header = 'Temp (C)';   Fill = 80  }
    )) {
        $col            = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $col.Name       = $colDef.Name
        $col.HeaderText = $colDef.Header
        $col.FillWeight = $colDef.Fill
        $col.ReadOnly   = $true
        $col.SortMode   = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
        [void]$Script:DiskGrid.Columns.Add($col)
    }

    $ParentPanel.Controls.Add($Script:DiskGrid)
}

function Refresh-Plugin {
    param(
        [System.Windows.Forms.Panel]$DataPanel
    )

    if ($null -eq $Script:DiskGrid) { return }

    try {
        $drives = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop

        $Script:DiskGrid.SuspendLayout()
        $Script:DiskGrid.Rows.Clear()

        foreach ($drive in $drives) {
            $sizeGB = if ($drive.Size) { [math]::Round($drive.Size / 1GB, 0) } else { 'N/A' }
            $status  = if ($drive.Status) { $drive.Status } else { 'Unknown' }

            $ri  = $Script:DiskGrid.Rows.Add(
                $drive.DeviceID,
                $drive.Model,
                $sizeGB,
                $status,
                'N/A')

            $row = $Script:DiskGrid.Rows[$ri]

            # Color-code the Status cell
            $row.Cells['Status'].Style.ForeColor = switch ($status) {
                'OK'        { $Script:DiskColors.Green  }
                'Pred Fail' { $Script:DiskColors.Red    }
                default     { $Script:DiskColors.Yellow }
            }
        }

        $Script:DiskGrid.ResumeLayout()
    } catch {
        if ($null -ne $Script:DiskGrid) { $Script:DiskGrid.ResumeLayout() }
    }
}

Export-ModuleMember -Function Get-PluginManifest, Initialize-Plugin, Refresh-Plugin
