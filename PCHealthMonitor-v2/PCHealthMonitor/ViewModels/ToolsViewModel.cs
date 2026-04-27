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

        HourUpCommand   = new RelayCommand(() => ScheduleHour   += 1);
        HourDownCommand = new RelayCommand(() => ScheduleHour   -= 1);
        MinUpCommand    = new RelayCommand(() => ScheduleMinute += 5);
        MinDownCommand  = new RelayCommand(() => ScheduleMinute -= 5);
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

    // Frequency tile options
    public static IReadOnlyList<FrequencyOption> FrequencyOptions { get; } =
    [
        new("Daily",         "Every day",             1),
        new("Every 3 Days",  "Every 3 days",          3),
        new("Weekly",        "Once a week",           7),
        new("Biweekly",      "Every 2 weeks",        14),
        new("Monthly",       "Once a month",         30),
    ];

    private FrequencyOption _selectedFrequency = FrequencyOptions[2]; // Weekly default
    public FrequencyOption SelectedFrequency
    {
        get => _selectedFrequency;
        set
        {
            SetProperty(ref _selectedFrequency, value);
            if (value is not null) _scheduleIntervalDays = value.Days;
        }
    }

    private int _scheduleIntervalDays = 7;   // kept for service call
    public int ScheduleIntervalDays => _scheduleIntervalDays;

    // ── Clock spinners ─────────────────────────────────────────────────────────
    private int _scheduleHour   = 2;
    private int _scheduleMinute = 0;

    public int ScheduleHour
    {
        get => _scheduleHour;
        set { _scheduleHour = ((value % 24) + 24) % 24; OnPropertyChanged(nameof(ScheduleHour)); OnPropertyChanged(nameof(ScheduleTimeDisplay)); }
    }
    public int ScheduleMinute
    {
        get => _scheduleMinute;
        set { _scheduleMinute = ((value % 60) + 60) % 60; OnPropertyChanged(nameof(ScheduleMinute)); OnPropertyChanged(nameof(ScheduleTimeDisplay)); }
    }

    public string ScheduleTimeDisplay => $"{_scheduleHour:D2}:{_scheduleMinute:D2}";

    // kept for service compatibility
    private string ScheduleTime => ScheduleTimeDisplay;

    public ICommand HourUpCommand    { get; }
    public ICommand HourDownCommand  { get; }
    public ICommand MinUpCommand     { get; }
    public ICommand MinDownCommand   { get; }

    private string _scheduleStatus = "No schedule configured";
    public string ScheduleStatus { get => _scheduleStatus; set => SetProperty(ref _scheduleStatus, value); }

    private async Task SaveScheduleAsync()
    {
        if (!_pro.CanUse(ProFeature.ScheduledCleanup))
        {
            ProUpgradeRequested?.Invoke(this, EventArgs.Empty);
            return;
        }
        await _scheduler.SaveCleanupScheduleAsync(ScheduleEnabled, ScheduleIntervalDays, ScheduleTimeDisplay);
        ScheduleStatus = ScheduleEnabled
            ? $"Active — {SelectedFrequency?.Label ?? "Weekly"} at {ScheduleTimeDisplay}"
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

public sealed record FrequencyOption(string Label, string Subtitle, int Days);
