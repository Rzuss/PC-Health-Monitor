using System;
using System.Collections.Generic;

namespace PCHealthMonitor.Services;

// ─────────────────────────────────────────────────────────────────────────────
// AlertService — fires toast notifications when CPU or RAM exceeds
// user-defined thresholds.
//
// Throttle: one toast per metric per 5 minutes maximum, so the user
// isn't flooded when the system is under sustained load.
// All checks are passive — no CPU impact, no background thread needed.
// ─────────────────────────────────────────────────────────────────────────────

public sealed class AlertService
{
    private readonly SettingsService  _settings;
    private readonly ToastService     _toast;
    private readonly ProFeatureService _pro;

    // Track last alert time per metric key to throttle notifications
    private readonly Dictionary<string, DateTime> _lastAlerted = new();
    private static readonly TimeSpan ThrottleWindow = TimeSpan.FromMinutes(5);

    public AlertService(SettingsService settings, ToastService toast, ProFeatureService pro)
    {
        _settings = settings;
        _toast    = toast;
        _pro      = pro;
    }

    /// Call from HardwareService.SnapshotUpdated (or DashboardViewModel.Poll).
    /// No-op if the user is not on Pro or has not configured thresholds.
    public void Evaluate(HardwareSnapshot snap)
    {
        if (!_pro.IsPro) return;

        var s = _settings.Load();

        if (s.CpuAlertThreshold > 0 && snap.CpuLoad >= s.CpuAlertThreshold)
            FireIfNotThrottled("cpu",
                $"CPU usage is at {snap.CpuLoad:0}% (threshold: {s.CpuAlertThreshold}%)",
                ToastType.Warning);

        if (s.RamAlertThreshold > 0 && snap.RamLoad >= s.RamAlertThreshold)
            FireIfNotThrottled("ram",
                $"RAM usage is at {snap.RamLoad}% (threshold: {s.RamAlertThreshold}%)",
                ToastType.Warning);
    }

    // ── Internal ──────────────────────────────────────────────────────────────
    private void FireIfNotThrottled(string key, string message, ToastType type)
    {
        var now = DateTime.Now;
        if (_lastAlerted.TryGetValue(key, out var last) && now - last < ThrottleWindow)
            return;

        _lastAlerted[key] = now;
        _toast.Show(message, type, durationMs: 6_000);
    }
}
