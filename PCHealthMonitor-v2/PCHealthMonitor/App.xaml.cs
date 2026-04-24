using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using PCHealthMonitor.Services;
using PCHealthMonitor.ViewModels;
using PCHealthMonitor.Views.Dashboard;
using PCHealthMonitor.Views.Startup;
using PCHealthMonitor.Views.JunkCleaner;
using PCHealthMonitor.Views.Storage;
using PCHealthMonitor.Views.Boost;
using PCHealthMonitor.Views.DiskHealth;
using PCHealthMonitor.Views.Tools;
using PCHealthMonitor.Views.Network;
using PCHealthMonitor.Views.Settings;
using System;
using System.Windows;

namespace PCHealthMonitor;

public partial class App : Application
{
    private IHost? _host;

    public static IServiceProvider Services => ((App)Current)._host!.Services;

    // Convenience wrapper so Views can call App.Services.GetRequiredService<T>()
    // without importing Microsoft.Extensions.DependencyInjection everywhere
    public static T GetService<T>() where T : notnull
        => Services.GetRequiredService<T>();

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _host = Host.CreateDefaultBuilder()
            .ConfigureServices(ConfigureServices)
            .Build();

        await _host.StartAsync();

        var mainWindow = Services.GetRequiredService<MainWindow>();
        mainWindow.Show();
    }

    private static void ConfigureServices(IServiceCollection services)
    {
        // Services (singletons — live for app lifetime)
        services.AddSingleton<HardwareService>();
        services.AddSingleton<CleanerService>();
        services.AddSingleton<StorageService>();
        services.AddSingleton<DriverService>();
        services.AddSingleton<SchedulerService>();
        services.AddSingleton<BoostService>();
        services.AddSingleton<NetworkService>();
        services.AddSingleton<BatteryService>();
        services.AddSingleton<ReportService>();
        services.AddSingleton<LicenseService>();
        services.AddSingleton<SettingsService>();

        // ViewModels
        services.AddSingleton<MainViewModel>();
        services.AddTransient<DashboardViewModel>();
        services.AddTransient<StartupViewModel>();
        services.AddTransient<JunkCleanerViewModel>();
        services.AddTransient<StorageViewModel>();
        services.AddTransient<BoostViewModel>();
        services.AddTransient<DiskHealthViewModel>();
        services.AddTransient<ToolsViewModel>();
        services.AddTransient<NetworkViewModel>();
        services.AddTransient<SettingsViewModel>();

        // Views (transient — new instance per navigation)
        services.AddTransient<DashboardView>();
        services.AddTransient<StartupView>();
        services.AddTransient<JunkCleanerView>();
        services.AddTransient<StorageView>();
        services.AddTransient<BoostView>();
        services.AddTransient<DiskHealthView>();
        services.AddTransient<ToolsView>();
        services.AddTransient<NetworkView>();
        services.AddTransient<SettingsView>();

        // Windows
        services.AddSingleton<MainWindow>();
    }

    protected override async void OnExit(ExitEventArgs e)
    {
        if (_host is not null)
        {
            // Ensure hardware monitoring stops cleanly
            var hw = Services.GetService<HardwareService>();
            hw?.Dispose();

            await _host.StopAsync();
            _host.Dispose();
        }
        base.OnExit(e);
    }
}
