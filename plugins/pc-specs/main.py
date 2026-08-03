#!/usr/bin/env python3
"""
PC Specs — Tabame launcher plugin
Live system-overview dashboard: CPU, GPU, RAM, storage, disk I/O, network,
motherboard/BIOS, OS, battery, and top processes. Streams a rev:0 refresh
every `REFRESH_SECONDS` while the plugin owns the query.

Real telemetry sources only — every field is best-effort and comes back
as "N/A" (or the panel is simply omitted) when it can't be determined:
  - psutil: CPU load/freq, RAM/swap, disks, disk I/O, network counters,
    boot time, battery, per-process stats
  - WMI (Win32_*): CPU/board/BIOS names & dates, physical memory
    speed/type, disk model/media-type mapping, GPU name/VRAM fallback
  - nvidia-smi: GPU name + total VRAM (specs only, queried once — no
    live load/clock/temp polling)
  - registry (DisplayVersion): Windows feature version (e.g. "23H2")

No config file and no third-party hardware-monitoring backend (e.g.
LibreHardwareMonitor) are required or used — anything that could only be
sourced from those (fan RPM, voltages, PSU wattage, per-component temps,
chipset/case/peripheral labels) has been dropped rather than faked.

WMI/hardware-identity facts (CPU name, motherboard, BIOS, memory
type/speed, disk model/media map, GPU name/VRAM, OS identity) don't
change while the plugin runs, so they're queried exactly ONCE at
startup via gather_static() and cached in STATIC — never re-queried on
each refresh. This also sidesteps a real bug: WMI/COM connections are
thread-affine, and this plugin has both a main thread and a background
refresh thread; a WMI connection touched from a different thread than
it was created in silently breaks (swallowed by try/except, showing up
as fields quietly going blank). Querying WMI only once, synchronously,
before the background thread even starts, avoids that entirely. Only
genuinely live values (load%, throughput, temps, battery, processes)
are re-queried every refresh, all via psutil/ctypes/subprocess, which
are thread-safe.

If GPU detection fails, the GRAPHICS CARD panel shows the actual
nvidia-smi/WMI error text instead of a generic "not detected" message
— see _detect_gpu().
"""

import datetime
import json
import os
import platform
import re
import shutil
import socket
import subprocess
import sys
import threading
import time

try:
    import psutil
except Exception:
    psutil = None

STOP = threading.Event()
LOCK = threading.Lock()

HIST_LEN = 24
HIST = {"cpu": [], "mem": [], "down": [], "up": [], "dread": [], "dwrite": []}

_NET_LAST = {"t": None, "bytes_sent": 0, "bytes_recv": 0}
_DISK_LAST = {"t": None, "read": 0, "write": 0}

_MEM_TYPE = {20: "DDR", 21: "DDR2", 24: "DDR3", 26: "DDR4", 34: "DDR5"}

REFRESH_SECONDS = 2

# Populated once by gather_static() before the background thread starts.
STATIC = {}


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def send(frame):
    try:
        sys.stdout.write(json.dumps(frame) + "\n")
        sys.stdout.flush()
    except Exception as e:
        log("send failed:", e)


# ---------------------------------------------------------------- WMI ----


def get_wmi():
    """Connect to the standard Win32 WMI namespace. Only ever called
    from gather_static(), which runs once on the main thread before any
    other thread starts — see the module docstring for why."""
    try:
        import wmi

        return wmi.WMI()
    except Exception as e:
        log("wmi unavailable:", e)
        return None


def _find_nvidia_smi():
    """Locate nvidia-smi.exe beyond a plain PATH lookup. A plugin
    subprocess spawned by a launcher app doesn't always inherit the
    same PATH a manually-run script sees, which is a common reason
    nvidia-smi resolves in one context and not the other."""
    which = shutil.which("nvidia-smi")
    if which:
        return which
    for c in (
        r"C:\Windows\System32\nvidia-smi.exe",
        r"C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe",
    ):
        if os.path.isfile(c):
            return c
    return "nvidia-smi"  # let subprocess try PATH lookup as a last resort


def _detect_gpu(w):
    """One-shot GPU identity lookup — name + VRAM only, no live usage.
    Tries nvidia-smi first, then WMI Win32_VideoController. Returns
    (name, vram_gb, errors) — errors is a list of the actual exception
    strings so a failure can be shown in the panel instead of just
    disappearing silently."""
    errors = []

    nvidia_smi = _find_nvidia_smi()
    try:
        out = subprocess.check_output(
            [
                nvidia_smi,
                "--query-gpu=name,memory.total",
                "--format=csv,noheader,nounits",
            ],
            stderr=subprocess.STDOUT,
            text=True,
            timeout=4,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        line = out.strip().splitlines()[0]
        name, memt = [p.strip() for p in line.split(",")]
        return name, float(memt) / 1024, errors
    except Exception as e:
        errors.append(f"nvidia-smi ({nvidia_smi}): {e}")

    if not w:
        errors.append(
            "WMI: connection unavailable (wmi module missing or COM connect failed)"
        )
        return None, None, errors

    try:
        gpus = [g for g in w.Win32_VideoController() if g.Name]
        if not gpus:
            errors.append("WMI: Win32_VideoController returned no adapters")
            return None, None, errors

        def is_real(g):
            n = g.Name.lower()
            return not any(
                x in n
                for x in ("basic render", "basic display", "remote display", "virtual")
            )

        # Prefer a real adapter over a virtual/basic one if both are listed —
        # WMI enumeration order isn't guaranteed to put the dedicated GPU first.
        real = [g for g in gpus if is_real(g)]
        gpu = (real or gpus)[0]
        vram_gb = None
        if gpu.AdapterRAM:
            # AdapterRAM is a signed 32-bit field - caps out near 4GB,
            # still useful as a lower-bound estimate.
            gb = gpu.AdapterRAM / (1024**3)
            if gb > 0:
                vram_gb = gb
        return gpu.Name, vram_gb, errors
    except Exception as e:
        errors.append(f"WMI: {e}")
        return None, None, errors


def gather_static():
    """One-shot collection of everything that doesn't change while the
    plugin is running: CPU name, motherboard/BIOS, memory type/speed,
    disk model+media map, GPU identity/VRAM, and OS identity. Called
    once from main() before the refresh thread starts."""
    w = get_wmi()

    # --- CPU name ---
    cpu_name = None
    if w:
        try:
            cpu_name = w.Win32_Processor()[0].Name.strip()
        except Exception as e:
            log("wmi cpu name error:", e)
    STATIC["cpu_name"] = cpu_name or platform.processor() or "Unknown CPU"

    # --- Memory (type/speed/module count) ---
    mem_speed = mem_type = mem_sticks = None
    if w:
        try:
            sticks = list(w.Win32_PhysicalMemory())
            if sticks:
                speeds = {
                    s.ConfiguredClockSpeed or s.Speed
                    for s in sticks
                    if (s.ConfiguredClockSpeed or s.Speed)
                }
                if speeds:
                    mem_speed = max(speeds)
                mem_sticks = len(sticks)
                types = {
                    getattr(s, "SMBIOSMemoryType", None)
                    for s in sticks
                    if getattr(s, "SMBIOSMemoryType", None)
                }
                if types:
                    mem_type = _MEM_TYPE.get(list(types)[0])
        except Exception as e:
            log("wmi memory error:", e)
    STATIC["mem_speed"] = mem_speed
    STATIC["mem_type"] = mem_type
    STATIC["mem_sticks"] = mem_sticks

    # --- Motherboard / BIOS ---
    board_mfr = board_prod = bios_ver = bios_date = socket_name = None
    if w:
        try:
            b = w.Win32_BaseBoard()[0]
            board_mfr, board_prod = b.Manufacturer, b.Product
        except Exception as e:
            log("wmi baseboard error:", e)
        try:
            bios = w.Win32_BIOS()[0]
            bios_ver = bios.SMBIOSBIOSVersion
            rd = bios.ReleaseDate  # e.g. 20240418000000.000000+000
            if rd:
                try:
                    dt = datetime.datetime.strptime(rd.split(".")[0], "%Y%m%d%H%M%S")
                    bios_date = dt.strftime("%m/%d/%Y")
                except Exception:
                    pass
        except Exception as e:
            log("wmi bios error:", e)
        try:
            cpu = w.Win32_Processor()
            if cpu and cpu[0].SocketDesignation:
                socket_name = cpu[0].SocketDesignation
        except Exception:
            pass
    STATIC["motherboard"] = f"{board_mfr or ''} {board_prod or ''}".strip() or "N/A"
    STATIC["bios_version"] = bios_ver or "N/A"
    STATIC["bios_date"] = bios_date
    STATIC["socket"] = socket_name

    # --- OS identity ---
    os_caption = os_build = install_date = os_version = None
    if w:
        try:
            os_info = w.Win32_OperatingSystem()[0]
            os_caption = os_info.Caption
            os_build = os_info.BuildNumber
            inst = os_info.InstallDate
            if inst:
                try:
                    dt = datetime.datetime.strptime(inst.split(".")[0], "%Y%m%d%H%M%S")
                    install_date = dt.strftime("%b %d, %Y")
                except Exception:
                    pass
        except Exception as e:
            log("wmi os error:", e)
    STATIC["os_caption"] = os_caption or f"{platform.system()} {platform.release()}"
    STATIC["os_build"] = os_build or "N/A"
    STATIC["install_date"] = install_date or "N/A"

    # DisplayVersion (e.g. "23H2") lives in the registry, not WMI.
    if platform.system() == "Windows":
        try:
            import winreg

            key = winreg.OpenKey(
                winreg.HKEY_LOCAL_MACHINE,
                r"SOFTWARE\Microsoft\Windows NT\CurrentVersion",
            )
            try:
                os_version = winreg.QueryValueEx(key, "DisplayVersion")[0]
            except FileNotFoundError:
                os_version = winreg.QueryValueEx(key, "ReleaseId")[0]
        except Exception as e:
            log("registry version error:", e)
    STATIC["os_version"] = os_version or "N/A"

    # --- Disk model + media-type (SSD/HDD) map ---
    models = {}
    if w:
        try:
            for pd in w.Win32_DiskDrive():
                model = (pd.Model or "").strip()
                for part in pd.associators("Win32_DiskDriveToDiskPartition"):
                    for ld in part.associators("Win32_LogicalDiskToPartition"):
                        models[ld.DeviceID] = model
        except Exception as e:
            log("disk model mapping failed:", e)
    media = {}
    try:
        import wmi

        storage = wmi.WMI(namespace="root\\Microsoft\\Windows\\Storage")
        media_map = {0: "Unknown", 3: "HDD", 4: "SSD", 5: "SCM"}
        for pd in storage.MSFT_PhysicalDisk():
            media[pd.FriendlyName] = media_map.get(pd.MediaType, "Disk")
    except Exception as e:
        log("media type query failed:", e)
    STATIC["disk_models"] = models
    STATIC["disk_media"] = media
    system_drive = os.environ.get("SystemDrive", "C:")
    STATIC["system_drive_model"] = models.get(system_drive, system_drive)

    # --- GPU identity/VRAM (queried once — specs only, no live usage) ---
    gpu_name, gpu_vram_gb, gpu_errors = _detect_gpu(w)
    STATIC["gpu_name"] = gpu_name
    STATIC["gpu_vram_gb"] = gpu_vram_gb
    STATIC["gpu_errors"] = gpu_errors


# ---------------------------------------------------------------- fmt ----


def fmt_size(num_bytes):
    if num_bytes is None:
        return "N/A"
    gb = num_bytes / (1024**3)
    if gb >= 1000:
        return f"{gb / 1024:.2f} TB"
    return f"{gb:.0f} GB"


def fmt_uptime(seconds):
    seconds = int(seconds)
    d, seconds = divmod(seconds, 86400)
    h, seconds = divmod(seconds, 3600)
    m, _ = divmod(seconds, 60)
    return f"{d}d {h}h {m}m"


def fmt_secs_left(s):
    if s is None or s < 0:
        return "N/A"
    h, rem = divmod(int(s), 3600)
    m = rem // 60
    return f"{h}h {m}m"


def push_hist(key, value):
    if value is None:
        return
    h = HIST[key]
    h.append(round(float(value), 1))
    if len(h) > HIST_LEN:
        h.pop(0)


def temp_color(c):
    if c is None:
        return "#8B8FA3"
    if c < 50:
        return "#22C55E"
    if c < 75:
        return "#EAB308"
    return "#EF4444"


# ---------------------------------------------------------- live data ---


def cpu_data():
    percent = psutil.cpu_percent(interval=None) if psutil else None
    push_hist("cpu", percent)
    freq = psutil.cpu_freq() if psutil else None
    return {
        "name": STATIC.get("cpu_name", "Unknown CPU"),
        "cores_physical": psutil.cpu_count(logical=False) if psutil else None,
        "cores_logical": psutil.cpu_count(logical=True) if psutil else None,
        "load": percent,
        "freq_current": freq.current if freq else None,
        "freq_max": freq.max if freq else None,
    }


def gpu_data():
    """GPU is specs-only (name + VRAM), gathered once in gather_static()
    — no per-refresh polling. If detection failed, the actual error
    strings are surfaced here so the panel can show *why* instead of
    just "not detected"."""
    if STATIC.get("gpu_name"):
        return {
            "name": STATIC["gpu_name"],
            "vram_total_gb": STATIC.get("gpu_vram_gb"),
            "available": True,
        }
    return {"available": False, "errors": STATIC.get("gpu_errors", [])}


def mem_data():
    vm = psutil.virtual_memory() if psutil else None
    push_hist("mem", vm.percent if vm else None)
    swap = psutil.swap_memory() if psutil else None
    return {
        "total": vm.total if vm else None,
        "used": vm.used if vm else None,
        "available": vm.available if vm else None,
        "percent": vm.percent if vm else None,
        "speed": STATIC.get("mem_speed"),
        "type": STATIC.get("mem_type"),
        "sticks": STATIC.get("mem_sticks"),
        "swap_used": swap.used if swap else None,
        "swap_total": swap.total if swap else None,
        "swap_percent": swap.percent if swap else None,
    }


def storage_data():
    if not psutil:
        return []
    models = STATIC.get("disk_models", {})
    media = STATIC.get("disk_media", {})
    drives = []
    for part in psutil.disk_partitions(all=False):
        if not part.device:
            continue
        try:
            usage = psutil.disk_usage(part.mountpoint)
        except Exception:
            continue
        letter = part.device.rstrip("\\")
        model = models.get(letter, part.mountpoint)
        dtype = media.get(model, "N/A")
        drives.append(
            {
                "letter": letter,
                "model": model,
                "type": dtype,
                "used": usage.used,
                "total": usage.total,
                "percent": usage.percent,
            }
        )
    return drives


def disk_io_data():
    if not psutil:
        return {"read": None, "write": None}
    io = psutil.disk_io_counters()
    if io is None:
        return {"read": None, "write": None}
    now = time.time()
    read_mbps = write_mbps = None
    with LOCK:
        last = _DISK_LAST
        if last["t"] is not None:
            dt = max(now - last["t"], 0.001)
            read_mbps = max((io.read_bytes - last["read"]) / 1e6 / dt, 0)
            write_mbps = max((io.write_bytes - last["write"]) / 1e6 / dt, 0)
            push_hist("dread", read_mbps)
            push_hist("dwrite", write_mbps)
        last["t"] = now
        last["read"] = io.read_bytes
        last["write"] = io.write_bytes
    return {"read": read_mbps, "write": write_mbps}


def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "N/A"


def get_ping_ms(host="8.8.8.8"):
    try:
        flag = "-n" if platform.system() == "Windows" else "-c"
        out = subprocess.check_output(
            ["ping", flag, "1", host], stderr=subprocess.DEVNULL, text=True, timeout=3
        )
        m = re.search(r"time[=<]([\d.]+)\s*ms", out, re.IGNORECASE)
        if m:
            return float(m.group(1))
    except Exception as e:
        log("ping failed:", e)
    return None


def network_data():
    if not psutil:
        return {"down": None, "up": None, "ping": None, "ip": "N/A"}
    now = time.time()
    counters = psutil.net_io_counters()
    down_mbps = up_mbps = None
    with LOCK:
        last = _NET_LAST
        if last["t"] is not None:
            dt = max(now - last["t"], 0.001)
            down_mbps = max(
                (counters.bytes_recv - last["bytes_recv"]) * 8 / 1e6 / dt, 0
            )
            up_mbps = max((counters.bytes_sent - last["bytes_sent"]) * 8 / 1e6 / dt, 0)
            push_hist("down", down_mbps)
            push_hist("up", up_mbps)
        last["t"] = now
        last["bytes_recv"] = counters.bytes_recv
        last["bytes_sent"] = counters.bytes_sent
    return {
        "down": down_mbps,
        "up": up_mbps,
        "ping": get_ping_ms(),
        "ip": get_local_ip(),
    }


def system_data():
    return {
        "motherboard": STATIC.get("motherboard", "N/A"),
        "bios": STATIC.get("bios_version", "N/A"),
        "os": STATIC.get("os_caption", "N/A"),
        "os_version": STATIC.get("os_version", "N/A"),
        "os_build": STATIC.get("os_build", "N/A"),
        "install_date": STATIC.get("install_date", "N/A"),
        "system_drive_model": STATIC.get("system_drive_model", "N/A"),
    }


def resolution():
    try:
        import ctypes

        u = ctypes.windll.user32
        return u.GetSystemMetrics(0), u.GetSystemMetrics(1)
    except Exception:
        return None, None


def motherboard_data():
    """Board identity/BIOS facts only — no temps/voltages, since those
    have no generic OS API and previously required LibreHardwareMonitor."""
    return {"bios_date": STATIC.get("bios_date"), "socket": STATIC.get("socket")}


def battery_data():
    if not psutil:
        return None
    try:
        b = psutil.sensors_battery()
        if b is None:
            return None
        return {
            "percent": b.percent,
            "plugged": b.power_plugged,
            "secsleft": b.secsleft,
        }
    except Exception as e:
        log("battery query failed:", e)
        return None


def top_processes(n=5):
    if not psutil:
        return []
    procs = []
    for p in psutil.process_iter(["pid", "name", "cpu_percent", "memory_percent"]):
        try:
            procs.append(p.info)
        except Exception:
            continue
    procs.sort(key=lambda p: p.get("cpu_percent") or 0, reverse=True)
    return procs[:n]


# ------------------------------------------------------------- panels ----


def meta_row(label, text, **kw):
    row = {"label": label, "text": text}
    row.update(kw)
    return row


def build_panels():
    cpu = cpu_data()
    gpu = gpu_data()
    mem = mem_data()
    disks = storage_data()
    dio = disk_io_data()
    net = network_data()
    sysd = system_data()
    mobo = motherboard_data()
    battery = battery_data()
    procs = top_processes()
    w_res, h_res = resolution()
    uptime = fmt_uptime(time.time() - psutil.boot_time()) if psutil else "N/A"

    panels = []

    # --- overview header ---
    overview_meta = [
        meta_row("Uptime", uptime, icon="clock", color="#22C55E"),
        meta_row("OS", sysd["os"], icon="window"),
        meta_row(
            "Resolution",
            f"{w_res} x {h_res}" if w_res else "N/A",
            icon="grid",
        ),
        meta_row("Last Update", time.strftime("%H:%M:%S"), icon="refresh"),
    ]
    panels.append(
        {
            "id": "overview",
            "title": "PC SPECS — System Overview",
            "height": 130,
            "view": "detail",
            "detail": {"markdown": "", "metadata": overview_meta},
        }
    )

    # --- processor ---
    cpu_meta = [
        meta_row("Model", cpu["name"], icon="terminal", color="#38BDF8"),
        meta_row(
            "Cores",
            f"{cpu['cores_physical']} physical / {cpu['cores_logical']} logical"
            if cpu["cores_physical"]
            else "N/A",
        ),
        meta_row(
            "Load",
            f"{cpu['load']:.0f}%" if cpu["load"] is not None else "N/A",
            color="#38BDF8",
        ),
        meta_row(
            "Frequency",
            f"{cpu['freq_current']:.0f} / {cpu['freq_max']:.0f} MHz"
            if cpu["freq_current"]
            else "N/A",
        ),
    ]
    if len(HIST["cpu"]) >= 2:
        cpu_meta.append(
            {
                "label": "Load trend",
                "sparkline": HIST["cpu"],
                "text": f"{HIST['cpu'][-1]:.0f}%",
            }
        )
    panels.append(
        {
            "id": "cpu",
            "title": "PROCESSOR",
            "height": 150,
            "view": "detail",
            "detail": {"markdown": "", "metadata": cpu_meta},
        }
    )

    # --- graphics (specs only — name + VRAM, no live usage) ---
    if gpu.get("available"):
        gpu_meta = [
            meta_row("Model", gpu["name"], icon="grid", color="#22C55E"),
            meta_row(
                "VRAM",
                f"~{gpu['vram_total_gb']:.0f} GB"
                if gpu.get("vram_total_gb")
                else "N/A",
            ),
        ]
        gpu_height = 80
    else:
        errs = gpu.get("errors") or []
        if errs:
            gpu_meta = [meta_row("Status", "GPU not detected — " + " | ".join(errs))]
        else:
            gpu_meta = [meta_row("Status", "No GPU detected.")]
        gpu_height = max(100, 60 + 20 * len(errs))
    panels.append(
        {
            "id": "gpu",
            "title": "GRAPHICS CARD",
            "height": gpu_height,
            "view": "detail",
            "detail": {"markdown": "", "metadata": gpu_meta},
        }
    )

    # --- memory ---
    mem_meta = [
        meta_row(
            "Used / Total",
            f"{fmt_size(mem['used'])} / {fmt_size(mem['total'])}"
            if mem["total"]
            else "N/A",
            color="#A78BFA",
        ),
        meta_row(
            "Available", fmt_size(mem["available"]) if mem["available"] else "N/A"
        ),
        meta_row(
            "Load", f"{mem['percent']:.0f}%" if mem["percent"] is not None else "N/A"
        ),
        meta_row("Type", mem["type"] or "N/A"),
        meta_row("Speed", f"{mem['speed']:.0f} MT/s" if mem["speed"] else "N/A"),
        meta_row("Modules", str(mem["sticks"]) if mem["sticks"] else "N/A"),
        meta_row(
            "Swap",
            f"{fmt_size(mem['swap_used'])} / {fmt_size(mem['swap_total'])} ({mem['swap_percent']:.0f}%)"
            if mem["swap_total"]
            else "None configured",
        ),
    ]
    if len(HIST["mem"]) >= 2:
        mem_meta.append(
            {
                "label": "Load trend",
                "sparkline": HIST["mem"],
                "text": f"{HIST['mem'][-1]:.0f}%",
            }
        )
    panels.append(
        {
            "id": "memory",
            "title": "MEMORY",
            "height": 220,
            "view": "detail",
            "detail": {"markdown": "", "metadata": mem_meta},
        }
    )

    # --- storage (list w/ progress bars) ---
    storage_items = []
    if disks:
        for d in disks:
            storage_items.append(
                {
                    "id": f"disk-{d['letter']}",
                    "title": f"{d['model']} ({d['letter']})",
                    "subtitle": f"{d['type']} · {fmt_size(d['used'])} / {fmt_size(d['total'])}",
                    "icon": "database",
                    "progress": d["percent"] / 100,
                    "accessories": [{"text": f"{d['percent']:.0f}%"}],
                }
            )
    panels.append(
        {
            "id": "storage",
            "title": "STORAGE",
            "height": max(120, 72 * max(len(storage_items), 1)),
            "view": "list",
            "emptyText": "No drives detected",
            "items": storage_items,
        }
    )

    # --- disk I/O ---
    dio_meta = []
    if len(HIST["dread"]) >= 2:
        dio_meta.append(
            {
                "label": "Read",
                "sparkline": HIST["dread"],
                "text": f"{dio['read']:.1f} MB/s" if dio["read"] is not None else "N/A",
                "color": "#38BDF8",
            }
        )
    else:
        dio_meta.append(meta_row("Read", "collecting…"))
    if len(HIST["dwrite"]) >= 2:
        dio_meta.append(
            {
                "label": "Write",
                "sparkline": HIST["dwrite"],
                "text": f"{dio['write']:.1f} MB/s"
                if dio["write"] is not None
                else "N/A",
                "color": "#F472B6",
            }
        )
    else:
        dio_meta.append(meta_row("Write", "collecting…"))
    panels.append(
        {
            "id": "disk_io",
            "title": "DISK I/O",
            "height": max(90, 45 * max(len(dio_meta), 1)),
            "view": "detail",
            "detail": {"markdown": "", "metadata": dio_meta},
        }
    )

    # --- network ---
    net_meta = []
    if len(HIST["down"]) >= 2:
        net_meta.append(
            {
                "label": "Download",
                "sparkline": HIST["down"],
                "text": f"{net['down']:.1f} Mbps" if net["down"] is not None else "N/A",
                "color": "#A78BFA",
            }
        )
    else:
        net_meta.append(meta_row("Download", "collecting…"))
    if len(HIST["up"]) >= 2:
        net_meta.append(
            {
                "label": "Upload",
                "sparkline": HIST["up"],
                "text": f"{net['up']:.1f} Mbps" if net["up"] is not None else "N/A",
                "color": "#F472B6",
            }
        )
    else:
        net_meta.append(meta_row("Upload", "collecting…"))
    net_meta.append(
        meta_row("Ping", f"{net['ping']:.0f} ms" if net["ping"] is not None else "N/A")
    )
    net_meta.append(meta_row("Local IP", net["ip"]))
    panels.append(
        {
            "id": "network",
            "title": "NETWORK",
            "height": max(50, 35 * max(len(net_meta), 1)),
            "view": "detail",
            "detail": {"markdown": "", "metadata": net_meta},
        }
    )

    # --- motherboard ---
    mobo_meta = [
        meta_row("Board", sysd["motherboard"], icon="terminal"),
        meta_row("BIOS Version", str(sysd["bios"])),
        meta_row("BIOS Date", mobo["bios_date"] or "N/A"),
        meta_row("CPU Socket", mobo["socket"] or "N/A"),
    ]
    panels.append(
        {
            "id": "motherboard",
            "title": "MOTHERBOARD",
            "height": max(50, 35 * max(len(mobo_meta), 1)),
            "view": "detail",
            "detail": {"markdown": "", "metadata": mobo_meta},
        }
    )

    # --- system / OS ---
    sys_meta = [
        meta_row("Operating System", sysd["os"]),
        meta_row("Version", sysd["os_version"]),
        meta_row("Build", str(sysd["os_build"])),
        meta_row("Installed", sysd["install_date"]),
        meta_row("System Drive", sysd["system_drive_model"]),
    ]
    panels.append(
        {
            "id": "system",
            "title": "SYSTEM",
            "height": max(50, 30 * max(len(sys_meta), 1)),
            "view": "detail",
            "detail": {"markdown": "", "metadata": sys_meta},
        }
    )

    # --- battery (only shown when one is actually present) ---
    if battery is not None:
        battery_meta = [
            meta_row(
                "Charge",
                f"{battery['percent']:.0f}%",
                icon="battery",
                color="#22C55E" if battery["percent"] > 20 else "#EF4444",
            ),
            meta_row("Status", "Plugged In" if battery["plugged"] else "On Battery"),
        ]
        if not battery["plugged"]:
            battery_meta.append(
                meta_row("Time Remaining", fmt_secs_left(battery["secsleft"]))
            )
        panels.append(
            {
                "id": "battery",
                "title": "BATTERY",
                "height": 150,
                "view": "detail",
                "detail": {"markdown": "", "metadata": battery_meta},
            }
        )

    # --- top processes ---
    proc_items = [
        {
            "id": f"proc-{p['pid']}",
            "title": p.get("name") or "Unknown",
            "subtitle": f"PID {p['pid']}",
            "icon": "cpu",
            "accessories": [
                {"text": f"{(p.get('cpu_percent') or 0):.0f}% CPU"},
                {"text": f"{(p.get('memory_percent') or 0):.1f}% MEM"},
            ],
        }
        for p in procs
        if (p.get("name") or "").lower() != "system idle process"
    ]
    panels.append(
        {
            "id": "processes",
            "title": "TOP PROCESSES",
            "height": max(120, 55 * max(len(proc_items), 1)),
            "view": "list",
            "emptyText": "No process data",
            "items": proc_items,
        }
    )

    return panels


def build_frame(rev):
    try:
        panels = build_panels()
    except Exception as e:
        log("build_panels failed:", e)
        return {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "detail": {"markdown": f"# Error building dashboard\n\n```\n{e}\n```"},
        }
    return {
        "type": "render",
        "rev": rev,
        "view": "dashboard",
        "placeholder": "specs",
        "actions": [
            {
                "id": "refresh",
                "title": "Refresh now",
                "icon": "refresh",
                "shortcut": "ctrl+r",
            },
        ],
        "dashboard": {"layout": "stack", "panels": panels},
    }


# ------------------------------------------------------------- runtime ---


def refresh_loop():
    while not STOP.is_set():
        STOP.wait(REFRESH_SECONDS)
        if STOP.is_set():
            break
        send(build_frame(0))


def main():
    # Gather everything static exactly once, synchronously, on the main
    # thread — before the background refresh thread exists at all.
    gather_static()

    if psutil:
        psutil.cpu_percent(interval=None)  # warm up
        for p in psutil.process_iter():
            try:
                p.cpu_percent(interval=None)  # warm up per-process cpu_percent
            except Exception:
                continue

    threading.Thread(target=refresh_loop, daemon=True).start()

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
            STOP.set()
            break
        elif t in ("init", "query"):
            send(build_frame(msg.get("rev", 0)))
        elif t == "action":
            action = msg.get("action", "default")
            if action in ("refresh", "default"):
                send(build_frame(0))
            else:
                send(build_frame(0))

    STOP.set()


if __name__ == "__main__":
    main()
