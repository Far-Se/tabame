#!/usr/bin/env python3
"""
Tabame Docker plugin.

Pages:
  docker:home                      dashboard  overview + lifecycle kanban + recent containers
  docker:containers                table      full container list, bulk select, filter
  docker:container:<id>            dashboard  info + live CPU/Mem chart + recent logs
  docker:container:<id>:logs       log        full-page follow logs
  docker:images                    table      local images, pull / run / remove
  docker:run                       form       create + start a container from an image
  docker:pull                      form       pull an image without running it
  docker:volumes                   list       volumes, inspect / remove
  docker:volume:<name>             detail     raw `docker volume inspect` output
"""
import sys
import json
import re
import subprocess
import threading
import time

DOCKER = "docker"


# --------------------------------------------------------------------------
# wire protocol helpers
# --------------------------------------------------------------------------

def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# --------------------------------------------------------------------------
# docker CLI helpers
# --------------------------------------------------------------------------

def run_docker(args, timeout=15):
    try:
        p = subprocess.run([DOCKER, *args], capture_output=True, text=True, timeout=timeout)
        return p.returncode == 0, p.stdout, (p.stderr or "").strip()
    except FileNotFoundError:
        return False, "", "docker executable not found on PATH"
    except subprocess.TimeoutExpired:
        return False, "", "docker command timed out"
    except Exception as e:
        return False, "", str(e)


def docker_json_lines(args, timeout=15):
    ok, out, err = run_docker(args, timeout)
    if not ok:
        return None, err
    items = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            items.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return items, None


def docker_ready():
    ok, out, err = run_docker(["info", "--format", "{{.ServerVersion}}"], timeout=8)
    return ok, err


def fetch_version():
    ok, out, _ = run_docker(["version", "--format", "{{.Server.Version}}"], timeout=8)
    return out.strip() if ok else None


def fetch_containers():
    items, err = docker_json_lines(["ps", "-a", "--format", "{{json .}}"])
    if items is None:
        return None, err
    stats_map = {}
    stat_items, _ = docker_json_lines(["stats", "--no-stream", "--format", "{{json .}}"])
    if stat_items:
        for s in stat_items:
            cid = s.get("Container", s.get("ID", ""))
            stats_map[cid] = s
            stats_map[cid[:12]] = s
    out = []
    for c in items:
        cid = c.get("ID", "")
        stat = stats_map.get(cid) or stats_map.get(cid[:12]) or {}
        out.append({
            "id": cid,
            "name": (c.get("Names", "") or "").strip(),
            "image": c.get("Image", ""),
            "state": (c.get("State", "") or "").lower(),
            "status": c.get("Status", ""),
            "ports": c.get("Ports", "") or "",
            "created": c.get("RunningFor") or c.get("CreatedAt", ""),
            "command": (c.get("Command", "") or "").strip('"'),
            "cpu": stat.get("CPUPerc", "—"),
            "mem": stat.get("MemPerc", "—"),
        })
    return out, None


def fetch_images():
    items, err = docker_json_lines(["images", "--format", "{{json .}}"])
    if items is None:
        return None, err
    out = []
    for im in items:
        repo = im.get("Repository", "<none>")
        tag = im.get("Tag", "<none>")
        full = f"{repo}:{tag}" if repo != "<none>" else im.get("ID", "")
        out.append({
            "id": im.get("ID", ""),
            "full": full,
            "size": im.get("Size", ""),
            "created": im.get("CreatedSince", ""),
        })
    return out, None


def fetch_volumes():
    items, err = docker_json_lines(["volume", "ls", "--format", "{{json .}}"])
    if items is None:
        return None, err
    out = []
    for v in items:
        out.append({
            "name": v.get("Name", ""),
            "driver": v.get("Driver", ""),
            "mountpoint": v.get("Mountpoint", ""),
            "scope": v.get("Scope", ""),
        })
    return out, None


def fetch_system_df():
    items, _ = docker_json_lines(["system", "df", "--format", "{{json .}}"])
    return items


def fetch_log_tail(cid, n=50):
    ok, out, err = run_docker(["logs", "--tail", str(n), cid], timeout=10)
    if not ok:
        return [{"level": "error", "text": err or "Could not read logs"}]
    lines = [{"text": ln} for ln in out.splitlines()[-n:]]
    return lines or [{"text": "(no output)"}]


def inspect_container(cid):
    ok, out, _ = run_docker(["inspect", cid], timeout=10)
    if not ok:
        return None
    try:
        data = json.loads(out)
        return data[0] if data else None
    except Exception:
        return None


# --------------------------------------------------------------------------
# in-memory state
# --------------------------------------------------------------------------

STATE = {
    "page": "home",       # home | containers | container | logs | images | run | pull | volumes | volume
    "cid": None,
    "containers": [],
    "images": [],
    "volumes": [],
    "stats_stop": None,
    "stats_series": {"cpu": [], "mem": []},
    "log_stop": None,
    "log_proc": None,
    "log_buffer": [],
}


def split_id(item_id):
    if ":" in item_id:
        k, r = item_id.split(":", 1)
        return k, r
    return "", item_id


# --------------------------------------------------------------------------
# item builders
# --------------------------------------------------------------------------

STATE_COLOR = {"running": "#22C55E", "paused": "#F59E0B"}


def container_actions(c):
    acts = []
    if c["state"] == "running":
        acts.append({"id": "stop", "title": "Stop", "icon": "close"})
        acts.append({"id": "restart", "title": "Restart", "icon": "refresh"})
        acts.append({"id": "pause", "title": "Pause", "icon": "clock"})
    elif c["state"] == "paused":
        acts.append({"id": "unpause", "title": "Resume", "icon": "play"})
        acts.append({"id": "stop", "title": "Stop", "icon": "close"})
    else:
        acts.append({"id": "start", "title": "Start", "icon": "play"})
    acts.append({"id": "logs", "title": "View logs", "icon": "terminal"})
    acts.append({
        "id": "remove", "title": "Remove", "icon": "trash", "destructive": True,
        "confirm": {
            "title": f"Remove {c['name']}?",
            "message": "This force-removes the container.",
            "confirmLabel": "Remove",
        },
    })
    return acts


def container_list_item(c):
    return {
        "id": "c:" + c["id"],
        "title": c["name"] or c["id"][:12],
        "subtitle": c["image"],
        "icon": "server",
        "accessories": [{"text": c["status"], "color": STATE_COLOR.get(c["state"], "#94A3B8")}],
        "actions": container_actions(c),
        "preview": {
            "markdown": f"**{c['name']}**\n\n`{c['id'][:12]}`\n\n{c['status']}",
            "metadata": [
                {"label": "Image", "text": c["image"]},
                {"label": "Ports", "text": c["ports"] or "—"},
                {"label": "Command", "text": c["command"] or "—"},
                {"label": "CPU", "text": c["cpu"]},
                {"label": "Mem", "text": c["mem"]},
            ],
        },
    }


def image_actions(im):
    return [
        {"id": "run", "title": "Run container", "icon": "play"},
        {
            "id": "remove", "title": "Remove image", "icon": "trash", "destructive": True,
            "confirm": {
                "title": f"Remove {im['full']}?",
                "message": "This deletes the local image.",
                "confirmLabel": "Remove",
            },
        },
    ]


def image_list_item(im):
    return {
        "id": "i:" + im["id"],
        "title": im["full"],
        "subtitle": im["id"][:19],
        "icon": "database",
        "accessories": [{"text": im["size"]}],
        "actions": image_actions(im),
        "preview": {
            "markdown": f"**{im['full']}**",
            "metadata": [
                {"label": "Size", "text": im["size"]},
                {"label": "Created", "text": im["created"]},
                {"label": "Image ID", "text": im["id"]},
            ],
        },
    }


# --------------------------------------------------------------------------
# render: home
# --------------------------------------------------------------------------

def render_home(rev):
    ready, err = docker_ready()
    if not ready:
        send({
            "type": "render", "rev": rev, "view": "detail",
            "page": {"id": "docker:home", "title": "Docker", "history": "none"},
            "detail": {"markdown": f"# Docker unavailable\n\nCouldn't reach the Docker daemon.\n\n```\n{err}\n```\n\nMake sure Docker Desktop is running, then retry."},
            "actions": [{"id": "retry", "title": "Retry", "icon": "refresh"}],
        })
        return

    containers, _ = fetch_containers()
    images, _ = fetch_images()
    volumes, _ = fetch_volumes()
    dfitems = fetch_system_df()
    version = fetch_version()
    STATE["containers"] = containers or []
    STATE["images"] = images or []
    STATE["volumes"] = volumes or []

    running = sum(1 for c in STATE["containers"] if c["state"] == "running")
    stopped = len(STATE["containers"]) - running

    meta = [
        {"label": "Docker Engine", "text": version or "unknown"},
        {"label": "Containers", "text": str(len(STATE["containers"]))},
        {"label": "Running", "text": str(running), "color": "#22C55E"},
        {"label": "Stopped", "text": str(stopped), "color": "#94A3B8"},
        {"label": "Images", "text": str(len(STATE["images"]))},
        {"label": "Volumes", "text": str(len(STATE["volumes"]))},
    ]
    if dfitems:
        meta.append({"separator": True})
        for row in dfitems:
            meta.append({
                "label": row.get("Type", ""),
                "text": f"{row.get('Size', '—')} ({row.get('Reclaimable', '—')} reclaimable)",
            })

    kanban_items = []
    for c in STATE["containers"]:
        col = "running" if c["state"] == "running" else "paused" if c["state"] == "paused" else "stopped"
        kanban_items.append({
            "id": c["id"], "title": c["name"] or c["id"][:12], "subtitle": c["image"],
            "column": col,
            "accessories": [{"text": c["status"]}],
        })

    recent = sorted(STATE["containers"], key=lambda c: c["created"])[:5]
    table_items = []
    for c in recent:
        table_items.append({
            "id": "c:" + c["id"], "title": c["name"] or c["id"][:12], "subtitle": c["created"],
            "cells": {"status": c["status"], "image": c["image"]},
            "actions": container_actions(c),
        })

    send({
        "type": "render", "rev": rev, "view": "dashboard",
        "page": {"id": "docker:home", "title": "Docker", "history": "none"},
        "placeholder": "Search containers, images…",
        "dashboard": {
            "layout": "stack",
            "panels": [
                {
                    "id": "overview", "title": "Overview", "view": "detail", "height": 220,
                    "detail": {"markdown": f"**{running} running** · {stopped} stopped", "metadata": meta},
                },
                {
                    "id": "lifecycle", "title": "Container lifecycle — drag to start / stop / pause",
                    "view": "kanban", "height": 260,
                    "kanban": {"columns": [
                        {"id": "running", "title": "Running", "color": "#22C55E"},
                        {"id": "paused", "title": "Paused", "color": "#F59E0B"},
                        {"id": "stopped", "title": "Stopped", "color": "#94A3B8"},
                    ]},
                    "items": kanban_items,
                    "emptyText": "No containers yet",
                },
                {
                    "id": "recent", "title": "Recently created", "view": "table", "height": 220,
                    "columns": [{"id": "status", "label": "Status"}, {"id": "image", "label": "Image"}],
                    "items": table_items,
                    "emptyText": "No containers yet",
                },
            ],
        },
        "actions": [
            {"id": "containers", "title": "Open Containers", "icon": "server", "shortcut": "ctrl+alt+c"},
            {"id": "images", "title": "Open Images", "icon": "database", "shortcut": "ctrl+alt+i"},
            {"id": "volumes", "title": "Open Volumes", "icon": "folder", "shortcut": "ctrl+alt+v"},
            {"id": "refresh", "title": "Refresh", "icon": "refresh", "shortcut": "ctrl+alt+r"},
        ],
        "floatingAction": [
            {"id": "new", "title": "New container", "icon": "add"},
            {"id": "refresh", "title": "Refresh", "icon": "refresh"},
        ],
    })


def render_home_search(rev, text):
    t = text.lower()
    items = []
    for c in STATE["containers"]:
        if t in (c["name"] or "").lower() or t in c["image"].lower():
            items.append(container_list_item(c))
    for im in STATE["images"]:
        if t in im["full"].lower():
            items.append(image_list_item(im))
    send({
        "type": "render", "rev": rev, "view": "list",
        "page": {"id": "docker:home", "title": "Docker", "history": "none"},
        "placeholder": "Search containers, images…",
        "emptyText": f'No matches for "{text}"',
        "items": items,
    })


# --------------------------------------------------------------------------
# render: containers table
# --------------------------------------------------------------------------

def render_containers(rev, text=""):
    items = STATE["containers"]
    if text:
        t = text.lower()
        items = [c for c in items if t in (c["name"] or "").lower() or t in c["image"].lower()]

    columns = [
        {"id": "status", "label": "Status"},
        {"id": "image", "label": "Image"},
        {"id": "ports", "label": "Ports"},
        {"id": "cpu", "label": "CPU", "align": "end"},
        {"id": "mem", "label": "Mem", "align": "end"},
        {"id": "created", "label": "Created"},
    ]
    rows = []
    for c in items:
        rows.append({
            "id": "c:" + c["id"], "title": c["name"] or c["id"][:12], "subtitle": c["id"][:12],
            "cells": {
                "status": c["status"], "image": c["image"], "ports": c["ports"] or "—",
                "cpu": c["cpu"], "mem": c["mem"], "created": c["created"],
            },
            "actions": container_actions(c),
        })

    send({
        "type": "render", "rev": rev, "view": "table",
        "page": {
            "id": "docker:containers", "title": "Containers", "history": "push",
            "breadcrumbs": [{"id": "docker:home", "label": "Docker"}],
        },
        "placeholder": "Filter containers…",
        "columns": columns,
        "items": rows,
        "selection": {"enabled": True, "max": 50},
        "empty": {
            "icon": "server", "title": "No containers", "hint": "Create one from an image",
            "action": {"id": "new", "title": "New container", "icon": "add"},
        },
        "actions": [
            {"id": "refresh", "title": "Refresh", "icon": "refresh", "shortcut": "ctrl+alt+r"},
            {"id": "new", "title": "New container", "icon": "add"},
        ],
        "floatingAction": [
            {"id": "bulk_stop", "title": "Stop selected", "icon": "close"},
            {
                "id": "bulk_remove", "title": "Remove selected", "icon": "trash", "destructive": True,
                "confirm": {
                    "title": "Remove selected containers?",
                    "message": "This force-removes them.",
                    "confirmLabel": "Remove",
                },
            },
        ],
    })


# --------------------------------------------------------------------------
# render: container detail (dashboard) + live stats polling
# --------------------------------------------------------------------------

def build_container_panels(c, inspect, log_lines):
    meta = [
        {"label": "Status", "text": c["status"]},
        {"label": "Image", "text": c["image"]},
        {"label": "Command", "text": c["command"] or "—"},
        {"label": "Ports", "text": c["ports"] or "—"},
        {"label": "Created", "text": c["created"]},
    ]
    if inspect:
        rp = ((inspect.get("HostConfig") or {}).get("RestartPolicy") or {}).get("Name", "")
        ip = (inspect.get("NetworkSettings") or {}).get("IPAddress", "") or "—"
        meta.append({"label": "Restart policy", "text": rp or "no"})
        meta.append({"label": "IP address", "text": ip})

    series = STATE["stats_series"]
    panels = [
        {
            "id": "info", "title": "Info", "view": "detail", "height": 220,
            "detail": {"markdown": f"### {c['name']}\n`{c['id'][:12]}`", "metadata": meta},
        },
        {
            "id": "stats", "title": "CPU / Memory — live", "view": "chart", "height": 200,
            "chart": {"title": "Usage %", "series": [
                {"id": "cpu", "label": "CPU %", "values": series["cpu"] or [0], "color": "#63A0EA"},
                {"id": "mem", "label": "Mem %", "values": series["mem"] or [0], "color": "#F59E0B"},
            ]},
        },
        {
            "id": "logs", "title": "Recent logs (tail 50 — open Logs to follow live)", "view": "log", "height": 220,
            "log": {"follow": False, "wrap": False, "lines": log_lines},
        },
    ]
    return panels


def render_container_detail(rev, cid, refresh=True):
    if refresh:
        containers, _ = fetch_containers()
        if containers is not None:
            STATE["containers"] = containers

    c = next((c for c in STATE["containers"] if c["id"] == cid or c["id"][:12] == cid), None)
    if not c:
        send({
            "type": "render", "rev": rev, "view": "detail",
            "page": {"id": f"docker:container:{cid}", "title": "Container", "history": "push"},
            "detail": {"markdown": "# Not found\n\nThis container no longer exists."},
            "actions": [{"id": "back_containers", "title": "Back to Containers", "icon": "server"}],
        })
        return

    inspect = inspect_container(cid)
    log_lines = fetch_log_tail(cid, 50)

    if c["state"] == "running":
        floating = [
            {"id": "stop", "title": "Stop", "icon": "close"},
            {"id": "restart", "title": "Restart", "icon": "refresh"},
        ]
    elif c["state"] == "paused":
        floating = [{"id": "unpause", "title": "Resume", "icon": "play"}]
    else:
        floating = [{"id": "start", "title": "Start", "icon": "play"}]
    floating.append({"id": "logs", "title": "Logs", "icon": "terminal"})

    send({
        "type": "render", "rev": rev, "view": "dashboard",
        "page": {
            "id": f"docker:container:{cid}", "title": c["name"] or cid[:12], "history": "push",
            "breadcrumbs": [
                {"id": "docker:home", "label": "Docker"},
                {"id": "docker:containers", "label": "Containers"},
            ],
        },
        "dashboard": {"layout": "stack", "panels": build_container_panels(c, inspect, log_lines)},
        "actions": [
            {"id": "refresh", "title": "Refresh", "icon": "refresh", "shortcut": "ctrl+alt+r"},
            {"id": "logs", "title": "Open full logs", "icon": "terminal"},
            {
                "id": "remove", "title": "Remove", "icon": "trash", "destructive": True,
                "confirm": {
                    "title": f"Remove {c['name']}?",
                    "message": "This force-removes the container.",
                    "confirmLabel": "Remove",
                },
            },
        ],
        "floatingAction": floating,
    })
    start_stats_polling(cid)


def start_stats_polling(cid):
    stop_stats_polling()
    STATE["stats_series"] = {"cpu": [], "mem": []}
    stop_evt = threading.Event()
    STATE["stats_stop"] = stop_evt

    def worker():
        while not stop_evt.is_set():
            stop_evt.wait(2.5)
            if stop_evt.is_set():
                break
            ok, out, _ = run_docker(["stats", "--no-stream", "--format", "{{json .}}", cid], timeout=8)
            if not ok or not out.strip():
                continue
            try:
                s = json.loads(out.strip().splitlines()[0])
                cpu = float(re.sub(r"[^\d.]", "", s.get("CPUPerc", "0") or "0") or 0)
                mem = float(re.sub(r"[^\d.]", "", s.get("MemPerc", "0") or "0") or 0)
            except Exception as e:
                log("stats parse error", e)
                continue
            series = STATE["stats_series"]
            series["cpu"] = (series["cpu"] + [cpu])[-20:]
            series["mem"] = (series["mem"] + [mem])[-20:]
            if stop_evt.is_set() or STATE["page"] != "container" or STATE["cid"] != cid:
                continue
            c = next((c for c in STATE["containers"] if c["id"] == cid), None)
            if not c:
                continue
            send({
                "type": "render", "rev": 0, "view": "dashboard",
                "page": {
                    "id": f"docker:container:{cid}", "title": c["name"] or cid[:12], "history": "none",
                },
                "dashboard": {"layout": "stack", "panels": build_container_panels(c, None, STATE["log_buffer"] or fetch_log_tail(cid, 50))},
            })

    t = threading.Thread(target=worker, daemon=True)
    t.start()


def stop_stats_polling():
    evt = STATE.get("stats_stop")
    if evt:
        evt.set()
    STATE["stats_stop"] = None


# --------------------------------------------------------------------------
# render: full-page logs (follow)
# --------------------------------------------------------------------------

def render_logs_page(rev, cid, cname):
    tail = fetch_log_tail(cid, 100)
    STATE["log_buffer"] = tail
    send({
        "type": "render", "rev": rev, "view": "log",
        "page": {
            "id": f"docker:container:{cid}:logs", "title": f"Logs · {cname}", "history": "push",
            "breadcrumbs": [
                {"id": "docker:home", "label": "Docker"},
                {"id": "docker:containers", "label": "Containers"},
                {"id": f"docker:container:{cid}", "label": cname or "Container"},
            ],
        },
        "log": {"follow": True, "wrap": False, "lines": tail},
        "actions": [{"id": "refresh", "title": "Refresh", "icon": "refresh"}],
    })
    start_log_follow(cid)


def start_log_follow(cid):
    stop_log_follow()
    stop_evt = threading.Event()
    STATE["log_stop"] = stop_evt

    def worker():
        try:
            proc = subprocess.Popen(
                [DOCKER, "logs", "-f", "--tail", "150", cid],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
            )
        except Exception as e:
            send({
                "type": "render", "rev": 0, "view": "log",
                "page": {"id": f"docker:container:{cid}:logs", "title": "Logs", "history": "none"},
                "log": {"follow": True, "lines": [{"level": "error", "text": str(e)}]},
            })
            return
        STATE["log_proc"] = proc
        last_send = 0.0
        while not stop_evt.is_set():
            line = proc.stdout.readline()
            if not line:
                if proc.poll() is not None:
                    break
                continue
            STATE["log_buffer"].append({"text": line.rstrip("\n")})
            STATE["log_buffer"] = STATE["log_buffer"][-500:]
            now = time.time()
            if now - last_send > 0.25 and STATE["page"] == "logs" and STATE["cid"] == cid:
                last_send = now
                send({
                    "type": "render", "rev": 0, "view": "log",
                    "page": {"id": f"docker:container:{cid}:logs", "title": "Logs", "history": "none"},
                    "log": {"follow": True, "wrap": False, "lines": STATE["log_buffer"]},
                })
        try:
            proc.terminate()
        except Exception:
            pass

    t = threading.Thread(target=worker, daemon=True)
    t.start()


def stop_log_follow():
    evt = STATE.get("log_stop")
    if evt:
        evt.set()
    proc = STATE.get("log_proc")
    if proc:
        try:
            proc.terminate()
        except Exception:
            pass
    STATE["log_proc"] = None
    STATE["log_stop"] = None


# --------------------------------------------------------------------------
# render: images table
# --------------------------------------------------------------------------

def render_images(rev, text=""):
    items = STATE["images"]
    if text:
        t = text.lower()
        items = [im for im in items if t in im["full"].lower()]

    columns = [{"id": "size", "label": "Size", "align": "end"}, {"id": "created", "label": "Created"}]
    rows = []
    for im in items:
        rows.append({
            "id": "i:" + im["id"], "title": im["full"], "subtitle": im["id"][:19],
            "cells": {"size": im["size"], "created": im["created"]},
            "actions": image_actions(im),
        })

    send({
        "type": "render", "rev": rev, "view": "table",
        "page": {
            "id": "docker:images", "title": "Images", "history": "push",
            "breadcrumbs": [{"id": "docker:home", "label": "Docker"}],
        },
        "placeholder": "Filter images…",
        "columns": columns,
        "items": rows,
        "empty": {
            "icon": "database", "title": "No images", "hint": "Pull one to get started",
            "action": {"id": "pull", "title": "Pull image", "icon": "download"},
        },
        "actions": [
            {"id": "refresh", "title": "Refresh", "icon": "refresh", "shortcut": "ctrl+alt+r"},
            {"id": "pull", "title": "Pull image", "icon": "download"},
        ],
        "floatingAction": {"id": "pull", "title": "Pull image", "icon": "download"},
    })


# --------------------------------------------------------------------------
# render: forms
# --------------------------------------------------------------------------

def render_run_form(rev, image=""):
    options = sorted({im["full"] for im in STATE["images"] if im["full"] and "<none>" not in im["full"]})
    send({
        "type": "render", "rev": rev, "view": "form",
        "page": {
            "id": "docker:run", "title": "New container", "history": "push",
            "breadcrumbs": [{"id": "docker:home", "label": "Docker"}],
        },
        "form": {
            "title": "Run a new container",
            "submitLabel": "Run",
            "fields": [
                {
                    "id": "image", "type": "combobox", "label": "Image", "required": True,
                    "value": image, "allowCustom": True, "options": options,
                    "description": "Pick a local image, or type one to pull it",
                },
                {"id": "name", "type": "text", "label": "Container name", "placeholder": "optional"},
                {
                    "id": "ports", "type": "text", "label": "Port mapping",
                    "placeholder": "8080:80, 5432:5432",
                    "description": "host:container pairs, comma-separated",
                },
                {
                    "id": "env", "type": "tags", "label": "Environment variables", "options": [],
                    "description": "KEY=VALUE, press Enter after each",
                },
                {"id": "command", "type": "text", "label": "Command", "placeholder": "optional override"},
            ],
        },
    })


def render_pull_form(rev):
    send({
        "type": "render", "rev": rev, "view": "form",
        "page": {
            "id": "docker:pull", "title": "Pull image", "history": "push",
            "breadcrumbs": [{"id": "docker:home", "label": "Docker"}, {"id": "docker:images", "label": "Images"}],
        },
        "form": {
            "title": "Pull an image",
            "submitLabel": "Pull",
            "fields": [{"id": "image", "type": "text", "label": "Image", "placeholder": "nginx:latest", "required": True}],
        },
    })


def run_operation(rev, op_id, title, work_fn, on_success, on_error):
    send({
        "type": "render", "rev": rev, "view": "operation",
        "page": {"id": f"docker:op:{op_id}", "title": title, "history": "none"},
        "operation": {"id": op_id, "title": title, "cancellable": False},
    })

    def worker():
        try:
            result = work_fn()
            on_success(result)
        except Exception as e:
            on_error(str(e))

    threading.Thread(target=worker, daemon=True).start()


def do_pull(image_name):
    def work():
        ok, out, err = run_docker(["pull", image_name], timeout=600)
        if not ok:
            raise RuntimeError(err or "pull failed")
        return out

    def success(_out):
        images, _ = fetch_images()
        STATE["images"] = images or []
        send({"type": "command", "command": "toast", "text": f"Pulled {image_name}"})
        STATE["page"] = "images"
        render_images(0)

    def error(msg):
        send({
            "type": "render", "rev": 0, "view": "detail",
            "page": {"id": "docker:op:pull", "title": "Pull failed", "history": "none"},
            "detail": {"markdown": f"# Pull failed\n\n```\n{msg}\n```"},
            "actions": [{"id": "back_images", "title": "Back to Images", "icon": "database"}],
        })

    run_operation(0, "pull-" + image_name, f"Pulling {image_name}…", work, success, error)


def do_run(values):
    image = (values.get("image") or "").strip()
    if not image:
        return
    args = ["run", "-d"]
    name = (values.get("name") or "").strip()
    if name:
        args += ["--name", name]
    ports = (values.get("ports") or "").strip()
    if ports:
        for p in ports.split(","):
            p = p.strip()
            if p:
                args += ["-p", p]
    for e in (values.get("env") or []):
        if "=" in e:
            args += ["-e", e]
    args.append(image)
    command = (values.get("command") or "").strip()
    if command:
        args += command.split()

    def work():
        ok, out, err = run_docker(args, timeout=300)
        if not ok:
            raise RuntimeError(err or "run failed")
        return out.strip()

    def success(cid):
        containers, _ = fetch_containers()
        STATE["containers"] = containers or []
        send({"type": "command", "command": "toast", "text": "Container started"})
        STATE["page"] = "container"
        STATE["cid"] = cid
        render_container_detail(0, cid, refresh=False)

    def error(msg):
        send({
            "type": "render", "rev": 0, "view": "detail",
            "page": {"id": "docker:op:run", "title": "Run failed", "history": "none"},
            "detail": {"markdown": f"# Couldn't start container\n\n```\n{msg}\n```"},
            "actions": [{"id": "back_containers", "title": "Back to Containers", "icon": "server"}],
        })

    run_operation(0, "run-" + image, f"Starting {image}…", work, success, error)


# --------------------------------------------------------------------------
# render: volumes
# --------------------------------------------------------------------------

def render_volumes(rev, text=""):
    items = STATE["volumes"]
    if text:
        t = text.lower()
        items = [v for v in items if t in v["name"].lower()]

    rows = []
    for v in items:
        rows.append({
            "id": "v:" + v["name"], "title": v["name"], "subtitle": v["driver"],
            "icon": "folder",
            "accessories": [{"text": v["scope"]}],
            "actions": [
                {"id": "inspect", "title": "Inspect", "icon": "info"},
                {
                    "id": "remove", "title": "Remove", "icon": "trash", "destructive": True,
                    "confirm": {
                        "title": f"Remove volume {v['name']}?",
                        "message": "This deletes the volume and its data.",
                        "confirmLabel": "Remove",
                    },
                },
            ],
            "preview": {
                "markdown": f"**{v['name']}**",
                "metadata": [
                    {"label": "Driver", "text": v["driver"]},
                    {"label": "Mountpoint", "text": v["mountpoint"]},
                    {"label": "Scope", "text": v["scope"]},
                ],
            },
        })

    send({
        "type": "render", "rev": rev, "view": "list",
        "page": {
            "id": "docker:volumes", "title": "Volumes", "history": "push",
            "breadcrumbs": [{"id": "docker:home", "label": "Docker"}],
        },
        "placeholder": "Filter volumes…",
        "preview": {"enabled": True},
        "items": rows,
        "emptyText": "No volumes",
        "actions": [{"id": "refresh", "title": "Refresh", "icon": "refresh", "shortcut": "ctrl+alt+r"}],
    })


def render_volume_inspect(rev, name):
    ok, out, err = run_docker(["volume", "inspect", name], timeout=10)
    md = f"# {name}\n\n```json\n{out.strip()}\n```" if ok else f"# {name}\n\nCouldn't inspect volume.\n\n```\n{err}\n```"
    send({
        "type": "render", "rev": rev, "view": "detail",
        "page": {
            "id": f"docker:volume:{name}", "title": name, "history": "push",
            "breadcrumbs": [{"id": "docker:home", "label": "Docker"}, {"id": "docker:volumes", "label": "Volumes"}],
        },
        "detail": {"markdown": md},
    })


# --------------------------------------------------------------------------
# navigation
# --------------------------------------------------------------------------

def clear_query():
    send({"type": "command", "command": "setQuery", "text": " "})


def goto_home(rev):
    stop_stats_polling()
    stop_log_follow()
    STATE["page"] = "home"
    STATE["cid"] = None
    clear_query()
    render_home(rev)


def goto_containers(rev):
    stop_stats_polling()
    stop_log_follow()
    STATE["page"] = "containers"
    STATE["cid"] = None
    clear_query()
    containers, _ = fetch_containers()
    STATE["containers"] = containers if containers is not None else STATE["containers"]
    render_containers(rev)


def goto_images(rev):
    stop_stats_polling()
    stop_log_follow()
    STATE["page"] = "images"
    STATE["cid"] = None
    clear_query()
    images, _ = fetch_images()
    STATE["images"] = images if images is not None else STATE["images"]
    render_images(rev)


def goto_volumes(rev):
    stop_stats_polling()
    stop_log_follow()
    STATE["page"] = "volumes"
    STATE["cid"] = None
    clear_query()
    volumes, _ = fetch_volumes()
    STATE["volumes"] = volumes if volumes is not None else STATE["volumes"]
    render_volumes(rev)


def goto_container(rev, cid):
    stop_log_follow()
    if STATE.get("cid") != cid:
        stop_stats_polling()
    STATE["page"] = "container"
    STATE["cid"] = cid
    clear_query()
    render_container_detail(rev, cid)


def goto_logs(rev, cid):
    stop_stats_polling()
    STATE["page"] = "logs"
    STATE["cid"] = cid
    cname = next((c["name"] for c in STATE["containers"] if c["id"] == cid), "")
    clear_query()
    render_logs_page(rev, cid, cname)


def goto_run(rev, image=""):
    stop_stats_polling()
    stop_log_follow()
    STATE["page"] = "run"
    STATE["cid"] = None
    clear_query()
    render_run_form(rev, image)


def goto_pull(rev):
    stop_stats_polling()
    stop_log_follow()
    STATE["page"] = "pull"
    clear_query()
    render_pull_form(rev)


def goto_volume_inspect(rev, name):
    stop_stats_polling()
    stop_log_follow()
    STATE["page"] = "volume"
    STATE["cid"] = None
    clear_query()
    render_volume_inspect(rev, name)


def refresh_current(rev):
    page = STATE["page"]
    if page == "home":
        render_home(rev)
    elif page == "containers":
        containers, _ = fetch_containers()
        STATE["containers"] = containers if containers is not None else STATE["containers"]
        render_containers(rev)
    elif page == "images":
        images, _ = fetch_images()
        STATE["images"] = images if images is not None else STATE["images"]
        render_images(rev)
    elif page == "volumes":
        volumes, _ = fetch_volumes()
        STATE["volumes"] = volumes if volumes is not None else STATE["volumes"]
        render_volumes(rev)
    elif page == "container":
        render_container_detail(rev, STATE["cid"])


def do_remove_container(cid):
    run_docker(["rm", "-f", cid])
    containers, _ = fetch_containers()
    STATE["containers"] = containers or []


# --------------------------------------------------------------------------
# event handlers
# --------------------------------------------------------------------------

def route_query(rev, text):
    page = STATE["page"]
    if page == "home":
        if text:
            render_home_search(rev, text)
        else:
            render_home(rev)
    elif page == "containers":
        render_containers(rev, text)
    elif page == "images":
        render_images(rev, text)
    elif page == "volumes":
        render_volumes(rev, text)
    # container / logs / run / pull / volume pages ignore free-text filtering


def handle_frame_action(rev, action, ids):
    page = STATE["page"]
    if action == "retry":
        goto_home(rev)
    elif action == "refresh":
        refresh_current(rev)
    elif action == "containers":
        goto_containers(rev)
    elif action == "images":
        goto_images(rev)
    elif action == "volumes":
        goto_volumes(rev)
    elif action == "new":
        goto_run(rev)
    elif action == "pull":
        goto_pull(rev)
    elif action == "back_home":
        goto_home(rev)
    elif action == "back_containers":
        goto_containers(rev)
    elif action == "back_images":
        goto_images(rev)
    elif action == "logs" and page == "container":
        goto_logs(rev, STATE["cid"])
    elif action == "remove" and page == "container":
        cid = STATE["cid"]
        do_remove_container(cid)
        send({"type": "command", "command": "toast", "text": "Container removed"})
        goto_containers(rev)
    elif action == "start" and page == "container":
        run_docker(["start", STATE["cid"]])
        refresh_current(0)
    elif action == "stop" and page == "container":
        run_docker(["stop", STATE["cid"]])
        refresh_current(0)
    elif action == "restart" and page == "container":
        run_docker(["restart", STATE["cid"]])
        refresh_current(0)
    elif action == "unpause" and page == "container":
        run_docker(["unpause", STATE["cid"]])
        refresh_current(0)
    elif action == "bulk_stop" and ids:
        for iid in ids:
            _, cid = split_id(iid)
            run_docker(["stop", cid])
        refresh_current(0)
    elif action == "bulk_remove" and ids:
        for iid in ids:
            _, cid = split_id(iid)
            run_docker(["rm", "-f", cid])
        refresh_current(0)


def handle_container_action(rev, cid, action):
    if action == "default":
        goto_container(rev, cid)
    elif action == "start":
        run_docker(["start", cid])
        after_container_op()
    elif action == "stop":
        run_docker(["stop", cid])
        after_container_op()
    elif action == "restart":
        run_docker(["restart", cid])
        after_container_op()
    elif action == "pause":
        run_docker(["pause", cid])
        after_container_op()
    elif action == "unpause":
        run_docker(["unpause", cid])
        after_container_op()
    elif action == "logs":
        goto_logs(rev, cid)
    elif action == "remove":
        do_remove_container(cid)
        send({"type": "command", "command": "toast", "text": "Container removed"})
        if STATE["page"] == "container" and STATE["cid"] == cid:
            goto_containers(rev)
        else:
            refresh_current(0)


def after_container_op():
    containers, _ = fetch_containers()
    STATE["containers"] = containers or []
    refresh_current(0)


def handle_image_action(rev, iid, action):
    im = next((x for x in STATE["images"] if x["id"] == iid), None)
    if action in ("default", "run"):
        goto_run(rev, image=(im["full"] if im else ""))
    elif action == "remove":
        run_docker(["rmi", iid])
        images, _ = fetch_images()
        STATE["images"] = images or []
        send({"type": "command", "command": "toast", "text": "Image removed"})
        render_images(0)


def handle_volume_action(rev, name, action):
    if action in ("default", "inspect"):
        goto_volume_inspect(rev, name)
    elif action == "remove":
        run_docker(["volume", "rm", name])
        volumes, _ = fetch_volumes()
        STATE["volumes"] = volumes or []
        send({"type": "command", "command": "toast", "text": "Volume removed"})
        render_volumes(0)


def handle_action(rev, msg):
    item_id = msg.get("id", "")
    action = msg.get("action", "default")
    ids = msg.get("ids")
    if item_id == "":
        handle_frame_action(rev, action, ids)
        return
    kind, real_id = split_id(item_id)
    if kind == "c":
        handle_container_action(rev, real_id, action)
    elif kind == "i":
        handle_image_action(rev, real_id, action)
    elif kind == "v":
        handle_volume_action(rev, real_id, action)


def handle_submit(rev, msg):
    values = msg.get("values", {})
    if STATE["page"] == "run":
        do_run(values)
    elif STATE["page"] == "pull":
        image = (values.get("image") or "").strip()
        if image:
            do_pull(image)


def handle_back(rev, to_page_id):
    stop_stats_polling()
    stop_log_follow()
    if not to_page_id or to_page_id == "docker:home":
        goto_home(rev)
    elif to_page_id == "docker:containers":
        goto_containers(rev)
    elif to_page_id == "docker:images":
        goto_images(rev)
    elif to_page_id == "docker:volumes":
        goto_volumes(rev)
    elif to_page_id.startswith("docker:container:") and to_page_id.count(":") == 2:
        goto_container(rev, to_page_id.split(":", 2)[2])
    else:
        goto_home(rev)


def handle_kanban_move(msg):
    cid = msg.get("id", "")
    target = msg.get("columnId")
    if target == "running":
        run_docker(["start", cid])
    elif target == "stopped":
        run_docker(["stop", cid])
    elif target == "paused":
        run_docker(["pause", cid])
    if STATE["page"] == "home":
        render_home(0)


# --------------------------------------------------------------------------
# main loop
# --------------------------------------------------------------------------

def cleanup():
    stop_stats_polling()
    stop_log_follow()


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
        try:
            if t == "close":
                cleanup()
                break
            elif t in ("init", "query"):
                rev = msg.get("rev", 0)
                text = (msg.get("text", msg.get("query", "")) or "").strip()
                route_query(rev, text)
            elif t == "action":
                handle_action(msg.get("rev", 0), msg)
            elif t == "submit":
                handle_submit(msg.get("rev", 0), msg)
            elif t == "back":
                handle_back(0, msg.get("toPageId"))
            elif t == "navigate":
                handle_back(0, msg.get("targetPageId"))
            elif t == "kanbanMove":
                handle_kanban_move(msg)
            # select / cancel / toggle / chartSelect / loadMore / tab: no-op
        except Exception as e:
            log("handler error:", e)
    cleanup()


if __name__ == "__main__":
    main()
