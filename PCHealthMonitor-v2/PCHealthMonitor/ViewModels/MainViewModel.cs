using PCHealthMonitor.Services;

namespace PCHealthMonitor.ViewModels;

public sealed class MainViewModel : BaseViewModel
{
    private readonly ProFeatureService _pro;

    public MainViewModel(ProFeatureService pro)
    {
        _pro = pro;
    }

    /// True when a valid Pro license is active.
    /// Bound to the "PRO" badge visibility in MainWindow.xaml.
    public bool IsPro => _pro.IsPro;

    /// Refreshes IsPro binding — call after activation/deactivation.
    public void NotifyProStatusChanged()
        => OnPropertyChanged(nameof(IsPro));
}
