using PCHealthMonitor.Helpers;
using PCHealthMonitor.Services;
using System.Threading.Tasks;
using System.Windows.Input;

namespace PCHealthMonitor.ViewModels;

public sealed class SettingsViewModel : BaseViewModel
{
    private readonly SettingsService _settings;
    private readonly LicenseService  _license;

    public SettingsViewModel(SettingsService settings, LicenseService license)
    {
        _settings = settings;
        _license  = license;

        SaveCommand    = new RelayCommand(Save);
        ActivateCommand = new AsyncRelayCommand(ActivateAsync, () => !IsBusy && !string.IsNullOrWhiteSpace(LicenseKey));
        ResetCommand   = new RelayCommand(Reset);

        LoadFromSettings();
    }

    public ICommand SaveCommand     { get; }
    public ICommand ActivateCommand { get; }
    public ICommand ResetCommand    { get; }

    // ── General settings ──────────────────────────────────────────────────
    private bool _startWithWindows;
    public bool StartWithWindows { get => _startWithWindows; set => SetProperty(ref _startWithWindows, value); }

    private bool _minimizeToTray = true;
    public bool MinimizeToTray { get => _minimizeToTray; set => SetProperty(ref _minimizeToTray, value); }

    private bool _showNotifications = true;
    public bool ShowNotifications { get => _showNotifications; set => SetProperty(ref _showNotifications, value); }

    private int _scanIntervalHours = 24;
    public int ScanIntervalHours { get => _scanIntervalHours; set => SetProperty(ref _scanIntervalHours, value); }

    // ── License ───────────────────────────────────────────────────────────
    private bool _isActivated;
    public bool IsActivated { get => _isActivated; set => SetProperty(ref _isActivated, value); }

    private bool _isBusy;
    public bool IsBusy { get => _isBusy; set { SetProperty(ref _isBusy, value); AsyncRelayCommand.RaiseCanExecuteChanged(); } }

    private string _licenseKey = string.Empty;
    public string LicenseKey
    {
        get => _licenseKey;
        set { SetProperty(ref _licenseKey, value); AsyncRelayCommand.RaiseCanExecuteChanged(); }
    }

    private string _licenseStatus = string.Empty;
    public string LicenseStatus { get => _licenseStatus; set => SetProperty(ref _licenseStatus, value); }

    // ── App info ──────────────────────────────────────────────────────────
    public string Version     => "2.0.0";
    public string AppName     => "PC Health Monitor";
    public string CopyrightTxt => "© 2025 Rotem. All rights reserved.";

    // ── Commands ──────────────────────────────────────────────────────────
    private void Save()
    {
        _settings.Save(new AppSettings
        {
            StartWithWindows  = StartWithWindows,
            MinimizeToTray    = MinimizeToTray,
            ShowNotifications = ShowNotifications,
            ScanIntervalHours = ScanIntervalHours
        });
        LicenseStatus = "Settings saved.";
    }

    private async Task ActivateAsync()
    {
        IsBusy = true;
        LicenseStatus = "Validating license...";

        bool ok = await _license.ActivateAsync(LicenseKey.Trim());
        IsActivated   = ok;
        LicenseStatus = ok ? "Pro activated — thank you!" : "Invalid license key. Please try again.";
        IsBusy = false;
    }

    private void Reset()
    {
        _settings.Reset();
        LoadFromSettings();
        LicenseStatus = "Settings restored to defaults.";
    }

    private void LoadFromSettings()
    {
        var s = _settings.Load();
        StartWithWindows  = s.StartWithWindows;
        MinimizeToTray    = s.MinimizeToTray;
        ShowNotifications = s.ShowNotifications;
        ScanIntervalHours = s.ScanIntervalHours;
        IsActivated       = _license.IsActivated;
    }
}
