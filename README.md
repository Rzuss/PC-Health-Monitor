# PC Health Monitor

<div align="center">

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6?logo=windows&logoColor=white)
![Status](https://img.shields.io/badge/Status-Active-green)
![License](https://img.shields.io/badge/License-MIT-green)
![Install](https://img.shields.io/badge/Install-One--Liner-38bdf8?logo=powershell)
![EXE](https://img.shields.io/badge/Download-.exe-a855f7?logo=windows)
![CI](https://img.shields.io/github/actions/workflow/status/Rzuss/PC-Health-Monitor/validate.yml?label=CI&logo=github)

**A lightweight, real-time PC monitoring and cleanup tool built entirely in PowerShell.**  
No installation required. No third-party dependencies. Just run and go.

</div>

---

## Quick Install (One-Liner)

```powershell
irm https://raw.githubusercontent.com/Rzuss/PC-Health-Monitor/main/install.ps1 | iex
```

> Installs silently to `%LOCALAPPDATA%\PC-Health-Monitor` and creates a Desktop shortcut.  
> For full access, right-click the shortcut and select **Run as Administrator**.

---

## Preview

<div align="center">

[![PC Health Monitor App Screenshot](screenshots/PC-Health-Monitor.png)](screenshots/PC-Health-Monitor.png)

*Click image to view full size — Cyber-HUD dark theme with live gauges, process manager, and network tab*

</div>

---

## Why This Tool?

Most PC optimizers are bloated with ads, telemetry, and unnecessary dependencies. PC Health Monitor offers a clean alternative:

- **Zero dependencies** — pure PowerShell + Windows Forms, nothing to install
- **100% transparent** — open source, what you see is what runs
- **Privacy first** — no background data collection, everything stays local
- **Cyber-HUD dark theme** — obsidian background, electric blue + neon purple accents, GDI+ circular gauges
- **System tray integration** — minimize and monitor from taskbar with smart threshold alerts

> The project is actively developed. New features are being added regularly!

---

## Features

### 🖥️ Real-Time Dashboard
- Live CPU, RAM, and Disk usage with **GDI+ circular gauge cards**
- **Hardware Temperature card** — reads CPU & GPU temps via LibreHardwareMonitor WMI (graceful fallback if LHM is not running)
- Auto-refresh every 3 seconds with last-updated timestamp
- Live CPU history SplineArea chart (last 60 seconds)
- **Top 25 processes by RAM** with color-coded severity and **END button** per process
- Runspace-based async refresh — UI never freezes

### ☠️ Process Manager (Kill)
- **END button** on every process row for one-click termination
- Confirmation dialog before execution (default: No — prevents accidents)
- **Protected process blacklist**: `explorer`, `lsass`, `winlogon`, `csrss`, `dwm`, and more — cannot be terminated
- Permission-aware error messages: different guidance for Standard User vs Administrator
- Immediate process grid refresh after successful kill

### 🌐 Network Intelligence Tab
- Live view of all active TCP connections
- Columns: Process, PID, Local Port, Remote IP, State
- **State color coding**: ESTABLISHED (blue), LISTEN (green), CLOSE_WAIT (yellow), TIME_WAIT (dim)
- **Suspicious connection highlighting**: non-RFC1918 remote IPs flagged in orange
- Refreshes every 6 seconds when tab is active — no wasted CPU when hidden

### 🔒 Security Audit Tab
- **Windows Defender** status + last scan date (green/red/yellow indicator)
- **Pending Windows Updates** count with severity color coding
- **Firewall** status per profile: Domain / Private / Public
- **Open Listening Ports** grid with owning process identification
- SCAN NOW button for immediate re-audit
- **EXPORT REPORT** — generates a styled HTML report on the Desktop

### 🚀 Startup Manager
- Lists all programs that launch on boot (User and System registry hives)
- One-click Disable removes startup items directly from the registry
- Instant row removal after successful disable with visual feedback
- Requires Administrator for System-level items (with clear status indicators)

### 🧹 Junk File Cleaner
- Scans 6 locations with size and file count breakdown (Temp, Windows Temp, Internet Cache, Recycle Bin, WU Cache, Thumbnails)
- Clean per location or Clean All in one shot
- Safe cleanup — deletes contents only, never root folders
- Async operation with Marquee progress bar — UI stays responsive
- Real-time status updates and completion notifications

### 🔔 System Tray
- Minimizes to tray instead of closing
- Right-click menu: Open / Exit
- Smart alerts: CPU > 85%, RAM > 85%, Disk > 90%
- Hint popup on first minimize

### 📋 Logging Engine
- Structured log at `%TEMP%\PCHealth-Monitor.log`
- Format: `[YYYY-MM-DD HH:mm:ss] [LEVEL] Message`
- Automatic log rotation at 512 KB
- Session header with OS version, PowerShell version, and privilege level
- All error paths log to file — attach log when opening GitHub Issues

---

## Requirements

| Component   | Requirement                                       |
|-------------|---------------------------------------------------|
| OS          | Windows 10 or 11                                  |
| PowerShell  | 5.1 or higher (built into Windows)                |
| Permissions | Standard user (Admin recommended for full access) |
| Optional    | [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) running for CPU/GPU temps |

---

## Getting Started

**Option A — One-liner (recommended)**

```powershell
irm https://raw.githubusercontent.com/Rzuss/PC-Health-Monitor/main/install.ps1 | iex
```

**Option B — Manual**

```bash
git clone https://github.com/Rzuss/PC-Health-Monitor.git
```

Double-click `Create-Desktop-Shortcut.bat` to create the launcher, then run the **PC Health Monitor** shortcut on your Desktop.

**Option C — Standalone .exe**

```powershell
# Requires PS2EXE module (auto-installed on first run)
.\Build-Exe.ps1
```

Output: `dist\PC-Health-Monitor.exe` — run directly, no PowerShell window required.

---

## Troubleshooting

If you encounter issues, attach the log file when opening a GitHub Issue:

```
%TEMP%\PCHealth-Monitor.log
```

The log includes OS info, PowerShell version, privilege level, and the full error chain.

---

## File Structure

```
PC-Health-Monitor/
|
|-- PC-Health-Monitor.ps1          # Main GUI application (1286 lines, 7 regions)
|-- install.ps1                    # One-liner installer (irm | iex)
|-- Build-Exe.ps1                  # Compile to .exe via PS2EXE
|-- PC-Cleanup-Rotem.ps1           # Standalone cleanup script
|-- Create-Desktop-Shortcut.bat    # Legacy shortcut setup
|-- Launch-Monitor.vbs             # Silent launcher (auto-generated)
|-- dist/                          # Compiled .exe output (git-ignored)
|-- screenshots/                   # App screenshots for README
|-- .github/
|   |-- workflows/
|       |-- validate.yml           # PSScriptAnalyzer CI on push & PR
|-- PC-Health-Monitor-Roadmap.docx # Development roadmap & sprint plans
|-- README.md
|-- CLAUDE.md                      # Project architecture & AI guidelines
|-- .gitignore
```

---

## Technical Highlights

**Architecture & Performance**
- Runspace-based async execution prevents UI freezing during heavy operations
- CIM queries optimized with property filters for minimal overhead
- Tab-aware refresh: Network and Security tabs only refresh when visible
- 3-second refresh cycle with separate counters for expensive operations (temps: 6s, security: 30s)

**Code Quality**
- **7 `#region` blocks** for logical separation: Logging Engine → Styles → Helpers → Core Logic → UI Init → Events → Execution
- Centralized `Write-Log` function with rotation, session headers, and ExceptionRecord capture
- Helper functions for consistent UI styling (`New-Lbl`, `New-Btn`, `New-Pnl`, `Style-Grid`, etc.)
- GDI+ custom painting: `Draw-CircleGauge`, `Draw-GlowBorder`, `Temp-Color`
- 100% ASCII-safe PowerShell — no em-dashes, no Unicode encoding issues

**Safety**
- All destructive operations (cleanup, process kill, disable startup) require user confirmation
- Protected process blacklist prevents accidental OS crash
- Non-destructive defaults — never deletes folder roots, only contents
- Admin detection prevents accidental elevation requirement errors
- Registry operations use native `reg.exe` for reliability

**CI/CD**
- GitHub Actions workflow validates every push and PR with `PSScriptAnalyzer`
- Fails on Error-level findings — keeps the codebase clean

---

## Planned Features

- [ ] Network Intelligence Tab enhancements — GeoIP lookup, C2 detection signatures
- [ ] Predictive Maintenance — time-series anomaly detection for disk fill rates
- [ ] Smart Startup Classifier — AI-powered risk assessment with community database
- [ ] S.M.A.R.T. Disk Health Monitor — drive health status and failure prediction
- [ ] Fleet Management — cloud agent for monitoring multiple machines
- [ ] Duplicate File Scanner — intelligent duplicate detection across drives

---

## Contributing

Contributions, issues, and feature requests are welcome!

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit your changes following [Conventional Commits](https://www.conventionalcommits.org/)
4. Push to the branch: `git push origin feature/my-feature`
5. Open a Pull Request

---

## License

This project is licensed under the MIT License. See LICENSE file for details.

---

<div align="center">
Made with PowerShell on Windows — by Rotem

⭐ Star the project if you find it useful!
</div>
