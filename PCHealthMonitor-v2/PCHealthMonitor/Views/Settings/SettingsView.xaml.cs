using Microsoft.Extensions.DependencyInjection;
using PCHealthMonitor.ViewModels;
using System.Windows.Controls;

namespace PCHealthMonitor.Views.Settings;

public partial class SettingsView : Page
{
    public SettingsView() : this(App.Services.GetRequiredService<SettingsViewModel>()) { }

    public SettingsView(SettingsViewModel vm)
    {
        InitializeComponent();
        DataContext = vm;
    }
}
