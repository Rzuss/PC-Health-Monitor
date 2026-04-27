using PCHealthMonitor.Tests;

namespace PCHealthMonitor.Tests.Tests;

/// <summary>
/// Verifies that every sidebar nav button exists and navigates without crashing.
/// </summary>
[Collection("App")]
public class NavigationTests : AppTestBase
{
    public NavigationTests(AppFixture fix) : base(fix) { }

    [Theory]
    [InlineData("NavDashboard")]
    [InlineData("NavStartup")]
    [InlineData("NavJunkCleaner")]
    [InlineData("NavStorage")]
    [InlineData("NavBoost")]
    [InlineData("NavDiskHealth")]
    [InlineData("NavTools")]
    [InlineData("NavNetwork")]
    [InlineData("NavSettings")]
    public void NavButton_Exists_And_IsClickable(string navId)
    {
        var btn = Win.FindFirstDescendant(cf => cf.ByAutomationId(navId));
        Assert.NotNull(btn);
        btn!.AsButton().Click();
        Thread.Sleep(500);
        // If we get here without an exception the page loaded without crashing
    }
}
