using PCHealthMonitor.ViewModels;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Management;
using System.Threading.Tasks;

namespace PCHealthMonitor.Services;

public sealed class StorageService
{
    // ── Drive list ─────────────────────────────────────────────────────────
    public async Task<List<DriveInfo>> GetDrivesAsync()
    {
        return await Task.Run(() =>
        {
            var result = new List<DriveInfo>();
            foreach (var drive in System.IO.DriveInfo.GetDrives())
            {
                try
                {
                    if (!drive.IsReady) continue;
                    result.Add(new DriveInfo
                    {
                        Name      = drive.Name,
                        RootPath  = drive.RootDirectory.FullName,
                        DriveType = drive.DriveType.ToString(),
                        TotalBytes = drive.TotalSize,
                        FreeBytes  = drive.TotalFreeSpace
                    });
                }
                catch { }
            }
            return result;
        });
    }

    // ── Large items ────────────────────────────────────────────────────────
    public async Task<List<FolderEntry>> GetLargeItemsAsync(string rootPath, int topN = 50)
    {
        return await Task.Run(() =>
        {
            var items = new List<FolderEntry>();
            try
            {
                // Top-level directories
                foreach (var dir in Directory.GetDirectories(rootPath))
                {
                    try
                    {
                        long size = GetDirectorySize(dir);
                        items.Add(new FolderEntry
                        {
                            Name     = Path.GetFileName(dir),
                            Path     = dir,
                            Bytes    = size,
                            IsFolder = true
                        });
                    }
                    catch { }
                }
                // Top-level files
                foreach (var file in Directory.GetFiles(rootPath))
                {
                    try
                    {
                        var fi = new FileInfo(file);
                        items.Add(new FolderEntry
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

            return items.OrderByDescending(i => i.Bytes).Take(topN).ToList();
        });
    }

    // ── S.M.A.R.T. via WMI ────────────────────────────────────────────────
    public async Task<List<SmartDisk>> GetSmartDataAsync()
    {
        return await Task.Run(() =>
        {
            var disks = new List<SmartDisk>();
            try
            {
                using var searcher = new ManagementObjectSearcher(
                    @"\\.\root\wmi", "SELECT * FROM MSStorageDriver_FailurePredictStatus");
                foreach (ManagementObject obj in searcher.Get())
                {
                    bool predicted = (bool)(obj["PredictFailure"] ?? false);
                    disks.Add(new SmartDisk
                    {
                        Model  = obj["InstanceName"]?.ToString() ?? "Unknown",
                        Status = predicted ? "Warning" : "Good",
                        Health = predicted ? 50 : 100
                    });
                }
            }
            catch
            {
                // No admin / WMI unavailable — return empty list gracefully
            }
            return disks;
        });
    }

    private static long GetDirectorySize(string path)
    {
        long size = 0;
        try
        {
            foreach (var f in Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories))
            {
                try { size += new FileInfo(f).Length; } catch { }
            }
        }
        catch { }
        return size;
    }
}
