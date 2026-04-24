using PCHealthMonitor.Helpers;
using PCHealthMonitor.Services;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows.Input;

namespace PCHealthMonitor.ViewModels;

public sealed class JunkCleanerViewModel : BaseViewModel
{
    private readonly CleanerService _cleaner;

    public JunkCleanerViewModel(CleanerService cleaner)
    {
        _cleaner       = cleaner;
        ScanCommand    = new AsyncRelayCommand(ScanAsync,   () => !IsBusy);
        CleanCommand   = new AsyncRelayCommand(CleanAsync,  () => !IsBusy && TotalBytes > 0);
    }

    public ICommand ScanCommand  { get; }
    public ICommand CleanCommand { get; }

    public ObservableCollection<JunkCategory> Categories { get; } = new();

    private bool _isBusy;
    public bool IsBusy { get => _isBusy; set { SetProperty(ref _isBusy, value); AsyncRelayCommand.RaiseCanExecuteChanged(); } }

    private long _totalBytes;
    public long TotalBytes { get => _totalBytes; set => SetProperty(ref _totalBytes, value); }

    public string TotalDisplay => TotalBytes switch
    {
        >= 1_073_741_824 => $"{TotalBytes / 1_073_741_824.0:0.0} GB",
        >= 1_048_576     => $"{TotalBytes / 1_048_576.0:0.0} MB",
        _                => $"{TotalBytes / 1_024.0:0} KB"
    };

    private string _statusText = "Ready to scan";
    public string StatusText { get => _statusText; set => SetProperty(ref _statusText, value); }

    private async Task ScanAsync()
    {
        IsBusy = true;
        StatusText = "Scanning...";
        Categories.Clear();
        TotalBytes = 0;

        var result = await _cleaner.AnalyzeAsync();
        foreach (var cat in result.Categories)
        {
            Categories.Add(cat);
            TotalBytes += cat.Bytes;
        }
        OnPropertyChanged(nameof(TotalDisplay));
        StatusText = $"Found {TotalDisplay} in {Categories.Count} categories";
        IsBusy = false;
    }

    private async Task CleanAsync()
    {
        IsBusy = true;
        StatusText = "Cleaning...";
        long cleaned = await _cleaner.CleanAsync(Categories);
        TotalBytes = 0;
        OnPropertyChanged(nameof(TotalDisplay));
        StatusText = $"Cleaned successfully — freed {FormatBytes(cleaned)}";
        Categories.Clear();
        IsBusy = false;
    }

    private static string FormatBytes(long b) => b switch
    {
        >= 1_073_741_824 => $"{b / 1_073_741_824.0:0.0} GB",
        >= 1_048_576     => $"{b / 1_048_576.0:0.0} MB",
        _                => $"{b / 1_024.0:0} KB"
    };
}

public sealed class JunkCategory : BaseViewModel
{
    public string Name      { get; init; } = string.Empty;
    public long   Bytes     { get; init; }
    public int    FileCount { get; init; }
    public bool   Selected  { get; set; } = true;

    public string SizeDisplay => Bytes switch
    {
        >= 1_073_741_824 => $"{Bytes / 1_073_741_824.0:0.0} GB",
        >= 1_048_576     => $"{Bytes / 1_048_576.0:0.0} MB",
        _                => $"{Bytes / 1_024.0:0} KB"
    };
}
