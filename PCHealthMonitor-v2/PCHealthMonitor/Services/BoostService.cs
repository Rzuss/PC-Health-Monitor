using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

namespace PCHealthMonitor.Services;

public sealed class BoostService
{
    private bool _isActive;

    public async Task ActivateAsync(int durationMinutes)
    {
        if (_isActive) return;
        await Task.Run(() =>
        {
            // Elevate foreground processes to High priority
            try
            {
                foreach (var proc in Process.GetProcesses())
                {
                    try
                    {
                        if (proc.MainWindowHandle != IntPtr.Zero) // foreground / GUI process
                            proc.PriorityClass = ProcessPriorityClass.High;
                    }
                    catch { }
                }
            }
            catch { }

            // Flush standby memory via EmptyWorkingSet on own process (safe)
            try { EmptyWorkingSet(Process.GetCurrentProcess().Handle); } catch { }

            _isActive = true;
        });
    }

    public void Deactivate()
    {
        if (!_isActive) return;
        try
        {
            foreach (var proc in Process.GetProcesses())
            {
                try
                {
                    if (proc.MainWindowHandle != IntPtr.Zero)
                        proc.PriorityClass = ProcessPriorityClass.Normal;
                }
                catch { }
            }
        }
        catch { }
        _isActive = false;
    }

    [DllImport("psapi.dll")]
    private static extern bool EmptyWorkingSet(IntPtr hProcess);
}
