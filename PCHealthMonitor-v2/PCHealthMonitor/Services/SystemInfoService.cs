using Microsoft.Win32;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Management;
using System.Threading.Tasks;

namespace PCHealthMonitor.Services;

public sealed class SystemInfoService
{
    // ── Static snapshot (loaded once on first call) ───────────────────────
    public Task<SystemInfoSnapshot> GetSnapshotAsync() =>
        Task.Run(BuildSnapshot);

    private static SystemInfoSnapshot BuildSnapshot()
    {
        var snap = new SystemInfoSnapshot();

        // ── CPU ───────────────────────────────────────────────────────────
        snap.CpuName    = GetRegistryString(
            @"HARDWARE\DESCRIPTION\System\CentralProcessor\0",
            "ProcessorNameString",
            "Unknown CPU")?.Trim() ?? "Unknown CPU";

        snap.CpuCores   = GetPhysicalCoreCount();
        snap.CpuLogical = Environment.ProcessorCount;

        // ── RAM ───────────────────────────────────────────────────────────
        snap.RamSpeedMhz = GetRamSpeedMhz();

        // ── GPU ───────────────────────────────────────────────────────────
        (snap.GpuName, snap.GpuVramGb) = GetGpuInfo();

        // ── Storage drives ────────────────────────────────────────────────
        snap.Drives = GetDrives();

        // ── OS ────────────────────────────────────────────────────────────
        snap.OsName    = GetRegistryString(
            @"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
            "ProductName",
            "Windows") ?? "Windows";
        snap.OsBuild   = GetRegistryString(
            @"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
            "CurrentBuildNumber",
            "") ?? "";
        snap.Uptime        = FormatUptime(TimeSpan.FromMilliseconds(Environment.TickCount64));
        snap.MachineName   = Environment.MachineName;
        snap.UserName      = Environment.UserName;
        snap.Architecture  = Environment.Is64BitOperatingSystem ? "64-bit" : "32-bit";

        return snap;
    }

    // ── Helpers ───────────────────────────────────────────────────────────
    private static string? GetRegistryString(string keyPath, string valueName, string? fallback)
    {
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(keyPath);
            return key?.GetValue(valueName)?.ToString() ?? fallback;
        }
        catch { return fallback; }
    }

    private static int GetPhysicalCoreCount()
    {
        try
        {
            int cores = 0;
            using var searcher = new ManagementObjectSearcher(
                "SELECT NumberOfCores FROM Win32_Processor");
            searcher.Options.Timeout = TimeSpan.FromSeconds(4);
            foreach (ManagementObject obj in searcher.Get())
            {
                using (obj)
                    cores += Convert.ToInt32(obj["NumberOfCores"]);
            }
            return cores > 0 ? cores : Environment.ProcessorCount;
        }
        catch { return Environment.ProcessorCount; }
    }

    private static int GetRamSpeedMhz()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(
                "SELECT Speed FROM Win32_PhysicalMemory");
            searcher.Options.Timeout = TimeSpan.FromSeconds(4);
            int speed = 0;
            foreach (ManagementObject obj in searcher.Get())
            {
                using (obj)
                {
                    var s = Convert.ToInt32(obj["Speed"]);
                    if (s > speed) speed = s;
                }
            }
            return speed;
        }
        catch { return 0; }
    }

    private static (string name, double vramGb) GetGpuInfo()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(
                "SELECT Name, AdapterRAM FROM Win32_VideoController");
            searcher.Options.Timeout = TimeSpan.FromSeconds(5);
            foreach (ManagementObject obj in searcher.Get())
            {
                using (obj)
                {
                    var name  = obj["Name"]?.ToString() ?? "Unknown";
                    var vram  = Convert.ToInt64(obj["AdapterRAM"] ?? 0L);
                    return (name, vram / 1_073_741_824.0);
                }
            }
        }
        catch { }
        return ("Unknown", 0);
    }

    private static List<DriveEntry> GetDrives()
    {
        var list = new List<DriveEntry>();
        try
        {
            foreach (var di in DriveInfo.GetDrives())
            {
                if (di.DriveType != DriveType.Fixed &&
                    di.DriveType != DriveType.Removable) continue;
                try
                {
                    if (!di.IsReady) continue;
                    var total  = di.TotalSize;
                    var free   = di.TotalFreeSpace;
                    var used   = total - free;
                    list.Add(new DriveEntry
                    {
                        Label     = string.IsNullOrEmpty(di.VolumeLabel)
                                        ? di.Name
                                        : $"{di.VolumeLabel} ({di.Name})",
                        DriveType = di.DriveType == DriveType.Removable ? "Removable" : "Fixed",
                        FileSystem = di.DriveFormat,
                        TotalGb   = total  / 1_073_741_824.0,
                        FreeGb    = free   / 1_073_741_824.0,
                        UsedGb    = used   / 1_073_741_824.0,
                        UsedPct   = total > 0 ? (int)(used * 100.0 / total) : 0
                    });
                }
                catch { }
            }
        }
        catch { }
        return list;
    }

    private static string FormatUptime(TimeSpan t)
    {
        if (t.TotalDays >= 1)
            return $"{(int)t.TotalDays}d {t.Hours}h {t.Minutes}m";
        if (t.TotalHours >= 1)
            return $"{(int)t.TotalHours}h {t.Minutes}m";
        return $"{t.Minutes}m";
    }
}

// ── Data models ───────────────────────────────────────────────────────────
public sealed class SystemInfoSnapshot
{
    // CPU
    public string CpuName    { get; set; } = "";
    public int    CpuCores   { get; set; }
    public int    CpuLogical { get; set; }
    public float  CpuLoad    { get; set; }   // filled by ViewModel from HardwareService
    public float  CpuTempC   { get; set; }   // filled by ViewModel from HardwareService

    // RAM
    public double RamTotalGb  { get; set; }
    public double RamUsedGb   { get; set; }
    public uint   RamLoadPct  { get; set; }
    public int    RamSpeedMhz { get; set; }

    // GPU
    public string GpuName   { get; set; } = "";
    public double GpuVramGb { get; set; }
    public string GpuVramDisplay => GpuVramGb > 0 ? $"{GpuVramGb:0.0} GB VRAM" : "";

    // Drives
    public List<DriveEntry> Drives { get; set; } = new();

    // OS
    public string OsName       { get; set; } = "";
    public string OsBuild      { get; set; } = "";
    public string Uptime       { get; set; } = "";
    public string MachineName  { get; set; } = "";
    public string UserName     { get; set; } = "";
    public string Architecture { get; set; } = "";

    // Derived display strings
    public string CpuLoadDisplay  => $"{CpuLoad:0}%";
    public string CpuTempDisplay  => CpuTempC > 0 ? $"{CpuTempC:0} °C" : "--";
    public string RamDisplay      => $"{RamUsedGb:0.0} / {RamTotalGb:0.0} GB";
    public string CpuCoreDisplay  => $"{CpuCores} cores · {CpuLogical} threads";
    public string RamSpeedDisplay => RamSpeedMhz > 0 ? $"{RamSpeedMhz} MHz" : "";
    public string OsDisplay       => OsBuild.Length > 0 ? $"{OsName}  ·  Build {OsBuild}" : OsName;
}

public sealed class DriveEntry
{
    public string Label      { get; init; } = "";
    public string DriveType  { get; init; } = "";
    public string FileSystem { get; init; } = "";
    public double TotalGb    { get; init; }
    public double FreeGb     { get; init; }
    public double UsedGb     { get; init; }
    public int    UsedPct    { get; init; }

    public string SizeDisplay => $"{UsedGb:0.0} / {TotalGb:0.0} GB";
    public string FreeDisplay => $"{FreeGb:0.0} GB free";
}
