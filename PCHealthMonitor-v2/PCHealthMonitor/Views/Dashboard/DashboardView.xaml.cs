using Microsoft.Extensions.DependencyInjection;
using PCHealthMonitor.Services;
using PCHealthMonitor.ViewModels;
using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace PCHealthMonitor.Views.Dashboard;

public partial class DashboardView : Page
{
    private readonly DashboardViewModel    _vm;
    private readonly HardwareService       _hardware;
    private readonly MetricsHistoryService _history;
    private readonly ProFeatureService     _pro;

    private int _displayedScore = -1;
    private int _snapshotTick   = 0;          // used to throttle chart redraws
    private int _selectedHours  = 1;          // active time range

    // Arc geometry constants
    private const double CX = 100, CY = 100, R = 80;
    private const double ArcStartAngle = 220;
    private const double ArcSweepDeg   = 280;

    public DashboardView() : this(
        App.Services.GetRequiredService<DashboardViewModel>(),
        App.Services.GetRequiredService<HardwareService>(),
        App.Services.GetRequiredService<MetricsHistoryService>(),
        App.Services.GetRequiredService<ProFeatureService>()) { }

    public DashboardView(
        DashboardViewModel    vm,
        HardwareService       hardware,
        MetricsHistoryService history,
        ProFeatureService     pro)
    {
        InitializeComponent();
        _vm       = vm;
        _hardware = hardware;
        _history  = history;
        _pro      = pro;
        DataContext = vm;

        _hardware.SnapshotUpdated += OnSnapshot;

        // Live update when the user activates Pro mid-session
        var license = App.Services.GetRequiredService<LicenseService>();
        license.ProStatusChanged += (_, _) =>
            Dispatcher.InvokeAsync(RefreshProVisibility, DispatcherPriority.Normal);

        Loaded += (_, _) =>
        {
            RefreshProVisibility();
            HighlightTimeRangeButton(_selectedHours);
            OnSnapshot(null, _hardware.Latest);
        };

        Unloaded += (_, _) =>
        {
            _hardware.SnapshotUpdated -= OnSnapshot;
            _arcTimer?.Stop();
            _arcTimer = null;
        };
    }

    private void RefreshProVisibility()
    {
        bool isPro = _pro.IsPro;
        HistoryCard.Visibility = isPro ? Visibility.Visible : Visibility.Collapsed;
        // Redraw charts immediately if now Pro and the card just became visible
        if (isPro) DrawCharts();
    }

    // ── Hardware snapshot → UI ────────────────────────────────────────────
    private void OnSnapshot(object? sender, HardwareSnapshot snap)
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.BeginInvoke(() => OnSnapshot(sender, snap));
            return;
        }

        // CPU
        CpuLoadLabel.Text = $"{snap.CpuLoad:0}%";
        CpuTempLabel.Text = snap.CpuTempC > 0 ? $"{snap.CpuTempC:0} °C" : "-- °C";
        AnimateBar(CpuBar, snap.CpuLoad);
        CpuBar.Foreground = snap.CpuLoad > 85
            ? (Brush)FindResource("RedBrush")
            : snap.CpuLoad > 60
                ? (Brush)FindResource("YellowBrush")
                : (Brush)FindResource("BlueBrush");

        // RAM
        RamLoadLabel.Text = $"{snap.RamLoad}%";
        RamGbLabel.Text   = $"{snap.RamUsedGb:0.0} / {snap.RamTotalGb:0.0} GB";
        AnimateBar(RamBar, snap.RamLoad);

        // Disk
        DiskLoadLabel.Text = $"{snap.DiskLoad:0}%";
        AnimateBar(DiskBar, snap.DiskLoad);

        // Health score arc
        if (snap.HealthScore != _displayedScore)
        {
            _displayedScore = snap.HealthScore;
            AnimateScoreArc(snap.HealthScore);
            ScoreGrade.Text = snap.HealthGrade;
            ScoreNumber.Foreground = snap.HealthScore switch
            {
                >= 80 => (Brush)FindResource("GreenBrush"),
                >= 60 => (Brush)FindResource("BlueBrush"),
                >= 40 => (Brush)FindResource("YellowBrush"),
                _     => (Brush)FindResource("RedBrush")
            };
        }

        // Pro: redraw charts every ~30 seconds (15 ticks × 2s poll interval)
        if (_pro.IsPro)
        {
            _snapshotTick++;
            if (_snapshotTick % 15 == 1)  // 1 = immediate on first load
                DrawCharts();
        }
    }

    // ── Arc animation ─────────────────────────────────────────────────────
    private System.Windows.Threading.DispatcherTimer? _arcTimer;

    private void AnimateScoreArc(int score)
    {
        _arcTimer?.Stop();

        var from      = (double)Math.Max(0, _displayedScore < 0 ? 0 : _displayedScore);
        var startTime = DateTime.Now;
        var duration  = TimeSpan.FromMilliseconds(500);

        _arcTimer = new System.Windows.Threading.DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(16)
        };
        _arcTimer.Tick += (_, _) =>
        {
            var progress = Math.Min(1.0, (DateTime.Now - startTime).TotalMilliseconds / duration.TotalMilliseconds);
            var eased = 1 - Math.Pow(1 - progress, 3);
            var cur   = (int)(from + (score - from) * eased);
            ScoreNumber.Text = cur.ToString();
            UpdateArcGeometry(cur);
            if (progress >= 1.0) _arcTimer.Stop();
        };
        _arcTimer.Start();

        ScoreNumber.Text = score.ToString();
        UpdateArcGeometry(score);
    }

    private void UpdateArcGeometry(int score)
    {
        double pct      = Math.Clamp(score / 100.0, 0, 1);
        double sweepDeg = ArcSweepDeg * pct;
        double endAngle = ArcStartAngle + sweepDeg;

        var endPoint = AngleToPoint(endAngle, CX, CY, R);
        ValueArc.Point    = endPoint;
        ValueArc.IsLargeArc = sweepDeg > 180;
    }

    private static Point AngleToPoint(double degrees, double cx, double cy, double r)
    {
        double rad = (degrees - 90) * Math.PI / 180.0;
        return new Point(cx + r * Math.Cos(rad), cy + r * Math.Sin(rad));
    }

    // ── ProgressBar smooth animation ──────────────────────────────────────
    private static void AnimateBar(System.Windows.Controls.ProgressBar bar, double target)
    {
        var anim = new DoubleAnimation(target,
            new Duration(TimeSpan.FromMilliseconds(300)))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };
        bar.BeginAnimation(System.Windows.Controls.ProgressBar.ValueProperty, anim);
    }

    // ── Historical chart drawing ──────────────────────────────────────────
    private void DrawCharts()
    {
        var pts  = _history.GetHistory(_selectedHours);
        var W    = ChartCanvas.ActualWidth;
        var H    = ChartCanvas.ActualHeight;

        if (W < 10 || H < 10) return;

        // Update grid lines
        SetGridLine(GridLine75, 0, W, H * 0.25);
        SetGridLine(GridLine50, 0, W, H * 0.50);
        SetGridLine(GridLine25, 0, W, H * 0.75);

        // Y-axis labels
        Canvas.SetTop(Label75, H * 0.25 - 9);
        Canvas.SetTop(Label50, H * 0.50 - 9);
        Canvas.SetTop(Label25, H * 0.75 - 9);

        if (pts.Count < 2)
        {
            CpuLine.Points.Clear();
            RamLine.Points.Clear();
            DiskLine.Points.Clear();
            NoDataLabel.Visibility = Visibility.Visible;
            Canvas.SetLeft(NoDataLabel, (W - 240) / 2);
            return;
        }

        NoDataLabel.Visibility = Visibility.Collapsed;

        CpuLine.Points  = BuildPoints(pts, p => p.CpuLoad,          W, H);
        RamLine.Points  = BuildPoints(pts, p => (float)p.RamLoad,   W, H);
        DiskLine.Points = BuildPoints(pts, p => p.DiskLoad,          W, H);
    }

    private static void SetGridLine(System.Windows.Shapes.Line line, double x1, double x2, double y)
    {
        line.X1 = x1; line.X2 = x2;
        line.Y1 = y;  line.Y2 = y;
    }

    private static PointCollection BuildPoints(
        IReadOnlyList<MetricPoint> data,
        Func<MetricPoint, float>   getValue,
        double W, double H)
    {
        var pc = new PointCollection(data.Count);
        for (int i = 0; i < data.Count; i++)
        {
            double x = (double)i / (data.Count - 1) * W;
            double y = H - (getValue(data[i]) / 100.0 * H);
            pc.Add(new Point(x, Math.Clamp(y, 0, H)));
        }
        return pc;
    }

    // Called when the chart border is resized
    private void ChartCanvas_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (_pro.IsPro) DrawCharts();
    }

    // ── Time range selector ───────────────────────────────────────────────
    private void TimeRangeBtn_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button btn) return;
        if (!int.TryParse(btn.Tag?.ToString(), out int hours)) return;

        // Gate: Performance History is Pro-only
        if (!_pro.IsPro)
        {
            ProUpgradeOverlay_Click(sender, e);
            return;
        }

        _selectedHours = hours;
        HighlightTimeRangeButton(hours);
        DrawCharts();
    }

    private void HighlightTimeRangeButton(int hours)
    {
        // Reset all
        foreach (var btn in new[] { Btn1H, Btn24H, Btn7D, Btn30D })
        {
            btn.Opacity    = 0.6;
            btn.FontWeight = FontWeights.Normal;
        }

        // Highlight active
        var active = hours switch
        {
            1   => Btn1H,
            24  => Btn24H,
            168 => Btn7D,
            _   => Btn30D
        };
        active.Opacity    = 1.0;
        active.FontWeight = FontWeights.SemiBold;
    }

    // ── Button handlers ───────────────────────────────────────────────────
    private void ScanBtn_Click(object sender, RoutedEventArgs e)
    {
        LastScanText.Text = $"Last scan: {DateTime.Now:HH:mm:ss}";
        _vm.RunQuickScanCommand.Execute(null);
    }

    private void ActivateBoostBtn_Click(object sender, RoutedEventArgs e) => NavigateMain("Boost");
    private void QuickClean_Click(object sender, RoutedEventArgs e)       => NavigateMain("JunkCleaner");
    private void QuickStartup_Click(object sender, RoutedEventArgs e)     => NavigateMain("Startup");
    private void QuickDiskHealth_Click(object sender, RoutedEventArgs e)  => NavigateMain("DiskHealth");

    private void NavigateMain(string page)
    {
        if (Window.GetWindow(this) is MainWindow mw)
            mw.NavigateTo(page);
    }

    private void ProUpgradeOverlay_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new PCHealthMonitor.Views.Upgrade.ProUpgradeWindow
        {
            Owner = Window.GetWindow(this)
        };
        dlg.NavigateToLicense += (_, _) => NavigateMain("Settings");
        dlg.ShowDialog();
    }
}
