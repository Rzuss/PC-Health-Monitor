# PC Health Monitor

<div align="center">

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6?logo=windows&logoColor=white)
![Status](https://img.shields.io/badge/Status-Active-green)
![License](https://img.shields.io/badge/License-MIT-green)
![CI](https://img.shields.io/github/actions/workflow/status/Rzuss/PC-Health-Monitor/validate.yml?label=CI&logo=github)
![Plugins](https://img.shields.io/badge/Plugins-Supported-a855f7?logo=powershell)

**A lightweight, real-time PC health and optimization tool built entirely in PowerShell 5.1 + WinForms.**  
No bloat. No telemetry. No third-party dependencies. Plugin-extensible. Just run and go.

</div>

---

## Quick Install

**Option A — One-liner**

```powershell
irm https://raw.githubusercontent.com/Rzuss/PC-Health-Monitor/main/install.ps1 | iex
```

> Installs to `%LOCALAPPDATA%\PC-Health-Monitor` and creates a Desktop shortcut.

**Option B — Windows Installer (.exe)**

Download `PC-Health-Monitor-Setup.exe` from the [Releases](https://github.com/Rzuss/PC-Health-Monitor/releases) page.  
No admin required. Includes Start Menu shortcut and Uninstaller.

**Option C — Manual**

```powershell
git clone https://github.com/Rzuss/PC-Health-Monitor.git
cd PC-Health-Monitor
powershell -ExecutionPolicy Bypass -File PC-Health-Monitor.ps1
```

---

## Preview

<div align="center">

[![PC Health Monitor Screenshot](screenshots/PC-Health-Monitor.png)](screenshots/PC-Health-Monitor.png)

*Cyber-HUD dark theme — live gauges, process manager, junk cleaner, and disk analyzer*

</div>

---

## Features

### 🖥️ Real-Time Dashboard
- Live **CPU, RAM, and Disk** usage with GDI+ circular gauge cards
- Auto-refresh every 3 seconds with last-updated timestamp
- Live CPU history chart (last 60 seconds)
- All data collected in a **persistent background runspace** — UI never freezes

### 📊 Predictive Health Score
- Composite **Health Score (0–100)** updated daily via Python analytics engine
- Predictive alerts: *"Disk C: fills in ~14 days at current rate"*
- RAM trend analysis — detects slow memory leaks over time
- Powered by `health_analyzer.py` running as a Windows Scheduled Task

### 🧠 Behavioral Baseline Engine
- Builds a **personal behavioral profile** of every process over 30 days
- Detects anomalies using **Z-score statistics** — flags processes deviating from their own normal baseline
- Anomaly column in process grid with detail popup: current vs. baseline, Z-score, suggested causes
- Powered by `baseline_engine.py` running as a Windows Scheduled Task

### ☠️ Process Manager
- **Top 25 processes by RAM** with color-coded severity
- **END button** per row for one-click termination with confirmation dialog
- **Protected blacklist** — `explorer`, `lsass`, `winlogon`, `csrss`, `dwm` cannot be terminated
- Permission-aware error messages for Standard User vs. Administrator

### 🚀 Startup Manager
- Lists all programs that launch on boot (User and System registry hives)
- One-click **Disable** removes items from the registry instantly

### 🧹 Junk File Cleaner
- Scans 6 locations: Temp, Windows Temp, Internet Cache, Recycle Bin, WU Cache, Thumbnails
- Clean per-location or **Clean All** in one shot
- Async with Marquee progress bar — UI stays responsive throughout

### 📁 Top 10 Largest Folders
- On-demand scan of drive C: for the **10 biggest folders by size**
- Folder icon button on each row — click to open directly in Explorer
- Progress bar showing relative size vs. the largest folder

### 🔌 Plugin Architecture
- Drop any `.psm1` file into `/plugins` — a new tab appears automatically
- Plugins receive the full color palette and a dedicated UI panel
- See `plugins/PLUGIN-API.md` for the full development contract

### 🔔 System Tray Integration
- Minimizes to tray instead of closing
- Smart alerts: CPU > 85%, RAM > 85%, Disk > 90%

### 📋 Logging Engine
- Structured log at `%TEMP%\PCHealth-Monitor.log` with automatic rotation at 512 KB
- Telemetry CSV at `%TEMP%\PCHealth-Telemetry.csv` — feeds the analytics engine

---

## Requirements

| Component  | Requirement                                                          |
|------------|----------------------------------------------------------------------|
| OS         | Windows 10 or 11                                                     |
| PowerShell | 5.1+ (built into Windows)                                            |
| Privileges | Standard user (Administrator recommended for full cleanup access)    |
| Python     | 3.8+ with `pandas`, `numpy` — optional, for analytics engine only   |

---

## Enable Analytics Engine (Optional)

```powershell
pip install pandas numpy
.\Register-HealthTask.ps1
```

Registers two daily Scheduled Tasks: health scoring at 03:00 AM and baseline profiling at 03:05 AM.

---

## Plugin Development

Drop a `.psm1` into the `plugins/` folder. Auto-discovered on next launch.

Every plugin exports three functions:

```powershell
function Get-PluginManifest { @{ Name='My Plugin'; TabName='My Tab'; Version='1.0'; Author='You' } }
function Initialize-Plugin  { param([System.Windows.Forms.Panel]$ParentPanel, [hashtable]$Colors) }
function Refresh-Plugin     { param([System.Windows.Forms.Panel]$DataPanel) }
```

See `plugins/PLUGIN-API.md` for the full contract.

---

## File Structure

```
PC-Health-Monitor/
├── PC-Health-Monitor.ps1        # Main GUI application (PowerShell 5.1 + WinForms)
├── install.ps1                  # One-liner installer
├── installer.iss                # Inno Setup 6 script — builds Setup.exe
├── PC-Cleanup-Rotem.ps1         # Standalone cleanup script
├── health_analyzer.py           # Predictive health score engine
├── baseline_engine.py           # Behavioral anomaly detection engine
├── Register-HealthTask.ps1      # Register analytics Scheduled Tasks
├── Create-Desktop-Shortcut.bat  # Manual shortcut setup
├── Launch-Monitor.vbs           # Silent launcher (used by installer)
├── plugins/
│   └── PLUGIN-API.md            # Plugin development contract
├── screenshots/
│   └── PC-Health-Monitor.png
├── .github/
│   └── workflows/
│       ├── validate.yml         # PSScriptAnalyzer CI on every push
│       └── build-installer.yml  # Builds Setup.exe on version tag push
├── README.md
├── CLAUDE.md
└── .gitignore
```

---

## CI/CD

| Workflow             | Trigger            | Action                                      |
|----------------------|--------------------|---------------------------------------------|
| `validate.yml`       | Push / PR          | PSScriptAnalyzer — fails on Error findings  |
| `build-installer.yml`| `git tag v*`       | Builds `PC-Health-Monitor-X.X-Setup.exe` and publishes to GitHub Releases |

---

## Troubleshooting

Attach the log file when opening a GitHub Issue:

```
%TEMP%\PCHealth-Monitor.log
```

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Follow [Conventional Commits](https://www.conventionalcommits.org/)
4. Open a Pull Request

---

## License

MIT License — see LICENSE file for details.

---

<div align="center">
Built with PowerShell on Windows — by Rotem

⭐ Star the project if you find it useful!
</div>
