using System;

namespace PCHealthMonitor.Services;

// ─────────────────────────────────────────────────────────────────────────────
// ProFeatureService — feature gate abstraction for the Freemium model.
//
// Usage (in any ViewModel):
//   if (_pro.CanUse(ProFeature.HistoricalCharts)) { ... }
//   _pro.RequirePro(ProFeature.ExportReports);   // throws ProRequiredException
//
// All four Pro features are gated here so the UI and business logic never
// need to know about license keys directly — only about capabilities.
// ─────────────────────────────────────────────────────────────────────────────

public enum ProFeature
{
    HistoricalCharts,   // 24h / 7d / 30d CPU, RAM, Disk history graphs
    ScheduledCleanup,   // Windows Task Scheduler auto-cleanup
    ExportReports,      // PDF / CSV system health reports
    CustomAlerts,       // Toast when CPU/RAM exceeds user-defined threshold %
}

public sealed class ProFeatureService
{
    private readonly LicenseService _license;

    public ProFeatureService(LicenseService license)
        => _license = license;

    // ── Status ────────────────────────────────────────────────────────────────
    public bool IsPro => _license.IsActivated;

    /// Returns true if the user may use this feature.
    public bool CanUse(ProFeature feature) => IsPro;   // all features require Pro

    // ── Guard helper ──────────────────────────────────────────────────────────
    /// Throws <see cref="ProRequiredException"/> if the user is not on Pro.
    /// Use this at the start of Pro-only operations so the caller gets a clear,
    /// typed exception it can catch and route to the upgrade UI.
    public void RequirePro(ProFeature feature)
    {
        if (!IsPro) throw new ProRequiredException(feature);
    }

    // ── Feature metadata (for UI labels / upgrade prompts) ───────────────────
    public static string GetDisplayName(ProFeature feature) => feature switch
    {
        ProFeature.HistoricalCharts  => "Historical Charts",
        ProFeature.ScheduledCleanup  => "Scheduled Cleanup",
        ProFeature.ExportReports     => "PDF / CSV Export",
        ProFeature.CustomAlerts      => "Custom Alerts",
        _ => feature.ToString()
    };

    public static string GetDescription(ProFeature feature) => feature switch
    {
        ProFeature.HistoricalCharts  => "View 24h, 7-day, and 30-day graphs for CPU, RAM, and Disk",
        ProFeature.ScheduledCleanup  => "Automatically clean junk files on a schedule you define",
        ProFeature.ExportReports     => "Export a full system health report as PDF or CSV",
        ProFeature.CustomAlerts      => "Get a notification when CPU or RAM exceeds your threshold",
        _ => string.Empty
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// ProRequiredException — thrown by ProFeatureService.RequirePro()
// ViewModels catch this and navigate to the upgrade / activation dialog.
// ─────────────────────────────────────────────────────────────────────────────
public sealed class ProRequiredException : Exception
{
    public ProFeature Feature { get; }

    public ProRequiredException(ProFeature feature)
        : base($"PC Health Monitor Pro is required to use {ProFeatureService.GetDisplayName(feature)}.")
        => Feature = feature;
}
