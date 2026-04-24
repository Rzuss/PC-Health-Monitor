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
/// Uses LibreHardwareMonitor for temperatures and Windows performance counters for load.
/// Polling interval: 2 seconds on a background thread; results marshalled to UI thread.
/// </summary>
public sealed class HardwareService : IDisposable
{
    // ── Events ───────────────────────────────────────────────────────────
    public event EventHandler<HardwareSnapshot>? SnapshotUpdated;

    // ── LibreHardwareMonitor ─────────────────────────────────────────────
    private readonly Computer _computer;
    private readonly UpdateVisitor _visitor = new();

    // ── Performance counters (for CPU/Disk load, not temp) ───────────────
    private PerformanceCounter? _cpuCounter;
    private PerformanceCounter? _diskCounter;

    // ── Timer ────────────────────────────────────────────────────────────
    private readonly DispatcherTimer _timer;
    private bool _disposed;

    public HardwareService()
    {
        // LibreHardwareMonitor — needs admin for full data; degrades gracefully
        _computer = new Computer
        {
            IsCpuEnabled     = true,
            IsMemoryEnabled  = true,
            IsStorageEnabled = true,
            IsGpuEnabled     = false, // GPU optional — added in Phase 2.1
        };

        try { _computer.Open(); } catch { /* no admin = no temps */ }

        // Performance counters — always available without elevation
        try
        {
            _cpuCounter  = new PerformanceCounter("Processor", "% Processor Time", "_Total");
            _diskCounter = new PerformanceCounter("PhysicalDisk", "% Disk Time", "_Total");
            // Warm-up first call (returns 0 on first call by design)
            _ = _cpuCounter.NextValue();
            _ = _diskCounter.NextValue();
        }
        catch { /* not critical */ }

        // Poll every 2 s on the UI dispatcher (timer fires on UI thread)
        _timer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromSeconds(2)
        };
        _timer.Tick += async (_, _) => await PollAsync();
        _timer.Start();
    }

    // ── Latest snapshot (readable without subscribing to the event) ──────
    public HardwareSnapshot Latest { get; private set; } = new();

    // ── Polling ───────────────────────────────────────────────────────────
    private async Task PollAsync()
    {
        if (_disposed) return;

        var snapshot = await Task.Run(BuildSnapshot);
        Latest = snapshot;
        SnapshotUpdated?.Invoke(this, snapshot);
    }

    private HardwareSnapshot BuildSnapshot()
    {
        var snap = new HardwareSnapshot();

        // CPU load
        try { snap.CpuLoad = Math.Min(100f, _cpuCounter?.NextValue() ?? 0f); } catch { }

        // Disk load
        try { snap.DiskLoad = Math.Min(100f, _diskCounter?.NextValue() ?? 0f); } catch { }

        // RAM used %
        try
        {
            var ramStatus = new MEMORYSTATUSEX();
            ramStatus.dwLength = (uint)Marshal.SizeOf(ramStatus);
            if (GlobalMemoryStatusEx(ref ramStatus))
            {
                snap.RamLoad      = ramStatus.dwMemoryLoad;
                snap.RamUsedGb    = (ramStatus.ullTotalPhys - ramStatus.ullAvailPhys) / 1_073_741_824.0;
                snap.RamTotalGb   = ramStatus.ullTotalPhys / 1_073_741_824.0;
            }
        }
        catch { }

        // CPU temp + more precise load via LibreHardwareMonitor
        try
        {
            _computer.Accept(_visitor);
            foreach (var hw in _computer.Hardware)
            {
                if (hw.HardwareType == HardwareType.Cpu)
                {
                    foreach (var sensor in hw.Sensors)
                    {
                        if (sensor.SensorType == SensorType.Temperature
                            && sensor.Name.Contains("Package", StringComparison.OrdinalIgnoreCase)
                            && sensor.Value.HasValue)
                        {
                            snap.CpuTempC = (float)sensor.Value.Value;
                        }
                        if (sensor.SensorType == SensorType.Load
                            && sensor.Name.Contains("Total", StringComparison.OrdinalIgnoreCase)
                            && sensor.Value.HasValue)
                        {
                            // Override perf-counter reading with LHM data (more accurate)
                            snap.CpuLoad = (float)sensor.Value.Value;
                        }
                    }
                }
            }
        }
        catch { }

        return snap;
    }

    // ── Win32 ─────────────────────────────────────────────────────────────
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MEMORYSTATUSEX
    {
        public uint   dwLength;
        public uint   dwMemoryLoad;
        public ulong  ullTotalPhys;
        public ulong  ullAvailPhys;
        public ulong  ullTotalPageFile;
        public ulong  ullAvailPageFile;
        public ulong  ullTotalVirtual;
        public ulong  ullAvailVirtual;
        public ulong  ullAvailExtendedVirtual;
    }

    // ── Dispose ───────────────────────────────────────────────────────────
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _timer.Stop();
        _cpuCounter?.Dispose();
        _diskCounter?.Dispose();
        try { _computer.Close(); } catch { }
    }
}

// ── LibreHardwareMonitor visitor ──────────────────────────────────────────
file sealed class UpdateVisitor : IVisitor
{
    public void VisitComputer(IComputer computer)  { computer.Traverse(this); }
    public void VisitHardware(IHardware hardware)  { hardware.Update(); foreach (var sub in hardware.SubHardware) sub.Accept(this); }
    public void VisitSensor(ISensor sensor)        { }
    public void VisitParameter(IParameter para)    { }
}

// ── Snapshot DTO ─────────────────────────────────────────────────────────
public sealed class HardwareSnapshot
{
    public float  CpuLoad    { get; set; }   // 0–100 %
    public float  CpuTempC   { get; set; }   // °C (0 = unavailable)
    public uint   RamLoad    { get; set; }   // 0–100 %
    public double RamUsedGb  { get; set; }
    public double RamTotalGb { get; set; }
    public float  DiskLoad   { get; set; }   // 0–100 %

    /// <summary>Computed health score 0–100 based on load / temperature.</summary>
    public int HealthScore
    {
        get
        {
            // Start perfect and subtract penalties
            double score = 100;

            // CPU load penalty (max -30)
            score -= CpuLoad * 0.30;

            // RAM load penalty (max -25)
            score -= RamLoad * 0.25;

            // CPU temp penalty: >70°C start penalizing (max -20)
            if (CpuTempC > 70)
                score -= Math.Min(20, (CpuTempC - 70) * 0.8);

            // Disk load penalty (max -15)
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
