using Microsoft.Extensions.DependencyInjection;
using PCHealthMonitor.Helpers;
using PCHealthMonitor.ViewModels;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

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

    // ── Double-click → open folder/file location in Explorer ─────────────────
    private void LargeItemsGrid_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (sender is not DataGrid grid) return;
        if (grid.SelectedItem is not FolderEntry item) return;

        try
        {
            if (item.IsFolder && Directory.Exists(item.Path))
            {
                // Open the folder directly
                Process.Start(new ProcessStartInfo("explorer.exe", item.Path)
                {
                    UseShellExecute = true
                });
            }
            else if (!item.IsFolder && File.Exists(item.Path))
            {
                // Select the file inside its parent folder
                Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{item.Path}\"")
                {
                    UseShellExecute = true
                });
            }
        }
        catch { /* Explorer unavailable — ignore */ }
    }
}
