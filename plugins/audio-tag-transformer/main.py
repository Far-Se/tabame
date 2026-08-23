#!/usr/bin/env python3
"""Audio Tag Transformer - a visual batch editor for Tabame.

The plugin deliberately keeps the protocol layer at the bottom of the file
and the media/recipe code independent from it.  All protocol output is a
newline-delimited JSON frame or command on stdout; diagnostics go to stderr.
"""

from __future__ import annotations

import copy
import datetime as _datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import threading
import uuid
from dataclasses import dataclass, field
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple


try:
    from mutagen.flac import FLAC
    from mutagen.id3 import COMM, ID3, ID3NoHeaderError
    from mutagen.id3 import TALB, TCOM, TCON, TDRC, TIT2, TPE1, TPE2, TPOS, TRCK

    MUTAGEN_ERROR = ""
except Exception as exc:  # The host normally installs mutagen from plugin.json.
    FLAC = None
    ID3 = None
    ID3NoHeaderError = Exception
    COMM = TALB = TCOM = TCON = TDRC = TIT2 = TPE1 = TPE2 = TPOS = TRCK = None
    MUTAGEN_ERROR = f"The mutagen dependency is unavailable: {exc}"


# ---------------------------------------------------------------------------
# Constants and application state

PLUGIN_NAME = "Audio Tag Transformer"

SOURCE_FIELDS = [
    "FileName",
    "FileStem",
    "Extension",
    "FullPath",
    "Directory",
    "ParentFolder",
    "FileSize",
    "Created",
    "Modified",
    "Title",
    "Artist",
    "Album",
    "AlbumArtist",
    "TrackNumber",
    "DiscNumber",
    "Date",
    "Genre",
    "Composer",
    "Comment",
]
SOURCE_LOOKUP = {name.casefold(): name for name in SOURCE_FIELDS}

OUTPUT_TARGETS = [
    ("Filename", "Filename"),
    ("Title", "Title"),
    ("Artist", "Artist"),
    ("Album", "Album"),
    ("Album Artist", "AlbumArtist"),
    ("Track Number", "TrackNumber"),
    ("Disc Number", "DiscNumber"),
    ("Date", "Date"),
    ("Genre", "Genre"),
    ("Composer", "Composer"),
    ("Comment", "Comment"),
]
OUTPUT_TARGET_LOOKUP = {value.casefold(): value for _label, value in OUTPUT_TARGETS}

MODE_OPTIONS = [
    ("Extract", "extract"),
    ("Replace first", "replace_first"),
    ("Replace all", "replace_all"),
]
NO_MATCH_OPTIONS = [
    ("Error and skip file", "error"),
    ("Return an empty string", "empty"),
    ("Return original source", "original"),
]
NO_VALUE_OPTIONS = [
    ("Error and skip file", "error"),
    ("Skip empty result", "skip"),
    ("Write an empty audio tag", "allow"),
]
COLLISION_OPTIONS = [
    ("Skip collision", "skip"),
    ("Append numeric suffix", "suffix"),
]

RESERVED_WINDOWS_NAMES = {
    "CON",
    "PRN",
    "AUX",
    "NUL",
    *(f"COM{i}" for i in range(1, 10)),
    *(f"LPT{i}" for i in range(1, 10)),
}

DEFAULT_OUTPUT = {
    "template": "{1}",
    "target": "Filename",
    "trim": True,
    "collapse_whitespace": True,
    "no_value": "error",
    "collision": "skip",
}


class RecipeError(Exception):
    """A user-facing recipe or transformation validation error."""


class NoMatchError(RecipeError):
    pass


class ApplySkip(Exception):
    """An apply-time condition that should be reported as skipped."""


@dataclass
class FileRecord:
    file_id: str
    path: str
    canonical: str
    extension: str
    snapshot: Dict[str, str]
    stat_size: int
    stat_mtime_ns: int
    stat_ctime_ns: int
    include: bool = True
    load_error: str = ""


def new_rule(name: str = "New rule") -> Dict[str, Any]:
    return {
        "id": f"r-{uuid.uuid4().hex}",
        "name": name,
        "source": "FileName",
        "pattern": "(.+)",
        "flags": "",
        "mode": "extract",
        "replacement": "$1",
        "no_match": "error",
    }


STATE: Dict[str, Any] = {
    "page_id": "atag:load",
    "route_stack": ["atag:load"],
    "files": {},
    "file_query": "",
    "load_mode": "replace",
    "load_draft": {"files": [], "folder": "", "recursive": False},
    "load_notice": "",
    "rules": [],
    "output": copy.deepcopy(DEFAULT_OUTPUT),
    "rule_draft": {},
    "editing_rule_id": None,
    "output_draft": {},
    "save_draft": {"name": ""},
    "saved_recipes": {},
    "saved_query": "",
    "pending_recipe_requests": {},
    "preview_plans": {},
    "preview_order": [],
    "preview_query": "",
    "preview_loading": False,
    "preview_generation": 0,
    "preview_error": "",
    "apply_active": False,
    "apply_cancel": None,
    "apply_completed": 0,
    "apply_total": 0,
    "apply_detail": "",
    "apply_results": [],
    "closing": False,
    "scan_generation": 0,
    "scan_cancel": None,
}

STATE_LOCK = threading.RLock()
SEND_LOCK = threading.Lock()
STOP_EVENT = threading.Event()


# ---------------------------------------------------------------------------
# Protocol output and small presentation helpers


def log(*values: Any) -> None:
    print(*values, file=sys.stderr, flush=True)


def send(message: Dict[str, Any]) -> None:
    """Write one protocol object without interleaving worker-thread output."""
    if STOP_EVENT.is_set() and message.get("type") == "render":
        return
    line = json.dumps(message, ensure_ascii=False, separators=(",", ":"))
    with SEND_LOCK:
        try:
            sys.stdout.write(line + "\n")
            sys.stdout.flush()
        except (BrokenPipeError, OSError):
            STOP_EVENT.set()


def send_command(command: str, **fields: Any) -> None:
    message = {"type": "command", "command": command}
    message.update(fields)
    send(message)


def page_title(page_id: str) -> str:
    if page_id == "atag:load":
        return "Load audio files"
    if page_id == "atag:files":
        return "Audio files"
    if page_id == "atag:recipe":
        return "Recipe"
    if page_id.startswith("atag:rule:"):
        return "Edit rule"
    if page_id == "atag:output":
        return "Output settings"
    if page_id == "atag:preview":
        return "Preview"
    if page_id.startswith("atag:preview:"):
        return "File preview"
    if page_id == "atag:apply":
        return "Apply changes"
    if page_id == "atag:result":
        return "Result"
    if page_id.startswith("atag:result:"):
        return "Result detail"
    if page_id == "atag:save":
        return "Save recipe"
    if page_id == "atag:recipes":
        return "Saved recipes"
    return PLUGIN_NAME


def breadcrumbs_for(page_id: str) -> List[Dict[str, str]]:
    load = {"id": "atag:load", "label": "Load"}
    files = {"id": "atag:files", "label": "Files"}
    recipe = {"id": "atag:recipe", "label": "Recipe"}
    output = {"id": "atag:output", "label": "Output"}
    if page_id == "atag:load":
        return []
    if page_id == "atag:files":
        return [load]
    if page_id == "atag:recipe":
        return [load, files]
    if page_id.startswith("atag:rule:") or page_id == "atag:save":
        return [load, files, recipe]
    if page_id == "atag:output":
        return [load, files, recipe]
    if page_id == "atag:preview":
        return [load, files, recipe, output]
    if page_id.startswith("atag:preview:"):
        return [load, files, recipe]
    if page_id == "atag:apply":
        return [load, files, recipe]
    if page_id == "atag:result" or page_id.startswith("atag:result:"):
        return [load, files]
    if page_id == "atag:recipes":
        return [load]
    return []


def make_page(page_id: str, history: str = "none", preserve: bool = True) -> Dict[str, Any]:
    page = {
        "id": page_id,
        "title": page_title(page_id),
        "history": history,
        "preserveState": preserve,
    }
    ancestors = breadcrumbs_for(page_id)
    if ancestors:
        page["breadcrumbs"] = ancestors
    return page


def render(
    view: str,
    rev: int = 0,
    page_id: Optional[str] = None,
    history: str = "none",
    preserve: bool = True,
    **payload: Any,
) -> None:
    with STATE_LOCK:
        actual_page = page_id or STATE["page_id"]
    frame: Dict[str, Any] = {
        "type": "render",
        "rev": int(rev or 0),
        "view": view,
        "page": make_page(actual_page, history, preserve),
    }
    frame.update(payload)
    send(frame)


def render_error(message: str, rev: int = 0, page_id: Optional[str] = None, title: str = "Could not continue") -> None:
    safe = str(message).replace("```", "'''\u200b")
    render(
        "detail",
        rev=rev,
        page_id=page_id,
        detail={"markdown": f"# {title}\n\n{safe}"},
        canGoBack=page_id not in (None, "atag:load"),
        actions=[{"id": "back", "title": "Back", "icon": "open"}],
    )


def shorten(value: Any, limit: int = 84) -> str:
    text = "" if value is None else str(value)
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) <= limit:
        return text
    return text[: max(1, limit - 1)] + "…"


def display_option_list(options: Sequence[Tuple[str, str]]) -> List[Dict[str, str]]:
    return [{"value": value, "label": label} for label, value in options]


def md_code(value: Any) -> str:
    text = "" if value is None else str(value)
    return "`" + text.replace("`", "'") + "`"


def normalize_bool(value: Any, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    return str(value).strip().casefold() in {"1", "true", "yes", "on"}


def friendly_exception(exc: BaseException) -> str:
    text = str(exc).strip()
    return f"{type(exc).__name__}: {text}" if text else type(exc).__name__


# ---------------------------------------------------------------------------
# Filesystem and audio-tag snapshots


def canonical_path(value: Any) -> str:
    if not isinstance(value, str):
        return ""
    text = os.path.expandvars(os.path.expanduser(value.strip().strip('"')))
    if not text:
        return ""
    return os.path.realpath(os.path.abspath(text))


def path_key(path: str) -> str:
    return os.path.normcase(os.path.realpath(os.path.abspath(path)))


def make_file_id(path: str) -> str:
    digest = hashlib.sha1(path_key(path).encode("utf-8", "replace")).hexdigest()
    return f"file-{digest[:20]}"


def supported_audio_file(path: str) -> bool:
    return os.path.splitext(path)[1].casefold() in {".mp3", ".flac"}


def file_timestamp(timestamp: float) -> str:
    try:
        return _datetime.datetime.fromtimestamp(timestamp).isoformat(timespec="seconds")
    except (OverflowError, OSError, ValueError):
        return ""


def values_as_strings(value: Any) -> List[str]:
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return [str(item) for item in value if item is not None]
    return [str(value)]


def join_tag_values(values: Iterable[Any]) -> str:
    parts: List[str] = []
    for value in values:
        parts.extend(values_as_strings(value))
    return "; ".join(part for part in parts if part != "")


def read_id3_text(tags: Any, frame_id: str) -> str:
    values: List[Any] = []
    for frame in tags.getall(frame_id):
        values.extend(values_as_strings(getattr(frame, "text", frame)))
    return join_tag_values(values)


def read_id3_comments(tags: Any) -> str:
    values: List[Any] = []
    for frame in tags.getall("COMM"):
        values.extend(values_as_strings(getattr(frame, "text", frame)))
    return join_tag_values(values)


def read_vorbis_value(tags: Any, aliases: Iterable[str]) -> str:
    wanted = {alias.casefold() for alias in aliases}
    values: List[Any] = []
    for key, value in (tags or {}).items():
        if str(key).casefold() in wanted:
            values.extend(values_as_strings(value))
    return join_tag_values(values)


def read_audio_tags(path: str) -> Dict[str, str]:
    if MUTAGEN_ERROR:
        raise RecipeError(MUTAGEN_ERROR)
    if ID3 is None or FLAC is None:
        raise RecipeError("The mutagen dependency is unavailable.")

    extension = os.path.splitext(path)[1].casefold()
    result = {field_name: "" for field_name in SOURCE_FIELDS[9:]}
    if extension == ".mp3":
        try:
            tags = ID3(path)
        except ID3NoHeaderError:
            return result
        result.update(
            {
                "Title": read_id3_text(tags, "TIT2"),
                "Artist": read_id3_text(tags, "TPE1"),
                "Album": read_id3_text(tags, "TALB"),
                "AlbumArtist": read_id3_text(tags, "TPE2"),
                "TrackNumber": read_id3_text(tags, "TRCK"),
                "DiscNumber": read_id3_text(tags, "TPOS"),
                "Date": read_id3_text(tags, "TDRC") or read_id3_text(tags, "TYER"),
                "Genre": read_id3_text(tags, "TCON"),
                "Composer": read_id3_text(tags, "TCOM"),
                "Comment": read_id3_comments(tags),
            }
        )
        return result

    if extension == ".flac":
        audio = FLAC(path)
        tags = audio.tags or {}
        result.update(
            {
                "Title": read_vorbis_value(tags, ["TITLE"]),
                "Artist": read_vorbis_value(tags, ["ARTIST"]),
                "Album": read_vorbis_value(tags, ["ALBUM"]),
                "AlbumArtist": read_vorbis_value(tags, ["ALBUMARTIST", "ALBUM ARTIST"]),
                "TrackNumber": read_vorbis_value(tags, ["TRACKNUMBER", "TRACK"]),
                "DiscNumber": read_vorbis_value(tags, ["DISCNUMBER", "DISC"]),
                "Date": read_vorbis_value(tags, ["DATE", "YEAR"]),
                "Genre": read_vorbis_value(tags, ["GENRE"]),
                "Composer": read_vorbis_value(tags, ["COMPOSER"]),
                "Comment": read_vorbis_value(tags, ["COMMENT", "DESCRIPTION"]),
            }
        )
        return result

    raise RecipeError(f"Unsupported audio format: {os.path.splitext(path)[1]}")


def read_snapshot(path: str) -> FileRecord:
    canonical = canonical_path(path)
    if not canonical or not os.path.isfile(canonical):
        raise OSError(f"File not found: {path}")
    if not supported_audio_file(canonical):
        raise RecipeError("Only .mp3 and .flac files are supported.")

    stat = os.stat(canonical)
    path_obj = Path(canonical)
    extension = path_obj.suffix.lstrip(".").lower()
    snapshot: Dict[str, str] = {
        "FileName": path_obj.name,
        "FileStem": path_obj.stem,
        "Extension": extension,
        "FullPath": canonical,
        "Directory": str(path_obj.parent),
        "ParentFolder": path_obj.parent.name,
        "FileSize": str(stat.st_size),
        "Created": file_timestamp(getattr(stat, "st_ctime", 0.0)),
        "Modified": file_timestamp(getattr(stat, "st_mtime", 0.0)),
    }
    tag_error = ""
    try:
        snapshot.update(read_audio_tags(canonical))
    except Exception as exc:
        # Keep the file visible so the user can see why it is blocked in preview.
        tag_error = f"Could not read audio tags: {friendly_exception(exc)}"
        for field_name in SOURCE_FIELDS[9:]:
            snapshot.setdefault(field_name, "")

    return FileRecord(
        file_id=make_file_id(canonical),
        path=canonical,
        canonical=canonical,
        extension=extension,
        snapshot=snapshot,
        stat_size=stat.st_size,
        stat_mtime_ns=getattr(stat, "st_mtime_ns", int(stat.st_mtime * 1_000_000_000)),
        stat_ctime_ns=getattr(stat, "st_ctime_ns", int(stat.st_ctime * 1_000_000_000)),
        load_error=tag_error,
    )


def discover_paths(file_paths: Sequence[str], folder_paths: Sequence[str], recursive: bool) -> Tuple[List[str], List[str]]:
    discovered: List[str] = []
    warnings: List[str] = []
    seen: set = set()

    def add_file(path: str) -> None:
        canonical = canonical_path(path)
        if not canonical:
            return
        key = path_key(canonical)
        if key in seen:
            return
        seen.add(key)
        if not os.path.isfile(canonical):
            warnings.append(f"File not found: {canonical}")
            return
        if not supported_audio_file(canonical):
            warnings.append(f"Skipped unsupported file: {os.path.basename(canonical)}")
            return
        discovered.append(canonical)

    def add_folder(folder: str) -> None:
        canonical = canonical_path(folder)
        if not canonical or not os.path.isdir(canonical):
            warnings.append(f"Folder not found: {folder}")
            return
        try:
            if recursive:
                def on_walk_error(exc: OSError) -> None:
                    warnings.append(f"Could not scan {getattr(exc, 'filename', canonical)}: {friendly_exception(exc)}")

                for root, dirs, filenames in os.walk(canonical, topdown=True, followlinks=False, onerror=on_walk_error):
                    dirs.sort(key=str.casefold)
                    for filename in sorted(filenames, key=str.casefold):
                        add_file(os.path.join(root, filename))
            else:
                for filename in sorted(os.listdir(canonical), key=str.casefold):
                    add_file(os.path.join(canonical, filename))
        except OSError as exc:
            warnings.append(f"Could not scan {canonical}: {friendly_exception(exc)}")

    for path in file_paths:
        add_file(path)
    for folder in folder_paths:
        add_folder(folder)
    return discovered, warnings


def merge_records(records: Sequence[FileRecord], replace: bool) -> None:
    with STATE_LOCK:
        current = {} if replace else dict(STATE["files"])
        for record in records:
            current[record.file_id] = record
        STATE["files"] = current


def start_scan(file_paths: Sequence[str], folder_paths: Sequence[str], recursive: bool, replace: bool, rev: int = 0) -> None:
    paths = [canonical_path(path) for path in file_paths if canonical_path(path)]
    folders = [canonical_path(path) for path in folder_paths if canonical_path(path)]
    if not paths and not folders:
        with STATE_LOCK:
            STATE["load_notice"] = "Choose files, drop MP3/FLAC files, or choose a folder before scanning."
        render_load(0, error=STATE["load_notice"])
        return

    with STATE_LOCK:
        old_cancel = STATE.get("scan_cancel")
        if old_cancel:
            old_cancel.set()
        cancel_event = threading.Event()
        STATE["scan_cancel"] = cancel_event
        STATE["scan_generation"] += 1
        generation = STATE["scan_generation"]
        STATE["load_notice"] = ""

    render_load(rev, loading=True)

    def worker() -> None:
        try:
            discovered, warnings = discover_paths(paths, folders, recursive)
            records: List[FileRecord] = []
            for index, path in enumerate(discovered):
                if cancel_event.is_set() or STOP_EVENT.is_set():
                    return
                try:
                    records.append(read_snapshot(path))
                except Exception as exc:
                    log("Snapshot failed", path, exc)
                    # A record with a filesystem snapshot is more useful than
                    # silently dropping a malformed media file.
                    try:
                        stat = os.stat(path)
                        path_obj = Path(path)
                        snapshot = {
                            "FileName": path_obj.name,
                            "FileStem": path_obj.stem,
                            "Extension": path_obj.suffix.lstrip(".").lower(),
                            "FullPath": path,
                            "Directory": str(path_obj.parent),
                            "ParentFolder": path_obj.parent.name,
                            "FileSize": str(stat.st_size),
                            "Created": file_timestamp(getattr(stat, "st_ctime", 0.0)),
                            "Modified": file_timestamp(getattr(stat, "st_mtime", 0.0)),
                        }
                        snapshot.update({field_name: "" for field_name in SOURCE_FIELDS[9:]})
                        records.append(
                            FileRecord(
                                file_id=make_file_id(path),
                                path=path,
                                canonical=path,
                                extension=path_obj.suffix.lstrip(".").lower(),
                                snapshot=snapshot,
                                stat_size=stat.st_size,
                                stat_mtime_ns=getattr(stat, "st_mtime_ns", 0),
                                stat_ctime_ns=getattr(stat, "st_ctime_ns", 0),
                                load_error=f"Could not read file: {friendly_exception(exc)}",
                            )
                        )
                    except Exception:
                        warnings.append(f"Could not load {path}: {friendly_exception(exc)}")
                if index % 20 == 0 and STATE.get("page_id") == "atag:load":
                    render_load(0, loading=True, loading_text=f"Reading audio tags… {index + 1}/{len(discovered)}")

            with STATE_LOCK:
                if generation != STATE["scan_generation"] or cancel_event.is_set() or STATE["closing"]:
                    return
                merge_records(records, replace=replace)
                STATE["load_notice"] = ""
                if warnings:
                    STATE["load_notice"] = "  ".join(warnings[:5])
                    if len(warnings) > 5:
                        STATE["load_notice"] += f"  (+{len(warnings) - 5} more)"

            if not records:
                with STATE_LOCK:
                    STATE["load_notice"] = STATE["load_notice"] or "No readable MP3 or FLAC files were found."
                render_load(0, error=STATE["load_notice"])
                return

            navigate_to("atag:files", push=replace, clear_query=True)
        except Exception as exc:
            log("Scan failed", exc)
            with STATE_LOCK:
                STATE["load_notice"] = f"Scan failed: {friendly_exception(exc)}"
            render_load(0, error=STATE["load_notice"])

    threading.Thread(target=worker, name="atag-scan", daemon=True).start()


# ---------------------------------------------------------------------------
# Regex and template engine


def parse_regex_input(pattern_text: Any, flags_text: Any = "") -> Tuple[str, int, str]:
    original = "" if pattern_text is None else str(pattern_text)
    text = original.strip()
    inline_flags = ""
    pattern = text
    if text.startswith("/"):
        closing = -1
        escaped = False
        for index in range(1, len(text)):
            char = text[index]
            if char == "/" and not escaped:
                closing = index
                break
            if char == "\\" and not escaped:
                escaped = True
            else:
                escaped = False
        if closing < 0:
            raise RecipeError("Regex notation starts with '/' but has no closing '/'.")
        pattern = text[1:closing]
        inline_flags = text[closing + 1 :]
        if inline_flags and not re.fullmatch(r"[ims]+", inline_flags):
            bad = next((char for char in inline_flags if char not in "ims"), inline_flags)
            raise RecipeError(f"Unsupported regex flag '{bad}'. Supported flags are i, m, and s.")

        # JavaScript escapes a delimiter as \/.  Remove only that delimiter
        # escape while preserving all other backslashes in the regex.
        unescaped: List[str] = []
        index = 0
        while index < len(pattern):
            if pattern[index] == "\\" and index + 1 < len(pattern) and pattern[index + 1] == "/":
                unescaped.append("/")
                index += 2
            else:
                unescaped.append(pattern[index])
                index += 1
        pattern = "".join(unescaped)

    # Accept JavaScript's named-capture spelling as well as Python's spelling
    # so that $<name> replacements work naturally with /pattern/ notation.
    pattern = re.sub(r"\(\?<([A-Za-z_][A-Za-z0-9_]*)>", r"(?P<\1>", pattern)

    explicit_flags = "" if flags_text is None else str(flags_text).strip()
    combined = "".join(dict.fromkeys(inline_flags + explicit_flags))
    if combined and not re.fullmatch(r"[ims]+", combined):
        bad = next((char for char in combined if char not in "ims"), combined)
        raise RecipeError(f"Unsupported regex flag '{bad}'. Supported flags are i, m, and s.")

    re_flags = 0
    if "i" in combined:
        re_flags |= re.IGNORECASE
    if "m" in combined:
        re_flags |= re.MULTILINE
    if "s" in combined:
        re_flags |= re.DOTALL
    return pattern, re_flags, combined


def compile_rule(rule: Dict[str, Any]) -> Tuple[Any, str]:
    source = SOURCE_LOOKUP.get(str(rule.get("source", "")).casefold())
    if not source:
        raise RecipeError(f"Unknown source field '{rule.get('source', '')}'.")
    pattern, flags, normalized_flags = parse_regex_input(rule.get("pattern", ""), rule.get("flags", ""))
    if pattern == "":
        raise RecipeError("The regex pattern cannot be empty.")
    try:
        compiled = re.compile(pattern, flags)
    except re.error as exc:
        position = getattr(exc, "pos", None)
        suffix = f" at character {position}" if position is not None else ""
        raise RecipeError(f"Invalid regex{suffix}: {exc}") from exc
    return compiled, normalized_flags


def translate_replacement(replacement: Any, compiled: Any) -> str:
    text = "" if replacement is None else str(replacement)
    output: List[str] = []
    index = 0
    group_count = getattr(compiled, "groups", 0)
    group_names = set(getattr(compiled, "groupindex", {}).keys())
    while index < len(text):
        char = text[index]
        if char != "$":
            output.append(char)
            index += 1
            continue
        if index + 1 >= len(text):
            raise RecipeError("Replacement ends with '$'. Use '$$' for a literal dollar sign.")
        next_char = text[index + 1]
        if next_char == "$":
            output.append("$")
            index += 2
            continue
        if next_char == "<":
            closing = text.find(">", index + 2)
            if closing < 0:
                raise RecipeError("Named replacement is missing its closing '>'.")
            name = text[index + 2 : closing]
            if not name or name not in group_names:
                raise RecipeError(f"Replacement references unknown named capture '{name}'.")
            output.append(r"\g<" + name + ">")
            index = closing + 1
            continue
        if next_char.isdigit():
            end = index + 1
            while end < len(text) and text[end].isdigit() and end < index + 3:
                end += 1
            digits = text[index + 1 : end]
            if end < len(text) and text[end].isdigit():
                raise RecipeError("Capture references may contain at most two digits ($0 through $99).")
            number = int(digits)
            if number != 0 and number > group_count:
                raise RecipeError(f"Replacement references ${number}, but the regex has only {group_count} capture group(s).")
            output.append(r"\g<" + str(number) + ">")
            index = end
            continue
        raise RecipeError(f"Invalid replacement sequence '${next_char}'. Use $0, $1-$99, $<name>, or $$.")
    return "".join(output)


def apply_rule(source_value: str, rule: Dict[str, Any]) -> str:
    compiled, _flags = compile_rule(rule)
    replacement = translate_replacement(rule.get("replacement", ""), compiled)
    mode = str(rule.get("mode", "extract"))
    match = compiled.search(source_value)
    if match is None:
        behavior = str(rule.get("no_match", "error"))
        if behavior == "empty":
            return ""
        if behavior == "original":
            return source_value
        raise NoMatchError(f"Rule '{rule.get('name') or rule.get('id')}' found no match in {md_code(source_value)}.")
    if mode == "extract":
        try:
            return match.expand(replacement)
        except (IndexError, re.error) as exc:
            raise RecipeError(f"Could not expand the replacement: {exc}") from exc
    if mode not in {"replace_first", "replace_all"}:
        raise RecipeError(f"Unknown rule mode '{mode}'.")
    try:
        return compiled.sub(replacement, source_value, count=1 if mode == "replace_first" else 0)
    except (IndexError, re.error) as exc:
        raise RecipeError(f"Could not apply the replacement: {exc}") from exc


def parse_template(template: Any, rule_count: int) -> List[Tuple[str, Any]]:
    text = "" if template is None else str(template)
    tokens: List[Tuple[str, Any]] = []
    literal: List[str] = []

    def flush_literal() -> None:
        if literal:
            tokens.append(("literal", "".join(literal)))
            literal.clear()

    index = 0
    while index < len(text):
        if text.startswith("{{", index):
            literal.append("{")
            index += 2
            continue
        if text.startswith("}}", index):
            literal.append("}")
            index += 2
            continue
        char = text[index]
        if char == "{":
            closing = text.find("}", index + 1)
            if closing < 0:
                raise RecipeError("Template has an opening '{' without a closing '}'.")
            name = text[index + 1 : closing]
            if not name:
                raise RecipeError("Template contains an empty placeholder '{}'.")
            flush_literal()
            if name.isdigit():
                number = int(name)
                if number < 1 or number > rule_count:
                    raise RecipeError(f"Template references rule {{{number}}}, but the recipe has {rule_count} rule(s).")
                tokens.append(("rule", number))
            else:
                source = SOURCE_LOOKUP.get(name.casefold())
                if not source:
                    raise RecipeError(f"Unknown template placeholder '{{{name}}}'. Use a source field or a rule token such as {{1}}.")
                tokens.append(("source", source))
            index = closing + 1
            continue
        if char == "}":
            raise RecipeError("Template has a single '}'. Use '}}' for a literal closing brace.")
        literal.append(char)
        index += 1
    flush_literal()
    return tokens


def expand_template(tokens: Sequence[Tuple[str, Any]], snapshot: Dict[str, str], rule_outputs: Dict[int, str]) -> str:
    parts: List[str] = []
    for kind, value in tokens:
        if kind == "literal":
            parts.append(str(value))
        elif kind == "source":
            parts.append(snapshot.get(str(value), ""))
        else:
            parts.append(rule_outputs.get(int(value), ""))
    return "".join(parts)


def cleanup_output(value: str, output: Dict[str, Any]) -> str:
    result = value
    if normalize_bool(output.get("collapse_whitespace"), True):
        result = re.sub(r"\s+", " ", result)
    if normalize_bool(output.get("trim"), True):
        result = result.strip()
    return result


def validate_rule_values(values: Dict[str, Any]) -> Tuple[Dict[str, Any], Dict[str, str]]:
    normalized = {
        "id": str(values.get("id") or f"r-{uuid.uuid4().hex}"),
        "name": str(values.get("name") or "").strip(),
        "source": SOURCE_LOOKUP.get(str(values.get("source") or "").casefold(), ""),
        "pattern": str(values.get("pattern") or ""),
        "flags": str(values.get("flags") or "").strip(),
        "mode": str(values.get("mode") or "extract"),
        "replacement": str(values.get("replacement") or ""),
        "no_match": str(values.get("no_match") or "error"),
    }
    errors: Dict[str, str] = {}
    if not normalized["name"]:
        errors["name"] = "Give the rule a display name."
    if not normalized["source"]:
        errors["source"] = "Choose a valid source field."
    if not normalized["pattern"].strip():
        errors["pattern"] = "Enter a regex pattern."
    if normalized["mode"] not in {value for _label, value in MODE_OPTIONS}:
        errors["mode"] = "Choose Extract, Replace first, or Replace all."
    if normalized["no_match"] not in {value for _label, value in NO_MATCH_OPTIONS}:
        errors["no_match"] = "Choose a no-match behavior."
    if not errors:
        try:
            compiled, _flags = compile_rule(normalized)
            translate_replacement(normalized["replacement"], compiled)
        except RecipeError as exc:
            message = str(exc)
            if "replacement" in message.casefold() or "capture" in message.casefold() or "dollar" in message.casefold():
                errors["replacement"] = message
            elif "flag" in message.casefold():
                errors["flags"] = message
            else:
                errors["pattern"] = message
    return normalized, errors


def validate_output_values(values: Dict[str, Any], rule_count: int) -> Tuple[Dict[str, Any], Dict[str, str]]:
    normalized = {
        "template": "" if values.get("template") is None else str(values.get("template")),
        "target": OUTPUT_TARGET_LOOKUP.get(str(values.get("target") or "").casefold(), ""),
        "trim": normalize_bool(values.get("trim"), True),
        "collapse_whitespace": normalize_bool(values.get("collapse_whitespace"), True),
        "no_value": str(values.get("no_value") or "error"),
        "collision": str(values.get("collision") or "skip"),
    }
    errors: Dict[str, str] = {}
    if not normalized["target"]:
        errors["target"] = "Choose an output target."
    if normalized["no_value"] not in {value for _label, value in NO_VALUE_OPTIONS}:
        errors["no_value"] = "Choose a no-value policy."
    if normalized["collision"] not in {value for _label, value in COLLISION_OPTIONS}:
        errors["collision"] = "Choose a filename collision policy."
    try:
        parse_template(normalized["template"], rule_count)
    except RecipeError as exc:
        errors["template"] = str(exc)
    return normalized, errors


# ---------------------------------------------------------------------------
# Preview planning and safe output operations


def sanitize_windows_stem(value: str) -> Tuple[str, List[str]]:
    if value in {"", ".", ".."}:
        raise RecipeError("The transformed filename stem is empty.")
    if value.endswith((".", " ")):
        raise RecipeError("Windows filenames cannot end with a dot or space.")
    sanitized = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", value)
    warnings: List[str] = []
    if sanitized != value:
        warnings.append("Windows-invalid filename characters were replaced with '_'.")
    if not sanitized or sanitized in {".", ".."}:
        raise RecipeError("The transformed filename stem is empty after sanitization.")
    reserved_base = sanitized.split(".", 1)[0].upper()
    if reserved_base in RESERVED_WINDOWS_NAMES:
        raise RecipeError(f"'{sanitized}' is a reserved Windows filename.")
    return sanitized, warnings


def numeric_candidate(path: str, occupied: set) -> str:
    stem, extension = os.path.splitext(path)
    for index in range(1, 100000):
        candidate = f"{stem} ({index}){extension}"
        if path_key(candidate) not in occupied and not os.path.lexists(candidate):
            return candidate
    raise RecipeError("Could not find an available numeric filename suffix.")


def evaluate_file(record: FileRecord, rules: Sequence[Dict[str, Any]], output: Dict[str, Any]) -> Dict[str, Any]:
    plan: Dict[str, Any] = {
        "file_id": record.file_id,
        "path": record.path,
        "filename": os.path.basename(record.path),
        "target": output.get("target", "Filename"),
        "snapshot": copy.deepcopy(record.snapshot),
        "rule_outputs": {},
        "expanded_template": "",
        "current_value": "",
        "proposed_value": "",
        "proposed_path": "",
        "warnings": [],
        "error": "",
        "status": "valid",
    }
    if record.load_error:
        raise RecipeError(record.load_error)

    tokens = parse_template(output.get("template", ""), len(rules))
    rule_outputs: Dict[int, str] = {}
    for number, rule in enumerate(rules, start=1):
        source_name = SOURCE_LOOKUP.get(str(rule.get("source", "")).casefold())
        if not source_name:
            raise RecipeError(f"Rule {number} has an unknown source field.")
        source_value = record.snapshot.get(source_name, "")
        rule_outputs[number] = apply_rule(source_value, rule)

    expanded = expand_template(tokens, record.snapshot, rule_outputs)
    final_value = cleanup_output(expanded, output)
    plan["rule_outputs"] = {str(number): value for number, value in rule_outputs.items()}
    plan["expanded_template"] = final_value

    if final_value == "":
        no_value = output.get("no_value", "error")
        if no_value == "skip":
            plan["status"] = "skipped"
            plan["warnings"].append("The final value is empty; skipped by the no-value policy.")
        elif no_value == "allow" and output.get("target") != "Filename":
            plan["warnings"].append("The final value is empty; an empty audio tag will be written.")
        else:
            raise RecipeError("The final template produced no value.")

    target = output.get("target", "Filename")
    if target == "Filename":
        plan["current_value"] = os.path.basename(record.path)
        if plan["status"] == "skipped":
            return plan
        stem, warnings = sanitize_windows_stem(final_value)
        plan["warnings"].extend(warnings)
        extension = os.path.splitext(record.path)[1]
        proposed_path = os.path.join(os.path.dirname(record.path), stem + extension)
        plan["proposed_path"] = proposed_path
        plan["proposed_value"] = os.path.basename(proposed_path)
        if path_key(proposed_path) == path_key(record.path):
            plan["status"] = "unchanged"
        return plan

    plan["current_value"] = record.snapshot.get(target, "")
    plan["proposed_value"] = final_value
    if plan["current_value"] == plan["proposed_value"]:
        plan["status"] = "unchanged"
    return plan


def apply_filename_collision_policy(plans: List[Dict[str, Any]], records: Sequence[FileRecord], policy: str) -> None:
    existing = {path_key(record.path) for record in records}
    reserved: set = set()
    for plan in plans:
        if plan.get("status") != "valid" or not plan.get("proposed_path"):
            continue
        source_key = path_key(plan["path"])
        candidate = plan["proposed_path"]
        candidate_key = path_key(candidate)
        conflict = candidate_key in reserved or (candidate_key in existing and candidate_key != source_key)
        if conflict:
            if policy == "suffix":
                candidate = numeric_candidate(candidate, existing | reserved)
                plan["warnings"].append("A collision was resolved with a numeric suffix.")
                plan["proposed_path"] = candidate
                plan["proposed_value"] = os.path.basename(candidate)
                candidate_key = path_key(candidate)
            else:
                plan["status"] = "collision"
                plan["error"] = f"The proposed filename already exists: {os.path.basename(candidate)}"
                continue
        reserved.add(candidate_key)


def create_preview_plans(records: Sequence[FileRecord], rules: Sequence[Dict[str, Any]], output: Dict[str, Any]) -> Tuple[List[Dict[str, Any]], str]:
    plans: List[Dict[str, Any]] = []
    global_error = ""
    try:
        parse_template(output.get("template", ""), len(rules))
        for rule in rules:
            compiled, _flags = compile_rule(rule)
            translate_replacement(rule.get("replacement", ""), compiled)
    except RecipeError as exc:
        global_error = str(exc)

    for record in records:
        if not record.include:
            plans.append(
                {
                    "file_id": record.file_id,
                    "path": record.path,
                    "filename": os.path.basename(record.path),
                    "target": output.get("target", "Filename"),
                    "snapshot": copy.deepcopy(record.snapshot),
                    "rule_outputs": {},
                    "expanded_template": "",
                    "current_value": record.snapshot.get(output.get("target", "Filename"), os.path.basename(record.path))
                    if output.get("target") != "Filename"
                    else os.path.basename(record.path),
                    "proposed_value": "",
                    "proposed_path": "",
                    "warnings": ["Excluded from the current batch."],
                    "error": "",
                    "status": "excluded",
                }
            )
            continue
        if global_error:
            plan = {
                "file_id": record.file_id,
                "path": record.path,
                "filename": os.path.basename(record.path),
                "target": output.get("target", "Filename"),
                "snapshot": copy.deepcopy(record.snapshot),
                "rule_outputs": {},
                "expanded_template": "",
                "current_value": "",
                "proposed_value": "",
                "proposed_path": "",
                "warnings": [],
                "error": global_error,
                "status": "error",
            }
            plans.append(plan)
            continue
        try:
            plans.append(evaluate_file(record, rules, output))
        except Exception as exc:
            plans.append(
                {
                    "file_id": record.file_id,
                    "path": record.path,
                    "filename": os.path.basename(record.path),
                    "target": output.get("target", "Filename"),
                    "snapshot": copy.deepcopy(record.snapshot),
                    "rule_outputs": {},
                    "expanded_template": "",
                    "current_value": record.snapshot.get(output.get("target", ""), "")
                    if output.get("target") != "Filename"
                    else os.path.basename(record.path),
                    "proposed_value": "",
                    "proposed_path": "",
                    "warnings": [],
                    "error": str(exc),
                    "status": "error",
                }
            )

    if output.get("target") == "Filename" and not global_error:
        apply_filename_collision_policy(plans, records, str(output.get("collision", "skip")))
    return plans, global_error


def current_stat_matches(record: FileRecord) -> bool:
    try:
        stat = os.stat(record.path)
    except OSError:
        return False
    return (
        stat.st_size == record.stat_size
        and getattr(stat, "st_mtime_ns", int(stat.st_mtime * 1_000_000_000)) == record.stat_mtime_ns
        and getattr(stat, "st_ctime_ns", int(stat.st_ctime * 1_000_000_000)) == record.stat_ctime_ns
    )


def safe_rename_no_overwrite(source: str, destination: str) -> None:
    if path_key(source) == path_key(destination):
        return
    if os.path.lexists(destination):
        raise FileExistsError(f"The destination already exists: {destination}")
    if os.name == "nt":
        # Windows os.rename does not replace an existing destination.  The
        # existence check plus this non-replacing primitive avoids os.replace.
        os.rename(source, destination)
        return
    # On POSIX, os.rename may replace a file.  A hard-link followed by unlink
    # gives the same-file rename behavior while refusing an occupied target.
    os.link(source, destination)
    try:
        os.unlink(source)
    except Exception:
        # The source is still intact at this point; leave the safe new link.
        raise


def write_tag_atomically(record: FileRecord, target: str, value: str) -> None:
    if not current_stat_matches(record):
        raise RecipeError("The file changed after preview; it was not modified.")
    source = record.path
    directory = os.path.dirname(source)
    fd, temp_path = tempfile.mkstemp(prefix=".atag-", suffix=os.path.splitext(source)[1], dir=directory)
    os.close(fd)
    try:
        shutil.copy2(source, temp_path)
        extension = os.path.splitext(source)[1].casefold()
        if extension == ".mp3":
            tags = None
            try:
                tags = ID3(temp_path)
            except ID3NoHeaderError:
                tags = ID3()
            if target == "Title":
                tags.delall("TIT2")
                tags.add(TIT2(encoding=3, text=[value]))
            elif target == "Artist":
                tags.delall("TPE1")
                tags.add(TPE1(encoding=3, text=[value]))
            elif target == "Album":
                tags.delall("TALB")
                tags.add(TALB(encoding=3, text=[value]))
            elif target == "AlbumArtist":
                tags.delall("TPE2")
                tags.add(TPE2(encoding=3, text=[value]))
            elif target == "TrackNumber":
                tags.delall("TRCK")
                tags.add(TRCK(encoding=3, text=[value]))
            elif target == "DiscNumber":
                tags.delall("TPOS")
                tags.add(TPOS(encoding=3, text=[value]))
            elif target == "Date":
                tags.delall("TDRC")
                tags.delall("TYER")
                tags.add(TDRC(encoding=3, text=[value]))
            elif target == "Genre":
                tags.delall("TCON")
                tags.add(TCON(encoding=3, text=[value]))
            elif target == "Composer":
                tags.delall("TCOM")
                tags.add(TCOM(encoding=3, text=[value]))
            elif target == "Comment":
                tags.delall("COMM")
                tags.add(COMM(encoding=3, lang="eng", desc="", text=[value]))
            else:
                raise RecipeError(f"Unsupported MP3 audio-tag target: {target}")
            tags.save(temp_path)
        elif extension == ".flac":
            audio = FLAC(temp_path)
            if audio.tags is None:
                audio.add_tags()
            tags = audio.tags
            aliases = {
                "Title": {"TITLE"},
                "Artist": {"ARTIST"},
                "Album": {"ALBUM"},
                "AlbumArtist": {"ALBUMARTIST", "ALBUM ARTIST"},
                "TrackNumber": {"TRACKNUMBER", "TRACK"},
                "DiscNumber": {"DISCNUMBER", "DISC"},
                "Date": {"DATE", "YEAR"},
                "Genre": {"GENRE"},
                "Composer": {"COMPOSER"},
                "Comment": {"COMMENT", "DESCRIPTION"},
            }
            wanted = aliases.get(target)
            if not wanted:
                raise RecipeError(f"Unsupported FLAC audio-tag target: {target}")
            for key in list(tags.keys()):
                if str(key).upper() in wanted:
                    del tags[key]
            canonical_key = {
                "Title": "TITLE",
                "Artist": "ARTIST",
                "Album": "ALBUM",
                "AlbumArtist": "ALBUMARTIST",
                "TrackNumber": "TRACKNUMBER",
                "DiscNumber": "DISCNUMBER",
                "Date": "DATE",
                "Genre": "GENRE",
                "Composer": "COMPOSER",
                "Comment": "COMMENT",
            }[target]
            tags[canonical_key] = [value]
            audio.save()
        else:
            raise RecipeError("Only MP3 and FLAC audio tags can be written.")

        if not current_stat_matches(record):
            raise RecipeError("The file changed while its audio tag was being prepared; it was not modified.")
        os.replace(temp_path, source)
    finally:
        if os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except OSError:
                pass


# ---------------------------------------------------------------------------
# Navigation and route rendering


def navigate_to(page_id: str, push: bool = True, clear_query: bool = True, preserve: bool = True) -> None:
    with STATE_LOCK:
        if push and (not STATE["route_stack"] or STATE["route_stack"][-1] != page_id):
            STATE["route_stack"].append(page_id)
        elif not push:
            if page_id in STATE["route_stack"]:
                STATE["route_stack"] = STATE["route_stack"][: STATE["route_stack"].index(page_id) + 1]
            elif STATE["route_stack"]:
                STATE["route_stack"][-1] = page_id
            else:
                STATE["route_stack"] = [page_id]
        STATE["page_id"] = page_id
        if clear_query:
            STATE["file_query"] = ""
            STATE["preview_query"] = ""
            STATE["saved_query"] = ""
    if clear_query:
        send_command("setQuery", text="")
    render_current(0, history="push" if push else "none", preserve=preserve)


def go_back(target: Optional[str] = None) -> None:
    with STATE_LOCK:
        stack = list(STATE["route_stack"])
        if target and target in stack:
            stack = stack[: stack.index(target) + 1]
            page_id = target
        elif len(stack) > 1:
            stack.pop()
            page_id = stack[-1]
        else:
            page_id = "atag:load"
            stack = [page_id]
        STATE["route_stack"] = stack
        STATE["page_id"] = page_id
        STATE["file_query"] = ""
        STATE["preview_query"] = ""
        STATE["saved_query"] = ""
    send_command("setQuery", text="")
    render_current(0, history="none")


def render_current(rev: int = 0, history: str = "none", preserve: bool = True) -> None:
    with STATE_LOCK:
        page_id = STATE["page_id"]
    if page_id == "atag:load":
        render_load(rev, history=history, preserve=preserve)
    elif page_id == "atag:files":
        render_files(rev, history=history, preserve=preserve)
    elif page_id == "atag:recipe":
        render_recipe(rev, history=history, preserve=preserve)
    elif page_id.startswith("atag:rule:"):
        render_rule_form(rev, history=history, preserve=preserve)
    elif page_id == "atag:output":
        render_output_form(rev, history=history, preserve=preserve)
    elif page_id == "atag:preview":
        render_preview(rev, history=history, preserve=preserve)
    elif page_id.startswith("atag:preview:"):
        render_preview_detail(rev, history=history, preserve=preserve)
    elif page_id == "atag:apply":
        render_apply(rev, history=history, preserve=preserve)
    elif page_id == "atag:result":
        render_result(rev, history=history, preserve=preserve)
    elif page_id.startswith("atag:result:"):
        render_result_detail(rev, history=history, preserve=preserve)
    elif page_id == "atag:save":
        render_save_form(rev, history=history, preserve=preserve)
    elif page_id == "atag:recipes":
        render_saved_recipes(rev, history=history, preserve=preserve)
    else:
        with STATE_LOCK:
            STATE["page_id"] = "atag:load"
            STATE["route_stack"] = ["atag:load"]
        render_load(rev, history="replace")


def load_fields() -> List[Dict[str, Any]]:
    with STATE_LOCK:
        draft = copy.deepcopy(STATE["load_draft"])
        mode = STATE["load_mode"]
    return [
        {
            "id": "files",
            "type": "dropzone",
            "label": "MP3 / FLAC files",
            "description": "Drop or choose multiple audio files. Existing files are deduplicated by canonical absolute path.",
            "multiple": True,
            "extensions": ["mp3", "flac"],
            "value": draft.get("files", []) if mode == "append" else [],
        },
        {
            "id": "folder",
            "type": "folderpicker",
            "label": "Folder",
            "description": "Scan this folder for MP3 and FLAC files.",
            "value": draft.get("folder", "") if mode == "append" else "",
        },
        {
            "id": "recursive",
            "type": "checkbox",
            "label": "Scan subfolders recursively",
            "value": normalize_bool(draft.get("recursive"), False),
        },
    ]


def render_load(
    rev: int = 0,
    loading: bool = False,
    loading_text: str = "Reading filenames, filesystem metadata, and audio tags…",
    error: str = "",
    history: str = "none",
    preserve: bool = True,
) -> None:
    with STATE_LOCK:
        mode = STATE["load_mode"]
        notice = error or STATE.get("load_notice", "")
        saved = bool(STATE["saved_recipes"])
    actions = []
    if saved:
        actions.append({"id": "open_saved", "title": "Load saved recipe", "icon": "bookmark"})
    render(
        "form",
        rev=rev,
        page_id="atag:load",
        history=history,
        preserve=preserve,
        placeholder="Choose audio files or a folder…",
        loading=loading,
        loadingText=loading_text if loading else None,
        form={
            "title": "Add files to the current batch" if mode == "append" else "Load audio files",
            "error": notice or None,
            "submitLabel": "Scan and continue",
            "fields": load_fields(),
        },
        dropZone={
            "id": "load-files",
            "label": "Drop MP3 or FLAC files here",
            "hint": "You can also drop a folder and choose recursive scanning.",
            "extensions": ["mp3", "flac"],
            "multiple": True,
        },
        actions=actions,
        canGoBack=mode == "append",
    )


def file_status(record: FileRecord) -> str:
    if not record.include:
        return "Excluded"
    if record.load_error:
        return "Error · " + shorten(record.load_error, 54)
    return "Included · Ready"


def record_matches(record: FileRecord, query: str) -> bool:
    text = query.casefold().strip()
    if not text:
        return True
    values = [record.path, file_status(record)] + [record.snapshot.get(field_name, "") for field_name in SOURCE_FIELDS]
    haystack = "\n".join(str(value).casefold() for value in values)
    return text in haystack


def file_item(record: FileRecord) -> Dict[str, Any]:
    action_toggle = "include" if not record.include else "exclude"
    action_title = "Include in batch" if not record.include else "Exclude from batch"
    status = file_status(record)
    return {
        "id": f"file:{record.file_id}",
        "title": record.snapshot.get("FileName", os.path.basename(record.path)),
        "subtitle": shorten(record.path, 120),
        "icon": "music" if record.extension == "mp3" else "file",
        "cells": {
            "format": record.extension.upper(),
            "title": shorten(record.snapshot.get("Title", ""), 48) or "—",
            "artist": shorten(record.snapshot.get("Artist", ""), 48) or "—",
            "album": shorten(record.snapshot.get("Album", ""), 48) or "—",
            "status": status,
        },
        "actions": [
            {"id": "default", "title": "Open file details", "icon": "open"},
            {"id": action_toggle, "title": action_title, "icon": "check" if action_toggle == "include" else "minus"},
            {"id": "remove", "title": "Remove from batch", "icon": "trash"},
            {"id": "open_folder", "title": "Open containing folder", "icon": "folder"},
            {"id": "copy_path", "title": "Copy full path", "icon": "copy"},
        ],
    }


def render_files(rev: int = 0, history: str = "none", preserve: bool = True) -> None:
    with STATE_LOCK:
        records = list(STATE["files"].values())
        query = STATE["file_query"]
        notice = STATE.get("load_notice", "")
    visible = [record for record in records if record_matches(record, query)]
    empty_payload = {
        "icon": "search" if query else "music",
        "title": "No files match the filter" if query else "No audio files loaded",
        "hint": "Clear the query or add more MP3/FLAC files." if query else "Load a file or folder to begin.",
        "action": {"id": "add_files", "title": "Add files", "icon": "add"},
    }
    actions = [
        {"id": "add_files", "title": "Add files", "icon": "add"},
        {"id": "continue_recipe", "title": "Continue to recipe", "icon": "open"},
    ]
    banners = []
    if notice:
        banners.append({"id": "load-notice", "style": "warning", "title": "Load note", "message": notice, "dismissible": True})
    render(
        "table",
        rev=rev,
        page_id="atag:files",
        history=history,
        preserve=preserve,
        elementId="audio-file-table",
        placeholder="Filter files by filename, path, Title, Artist, or Album…",
        empty=empty_payload,
        banners=banners,
        dropZone={
            "id": "add-files",
            "label": "Drop more MP3 or FLAC files",
            "extensions": ["mp3", "flac"],
            "multiple": True,
        },
        columns=[
            {"id": "format", "label": "Format", "width": 84},
            {"id": "title", "label": "Title", "width": 170},
            {"id": "artist", "label": "Artist", "width": 170},
            {"id": "album", "label": "Album", "width": 170},
            {"id": "status", "label": "Inclusion / status", "width": 190},
        ],
        table={"resizable": True, "stickyHeader": True, "columnVisibility": True},
        selection={"enabled": True, "max": 1000},
        actions=actions,
        floatingAction=[
            {"id": "add_files", "title": "Add files", "icon": "add"},
            {"id": "continue_recipe", "title": "Continue to recipe", "icon": "open"},
        ],
        items=[file_item(record) for record in visible],
    )


def source_metadata(snapshot: Dict[str, str]) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    for field_name in SOURCE_FIELDS:
        rows.append({"label": field_name, "text": snapshot.get(field_name, "") or "—", "icon": "tag" if field_name in SOURCE_FIELDS[9:] else "file"})
    return rows


def render_file_detail(file_id: str, rev: int = 0, history: str = "none", preserve: bool = True) -> None:
    with STATE_LOCK:
        record = STATE["files"].get(file_id)
    if not record:
        render_error("That file is no longer in the current batch.", rev, "atag:files")
        return
    tag_heading = "Included in batch" if record.include else "Excluded from batch"
    body = (
        f"# {record.snapshot.get('FileName', os.path.basename(record.path))}\n\n"
        f"**{tag_heading}**\n\nPath: {md_code(record.path)}\n\n"
        "These are the immutable values captured when the batch was loaded."
    )
    if record.load_error:
        body += f"\n\n> Error: {record.load_error}"
    render(
        "detail",
        rev=rev,
        page_id=f"atag:preview:{file_id}",
        history=history,
        preserve=preserve,
        detail={"markdown": body, "metadata": source_metadata(record.snapshot)},
        actions=[
            {"id": "open_folder", "title": "Open containing folder", "icon": "folder"},
            {"id": "copy_path", "title": "Copy full path", "icon": "copy"},
        ],
        canGoBack=True,
    )


def rule_item(rule: Dict[str, Any], number: int, count: int) -> Dict[str, Any]:
    pattern = str(rule.get("pattern", ""))
    flags = str(rule.get("flags", ""))
    display_pattern = pattern + (f" [{flags}]" if flags else "")
    actions = [
        {"id": "default", "title": "Edit rule", "icon": "edit"},
        {"id": "duplicate", "title": "Duplicate rule", "icon": "copy"},
        {"id": "move_up", "title": "Move up", "icon": "upload"},
        {"id": "move_down", "title": "Move down", "icon": "download"},
        {
            "id": "delete",
            "title": "Delete rule",
            "icon": "trash",
            "destructive": True,
            "confirm": {"title": "Delete this rule?", "message": "The rule will be removed from the recipe.", "confirmLabel": "Delete"},
        },
    ]
    return {
        "id": f"rule:{rule['id']}",
        "title": f"{number}. {rule.get('name') or 'Unnamed rule'}",
        "subtitle": f"{rule.get('source', '')} · {rule.get('mode', 'extract')} · no match: {rule.get('no_match', 'error')}",
        "icon": "tag",
        "cells": {
            "order": str(number),
            "rule": rule.get("name", "Unnamed rule"),
            "source": rule.get("source", ""),
            "regex": shorten(display_pattern, 70),
            "replacement": shorten(rule.get("replacement", ""), 50) or "(empty)",
            "output": f"{{{number}}}",
        },
        "actions": actions,
    }


def render_recipe(rev: int = 0, history: str = "none", preserve: bool = True) -> None:
    with STATE_LOCK:
        rules = copy.deepcopy(STATE["rules"])
        notice = STATE.get("load_notice", "")
    banners = []
    if notice:
        banners.append({"id": "recipe-notice", "style": "info", "title": "Recipe note", "message": notice, "dismissible": True})
    actions = [
        {"id": "add_rule", "title": "Add Rule", "icon": "add"},
        {"id": "output_settings", "title": "Output Settings", "icon": "settings"},
        {"id": "save_recipe", "title": "Save Recipe", "icon": "bookmark"},
        {"id": "preview", "title": "Preview", "icon": "search"},
    ]
    render(
        "table",
        rev=rev,
        page_id="atag:recipe",
        history=history,
        preserve=preserve,
        elementId="recipe-rule-table",
        placeholder="Rules are edited from the table actions…",
        empty={
            "icon": "tag",
            "title": "No transformation rules yet",
            "hint": "Add an ordered regex rule, then choose the final output template.",
            "action": {"id": "add_rule", "title": "Add Rule", "icon": "add"},
        },
        banners=banners,
        columns=[
            {"id": "order", "label": "#", "width": 48, "align": "end"},
            {"id": "rule", "label": "Rule", "width": 160},
            {"id": "source", "label": "Source", "width": 120},
            {"id": "regex", "label": "Regex", "width": 230},
            {"id": "replacement", "label": "Replacement", "width": 160},
            {"id": "output", "label": "Output token", "width": 100},
        ],
        table={"resizable": True, "stickyHeader": True, "columnVisibility": True},
        actions=actions,
        floatingAction=actions,
        items=[rule_item(rule, index, len(rules)) for index, rule in enumerate(rules, start=1)],
    )


def rule_fields(draft: Dict[str, Any], errors: Optional[Dict[str, str]] = None) -> List[Dict[str, Any]]:
    errors = errors or {}
    return [
        {
            "id": "name",
            "type": "text",
            "label": "Display name",
            "value": draft.get("name", ""),
            "required": True,
            "error": errors.get("name"),
        },
        {
            "id": "source",
            "type": "dropdown",
            "label": "Source field",
            "value": draft.get("source", "FileName"),
            "options": SOURCE_FIELDS,
            "required": True,
            "error": errors.get("source"),
        },
        {
            "id": "pattern",
            "type": "text",
            "label": "Regex pattern",
            "value": draft.get("pattern", ""),
            "placeholder": r"/ft\.(.*?)\W/i or (\w+)\s+(\w+)",
            "description": "Use a plain pattern or JavaScript-style /pattern/ims notation. Supported flags: i, m, s.",
            "required": True,
            "watch": True,
            "validate": True,
            "validationDebounceMs": 400,
            "error": errors.get("pattern"),
            "valid": not errors.get("pattern") if draft.get("pattern") else None,
        },
        {
            "id": "flags",
            "type": "text",
            "label": "Regex flags",
            "value": draft.get("flags", ""),
            "placeholder": "ims",
            "description": "Optional separate flags; notation flags and this field are combined.",
            "watch": True,
            "validate": True,
            "error": errors.get("flags"),
            "valid": not errors.get("flags") if draft.get("flags") else None,
        },
        {
            "id": "mode",
            "type": "dropdown",
            "label": "Mode",
            "value": draft.get("mode", "extract"),
            "options": display_option_list(MODE_OPTIONS),
            "description": "Extract returns only the first match's expanded replacement; replace modes operate on the complete source.",
            "error": errors.get("mode"),
        },
        {
            "id": "replacement",
            "type": "text",
            "label": "Replacement expression",
            "value": draft.get("replacement", ""),
            "placeholder": "$1 or $<artist> — $$ is a literal dollar",
            "description": "$1 means a capture inside this rule. {1} means this rule's final output in the final template.",
            "watch": True,
            "validate": True,
            "validationDebounceMs": 400,
            "error": errors.get("replacement"),
            "valid": not errors.get("replacement") if draft.get("replacement") is not None else None,
        },
        {
            "id": "no_match",
            "type": "dropdown",
            "label": "No-match behavior",
            "value": draft.get("no_match", "error"),
            "options": display_option_list(NO_MATCH_OPTIONS),
            "description": "The default marks the file as an error and skips it.",
            "error": errors.get("no_match"),
        },
    ]


def render_rule_form(rev: int = 0, history: str = "none", preserve: bool = True, errors: Optional[Dict[str, str]] = None, form_error: str = "") -> None:
    with STATE_LOCK:
        draft = copy.deepcopy(STATE["rule_draft"])
        is_new = not bool(STATE.get("editing_rule_id")) or STATE.get("editing_rule_id") == "new"
    render(
        "form",
        rev=rev,
        page_id=STATE["page_id"],
        history=history,
        preserve=preserve,
        placeholder="Edit the rule, then save…",
        form={
            "title": "Add rule" if is_new else "Edit rule",
            "error": form_error or None,
            "buttons": [
                {"id": "save", "label": "Save rule"},
                {"id": "cancel", "label": "Cancel"},
            ],
            "fields": rule_fields(draft, errors),
        },
        canGoBack=True,
    )


def output_fields(draft: Dict[str, Any], errors: Optional[Dict[str, str]] = None) -> List[Dict[str, Any]]:
    errors = errors or {}
    return [
        {
            "id": "template",
            "type": "textarea",
            "label": "Final template",
            "value": draft.get("template", ""),
            "placeholder": "{1} {2} {Album}",
            "description": "Combine {1}, {2}, direct sources such as {Album}, and literal text. Use {{ and }} for literal braces.",
            "watch": True,
            "validate": True,
            "validationDebounceMs": 400,
            "error": errors.get("template"),
            "valid": not errors.get("template") if draft.get("template") is not None else None,
        },
        {
            "id": "target",
            "type": "dropdown",
            "label": "Write result to",
            "value": draft.get("target", "Filename"),
            "options": display_option_list(OUTPUT_TARGETS),
            "description": "Audio-tag targets preserve unrelated audio tags, embedded cover art, and other tag data.",
            "error": errors.get("target"),
        },
        {"id": "trim", "type": "checkbox", "label": "Trim leading and trailing whitespace", "value": normalize_bool(draft.get("trim"), True)},
        {"id": "collapse_whitespace", "type": "checkbox", "label": "Collapse repeated whitespace", "value": normalize_bool(draft.get("collapse_whitespace"), True)},
        {
            "id": "no_value",
            "type": "dropdown",
            "label": "No-value policy",
            "value": draft.get("no_value", "error"),
            "options": display_option_list(NO_VALUE_OPTIONS),
            "description": "Empty filename results are always rejected; empty audio tags can be explicitly allowed.",
            "error": errors.get("no_value"),
        },
        {
            "id": "collision",
            "type": "dropdown",
            "label": "Filename collision behavior",
            "value": draft.get("collision", "skip"),
            "options": display_option_list(COLLISION_OPTIONS),
            "description": "Applies only to Filename output. No other file is ever overwritten.",
            "error": errors.get("collision"),
        },
    ]


def render_output_form(rev: int = 0, history: str = "none", preserve: bool = True, errors: Optional[Dict[str, str]] = None, form_error: str = "") -> None:
    with STATE_LOCK:
        draft = copy.deepcopy(STATE["output_draft"] or STATE["output"])
    render(
        "form",
        rev=rev,
        page_id="atag:output",
        history=history,
        preserve=preserve,
        placeholder="Configure the final template and output target…",
        form={
            "title": "Output settings",
            "error": form_error or None,
            "buttons": [
                {"id": "preview", "label": "Save and preview"},
                {"id": "cancel", "label": "Cancel"},
            ],
            "fields": output_fields(draft, errors),
        },
        canGoBack=True,
    )


def render_preview(rev: int = 0, history: str = "none", preserve: bool = True) -> None:
    with STATE_LOCK:
        loading = STATE["preview_loading"]
        order = list(STATE["preview_order"])
        plans = copy.deepcopy(STATE["preview_plans"])
        preview_error = STATE.get("preview_error", "")
        query = STATE.get("preview_query", "")
        target = STATE["output"].get("target", "Filename")
    if loading:
        render(
            "table",
            rev=rev,
            page_id="atag:preview",
            history=history,
            preserve=preserve,
            elementId="preview-table",
            placeholder="Dry run in progress…",
            loading=True,
            loadingText="Evaluating every included file against the immutable snapshot…",
            columns=[
                {"id": "current", "label": "Current value", "width": 210},
                {"id": "proposed", "label": "Proposed value", "width": 250},
                {"id": "status", "label": "Status", "width": 150},
            ],
            table={"resizable": True, "stickyHeader": True},
            items=[],
        )
        return

    all_plans = [plans[file_id] for file_id in order if file_id in plans]
    query_text = str(query).casefold().strip()
    plans_list = [
        plan
        for plan in all_plans
        if not query_text
        or query_text in " ".join(
            str(plan.get(key, ""))
            for key in ("filename", "path", "current_value", "proposed_value", "status", "error")
        ).casefold()
    ]
    valid_count = sum(1 for plan in all_plans if plan.get("status") == "valid")
    error_count = sum(1 for plan in all_plans if plan.get("status") in {"error", "collision"})
    excluded_count = sum(1 for plan in all_plans if plan.get("status") in {"excluded", "skipped", "unchanged"})
    banners = []
    if preview_error:
        banners.append({"id": "preview-error", "style": "error", "title": "Preview validation error", "message": preview_error, "dismissible": False})
    else:
        summary = f"{valid_count} ready to apply · {error_count} error/collision · {excluded_count} excluded, skipped, or unchanged"
        style = "success" if valid_count else "warning"
        banners.append({"id": "preview-summary", "style": style, "title": "Mandatory dry run complete", "message": summary, "dismissible": False})
    items: List[Dict[str, Any]] = []
    for plan in plans_list:
        status = plan.get("status", "error")
        status_label = {
            "valid": "Valid",
            "unchanged": "Unchanged",
            "excluded": "Excluded",
            "skipped": "Skipped",
            "collision": "Collision",
            "error": "Error",
        }.get(status, status.title())
        message = plan.get("error") or "; ".join(plan.get("warnings", []))
        items.append(
            {
                "id": f"preview:{plan['file_id']}",
                "title": plan.get("filename", os.path.basename(plan.get("path", ""))),
                "subtitle": shorten(message, 120) or shorten(plan.get("path", ""), 120),
                "icon": "check" if status == "valid" else "warning" if status in {"error", "collision"} else "music",
                "cells": {
                    "current": shorten(plan.get("current_value", "") or "—", 100),
                    "proposed": shorten(plan.get("proposed_value", "") or "—", 120),
                    "status": status_label,
                },
                "actions": [
                    {"id": "default", "title": "Open before/after detail", "icon": "open"},
                    {"id": "open_folder", "title": "Open containing folder", "icon": "folder"},
                ],
            }
        )
    floating: List[Dict[str, Any]] = [
        {"id": "refresh_preview", "title": "Refresh preview", "icon": "refresh"},
        {"id": "output_settings", "title": "Output settings", "icon": "settings"},
    ]
    if valid_count:
        floating.insert(
            0,
            {
                "id": "apply",
                "title": f"Apply {valid_count} change(s)",
                "icon": "check",
                "destructive": True,
                "confirm": {
                    "title": "Apply audio-tag changes?",
                    "message": f"This will write {valid_count} file(s) to {target}. A dry run has completed; no unrelated audio tags will be changed.",
                    "confirmLabel": "Apply changes",
                },
            },
        )
    render(
        "table",
        rev=rev,
        page_id="atag:preview",
        history=history,
        preserve=preserve,
        elementId="preview-table",
        placeholder="Filter the dry-run table by filename, value, or status…",
        banners=banners,
        empty={"icon": "search", "title": "Nothing to preview", "hint": "Load at least one included audio file first."},
        columns=[
            {"id": "current", "label": "Current value", "width": 210},
            {"id": "proposed", "label": "Proposed value", "width": 250},
            {"id": "status", "label": "Status", "width": 150},
        ],
        table={"resizable": True, "stickyHeader": True, "columnVisibility": True},
        actions=floating,
        floatingAction=floating,
        items=items,
    )


def metadata_for_plan(plan: Dict[str, Any]) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    snapshot = plan.get("snapshot", {})
    for field_name in SOURCE_FIELDS:
        rows.append({"label": field_name, "text": snapshot.get(field_name, "") or "—", "icon": "tag" if field_name in SOURCE_FIELDS[9:] else "file"})
    rows.append({"separator": True})
    for number, value in sorted(((int(key), value) for key, value in plan.get("rule_outputs", {}).items()), key=lambda pair: pair[0]):
        rows.append({"label": f"Rule {number} output", "text": value or "—", "icon": "check"})
    rows.extend(
        [
            {"label": "Expanded final template", "text": plan.get("expanded_template", "") or "—", "icon": "code"},
            {"label": "Old target value", "text": plan.get("current_value", "") or "—", "icon": "file"},
            {"label": "New target value", "text": plan.get("proposed_value", "") or "—", "icon": "check"},
        ]
    )
    return rows


def render_preview_detail(rev: int = 0, history: str = "none", preserve: bool = True) -> None:
    with STATE_LOCK:
        page_id = STATE["page_id"]
        file_id = page_id.split("atag:preview:", 1)[1] if "atag:preview:" in page_id else ""
        plan = copy.deepcopy(STATE["preview_plans"].get(file_id))
        record = STATE["files"].get(file_id)
    if not plan and record:
        render_file_detail(file_id, rev, history, preserve)
        return
    if not plan:
        render_error("That preview row is no longer available.", rev, "atag:preview")
        return
    status = plan.get("status", "error")
    status_message = plan.get("error") or "; ".join(plan.get("warnings", [])) or status.title()
    body = (
        f"# {plan.get('filename', '')}\n\n"
        f"Target: **{plan.get('target', '')}**\n\n"
        f"Status: **{status.title()}**\n\n"
        f"Source path: {md_code(plan.get('path', ''))}\n\n"
        f"## Expanded result\n\n{md_code(plan.get('expanded_template', '') or '—')}\n\n"
        f"## Exact target change\n\n"
        f"Before: {md_code(plan.get('current_value', '') or '—')}\n\n"
        f"After: {md_code(plan.get('proposed_value', '') or '—')}"
    )
    if status_message:
        body += f"\n\n> {status_message}"
    render(
        "detail",
        rev=rev,
        page_id=page_id,
        history=history,
        preserve=preserve,
        detail={"markdown": body, "metadata": metadata_for_plan(plan)},
        actions=[
            {"id": "open_folder", "title": "Open containing folder", "icon": "folder"},
            {"id": "copy_path", "title": "Copy full path", "icon": "copy"},
        ],
        canGoBack=True,
    )


def render_apply(rev: int = 0, history: str = "none", preserve: bool = True) -> None:
    with STATE_LOCK:
        completed = int(STATE.get("apply_completed", 0))
        total = int(STATE.get("apply_total", 0))
        detail = STATE.get("apply_detail", "Preparing…")
        active = bool(STATE.get("apply_active"))
    progress = (completed / total) if total else None
    operation: Dict[str, Any] = {
        "id": "atag-apply",
        "title": "Applying changes" if active else "Application finished",
        "detail": detail,
        "cancellable": active,
    }
    if progress is not None:
        operation["progress"] = max(0.0, min(1.0, progress))
    render(
        "operation",
        rev=rev,
        page_id="atag:apply",
        history=history,
        preserve=preserve,
        operation=operation,
        canGoBack=True,
        actions=[{"id": "cancel_apply", "title": "Cancel application", "icon": "close", "destructive": True}] if active else [],
    )


def result_item(result: Dict[str, Any]) -> Dict[str, Any]:
    outcome = result.get("outcome", "failed")
    color = {"changed": "#16A34A", "skipped": "#CA8A04", "failed": "#DC2626", "cancelled": "#7C3AED"}.get(outcome, "#64748B")
    return {
        "id": f"result:{result.get('file_id', '')}",
        "title": result.get("filename", "Unknown file"),
        "subtitle": shorten(result.get("message", ""), 120),
        "icon": "check" if outcome == "changed" else "warning" if outcome == "failed" else "close" if outcome == "cancelled" else "info",
        "accessories": [{"text": outcome.title(), "color": color}],
        "cells": {"outcome": outcome.title(), "message": shorten(result.get("message", ""), 130)},
        "actions": [
            {"id": "default", "title": "Open result detail", "icon": "open"},
            {"id": "open_folder", "title": "Open containing folder", "icon": "folder"},
        ],
    }


def render_result(rev: int = 0, history: str = "none", preserve: bool = True) -> None:
    with STATE_LOCK:
        results = copy.deepcopy(STATE.get("apply_results", []))
    counts = {outcome: sum(1 for result in results if result.get("outcome") == outcome) for outcome in ("changed", "skipped", "failed", "cancelled")}
    style = "success" if counts["failed"] == 0 and counts["cancelled"] == 0 else "warning"
    message = (
        f"Changed {counts['changed']} · skipped {counts['skipped']} · "
        f"failed {counts['failed']} · cancelled {counts['cancelled']}"
    )
    render(
        "table",
        rev=rev,
        page_id="atag:result",
        history=history,
        preserve=preserve,
        elementId="apply-result-table",
        placeholder="Filter the application result…",
        banners=[{"id": "result-summary", "style": style, "title": "Batch finished", "message": message, "dismissible": False}],
        empty={"icon": "info", "title": "No application results", "hint": "Return to the file list and run a preview first."},
        columns=[
            {"id": "outcome", "label": "Outcome", "width": 110},
            {"id": "message", "label": "Message", "width": 360},
        ],
        table={"resizable": True, "stickyHeader": True},
        actions=[
            {"id": "return_files", "title": "Return to file list", "icon": "list"},
            {"id": "open_last_folder", "title": "Open containing folder", "icon": "folder"},
        ],
        floatingAction={"id": "return_files", "title": "Return to file list", "icon": "list"},
        items=[result_item(result) for result in results],
    )


def render_result_detail(rev: int = 0, history: str = "none", preserve: bool = True) -> None:
    with STATE_LOCK:
        page_id = STATE["page_id"]
        file_id = page_id.split("atag:result:", 1)[1] if "atag:result:" in page_id else ""
        result = next((copy.deepcopy(item) for item in STATE.get("apply_results", []) if item.get("file_id") == file_id), None)
    if not result:
        render_error("That result row is no longer available.", rev, "atag:result")
        return
    body = (
        f"# {result.get('filename', '')}\n\n"
        f"Outcome: **{result.get('outcome', '').title()}**\n\n"
        f"{result.get('message', '')}\n\n"
        f"Path: {md_code(result.get('path', ''))}"
    )
    render(
        "detail",
        rev=rev,
        page_id=page_id,
        history=history,
        preserve=preserve,
        detail={"markdown": body},
        actions=[
            {"id": "open_folder", "title": "Open containing folder", "icon": "folder"},
            {"id": "copy_path", "title": "Copy full path", "icon": "copy"},
        ],
        canGoBack=True,
    )


def render_save_form(rev: int = 0, history: str = "none", preserve: bool = True, error: str = "") -> None:
    with STATE_LOCK:
        name = STATE["save_draft"].get("name", "")
    render(
        "form",
        rev=rev,
        page_id="atag:save",
        history=history,
        preserve=preserve,
        placeholder="Name this recipe…",
        form={
            "title": "Save named recipe",
            "error": error or None,
            "buttons": [{"id": "save", "label": "Save recipe"}, {"id": "cancel", "label": "Cancel"}],
            "fields": [
                {"id": "name", "type": "text", "label": "Recipe name", "value": name, "required": True, "placeholder": "Artist from filename", "description": "Only recipe rules and output settings are saved; loaded file paths are not persisted."},
            ],
        },
        canGoBack=True,
    )


def recipe_storage_key(name: str) -> str:
    digest = hashlib.sha1(name.encode("utf-8", "replace")).hexdigest()[:10]
    safe = re.sub(r"[^A-Za-z0-9._-]+", "_", name).strip("._-") or "recipe"
    return f"atag.recipe.{safe[:50]}-{digest}"


def normalize_saved_recipe(recipe: Any) -> Dict[str, Any]:
    if not isinstance(recipe, dict):
        raise RecipeError("Saved recipe data is not an object.")
    raw_rules = recipe.get("rules")
    if not isinstance(raw_rules, list):
        raise RecipeError("Saved recipe rules are not a list.")
    rules: List[Dict[str, Any]] = []
    seen_ids: set = set()
    for raw_rule in raw_rules:
        if not isinstance(raw_rule, dict):
            raise RecipeError("Saved recipe contains a malformed rule.")
        normalized, errors = validate_rule_values(raw_rule)
        if errors:
            raise RecipeError("Saved recipe rule is invalid: " + "; ".join(errors.values()))
        if normalized["id"] in seen_ids:
            normalized["id"] = f"r-{uuid.uuid4().hex}"
        seen_ids.add(normalized["id"])
        rules.append(normalized)
    output, errors = validate_output_values(recipe.get("output") or DEFAULT_OUTPUT, len(rules))
    if errors:
        raise RecipeError("Saved recipe output is invalid: " + "; ".join(errors.values()))
    return {"version": 1, "name": str(recipe.get("name") or "Saved recipe"), "rules": rules, "output": output}


def render_saved_recipes(rev: int = 0, history: str = "none", preserve: bool = True) -> None:
    with STATE_LOCK:
        recipes = copy.deepcopy(STATE["saved_recipes"])
        query = str(STATE.get("saved_query", ""))
    items = []
    for key, payload in sorted(recipes.items(), key=lambda item: str(item[1].get("name", item[0])).casefold()):
        recipe = payload.get("recipe", {})
        if not isinstance(recipe, dict):
            continue
        recipe_output = recipe.get("output") if isinstance(recipe.get("output"), dict) else {}
        searchable = f"{payload.get('name', '')} {recipe_output.get('target', '')}".casefold()
        if query.casefold().strip() and query.casefold().strip() not in searchable:
            continue
        items.append(
            {
                "id": f"saved:{key}",
                "title": payload.get("name", key),
                "subtitle": f"{len(recipe.get('rules', []))} rule(s) · {recipe_output.get('target', 'Filename')}",
                "icon": "bookmark",
                "actions": [
                    {"id": "default", "title": "Load recipe", "icon": "open"},
                    {"id": "delete", "title": "Delete saved recipe", "icon": "trash", "destructive": True, "confirm": {"title": "Delete saved recipe?", "message": "The saved recipe will be removed from Tabame storage.", "confirmLabel": "Delete"}},
                ],
            }
        )
    render(
        "list",
        rev=rev,
        page_id="atag:recipes",
        history=history,
        preserve=preserve,
        placeholder="Filter saved recipes…",
        empty={"icon": "bookmark", "title": "No saved recipes", "hint": "Save a recipe from the recipe page."},
        actions=[{"id": "back", "title": "Back", "icon": "open"}],
        items=items,
        canGoBack=True,
    )


# ---------------------------------------------------------------------------
# Preview/application workers


def begin_preview() -> None:
    with STATE_LOCK:
        records = copy.deepcopy(list(STATE["files"].values()))
        rules = copy.deepcopy(STATE["rules"])
        output = copy.deepcopy(STATE["output"])
        STATE["preview_generation"] += 1
        generation = STATE["preview_generation"]
        STATE["preview_loading"] = True
        STATE["preview_error"] = ""
        STATE["preview_plans"] = {}
        STATE["preview_order"] = []
    if not records:
        with STATE_LOCK:
            STATE["preview_loading"] = False
            STATE["preview_error"] = "Load at least one MP3 or FLAC file before previewing."
        render_preview(0)
        return
    render_preview(0)

    def worker() -> None:
        try:
            plans, global_error = create_preview_plans(records, rules, output)
            with STATE_LOCK:
                if generation != STATE["preview_generation"] or STATE["closing"]:
                    return
                STATE["preview_plans"] = {plan["file_id"]: plan for plan in plans}
                STATE["preview_order"] = [plan["file_id"] for plan in plans]
                STATE["preview_loading"] = False
                STATE["preview_error"] = global_error
            if STATE.get("page_id") == "atag:preview":
                render_preview(0)
        except Exception as exc:
            log("Preview failed", exc)
            with STATE_LOCK:
                STATE["preview_loading"] = False
                STATE["preview_error"] = friendly_exception(exc)
            render_preview(0)

    threading.Thread(target=worker, name="atag-preview", daemon=True).start()


def apply_one(record: FileRecord, plan: Dict[str, Any], output: Dict[str, Any], occupied: set) -> Dict[str, Any]:
    result = {
        "file_id": record.file_id,
        "filename": os.path.basename(record.path),
        "path": record.path,
        "outcome": "changed",
        "message": "",
    }
    if not current_stat_matches(record):
        raise RecipeError("The file changed after preview; it was not modified.")
    target = output.get("target", "Filename")
    if target == "Filename":
        destination = plan.get("proposed_path", "")
        if not destination:
            raise RecipeError("The preview did not produce a destination filename.")
        if path_key(destination) != path_key(record.path) and path_key(destination) in occupied:
            if output.get("collision") == "suffix":
                destination = numeric_candidate(destination, occupied | {path_key(record.path)})
            else:
                raise ApplySkip(f"The destination became occupied: {os.path.basename(destination)}")
        if path_key(destination) != path_key(record.path) and os.path.lexists(destination):
            if output.get("collision") == "suffix":
                destination = numeric_candidate(destination, occupied | {path_key(record.path)})
            else:
                raise ApplySkip(f"The destination became occupied: {os.path.basename(destination)}")
        try:
            safe_rename_no_overwrite(record.path, destination)
        except FileExistsError as exc:
            if output.get("collision") == "suffix":
                destination = numeric_candidate(destination, occupied | {path_key(record.path)})
                safe_rename_no_overwrite(record.path, destination)
            else:
                raise ApplySkip(str(exc)) from exc
        occupied.add(path_key(destination))
        result["filename"] = os.path.basename(destination)
        result["path"] = destination
        result["message"] = f"Renamed to {os.path.basename(destination)}."
        result["new_path"] = destination
        return result

    write_tag_atomically(record, target, str(plan.get("proposed_value", "")))
    result["message"] = f"Updated the {target} audio tag."
    return result


def refresh_record_after_apply(record: FileRecord, new_path: Optional[str] = None) -> None:
    path = new_path or record.path
    try:
        refreshed = read_snapshot(path)
    except Exception as exc:
        log("Could not refresh record after apply", path, exc)
        return
    with STATE_LOCK:
        if record.file_id in STATE["files"]:
            if new_path:
                refreshed.file_id = record.file_id
            STATE["files"][record.file_id] = refreshed


def start_apply() -> None:
    with STATE_LOCK:
        if STATE["apply_active"]:
            return
        plans = [copy.deepcopy(STATE["preview_plans"].get(file_id)) for file_id in STATE["preview_order"]]
        plans = [plan for plan in plans if plan]
        records = {record.file_id: copy.deepcopy(record) for record in STATE["files"].values()}
        output = copy.deepcopy(STATE["output"])
        jobs = [plan for plan in plans if plan.get("status") == "valid"]
        if not jobs:
            render_error("There are no valid preview rows to apply.", 0, "atag:preview", "Nothing to apply")
            return
        cancel_event = threading.Event()
        STATE["apply_cancel"] = cancel_event
        STATE["apply_active"] = True
        STATE["apply_completed"] = 0
        STATE["apply_total"] = len(jobs)
        STATE["apply_detail"] = f"Ready to apply {len(jobs)} file(s)."
        STATE["apply_results"] = []

    # Request the host's post-close grace before starting any destructive work.
    send_command("background", timeout=300)
    navigate_to("atag:apply", push=True, clear_query=True)

    def worker() -> None:
        results: List[Dict[str, Any]] = []
        occupied: set = set()
        for plan in plans:
            status = plan.get("status")
            if status == "excluded":
                results.append({"file_id": plan["file_id"], "filename": plan["filename"], "path": plan["path"], "outcome": "skipped", "message": "Excluded from the batch."})
            elif status in {"error", "collision", "skipped", "unchanged"}:
                message = plan.get("error") or "; ".join(plan.get("warnings", [])) or "No change was needed."
                results.append({"file_id": plan["file_id"], "filename": plan["filename"], "path": plan["path"], "outcome": "skipped", "message": message})

        for plan in [item for item in plans if item.get("status") == "valid"]:
            with STATE_LOCK:
                cancel_event = STATE.get("apply_cancel")
            if cancel_event and cancel_event.is_set():
                results.append({"file_id": plan["file_id"], "filename": plan["filename"], "path": plan["path"], "outcome": "cancelled", "message": "Cancelled before this file was changed."})
                with STATE_LOCK:
                    STATE["apply_completed"] += 1
                    STATE["apply_detail"] = "Cancellation requested; stopping between files."
                if STATE.get("page_id") == "atag:apply":
                    render_apply(0)
                continue
            record = records.get(plan["file_id"])
            if not record:
                results.append({"file_id": plan["file_id"], "filename": plan["filename"], "path": plan["path"], "outcome": "failed", "message": "The file disappeared from the batch."})
                with STATE_LOCK:
                    STATE["apply_completed"] += 1
                continue
            try:
                result = apply_one(record, plan, output, occupied)
                results.append(result)
                refresh_record_after_apply(record, result.get("new_path"))
            except ApplySkip as exc:
                results.append({"file_id": record.file_id, "filename": os.path.basename(record.path), "path": record.path, "outcome": "skipped", "message": str(exc)})
            except Exception as exc:
                log("Apply failed", record.path, exc)
                results.append({"file_id": record.file_id, "filename": os.path.basename(record.path), "path": record.path, "outcome": "failed", "message": friendly_exception(exc)})
            with STATE_LOCK:
                STATE["apply_completed"] += 1
                completed = STATE["apply_completed"]
                total = STATE["apply_total"]
                STATE["apply_detail"] = f"Processed {completed} of {total} file(s)."
                cancel_requested = bool(STATE.get("apply_cancel") and STATE["apply_cancel"].is_set())
                if cancel_requested:
                    STATE["apply_detail"] = "Cancellation requested; stopping between files."
            if STATE.get("page_id") == "atag:apply":
                render_apply(0)

        with STATE_LOCK:
            STATE["apply_results"] = results
            STATE["apply_active"] = False
            cancelled = any(result.get("outcome") == "cancelled" for result in results)
            failed = sum(1 for result in results if result.get("outcome") == "failed")
            changed = sum(1 for result in results if result.get("outcome") == "changed")
            STATE["apply_detail"] = f"Changed {changed}; {failed} failed; {'cancelled' if cancelled else 'complete'}."
            closing = STATE["closing"]
            if not closing:
                STATE["page_id"] = "atag:result"
                if STATE["route_stack"][-1:] != ["atag:result"]:
                    STATE["route_stack"].append("atag:result")
        summary = f"Changed {changed} file(s); {failed} failed"
        if cancelled:
            summary += "; application cancelled"
        send_command("notify", title=PLUGIN_NAME, text=summary + ".")
        if not closing:
            render_result(0, history="push")

    # Non-daemon: if the launcher closes, the requested background grace lets
    # this worker finish safely before the process exits.
    threading.Thread(target=worker, name="atag-apply", daemon=False).start()


# ---------------------------------------------------------------------------
# Saved recipe storage and protocol event handlers


def save_current_recipe(name: str) -> None:
    with STATE_LOCK:
        recipe = {"version": 1, "name": name, "rules": copy.deepcopy(STATE["rules"]), "output": copy.deepcopy(STATE["output"])}
    key = recipe_storage_key(name)
    payload = {"name": name, "recipe": recipe}
    with STATE_LOCK:
        STATE["saved_recipes"][key] = payload
    send_command("storage", op="set", key=key, value=json.dumps(recipe, ensure_ascii=False))
    with STATE_LOCK:
        STATE["load_notice"] = f"Saved recipe '{name}'."
    navigate_to("atag:recipe", push=False, clear_query=True)


def handle_storage(message: Dict[str, Any]) -> None:
    request_id = message.get("requestId")
    if request_id == "recipe_keys":
        keys = message.get("keys") or []
        for key in keys:
            if not str(key).startswith("atag.recipe."):
                continue
            request = f"recipe_value:{key}"
            with STATE_LOCK:
                STATE["pending_recipe_requests"][request] = {"key": key, "kind": "init"}
            send_command("storage", op="get", key=key, requestId=request)
        return
    with STATE_LOCK:
        pending = STATE["pending_recipe_requests"].pop(request_id, None)
    if not pending:
        return
    value = message.get("value")
    if value is None:
        return
    try:
        raw_recipe = json.loads(value) if isinstance(value, str) else value
        recipe = normalize_saved_recipe(raw_recipe)
        name = str(recipe.get("name") or pending.get("key") or "Saved recipe")
        payload = {"name": name, "recipe": recipe}
        with STATE_LOCK:
            STATE["saved_recipes"][pending["key"]] = payload
            page_id = STATE["page_id"]
        if page_id in {"atag:load", "atag:recipes"}:
            render_current(0)
        if pending.get("kind") == "load":
            with STATE_LOCK:
                STATE["rules"] = copy.deepcopy(recipe["rules"])
                STATE["output"] = copy.deepcopy(recipe["output"])
                STATE["load_notice"] = f"Loaded recipe '{name}'."
            navigate_to("atag:recipe", push=False, clear_query=True)
    except Exception as exc:
        log("Saved recipe parse failed", exc)
        if pending.get("kind") == "load":
            render_error(f"Could not load the saved recipe: {friendly_exception(exc)}", 0, "atag:recipes")


def handle_select(message: Dict[str, Any]) -> None:
    item_id = str(message.get("id") or "")
    with STATE_LOCK:
        if item_id.startswith("file:"):
            STATE["selected_file_id"] = item_id[5:]
        elif item_id.startswith("rule:"):
            STATE["selected_rule_id"] = item_id[5:]


def update_form_draft(values: Dict[str, Any]) -> None:
    with STATE_LOCK:
        page_id = STATE["page_id"]
        if page_id == "atag:load":
            STATE["load_draft"].update(copy.deepcopy(values))
        elif page_id.startswith("atag:rule:"):
            STATE["rule_draft"].update(copy.deepcopy(values))
        elif page_id == "atag:output":
            STATE["output_draft"].update(copy.deepcopy(values))
        elif page_id == "atag:save":
            STATE["save_draft"].update(copy.deepcopy(values))


def validate_current_form(values: Dict[str, Any]) -> Dict[str, str]:
    update_form_draft(values)
    with STATE_LOCK:
        page_id = STATE["page_id"]
        if page_id.startswith("atag:rule:"):
            _normalized, errors = validate_rule_values(STATE["rule_draft"])
            return errors
        if page_id == "atag:output":
            _normalized, errors = validate_output_values(STATE["output_draft"], len(STATE["rules"]))
            return errors
    return {}


def handle_change(message: Dict[str, Any]) -> None:
    values = message.get("values") or {}
    errors = validate_current_form(values)
    with STATE_LOCK:
        page_id = STATE["page_id"]
    if page_id.startswith("atag:rule:"):
        render_rule_form(0, errors=errors)
    elif page_id == "atag:output":
        render_output_form(0, errors=errors)


def handle_validate(message: Dict[str, Any]) -> None:
    values = message.get("values") or {}
    errors = validate_current_form(values)
    with STATE_LOCK:
        page_id = STATE["page_id"]
    if page_id.startswith("atag:rule:"):
        render_rule_form(int(message.get("rev") or 0), errors=errors)
    elif page_id == "atag:output":
        render_output_form(int(message.get("rev") or 0), errors=errors)


def form_values_for_load(values: Dict[str, Any]) -> Tuple[List[str], List[str], bool]:
    raw_files = values.get("files") or []
    if isinstance(raw_files, str):
        raw_files = [raw_files]
    files = [canonical_path(value) for value in raw_files if canonical_path(value)]
    folder = canonical_path(values.get("folder") or "")
    folders = [folder] if folder else []
    recursive = normalize_bool(values.get("recursive"), False)
    return files, folders, recursive


def handle_submit(message: Dict[str, Any]) -> None:
    values = message.get("values") or {}
    button = str(message.get("button") or "")
    with STATE_LOCK:
        page_id = STATE["page_id"]

    if page_id == "atag:load":
        files, folders, recursive = form_values_for_load(values)
        with STATE_LOCK:
            mode = STATE["load_mode"]
            STATE["load_draft"] = {"files": files, "folder": folders[0] if folders else "", "recursive": recursive}
        if not files and not folders:
            render_load(0, error="Choose at least one file or folder before continuing.")
            return
        start_scan(files, folders, recursive, replace=mode == "replace", rev=0)
        return

    if page_id.startswith("atag:rule:"):
        if button == "cancel":
            go_back("atag:recipe")
            return
        normalized, errors = validate_rule_values(values)
        if errors:
            with STATE_LOCK:
                STATE["rule_draft"].update(normalized)
            render_rule_form(0, errors=errors, form_error="Fix the highlighted regex or replacement errors before saving.")
            return
        with STATE_LOCK:
            editing_id = STATE.get("editing_rule_id")
            rules = copy.deepcopy(STATE["rules"])
            if editing_id and editing_id != "new":
                for index, rule in enumerate(rules):
                    if rule.get("id") == editing_id:
                        normalized["id"] = editing_id
                        rules[index] = normalized
                        break
                else:
                    rules.append(normalized)
            else:
                rules.append(normalized)
            STATE["rules"] = rules
            STATE["rule_draft"] = {}
            STATE["editing_rule_id"] = None
            STATE["preview_plans"] = {}
            STATE["preview_order"] = []
            STATE["load_notice"] = "Rule saved."
        navigate_to("atag:recipe", push=False, clear_query=True)
        return

    if page_id == "atag:output":
        if button == "cancel":
            go_back("atag:recipe")
            return
        normalized, errors = validate_output_values(values, len(STATE["rules"]))
        if errors:
            with STATE_LOCK:
                STATE["output_draft"].update(normalized)
            render_output_form(0, errors=errors, form_error="Fix the template before starting the dry run.")
            return
        with STATE_LOCK:
            STATE["output"] = normalized
            STATE["output_draft"] = copy.deepcopy(normalized)
        navigate_to("atag:preview", push=True, clear_query=True)
        begin_preview()
        return

    if page_id == "atag:save":
        if button == "cancel":
            go_back("atag:recipe")
            return
        name = str(values.get("name") or "").strip()
        if not name:
            render_save_form(0, error="Give the recipe a name before saving.")
            return
        with STATE_LOCK:
            _output, output_errors = validate_output_values(STATE["output"], len(STATE["rules"]))
        if output_errors:
            render_save_form(0, error="Save the recipe after fixing its output settings: " + "; ".join(output_errors.values()))
            return
        save_current_recipe(name)
        return


def start_add_files() -> None:
    with STATE_LOCK:
        STATE["load_mode"] = "append"
        STATE["load_draft"] = {"files": [], "folder": "", "recursive": False}
    navigate_to("atag:load", push=True, clear_query=True)


def file_record_from_id(file_id: str) -> Optional[FileRecord]:
    with STATE_LOCK:
        return STATE["files"].get(file_id)


def handle_file_action(file_id: str, action: str) -> None:
    record = file_record_from_id(file_id)
    if not record:
        render_error("That file is no longer in the current batch.", 0, "atag:files")
        return
    if action == "default":
        with STATE_LOCK:
            plan_exists = file_id in STATE["preview_plans"]
            STATE["page_id"] = f"atag:preview:{file_id}"
            if STATE["route_stack"][-1:] != [STATE["page_id"]]:
                STATE["route_stack"].append(STATE["page_id"])
        send_command("setQuery", text="")
        if plan_exists:
            render_preview_detail(0, history="push")
        else:
            render_file_detail(file_id, 0, history="push")
    elif action in {"include", "exclude"}:
        with STATE_LOCK:
            record.include = action == "include"
            STATE["preview_plans"] = {}
            STATE["preview_order"] = []
        render_files(0)
    elif action == "remove":
        with STATE_LOCK:
            STATE["files"].pop(file_id, None)
            STATE["preview_plans"].pop(file_id, None)
            STATE["preview_order"] = [item for item in STATE["preview_order"] if item != file_id]
        render_files(0)
    elif action == "open_folder":
        send_command("open", path=os.path.dirname(record.path))
    elif action == "copy_path":
        send_command("copy", text=record.path)


def handle_rule_action(rule_id: str, action: str) -> None:
    with STATE_LOCK:
        rules = copy.deepcopy(STATE["rules"])
        index = next((idx for idx, rule in enumerate(rules) if rule.get("id") == rule_id), None)
    if index is None:
        render_error("That rule no longer exists.", 0, "atag:recipe")
        return
    if action == "default":
        with STATE_LOCK:
            STATE["editing_rule_id"] = rule_id
            STATE["rule_draft"] = copy.deepcopy(rules[index])
        navigate_to(f"atag:rule:{rule_id}", push=True, clear_query=True)
    elif action == "duplicate":
        duplicate = copy.deepcopy(rules[index])
        duplicate["id"] = f"r-{uuid.uuid4().hex}"
        duplicate["name"] = f"Copy of {duplicate.get('name') or 'rule'}"
        rules.insert(index + 1, duplicate)
        with STATE_LOCK:
            STATE["rules"] = rules
            STATE["load_notice"] = "Rule duplicated."
        render_recipe(0)
    elif action == "delete":
        rules.pop(index)
        with STATE_LOCK:
            STATE["rules"] = rules
            STATE["preview_plans"] = {}
            STATE["preview_order"] = []
            STATE["load_notice"] = "Rule deleted."
        render_recipe(0)
    elif action in {"move_up", "move_down"}:
        destination = index - 1 if action == "move_up" else index + 1
        if destination < 0 or destination >= len(rules):
            return
        rules[index], rules[destination] = rules[destination], rules[index]
        with STATE_LOCK:
            STATE["rules"] = rules
            STATE["preview_plans"] = {}
            STATE["preview_order"] = []
        render_recipe(0)


def handle_saved_action(key: str, action: str) -> None:
    if action == "delete":
        with STATE_LOCK:
            STATE["saved_recipes"].pop(key, None)
        send_command("storage", op="delete", key=key)
        render_saved_recipes(0)
        return
    if action == "default":
        request = f"load_recipe:{key}"
        with STATE_LOCK:
            STATE["pending_recipe_requests"][request] = {"key": key, "kind": "load"}
        send_command("storage", op="get", key=key, requestId=request)
        render(
            "list",
            rev=0,
            page_id="atag:recipes",
            loading=True,
            loadingText="Loading saved recipe…",
            items=[],
            canGoBack=True,
        )


def handle_frame_action(action: str, ids: Optional[Sequence[str]] = None) -> None:
    if action == "add_files":
        start_add_files()
    elif action == "continue_recipe":
        with STATE_LOCK:
            included = [record for record in STATE["files"].values() if record.include]
        if not included:
            render_error("Include at least one file before continuing to the recipe.", 0, "atag:files", "No included files")
        else:
            navigate_to("atag:recipe", push=True, clear_query=True)
    elif action == "add_rule":
        rule = new_rule()
        with STATE_LOCK:
            STATE["editing_rule_id"] = "new"
            STATE["rule_draft"] = rule
        navigate_to(f"atag:rule:{rule['id']}", push=True, clear_query=True, preserve=False)
    elif action == "output_settings":
        with STATE_LOCK:
            STATE["output_draft"] = copy.deepcopy(STATE["output"])
        navigate_to("atag:output", push=True, clear_query=True)
    elif action == "save_recipe":
        with STATE_LOCK:
            STATE["save_draft"] = {"name": ""}
        navigate_to("atag:save", push=True, clear_query=True, preserve=False)
    elif action == "preview" or action == "refresh_preview":
        with STATE_LOCK:
            page_id = STATE["page_id"]
        if page_id != "atag:preview":
            navigate_to("atag:preview", push=True, clear_query=True)
        begin_preview()
    elif action == "apply":
        start_apply()
    elif action in {"cancel_apply", "cancel"}:
        with STATE_LOCK:
            event = STATE.get("apply_cancel")
            if event:
                event.set()
                STATE["apply_detail"] = "Cancellation requested; stopping between files."
        if STATE.get("page_id") == "atag:apply":
            render_apply(0)
    elif action == "open_saved":
        navigate_to("atag:recipes", push=True, clear_query=True)
    elif action == "return_files":
        go_back("atag:files")
    elif action == "open_last_folder":
        with STATE_LOCK:
            results = STATE.get("apply_results", [])
        if results:
            send_command("open", path=os.path.dirname(results[-1].get("path", "")))
    elif action == "back":
        go_back()


def handle_action(message: Dict[str, Any]) -> None:
    item_id = str(message.get("id") or "")
    action = str(message.get("action") or "default")
    ids = message.get("ids") or []
    if item_id == "":
        handle_frame_action(action, ids)
        return
    if item_id.startswith("file:"):
        handle_file_action(item_id[5:], action)
    elif item_id.startswith("rule:"):
        handle_rule_action(item_id[5:], action)
    elif item_id.startswith("preview:"):
        file_id = item_id[8:]
        if action == "default":
            with STATE_LOCK:
                STATE["page_id"] = f"atag:preview:{file_id}"
                STATE["route_stack"].append(STATE["page_id"])
            send_command("setQuery", text="")
            render_preview_detail(0, history="push")
        elif action == "open_folder" or action == "copy_path":
            record = file_record_from_id(file_id)
            if record:
                send_command("open" if action == "open_folder" else "copy", **({"path": os.path.dirname(record.path)} if action == "open_folder" else {"text": record.path}))
    elif item_id.startswith("result:"):
        file_id = item_id[7:]
        if action == "default":
            with STATE_LOCK:
                STATE["page_id"] = f"atag:result:{file_id}"
                STATE["route_stack"].append(STATE["page_id"])
            send_command("setQuery", text="")
            render_result_detail(0, history="push")
        elif action in {"open_folder", "copy_path"}:
            with STATE_LOCK:
                result = next((item for item in STATE.get("apply_results", []) if item.get("file_id") == file_id), None)
            if result:
                if action == "open_folder":
                    send_command("open", path=os.path.dirname(result.get("path", "")))
                else:
                    send_command("copy", text=result.get("path", ""))
    elif item_id.startswith("saved:"):
        handle_saved_action(item_id[6:], action)


def handle_drop(message: Dict[str, Any]) -> None:
    paths = message.get("paths") or []
    if isinstance(paths, str):
        paths = [paths]
    files: List[str] = []
    folders: List[str] = []
    for raw_path in paths:
        path = canonical_path(raw_path)
        if not path:
            continue
        if os.path.isdir(path):
            folders.append(path)
        else:
            files.append(path)
    with STATE_LOCK:
        page_id = STATE["page_id"]
        replace = page_id == "atag:load" and STATE["load_mode"] == "replace"
        recursive = normalize_bool(STATE["load_draft"].get("recursive"), False)
        if page_id == "atag:files":
            replace = False
    if not files and not folders:
        return
    start_scan(files, folders, recursive, replace=replace, rev=int(message.get("rev") or 0))


def handle_back(message: Dict[str, Any]) -> None:
    with STATE_LOCK:
        page_id = STATE["page_id"]
        active = STATE["apply_active"]
    target = message.get("toPageId")
    if page_id == "atag:apply" and active:
        with STATE_LOCK:
            event = STATE.get("apply_cancel")
            if event:
                event.set()
        return
    if target and isinstance(target, str):
        go_back(target)
    else:
        go_back()


def handle_navigate(message: Dict[str, Any]) -> None:
    target = message.get("targetPageId")
    if not isinstance(target, str):
        return
    with STATE_LOCK:
        known = (
            target in {"atag:load", "atag:files", "atag:recipe", "atag:output", "atag:preview", "atag:apply", "atag:result", "atag:save", "atag:recipes"}
            or target.startswith("atag:rule:")
            or target.startswith("atag:preview:")
            or target.startswith("atag:result:")
        )
        if not known:
            return
        stack = STATE["route_stack"]
        if target in stack:
            STATE["route_stack"] = stack[: stack.index(target) + 1]
        else:
            STATE["route_stack"].append(target)
        STATE["page_id"] = target
        STATE["file_query"] = ""
        STATE["preview_query"] = ""
        STATE["saved_query"] = ""
    send_command("setQuery", text="")
    render_current(int(message.get("rev") or 0), history="none")


def handle_query(message: Dict[str, Any]) -> None:
    text = message.get("text", message.get("query", ""))
    if text is None:
        text = ""
    with STATE_LOCK:
        page_id = STATE["page_id"]
        if page_id == "atag:files":
            STATE["file_query"] = str(text)
        elif page_id == "atag:preview":
            STATE["preview_query"] = str(text)
        elif page_id == "atag:recipes":
            STATE["saved_query"] = str(text)
    if page_id == "atag:files":
        render_files(int(message.get("rev") or 0))
    elif page_id == "atag:preview":
        render_preview(int(message.get("rev") or 0))
    elif page_id in {"atag:load", "atag:recipes"}:
        render_current(int(message.get("rev") or 0))


def handle_tab(message: Dict[str, Any]) -> None:
    item_id = str(message.get("id") or "")
    if item_id.startswith("file:"):
        record = file_record_from_id(item_id[5:])
        if record:
            send_command("setQuery", text=record.snapshot.get("FileName", ""))


def handle_close() -> None:
    with STATE_LOCK:
        STATE["closing"] = True
        scan_cancel = STATE.get("scan_cancel")
        apply_cancel = STATE.get("apply_cancel")
        apply_active = STATE.get("apply_active")
    if scan_cancel:
        scan_cancel.set()
    if apply_active and apply_cancel:
        # background was requested before the worker began; stop between files.
        apply_cancel.set()
    STOP_EVENT.set()


def dispatch(message: Dict[str, Any]) -> bool:
    message_type = message.get("type")
    if message_type == "close":
        handle_close()
        return False
    if message_type == "init":
        send_command("storage", op="keys", requestId="recipe_keys")
        render_load(int(message.get("rev") or 0), history="replace")
    elif message_type == "query":
        handle_query(message)
    elif message_type == "select":
        handle_select(message)
    elif message_type == "action":
        handle_action(message)
    elif message_type == "submit":
        handle_submit(message)
    elif message_type == "change":
        handle_change(message)
    elif message_type == "validate":
        handle_validate(message)
    elif message_type == "drop":
        handle_drop(message)
    elif message_type == "cancel":
        handle_frame_action("cancel_apply")
    elif message_type == "back":
        handle_back(message)
    elif message_type == "navigate":
        handle_navigate(message)
    elif message_type == "storage":
        handle_storage(message)
    elif message_type == "tab":
        handle_tab(message)
    return True


def main() -> None:
    for line in sys.stdin:
        if STOP_EVENT.is_set():
            break
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
            if not isinstance(message, dict):
                continue
            if not dispatch(message):
                break
        except json.JSONDecodeError:
            log("Ignoring malformed JSON input")
        except Exception as exc:
            log("Unhandled event error", exc)
            with STATE_LOCK:
                page_id = STATE.get("page_id", "atag:load")
            render_error(f"Unexpected plugin error: {friendly_exception(exc)}", 0, page_id, "Audio Tag Transformer error")
    handle_close()


if __name__ == "__main__":
    main()
