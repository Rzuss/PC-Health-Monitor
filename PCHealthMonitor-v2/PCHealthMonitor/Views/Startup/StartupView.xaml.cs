using Microsoft.Extensions.DependencyInjection;
using PCHealthMonitor.Helpers;
using PCHealthMonitor.ViewModels;
using System.Windows.Controls;

namespace PCHealthMonitor.Views.Startup;

public partial class StartupView : Page
{
    public StartupView() : this(App.Services.GetRequiredService<StartupViewModel>()) { }

    public StartupView(StartupViewModel vm)
    {
        InitializeComponent();
        DataContext = vm;
        Loaded += async (_, _) =>
        {
            if (vm.LoadCommand is AsyncRelayCommand cmd)
                await cmd.ExecuteAsync();
        };
    }
}
