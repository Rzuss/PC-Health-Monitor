using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;

namespace PCHealthMonitor.Services;

/// <summary>
/// Generates plain-text and JSON health reports saved to the user's Documents folder.
/// </summary>
public sealed class ReportService
{
    private static readonly string ReportsDir =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
                     "PCHealthMonitor", "Reports");

    public async Task<string> GenerateTextReportAsync(HardwareSnapshot snap)
    {
        return await Task.Run(() =>
        {
            var sb = new StringBuilder();
            sb.AppendLine("═══════════════════════════════════════════════");
            sb.AppendLine("  PC Health Monitor — System Report");
            sb.AppendLine($"  Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
            sb.AppendLine("═══════════════════════════════════════════════");
            sb.AppendLine();
            sb.AppendLine($"Health Score : {snap.HealthScore}/100  ({snap.HealthGrade})");
            sb.AppendLine($"CPU Load     : {snap.CpuLoad:0.0}%");
            sb.AppendLine($"CPU Temp     : {(snap.CpuTempC > 0 ? $"{snap.CpuTempC:0}°C" : "N/A")}");
            sb.AppendLine($"RAM Load     : {snap.RamLoad}%  ({snap.RamUsedGb:0.1} / {snap.RamTotalGb:0.1} GB)");
            sb.AppendLine($"Disk Activity: {snap.DiskLoad:0.0}%");
            sb.AppendLine();
            sb.AppendLine("═══════════════════════════════════════════════");

            Directory.CreateDirectory(ReportsDir);
            var path = Path.Combine(ReportsDir, $"report_{DateTime.Now:yyyyMMdd_HHmmss}.txt");
            File.WriteAllText(path, sb.ToString(), Encoding.UTF8);
            return path;
        });
    }
}
