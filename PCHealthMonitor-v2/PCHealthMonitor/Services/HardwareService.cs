using LibreHardwareMonitor.Hardware;
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Threading;

namespace PCHealthMonitor.Services;

/// <summary>
/// Provides real-time hardware metrics: CPU%, RAM%, Disk%, CPU temperature.
/// Thread-safe: uses _isPolling guard to prevent concurrent LibreHardwareMonitor access.
/// </summary>
public sealed class HardwareService : IDisposable
{
    public event EventHandler<HardwareSnapshot>? SnapshotUpdated;

    private readonly Computer     _computer;
    private readonly UpdateVisitor _visitor = new();
    private readonly object        _hwLock  = new();   // serialise LibreHardwareMonitor calls

    private PerformanceCounter? _cpuCounter;
    private PerformanceCounter? _diskCounter;

    private readonly DispatcherTimer _timer;
    private readonly object _snapLock  = new();
    private volatile bool   _isPolling = false;   // re-entrancy guard
    private bool _disposed;

    public HardwareService()
    {
        _computer = new Computer
        {
            IsCpuEnabled     = true,
            IsMemoryEnabled  = true,
            IsStorageEnabled = true,
            IsGpuEnabled     = false,
        };

        try { _computer.Open(); } catch { /* driver unavailable — metrics degrade gracefully */ }

        try
        {
            _cpuCounter  = new PerformanceCounter("Processor", "% Processor Time", "_Total");
            _diskCounter = new PerformanceCounter("PhysicalDisk", "% Disk Time", "_Total");
            // First call always returns 0 — discard it
            _ = _cpuCounter.NextValue();
            _ = _diskCounter.NextValue();
        }
        catch { }

        _timer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromSeconds(2)
        };

        // CRITICAL FIX: use _isPolling guard so we NEVER start a new poll
        // while the previous Task.Run(BuildSnapshot) is still executing.
        // Without this guard, concurrent calls to _computer.Accept() crash the
        // LibreHardwareMonitor native layer with an AccessViolationException
        // that bypasses all catch blocks and kills the process silently.
        _timer.Tick += async (_, _) =>
        {
            if (_isPolling) return;   // skip this tick — previous poll still running
            _isPolling = true;
            try   { await PollAsync(); }
            catch { /* belt-and-suspenders — exceptions are already swallowed inside */ }
            finally { _isPolling = false; }
        };
        _timer.Start();
    }

    // ── Thread-safe Latest snapshot ───────────────────────────────────────
    private HardwareSnapshot _latest = new();
    public HardwareSnapshot Latest
    {
        get { lock (_snapLock) { return _latest; } }
        private set { lock (_snapLock) { _latest = value; } }
    }

    private async Task PollAsync()
    {
        if (_disposed) return;

        var snapshot = await Task.Run(BuildSnapshot).ConfigureAwait(true);
        // ConfigureAwait(true) = resume on the captured (UI) SynchronizationContext,
        // so SnapshotUpdated is always raised on the UI thread.

        if (_disposed) return;

        Latest = snapshot;
        SnapshotUpdated?.Invoke(this, snapshot);
    }

    private HardwareSnapshot BuildSnapshot()
    {
        // This method runs on a threadpool thread.
        // _hwLock prevents concurrent LibreHardwareMonitor access
        // (e.g., if somehow two polls start before the guard is set).
        var snap = new HardwareSnapshot();

        try { snap.CpuLoad  = Math.Min(100f, _cpuCounter?.NextValue()  ?? 0f); } catch { }
        try { snap.DiskLoad = Math.Min(100f, _diskCounter?.NextValue() ?? 0f); } catch { }

        try
        {
            var ramStatus = new MEMORYSTATUSEX();
            ramStatus.dwLength = (uint)Marshal.SizeOf(ramStatus);
            if (GlobalMemoryStatusEx(ref ramStatus))
            {
                snap.RamLoad    = ramStatus.dwMemoryLoad;
                snap.RamUsedGb  = (ramStatus.ullTotalPhys - ramStatus.ullAvailPhys) / 1_073_741_824.0;
                snap.RamTotalGb = ramStatus.ullTotalPhys / 1_073_741_824.0;
            }
        }
        catch { }

        // LibreHardwareMonitor — lock protects against concurrent access
        try
        {
            lock (_hwLock)
            {
                if (_disposed) return snap;
                _computer.Accept(_visitor);
                foreach (var hw in _computer.Hardware)
                {
                    if (hw.HardwareType != HardwareType.Cpu) continue;
                    foreach (var sensor in hw.Sensors)
                    {
                        if (sensor.SensorType == SensorType.Temperature
                            && sensor.Name.Contains("Package", StringComparison.OrdinalIgnoreCase)
                            && sensor.Value.HasValue)
                            snap.CpuTempC = (float)sensor.Value.Value;

                        if (sensor.SensorType == SensorType.Load
                            && sensor.Name.Contains("Total", StringComparison.OrdinalIgnoreCase)
                            && sensor.Value.HasValue)
                            snap.CpuLoad = (float)sensor.Value.Value;
                    }
                }
            }
        }
        catch { /* hardware driver error — degrade gracefully */ }

        return snap;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MEMORYSTATUSEX
    {
        public uint  dwLength;
        public uint  dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _timer.Stop();
        _cpuCounter?.Dispose();
        _diskCounter?.Dispose();
        try { lock (_hwLock) { _computer.Close(); } } catch { }
    }
}

internal sealed class UpdateVisitor : IVisitor
{
    public void VisitComputer(IComputer computer)  { computer.Traverse(this); }
    public void VisitHardware(IHardware hardware)  { hardware.Update(); foreach (var sub in hardware.SubHardware) sub.Accept(this); }
    public void VisitSensor(ISensor sensor)        { }
    public void VisitParameter(IParameter para)    { }
}

public sealed class HardwareSnapshot
{
    public float  CpuLoad    { get; set; }
    public float  CpuTempC   { get; set; }
    public uint   RamLoad    { get; set; }
    public double RamUsedGb  { get; set; }
    public double RamTotalGb { get; set; }
    public float  DiskLoad   { get; set; }

    public int HealthScore
    {
        get
        {
            double score = 100;
            score -= CpuLoad  * 0.30;
            score -= RamLoad  * 0.25;
            if (CpuTempC > 70) score -= Math.Min(20, (CpuTempC - 70) * 0.8);
            score -= DiskLoad * 0.15;
            return (int)Math.Clamp(score, 0, 100);
        }
    }

    public string HealthGrade => HealthScore switch
    {
        >= 80 => "Excellent",
        >= 60 => "Good",
        >= 40 => "Fair",
        >= 20 => "Poor",
        _     => "Critical"
    };
}
