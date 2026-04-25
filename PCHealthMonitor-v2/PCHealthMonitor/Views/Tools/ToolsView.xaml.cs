using Microsoft.Extensions.DependencyInjection;
using PCHealthMonitor.ViewModels;
using System.Windows.Controls;

namespace PCHealthMonitor.Views.Tools;

public partial class ToolsView : Page
{
    public ToolsView() : this(App.Services.GetRequiredService<ToolsViewModel>()) { }

    public ToolsView(ToolsViewModel vm)
    {
        InitializeComponent();
        DataContext = vm;
    }
}
