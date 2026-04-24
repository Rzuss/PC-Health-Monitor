using PCHealthMonitor.Helpers;
using PCHealthMonitor.Services;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows.Input;

namespace PCHealthMonitor.ViewModels;

public sealed class ToolsViewModel : BaseViewModel
{
    private readonly DriverService    _driver;
    private readonly SchedulerService _scheduler;

    public ToolsViewModel(DriverService driver, SchedulerService scheduler)
    {
        _driver    = driver;
        _scheduler = scheduler;

        ScanDriversCommand    = new AsyncRelayCommand(ScanDriversAsync,  () => !IsBusy);
        SaveScheduleCommand   = new RelayCommand(SaveSchedule);
        DeleteScheduleCommand = new AsyncRelayCommand(DeleteScheduleAsync);
    }

    public ICommand ScanDriversCommand    { get; }
    public ICommand SaveScheduleCommand   { get; }
    public ICommand DeleteScheduleCommand { get; }

    // ── Driver Audit ─────────────────────────────────────────────────────
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

    // ── Auto-Schedule ────────────────────────────────────────────────────
    private bool _scheduleEnabled;
    public bool ScheduleEnabled { get => _scheduleEnabled; set => SetProperty(ref _scheduleEnabled, value); }

    private int _scheduleIntervalDays = 7;
    public int ScheduleIntervalDays
    {
        get => _scheduleIntervalDays;
        set => SetProperty(ref _scheduleIntervalDays, value);
    }

    private string _scheduleTime = "02:00";
    public string ScheduleTime { get => _scheduleTime; set => SetProperty(ref _scheduleTime, value); }

    private string _scheduleStatus = "No schedule configured";
    public string ScheduleStatus { get => _scheduleStatus; set => SetProperty(ref _scheduleStatus, value); }

    private void SaveSchedule()
    {
        _scheduler.SaveCleanupSchedule(ScheduleEnabled, ScheduleIntervalDays, ScheduleTime);
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
}

public sealed class DriverEntry
{
    public string Name        { get; init; } = string.Empty;
    public string Version     { get; init; } = string.Empty;
    public string Date        { get; init; } = string.Empty;
    public string Status      { get; init; } = string.Empty;  // Outdated / Aging
    public string DeviceClass { get; init; } = string.Empty;
}
