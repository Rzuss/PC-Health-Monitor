using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using DriveInfoVM = PCHealthMonitor.ViewModels.DriveInfo;
using FolderEntry = PCHealthMonitor.ViewModels.FolderEntry;

namespace PCHealthMonitor.Services;

public sealed class StorageService
{
    // System directories that are too large/slow to scan — skip them
    private static readonly HashSet<string> SkipDirs = new(StringComparer.OrdinalIgnoreCase)
    {
        "Windows", "Program Files", "Program Files (x86)",
        "$Recycle.Bin", "System Volume Information", "Recovery",
        "ProgramData", "pagefile.sys", "swapfile.sys", "hiberfil.sys"
    };

    // ── Drive list ─────────────────────────────────────────────────────────
    public async Task<List<DriveInfoVM>> GetDrivesAsync()
    {
        return await Task.Run(() =>
        {
            var result = new List<DriveInfoVM>();
            foreach (var drive in DriveInfo.GetDrives())
            {
                try
                {
                    if (!drive.IsReady) continue;
                    result.Add(new DriveInfoVM
                    {
                        Name       = drive.Name,
                        RootPath   = drive.RootDirectory.FullName,
                        DriveType  = drive.DriveType.ToString(),
                        TotalBytes = drive.TotalSize,
                        FreeBytes  = drive.TotalFreeSpace
                    });
                }
                catch { }
            }
            return result;
        });
    }

    // ── Smart large-items scan ─────────────────────────────────────────────
    // Strategy:
    //   1. Scan the user's home folder (fast, relevant)
    //   2. Scan top-level drive dirs, SKIPPING system folders
    //   3. Hard limit: 10 seconds total, max 500 dirs/files per level
    public async Task<StorageScanResult> GetLargeItemsAsync(string rootPath, int topN = 50)
    {
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        try
        {
            var items = await Task.Run(() => SmartScan(rootPath, topN, cts.Token), cts.Token);
            return new StorageScanResult { Items = items, TimedOut = false };
        }
        catch (OperationCanceledException)
        {
            return new StorageScanResult { Items = new List<FolderEntry>(), TimedOut = true };
        }
        catch
        {
            return new StorageScanResult { Items = new List<FolderEntry>(), TimedOut = false };
        }
    }

    private static List<FolderEntry> SmartScan(string rootPath, int topN, CancellationToken ct)
    {
        var items = new List<FolderEntry>();

        // Priority 1: User home folders (most relevant)
        var userHome = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (Directory.Exists(userHome))
            ScanLevel1(userHome, items, ct, maxDirs: 200);

        // Priority 2: Top-level drive dirs, skipping system folders
        if (!ct.IsCancellationRequested)
            ScanLevel1(rootPath, items, ct, maxDirs: 100, skipSystem: true);

        // Deduplicate and sort
        return items
            .GroupBy(i => i.Path, StringComparer.OrdinalIgnoreCase)
            .Select(g => g.First())
            .Where(i => i.Bytes > 1_024)   // ignore items smaller than 1 KB
            .OrderByDescending(i => i.Bytes)
            .Take(topN)
            .ToList();
    }

    private static void ScanLevel1(string root, List<FolderEntry> results,
        CancellationToken ct, int maxDirs = 200, bool skipSystem = false)
    {
        int dirCount = 0;
        try
        {
            foreach (var dir in Directory.EnumerateDirectories(root))
            {
                if (ct.IsCancellationRequested || dirCount++ > maxDirs) break;

                var name = Path.GetFileName(dir);
                if (skipSystem && SkipDirs.Contains(name)) continue;

                try
                {
                    long size = GetSizeOneLevel(dir, ct);
                    results.Add(new FolderEntry
                    {
                        Name     = name,
                        Path     = dir,
                        Bytes    = size,
                        IsFolder = true
                    });
                }
                catch { }
            }

            // Also include large individual files at root level
            int fileCount = 0;
            foreach (var file in Directory.EnumerateFiles(root))
            {
                if (ct.IsCancellationRequested || fileCount++ > 50) break;
                try
                {
                    var fi = new FileInfo(file);
                    if (fi.Length > 10_485_760)  // only files > 10 MB
                        results.Add(new FolderEntry
                        {
                            Name     = fi.Name,
                            Path     = file,
                            Bytes    = fi.Length,
                            IsFolder = false
                        });
                }
                catch { }
            }
        }
        catch { }
    }

    /// <summary>Sum of all files in dir + one level of subdirectories. Max 300 items.</summary>
    private static long GetSizeOneLevel(string path, CancellationToken ct)
    {
        long size = 0;
        int  count = 0;

        // Files at root of this directory
        try
        {
            foreach (var f in Directory.EnumerateFiles(path))
            {
                if (ct.IsCancellationRequested || count++ > 500) return size;
                try { size += new FileInfo(f).Length; } catch { }
            }
        }
        catch { }

        // Files in immediate subdirectories (level 2 — no deeper)
        try
        {
            foreach (var sub in Directory.EnumerateDirectories(path))
            {
                if (ct.IsCancellationRequested || count > 500) return size;
                try
                {
                    foreach (var f in Directory.EnumerateFiles(sub))
                    {
                        if (ct.IsCancellationRequested || count++ > 500) return size;
                        try { size += new FileInfo(f).Length; } catch { }
                    }
                }
                catch { }
            }
        }
        catch { }

        return size;
    }

}

public sealed class StorageScanResult
{
    public List<FolderEntry> Items    { get; init; } = new();
    public bool              TimedOut { get; init; }
}
