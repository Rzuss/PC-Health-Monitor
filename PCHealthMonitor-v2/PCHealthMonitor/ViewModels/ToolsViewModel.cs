using PCHealthMonitor.Helpers;
using PCHealthMonitor.Services;
using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows.Input;

namespace PCHealthMonitor.ViewModels;

public sealed class ToolsViewModel : BaseViewModel
{
    private readonly DriverService        _driver;
    private readonly SchedulerService     _scheduler;
    private readonly ProFeatureService    _pro;
    private readonly HardwareService      _hardware;
    private readonly MetricsHistoryService _history;
    private readonly ReportService        _report;
    private readonly ToastService         _toast;

    public ToolsViewModel(
        DriverService        driver,
        SchedulerService     scheduler,
        ProFeatureService    pro,
        HardwareService      hardware,
        MetricsHistoryService history,
        ReportService        report,
        ToastService         toast)
    {
        _driver   = driver;
        _scheduler = scheduler;
        _pro      = pro;
        _hardware = hardware;
        _history  = history;
        _report   = report;
        _toast    = toast;

        ScanDriversCommand    = new AsyncRelayCommand(ScanDriversAsync,   () => !IsBusy);
        SaveScheduleCommand   = new AsyncRelayCommand(SaveScheduleAsync);
        DeleteScheduleCommand = new AsyncRelayCommand(DeleteScheduleAsync);
        ExportCsvCommand      = new AsyncRelayCommand(ExportCsvAsync);
        ExportHtmlCommand     = new AsyncRelayCommand(ExportHtmlAsync);
    }

    public ICommand ScanDriversCommand    { get; }
    public ICommand SaveScheduleCommand   { get; }
    public ICommand DeleteScheduleCommand { get; }
    public ICommand ExportCsvCommand      { get; }
    public ICommand ExportHtmlCommand     { get; }

    // ── Pro visibility ────────────────────────────────────────────────────────
    public bool IsPro => _pro.IsPro;

    /// <summary>Fired when a Pro-gated action is attempted by a free user.</summary>
    public event EventHandler? ProUpgradeRequested;

    // ── Driver Audit ─────────────────────────────────────────────────────────
    public ObservableCollection<DriverEntry> FlaggedDrivers { get; } = new();

    private bool _isBusy;
    public bool IsBusy { get => _isBusy; set { SetProperty(ref _isBusy, value); AsyncRelayCommand.RaiseCanExecuteChanged(); } }

    private string _driverStatus = "Click Scan to audit installed drivers";
    public string DriverStatus { get => _driverStatus; set => SetProperty(ref _driverStatus, value); }

    private async Task ScanDriversAsync()
    {
        IsBusy = true;
        DriverStatus = "Scanning drivers...";
        FlaggedDrivers.Clear();

        var drivers = await _driver.GetFlaggedDriversAsync();
        foreach (var d in drivers) FlaggedDrivers.Add(d);

        DriverStatus = FlaggedDrivers.Count > 0
            ? $"{FlaggedDrivers.Count} driver(s) need attention"
            : "All drivers are up to date";

        IsBusy = false;
    }

    // ── Auto-Schedule (Pro gated) ─────────────────────────────────────────────
    private bool _scheduleEnabled;
    public bool ScheduleEnabled { get => _scheduleEnabled; set => SetProperty(ref _scheduleEnabled, value); }

    // ScheduleIntervalDays stays int for the service call
    private int _scheduleIntervalDays = 7;
    public int ScheduleIntervalDays
    {
        get => _scheduleIntervalDays;
        set => SetProperty(ref _scheduleIntervalDays, value);
    }

    // String-based option that the ComboBox Tag binding can use
    public string ScheduleIntervalOption
    {
        get => _scheduleIntervalDays.ToString();
        set
        {
            if (int.TryParse(value, out int days))
            {
                _scheduleIntervalDays = days;
                OnPropertyChanged(nameof(ScheduleIntervalDays));
                OnPropertyChanged(nameof(ScheduleIntervalOption));
            }
        }
    }

    private string _scheduleTime = "02:00";
    public string ScheduleTime { get => _scheduleTime; set => SetProperty(ref _scheduleTime, value); }

    private string _scheduleStatus = "No schedule configured";
    public string ScheduleStatus { get => _scheduleStatus; set => SetProperty(ref _scheduleStatus, value); }

    private async Task SaveScheduleAsync()
    {
        if (!_pro.CanUse(ProFeature.ScheduledCleanup))
        {
            ProUpgradeRequested?.Invoke(this, EventArgs.Empty);
            return;
        }
        await _scheduler.SaveCleanupScheduleAsync(ScheduleEnabled, ScheduleIntervalDays, ScheduleTime);
        ScheduleStatus = ScheduleEnabled
            ? $"Scheduled: every {ScheduleIntervalDays} day(s) at {ScheduleTime}"
            : "Schedule disabled";
    }

    private async Task DeleteScheduleAsync()
    {
        await _scheduler.DeleteCleanupScheduleAsync();
        ScheduleEnabled = false;
        ScheduleStatus  = "Schedule removed";
    }

    // ── Export (Pro gated) ────────────────────────────────────────────────────
    private string _exportStatus = string.Empty;
    public string ExportStatus { get => _exportStatus; set => SetProperty(ref _exportStatus, value); }

    private async Task ExportCsvAsync()
    {
        if (!_pro.CanUse(ProFeature.ExportReports))
        {
            ProUpgradeRequested?.Invoke(this, EventArgs.Empty);
            return;
        }

        try
        {
            ExportStatus = "Generating CSV…";
            var snap    = _hardware.Latest;
            var histPts = _history.GetHistory(hours: 24);
            var path    = await _report.GenerateCsvReportAsync(snap, histPts);
            ExportStatus = $"Saved: {System.IO.Path.GetFileName(path)}";
            _toast.Success($"CSV report saved to Documents\\PCHealthMonitor\\Reports");
            ReportService.OpenFile(path);
        }
        catch (Exception ex)
        {
            ExportStatus = $"Export failed: {ex.Message}";
        }
    }

    private async Task ExportHtmlAsync()
    {
        if (!_pro.CanUse(ProFeature.ExportReports))
        {
            ProUpgradeRequested?.Invoke(this, EventArgs.Empty);
            return;
        }

        try
        {
            ExportStatus = "Generating report…";
            var snap    = _hardware.Latest;
            var histPts = _history.GetHistory(hours: 24);
            var path    = await _report.GenerateHtmlReportAsync(snap, histPts);
            ExportStatus = $"Opened: {System.IO.Path.GetFileName(path)}";
            _toast.Success("HTML report opened in browser. Press Ctrl+P to save as PDF.");
            ReportService.OpenFile(path);
        }
        catch (Exception ex)
        {
            ExportStatus = $"Export failed: {ex.Message}";
        }
    }
}

public sealed class DriverEntry
{
    public string Name        { get; init; } = string.Empty;
    public string Version     { get; init; } = string.Empty;
    public string Date        { get; init; } = string.Empty;
    public string Status      { get; init; } = string.Empty;
    public string DeviceClass { get; init; } = string.Empty;
}
