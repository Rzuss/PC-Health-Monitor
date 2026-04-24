using PCHealthMonitor.Helpers;
using PCHealthMonitor.Services;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows.Input;

namespace PCHealthMonitor.ViewModels;

public sealed class NetworkViewModel : BaseViewModel
{
    private readonly NetworkService _network;

    public NetworkViewModel(NetworkService network)
    {
        _network    = network;
        ScanCommand = new AsyncRelayCommand(ScanAsync, () => !IsScanning);
    }

    public ICommand ScanCommand { get; }

    public ObservableCollection<NetworkAdapterInfo> Adapters     { get; } = new();
    public ObservableCollection<ActiveConnection>   Connections  { get; } = new();

    private bool _isScanning;
    public bool IsScanning { get => _isScanning; set { SetProperty(ref _isScanning, value); AsyncRelayCommand.RaiseCanExecuteChanged(); } }

    private string _publicIp = "--";
    public string PublicIp { get => _publicIp; set => SetProperty(ref _publicIp, value); }

    private long _downloadBps;
    public long DownloadBps { get => _downloadBps; set => SetProperty(ref _downloadBps, value); }

    private long _uploadBps;
    public long UploadBps { get => _uploadBps; set => SetProperty(ref _uploadBps, value); }

    public string DownloadDisplay => FormatSpeed(DownloadBps);
    public string UploadDisplay   => FormatSpeed(UploadBps);

    private string _statusText = "Click Scan to analyze network";
    public string StatusText { get => _statusText; set => SetProperty(ref _statusText, value); }

    private async Task ScanAsync()
    {
        IsScanning = true;
        StatusText = "Scanning network...";
        Adapters.Clear();
        Connections.Clear();

        var result = await _network.ScanAsync();
        foreach (var a in result.Adapters)    Adapters.Add(a);
        foreach (var c in result.Connections) Connections.Add(c);

        PublicIp     = result.PublicIp;
        DownloadBps  = result.DownloadBps;
        UploadBps    = result.UploadBps;
        OnPropertyChanged(nameof(DownloadDisplay));
        OnPropertyChanged(nameof(UploadDisplay));

        StatusText = $"{Adapters.Count} adapter(s) · {Connections.Count} active connection(s)";
        IsScanning = false;
    }

    private static string FormatSpeed(long bps) => bps switch
    {
        >= 1_000_000 => $"{bps / 1_000_000.0:0.0} Mbps",
        >= 1_000     => $"{bps / 1_000.0:0.0} Kbps",
        _            => $"{bps} bps"
    };
}

public sealed class NetworkAdapterInfo
{
    public string Name        { get; init; } = string.Empty;
    public string IpAddress   { get; init; } = string.Empty;
    public string MacAddress  { get; init; } = string.Empty;
    public string Status      { get; init; } = string.Empty;
    public string Speed       { get; init; } = string.Empty;
}

public sealed class ActiveConnection
{
    public string Protocol    { get; init; } = string.Empty;
    public string LocalPort   { get; init; } = string.Empty;
    public string RemoteAddr  { get; init; } = string.Empty;
    public string RemotePort  { get; init; } = string.Empty;
    public string State       { get; init; } = string.Empty;
    public string ProcessName { get; init; } = string.Empty;
}
