#!/usr/bin/env python3
"""Tabame Environment Variables plugin.

Pages: home -> user/system variables -> variable detail or PATH editor -> forms.
Machine changes run this script again through Windows' runas verb.
"""
from __future__ import annotations

import ctypes
import hashlib
import json
import ntpath
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from typing import Any

try:
    import winreg
except ImportError:
    winreg = None

SUPPORTED = os.name == "nt" and winreg is not None
# //TODO: Implement multiplatform registry/environment read and write support.
REG_SZ = getattr(winreg, "REG_SZ", 1)
REG_EXPAND_SZ = getattr(winreg, "REG_EXPAND_SZ", 2)
KEYS = {
    "user": ("HKEY_CURRENT_USER", "Environment"),
    "system": ("HKEY_LOCAL_MACHINE", r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment"),
}
MOCK_DATA = {
    "user": {
        "Path": {"name": "Path", "value": r"%USERPROFILE%\bin;C:\Users\Demo\AppData\Local\Programs\Python\Python312\Scripts", "type": REG_EXPAND_SZ},
        "EDITOR": {"name": "EDITOR", "value": "code", "type": REG_SZ},
        "USERPROFILE": {"name": "USERPROFILE", "value": r"C:\Users\Demo", "type": REG_SZ},
    },
    "system": {
        "Path": {"name": "Path", "value": r"%SystemRoot%\system32;%SystemRoot%;C:\Windows\System32\Wbem", "type": REG_EXPAND_SZ},
        "ComSpec": {"name": "ComSpec", "value": r"%SystemRoot%\system32\cmd.exe", "type": REG_EXPAND_SZ},
        "OS": {"name": "OS", "value": "Windows_NT", "type": REG_SZ},
    },
}
STATE: dict[str, Any] = {"route": {"screen": "home"}, "revealed": set()}
PAGE_ROUTES: dict[str, dict[str, Any]] = {}
LAST_VARIABLES: dict[str, dict[str, Any]] = {}
LAST_PATH_ENTRIES: dict[str, dict[str, Any]] = {}


def send(frame: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(frame, ensure_ascii=False, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def command(name: str, **values: Any) -> None:
    send({"type": "command", "command": name, **values})


def toast(text: str, style: str = "info") -> None:
    command("toast", text=text, style=style)


def page_meta(page_id: str, title: str, history: str, ancestors: list[tuple[str, str]] | None = None) -> dict[str, Any]:
    return {"id": page_id, "title": title, "history": history, "preserveState": True,
            "breadcrumbs": [{"id": key, "label": label} for key, label in (ancestors or [])]}


def remember_page(page_id: str, route: dict[str, Any]) -> None:
    previous = STATE.get("page_id")
    if previous and previous != page_id:
        command("setQuery", text="")
    PAGE_ROUTES[page_id] = dict(route)
    STATE["route"] = dict(route)
    STATE["page_id"] = page_id


def read_scope(scope: str) -> dict[str, dict[str, Any]]:
    if not SUPPORTED:
        return MOCK_DATA[scope]
    root_name, subkey = KEYS[scope]
    root = getattr(winreg, root_name)
    values: dict[str, dict[str, Any]] = {}
    try:
        key = winreg.OpenKey(root, subkey, 0, winreg.KEY_READ)
    except FileNotFoundError:
        return values
    with key:
        index = 0
        while True:
            try:
                name, value, value_type = winreg.EnumValue(key, index)
            except OSError:
                break
            index += 1
            if name and isinstance(value, str):
                values[name.casefold()] = {"name": name, "value": value, "type": value_type}
    return values


def get_variable(scope: str, name: str, values: dict[str, dict[str, Any]] | None = None) -> dict[str, Any] | None:
    return (values if values is not None else read_scope(scope)).get(name.casefold())


def path_value(scope: str) -> tuple[str, dict[str, Any] | None]:
    if scope == "effective":
        value = os.environ.get("PATH", "")
        return value, {"name": "PATH", "value": value, "type": None}
    info = get_variable(scope, "Path")
    return (info["value"], info) if info else ("", None)


def registry_type_name(value_type: int | None) -> str:
    if value_type == REG_EXPAND_SZ:
        return "REG_EXPAND_SZ · expands %variables%"
    if value_type == REG_SZ:
        return "REG_SZ · literal text"
    return "Not set / process environment" if value_type is None else f"Registry type {value_type}"


def is_sensitive(name: str) -> bool:
    return bool(re.search(r"(token|secret|password|passwd|credential|private|auth|api.?key)", name, re.I))


def display_value(name: str, value: str, limit: int = 84) -> str:
    if is_sensitive(name):
        return "•••••••• (hidden)"
    compact = value.replace("\r", " ").replace("\n", " ↵ ")
    if not compact:
        return "(empty)"
    return compact if len(compact) <= limit else compact[:limit - 1] + "…"


def md_inline(value: str) -> str:
    return value.replace("\\", "\\\\").replace("`", "\\`").replace("*", "\\*").replace("_", "\\_")


def path_split(value: str) -> list[str]:
    return [] if value == "" else value.split(";")


def path_join(entries: list[str]) -> str:
    return ";".join(entries)


def unwrap_path(entry: str) -> str:
    value = entry.strip()
    if len(value) >= 2 and value[0] == value[-1] == '"':
        value = value[1:-1].strip()
    return value


def expand_path(entry: str) -> str:
    return os.path.expanduser(os.path.expandvars(unwrap_path(entry)))


def unresolved_variable(entry: str) -> bool:
    return bool(re.search(r"%[^%]+%", expand_path(entry)))


def path_key(entry: str) -> str:
    value = unwrap_path(entry)
    expanded = os.path.expandvars(value)
    if re.search(r"%[^%]+%", expanded):
        value = re.sub(r"%([^%]+)%", lambda match: "%" + match.group(1).casefold() + "%", value)
    else:
        value = expanded
    normalized = ntpath.normcase(ntpath.normpath(value.replace("/", "\\")))
    return normalized.rstrip("\\") if len(normalized) > 3 else normalized


def duplicate_indexes(entries: list[str]) -> dict[int, int]:
    seen: dict[str, int] = {}
    duplicates: dict[int, int] = {}
    for index, entry in enumerate(entries):
        if not entry.strip():
            continue
        key = path_key(entry)
        if key in seen:
            duplicates[index] = seen[key]
        else:
            seen[key] = index
    return duplicates


def path_status(entry: str) -> tuple[str, str]:
    if not SUPPORTED:
        return "unknown", "Sample path · checked only on Windows"
    value = unwrap_path(entry)
    if not value:
        return "empty", "Empty entry · Windows searches the current directory"
    expanded = expand_path(value)
    if unresolved_variable(value):
        return "unknown", "Unresolved environment variable · kept during cleanup"
    if not ntpath.isabs(expanded):
        return "unknown", "Relative path · status depends on each process current folder"
    try:
        os.stat(expanded)
    except FileNotFoundError:
        return "missing", "Folder does not exist"
    except NotADirectoryError:
        return "file", "A parent is not a directory"
    except PermissionError:
        return "unknown", "Access denied · kept during cleanup"
    except OSError as error:
        return "unknown", f"Could not check path ({error}) · kept during cleanup"
    if os.path.isdir(expanded):
        return "ok", "Folder exists"
    return "file", "Path exists but is not a folder"


def confirm(title: str, message: str, label: str) -> dict[str, str]:
    return {"title": title, "message": message, "confirmLabel": label}


def var_page_id(scope: str, name: str) -> str:
    digest = hashlib.sha1(name.casefold().encode("utf-8", "replace")).hexdigest()[:12]
    return f"env:{scope}:var:{digest}"


def path_detail_page_id(scope: str, index: int, entry: str) -> str:
    digest = hashlib.sha1(entry.encode("utf-8", "replace")).hexdigest()[:8]
    return f"env:{scope}:path-entry:{index}:{digest}"


def scope_ancestors() -> list[tuple[str, str]]:
    return [("env:home", "Environment")]


def render_home(rev: int = 0, history: str = "replace", query: str = "") -> None:
    user_vars, system_vars = read_scope("user"), read_scope("system")
    user_path, _ = path_value("user")
    system_path, _ = path_value("system")
    items = [
        {"id": "scope:user", "title": "User variables", "subtitle": f"{len(user_vars)} variables · {len(path_split(user_path))} PATH entries", "icon": "user"},
        {"id": "scope:system", "title": "System variables", "subtitle": f"{len(system_vars)} variables · {len(path_split(system_path))} PATH entries · administrator approval for changes", "icon": "shield"},
        {"id": "path:effective", "title": "Current process PATH", "subtitle": f"{len(os.environ.get('PATH', '').split(os.pathsep)) if os.environ.get('PATH', '') else 0} entries inherited by Tabame", "icon": "terminal", "actions": [{"id": "copy", "title": "Copy current PATH", "icon": "copy"}]},
    ]
    items = [item for item in items if query.casefold() in (item["title"] + " " + item["subtitle"]).casefold()]
    frame: dict[str, Any] = {"type": "render", "rev": rev, "view": "list",
        "page": page_meta("env:home", "Environment Variables", history),
        "placeholder": "Open user, system, or current PATH", "emptyText": "No environment pages match that search",
        "items": items, "actions": [
            {"id": "refresh", "title": "Refresh", "icon": "refresh", "shortcut": "ctrl+r"},
            {"id": "windows-dialog", "title": "Open Windows environment dialog", "icon": "open"},
        ]}
    if not SUPPORTED:
        frame["banners"] = [{"id": "mock", "style": "warning", "title": "Windows registry unavailable", "message": "Showing sample data. #TODO: Implement multiplatform", "dismissible": False}]
    remember_page("env:home", {"screen": "home", "query": query})
    send(frame)


def render_scope(scope: str, rev: int = 0, history: str = "push", query: str = "") -> None:
    values = read_scope(scope)
    infos = sorted(values.values(), key=lambda item: (item["name"].casefold() != "path", item["name"].casefold()))
    LAST_VARIABLES.clear()
    items = []
    for info in infos:
        name, value = info["name"], info["value"]
        if query and query.casefold() not in (name + " " + value).casefold():
            continue
        item_id = "var:" + hashlib.sha1(name.casefold().encode("utf-8", "replace")).hexdigest()[:12]
        LAST_VARIABLES[item_id] = {"scope": scope, **info}
        is_path = name.casefold() == "path"
        subtitle = f"{len(path_split(value))} entries · {registry_type_name(info['type'])}" if is_path else f"{registry_type_name(info['type'])} · {display_value(name, value)}"
        actions = [
            {"id": "edit", "title": "Edit value", "icon": "edit"},
            {"id": "copy", "title": "Copy value", "icon": "copy"},
            {"id": "delete", "title": "Remove variable", "icon": "delete", "destructive": True,
             "confirm": confirm(f"Remove {name}?", "This deletes the value from this registry scope.", "Remove")},
        ]
        if is_path:
            actions.insert(0, {"id": "edit-path", "title": "Manage PATH entries", "icon": "folder"})
        else:
            actions.insert(0, {"id": "view", "title": "View variable", "icon": "open"})
        items.append({"id": item_id, "title": name, "subtitle": subtitle, "icon": "folder" if is_path else ("key" if is_sensitive(name) else "tag"), "actions": actions})
    title = "User variables" if scope == "user" else "System variables"
    page_id = f"env:{scope}:variables"
    frame: dict[str, Any] = {"type": "render", "rev": rev, "view": "list",
        "page": page_meta(page_id, title, history, scope_ancestors()),
        "placeholder": f"Filter {title.lower()}…",
        "emptyText": "No variables match that search" if values else "No variables are stored in this scope",
        "items": items, "floatingAction": {"id": "add-variable", "title": "Add variable", "icon": "add"},
        "actions": [
            {"id": "add-variable", "title": "Add environment variable", "icon": "add"},
            {"id": "copy-json", "title": "Copy JSON export (includes secrets)", "icon": "copy"},
            {"id": "copy-reg", "title": "Copy .reg export (includes values)", "icon": "download"},
            {"id": "refresh", "title": "Refresh", "icon": "refresh", "shortcut": "ctrl+r"},
            {"id": "windows-dialog", "title": "Open Windows environment dialog", "icon": "open"},
        ]}
    if scope == "system":
        frame["banners"] = [{"id": "system-scope", "style": "info", "title": "Machine-wide values", "message": "Changing or removing a system variable asks Windows for administrator approval.", "dismissible": False}]
    if not SUPPORTED:
        frame["banners"] = [{"id": "mock", "style": "warning", "title": "Sample data", "message": "This is a mockup on Linux and macOS. #TODO: Implement multiplatform", "dismissible": False}]
    remember_page(page_id, {"screen": "scope", "scope": scope, "query": query})
    send(frame)


def render_path(scope: str, rev: int = 0, history: str = "push", query: str = "") -> None:
    raw, info = path_value(scope)
    entries = raw.split(os.pathsep) if scope == "effective" and not SUPPORTED and raw else path_split(raw)
    duplicates = duplicate_indexes(entries)
    LAST_PATH_ENTRIES.clear()
    items = []
    for index, entry in enumerate(entries):
        status, description = path_status(entry)
        if index in duplicates:
            status, description = "duplicate", f"Duplicate of entry #{duplicates[index] + 1} · {description}"
        if query and query.casefold() not in (entry + " " + description).casefold():
            continue
        digest = hashlib.sha1(f"{index}\0{entry}".encode("utf-8", "replace")).hexdigest()[:8]
        item_id = f"path:{index}:{digest}"
        LAST_PATH_ENTRIES[item_id] = {"scope": scope, "index": index, "entry": entry, "raw": raw, "type": info.get("type") if info else None}
        actions = [{"id": "copy", "title": "Copy path", "icon": "copy"}]
        if scope != "effective":
            actions = [
                {"id": "edit", "title": "Edit entry", "icon": "edit"},
                {"id": "move-up", "title": "Move up", "icon": "upload", "shortcut": "alt+up"},
                {"id": "move-down", "title": "Move down", "icon": "download", "shortcut": "alt+down"},
                {"id": "open", "title": "Open folder", "icon": "open"},
                {"id": "copy", "title": "Copy path", "icon": "copy"},
                {"id": "remove", "title": "Remove entry", "icon": "delete", "destructive": True,
                 "confirm": confirm("Remove this PATH entry?", md_inline(entry), "Remove")},
            ]
        title = entry if entry else "(empty entry — current directory)"
        icon = {"ok": "check", "missing": "error", "file": "warning", "unknown": "help", "empty": "warning", "duplicate": "copy"}.get(status, "folder")
        items.append({"id": item_id, "title": title, "subtitle": f"Entry {index + 1} · {description}", "icon": icon, "actions": actions})
    if scope == "effective":
        page_id, title = "env:effective:path", "Current process PATH"
        ancestors = [("env:home", "Environment")]
        frame_actions = [{"id": "copy-path", "title": "Copy current PATH", "icon": "copy"}, {"id": "refresh", "title": "Refresh", "icon": "refresh", "shortcut": "ctrl+r"}]
    else:
        page_id, title = f"env:{scope}:path", f"{'User' if scope == 'user' else 'System'} PATH"
        ancestors = [("env:home", "Environment"), (f"env:{scope}:variables", "User variables" if scope == "user" else "System variables")]
        frame_actions = [
            {"id": "add-path", "title": "Add PATH entry", "icon": "add"},
            {"id": "clean-duplicates", "title": "Clean duplicate entries", "icon": "delete", "destructive": True,
             "confirm": confirm("Remove duplicate PATH entries?", "The first occurrence is kept; later equivalent entries are removed.", "Clean duplicates")},
            {"id": "remove-missing", "title": "Remove missing entries", "icon": "delete", "destructive": True,
             "confirm": confirm("Remove broken PATH entries?", "Removes missing paths and files. Empty entries, unresolved variables, and paths Windows cannot check are kept.", "Remove broken")},
            {"id": "copy-path", "title": "Copy full PATH", "icon": "copy"},
            {"id": "edit-whole-path", "title": "Edit full PATH value", "icon": "edit"},
            {"id": "refresh", "title": "Refresh", "icon": "refresh", "shortcut": "ctrl+r"},
        ]
    frame: dict[str, Any] = {"type": "render", "rev": rev, "view": "list", "page": page_meta(page_id, title, history, ancestors),
        "placeholder": "Filter PATH entries…", "emptyText": "No PATH entries match that search" if entries else "PATH is empty. Add a folder to get started.",
        "items": items, "actions": frame_actions}
    if scope != "effective":
        bad_count = sum(1 for entry in entries if path_status(entry)[0] in {"missing", "file"})
        frame["floatingAction"] = {"id": "add-path", "title": "Add PATH entry", "icon": "add"}
        frame["banners"] = [{"id": "path-summary", "style": "warning" if bad_count or duplicates else "info",
            "title": f"{len(entries)} entries · {len(duplicates)} duplicates · {bad_count} broken",
            "message": f"Stored as {registry_type_name(info.get('type') if info else None)}. Unresolved and unchecked paths are kept during cleanup.", "dismissible": False}]
    elif not SUPPORTED:
        frame["banners"] = [{"id": "mock", "style": "warning", "title": "Sample PATH", "message": "Showing the current process PATH; registry editing is Windows-only. #TODO: Implement multiplatform", "dismissible": False}]
    if scope != "effective" and not SUPPORTED:
        frame["banners"] = [{"id": "mock", "style": "warning", "title": "Sample PATH", "message": "This is a UI mockup on Linux and macOS. #TODO: Implement multiplatform", "dismissible": False}]
    remember_page(page_id, {"screen": "path", "scope": scope, "query": query, "raw": raw, "type": info.get("type") if info else None})
    send(frame)


def render_variable_detail(scope: str, name: str, rev: int = 0, history: str = "push", reveal: bool = False) -> None:
    info = get_variable(scope, name)
    if info is None:
        toast(f"{name} no longer exists in this scope", "error")
        render_scope(scope, 0, history="replace")
        return
    name, value, value_type = info["name"], info["value"], info["type"]
    if name.casefold() == "path":
        render_path(scope, rev, history)
        return
    reveal_key = (scope, name.casefold())
    if reveal:
        STATE["revealed"].add(reveal_key)
    hidden = is_sensitive(name) and reveal_key not in STATE["revealed"]
    shown = "(hidden — use Reveal value to display)" if hidden else value
    page_id = var_page_id(scope, name)
    markdown = (f"# `{md_inline(name)}`\n\n**Scope:** {'User' if scope == 'user' else 'System'}  \n"
                f"**Type:** {registry_type_name(value_type)}  \n**Length:** {len(value)} characters\n\n## Value\n\n```text\n{shown}\n```")
    actions = [
        {"id": "edit", "title": "Edit value", "icon": "edit"},
        {"id": "copy", "title": "Copy value", "icon": "copy"},
        {"id": "delete", "title": "Remove variable", "icon": "delete", "destructive": True,
         "confirm": confirm(f"Remove {name}?", "This deletes the value from this registry scope.", "Remove")},
    ]
    if is_sensitive(name):
        actions.insert(0, {"id": "hide" if not hidden else "reveal", "title": "Hide value" if not hidden else "Reveal value", "icon": "lock" if not hidden else "unlock"})
    frame = {"type": "render", "rev": rev, "view": "detail",
        "page": page_meta(page_id, name, history, scope_ancestors() + [(f"env:{scope}:variables", "User variables" if scope == "user" else "System variables")]),
        "detail": {"markdown": markdown}, "actions": actions}
    remember_page(page_id, {"screen": "variable-detail", "scope": scope, "name": name, "revealed": not hidden})
    send(frame)


def render_path_entry_detail(scope: str, index: int, entry: str, rev: int = 0, history: str = "push", raw: str | None = None, value_type: int | None = None) -> None:
    page_id = path_detail_page_id(scope, index, entry)
    status, description = path_status(entry)
    actions = [{"id": "copy", "title": "Copy path", "icon": "copy"}, {"id": "open", "title": "Open folder", "icon": "open"}]
    if scope != "effective":
        actions += [
            {"id": "edit", "title": "Edit entry", "icon": "edit"},
            {"id": "move-up", "title": "Move up", "icon": "upload", "shortcut": "alt+up"},
            {"id": "move-down", "title": "Move down", "icon": "download", "shortcut": "alt+down"},
            {"id": "remove", "title": "Remove entry", "icon": "delete", "destructive": True,
             "confirm": confirm("Remove this PATH entry?", md_inline(entry), "Remove")},
        ]
    ancestors = [("env:home", "Environment")]
    if scope != "effective":
        ancestors.append((f"env:{scope}:variables", "User variables" if scope == "user" else "System variables"))
    ancestors.append((f"env:{scope}:path", "PATH"))
    frame = {"type": "render", "rev": rev, "view": "detail",
        "page": page_meta(page_id, f"PATH entry {index + 1}", history, ancestors),
        "detail": {"markdown": f"# PATH entry {index + 1}\n\n**Status:** {description}\n\n```text\n{entry}\n```"},
        "actions": actions}
    if raw is None:
        raw, info = path_value(scope)
        value_type = info.get("type") if info else None
    remember_page(page_id, {"screen": "path-detail", "scope": scope, "index": index, "entry": entry, "raw": raw, "type": value_type})
    send(frame)


def registry_snapshot(info: dict[str, Any] | None) -> dict[str, Any]:
    return {"exists": info is not None, "value": info["value"] if info else None, "type": info["type"] if info else None}


def same_snapshot(current: dict[str, Any] | None, expected: dict[str, Any]) -> bool:
    return registry_snapshot(current) == expected


def type_options() -> list[dict[str, str]]:
    return [
        {"value": "keep", "label": "Keep existing type"},
        {"value": "auto", "label": "Choose automatically"},
        {"value": "string", "label": "REG_SZ · literal text"},
        {"value": "expand", "label": "REG_EXPAND_SZ · expand %variables%"},
    ]


def render_form(context: dict[str, Any], rev: int = 0, history: str = "push", error: str | None = None) -> None:
    scope, kind, mode = context["scope"], context["kind"], context["mode"]
    if kind == "variable":
        name, info = context.get("name", ""), context.get("info")
        fields = []
        if mode == "add":
            fields.append({"id": "name", "type": "text", "label": "Variable name", "required": True,
                           "description": "Names cannot contain '='. Windows environment variable names are case-insensitive."})
        fields.extend([
            {"id": "value", "type": "password" if is_sensitive(name) else "textarea", "label": "Value", "value": info["value"] if info else "",
             "description": (f"Value for {name}. Use %NAME% to reference another environment variable." if mode == "edit" else "Use %NAME% to reference another environment variable.")},
            {"id": "type", "type": "dropdown", "label": "Registry storage type", "value": "keep" if info else "auto", "options": type_options()},
        ])
        title = "Add environment variable" if mode == "add" else f"Edit {name}"
        submit_label = "Add variable" if mode == "add" else "Save changes"
        suffix = hashlib.sha1(name.casefold().encode("utf-8", "replace")).hexdigest()[:8] if name else "new"
        page_id = f"env:{scope}:form:variable:{mode}:{suffix}"
        parent = {"screen": "scope", "scope": scope, "query": ""}
    else:
        if mode == "add":
            fields = [
                {"id": "paths", "type": "textarea", "label": "Folder paths", "required": True,
                 "description": "One folder per line. Semicolon-separated values can also be pasted."},
                {"id": "position", "type": "radio", "label": "Add entries", "value": "end", "options": [
                    {"value": "end", "label": "At the end"}, {"value": "start", "label": "At the beginning"}]},
                {"id": "allowDuplicate", "type": "checkbox", "label": "Allow duplicates", "value": False},
            ]
            title, submit_label, page_tag = "Add PATH entries", "Add entries", "new"
        elif mode == "whole":
            fields = [{"id": "path", "type": "textarea", "label": "Full PATH value", "value": context.get("raw", ""),
                       "description": "Separate folders with semicolons. Existing order is preserved when you save."}]
            title, submit_label, page_tag = "Edit full PATH value", "Save PATH", "whole"
        else:
            fields = [{"id": "path", "type": "text", "label": "Folder path", "value": context.get("entry", ""), "required": True,
                       "description": "A semicolon separates PATH entries and cannot be used inside one entry."}]
            title, submit_label, page_tag = f"Edit PATH entry {context['index'] + 1}", "Save entry", str(context.get("index", 0))
        page_id = f"env:{scope}:form:path:{mode}:{page_tag}"
        parent = {"screen": "path", "scope": scope, "query": ""}
    ancestors = scope_ancestors() + [(f"env:{scope}:variables", "User variables" if scope == "user" else "System variables")]
    if kind == "path":
        ancestors.append((f"env:{scope}:path", "PATH"))
    frame: dict[str, Any] = {"type": "render", "rev": rev, "view": "form",
        "page": page_meta(page_id, title, history, ancestors), "canGoBack": True,
        "form": {"title": title, "submitLabel": submit_label, "fields": fields}}
    if error:
        frame["form"]["error"] = error
    if not SUPPORTED:
        frame["banners"] = [{"id": "mock", "style": "warning", "title": "Preview only",
            "message": "Submitting writes only on Windows. #TODO: Implement multiplatform", "dismissible": False}]
    remember_page(page_id, {"screen": "form", "scope": scope, "kind": kind, "mode": mode,
                           "context": context, "parent": parent})
    send(frame)


def notify_environment_changed() -> None:
    user32 = ctypes.WinDLL("user32", use_last_error=True)
    size_t = ctypes.c_size_t
    user32.SendMessageTimeoutW.argtypes = [ctypes.c_void_p, ctypes.c_uint, size_t, ctypes.c_void_p,
                                           ctypes.c_uint, ctypes.c_uint, ctypes.POINTER(size_t)]
    user32.SendMessageTimeoutW.restype = size_t
    text = ctypes.c_wchar_p("Environment")
    result = size_t()
    user32.SendMessageTimeoutW(ctypes.c_void_p(0xFFFF), 0x001A, 0, ctypes.cast(text, ctypes.c_void_p),
                               0x0002, 5000, ctypes.byref(result))


def apply_registry_request(request: dict[str, Any]) -> None:
    if not SUPPORTED:
        raise RuntimeError("Registry editing is available on Windows only")
    scope, op, name = request.get("scope"), request.get("op"), request.get("name")
    if scope not in {"user", "system"} or op not in {"set", "delete"}:
        raise ValueError("Invalid registry operation")
    if not isinstance(name, str) or not name.strip() or "=" in name or "\x00" in name:
        raise ValueError("Enter a valid environment variable name")
    if any(ord(character) < 32 or ord(character) == 127 for character in name):
        raise ValueError("Variable names cannot contain control characters")
    root_name, subkey = KEYS[scope]
    root = getattr(winreg, root_name)
    access = winreg.KEY_QUERY_VALUE | winreg.KEY_SET_VALUE
    try:
        key = winreg.OpenKey(root, subkey, 0, access)
    except FileNotFoundError:
        key = winreg.CreateKeyEx(root, subkey, 0, access)
    with key:
        current_name = current_value = current_type = None
        index = 0
        while True:
            try:
                item_name, item_value, item_type = winreg.EnumValue(key, index)
            except OSError:
                break
            index += 1
            if item_name.casefold() == name.casefold():
                current_name, current_value, current_type = item_name, item_value, item_type
                break
        current = None if current_name is None or not isinstance(current_value, str) else {
            "name": current_name, "value": current_value, "type": current_type}
        if current_name is not None and current is None:
            raise RuntimeError(f"{current_name} exists with a registry type this editor cannot change")
        expected = request.get("expected") or {"exists": False, "value": None, "type": None}
        if not same_snapshot(current, expected):
            raise RuntimeError(f"{name} changed since it was opened. Refresh and try again.")
        actual_name = current_name or name
        if op == "delete":
            if current_name is None:
                raise RuntimeError(f"{name} no longer exists")
            winreg.DeleteValue(key, current_name)
        else:
            value, value_type = request.get("value"), request.get("newType")
            if not isinstance(value, str) or "\x00" in value:
                raise ValueError("Environment values must be text without NUL characters")
            if value_type not in {REG_SZ, REG_EXPAND_SZ}:
                raise ValueError("Invalid environment variable storage type")
            winreg.SetValueEx(key, actual_name, 0, value_type, value)
    notify_environment_changed()


def is_admin() -> bool:
    if not SUPPORTED:
        return False
    try:
        shell32 = ctypes.WinDLL("shell32", use_last_error=True)
        shell32.IsUserAnAdmin.restype = ctypes.c_int
        return bool(shell32.IsUserAnAdmin())
    except Exception:
        return False


class ShellExecuteInfo(ctypes.Structure):
    _fields_ = [
        ("cbSize", ctypes.c_ulong), ("fMask", ctypes.c_ulong), ("hwnd", ctypes.c_void_p),
        ("lpVerb", ctypes.c_wchar_p), ("lpFile", ctypes.c_wchar_p), ("lpParameters", ctypes.c_wchar_p),
        ("lpDirectory", ctypes.c_wchar_p), ("nShow", ctypes.c_int), ("hInstApp", ctypes.c_void_p),
        ("lpIDList", ctypes.c_void_p), ("lpClass", ctypes.c_wchar_p), ("hkeyClass", ctypes.c_void_p),
        ("dwHotKey", ctypes.c_ulong), ("hIconOrMonitor", ctypes.c_void_p), ("hProcess", ctypes.c_void_p),
    ]


def run_elevated_request(request: dict[str, Any]) -> None:
    script = os.path.abspath(sys.argv[0])
    with tempfile.TemporaryDirectory(prefix="tabame-env-") as folder:
        request_path, result_path = os.path.join(folder, "request.json"), os.path.join(folder, "result.json")
        with open(request_path, "w", encoding="utf-8") as output:
            json.dump(request, output, ensure_ascii=False)
        params = subprocess.list2cmdline([script, "--elevated-write", request_path, result_path])
        info = ShellExecuteInfo()
        info.cbSize, info.fMask = ctypes.sizeof(info), 0x00000040  # SEE_MASK_NOCLOSEPROCESS
        info.lpVerb, info.lpFile, info.lpParameters = "runas", sys.executable, params
        info.lpDirectory, info.nShow = os.path.dirname(script), 1
        shell32 = ctypes.WinDLL("shell32", use_last_error=True)
        shell32.ShellExecuteExW.argtypes = [ctypes.POINTER(ShellExecuteInfo)]
        shell32.ShellExecuteExW.restype = ctypes.c_int
        if not shell32.ShellExecuteExW(ctypes.byref(info)):
            error = ctypes.get_last_error()
            if error == 1223:
                raise RuntimeError("Windows administrator approval was cancelled")
            raise OSError(error, "Could not start the administrator helper")
        try:
            kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
            kernel32.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_uint]
            kernel32.WaitForSingleObject.restype = ctypes.c_uint
            kernel32.GetExitCodeProcess.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
            kernel32.GetExitCodeProcess.restype = ctypes.c_int
            kernel32.WaitForSingleObject(info.hProcess, 0xFFFFFFFF)
            exit_code = ctypes.c_ulong()
            kernel32.GetExitCodeProcess(info.hProcess, ctypes.byref(exit_code))
        finally:
            if info.hProcess:
                ctypes.WinDLL("kernel32", use_last_error=True).CloseHandle(info.hProcess)
        try:
            with open(result_path, "r", encoding="utf-8") as source:
                result = json.load(source)
        except (OSError, json.JSONDecodeError):
            if exit_code.value != 0:
                raise RuntimeError("The administrator helper failed without returning details")
            return
        if not result.get("ok"):
            raise RuntimeError(result.get("error", "The administrator helper failed"))


def commit(scope: str, name: str, op: str, expected: dict[str, Any], value: str | None = None, new_type: int | None = None) -> None:
    if not SUPPORTED:
        raise RuntimeError("Windows registry editing is not available in this mockup")
    if not same_snapshot(get_variable(scope, name), expected):
        raise RuntimeError(f"{name} changed since it was opened. Refresh and try again.")
    if op == "set" and new_type is None:
        raise ValueError("No registry storage type was selected")
    request = {"scope": scope, "name": name, "op": op, "expected": expected, "value": value, "newType": new_type}
    if scope == "system" and not is_admin():
        send({"type": "render", "rev": 0, "view": "detail", "loading": True,
              "loadingText": "Waiting for Windows administrator approval…",
              "detail": {"markdown": "Windows is asking for approval to update this value."}})
        run_elevated_request(request)
    else:
        try:
            apply_registry_request(request)
            return
        except PermissionError:
            if scope != "system":
                raise
            send({"type": "render", "rev": 0, "view": "detail", "loading": True,
                  "loadingText": "Waiting for Windows administrator approval…",
                  "detail": {"markdown": "Windows is asking for approval to update this value."}})
            run_elevated_request(request)


def select_type(selector: str, value: str, old_info: dict[str, Any] | None, is_path: bool = False) -> int:
    if selector == "keep" and old_info and old_info["type"] in {REG_SZ, REG_EXPAND_SZ}:
        return old_info["type"]
    if selector == "string":
        return REG_SZ
    if selector == "expand":
        return REG_EXPAND_SZ
    return REG_EXPAND_SZ if is_path or re.search(r"%[^%]+%", value) else REG_SZ


def mutate_path(scope: str, expected_raw: str, entries: list[str]) -> None:
    info = get_variable(scope, "Path")
    current_raw = info["value"] if info else ""
    if current_raw != expected_raw:
        raise RuntimeError("PATH changed since this page opened. Refresh before editing.")
    expected = registry_snapshot(info)
    value_type = info["type"] if info and info["type"] in {REG_SZ, REG_EXPAND_SZ} else REG_EXPAND_SZ
    commit(scope, info["name"] if info else "Path", "set", expected, path_join(entries), value_type)


def open_folder(entry: str) -> None:
    expanded = expand_path(entry)
    if not SUPPORTED or not expanded or not os.path.isdir(expanded):
        toast("This entry is not an existing folder", "error")
        return
    os.startfile(expanded)


def open_windows_dialog() -> None:
    if not SUPPORTED:
        toast("The Windows environment dialog is only available on Windows", "error")
    else:
        subprocess.Popen(["rundll32.exe", "sysdm.cpl,EditEnvironmentVariables"])


def export_json(scope: str) -> str:
    variables = read_scope(scope)
    return json.dumps({"scope": scope, "exportedAt": datetime.now(timezone.utc).isoformat(),
        "variables": {info["name"]: {"value": info["value"], "type": registry_type_name(info["type"])} for info in variables.values()}},
        ensure_ascii=False, indent=2)


def export_reg(scope: str) -> str:
    root_name, subkey = KEYS[scope]
    reg_key = root_name + "\\" + subkey
    lines = ["Windows Registry Editor Version 5.00", "", f"[{reg_key}]"]
    for info in sorted(read_scope(scope).values(), key=lambda item: item["name"].casefold()):
        value = info["value"]
        escaped_name = info["name"].replace("\\", "\\\\").replace('"', '\\"')
        if info["type"] == REG_EXPAND_SZ:
            raw = (value + "\0").encode("utf-16le")
            chunks = [raw[index:index + 24] for index in range(0, len(raw), 24)]
            continuation = "," + chr(92) + "\r\n  "
            rhs = "hex(2):" + continuation.join(",".join(f"{byte:02x}" for byte in chunk) for chunk in chunks)
        else:
            escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "\\r").replace("\n", "\\n")
            rhs = f'"{escaped}"'
        lines.append(f'"{escaped_name}"={rhs}')
    return "\r\n".join(lines)


def open_variable_form(scope: str, mode: str, name: str = "") -> None:
    info = get_variable(scope, name) if mode == "edit" else None
    context = {"scope": scope, "kind": "variable", "mode": mode,
               "name": info["name"] if info else name, "info": info}
    render_form(context)


def open_path_form(scope: str, mode: str, index: int | None = None, entry: str = "",
                   raw: str | None = None, value_type: int | None = None,
                   expected: dict[str, Any] | None = None) -> None:
    context = {"scope": scope, "kind": "path", "mode": mode, "index": index,
               "entry": entry, "raw": raw, "type": value_type,
               "expected": expected if expected is not None else registry_snapshot(get_variable(scope, "Path"))}
    render_form(context)


def return_parent(route: dict[str, Any], rev: int = 0) -> None:
    parent = route.get("parent", {})
    if parent.get("screen") == "path":
        render_path(parent.get("scope", route.get("scope", "user")), rev, "replace", parent.get("query", ""))
    else:
        render_scope(parent.get("scope", route.get("scope", "user")), rev, "replace", parent.get("query", ""))


def show_write_error(route: dict[str, Any], error: Exception) -> None:
    toast(str(error), "error")
    screen, scope = route.get("screen"), route.get("scope", "user")
    if screen in {"path", "path-detail"}:
        render_path(scope, 0, "none", route.get("query", ""))
    elif screen == "variable-detail":
        render_variable_detail(scope, route.get("name", ""), 0, "none", route.get("revealed", False))
    elif screen == "form":
        render_form(route["context"], 0, "none", str(error))
    else:
        render_scope(scope, 0, "none", route.get("query", ""))


def handle_submit(msg: dict[str, Any]) -> None:
    route = STATE.get("route", {})
    if route.get("screen") != "form":
        return
    context = route["context"]
    values = msg.get("values") if isinstance(msg.get("values"), dict) else {}
    scope = context["scope"]
    try:
        if context["kind"] == "variable":
            old_info = context.get("info")
            name = context.get("name", "") if context["mode"] == "edit" else str(values.get("name", "")).strip()
            value = values.get("value", "")
            if not name or "=" in name or "\x00" in name:
                raise ValueError("Enter a variable name without '=' or NUL characters")
            if any(ord(character) < 32 or ord(character) == 127 for character in name):
                raise ValueError("Variable names cannot contain control characters")
            if not isinstance(value, str) or "\x00" in value:
                raise ValueError("Environment values must be text without NUL characters")
            expected = registry_snapshot(old_info)
            if context["mode"] == "add" and get_variable(scope, name) is not None:
                raise ValueError(f"{name} already exists in this scope")
            new_type = select_type(str(values.get("type", "auto")), value, old_info)
            _name = name if context["mode"] == "add" else old_info["name"]
            commit(scope, _name, "set", expected, value, new_type)
            toast(f"{name} saved to {'user' if scope == 'user' else 'system'} variables", "success")
        elif context["mode"] == "add":
            raw, info = path_value(scope)
            if registry_snapshot(info) != context.get("expected"):
                raise RuntimeError("PATH changed while this form was open. Reopen the form and try again.")
            candidates = [part.strip() for line in str(values.get("paths", "")).splitlines()
                          for part in line.split(";") if part.strip()]
            if not candidates:
                raise ValueError("Enter at least one folder path")
            entries = path_split(raw)
            known = {path_key(entry) for entry in entries if entry.strip()}
            allow_duplicate = bool(values.get("allowDuplicate", False))
            added, skipped = [], 0
            for candidate in candidates:
                candidate, key = unwrap_path(candidate), path_key(candidate)
                if not allow_duplicate and key in known:
                    skipped += 1
                    continue
                added.append(candidate)
                known.add(key)
            entries = (added + entries) if values.get("position") == "start" else (entries + added)
            if added:
                mutate_path(scope, raw, entries)
            toast(f"Added {len(added)} PATH entr{'y' if len(added) == 1 else 'ies'}" +
                  (f" · skipped {skipped} duplicate(s)" if skipped else ""), "success" if added else "info")
        elif context["mode"] == "whole":
            raw = str(values.get("path", ""))
            if "\x00" in raw:
                raise ValueError("PATH cannot contain NUL characters")
            current_raw, info = path_value(scope)
            if current_raw != context.get("raw") or registry_snapshot(info) != context.get("expected"):
                raise RuntimeError("PATH changed while this form was open. Reopen the form and try again.")
            value_type = info["type"] if info and info["type"] in {REG_SZ, REG_EXPAND_SZ} else REG_EXPAND_SZ
            commit(scope, info["name"] if info else "Path", "set", registry_snapshot(info), raw, value_type)
            toast("Full PATH value saved", "success")
        else:
            old_entry = context["entry"]
            new_entry = unwrap_path(str(values.get("path", "")))
            if not new_entry:
                raise ValueError("Enter a folder path")
            if ";" in new_entry:
                raise ValueError("A semicolon separates PATH entries. Edit one entry at a time.")
            raw, info = path_value(scope)
            if raw != context.get("raw") or registry_snapshot(info) != context.get("expected"):
                raise RuntimeError("PATH changed since this form opened. Reopen the entry and try again.")
            entries, index = path_split(raw), int(context["index"])
            if index >= len(entries) or entries[index] != old_entry:
                raise RuntimeError("This PATH entry moved. Refresh and try again.")
            entries[index] = new_entry
            mutate_path(scope, raw, entries)
            toast("PATH entry updated", "success")
    except Exception as error:
        render_form(context, 0, "none", str(error))
        return
    return_parent(route)


def variable_action(scope: str, info: dict[str, Any], action: str) -> None:
    name, expected = info["name"], registry_snapshot(info)
    if action in {"default", "view"}:
        render_path(scope) if name.casefold() == "path" else render_variable_detail(scope, name)
    elif action == "edit":
        open_variable_form(scope, "edit", name)
    elif action == "copy":
        command("copy", text=info["value"])
        toast(f"Copied {name}", "success")
    elif action == "delete":
        commit(scope, name, "delete", expected)
        STATE["revealed"].discard((scope, name.casefold()))
        toast(f"Removed {name}", "success")
        render_scope(scope, 0, "none")
    elif action == "edit-path":
        render_path(scope)


def path_action(item: dict[str, Any], action: str) -> None:
    scope, index, entry, raw = item["scope"], item["index"], item["entry"], item["raw"]
    if action == "default":
        render_path_entry_detail(scope, index, entry, raw=raw, value_type=item.get("type"))
        return
    if action == "copy":
        command("copy", text=entry)
        toast("Copied PATH entry", "success")
        return
    if action == "open":
        open_folder(entry)
        return
    if scope == "effective":
        return
    route = STATE.get("route", {})
    if route.get("raw") != raw:
        raise RuntimeError("PATH changed since this entry was displayed. Refresh before editing.")
    if action == "edit":
        open_path_form(scope, "edit", index, entry, raw, item.get("type"), registry_snapshot(get_variable(scope, "Path")))
    elif action in {"move-up", "move-down", "remove"}:
        entries = path_split(raw)
        if index >= len(entries) or entries[index] != entry:
            raise RuntimeError("This PATH entry moved. Refresh before editing.")
        if action == "remove":
            del entries[index]
            mutate_path(scope, raw, entries)
            toast("PATH entry removed", "success")
        else:
            target = index + (-1 if action == "move-up" else 1)
            if target < 0 or target >= len(entries):
                toast("This entry is already at the beginning" if target < 0 else "This entry is already at the end", "info")
                return
            entries[index], entries[target] = entries[target], entries[index]
            mutate_path(scope, raw, entries)
            toast("PATH order updated", "success")
        render_path(scope, 0, "none")


def variable_detail_action(route: dict[str, Any], action: str) -> None:
    scope, name = route["scope"], route["name"]
    info = get_variable(scope, name)
    if not info:
        raise RuntimeError(f"{name} no longer exists")
    if action == "edit":
        open_variable_form(scope, "edit", name)
    elif action == "copy":
        command("copy", text=info["value"])
        toast(f"Copied {name}", "success")
    elif action == "delete":
        commit(scope, name, "delete", registry_snapshot(info))
        STATE["revealed"].discard((scope, name.casefold()))
        toast(f"Removed {name}", "success")
        render_scope(scope, 0, "replace")
    elif action == "reveal":
        render_variable_detail(scope, name, history="none", reveal=True)
    elif action == "hide":
        STATE["revealed"].discard((scope, name.casefold()))
        render_variable_detail(scope, name, history="none")


def frame_action(route: dict[str, Any], action: str) -> None:
    screen, scope = route.get("screen"), route.get("scope", "user")
    if screen == "variable-detail":
        variable_detail_action(route, action)
        return
    if screen == "path-detail":
        path_action({"scope": scope, "index": route["index"], "entry": route["entry"],
                     "raw": route["raw"], "type": route.get("type")}, action)
        return
    if action == "refresh":
        if screen == "scope":
            render_scope(scope, 0, "none", route.get("query", ""))
        elif screen == "path":
            render_path(scope, 0, "none", route.get("query", ""))
        else:
            render_home(0, "none", route.get("query", ""))
    elif action == "windows-dialog":
        open_windows_dialog()
    elif action == "add-variable":
        open_variable_form(scope, "add")
    elif action == "add-path":
        raw, info = path_value(scope)
        render_form({"scope": scope, "kind": "path", "mode": "add", "raw": raw,
                     "type": info.get("type") if info else None, "expected": registry_snapshot(info)})
    elif action == "copy-json":
        command("copy", text=export_json(scope))
        toast("Copied environment variables as JSON", "success")
    elif action == "copy-reg":
        command("copy", text=export_reg(scope))
        toast("Copied .reg export to the clipboard", "success")
    elif action == "copy-path":
        command("copy", text=path_value(scope)[0])
        toast("Copied full PATH", "success")
    elif action == "edit-whole-path":
        raw, info = path_value(scope)
        render_form({"scope": scope, "kind": "path", "mode": "whole", "raw": raw,
                     "type": info.get("type") if info else None, "expected": registry_snapshot(info)})
    elif action == "clean-duplicates":
        raw, _ = path_value(scope)
        if raw != route.get("raw"):
            raise RuntimeError("PATH changed since this page opened. Refresh before cleanup.")
        entries, duplicates = path_split(raw), duplicate_indexes(path_split(raw))
        if not duplicates:
            toast("No duplicate PATH entries found", "success")
            return
        mutate_path(scope, raw, [entry for index, entry in enumerate(entries) if index not in duplicates])
        toast(f"Removed {len(duplicates)} duplicate PATH entr{'y' if len(duplicates) == 1 else 'ies'}", "success")
        render_path(scope, 0, "none")
    elif action == "remove-missing":
        raw, _ = path_value(scope)
        if raw != route.get("raw"):
            raise RuntimeError("PATH changed since this page opened. Refresh before cleanup.")
        entries, kept, removed = path_split(raw), [], 0
        for entry in entries:
            status, _ = path_status(entry)
            if status in {"missing", "file"}:
                removed += 1
            else:
                kept.append(entry)
        if not removed:
            toast("No broken PATH entries that Windows can safely remove were found", "success")
            return
        mutate_path(scope, raw, kept)
        toast(f"Removed {removed} missing or non-folder PATH entr{'y' if removed == 1 else 'ies'}", "success")
        render_path(scope, 0, "none")


def handle_action(msg: dict[str, Any]) -> None:
    item_id, action = str(msg.get("id") or ""), str(msg.get("action") or "default")
    route = STATE.get("route", {"screen": "home"})
    try:
        if not item_id:
            frame_action(route, action)
        elif item_id.startswith("scope:") and action == "default":
            render_scope(item_id.split(":", 1)[1])
        elif item_id == "path:effective" and action in {"default", "copy"}:
            if action == "copy":
                command("copy", text=os.environ.get("PATH", ""))
                toast("Copied current process PATH", "success")
            else:
                render_path("effective")
        elif item_id.startswith("var:") and item_id in LAST_VARIABLES:
            info = LAST_VARIABLES[item_id]
            variable_action(info["scope"], info, action)
        elif item_id.startswith("path:") and item_id in LAST_PATH_ENTRIES:
            path_action(LAST_PATH_ENTRIES[item_id], action)
    except Exception as error:
        show_write_error(route, error)


def handle_initial_query(text: str, rev: int) -> None:
    words = text.strip().casefold().split()
    if words and words[0] in {"user", "system"}:
        scope = words[0]
        tail = words[1:]
        if tail and tail[0] in {"path", "paths"}:
            render_path(scope, rev, "replace", " ".join(tail[1:]))
        else:
            render_scope(scope, rev, "replace", " ".join(tail))
        STATE["ignore_next_query"] = text
        command("setQuery", text="")
    elif words and words[0] in {"path", "paths"}:
        scope, tail = "user", words[1:]
        if tail and tail[0] in {"user", "system"}:
            scope, tail = tail[0], tail[1:]
        render_path(scope, rev, "replace", " ".join(tail))
        STATE["ignore_next_query"] = text
        command("setQuery", text="")
    elif words[:2] == ["effective", "path"]:
        render_path("effective", rev, "replace", " ".join(words[2:]))
        STATE["ignore_next_query"] = text
        command("setQuery", text="")
    else:
        render_home(rev, "replace", text.strip())


def handle_query(text: str, rev: int, initial: bool = False) -> None:
    if initial:
        handle_initial_query(text, rev)
        return
    ignored_text = STATE.pop("ignore_next_query", None)
    if ignored_text == text:
        return
    route = STATE.get("route", {"screen": "home"})
    screen = route.get("screen")
    if screen == "home":
        words = text.strip().casefold().split()
        if words and words[0] in {"user", "system"}:
            scope, tail = words[0], words[1:]
            if tail and tail[0] in {"path", "paths"}:
                render_path(scope, rev, "push", " ".join(tail[1:]))
            else:
                render_scope(scope, rev, "push", " ".join(tail))
        elif words and words[0] in {"path", "paths"}:
            scope, tail = "user", words[1:]
            if tail and tail[0] in {"user", "system"}:
                scope, tail = tail[0], tail[1:]
            render_path(scope, rev, "push", " ".join(tail))
        elif words[:2] == ["effective", "path"]:
            render_path("effective", rev, "push", " ".join(words[2:]))
        else:
            render_home(rev, "none", text.strip())
    elif screen == "scope":
        render_scope(route["scope"], rev, "none", text.strip())
    elif screen == "path":
        render_path(route["scope"], rev, "none", text.strip())


def handle_back(msg: dict[str, Any]) -> None:
    target = msg.get("toPageId")
    route = PAGE_ROUTES.get(target) if isinstance(target, str) else None
    if route is None:
        current = STATE.get("route", {})
        route = current.get("parent") if current.get("screen") == "form" else None
    if route is None:
        route = {"screen": "home"}
    rev = msg.get("rev", 0)
    screen = route.get("screen")
    if screen == "home":
        render_home(rev, "none", route.get("query", ""))
    elif screen == "scope":
        render_scope(route["scope"], rev, "none", route.get("query", ""))
    elif screen == "path":
        render_path(route["scope"], rev, "none", route.get("query", ""))
    elif screen == "variable-detail":
        render_variable_detail(route["scope"], route["name"], rev, "none", route.get("revealed", False))
    elif screen == "path-detail":
        render_path_entry_detail(route["scope"], route["index"], route["entry"], rev, "none", route.get("raw"), route.get("type"))
    elif screen == "form":
        render_form(route["context"], rev, "none")
    else:
        render_home(rev, "none")


def handle_navigate(target: str, rev: int) -> None:
    route = PAGE_ROUTES.get(target)
    if not route:
        return
    screen = route.get("screen")
    if screen == "home":
        render_home(rev, "none", route.get("query", ""))
    elif screen == "scope":
        render_scope(route["scope"], rev, "none", route.get("query", ""))
    elif screen == "path":
        render_path(route["scope"], rev, "none", route.get("query", ""))


def elevated_entry(args: list[str]) -> int:
    if len(args) != 2:
        return 2
    request_path, result_path = args
    try:
        if not is_admin():
            raise PermissionError("The helper did not receive administrator access")
        with open(request_path, "r", encoding="utf-8") as source:
            request = json.load(source)
        if request.get("scope") != "system":
            raise ValueError("The elevated helper only accepts system-scope changes")
        apply_registry_request(request)
        result = {"ok": True}
    except Exception as error:
        result = {"ok": False, "error": str(error)}
    try:
        with open(result_path, "w", encoding="utf-8") as output:
            json.dump(result, output, ensure_ascii=False)
    except OSError:
        return 3
    return 0 if result["ok"] else 1


def main() -> None:
    if len(sys.argv) >= 2 and sys.argv[1] == "--elevated-write":
        raise SystemExit(elevated_entry(sys.argv[2:]))
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(msg, dict):
            continue
        kind = msg.get("type")
        rev = msg.get("rev", 0)
        if not isinstance(rev, int):
            rev = 0
        if kind == "close":
            break
        if kind == "init":
            text = msg.get("text", msg.get("query", ""))
            handle_query(text if isinstance(text, str) else "", rev, initial=True)
        elif kind == "query":
            text = msg.get("text", "")
            handle_query(text if isinstance(text, str) else "", rev)
        elif kind == "action":
            handle_action(msg)
        elif kind == "submit":
            handle_submit(msg)
        elif kind == "back":
            handle_back(msg)
        elif kind == "navigate":
            handle_navigate(str(msg.get("targetPageId", "")), rev)
        # select and tab events do not need a response.


if __name__ == "__main__":
    main()
