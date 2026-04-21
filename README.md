# PC Health Monitor

<div align="center">

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6?logo=windows&logoColor=white)
![Status](https://img.shields.io/badge/Status-Active-brightgreen)
![License](https://img.shields.io/badge/License-MIT-green)
![CI](https://img.shields.io/github/actions/workflow/status/Rzuss/PC-Health-Monitor/validate.yml?label=CI&logo=github)

**A lightweight, real-time PC health and optimization tool built entirely in PowerShell 5.1 + WinForms.**  
No bloat. No telemetry. No third-party dependencies. Just run and go.

</div>

---

## Quick Start

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

*Cyber-HUD dark theme — live gauges, health score, VIP mode, junk cleaner, and disk analyzer*

</div>

---

## Features

### 🖥️ Real-Time Dashboard
- Live **CPU, RAM, and Disk** usage with GDI+ circular gauge cards
- Auto-refresh every 3 seconds — all data from a **persistent background Runspace** (UI never freezes)
- Live CPU history chart (last 60 seconds, SplineArea)
- Last-updated timestamp and blinking status dot in the status bar

### 🏆 Health Score (X / 100)
- Composite score updated every 15 seconds across 5 factors:
  - CPU Load (max −25 pts), RAM Usage (−25), Disk C: (−20), Startup Apps (−15), Junk Files (−15)
- Color-coded tier: **Excellent / Good / Fair / Needs Cleanup / Critical**
- Trend arrow (↑ ↓) shows change since last reading
- **(i) Info button** opens a breakdown popup table — factor · current value · points lost · tip
- Left accent bar changes color dynamically by score tier

### ⚡ VIP Mode — Process Priority Elevation
- Elevates a selected app to **High CPU priority** with one click
- Combo box shows **only apps with open windows** — services and background processes are filtered out automatically
- Auto-restores original priority when:
  - The user clicks **CLEAR VIP**
  - The selected app closes (detected every tick)
  - PC Health Monitor exits
- Never uses `RealTime` priority — OS stability is always preserved

### ☠️ Process Manager
- **Top 25 processes by RAM** — color-coded severity
- **Status column** — anomaly detection per process (Z-score)
- **END button** per row — one-click termination with confirmation
- Protected blacklist: `explorer`, `lsass`, `winlogon`, `csrss`, `dwm` cannot be terminated

### 🚀 Startup Manager
- Lists all programs that launch on boot (User + System registry hives)
- One-click **Disable** removes the registry entry instantly

### 🧹 Junk File Cleaner
Scans 6 locations and reports recoverable space:

| Location | Path |
|---|---|
| User Temp Files | `%LOCALAPPDATA%\Temp` |
| Windows Temp | `C:\Windows\Temp` |
| Internet Cache | `%LOCALAPPDATA%\Microsoft\Windows\INetCache` |
| Recycle Bin | `C:\$Recycle.Bin` |
| WU Download Cache | `C:\Windows\SoftwareDistribution\Download` |
| Thumbnail Cache | `%LOCALAPPDATA%\Microsoft\Windows\Explorer` |

- **📁 Open button** on every row — opens that folder directly in Windows Explorer
- **Thumbnail Cache** uses a safe Stop-Explorer → delete → Restart-Explorer cycle to fully unlock cache files
- Two-pass deletion: locked files never block others; real remaining size shown after rescan
- Async Runspace — UI stays responsive throughout; progress shown in log panel

### 📁 Storage Analyzer
- On-demand scan of drive C: for the **10 largest folders**
- **📁 Open button** on every row — opens folder in Explorer
- Color-coded progress bar relative to the largest folder

### 🔒 Security Audit
- Windows Update status, Firewall, UAC, and open ports — all in one panel
- Runs in a background Runspace (no UI freeze on SCAN)

### 🔔 Smart Alerts + System Tray
- Minimizes to tray instead of closing — balloon tip on first minimize
- CPU > 85% sustained 12 s → balloon tip (5-minute cooldown)
- RAM > 85% → balloon tip (5-minute cooldown)
- Disk C: > 90% → balloon tip (10-minute cooldown)

### 🆕 First-Run Welcome Screen
- Shown once on first launch (registry-gated flag)
- Highlights all four main features with icons before entering the dashboard

### 🔄 Auto-Update Check
- Background Runspace queries GitHub Releases API on startup
- If a newer version exists, a dismissible green banner appears in the title bar
- Click the banner to open the Releases page; "Dismiss" hides it for the session

### 📋 Logging Engine
- Structured log at `%TEMP%\PCHealth-Monitor.log` — auto-rotated at 512 KB
- All errors wrapped in `Try-Catch` with full exception detail

---

## Requirements

| Component | Requirement |
|---|---|
| OS | Windows 10 or 11 |
| PowerShell | 5.1+ (built into Windows) |
| Privileges | Standard user · Administrator recommended for full cleanup |
| .NET | 4.x (built into Windows 10/11) |

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    UI Thread (STA)                       │
│  WinForms Timer (3 s) → Do-Refresh → reads DataCache    │
│  Controls: Dashboard · Startup · Junk · Storage         │
└────────────────────┬────────────────────────────────────┘
                     │ synchronized hashtable
┌────────────────────▼────────────────────────────────────┐
│               DataEngine Runspace (MTA)                  │
│  Get-CimInstance · performance data every 3 s           │
│  Writes CPU, RAM, Disk, Processes → DataCache           │
└─────────────────────────────────────────────────────────┘
       Additional per-action Runspaces (STA):
         · Junk Cleaner      · Security Audit
         · Storage Scan      · Auto-Update Check
```

All heavy operations run in isolated Runspaces — the GUI never freezes.

---

## File Structure

```
PC-Health-Monitor/
├── PC-Health-Monitor.ps1        # Main application — all UI + logic
├── install.ps1                  # One-liner web installer
├── installer.iss                # Inno Setup 6 script (builds Setup.exe)
├── Launch-Monitor.vbs           # Silent launcher (used by installer)
├── Create-Desktop-Shortcut.bat  # Manual shortcut helper
├── screenshots/
│   └── PC-Health-Monitor.png
├── .github/
│   └── workflows/
│       ├── validate.yml         # PSScriptAnalyzer CI on every push
│       └── build-installer.yml  # Builds Setup.exe on version tag
├── README.md
├── CLAUDE.md                    # AI coworker project instructions
└── .gitignore
```

---

## CI/CD

| Workflow | Trigger | Action |
|---|---|---|
| `validate.yml` | Push / PR | PSScriptAnalyzer — fails on Error-level findings |
| `build-installer.yml` | `git tag v*` | Builds `PC-Health-Monitor-X.X-Setup.exe` → GitHub Release |

---

## Changelog

### Unreleased
- **VIP Mode** — elevate any user-facing app to High CPU priority; auto-restore on exit
- **Health Score redesign** — X/100 format with per-factor breakdown popup (i button)
- **📁 Folder buttons** in Junk Cleaner and Storage tabs — open location in Explorer
- **Thumbnail Cache fix** — Stop-Explorer cycle ensures files are truly deleted
- **Auto-Update banner** — GitHub API check on startup; dismissible green banner
- **First-Run Welcome Screen** — one-time onboarding shown on first launch
- **pollTimer scope fix** — `$script:pollTimer` prevents null-ref in Add_Tick closures
- **VIP status label** — layout rebalanced so text fits within the 1020px card

### Previous
- DataEngine background Runspace — decoupled data collection from UI thread
- Security Audit tab — async scan with SCAN NOW polling
- Junk Cleaner two-pass deletion — locked files never block others
- Status bar — version, timestamp, admin indicator
- Startup Manager with Disable button
- System tray with smart threshold alerts
- Process Manager with anomaly status column and END button

---

## Troubleshooting

Attach the log file when opening a GitHub Issue:
```
%TEMP%\PCHealth-Monitor.log
```

Common questions:

**"Running without Administrator rights"** — Some cleanup targets (WU Cache, Recycle Bin system hive) require elevation. Right-click the script → Run as Administrator.

**Thumbnail Cache shows 0 MB after cleaning** — Fixed in latest version. The cleaner now stops and restarts Windows Explorer to release file locks before deletion.

**VIP Mode — "Failed — try running as Administrator"** — Process priority changes above Normal require the calling process to have sufficient privileges over the target process.

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

Built with PowerShell + WinForms on Windows — by Rotem

⭐ Star the project if you find it useful!

</div>
