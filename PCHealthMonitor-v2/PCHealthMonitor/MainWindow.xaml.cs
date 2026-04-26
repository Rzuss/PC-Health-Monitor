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
using PCHealthMonitor.Views.Upgrade;
using System;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace PCHealthMonitor;

public partial class MainWindow : Window
{
    private readonly MainViewModel    _vm;
    private readonly LicenseService  _license;
    private readonly HardwareService _hardware;
    private readonly SettingsService _settingsService;
    private readonly ToastService    _toast;
    private TaskbarIcon?             _trayIcon;
    private bool                     _isMaximized;

    // ─── Constructor ──────────────────────────────────────────────────────
    public MainWindow(MainViewModel vm, LicenseService license,
                      HardwareService hardware, SettingsService settingsService,
                      ToastService toast)
    {
        InitializeComponent();

        _vm              = vm;
        _license         = license;
        _hardware        = hardware;
        _settingsService = settingsService;
        _toast           = toast;
        DataContext = vm;

        // Initialize tray icon
        _trayIcon = (TaskbarIcon)FindResource("TrayIcon");

        // Wire hardware updates to status bar
        _hardware.SnapshotUpdated += OnSnapshotUpdated;

        // Refresh Pro badge whenever activation state changes
        _license.ProStatusChanged += (_, isPro) =>
            Dispatcher.InvokeAsync(() =>
            {
                UpdateProBadge();
                _vm.NotifyProStatusChanged();
            });

        // Subscribe to toast events (fired from any thread → marshal to UI)
        _toast.ToastRequested += (_, msg) =>
            Dispatcher.InvokeAsync(() => ShowToast(msg));

        // Restore window geometry, then navigate on load
        Loaded += (_, _) =>
        {
            RestoreWindowGeometry();
            NavigateTo("Dashboard");
            UpdateProBadge();
        };

        // Save geometry whenever the window is actually closing
        Closing += (_, _) => SaveWindowGeometry();
        Closed  += (_, _) => _trayIcon?.Dispose();
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
        {
            MainFrame.Navigate(target);
            // Clear the journal after every navigation so old page instances
            // are not kept alive in memory with their timers still running.
            while (MainFrame.CanGoBack)
                MainFrame.RemoveBackEntry();
        }
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
        // Save geometry before hiding so tray-only sessions persist size/pos
        SaveWindowGeometry();
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

    // ─── Window geometry persistence ──────────────────────────────────────
    private void RestoreWindowGeometry()
    {
        try
        {
            var s = _settingsService.Load();
            if (s.WindowLeft >= 0 && s.WindowTop >= 0)
            {
                // Clamp to ensure window is on a visible screen
                var wa = SystemParameters.WorkArea;
                Left   = Math.Max(0, Math.Min(s.WindowLeft, wa.Right  - 200));
                Top    = Math.Max(0, Math.Min(s.WindowTop,  wa.Bottom - 100));
            }
            if (s.WindowWidth  >= MinWidth)  Width  = s.WindowWidth;
            if (s.WindowHeight >= MinHeight) Height = s.WindowHeight;
        }
        catch { /* leave defaults */ }
    }

    private void SaveWindowGeometry()
    {
        try
        {
            if (WindowState == WindowState.Minimized) return; // don't save minimized state

            var s = _settingsService.Load();
            if (WindowState == WindowState.Normal)
            {
                s.WindowLeft   = Left;
                s.WindowTop    = Top;
                s.WindowWidth  = Width;
                s.WindowHeight = Height;
            }
            // If maximized, keep the last Normal geometry so restore looks right
            _settingsService.Save(s);
        }
        catch { }
    }

    // ─── Upgrade ─────────────────────────────────────────────────────────
    private void GetProBtn_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new ProUpgradeWindow { Owner = this };
        dlg.NavigateToLicense += (_, _) => NavigateTo("Settings");
        dlg.ShowDialog();
    }

    // ─── Keyboard shortcuts ───────────────────────────────────────────────
    // Ctrl+1–8: switch tabs | Ctrl+R: navigate to Dashboard (re-scan)
    // Esc: hide to tray
    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);

        bool ctrl = Keyboard.Modifiers == ModifierKeys.Control;

        if (ctrl)
        {
            var page = e.Key switch
            {
                Key.D1 or Key.NumPad1 => "Dashboard",
                Key.D2 or Key.NumPad2 => "Startup",
                Key.D3 or Key.NumPad3 => "JunkCleaner",
                Key.D4 or Key.NumPad4 => "Storage",
                Key.D5 or Key.NumPad5 => "Boost",
                Key.D6 or Key.NumPad6 => "DiskHealth",
                Key.D7 or Key.NumPad7 => "Tools",
                Key.D8 or Key.NumPad8 => "Network",
                Key.D9 or Key.NumPad9 => "Settings",
                Key.R                  => "Dashboard",
                _                      => null
            };

            if (page is not null)
            {
                NavigateTo(page);
                e.Handled = true;
            }
        }
        else if (e.Key == Key.Escape)
        {
            // Minimize to tray on Escape
            SaveWindowGeometry();
            Hide();
            e.Handled = true;
        }
    }

    // ─── Toast notification system ────────────────────────────────────────
    // Called on the UI thread via Dispatcher.InvokeAsync.
    // Creates a toast card, adds it to the ToastPanel, animates it in,
    // waits for the duration, then animates it out and removes it.
    private async void ShowToast(ToastMessage msg)
    {
        // ── Color scheme by type ──────────────────────────────────────────
        var (accentHex, iconText) = msg.Type switch
        {
            ToastType.Success => ("#22C55E", "✓"),
            ToastType.Warning => ("#F59E0B", "⚠"),
            ToastType.Error   => ("#EF4444", "✕"),
            _                 => ("#3B82F6", "ℹ"),
        };
        var accentBrush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(accentHex));

        // ── Build toast card ──────────────────────────────────────────────
        var card = new Border
        {
            Background    = (Brush)FindResource("BgCard2Brush"),
            CornerRadius  = new CornerRadius(10),
            Margin        = new Thickness(0, 6, 0, 0),
            Padding       = new Thickness(14, 11, 14, 11),
            BorderBrush   = accentBrush,
            BorderThickness = new Thickness(0, 0, 0, 0),
            Opacity       = 0,
            RenderTransform = new TranslateTransform(40, 0),
        };
        card.Effect = new System.Windows.Media.Effects.DropShadowEffect
        {
            Color = Colors.Black, BlurRadius = 20, ShadowDepth = 0, Opacity = 0.5
        };

        // Left accent bar + content
        var innerGrid = new Grid();
        innerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(4) });
        innerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(36) });
        innerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        innerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        // Left color strip
        var strip = new Border
        {
            Background   = accentBrush,
            CornerRadius = new CornerRadius(3),
            Width = 4,
            Margin = new Thickness(0, 0, 12, 0)
        };
        Grid.SetColumn(strip, 0);

        // Icon
        var icon = new TextBlock
        {
            Text               = iconText,
            Foreground         = accentBrush,
            FontSize           = 16,
            FontWeight         = FontWeights.Bold,
            VerticalAlignment  = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        Grid.SetColumn(icon, 1);

        // Message text
        var text = new TextBlock
        {
            Text               = msg.Text,
            Foreground         = (Brush)FindResource("TextBrush"),
            FontSize           = 13,
            TextWrapping       = TextWrapping.Wrap,
            VerticalAlignment  = VerticalAlignment.Center,
            Margin             = new Thickness(0, 0, 8, 0),
        };
        Grid.SetColumn(text, 2);

        // Dismiss button
        var dismiss = new Button
        {
            Content         = "✕",
            Foreground      = (Brush)FindResource("SubTextBrush"),
            Background      = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            FontSize        = 11,
            Cursor          = Cursors.Hand,
            VerticalAlignment   = VerticalAlignment.Center,
            Padding         = new Thickness(4),
        };
        Grid.SetColumn(dismiss, 3);

        innerGrid.Children.Add(strip);
        innerGrid.Children.Add(icon);
        innerGrid.Children.Add(text);
        innerGrid.Children.Add(dismiss);
        card.Child = innerGrid;

        ToastPanel.Items.Add(card);

        // Track whether the user dismissed early
        bool dismissed = false;
        dismiss.Click += (_, _) => { dismissed = true; };

        // ── Animate in — slide from right + fade ──────────────────────────
        var translate = (TranslateTransform)card.RenderTransform;

        var slideIn = new DoubleAnimation(40, 0,
            new Duration(TimeSpan.FromMilliseconds(250)))
        {
            EasingFunction = new ExponentialEase { EasingMode = EasingMode.EaseOut }
        };
        var fadeIn = new DoubleAnimation(0, 1,
            new Duration(TimeSpan.FromMilliseconds(200)));

        translate.BeginAnimation(TranslateTransform.XProperty, slideIn);
        card.BeginAnimation(OpacityProperty, fadeIn);

        // ── Wait for duration (or early dismiss) ──────────────────────────
        var elapsed = 0;
        const int pollMs = 50;
        while (elapsed < msg.DurationMs && !dismissed)
        {
            await Task.Delay(pollMs);
            elapsed += pollMs;
        }

        // ── Animate out — fade ────────────────────────────────────────────
        var fadeOut = new DoubleAnimation(1, 0,
            new Duration(TimeSpan.FromMilliseconds(180)));

        var tcs = new TaskCompletionSource<bool>();
        fadeOut.Completed += (_, _) => tcs.TrySetResult(true);
        card.BeginAnimation(OpacityProperty, fadeOut);

        await tcs.Task;
        ToastPanel.Items.Remove(card);
    }

    // ─── Edge resize (WM_NCHITTEST) ───────────────────────────────────────
    // WindowStyle=None + AllowsTransparency=True means Windows won't handle
    // resize hits automatically. We hook WndProc and return the correct
    // HT* code so Windows does the native drag-resize.

    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);

    private const int WM_NCHITTEST  = 0x0084;
    private const int HTLEFT        = 10;
    private const int HTRIGHT       = 11;
    private const int HTTOP         = 12;
    private const int HTTOPLEFT     = 13;
    private const int HTTOPRIGHT    = 14;
    private const int HTBOTTOM      = 15;
    private const int HTBOTTOMLEFT  = 16;
    private const int HTBOTTOMRIGHT = 17;

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        var source = (HwndSource)PresentationSource.FromVisual(this);
        source?.AddHook(WndProc);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg != WM_NCHITTEST || WindowState == WindowState.Maximized)
            return IntPtr.Zero;

        // Decode screen coordinates from lParam
        int x = unchecked((short)(lParam.ToInt32() & 0xFFFF));
        int y = unchecked((short)((lParam.ToInt32() >> 16) & 0xFFFF));

        var local = PointFromScreen(new Point(x, y));
        double w = ActualWidth;
        double h = ActualHeight;
        const double edge = 8; // px hit zone

        bool left   = local.X < edge;
        bool right  = local.X > w - edge;
        bool top    = local.Y < edge;
        bool bottom = local.Y > h - edge;

        if (top    && left)  { handled = true; return (IntPtr)HTTOPLEFT;     }
        if (top    && right) { handled = true; return (IntPtr)HTTOPRIGHT;    }
        if (bottom && left)  { handled = true; return (IntPtr)HTBOTTOMLEFT;  }
        if (bottom && right) { handled = true; return (IntPtr)HTBOTTOMRIGHT; }
        if (left)            { handled = true; return (IntPtr)HTLEFT;        }
        if (right)           { handled = true; return (IntPtr)HTRIGHT;       }
        if (top)             { handled = true; return (IntPtr)HTTOP;         }
        if (bottom)          { handled = true; return (IntPtr)HTBOTTOM;      }

        return IntPtr.Zero;
    }
}
