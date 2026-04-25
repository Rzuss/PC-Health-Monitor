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
using System.IO;
using System.Windows;

namespace PCHealthMonitor;

public partial class App : Application
{
    private IHost? _host;

    public static IServiceProvider Services => ((App)Current)._host!.Services;

    public static T GetService<T>() where T : notnull
        => Services.GetRequiredService<T>();

    protected override async void OnStartup(StartupEventArgs e)
    {
        // CRITICAL FIX: Register ALL exception handlers BEFORE base.OnStartup.
        // Previously they were registered after base.OnStartup, meaning any exception
        // during DI/host setup was completely unhandled and killed the process silently.

        // 1. UI-thread exceptions (most common crash source)
        DispatcherUnhandledException += (_, ex) =>
        {
            WriteCrashLog("DispatcherUnhandledException", ex.Exception);
            MessageBox.Show(
                $"An unexpected error occurred:\n\n{ex.Exception.Message}",
                "PC Health Monitor — Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
            ex.Handled = true;   // keep app alive
        };

        // 2. Non-UI thread CLR exceptions
        AppDomain.CurrentDomain.UnhandledException += (_, ex) =>
        {
            var err = ex.ExceptionObject is Exception e2 ? e2 : new Exception(ex.ExceptionObject?.ToString());
            WriteCrashLog("UnhandledException (fatal=" + ex.IsTerminating + ")", err);
            if (!ex.IsTerminating)
            {
                MessageBox.Show($"Fatal background error:\n\n{err.Message}",
                    "PC Health Monitor", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        };

        // 3. Fire-and-forget Task exceptions (prevents silent process termination)
        System.Threading.Tasks.TaskScheduler.UnobservedTaskException += (_, ex) =>
        {
            WriteCrashLog("UnobservedTaskException", ex.Exception);
            ex.SetObserved();
        };

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
            var hw = Services.GetService<HardwareService>();
            hw?.Dispose();

            await _host.StopAsync();
            _host.Dispose();
        }
        base.OnExit(e);
    }

    // ── Crash log ─────────────────────────────────────────────────────────
    private static void WriteCrashLog(string source, Exception ex)
    {
        try
        {
            var logDir  = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "PCHealthMonitor", "Logs");
            Directory.CreateDirectory(logDir);
            var logFile = Path.Combine(logDir, "crash.log");
            var line    = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] [{source}] {ex.GetType().Name}: {ex.Message}\n{ex.StackTrace}\n{new string('-', 80)}\n";
            File.AppendAllText(logFile, line);
        }
        catch { /* log write failed — don't crash inside the crash handler */ }
    }
}
