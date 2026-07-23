#!/usr/bin/env python3
"""
Tabame plugin: System Monitor
Keyword: sys
Pushes a `detail` view (CPU / RAM / disk / uptime) with sparklines, refreshed
every 1.5s via unsolicited rev:0 frames from a background thread.
"""
import sys
import json
import time
import threading
from collections import deque

try:
    import psutil
    _IMPORT_ERROR = None
except Exception as e:  # missing/failed install -> degrade gracefully
    psutil = None
    _IMPORT_ERROR = str(e)

REFRESH_SECONDS = 1.5
HISTORY_LEN = 30

_stdout_lock = threading.Lock()
_stop = threading.Event()
_started = threading.Event()

_cpu_history = deque(maxlen=HISTORY_LEN)
_ram_history = deque(maxlen=HISTORY_LEN)


def send(frame):
    with _stdout_lock:
        sys.stdout.write(json.dumps(frame) + "\n")
        sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def fmt_bytes(n):
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024:
            return f"{n:.1f}{unit}"
        n /= 1024
    return f"{n:.1f}PB"


def color_for(pct):
    if pct >= 90:
        return "#EF4444"
    if pct >= 70:
        return "#F59E0B"
    return "#22C55E"


def error_frame():
    return {
        "type": "render", "rev": 0, "view": "detail",
        "detail": {"markdown": f"# System Monitor\n\npsutil isn't available:\n\n```\n{_IMPORT_ERROR}\n```\n\nCheck that the `pip` install in `plugin.json` succeeded."},
    }


def build_frame():
    cpu_total = psutil.cpu_percent(interval=None)
    per_core = psutil.cpu_percent(interval=None, percpu=True)
    mem = psutil.virtual_memory()
    swap = psutil.swap_memory()

    _cpu_history.append(cpu_total)
    _ram_history.append(mem.percent)

    cores_text = " / ".join(f"{c:.0f}%" for c in per_core[:8])
    if len(per_core) > 8:
        cores_text += "…"

    metadata = [
        {
            "label": "CPU", "text": f"{cpu_total:.0f}%",
            "color": color_for(cpu_total),
            "sparkline": list(_cpu_history) if len(_cpu_history) >= 2 else [cpu_total, cpu_total],
        },
        {"label": "Cores", "text": cores_text, "icon": "terminal"},
        {"separator": True},
        {
            "label": "RAM", "text": f"{fmt_bytes(mem.used)} / {fmt_bytes(mem.total)}  ({mem.percent:.0f}%)",
            "color": color_for(mem.percent),
            "sparkline": list(_ram_history) if len(_ram_history) >= 2 else [mem.percent, mem.percent],
        },
        {"label": "Swap", "text": f"{fmt_bytes(swap.used)} / {fmt_bytes(swap.total)}  ({swap.percent:.0f}%)"},
        {"separator": True},
    ]

    for part in psutil.disk_partitions(all=False):
        try:
            usage = psutil.disk_usage(part.mountpoint)
        except (PermissionError, OSError):
            continue
        metadata.append({
            "label": part.device.rstrip("\\"),
            "text": f"{fmt_bytes(usage.used)} / {fmt_bytes(usage.total)}  ({usage.percent:.0f}%)",
            "color": color_for(usage.percent),
            "icon": "database",
        })

    uptime_s = int(time.time() - psutil.boot_time())
    h, rem = divmod(uptime_s, 3600)
    m, _rem2 = divmod(rem, 60)
    metadata.append({"separator": True})
    metadata.append({"label": "Uptime", "text": f"{h}h {m}m", "icon": "clock"})

    return {
        "type": "render",
        "rev": 0,
        "view": "detail",
        "detail": {
            "markdown": "# System Monitor\n\nLive usage — updates every " f"{REFRESH_SECONDS:g}s.",
            "metadata": metadata,
        },
        "actions": [
            {"id": "refresh", "title": "Refresh now", "icon": "refresh", "shortcut": "ctrl+r"},
        ],
    }


def monitor_loop():
    # First cpu_percent() call has no baseline yet — prime it, then loop.
    psutil.cpu_percent(interval=None)
    psutil.cpu_percent(interval=None, percpu=True)
    time.sleep(0.2)
    while not _stop.is_set():
        try:
            send(build_frame())
        except Exception as e:
            log("monitor_loop error:", e)
        _stop.wait(REFRESH_SECONDS)


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue

        t = msg.get("type")

        if t == "close":
            _stop.set()
            break

        elif t in ("init", "query"):
            if psutil is None:
                send(error_frame())
            elif not _started.is_set():
                _started.set()
                threading.Thread(target=monitor_loop, daemon=True).start()
            # Subsequent renders come from the background thread, not here.

        elif t == "action":
            if psutil is None:
                send(error_frame())
            elif msg.get("action") == "refresh":
                send(build_frame())

        # "select" / "back" / "tab": not used on this single detail screen.


if __name__ == "__main__":
    main()
