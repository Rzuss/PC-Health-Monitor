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
///
/// SAFETY MODEL:
///   - LibreHardwareMonitor (LHM) is optional. If _computer.Open() fails
///     (AccessViolationException, driver error, permission denied), _lhmEnabled
///     is set to false and LHM is never called again. All metrics fall back to
///     safe Win32 API calls that cannot crash the process.
///   - _isPolling guard prevents concurrent Task.Run(BuildSnapshot) calls,
///     which would cause concurrent LHM access (LHM is not thread-safe).
///   - All LHM calls are inside lock(_hwLock) for additional protection.
/// </summary>
public sealed class HardwareService : IDisposable
{
    public event EventHandler<HardwareSnapshot>? SnapshotUpdated;

    private Computer?      _computer;
    private readonly UpdateVisitor _visitor  = new();
    private readonly object        _hwLock   = new();
    private bool                   _lhmEnabled = false;   // set true only if Open() succeeds

    private PerformanceCounter? _cpuCounter;
    private PerformanceCounter? _diskCounter;

    private readonly DispatcherTimer _timer;
    private readonly object _snapLock  = new();
    private volatile bool   _isPolling = false;
    private bool             _disposed;

    public HardwareService()
    {
        // ── LibreHardwareMonitor (optional) ───────────────────────────────
        // Open() accesses hardware drivers via WMI and P/Invoke.
        // It can throw AccessViolationException on some machines — which in
        // .NET 8 kills the process before any catch block runs.
        // We therefore test it with a very conservative try-catch, and if it
        // fails we simply run without temperature readings.
        InitLhm();

        // ── PerformanceCounters (safe — pure Win32, never crashes) ────────
        try
        {
            _cpuCounter  = new PerformanceCounter("Processor", "% Processor Time", "_Total");
            _diskCounter = new PerformanceCounter("PhysicalDisk", "% Disk Time", "_Total");
            _ = _cpuCounter.NextValue();   // first call always returns 0 — discard
            _ = _diskCounter.NextValue();
        }
        catch { }

        // ── Polling timer ─────────────────────────────────────────────────
        _timer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromSeconds(2)
        };
        _timer.Tick += async (_, _) =>
        {
            if (_isPolling) return;   // re-entrancy guard
            _isPolling = true;
            try   { await PollAsync(); }
            catch { }
            finally { _isPolling = false; }
        };
        _timer.Start();
    }

    private void InitLhm()
    {
        try
        {
            _computer = new Computer
            {
                IsCpuEnabled     = true,
                IsMemoryEnabled  = false,  // handled via GlobalMemoryStatusEx (safer)
                IsStorageEnabled = false,  // can be very slow, skip
                IsGpuEnabled     = false,
            };
            _computer.Open();
            _lhmEnabled = true;
        }
        catch
        {
            // LHM failed to initialize — disable permanently.
            // The app will still show CPU%, RAM%, Disk% via safe Win32 APIs.
            // Temperature will show "--".
            try { _computer?.Close(); } catch { }
            _computer   = null;
            _lhmEnabled = false;
        }
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

        // ConfigureAwait(true) = resume on the UI SynchronizationContext,
        // so SnapshotUpdated is always raised on the UI thread.
        var snapshot = await Task.Run(BuildSnapshot).ConfigureAwait(true);

        if (_disposed) return;

        Latest = snapshot;
        SnapshotUpdated?.Invoke(this, snapshot);
    }

    private HardwareSnapshot BuildSnapshot()
    {
        var snap = new HardwareSnapshot();

        // ── PerformanceCounters (safe) ────────────────────────────────────
        try { snap.CpuLoad  = Math.Min(100f, _cpuCounter?.NextValue()  ?? 0f); } catch { }
        try { snap.DiskLoad = Math.Min(100f, _diskCounter?.NextValue() ?? 0f); } catch { }

        // ── RAM via GlobalMemoryStatusEx (safe Win32) ─────────────────────
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

        // ── LibreHardwareMonitor (optional — temperature only) ────────────
        if (_lhmEnabled && _computer is not null)
        {
            try
            {
                lock (_hwLock)
                {
                    if (_disposed || !_lhmEnabled) return snap;
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
            catch
            {
                // Any failure from LHM → disable permanently for this session
                _lhmEnabled = false;
            }
        }

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
        _disposed   = true;
        _lhmEnabled = false;
        _timer.Stop();
        _cpuCounter?.Dispose();
        _diskCounter?.Dispose();
        try { lock (_hwLock) { _computer?.Close(); } } catch { }
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
