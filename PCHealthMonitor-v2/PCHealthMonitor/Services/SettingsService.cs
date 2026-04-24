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
    public bool StartWithWindows  { get; set; } = false;
    public bool MinimizeToTray    { get; set; } = true;
    public bool ShowNotifications { get; set; } = true;
    public int  ScanIntervalHours { get; set; } = 24;
}
