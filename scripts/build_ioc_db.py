"""
scripts/build_ioc_db.py -- PC Health Monitor IOC database builder
Downloads AbuseCH Feodo Tracker + URLhaus feeds and writes threat_intel.json.
Uses ONLY Python stdlib — no pip packages required.
"""

import csv
import io
import json
import os
import re
import sys
from datetime import datetime, timezone
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError

FEODO_URL   = "https://feodotracker.abuse.ch/downloads/ipblocklist_aggressive.csv"
URLHAUS_URL = "https://urlhaus.abuse.ch/downloads/hostfile/"

REPO_ROOT   = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_PATH = os.path.join(REPO_ROOT, "threat_intel.json")

TIMEOUT     = 30   # seconds per feed download
IPV4_RE     = re.compile(r"^\d{1,3}(?:\.\d{1,3}){3}$")

USER_AGENT  = (
    "Mozilla/5.0 PC-Health-Monitor/IOC-Builder "
    "(https://github.com/Rzuss/PC-Health-Monitor)"
)


def _fetch(url: str) -> str | None:
    """Download URL and return text content, or None on failure."""
    try:
        req = Request(url, headers={"User-Agent": USER_AGENT})
        with urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read()
            return raw.decode("utf-8", errors="replace")
    except (URLError, HTTPError, OSError) as exc:
        print(f"[WARN] Failed to download {url}: {exc}", file=sys.stderr)
        return None


def parse_feodo(text: str) -> dict:
    """
    Parse Feodo Tracker ipblocklist_aggressive.csv.
    Quoted CSV, comment lines start with #.
    Header row: first_seen_utc, dst_ip, dst_port, c2_status, last_online, malware
    IP is at column index 1 (dst_ip), malware family at index 5.
    """
    iocs = {}
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    reader = csv.reader(
        line for line in text.splitlines() if not line.startswith("#") and line.strip()
    )
    for i, row in enumerate(reader):
        if not row:
            continue
        # Skip header row (first non-comment line contains field names)
        if i == 0 and not IPV4_RE.match(row[1].strip().strip('"')):
            continue
        ip      = row[1].strip().strip('"') if len(row) > 1 else ""
        malware = row[5].strip().strip('"') if len(row) > 5 else "Unknown"
        if not IPV4_RE.match(ip):
            continue
        iocs[ip] = {
            "type":   "C2",
            "family": malware or "Unknown",
            "source": "AbuseCH-Feodo",
            "added":  today,
        }
    return iocs


def parse_urlhaus(text: str) -> dict:
    """
    Parse URLhaus hosts file — extract IPv4 addresses only (skip hostnames).
    Format: '127.0.0.1<TAB><hostname>' — target tokens are hostnames, not IPs.
    Any line whose second token matches IPv4 pattern is extracted.
    """
    iocs = {}
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        # Tab or space separated: <redirect_ip> <target>
        parts = re.split(r"[\t ]+", line)
        # Take all tokens except the redirect IP (first field) as candidates
        candidates = parts[1:] if len(parts) >= 2 else parts
        for token in candidates:
            token = token.strip()
            if not IPV4_RE.match(token):
                continue
            # Skip loopback, private and unroutable ranges
            if token.startswith(("127.", "10.", "192.168.", "0.", "169.254.")):
                continue
            if re.match(r"^172\.(1[6-9]|2[0-9]|3[01])\.", token):
                continue
            if token not in iocs:
                iocs[token] = {
                    "type":   "C2",
                    "family": "URLhaus",
                    "source": "AbuseCH-URLhaus",
                    "added":  today,
                }
    return iocs


def main() -> None:
    print("=== PC Health Monitor — IOC Database Builder ===")
    combined: dict = {}

    # ---------------------------------------------------------------- Feodo
    print(f"Downloading Feodo Tracker: {FEODO_URL}")
    feodo_text = _fetch(FEODO_URL)
    if feodo_text:
        feodo_iocs = parse_feodo(feodo_text)
        combined.update(feodo_iocs)
        print(f"  Feodo: {len(feodo_iocs)} C2 IPs parsed")
    else:
        print("  [SKIP] Feodo feed unavailable")

    # --------------------------------------------------------------- URLhaus
    print(f"Downloading URLhaus hosts: {URLHAUS_URL}")
    urlhaus_text = _fetch(URLHAUS_URL)
    if urlhaus_text:
        urlhaus_iocs = parse_urlhaus(urlhaus_text)
        # Feodo entries already in combined take priority — don't overwrite
        for ip, entry in urlhaus_iocs.items():
            if ip not in combined:
                combined[ip] = entry
        print(f"  URLhaus: {len(urlhaus_iocs)} IPs parsed "
              f"({sum(1 for ip in urlhaus_iocs if ip not in (combined.keys() - urlhaus_iocs.keys()))} new)")
    else:
        print("  [SKIP] URLhaus feed unavailable")

    total = len(combined)
    print(f"\nTotal unique IOCs: {total}")

    if total == 0:
        print("[ABORT] No IOCs collected — threat_intel.json NOT overwritten.")
        sys.exit(0)

    output = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source_count": 2,
        "ioc_count":    total,
        "iocs":         combined,
    }

    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(output, f, separators=(",", ":"))   # compact — can be large

    size_kb = os.path.getsize(OUTPUT_PATH) / 1024
    print(f"Written: {OUTPUT_PATH}  ({size_kb:.1f} KB)")


if __name__ == "__main__":
    main()
