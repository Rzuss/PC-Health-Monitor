using Microsoft.Extensions.DependencyInjection;
using PCHealthMonitor.Helpers;
using PCHealthMonitor.ViewModels;
using System.Windows.Controls;

namespace PCHealthMonitor.Views.Storage;

public partial class StorageView : Page
{
    public StorageView() : this(App.Services.GetRequiredService<StorageViewModel>()) { }

    public StorageView(StorageViewModel vm)
    {
        InitializeComponent();
        DataContext = vm;

        // Auto-load drive list on page load (fast — just enumerates drives, no scan).
        // Guard: only trigger if drives aren't already loaded (handles back-navigation).
        Loaded += async (_, _) =>
        {
            if (vm.Drives.Count == 0 && vm.LoadDrivesCommand is AsyncRelayCommand cmd)
                await cmd.ExecuteAsync();
        };
    }
}
