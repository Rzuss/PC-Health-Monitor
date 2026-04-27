using PCHealthMonitor.Tests;

namespace PCHealthMonitor.Tests.Tests;

[Collection("App")]
public class StartupTests : AppTestBase
{
    public StartupTests(AppFixture fix) : base(fix)
    {
        NavigateTo("NavStartup");
    }

    [Fact]
    public void RefreshButton_Exists()
    {
        Find("StartupRefreshBtn");
    }

    [Fact]
    public void Refresh_LoadsEntries()
    {
        Find("StartupRefreshBtn").AsButton().Click();

        // Wait for entries to populate (registry read is fast)
        Thread.Sleep(2000);
        var list = Find("StartupList");
        var items = list.FindAllDescendants(cf => cf.ByControlType(FlaUI.Core.Definitions.ControlType.ListItem));
        Assert.True(items.Length > 0, "Startup list should have at least one entry");
    }

    [Fact]
    public void StartupList_Exists_And_IsVisible()
    {
        var list = Find("StartupList");
        Assert.False(list.IsOffscreen);
    }
}
