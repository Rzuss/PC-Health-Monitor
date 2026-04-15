# PC Health Monitor

<div align="center">

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6?logo=windows&logoColor=white)
![Status](https://img.shields.io/badge/Status-Active-green)
![License](https://img.shields.io/badge/License-MIT-green)

**A lightweight, real-time PC monitoring and cleanup tool built entirely in PowerShell.**
No installation required. No third-party dependencies. Just run and go.

</div>

---

## Preview

<div align="center">

[![PC Health Monitor App Screenshot](screenshots/PC-Health-Monitor.png)](screenshots/PC-Health-Monitor.png)

*Click image to view full size - Shows Dashboard, Cleanup, and Startup Optimizer tabs*

</div>

---

## Why This Tool?

Most PC optimizers are bloated with ads, telemetry, and unnecessary dependencies. PC Health Monitor offers a clean alternative:

- **Zero dependencies** — pure PowerShell + Windows Forms, nothing to install
- **100% transparent** — open source, what you see is what runs
- **Privacy first** — no background data collection, everything stays local
- **Dark theme UI** — modern Catppuccin Mocha color palette with real-time updates
- **System tray integration** — minimize and monitor from taskbar with smart alerts

> The project is actively developed. New features are being added regularly!

---

## Features

**Real-Time Dashboard**
- Live CPU, RAM, and Disk usage cards with color-coded progress bars
- Auto-refresh every 3 seconds with last-updated timestamp
- Live CPU history chart (last 60 seconds of data)
- Top 25 processes ranked by RAM, color-coded by severity
- Responsive UI using Runspace-based background operations

**Startup Manager**
- Lists all programs that launch on boot (User and System registry hives)
- One-click Disable button removes startup items directly from the registry
- Instant row removal after successful disable with visual feedback
- Requires Administrator for System-level items (with clear status indicators)

**Junk File Cleaner**
- Scans 6 locations with size and file count breakdown (Temp, Windows Temp, Internet Cache, Recycle Bin, WU Cache, Thumbnails)
- Clean per location or Clean All in one shot
- Safe cleanup — deletes contents only, never root folders
- Async operation with Marquee progress bar — UI stays responsive during cleanup
- Real-time status updates and completion notifications

**System Tray**
- Minimizes to tray instead of closing
- Right-click menu: Open / Exit
- Smart alerts when CPU exceeds 85%, RAM exceeds 85%, or Disk exceeds 90%
- Hint popup on first minimize explaining tray functionality

**Security & Access Control**
- Detects if running without Administrator rights
- Disables buttons that require elevation with a clear warning banner
- Admin-required cleanup locations are protected
- Tooltips explain why certain features are unavailable

---

## Requirements

| Component | Requirement |
|-----------|-------------|
| OS | Windows 10 or 11 |
| PowerShell | 5.1 or higher (built into Windows) |
| Permissions | Standard user (Admin recommended for full cleanup) |

---

## Getting Started

**1. Clone or download**

```bash
git clone https://github.com/Rzuss/PC-Health-Monitor.git
```

**2. Create the Desktop shortcut (first time only)**

Double-click `Create-Desktop-Shortcut.bat`

This creates a silent launcher and places a shortcut on your Desktop.

**3. Launch**

Double-click the **PC Health Monitor** shortcut on your Desktop.

> For full cleanup access, right-click the shortcut and select **Run as Administrator**.

---

## File Structure

```
PC-Health-Monitor/
|
|-- PC-Health-Monitor.ps1          # Main GUI application (808 lines)
|-- PC-Cleanup-Rotem.ps1           # Standalone cleanup script
|-- Create-Desktop-Shortcut.ps1    # Shortcut creation logic
|-- Create-Desktop-Shortcut.bat    # Run this once to set up
|-- Launch-Monitor.vbs             # Silent launcher (auto-generated)
|-- screenshots/                   # App screenshots for README
|-- README.md
|-- CLAUDE.md                       # Project architecture & guidelines
|-- .gitignore
```

---

## Technical Highlights

**Architecture & Performance**
- Runspace-based async execution prevents UI freezing during heavy operations
- CIM queries optimized with property filters for minimal overhead
- Delta refresh pattern — only updates changed data in DataGridView
- 3-second refresh cycle with intelligent throttling for expensive operations

**Code Quality**
- 100% ASCII-safe PowerShell (no em-dashes, no Unicode issues)
- Comprehensive error handling with Try-Catch blocks
- Helper functions for consistent UI styling (New-Lbl, New-Btn, New-Pnl, etc.)
- Modular design — easy to extend with new tabs and features

**Safety**
- All destructive operations (cleanup, disable startup) require user confirmation
- Non-destructive by default — never deletes folder roots, only contents
- Admin detection prevents accidental elevation requirement errors
- Registry operations use native `reg.exe` for reliability

---

## Planned Features

- [ ] Network Intelligence Tab — active connections with GeoIP, process correlation, C2 detection
- [ ] Predictive Maintenance — time-series anomaly detection for disk fill rates
- [ ] Smart Startup Classifier — AI-powered risk assessment with community database
- [ ] Hardware Health Monitor — CPU temperature, S.M.A.R.T. disk status
- [ ] Security Tab — Defender status, missing Windows updates, antivirus scan
- [ ] Fleet Management — cloud agent for monitoring multiple machines
- [ ] Duplicate File Scanner — intelligent duplicate detection across drives

---

## Contributing

Contributions, issues, and feature requests are welcome!

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit your changes: `git commit -m "Add my feature"`
4. Push to the branch: `git push origin feature/my-feature`
5. Open a Pull Request

---

## License

This project is licensed under the MIT License. See LICENSE file for details.

---

<div align="center">
Made with PowerShell on Windows — by Rotem

Star the project if you find it useful!
</div>
