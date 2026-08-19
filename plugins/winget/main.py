#!/usr/bin/env python3
"""
Tabame launcher plugin: WinGet dashboard.
Search, install, update and uninstall Windows apps through winget,
with a confirm dialog before every change.
"""

import json
import re
import shutil
import subprocess
import sys
import threading
import time

# ---------------------------------------------------------------------------
# stdio helpers
# ---------------------------------------------------------------------------

STDOUT_LOCK = threading.Lock()


def send(frame):
    with STDOUT_LOCK:
        sys.stdout.write(json.dumps(frame) + "\n")
        sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# winget process helpers
# ---------------------------------------------------------------------------

NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
WINGET = shutil.which("winget")


def run_winget(args, timeout=120):
    """Run winget and return (ok, stdout)."""
    if not WINGET:
        return False, "winget was not found on PATH."
    try:
        proc = subprocess.run(
            [WINGET, *args],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            creationflags=NO_WINDOW,
        )
        out = (proc.stdout or "") + "\n" + (proc.stderr or "")
        return proc.returncode == 0, out
    except subprocess.TimeoutExpired:
        return False, "Command timed out."
    except Exception as e:  # noqa: BLE001
        return False, str(e)


def parse_winget_table(output):
    """Parse the fixed-width table winget prints for list/search/upgrade."""
    lines = output.splitlines()
    header_idx = None
    for i, line in enumerate(lines):
        if re.search(r"\bName\b", line) and re.search(r"\bId\b", line):
            header_idx = i
            break
    if header_idx is None:
        return []

    header = lines[header_idx]
    col_names = ["Name", "Id", "Version", "Available", "Source"]
    positions = []
    for name in col_names:
        m = re.search(r"\b" + name + r"\b", header)
        if m:
            positions.append((name, m.start()))
    positions.sort(key=lambda p: p[1])
    if not positions:
        return []

    rows = []
    for line in lines[header_idx + 1 :]:
        if not line.strip():
            break
        if set(line.strip()) <= {"-"}:
            continue
        row = {}
        for idx, (name, start) in enumerate(positions):
            end = positions[idx + 1][1] if idx + 1 < len(positions) else len(line)
            row[name] = line[start:end].strip()
        if row.get("Name") and row.get("Id"):
            rows.append(row)
    return rows


def fetch_installed():
    ok, out = run_winget(["list", "--accept-source-agreements"], timeout=60)
    return parse_winget_table(out) if ok else []


def fetch_updates():
    ok, out = run_winget(
        ["upgrade", "--accept-source-agreements", "--include-unknown"], timeout=60
    )
    return parse_winget_table(out) if ok else []


def search_packages(query):
    ok, out = run_winget(["search", query, "--accept-source-agreements"], timeout=45)
    if not ok:
        return None
    return parse_winget_table(out)


# ---------------------------------------------------------------------------
# state
# ---------------------------------------------------------------------------

state = {
    "screen": "root",  # root | installed | updates | update_log
    "installed": None,  # cached list or None
    "updates": None,  # cached list or None
    "installed_loading": False,
    "updates_loading": False,
    "latest_rev": 0,
    "search_gen": 0,
    "update_running": False,
    "update_total": 0,
    "update_completed": 0,
    "update_current": "",
    "update_lines": [],
    "update_run_id": 0,
}
state_lock = threading.Lock()


def invalidate_cache():
    with state_lock:
        state["installed"] = None
        state["updates"] = None


# ---------------------------------------------------------------------------
# rendering
# ---------------------------------------------------------------------------


def confirm(title, message, label):
    return {"title": title, "message": message, "confirmLabel": label}


def render_root(rev, text):
    text = (text or "").strip()
    if text:
        render_search(rev, text)
    else:
        render_dashboard(rev)


def render_dashboard(rev):
    with state_lock:
        installed = state["installed"]
        updates = state["updates"]
        loading_installed = state["installed_loading"]
        loading_updates = state["updates_loading"]

    installed_count = len(installed) if installed is not None else None
    updates_count = len(updates) if updates is not None else None

    stats_items = [
        {
            "id": "stat-installed",
            "title": "Installed apps",
            "subtitle": "via winget"
            if installed_count is None
            else f"{installed_count} package(s)",
            "icon": "app",
            "accessories": [
                {"text": "…" if installed_count is None else str(installed_count)}
            ],
            "actions": [
                {"id": "default", "title": "View installed apps", "icon": "list"}
            ],
        },
        {
            "id": "stat-updates",
            "title": "Updates available",
            "subtitle": "checking…"
            if updates_count is None
            else (
                "Everything is up to date" if updates_count == 0 else "Ready to install"
            ),
            "icon": "refresh",
            "accessories": [
                {
                    "text": "…" if updates_count is None else str(updates_count),
                    "color": None if updates_count in (None, 0) else "#F59E0B",
                }
            ],
            "actions": [{"id": "default", "title": "View updates", "icon": "list"}],
        },
    ]

    panel_stats = {
        "id": "stats",
        "title": "Overview",
        "height": 130,
        "view": "list",
        "loading": loading_installed or loading_updates,
        "loadingText": "Checking winget…",
        "items": stats_items,
    }

    update_items = []
    if updates:
        for pkg in updates[:6]:
            update_items.append(
                {
                    "id": f"upd:{pkg['Id']}",
                    "title": pkg["Name"],
                    "subtitle": f"{pkg['Id']} • {pkg.get('Version', '?')} → {pkg.get('Available', '?')}",
                    "icon": "download",
                    "actions": [
                        {
                            "id": "default",
                            "title": "Update",
                            "icon": "download",
                            "confirm": confirm(
                                f"Update {pkg['Name']}?",
                                f"Runs winget upgrade for {pkg['Id']}.",
                                "Update",
                            ),
                        }
                    ],
                }
            )

    panel_updates = {
        "id": "updates-panel",
        "title": "Available updates",
        "height": 260,
        "view": "list",
        "loading": loading_updates and updates is None,
        "loadingText": "Checking for updates…",
        "emptyText": "Everything is up to date" if updates is not None else "Checking…",
        "items": update_items,
        "actions": (
            [
                {
                    "id": "update-all",
                    "title": "Update all",
                    "icon": "download",
                    "confirm": confirm(
                        "Update all apps?",
                        f"Runs winget upgrade --all for {len(updates)} package(s).",
                        "Update all",
                    ),
                }
            ]
            if updates
            else []
        ),
    }

    quick_tiles = [
        {
            "id": "qa:search",
            "title": "Search apps",
            "subtitle": "Type a name above",
            "icon": "search",
            "tileColor": "#1E427B",
        },
        {
            "id": "qa:installed",
            "title": "Installed",
            "subtitle": "Browse & uninstall",
            "icon": "list",
            "tileColor": "#1E427B",
        },
        {
            "id": "qa:updates",
            "title": "Updates",
            "subtitle": "Review & apply",
            "icon": "refresh",
            "tileColor": "#1E427B",
        },
        {
            "id": "qa:refresh",
            "title": "Refresh",
            "subtitle": "Re-scan packages",
            "icon": "sync",
            "tileColor": "#1E427B",
        },
    ]
    panel_quick = {
        "id": "quick",
        "title": "Quick actions",
        "height": 150,
        "view": "grid",
        "grid": {"columns": 6, "aspectRatio": 1.0},
        "items": quick_tiles,
    }

    frame = {
        "type": "render",
        "rev": rev,
        "view": "dashboard",
        "placeholder": "Type an app name to search winget…",
        "dashboard": {
            "layout": "stack",
            "panels": [panel_stats, panel_updates, panel_quick],
        },
    }
    if not WINGET:
        frame = {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "detail": {
                "markdown": "# winget not found\n\nThe `winget` command wasn't found on PATH. "
                "Install App Installer from the Microsoft Store, then reopen this plugin."
            },
        }
    send(frame)


def render_search(rev, query):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "loading": True,
            "loadingText": f'Searching winget for "{query}"…',
            "placeholder": "Type an app name to search winget…",
            "items": [],
        }
    )

    def work():
        results = search_packages(query)
        with state_lock:
            if rev < state["latest_rev"]:
                return  # a newer query has already superseded this one
        if results is None:
            send(
                {
                    "type": "render",
                    "rev": rev,
                    "view": "detail",
                    "detail": {
                        "markdown": f"# Search failed\n\nCould not search winget for `{query}`."
                    },
                }
            )
            return
        items = []
        for pkg in results[:40]:
            items.append(
                {
                    "id": f"pkg:{pkg['Id']}",
                    "title": pkg["Name"],
                    "subtitle": f"{pkg['Id']} • {pkg.get('Version', '')} • {pkg.get('Source', '')}",
                    "icon": "download",
                    "actions": [
                        {
                            "id": "default",
                            "title": "Install",
                            "icon": "download",
                            "confirm": confirm(
                                f"Install {pkg['Name']}?",
                                f"Runs winget install for {pkg['Id']}.",
                                "Install",
                            ),
                        }
                    ],
                }
            )
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "list",
                "placeholder": "Type an app name to search winget…",
                "emptyText": f'No results for "{query}"',
                "items": items,
            }
        )

    threading.Thread(target=work, daemon=True).start()


def render_installed(rev, filter_text=""):
    with state_lock:
        installed = state["installed"]
        loading = state["installed_loading"]

    if installed is None:
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "list",
                "canGoBack": True,
                "placeholder": "Filter installed apps…",
                "loading": True,
                "loadingText": "Reading installed apps…",
                "items": [],
            }
        )
        if not loading:
            start_fetch_installed()
        return

    ft = filter_text.strip().lower()
    with state_lock:
        update_ids = {u["Id"] for u in (state["updates"] or [])}

    items = []
    for pkg in installed:
        if ft and ft not in pkg["Name"].lower() and ft not in pkg["Id"].lower():
            continue
        has_update = pkg["Id"] in update_ids
        actions = [
            {
                "id": "uninstall" if has_update else "default",
                "title": "Uninstall",
                "icon": "trash",
                "destructive": True,
                "confirm": confirm(
                    f"Uninstall {pkg['Name']}?",
                    f"Runs winget uninstall for {pkg['Id']}. This cannot be undone.",
                    "Uninstall",
                ),
            }
        ]
        if has_update:
            actions.insert(
                0,
                {
                    "id": "default",
                    "title": "Update",
                    "icon": "download",
                    "confirm": confirm(
                        f"Update {pkg['Name']}?",
                        f"Runs winget upgrade for {pkg['Id']}.",
                        "Update",
                    ),
                },
            )
        items.append(
            {
                "id": f"inst:{pkg['Id']}",
                "title": pkg["Name"],
                "subtitle": f"{pkg['Id']} • {pkg.get('Version', '')}",
                "icon": "app",
                "accessories": [{"text": "Update available", "color": "#F59E0B"}]
                if has_update
                else [],
                "actions": actions,
            }
        )

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "placeholder": "Filter installed apps…",
            "emptyText": "No matching apps" if ft else "No apps found",
            "items": items,
            "actions": [{"id": "refresh", "title": "Refresh list", "icon": "sync"}],
        }
    )


def render_updates(rev, filter_text=""):
    with state_lock:
        updates = state["updates"]
        loading = state["updates_loading"]

    if updates is None:
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "list",
                "canGoBack": True,
                "placeholder": "Filter updates…",
                "loading": True,
                "loadingText": "Checking for updates…",
                "items": [],
            }
        )
        if not loading:
            start_fetch_updates()
        return

    ft = filter_text.strip().lower()
    items = []
    for pkg in updates:
        if ft and ft not in pkg["Name"].lower() and ft not in pkg["Id"].lower():
            continue
        items.append(
            {
                "id": f"upd:{pkg['Id']}",
                "title": pkg["Name"],
                "subtitle": f"{pkg['Id']} • {pkg.get('Version', '?')} → {pkg.get('Available', '?')}",
                "icon": "download",
                "actions": [
                    {
                        "id": "default",
                        "title": "Update",
                        "icon": "download",
                        "confirm": confirm(
                            f"Update {pkg['Name']}?",
                            f"Runs winget upgrade for {pkg['Id']}.",
                            "Update",
                        ),
                    }
                ],
            }
        )

    frame_actions = []
    if updates:
        frame_actions.append(
            {
                "id": "update-all",
                "title": "Update all",
                "icon": "download",
                "confirm": confirm(
                    "Update all apps?",
                    f"Runs winget upgrade --all for {len(updates)} package(s).",
                    "Update all",
                ),
            }
        )
    frame_actions.append({"id": "refresh", "title": "Refresh list", "icon": "sync"})

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "placeholder": "Filter updates…",
            "empty": {
                "icon": "check",
                "title": "Up to date",
                "hint": "No pending updates",
            }
            if not ft
            else None,
            "emptyText": "No matching updates" if ft else "Everything is up to date",
            "items": items,
            "selection": {"enabled": True},
            "actions": frame_actions,
            "floatingAction": {
                "id": "update-selected",
                "title": "Update selected",
                "icon": "download",
                "confirm": confirm(
                    "Update selected apps?",
                    "Updates every app selected in this list.",
                    "Update selected",
                ),
            }
            if updates
            else None,
        }
    )


def render_update_log(rev=0):
    with state_lock:
        running = state["update_running"]
        total = state["update_total"]
        completed = state["update_completed"]
        current = state["update_current"]
        lines = list(state["update_lines"])

    if running:
        position = min(completed + 1, total)
        title = f"Updating {position} of {total}"
        detail = current
        progress = completed / total if total else 0
    else:
        title = "Update run complete"
        detail = f"Processed {completed} app(s)"
        progress = 1

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "log",
            "canGoBack": True,
            "placeholder": "Updates are shown below…",
            "operation": {
                "id": "winget-update-batch",
                "title": title,
                "detail": detail,
                "progress": progress,
            },
            "log": {"follow": True, "wrap": True, "lines": lines},
            "floatingAction": {
                "id": "back-to-updates",
                "title": "Back to updates",
                "icon": "list",
            }
            if not running
            else None,
        }
    )


def render_current(rev, text):
    screen = state["screen"]
    if screen == "installed":
        render_installed(rev, text)
    elif screen == "updates":
        render_updates(rev, text)
    elif screen == "update_log":
        render_update_log(rev)
    else:
        render_root(rev, text)


# ---------------------------------------------------------------------------
# background fetchers
# ---------------------------------------------------------------------------


def start_fetch_installed():
    with state_lock:
        if state["installed_loading"]:
            return
        state["installed_loading"] = True

    def work():
        result = fetch_installed()
        with state_lock:
            state["installed"] = result
            state["installed_loading"] = False
            screen = state["screen"]
        if screen == "installed":
            render_installed(0)
        elif screen == "root":
            render_dashboard(0)

    threading.Thread(target=work, daemon=True).start()


def start_fetch_updates():
    with state_lock:
        if state["updates_loading"]:
            return
        state["updates_loading"] = True

    def work():
        result = fetch_updates()
        with state_lock:
            state["updates"] = result
            state["updates_loading"] = False
            screen = state["screen"]
        if screen == "updates":
            render_updates(0)
        elif screen == "root":
            render_dashboard(0)

    threading.Thread(target=work, daemon=True).start()


def refresh_all():
    invalidate_cache()
    start_fetch_installed()
    start_fetch_updates()


# ---------------------------------------------------------------------------
# mutating operations (install / uninstall / update)
# ---------------------------------------------------------------------------


def run_change(kind, args, name):
    verb = {"install": "Installing", "uninstall": "Uninstalling", "update": "Updating"}[
        kind
    ]
    past = {"install": "Installed", "uninstall": "Uninstalled", "update": "Updated"}[
        kind
    ]

    send(
        {
            "type": "command",
            "command": "toast",
            "text": f"{verb} {name}…",
            "style": "progress",
        }
    )

    def work():
        ok, out = run_winget(args, timeout=300)
        if ok:
            send(
                {
                    "type": "command",
                    "command": "toast",
                    "text": f"{past} {name}",
                    "style": "success",
                }
            )
            send(
                {
                    "type": "command",
                    "command": "notify",
                    "title": "WinGet",
                    "text": f"{past} {name}",
                }
            )
        else:
            snippet = out.strip().splitlines()[-1] if out.strip() else "Unknown error"
            send(
                {
                    "type": "command",
                    "command": "toast",
                    "text": f"Failed: {name}",
                    "style": "error",
                }
            )
            send(
                {
                    "type": "command",
                    "command": "notify",
                    "title": "WinGet",
                    "text": f"{name} failed: {snippet}",
                }
            )
        invalidate_cache()
        with state_lock:
            screen = state["screen"]
        if screen == "root":
            render_dashboard(0)
            start_fetch_installed()
            start_fetch_updates()
        elif screen == "installed":
            start_fetch_installed()
            render_installed(0)
        elif screen == "updates":
            start_fetch_updates()
            render_updates(0)

    threading.Thread(target=work, daemon=True).start()


def do_install(pkg_id, name):
    run_change(
        "install",
        [
            "install",
            "--id",
            pkg_id,
            "-e",
            "--silent",
            "--accept-package-agreements",
            "--accept-source-agreements",
        ],
        name,
    )


def do_uninstall(pkg_id, name):
    run_change(
        "uninstall",
        ["uninstall", "--id", pkg_id, "-e", "--silent", "--accept-source-agreements"],
        name,
    )


def do_update(pkg_id, name):
    run_change(
        "update",
        [
            "upgrade",
            "--id",
            pkg_id,
            "-e",
            "--silent",
            "--accept-package-agreements",
            "--accept-source-agreements",
        ],
        name,
    )


def _update_log_line(level, text, source="winget"):
    with state_lock:
        run_id = state["update_run_id"]
        line_id = len(state["update_lines"]) + 1
        state["update_lines"].append(
            {
                "id": f"{run_id}:{line_id}",
                "timestamp": time.strftime("%H:%M:%S"),
                "level": level,
                "source": source,
                "text": text,
            }
        )
        if len(state["update_lines"]) > 500:
            state["update_lines"] = state["update_lines"][-500:]
        show_log = state["screen"] == "update_log"
    if show_log:
        render_update_log(0)


def do_update_selected(selected_ids):
    requested_ids = {
        value.split(":", 1)[1] if ":" in value else value
        for value in selected_ids
        if isinstance(value, str) and value
    }
    with state_lock:
        if state["update_running"]:
            already_running = True
            packages = []
        else:
            already_running = False
            packages = [
                pkg
                for pkg in (state["updates"] or [])
                if pkg["Id"] in requested_ids
            ]

    if already_running:
        send(
            {
                "type": "command",
                "command": "toast",
                "text": "An update run is already in progress",
                "style": "info",
            }
        )
        return
    if not packages:
        send(
            {
                "type": "command",
                "command": "toast",
                "text": "Select at least one app to update",
                "style": "info",
            }
        )
        return

    with state_lock:
        state["screen"] = "update_log"
        state["update_running"] = True
        state["update_total"] = len(packages)
        state["update_completed"] = 0
        state["update_current"] = "Preparing updates…"
        state["update_lines"] = []
        state["update_run_id"] += 1

    send({"type": "command", "command": "setQuery", "text": " "})
    _update_log_line("info", f"Queued {len(packages)} app(s) for update")

    def work():
        succeeded = 0
        failed = 0
        for index, pkg in enumerate(packages, start=1):
            name = pkg["Name"]
            pkg_id = pkg["Id"]
            with state_lock:
                state["update_current"] = name
            _update_log_line(
                "info",
                f"[{index}/{len(packages)}] Updating {name} ({pkg_id})",
                source=name,
            )
            ok, out = run_winget(
                [
                    "upgrade",
                    "--id",
                    pkg_id,
                    "-e",
                    "--silent",
                    "--accept-package-agreements",
                    "--accept-source-agreements",
                ],
                timeout=300,
            )
            if ok:
                succeeded += 1
                _update_log_line("success", f"Updated {name}", source=name)
            else:
                failed += 1
                output_lines = [line.strip() for line in out.splitlines() if line.strip()]
                reason = output_lines[-1] if output_lines else "Unknown winget error"
                _update_log_line("error", f"Failed to update {name}: {reason}", source=name)
            with state_lock:
                state["update_completed"] = index
            render_update_log(0)

        with state_lock:
            state["update_running"] = False
            state["update_current"] = ""
        level = "success" if failed == 0 else "warn"
        _update_log_line(level, f"Finished: {succeeded} succeeded, {failed} failed")
        send(
            {
                "type": "command",
                "command": "toast",
                "text": "Updates complete" if failed == 0 else "Some updates failed",
                "style": "success" if failed == 0 else "error",
            }
        )
        send(
            {
                "type": "command",
                "command": "notify",
                "title": "WinGet updates complete",
                "text": f"{succeeded} succeeded, {failed} failed",
            }
        )
        invalidate_cache()
        start_fetch_installed()
        start_fetch_updates()

    threading.Thread(target=work, daemon=True).start()


def do_update_all():
    with state_lock:
        ids = [f"upd:{pkg['Id']}" for pkg in (state["updates"] or [])]
    do_update_selected(ids)


# ---------------------------------------------------------------------------
# name lookups for confirm() dialogs / action handling
# ---------------------------------------------------------------------------


def find_pkg(pkg_id, pools):
    for pool in pools:
        if not pool:
            continue
        for p in pool:
            if p["Id"] == pkg_id:
                return p
    return None


# ---------------------------------------------------------------------------
# action handling
# ---------------------------------------------------------------------------


def handle_action(item_id, action, selected_ids=None):
    selected_ids = selected_ids or []
    screen = state["screen"]

    # navigation from the dashboard
    if screen == "root":
        if item_id in ("stat-installed", "qa:installed"):
            state["screen"] = "installed"
            send({"type": "command", "command": "setQuery", "text": " "})
            render_installed(0)
            return
        if item_id in ("stat-updates", "qa:updates"):
            state["screen"] = "updates"
            send({"type": "command", "command": "setQuery", "text": " "})
            render_updates(0)
            return
        if item_id == "qa:search":
            send({"type": "command", "command": "setQuery", "text": " "})
            send(
                {
                    "type": "command",
                    "command": "toast",
                    "text": "Start typing an app name to search",
                    "style": "info",
                }
            )
            return
        if item_id == "qa:refresh":
            refresh_all()
            render_dashboard(0)
            return
        if item_id == "" and action == "update-all":
            do_update_all()
            return
        if item_id.startswith("upd:") and action == "default":
            do_update_selected([item_id])
            return
        if item_id.startswith("pkg:") and action == "default":
            pkg_id = item_id.split(":", 1)[1]
            do_install(pkg_id, pkg_id)
            return

    elif screen == "installed":
        if item_id == "" and action == "refresh":
            invalidate_cache()
            start_fetch_installed()
            start_fetch_updates()
            render_installed(0)
            return
        if item_id.startswith("inst:"):
            pkg_id = item_id.split(":", 1)[1]
            with state_lock:
                pkg = find_pkg(pkg_id, [state["installed"]])
                has_update = any(u["Id"] == pkg_id for u in (state["updates"] or []))
            name = pkg["Name"] if pkg else pkg_id
            if action == "uninstall" or (action == "default" and not has_update):
                do_uninstall(pkg_id, name)
                return
            if action in ("default", "update"):
                do_update_selected([f"upd:{pkg_id}"])
                return

    elif screen == "updates":
        if item_id == "" and action == "refresh":
            invalidate_cache()
            start_fetch_updates()
            start_fetch_installed()
            render_updates(0)
            return
        if item_id == "" and action == "update-all":
            do_update_all()
            return
        if item_id == "" and action == "update-selected":
            do_update_selected(selected_ids)
            return
        if item_id.startswith("upd:") and action in ("default", "update"):
            do_update_selected([item_id])
            return

    elif screen == "update_log":
        if item_id == "" and action == "back-to-updates":
            show_updates()
            return


def show_updates():
    state["screen"] = "updates"
    send({"type": "command", "command": "setQuery", "text": " "})
    with state_lock:
        updates = state["updates"]
    if updates is None:
        start_fetch_updates()
    render_updates(0)


def handle_back():
    if state["screen"] == "update_log":
        show_updates()
        return
    state["screen"] = "root"
    send({"type": "command", "command": "setQuery", "text": " "})
    render_dashboard(0)


# ---------------------------------------------------------------------------
# main loop
# ---------------------------------------------------------------------------


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
            rev = msg.get("rev", 0)
            text = msg.get("text", msg.get("query", ""))
            with state_lock:
                state["latest_rev"] = max(state["latest_rev"], rev)
            render_current(rev, text)
            if t == "init":
                # warm the cache in the background so the dashboard fills in fast
                start_fetch_installed()
                start_fetch_updates()

        elif t == "action":
            handle_action(
                msg.get("id", ""),
                msg.get("action", "default"),
                msg.get("ids", []),
            )

        elif t == "back":
            handle_back()

        # select / toggle / other message types: no-op for this plugin

    sys.exit(0)


if __name__ == "__main__":
    main()
