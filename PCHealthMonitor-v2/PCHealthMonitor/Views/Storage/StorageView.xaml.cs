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
        Loaded += async (_, _) => await vm.ScanCommand.ExecuteAsync(null);
    }
}
