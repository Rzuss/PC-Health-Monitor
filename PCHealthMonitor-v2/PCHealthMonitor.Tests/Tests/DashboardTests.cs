using PCHealthMonitor.Tests;

namespace PCHealthMonitor.Tests.Tests;

[Collection("App")]
public class DashboardTests : AppTestBase
{
    public DashboardTests(AppFixture fix) : base(fix)
    {
        NavigateTo("NavDashboard");
    }

    [Fact]
    public void ScanButton_Exists()
    {
        Find("DashboardScanBtn");
    }

    [Fact]
    public void ScoreNumber_Exists_And_IsVisible()
    {
        var score = Find("DashboardScoreNumber");
        Assert.True(score.IsOffscreen == false || score.BoundingRectangle.Width > 0);
    }

    [Fact]
    public void ScanNow_UpdatesScore()
    {
        var scanBtn = Find("DashboardScanBtn").AsButton();
        scanBtn.Click();

        // Wait up to 12 s for the score to update from "--"
        var scoreEl = WaitFor("DashboardScoreNumber", maxMs: 12_000);
        Assert.NotNull(scoreEl);
        var text = scoreEl!.AsLabel().Text;
        Assert.False(string.IsNullOrWhiteSpace(text));
        Assert.NotEqual("--", text);
    }

    [Fact]
    public void CpuLoadLabel_Exists()
    {
        var el = Win.FindFirstDescendant(cf => cf.ByName("CPU"));
        Assert.NotNull(el);
    }
}
