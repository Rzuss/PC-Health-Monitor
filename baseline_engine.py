"""
baseline_engine.py -- PC Health Monitor behavioral baseline engine
Builds per-process statistical profiles from telemetry CSV and detects current anomalies.
"""

import json
import os
import sys
from datetime import datetime, timedelta

try:
    import pandas as pd
    import numpy as np
except ImportError:
    print("ERROR: pandas and numpy are required. Run: python -m pip install pandas")
    sys.exit(1)

TEMP      = os.environ.get("TEMP", "")
LOCAL_APP = os.environ.get("LOCALAPPDATA", "")
INSTALL   = os.path.join(LOCAL_APP, "PC-Health-Monitor")

TELEMETRY_PATH = os.path.join(TEMP, "PCHealth-Telemetry.csv")
BASELINE_PATH  = os.path.join(INSTALL, "baseline_profile.json")
ANOMALIES_PATH = os.path.join(INSTALL, "PCHealth-Anomalies.json")

Z_THRESHOLD = 2.5
MIN_SAMPLES = 20


def load_process_telemetry() -> "pd.DataFrame | None":
    if not os.path.exists(TELEMETRY_PATH):
        print("Telemetry CSV not found — nothing to process.")
        return None
    try:
        df = pd.read_csv(TELEMETRY_PATH)
        df["timestamp"] = pd.to_datetime(df["timestamp"], errors="coerce")
        df = df.dropna(subset=["timestamp"])
        cutoff = datetime.now() - timedelta(days=30)
        df = df[df["timestamp"] > cutoff]
        df["value"] = pd.to_numeric(df["value"], errors="coerce")
        df = df.dropna(subset=["value"])
        # Keep only rows with a non-empty process name
        df = df[df["process"].notna() & (df["process"].astype(str).str.strip() != "")]
        if df.empty:
            print("No process-level rows found in telemetry.")
            return None
        return df
    except Exception as exc:
        print(f"[ERROR] Could not load telemetry: {exc}")
        return None


def build_baseline(df: "pd.DataFrame") -> dict:
    """
    Groups by (process, metric), computes mean/std/count for groups with >= MIN_SAMPLES.
    Skips constant processes (std == 0 or std < 1% of mean).
    Returns dict keyed as "{process}_{metric}".
    """
    profile = {}
    grouped = df.groupby(["process", "metric"])

    for (process, metric), group in grouped:
        vals = group["value"].values
        n = len(vals)
        if n < MIN_SAMPLES:
            continue

        mean = float(np.mean(vals))
        std  = float(np.std(vals, ddof=1))

        # Skip constants — std == 0 or less than 1% of mean
        if std == 0 or (mean != 0 and std / abs(mean) < 0.01):
            continue

        key = f"{process}_{metric}"
        profile[key] = {
            "mean":        round(mean, 2),
            "std":         round(std, 2),
            "samples":     int(n),
            "z_threshold": Z_THRESHOLD,
        }

    return profile


def detect_anomalies(df: "pd.DataFrame", profile: dict) -> list:
    """
    For each (process, metric) in the profile, get the LATEST value from the CSV
    and flag it if it exceeds z_threshold standard deviations from the mean.
    """
    anomalies = []

    for key, stats in profile.items():
        # Key format: "{process}_{metric}"
        # Split on first underscore that separates process from metric
        # Metric names contain underscores (process_ram_mb), so split from right at metric prefix
        for metric in ("process_ram_mb", "process_cpu_pct"):
            suffix = f"_{metric}"
            if key.endswith(suffix):
                process = key[: -len(suffix)]
                break
        else:
            continue

        subset = df[(df["process"] == process) & (df["metric"] == metric)]
        if subset.empty:
            continue

        latest_row = subset.sort_values("timestamp").iloc[-1]
        current    = float(latest_row["value"])
        mean       = stats["mean"]
        std        = stats["std"]
        z          = (current - mean) / std

        if z > Z_THRESHOLD:
            pct_above = round(((current - mean) / mean) * 100) if mean != 0 else 0
            try:
                pid = int(latest_row["pid"]) if pd.notna(latest_row.get("pid")) else 0
            except (ValueError, TypeError, KeyError):
                pid = 0
            anomalies.append({
                "process":   process,
                "metric":    metric,
                "current":   round(current, 1),
                "mean":      round(mean, 1),
                "std":       round(std, 1),
                "z_score":   round(z, 2),
                "pct_above": pct_above,
                "pid":       pid,
                "detected_at": datetime.now().isoformat(timespec="seconds"),
            })

    # Sort by z_score descending so most severe anomalies come first
    anomalies.sort(key=lambda a: a["z_score"], reverse=True)
    return anomalies


def register_scheduled_task(python_path: str, script_path: str) -> None:
    """Register 'PC-Health-Monitor Baseline' scheduled task via PowerShell."""
    import subprocess
    ps = f"""
$Action  = New-ScheduledTaskAction -Execute '{python_path}' -Argument 'baseline_engine.py' -WorkingDirectory '{os.path.dirname(script_path)}'
$Trigger = New-ScheduledTaskTrigger -Daily -At '03:05'
$Settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false -MultipleInstances IgnoreNew
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$Task = New-ScheduledTask -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description 'PC Health Monitor behavioral baseline engine'
Register-ScheduledTask -TaskName 'PC-Health-Monitor Baseline' -InputObject $Task -Force | Out-Null
Write-Host '[OK] Baseline task registered: daily 03:05 AM'
"""
    result = subprocess.run(
        ["powershell", "-NoProfile", "-Command", ps],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        print(result.stdout.strip())
    else:
        print(f"[WARN] Could not register task: {result.stderr.strip()}")


def main():
    import argparse
    parser = argparse.ArgumentParser(description="PC Health Monitor baseline engine")
    parser.add_argument("--register-task", action="store_true",
                        help="Register Windows Scheduled Task and exit")
    args = parser.parse_args()

    if args.register_task:
        register_scheduled_task(sys.executable, os.path.abspath(__file__))
        return

    os.makedirs(INSTALL, exist_ok=True)

    df = load_process_telemetry()
    if df is None:
        # Write empty outputs so the PS1 never crashes on missing files
        with open(BASELINE_PATH,  "w") as f:
            json.dump({}, f, indent=2)
        with open(ANOMALIES_PATH, "w") as f:
            json.dump([], f, indent=2)
        return

    profile   = build_baseline(df)
    anomalies = detect_anomalies(df, profile)

    with open(BASELINE_PATH, "w", encoding="utf-8") as f:
        json.dump(profile, f, indent=2)

    with open(ANOMALIES_PATH, "w", encoding="utf-8") as f:
        json.dump(anomalies, f, indent=2)

    print(f"Baseline profile: {len(profile)} entries written to {BASELINE_PATH}")
    print(f"Anomalies:        {len(anomalies)} detected  -> {ANOMALIES_PATH}")
    for a in anomalies[:5]:
        print(f"  [{a['z_score']:+.1f}z] {a['process']} {a['metric']}: "
              f"{a['current']} vs avg {a['mean']} (+{a['pct_above']}%)")


if __name__ == "__main__":
    main()
