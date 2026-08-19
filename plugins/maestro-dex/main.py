#!/usr/bin/env python3
"""Tabame launcher plugin for the locally installed Maestro DEX database."""

from __future__ import annotations

import json
import os
import re
import sqlite3
import sys
import unicodedata
from pathlib import Path
from typing import Any

try:
    import winreg
except ImportError:  # Maestro DEX itself is Windows-only.
    winreg = None  # type: ignore[assignment]


PLUGIN_NAME = "Maestro DEX"
DATABASE_FILENAME = "dex"
EXECUTABLE_NAMES = ("MaestroDEX.exe", "Maestro Dex.exe")
SETTINGS_KEY = "settings"
SETTINGS_REQUEST_ID = "maestro-settings"
DEFAULT_MAX_RESULTS = 60
MIN_RESULTS = 10
MAX_RESULTS = 200
DETAIL_CACHE_LIMIT = 48

PAGE_SEARCH = "maestro:search"
PAGE_SETTINGS = "maestro:settings"


def send(message: dict[str, Any]) -> None:
    """Write exactly one protocol message to stdout."""
    sys.stdout.write(
        json.dumps(message, ensure_ascii=True, separators=(",", ":")) + "\n"
    )
    sys.stdout.flush()


def command(name: str, **fields: Any) -> None:
    send({"type": "command", "command": name, **fields})


def log(*parts: Any) -> None:
    print(*parts, file=sys.stderr, flush=True)


def clamp_result_limit(value: Any) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        parsed = DEFAULT_MAX_RESULTS
    return max(MIN_RESULTS, min(parsed, MAX_RESULTS))


def normalize_search_term(value: str) -> str:
    lowered = value.strip().lower()
    decomposed = unicodedata.normalize("NFD", lowered)
    return "".join(char for char in decomposed if not unicodedata.combining(char))


def escape_like(value: str) -> str:
    return value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def markdown_text(value: Any) -> str:
    text = str(value or "")
    return re.sub(r"([\\`*_{}\[\]<>#+.!|])", r"\\\1", text)


def clean_inline_text(value: Any) -> str:
    return re.sub(r"\s+", " ", str(value or "").replace("\r\n", "\n")).strip()


def format_definition_markup(value: Any) -> str:
    """Translate Maestro DEX's compact definition markup to Markdown."""
    text = clean_inline_text(value)
    text = text.replace("**", "\n\n")
    text = text.replace("*", "\n- ")
    text = re.sub(r"@([^@]+)@", r"**\1**", text)
    text = re.sub(r"\$([^$]+)\$", r"*\1*", text)
    text = re.sub(r"#([^#]+)#", r"`\1`", text)
    text = re.sub(r"\s+([.,;:!?])", r"\1", text)
    text = re.sub(r"\(\s+", "(", text)
    text = re.sub(r"\s+\)", ")", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def plain_definition(value: Any) -> str:
    text = format_definition_markup(value)
    text = re.sub(r"[`*_]", "", text)
    text = re.sub(r"^\s*-\s*", "• ", text, flags=re.MULTILINE)
    return text.strip()


def make_preview(value: Any, max_length: int = 360) -> str:
    preview = re.sub(r"\s+", " ", format_definition_markup(value)).strip()
    if len(preview) <= max_length:
        return preview
    return preview[: max_length - 1].rstrip() + "…"


def candidate_database(installation_value: Any) -> tuple[Path, Path] | None:
    """Resolve an installation directory and its database from a folder or dex file."""
    if not isinstance(installation_value, str) or not installation_value.strip():
        return None
    expanded = os.path.expandvars(installation_value.strip().strip('"'))
    path = Path(expanded).expanduser()
    try:
        if path.is_file() and path.name.lower() == DATABASE_FILENAME:
            return path.parent.resolve(), path.resolve()
        database_path = path / DATABASE_FILENAME
        if path.is_dir() and database_path.is_file():
            return path.resolve(), database_path.resolve()
    except OSError:
        return None
    return None


def executable_in(installation_path: Path | None) -> Path | None:
    if installation_path is None:
        return None
    for name in EXECUTABLE_NAMES:
        candidate = installation_path / name
        if candidate.is_file():
            return candidate
    return None


def quoted_executable_parent(value: Any) -> Path | None:
    if not isinstance(value, str) or not value.strip():
        return None
    text = value.strip()
    quoted = re.match(r'^"([^"]+)"', text)
    raw_path = quoted.group(1) if quoted else text.split(",", 1)[0].strip().strip('"')
    path = Path(os.path.expandvars(raw_path))
    return path.parent if path.suffix else path


def registry_installation_candidates() -> list[Path]:
    if winreg is None:
        return []

    candidates: list[Path] = []
    roots = (winreg.HKEY_LOCAL_MACHINE, winreg.HKEY_CURRENT_USER)
    views = (winreg.KEY_WOW64_32KEY, winreg.KEY_WOW64_64KEY)
    uninstall_key = r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"

    for root in roots:
        for view in views:
            try:
                parent = winreg.OpenKey(root, uninstall_key, 0, winreg.KEY_READ | view)
            except OSError:
                continue
            try:
                subkey_count = winreg.QueryInfoKey(parent)[0]
                for index in range(subkey_count):
                    try:
                        child_name = winreg.EnumKey(parent, index)
                        child = winreg.OpenKey(parent, child_name)
                    except OSError:
                        continue
                    try:
                        try:
                            display_name = str(
                                winreg.QueryValueEx(child, "DisplayName")[0]
                            )
                        except OSError:
                            continue
                        normalized = display_name.lower()
                        if "maestro" not in normalized or "dex" not in normalized:
                            continue
                        try:
                            location = winreg.QueryValueEx(child, "InstallLocation")[0]
                        except OSError:
                            location = None
                        if isinstance(location, str) and location.strip():
                            candidates.append(
                                Path(os.path.expandvars(location.strip().strip('"')))
                            )
                        for field in ("DisplayIcon", "UninstallString"):
                            try:
                                parent_path = quoted_executable_parent(
                                    winreg.QueryValueEx(child, field)[0]
                                )
                            except OSError:
                                parent_path = None
                            if parent_path is not None:
                                candidates.append(parent_path)
                    finally:
                        child.Close()
            finally:
                parent.Close()
    return candidates


def common_installation_candidates() -> list[Path]:
    candidates: list[Path] = []
    for variable in ("ProgramFiles(x86)", "ProgramFiles", "LOCALAPPDATA"):
        root = os.environ.get(variable)
        if not root:
            continue
        base = Path(root)
        candidates.extend(
            (
                base / "Octavian Rasnita" / "Maestro DEX 3",
                base / "Maestro DEX 3",
                base / "Maestro DEX",
                base / "Maestro Dex",
            )
        )
    return candidates


def detect_installation() -> tuple[Path, Path] | None:
    seen: set[str] = set()
    for candidate in (
        registry_installation_candidates() + common_installation_candidates()
    ):
        key = str(candidate).lower()
        if key in seen:
            continue
        seen.add(key)
        resolved = candidate_database(str(candidate))
        if resolved is not None:
            return resolved
    return None


class MaestroDatabase:
    REQUIRED_TABLES = {"lexem", "lexem_definition", "definition", "source"}

    def __init__(self) -> None:
        self.path: Path | None = None
        self.connection: sqlite3.Connection | None = None

    def close(self) -> None:
        if self.connection is not None:
            self.connection.close()
        self.connection = None
        self.path = None

    def open(self, path: Path) -> None:
        self.close()
        uri = path.resolve().as_uri() + "?mode=ro"
        connection = sqlite3.connect(uri, uri=True, timeout=3.0)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA query_only = ON")
        tables = {
            row[0]
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            ).fetchall()
        }
        missing = self.REQUIRED_TABLES - tables
        if missing:
            connection.close()
            raise ValueError(
                "The selected dex file is missing tables: " + ", ".join(sorted(missing))
            )
        self.path = path
        self.connection = connection

    def require_connection(self) -> sqlite3.Connection:
        if self.connection is None:
            raise RuntimeError("The Maestro DEX database is not open.")
        return self.connection

    def search(self, search_text: str, limit: int) -> list[dict[str, Any]]:
        raw_query = search_text.strip().lower()
        if not raw_query:
            return []

        ascii_query = normalize_search_term(raw_query)
        dia_prefix = escape_like(raw_query) + "%"
        ascii_prefix = escape_like(ascii_query) + "%"
        safe_limit = clamp_result_limit(limit)
        sql = """
            WITH matches AS (
              SELECT
                l.id AS lexemId,
                l.lexem AS lemma,
                l.inflection_dia AS matchedForm,
                l.inflection AS matchedAscii,
                CASE
                  WHEN l.inflection_dia = ? THEN 0
                  WHEN l.inflection = ? THEN 1
                  WHEN l.lexem = ? THEN 2
                  WHEN l.inflection_dia LIKE ? ESCAPE '\\' THEN 3
                  WHEN l.inflection LIKE ? ESCAPE '\\' THEN 4
                  WHEN l.lexem LIKE ? ESCAPE '\\' THEN 5
                  ELSE 6
                END AS matchRank
              FROM lexem l
              WHERE l.inflection_dia = ?
                 OR l.inflection = ?
                 OR l.lexem = ?
                 OR l.inflection_dia LIKE ? ESCAPE '\\'
                 OR l.inflection LIKE ? ESCAPE '\\'
                 OR l.lexem LIKE ? ESCAPE '\\'
            ),
            ranked AS (
              SELECT *, ROW_NUMBER() OVER (
                PARTITION BY lexemId
                ORDER BY matchRank, length(matchedForm), matchedForm
              ) AS rowNumber
              FROM matches
            )
            SELECT
              r.lexemId,
              r.lemma,
              r.matchedForm,
              r.matchedAscii,
              r.matchRank,
              COUNT(DISTINCT ld.definition_id) AS definitionCount,
              GROUP_CONCAT(DISTINCT s.shortname) AS sources
            FROM ranked r
            LEFT JOIN lexem_definition ld ON ld.lexem_id = r.lexemId
            LEFT JOIN definition d ON d.id = ld.definition_id
            LEFT JOIN source s ON s.id = d.source_id
            WHERE r.rowNumber = 1
            GROUP BY r.lexemId, r.lemma, r.matchedForm, r.matchedAscii, r.matchRank
            ORDER BY r.matchRank, length(r.matchedForm), r.lemma COLLATE NOCASE
            LIMIT ?
        """
        values = (
            raw_query,
            ascii_query,
            raw_query,
            dia_prefix,
            ascii_prefix,
            dia_prefix,
            raw_query,
            ascii_query,
            raw_query,
            dia_prefix,
            ascii_prefix,
            dia_prefix,
            safe_limit,
        )
        rows = self.require_connection().execute(sql, values).fetchall()
        results: list[dict[str, Any]] = []
        for row in rows:
            sources = [
                source.strip()
                for source in str(row["sources"] or "").split(",")
                if source.strip()
            ]
            results.append(
                {
                    "lexemId": int(row["lexemId"]),
                    "lemma": str(row["lemma"] or ""),
                    "matchedForm": str(row["matchedForm"] or row["lemma"] or ""),
                    "matchedAscii": str(row["matchedAscii"] or ""),
                    "matchRank": int(row["matchRank"]),
                    "definitionCount": int(row["definitionCount"]),
                    "sources": sources,
                }
            )
        return results

    def details(self, entry: dict[str, Any]) -> dict[str, Any]:
        rows = (
            self.require_connection()
            .execute(
                """
            SELECT
              d.id AS id,
              s.shortname AS sourceShortName,
              s.name AS sourceName,
              s.author AS sourceAuthor,
              s.year AS sourceYear,
              d.definition AS definition
            FROM lexem_definition ld
            JOIN definition d ON d.id = ld.definition_id
            LEFT JOIN source s ON s.id = d.source_id
            WHERE ld.lexem_id = ?
            ORDER BY s.shortname COLLATE NOCASE, d.id
            """,
                (entry["lexemId"],),
            )
            .fetchall()
        )

        definitions = [dict(row) for row in rows]
        markdown_blocks: list[str] = []
        plain_blocks: list[str] = []
        for definition in definitions:
            short_name = str(definition.get("sourceShortName") or "Fără sursă")
            source_bits = [
                definition.get("sourceShortName"),
                definition.get("sourceName"),
                definition.get("sourceAuthor"),
            ]
            source_line = " • ".join(str(value) for value in source_bits if value)
            if definition.get("sourceYear"):
                source_line = (source_line + " • " if source_line else "") + str(
                    definition["sourceYear"]
                )
            content = format_definition_markup(definition.get("definition"))
            markdown_blocks.append(
                f"## {markdown_text(short_name)}\n"
                + (f"{markdown_text(source_line)}\n\n" if source_line else "")
                + content
            )
            plain_blocks.append(
                f"{short_name}\n{plain_definition(definition.get('definition'))}"
            )

        lemma = str(entry["lemma"])
        matched_form = str(entry["matchedForm"])
        header = [f"# {markdown_text(lemma)}"]
        if matched_form != lemma:
            header.append(f"Forma căutată: **{markdown_text(matched_form)}**")
        header.append(f"Definiții găsite: **{len(definitions)}**")
        no_definitions = "Nicio definiție disponibilă."
        return {
            "markdown": "\n\n".join(header)
            + "\n\n"
            + (
                "\n\n---\n\n".join(markdown_blocks)
                if markdown_blocks
                else no_definitions
            ),
            "plainText": lemma
            + "\n\n"
            + ("\n\n".join(plain_blocks) if plain_blocks else no_definitions),
            "definitions": definitions,
        }


DB = MaestroDatabase()
STATE: dict[str, Any] = {
    "ready": False,
    "settings_requested": False,
    "installation_path": None,
    "database_path": None,
    "max_results": DEFAULT_MAX_RESULTS,
    "route": PAGE_SEARCH,
    "route_stack": [PAGE_SEARCH],
    "search_query": "",
    "entries": [],
    "selected_id": None,
    "current_entry": None,
    "details_cache": {},
    "last_error": None,
}


def page(page_id: str, title: str, history: str = "none") -> dict[str, Any]:
    breadcrumbs = (
        [] if page_id == PAGE_SEARCH else [{"id": PAGE_SEARCH, "label": PLUGIN_NAME}]
    )
    return {
        "id": page_id,
        "title": title,
        "history": history,
        "preserveState": True,
        "breadcrumbs": breadcrumbs,
    }


def settings_payload() -> str:
    return json.dumps(
        {
            "installationPath": str(STATE["installation_path"] or ""),
            "maxResults": STATE["max_results"],
        },
        ensure_ascii=False,
    )


def save_settings() -> None:
    command("storage", op="set", key=SETTINGS_KEY, value=settings_payload())


def parse_settings(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    if isinstance(value, str) and value.strip():
        try:
            parsed = json.loads(value)
            return parsed if isinstance(parsed, dict) else {}
        except json.JSONDecodeError:
            return {}
    return {}


def configure_database(installation_value: Any) -> str | None:
    resolved = candidate_database(installation_value)
    if resolved is None:
        return "Select the Maestro DEX installation folder containing the `dex` database file."
    installation_path, database_path = resolved
    try:
        DB.open(database_path)
    except (OSError, sqlite3.Error, ValueError) as error:
        return f"The selected folder does not contain a readable Maestro DEX database: {error}"
    STATE["installation_path"] = installation_path
    STATE["database_path"] = database_path
    STATE["last_error"] = None
    STATE["details_cache"] = {}
    return None


def load_or_detect_settings(value: Any) -> None:
    stored = parse_settings(value)
    STATE["max_results"] = clamp_result_limit(stored.get("maxResults"))
    configured = False
    stored_path = stored.get("installationPath")
    if stored_path:
        configured = configure_database(stored_path) is None

    if not configured:
        detected = detect_installation()
        if detected is not None:
            installation_path, _ = detected
            configured = configure_database(str(installation_path)) is None
            if configured:
                save_settings()

    STATE["ready"] = True
    render_search(0, STATE["search_query"])


def installation_metadata() -> list[dict[str, Any]]:
    installation = STATE["installation_path"]
    database = STATE["database_path"]
    rows: list[dict[str, Any]] = []
    if installation:
        rows.append(
            {"label": "Installation", "text": str(installation), "icon": "folder"}
        )
    if database:
        try:
            size_mb = Path(database).stat().st_size / (1024 * 1024)
            rows.append(
                {"label": "Database", "text": f"{size_mb:,.1f} MB", "icon": "database"}
            )
        except OSError:
            pass
    rows.append(
        {"label": "Result limit", "text": str(STATE["max_results"]), "icon": "list"}
    )
    return rows


def frame_actions() -> list[dict[str, Any]]:
    actions = [
        {
            "id": "settings",
            "title": "Maestro DEX Settings",
            "icon": "settings",
            "shortcut": "ctrl+alt+s",
        },
        {
            "id": "refresh",
            "title": "Reload Database",
            "icon": "refresh",
            "shortcut": "ctrl+r",
        },
    ]
    if STATE["installation_path"]:
        actions.append(
            {
                "id": "open-installation",
                "title": "Open Installation Folder",
                "icon": "folder",
            }
        )
    if executable_in(STATE["installation_path"]):
        actions.append(
            {"id": "launch-maestro", "title": "Launch Maestro DEX", "icon": "open"}
        )
    return actions


def search_empty_frame(rev: int, *, history: str = "none") -> None:
    database_available = DB.connection is not None
    query = str(STATE["search_query"]).strip()
    if not database_available:
        empty = {
            "icon": "warning",
            "title": "Choose your Maestro DEX installation",
            "hint": "Select the folder containing the dex database and MaestroDEX.exe.",
            "action": {"id": "settings", "title": "Set installation", "icon": "folder"},
        }
    elif query:
        empty = {
            "icon": "search",
            "title": f"No definitions found for “{query}”",
            "hint": "Try another lemma or an inflected form, with or without Romanian diacritics.",
        }
    else:
        empty = {
            "icon": "book",
            "title": "Search the Romanian dictionary",
            "hint": "Try casă, casa, merge, or merg. Inflected forms are supported.",
        }

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": page(PAGE_SEARCH, PLUGIN_NAME, history),
            "elementId": "maestro-results",
            "placeholder": "Search a Romanian word in Maestro DEX…",
            "items": [],
            "empty": empty,
            "actions": frame_actions(),
            # "floatingAction": [
            #     {"id": "settings", "title": "Settings", "icon": "settings"},
            #     *(
            #         [{"id": "launch-maestro", "title": "Open Maestro DEX", "icon": "open"}]
            #         if executable_in(STATE["installation_path"])
            #         else []
            #     ),
            # ],
        }
    )


def result_section(rank: int) -> str:
    if rank <= 2:
        return "Exact matches"
    if rank <= 5:
        return "Starts with"
    return "Related matches"


def accessory_text(entry: dict[str, Any]) -> str:
    definition_count = entry["definitionCount"]
    source_count = len(entry["sources"])
    if source_count:
        return f"{definition_count} defs • {source_count} sources"
    return f"{definition_count} defs"


def entry_preview(
    entry: dict[str, Any], details: dict[str, Any] | None
) -> dict[str, Any]:
    if details and details["definitions"]:
        blocks = []
        for definition in details["definitions"][:3]:
            title = markdown_text(definition.get("sourceShortName") or "Fără sursă")
            blocks.append(f"### {title}\n{make_preview(definition.get('definition'))}")
        remaining = len(details["definitions"]) - len(blocks)
        if remaining > 0:
            blocks.append(
                f"*Press Enter to read {remaining} more definition{'s' if remaining != 1 else ''}.*"
            )
        markdown = "\n\n".join(blocks)
    else:
        markdown = "Select this result to load its definition preview."

    sources = ", ".join(entry["sources"]) or "Unknown"
    return {
        "markdown": f"## {markdown_text(entry['lemma'])}\n\n{markdown}",
        "metadata": [
            {"label": "Lemma", "text": entry["lemma"], "icon": "book"},
            {"label": "Matched form", "text": entry["matchedForm"], "icon": "search"},
            {
                "label": "Definitions",
                "text": str(entry["definitionCount"]),
                "icon": "document",
            },
            {"separator": True},
            {"label": "Sources", "text": sources, "icon": "database"},
        ],
    }


def item_for_entry(entry: dict[str, Any]) -> dict[str, Any]:
    entry_id = f"entry:{entry['lexemId']}"
    details = STATE["details_cache"].get(entry_id)
    matched = entry["matchedForm"]
    subtitle = f"Matched form: {matched}" if matched != entry["lemma"] else ""
    source = entry["sources"][0] if entry["sources"] else None
    accessories: list[dict[str, Any]] = [
        {
            "text": accessory_text(entry),
            "color": "#22C55E" if entry["matchRank"] <= 2 else "#3B82F6",
        }
    ]
    if source:
        accessories.append({"text": source, "icon": "bookmark"})
    return {
        "id": entry_id,
        "title": entry["lemma"],
        "subtitle": subtitle,
        "icon": "book" if entry["matchRank"] <= 2 else "search",
        "section": result_section(entry["matchRank"]),
        "accessories": accessories,
        "actions": [
            {"id": "default", "title": "Show Full Definitions", "icon": "document"},
            {
                "id": "copy-definitions",
                "title": "Copy Definitions",
                "icon": "copy",
                "shortcut": "ctrl+shift+c",
            },
            {
                "id": "copy-lemma",
                "title": "Copy Lemma",
                "icon": "content_copy",
                "shortcut": "ctrl+alt+c",
            },
        ],
        "preview": entry_preview(entry, details),
    }


def find_entry(item_id: str | None) -> dict[str, Any] | None:
    if not item_id:
        return None
    for entry in STATE["entries"]:
        if f"entry:{entry['lexemId']}" == item_id:
            return entry
    current = STATE.get("current_entry")
    if current and f"entry:{current['lexemId']}" == item_id:
        return current
    return None


def ensure_details(entry: dict[str, Any]) -> dict[str, Any]:
    entry_id = f"entry:{entry['lexemId']}"
    cached = STATE["details_cache"].get(entry_id)
    if cached is None:
        cached = DB.details(entry)
        while len(STATE["details_cache"]) >= DETAIL_CACHE_LIMIT:
            STATE["details_cache"].pop(next(iter(STATE["details_cache"])))
        STATE["details_cache"][entry_id] = cached
    return cached


def send_result_list(rev: int, history: str = "none") -> None:
    items = [item_for_entry(entry) for entry in STATE["entries"]]
    frame: dict[str, Any] = {
        "type": "render",
        "rev": rev,
        "view": "list",
        "page": page(PAGE_SEARCH, PLUGIN_NAME, history),
        "elementId": "maestro-results",
        "placeholder": "Search a Romanian word in Maestro DEX…",
        "preview": {"enabled": True, "wide": False},
        "items": items,
        "actions": frame_actions(),
        # "floatingAction": [
        #     {"id": "settings", "title": "Settings", "icon": "settings"},
        #     *(
        #         [{"id": "launch-maestro", "title": "Open Maestro DEX", "icon": "open"}]
        #         if executable_in(STATE["installation_path"])
        #         else []
        #     ),
        # ],
    }
    if STATE["selected_id"]:
        frame["selectId"] = STATE["selected_id"]
    send(frame)


def render_search(rev: int, text: str | None = None, *, history: str = "none") -> None:
    STATE["route"] = PAGE_SEARCH
    if text is not None:
        STATE["search_query"] = text
    query = str(STATE["search_query"]).strip()

    if not STATE["ready"]:
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "list",
                "page": page(PAGE_SEARCH, PLUGIN_NAME, history),
                "loading": True,
                "loadingText": "Finding the Maestro DEX installation…",
                "items": [],
            }
        )
        return
    if DB.connection is None or not query:
        STATE["entries"] = []
        STATE["selected_id"] = None
        search_empty_frame(rev, history=history)
        return

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": page(PAGE_SEARCH, PLUGIN_NAME, history),
            "loading": True,
            "loadingText": f"Searching Maestro DEX for “{query}”…",
            "items": [],
        }
    )
    try:
        entries = DB.search(query, STATE["max_results"])
        STATE["entries"] = entries
        STATE["selected_id"] = f"entry:{entries[0]['lexemId']}" if entries else None
        if entries:
            ensure_details(entries[0])
            send_result_list(rev)
        else:
            search_empty_frame(rev)
    except (OSError, sqlite3.Error, RuntimeError) as error:
        STATE["last_error"] = str(error)
        STATE["entries"] = []
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "detail",
                "page": page(PAGE_SEARCH, PLUGIN_NAME),
                "wide": False,
                "detail": {
                    "markdown": "# Maestro DEX search failed\n\n"
                    "The configured database could not be queried. Open settings to select the installation again.\n\n"
                    f"```\n{error}\n```",
                    "metadata": installation_metadata(),
                },
                "actions": frame_actions(),
                "floatingAction": {
                    "id": "settings",
                    "title": "Settings",
                    "icon": "settings",
                },
            }
        )


def render_settings(
    rev: int = 0,
    *,
    history: str = "none",
    error: str | None = None,
    values: dict[str, Any] | None = None,
) -> None:
    STATE["route"] = PAGE_SETTINGS
    values = values or {}
    installation_value = values.get(
        "installationPath", STATE["installation_path"] or ""
    )
    max_value = clamp_result_limit(values.get("maxResults", STATE["max_results"]))
    actions: list[dict[str, Any]] = []
    if STATE["installation_path"]:
        actions.append(
            {
                "id": "open-installation",
                "title": "Open Installation Folder",
                "icon": "folder",
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "page": page(PAGE_SETTINGS, "Settings", history),
            "elementId": "maestro-settings-form",
            "placeholder": "Configure Maestro DEX…",
            "form": {
                "title": "Maestro DEX Settings",
                **({"error": error} if error else {}),
                "submitLabel": "Save settings",
                "sections": [
                    {
                        "id": "database",
                        "title": "Installation",
                        "description": "Tabame opens the dex database read-only.",
                    },
                    {
                        "id": "search",
                        "title": "Search",
                        "description": "Limit the number of matches shown in the launcher.",
                    },
                ],
                "fields": [
                    {
                        "id": "installationPath",
                        "type": "folderpicker",
                        "label": "Maestro DEX installation folder",
                        "description": "Choose the folder containing the dex file and, normally, MaestroDEX.exe.",
                        "value": str(installation_value),
                        "required": True,
                        "section": "database",
                    },
                    {
                        "id": "maxResults",
                        "type": "number",
                        "label": "Maximum results",
                        "description": f"Choose between {MIN_RESULTS} and {MAX_RESULTS} results.",
                        "value": max_value,
                        "min": MIN_RESULTS,
                        "max": MAX_RESULTS,
                        "required": True,
                        "section": "search",
                    },
                ],
            },
            "actions": actions,
        }
    )


def render_entry(entry: dict[str, Any], rev: int = 0, *, history: str = "none") -> None:
    STATE["current_entry"] = entry
    route = f"maestro:entry:{entry['lexemId']}"
    STATE["route"] = route
    details = ensure_details(entry)
    sources = ", ".join(entry["sources"]) or "Unknown"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "page": page(route, entry["lemma"], history),
            "elementId": "maestro-entry-detail",
            "placeholder": "Definition details",
            "wide": False,
            "preview": {"wide": False},
            "detail": {
                "markdown": details["markdown"],
                "wide": False,
                "metadata": [
                    {"label": "Lemma", "text": entry["lemma"], "icon": "book"},
                    {
                        "label": "Matched form",
                        "text": entry["matchedForm"],
                        "icon": "search",
                    },
                    {
                        "label": "Definitions",
                        "text": str(len(details["definitions"])),
                        "icon": "document",
                    },
                    {"separator": True},
                    {"label": "Sources", "text": sources, "icon": "database"},
                ],
            },
            "actions": [
                {
                    "id": "copy-definitions",
                    "title": "Copy Definitions",
                    "icon": "copy",
                    "shortcut": "ctrl+shift+c",
                },
                {
                    "id": "copy-lemma",
                    "title": "Copy Lemma",
                    "icon": "content_copy",
                    "shortcut": "ctrl+alt+c",
                },
                {"id": "settings", "title": "Maestro DEX Settings", "icon": "settings"},
                *(
                    [
                        {
                            "id": "launch-maestro",
                            "title": "Launch Maestro DEX",
                            "icon": "open",
                        }
                    ]
                    if executable_in(STATE["installation_path"])
                    else []
                ),
            ],
        }
    )


def clear_page_query() -> None:
    command("setQuery", text="")


def go_settings() -> None:
    STATE["route_stack"].append(PAGE_SETTINGS)
    clear_page_query()
    render_settings(history="push")


def go_entry(entry: dict[str, Any]) -> None:
    route = f"maestro:entry:{entry['lexemId']}"
    STATE["route_stack"].append(route)
    clear_page_query()
    render_entry(entry, history="push")


def return_to_search(history: str = "none") -> None:
    STATE["route"] = PAGE_SEARCH
    STATE["route_stack"] = [PAGE_SEARCH]
    command("setQuery", text=STATE["search_query"])
    render_search(0, history=history)


def copy_definitions(entry: dict[str, Any]) -> None:
    details = ensure_details(entry)
    command("copy", text=details["plainText"])


def handle_action(message: dict[str, Any]) -> None:
    item_id = str(message.get("id") or "")
    action = str(message.get("action") or "default")
    entry = find_entry(item_id) or STATE.get("current_entry")

    try:
        if action == "settings":
            go_settings()
        elif action == "refresh":
            installation = STATE.get("installation_path")
            error = configure_database(str(installation or ""))
            if error:
                command("toast", text=error, style="error")
                go_settings()
            else:
                command("toast", text="Maestro DEX database reloaded", style="success")
                render_search(0)
        elif action == "open-installation" and STATE["installation_path"]:
            command("open", path=str(STATE["installation_path"]))
        elif action == "launch-maestro":
            executable = executable_in(STATE["installation_path"])
            if executable:
                command("open", path=str(executable))
            else:
                command(
                    "toast",
                    text="MaestroDEX.exe was not found in the configured folder",
                    style="error",
                )
        elif action == "copy-lemma" and entry:
            command("copy", text=entry["lemma"])
        elif action == "copy-definitions" and entry:
            copy_definitions(entry)
        elif action == "default" and entry:
            go_entry(entry)
    except (OSError, sqlite3.Error, RuntimeError) as error:
        command("toast", text=f"Maestro DEX error: {error}", style="error")


def handle_select(message: dict[str, Any]) -> None:
    if STATE["route"] != PAGE_SEARCH:
        return
    item_id = str(message.get("id") or "")
    entry = find_entry(item_id)
    if entry is None:
        return
    STATE["selected_id"] = item_id
    rev = int(message.get("rev") or 0)
    try:
        ensure_details(entry)
        send_result_list(rev)
    except (OSError, sqlite3.Error, RuntimeError) as error:
        command("toast", text=f"Could not load definitions: {error}", style="error")


def handle_submit(message: dict[str, Any]) -> None:
    if STATE["route"] != PAGE_SETTINGS:
        return
    values = message.get("values")
    if not isinstance(values, dict):
        values = {}
    installation_value = values.get("installationPath", "")
    error = configure_database(installation_value)
    if error:
        render_settings(0, error=error, values=values)
        return

    STATE["max_results"] = clamp_result_limit(values.get("maxResults"))
    save_settings()
    command("toast", text="Maestro DEX settings saved", style="success")
    return_to_search(history="replace")


def handle_back(message: dict[str, Any]) -> None:
    target = str(message.get("toPageId") or PAGE_SEARCH)
    if target == PAGE_SEARCH:
        return_to_search()
        return
    if target == PAGE_SETTINGS:
        render_settings(int(message.get("rev") or 0))
        return
    current = STATE.get("current_entry")
    if current and target == f"maestro:entry:{current['lexemId']}":
        render_entry(current, int(message.get("rev") or 0))
        return
    return_to_search()


def handle_navigate(message: dict[str, Any]) -> None:
    target = str(message.get("targetPageId") or PAGE_SEARCH)
    if target == PAGE_SEARCH:
        return_to_search()
    elif target == PAGE_SETTINGS:
        render_settings(int(message.get("rev") or 0))


def handle_query(message: dict[str, Any]) -> None:
    text = str(message.get("text", message.get("query", "")) or "")
    rev = int(message.get("rev") or 0)
    if not STATE["ready"]:
        STATE["search_query"] = text
        render_search(rev)
        return
    if STATE["route"] == PAGE_SEARCH:
        render_search(rev, text)
    elif STATE["route"] == PAGE_SETTINGS:
        render_settings(rev)
    elif str(STATE["route"]).startswith("maestro:entry:") and STATE.get(
        "current_entry"
    ):
        render_entry(STATE["current_entry"], rev)


def handle_storage(message: dict[str, Any]) -> None:
    if message.get("requestId") != SETTINGS_REQUEST_ID:
        return
    load_or_detect_settings(message.get("value"))


def handle_message(message: dict[str, Any]) -> bool:
    message_type = message.get("type")
    if message_type == "close":
        DB.close()
        return False
    if message_type == "init":
        STATE["search_query"] = str(message.get("query") or "")
        if not STATE["settings_requested"]:
            STATE["settings_requested"] = True
            command(
                "storage", op="get", key=SETTINGS_KEY, requestId=SETTINGS_REQUEST_ID
            )
        render_search(0)
    elif message_type == "query":
        handle_query(message)
    elif message_type == "storage":
        handle_storage(message)
    elif message_type == "select":
        handle_select(message)
    elif message_type == "action":
        handle_action(message)
    elif message_type == "submit":
        handle_submit(message)
    elif message_type == "back":
        handle_back(message)
    elif message_type == "navigate":
        handle_navigate(message)
    elif message_type == "tab" and STATE["route"] == PAGE_SEARCH:
        entry = find_entry(str(message.get("id") or ""))
        if entry:
            command("setQuery", text=entry["lemma"])
    return True


def main() -> None:
    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
            if not isinstance(message, dict):
                continue
            if not handle_message(message):
                break
        except json.JSONDecodeError:
            log("Ignored malformed JSON input")
        except Exception as error:  # Keep the protocol process alive on bad input.
            log("Unhandled Maestro DEX plugin error:", repr(error))
            send(
                {
                    "type": "render",
                    "rev": 0,
                    "view": "detail",
                    "wide": False,
                    "detail": {
                        "markdown": "# Maestro DEX error\n\n"
                        "The plugin recovered from an unexpected error.\n\n"
                        f"```\n{error}\n```"
                    },
                    "actions": [
                        {"id": "settings", "title": "Open Settings", "icon": "settings"}
                    ],
                }
            )
    DB.close()


if __name__ == "__main__":
    main()
