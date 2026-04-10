# PC Health Monitor

<div align="center">

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6?logo=windows&logoColor=white)
![Status](https://img.shields.io/badge/Status-Work%20In%20Progress-yellow)
![License](https://img.shields.io/badge/License-MIT-green)

**A lightweight, real-time PC monitoring and cleanup tool built entirely in PowerShell.**  
No installation required. No third-party dependencies. Just run and go.

</div>

---

## What It Does

PC Health Monitor gives you a clean, always-on dashboard to keep your Windows machine healthy and performant:

- **Live system stats** — CPU, RAM, and disk usage refresh automatically every few seconds
- **Process inspector** — Top 25 processes ranked by RAM consumption, color-coded by severity
- **Startup manager** — See every program that launches on boot, and disable them directly from the UI
- **Junk file cleaner** — Scan and remove temp files, Windows Update cache, thumbnail cache, browser cache, and more with one click

> **The project is still under development (WIP). Feel free to contribute or give feedback!**

---

## Screenshots

> *(Screenshots coming soon)*

| Dashboard | Startup Manager | Cleanup |
|-----------|-----------------|---------|
| Live CPU / RAM / Disk | Disable startup items | Clean junk with one click |

---

## Features

- **Dark theme** (Catppuccin Mocha color palette)
- **Auto-refresh** every 3 seconds — no need to restart the app
- **Last updated** timestamp visible at all times
- **One-click cleanup** for 6 junk file locations with size breakdown
- **Startup disabler** with registry-level removal and confirmation dialog
- **Zero dependencies** — pure PowerShell + Windows Forms, nothing to install
- **Silent launch** via `.vbs` launcher — no black PowerShell window on startup
- **Desktop shortcut** creator included

---

## Requirements

| Requirement | Version |
|-------------|---------|
| Windows | 10 or 11 |
| PowerShell | 5.1 or higher (built into Windows) |
| Permissions | Standard user (Admin recommended for full cleanup) |

---

## Getting Started

### 1. Clone or Download

```bash
git clone https://github.com/YOUR_USERNAME/PC-Health-Monitor.git
```

Or download the ZIP and extract it to any folder.

### 2. Create the Desktop Shortcut (first time only)

Double-click `Create-Desktop-Shortcut.bat`

This will:
- Create `Launch-Monitor.vbs` (silent launcher — no console window)
- Place a `PC Health Monitor` shortcut on your Desktop

### 3. Launch

Double-click the **PC Health Monitor** shortcut on your Desktop.

> **Note:** For full cleanup functionality (Windows Temp, WU Cache), right-click the shortcut and select **Run as Administrator**.

---

## File Structure

```
PC-Health-Monitor/
│
├── PC-Health-Monitor.ps1          # Main GUI application (Windows Forms + Dark Theme)
├── PC-Cleanup-Rotem.ps1           # Standalone cleanup script with desktop report
├── Create-Desktop-Shortcut.ps1    # Shortcut creation logic
├── Create-Desktop-Shortcut.bat    # Double-click this to set up your shortcut
├── Launch-Monitor.vbs             # Silent launcher (auto-generated, no console window)
└── README.md
```

---

## Dashboard Tabs

### Dashboard
Real-time cards showing:
- **CPU Load** — current processor usage percentage
- **RAM Usage** — used vs total memory in GB
- **Disk C:** — used and free space

Below the cards: a live table of the **Top 25 processes** sorted by RAM, color-coded:
- 🔴 Red — over 500 MB
- 🟡 Yellow — 200–500 MB
- ⬜ Normal — under 200 MB

### Startup Programs
Lists all programs registered to launch on boot (from both User and System registry hives).

- Click **Disable** to remove any User startup item from the registry immediately
- System items require the app to be running as Administrator

### Cleanup
Shows 6 junk file locations with size and file count:

| Location | Path |
|----------|------|
| User Temp Files | `%TEMP%` |
| Windows Temp | `C:\Windows\Temp` |
| Internet Cache | `%LOCALAPPDATA%\Microsoft\Windows\INetCache` |
| Recycle Bin | `C:\$Recycle.Bin` |
| WU Download Cache | `C:\Windows\SoftwareDistribution\Download` |
| Thumbnail Cache | `%LOCALAPPDATA%\Microsoft\Windows\Explorer` |

Use **Clean** per location or **Clean All** to free space in one shot.

---

## Planned Features

- [ ] System Tray icon with background monitoring and alerts
- [ ] CPU / RAM usage history graphs (last 24 hours)
- [ ] Hardware health — temperatures, S.M.A.R.T. disk status, battery health
- [ ] Security tab — Windows Defender status, missing updates, active network connections
- [ ] Duplicate file scanner
- [ ] Unused software detector (not launched in 90+ days)

---

## Contributing

Contributions, issues, and feature requests are welcome!

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -m 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<div align="center">
Made with PowerShell on Windows — by Rotem
</div>
