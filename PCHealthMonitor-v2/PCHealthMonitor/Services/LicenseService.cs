using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace PCHealthMonitor.Services;

public sealed class LicenseService
{
    private static readonly string LicenseFile =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                     "PCHealthMonitor", "license.dat");

    private bool _activated;
    public bool IsActivated => _activated;

    public LicenseService() => _activated = LoadFromDisk();

    public async Task<bool> ActivateAsync(string key)
    {
        // Offline validation: valid key = SHA256 of key starts with "PCHM"
        return await Task.Run(() =>
        {
            if (string.IsNullOrWhiteSpace(key)) return false;

            var hash = Convert.ToHexString(
                SHA256.HashData(Encoding.UTF8.GetBytes(key.ToUpperInvariant())));

            // Demo: any key starting with "PCHM-" is accepted
            bool valid = key.StartsWith("PCHM-", StringComparison.OrdinalIgnoreCase)
                         && key.Length >= 19;

            if (valid)
            {
                _activated = true;
                SaveToDisk(key);
            }
            return valid;
        });
    }

    private bool LoadFromDisk()
    {
        try
        {
            if (!File.Exists(LicenseFile)) return false;
            var data = File.ReadAllText(LicenseFile);
            var doc  = JsonDocument.Parse(data);
            return doc.RootElement.GetProperty("activated").GetBoolean();
        }
        catch { return false; }
    }

    private void SaveToDisk(string key)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LicenseFile)!);
            var json = JsonSerializer.Serialize(new { activated = true, key });
            File.WriteAllText(LicenseFile, json);
        }
        catch { }
    }
}
