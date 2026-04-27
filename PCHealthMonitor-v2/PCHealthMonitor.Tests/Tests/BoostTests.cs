using PCHealthMonitor.Tests;

namespace PCHealthMonitor.Tests.Tests;

[Collection("App")]
public class BoostTests : AppTestBase
{
    public BoostTests(AppFixture fix) : base(fix)
    {
        NavigateTo("NavBoost");
        Thread.Sleep(1500); // let process list auto-load
    }

    [Fact]
    public void RefreshAndActivate_ButtonsExist()
    {
        Find("BoostRefreshBtn");
        Find("BoostActivateBtn");
    }

    [Fact]
    public void Refresh_LoadsProcessList()
    {
        Find("BoostRefreshBtn").AsButton().Click();
        Thread.Sleep(3000);

        // Process list is a ListBox — look for list items
        var items = Win.FindAllDescendants(cf =>
            cf.ByControlType(FlaUI.Core.Definitions.ControlType.ListItem));
        Assert.True(items.Length > 0, "Process list should contain at least one running app");
    }

    [Fact]
    public void ActivateBtn_IsDisabled_WhenNoProcessSelected()
    {
        // Without selecting a process, Activate should be disabled
        var btn = Find("BoostActivateBtn").AsButton();
        Assert.False(btn.IsEnabled, "Activate should be disabled with no process selected");
    }
}
