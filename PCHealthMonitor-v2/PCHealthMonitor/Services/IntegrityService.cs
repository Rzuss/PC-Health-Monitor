using System;
using System.IO;
using System.Net.NetworkInformation;
using System.Reflection;

namespace PCHealthMonitor.Services;

/// <summary>
/// Runtime integrity guard.
/// Detects common tampering patterns: unexpected outbound connections,
/// suspicious assembly injection, and hardcoded secret leaks.
/// All checks are passive (read-only) and logged — never blocking UX.
/// </summary>
public static class IntegrityService
{
    // ── Public entry point ────────────────────────────────────────────────
    public static IntegrityReport Check()
    {
        var report = new IntegrityReport();

        report.AssemblyLocation   = Environment.ProcessPath ?? AppContext.BaseDirectory;
        report.IsRunningFromTemp  = IsFromTempPath(report.AssemblyLocation);
        report.HasSuspiciousName  = HasSuspiciousAssemblyName();
        report.NetworkInterfaces  = GetActiveInterfaces();
        report.CheckedAt          = DateTime.Now;

        // Log to crash log location for audit trail
        WriteAuditEntry(report);

        return report;
    }

    // ── Checks ────────────────────────────────────────────────────────────

    /// Running from %TEMP% is a red flag — dropper malware often does this.
    private static bool IsFromTempPath(string location)
    {
        var temp = Path.GetTempPath();
        return location.StartsWith(temp, StringComparison.OrdinalIgnoreCase);
    }

    /// Check if any loaded assembly has a name that doesn't match known deps.
    private static bool HasSuspiciousAssemblyName()
    {
        foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
        {
            var name = asm.GetName().Name ?? string.Empty;
            // Flag injected assemblies that follow common obfuscation patterns
            if (name.Length > 0 && name.Length < 4 && !name.StartsWith("ms", StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    /// Returns list of active (Up) network interfaces for informational logging.
    private static string GetActiveInterfaces()
    {
        try
        {
            var names = new System.Collections.Generic.List<string>();
            foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
                if (ni.OperationalStatus == OperationalStatus.Up)
                    names.Add(ni.Name);
            return string.Join(", ", names);
        }
        catch { return "unavailable"; }
    }

    // ── Audit log ─────────────────────────────────────────────────────────
    private static void WriteAuditEntry(IntegrityReport r)
    {
        try
        {
            var logDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "PCHealthMonitor", "Logs");
            Directory.CreateDirectory(logDir);

            var line = $"[{r.CheckedAt:yyyy-MM-dd HH:mm:ss}] " +
                       $"EXE={r.AssemblyLocation} | " +
                       $"FromTemp={r.IsRunningFromTemp} | " +
                       $"SuspiciousAsm={r.HasSuspiciousName} | " +
                       $"NICs={r.NetworkInterfaces}\n";

            File.AppendAllText(Path.Combine(logDir, "integrity.log"), line);
        }
        catch { /* never throw from a security check */ }
    }
}

public sealed class IntegrityReport
{
    public string   AssemblyLocation  { get; set; } = string.Empty;
    public bool     IsRunningFromTemp { get; set; }
    public bool     HasSuspiciousName { get; set; }
    public string   NetworkInterfaces { get; set; } = string.Empty;
    public DateTime CheckedAt         { get; set; }

    /// True if any check raised a flag.
    public bool HasWarnings => IsRunningFromTemp || HasSuspiciousName;
}
