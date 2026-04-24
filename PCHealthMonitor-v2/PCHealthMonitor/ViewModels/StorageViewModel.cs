using PCHealthMonitor.Helpers;
using PCHealthMonitor.Services;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows.Input;

namespace PCHealthMonitor.ViewModels;

public sealed class StorageViewModel : BaseViewModel
{
    private readonly StorageService _storage;

    public StorageViewModel(StorageService storage)
    {
        _storage     = storage;
        ScanCommand  = new AsyncRelayCommand(ScanAsync, () => !IsScanning);
    }

    public ICommand ScanCommand { get; }

    public ObservableCollection<DriveInfo> Drives      { get; } = new();
    public ObservableCollection<FolderEntry> LargeItems { get; } = new();

    private bool _isScanning;
    public bool IsScanning { get => _isScanning; set { SetProperty(ref _isScanning, value); AsyncRelayCommand.RaiseCanExecuteChanged(); } }

    private string _statusText = "Select a drive and scan";
    public string StatusText { get => _statusText; set => SetProperty(ref _statusText, value); }

    private DriveInfo? _selectedDrive;
    public DriveInfo? SelectedDrive
    {
        get => _selectedDrive;
        set { SetProperty(ref _selectedDrive, value); AsyncRelayCommand.RaiseCanExecuteChanged(); }
    }

    private async Task ScanAsync()
    {
        IsScanning = true;
        StatusText = "Scanning drives...";
        Drives.Clear();
        LargeItems.Clear();

        var drives = await _storage.GetDrivesAsync();
        foreach (var d in drives) Drives.Add(d);

        if (SelectedDrive is not null)
        {
            StatusText = $"Analyzing {SelectedDrive.Name}...";
            var items = await _storage.GetLargeItemsAsync(SelectedDrive.RootPath, topN: 50);
            foreach (var item in items) LargeItems.Add(item);
        }

        StatusText = $"Found {Drives.Count} drives · {LargeItems.Count} large items";
        IsScanning = false;
    }
}

public sealed class DriveInfo : BaseViewModel
{
    public string Name       { get; init; } = string.Empty;
    public string RootPath   { get; init; } = string.Empty;
    public string DriveType  { get; init; } = string.Empty;
    public long   TotalBytes { get; init; }
    public long   FreeBytes  { get; init; }
    public long   UsedBytes  => TotalBytes - FreeBytes;
    public double UsedPct    => TotalBytes > 0 ? UsedBytes * 100.0 / TotalBytes : 0;
    public string UsedDisplay => $"{UsedBytes / 1_073_741_824.0:0.0} / {TotalBytes / 1_073_741_824.0:0.0} GB";
}

public sealed class FolderEntry
{
    public string Name      { get; init; } = string.Empty;
    public string Path      { get; init; } = string.Empty;
    public long   Bytes     { get; init; }
    public bool   IsFolder  { get; init; }
    public string SizeDisplay => Bytes switch
    {
        >= 1_073_741_824 => $"{Bytes / 1_073_741_824.0:0.0} GB",
        >= 1_048_576     => $"{Bytes / 1_048_576.0:0.0} MB",
        _                => $"{Bytes / 1_024.0:0} KB"
    };
}
