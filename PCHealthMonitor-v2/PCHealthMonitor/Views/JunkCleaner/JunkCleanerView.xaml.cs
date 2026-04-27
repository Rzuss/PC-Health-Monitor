using Microsoft.Extensions.DependencyInjection;
using PCHealthMonitor.ViewModels;
using System.Windows.Controls;

namespace PCHealthMonitor.Views.JunkCleaner;

public partial class JunkCleanerView : Page
{
    private readonly JunkCleanerViewModel _vm;

    public JunkCleanerView() : this(App.Services.GetRequiredService<JunkCleanerViewModel>()) { }

    public JunkCleanerView(JunkCleanerViewModel vm)
    {
        InitializeComponent();
        _vm = vm;
        DataContext = vm;

        // Auto-scan every time the page becomes visible (tab navigation)
        IsVisibleChanged += (_, e) =>
        {
            if (e.NewValue is true && !_vm.IsBusy && _vm.ScanCommand.CanExecute(null))
                _vm.ScanCommand.Execute(null);
        };
    }
}
