using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace PCHealthMonitor.Services;

// ─────────────────────────────────────────────────────────────────────────────
// LicenseService — Gumroad API validation + DPAPI-encrypted local cache
//
// Activation flow:
//   1. User enters license key → ActivateAsync(key)
//   2. Call Gumroad /v2/licenses/verify with product_id + key
//   3. On success → encrypt {key, email, activatedAt} with DPAPI → disk
//   4. On startup → load from disk; if ≤ 7 days since last online check → trust cache
//   5. If > 7 days → re-verify online silently; if offline → keep cache valid
//
// SETUP REQUIRED:
//   Replace GumroadProductId with the short ID from your Gumroad product URL.
//   Example: https://rzuss.gumroad.com/l/ABCDE  →  GumroadProductId = "ABCDE"
// ─────────────────────────────────────────────────────────────────────────────

public sealed class LicenseService
{
    // ── Constants ─────────────────────────────────────────────────────────────
    private const string GumroadProductId  = "PCHM_PRO_PLACEHOLDER"; // ← Replace with real Gumroad product ID
    private const string GumroadVerifyUrl  = "https://api.gumroad.com/v2/licenses/verify";
    private const int    GracePeriodDays   = 7;   // days before requiring online re-check
    private const string AppName           = "PCHealthMonitor";

    // ── Storage ───────────────────────────────────────────────────────────────
    private static readonly string LicenseFile =
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            AppName, "license.dat");

    // ── State ─────────────────────────────────────────────────────────────────
    private LicenseData? _data;

    public bool     IsActivated  => _data?.Activated == true;
    public string   LicenseEmail => _data?.Email     ?? string.Empty;
    public string   LicenseKey   => _data?.Key       ?? string.Empty;
    public DateTime? ActivatedAt => _data?.ActivatedAt;

    /// Raised on activation or deactivation so UI components can update live.
    public event EventHandler<bool>? ProStatusChanged;

    // ── Constructor ───────────────────────────────────────────────────────────
    public LicenseService()
    {
        _data = LoadFromDisk();
    }

    // ── Startup background re-check ───────────────────────────────────────────
    /// Call once at startup (fire-and-forget OK). Silently re-verifies if grace
    /// period has passed; updates disk cache on success; on failure keeps cache.
    public async Task RefreshAsync()
    {
        if (_data is null || !_data.Activated) return;

        var daysSinceCheck = (DateTime.UtcNow - _data.LastOnlineCheckUtc).TotalDays;
        if (daysSinceCheck < GracePeriodDays) return;  // within grace — no call needed

        try
        {
            var result = await VerifyWithGumroadAsync(_data.Key);
            if (result.Success)
            {
                _data.LastOnlineCheckUtc = DateTime.UtcNow;
                _data.Email              = result.Email;
                SaveToDisk(_data);
            }
            else
            {
                // License was revoked on Gumroad — deactivate
                _data = null;
                ClearDisk();
            }
        }
        catch
        {
            // Offline or API error — keep cached activation; try again next session
        }
    }

    // ── Activate ──────────────────────────────────────────────────────────────
    /// Returns (Success, ErrorMessage). On success, IsActivated becomes true.
    public async Task<(bool Success, string Message)> ActivateAsync(string key)
    {
        key = key.Trim();
        if (string.IsNullOrEmpty(key))
            return (false, "Please enter a license key.");

        try
        {
            var result = await VerifyWithGumroadAsync(key);
            if (!result.Success)
                return (false, result.ErrorMessage ?? "Invalid license key. Please check and try again.");

            _data = new LicenseData
            {
                Activated            = true,
                Key                  = key,
                Email                = result.Email,
                ActivatedAt          = DateTime.UtcNow,
                LastOnlineCheckUtc   = DateTime.UtcNow,
            };
            SaveToDisk(_data);
            ProStatusChanged?.Invoke(this, true);
            return (true, $"Activated! Welcome, {result.Email}");
        }
        catch (HttpRequestException)
        {
            // Fallback: if offline and key looks plausible, grant temporary activation.
            // Gumroad keys are typically 35 chars: XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX
            // We accept any key that is at least 10 chars and contains a hyphen.
            // The key will be verified online on the next launch.
            bool looksValid = key.Length >= 10 && key.Contains('-');
            if (looksValid)
            {
                _data = new LicenseData
                {
                    Activated            = true,
                    Key                  = key,
                    Email                = "Offline Activation",
                    ActivatedAt          = DateTime.UtcNow,
                    LastOnlineCheckUtc   = DateTime.MinValue, // force re-check on next launch
                };
                SaveToDisk(_data);
                ProStatusChanged?.Invoke(this, true);
                return (true, "Activated offline. Will verify online on next launch.");
            }
            return (false, "Could not reach license server. Check your internet connection.");
        }
        catch (Exception ex)
        {
            return (false, $"Activation error: {ex.Message}");
        }
    }

    // ── Deactivate ────────────────────────────────────────────────────────────
    public void Deactivate()
    {
        _data = null;
        ClearDisk();
        ProStatusChanged?.Invoke(this, false);
    }

    // ── Gumroad API ───────────────────────────────────────────────────────────
    private static readonly HttpClient _http = new()
    {
        Timeout = TimeSpan.FromSeconds(10)
    };

    private static async Task<GumroadResult> VerifyWithGumroadAsync(string key)
    {
        var body = new FormUrlEncodedContent(new[]
        {
            new KeyValuePair<string,string>("product_id",             GumroadProductId),
            new KeyValuePair<string,string>("license_key",            key),
            new KeyValuePair<string,string>("increment_uses_count",   "false"),
        });

        using var response = await _http.PostAsync(GumroadVerifyUrl, body);
        var json = await response.Content.ReadAsStringAsync();

        using var doc = JsonDocument.Parse(json);
        var root    = doc.RootElement;
        bool success = root.TryGetProperty("success", out var sp) && sp.GetBoolean();

        if (!success)
        {
            string? msg = null;
            if (root.TryGetProperty("message", out var mp)) msg = mp.GetString();
            return new GumroadResult { Success = false, ErrorMessage = msg };
        }

        string email = string.Empty;
        if (root.TryGetProperty("purchase", out var purchase))
            if (purchase.TryGetProperty("email", out var ep))
                email = ep.GetString() ?? string.Empty;

        return new GumroadResult { Success = true, Email = email };
    }

    // ── Disk persistence (DPAPI encrypted) ────────────────────────────────────
    private static LicenseData? LoadFromDisk()
    {
        try
        {
            if (!File.Exists(LicenseFile)) return null;
            var cipherBytes = File.ReadAllBytes(LicenseFile);
            var plainBytes  = ProtectedData.Unprotect(cipherBytes, null, DataProtectionScope.CurrentUser);
            var json        = Encoding.UTF8.GetString(plainBytes);
            return JsonSerializer.Deserialize<LicenseData>(json);
        }
        catch { return null; }
    }

    private static void SaveToDisk(LicenseData data)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LicenseFile)!);
            var json        = JsonSerializer.Serialize(data);
            var plainBytes  = Encoding.UTF8.GetBytes(json);
            var cipherBytes = ProtectedData.Protect(plainBytes, null, DataProtectionScope.CurrentUser);
            File.WriteAllBytes(LicenseFile, cipherBytes);
        }
        catch { }
    }

    private static void ClearDisk()
    {
        try { if (File.Exists(LicenseFile)) File.Delete(LicenseFile); } catch { }
    }

    // ── Inner types ───────────────────────────────────────────────────────────
    private sealed class LicenseData
    {
        public bool     Activated            { get; set; }
        public string   Key                  { get; set; } = string.Empty;
        public string   Email                { get; set; } = string.Empty;
        public DateTime ActivatedAt          { get; set; }
        public DateTime LastOnlineCheckUtc   { get; set; }
    }

    private sealed class GumroadResult
    {
        public bool    Success      { get; set; }
        public string  Email        { get; set; } = string.Empty;
        public string? ErrorMessage { get; set; }
    }
}
