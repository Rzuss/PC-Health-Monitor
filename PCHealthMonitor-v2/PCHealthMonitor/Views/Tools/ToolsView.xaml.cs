using Microsoft.Extensions.DependencyInjection;
using PCHealthMonitor.ViewModels;
using System.Windows;
using System.Windows.Controls;

namespace PCHealthMonitor.Views.Tools;

public partial class ToolsView : Page
{
    public ToolsView() : this(App.Services.GetRequiredService<ToolsViewModel>()) { }

    public ToolsView(ToolsViewModel vm)
    {
        InitializeComponent();
        DataContext = vm;

        // Wire Pro-gate event: any Pro action by a free user opens the upgrade dialog
        vm.ProUpgradeRequested += (_, _) => ShowUpgradeDialog();
    }

    private void ShowUpgradeDialog()
    {
        var dlg = new PCHealthMonitor.Views.Upgrade.ProUpgradeWindow
        {
            Owner = Window.GetWindow(this)
        };
        dlg.NavigateToLicense += (_, _) =>
        {
            if (Window.GetWindow(this) is MainWindow mw)
                mw.NavigateTo("Settings");
        };
        dlg.ShowDialog();
    }
}
