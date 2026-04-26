using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace PCHealthMonitor.Services;

/// <summary>
/// Generates system health reports.
/// Free tier: plain text report.
/// Pro tier:  CSV export + styled HTML report (printable as PDF from browser).
/// All output goes to Documents\PCHealthMonitor\Reports\.
/// </summary>
public sealed class ReportService
{
    private static readonly string ReportsDir =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
                     "PCHealthMonitor", "Reports");

    // ── Free: plain-text ──────────────────────────────────────────────────────
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

    // ── Pro: CSV ──────────────────────────────────────────────────────────────
    public async Task<string> GenerateCsvReportAsync(
        HardwareSnapshot snap,
        IReadOnlyList<MetricPoint> history)
    {
        var now      = DateTime.Now;
        var snapCopy = snap;
        var histCopy = history;

        return await Task.Run(() =>
        {
            var sb = new StringBuilder();
            sb.AppendLine("PC Health Monitor — CSV Export");
            sb.AppendLine($"Generated:,{now:yyyy-MM-dd HH:mm:ss}");
            sb.AppendLine();

            sb.AppendLine("=== Current Snapshot ===");
            sb.AppendLine("Metric,Value");
            sb.AppendLine($"Health Score,{snapCopy.HealthScore}/100 ({snapCopy.HealthGrade})");
            sb.AppendLine($"CPU Load,{snapCopy.CpuLoad:0.0}%");
            sb.AppendLine($"CPU Temperature,{(snapCopy.CpuTempC > 0 ? $"{snapCopy.CpuTempC:0}°C" : "N/A")}");
            sb.AppendLine($"RAM Load,{snapCopy.RamLoad}%");
            sb.AppendLine($"RAM Used,{snapCopy.RamUsedGb:0.2} GB");
            sb.AppendLine($"RAM Total,{snapCopy.RamTotalGb:0.2} GB");
            sb.AppendLine($"Disk Activity,{snapCopy.DiskLoad:0.0}%");
            sb.AppendLine();

            if (histCopy.Count > 0)
            {
                sb.AppendLine("=== Historical Data ===");
                sb.AppendLine("Timestamp,CPU%,RAM%,Disk%");
                foreach (var p in histCopy)
                    sb.AppendLine($"{p.Timestamp:yyyy-MM-dd HH:mm:ss},{p.CpuLoad:0.0},{p.RamLoad},{p.DiskLoad:0.0}");
            }

            Directory.CreateDirectory(ReportsDir);
            var path = Path.Combine(ReportsDir, $"report_{now:yyyyMMdd_HHmmss}.csv");
            // UTF-8 BOM so Excel opens it correctly
            File.WriteAllText(path, sb.ToString(), new UTF8Encoding(encoderShouldEmitUTF8Identifier: true));
            return path;
        });
    }

    // ── Pro: HTML (open in browser → Ctrl+P → Save as PDF) ───────────────────
    public async Task<string> GenerateHtmlReportAsync(
        HardwareSnapshot snap,
        IReadOnlyList<MetricPoint> history)
    {
        var now      = DateTime.Now;
        var snapCopy = snap;
        var histCopy = history;

        return await Task.Run(() =>
        {
            var cpuPath  = BuildSvgPoints(histCopy, p => p.CpuLoad,          300, 60);
            var ramPath  = BuildSvgPoints(histCopy, p => (float)p.RamLoad,   300, 60);
            var diskPath = BuildSvgPoints(histCopy, p => p.DiskLoad,         300, 60);

            var tableRows = BuildTableRows(histCopy, maxRows: 30);

            var html = $@"<!DOCTYPE html>
<html lang=""en"">
<head>
<meta charset=""UTF-8""/>
<title>PC Health Monitor — System Report</title>
<style>
  *{{margin:0;padding:0;box-sizing:border-box}}
  body{{font-family:'Segoe UI',sans-serif;background:#0a0d14;color:#e2e8f0;padding:32px}}
  h1{{font-size:22px;font-weight:600;margin-bottom:4px}}
  .sub{{color:#94a3b8;font-size:13px;margin-bottom:32px}}
  .grid{{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:24px}}
  .card{{background:#131929;border:1px solid #1e2a3a;border-radius:12px;padding:20px}}
  .card-wide{{grid-column:1/-1}}
  .lbl{{font-size:11px;color:#64748b;text-transform:uppercase;letter-spacing:.05em;margin-bottom:4px}}
  .val{{font-size:28px;font-weight:700}}
  .sub2{{font-size:12px;color:#94a3b8;margin-top:2px}}
  .excellent{{color:#22c55e}}.good{{color:#84cc16}}.fair{{color:#f59e0b}}.poor{{color:#ef4444}}
  .chart-lbl{{font-size:12px;color:#64748b;margin-bottom:8px}}
  svg{{display:block;width:100%}}
  table{{width:100%;border-collapse:collapse;font-size:12px}}
  th{{text-align:left;padding:8px 12px;color:#64748b;border-bottom:1px solid #1e2a3a}}
  td{{padding:8px 12px;border-bottom:1px solid #1a2030}}
  tr:last-child td{{border-bottom:none}}
  @media print{{body{{background:#fff;color:#000}}.card{{background:#f8fafc;border-color:#e2e8f0}}}}
</style>
</head>
<body>
<h1>PC Health Monitor</h1>
<div class=""sub"">System Report · {now:dddd, MMMM d yyyy · HH:mm:ss}</div>
<div class=""grid"">
  <div class=""card"">
    <div class=""lbl"">Health Score</div>
    <div class=""val {ScoreClass(snapCopy.HealthScore)}"">{snapCopy.HealthScore}<span style=""font-size:16px;font-weight:400"">/100</span></div>
    <div class=""sub2"">{snapCopy.HealthGrade}</div>
  </div>
  <div class=""card"">
    <div class=""lbl"">CPU Load</div>
    <div class=""val"">{snapCopy.CpuLoad:0.0}<span style=""font-size:16px"">%</span></div>
    <div class=""sub2"">Temp: {(snapCopy.CpuTempC > 0 ? $"{snapCopy.CpuTempC:0}°C" : "N/A")}</div>
  </div>
  <div class=""card"">
    <div class=""lbl"">RAM</div>
    <div class=""val"">{snapCopy.RamLoad}<span style=""font-size:16px"">%</span></div>
    <div class=""sub2"">{snapCopy.RamUsedGb:0.1} GB / {snapCopy.RamTotalGb:0.1} GB</div>
  </div>
  <div class=""card"">
    <div class=""lbl"">Disk Activity</div>
    <div class=""val"">{snapCopy.DiskLoad:0.0}<span style=""font-size:16px"">%</span></div>
  </div>
</div>
{(histCopy.Count > 0 ? $@"<div class=""card card-wide"" style=""margin-bottom:24px"">
  <div class=""chart-lbl"">CPU History</div>
  <svg viewBox=""0 0 300 60"" style=""height:60px"" preserveAspectRatio=""none"">
    <polyline points=""{cpuPath}"" fill=""none"" stroke=""#3b82f6"" stroke-width=""1.5""/>
  </svg>
  <div class=""chart-lbl"" style=""margin-top:16px"">RAM History</div>
  <svg viewBox=""0 0 300 60"" style=""height:60px"" preserveAspectRatio=""none"">
    <polyline points=""{ramPath}"" fill=""none"" stroke=""#8b5cf6"" stroke-width=""1.5""/>
  </svg>
  <div class=""chart-lbl"" style=""margin-top:16px"">Disk History</div>
  <svg viewBox=""0 0 300 60"" style=""height:60px"" preserveAspectRatio=""none"">
    <polyline points=""{diskPath}"" fill=""none"" stroke=""#f59e0b"" stroke-width=""1.5""/>
  </svg>
</div>
<div class=""card card-wide"">
  <div class=""chart-lbl"" style=""margin-bottom:12px"">Data Sample ({histCopy.Count} points, showing up to 30)</div>
  <table><tr><th>Timestamp</th><th>CPU%</th><th>RAM%</th><th>Disk%</th></tr>
  {tableRows}</table>
</div>" : "")}
</body></html>";

            Directory.CreateDirectory(ReportsDir);
            var path = Path.Combine(ReportsDir, $"report_{now:yyyyMMdd_HHmmss}.html");
            File.WriteAllText(path, html, Encoding.UTF8);
            return path;
        });
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    private static string ScoreClass(int score) => score switch
    {
        >= 80 => "excellent",
        >= 60 => "good",
        >= 40 => "fair",
        _     => "poor"
    };

    private static string BuildSvgPoints(IReadOnlyList<MetricPoint> list, Func<MetricPoint, float> sel, int w, int h)
    {
        if (list.Count < 2) return string.Empty;
        var sb = new StringBuilder();
        for (int i = 0; i < list.Count; i++)
        {
            double x = (double)i / (list.Count - 1) * w;
            double y = h - sel(list[i]) / 100.0 * h;
            if (i > 0) sb.Append(' ');
            sb.Append($"{x:0.0},{y:0.0}");
        }
        return sb.ToString();
    }

    private static string BuildTableRows(IReadOnlyList<MetricPoint> list, int maxRows)
    {
        if (list.Count == 0) return string.Empty;
        var step = Math.Max(1, list.Count / maxRows);
        var sb   = new StringBuilder();
        for (int i = 0; i < list.Count; i += step)
        {
            var p = list[i];
            sb.Append($"<tr><td>{p.Timestamp:HH:mm:ss}</td><td>{p.CpuLoad:0.0}</td><td>{p.RamLoad}</td><td>{p.DiskLoad:0.0}</td></tr>");
        }
        return sb.ToString();
    }

    // ── Open file in default application ─────────────────────────────────────
    public static void OpenFile(string path)
    {
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
        catch { }
    }
}
