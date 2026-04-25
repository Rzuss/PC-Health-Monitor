using Hardcodet.Wpf.TaskbarNotification;
using Microsoft.Extensions.DependencyInjection;
using PCHealthMonitor.Services;
using PCHealthMonitor.ViewModels;
using PCHealthMonitor.Views.Dashboard;
using PCHealthMonitor.Views.Startup;
using PCHealthMonitor.Views.JunkCleaner;
using PCHealthMonitor.Views.Storage;
using PCHealthMonitor.Views.Boost;
using PCHealthMonitor.Views.DiskHealth;
using PCHealthMonitor.Views.Tools;
using PCHealthMonitor.Views.Network;
using PCHealthMonitor.Views.Settings;
using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace PCHealthMonitor;

public partial class MainWindow : Window
{
    private readonly MainViewModel    _vm;
    private readonly LicenseService  _license;
    private readonly HardwareService _hardware;
    private TaskbarIcon?             _trayIcon;
    private bool                     _isMaximized;

    // ─── Constructor ──────────────────────────────────────────────────────
    public MainWindow(MainViewModel vm, LicenseService license, HardwareService hardware)
    {
        InitializeComponent();

        _vm       = vm;
        _license  = license;
        _hardware = hardware;
        DataContext = vm;

        // Initialize tray icon
        _trayIcon = (TaskbarIcon)FindResource("TrayIcon");

        // Wire hardware updates to status bar
        _hardware.SnapshotUpdated += OnSnapshotUpdated;

        // Navigate to Dashboard on load
        Loaded += (_, _) =>
        {
            NavigateTo("Dashboard");
            UpdateProBadge();
        };

        Closed += (_, _) => _trayIcon?.Dispose();
    }

    // ─── Hardware snapshot → title bar status ─────────────────────────────
    private void OnSnapshotUpdated(object? sender, HardwareSnapshot snap)
    {
        var text = snap.HealthScore switch
        {
            >= 80 => $"System is healthy  ·  CPU {snap.CpuLoad:0}%  RAM {snap.RamLoad}%",
            >= 60 => $"System is good  ·  CPU {snap.CpuLoad:0}%  RAM {snap.RamLoad}%",
            >= 40 => $"System needs attention  ·  CPU {snap.CpuLoad:0}%",
            _     => $"Performance is degraded  ·  CPU {snap.CpuLoad:0}%"
        };

        if (Dispatcher.CheckAccess())
            StatusText.Text = text;
        else
            Dispatcher.BeginInvoke(() => StatusText.Text = text);
    }

    // ─── Navigation ───────────────────────────────────────────────────────
    private void NavBtn_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn)
            NavigateTo(btn.Tag?.ToString() ?? "Dashboard");
    }

    internal void NavigateTo(string page)
    {
        // Highlight active nav button
        foreach (UIElement el in NavPanel.Children)
        {
            if (el is Button btn)
            {
                bool isActive = btn.Tag?.ToString() == page;
                btn.Foreground = isActive
                    ? (Brush)FindResource("TextBrush")
                    : (Brush)FindResource("SubTextBrush");
                btn.BorderBrush = isActive
                    ? (Brush)FindResource("BlueBrush")
                    : (Brush)FindResource("BorderBrush");
            }
        }

        // Navigate frame to the appropriate Page
        Page? target = page switch
        {
            "Dashboard"   => App.Services.GetRequiredService<DashboardView>()   ?? new DashboardView(),
            "Startup"     => App.Services.GetRequiredService<StartupView>()     ?? new StartupView(),
            "JunkCleaner" => App.Services.GetRequiredService<JunkCleanerView>() ?? new JunkCleanerView(),
            "Storage"     => App.Services.GetRequiredService<StorageView>()     ?? new StorageView(),
            "Boost"       => App.Services.GetRequiredService<BoostView>()       ?? new BoostView(),
            "DiskHealth"  => App.Services.GetRequiredService<DiskHealthView>()  ?? new DiskHealthView(),
            "Tools"       => App.Services.GetRequiredService<ToolsView>()       ?? new ToolsView(),
            "Network"     => App.Services.GetRequiredService<NetworkView>()     ?? new NetworkView(),
            "Settings"    => App.Services.GetRequiredService<SettingsView>()    ?? new SettingsView(),
            _             => null
        };

        if (target is not null)
            MainFrame.Navigate(target);
    }

    // ─── Pro badge ────────────────────────────────────────────────────────
    private void UpdateProBadge()
    {
        bool isPro = _license.IsActivated;
        ProBadge.Visibility  = isPro ? Visibility.Visible   : Visibility.Collapsed;
        UpgradeBanner.Visibility = isPro ? Visibility.Collapsed : Visibility.Visible;
    }

    // ─── Window chrome ────────────────────────────────────────────────────
    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2)
            ToggleMaximize();
        else
            DragMove();
    }

    private void MinimizeBtn_Click(object sender, RoutedEventArgs e)
    {
        WindowState = WindowState.Minimized;
    }

    private void MaximizeBtn_Click(object sender, RoutedEventArgs e) => ToggleMaximize();

    private void ToggleMaximize()
    {
        if (_isMaximized)
        {
            WindowState = WindowState.Normal;
            _isMaximized = false;
        }
        else
        {
            WindowState = WindowState.Maximized;
            _isMaximized = true;
        }
    }

    private void CloseBtn_Click(object sender, RoutedEventArgs e)
    {
        // Minimize to tray instead of closing
        Hide();
    }

    // ─── System tray ──────────────────────────────────────────────────────
    private void TrayIcon_LeftMouseDown(object sender, RoutedEventArgs e)
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
    }

    private void TrayMenu_Open(object sender, RoutedEventArgs e)
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
    }

    private void TrayMenu_Scan(object sender, RoutedEventArgs e)
    {
        TrayMenu_Open(sender, e);
        NavigateTo("Dashboard");
        // TODO: trigger quick scan via DashboardViewModel
    }

    private void TrayMenu_Exit(object sender, RoutedEventArgs e)
    {
        _trayIcon?.Dispose();
        Application.Current.Shutdown();
    }

    // ─── Upgrade ─────────────────────────────────────────────────────────
    private void GetProBtn_Click(object sender, RoutedEventArgs e)
    {
        NavigateTo("Settings"); // Settings view hosts the license activation dialog
    }
}
