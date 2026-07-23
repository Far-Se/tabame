#!/usr/bin/env python3
import sys, json, socket, subprocess, urllib.request

try:
    import psutil
except ImportError:
    psutil = None


def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def need_psutil(rev):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "empty": {
                "icon": "warning",
                "title": "psutil not installed",
                "hint": "Reopen the launcher to let it install dependencies.",
            },
            "items": [],
        }
    )


# ---------------------------------------------------------------- state ----

STATE = {
    "screen": "root",           # root | ports | procs | wifi | adapters | ping_input | ping_result | publicip
    "root_query": "",
    "ports_query": "",
    "procs_query": "",
    "wifi_query": "",
    "adapters_query": "",
    "ping_host": "",
    "public_ip": None,
}


def goto(screen, clear_bar=True):
    STATE["screen"] = screen
    if clear_bar:
        send({"type": "command", "command": "setQuery", "text": ""})


# ---------------------------------------------------------------- root -----

ROOT_ITEMS = [
    {"id": "cmd:ports", "title": "Ports", "subtitle": "Listening ports · kill by port", "icon": "server"},
    {"id": "cmd:procs", "title": "Processes", "subtitle": "Fuzzy process finder · kill", "icon": "terminal"},
    {"id": "cmd:wifi", "title": "WiFi", "subtitle": "Current network · saved passwords", "icon": "wifi"},
    {"id": "cmd:adapters", "title": "Adapters", "subtitle": "Network interfaces · IP · MAC", "icon": "globe"},
    {"id": "cmd:ping", "title": "Ping", "subtitle": "Ping a host or IP", "icon": "bolt"},
    {"id": "cmd:publicip", "title": "Public IP", "subtitle": "Your external IP address", "icon": "globe"},
    {"id": "cmd:flushdns", "title": "Flush DNS cache", "subtitle": "ipconfig /flushdns", "icon": "refresh"},
]


def render_root(rev, query):
    q = query.strip().lower()
    items = [
        it for it in ROOT_ITEMS
        if not q or q in it["title"].lower() or q in it["subtitle"].lower()
    ]
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "placeholder": "Search sysnet tools…",
            "emptyText": "No matching tool",
            "items": items,
        }
    )


# --------------------------------------------------------------- ports -----

def proc_name(pid):
    if not pid:
        return "—"
    try:
        return psutil.Process(pid).name()
    except Exception:
        return "unknown"


def collect_ports(query):
    rows = {}
    try:
        conns = psutil.net_connections(kind="inet")
    except Exception as e:
        log("net_connections failed:", e)
        conns = []
    for c in conns:
        if c.type == socket.SOCK_STREAM and c.status != psutil.CONN_LISTEN:
            continue
        if not c.laddr:
            continue
        proto = "TCP" if c.type == socket.SOCK_STREAM else "UDP"
        key = (proto, c.laddr.port, c.pid)
        if key in rows:
            continue
        rows[key] = {"proto": proto, "port": c.laddr.port, "pid": c.pid, "name": proc_name(c.pid)}
    items = list(rows.values())
    q = query.strip().lower()
    if q:
        if q.isdigit():
            items = [r for r in items if str(r["port"]).startswith(q)]
        else:
            items = [r for r in items if q in r["name"].lower() or q in r["proto"].lower()]
    items.sort(key=lambda r: r["port"])
    return items


def port_item_id(r):
    return f"{r['proto']}-{r['port']}-{r['pid'] or 0}"


def to_port_item(r):
    actions = [{"id": "copy_port", "title": "Copy port", "icon": "copy"}]
    if r["pid"]:
        actions.append(
            {
                "id": "kill",
                "title": f"Kill {r['name']}",
                "icon": "trash",
                "destructive": True,
                "confirm": {
                    "title": "Kill process?",
                    "message": f"Terminate {r['name']} (PID {r['pid']}), freeing port {r['port']}.",
                    "confirmLabel": "Kill",
                },
            }
        )
    return {
        "id": port_item_id(r),
        "title": f"{r['proto']} :{r['port']}",
        "subtitle": f"{r['name']} · PID {r['pid'] or '—'}",
        "icon": "server",
        "accessories": [{"text": r["proto"]}],
        "actions": actions,
    }


def render_ports(rev, query):
    items = collect_ports(query)
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "placeholder": "Filter by port or process… (Esc to go back)",
            "emptyText": "No listening ports match",
            "canGoBack": True,
            "actions": [{"id": "refresh", "title": "Refresh", "icon": "refresh"}],
            "items": [to_port_item(r) for r in items],
        }
    )


# --------------------------------------------------------------- procs -----

def snapshot_procs():
    rows = []
    for p in psutil.process_iter(["pid", "name", "username", "memory_info"]):
        try:
            info = p.info
            mem_info = info.get("memory_info")
            mem_mb = mem_info.rss / (1024 * 1024) if mem_info else 0.0
            user = (info.get("username") or "").split("\\")[-1]
            rows.append({"pid": info["pid"], "name": info["name"] or "?", "user": user, "mem_mb": mem_mb})
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return rows


def score_name(name_lower, q):
    if q == name_lower:
        return 0
    if name_lower.startswith(q):
        return 1
    if q in name_lower:
        return 2
    return None


def filtered_procs(query):
    rows = snapshot_procs()
    q = query.strip().lower()
    if q:
        scored = []
        for r in rows:
            s = score_name(r["name"].lower(), q)
            if s is not None:
                scored.append((s, r))
        scored.sort(key=lambda t: (t[0], -t[1]["mem_mb"]))
        rows = [r for _, r in scored]
    else:
        rows.sort(key=lambda r: -r["mem_mb"])
    return rows[:60]


def to_proc_item(r):
    return {
        "id": str(r["pid"]),
        "title": r["name"],
        "subtitle": f"PID {r['pid']} · {r['mem_mb']:.0f} MB" + (f" · {r['user']}" if r["user"] else ""),
        "icon": "app",
        "accessories": [{"text": f"{r['mem_mb']:.0f} MB"}],
        "actions": [
            {"id": "copy_pid", "title": "Copy PID", "icon": "copy"},
            {
                "id": "default",
                "title": "Kill process",
                "icon": "trash",
                "destructive": True,
                "confirm": {
                    "title": f"Kill {r['name']}?",
                    "message": f"Terminate PID {r['pid']}. Unsaved work in this process may be lost.",
                    "confirmLabel": "Kill",
                },
            },
        ],
    }


def render_procs(rev, query):
    rows = filtered_procs(query)
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "placeholder": "Fuzzy search processes… (Esc to go back)",
            "emptyText": "No matching processes",
            "canGoBack": True,
            "actions": [{"id": "refresh", "title": "Refresh", "icon": "refresh"}],
            "items": [to_proc_item(r) for r in rows],
        }
    )


# ---------------------------------------------------------------- wifi -----

def run_netsh(args):
    try:
        out = subprocess.run(["netsh"] + args, capture_output=True, timeout=10)
        raw = out.stdout
        for enc in ("utf-8", "cp1252", "cp437"):
            try:
                return raw.decode(enc)
            except UnicodeDecodeError:
                continue
        return raw.decode("utf-8", errors="ignore")
    except Exception as e:
        log("netsh failed:", args, e)
        return ""


def get_wifi_status():
    text = run_netsh(["wlan", "show", "interfaces"])
    info = {}
    for line in text.splitlines():
        if ":" in line:
            k, _, v = line.partition(":")
            info[k.strip()] = v.strip()
    return info


def get_wifi_profiles():
    text = run_netsh(["wlan", "show", "profiles"])
    names = []
    for line in text.splitlines():
        if "Profile" in line and ":" in line and "All User" in line:
            _, _, v = line.partition(":")
            name = v.strip()
            if name:
                names.append(name)
    return names


def get_wifi_password(name):
    text = run_netsh(["wlan", "show", "profile", f'name="{name}"', "key=clear"])
    for line in text.splitlines():
        if "Key Content" in line and ":" in line:
            _, _, v = line.partition(":")
            return v.strip()
    return None


def render_wifi(rev, query):
    info = get_wifi_status()
    profiles = get_wifi_profiles()
    q = query.strip().lower()
    items = []

    state = info.get("State", "")
    ssid = info.get("SSID", "")
    if state or ssid:
        signal = info.get("Signal", "")
        items.append(
            {
                "id": "__current__",
                "title": ssid or "Not connected",
                "subtitle": " · ".join([p for p in (state, signal) if p]),
                "icon": "wifi",
                "section": "Current connection",
                "preview": {
                    "metadata": [
                        {"label": "State", "text": state or "—"},
                        {"label": "Signal", "text": signal or "—"},
                        {"label": "Radio type", "text": info.get("Radio type", "—")},
                        {"label": "Channel", "text": info.get("Channel", "—")},
                        {"label": "Authentication", "text": info.get("Authentication", "—")},
                        {"label": "Receive rate", "text": info.get("Receive rate (Mbps)", "—")},
                        {"label": "Transmit rate", "text": info.get("Transmit rate (Mbps)", "—")},
                    ]
                },
                "actions": [{"id": "refresh", "title": "Refresh", "icon": "refresh"}],
            }
        )

    for name in profiles:
        if q and q not in name.lower():
            continue
        is_current = bool(ssid) and name == ssid
        items.append(
            {
                "id": name,
                "title": name,
                "subtitle": "Connected now" if is_current else "Saved network",
                "icon": "wifi",
                "section": "Saved networks",
                "actions": [
                    {"id": "connect", "title": "Connect", "icon": "link"},
                    {
                        "id": "copy_password",
                        "title": "Copy password",
                        "icon": "key",
                        "confirm": {
                            "title": f'Copy password for "{name}"?',
                            "message": "The saved Wi-Fi password will be copied to your clipboard.",
                            "confirmLabel": "Copy",
                        },
                    },
                ],
            }
        )

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "placeholder": "Filter saved networks… (Esc to go back)",
            "preview": {"enabled": True},
            "emptyText": "No Wi-Fi info available",
            "canGoBack": True,
            "actions": [{"id": "refresh", "title": "Refresh", "icon": "refresh"}],
            "items": items,
        }
    )


# ------------------------------------------------------------ adapters -----

def collect_adapters(query):
    addrs = psutil.net_if_addrs()
    stats = psutil.net_if_stats()
    rows = []
    for name, alist in addrs.items():
        ipv4 = next((a.address for a in alist if a.family == socket.AF_INET), None)
        ipv6 = next((a.address for a in alist if a.family == socket.AF_INET6), None)
        mac = next((a.address for a in alist if a.family == psutil.AF_LINK), None)
        netmask = next((a.netmask for a in alist if a.family == socket.AF_INET), None)
        st = stats.get(name)
        rows.append(
            {
                "name": name,
                "ipv4": ipv4,
                "ipv6": ipv6,
                "mac": mac,
                "netmask": netmask,
                "up": bool(st.isup) if st else False,
                "speed": st.speed if st else 0,
                "mtu": st.mtu if st else 0,
            }
        )
    q = query.strip().lower()
    if q:
        rows = [r for r in rows if q in r["name"].lower() or (r["ipv4"] and q in r["ipv4"])]
    rows.sort(key=lambda r: (not r["up"], not r["ipv4"], r["name"].lower()))
    return rows


def render_adapters(rev, query):
    rows = collect_adapters(query)
    items = []
    for r in rows:
        items.append(
            {
                "id": r["name"],
                "title": r["name"],
                "subtitle": r["ipv4"] or ("up, no IPv4" if r["up"] else "down"),
                "icon": "globe",
                "section": "Up" if r["up"] else "Down",
                "accessories": [{"text": "up" if r["up"] else "down", "color": "#22C55E" if r["up"] else "#8A8A8A"}],
                "preview": {
                    "metadata": [
                        {"label": "IPv4", "text": r["ipv4"] or "—"},
                        {"label": "Netmask", "text": r["netmask"] or "—"},
                        {"label": "IPv6", "text": r["ipv6"] or "—"},
                        {"label": "MAC", "text": r["mac"] or "—"},
                        {"label": "Speed", "text": f"{r['speed']} Mbps" if r["speed"] else "—"},
                        {"label": "MTU", "text": str(r["mtu"]) if r["mtu"] else "—"},
                    ]
                },
                "actions": [{"id": "copy_ip", "title": "Copy IPv4", "icon": "copy"}] if r["ipv4"] else [],
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "placeholder": "Filter adapters… (Esc to go back)",
            "preview": {"enabled": True},
            "emptyText": "No adapters found",
            "canGoBack": True,
            "actions": [{"id": "refresh", "title": "Refresh", "icon": "refresh"}],
            "items": items,
        }
    )


# ---------------------------------------------------------------- ping -----

def render_ping_input(rev):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "placeholder": "Type a host or IP, press Enter to ping…",
            "emptyText": "",
            "empty": {"icon": "bolt", "title": "Ping a host", "hint": "Type a hostname or IP, then press Enter"},
            "inputMode": "submit",
            "canGoBack": True,
            "items": [],
        }
    )


def do_ping(rev, host):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "loading": True,
            "loadingText": f"Pinging {host}…",
            "detail": {"markdown": ""},
            "canGoBack": True,
        }
    )
    try:
        out = subprocess.run(["ping", "-n", "4", host], capture_output=True, timeout=15)
        raw = out.stdout.decode("utf-8", errors="ignore") or out.stdout.decode("cp437", errors="ignore")
    except Exception as e:
        raw = f"Ping failed: {e}"
    STATE["ping_host"] = host
    STATE["screen"] = "ping_result"
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "detail": {"markdown": f"### Ping {host}\n\n```\n{raw.strip()}\n```"},
            "canGoBack": True,
            "actions": [{"id": "ping_again", "title": "Ping again", "icon": "bolt"}],
        }
    )


# ------------------------------------------------------------ public ip ----

def render_publicip(rev):
    STATE["public_ip"] = None
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "loading": True,
            "loadingText": "Looking up your public IP…",
            "detail": {"markdown": ""},
            "canGoBack": True,
        }
    )
    try:
        with urllib.request.urlopen("https://api.ipify.org", timeout=8) as resp:
            ip = resp.read().decode("utf-8", errors="ignore").strip()
    except Exception as e:
        ip = None
        err = str(e)
    if ip:
        STATE["public_ip"] = ip
        send(
            {
                "type": "render",
                "rev": 0,
                "view": "detail",
                "detail": {"markdown": f"### Public IP\n\n**{ip}**", "metadata": [{"label": "Address", "text": ip}]},
                "canGoBack": True,
                "actions": [{"id": "copy_ip", "title": "Copy IP", "icon": "copy"}],
            }
        )
    else:
        send(
            {
                "type": "render",
                "rev": 0,
                "view": "detail",
                "detail": {"markdown": f"### Public IP\n\nLookup failed: `{err}`"},
                "canGoBack": True,
            }
        )


# ---------------------------------------------------------------- dns -----

def flush_dns():
    try:
        subprocess.run(["ipconfig", "/flushdns"], capture_output=True, timeout=10)
        send({"type": "command", "command": "toast", "text": "DNS cache flushed"})
    except Exception as e:
        send({"type": "command", "command": "toast", "text": f"Flush failed: {e}", "style": "error"})


# ---------------------------------------------------------------- main -----

def dispatch_query(rev, text):
    screen = STATE["screen"]
    if screen == "root":
        STATE["root_query"] = text
        render_root(rev, text)
    elif screen == "ports":
        STATE["ports_query"] = text
        render_ports(rev, text)
    elif screen == "procs":
        STATE["procs_query"] = text
        render_procs(rev, text)
    elif screen == "wifi":
        STATE["wifi_query"] = text
        render_wifi(rev, text)
    elif screen == "adapters":
        STATE["adapters_query"] = text
        render_adapters(rev, text)
    elif screen == "ping_input":
        render_ping_input(rev)
    elif screen == "ping_result":
        send({"type": "render", "rev": rev, "view": "detail",
              "detail": {"markdown": f"### Ping {STATE['ping_host']}\n\nPress Ctrl+K → Ping again, or Esc to go back."},
              "canGoBack": True})
    elif screen == "publicip":
        pass  # nothing to do on keystrokes here


def handle_back():
    screen = STATE["screen"]
    if screen == "ping_result":
        STATE["screen"] = "ping_input"
        render_ping_input(0)
    else:
        goto("root")
        render_root(0, STATE["root_query"])


def handle_action(item_id, action):
    screen = STATE["screen"]

    if screen == "root":
        if action == "refresh":
            render_root(0, STATE["root_query"])
            return
        if item_id == "cmd:flushdns":
            flush_dns()
            return
        mapping = {
            "cmd:ports": "ports",
            "cmd:procs": "procs",
            "cmd:wifi": "wifi",
            "cmd:adapters": "adapters",
            "cmd:ping": "ping_input",
            "cmd:publicip": "publicip",
        }
        target = mapping.get(item_id)
        if target:
            goto(target)
            if target == "ping_input":
                render_ping_input(0)
            elif target == "publicip":
                render_publicip(0)
            elif target == "ports":
                render_ports(0, "")
            elif target == "procs":
                render_procs(0, "")
            elif target == "wifi":
                render_wifi(0, "")
            elif target == "adapters":
                render_adapters(0, "")
        return

    if screen == "ports":
        if action == "refresh":
            render_ports(0, STATE["ports_query"])
            return
        if action == "default":
            action = "copy_port"
        rows = collect_ports(STATE["ports_query"])
        row = next((r for r in rows if port_item_id(r) == item_id), None)
        if not row:
            render_ports(0, STATE["ports_query"])
            return
        if action == "copy_port":
            send({"type": "command", "command": "copy", "text": str(row["port"])})
        elif action == "kill":
            try:
                psutil.Process(row["pid"]).terminate()
                send({"type": "command", "command": "toast", "text": f"Killed {row['name']} (PID {row['pid']})"})
            except Exception as e:
                send({"type": "command", "command": "toast", "text": f"Couldn't kill: {e}", "style": "error"})
            render_ports(0, STATE["ports_query"])
        return

    if screen == "procs":
        if action == "refresh":
            render_procs(0, STATE["procs_query"])
            return
        if not item_id:
            return
        pid = int(item_id)
        if action == "copy_pid":
            send({"type": "command", "command": "copy", "text": item_id})
        elif action == "default":
            try:
                psutil.Process(pid).terminate()
                send({"type": "command", "command": "toast", "text": f"Killed PID {pid}"})
            except Exception as e:
                send({"type": "command", "command": "toast", "text": f"Couldn't kill: {e}", "style": "error"})
            render_procs(0, STATE["procs_query"])
        return

    if screen == "wifi":
        if action == "refresh" or item_id == "__current__":
            render_wifi(0, STATE["wifi_query"])
            return
        if action in ("connect", "default"):
            run_netsh(["wlan", "connect", f'name="{item_id}"'])
            send({"type": "command", "command": "toast", "text": f"Connecting to {item_id}…"})
            render_wifi(0, STATE["wifi_query"])
        elif action == "copy_password":
            pw = get_wifi_password(item_id)
            if pw:
                send({"type": "command", "command": "copy", "text": pw})
            else:
                send({"type": "command", "command": "toast", "text": "No password stored (open network?)", "style": "info"})
        return

    if screen == "adapters":
        if action == "refresh":
            render_adapters(0, STATE["adapters_query"])
            return
        if action == "copy_ip":
            rows = collect_adapters(STATE["adapters_query"])
            row = next((r for r in rows if r["name"] == item_id), None)
            if row and row["ipv4"]:
                send({"type": "command", "command": "copy", "text": row["ipv4"]})
        return

    if screen == "ping_result":
        if action == "ping_again":
            STATE["screen"] = "ping_input"
            render_ping_input(0)
        return

    if screen == "publicip":
        if action == "copy_ip" and STATE["public_ip"]:
            send({"type": "command", "command": "copy", "text": STATE["public_ip"]})
        return


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
            break

        elif t in ("init", "query"):
            if psutil is None:
                need_psutil(msg.get("rev", 0))
                continue
            dispatch_query(msg.get("rev", 0), msg.get("text", msg.get("query", "")))

        elif t == "submitQuery":
            if STATE["screen"] == "ping_input":
                host = msg.get("text", "").strip()
                if host:
                    do_ping(msg.get("rev", 0), host)
                else:
                    render_ping_input(msg.get("rev", 0))

        elif t == "action":
            if psutil is None:
                need_psutil(0)
                continue
            handle_action(msg.get("id", ""), msg.get("action", "default"))

        elif t == "back":
            handle_back()


if __name__ == "__main__":
    main()
