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

*Deep Space dark theme — live gauges, health score, VIP mode, boost optimizer, S.M.A.R.T disk health, driver audit, and more*

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
- **(i) Info button** opens a styled breakdown popup — factor · current value · points lost · tip
- Left accent bar changes color dynamically by score tier

### ⚡ VIP Mode — Process Priority Elevation
- Elevates a selected app to **High CPU priority** with one click
- Combo box shows **only apps with open windows** — services and background processes filtered automatically
- Auto-restores original priority when user clicks CLEAR VIP, app closes, or monitor exits
- Never uses `RealTime` priority — OS stability always preserved

### ☠️ Process Manager
- **Top 25 processes by RAM** — color-coded severity rows
- **Status column** — anomaly detection per process (Z-score based)
- **END button** per row — one-click termination with confirmation dialog
- Protected blacklist: `explorer`, `lsass`, `winlogon`, `csrss`, `dwm` cannot be terminated

### 🚀 Startup Manager
- Lists all programs that launch on boot (User + System registry hives)
- One-click **Disable** removes the registry entry instantly
- Shows app count with recommendation if over threshold

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

- **📁 Open button** on every row — opens folder directly in Windows Explorer
- **Thumbnail Cache** uses a safe Stop-Explorer → delete → Restart-Explorer cycle
- Two-pass deletion: locked files never block others

### 💾 Storage Analyzer
- Scans **C: drive** and lists the **Top 10 largest folders** by size
- **📁 Open button** per row — jump directly to the folder in Explorer
- Path, size, and file count displayed per entry

### ⚡ Boost Mode
- One-click **performance optimizer** for gaming, rendering, or heavy multitasking
- **Lowers CPU priority** of known background processes (Teams, Discord, Spotify, OneDrive, Chrome, and more) — they keep running, just yield CPU time
- **Switches power plan** to High Performance automatically
- **Flushes Standby RAM** via `NtSetSystemInformation` — releases memory held by idle processes
- **Full restore on deactivate** — priorities and power plan revert to original state
- Live action log shows every change made in real time

### 🔬 Disk Health — S.M.A.R.T.
- Reads **S.M.A.R.T. data** from all physical drives via `Get-PhysicalDisk` + `Get-StorageReliabilityCounter`
- **No third-party tools required** — uses the native Windows Storage API
- Per-disk card shows: Temperature · Read Errors · Write Errors · Wear Level · Power-On Hours
- Color-coded alerts: red for critical (errors > 0, temp > 55°C), yellow for warnings
- Status badge: **Healthy / Warning / Critical**

### 🔧 Tools Tab

#### Driver Audit
- Inventories all installed drivers via `Win32_PnPSignedDriver`
- **Age-flags each driver:**
  - 🔴 **Outdated** — older than 2 years (update recommended)
  - 🟡 **Aging** — 1–2 years old (monitor for updates)
- Shows only drivers that need attention — OK drivers are filtered out
- Summary: *"X driver(s) need attention out of Y scanned"*

#### Auto-Schedule Cleanup
- Creates a **Windows Scheduled Task** for automatic junk cleanup
- Choose **Daily or Weekly** frequency + run time (hour picker)
- Uses `Register-ScheduledTask` / `Unregister-ScheduledTask` — no third-party scheduler
- Runs silently in background; results logged to app log file

---

## (i) Information System

Every feature has a dedicated **information button** — a consistent 28×28 rounded blue `i` button placed near its section header. Clicking it opens a styled dark-theme dialog with:

- Bold colored title + section divider
- Professional, concise feature explanation
- What it does, what it does NOT do, and usage tips
- "Got it" close button

Features with (i) buttons: **Health Score · VIP Mode · Startup Apps · Junk Cleaner · Storage Analyzer · Boost Mode · Disk Health · Driver Audit · Auto-Schedule**

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    STA UI Thread                     │
│   WinForms · TabControl · GDI+ Paint · Event Handlers│
└───────────────────────┬─────────────────────────────┘
                        │  $script:DataCache (synchronized hashtable)
┌───────────────────────▼─────────────────────────────┐
│               Background Runspace (DataEngine)        │
│   CPU · RAM · Disk · Process list · Security Audit   │
│   Get-CimInstance · Get-Process · Get-Counter        │
└─────────────────────────────────────────────────────┘

Background operations:
  · Storage Scan      · Driver Audit      · S.M.A.R.T. Read
  · Auto-Update Check · Boost Mode toggle · Task Scheduler ops
```

All heavy operations run in isolated Runspaces — the GUI never freezes.

---

## File Structure

```
PC-Health-Monitor/
├── PC-Health-Monitor.ps1        # Main application — all UI + logic (~4000 lines)
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
- **Boost Mode tab** — one-click performance optimizer; lowers background process priorities, switches to High Performance power plan, flushes Standby RAM; full auto-restore on deactivate
- **Disk Health tab** — per-drive S.M.A.R.T. cards (Temperature, Read/Write Errors, Wear Level, Power-On Hours) via native Windows Storage API
- **Tools tab** — Driver Audit with age-flagging (Outdated/Aging) + Auto-Schedule Cleanup via Windows Task Scheduler
- **Unified (i) information buttons** — consistent 28×28 dark-theme dialog on every feature; `New-InfoBtn()` helper for standardized style across all 9 features
- **Driver Audit filtering** — shows only flagged drivers (Outdated/Aging); OK drivers hidden; summary label with count
- **VIP status visibility fix** — "No VIP active" label upgraded from near-invisible Dim to readable SubText color
- **Show-ScoreInfo color fix** — eliminated WinForms event scope issue causing null color errors on popup open

### Previous
- **VIP Mode** — elevate any user-facing app to High CPU priority; auto-restore on exit
- **Health Score redesign** — X/100 format with per-factor breakdown popup
- **📁 Folder buttons** in Junk Cleaner and Storage tabs
- **Deep Space visual overhaul** — new color palette, Segoe UI Variable typography, card depth system, GDI+ gauge redesign
- **Auto-Update banner** — GitHub API check on startup; dismissible
- **First-Run Welcome Screen** — one-time onboarding
- **DataEngine background Runspace** — decoupled data collection from UI thread
- **Security Audit tab** — async scan with SCAN NOW polling
- **Startup Manager** with Disable button
- **System tray** with smart threshold alerts
- **Process Manager** with anomaly status column and END button

---

## Troubleshooting

Attach the log file when opening a GitHub Issue:
```
%TEMP%\PCHealth-Monitor.log
```

| Issue | Solution |
|---|---|
| "Running without Administrator rights" | Right-click the script → Run as Administrator |
| Thumbnail Cache shows 0 MB after clean | Fixed — cleaner stops/restarts Explorer to release locks |
| VIP Mode — "Failed — try as Administrator" | Process priority changes require sufficient privileges |
| Disk Health shows "—" for some values | Drive controller does not expose those S.M.A.R.T. metrics via Windows API |
| Boost Mode — power plan unchanged | No "High Performance" plan found; create one via Windows Power Options |

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
