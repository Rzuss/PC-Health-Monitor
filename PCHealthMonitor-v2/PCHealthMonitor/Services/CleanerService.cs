using PCHealthMonitor.ViewModels;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

namespace PCHealthMonitor.Services;

public sealed class CleanerService
{
    // ── Shell32 P/Invoke — Recycle Bin size query + empty ────────────────────
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHQueryRecycleBin(string? pszRootPath, ref SHQUERYRBINFO pSHQueryRBInfo);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHEmptyRecycleBin(IntPtr hwnd, string? pszRootPath, uint dwFlags);

    [StructLayout(LayoutKind.Sequential)]
    private struct SHQUERYRBINFO
    {
        public int  cbSize;
        public long i64Size;
        public long i64NumItems;
    }

    private const uint SHERB_NOCONFIRMATION = 0x00000001;
    private const uint SHERB_NOPROGRESSUI   = 0x00000002;
    private const uint SHERB_NOSOUND        = 0x00000004;

    // ── Category table ────────────────────────────────────────────────────────
    // Recycle Bin has no path entries — handled via Shell32 API in Scan/Clean
    private static readonly (string Name, string[] Paths)[] Categories = BuildCategories();

    private static (string Name, string[] Paths)[] BuildCategories()
    {
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return
        [
            ("Windows Temp Files",   [Path.GetTempPath(), @"C:\Windows\Temp"]),
            ("Browser Cache",        GetBrowserCachePaths(local)),
            ("Recycle Bin",          []),
            ("Windows Update Cache", [@"C:\Windows\SoftwareDistribution\Download"]),
            ("Prefetch Files",       [@"C:\Windows\Prefetch"]),
            ("Thumbnail Cache",      [Path.Combine(local, @"Microsoft\Windows\Explorer")]),
        ];
    }

    // Enumerate all Chrome, Edge, and Firefox profile cache directories.
    private static string[] GetBrowserCachePaths(string localAppData)
    {
        var paths = new List<string>();
        CollectChromiumCaches(Path.Combine(localAppData, @"Google\Chrome\User Data"), paths);
        CollectChromiumCaches(Path.Combine(localAppData, @"Microsoft\Edge\User Data"), paths);
        CollectFirefoxCaches(Path.Combine(localAppData, @"Mozilla\Firefox\Profiles"), paths);
        return paths.ToArray();
    }

    private static void CollectChromiumCaches(string userDataDir, List<string> paths)
    {
        if (!Directory.Exists(userDataDir)) return;
        try
        {
            foreach (var profileDir in Directory.EnumerateDirectories(userDataDir))
            {
                var cache = Path.Combine(profileDir, "Cache");
                if (Directory.Exists(cache)) paths.Add(cache);
            }
        }
        catch { }
    }

    private static void CollectFirefoxCaches(string profilesDir, List<string> paths)
    {
        if (!Directory.Exists(profilesDir)) return;
        try
        {
            foreach (var profileDir in Directory.EnumerateDirectories(profilesDir))
            {
                var cache = Path.Combine(profileDir, "cache2");
                if (Directory.Exists(cache)) paths.Add(cache);
            }
        }
        catch { }
    }

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

            // ── Recycle Bin: use Shell32 API for accurate size ────────────────
            if (name == "Recycle Bin")
            {
                try
                {
                    var info = new SHQUERYRBINFO { cbSize = Marshal.SizeOf<SHQUERYRBINFO>() };
                    int hr   = SHQueryRecycleBin(null, ref info);
                    if (hr == 0 && info.i64NumItems > 0)
                        cats.Add(new JunkCategory
                        {
                            Name      = name,
                            Bytes     = info.i64Size,
                            FileCount = (int)info.i64NumItems
                        });
                }
                catch { }
                continue;
            }

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

            // ── Recycle Bin: use Shell32 API — never manually delete $Recycle.Bin ──
            if (cat.Name == "Recycle Bin")
            {
                try
                {
                    // Query current size so we can report accurate freed bytes
                    var info = new SHQUERYRBINFO { cbSize = Marshal.SizeOf<SHQUERYRBINFO>() };
                    SHQueryRecycleBin(null, ref info);
                    int hr = SHEmptyRecycleBin(IntPtr.Zero, null,
                        SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND);
                    if (hr == 0) freed += info.i64Size;
                }
                catch { }
                continue;
            }

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
