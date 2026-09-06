#!/usr/bin/env python3
"""Rich Tabame launcher plugin for yt-dlp.

The plugin deliberately has no Python dependencies.  Tabame supplies the UI
protocol; yt-dlp and (optionally) ffmpeg are discovered from the user's PATH or
from paths selected in Settings.
"""

from __future__ import annotations

import datetime as datetime_module
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import threading
import time
import uuid
from collections import deque
from typing import Any


PLUGIN_NAME = "yt-dlp Downloader"
BACKGROUND_GRACE_SECONDS = 300
PROGRESS_PREFIX = "TBM_YTDLP_PROGRESS|"
INFO_PREFIX = "TBM_YTDLP_INFO|"
FILE_PREFIX = "TBM_YTDLP_FILE|"

SEND_LOCK = threading.Lock()
STATE_LOCK = threading.RLock()

UI_CLOSED = False
STORAGE_REQUESTED = False
STORAGE_LOADED = {"settings": False, "history": False}
SETTINGS_DIRTY = False
HISTORY_DIRTY = False
HISTORY_MERGE_PENDING = False
ACTIVE_JOB = None
LAST_RESULT = None
STARTUP_UPDATE_PENDING = False
STARTUP_UPDATE_STARTED = False


def default_download_folder() -> str:
    """Choose a useful cross-platform default without touching the filesystem."""

    home = Path.home()
    downloads = home / "Downloads"
    return str(downloads if downloads.exists() else home)


DEFAULT_DOWNLOAD_VALUES = {
    "mode": "video",
    "video_quality": "best",
    "video_container": "mp4",
    "audio_format": "mp3",
    "audio_quality": "192K",
    "custom_format": "",
    "embed_thumbnail": True,
    "write_thumbnail": False,
    "embed_metadata": True,
    "embed_chapters": False,
    "embed_subs": False,
    "write_subs": False,
    "auto_subs": False,
    "sub_langs": "en.*",
    "sponsor_block": False,
    "playlist": False,
    "cookies_browser": "none",
    "restrict_filenames": False,
    "rate_limit": "",
    "concurrent_fragments": 4,
    "output_template": "%(title)s [%(id)s].%(ext)s",
    "custom_args": "",
    "open_when_done": False,
}

SETTINGS = {
    "executable": "",
    "ffmpeg": "",
    "download_folder": default_download_folder(),
    "notifications": True,
    "auto_open": False,
    "update_on_open": True,
    "defaults": dict(DEFAULT_DOWNLOAD_VALUES),
}

HISTORY = []
TOOL_INFO = {
    "path": None,
    "version": None,
    "checking": False,
    "error": None,
}

STATE = {
    "screen": "home",
    "route_stack": ["ytdlp:home"],
    "query": "",
    "form_values": {},
    "detail_id": None,
    "history_status_filter": [],
    "history_sort": "finished",
    "history_direction": "desc",
    "selected_id": None,
}


def log(message: str) -> None:
    """Write diagnostics to stderr; stdout is reserved for protocol messages."""

    print(message, file=sys.stderr, flush=True)


def send(payload: dict[str, Any]) -> None:
    """Send exactly one flushed JSON object to Tabame."""

    try:
        line = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        with SEND_LOCK:
            sys.stdout.write(line + "\n")
            sys.stdout.flush()
    except (BrokenPipeError, OSError):
        # The launcher may have disappeared while a background worker was
        # finishing.  A notification attempt should not crash the worker.
        pass


def command(name: str, **fields: Any) -> None:
    send({"type": "command", "command": name, **fields})


def page(
    page_id: str,
    title: str,
    history: str = "none",
    breadcrumbs: list[dict[str, str]] | None = None,
) -> dict[str, Any]:
    result = {
        "id": page_id,
        "title": title,
        "history": history,
        "preserveState": True,
    }
    if breadcrumbs:
        result["breadcrumbs"] = breadcrumbs
    return result


def is_ui_closed() -> bool:
    with STATE_LOCK:
        return UI_CLOSED


def set_ui_closed(value: bool) -> None:
    global UI_CLOSED
    with STATE_LOCK:
        UI_CLOSED = value


def safe_text(value: Any, fallback: str = "") -> str:
    if value is None:
        return fallback
    return str(value)


def md_code(value: Any) -> str:
    return "`" + safe_text(value).replace("`", "'") + "`"


def truncate(value: Any, limit: int = 120) -> str:
    text = safe_text(value)
    if len(text) <= limit:
        return text
    return text[: max(0, limit - 3)].rstrip() + "..."


def iso_now() -> str:
    return datetime_module.datetime.now(datetime_module.timezone.utc).isoformat()


def parse_iso(value: Any) -> datetime_module.datetime | None:
    text = safe_text(value).strip()
    if not text:
        return None
    try:
        parsed = datetime_module.datetime.fromisoformat(text.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=datetime_module.timezone.utc)
        return parsed
    except ValueError:
        return None


def human_bytes(value: Any) -> str:
    try:
        amount = float(value)
    except (TypeError, ValueError):
        return "Unknown"
    if amount < 1024:
        return f"{int(amount)} B"
    for unit in ("KB", "MB", "GB", "TB"):
        amount /= 1024
        if amount < 1024 or unit == "TB":
            return f"{amount:.1f} {unit}"
    return "Unknown"


def human_duration(seconds: Any) -> str:
    try:
        total = max(0, int(float(seconds)))
    except (TypeError, ValueError):
        return "Unknown"
    hours, remainder = divmod(total, 3600)
    minutes, secs = divmod(remainder, 60)
    if hours:
        return f"{hours}h {minutes:02d}m {secs:02d}s"
    if minutes:
        return f"{minutes}m {secs:02d}s"
    return f"{secs}s"


def status_label(status: str) -> str:
    return {
        "success": "Completed",
        "error": "Failed",
        "cancelled": "Cancelled",
        "downloading": "Downloading",
        "queued": "Queued",
    }.get(status, status.title() if status else "Unknown")


def status_icon(status: str) -> str:
    return {
        "success": "check",
        "error": "error",
        "cancelled": "close",
        "downloading": "download",
        "queued": "clock",
    }.get(status, "download")


def status_color(status: str) -> str:
    return {
        "success": "#22C55E",
        "error": "#EF4444",
        "cancelled": "#94A3B8",
        "downloading": "#63A0EA",
        "queued": "#F59E0B",
    }.get(status, "#94A3B8")


def safe_json_load(value: Any, fallback: Any) -> Any:
    if isinstance(value, (dict, list)):
        return value
    if not isinstance(value, str) or not value.strip():
        return fallback
    try:
        return json.loads(value)
    except (TypeError, ValueError):
        return fallback


# ---------------------------------------------------------------------------
# Persistent state through Tabame storage


def merge_settings(data: Any) -> None:
    if not isinstance(data, dict):
        return
    for key in ("executable", "ffmpeg", "download_folder"):
        if isinstance(data.get(key), str):
            SETTINGS[key] = data[key]
    for key in ("notifications", "auto_open", "update_on_open"):
        if isinstance(data.get(key), bool):
            SETTINGS[key] = data[key]
    stored_defaults = data.get("defaults")
    if isinstance(stored_defaults, dict):
        for key in DEFAULT_DOWNLOAD_VALUES:
            if key in stored_defaults:
                SETTINGS["defaults"][key] = stored_defaults[key]
    if not safe_text(SETTINGS.get("download_folder")).strip():
        SETTINGS["download_folder"] = default_download_folder()


def merge_history(data: Any, preserve_current: bool = False) -> None:
    if not isinstance(data, list):
        return
    cleaned = []
    for record in data:
        if not isinstance(record, dict):
            continue
        if not record.get("id"):
            record["id"] = f"history-{uuid.uuid4().hex[:12]}"
        cleaned.append(record)
    if preserve_current:
        current_ids = {safe_text(record.get("id")) for record in HISTORY}
        cleaned = [record for record in cleaned if safe_text(record.get("id")) not in current_ids]
        combined = list(HISTORY) + cleaned
        combined.sort(key=lambda record: safe_text(record.get("finished_at")), reverse=True)
        del HISTORY[:]
        HISTORY.extend(combined[:50])
        return
    del HISTORY[:]
    HISTORY.extend(cleaned[:50])


def request_storage() -> None:
    global STORAGE_REQUESTED
    if STORAGE_REQUESTED:
        return
    STORAGE_REQUESTED = True
    command("storage", op="get", key="settings", requestId="ytdlp-settings")
    command("storage", op="get", key="history", requestId="ytdlp-history")


def persist_settings() -> None:
    global SETTINGS_DIRTY
    SETTINGS_DIRTY = True
    settings_payload = {
        "executable": SETTINGS["executable"],
        "ffmpeg": SETTINGS["ffmpeg"],
        "download_folder": SETTINGS["download_folder"],
        "notifications": SETTINGS["notifications"],
        "auto_open": SETTINGS["auto_open"],
        "update_on_open": SETTINGS["update_on_open"],
        "defaults": SETTINGS["defaults"],
    }
    command(
        "storage",
        op="set",
        key="settings",
        value=json.dumps(settings_payload, ensure_ascii=False),
    )


def persist_history(preserve_current: bool = False) -> None:
    global HISTORY_DIRTY, HISTORY_MERGE_PENDING
    HISTORY_DIRTY = True
    HISTORY_MERGE_PENDING = preserve_current
    command(
        "storage",
        op="set",
        key="history",
        value=json.dumps(HISTORY[:50], ensure_ascii=False),
    )
def handle_storage(message: dict[str, Any]) -> None:
    request_id = safe_text(message.get("requestId"))
    settings_loaded = False
    if request_id == "ytdlp-settings":
        if not STORAGE_LOADED["settings"] and not SETTINGS_DIRTY:
            merge_settings(safe_json_load(message.get("value"), {}))
        STORAGE_LOADED["settings"] = True
        settings_loaded = True
    elif request_id == "ytdlp-history":
        if not STORAGE_LOADED["history"]:
            stored_history = safe_json_load(message.get("value"), [])
            if not HISTORY_DIRTY:
                merge_history(stored_history)
            elif HISTORY_MERGE_PENDING:
                merge_history(stored_history, preserve_current=True)
        STORAGE_LOADED["history"] = True
    else:
        return
    if settings_loaded:
        # The first probe may have started before Tabame returned persisted
        # settings. Re-check now so a custom executable is never skipped.
        refresh_tool_async(startup=True)
    if not is_ui_closed() and STATE["screen"] == "home":
        render_home(0)


# ---------------------------------------------------------------------------
# Tool discovery


def resolve_executable(raw_value: Any = None) -> str | None:
    raw = safe_text(SETTINGS["executable"] if raw_value is None else raw_value).strip()
    if not raw:
        return shutil.which("yt-dlp")
    expanded = os.path.expandvars(os.path.expanduser(raw))
    looks_like_path = any(separator in expanded for separator in ("/", "\\")) or Path(expanded).is_absolute()
    if looks_like_path:
        candidate = Path(expanded)
        if candidate.is_file():
            try:
                return str(candidate.resolve())
            except OSError:
                return str(candidate)
        return None
    return shutil.which(expanded)


def process_options() -> dict[str, Any]:
    options: dict[str, Any] = {
        "text": True,
        "encoding": "utf-8",
        "errors": "replace",
        "bufsize": 1,
    }
    if os.name == "nt":
        options["creationflags"] = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    return options


def probe_tool(raw_executable: Any = None) -> dict[str, Any]:
    path = resolve_executable(raw_executable)
    if not path:
        configured = safe_text(SETTINGS["executable"] if raw_executable is None else raw_executable).strip()
        message = "The configured yt-dlp executable was not found." if configured else "yt-dlp was not found on PATH."
        return {"path": None, "version": None, "error": message}
    try:
        result = subprocess.run(
            [path, "--version"],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            timeout=8,
            **process_options(),
        )
        output = (result.stdout or "").strip()
        error = (result.stderr or "").strip()
        if result.returncode != 0:
            return {
                "path": path,
                "version": None,
                "error": truncate(error or f"yt-dlp exited with code {result.returncode}.", 240),
            }
        return {"path": path, "version": output.splitlines()[0] if output else "Detected", "error": None}
    except (OSError, subprocess.SubprocessError) as exc:
        return {"path": path, "version": None, "error": truncate(str(exc), 240)}


def refresh_tool_async(startup: bool = False) -> None:
    global STARTUP_UPDATE_PENDING
    with STATE_LOCK:
        if startup:
            STARTUP_UPDATE_PENDING = True
        if TOOL_INFO["checking"]:
            return
        TOOL_INFO["checking"] = True
        requested_executable = SETTINGS["executable"]

    def worker() -> None:
        global STARTUP_UPDATE_PENDING, STARTUP_UPDATE_STARTED
        result = probe_tool(requested_executable)
        should_update = False
        stale_startup_check = False
        with STATE_LOCK:
            TOOL_INFO.update(result)
            TOOL_INFO["checking"] = False
            current_executable = SETTINGS["executable"]
            stale_startup_check = startup and current_executable != requested_executable
            if startup and STARTUP_UPDATE_PENDING and not stale_startup_check and STORAGE_LOADED["settings"]:
                if SETTINGS["update_on_open"] and result.get("version") and not STARTUP_UPDATE_STARTED:
                    STARTUP_UPDATE_STARTED = True
                    should_update = True
                STARTUP_UPDATE_PENDING = False
        if stale_startup_check and not is_ui_closed():
            refresh_tool_async(startup=True)
            return
        if should_update and not is_ui_closed():
            start_update(automatic=True)
            return
        if not is_ui_closed() and STATE["screen"] in {"home", "settings"}:
            if STATE["screen"] == "home":
                render_home(0)
            else:
                render_settings()

    threading.Thread(target=worker, name="ytdlp-tool-check", daemon=True).start()


def tool_status_text() -> str:
    if TOOL_INFO["checking"]:
        return "Checking..."
    if TOOL_INFO["version"]:
        return f"yt-dlp {TOOL_INFO['version']}"
    return "Not detected"


def render_tool_details(rev: int = 0, history: str = "replace") -> None:
    path = TOOL_INFO["path"] or "Not found"
    error = TOOL_INFO["error"] or ""
    markdown = (
        "# yt-dlp setup\n\n"
        "The plugin runs the `yt-dlp` command directly and never passes user URLs "
        "through a shell.\n\n"
        f"**Executable:** {md_code(path)}\n\n"
        f"**Version:** {md_code(TOOL_INFO['version'] or 'Not detected')}\n\n"
        f"**On open:** {md_code('Check and update' if SETTINGS['update_on_open'] else 'Check only')}\n\n"
        "Install yt-dlp and make sure it is available on PATH, or choose a custom "
        "executable in Settings. FFmpeg is only needed for merging, extraction, "
        "and post-processing."
    )
    if error:
        markdown += f"\n\n> {error.replace(chr(10), ' ')}"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "page": page("ytdlp:tools", "yt-dlp setup", history, [{"id": "ytdlp:home", "label": "Home"}]),
            "detail": {"wide": True, "markdown": markdown},
            "actions": [
                {"id": "retry-tools", "title": "Check again", "icon": "refresh"},
                {"id": "settings", "title": "Open Settings", "icon": "settings"},
                {"id": "home", "title": "Back to Home", "icon": "home"},
            ],
            "floatingAction": {"id": "retry-tools", "title": "Check again", "icon": "refresh"},
        }
    )


# ---------------------------------------------------------------------------
# Form definitions


def form_values_with_defaults(seed: str = "") -> dict[str, Any]:
    values = dict(DEFAULT_DOWNLOAD_VALUES)
    values.update(SETTINGS.get("defaults", {}))
    values["urls"] = seed
    values["download_folder"] = SETTINGS["download_folder"]
    values["open_when_done"] = SETTINGS["auto_open"]
    return values


def option(value: str, label: str) -> dict[str, str]:
    return {"value": value, "label": label}


def download_fields(values: dict[str, Any], error_field: str | None = None, error_message: str | None = None) -> list[dict[str, Any]]:
    fields: list[dict[str, Any]] = [
        {
            "id": "urls",
            "type": "textarea",
            "label": "Source URLs or search phrases",
            "placeholder": "https://... or a YouTube search phrase",
            "description": "One per line. Plain text becomes a YouTube search; ytsearch:... is also accepted.",
            "required": True,
            "value": safe_text(values.get("urls")),
            "section": "source",
        },
        {
            "id": "download_folder",
            "type": "folderpicker",
            "label": "Download folder",
            "description": "yt-dlp creates the folder when needed.",
            "value": safe_text(values.get("download_folder"), default_download_folder()),
            "section": "source",
        },
        {
            "id": "mode",
            "type": "dropdown",
            "label": "Output mode",
            "value": safe_text(values.get("mode"), "video"),
            "options": [
                option("video", "Video"),
                option("audio", "Audio only"),
                option("custom", "Custom format selector"),
            ],
            "section": "format",
        },
        {
            "id": "video_quality",
            "type": "dropdown",
            "label": "Maximum video quality",
            "value": safe_text(values.get("video_quality"), "best"),
            "options": [
                option("best", "Best available"),
                option("2160", "Up to 2160p / 4K"),
                option("1440", "Up to 1440p"),
                option("1080", "Up to 1080p"),
                option("720", "Up to 720p"),
                option("480", "Up to 480p"),
                option("360", "Up to 360p"),
            ],
            "visibleWhen": {"field": "mode", "equals": "video"},
            "section": "format",
        },
        {
            "id": "video_container",
            "type": "dropdown",
            "label": "Video container",
            "value": safe_text(values.get("video_container"), "mp4"),
            "options": ["mp4", "mkv", "webm"],
            "visibleWhen": {"field": "mode", "equals": "video"},
            "section": "format",
        },
        {
            "id": "audio_format",
            "type": "dropdown",
            "label": "Audio format",
            "value": safe_text(values.get("audio_format"), "mp3"),
            "options": ["mp3", "m4a", "opus", "flac", "wav"],
            "visibleWhen": {"field": "mode", "equals": "audio"},
            "section": "format",
        },
        {
            "id": "audio_quality",
            "type": "dropdown",
            "label": "Audio quality",
            "value": safe_text(values.get("audio_quality"), "192K"),
            "options": ["best", "128K", "192K", "256K", "320K"],
            "visibleWhen": {"field": "mode", "equals": "audio"},
            "section": "format",
        },
        {
            "id": "custom_format",
            "type": "text",
            "label": "Custom format selector",
            "placeholder": "bv*+ba/b",
            "description": "Passed to yt-dlp as -f. Leave blank to use its default.",
            "value": safe_text(values.get("custom_format")),
            "visibleWhen": {"field": "mode", "equals": "custom"},
            "section": "format",
        },
        {
            "id": "embed_metadata",
            "type": "checkbox",
            "label": "Embed metadata",
            "value": bool(values.get("embed_metadata", True)),
            "section": "postprocess",
        },
        {
            "id": "embed_thumbnail",
            "type": "checkbox",
            "label": "Embed thumbnail",
            "description": "Requires FFmpeg for most formats.",
            "value": bool(values.get("embed_thumbnail", True)),
            "section": "postprocess",
        },
        {
            "id": "write_thumbnail",
            "type": "checkbox",
            "label": "Keep a separate thumbnail file",
            "value": bool(values.get("write_thumbnail", False)),
            "section": "postprocess",
        },
        {
            "id": "embed_chapters",
            "type": "checkbox",
            "label": "Embed chapters",
            "value": bool(values.get("embed_chapters", False)),
            "section": "postprocess",
        },
        {
            "id": "embed_subs",
            "type": "checkbox",
            "label": "Embed subtitles",
            "value": bool(values.get("embed_subs", False)),
            "section": "postprocess",
        },
        {
            "id": "write_subs",
            "type": "checkbox",
            "label": "Write subtitles beside the media",
            "value": bool(values.get("write_subs", False)),
            "section": "postprocess",
        },
        {
            "id": "auto_subs",
            "type": "checkbox",
            "label": "Download automatic subtitles",
            "value": bool(values.get("auto_subs", False)),
            "section": "postprocess",
        },
        {
            "id": "sub_langs",
            "type": "text",
            "label": "Subtitle languages",
            "placeholder": "en.*",
            "description": "yt-dlp language selector, for example en.* or all.",
            "value": safe_text(values.get("sub_langs"), "en.*"),
            "section": "postprocess",
        },
        {
            "id": "playlist",
            "type": "checkbox",
            "label": "Download the full playlist",
            "description": "When off, yt-dlp downloads only the supplied video.",
            "value": bool(values.get("playlist", False)),
            "section": "advanced",
        },
        {
            "id": "cookies_browser",
            "type": "dropdown",
            "label": "Cookies from browser",
            "description": "Use this only with a browser profile you trust.",
            "value": safe_text(values.get("cookies_browser"), "none"),
            "options": ["none", "chrome", "edge", "firefox", "brave", "opera", "vivaldi"],
            "section": "advanced",
        },
        {
            "id": "restrict_filenames",
            "type": "checkbox",
            "label": "Use portable filenames",
            "value": bool(values.get("restrict_filenames", False)),
            "section": "advanced",
        },
        {
            "id": "rate_limit",
            "type": "text",
            "label": "Rate limit",
            "placeholder": "Optional, e.g. 5M",
            "value": safe_text(values.get("rate_limit")),
            "section": "advanced",
        },
        {
            "id": "concurrent_fragments",
            "type": "number",
            "label": "Concurrent fragments",
            "description": "Higher values can improve speed but use more bandwidth.",
            "value": max(1, min(16, int_value(values.get("concurrent_fragments"), 4))),
            "min": 1,
            "max": 16,
            "section": "advanced",
        },
        {
            "id": "output_template",
            "type": "text",
            "label": "Output filename template",
            "description": "yt-dlp template, for example %(title)s [%(id)s].%(ext)s.",
            "value": safe_text(values.get("output_template"), DEFAULT_DOWNLOAD_VALUES["output_template"]),
            "section": "advanced",
        },
        {
            "id": "custom_args",
            "type": "textarea",
            "label": "Additional yt-dlp arguments",
            "description": "Optional double-quoted arguments appended before the source URL.",
            "value": safe_text(values.get("custom_args")),
            "section": "advanced",
        },
        {
            "id": "open_when_done",
            "type": "checkbox",
            "label": "Open the output when finished",
            "value": bool(values.get("open_when_done", False)),
            "section": "advanced",
        },
    ]
    if error_field:
        for field in fields:
            if field["id"] == error_field:
                field["error"] = error_message or "Please check this value."
                break
    return fields


def render_download_form(
    rev: int = 0,
    seed: str | None = None,
    error: str | None = None,
    error_field: str | None = None,
    history: str = "none",
) -> None:
    if seed is not None:
        STATE["form_values"] = form_values_with_defaults(seed)
    elif not STATE["form_values"]:
        STATE["form_values"] = form_values_with_defaults()
    values = STATE["form_values"]
    if not safe_text(values.get("download_folder")).strip():
        values["download_folder"] = SETTINGS["download_folder"]
    tool_missing = not TOOL_INFO["version"] and not TOOL_INFO["checking"]
    payload: dict[str, Any] = {
        "type": "render",
        "rev": rev,
        "view": "form",
        "page": page("ytdlp:download", "New download", history, [{"id": "ytdlp:home", "label": "Home"}]),
        "elementId": "download-form",
        "placeholder": "Configure a download...",
        "form": {
            "title": "New yt-dlp download",
            "error": error,
            "submitLabel": "Start download",
            "buttons": [
                {"id": "download", "label": "Start download"},
                {"id": "download-hide", "label": "Download and hide"},
            ],
            "sections": [
                {"id": "source", "title": "Source", "description": "Paste one or more URLs or search phrases."},
                {"id": "format", "title": "Format", "description": "Choose a curated format or pass your own selector."},
                {"id": "postprocess", "title": "Metadata and subtitles", "collapsible": True},
                {"id": "advanced", "title": "Advanced", "description": "Playlist, browser cookies, naming, and passthrough controls.", "collapsible": True},
            ],
            "fields": download_fields(values, error_field, error),
        },
        "actions": [
            {"id": "paste-urls", "title": "Paste from clipboard", "icon": "paste"},
            {"id": "settings", "title": "Open Settings", "icon": "settings"},
            {"id": "tools", "title": "yt-dlp setup", "icon": "info"},
        ],
    }
    if tool_missing:
        payload["banners"] = [
            {
                "id": "missing-tool",
                "style": "warning",
                "title": "yt-dlp is not ready",
                "message": "Install it or choose an executable in Settings before starting a download.",
                "actions": [{"id": "settings", "title": "Open Settings", "icon": "settings"}],
            }
        ]
    send(payload)


def int_value(value: Any, fallback: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return fallback


def settings_values() -> dict[str, Any]:
    values = {
        "executable": SETTINGS["executable"],
        "ffmpeg": SETTINGS["ffmpeg"],
        "download_folder": SETTINGS["download_folder"],
        "notifications": SETTINGS["notifications"],
        "auto_open": SETTINGS["auto_open"],
    }
    values.update(SETTINGS.get("defaults", {}))
    return values


def settings_fields(values: dict[str, Any], error_field: str | None = None, error_message: str | None = None) -> list[dict[str, Any]]:
    fields: list[dict[str, Any]] = [
        {
            "id": "executable",
            "type": "filepicker",
            "label": "yt-dlp executable",
            "description": "Leave empty to use yt-dlp from PATH.",
            "value": safe_text(values.get("executable")),
            "section": "tools",
        },
        {
            "id": "ffmpeg",
            "type": "filepicker",
            "label": "FFmpeg executable or folder",
            "description": "Optional. Used for merging, audio extraction, thumbnails, and subtitles.",
            "value": safe_text(values.get("ffmpeg")),
            "section": "tools",
        },
        {
            "id": "download_folder",
            "type": "folderpicker",
            "label": "Default download folder",
            "value": safe_text(values.get("download_folder"), default_download_folder()),
            "section": "tools",
        },
        {
            "id": "notifications",
            "type": "checkbox",
            "label": "Notify when a background job finishes",
            "value": bool(values.get("notifications", True)),
            "section": "behavior",
        },
        {
            "id": "auto_open",
            "type": "checkbox",
            "label": "Open the output after each download",
            "description": "The download form can override this for one job.",
            "value": bool(values.get("auto_open", False)),
            "section": "behavior",
        },
        {
            "id": "update_on_open",
            "type": "checkbox",
            "label": "Check and update yt-dlp when opened",
            "description": "Runs yt-dlp -U in the background; it only downloads an update when one is available.",
            "value": bool(values.get("update_on_open", True)),
            "section": "behavior",
        },
        {
            "id": "mode",
            "type": "dropdown",
            "label": "Default output mode",
            "value": safe_text(values.get("mode"), "video"),
            "options": [option("video", "Video"), option("audio", "Audio only"), option("custom", "Custom selector")],
            "section": "defaults",
        },
        {
            "id": "video_quality",
            "type": "dropdown",
            "label": "Default video quality",
            "value": safe_text(values.get("video_quality"), "best"),
            "options": ["best", "2160", "1440", "1080", "720", "480", "360"],
            "section": "defaults",
        },
        {
            "id": "video_container",
            "type": "dropdown",
            "label": "Default video container",
            "value": safe_text(values.get("video_container"), "mp4"),
            "options": ["mp4", "mkv", "webm"],
            "section": "defaults",
        },
        {
            "id": "audio_format",
            "type": "dropdown",
            "label": "Default audio format",
            "value": safe_text(values.get("audio_format"), "mp3"),
            "options": ["mp3", "m4a", "opus", "flac", "wav"],
            "section": "defaults",
        },
        {
            "id": "audio_quality",
            "type": "dropdown",
            "label": "Default audio quality",
            "value": safe_text(values.get("audio_quality"), "192K"),
            "options": ["best", "128K", "192K", "256K", "320K"],
            "section": "defaults",
        },
        {
            "id": "cookies_browser",
            "type": "dropdown",
            "label": "Default browser cookies",
            "value": safe_text(values.get("cookies_browser"), "none"),
            "options": ["none", "chrome", "edge", "firefox", "brave", "opera", "vivaldi"],
            "section": "defaults",
        },
        {
            "id": "embed_metadata",
            "type": "checkbox",
            "label": "Embed metadata by default",
            "value": bool(values.get("embed_metadata", True)),
            "section": "defaults",
        },
        {
            "id": "embed_thumbnail",
            "type": "checkbox",
            "label": "Embed thumbnails by default",
            "value": bool(values.get("embed_thumbnail", True)),
            "section": "defaults",
        },
        {
            "id": "playlist",
            "type": "checkbox",
            "label": "Download playlists by default",
            "value": bool(values.get("playlist", False)),
            "section": "defaults",
        },
        {
            "id": "concurrent_fragments",
            "type": "number",
            "label": "Default concurrent fragments",
            "value": max(1, min(16, int_value(values.get("concurrent_fragments"), 4))),
            "min": 1,
            "max": 16,
            "section": "defaults",
        },
        {
            "id": "rate_limit",
            "type": "text",
            "label": "Default rate limit",
            "placeholder": "Optional, e.g. 5M",
            "value": safe_text(values.get("rate_limit")),
            "section": "defaults",
        },
    ]
    if error_field:
        for field in fields:
            if field["id"] == error_field:
                field["error"] = error_message or "Please check this value."
                break
    return fields


def render_settings(
    rev: int = 0,
    error: str | None = None,
    error_field: str | None = None,
    history: str = "none",
) -> None:
    values = settings_values()
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "page": page("ytdlp:settings", "Settings", history, [{"id": "ytdlp:home", "label": "Home"}]),
            "elementId": "settings-form",
            "placeholder": "Configure yt-dlp...",
            "form": {
                "title": "yt-dlp Settings",
                "error": error,
                "submitLabel": "Save settings",
                "sections": [
                    {"id": "tools", "title": "Tools", "description": f"Current status: {tool_status_text()}"},
                    {"id": "behavior", "title": "Behavior"},
                    {"id": "defaults", "title": "Download defaults", "collapsible": True},
                ],
                "fields": settings_fields(values, error_field, error),
            },
            "actions": [
                {"id": "retry-tools", "title": "Check yt-dlp", "icon": "refresh"},
                {"id": "update", "title": "Update yt-dlp", "icon": "sync"},
                {"id": "home", "title": "Back to Home", "icon": "home"},
            ],
        }
    )


# ---------------------------------------------------------------------------
# Home dashboard and history views


def active_job_snapshot() -> Any:
    with STATE_LOCK:
        return ACTIVE_JOB


def visible_active_job_snapshot() -> Any:
    job = active_job_snapshot()
    return job if job and not job.get("automatic") else None


def job_progress(job: dict[str, Any]) -> float | None:
    if job.get("kind") != "download":
        return None
    items = job.get("items", [])
    if not items:
        return None
    terminal = 0
    current_progress = 0.0
    for item in items:
        status = item.get("status")
        if status in {"success", "error", "cancelled"}:
            terminal += 1
        elif status == "downloading":
            current_progress = float(item.get("percent", 0.0) or 0.0)
    return max(0.0, min(1.0, (terminal + current_progress) / len(items)))


def job_detail_text(job: dict[str, Any]) -> str:
    if job.get("kind") == "update":
        return "Running yt-dlp -U. You can close the launcher; the update remains supervised for up to 5 minutes."
    items = job.get("items", [])
    done = sum(1 for item in items if item.get("status") in {"success", "error", "cancelled"})
    current = next((item for item in items if item.get("status") == "downloading"), None)
    current_text = truncate((current or {}).get("title") or (current or {}).get("url") or "Preparing...", 90)
    parts = [f"{done}/{len(items)} sources finished", f"Current: {current_text}"]
    if current:
        speed = safe_text(current.get("speed"))
        eta = safe_text(current.get("eta"))
        if speed:
            parts.append(f"Speed: {speed}")
        if eta:
            parts.append(f"ETA: {eta}")
    parts.append("You can close the launcher; this job will continue in the background for up to 5 minutes.")
    return " · ".join(parts)


def operation_payload(job: dict[str, Any], page_history: str = "none") -> dict[str, Any]:
    if job.get("kind") == "update":
        operation = {
            "id": job["id"],
            "title": "Updating yt-dlp",
            "detail": job_detail_text(job),
            "cancellable": True,
        }
        panels = [
            {
                "id": "update-operation",
                "title": "Update",
                "height": 160,
                "view": "operation",
                "elementId": "update-operation",
                "operation": operation,
            },
            {
                "id": "update-log",
                "title": "Update output",
                "height": 360,
                "view": "log",
                "elementId": "update-log",
                "log": {"follow": True, "wrap": False, "lines": list(job.get("logs", [])) or [{"id": "waiting", "level": "info", "text": "Waiting for yt-dlp..."}]},
            },
        ]
    else:
        progress = job_progress(job)
        operation = {
            "id": job["id"],
            "title": f"Downloading {sum(1 for item in job['items'] if item.get('status') == 'success')}/{len(job['items'])}",
            "detail": job_detail_text(job),
            "cancellable": True,
        }
        if progress is not None:
            operation["progress"] = progress
        queue_items = []
        for item in job.get("items", []):
            status = item.get("status", "queued")
            accessories = [{"text": status_label(status), "color": status_color(status), "icon": status_icon(status)}]
            if item.get("speed"):
                accessories.append({"text": safe_text(item["speed"]), "icon": "bolt"})
            if item.get("eta"):
                accessories.append({"text": f"ETA {item['eta']}", "icon": "timer"})
            queue_item = {
                "id": item["id"],
                "title": truncate(item.get("title") or item.get("url"), 90),
                "subtitle": truncate(item.get("status_note") or item.get("url"), 120),
                "icon": status_icon(status),
                "accessories": accessories,
                "actions": [{"id": "copy-url", "title": "Copy source URL", "icon": "copy"}],
            }
            if status in {"downloading", "success"}:
                queue_item["progress"] = 1.0 if status == "success" else float(item.get("percent", 0.0) or 0.0)
            queue_items.append(queue_item)
        panels = [
            {
                "id": "download-operation",
                "title": "Download progress",
                "height": 180,
                "view": "operation",
                "elementId": "download-operation",
                "operation": operation,
            },
            {
                "id": "download-queue",
                "title": "Queue",
                "height": min(360, max(128, 72 * max(1, len(queue_items)))),
                "view": "list",
                "elementId": "download-queue",
                "items": queue_items,
                "emptyText": "Preparing the queue...",
            },
            {
                "id": "download-log",
                "title": "Live output",
                "height": 300,
                "view": "log",
                "elementId": "download-log",
                "log": {"follow": True, "wrap": False, "lines": list(job.get("logs", [])) or [{"id": "waiting", "level": "info", "text": "Waiting for yt-dlp..."}]},
            },
        ]
    return {
        "type": "render",
        "rev": 0,
        "view": "dashboard",
        "page": page("ytdlp:operation", "Download progress", page_history, [{"id": "ytdlp:home", "label": "Home"}]),
        "elementId": "active-job",
        "placeholder": "Download in progress...",
        "dashboard": {"layout": "stack", "panels": panels},
        "actions": [
            {"id": "hide-background", "title": "Hide and keep running", "icon": "download"},
            {
                "id": "cancel-all",
                "title": "Cancel job",
                "icon": "close",
                "destructive": True,
                "confirm": {"title": "Cancel this job?", "message": "The active yt-dlp process will be stopped.", "confirmLabel": "Cancel job"},
            },
        ],
        "floatingAction": {"id": "hide-background", "title": "Hide and keep running", "icon": "download"},
    }


def render_operation(job: dict[str, Any], page_history: str = "none") -> None:
    if is_ui_closed():
        return
    send(operation_payload(job, page_history))


def render_active_surface() -> None:
    job = active_job_snapshot()
    if not job or job.get("automatic") or is_ui_closed():
        return
    screen = STATE["screen"]
    if screen == "operation":
        render_operation(job)
    elif screen == "home":
        render_home(0)


def maybe_render_active_surface(job: dict[str, Any], force: bool = False) -> None:
    """Throttle noisy yt-dlp output to a calm, useful launcher refresh rate."""

    now = time.monotonic()
    with STATE_LOCK:
        last_render = float(job.get("last_render", 0.0) or 0.0)
        if not force and now - last_render < 0.25:
            return
        job["last_render"] = now
    render_active_surface()


def record_timestamp_text(record: dict[str, Any]) -> str:
    parsed = parse_iso(record.get("finished_at"))
    if not parsed:
        return "Unknown"
    local = parsed.astimezone()
    return local.strftime("%b %d · %H:%M")


def record_metadata(record: dict[str, Any]) -> list[dict[str, Any]]:
    status = safe_text(record.get("status"), "error")
    metadata = [
        {"label": "Status", "text": status_label(status), "color": status_color(status), "icon": status_icon(status)},
        {"label": "Source", "text": truncate(record.get("url"), 160), "icon": "link"},
        {"label": "Finished", "text": record_timestamp_text(record), "icon": "clock"},
        {"label": "Duration", "text": human_duration(record.get("duration")), "icon": "timer"},
    ]
    if record.get("format"):
        metadata.append({"label": "Format", "text": safe_text(record["format"]), "icon": "video" if record.get("mode") == "video" else "music"})
    if record.get("output_path"):
        metadata.extend(
            [
                {"separator": True},
                {"label": "Output", "text": truncate(record["output_path"], 180), "icon": "folder"},
            ]
        )
    if record.get("size"):
        metadata.append({"label": "Size", "text": human_bytes(record["size"]), "icon": "database"})
    return metadata


def record_preview(record: dict[str, Any]) -> dict[str, Any]:
    title = safe_text(record.get("title") or record.get("url"), "Untitled download")
    markdown = f"## {title}\n\nSource: {md_code(record.get('url'))}"
    if record.get("output_path"):
        markdown += f"\n\nOutput: {md_code(record['output_path'])}"
    if record.get("error"):
        markdown += f"\n\n> {truncate(record['error'], 300)}"
    return {"markdown": markdown, "metadata": record_metadata(record)}


def record_actions(record: dict[str, Any]) -> list[dict[str, Any]]:
    actions: list[dict[str, Any]] = [
        {"id": "default", "title": "View details", "icon": "open"},
        {"id": "copy-url", "title": "Copy source URL", "icon": "copy"},
        {"id": "redownload", "title": "Download again", "icon": "refresh"},
    ]
    if record.get("output_path"):
        actions.extend(
            [
                {"id": "open-output", "title": "Open output", "icon": "open"},
                {"id": "copy-path", "title": "Copy output path", "icon": "copy"},
            ]
        )
    actions.append(
        {
            "id": "delete-history",
            "title": "Remove from history",
            "icon": "trash",
            "destructive": True,
            "confirm": {"title": "Remove this history entry?", "message": "The downloaded file will not be deleted.", "confirmLabel": "Remove"},
        }
    )
    return actions


def history_item(record: dict[str, Any], timeline: bool = False) -> dict[str, Any]:
    status = safe_text(record.get("status"), "error")
    title = truncate(record.get("title") or record.get("url"), 100)
    output = record.get("output_path") or record.get("url") or ""
    item: dict[str, Any] = {
        "id": safe_text(record.get("id")),
        "title": title,
        "subtitle": truncate(output, 140),
        "icon": status_icon(status),
        "accessories": [
            {"text": status_label(status), "color": status_color(status), "icon": status_icon(status)},
            {"text": human_duration(record.get("duration")), "icon": "timer"},
        ],
        "actions": record_actions(record),
        "preview": record_preview(record),
    }
    if timeline:
        item["timestamp"] = record_timestamp_text(record)
    return item


def activity_chart() -> dict[str, Any]:
    today = datetime_module.datetime.now().date()
    days = [today - datetime_module.timedelta(days=offset) for offset in range(6, -1, -1)]
    counts = [0 for _ in days]
    for record in HISTORY:
        parsed = parse_iso(record.get("finished_at"))
        if not parsed:
            continue
        local_date = parsed.astimezone().date()
        if local_date in days:
            counts[days.index(local_date)] += 1
    return {
        "title": "Download attempts · last 7 days",
        "type": "bar",
        "showAxes": True,
        "showGrid": True,
        "showLegend": False,
        "tooltips": True,
        "xLabels": [day.strftime("%a") for day in days],
        "yTitle": "attempts",
        "series": [{"id": "attempts", "label": "Attempts", "values": counts, "color": "#63A0EA"}],
    }


def home_quick_items(query: str) -> list[dict[str, Any]]:
    items = []
    trimmed = query.strip()
    if trimmed:
        source = quick_query_to_input(trimmed)
        is_search = source.startswith("ytsearch")
        title = f"Search YouTube for {truncate(trimmed, 62)}" if is_search else f"Download from {truncate(trimmed, 62)}"
        items.append(
            {
                "id": "quick:query",
                "title": title,
                "subtitle": "Press Enter to configure this source",
                "icon": "search" if is_search else "download",
                "section": "From current query",
                "actions": [
                    {"id": "default", "title": "Configure download", "icon": "open"},
                    {"id": "copy-source", "title": "Copy source", "icon": "copy"},
                ],
                "preview": {
                    "markdown": "## Ready to download\n\n"
                    + ("This plain-text query will be sent to YouTube search.\n\n" if is_search else "This source will be passed to yt-dlp.\n\n")
                    + md_code(source),
                    "metadata": [
                        {"label": "Input", "text": truncate(trimmed, 180), "icon": "search" if is_search else "link"},
                        {"label": "yt-dlp source", "text": truncate(source, 180), "icon": "download"},
                    ],
                },
            }
        )
    items.extend(
        [
            {
                "id": "quick:new",
                "title": "New download",
                "subtitle": "Open the full format and post-processing form",
                "icon": "add",
                "section": "Start",
                "actions": [{"id": "default", "title": "Open form", "icon": "open"}],
                "preview": {"markdown": "## New download\n\nPaste URLs, choose a format, and start a supervised background job."},
            },
            {
                "id": "quick:history",
                "title": "Browse download history",
                "subtitle": "Filter, compare, and remove previous attempts",
                "icon": "clock",
                "section": "Manage",
                "actions": [{"id": "default", "title": "Open history", "icon": "open"}],
                "preview": {"markdown": "## History\n\nReview finished downloads without leaving the launcher."},
            },
        ]
    )
    active = visible_active_job_snapshot()
    if active:
        items.insert(
            0,
            {
                "id": "quick:active",
                "title": "View active job",
                "subtitle": job_detail_text(active),
                "icon": "download",
                "section": "Active job",
                "actions": [{"id": "default", "title": "View progress", "icon": "open"}],
                "preview": {"markdown": "## Active job\n\nThe download is supervised in the background and will notify you when it finishes."},
            },
        )
        active_progress = job_progress(active)
        if active_progress is not None:
            items[0]["progress"] = active_progress
    return items


def render_home(rev: int = 0, history: str = "none") -> None:
    active = visible_active_job_snapshot()
    if TOOL_INFO["version"]:
        tool_markdown = "## Ready\n\nPaste a URL into the launcher query or open **New download** for full control."
    elif TOOL_INFO["checking"]:
        tool_markdown = "## Checking yt-dlp\n\nThe executable is being checked in the background."
    else:
        tool_markdown = "## yt-dlp needs setup\n\nInstall yt-dlp or choose its executable in Settings, then check again."
    overview_metadata = [
        {"label": "yt-dlp", "text": tool_status_text(), "color": "#22C55E" if TOOL_INFO["version"] else "#F59E0B", "icon": "download"},
        {"label": "Destination", "text": truncate(SETTINGS["download_folder"], 180), "icon": "folder"},
        {"label": "History", "text": f"{len(HISTORY)} records", "icon": "clock"},
        {"label": "Notifications", "text": "On" if SETTINGS["notifications"] else "Off", "icon": "bell"},
    ]
    panels: list[dict[str, Any]] = [
        {
            "id": "overview",
            "title": "Downloader status",
            "height": 250,
            "view": "detail",
            "elementId": "overview",
            "detail": {"markdown": tool_markdown, "metadata": overview_metadata},
        },
        {
            "id": "quick-start",
            "title": "Quick start",
            "height": min(300, max(180, 76 * len(home_quick_items(STATE["query"])))),
            "view": "list",
            "elementId": "quick-start",
            "items": home_quick_items(STATE["query"]),
            "preview": {"enabled": True, "wide": False, "resizable": True, "initialWidth": 340},
        },
        {
            "id": "activity",
            "title": "Activity",
            "height": 190,
            "view": "chart",
            "elementId": "activity-chart",
            "chart": activity_chart(),
        },
        {
            "id": "recent",
            "title": "Recent downloads",
            "height": min(360, max(150, 76 * max(1, min(5, len(HISTORY))))),
            "view": "timeline",
            "elementId": "recent-downloads",
            "items": [history_item(record, timeline=True) for record in HISTORY[:5]],
            "emptyText": "No downloads yet. Start with a URL above.",
        },
    ]
    if active:
        panels.insert(
            1,
            {
                "id": "active-job",
                "title": "Active job",
                "height": 170,
                "view": "operation",
                "elementId": "active-job",
                "operation": operation_payload(active)["dashboard"]["panels"][0]["operation"],
            },
        )
    actions = [
        {"id": "new-download", "title": "New download", "icon": "add", "shortcut": "ctrl+n"},
        {"id": "history", "title": "Download history", "icon": "clock", "shortcut": "ctrl+h"},
        {"id": "settings", "title": "Settings", "icon": "settings"},
        {"id": "tools", "title": "yt-dlp setup", "icon": "info"},
        {"id": "retry-tools", "title": "Refresh tool status", "icon": "refresh"},
        {"id": "update", "title": "Update yt-dlp", "icon": "sync"},
        {"id": "open-folder", "title": "Open download folder", "icon": "folder"},
    ]
    if HISTORY:
        actions.append(
            {
                "id": "clear-history",
                "title": "Clear history",
                "icon": "trash",
                "destructive": True,
                "confirm": {"title": "Clear yt-dlp history?", "message": "Downloaded files will not be deleted.", "confirmLabel": "Clear history"},
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "dashboard",
            "page": page("ytdlp:home", "yt-dlp Downloader", history),
            "elementId": "home-dashboard",
            "placeholder": "Paste a URL or type a YouTube search...",
            "dashboard": {"layout": "stack", "panels": panels},
            "actions": actions,
            "floatingAction": {"id": "new-download", "title": "New download", "icon": "add", "shortcut": "ctrl+n"},
        }
    )


def filtered_history() -> list[dict[str, Any]]:
    query = safe_text(STATE["query"]).strip().lower()
    statuses = set(STATE["history_status_filter"])
    records = []
    for record in HISTORY:
        status = safe_text(record.get("status"))
        if statuses and status not in statuses:
            continue
        haystack = " ".join(safe_text(record.get(key)) for key in ("title", "url", "output_path", "error")).lower()
        if query and query not in haystack:
            continue
        records.append(record)
    sort_key = STATE["history_sort"]
    reverse = STATE["history_direction"] != "asc"
    if sort_key == "title":
        records.sort(key=lambda record: safe_text(record.get("title") or record.get("url")).lower(), reverse=reverse)
    elif sort_key == "status":
        records.sort(key=lambda record: safe_text(record.get("status")), reverse=reverse)
    elif sort_key == "format":
        records.sort(key=lambda record: safe_text(record.get("format")), reverse=reverse)
    else:
        records.sort(key=lambda record: safe_text(record.get("finished_at")), reverse=reverse)
    return records


def history_table_item(record: dict[str, Any]) -> dict[str, Any]:
    item = history_item(record)
    item["cells"] = {
        "status": status_label(safe_text(record.get("status"))),
        "format": safe_text(record.get("format"), "Unknown"),
        "finished": record_timestamp_text(record),
        "destination": truncate(record.get("output_path") or "-", 80),
    }
    return item


def render_history(rev: int = 0, history: str = "none") -> None:
    records = filtered_history()
    filters = [
        {"value": "success", "label": "Completed"},
        {"value": "error", "label": "Failed"},
        {"value": "cancelled", "label": "Cancelled"},
    ]
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "table",
            "page": page("ytdlp:history", "Download history", history, [{"id": "ytdlp:home", "label": "Home"}]),
            "elementId": "history-table",
            "placeholder": "Filter downloads...",
            "empty": {"icon": "clock", "title": "No matching downloads", "hint": "Start a download or change the filter.", "action": {"id": "new-download", "title": "New download", "icon": "add"}},
            "columns": [
                {"id": "title", "label": "Download", "width": 280},
                {"id": "status", "label": "Status", "width": 120, "sortable": True},
                {"id": "format", "label": "Format", "width": 100, "sortable": True},
                {"id": "finished", "label": "Finished", "width": 150, "sortable": True},
                {"id": "destination", "label": "Output", "width": 300},
            ],
            "table": {"resizable": True, "stickyHeader": True, "columnVisibility": True, "sortColumn": STATE["history_sort"], "sortDirection": STATE["history_direction"]},
            "toolbar": {"filters": [{"id": "status", "label": "Status", "multiple": True, "values": STATE["history_status_filter"], "options": filters}], "sort": {"value": STATE["history_sort"], "direction": STATE["history_direction"], "options": ["finished", "title", "status", "format"]}},
            "selection": {"enabled": True, "max": 50},
            "items": [history_table_item(record) for record in records],
            "actions": [
                {"id": "new-download", "title": "New download", "icon": "add", "shortcut": "ctrl+n"},
                {"id": "home", "title": "Back to Home", "icon": "home"},
                {
                    "id": "delete-selected",
                    "title": "Remove selected history",
                    "icon": "trash",
                    "destructive": True,
                    "confirm": {"title": "Remove selected history?", "message": "Downloaded files will not be deleted.", "confirmLabel": "Remove"},
                },
                {
                    "id": "clear-history",
                    "title": "Clear all history",
                    "icon": "trash",
                    "destructive": True,
                    "confirm": {"title": "Clear all yt-dlp history?", "message": "Downloaded files will not be deleted.", "confirmLabel": "Clear history"},
                },
            ],
            "floatingAction": {"id": "new-download", "title": "New download", "icon": "add"},
        }
    )


def find_record(record_id: Any) -> dict[str, Any] | None:
    needle = safe_text(record_id)
    return next((record for record in HISTORY if safe_text(record.get("id")) == needle), None)


def render_record_detail(record_id: str, history: str = "none") -> None:
    record = find_record(record_id)
    if not record:
        go_home()
        return
    STATE["screen"] = "detail"
    STATE["detail_id"] = record_id
    status = safe_text(record.get("status"), "error")
    title = safe_text(record.get("title") or record.get("url"), "Download details")
    escaped_title = title.replace("#", "\\#")
    markdown = f"# {escaped_title}\n\n"
    source = safe_text(record.get("url"))
    if source.startswith(("http://", "https://")):
        link_source = source.replace(")", "%29")
        markdown += f"[Open source in your browser]({link_source})\n\n"
    else:
        markdown += f"Source: {md_code(source)}\n\n"
    if record.get("output_path"):
        markdown += f"Output: {md_code(record['output_path'])}\n\n"
    if status == "success":
        markdown += "The download completed successfully."
    elif status == "cancelled":
        markdown += "The download was cancelled before completion."
    else:
        markdown += "yt-dlp reported an error. The latest diagnostic is below."
        if record.get("error"):
            markdown += f"\n\n```text\n{safe_text(record['error'])[-6000:]}\n```"
    actions = [action for action in record_actions(record) if action["id"] != "default"]
    if record.get("output_path"):
        actions.append(
            {
                "id": "delete-file",
                "title": "Delete output file",
                "icon": "trash",
                "destructive": True,
                "confirm": {"title": "Delete this output file?", "message": "This permanently deletes the downloaded file.", "confirmLabel": "Delete file"},
            }
        )
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "page": page("ytdlp:item:" + record_id, "Download details", history, [{"id": "ytdlp:home", "label": "Home"}, {"id": "ytdlp:history", "label": "History"}]),
            "elementId": "history-detail",
            "placeholder": "Download details...",
            "detail": {"wide": True, "markdown": markdown, "metadata": record_metadata(record)},
            "actions": actions,
            "floatingAction": {"id": "redownload", "title": "Download again", "icon": "refresh"},
        }
    )


def render_result(result: dict[str, Any]) -> None:
    global LAST_RESULT
    LAST_RESULT = result
    records = result.get("records", [])
    success_count = sum(1 for record in records if record.get("status") == "success")
    error_count = sum(1 for record in records if record.get("status") == "error")
    cancelled_count = sum(1 for record in records if record.get("status") == "cancelled")
    status = result.get("status", "error")
    if status == "success":
        heading = "# Downloads complete"
        intro = f"Processed {len(records)} source(s) successfully."
    elif status == "cancelled":
        heading = "# Download cancelled"
        intro = "The active yt-dlp process was stopped. Completed sources remain available in history."
    else:
        heading = "# Download finished with errors"
        intro = "yt-dlp finished with one or more errors. Review the per-source entries below."
    lines = [heading, "", intro, ""]
    for record in records:
        marker = "OK" if record.get("status") == "success" else status_label(safe_text(record.get("status"))).upper()
        lines.append(f"- **{marker}:** {truncate(record.get('title') or record.get('url'), 120)}")
        if record.get("output_path"):
            lines.append(f"  - {md_code(record['output_path'])}")
        if record.get("error"):
            lines.append(f"  - {truncate(record['error'], 260)}")
    metadata = [
        {"label": "Completed", "text": str(success_count), "color": "#22C55E", "icon": "check"},
        {"label": "Failed", "text": str(error_count), "color": "#EF4444" if error_count else "#94A3B8", "icon": "error"},
        {"label": "Cancelled", "text": str(cancelled_count), "color": "#94A3B8", "icon": "close"},
        {"label": "Elapsed", "text": human_duration(result.get("duration")), "icon": "timer"},
        {"label": "Destination", "text": truncate(SETTINGS["download_folder"], 180), "icon": "folder"},
    ]
    actions: list[dict[str, Any]] = [
        {"id": "download-another", "title": "Download another", "icon": "refresh"},
        {"id": "history", "title": "View history", "icon": "clock"},
        {"id": "home", "title": "Back to Home", "icon": "home"},
    ]
    successful_paths = [safe_text(record.get("output_path")) for record in records if record.get("status") == "success" and record.get("output_path")]
    if len(successful_paths) == 1:
        actions.insert(0, {"id": "open-output", "title": "Open output", "icon": "open"})
        actions.insert(1, {"id": "copy-path", "title": "Copy output path", "icon": "copy"})
    if successful_paths:
        actions.append({"id": "open-folder", "title": "Open download folder", "icon": "folder"})
    if status == "error":
        actions.append({"id": "copy-error", "title": "Copy diagnostics", "icon": "copy"})
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "page": page("ytdlp:result", "Download result", "replace", [{"id": "ytdlp:home", "label": "Home"}]),
            "elementId": "download-result",
            "placeholder": "Download result...",
            "detail": {"wide": True, "markdown": "\n".join(lines), "metadata": metadata},
            "actions": actions,
            "floatingAction": {"id": "download-another", "title": "Download another", "icon": "refresh"},
        }
    )


def render_update_result(result: dict[str, Any]) -> None:
    status = result.get("status", "error")
    if status == "success":
        heading = "# yt-dlp update check complete"
        message = "yt-dlp checked for updates and completed successfully. A newer release was installed if one was available."
    elif status == "cancelled":
        heading = "# Update cancelled"
        message = "The yt-dlp update was stopped."
    else:
        heading = "# yt-dlp update failed"
        message = "The update command returned an error."
    output = "\n".join(safe_text(line.get("text")) for line in result.get("logs", []))[-7000:]
    markdown = f"{heading}\n\n{message}"
    if output:
        markdown += f"\n\n```text\n{output}\n```"
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "page": page("ytdlp:update-result", "yt-dlp update", "replace", [{"id": "ytdlp:home", "label": "Home"}]),
            "detail": {"wide": True, "markdown": markdown},
            "actions": [
                {"id": "retry-tools", "title": "Check version", "icon": "refresh"},
                {"id": "update", "title": "Run update again", "icon": "sync"},
                {"id": "home", "title": "Back to Home", "icon": "home"},
            ],
            "floatingAction": {"id": "home", "title": "Back to Home", "icon": "home"},
        }
    )


# ---------------------------------------------------------------------------
# yt-dlp argument construction and process execution


def quick_query_to_input(query: str) -> str:
    trimmed = query.strip()
    if re.match(r"^[a-z][a-z0-9+.-]*://", trimmed, re.IGNORECASE) or re.match(r"^[a-z]+search\d*:", trimmed, re.IGNORECASE):
        return trimmed
    if trimmed.lower().startswith(("yt:", "auto:", "scsearch", "gvsearch")):
        return trimmed
    return "ytsearch1:" + trimmed


def normalize_inputs(raw: Any) -> tuple[list[str], str | None]:
    text = safe_text(raw)
    lines = [line.strip() for line in re.split(r"[\r\n]+", text) if line.strip()]
    if not lines:
        return [], "Add at least one URL or search phrase."
    results = []
    seen = set()
    for line in lines:
        if line.startswith("-"):
            return [], "Sources cannot start with a hyphen."
        source = quick_query_to_input(line)
        if source not in seen:
            seen.add(source)
            results.append(source)
    return results, None


def tokenize_custom_args(value: Any) -> list[str]:
    text = safe_text(value).strip()
    if not text:
        return []
    # Keep Windows-friendly double-quoted groups without invoking a shell.
    tokens = []
    pattern = re.compile(r'"([^"]*)"|(\S+)')
    for match in pattern.finditer(text):
        tokens.append(match.group(1) if match.group(1) is not None else match.group(2))
    return tokens


def build_yt_dlp_args(url: str, values: dict[str, Any]) -> list[str]:
    args: list[str] = []
    folder = safe_text(values.get("download_folder")).strip()
    if folder:
        args.extend(["-P", os.path.expanduser(folder)])
    output_template = safe_text(values.get("output_template"), DEFAULT_DOWNLOAD_VALUES["output_template"]).strip()
    args.extend(["-o", output_template or DEFAULT_DOWNLOAD_VALUES["output_template"]])

    mode = safe_text(values.get("mode"), "video")
    if mode == "video":
        quality = safe_text(values.get("video_quality"), "best")
        if quality == "best":
            selector = "bv*+ba/b"
        else:
            selector = f"bv*[height<={quality}]+ba/b[height<={quality}]"
        args.extend(["-f", selector, "--merge-output-format", safe_text(values.get("video_container"), "mp4")])
    elif mode == "audio":
        args.extend(["-x", "--audio-format", safe_text(values.get("audio_format"), "mp3")])
        audio_quality = safe_text(values.get("audio_quality"), "192K")
        args.extend(["--audio-quality", "0" if audio_quality == "best" else audio_quality])
    else:
        custom_format = safe_text(values.get("custom_format")).strip()
        if custom_format:
            args.extend(["-f", custom_format])

    boolean_args = (
        ("embed_thumbnail", "--embed-thumbnail"),
        ("write_thumbnail", "--write-thumbnail"),
        ("embed_metadata", "--embed-metadata"),
        ("embed_chapters", "--embed-chapters"),
        ("embed_subs", "--embed-subs"),
        ("write_subs", "--write-subs"),
        ("auto_subs", "--write-auto-subs"),
        ("sponsor_block", "--sponsorblock-remove"),
        ("restrict_filenames", "--restrict-filenames"),
    )
    for key, flag in boolean_args:
        if bool(values.get(key)):
            if key == "sponsor_block":
                args.extend([flag, "all"])
            else:
                args.append(flag)
    if any(bool(values.get(key)) for key in ("embed_subs", "write_subs", "auto_subs")):
        languages = safe_text(values.get("sub_langs"), "en.*").strip()
        if languages:
            args.extend(["--sub-langs", languages])
    args.append("--yes-playlist" if bool(values.get("playlist")) else "--no-playlist")

    browser = safe_text(values.get("cookies_browser"), "none").strip()
    if browser and browser != "none":
        args.extend(["--cookies-from-browser", browser])
    rate_limit = safe_text(values.get("rate_limit")).strip()
    if rate_limit:
        args.extend(["--limit-rate", rate_limit])
    fragments = int_value(values.get("concurrent_fragments"), 4)
    if fragments > 1:
        args.extend(["-N", str(max(1, min(16, fragments)))])
    ffmpeg = safe_text(SETTINGS.get("ffmpeg")).strip()
    if ffmpeg:
        args.extend(["--ffmpeg-location", os.path.expanduser(ffmpeg)])
    args.extend(tokenize_custom_args(values.get("custom_args")))

    # These markers are machine-readable but still leave normal yt-dlp output
    # available in the live log panel.
    args.extend(
        [
            "--newline",
            "--no-abort-on-error",
            "--progress-template",
            "download:" + PROGRESS_PREFIX + "%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress.downloaded_bytes)s|%(progress.total_bytes)s",
            "--print",
            "before_dl:" + INFO_PREFIX + "%(title)s|%(id)s",
            "--print",
            "after_move:" + FILE_PREFIX + "%(filepath)s",
            "--",
            url,
        ]
    )
    return args


def add_job_log(job: dict[str, Any], text: str, level: str = "info") -> None:
    clean = strip_ansi(text).strip()
    if not clean:
        return
    with STATE_LOCK:
        job["log_counter"] = int(job.get("log_counter", 0)) + 1
        job.setdefault("logs", deque(maxlen=140)).append(
            {
                "id": f"{job['id']}-log-{job['log_counter']}",
                "timestamp": time.strftime("%H:%M:%S"),
                "level": level,
                "source": "yt-dlp",
                "text": truncate(clean, 500),
            }
        )


def strip_ansi(text: str) -> str:
    return re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)


def parse_progress(item: dict[str, Any], payload: str) -> None:
    parts = payload.split("|")
    if parts:
        match = re.search(r"-?\d+(?:\.\d+)?", parts[0])
        if match:
            try:
                item["percent"] = max(0.0, min(1.0, float(match.group(0)) / 100.0))
            except ValueError:
                pass
    if len(parts) > 1 and parts[1].strip().lower() not in {"unknown", "n/a"}:
        item["speed"] = parts[1].strip()
    if len(parts) > 2 and parts[2].strip().lower() not in {"unknown", "n/a"}:
        item["eta"] = parts[2].strip()
    if len(parts) > 3:
        item["downloaded_bytes"] = int_value(parts[3], 0)
    if len(parts) > 4:
        item["total_bytes"] = int_value(parts[4], 0)


def parse_ytdlp_line(job: dict[str, Any], item: dict[str, Any], raw_line: str, stderr_lines: list[str]) -> None:
    line = strip_ansi(raw_line).strip()
    if not line:
        return
    if PROGRESS_PREFIX in line:
        parse_progress(item, line.split(PROGRESS_PREFIX, 1)[1])
        return
    if INFO_PREFIX in line:
        info = line.split(INFO_PREFIX, 1)[1]
        title, _, video_id = info.partition("|")
        if title and title.lower() not in {"na", "none"}:
            item["title"] = title.strip()
        if video_id:
            item["video_id"] = video_id.strip()
        add_job_log(job, f"Preparing: {item.get('title') or item.get('url')}")
        return
    if FILE_PREFIX in line:
        output = line.split(FILE_PREFIX, 1)[1].strip()
        if output:
            item["output_path"] = output
        add_job_log(job, f"Output: {output}")
        return

    destination = re.search(r"Destination:\s*(.+)$", line, re.IGNORECASE)
    if destination:
        item["output_path"] = destination.group(1).strip().strip('"')
    merging = re.search(r'Merging formats into "?(.+?)"?$', line, re.IGNORECASE)
    if merging:
        item["output_path"] = merging.group(1).strip().strip('"')
    playlist_item = re.search(r"Downloading (?:item|video) (\d+) of (\d+)", line, re.IGNORECASE)
    if playlist_item:
        item["status_note"] = f"Item {playlist_item.group(1)} of {playlist_item.group(2)}"

    upper = line.upper()
    if "ERROR" in upper:
        level = "error"
    elif "WARNING" in upper or "WARN" in upper:
        level = "warn"
    elif "[DOWNLOAD]" in upper:
        level = "info"
    else:
        level = "debug" if raw_line.startswith("[") else "info"
    if "ERROR" in upper or "WARNING" in upper or not line.startswith("[download]"):
        stderr_lines.append(line)
    add_job_log(job, line, level)


def read_stderr(job: dict[str, Any], item: dict[str, Any], stream: Any, stderr_lines: list[str]) -> None:
    try:
        for line in stream:
            parse_ytdlp_line(job, item, line, stderr_lines)
    except Exception as exc:
        add_job_log(job, f"Could not read yt-dlp diagnostics: {exc}", "error")


def last_error(lines: list[str], return_code: int) -> str:
    errors = [line for line in lines if "ERROR" in line.upper()]
    chosen = errors[-1] if errors else (lines[-1] if lines else f"yt-dlp exited with code {return_code}.")
    return truncate(chosen, 600)


def format_label(values: dict[str, Any]) -> str:
    mode = safe_text(values.get("mode"), "video")
    if mode == "video":
        quality = safe_text(values.get("video_quality"), "best")
        quality_label = "Best" if quality == "best" else f"Up to {quality}p"
        return f"Video / {quality_label} / {safe_text(values.get('video_container'), 'mp4')}"
    if mode == "audio":
        return f"Audio / {safe_text(values.get('audio_format'), 'mp3')} / {safe_text(values.get('audio_quality'), '192K')}"
    return "Custom format"


def record_for_item(item: dict[str, Any], job: dict[str, Any]) -> dict[str, Any]:
    output_path = safe_text(item.get("output_path")).strip()
    size = None
    if output_path:
        try:
            path = Path(output_path)
            if path.exists() and path.is_file():
                size = path.stat().st_size
        except OSError:
            pass
    return {
        "id": f"history-{uuid.uuid4().hex[:12]}",
        "url": item.get("url"),
        "title": item.get("title") or item.get("url"),
        "status": item.get("status", "error"),
        "output_path": output_path,
        "error": item.get("error", ""),
        "finished_at": iso_now(),
        "duration": item.get("duration", 0),
        "size": size,
        "mode": safe_text(job.get("values", {}).get("mode"), "video"),
        "format": format_label(job.get("values", {})),
    }


def append_history(records: list[dict[str, Any]]) -> None:
    HISTORY[0:0] = records
    del HISTORY[50:]
    persist_history(preserve_current=True)


def terminate_process(process: Any) -> None:
    if process is None:
        return
    try:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
    except (OSError, subprocess.SubprocessError):
        pass
    if os.name == "nt":
        try:
            subprocess.run(
                ["taskkill", "/T", "/F", "/PID", str(process.pid)],
                capture_output=True,
                timeout=5,
                **process_options(),
            )
        except (OSError, subprocess.SubprocessError):
            pass


def cancel_active_job() -> None:
    job = active_job_snapshot()
    if not job:
        command("toast", text="There is no active yt-dlp job.", style="info")
        return
    job["cancel"].set()
    terminate_process(job.get("process"))
    add_job_log(job, "Cancellation requested.", "warn")
    command("toast", text="Stopping yt-dlp...", style="progress")


def run_download(job: dict[str, Any]) -> None:
    global ACTIVE_JOB, LAST_RESULT
    started = time.monotonic()
    records: list[dict[str, Any]] = []
    try:
        folder = safe_text(job["values"].get("download_folder")).strip()
        if folder:
            Path(os.path.expanduser(folder)).mkdir(parents=True, exist_ok=True)
        for item in job["items"]:
            if job["cancel"].is_set():
                item["status"] = "cancelled"
                item["error"] = "Cancelled before starting."
                continue
            item["status"] = "downloading"
            item["started_at"] = time.monotonic()
            stderr_lines: list[str] = []
            process = None
            try:
                executable = resolve_executable()
                if not executable:
                    raise FileNotFoundError("yt-dlp was not found. Open Settings to choose its executable.")
                args = build_yt_dlp_args(item["url"], job["values"])
                log("Running: " + subprocess.list2cmdline([executable] + args))
                process = subprocess.Popen(
                    [executable] + args,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    **process_options(),
                )
                with STATE_LOCK:
                    job["process"] = process
                stderr_thread = threading.Thread(target=read_stderr, args=(job, item, process.stderr, stderr_lines), daemon=True)
                stderr_thread.start()
                if process.stdout is not None:
                    for line in process.stdout:
                        parse_ytdlp_line(job, item, line, stderr_lines)
                        if not is_ui_closed():
                            maybe_render_active_surface(job)
                return_code = process.wait()
                stderr_thread.join(timeout=2)
                item["status"] = "cancelled" if job["cancel"].is_set() else ("success" if return_code == 0 else "error")
                if item["status"] == "success":
                    item["percent"] = 1.0
                elif item["status"] == "cancelled":
                    item["error"] = "Cancelled by the user."
                else:
                    item["error"] = last_error(stderr_lines, return_code)
            except FileNotFoundError as exc:
                item["status"] = "error"
                item["error"] = str(exc)
            except Exception as exc:
                item["status"] = "cancelled" if job["cancel"].is_set() else "error"
                item["error"] = str(exc)
            finally:
                item["duration"] = time.monotonic() - item.get("started_at", started)
                with STATE_LOCK:
                    if job.get("process") is process:
                        job["process"] = None
                records.append(record_for_item(item, job))
                maybe_render_active_surface(job, force=True)
        for item in job["items"]:
            if item.get("status") == "queued":
                item["status"] = "cancelled"
                item["error"] = "Cancelled before starting."
                item["duration"] = 0
                records.append(record_for_item(item, job))
        if any(record["status"] == "error" for record in records):
            status = "error"
        elif records and all(record["status"] == "cancelled" for record in records):
            status = "cancelled"
        else:
            status = "success"
        result = {"kind": "download", "status": status, "records": records, "duration": time.monotonic() - started}
        append_history(records)
        LAST_RESULT = result
        with STATE_LOCK:
            if ACTIVE_JOB is job:
                ACTIVE_JOB = None
        if is_ui_closed():
            if SETTINGS["notifications"]:
                summary = (
                    f"{sum(1 for record in records if record['status'] == 'success')} completed, "
                    f"{sum(1 for record in records if record['status'] == 'error')} failed, "
                    f"{sum(1 for record in records if record['status'] == 'cancelled')} cancelled."
                )
                command("notify", title=PLUGIN_NAME, text=summary)
        else:
            if status == "success":
                command("toast", text=f"Finished {len(records)} download(s).", style="success")
            elif status == "cancelled":
                command("toast", text="yt-dlp job cancelled.", style="info")
            else:
                command("toast", text="yt-dlp finished with errors.", style="error")
            if bool(job["values"].get("open_when_done")) and len(records) == 1 and records[0].get("output_path"):
                command("open", path=records[0]["output_path"])
            if STATE["screen"] in {"operation", "home"}:
                STATE["screen"] = "result"
                if STATE["route_stack"]:
                    STATE["route_stack"][-1] = "ytdlp:result"
                render_result(result)
    except Exception as exc:
        log(f"Download worker failed: {exc}")
        fallback = {"kind": "download", "status": "error", "records": [{"id": f"history-{uuid.uuid4().hex[:12]}", "url": "", "title": "yt-dlp worker", "status": "error", "error": str(exc), "finished_at": iso_now(), "duration": time.monotonic() - started, "mode": "", "format": ""}], "duration": time.monotonic() - started}
        append_history(fallback["records"])
        LAST_RESULT = fallback
        with STATE_LOCK:
            if ACTIVE_JOB is job:
                ACTIVE_JOB = None
        if is_ui_closed():
            if SETTINGS["notifications"]:
                command("notify", title=PLUGIN_NAME, text=f"yt-dlp failed: {truncate(exc, 280)}")
        elif STATE["screen"] in {"operation", "home"}:
            render_result(fallback)


def run_update(job: dict[str, Any]) -> None:
    global ACTIVE_JOB, LAST_RESULT
    started = time.monotonic()
    process = None
    try:
        executable = resolve_executable()
        if not executable:
            raise FileNotFoundError("yt-dlp was not found. Open Settings to choose its executable.")
        log("Running: " + subprocess.list2cmdline([executable, "-U"]))
        process = subprocess.Popen(
            [executable, "-U"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            **process_options(),
        )
        with STATE_LOCK:
            job["process"] = process
        stderr_lines: list[str] = []
        stderr_thread = threading.Thread(target=read_update_stderr, args=(job, process.stderr, stderr_lines), daemon=True)
        stderr_thread.start()
        if process.stdout is not None:
            for line in process.stdout:
                add_job_log(job, line, "info")
                if not job.get("automatic"):
                    maybe_render_active_surface(job)
        return_code = process.wait()
        stderr_thread.join(timeout=2)
        status = "cancelled" if job["cancel"].is_set() else ("success" if return_code == 0 else "error")
        if status == "error":
            add_job_log(job, last_error(stderr_lines, return_code), "error")
        result = {"kind": "update", "status": status, "logs": list(job.get("logs", [])), "duration": time.monotonic() - started}
        LAST_RESULT = result
        with STATE_LOCK:
            if ACTIVE_JOB is job:
                ACTIVE_JOB = None
        TOOL_INFO.update(probe_tool())
        automatic = bool(job.get("automatic"))
        if is_ui_closed():
            if SETTINGS["notifications"] and (not automatic or status != "success"):
                text = "yt-dlp update finished." if status == "success" else "yt-dlp update failed."
                command("notify", title=PLUGIN_NAME, text=text)
        elif automatic:
            if status != "success":
                command("toast", text="yt-dlp background update failed.", style="error")
            elif STATE["screen"] == "home":
                render_home(0)
            elif STATE["screen"] == "settings":
                render_settings()
        elif STATE["screen"] in {"operation", "home"}:
            command("toast", text="yt-dlp update finished." if status == "success" else "yt-dlp update failed.", style="success" if status == "success" else "error")
            STATE["screen"] = "update-result"
            if STATE["route_stack"]:
                STATE["route_stack"][-1] = "ytdlp:update-result"
            render_update_result(result)
    except Exception as exc:
        log(f"Update worker failed: {exc}")
        result = {"kind": "update", "status": "error", "logs": [{"id": "update-error", "level": "error", "text": str(exc)}], "duration": time.monotonic() - started}
        LAST_RESULT = result
        with STATE_LOCK:
            if ACTIVE_JOB is job:
                ACTIVE_JOB = None
        automatic = bool(job.get("automatic"))
        if is_ui_closed():
            if SETTINGS["notifications"]:
                command("notify", title=PLUGIN_NAME, text=f"yt-dlp background update failed: {truncate(exc, 280)}" if automatic else f"yt-dlp update failed: {truncate(exc, 280)}")
        elif automatic:
            command("toast", text="yt-dlp background update failed.", style="error")
        elif STATE["screen"] in {"operation", "home"}:
            render_update_result(result)
    finally:
        with STATE_LOCK:
            job["process"] = None


def read_update_stderr(job: dict[str, Any], stream: Any, stderr_lines: list[str]) -> None:
    try:
        for line in stream:
            text_value = strip_ansi(line).strip()
            if text_value:
                stderr_lines.append(text_value)
                add_job_log(job, text_value, "error" if "ERROR" in text_value.upper() else "warn")
    except Exception as exc:
        add_job_log(job, f"Could not read update diagnostics: {exc}", "error")


def start_download(values: dict[str, Any], hide_after_start: bool = False) -> None:
    global ACTIVE_JOB
    with STATE_LOCK:
        if ACTIVE_JOB is not None:
            command("toast", text="A yt-dlp job is already running.", style="info")
            render_operation(ACTIVE_JOB)
            return
    urls, error = normalize_inputs(values.get("urls"))
    STATE["form_values"] = dict(values)
    if error:
        render_download_form(error=error, error_field="urls", history="none")
        return
    executable = resolve_executable()
    if not executable:
        render_download_form(error="yt-dlp was not found. Install it or choose the executable in Settings.", history="none")
        return
    folder = safe_text(values.get("download_folder")).strip() or default_download_folder()
    folder_path = Path(os.path.expanduser(folder))
    if folder_path.exists() and not folder_path.is_dir():
        render_download_form(error="The download folder points to a file, not a folder.", error_field="download_folder", history="none")
        return
    values = dict(values)
    values["download_folder"] = str(folder_path)
    values["concurrent_fragments"] = max(1, min(16, int_value(values.get("concurrent_fragments"), 4)))
    values["mode"] = safe_text(values.get("mode"), "video")
    SETTINGS["download_folder"] = str(folder_path)
    for key in DEFAULT_DOWNLOAD_VALUES:
        if key in values:
            SETTINGS["defaults"][key] = values[key]
    persist_settings()
    job_id = "download-" + uuid.uuid4().hex[:12]
    items = [{"id": f"{job_id}:source:{index}", "url": url, "status": "queued", "percent": 0.0} for index, url in enumerate(urls)]
    job = {"id": job_id, "kind": "download", "values": values, "items": items, "logs": deque(maxlen=140), "log_counter": 0, "cancel": threading.Event(), "process": None}
    with STATE_LOCK:
        ACTIVE_JOB = job
        STATE["screen"] = "operation"
        STATE["route_stack"].append("ytdlp:operation")
    command("storage", op="set", key="last_download", value=json.dumps(values, ensure_ascii=False))
    # Declare background grace before a possible hide.  The worker is
    # non-daemon so Python keeps it alive while Tabame supervises the process.
    command("background", timeout=BACKGROUND_GRACE_SECONDS)
    render_operation(job, page_history="push")
    worker = threading.Thread(target=run_download, args=(job,), name="ytdlp-download", daemon=False)
    job["thread"] = worker
    worker.start()
    if hide_after_start:
        command("hide")


def start_update(automatic: bool = False) -> None:
    global ACTIVE_JOB
    with STATE_LOCK:
        if ACTIVE_JOB is not None:
            if not automatic:
                command("toast", text="A yt-dlp job is already running.", style="info")
                render_operation(ACTIVE_JOB)
            return
    executable = resolve_executable()
    if not executable:
        if automatic:
            command("toast", text="yt-dlp update skipped because the executable is unavailable.", style="info")
        elif STATE["screen"] == "tools":
            render_tool_details()
        else:
            go_tools()
        return
    job = {"id": "update-" + uuid.uuid4().hex[:12], "kind": "update", "automatic": automatic, "logs": deque(maxlen=140), "log_counter": 0, "cancel": threading.Event(), "process": None}
    with STATE_LOCK:
        ACTIVE_JOB = job
        if not automatic:
            STATE["screen"] = "operation"
            STATE["route_stack"].append("ytdlp:operation")
    command("background", timeout=BACKGROUND_GRACE_SECONDS)
    if not automatic:
        render_operation(job, page_history="push")
    worker = threading.Thread(target=run_update, args=(job,), name="ytdlp-update", daemon=False)
    job["thread"] = worker
    worker.start()


# ---------------------------------------------------------------------------
# Routing and event handling


def set_query_empty() -> None:
    STATE["query"] = ""
    command("setQuery", text="")


def route_push(route: str) -> None:
    if not STATE["route_stack"] or STATE["route_stack"][-1] != route:
        STATE["route_stack"].append(route)


def go_home(history: str = "replace") -> None:
    STATE["screen"] = "home"
    STATE["detail_id"] = None
    STATE["route_stack"] = ["ytdlp:home"]
    set_query_empty()
    render_home(0, history)


def go_download(seed: str = "", history: str = "push") -> None:
    STATE["screen"] = "download"
    route_push("ytdlp:download")
    set_query_empty()
    render_download_form(0, seed=seed, history=history)


def go_settings(history: str = "push") -> None:
    STATE["screen"] = "settings"
    route_push("ytdlp:settings")
    set_query_empty()
    render_settings(0, history=history)


def go_history(history: str = "push") -> None:
    STATE["screen"] = "history"
    STATE["query"] = ""
    route_push("ytdlp:history")
    set_query_empty()
    render_history(0, history)


def go_detail(record_id: str, history: str = "push") -> None:
    STATE["screen"] = "detail"
    STATE["detail_id"] = record_id
    route_push("ytdlp:item:" + record_id)
    set_query_empty()
    render_record_detail(record_id, history)


def go_tools(history: str = "push") -> None:
    STATE["screen"] = "tools"
    route_push("ytdlp:tools")
    set_query_empty()
    render_tool_details(0, history)


def render_route(route: str, history: str = "replace") -> None:
    if route == "ytdlp:home":
        STATE["screen"] = "home"
        render_home(0, history)
    elif route == "ytdlp:download":
        STATE["screen"] = "download"
        render_download_form(0, history=history)
    elif route == "ytdlp:settings":
        STATE["screen"] = "settings"
        render_settings(0, history=history)
    elif route == "ytdlp:history":
        STATE["screen"] = "history"
        render_history(0, history)
    elif route == "ytdlp:tools":
        STATE["screen"] = "tools"
        render_tool_details(0, history)
    elif route == "ytdlp:operation" and ACTIVE_JOB:
        STATE["screen"] = "operation"
        render_operation(ACTIVE_JOB)
    elif route.startswith("ytdlp:item:"):
        record_id = route.split(":", 2)[2]
        if find_record(record_id):
            STATE["screen"] = "detail"
            STATE["detail_id"] = record_id
            render_record_detail(record_id, history)
        else:
            go_home()
    elif route == "ytdlp:result" and LAST_RESULT and LAST_RESULT.get("kind") == "download":
        STATE["screen"] = "result"
        render_result(LAST_RESULT)
    elif route == "ytdlp:update-result" and LAST_RESULT and LAST_RESULT.get("kind") == "update":
        STATE["screen"] = "update-result"
        render_update_result(LAST_RESULT)
    else:
        go_home()


def handle_back(message: dict[str, Any]) -> None:
    target = safe_text(message.get("toPageId"))
    stack = STATE["route_stack"]
    if target and target in stack:
        stack[:] = stack[: stack.index(target) + 1]
    elif len(stack) > 1:
        stack.pop()
    target = stack[-1] if stack else "ytdlp:home"
    render_route(target)


def handle_navigate(message: dict[str, Any]) -> None:
    target = safe_text(message.get("targetPageId"), "ytdlp:home")
    stack = STATE["route_stack"]
    if target in stack:
        stack[:] = stack[: stack.index(target) + 1]
    else:
        stack.append(target)
    set_query_empty()
    render_route(target)


def apply_settings(values: dict[str, Any]) -> None:
    executable = safe_text(values.get("executable")).strip()
    if executable and not resolve_executable(executable):
        render_settings(error="The selected yt-dlp executable could not be found.", error_field="executable")
        return
    folder = safe_text(values.get("download_folder")).strip() or default_download_folder()
    folder_path = Path(os.path.expanduser(folder))
    if folder_path.exists() and not folder_path.is_dir():
        render_settings(error="The default download folder points to a file.", error_field="download_folder")
        return
    SETTINGS["executable"] = executable
    SETTINGS["ffmpeg"] = safe_text(values.get("ffmpeg")).strip()
    SETTINGS["download_folder"] = str(folder_path)
    SETTINGS["notifications"] = bool(values.get("notifications", True))
    SETTINGS["auto_open"] = bool(values.get("auto_open", False))
    SETTINGS["update_on_open"] = bool(values.get("update_on_open", True))
    for key in DEFAULT_DOWNLOAD_VALUES:
        if key in values:
            SETTINGS["defaults"][key] = values[key]
    persist_settings()
    TOOL_INFO.update({"path": None, "version": None, "checking": False, "error": None})
    refresh_tool_async()
    command("toast", text="yt-dlp settings saved.", style="success")
    go_home()


def remove_history(ids: list[str]) -> None:
    ids_set = set(ids)
    before = len(HISTORY)
    HISTORY[:] = [record for record in HISTORY if safe_text(record.get("id")) not in ids_set]
    removed = before - len(HISTORY)
    persist_history()
    command("toast", text=f"Removed {removed} history entr{'y' if removed == 1 else 'ies'}.", style="success")
    if STATE["screen"] == "detail":
        go_history(history="replace")
    else:
        render_history(0)


def record_path(record: dict[str, Any]) -> Path | None:
    raw = safe_text(record.get("output_path")).strip()
    if not raw:
        return None
    return Path(os.path.expanduser(raw))


def handle_record_action(record: dict[str, Any], action: str) -> None:
    if action == "default":
        go_detail(safe_text(record.get("id")))
    elif action in {"copy-url", "copy-source"}:
        command("copy", text=safe_text(record.get("url")))
    elif action == "redownload":
        go_download(safe_text(record.get("url")))
    elif action == "open-output":
        path = record_path(record)
        if path and path.exists():
            command("open", path=str(path))
        else:
            command("toast", text="The output file is no longer available.", style="error")
    elif action == "open-folder":
        path = record_path(record)
        folder = path.parent if path else Path(SETTINGS["download_folder"])
        command("open", path=str(folder))
    elif action == "copy-path":
        path = record_path(record)
        if path:
            command("copy", text=str(path))
    elif action == "delete-history":
        remove_history([safe_text(record.get("id"))])
    elif action == "delete-file":
        path = record_path(record)
        if not path:
            return
        try:
            if path.exists() and path.is_file():
                path.unlink()
            record["output_path"] = ""
            persist_history()
            command("toast", text="Output file deleted.", style="success")
            render_record_detail(safe_text(record.get("id")), history="replace")
        except OSError as exc:
            command("toast", text=f"Could not delete output: {truncate(exc, 220)}", style="error")


def handle_action(message: dict[str, Any]) -> None:
    action = safe_text(message.get("action"), "default")
    item_id = safe_text(message.get("id"))
    ids = [safe_text(value) for value in (message.get("ids") or [])]
    if action in {"hide-background", "hide"}:
        if ACTIVE_JOB:
            command("background", timeout=BACKGROUND_GRACE_SECONDS)
            command("hide")
        return
    if action in {"cancel-all", "cancel"}:
        cancel_active_job()
        return
    if action in {"new-download", "quick:new"} or (item_id == "quick:new" and action == "default"):
        go_download()
        return
    if item_id == "quick:query":
        if action == "copy-source":
            command("copy", text=quick_query_to_input(STATE["query"]))
        else:
            go_download(quick_query_to_input(STATE["query"]))
        return
    if item_id == "quick:active":
        if ACTIVE_JOB:
            STATE["screen"] = "operation"
            route_push("ytdlp:operation")
            set_query_empty()
            render_operation(ACTIVE_JOB)
        return
    if item_id == "quick:history" or action == "history":
        go_history()
        return
    if item_id.startswith("history-"):
        record = find_record(item_id)
        if record:
            handle_record_action(record, action)
        return
    if item_id.startswith("download-") and ACTIVE_JOB and ACTIVE_JOB.get("kind") == "download":
        item = next((entry for entry in ACTIVE_JOB.get("items", []) if entry.get("id") == item_id), None)
        if item and action == "copy-url":
            command("copy", text=safe_text(item.get("url")))
        return
    if item_id == "":
        if STATE["screen"] == "detail" and STATE["detail_id"]:
            record = find_record(STATE["detail_id"])
            if record:
                handle_record_action(record, action)
            return
        if action == "settings":
            go_settings()
        elif action in {"tools", "check-tools"}:
            go_tools()
        elif action == "retry-tools":
            TOOL_INFO.update({"path": None, "version": None, "error": None})
            refresh_tool_async()
            if STATE["screen"] == "settings":
                render_settings()
            elif STATE["screen"] == "tools":
                render_tool_details(0)
            else:
                render_home(0)
        elif action == "update":
            start_update()
        elif action == "open-folder":
            command("open", path=str(Path(SETTINGS["download_folder"])))
        elif action == "paste-urls":
            command("clipboardRead", requestId="ytdlp-download-urls")
        elif action == "clear-history":
            HISTORY.clear()
            persist_history()
            command("toast", text="yt-dlp history cleared.", style="success")
            if STATE["screen"] == "history":
                render_history(0)
            else:
                render_home(0)
        elif action == "delete-selected":
            if ids:
                remove_history(ids)
            else:
                command("toast", text="Select one or more history rows first.", style="info")
        elif action == "download-another":
            go_download()
        elif action == "history":
            go_history()
        elif action == "home":
            go_home()
        elif action == "open-output" and LAST_RESULT:
            paths = [record.get("output_path") for record in LAST_RESULT.get("records", []) if record.get("output_path")]
            if len(paths) == 1 and Path(paths[0]).exists():
                command("open", path=paths[0])
        elif action == "copy-path" and LAST_RESULT:
            paths = [record.get("output_path") for record in LAST_RESULT.get("records", []) if record.get("output_path")]
            if len(paths) == 1:
                command("copy", text=paths[0])
        elif action == "copy-error" and LAST_RESULT:
            errors = [safe_text(record.get("error")) for record in LAST_RESULT.get("records", []) if record.get("error")]
            command("copy", text="\n".join(errors))
        return


def handle_query(message: dict[str, Any]) -> None:
    rev = int_value(message.get("rev"), 0)
    STATE["query"] = safe_text(message.get("text", message.get("query", "")))
    if STATE["screen"] == "home":
        render_home(rev)
    elif STATE["screen"] == "history":
        render_history(rev)


def handle_submit(message: dict[str, Any]) -> None:
    values = dict(message.get("values") or {})
    if STATE["screen"] == "download":
        start_download(values, hide_after_start=safe_text(message.get("button")) == "download-hide")
    elif STATE["screen"] == "settings":
        apply_settings(values)


def handle_toolbar_change(message: dict[str, Any]) -> None:
    control_id = safe_text(message.get("id"))
    if control_id == "status":
        values = message.get("values")
        STATE["history_status_filter"] = [safe_text(value) for value in values] if isinstance(values, list) else ([safe_text(message.get("value"))] if message.get("value") else [])
    elif control_id in {"sort", "history_sort"}:
        STATE["history_sort"] = safe_text(message.get("value"), STATE["history_sort"])
        STATE["history_direction"] = safe_text(message.get("direction"), STATE["history_direction"])
    if STATE["screen"] == "history":
        render_history(int_value(message.get("rev"), 0))


def handle_table_sort(message: dict[str, Any]) -> None:
    column = safe_text(message.get("columnId"), "finished")
    STATE["history_sort"] = column if column in {"title", "status", "format", "finished"} else "finished"
    STATE["history_direction"] = safe_text(message.get("direction"), "desc")
    render_history(int_value(message.get("rev"), 0))


def handle_clipboard(message: dict[str, Any]) -> None:
    if safe_text(message.get("requestId")) != "ytdlp-download-urls":
        return
    clipboard_text = safe_text(message.get("text"))
    if not clipboard_text.strip():
        command("toast", text="Clipboard does not contain text.", style="info")
        return
    STATE["form_values"]["urls"] = clipboard_text
    command("toast", text="URLs pasted from clipboard.", style="success")
    render_download_form(0)


def current_render(rev: int = 0) -> None:
    if STATE["screen"] == "home":
        render_home(rev)
    elif STATE["screen"] == "download":
        render_download_form(rev)
    elif STATE["screen"] == "settings":
        render_settings(rev)
    elif STATE["screen"] == "history":
        render_history(rev)
    elif STATE["screen"] == "detail" and STATE["detail_id"]:
        render_record_detail(STATE["detail_id"])
    elif STATE["screen"] == "operation" and ACTIVE_JOB:
        render_operation(ACTIVE_JOB)
    elif STATE["screen"] == "tools":
        render_tool_details(rev)
    elif STATE["screen"] == "result" and LAST_RESULT:
        render_result(LAST_RESULT)
    elif STATE["screen"] == "update-result" and LAST_RESULT:
        render_update_result(LAST_RESULT)
    else:
        go_home()


def handle_message(message: dict[str, Any]) -> bool:
    message_type = safe_text(message.get("type"))
    if message_type == "close":
        set_ui_closed(True)
        # Returning lets the main stdin loop finish.  A non-daemon worker keeps
        # Python alive while the previously requested background grace applies.
        return False
    if message_type == "init":
        set_ui_closed(False)
        STATE["query"] = safe_text(message.get("query"))
        request_storage()
        refresh_tool_async(startup=True)
        current_render(0)
    elif message_type == "query":
        handle_query(message)
    elif message_type == "submit":
        handle_submit(message)
    elif message_type == "submitQuery":
        STATE["query"] = safe_text(message.get("text"))
        go_download(quick_query_to_input(STATE["query"]))
    elif message_type == "action":
        handle_action(message)
    elif message_type == "cancel":
        cancel_active_job()
    elif message_type == "back":
        handle_back(message)
    elif message_type == "navigate":
        handle_navigate(message)
    elif message_type == "storage":
        handle_storage(message)
    elif message_type == "clipboard":
        handle_clipboard(message)
    elif message_type == "toolbarChange":
        handle_toolbar_change(message)
    elif message_type == "tableSort":
        handle_table_sort(message)
    elif message_type == "select":
        STATE["selected_id"] = safe_text(message.get("id"))
    elif message_type == "loadMore":
        if STATE["screen"] == "history":
            render_history(int_value(message.get("rev"), 0))
    return True


def error_frame(error: Any) -> None:
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "detail": {"wide": True, "markdown": f"# Plugin error\n\n```text\n{safe_text(error)}\n```"},
        }
    )


def main() -> None:
    try:
        for raw_line in sys.stdin:
            line = raw_line.strip()
            if not line:
                continue
            try:
                message = json.loads(line)
                if not isinstance(message, dict):
                    raise ValueError("Tabame message must be a JSON object.")
                if not handle_message(message):
                    break
            except json.JSONDecodeError as exc:
                log(f"Invalid JSON from Tabame: {exc}")
                error_frame(exc)
            except Exception as exc:
                log(f"Unhandled message error: {exc}")
                error_frame(exc)
        else:
            log("lifecycle: stdin reached EOF before close")
    finally:
        set_ui_closed(True)


if __name__ == "__main__":
    main()
