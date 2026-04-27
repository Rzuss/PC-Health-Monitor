using Microsoft.Extensions.DependencyInjection;
using PCHealthMonitor.ViewModels;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Navigation;

namespace PCHealthMonitor.Views.Settings;

public partial class SettingsView : Page
{
    public SettingsView() : this(App.Services.GetRequiredService<SettingsViewModel>()) { }

    public SettingsView(SettingsViewModel vm)
    {
        InitializeComponent();
        DataContext = vm;

        // Wire Pro-gate event: fired when free user tries to save Custom Alert thresholds
        vm.ProUpgradeRequested += (_, _) => ShowUpgradeDialog();
    }

    // Opens the Gumroad purchase page in the default browser
    private void Hyperlink_RequestNavigate(object sender, RequestNavigateEventArgs e)
    {
        Process.Start(new ProcessStartInfo(e.Uri.AbsoluteUri)
        {
            UseShellExecute = true
        });
        e.Handled = true;
    }

    private void ShowUpgradeDialog()
    {
        var dlg = new PCHealthMonitor.Views.Upgrade.ProUpgradeWindow
        {
            Owner = Window.GetWindow(this)
        };
        dlg.ShowDialog();
    }
}
