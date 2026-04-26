using System;
using System.Collections.Generic;
using System.Linq;

namespace PCHealthMonitor.Services;

// ─────────────────────────────────────────────────────────────────────────────
// MetricsHistoryService — ring buffer for historical CPU/RAM/Disk data.
//
// Storage strategy:
//   • Raw ring  : last 1,800 samples at 2-second poll interval = 1 hour of raw data
//   • Minute ring: one aggregated point per minute, kept for 24 hours (1,440 pts)
//   • 5-min ring : one point per 5 minutes, kept for 7 days (2,016 pts)
//   • 15-min ring: one point per 15 minutes, kept for 30 days (2,880 pts)
//
// No disk persistence — history is built up fresh each session.
// The HardwareService fires SnapshotUpdated; call Record() from there.
// ─────────────────────────────────────────────────────────────────────────────

public sealed class MetricsHistoryService
{
    // ── Constants ─────────────────────────────────────────────────────────────
    private const int RawCapacity    = 1_800;   // ~1 h at 2-sec intervals
    private const int MinuteCapacity = 1_440;   // 24 h at 1-min resolution
    private const int FiveMinCap     = 2_016;   // 7 d  at 5-min resolution
    private const int FifteenMinCap  = 2_880;   // 30 d at 15-min resolution

    // ── Ring buffers ──────────────────────────────────────────────────────────
    private readonly RingBuffer<MetricPoint> _raw       = new(RawCapacity);
    private readonly RingBuffer<MetricPoint> _minute    = new(MinuteCapacity);
    private readonly RingBuffer<MetricPoint> _fiveMin   = new(FiveMinCap);
    private readonly RingBuffer<MetricPoint> _fifteenMin= new(FifteenMinCap);

    // ── Aggregation accumulators ──────────────────────────────────────────────
    private readonly AccBucket _minAcc  = new(TimeSpan.FromMinutes(1));
    private readonly AccBucket _5mAcc   = new(TimeSpan.FromMinutes(5));
    private readonly AccBucket _15mAcc  = new(TimeSpan.FromMinutes(15));

    // ── Public API ────────────────────────────────────────────────────────────

    /// Feed a new hardware snapshot (call this from HardwareService.SnapshotUpdated).
    public void Record(HardwareSnapshot snap)
    {
        var now   = DateTime.Now;
        var point = new MetricPoint(now, snap.CpuLoad, snap.RamLoad, snap.DiskLoad);

        _raw.Push(point);

        if (_minAcc.Accept(now, point, out var m1)) _minute.Push(m1);
        if (_5mAcc.Accept(now, point, out var m5))  _fiveMin.Push(m5);
        if (_15mAcc.Accept(now, point, out var m15)) _fifteenMin.Push(m15);
    }

    /// Returns data points for the requested time window.
    /// <param name="hours">1 = last 1h (raw), 24 = 24h (minute avg),
    ///                     168 = 7d (5-min avg), 720 = 30d (15-min avg)</param>
    public IReadOnlyList<MetricPoint> GetHistory(int hours)
    {
        var cutoff = DateTime.Now.AddHours(-hours);

        if (hours <= 1)
            return _raw.ToList().Where(p => p.Timestamp >= cutoff).ToList();
        if (hours <= 24)
            return _minute.ToList().Where(p => p.Timestamp >= cutoff).ToList();
        if (hours <= 168)
            return _fiveMin.ToList().Where(p => p.Timestamp >= cutoff).ToList();

        return _fifteenMin.ToList().Where(p => p.Timestamp >= cutoff).ToList();
    }

    /// Latest single point (same as HardwareService.Latest but typed here).
    public MetricPoint? Latest => _raw.Latest;
}

// ─────────────────────────────────────────────────────────────────────────────
// Supporting types
// ─────────────────────────────────────────────────────────────────────────────

public sealed record MetricPoint(
    DateTime Timestamp,
    float    CpuLoad,
    uint     RamLoad,
    float    DiskLoad);

/// Thread-safe circular buffer.
internal sealed class RingBuffer<T>
{
    private readonly T[] _buf;
    private int _head;
    private int _count;
    private readonly object _lock = new();

    public RingBuffer(int capacity) => _buf = new T[capacity];

    public T? Latest
    {
        get
        {
            lock (_lock)
            {
                if (_count == 0) return default;
                var idx = (_head - 1 + _buf.Length) % _buf.Length;
                return _buf[idx];
            }
        }
    }

    public void Push(T item)
    {
        lock (_lock)
        {
            _buf[_head] = item;
            _head = (_head + 1) % _buf.Length;
            if (_count < _buf.Length) _count++;
        }
    }

    public List<T> ToList()
    {
        lock (_lock)
        {
            var result = new List<T>(_count);
            var start  = _count < _buf.Length ? 0 : _head;
            for (int i = 0; i < _count; i++)
                result.Add(_buf[(start + i) % _buf.Length]);
            return result;
        }
    }
}

/// Accumulates samples for a time bucket and emits an averaged point when the
/// bucket closes.
internal sealed class AccBucket
{
    private readonly TimeSpan _window;
    private DateTime _windowStart = DateTime.MinValue;
    private double _sumCpu, _sumRam, _sumDisk;
    private int _n;

    public AccBucket(TimeSpan window) => _window = window;

    /// Returns true and sets <paramref name="result"/> when a bucket closes.
    public bool Accept(DateTime now, MetricPoint p, out MetricPoint result)
    {
        result = default!;

        if (_windowStart == DateTime.MinValue)
            _windowStart = now;

        _sumCpu  += p.CpuLoad;
        _sumRam  += p.RamLoad;
        _sumDisk += p.DiskLoad;
        _n++;

        if (now - _windowStart < _window) return false;

        result = new MetricPoint(
            _windowStart + _window,
            (float)(_sumCpu  / _n),
            (uint) (_sumRam  / _n),
            (float)(_sumDisk / _n));

        _windowStart = now;
        _sumCpu = _sumRam = _sumDisk = 0;
        _n = 0;
        return true;
    }
}
