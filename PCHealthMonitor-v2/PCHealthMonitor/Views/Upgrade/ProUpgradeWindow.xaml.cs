using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace PCHealthMonitor.Views.Upgrade;

public partial class ProUpgradeWindow : Window
{
    private const string GumroadUrl = "https://rzuss.gumroad.com/l/PCHM_PRO_PLACEHOLDER";
    public event EventHandler? NavigateToLicense;

    // ── Free column: all free features, then grayed-out Pro-only ─────────────
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

    // ── Pro column: same free features FIRST, then Pro-exclusive highlighted ──
    // RowKind: 0 = shared (free) feature, 1 = separator, 2 = Pro-exclusive
    private static readonly (string Label, int Kind)[] _proRows =
    [
        // Shared / free features
        ("Live CPU, RAM & Disk monitoring",   0),
        ("Health Score & performance grades", 0),
        ("Startup program manager",           0),
        ("Junk Cleaner (temp & cache files)", 0),
        ("Storage analyzer",                  0),
        ("Boost Mode (process priority)",     0),
        ("Network monitor",                   0),
        ("System tray & notifications",       0),
        // Divider
        ("",                                  1),
        // Pro-exclusive
        ("Historical Charts (1h/24h/7d/30d)", 2),
        ("Custom CPU & RAM alert thresholds", 2),
        ("CSV & HTML/PDF export reports",     2),
        ("Scheduled auto-cleanup",            2),
        ("Priority support",                  2),
        ("All future Pro features",           2),
    ];

    public ProUpgradeWindow()
    {
        InitializeComponent();
        BuildFreeRows(FreeFeatures, _freeRows);
        BuildProRows(ProFeatures,   _proRows);
    }

    // ── Free column builder ───────────────────────────────────────────────────
    private static void BuildFreeRows(StackPanel panel, (string Label, bool Included)[] rows)
    {
        foreach (var (label, included) in rows)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 7) };

            row.Children.Add(new TextBlock
            {
                Text              = included ? "✓" : "✗",
                FontSize          = 12, FontWeight = FontWeights.Bold, Width = 20,
                Foreground        = included ? new SolidColorBrush(Color.FromRgb(80, 200, 130))
                                             : new SolidColorBrush(Color.FromRgb(70, 70, 90)),
                VerticalAlignment = VerticalAlignment.Center
            });
            row.Children.Add(new TextBlock
            {
                Text              = label,
                FontFamily        = new FontFamily("Segoe UI Variable, Segoe UI"),
                FontSize          = 12,
                Foreground        = included ? new SolidColorBrush(Color.FromRgb(200, 200, 215))
                                             : new SolidColorBrush(Color.FromRgb(70, 70, 90)),
                TextWrapping      = TextWrapping.Wrap,
                VerticalAlignment = VerticalAlignment.Center
            });
            panel.Children.Add(row);
        }
    }

    // ── Pro column builder ────────────────────────────────────────────────────
    private static void BuildProRows(StackPanel panel, (string Label, int Kind)[] rows)
    {
        foreach (var (label, kind) in rows)
        {
            // ── Separator ────────────────────────────────────────────────────
            if (kind == 1)
            {
                // Line + "Pro Exclusive" label
                var sep = new StackPanel { Margin = new Thickness(0, 8, 0, 8) };

                var line = new Border
                {
                    Height          = 1,
                    Background      = new SolidColorBrush(Color.FromArgb(80, 124, 111, 245)),
                    Margin          = new Thickness(0, 0, 0, 8)
                };

                var badge = new Border
                {
                    Background    = new SolidColorBrush(Color.FromArgb(60, 91, 84, 232)),
                    CornerRadius  = new CornerRadius(4),
                    Padding       = new Thickness(8, 3, 8, 3),
                    HorizontalAlignment = HorizontalAlignment.Left
                };
                badge.Child = new TextBlock
                {
                    Text       = "✦  Pro Exclusive",
                    Foreground = new SolidColorBrush(Color.FromRgb(180, 170, 255)),
                    FontFamily = new FontFamily("Segoe UI Variable, Segoe UI"),
                    FontSize   = 10,
                    FontWeight = FontWeights.SemiBold
                };

                sep.Children.Add(line);
                sep.Children.Add(badge);
                panel.Children.Add(sep);
                continue;
            }

            // ── Feature row ───────────────────────────────────────────────────
            bool isExclusive = kind == 2;

            var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 7) };

            row.Children.Add(new TextBlock
            {
                Text       = isExclusive ? "⚡" : "✓",
                FontSize   = isExclusive ? 11 : 12,
                FontWeight = FontWeights.Bold,
                Width      = 20,
                Foreground = isExclusive
                    ? new SolidColorBrush(Color.FromRgb(180, 170, 255))  // purple for Pro
                    : new SolidColorBrush(Color.FromRgb(80, 200, 130)),  // green for shared
                VerticalAlignment = VerticalAlignment.Center
            });

            var lbl = new TextBlock
            {
                Text         = label,
                FontFamily   = new FontFamily("Segoe UI Variable, Segoe UI"),
                FontSize     = 12,
                FontWeight   = isExclusive ? FontWeights.SemiBold : FontWeights.Normal,
                Foreground   = isExclusive
                    ? new SolidColorBrush(Colors.White)
                    : new SolidColorBrush(Color.FromRgb(190, 190, 210)),
                TextWrapping      = TextWrapping.Wrap,
                VerticalAlignment = VerticalAlignment.Center
            };
            row.Children.Add(lbl);
            panel.Children.Add(row);
        }
    }

    // ── Button handlers ───────────────────────────────────────────────────────
    private void GetProBtn_Click(object sender, RoutedEventArgs e)
    {
        try { Process.Start(new ProcessStartInfo(GumroadUrl) { UseShellExecute = true }); }
        catch { }
    }

    private void AlreadyHaveKeyBtn_Click(object sender, RoutedEventArgs e)
    {
        NavigateToLicense?.Invoke(this, EventArgs.Empty);
        Close();
    }

    private void CloseBtn_Click(object sender, RoutedEventArgs e) => Close();
}
