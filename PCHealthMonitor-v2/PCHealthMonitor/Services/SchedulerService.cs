using PCHealthMonitor.ViewModels;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading.Tasks;

namespace PCHealthMonitor.Services;

public sealed class SchedulerService
{
    private const string TaskName = "PCHealthMonitor_AutoClean";

    public async Task<List<StartupEntry>> GetStartupEntriesAsync()
    {
        return await Task.Run(() =>
        {
            var entries = new List<StartupEntry>();
            using var key = Microsoft.Win32.Registry.CurrentUser
                .OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run");
            if (key is not null)
            {
                foreach (var name in key.GetValueNames())
                {
                    entries.Add(new StartupEntry
                    {
                        Name      = name,
                        Path      = key.GetValue(name)?.ToString() ?? string.Empty,
                        Publisher = string.Empty,
                        Impact    = "Medium",
                        IsEnabled = true
                    });
                }
            }
            return entries;
        });
    }

    public void SetStartupEntry(StartupEntry entry)
    {
        try
        {
            using var key = Microsoft.Win32.Registry.CurrentUser
                .OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", writable: true);
            if (key is null) return;

            if (entry.IsEnabled)
                key.SetValue(entry.Name, entry.Path);
            else
                key.DeleteValue(entry.Name, throwOnMissingValue: false);
        }
        catch { /* insufficient permissions — silent fail */ }
    }

    // ── Schedule via schtasks.exe (async — never blocks the UI thread) ─────
    public async Task SaveCleanupScheduleAsync(bool enabled, int days, string time)
    {
        if (!enabled)
        {
            await DeleteCleanupScheduleAsync();
            return;
        }

        var exe  = Process.GetCurrentProcess().MainModule?.FileName ?? string.Empty;
        var args = $"/Create /F /TN \"{TaskName}\" /TR \"\\\"{exe}\\\" /silent\" " +
                   $"/SC DAILY /MO {days} /ST {time} /RL HIGHEST";

        await RunProcessAsync("schtasks.exe", args);
    }

    public async Task DeleteCleanupScheduleAsync()
        => await RunProcessAsync("schtasks.exe", $"/Delete /F /TN \"{TaskName}\"");

    private static Task RunProcessAsync(string exe, string args)
    {
        return Task.Run(() =>
        {
            try
            {
                Process.Start(new ProcessStartInfo(exe, args)
                {
                    CreateNoWindow  = true,
                    UseShellExecute = false
                })?.WaitForExit(10_000); // 10s timeout — never block indefinitely
            }
            catch { }
        });
    }
}
