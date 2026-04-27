using PCHealthMonitor.Tests;

namespace PCHealthMonitor.Tests.Tests;

[Collection("App")]
public class JunkCleanerTests : AppTestBase
{
    public JunkCleanerTests(AppFixture fix) : base(fix)
    {
        NavigateTo("NavJunkCleaner");
    }

    [Fact]
    public void ScanAndClean_ButtonsExist()
    {
        Find("JunkScanBtn");
        Find("JunkCleanBtn");
    }

    [Fact]
    public void Scan_PopulatesCategoriesGrid()
    {
        Find("JunkScanBtn").AsButton().Click();

        // Wait up to 35 s for the Clean button to become enabled — that signals scan completed with results.
        var cleanBtn = Find("JunkCleanBtn").AsButton();
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (!cleanBtn.IsEnabled && sw.ElapsedMilliseconds < 35_000)
            Thread.Sleep(500);

        Assert.True(cleanBtn.IsEnabled, "Clean button should be enabled after scan finds categories");

        // Verify the grid exists and is visible.
        var grid = Find("JunkCategoriesGrid");
        Assert.False(grid.IsOffscreen);
    }

    [Fact]
    public void CleanBtn_IsEnabled_AfterScan()
    {
        Find("JunkScanBtn").AsButton().Click();
        Thread.Sleep(5000); // brief wait for scan progress

        var cleanBtn = Find("JunkCleanBtn").AsButton();
        // Clean button should become enabled once categories are found
        Assert.True(cleanBtn.IsEnabled, "Clean button should be enabled after scan");
    }
}
