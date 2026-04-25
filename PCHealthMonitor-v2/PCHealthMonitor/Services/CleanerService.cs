using PCHealthMonitor.ViewModels;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace PCHealthMonitor.Services;

public sealed class CleanerService
{
    private static readonly (string Name, string[] Paths)[] Categories =
    [
        ("Windows Temp Files",       [Path.GetTempPath(), @"C:\Windows\Temp"]),
        ("Browser Cache",            [
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                         @"Google\Chrome\User Data\Default\Cache"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                         @"Microsoft\Edge\User Data\Default\Cache")]),
        ("Recycle Bin",              []),   // handled separately
        ("Windows Update Cache",     [@"C:\Windows\SoftwareDistribution\Download"]),
        ("Prefetch Files",           [@"C:\Windows\Prefetch"]),
        ("Thumbnail Cache",          [Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                                        @"Microsoft\Windows\Explorer")]),
    ];

    // CRITICAL FIX: Added 30-second CancellationToken so that large directories
    // (Windows SoftwareDistribution with thousands of files, network drives, etc.)
    // never block the background thread indefinitely. Without this, the scan could
    // run forever, accumulating Task objects until an OutOfMemoryException occurred.
    public async Task<ScanResult> AnalyzeAsync()
    {
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        try
        {
            return await Task.Run(() => ScanAll(cts.Token), cts.Token);
        }
        catch (OperationCanceledException)
        {
            return new ScanResult();   // timed out — return empty result safely
        }
        catch
        {
            return new ScanResult();
        }
    }

    private static ScanResult ScanAll(CancellationToken ct)
    {
        var cats = new List<JunkCategory>();
        foreach (var (name, paths) in Categories)
        {
            if (ct.IsCancellationRequested) break;

            long bytes = 0;
            int  count = 0;
            foreach (var p in paths)
            {
                if (ct.IsCancellationRequested) break;
                try
                {
                    if (!Directory.Exists(p)) continue;
                    var files = Directory.EnumerateFiles(p, "*", SearchOption.AllDirectories);
                    foreach (var f in files)
                    {
                        if (ct.IsCancellationRequested) break;
                        try { var fi = new FileInfo(f); bytes += fi.Length; count++; } catch { }
                    }
                }
                catch { }
            }
            if (count > 0)
                cats.Add(new JunkCategory { Name = name, Bytes = bytes, FileCount = count });
        }
        return new ScanResult
        {
            Categories = cats,
            TotalBytes = cats.Sum(c => c.Bytes),
            FileCount  = cats.Sum(c => c.FileCount)
        };
    }

    public async Task<long> CleanAsync(IEnumerable<JunkCategory> categories)
    {
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(60));
        try
        {
            return await Task.Run(() => CleanAll(categories, cts.Token), cts.Token);
        }
        catch { return 0; }
    }

    private static long CleanAll(IEnumerable<JunkCategory> categories, CancellationToken ct)
    {
        long freed = 0;
        foreach (var cat in categories.Where(c => c.Selected))
        {
            if (ct.IsCancellationRequested) break;
            var entry = Categories.FirstOrDefault(e => e.Name == cat.Name);
            if (entry == default) continue;
            foreach (var p in entry.Paths)
            {
                if (ct.IsCancellationRequested) break;
                try
                {
                    if (!Directory.Exists(p)) continue;
                    foreach (var f in Directory.EnumerateFiles(p, "*", SearchOption.AllDirectories))
                    {
                        if (ct.IsCancellationRequested) break;
                        try { var fi = new FileInfo(f); freed += fi.Length; fi.Delete(); } catch { }
                    }
                }
                catch { }
            }
        }
        return freed;
    }
}

public sealed class ScanResult
{
    public List<JunkCategory> Categories { get; init; } = new();
    public long TotalBytes { get; init; }
    public int  FileCount  { get; init; }
}
