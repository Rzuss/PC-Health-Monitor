using System;
using System.IO;
using System.Text.Json;

namespace PCHealthMonitor.Services;

public sealed class SettingsService
{
    private static readonly string SettingsFile =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                     "PCHealthMonitor", "settings.json");

    private static readonly AppSettings Defaults = new();

    public AppSettings Load()
    {
        try
        {
            if (!File.Exists(SettingsFile)) return Defaults;
            var json = File.ReadAllText(SettingsFile);
            return JsonSerializer.Deserialize<AppSettings>(json) ?? Defaults;
        }
        catch { return Defaults; }
    }

    public void Save(AppSettings settings)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(SettingsFile)!);
            File.WriteAllText(SettingsFile, JsonSerializer.Serialize(settings,
                new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }

    public void Reset() => Save(Defaults);
}

public sealed class AppSettings
{
    // ── User preferences ──────────────────────────────────────────────────
    public bool StartWithWindows  { get; set; } = false;
    public bool MinimizeToTray    { get; set; } = true;
    public bool ShowNotifications { get; set; } = true;
    public int  ScanIntervalHours { get; set; } = 24;

    // ── Pro: Custom alert thresholds (0 = disabled) ───────────────────────
    public int CpuAlertThreshold { get; set; } = 0;
    public int RamAlertThreshold { get; set; } = 0;

    // ── Window geometry (persisted between sessions) ───────────────────────
    // -1 = not set; window will use its XAML defaults (CenterScreen, 1200×780)
    public double WindowLeft   { get; set; } = -1;
    public double WindowTop    { get; set; } = -1;
    public double WindowWidth  { get; set; } = 1200;
    public double WindowHeight { get; set; } = 780;
}
