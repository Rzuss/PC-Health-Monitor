using PCHealthMonitor.ViewModels;
using System.Windows.Controls;

namespace PCHealthMonitor.Views.JunkCleaner;

public partial class JunkCleanerView : Page
{
    public JunkCleanerView() : this(App.Services.GetRequiredService<JunkCleanerViewModel>()) { }

    public JunkCleanerView(JunkCleanerViewModel vm)
    {
        InitializeComponent();
        DataContext = vm;
    }
}
