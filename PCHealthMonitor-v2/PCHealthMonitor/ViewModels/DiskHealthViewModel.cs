using PCHealthMonitor.Helpers;
using PCHealthMonitor.Services;
using System.Threading.Tasks;

namespace PCHealthMonitor.ViewModels;

/// <summary>
/// ViewModel for the System Info page (replaces Disk Health).
/// Loads static hardware/OS data once, then keeps CPU/RAM live via HardwareService.
/// </summary>
public sealed class DiskHealthViewModel : BaseViewModel
{
    private readonly SystemInfoService _sysInfo;
    private readonly HardwareService   _hardware;

    public DiskHealthViewModel(SystemInfoService sysInfo, HardwareService hardware)
    {
        _sysInfo  = sysInfo;
        _hardware = hardware;
    }

    // ── Snapshot (single object, all UI binds to it) ─────────────────────
    private SystemInfoSnapshot? _snapshot;
    public SystemInfoSnapshot? Snapshot
    {
        get => _snapshot;
        private set => SetProperty(ref _snapshot, value);
    }

    private bool _isLoading = true;
    public bool IsLoading { get => _isLoading; set => SetProperty(ref _isLoading, value); }

    // ── Called by View on Loaded ──────────────────────────────────────────
    public async Task LoadAsync()
    {
        // Always re-subscribe first — Unsubscribe() may have been called when the
        // user navigated away. Remove before adding to prevent double-subscription.
        _hardware.SnapshotUpdated -= OnHardwareUpdate;
        _hardware.SnapshotUpdated += OnHardwareUpdate;

        if (Snapshot is not null)
        {
            // Static data already loaded — just refresh live metrics and return
            OnHardwareUpdate(null, _hardware.Latest);
            return;
        }

        IsLoading = true;
        var snap  = await _sysInfo.GetSnapshotAsync();

        // Inject live metrics from latest hardware snapshot
        var hw = _hardware.Latest;
        snap.CpuLoad    = hw.CpuLoad;
        snap.CpuTempC   = hw.CpuTempC;
        snap.RamTotalGb = hw.RamTotalGb;
        snap.RamUsedGb  = hw.RamUsedGb;
        snap.RamLoadPct = hw.RamLoad;

        Snapshot  = snap;
        IsLoading = false;
    }

    public void Unsubscribe() =>
        _hardware.SnapshotUpdated -= OnHardwareUpdate;

    private void OnHardwareUpdate(object? sender, HardwareSnapshot hw)
    {
        if (Snapshot is null) return;
        Snapshot.CpuLoad    = hw.CpuLoad;
        Snapshot.CpuTempC   = hw.CpuTempC;
        Snapshot.RamTotalGb = hw.RamTotalGb;
        Snapshot.RamUsedGb  = hw.RamUsedGb;
        Snapshot.RamLoadPct = hw.RamLoad;
        // Notify UI that live display strings changed
        OnPropertyChanged(nameof(Snapshot));
    }
}
