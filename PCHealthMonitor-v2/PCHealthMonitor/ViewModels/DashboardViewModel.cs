using PCHealthMonitor.Helpers;
using PCHealthMonitor.Services;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows.Input;

namespace PCHealthMonitor.ViewModels;

public sealed class DashboardViewModel : BaseViewModel
{
    private readonly HardwareService _hardware;
    private readonly CleanerService  _cleaner;

    public DashboardViewModel(HardwareService hardware, CleanerService cleaner)
    {
        _hardware = hardware;
        _cleaner  = cleaner;
        RunQuickScanCommand = new AsyncRelayCommand(RunQuickScanAsync);
    }

    public ICommand RunQuickScanCommand { get; }

    private bool _isScanning;
    public bool IsScanning { get => _isScanning; set => SetProperty(ref _isScanning, value); }

    private int _issueCount;
    public int IssueCount { get => _issueCount; set => SetProperty(ref _issueCount, value); }

    private long _junkBytes;
    public long JunkBytes
    {
        get => _junkBytes;
        set { SetProperty(ref _junkBytes, value); OnPropertyChanged(nameof(JunkDisplay)); }
    }

    public string JunkDisplay => JunkBytes switch
    {
        >= 1_073_741_824 => $"{JunkBytes / 1_073_741_824.0:0.0} GB",
        >= 1_048_576     => $"{JunkBytes / 1_048_576.0:0.0} MB",
        >= 1_024         => $"{JunkBytes / 1_024.0:0.0} KB",
        _                => $"{JunkBytes} B"
    };

    public ObservableCollection<AlertItem> Alerts { get; } = new();

    // ── Quick scan — all collection updates happen on UI thread via OnUI() ──
    private async Task RunQuickScanAsync()
    {
        if (IsScanning) return;
        IsScanning = true;
        OnUI(Alerts.Clear);

        try
        {
            var result = await _cleaner.AnalyzeAsync();
            JunkBytes  = result.TotalBytes;
            IssueCount = result.FileCount;

            var snap = _hardware.Latest;

            if (snap.CpuTempC > 80)
                OnUI(() => Alerts.Add(new AlertItem("🌡️", $"CPU temperature is high: {snap.CpuTempC:0}°C")));
            if (snap.RamLoad > 85)
                OnUI(() => Alerts.Add(new AlertItem("⚠️", $"Memory usage is high: {snap.RamLoad}%")));
            if (result.TotalBytes > 500_000_000)
                OnUI(() => Alerts.Add(new AlertItem("🗑️", $"{JunkDisplay} of junk files found")));
        }
        finally
        {
            IsScanning = false;
        }
    }
}

public record AlertItem(string Icon, string Message);
