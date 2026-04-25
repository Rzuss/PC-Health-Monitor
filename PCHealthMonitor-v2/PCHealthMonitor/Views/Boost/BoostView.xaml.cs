using Microsoft.Extensions.DependencyInjection;
using PCHealthMonitor.ViewModels;
using System.Windows.Controls;

namespace PCHealthMonitor.Views.Boost;

public partial class BoostView : Page
{
    public BoostView() : this(App.Services.GetRequiredService<BoostViewModel>()) { }

    public BoostView(BoostViewModel vm)
    {
        InitializeComponent();
        DataContext = vm;
    }
}
