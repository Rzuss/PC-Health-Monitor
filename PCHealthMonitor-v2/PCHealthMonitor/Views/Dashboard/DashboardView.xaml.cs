using PCHealthMonitor.Services;
using PCHealthMonitor.ViewModels;
using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace PCHealthMonitor.Views.Dashboard;

public partial class DashboardView : Page
{
    private readonly DashboardViewModel _vm;
    private readonly HardwareService    _hardware;
    private int _displayedScore = -1;

    // Arc geometry constants
    private const double CX = 100, CY = 100, R = 80;
    private const double ArcStartAngle = 220;  // degrees — bottom-left
    private const double ArcSweepDeg   = 280;  // total arc sweep

    public DashboardView() : this(
        App.Services.GetRequiredService<DashboardViewModel>(),
        App.Services.GetRequiredService<HardwareService>()) { }

    public DashboardView(DashboardViewModel vm, HardwareService hardware)
    {
        InitializeComponent();
        _vm       = vm;
        _hardware = hardware;
        DataContext = vm;

        _hardware.SnapshotUpdated += OnSnapshot;

        Loaded   += (_, _) => OnSnapshot(null, _hardware.Latest);
        Unloaded += (_, _) => _hardware.SnapshotUpdated -= OnSnapshot;
    }

    // ── Hardware snapshot → UI ────────────────────────────────────────────
    private void OnSnapshot(object? sender, HardwareSnapshot snap)
    {
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
            Interval = TimeSpan.FromMilliseconds(16)  // ~60 fps
        };
        _arcTimer.Tick += (_, _) =>
        {
            var progress = Math.Min(1.0, (DateTime.Now - startTime).TotalMilliseconds / duration.TotalMilliseconds);
            // Ease-out cubic: 1 – (1–t)³
            var eased = 1 - Math.Pow(1 - progress, 3);
            var cur   = (int)(from + (score - from) * eased);
            ScoreNumber.Text = cur.ToString();
            UpdateArcGeometry(cur);
            if (progress >= 1.0) _arcTimer.Stop();
        };
        _arcTimer.Start();

        // Immediately set final values (visible if animation ticks lag)
        ScoreNumber.Text = score.ToString();
        UpdateArcGeometry(score);
    }

    private void UpdateArcGeometry(int score)
    {
        double pct       = Math.Clamp(score / 100.0, 0, 1);
        double sweepDeg  = ArcSweepDeg * pct;
        double endAngle  = ArcStartAngle + sweepDeg;

        var endPoint = AngleToPoint(endAngle, CX, CY, R);
        ValueArc.Point     = endPoint;
        ValueArc.IsLargeArc = sweepDeg > 180;
    }

    private static Point AngleToPoint(double degrees, double cx, double cy, double r)
    {
        double rad = (degrees - 90) * Math.PI / 180.0;
        return new Point(cx + r * Math.Cos(rad), cy + r * Math.Sin(rad));
    }

    // ── ProgressBar smooth animation ─────────────────────────────────────
    private static void AnimateBar(System.Windows.Controls.ProgressBar bar, double target)
    {
        var anim = new DoubleAnimation(target,
            new Duration(TimeSpan.FromMilliseconds(300)))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };
        bar.BeginAnimation(System.Windows.Controls.ProgressBar.ValueProperty, anim);
    }

    // ── Button handlers ───────────────────────────────────────────────────
    private void ScanBtn_Click(object sender, RoutedEventArgs e)
    {
        LastScanText.Text = $"Last scan: {DateTime.Now:HH:mm:ss}";
        _vm.RunQuickScanCommand.Execute(null);
    }

    private void ActivateBoostBtn_Click(object sender, RoutedEventArgs e) => NavigateMain("Boost");

    private void QuickClean_Click(object sender, RoutedEventArgs e)      => NavigateMain("JunkCleaner");
    private void QuickStartup_Click(object sender, RoutedEventArgs e)    => NavigateMain("Startup");
    private void QuickDiskHealth_Click(object sender, RoutedEventArgs e) => NavigateMain("DiskHealth");

    private void NavigateMain(string page)
    {
        if (Window.GetWindow(this) is MainWindow mw)
            mw.NavigateTo(page);
    }
}
