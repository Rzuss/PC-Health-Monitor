# 🚀 PC Health Monitor

<div align="center">

![PowerShell](https://img.shields.io/badge/PowerShell-%23212E3B.svg?style=for-the-badge&logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)
![Status](https://img.shields.io/badge/Status-Active--WIP-orange?style=for-the-badge)

**A high-performance, native Windows monitoring and cleanup suite built entirely in PowerShell.**

[Features](#-features) • [Why PC Health Monitor?](#-why-this-tool) • [Getting Started](#-getting-started) • [Screenshots](#-preview) • [Contributing](#-contributing)

---
</div>

## 🎯 Why this tool?
In an era of bloated system optimizers filled with telemetry and ads, **PC Health Monitor** offers a "Zero-Footprint" alternative. Built with a **Native-First** philosophy:
* **Zero Dependencies:** No installation, no .NET bloat, no third-party libraries.
* **100% Transparent:** Pure PowerShell source code. What you see is what runs.
* **Privacy-Focused:** No background data collection. Your system stats stay on your machine.

---

## 🖼 Preview
*(Screenshots coming soon - placeholder for your awesome Dark Mode UI)*
<div align="center">
  <img src="https://via.placeholder.com/800x450.png?text=Dashboard+Preview+-+Catppuccin+Theme" alt="PC Health Monitor Dashboard">
</div>

---

## ✨ Features

### 📊 Real-Time Telemetry
* **Live System Cards:** Sub-second refresh for CPU Load, RAM Usage (Used/Total), and Disk health.
* **CIM-Powered:** Uses the modern Common Information Model (CIM) for lower overhead than traditional WMI calls.

### 🔍 Intelligent Process Inspector
* **Dynamic Ranking:** Top 25 processes sorted by memory consumption.
* **Color-Coded Severity:** Instant visual cues for resource-hungry apps:
  - 🔴 **Critical:** > 500 MB
  - 🟡 **Warning:** 200–500 MB
  - ⬜ **Normal:** < 200 MB

### 🛡 Startup & Optimization
* **Boot Management:** Registry-level control over startup items (User & System hives).
* **Safe Cleanup:** One-click removal of deep-system junk:
  - Windows Update Cache (SoftwareDistribution)
  - Thumbnail & Icon Cache
  - User & System Temp files
  - Recycle Bin & Internet Cache

### 🥷 Stealth Integration
* **Silent Launcher:** Run the app without the black PowerShell console window using the included `.vbs` wrapper.
* **Desktop-Ready:** Automated shortcut creator included for easy access.

---

## 🛠 Requirements
| Component | Requirement |
| :--- | :--- |
| **OS** | Windows 10 / 11 |
| **PowerShell** | 5.1 or higher (Native Windows) |
| **Permissions** | Standard User (Admin recommended for deep cleanup) |

---

## 🚀 Getting Started

### 1. Installation
Clone the repository or download the latest release:
```bash
git clone [https://github.com/YOUR_USERNAME/PC-Health-Monitor.git](https://github.com/YOUR_USERNAME/PC-Health-Monitor.git)