using PCHealthMonitor.ViewModels;
using System;
using System.Collections.Generic;
using System.Management;
using System.Threading.Tasks;

namespace PCHealthMonitor.Services;

public sealed class DriverService
{
    // Drivers older than this are flagged as "Aging"
    private static readonly TimeSpan AgingThreshold   = TimeSpan.FromDays(365 * 2);
    private static readonly TimeSpan OutdatedThreshold = TimeSpan.FromDays(365 * 4);

    public async Task<List<DriverEntry>> GetFlaggedDriversAsync()
    {
        return await Task.Run(() =>
        {
            var flagged = new List<DriverEntry>();

            using var searcher = new ManagementObjectSearcher(
                "SELECT * FROM Win32_PnPSignedDriver WHERE DriverDate IS NOT NULL");

            foreach (ManagementObject obj in searcher.Get())
            {
                try
                {
                    var dateStr  = obj["DriverDate"]?.ToString();
                    var name     = obj["DeviceName"]?.ToString() ?? string.Empty;
                    var version  = obj["DriverVersion"]?.ToString() ?? string.Empty;
                    var devClass = obj["DeviceClass"]?.ToString() ?? string.Empty;

                    if (string.IsNullOrWhiteSpace(dateStr) || string.IsNullOrWhiteSpace(name))
                        continue;

                    // WMI dates: "20210315000000.000000+000"
                    if (!ManagementDateTimeConverter.ToDateTime(dateStr) is DateTime driverDate)
                        continue;

                    driverDate = ManagementDateTimeConverter.ToDateTime(dateStr);
                    var age    = DateTime.Now - driverDate;

                    string status;
                    if (age >= OutdatedThreshold)
                        status = "Outdated";
                    else if (age >= AgingThreshold)
                        status = "Aging";
                    else
                        continue; // driver is recent enough — skip

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

            // Sort: Outdated first, then Aging; alphabetical within group
            flagged.Sort((a, b) =>
            {
                int cmp = string.Compare(b.Status, a.Status, StringComparison.Ordinal); // Outdated > Aging
                return cmp != 0 ? cmp : string.Compare(a.Name, b.Name, StringComparison.OrdinalIgnoreCase);
            });

            return flagged;
        });
    }
}
