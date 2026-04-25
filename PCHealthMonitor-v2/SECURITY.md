# Security Policy

## What this software does and does NOT do

PC Health Monitor is a **fully offline, local-only** application.

| Action | Status |
|--------|--------|
| Reads local system info (CPU, RAM, disk) | ✅ Yes — by design |
| Writes to local temp/junk folders (cleanup) | ✅ Yes — by design, user-initiated only |
| Modifies startup registry entries | ✅ Yes — only when user explicitly clicks Remove |
| Elevates process priority (Boost Mode) | ✅ Yes — only for selected process, user-initiated |
| Sends data to any external server | ❌ Never |
| Collects telemetry or analytics | ❌ Never |
| Requires internet connection | ❌ Never |
| Stores passwords, tokens, or credentials | ❌ Never |

## Permissions used

The application runs **without Administrator privileges**. It uses:

- `System.Diagnostics.Process` — read running processes
- `Microsoft.Win32.Registry` — read CPU/OS info (HKLM read-only), write startup entries (HKCU only)
- `System.IO.DriveInfo` — read disk usage
- WMI (`Win32_Processor`, `Win32_PhysicalMemory`, `Win32_VideoController`) — read hardware info, no write
- LibreHardwareMonitor — read CPU temperature (may require admin for some sensors)
- `DllImport("user32.dll")` — window resize hit-testing only (`WM_NCHITTEST`)

## No secrets in source code

This repository is scanned on every commit to ensure it contains no:
- API keys or tokens
- Passwords or credentials
- Personal file paths
- IP addresses or hardcoded hostnames

## Verifying a binary

If you downloaded a pre-built `.exe` and want to verify it matches this source:

```powershell
# Get SHA-256 hash of the exe
Get-FileHash "PCHealthMonitor.exe" -Algorithm SHA256
```

Compare with the hash published in the [Releases](https://github.com/Rzuss/PC-Health-Monitor/releases) page.

## Reporting a vulnerability

If you discover a security issue, please open a **private** GitHub issue or contact
the author directly. Do not post vulnerability details publicly before they are addressed.

## Trusted distribution

The only official distribution channels are:

- Source code: https://github.com/Rzuss/PC-Health-Monitor
- Releases: https://github.com/Rzuss/PC-Health-Monitor/releases

Any other source distributing binaries named "PCHealthMonitor" should be treated
with caution and verified against the official SHA-256 hashes above.
