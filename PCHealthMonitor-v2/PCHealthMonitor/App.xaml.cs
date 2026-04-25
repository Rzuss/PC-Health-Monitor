using Hardcodet.Wpf.TaskbarNotification;
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
using System.Linq;
using System.Windows;
using System.Windows.Media.Imaging;

namespace PCHealthMonitor;

public partial class App : Application
{
    private IHost? _host;

    public static IServiceProvider Services => ((App)Current)._host!.Services;

    public static T GetService<T>() where T : notnull
        => Services.GetRequiredService<T>();

    protected override async void OnStartup(StartupEventArgs e)
    {
        // ── Exception handlers — registered BEFORE base.OnStartup ────────────
        DispatcherUnhandledException += (_, ex) =>
        {
            WriteCrashLog("DispatcherUnhandledException", ex.Exception);
            MessageBox.Show(
                $"An unexpected error occurred:\n\n{ex.Exception.Message}",
                "PC Health Monitor — Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
            ex.Handled = true;
        };

        AppDomain.CurrentDomain.UnhandledException += (_, ex) =>
        {
            var err = ex.ExceptionObject is Exception e2
                ? e2
                : new Exception(ex.ExceptionObject?.ToString());
            WriteCrashLog("UnhandledException (fatal=" + ex.IsTerminating + ")", err);
            if (!ex.IsTerminating)
                MessageBox.Show($"Fatal background error:\n\n{err.Message}",
                    "PC Health Monitor", MessageBoxButton.OK, MessageBoxImage.Error);
        };

        System.Threading.Tasks.TaskScheduler.UnobservedTaskException += (_, ex) =>
        {
            WriteCrashLog("UnobservedTaskException", ex.Exception);
            ex.SetObserved();
        };

        base.OnStartup(e);

        // ── Integrity check (passive, logged) ────────────────────────────────
        _ = IntegrityService.Check();   // fire-and-forget; result written to integrity.log

        // ── Build DI host ────────────────────────────────────────────────────
        _host = Host.CreateDefaultBuilder()
            .ConfigureServices(ConfigureServices)
            .Build();

        await _host.StartAsync();

        // ── /silent mode — scheduled auto-cleanup, no UI window ──────────────
        bool isSilent = e.Args.Any(a =>
            a.Equals("/silent",   StringComparison.OrdinalIgnoreCase) ||
            a.Equals("--silent",  StringComparison.OrdinalIgnoreCase));

        if (isSilent)
        {
            ShutdownMode = ShutdownMode.OnExplicitShutdown;
            await RunSilentCleanupAsync();
            Shutdown(0);
            return;
        }

        // ── Normal startup ───────────────────────────────────────────────────
        var mainWindow = Services.GetRequiredService<MainWindow>();
        mainWindow.Show();
    }

    // ── Silent cleanup mode ───────────────────────────────────────────────────
    // Called when launched by Task Scheduler with /silent argument.
    // Scans and cleans all junk categories, then shows a system tray balloon
    // notification with the result and exits.
    private async Task RunSilentCleanupAsync()
    {
        TaskbarIcon? tray = null;
        try
        {
            var cleaner = Services.GetRequiredService<CleanerService>();

            // 1. Scan
            var result = await cleaner.AnalyzeAsync();

            // 2. Mark all found categories as selected and clean
            foreach (var cat in result.Categories)
                cat.Selected = true;

            var freed = await cleaner.CleanAsync(result.Categories);

            // 3. Write cleanup log
            WriteCleanupLog(freed, result.Categories.Count);

            // 4. Show system tray balloon notification
            tray = new TaskbarIcon
            {
                IconSource = new BitmapImage(
                    new Uri("pack://application:,,,/Assets/icon.ico")),
                ToolTipText = "PC Health Monitor"
            };

            var mbFreed  = freed / 1_048_576.0;
            var message  = freed > 0
                ? $"Auto-cleanup complete · {mbFreed:0.0} MB freed from {result.Categories.Count} categories"
                : "Auto-cleanup ran · Nothing to clean this time";

            tray.ShowBalloonTip("PC Health Monitor", message, BalloonIcon.Info);

            // 5. Keep process alive long enough for the balloon to be visible
            await System.Threading.Tasks.Task.Delay(6_000);
        }
        catch (Exception ex)
        {
            WriteCrashLog("SilentCleanup", ex);
        }
        finally
        {
            tray?.Dispose();
        }
    }

    // ── DI registration ───────────────────────────────────────────────────────
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
        services.AddSingleton<SystemInfoService>();

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

        // Views (singleton — one instance per view, reused across navigations)
        services.AddSingleton<DashboardView>();
        services.AddSingleton<StartupView>();
        services.AddSingleton<JunkCleanerView>();
        services.AddSingleton<StorageView>();
        services.AddSingleton<BoostView>();
        services.AddSingleton<DiskHealthView>();
        services.AddSingleton<ToolsView>();
        services.AddSingleton<NetworkView>();
        services.AddSingleton<SettingsView>();

        // Windows
        services.AddSingleton<MainWindow>();
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    protected override async void OnExit(ExitEventArgs e)
    {
        if (_host is not null)
        {
            Services.GetService<HardwareService>()?.Dispose();
            await _host.StopAsync();
            _host.Dispose();
        }
        base.OnExit(e);
    }

    // ── Crash log ─────────────────────────────────────────────────────────────
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
        catch { }
    }

    // ── Cleanup log ───────────────────────────────────────────────────────────
    private static void WriteCleanupLog(long freedBytes, int categoryCount)
    {
        try
        {
            var logDir  = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "PCHealthMonitor", "Logs");
            Directory.CreateDirectory(logDir);
            var logFile = Path.Combine(logDir, "cleanup.log");
            var mb      = freedBytes / 1_048_576.0;
            var line    = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] [AutoClean] Freed {mb:0.0} MB across {categoryCount} categories\n";
            File.AppendAllText(logFile, line);
        }
        catch { }
    }
}
