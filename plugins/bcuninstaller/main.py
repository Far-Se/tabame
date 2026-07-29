#!/usr/bin/env python3
"""
BC Uninstaller — Tabame launcher plugin.

Ported from the "List Applications" BCUninstaller extension for Raycast.
Exports the installed-application list from BC Uninstaller's BCU-console.exe,
lets the user search/filter/queue apps, and runs a batch (quiet where
possible) uninstall through the same elevated BCU-console.exe.

Protocol: newline-delimited JSON over stdin/stdout. See the Tabame plugin
authoring spec for the full message/frame reference.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import xml.etree.ElementTree as ET

# ---------------------------------------------------------------------------
# stdout / stderr helpers
# ---------------------------------------------------------------------------

_OUT_LOCK = threading.Lock()


def send(frame):
    line = json.dumps(frame, ensure_ascii=False)
    with _OUT_LOCK:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()


def log(*parts):
    print(*parts, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# constants
# ---------------------------------------------------------------------------

VISIBILITY_MODES = [
    ("default", "Default Safe View", "Hides system, protected and update entries"),
    ("include-updates", "Include Updates", "Also shows Windows / app updates"),
    ("include-system", "Include System Components", "Also shows system components"),
    ("include-protected", "Include Protected Entries", "Also shows protected entries"),
    ("all", "Show All", "No filtering"),
]
VISIBILITY_LABELS = {key: label for key, label, _hint in VISIBILITY_MODES}

CTRL_ENTER = "ctrl+enter"
CTRL_R = "ctrl+r"
CTRL_F = "ctrl+f"
CTRL_D = "ctrl+d"
CTRL_S = "ctrl+s"
CTRL_SHIFT_DELETE = "ctrl+shift+delete"

PERSISTENT_CACHE_SECONDS = 15 * 60

QUIET_COLOR = "#22C55E"
NON_QUIET_COLOR = "#F97316"
SYSTEM_COLOR = "#8B8B8B"
PROTECTED_COLOR = "#EF4444"
UPDATE_COLOR = "#EAB308"
QUEUED_COLOR = "#3B82F6"

# ---------------------------------------------------------------------------
# shared state
# ---------------------------------------------------------------------------

LOCK = threading.RLock()
STATE = {
    "screen": "root",           # root | visibility | settings
    "query": "",
    "apps": [],                 # list[dict]
    "queue": {},                # id -> queue item dict
    "visibility": "default",
    "show_preview": False,
    "bcu_path": "",
    "auto_remove_junk": False,
    "loading": True,
    "error": None,
    "refreshing": False,
    "apps_loaded_at": 0,
    "settings_loaded": False,
    "apps_cache_loaded": False,
}


# ---------------------------------------------------------------------------
# BCU-console.exe plumbing
# ---------------------------------------------------------------------------

def resolve_bcu_console_path(preference_path):
    trimmed = (preference_path or "").strip()
    if not trimmed:
        raise RuntimeError(
            "Set the BC Uninstaller path in Settings (BCU-console.exe, "
            "BCUninstaller.exe, or the install folder)."
        )

    normalized = os.path.abspath(trimmed)
    lower = normalized.lower()

    if lower.endswith("bcu-console.exe"):
        candidates = [normalized]
    elif lower.endswith("bcuninstaller.exe"):
        candidates = [os.path.join(os.path.dirname(normalized), "win-x64", "BCU-console.exe")]
    else:
        candidates = [
            os.path.join(normalized, "BCU-console.exe"),
            os.path.join(normalized, "win-x64", "BCU-console.exe"),
        ]

    for candidate in candidates:
        if os.path.isfile(candidate):
            return candidate

    raise RuntimeError(
        "BCU-console.exe was not found. Checked: %s. Update the path in Settings."
        % ", ".join(candidates)
    )


def _ps_literal(value):
    return "'" + value.replace("'", "''") + "'"


def _parse_exit_code(stdout):
    match = re.search(r"__EXITCODE__=(\d+)", stdout)
    return int(match.group(1)) if match else -1


def run_bcu_command(executable_path, args):
    argument_list = "@(" + ", ".join(_ps_literal(a) for a in args) + ")"
    command = "; ".join(
        [
            "$ErrorActionPreference = 'Stop'",
            "$process = Start-Process -FilePath %s -ArgumentList %s -Verb RunAs -Wait -PassThru"
            % (_ps_literal(executable_path), argument_list),
            'Write-Output ("__EXITCODE__=" + $process.ExitCode)',
        ]
    )

    try:
        completed = subprocess.run(
            ["powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", command],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except OSError as exc:
        raise RuntimeError(f"Failed to launch BC Uninstaller: {exc}") from exc

    stdout = completed.stdout or ""
    stderr = completed.stderr or ""

    if completed.returncode != 0:
        combined = (stdout + "\n" + stderr).strip()
        hint = ""
        if re.search(r"administrator|elevat|access denied|permission", combined, re.I):
            hint = " BC Uninstaller may need elevated permissions."
        raise RuntimeError(
            f"BC Uninstaller exited with code {completed.returncode}.{hint}"
            + (f" {combined}" if combined else "")
        )

    exit_code = _parse_exit_code(stdout)
    if exit_code != 0:
        extra = stderr.strip()
        raise RuntimeError(
            f"BC Uninstaller exited with code {exit_code}." + (f" {extra}" if extra else "")
        )

    return {"stdout": stdout, "stderr": stderr, "exit_code": exit_code}


def wait_for_file(file_path, timeout_seconds):
    started = time.time()
    while time.time() - started < timeout_seconds:
        try:
            if os.path.getsize(file_path) > 0:
                return
        except OSError:
            pass
        time.sleep(0.2)
    raise RuntimeError(
        f'BC Uninstaller finished without writing the export file at "{file_path}". '
        "If you dismissed the Windows elevation prompt, try again and approve it."
    )


# ---------------------------------------------------------------------------
# export XML parsing
# ---------------------------------------------------------------------------

def _text(entry, tag):
    value = entry.findtext(tag)
    return value.strip() if isinstance(value, str) else ""


def _flag(entry, tag):
    return _text(entry, tag).lower() == "true"


def create_match_target(display_name, publisher, version, rating_id, registry_key_name):
    if rating_id:
        return {"type": "RatingId", "value": rating_id}
    if registry_key_name:
        return {"type": "RegistryKeyName", "value": registry_key_name}
    return {"type": "Fallback", "display_name": display_name, "publisher": publisher, "version": version}


def create_stable_id(match_target, bundle_provider_key, install_location, uninstall_kind,
                      about_url, display_name, publisher, version):
    if match_target["type"] == "RatingId":
        base_id = f"rating:{match_target['value']}"
    elif match_target["type"] == "RegistryKeyName":
        base_id = f"registry:{match_target['value']}"
    else:
        base_id = (
            f"fallback:{match_target['display_name']}::"
            f"{match_target['publisher']}::{match_target['version']}"
        )

    qualifiers = [bundle_provider_key, install_location, uninstall_kind, about_url,
                  display_name, publisher, version]
    qualifiers = [q.strip() for q in qualifiers if q and q.strip()]
    return "::".join([base_id, *qualifiers])


def format_match_target(match_target):
    if match_target["type"] == "RatingId":
        return f"RatingId={match_target['value']}"
    if match_target["type"] == "RegistryKeyName":
        return f"RegistryKeyName={match_target['value']}"
    return (
        f"DisplayName={match_target['display_name']}; "
        f"Publisher={match_target['publisher']}; DisplayVersion={match_target['version']}"
    )


def normalize_application_entry(entry, index):
    display_name = _text(entry, "DisplayName") or _text(entry, "RawDisplayName") or f"Unnamed Application {index + 1}"
    publisher = _text(entry, "Publisher")
    version = _text(entry, "DisplayVersion")
    uninstall_kind = _text(entry, "UninstallerKind")
    rating_id = _text(entry, "RatingId")
    registry_key_name = _text(entry, "RegistryKeyName")
    bundle_provider_key = _text(entry, "BundleProviderKey")
    install_location = _text(entry, "InstallLocation")
    about_url = _text(entry, "AboutUrl")

    match_target = create_match_target(display_name, publisher, version, rating_id, registry_key_name)

    return {
        "id": create_stable_id(match_target, bundle_provider_key, install_location, uninstall_kind,
                                about_url, display_name, publisher, version),
        "display_name": display_name,
        "publisher": publisher,
        "version": version,
        "uninstall_kind": uninstall_kind,
        "quiet_uninstall_possible": _flag(entry, "QuietUninstallPossible"),
        "uninstall_possible": _flag(entry, "UninstallPossible"),
        "is_protected": _flag(entry, "IsProtected"),
        "system_component": _flag(entry, "SystemComponent"),
        "is_update": _flag(entry, "IsUpdate"),
        "about_url": about_url,
        "rating_id": rating_id,
        "registry_key_name": registry_key_name,
        "bundle_provider_key": bundle_provider_key,
        "install_location": install_location,
        "match_target": match_target,
    }


def parse_exported_applications(xml_text):
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError as exc:
        raise RuntimeError(f"Failed to parse BC Uninstaller export: {exc}") from exc

    entries = root.findall(".//ApplicationUninstallerEntry")
    seen_ids = {}
    apps = []
    for index, entry in enumerate(entries):
        app = normalize_application_entry(entry, index)
        seen_count = seen_ids.get(app["id"], 0)
        seen_ids[app["id"]] = seen_count + 1
        if seen_count:
            app["id"] = f"{app['id']}::duplicate:{seen_count + 1}"
        apps.append(app)
    return apps


def export_applications(bcu_path_pref):
    executable_path = resolve_bcu_console_path(bcu_path_pref)
    tmp_dir = tempfile.mkdtemp(prefix="tabame-bcu-export-")
    export_path = os.path.join(tmp_dir, "applications.xml")
    try:
        run_bcu_command(executable_path, ["export", export_path, "/Q", "/U"])
        wait_for_file(export_path, 5.0)
        with open(export_path, "r", encoding="utf-8", errors="replace") as handle:
            xml_text = handle.read()
        apps = parse_exported_applications(xml_text)
        if not apps:
            raise RuntimeError("BC Uninstaller export completed but no applications were found.")
        return apps
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


# ---------------------------------------------------------------------------
# uninstall list (.bcul) XML
# ---------------------------------------------------------------------------

def escape_xml(value):
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&apos;")
    )


def create_condition_xml(value, target_property_id):
    return "\r\n".join(
        [
            "        <FilterCondition>",
            "          <InvertResults>false</InvertResults>",
            "          <ComparisonMethod>Equals</ComparisonMethod>",
            f"          <FilterText>{escape_xml(value)}</FilterText>",
            f"          <TargetPropertyId>{escape_xml(target_property_id)}</TargetPropertyId>",
            "          <Enabled>true</Enabled>",
            "        </FilterCondition>",
        ]
    )


def build_filter_conditions_xml(match_target):
    if match_target["type"] == "RatingId":
        return create_condition_xml(match_target["value"], "RatingId")
    if match_target["type"] == "RegistryKeyName":
        return create_condition_xml(match_target["value"], "RegistryKeyName")
    return "\r\n".join(
        [
            create_condition_xml(match_target["display_name"], "DisplayName"),
            create_condition_xml(match_target["publisher"], "Publisher"),
            create_condition_xml(match_target["version"], "DisplayVersion"),
        ]
    )


def build_uninstall_list_xml(items):
    filters = []
    for item in items:
        name = escape_xml(item["display_name"])
        conditions = build_filter_conditions_xml(item["match_target"])
        filters.append(
            "\r\n".join(
                [
                    "    <Filter>",
                    f"      <Name>{name}</Name>",
                    "      <Exclude>false</Exclude>",
                    "      <ComparisonEntries>",
                    conditions,
                    "      </ComparisonEntries>",
                    "      <Enabled>true</Enabled>",
                    "    </Filter>",
                ]
            )
        )
    return "\r\n".join(
        [
            '<?xml version="1.0" encoding="utf-16"?>',
            "<UninstallList>",
            "  <Filters>",
            "\r\n".join(filters),
            "  </Filters>",
            "  <Enabled>true</Enabled>",
            "</UninstallList>",
            "",
        ]
    )


def uninstall_queued_apps_with_bcu(bcu_path_pref, items, auto_remove_junk):
    executable_path = resolve_bcu_console_path(bcu_path_pref)
    tmp_dir = tempfile.mkdtemp(prefix="tabame-bcu-uninstall-")
    list_path = os.path.join(tmp_dir, "queued-apps.bcul")
    xml_text = build_uninstall_list_xml(items)
    args = ["uninstall", list_path, "/Q", "/U"]
    if auto_remove_junk:
        args.append("/J=VeryGood")

    try:
        with open(list_path, "w", encoding="utf-16-le") as handle:
            handle.write(xml_text)
        result = run_bcu_command(executable_path, args)
        quiet_count = sum(1 for item in items if item["quiet_uninstall_possible"])
        return {
            "exit_code": result["exit_code"],
            "stdout": result["stdout"],
            "stderr": result["stderr"],
            "quiet_count": quiet_count,
            "non_quiet_count": len(items) - quiet_count,
        }
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


# ---------------------------------------------------------------------------
# filtering / presentation helpers
# ---------------------------------------------------------------------------

def visible_apps(apps, visibility):
    if visibility == "all":
        return list(apps)
    result = []
    for app in apps:
        if app["system_component"] and visibility != "include-system":
            continue
        if app["is_protected"] and visibility != "include-protected":
            continue
        if app["is_update"] and visibility != "include-updates":
            continue
        result.append(app)
    return result


def matches_query(app, query):
    if not query:
        return True
    needle = query.lower()
    haystacks = [
        app["display_name"], app["publisher"], app["version"], app["uninstall_kind"],
        app["rating_id"], app["registry_key_name"], app["bundle_provider_key"],
    ]
    return any(needle in (h or "").lower() for h in haystacks)


def build_icon(app, is_queued):
    if is_queued:
        return "check"
    if app["is_protected"]:
        return "lock"
    if app["system_component"]:
        return "gear"
    if app["is_update"]:
        return "refresh"
    return "bolt" if app["quiet_uninstall_possible"] else "app"


def build_accessories(app, is_queued):
    chips = []
    if app["version"]:
        chips.append({"text": app["version"]})
    if is_queued:
        chips.append({"text": "queued", "color": QUEUED_COLOR})
    chips.append(
        {
            "text": "quiet" if app["quiet_uninstall_possible"] else "non-quiet",
            "color": QUIET_COLOR if app["quiet_uninstall_possible"] else NON_QUIET_COLOR,
        }
    )
    if app["system_component"]:
        chips.append({"text": "system", "color": SYSTEM_COLOR})
    if app["is_protected"]:
        chips.append({"text": "protected", "color": PROTECTED_COLOR})
    if app["is_update"]:
        chips.append({"text": "update", "color": UPDATE_COLOR})
    return chips


def build_preview_metadata(app, is_queued):
    rows = []
    if is_queued:
        rows.append({"label": "Queue", "text": "Queued", "color": QUEUED_COLOR, "icon": "check"})
    rows.append(
        {
            "label": "Uninstall",
            "text": "Quiet-capable" if app["quiet_uninstall_possible"] else "Non-quiet",
            "color": QUIET_COLOR if app["quiet_uninstall_possible"] else NON_QUIET_COLOR,
        }
    )
    if app["system_component"]:
        rows.append({"label": "Flag", "text": "System component", "color": SYSTEM_COLOR})
    if app["is_protected"]:
        rows.append({"label": "Flag", "text": "Protected", "color": PROTECTED_COLOR})
    if app["is_update"]:
        rows.append({"label": "Flag", "text": "Update", "color": UPDATE_COLOR})
    rows.append({"separator": True})
    rows.append({"label": "Publisher", "text": app["publisher"] or "Unknown"})
    rows.append({"label": "Version", "text": app["version"] or "Unknown"})
    rows.append({"label": "Uninstall Kind", "text": app["uninstall_kind"] or "Unknown"})
    rows.append({"label": "Install Location", "text": app["install_location"] or "Unknown"})
    rows.append({"separator": True})
    rows.append({"label": "Rating ID", "text": app["rating_id"] or "None"})
    rows.append({"label": "Registry Key", "text": app["registry_key_name"] or "None"})
    rows.append({"label": "Bundle Provider Key", "text": app["bundle_provider_key"] or "None"})
    rows.append({"label": "Match Target", "text": format_match_target(app["match_target"])})
    if app["about_url"]:
        rows.append({"label": "About URL", "text": app["about_url"], "url": app["about_url"]})
    return rows


def build_uninstall_confirm(queued_items, auto_remove_junk):
    quiet_count = sum(1 for item in queued_items if item["quiet_uninstall_possible"])
    non_quiet_count = len(queued_items) - quiet_count
    lines = [f"{quiet_count} quiet-capable", f"{non_quiet_count} non-quiet"]
    if auto_remove_junk:
        lines.append("BC Uninstaller will also clean high-confidence leftover registry entries and other uninstall junk.")
    else:
        lines.append("Auto-cleanup is off. Enable it in Settings to also remove leftover registry entries and other uninstall junk.")
    if non_quiet_count:
        lines.append("Non-quiet uninstallers may still require BC Uninstaller automation.")
    count = len(queued_items)
    return {
        "title": f"Uninstall {count} queued app{'' if count == 1 else 's'}?",
        "message": "\n".join(lines),
        "confirmLabel": "Uninstall",
    }


# ---------------------------------------------------------------------------
# frame builders
# ---------------------------------------------------------------------------

def build_frame_actions(queued_items, auto_remove_junk, visibility, show_preview):
    actions = []
    if queued_items:
        actions.append(
            {
                "id": "uninstall-queued",
                "title": f"Uninstall {len(queued_items)} Queued App{'' if len(queued_items) == 1 else 's'}",
                "icon": "trash",
                "shortcut": CTRL_ENTER,
                "destructive": True,
                "confirm": build_uninstall_confirm(queued_items, auto_remove_junk),
            }
        )
        actions.append({"id": "clear-queue", "title": "Clear Queue", "icon": "close", "shortcut": CTRL_SHIFT_DELETE})
    actions.append({"id": "refresh", "title": "Refresh Applications", "icon": "refresh", "shortcut": CTRL_R})
    actions.append(
        {
            "id": "open-visibility",
            "title": f"Visibility: {VISIBILITY_LABELS.get(visibility, visibility)}",
            "icon": "search",
            "shortcut": CTRL_F,
        }
    )
    actions.append(
        {
            "id": "toggle-preview",
            "title": "Hide Details Pane" if show_preview else "Show Details Pane",
            "icon": "grid",
            "shortcut": CTRL_D,
        }
    )
    actions.append({"id": "open-settings", "title": "Settings", "icon": "settings", "shortcut": CTRL_S})
    return actions


def build_root_frame(rev):
    with LOCK:
        apps = list(STATE["apps"])
        queue = dict(STATE["queue"])
        query = STATE["query"]
        visibility = STATE["visibility"]
        show_preview = STATE["show_preview"]
        loading = STATE["loading"]
        error = STATE["error"]
        bcu_path = STATE["bcu_path"]
        auto_remove_junk = STATE["auto_remove_junk"]

    filtered = [app for app in visible_apps(apps, visibility) if matches_query(app, query)]
    filtered.sort(key=lambda app: app["display_name"].lower())

    queued_items = list(queue.values())
    queue_count = len(queued_items)

    items = []
    if queue_count:
        quiet_count = sum(1 for item in queued_items if item["quiet_uninstall_possible"])
        non_quiet_count = queue_count - quiet_count
        items.append(
            {
                "id": "queue-summary",
                "title": f"{queue_count} queued app{'' if queue_count == 1 else 's'}",
                "subtitle": f"{quiet_count} quiet-capable, {non_quiet_count} non-quiet",
                "icon": "list",
                "section": "Queue",
                "actions": [
                    {
                        "id": "uninstall-queued",
                        "title": "Uninstall Queued Apps",
                        "icon": "trash",
                        "destructive": True,
                        "confirm": build_uninstall_confirm(queued_items, auto_remove_junk),
                    },
                    {"id": "clear-queue", "title": "Clear Queue", "icon": "close"},
                ],
                "preview": {
                    "markdown": "\n".join(f"- {item['display_name']}" for item in queued_items),
                    "metadata": [
                        {"label": "Queued Count", "text": str(queue_count)},
                        {"label": "Quiet-capable", "text": str(quiet_count)},
                        {"label": "Non-quiet", "text": str(non_quiet_count)},
                    ],
                },
            }
        )

    for app in filtered:
        is_queued = app["id"] in queue
        items.append(
            {
                "id": app["id"],
                "title": app["display_name"],
                "subtitle": app["publisher"] or app["version"] or "",
                "section": "Applications" if queue_count else "",
                "icon": build_icon(app, is_queued),
                "accessories": build_accessories(app, is_queued),
                "actions": [
                    {
                        "id": "default",
                        "title": "Remove from Queue" if is_queued else "Add to Queue",
                        "icon": "minus" if is_queued else "plus",
                    },
                    {"id": "copy-identifier", "title": "Copy BCU Identifier", "icon": "copy"},
                ],
                "preview": {
                    "markdown": f"## {app['display_name']}\n\n{app['publisher'] or 'Unknown publisher'}",
                    "metadata": build_preview_metadata(app, is_queued),
                },
            }
        )

    frame = {
        "type": "render",
        "rev": rev,
        "view": "list",
        "preview": {"enabled": show_preview},
        "placeholder": "Search installed software…",
        "canGoBack": False,
        "items": items,
        "actions": build_frame_actions(queued_items, auto_remove_junk, visibility, show_preview),
    }

    if loading:
        frame["loading"] = True
        frame["loadingText"] = "Loading installed applications…"
    elif error:
        frame["empty"] = {
            "icon": "warning",
            "title": "Could not load applications",
            "hint": error,
            "action": {"id": "refresh", "title": "Retry", "icon": "refresh"},
        }
    elif not bcu_path:
        frame["empty"] = {
            "icon": "settings",
            "title": "Set up BC Uninstaller",
            "hint": "Choose your BCU-console.exe, BCUninstaller.exe, or the install folder in Settings.",
            "action": {"id": "open-settings", "title": "Open Settings", "icon": "settings"},
        }
    elif not items:
        frame["emptyText"] = "No applications match the current filters"

    return frame


def build_visibility_frame(rev):
    with LOCK:
        current = STATE["visibility"]
    items = []
    for key, label, hint in VISIBILITY_MODES:
        is_current = key == current
        items.append(
            {
                "id": f"vis:{key}",
                "title": label,
                "subtitle": hint,
                "icon": "check" if is_current else "list",
                "accessories": [{"text": "current", "color": QUEUED_COLOR}] if is_current else [],
                "actions": [{"id": "default", "title": "Use This View", "icon": "check"}],
            }
        )
    return {
        "type": "render",
        "rev": rev,
        "view": "list",
        "canGoBack": True,
        "placeholder": "Choose visibility…",
        "items": items,
    }


def build_settings_frame(rev):
    with LOCK:
        bcu_path = STATE["bcu_path"]
        auto_remove_junk = STATE["auto_remove_junk"]
    return {
        "type": "render",
        "rev": rev,
        "view": "form",
        "canGoBack": True,
        "form": {
            "title": "BC Uninstaller Settings",
            "submitLabel": "Save",
            "fields": [
                {
                    "id": "bcu_path",
                    "type": "text",
                    "label": "BC Uninstaller path",
                    "value": bcu_path,
                    "placeholder": r"C:\Program Files\BCUninstaller",
                    "description": "BCU-console.exe, BCUninstaller.exe, or the install folder.",
                    "required": True,
                },
                {
                    "id": "auto_remove_junk",
                    "type": "checkbox",
                    "label": "Auto-remove high-confidence leftover junk",
                    "value": auto_remove_junk,
                    "description": "Adds /J=VeryGood so BC Uninstaller also cleans confident leftover registry entries after uninstalling.",
                },
            ],
        },
    }


def render_current(rev):
    with LOCK:
        screen = STATE["screen"]
    if screen == "visibility":
        send(build_visibility_frame(rev))
    elif screen == "settings":
        send(build_settings_frame(rev))
    else:
        send(build_root_frame(rev))


# ---------------------------------------------------------------------------
# persistence (Tabame storage command)
# ---------------------------------------------------------------------------

def persist_settings():
    with LOCK:
        payload = json.dumps(
            {
                "bcu_path": STATE["bcu_path"],
                "auto_remove_junk": STATE["auto_remove_junk"],
                "visibility": STATE["visibility"],
                "show_preview": STATE["show_preview"],
            }
        )
    send({"type": "command", "command": "storage", "op": "set", "key": "settings", "value": payload})


def persist_apps_cache(apps):
    payload = json.dumps({"apps": apps, "loaded_at": time.time()})
    send({"type": "command", "command": "storage", "op": "set", "key": "apps_cache", "value": payload})


# ---------------------------------------------------------------------------
# refresh / uninstall workers
# ---------------------------------------------------------------------------

def find_app(item_id):
    with LOCK:
        for app in STATE["apps"]:
            if app["id"] == item_id:
                return app
    return None


def toggle_queue(app):
    with LOCK:
        if app["id"] in STATE["queue"]:
            del STATE["queue"][app["id"]]
        else:
            STATE["queue"][app["id"]] = {
                "id": app["id"],
                "display_name": app["display_name"],
                "quiet_uninstall_possible": app["quiet_uninstall_possible"],
                "match_target": app["match_target"],
            }


def start_refresh(force=False, silent=False):
    with LOCK:
        if STATE["refreshing"]:
            return
        if not STATE["bcu_path"]:
            return
        if not force and STATE["apps"] and (time.time() - STATE["apps_loaded_at"]) < PERSISTENT_CACHE_SECONDS:
            return
        STATE["refreshing"] = True
        bcu_path = STATE["bcu_path"]

    if silent:
        send({"type": "command", "command": "toast", "text": "Refreshing applications…", "style": "progress"})
    else:
        with LOCK:
            STATE["loading"] = True
            STATE["error"] = None
        render_current(0)

    threading.Thread(target=_refresh_worker, args=(bcu_path, silent), daemon=True).start()


def _refresh_worker(bcu_path, silent):
    try:
        apps = export_applications(bcu_path)
        apps.sort(key=lambda app: app["display_name"].lower())
        with LOCK:
            STATE["apps"] = apps
            STATE["apps_loaded_at"] = time.time()
            STATE["loading"] = False
            STATE["error"] = None
            STATE["refreshing"] = False
            live_ids = {app["id"] for app in apps}
            STATE["queue"] = {qid: item for qid, item in STATE["queue"].items() if qid in live_ids}
        persist_apps_cache(apps)
        if silent:
            send({"type": "command", "command": "toast", "text": f"{len(apps)} applications loaded", "style": "success"})
        render_current(0)
    except Exception as exc:  # noqa: BLE001 - never let the worker crash the process
        message = str(exc)
        with LOCK:
            STATE["loading"] = False
            STATE["refreshing"] = False
            if not silent:
                STATE["error"] = message
        log("refresh error:", message)
        if silent:
            send({"type": "command", "command": "toast", "text": "Refresh failed", "style": "error"})
        else:
            render_current(0)


def begin_uninstall():
    with LOCK:
        queued_items = list(STATE["queue"].values())
        auto_remove_junk = STATE["auto_remove_junk"]
        bcu_path = STATE["bcu_path"]
        live_ids = {app["id"] for app in STATE["apps"]}

    if not queued_items:
        send({"type": "command", "command": "toast", "text": "Queue is empty", "style": "error"})
        return

    missing = [item for item in queued_items if item["id"] not in live_ids]
    if missing:
        send({"type": "command", "command": "toast", "text": "Queue is stale — refresh and try again", "style": "error"})
        return

    send(
        {
            "type": "command",
            "command": "toast",
            "text": f"Submitting {len(queued_items)} app(s) to BC Uninstaller…",
            "style": "progress",
        }
    )
    threading.Thread(target=_uninstall_worker, args=(bcu_path, queued_items, auto_remove_junk), daemon=True).start()


def _uninstall_worker(bcu_path, queued_items, auto_remove_junk):
    try:
        summary = uninstall_queued_apps_with_bcu(bcu_path, queued_items, auto_remove_junk)
        with LOCK:
            STATE["queue"] = {}
        send(
            {
                "type": "command",
                "command": "toast",
                "text": f"Batch uninstall complete — quiet: {summary['quiet_count']}, non-quiet: {summary['non_quiet_count']}",
                "style": "success",
            }
        )
        render_current(0)
        start_refresh(force=True, silent=True)
    except Exception as exc:  # noqa: BLE001
        log("uninstall error:", exc)
        send({"type": "command", "command": "toast", "text": f"Batch uninstall failed: {exc}", "style": "error"})


def _maybe_start_initial_refresh():
    with LOCK:
        if not (STATE["settings_loaded"] and STATE["apps_cache_loaded"]):
            return
        bcu_path = STATE["bcu_path"]
        has_fresh_cache = bool(STATE["apps"]) and (time.time() - STATE["apps_loaded_at"]) < PERSISTENT_CACHE_SECONDS
        has_apps = bool(STATE["apps"])

    if not bcu_path:
        with LOCK:
            STATE["loading"] = False
        render_current(0)
        return

    if has_fresh_cache:
        with LOCK:
            STATE["loading"] = False
        render_current(0)
        return

    start_refresh(force=False, silent=has_apps)


# ---------------------------------------------------------------------------
# message handlers
# ---------------------------------------------------------------------------

def handle_query(text, rev):
    with LOCK:
        STATE["query"] = text
        screen = STATE["screen"]
    if screen == "root":
        render_current(rev)


def handle_root_frame_action(action):
    if action == "refresh":
        start_refresh(force=True)
        return
    if action == "open-visibility":
        with LOCK:
            STATE["screen"] = "visibility"
        render_current(0)
        return
    if action == "open-settings":
        with LOCK:
            STATE["screen"] = "settings"
        send(build_settings_frame(0))
        return
    if action == "toggle-preview":
        with LOCK:
            STATE["show_preview"] = not STATE["show_preview"]
        persist_settings()
        render_current(0)
        return
    if action == "uninstall-queued":
        begin_uninstall()
        return
    if action == "clear-queue":
        with LOCK:
            STATE["queue"] = {}
        send({"type": "command", "command": "toast", "text": "Queue cleared", "style": "success"})
        render_current(0)
        return


def handle_root_action(item_id, action):
    if item_id == "":
        handle_root_frame_action(action)
        return

    if item_id == "queue-summary":
        if action == "uninstall-queued":
            begin_uninstall()
        elif action == "clear-queue":
            with LOCK:
                STATE["queue"] = {}
            send({"type": "command", "command": "toast", "text": "Queue cleared", "style": "success"})
            render_current(0)
        return

    app = find_app(item_id)
    if app is None:
        render_current(0)
        return

    if action == "default":
        toggle_queue(app)
        render_current(0)
        return

    if action == "copy-identifier":
        send({"type": "command", "command": "copy", "text": format_match_target(app["match_target"])})
        send(
            {
                "type": "command",
                "command": "toast",
                "text": f"Copied BCU identifier for {app['display_name']}",
                "style": "success",
            }
        )
        return


def handle_visibility_action(item_id, action):
    if action != "default" or not item_id.startswith("vis:"):
        return
    key = item_id[len("vis:"):]
    with LOCK:
        STATE["visibility"] = key
        STATE["screen"] = "root"
    persist_settings()
    render_current(0)


def handle_action(item_id, action):
    with LOCK:
        screen = STATE["screen"]
    if screen == "visibility":
        handle_visibility_action(item_id, action)
    else:
        handle_root_action(item_id, action)


def handle_back(rev):
    with LOCK:
        STATE["screen"] = "root"
    render_current(rev)


def handle_submit(values):
    bcu_path = (values.get("bcu_path") or "").strip()
    auto_remove_junk = bool(values.get("auto_remove_junk"))
    with LOCK:
        old_path = STATE["bcu_path"]
        STATE["bcu_path"] = bcu_path
        STATE["auto_remove_junk"] = auto_remove_junk
        STATE["screen"] = "root"
    persist_settings()
    send({"type": "command", "command": "toast", "text": "Settings saved", "style": "success"})
    render_current(0)
    if bcu_path and bcu_path != old_path:
        start_refresh(force=True)


def handle_storage_reply(msg):
    request_id = msg.get("requestId")

    if request_id == "settings-load":
        raw_value = msg.get("value")
        data = {}
        if raw_value:
            try:
                data = json.loads(raw_value)
            except (TypeError, ValueError):
                data = {}
        with LOCK:
            STATE["bcu_path"] = data.get("bcu_path", "") or STATE["bcu_path"]
            STATE["auto_remove_junk"] = bool(data.get("auto_remove_junk", False))
            STATE["visibility"] = data.get("visibility") or "default"
            STATE["show_preview"] = bool(data.get("show_preview", False))
            STATE["settings_loaded"] = True
        _maybe_start_initial_refresh()
        return

    if request_id == "apps-cache-load":
        raw_value = msg.get("value")
        if raw_value:
            try:
                data = json.loads(raw_value)
            except (TypeError, ValueError):
                data = {}
            apps = data.get("apps") or []
            loaded_at = data.get("loaded_at") or 0
            if apps:
                with LOCK:
                    if not STATE["apps"]:
                        STATE["apps"] = apps
                        STATE["apps_loaded_at"] = loaded_at
        with LOCK:
            STATE["apps_cache_loaded"] = True
        _maybe_start_initial_refresh()
        return


# ---------------------------------------------------------------------------
# main loop
# ---------------------------------------------------------------------------

def main():
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "list",
            "loading": True,
            "loadingText": "Loading installed applications…",
            "placeholder": "Search installed software…",
            "items": [],
        }
    )
    send({"type": "command", "command": "storage", "op": "get", "key": "settings", "requestId": "settings-load"})
    send({"type": "command", "command": "storage", "op": "get", "key": "apps_cache", "requestId": "apps-cache-load"})

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue

        msg_type = msg.get("type")
        try:
            if msg_type == "close":
                break
            elif msg_type in ("init", "query"):
                handle_query(msg.get("text", msg.get("query", "")), msg.get("rev", 0))
            elif msg_type == "action":
                handle_action(msg.get("id", ""), msg.get("action", "default"))
            elif msg_type == "back":
                handle_back(msg.get("rev", 0))
            elif msg_type == "submit":
                handle_submit(msg.get("values", {}))
            elif msg_type == "storage":
                handle_storage_reply(msg)
        except Exception as exc:  # noqa: BLE001 - keep the plugin alive no matter what
            log("unhandled error:", exc)


if __name__ == "__main__":
    main()
