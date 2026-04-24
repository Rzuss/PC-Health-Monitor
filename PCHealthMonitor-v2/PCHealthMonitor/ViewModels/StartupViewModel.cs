using PCHealthMonitor.Helpers;
using PCHealthMonitor.Services;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows.Input;

namespace PCHealthMonitor.ViewModels;

public sealed class StartupViewModel : BaseViewModel
{
    private readonly SchedulerService _scheduler;

    public StartupViewModel(SchedulerService scheduler)
    {
        _scheduler = scheduler;
        LoadCommand  = new AsyncRelayCommand(LoadAsync);
        ToggleCommand = new RelayCommand<StartupEntry>(Toggle);
    }

    public ICommand LoadCommand   { get; }
    public ICommand ToggleCommand { get; }

    public ObservableCollection<StartupEntry> Entries { get; } = new();

    private bool _isLoading;
    public bool IsLoading { get => _isLoading; set => SetProperty(ref _isLoading, value); }

    private async Task LoadAsync()
    {
        IsLoading = true;
        Entries.Clear();
        var items = await _scheduler.GetStartupEntriesAsync();
        foreach (var e in items) Entries.Add(e);
        IsLoading = false;
    }

    private void Toggle(StartupEntry? entry)
    {
        if (entry is null) return;
        entry.IsEnabled = !entry.IsEnabled;
        _scheduler.SetStartupEntry(entry);
    }
}

public sealed class StartupEntry : BaseViewModel
{
    public string Name        { get; init; } = string.Empty;
    public string Publisher   { get; init; } = string.Empty;
    public string Path        { get; init; } = string.Empty;
    public string Impact      { get; init; } = "Low"; // Low / Medium / High

    private bool _isEnabled;
    public bool IsEnabled
    {
        get => _isEnabled;
        set => SetProperty(ref _isEnabled, value);
    }
}
