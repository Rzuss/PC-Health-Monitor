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
            // HKCU Run
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
        using var key = Microsoft.Win32.Registry.CurrentUser
            .OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", writable: true);
        if (key is null) return;

        if (entry.IsEnabled)
            key.SetValue(entry.Name, entry.Path);
        else
            key.DeleteValue(entry.Name, throwOnMissingValue: false);
    }

    public void SaveCleanupSchedule(bool enabled, int days, string time)
    {
        if (!enabled) { DeleteCleanupScheduleAsync().GetAwaiter().GetResult(); return; }

        // Create Windows Task Scheduler task via schtasks.exe
        var args = $"/Create /F /TN \"{TaskName}\" /TR \"\\\"{Process.GetCurrentProcess().MainModule?.FileName}\\\" /silent\" " +
                   $"/SC DAILY /MO {days} /ST {time} /RL HIGHEST";
        Process.Start(new ProcessStartInfo("schtasks.exe", args)
        {
            CreateNoWindow  = true,
            UseShellExecute = false
        })?.WaitForExit();
    }

    public async Task DeleteCleanupScheduleAsync()
    {
        await Task.Run(() =>
        {
            var args = $"/Delete /F /TN \"{TaskName}\"";
            Process.Start(new ProcessStartInfo("schtasks.exe", args)
            {
                CreateNoWindow  = true,
                UseShellExecute = false
            })?.WaitForExit();
        });
    }
}
