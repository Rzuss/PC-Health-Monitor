using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace PCHealthMonitor.Views.Upgrade;

public partial class ProUpgradeWindow : Window
{
    // ── Gumroad purchase URL ─────────────────────────────────────────────────
    // Replace the ID after /l/ with your real Gumroad product ID
    private const string GumroadUrl = "https://rzuss.gumroad.com/l/PCHM_PRO_PLACEHOLDER";

    // Raised when the user clicks "I already have a license key →"
    public event EventHandler? NavigateToLicense;

    // ── Feature list definitions ──────────────────────────────────────────────
    private static readonly (string Label, bool Included)[] _freeRows =
    [
        ("Live CPU, RAM & Disk monitoring",   true),
        ("Health Score & performance grades", true),
        ("Startup program manager",           true),
        ("Junk Cleaner (temp & cache files)", true),
        ("Storage analyzer",                  true),
        ("Boost Mode (process priority)",     true),
        ("Network monitor",                   true),
        ("System tray & notifications",       true),
        ("Historical performance charts",     false),
        ("Custom CPU & RAM alert thresholds", false),
        ("CSV & HTML/PDF export reports",     false),
        ("Scheduled auto-cleanup",            false),
    ];

    private static readonly (string Label, bool Included)[] _proRows =
    [
        ("Everything in Free",                true),
        ("Historical Charts (1h/24h/7d/30d)", true),
        ("Custom CPU & RAM alert thresholds", true),
        ("CSV & HTML/PDF export reports",     true),
        ("Scheduled auto-cleanup",            true),
        ("Priority support",                  true),
        ("All future Pro features",           true),
    ];

    public ProUpgradeWindow()
    {
        InitializeComponent();
        BuildFeatureRows(FreeFeatures, _freeRows, isPro: false);
        BuildFeatureRows(ProFeatures,  _proRows,  isPro: true);
    }

    // ── Row builder ───────────────────────────────────────────────────────────
    private static void BuildFeatureRows(
        StackPanel panel,
        (string Label, bool Included)[] rows,
        bool isPro)
    {
        foreach (var (label, included) in rows)
        {
            var row = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Margin      = new Thickness(0, 0, 0, 7)
            };

            // Icon
            var icon = new TextBlock
            {
                Text       = included ? "✓" : "✗",
                FontSize   = 12,
                FontWeight = FontWeights.Bold,
                Width      = 18,
                Foreground = included
                    ? new SolidColorBrush(isPro ? Color.FromRgb(80, 220, 140) : Color.FromRgb(80, 200, 130))
                    : new SolidColorBrush(Color.FromRgb(90, 90, 110)),
                VerticalAlignment = VerticalAlignment.Center
            };

            // Label
            var text = new TextBlock
            {
                Text       = label,
                FontFamily = new FontFamily("Segoe UI Variable, Segoe UI"),
                FontSize   = 12,
                Foreground = included
                    ? new SolidColorBrush(isPro ? Colors.White : Color.FromRgb(200, 200, 215))
                    : new SolidColorBrush(Color.FromRgb(80, 80, 100)),
                TextWrapping      = TextWrapping.Wrap,
                VerticalAlignment = VerticalAlignment.Center
            };

            row.Children.Add(icon);
            row.Children.Add(text);
            panel.Children.Add(row);
        }
    }

    // ── Button handlers ───────────────────────────────────────────────────────
    private void GetProBtn_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo(GumroadUrl) { UseShellExecute = true });
        }
        catch { /* ignore — browser unavailable */ }
    }

    private void AlreadyHaveKeyBtn_Click(object sender, RoutedEventArgs e)
    {
        NavigateToLicense?.Invoke(this, EventArgs.Empty);
        Close();
    }

    private void CloseBtn_Click(object sender, RoutedEventArgs e) => Close();
}
