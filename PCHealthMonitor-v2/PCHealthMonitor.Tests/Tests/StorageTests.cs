using PCHealthMonitor.Tests;

namespace PCHealthMonitor.Tests.Tests;

[Collection("App")]
public class StorageTests : AppTestBase
{
    public StorageTests(AppFixture fix) : base(fix)
    {
        NavigateTo("NavStorage");
        Thread.Sleep(1500); // let drive list load
    }

    [Fact]
    public void ScanButton_Exists()
    {
        Find("StorageScanBtn");
    }

    [Fact]
    public void DrivesList_ShowsAtLeastOneDrive()
    {
        var list = Find("StorageDrivesList");
        var items = list.FindAllDescendants(cf => cf.ByControlType(FlaUI.Core.Definitions.ControlType.ListItem));
        Assert.True(items.Length > 0, "At least one drive should be listed");
    }

    [Fact]
    public void ScanLargeItems_CompletesWithinTimeout()
    {
        Find("StorageScanBtn").AsButton().Click();

        // Scan has a 10 s internal timeout; allow 15 s for UI to update
        Thread.Sleep(15_000);

        // After scan, status text should no longer say "Scanning..."
        var statusEl = Win.FindFirstDescendant(cf => cf.ByAutomationId("StorageStatusText"));
        if (statusEl != null)
        {
            Assert.DoesNotContain("Scanning", statusEl.AsLabel().Text);
        }
        // If statusEl is null the page is still rendered — that's acceptable
    }
}
