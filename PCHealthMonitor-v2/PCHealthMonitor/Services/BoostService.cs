using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

namespace PCHealthMonitor.Services;

/// <summary>
/// Provides targeted process boosting — elevates a single chosen process to
/// ProcessPriorityClass.High and flushes standby memory.
/// All prior boosted processes are restored to Normal on Deactivate().
/// </summary>
public sealed class BoostService
{
    // Tracks which PIDs we elevated so we can restore them exactly.
    private readonly List<int> _boostedPids = new();

    // ── Query running processes with a visible window ─────────────────────
    public Task<List<ProcessEntry>> GetBoostableProcessesAsync() =>
        Task.Run(() =>
        {
            var list = new List<ProcessEntry>();
            foreach (var p in Process.GetProcesses())
            {
                try
                {
                    if (p.MainWindowHandle == IntPtr.Zero) continue;
                    if (string.IsNullOrEmpty(p.MainWindowTitle)) continue;

                    list.Add(new ProcessEntry
                    {
                        Pid         = p.Id,
                        Name        = p.ProcessName,
                        WindowTitle = p.MainWindowTitle,
                        MemoryMb    = p.WorkingSet64 / 1_048_576.0
                    });
                }
                catch { }
                finally { p.Dispose(); }
            }

            return list
                .OrderByDescending(x => x.MemoryMb)
                .ToList();
        });

    // ── Boost a specific process ──────────────────────────────────────────
    public Task BoostProcessAsync(int pid) =>
        Task.Run(() =>
        {
            // Restore any previously boosted processes first
            RestoreAll();

            try
            {
                using var proc = Process.GetProcessById(pid);
                proc.PriorityClass = ProcessPriorityClass.High;
                _boostedPids.Add(pid);
            }
            catch { }

            // Flush standby memory (safe, no admin needed)
            try
            {
                using var self = Process.GetCurrentProcess();
                EmptyWorkingSet(self.Handle);
            }
            catch { }
        });

    // ── Restore ───────────────────────────────────────────────────────────
    public void Deactivate() => RestoreAll();

    private void RestoreAll()
    {
        foreach (var pid in _boostedPids)
        {
            try
            {
                using var p = Process.GetProcessById(pid);
                p.PriorityClass = ProcessPriorityClass.Normal;
            }
            catch { }
        }
        _boostedPids.Clear();
    }

    [DllImport("psapi.dll")]
    private static extern bool EmptyWorkingSet(IntPtr hProcess);
}

// ── Data model ────────────────────────────────────────────────────────────
public sealed class ProcessEntry
{
    public int    Pid         { get; init; }
    public string Name        { get; init; } = "";
    public string WindowTitle { get; init; } = "";
    public double MemoryMb    { get; init; }

    // Display helpers
    public string DisplayName   => string.IsNullOrWhiteSpace(WindowTitle) ? Name : WindowTitle;
    public string MemoryDisplay => $"{MemoryMb:0} MB";
    // First letter for avatar
    public string Initial       => (DisplayName.Length > 0 ? DisplayName[0].ToString() : "?").ToUpper();
}
