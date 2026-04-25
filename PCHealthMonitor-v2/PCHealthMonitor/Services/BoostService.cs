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
            // Elevate foreground GUI processes to High priority
            foreach (var proc in Process.GetProcesses())
            {
                using (proc)
                {
                    try
                    {
                        if (proc.MainWindowHandle != IntPtr.Zero)
                            proc.PriorityClass = ProcessPriorityClass.High;
                    }
                    catch { }
                }
            }

            // Flush own working set (safe, no admin needed)
            try
            {
                using var self = Process.GetCurrentProcess();
                EmptyWorkingSet(self.Handle);
            }
            catch { }

            _isActive = true;
        });
    }

    public void Deactivate()
    {
        if (!_isActive) return;

        foreach (var proc in Process.GetProcesses())
        {
            using (proc)
            {
                try
                {
                    if (proc.MainWindowHandle != IntPtr.Zero)
                        proc.PriorityClass = ProcessPriorityClass.Normal;
                }
                catch { }
            }
        }

        _isActive = false;
    }

    [DllImport("psapi.dll")]
    private static extern bool EmptyWorkingSet(IntPtr hProcess);
}
