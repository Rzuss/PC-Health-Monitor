using Microsoft.Extensions.DependencyInjection;
using PCHealthMonitor.ViewModels;
using System.Windows.Controls;

namespace PCHealthMonitor.Views.DiskHealth;

public partial class DiskHealthView : Page
{
    public DiskHealthView() : this(App.Services.GetRequiredService<DiskHealthViewModel>()) { }

    public DiskHealthView(DiskHealthViewModel vm)
    {
        InitializeComponent();
        DataContext = vm;

        Loaded   += async (_, _) => await vm.LoadAsync();
        Unloaded += (_, _)       => vm.Unsubscribe();
    }
}
