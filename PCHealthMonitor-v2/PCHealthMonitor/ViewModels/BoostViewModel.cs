using PCHealthMonitor.Helpers;
using PCHealthMonitor.Services;
using System;
using System.Threading.Tasks;
using System.Windows.Input;
using System.Windows.Threading;

namespace PCHealthMonitor.ViewModels;

public sealed class BoostViewModel : BaseViewModel, IDisposable
{
    private readonly BoostService _boost;
    private DispatcherTimer?      _vipTimer;
    private DateTime              _vipExpiry;

    public BoostViewModel(BoostService boost)
    {
        _boost          = boost;
        ActivateCommand = new AsyncRelayCommand(ActivateAsync, () => !IsVipActive && !IsBusy);
        DeactivateCommand = new RelayCommand(Deactivate, () => IsVipActive);
    }

    public ICommand ActivateCommand   { get; }
    public ICommand DeactivateCommand { get; }

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

    private string _vipStatus = "No VIP session active";
    public string VipStatus { get => _vipStatus; set => SetProperty(ref _vipStatus, value); }

    private string _timeRemaining = string.Empty;
    public string TimeRemaining { get => _timeRemaining; set => SetProperty(ref _timeRemaining, value); }

    private int _boostDurationMin = 30;
    public int BoostDurationMin
    {
        get => _boostDurationMin;
        set => SetProperty(ref _boostDurationMin, Math.Clamp(value, 10, 120));
    }

    private async Task ActivateAsync()
    {
        IsBusy = true;
        await _boost.ActivateAsync(BoostDurationMin);
        _vipExpiry = DateTime.Now.AddMinutes(BoostDurationMin);
        IsVipActive = true;
        VipStatus   = $"VIP session active — boosted for {BoostDurationMin} min";

        _vipTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _vipTimer.Tick += (_, _) =>
        {
            var rem = _vipExpiry - DateTime.Now;
            if (rem <= TimeSpan.Zero)
            {
                Deactivate();
                return;
            }
            TimeRemaining = $"{rem.Minutes:00}:{rem.Seconds:00} remaining";
        };
        _vipTimer.Start();
        IsBusy = false;
    }

    private void Deactivate()
    {
        _vipTimer?.Stop();
        _boost.Deactivate();
        IsVipActive   = false;
        VipStatus     = "VIP session ended";
        TimeRemaining = string.Empty;
    }

    public void Dispose()
    {
        _vipTimer?.Stop();
        if (IsVipActive) _boost.Deactivate();
    }
}
