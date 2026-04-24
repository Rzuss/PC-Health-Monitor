using PCHealthMonitor.Helpers;
using PCHealthMonitor.Services;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows.Input;

namespace PCHealthMonitor.ViewModels;

public sealed class DiskHealthViewModel : BaseViewModel
{
    private readonly StorageService _storage;

    public DiskHealthViewModel(StorageService storage)
    {
        _storage    = storage;
        ScanCommand = new AsyncRelayCommand(ScanAsync, () => !IsScanning);
    }

    public ICommand ScanCommand { get; }

    public ObservableCollection<SmartDisk> Disks { get; } = new();

    private bool _isScanning;
    public bool IsScanning { get => _isScanning; set { SetProperty(ref _isScanning, value); AsyncRelayCommand.RaiseCanExecuteChanged(); } }

    private string _statusText = "Click Scan to read S.M.A.R.T. data";
    public string StatusText { get => _statusText; set => SetProperty(ref _statusText, value); }

    private async Task ScanAsync()
    {
        IsScanning = true;
        StatusText = "Reading S.M.A.R.T. data...";
        Disks.Clear();

        var disks = await _storage.GetSmartDataAsync();
        foreach (var d in disks) Disks.Add(d);

        StatusText = Disks.Count > 0
            ? $"Scanned {Disks.Count} disk(s)"
            : "No disks found or insufficient permissions";

        IsScanning = false;
    }
}

public sealed class SmartDisk : BaseViewModel
{
    public string Model        { get; init; } = string.Empty;
    public string SerialNumber { get; init; } = string.Empty;
    public string Interface    { get; init; } = string.Empty; // SSD / HDD / NVMe
    public long   SizeBytes    { get; init; }
    public string SizeDisplay  => $"{SizeBytes / 1_073_741_824.0:0} GB";
    public int    Temperature  { get; init; }  // °C
    public int    Health       { get; init; }  // 0–100 %
    public string Status       { get; init; } = "Unknown"; // Good / Warning / Critical

    public ObservableCollection<SmartAttribute> Attributes { get; } = new();
}

public sealed class SmartAttribute
{
    public int    Id      { get; init; }
    public string Name    { get; init; } = string.Empty;
    public long   Value   { get; init; }
    public string Display { get; init; } = string.Empty;
    public bool   IsAlert { get; init; }
}
