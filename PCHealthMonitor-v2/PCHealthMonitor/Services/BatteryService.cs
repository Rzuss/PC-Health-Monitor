using System;
using System.Management;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace PCHealthMonitor.Services;

/// <summary>
/// Reads battery status (for laptops). Returns null on desktops.
/// </summary>
public sealed class BatteryService
{
    public async Task<BatteryInfo?> GetBatteryInfoAsync()
    {
        return await Task.Run(() =>
        {
            var status = SystemInformation.PowerStatus;
            if (status.BatteryChargeStatus == BatteryChargeStatus.NoSystemBattery)
                return null;

            return new BatteryInfo
            {
                ChargePercent = (int)(status.BatteryLifePercent * 100),
                IsCharging    = status.PowerLineStatus == PowerLineStatus.Online,
                TimeRemainSec = status.BatteryLifeRemaining
            };
        });
    }
}

public sealed class BatteryInfo
{
    public int  ChargePercent  { get; init; }
    public bool IsCharging     { get; init; }
    public int  TimeRemainSec  { get; init; }
    public string TimeDisplay  => TimeRemainSec > 0
        ? $"{TimeRemainSec / 3600}h {(TimeRemainSec % 3600) / 60}m"
        : IsCharging ? "Charging" : "Unknown";
}
