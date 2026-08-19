#!/usr/bin/env python3
"""Tabame launcher plugin for sharkdp/fd.

The plugin is dependency-free. It keeps Tabame's stdin loop responsive while a
background worker owns the current fd process; a new keystroke cancels the old
process and its stale render frame.
"""

from __future__ import annotations

import copy
import fnmatch
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading
from typing import Any


SEND_LOCK = threading.Lock()
STATE_LOCK = threading.RLock()
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
SETTINGS_KEY = "settings"
SETTINGS_REQUEST_ID = "fd-settings-load"
INSTALL_COMMANDS = {
    "install_scoop": ("Scoop", "scoop install fd"),
    "install_chocolatey": ("Chocolatey", "choco install fd"),
    "install_winget": ("Winget", "winget install sharkdp.fd"),
}


def default_settings() -> dict[str, Any]:
    return {
        "configured": False,
        "executable": "fd",
        "roots": [str(Path.home())],
        "includes": [],
        "excludes": ["node_modules", ".git", ".dart_tool", ".venv", "__pycache__"],
        "mode": "literal",
        "item_type": "files",
        "max_results": 150,
        "hidden": False,
        "ignored": False,
        "follow": False,
        "full_path": False,
    }


STATE: dict[str, Any] = {
    "loaded": False,
    "screen": "loading",
    "settings": default_settings(),
    "current_query": "",
    "results": [],
    "items": {},
    "active_process": None,
    "search_serial": 0,
    "closing": False,
}


def send(message: dict[str, Any]) -> None:
    with SEND_LOCK:
        sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def command(name: str, **fields: Any) -> None:
    send({"type": "command", "command": name, **fields})


def log(*parts: Any) -> None:
    print(*parts, file=sys.stderr, flush=True)


def page(page_id: str, title: str, history: str = "none", *, root: bool = False) -> dict[str, Any]:
    result: dict[str, Any] = {
        "id": page_id,
        "title": title,
        "history": history,
        "preserveState": True,
    }
    if not root:
        result["breadcrumbs"] = [{"id": "fd:search", "label": "Search"}]
    return result


SEARCH_ACTIONS = [
    {"id": "refresh", "title": "Run search again", "icon": "refresh", "shortcut": "ctrl+r"},
    {"id": "settings", "title": "Search settings", "icon": "settings", "shortcut": "ctrl+shift+s"},
    {"id": "help", "title": "How this search works", "icon": "help", "shortcut": "ctrl+shift+h"},
]


def split_rules(value: Any) -> list[str]:
    if isinstance(value, list):
        candidates = value
    else:
        candidates = str(value or "").splitlines()
    result: list[str] = []
    seen: set[str] = set()
    for candidate in candidates:
        rule = str(candidate).strip().strip('"')
        key = rule.casefold()
        if rule and key not in seen:
            seen.add(key)
            result.append(rule)
    return result


def normalize_root(value: str) -> str:
    expanded = os.path.expanduser(os.path.expandvars(value.strip().strip('"')))
    if os.name == "nt" and len(expanded) == 2 and expanded[1] == ":":
        expanded += "\\"
    return os.path.abspath(expanded)


def roots_from_values(roots_text: Any, quick_root: Any = "") -> list[str]:
    values = split_rules(roots_text)
    if str(quick_root or "").strip():
        values.append(str(quick_root))
    roots: list[str] = []
    seen: set[str] = set()
    for value in values:
        root = normalize_root(value)
        key = os.path.normcase(root)
        if key not in seen:
            seen.add(key)
            roots.append(root)
    return roots


def sanitized_settings(raw: Any) -> dict[str, Any]:
    settings = default_settings()
    if not isinstance(raw, dict):
        return settings

    executable = str(raw.get("executable", settings["executable"])).strip().strip('"')
    settings["executable"] = executable or "fd"
    try:
        settings["roots"] = roots_from_values(raw.get("roots", settings["roots"]))
    except (OSError, ValueError):
        settings["roots"] = default_settings()["roots"]
    if not settings["roots"]:
        settings["roots"] = default_settings()["roots"]
    settings["includes"] = split_rules(raw.get("includes", []))
    settings["excludes"] = split_rules(raw.get("excludes", settings["excludes"]))
    settings["mode"] = raw.get("mode") if raw.get("mode") in {"literal", "glob", "regex"} else "literal"
    settings["item_type"] = (
        raw.get("item_type") if raw.get("item_type") in {"files", "folders", "both"} else "files"
    )
    try:
        settings["max_results"] = max(20, min(500, int(raw.get("max_results", 150))))
    except (TypeError, ValueError):
        settings["max_results"] = 150
    for key in ("hidden", "ignored", "follow", "full_path"):
        settings[key] = bool(raw.get(key, settings[key]))
    settings["configured"] = bool(raw.get("configured", True))
    return settings


def save_settings() -> None:
    payload = json.dumps(STATE["settings"], ensure_ascii=False)
    command("storage", op="set", key=SETTINGS_KEY, value=payload)


def resolve_executable(value: str) -> str | None:
    expanded = os.path.expanduser(os.path.expandvars(value))
    if os.path.isfile(expanded):
        return os.path.abspath(expanded)
    return shutil.which(expanded)


def render_boot(rev: int = 0) -> None:
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": page("fd:search", "fd File Search", root=True),
            "loading": True,
            "loadingText": "Loading your search settings…",
            "items": [],
        }
    )


def settings_fields(settings: dict[str, Any], errors: dict[str, str] | None = None) -> list[dict[str, Any]]:
    errors = errors or {}

    def field(data: dict[str, Any]) -> dict[str, Any]:
        if data["id"] in errors:
            data["error"] = errors[data["id"]]
        return data

    executable = resolve_executable(settings["executable"])
    executable_hint = f"Found: {executable}" if executable else "Not found on PATH yet. Install fd or choose fd.exe."
    return [
        field(
            {
                "id": "roots",
                "type": "textarea",
                "label": "Search roots",
                "value": "\n".join(settings["roots"]),
                "required": True,
                "section": "locations",
                "description": "One drive or folder per line. Examples: C:\\, D:\\Work, %USERPROFILE%\\Documents.",
            }
        ),
        {
            "id": "quick_root",
            "type": "folderpicker",
            "label": "Add another root",
            "section": "locations",
            "description": "Optional: pick a folder and it will be merged into the list above when you save.",
        },
        {
            "id": "includes",
            "type": "textarea",
            "label": "Include only",
            "value": "\n".join(settings["includes"]),
            "section": "filters",
            "description": "Optional OR rules. Use path names (src), extensions (.dart), or globs (*.md), one per line.",
        },
        {
            "id": "excludes",
            "type": "textarea",
            "label": "Exclude",
            "value": "\n".join(settings["excludes"]),
            "section": "filters",
            "description": "Skip noisy path names, extensions, or globs. These are passed to fd for fast pruning.",
        },
        {
            "id": "mode",
            "type": "dropdown",
            "label": "Query mode",
            "value": settings["mode"],
            "section": "behavior",
            "options": [
                {"value": "literal", "label": "Smart literal · safe substring"},
                {"value": "glob", "label": "Glob · e.g. report*.pdf"},
                {"value": "regex", "label": "Regular expression"},
            ],
        },
        {
            "id": "item_type",
            "type": "dropdown",
            "label": "Result type",
            "value": settings["item_type"],
            "section": "behavior",
            "options": [
                {"value": "files", "label": "Files only"},
                {"value": "folders", "label": "Folders only"},
                {"value": "both", "label": "Files and folders"},
            ],
        },
        field(
            {
                "id": "max_results",
                "type": "number",
                "label": "Maximum results",
                "value": settings["max_results"],
                "min": 20,
                "max": 500,
                "section": "behavior",
                "description": "The plugin scans a larger candidate pool, ranks exact and prefix matches, then shows this many.",
            }
        ),
        {
            "id": "full_path",
            "type": "checkbox",
            "label": "Match the query against the full path",
            "value": settings["full_path"],
            "section": "behavior",
        },
        {
            "id": "hidden",
            "type": "checkbox",
            "label": "Search hidden files and folders",
            "value": settings["hidden"],
            "section": "behavior",
        },
        {
            "id": "ignored",
            "type": "checkbox",
            "label": "Search entries ignored by .gitignore/.fdignore",
            "value": settings["ignored"],
            "section": "behavior",
        },
        {
            "id": "follow",
            "type": "checkbox",
            "label": "Follow symbolic links",
            "value": settings["follow"],
            "section": "behavior",
        },
        field(
            {
                "id": "executable",
                "type": "text",
                "label": "fd executable",
                "value": settings["executable"],
                "required": True,
                "section": "advanced",
                "description": executable_hint,
            }
        ),
    ]


def render_settings(
    rev: int = 0,
    *,
    history: str = "push",
    errors: dict[str, str] | None = None,
    first_run: bool = False,
) -> None:
    STATE["screen"] = "settings"
    settings = STATE["settings"]
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "page": page("fd:settings", "Set up fd Search", "none" if first_run else history, root=first_run),
            "elementId": "fd-settings-form",
            "placeholder": "Configure where fd should search",
            "actions": [{"id": "help", "title": "Settings help", "icon": "help"}],
            "form": {
                "title": "Where should fd search?",
                **({"error": "Fix the highlighted settings before saving."} if errors else {}),
                "sections": [
                    {"id": "locations", "title": "Locations", "description": "Search one folder, several drives, or both."},
                    {"id": "filters", "title": "Path filters", "description": "Keep useful trees and prune noisy ones."},
                    {"id": "behavior", "title": "Search behavior", "collapsible": True},
                    {"id": "advanced", "title": "Executable", "collapsible": True},
                ],
                "submitLabel": "Save and search",
                "fields": settings_fields(settings, errors),
            },
        }
    )


def root_summary(settings: dict[str, Any]) -> str:
    roots = settings["roots"]
    noun = "root" if len(roots) == 1 else "roots"
    return f"{len(roots)} {noun} · {settings['mode']} mode · up to {settings['max_results']} results"


def render_search_prompt(rev: int, *, history: str = "none") -> None:
    STATE["screen"] = "search"
    settings = STATE["settings"]
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": page("fd:search", "fd File Search", history, root=True),
            "elementId": "fd-results",
            "placeholder": f"Search filenames across {len(settings['roots'])} configured location(s)…",
            "wide": True,
            "empty": {
                "icon": "search",
                "title": "Start typing a filename",
                "hint": root_summary(settings),
                "action": {"id": "settings", "title": "Review search locations", "icon": "settings"},
            },
            "actions": SEARCH_ACTIONS,
            "floatingAction": {"id": "settings", "title": "Settings", "icon": "settings"},
            "items": [],
        }
    )


def render_loading(rev: int, query: str, *, history: str = "none") -> None:
    STATE["screen"] = "search"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": page("fd:search", "fd File Search", history, root=True),
            "elementId": "fd-results",
            "placeholder": "Keep typing to refine…",
            "loading": True,
            "loadingText": f"fd is searching for “{query}”…",
            "wide": True,
            "actions": SEARCH_ACTIONS,
            "items": [],
        }
    )


def render_search_error(rev: int, title: str, hint: str) -> None:
    STATE["screen"] = "search"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": page("fd:search", "fd Search Error", root=True),
            "elementId": "fd-results",
            "placeholder": "Edit the query or open Settings",
            "empty": {
                "icon": "error",
                "title": title,
                "hint": hint[:500],
                "action": {"id": "settings", "title": "Open settings", "icon": "settings"},
            },
            "actions": SEARCH_ACTIONS,
            "floatingAction": {"id": "settings", "title": "Settings", "icon": "settings"},
            "items": [],
        }
    )


def render_fd_installer(rev: int = 0, *, launch_error: str = "") -> None:
    STATE["screen"] = "install"
    windows = os.name == "nt"
    metadata: list[dict[str, Any]] = []
    if windows:
        metadata = [
            {
                "label": "Scoop",
                "text": "scoop install fd",
                "icon": "terminal",
                "actions": [{"id": "install_scoop", "title": "Install with Scoop", "icon": "download"}],
            },
            {
                "label": "Chocolatey",
                "text": "choco install fd",
                "icon": "terminal",
                "actions": [
                    {"id": "install_chocolatey", "title": "Install with Chocolatey", "icon": "download"}
                ],
            },
            {
                "label": "Winget",
                "text": "winget install sharkdp.fd",
                "icon": "terminal",
                "actions": [{"id": "install_winget", "title": "Install with Winget", "icon": "download"}],
            },
        ]

    if launch_error:
        intro = f"## Could not open the installer terminal\n\n```\n{launch_error}\n```\n\n"
    elif windows:
        intro = (
            "Choose the package manager already available on this PC. The button opens a **visible command "
            "prompt**, runs the command shown, and keeps the terminal open so you can review the result.\n\n"
        )
    else:
        intro = (
            "Automatic installers are currently available on Windows only. Install `fd` with your platform's "
            "package manager, or use **Settings** to select an existing `fd`/`fdfind` executable.\n\n"
        )

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "page": page("fd:install", "Install fd", root=True),
            "elementId": "fd-installer",
            "placeholder": "Install fd to begin searching",
            "actions": [
                {"id": "check_fd", "title": "Check for fd again", "icon": "refresh", "shortcut": "ctrl+r"},
                {"id": "settings", "title": "Choose an executable", "icon": "settings"},
                {"id": "open_fd_docs", "title": "Open fd installation guide", "icon": "globe"},
            ],
            "floatingAction": [
                {"id": "check_fd", "title": "Check again", "icon": "refresh"},
                {"id": "settings", "title": "Settings", "icon": "settings"},
            ],
            "detail": {
                "wide": True,
                "markdown": (
                    "# `fd` is required\n\n"
                    "The plugin itself is ready, but the `fd` executable was not found.\n\n"
                    f"{intro}"
                    "After installation, reopen Tabame and type **`fd`** again."
                ),
                "metadata": metadata,
            },
        }
    )


def launch_visible_installer(action: str) -> None:
    installer = INSTALL_COMMANDS.get(action)
    if installer is None:
        return
    if os.name != "nt":
        # //TODO: Implement multiplatform
        command("toast", text="Automatic fd installation is currently available on Windows only.", style="error")
        return

    manager, install_command = installer
    try:
        command_prompt = os.path.expandvars(r"%SystemRoot%\System32\cmd.exe")
        os.startfile(
            command_prompt,
            "open",
            arguments=f'/d /k "{install_command}"',
            cwd=os.path.expandvars(r"%USERPROFILE%"),
            show_cmd=1,
        )
        command("hide")
    except OSError as exc:
        log(f"Could not launch {manager} installer:", exc)
        render_fd_installer(0, launch_error=str(exc))


def render_help(rev: int = 0, *, history: str = "push") -> None:
    STATE["screen"] = "help"
    settings = STATE["settings"]
    include_text = ", ".join(settings["includes"]) or "none"
    exclude_text = ", ".join(settings["excludes"]) or "none"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "page": page("fd:help", "Using fd File Search", history),
            "elementId": "fd-help",
            "placeholder": "fd search help",
            "actions": [{"id": "settings", "title": "Search settings", "icon": "settings"}],
            "floatingAction": {"id": "settings", "title": "Settings", "icon": "settings"},
            "detail": {
                "wide": True,
                "markdown": (
                    "# Fast file search with `fd`\n\n"
                    "Type **`fd`**, a space, then part of a filename. Searches are cancelled and restarted "
                    "as you type, so old results never replace a newer query.\n\n"
                    "## Result keys\n\n"
                    "- **Enter** opens the selected file or folder and closes the launcher.\n"
                    "- **Ctrl+K** offers Open folder, Copy path, Copy name, and Paste path.\n"
                    "- **Ctrl+R** reruns the current search.\n"
                    "- **Ctrl+Shift+S** opens settings.\n\n"
                    "## Filter rules\n\n"
                    "A simple name such as `node_modules` matches that path segment. An extension such as "
                    "`.dll` matches files ending in it. Globs such as `*.generated.dart` are also accepted. "
                    "Include rules use **OR** semantics; excludes always win.\n\n"
                    "Literal mode uses fd's smart-case substring matching. Glob and regular-expression modes "
                    "pass the query through to fd unchanged."
                ),
                "metadata": [
                    {"label": "Search roots", "text": str(len(settings["roots"])), "icon": "folder"},
                    {"label": "Query mode", "text": settings["mode"], "icon": "search"},
                    {"label": "Include rules", "text": include_text, "icon": "check"},
                    {"label": "Exclude rules", "text": exclude_text, "icon": "close"},
                    {"separator": True},
                    {"label": "fd project", "text": "github.com/sharkdp/fd", "url": "https://github.com/sharkdp/fd"},
                ],
            },
        }
    )


def fd_exclude_rule(rule: str) -> str:
    if rule.startswith(".") and not any(char in rule for char in "*/?[]\\"):
        return f"*{rule}"
    return rule.replace("\\", "/")


def include_extensions(rules: list[str]) -> list[str]:
    """Return extension names when every include rule is extension-only."""
    extensions: list[str] = []
    for rule in rules:
        candidate = rule.strip()
        if candidate.startswith("*.") and not any(char in candidate[2:] for char in "*/?[]\\"):
            candidate = candidate[1:]
        if not candidate.startswith(".") or len(candidate) == 1:
            return []
        if any(char in candidate[1:] for char in "*/?[]\\"):
            return []
        extensions.append(candidate[1:].casefold())
    return extensions


def matches_filter(path: str, rule: str) -> bool:
    normalized = path.replace("\\", "/").casefold()
    filename = normalized.rsplit("/", 1)[-1]
    candidate = rule.strip().replace("\\", "/").casefold()
    if not candidate:
        return False
    if candidate.startswith(".") and not any(char in candidate for char in "*/?[]"):
        return filename.endswith(candidate)
    if any(char in candidate for char in "*?["):
        return (
            fnmatch.fnmatchcase(filename, candidate)
            or fnmatch.fnmatchcase(normalized, candidate)
            or fnmatch.fnmatchcase(normalized, f"*/{candidate}")
        )
    if "/" in candidate:
        needle = candidate.strip("/")
        return f"/{needle}/" in f"/{normalized.strip('/')}/" or normalized.endswith(f"/{needle}")
    return candidate in [part for part in normalized.split("/") if part]


def path_root(path: str, roots: list[str]) -> str:
    best = roots[0]
    best_length = -1
    for root in roots:
        try:
            common = os.path.normcase(os.path.commonpath([path, root]))
            if common == os.path.normcase(os.path.commonpath([root])):
                length = len(os.path.normcase(root))
                if length > best_length:
                    best = root
                    best_length = length
        except ValueError:
            continue
    return best


def root_label(root: str) -> str:
    drive, _ = os.path.splitdrive(root)
    name = os.path.basename(os.path.normpath(root))
    if not name:
        return drive + os.sep if drive else root
    return f"{name} · {drive}" if drive else name


def icon_for(path: str, is_dir: bool) -> str:
    if is_dir:
        return "folder"
    extension = Path(path).suffix.casefold()
    if extension in {".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg", ".ico"}:
        return "image"
    if extension in {".mp3", ".wav", ".flac", ".aac", ".ogg", ".m4a"}:
        return "music"
    if extension in {".mp4", ".mkv", ".avi", ".mov", ".webm"}:
        return "video"
    if extension in {".py", ".js", ".ts", ".dart", ".rs", ".go", ".java", ".cpp", ".c", ".h", ".cs"}:
        return "code"
    if extension in {".md", ".txt", ".pdf", ".doc", ".docx", ".rtf"}:
        return "document"
    if extension in {".zip", ".7z", ".rar", ".tar", ".gz"}:
        return "download"
    return "file"


def markdown_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace("`", "\\`").replace("*", "\\*").replace("_", "\\_")


def result_rank(record: dict[str, Any], query: str, mode: str) -> tuple[Any, ...]:
    name = record["name"].casefold()
    stem = Path(record["name"]).stem.casefold()
    q = query.casefold()
    if mode != "literal":
        return (len(name), name, record["path"].casefold())
    if name == q:
        bucket = 0
    elif stem == q:
        bucket = 1
    elif name.startswith(q):
        bucket = 2
    elif any(part.startswith(q) for part in name.replace("-", " ").replace("_", " ").split()):
        bucket = 3
    else:
        bucket = 4
    return (bucket, len(name), name, len(record["path"]), record["path"].casefold())


def item_from_record(record: dict[str, Any]) -> dict[str, Any]:
    path = record["path"]
    name = record["name"]
    parent = os.path.dirname(path)
    is_dir = record["is_dir"]
    extension = Path(name).suffix[1:] if Path(name).suffix else ""
    accessories = [{"text": "Folder" if is_dir else (extension.upper() if extension else "File")}]
    return {
        "id": path,
        "title": name,
        "subtitle": parent,
        "icon": icon_for(path, is_dir),
        "section": root_label(record["root"]),
        "lines": 1,
        "accessories": accessories,
        "actions": [
            {"id": "default", "title": "Open", "icon": "open"},
            {"id": "open_parent", "title": "Open containing folder", "icon": "folder", "shortcut": "ctrl+shift+o"},
            {"id": "copy_path", "title": "Copy full path", "icon": "copy", "shortcut": "ctrl+shift+c"},
            {"id": "copy_name", "title": "Copy file name", "icon": "document"},
            {"id": "copy_parent", "title": "Copy containing folder", "icon": "folder"},
            {"id": "paste_path", "title": "Paste path into previous app", "icon": "paste"},
        ],
        "preview": {
            "markdown": f"### {markdown_escape(name)}\n\nPress **Enter** to open this {'folder' if is_dir else 'file'}.",
            "metadata": [
                {"label": "Full path", "text": path, "icon": "file" if not is_dir else "folder"},
                {"label": "Containing folder", "text": parent, "icon": "folder"},
                {"label": "Type", "text": "Folder" if is_dir else (f".{extension} file" if extension else "File")},
                {"label": "Search root", "text": record["root"], "icon": "search"},
            ],
        },
    }


def render_results(rev: int, query: str, records: list[dict[str, Any]], limited: bool) -> None:
    if not records:
        settings = STATE["settings"]
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "list",
                "page": page("fd:search", "fd · No matches", root=True),
                "elementId": "fd-results",
                "placeholder": "Try a shorter filename or different filters",
                "empty": {
                    "icon": "search",
                    "title": f"No matches for “{query}”",
                    "hint": root_summary(settings),
                    "action": {"id": "settings", "title": "Review filters", "icon": "settings"},
                },
                "actions": SEARCH_ACTIONS,
                "floatingAction": {"id": "settings", "title": "Settings", "icon": "settings"},
                "items": [],
            }
        )
        return

    items = [item_from_record(record) for record in records]
    with STATE_LOCK:
        STATE["results"] = records
        STATE["items"] = {item["id"]: record for item, record in zip(items, records)}
    count_text = f"{len(items)}+ matches" if limited else f"{len(items)} match{'es' if len(items) != 1 else ''}"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": page("fd:search", f"fd · {count_text}", root=True),
            "elementId": "fd-results",
            "placeholder": "Search filenames…",
            "preview": {"enabled": True, "wide": True},
            "actions": SEARCH_ACTIONS,
            "floatingAction": {"id": "settings", "title": "Settings", "icon": "settings"},
            "items": items,
        }
    )


def terminate_process(process: subprocess.Popen[bytes] | None) -> None:
    if process is None or process.poll() is not None:
        return
    try:
        process.terminate()
    except OSError:
        pass


def cancel_search() -> int:
    with STATE_LOCK:
        STATE["search_serial"] += 1
        serial = STATE["search_serial"]
        process = STATE.get("active_process")
        STATE["active_process"] = None
    terminate_process(process)
    return serial


def build_fd_command(executable: str, query: str, settings: dict[str, Any]) -> list[str]:
    args = [executable, "--absolute-path", "--color=never", "--print0"]
    if settings["mode"] == "literal":
        args.append("--fixed-strings")
    elif settings["mode"] == "glob":
        args.append("--glob")
    if settings["item_type"] == "files":
        args.extend(["--type", "file"])
    elif settings["item_type"] == "folders":
        args.extend(["--type", "directory"])
    if settings["hidden"]:
        args.append("--hidden")
    if settings["ignored"]:
        args.append("--no-ignore")
    if settings["follow"]:
        args.append("--follow")
    if settings["full_path"]:
        args.append("--full-path")
    for extension in include_extensions(settings["includes"]):
        args.extend(["--extension", extension])
    for rule in settings["excludes"]:
        args.extend(["--exclude", fd_exclude_rule(rule)])
    args.extend(["--", query, *settings["roots"]])
    return args


def run_search(serial: int, rev: int, query: str, settings: dict[str, Any], executable: str) -> None:
    process: subprocess.Popen[bytes] | None = None
    stopped_for_limit = False
    try:
        args = build_fd_command(executable, query, settings)
        log("fd search:", args)
        process = subprocess.Popen(
            args,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            creationflags=NO_WINDOW,
        )
        with STATE_LOCK:
            if serial != STATE["search_serial"] or STATE["closing"]:
                terminate_process(process)
                return
            STATE["active_process"] = process

        assert process.stdout is not None
        assert process.stderr is not None
        stderr_buffer = bytearray()

        def drain_stderr() -> None:
            while True:
                chunk = process.stderr.read(8192)
                if not chunk:
                    return
                # Keep the UI error useful without retaining unbounded diagnostics.
                if len(stderr_buffer) < 65536:
                    stderr_buffer.extend(chunk[: 65536 - len(stderr_buffer)])

        stderr_thread = threading.Thread(target=drain_stderr, name=f"fd-stderr-{serial}", daemon=True)
        stderr_thread.start()
        accepted: list[dict[str, Any]] = []
        seen: set[str] = set()
        pending = b""
        display_limit = settings["max_results"]
        scan_limit = min(3000, max(display_limit * 5, display_limit + 400))

        while True:
            with STATE_LOCK:
                current = serial == STATE["search_serial"] and not STATE["closing"]
            if not current:
                terminate_process(process)
                return
            chunk = process.stdout.read(65536)
            if not chunk:
                break
            pending += chunk
            parts = pending.split(b"\0")
            pending = parts.pop()
            for raw_path in parts:
                if not raw_path:
                    continue
                path = os.path.normpath(os.fsdecode(raw_path))
                key = os.path.normcase(path)
                if key in seen:
                    continue
                if settings["includes"] and not any(matches_filter(path, rule) for rule in settings["includes"]):
                    continue
                if any(matches_filter(path, rule) for rule in settings["excludes"]):
                    continue
                seen.add(key)
                if settings["item_type"] == "folders":
                    is_dir = True
                elif settings["item_type"] == "files":
                    is_dir = False
                else:
                    is_dir = os.path.isdir(path)
                accepted.append(
                    {
                        "path": path,
                        "name": os.path.basename(path) or path,
                        "root": path_root(path, settings["roots"]),
                        "is_dir": is_dir,
                    }
                )
                if len(accepted) >= scan_limit:
                    stopped_for_limit = True
                    terminate_process(process)
                    break
            if stopped_for_limit:
                break

        return_code = process.wait()
        stderr_thread.join(timeout=1)
        error_text = bytes(stderr_buffer).decode("utf-8", errors="replace").strip()

        with STATE_LOCK:
            current = serial == STATE["search_serial"] and not STATE["closing"]
            if STATE.get("active_process") is process:
                STATE["active_process"] = None
        if not current:
            return
        if return_code != 0 and not stopped_for_limit:
            with STATE_LOCK:
                if serial == STATE["search_serial"] and not STATE["closing"]:
                    render_search_error(
                        rev,
                        "fd could not run this search",
                        error_text or f"fd exited with code {return_code}.",
                    )
            return
        if error_text:
            log("fd warning:", error_text)

        accepted.sort(key=lambda record: result_rank(record, query, settings["mode"]))
        limited = len(accepted) > display_limit or stopped_for_limit
        with STATE_LOCK:
            if serial == STATE["search_serial"] and not STATE["closing"]:
                render_results(rev, query, accepted[:display_limit], limited)
    except FileNotFoundError:
        with STATE_LOCK:
            if serial == STATE["search_serial"] and not STATE["closing"]:
                render_fd_installer(rev)
    except Exception as exc:
        log("search failed:", repr(exc))
        with STATE_LOCK:
            if serial == STATE["search_serial"] and not STATE["closing"]:
                render_search_error(rev, "The search failed", str(exc))
    finally:
        with STATE_LOCK:
            if STATE.get("active_process") is process:
                STATE["active_process"] = None


def start_search(rev: int, text: str, *, history: str = "none") -> None:
    query = text.strip()
    STATE["current_query"] = text
    serial = cancel_search()
    with STATE_LOCK:
        STATE["results"] = []
        STATE["items"] = {}
    if not query:
        render_search_prompt(rev, history=history)
        return

    settings = copy.deepcopy(STATE["settings"])
    executable = resolve_executable(settings["executable"])
    if executable is None:
        render_fd_installer(rev)
        return
    missing_roots = [root for root in settings["roots"] if not os.path.isdir(root)]
    if missing_roots:
        render_search_error(rev, "A search root is unavailable", missing_roots[0])
        return

    render_loading(rev, query, history=history)
    threading.Thread(
        target=run_search,
        args=(serial, rev, query, settings, executable),
        name=f"fd-search-{serial}",
        daemon=True,
    ).start()


def validate_form(values: dict[str, Any]) -> tuple[dict[str, Any] | None, dict[str, str]]:
    errors: dict[str, str] = {}
    try:
        roots = roots_from_values(values.get("roots", ""), values.get("quick_root", ""))
    except (OSError, ValueError) as exc:
        roots = []
        errors["roots"] = str(exc)
    if not roots:
        errors["roots"] = "Add at least one drive or folder."
    else:
        missing = [root for root in roots if not os.path.isdir(root)]
        if missing:
            errors["roots"] = f"Folder does not exist or is unavailable: {missing[0]}"

    executable_value = str(values.get("executable", "fd")).strip().strip('"') or "fd"
    if resolve_executable(executable_value) is None:
        errors["executable"] = "fd was not found. Install it or select the full path to fd.exe."
    try:
        max_results = int(values.get("max_results", 150))
        if not 20 <= max_results <= 500:
            raise ValueError
    except (TypeError, ValueError):
        max_results = 150
        errors["max_results"] = "Choose a value from 20 to 500."

    if errors:
        return None, errors
    settings = sanitized_settings(
        {
            "configured": True,
            "executable": executable_value,
            "roots": roots,
            "includes": split_rules(values.get("includes", "")),
            "excludes": split_rules(values.get("excludes", "")),
            "mode": values.get("mode", "literal"),
            "item_type": values.get("item_type", "files"),
            "max_results": max_results,
            "hidden": values.get("hidden", False),
            "ignored": values.get("ignored", False),
            "follow": values.get("follow", False),
            "full_path": values.get("full_path", False),
        }
    )
    return settings, {}


def handle_settings_submit(values: dict[str, Any]) -> None:
    settings, errors = validate_form(values)
    if errors:
        preview = copy.deepcopy(STATE["settings"])
        preview.update(
            {
                "executable": str(values.get("executable", preview["executable"])),
                "includes": split_rules(values.get("includes", "")),
                "excludes": split_rules(values.get("excludes", "")),
                "mode": values.get("mode", preview["mode"]),
                "item_type": values.get("item_type", preview["item_type"]),
                "hidden": bool(values.get("hidden", False)),
                "ignored": bool(values.get("ignored", False)),
                "follow": bool(values.get("follow", False)),
                "full_path": bool(values.get("full_path", False)),
            }
        )
        try:
            preview["roots"] = roots_from_values(values.get("roots", ""), values.get("quick_root", ""))
        except (OSError, ValueError):
            pass
        try:
            preview["max_results"] = int(values.get("max_results", preview["max_results"]))
        except (TypeError, ValueError):
            pass
        old_settings = STATE["settings"]
        STATE["settings"] = preview
        render_settings(0, history="none", errors=errors, first_run=not old_settings.get("configured", False))
        STATE["settings"] = old_settings
        return

    assert settings is not None
    STATE["settings"] = settings
    save_settings()
    command("toast", text="fd search settings saved", style="success")
    start_search(0, STATE["current_query"], history="replace")


def handle_action(item_id: str, action: str) -> None:
    if not item_id:
        if action in INSTALL_COMMANDS:
            launch_visible_installer(action)
        elif action == "settings":
            cancel_search()
            render_settings(0, first_run=not STATE["settings"].get("configured", False))
        elif action == "help":
            cancel_search()
            render_help()
        elif action == "refresh":
            start_search(0, STATE["current_query"])
        elif action == "check_fd":
            check_fd_again()
        elif action == "open_fd_docs":
            command("open", url="https://github.com/sharkdp/fd#installation")
        return

    record = STATE["items"].get(item_id)
    if not record:
        return
    path = record["path"]
    parent = os.path.dirname(path)
    if action == "default":
        command("open", path=path)
        command("hide")
    elif action == "open_parent":
        command("open", path=parent)
        command("hide")
    elif action == "copy_path":
        command("copy", text=path)
    elif action == "copy_name":
        command("copy", text=record["name"])
    elif action == "copy_parent":
        command("copy", text=parent)
    elif action == "paste_path":
        command("paste", text=path)


def return_to_search(rev: int = 0) -> None:
    start_search(rev, STATE["current_query"])


def check_fd_again() -> None:
    settings = STATE["settings"]
    if resolve_executable(settings["executable"]) is None:
        render_fd_installer(0)
    elif settings.get("configured", False):
        command("toast", text="fd is ready", style="success")
        start_search(0, STATE["current_query"])
    else:
        command("toast", text="fd is ready — choose your search locations", style="success")
        render_settings(0, history="replace", first_run=True)


def handle_storage(message: dict[str, Any]) -> None:
    if message.get("requestId") != SETTINGS_REQUEST_ID:
        return
    raw_value = message.get("value")
    settings = default_settings()
    if raw_value:
        try:
            decoded = json.loads(raw_value) if isinstance(raw_value, str) else raw_value
            settings = sanitized_settings(decoded)
        except (json.JSONDecodeError, TypeError, ValueError) as exc:
            log("Could not decode stored settings:", exc)
    STATE["settings"] = settings
    STATE["loaded"] = True
    if resolve_executable(settings["executable"]) is None:
        render_fd_installer(0)
    elif settings["configured"]:
        start_search(0, STATE["current_query"])
    else:
        render_settings(0, history="none", first_run=True)


def handle_message(message: dict[str, Any]) -> bool:
    kind = message.get("type")
    if kind == "close":
        with STATE_LOCK:
            STATE["closing"] = True
        cancel_search()
        return False
    if kind == "init":
        STATE["current_query"] = str(message.get("query", ""))
        render_boot(0)
        command("storage", op="get", key=SETTINGS_KEY, requestId=SETTINGS_REQUEST_ID)
    elif kind == "query":
        STATE["current_query"] = str(message.get("text", ""))
        if STATE["loaded"] and STATE["screen"] == "search":
            start_search(int(message.get("rev", 0)), STATE["current_query"])
    elif kind == "storage":
        handle_storage(message)
    elif kind == "submit" and STATE["screen"] == "settings":
        handle_settings_submit(message.get("values") or {})
    elif kind == "action":
        handle_action(str(message.get("id", "")), str(message.get("action", "default")))
    elif kind == "back":
        target = message.get("toPageId")
        if target == "fd:settings":
            render_settings(int(message.get("rev", 0)), history="none")
        elif target == "fd:help":
            render_help(int(message.get("rev", 0)), history="none")
        else:
            return_to_search(int(message.get("rev", 0)))
    elif kind == "navigate":
        target = message.get("targetPageId")
        if target == "fd:settings":
            render_settings(int(message.get("rev", 0)), history="none")
        elif target == "fd:help":
            render_help(int(message.get("rev", 0)), history="none")
        else:
            return_to_search(int(message.get("rev", 0)))
    return True


def main() -> None:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
            if isinstance(message, dict) and not handle_message(message):
                break
        except json.JSONDecodeError:
            log("Ignored malformed JSON from host")
        except Exception as exc:
            log("Message handler failed:", repr(exc))
            send(
                {
                    "type": "render",
                    "rev": int(message.get("rev", 0)) if isinstance(message, dict) else 0,
                    "view": "detail",
                    "detail": {"markdown": f"# fd plugin error\n\n```\n{exc}\n```"},
                }
            )
    with STATE_LOCK:
        STATE["closing"] = True
    cancel_search()


if __name__ == "__main__":
    main()
