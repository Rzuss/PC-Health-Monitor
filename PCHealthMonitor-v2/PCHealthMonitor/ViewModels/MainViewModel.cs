using PCHealthMonitor.Helpers;
using PCHealthMonitor.Services;
using System.Windows.Input;

namespace PCHealthMonitor.ViewModels;

public sealed class MainViewModel : BaseViewModel
{
    private readonly LicenseService _license;

    public MainViewModel(LicenseService license)
    {
        _license = license;
    }

    private bool _isPro;
    public bool IsPro
    {
        get => _isPro;
        set => SetProperty(ref _isPro, value);
    }
}
