using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.UIA3;
using System.Diagnostics;

namespace PCHealthMonitor.Tests;

/// <summary>
/// Single app instance shared across the entire test run via ICollectionFixture.
///
/// WHY NOT PER-CLASS (IClassFixture)?
/// Force-killing a WPF process with AllowsTransparency=True corrupts the Windows
/// UIAutomation COM server state for the test-runner process. The next launched
/// window registers its UIA providers, but the COM server returns an empty tree
/// (children=0, descendants=0). This is not a timing problem — it persists for
/// the lifetime of the test-runner process.
///
/// WHY A SINGLE INSTANCE IS SAFE:
/// The WPF Frame navigates to a clean page between test classes (each class
/// calls NavigateTo in its constructor). The sidebar is always rendered. The
/// only risk is a test that leaves a long-running background operation — we
/// handle that with WaitFor() and per-test timeouts.
/// </summary>
public sealed class AppFixture : IDisposable
{
    private static readonly string AppPath = Path.GetFullPath(
        Path.Combine(AppContext.BaseDirectory,
            @"..\..\..\..\PCHealthMonitor\bin\x64\Release\net8.0-windows\win-x64\PCHealthMonitor.exe"));

    public Application    App        { get; }
    public UIA3Automation Auto       { get; } = new();
    public Window         MainWindow { get; }

    public AppFixture()
    {
        if (!File.Exists(AppPath))
            throw new FileNotFoundException(
                $"Build the app first (Release|x64). Expected:\n{AppPath}");

        // Kill any leftover instance before starting fresh.
        foreach (var p in Process.GetProcessesByName("PCHealthMonitor"))
        {
            try { p.Kill(); p.WaitForExit(5000); } catch { }
        }
        Thread.Sleep(1000);

        App = Application.Launch(AppPath);

        Window? win = null;
        for (int i = 0; i < 25 && win == null; i++)
        {
            Thread.Sleep(1000);
            try { win = App.GetMainWindow(Auto, TimeSpan.FromSeconds(2)); } catch { }
        }

        MainWindow = win ?? throw new TimeoutException("PCHealthMonitor main window did not appear.");
        Thread.Sleep(2500); // let WPF complete initial render + layout passes
    }

    public void Dispose()
    {
        try { App.Kill(); } catch { }
        try { App.Dispose(); } catch { }
        try { Auto.Dispose(); } catch { }
    }
}

/// <summary>
/// Base class for all test classes.
/// All classes belong to the "App" collection — they share the single AppFixture.
/// DisableTestParallelization ensures classes run one at a time.
/// </summary>
public abstract class AppTestBase
{
    protected readonly AppFixture Fix;
    protected Window Win => Fix.MainWindow;

    protected AppTestBase(AppFixture fix) => Fix = fix;

    protected void NavigateTo(string navId)
    {
        AutomationElement? btn = null;
        for (int i = 0; i < 14 && btn == null; i++)
        {
            Thread.Sleep(600);
            btn = Win.FindFirstDescendant(cf => cf.ByAutomationId(navId));
        }

        if (btn == null)
        {
            var bounds      = Win.BoundingRectangle;
            var children    = Win.FindAllChildren();
            var descendants = Win.FindAllDescendants();
            throw new Exception(
                $"'{navId}' not found after {14 * 600}ms. " +
                $"Win.Bounds={bounds}, children={children.Length}, descendants={descendants.Length}. " +
                $"First child names: [{string.Join(", ", children.Take(5).Select(c => c.AutomationId ?? c.Name ?? "(null)"))}]");
        }

        btn!.AsButton().Click();
        Thread.Sleep(1000);
    }

    protected AutomationElement Find(string automationId)
    {
        AutomationElement? el = null;
        for (int i = 0; i < 10 && el == null; i++)
        {
            Thread.Sleep(500);
            el = Win.FindFirstDescendant(cf => cf.ByAutomationId(automationId));
        }
        Assert.NotNull(el);
        return el!;
    }

    protected AutomationElement? WaitFor(string automationId, int maxMs = 12000)
    {
        var sw = Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < maxMs)
        {
            var el = Win.FindFirstDescendant(cf => cf.ByAutomationId(automationId));
            if (el != null) return el;
            Thread.Sleep(500);
        }
        return null;
    }
}
