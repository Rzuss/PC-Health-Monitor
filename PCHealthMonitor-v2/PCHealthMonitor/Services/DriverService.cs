using PCHealthMonitor.ViewModels;
using System;
using System.Collections.Generic;
using System.Management;
using System.Threading;
using System.Threading.Tasks;

namespace PCHealthMonitor.Services;

public sealed class DriverService
{
    // Drivers older than this are flagged
    private static readonly TimeSpan AgingThreshold    = TimeSpan.FromDays(365 * 2);
    private static readonly TimeSpan OutdatedThreshold = TimeSpan.FromDays(365 * 4);

    public async Task<List<DriverEntry>> GetFlaggedDriversAsync()
    {
        // CRITICAL FIX #1: Win32_PnPSignedDriver is notorious for blocking 30-60 seconds
        // on some machines. Without a timeout it hangs the background thread indefinitely,
        // which eventually causes the app to freeze and crash.
        // We wrap the entire WMI query in Task.Run with a 20-second CancellationToken.
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        try
        {
            return await Task.Run(() => QueryFlaggedDrivers(cts.Token), cts.Token);
        }
        catch (OperationCanceledException)
        {
            return new List<DriverEntry>();   // timed out — return empty, never crash
        }
        catch
        {
            return new List<DriverEntry>();
        }
    }

    private static List<DriverEntry> QueryFlaggedDrivers(CancellationToken ct)
    {
        var flagged = new List<DriverEntry>();

        // CRITICAL FIX #2: ManagementObject implements IDisposable — must be disposed
        // inside the foreach loop. Previously, every WMI object was leaked, causing
        // hundreds of COM references to accumulate and eventually OutOfMemoryException.
        // Each ManagementObject holds native COM memory that only the GC finalizer would
        // eventually release — but under pressure that could be too late.
        using var searcher = new ManagementObjectSearcher(
            "SELECT DeviceName, DriverVersion, DriverDate, DeviceClass " +
            "FROM Win32_PnPSignedDriver WHERE DriverDate IS NOT NULL");

        // Set a WMI timeout on the options as an extra safety net
        searcher.Options.Timeout = TimeSpan.FromSeconds(18);

        ManagementObjectCollection? results = null;
        try { results = searcher.Get(); }
        catch { return flagged; }

        try
        {
            foreach (ManagementObject obj in results)
            {
                // CRITICAL FIX: dispose each object immediately after use
                using (obj)
                {
                    if (ct.IsCancellationRequested) break;
                    try
                    {
                        var dateStr  = obj["DriverDate"]?.ToString();
                        var name     = obj["DeviceName"]?.ToString() ?? string.Empty;
                        var version  = obj["DriverVersion"]?.ToString() ?? string.Empty;
                        var devClass = obj["DeviceClass"]?.ToString() ?? string.Empty;

                        if (string.IsNullOrWhiteSpace(dateStr) || string.IsNullOrWhiteSpace(name))
                            continue;

                        DateTime driverDate;
                        try { driverDate = ManagementDateTimeConverter.ToDateTime(dateStr); }
                        catch { continue; }

                        var age = DateTime.Now - driverDate;

                        string status;
                        if (age >= OutdatedThreshold)
                            status = "Outdated";
                        else if (age >= AgingThreshold)
                            status = "Aging";
                        else
                            continue;

                        flagged.Add(new DriverEntry
                        {
                            Name        = name,
                            Version     = version,
                            Date        = driverDate.ToString("yyyy-MM-dd"),
                            Status      = status,
                            DeviceClass = devClass
                        });
                    }
                    catch { }
                }
            }
        }
        finally
        {
            results.Dispose();
        }

        flagged.Sort((a, b) =>
        {
            int cmp = string.Compare(b.Status, a.Status, StringComparison.Ordinal);
            return cmp != 0 ? cmp : string.Compare(a.Name, b.Name, StringComparison.OrdinalIgnoreCase);
        });

        return flagged;
    }
}
