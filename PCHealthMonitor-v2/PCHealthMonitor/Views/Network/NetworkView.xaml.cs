using Microsoft.Extensions.DependencyInjection;
using PCHealthMonitor.ViewModels;
using System.Windows.Controls;

namespace PCHealthMonitor.Views.Network;

public partial class NetworkView : Page
{
    public NetworkView() : this(App.Services.GetRequiredService<NetworkViewModel>()) { }

    public NetworkView(NetworkViewModel vm)
    {
        InitializeComponent();
        DataContext = vm;
    }
}
