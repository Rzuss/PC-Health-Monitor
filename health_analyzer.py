"""
health_analyzer.py -- PC Health Monitor predictive analytics engine
Reads telemetry CSV + security/startup JSON, computes Health Score, writes health_report.json
"""

import json
import os
import sys
from datetime import datetime, timedelta

try:
    import pandas as pd
    import numpy as np
except ImportError:
    print("ERROR: pandas is required. Run: python -m pip install pandas")
    sys.exit(1)

TEMP          = os.environ.get("TEMP", "")
LOCAL_APP     = os.environ.get("LOCALAPPDATA", "")
OUTPUT_DIR    = os.path.join(LOCAL_APP, "PC-Health-Monitor")
OUTPUT_PATH   = os.path.join(OUTPUT_DIR, "health_report.json")

TELEMETRY_PATH = os.path.join(TEMP, "PCHealth-Telemetry.csv")
SECURITY_PATH  = os.path.join(TEMP, "PCHealth-Security.json")
STARTUP_PATH   = os.path.join(TEMP, "PCHealth-Startup.json")


def _write_report(report: dict) -> None:
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)


def _null_report(reason: str) -> None:
    _write_report({
        "score": None,
        "grade": None,
        "trend": None,
        "disk_days_remaining": None,
        "ram_trend_pct_per_day": None,
        "messages": [reason],
        "generated_at": datetime.now().isoformat(timespec="seconds"),
    })


def _load_telemetry():
    if not os.path.exists(TELEMETRY_PATH):
        return None
    try:
        df = pd.read_csv(TELEMETRY_PATH)
        df["timestamp"] = pd.to_datetime(df["timestamp"], errors="coerce")
        df = df.dropna(subset=["timestamp"])
        cutoff = datetime.now() - timedelta(days=30)
        df = df[df["timestamp"] > cutoff]
        df["value"] = pd.to_numeric(df["value"], errors="coerce")
        df = df.dropna(subset=["value"])
        return df if len(df) >= 10 else None
    except Exception as exc:
        print(f"[WARN] Could not load telemetry: {exc}")
        return None


def _calc_disk_days(df: "pd.DataFrame"):
    """Return predicted days until DiskFree_GB < 10, or None if insufficient data."""
    disk = df[df["metric"] == "DiskFree_GB"].copy().sort_values("timestamp")
    if len(disk) < 5:
        return None
    disk["day_num"] = (
        disk["timestamp"] - disk["timestamp"].min()
    ).dt.total_seconds() / 86400.0
    x = disk["day_num"].values
    y = disk["value"].values
    coeffs = np.polyfit(x, y, 1)   # [slope GB/day, intercept]
    slope = coeffs[0]
    current_free = float(y[-1])
    if slope >= 0:
        return 999                  # stable or growing
    days = (current_free - 10.0) / (-slope)
    return max(0, round(days))


def _calc_ram_trend(df: "pd.DataFrame"):
    """Return average RAM% change per day (slope of linear regression)."""
    ram = df[df["metric"] == "RAM%"].copy().sort_values("timestamp")
    if len(ram) < 5:
        return 0.0
    ram["day_num"] = (
        ram["timestamp"] - ram["timestamp"].min()
    ).dt.total_seconds() / 86400.0
    if ram["day_num"].max() < 0.1:
        return 0.0
    x = ram["day_num"].values
    y = ram["value"].values
    coeffs = np.polyfit(x, y, 1)
    return round(float(coeffs[0]), 3)


def _load_json(path: str):
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _startup_count():
    data = _load_json(STARTUP_PATH)
    if data is None:
        return None
    if isinstance(data, list):
        return len(data)
    if isinstance(data, dict):
        return int(data.get("count", data.get("startup_count", 0)))
    return 0


# ---------------------------------------------------------------------------
# Score calculation
# ---------------------------------------------------------------------------
# Weight budget (max 100 pts, no anomaly penalty):
#   disk     30 pts
#   ram      20 pts
#   security 25 pts  (defender 10 + firewall 10 + updates 5)
#   startup  15 pts
#   base     10 pts  (always awarded — represents baseline system health)
# Anomaly penalty: -2 pts per anomaly (Sprint 7 baseline, skipped if missing)
# ---------------------------------------------------------------------------

def _compute_score(disk_days, ram_trend, security, startup_count):
    score = 10   # base points
    messages = []

    # -- Disk: 30 pts --------------------------------------------------------
    if disk_days is None:
        score += 15                 # partial when no trend data yet
    elif disk_days >= 90:
        score += 30
    elif disk_days <= 7:
        score += 0
        messages.append(f"Disk C: fills in ~{disk_days} days — critical!")
    else:
        pts = round(30 * (disk_days - 7) / (90 - 7))
        score += pts
        if disk_days < 30:
            messages.append(f"Disk C: fills in ~{disk_days} days")

    # -- RAM: 20 pts ---------------------------------------------------------
    if ram_trend is None:
        score += 10
    elif ram_trend <= 0.0:
        score += 20
    elif ram_trend >= 5.0:
        score += 0
        messages.append(f"RAM usage trending up sharply ({ram_trend:+.1f}%/day)")
    else:
        pts = round(20 * (1.0 - ram_trend / 5.0))
        score += pts
        if ram_trend > 0.5:
            messages.append(f"RAM usage trending up ({ram_trend:+.1f}%/day)")

    # -- Security: 25 pts ----------------------------------------------------
    if security:
        if security.get("defender_enabled"):
            score += 10
        else:
            messages.append("Windows Defender is disabled")

        fw_all = (
            security.get("firewall_domain") and
            security.get("firewall_private") and
            security.get("firewall_public")
        )
        if fw_all:
            score += 10
        else:
            messages.append("Firewall not enabled on all profiles")

        pending = int(security.get("pending_updates", 0))
        if pending < 10:
            score += 5
        else:
            messages.append(f"{pending} pending Windows updates")
    else:
        score += 12         # partial credit — no security data

    # -- Startup: 15 pts -----------------------------------------------------
    if startup_count is None:
        score += 10
    elif startup_count <= 5:
        score += 15
    elif startup_count <= 25:
        pts = round(15 * (1.0 - (startup_count - 5) / 20.0))
        score += max(0, pts)
    else:
        score += 0
        if startup_count > 20:
            messages.append(f"{startup_count} startup programs may slow boot")

    return max(0, min(100, score)), messages


def _grade(score: int) -> str:
    if score >= 80:
        return "EXCELLENT"
    if score >= 65:
        return "GOOD"
    if score >= 50:
        return "FAIR"
    return "POOR"


def _trend(disk_days, ram_trend) -> str:
    bad = good = 0
    if disk_days is not None:
        if disk_days != 999 and disk_days < 30:
            bad += 1
        elif disk_days >= 90:
            good += 1
    if ram_trend is not None:
        if ram_trend > 0.5:
            bad += 1
        elif ram_trend < -0.5:
            good += 1
    if bad > good:
        return "DEGRADING"
    if good > bad:
        return "IMPROVING"
    return "STABLE"


# ---------------------------------------------------------------------------
def main():
    df = _load_telemetry()
    if df is None:
        _null_report("Insufficient telemetry data — keep the app running to collect data")
        print("No telemetry data available. health_report.json written with score: null")
        return

    disk_days     = _calc_disk_days(df)
    ram_trend     = _calc_ram_trend(df)
    security      = _load_json(SECURITY_PATH)
    startup_count = _startup_count()

    score, messages = _compute_score(disk_days, ram_trend, security, startup_count)
    grade  = _grade(score)
    trend  = _trend(disk_days, ram_trend)

    report = {
        "score":               score,
        "grade":               grade,
        "trend":               trend,
        "disk_days_remaining": disk_days if disk_days is not None and disk_days != 999 else None,
        "ram_trend_pct_per_day": ram_trend,
        "messages":            messages[:3],
        "generated_at":        datetime.now().isoformat(timespec="seconds"),
    }
    _write_report(report)
    print(f"Health report written: score={score} ({grade}), trend={trend}")
    if messages:
        for m in messages[:3]:
            print(f"  - {m}")


if __name__ == "__main__":
    main()
