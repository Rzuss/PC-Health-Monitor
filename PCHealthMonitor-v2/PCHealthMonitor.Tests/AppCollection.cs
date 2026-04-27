using Xunit;

// Single app instance for the entire test run — classes share AppFixture via ICollectionFixture.
// DisableTestParallelization ensures only one test class runs at a time.
[assembly: CollectionBehavior(DisableTestParallelization = true)]

[CollectionDefinition("App")]
public class AppCollection : ICollectionFixture<PCHealthMonitor.Tests.AppFixture> { }
