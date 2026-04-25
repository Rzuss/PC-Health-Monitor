using PCHealthMonitor.Helpers;
using PCHealthMonitor.Services;
using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows.Input;
using System.Windows.Threading;

namespace PCHealthMonitor.ViewModels;

public sealed class BoostViewModel : BaseViewModel, IDisposable
{
    private readonly BoostService  _boost;
    private DispatcherTimer?       _vipTimer;
    private DateTime               _vipExpiry;

    public BoostViewModel(BoostService boost)
    {
        _boost = boost;

        RefreshCommand    = new AsyncRelayCommand(RefreshProcessesAsync, () => !IsBusy);
        ActivateCommand   = new AsyncRelayCommand(ActivateAsync,
                                () => !IsVipActive && !IsBusy && SelectedProcess is not null);
        DeactivateCommand = new RelayCommand(Deactivate, () => IsVipActive);
    }

    // ── Commands ──────────────────────────────────────────────────────────
    public ICommand RefreshCommand    { get; }
    public ICommand ActivateCommand   { get; }
    public ICommand DeactivateCommand { get; }

    // ── Process list ──────────────────────────────────────────────────────
    public ObservableCollection<ProcessEntry> Processes { get; } = new();

    private ProcessEntry? _selectedProcess;
    public ProcessEntry? SelectedProcess
    {
        get => _selectedProcess;
        set
        {
            SetProperty(ref _selectedProcess, value);
            AsyncRelayCommand.RaiseCanExecuteChanged();
        }
    }

    // ── State ─────────────────────────────────────────────────────────────
    private bool _isVipActive;
    public bool IsVipActive
    {
        get => _isVipActive;
        set { SetProperty(ref _isVipActive, value); AsyncRelayCommand.RaiseCanExecuteChanged(); }
    }

    private bool _isBusy;
    public bool IsBusy
    {
        get => _isBusy;
        set { SetProperty(ref _isBusy, value); AsyncRelayCommand.RaiseCanExecuteChanged(); }
    }

    private string _vipStatus = "Select a process below, then click Activate";
    public string VipStatus { get => _vipStatus; set => SetProperty(ref _vipStatus, value); }

    private string _activeProcessName = "";
    public string ActiveProcessName { get => _activeProcessName; set => SetProperty(ref _activeProcessName, value); }

    private string _timeRemaining = string.Empty;
    public string TimeRemaining { get => _timeRemaining; set => SetProperty(ref _timeRemaining, value); }

    private int _boostDurationMin = 30;
    public int BoostDurationMin
    {
        get => _boostDurationMin;
        set => SetProperty(ref _boostDurationMin, Math.Clamp(value, 5, 120));
    }

    private string _statusMessage = "";
    public string StatusMessage { get => _statusMessage; set => SetProperty(ref _statusMessage, value); }

    // ── Load process list ─────────────────────────────────────────────────
    private async Task RefreshProcessesAsync()
    {
        IsBusy = true;
        StatusMessage = "Scanning running processes...";

        var procs = await _boost.GetBoostableProcessesAsync();

        Processes.Clear();
        foreach (var p in procs)
            Processes.Add(p);

        StatusMessage = $"{Processes.Count} processes found";
        IsBusy = false;
    }

    // ── Activate boost for selected process ───────────────────────────────
    private async Task ActivateAsync()
    {
        if (SelectedProcess is null) return;

        IsBusy = true;
        var target = SelectedProcess;

        await _boost.BoostProcessAsync(target.Pid);

        _vipExpiry        = DateTime.Now.AddMinutes(BoostDurationMin);
        IsVipActive       = true;
        ActiveProcessName = target.DisplayName;
        VipStatus         = $"Boosting \"{target.DisplayName}\" to HIGH priority";

        _vipTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _vipTimer.Tick += (_, _) =>
        {
            var rem = _vipExpiry - DateTime.Now;
            if (rem <= TimeSpan.Zero)
            {
                Deactivate();
                return;
            }
            TimeRemaining = $"{(int)rem.TotalMinutes:00}:{rem.Seconds:00} remaining";
        };
        _vipTimer.Start();
        IsBusy = false;
    }

    // ── Deactivate ────────────────────────────────────────────────────────
    private void Deactivate()
    {
        _vipTimer?.Stop();
        _vipTimer = null;
        _boost.Deactivate();
        IsVipActive       = false;
        ActiveProcessName = "";
        VipStatus         = "Select a process below, then click Activate";
        TimeRemaining     = string.Empty;
        AsyncRelayCommand.RaiseCanExecuteChanged();
    }

    // ── Init: auto-load on first use ──────────────────────────────────────
    public async Task InitAsync()
    {
        if (Processes.Count == 0)
            await RefreshProcessesAsync();
    }

    public void Dispose()
    {
        _vipTimer?.Stop();
        if (IsVipActive) _boost.Deactivate();
    }
}
