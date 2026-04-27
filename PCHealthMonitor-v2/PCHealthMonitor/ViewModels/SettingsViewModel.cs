using Microsoft.Win32;
using PCHealthMonitor.Helpers;
using PCHealthMonitor.Services;
using System;
using System.Diagnostics;
using System.Reflection;
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

        SaveCommand       = new RelayCommand(Save);
        ActivateCommand   = new AsyncRelayCommand(ActivateAsync, () => !IsBusy && !string.IsNullOrWhiteSpace(LicenseKey));
        DeactivateCommand = new RelayCommand(Deactivate, () => IsActivated);
        ResetCommand      = new RelayCommand(Reset);

        LoadFromSettings();
    }

    public ICommand SaveCommand       { get; }
    public ICommand ActivateCommand   { get; }
    public ICommand DeactivateCommand { get; }
    public ICommand ResetCommand      { get; }

    // ── Pro visibility ────────────────────────────────────────────────────
    public bool IsPro => _license.IsActivated;

    /// <summary>Fired when a Pro-gated Save is attempted by a free user.</summary>
    public event EventHandler? ProUpgradeRequested;

    // ── General settings ──────────────────────────────────────────────────
    private bool _startWithWindows;
    public bool StartWithWindows { get => _startWithWindows; set => SetProperty(ref _startWithWindows, value); }

    private bool _minimizeToTray = true;
    public bool MinimizeToTray { get => _minimizeToTray; set => SetProperty(ref _minimizeToTray, value); }

    private bool _showNotifications = true;
    public bool ShowNotifications { get => _showNotifications; set => SetProperty(ref _showNotifications, value); }

    private int _scanIntervalHours = 24;
    public int ScanIntervalHours { get => _scanIntervalHours; set => SetProperty(ref _scanIntervalHours, value); }

    // ── Pro: Custom alert thresholds ──────────────────────────────────────
    // 0 = disabled. Set to 1-100 to enable.
    private int _cpuAlertThreshold;
    public int CpuAlertThreshold { get => _cpuAlertThreshold; set => SetProperty(ref _cpuAlertThreshold, value); }

    private int _ramAlertThreshold;
    public int RamAlertThreshold { get => _ramAlertThreshold; set => SetProperty(ref _ramAlertThreshold, value); }

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
    public string LicenseStatus
    {
        get => _licenseStatus;
        set
        {
            SetProperty(ref _licenseStatus, value);
            // Treat status as error if it does NOT start with a success phrase
            LicenseStatusIsError = !string.IsNullOrEmpty(value)
                && !value.StartsWith("Activated",      StringComparison.OrdinalIgnoreCase)
                && !value.StartsWith("Settings saved", StringComparison.OrdinalIgnoreCase)
                && !value.StartsWith("Settings rest",  StringComparison.OrdinalIgnoreCase)
                && !value.StartsWith("Validating",     StringComparison.OrdinalIgnoreCase);
        }
    }

    private bool _licenseStatusIsError;
    public bool LicenseStatusIsError { get => _licenseStatusIsError; set => SetProperty(ref _licenseStatusIsError, value); }

    // ── App info (read from assembly metadata — always in sync with .csproj) ─
    public string Version      => Assembly.GetExecutingAssembly()
                                          .GetName().Version?.ToString(3) ?? "2.0.0";
    public string AppName      => "PC Health Monitor";
    public string CopyrightTxt => "© 2026 Rotem Zussman. All rights reserved.";

    // ── Commands ──────────────────────────────────────────────────────────
    private void Save()
    {
        // Gate: alert thresholds are Pro-only — intercept if free user tries to set them
        if (!IsPro && (CpuAlertThreshold > 0 || RamAlertThreshold > 0))
        {
            CpuAlertThreshold = 0;
            RamAlertThreshold = 0;
            ProUpgradeRequested?.Invoke(this, EventArgs.Empty);
            return;
        }

        var existing = _settings.Load();
        _settings.Save(new AppSettings
        {
            StartWithWindows   = StartWithWindows,
            MinimizeToTray     = MinimizeToTray,
            ShowNotifications  = ShowNotifications,
            ScanIntervalHours  = ScanIntervalHours,
            CpuAlertThreshold  = CpuAlertThreshold,
            RamAlertThreshold  = RamAlertThreshold,
            // preserve geometry
            WindowLeft  = existing.WindowLeft,
            WindowTop   = existing.WindowTop,
            WindowWidth = existing.WindowWidth,
            WindowHeight= existing.WindowHeight,
        });

        // Apply "Start with Windows" to the registry immediately
        ApplyStartWithWindows(StartWithWindows);

        LicenseStatus = "Settings saved.";
    }

    private async Task ActivateAsync()
    {
        IsBusy = true;
        LicenseStatus = "Validating license...";

        var (ok, msg) = await _license.ActivateAsync(LicenseKey.Trim());
        IsActivated   = ok;
        LicenseStatus = msg;
        IsBusy = false;
    }

    private void Deactivate()
    {
        _license.Deactivate();
        IsActivated   = false;
        LicenseKey    = string.Empty;
        LicenseStatus = "License removed. You are now on the Free plan.";
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
        StartWithWindows   = s.StartWithWindows;
        MinimizeToTray     = s.MinimizeToTray;
        ShowNotifications  = s.ShowNotifications;
        ScanIntervalHours  = s.ScanIntervalHours;
        CpuAlertThreshold  = s.CpuAlertThreshold;
        RamAlertThreshold  = s.RamAlertThreshold;
        IsActivated        = _license.IsActivated;
    }

    // ── Registry: Start with Windows ─────────────────────────────────────────
    private const string RunKey    = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
    private const string AppRegKey = "PCHealthMonitor";

    private static void ApplyStartWithWindows(bool enable)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
            if (key is null) return;

            if (enable)
            {
                // Store the full path in quotes so paths with spaces work
                var exePath = Process.GetCurrentProcess().MainModule?.FileName ?? string.Empty;
                if (!string.IsNullOrEmpty(exePath))
                    key.SetValue(AppRegKey, $"\"{exePath}\"");
            }
            else
            {
                key.DeleteValue(AppRegKey, throwOnMissingValue: false);
            }
        }
        catch { /* insufficient permissions — fail silently */ }
    }
}
