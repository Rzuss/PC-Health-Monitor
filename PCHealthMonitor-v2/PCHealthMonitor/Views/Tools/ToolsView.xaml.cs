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
    }

    private void ProUpgradeOverlay_Click(object sender, RoutedEventArgs e)
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
