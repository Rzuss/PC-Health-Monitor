using Microsoft.Extensions.DependencyInjection;
using PCHealthMonitor.Helpers;
using PCHealthMonitor.ViewModels;
using System.Windows.Controls;

namespace PCHealthMonitor.Views.Boost;

public partial class BoostView : Page
{
    public BoostView() : this(App.Services.GetRequiredService<BoostViewModel>()) { }

    public BoostView(BoostViewModel vm)
    {
        InitializeComponent();
        DataContext = vm;

        // Auto-load process list on first visit
        Loaded += async (_, _) =>
        {
            if (vm.Processes.Count == 0 && vm.RefreshCommand is AsyncRelayCommand cmd)
                await cmd.ExecuteAsync();
        };
    }
}
