using PCHealthMonitor.Tests;

namespace PCHealthMonitor.Tests.Tests;

[Collection("App")]
public class NetworkTests : AppTestBase
{
    public NetworkTests(AppFixture fix) : base(fix)
    {
        NavigateTo("NavNetwork");
    }

    [Fact]
    public void ScanButton_Exists()
    {
        Find("NetworkScanBtn");
    }

    [Fact]
    public void Scan_PopulatesPublicIp()
    {
        Find("NetworkScanBtn").AsButton().Click();

        // Network scan takes ~2 s (1 s throughput + HTTP)
        var ipEl = WaitFor("NetworkPublicIp", maxMs: 10_000);
        Assert.NotNull(ipEl);

        var text = ipEl!.AsLabel().Text;
        Assert.False(string.IsNullOrWhiteSpace(text));
        Assert.NotEqual("--", text);
    }

    [Fact]
    public void Scan_PopulatesConnectionsGrid()
    {
        Find("NetworkScanBtn").AsButton().Click();
        Thread.Sleep(5000);

        var grid = Find("NetworkConnectionsGrid");
        var rows = grid.FindAllDescendants(cf =>
            cf.ByControlType(FlaUI.Core.Definitions.ControlType.DataItem));
        Assert.True(rows.Length > 0, "Active connections grid should have rows after scan");
    }
}
