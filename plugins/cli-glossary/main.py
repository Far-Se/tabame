#!/usr/bin/env python3
"""CLI Agent Glossary - a persistent Tabame launcher plugin.

The plugin stores prompt templates and agent command presets as plain JSON next
to this file.  It deliberately builds subprocess argv lists instead of shell
strings so a prompt can contain quotes, newlines, or nested examples safely.
"""

from __future__ import annotations

import copy
import json
import ntpath
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple


# ---------------------------------------------------------------------------
# Paths, defaults, and process-wide state
# ---------------------------------------------------------------------------


PLUGIN_DIR = Path(__file__).resolve().parent
ENTRIES_PATH = PLUGIN_DIR / "entries.json"
AGENTS_PATH = PLUGIN_DIR / "agents.json"

LOCAL_APP_DATA = Path(
    os.environ.get("LOCALAPPDATA")
    or (Path.home() / "AppData" / "Local")
)
RUNS_ROOT = LOCAL_APP_DATA / "Tabame" / "plugins" / "cli-glossary" / "runs"

RUN_TIMEOUT_SECONDS = 300
OUTPUT_WAIT_SECONDS = 2
VARIABLE_RE = re.compile(r"\{(\w+)\}")
BUILTIN_AGENT_ID = "codex"

DEFAULT_AGENTS = [
    {
        "id": "codex",
        "name": "Codex",
        "binary": ["codex", "exec"],
        "file_flag": ["-i", "{file}"],
        "output_flag": ["-o", "{output}"],
        "trailing_flags": ["--skip-git-repo-check"],
        "output_filename": "result.md",
    }
]

DEFAULT_ENTRIES = [
    {
        "id": "ocr-image",
        "name": "OCR image",
        "agent_id": "codex",
        "needs_file": True,
        "prompt": "OCR this image. ONLY OUTPUT THE TEXT AND NOTHING ELSE",
    },
    {
        "id": "translate",
        "name": "Translate",
        "agent_id": "codex",
        "needs_file": False,
        "prompt": (
            "Please translate {text} to english, spanish and german. Please "
            "translate it with the meaning from original language. Please "
            "only give a list of the language and the result such as English: "
            "[translated result]"
        ),
    },
]


SEND_LOCK = threading.Lock()
STATE_LOCK = threading.RLock()
CLOSING = threading.Event()

STATE: Dict[str, Any] = {
    "entries": [],
    "agents": [],
    "page_id": "glossary:home",
    "route_stack": ["glossary:home"],
    "home_query": "",
    "agents_query": "",
    "entry_drafts": {},
    "agent_drafts": {},
    "run_drafts": {},
    "save_draft": None,
    "data_error": "",
}

RUNTIME: Dict[str, Any] = {
    "active_run": None,
    "last_result": None,
    "save_context": None,
}


# ---------------------------------------------------------------------------
# Wire protocol helpers
# ---------------------------------------------------------------------------


def send(frame: Dict[str, Any]) -> None:
    """Write exactly one flushed JSON frame to stdout."""

    if CLOSING.is_set():
        return
    try:
        with SEND_LOCK:
            sys.stdout.write(json.dumps(frame, ensure_ascii=False) + "\n")
            sys.stdout.flush()
    except (BrokenPipeError, OSError):
        CLOSING.set()


def command(name: str, **fields: Any) -> None:
    payload: Dict[str, Any] = {"type": "command", "command": name}
    payload.update(fields)
    send(payload)


def log(*values: Any) -> None:
    print(*values, file=sys.stderr, flush=True)


def new_id(prefix: str) -> str:
    return f"{prefix}-{uuid.uuid4().hex}"


def as_string(value: Any, default: str = "") -> str:
    if value is None:
        return default
    if isinstance(value, str):
        return value
    return str(value)


def message_rev(message: Dict[str, Any]) -> int:
    try:
        return int(message.get("rev", 0))
    except (TypeError, ValueError):
        return 0


# ---------------------------------------------------------------------------
# JSON persistence and normalization
# ---------------------------------------------------------------------------


def write_json_atomic(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    os.replace(str(temporary), str(path))


def read_json_file(path: Path, default: Any) -> Any:
    if not path.exists():
        value = copy.deepcopy(default)
        write_json_atomic(path, value)
        return value
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def normalize_token_list(value: Any) -> List[str]:
    if isinstance(value, list):
        return [as_string(token) for token in value if as_string(token).strip()]
    if isinstance(value, str):
        return [line.strip() for line in value.splitlines() if line.strip()]
    return []


def normalize_agent(raw: Any) -> Dict[str, Any]:
    item = raw if isinstance(raw, dict) else {}
    return {
        "id": as_string(item.get("id"), new_id("agent")),
        "name": as_string(item.get("name"), "Unnamed agent").strip()
        or "Unnamed agent",
        "binary": normalize_token_list(item.get("binary")),
        "file_flag": normalize_token_list(item.get("file_flag")),
        "output_flag": normalize_token_list(item.get("output_flag")),
        "trailing_flags": normalize_token_list(item.get("trailing_flags")),
        "output_filename": as_string(item.get("output_filename"), "result.md").strip()
        or "result.md",
    }


def normalize_entry(raw: Any) -> Dict[str, Any]:
    item = raw if isinstance(raw, dict) else {}
    prompt = as_string(item.get("prompt"))
    raw_names = raw_variables(prompt)
    return {
        "id": as_string(item.get("id"), new_id("entry")),
        "name": as_string(item.get("name"), "Untitled entry").strip()
        or "Untitled entry",
        "agent_id": as_string(item.get("agent_id"), BUILTIN_AGENT_ID),
        "needs_file": bool(item.get("needs_file")) or "file" in raw_names,
        "prompt": prompt,
    }


def load_data() -> None:
    errors: List[str] = []
    try:
        raw_agents = read_json_file(AGENTS_PATH, DEFAULT_AGENTS)
        if not isinstance(raw_agents, list):
            raise ValueError("agents.json must contain a JSON array")
        agents = [normalize_agent(item) for item in raw_agents]
    except Exception as exc:
        errors.append(f"Could not read agents.json: {exc}")
        agents = [normalize_agent(item) for item in DEFAULT_AGENTS]

    try:
        raw_entries = read_json_file(ENTRIES_PATH, DEFAULT_ENTRIES)
        if not isinstance(raw_entries, list):
            raise ValueError("entries.json must contain a JSON array")
        entries = [normalize_entry(item) for item in raw_entries]
    except Exception as exc:
        errors.append(f"Could not read entries.json: {exc}")
        entries = [normalize_entry(item) for item in DEFAULT_ENTRIES]

    with STATE_LOCK:
        STATE["agents"] = agents
        STATE["entries"] = entries
        STATE["data_error"] = "\n".join(errors)


def cleanup_run_directories() -> None:
    """Remove scratch artifacts from previous plugin sessions."""

    try:
        if RUNS_ROOT.is_symlink():
            log("Refusing to clean CLI Glossary runs because the runs root is a symlink.")
            return
        RUNS_ROOT.mkdir(parents=True, exist_ok=True)
        if RUNS_ROOT.is_symlink():
            log("Refusing to clean CLI Glossary runs because the runs root is a symlink.")
            return
        root = RUNS_ROOT.resolve()
        removed = 0
        for child in root.iterdir():
            # Never follow a symlink out of the plugin-owned scratch root.
            if child.is_symlink():
                child.unlink()
                removed += 1
            elif child.is_dir():
                shutil.rmtree(str(child))
                removed += 1
            elif child.is_file():
                child.unlink()
                removed += 1
        if removed:
            log(f"Removed {removed} old CLI Glossary run artifact(s).")
    except Exception as exc:
        log("Could not clean CLI Glossary run artifacts:", exc)


def save_agents() -> None:
    with STATE_LOCK:
        write_json_atomic(AGENTS_PATH, STATE["agents"])


def save_entries() -> None:
    with STATE_LOCK:
        write_json_atomic(ENTRIES_PATH, STATE["entries"])


def find_agent(agent_id: str) -> Optional[Dict[str, Any]]:
    with STATE_LOCK:
        for agent in STATE["agents"]:
            if agent.get("id") == agent_id:
                return agent
    return None


def find_entry(entry_id: str) -> Optional[Dict[str, Any]]:
    with STATE_LOCK:
        for entry in STATE["entries"]:
            if entry.get("id") == entry_id:
                return entry
    return None


# ---------------------------------------------------------------------------
# Template variables, command construction, and presentation helpers
# ---------------------------------------------------------------------------


def raw_variables(prompt: str) -> List[str]:
    names: List[str] = []
    for match in VARIABLE_RE.finditer(prompt):
        name = match.group(1)
        if name not in names:
            names.append(name)
    return names


def entry_variables(entry: Dict[str, Any]) -> List[str]:
    prompt_names = raw_variables(as_string(entry.get("prompt")))
    needs_file = bool(entry.get("needs_file")) or "file" in prompt_names
    if needs_file and "file" not in prompt_names:
        # The checkbox implies the reserved variable.  It is shown first so
        # the special file input is always easy to find.
        prompt_names.insert(0, "file")
    return prompt_names


def entry_needs_file(entry: Dict[str, Any]) -> bool:
    return "file" in entry_variables(entry)


def substitute_placeholders(text: str, substitutions: Dict[str, Any]) -> str:
    def replace(match: re.Match[str]) -> str:
        name = match.group(1)
        if name not in substitutions:
            return match.group(0)
        return as_string(substitutions[name])

    return VARIABLE_RE.sub(replace, text)


def safe_output_filename(value: Any) -> str:
    raw = as_string(value, "result.md").strip()
    # Agent presets are allowed to be edited, but output must remain in the
    # per-run directory.  Support both slash styles when taking the basename.
    name = ntpath.basename(raw.replace("/", "\\"))
    return name if name not in ("", ".", "..") else "result.md"


def new_run_directory() -> Path:
    RUNS_ROOT.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    directory = RUNS_ROOT / f"run-{stamp}-{uuid.uuid4().hex[:8]}"
    directory.mkdir(parents=True, exist_ok=False)
    return directory


def parse_token_field(value: Any) -> List[str]:
    """Parse the agent editor's one-token-per-line fields.

    A JSON array is also accepted as a small convenience for users importing
    an existing preset; the saved representation remains an array.
    """

    if isinstance(value, list):
        return normalize_token_list(value)
    text = as_string(value)
    stripped = text.strip()
    if stripped.startswith("["):
        try:
            parsed = json.loads(stripped)
            if isinstance(parsed, list):
                return normalize_token_list(parsed)
        except json.JSONDecodeError:
            pass
    return normalize_token_list(text)


def tokens_for_display(tokens: Iterable[Any]) -> str:
    return "\n".join(as_string(token) for token in tokens)


def snippet(prompt: str, limit: int = 120) -> str:
    compact = " ".join(as_string(prompt).split())
    if len(compact) <= limit:
        return compact
    return compact[: limit - 1].rstrip() + "…"


def display_command(argv: List[str]) -> str:
    try:
        return subprocess.list2cmdline([as_string(part) for part in argv])
    except Exception:
        return " ".join(as_string(part) for part in argv)


def field_id_for_variable(name: str) -> str:
    return f"run-var-{name}"


def variable_label(name: str) -> str:
    if name == "file":
        return "File input"
    return name.replace("_", " ").title()


def default_save_folder() -> str:
    for folder_name in ("Desktop", "Documents"):
        folder = Path.home() / folder_name
        if folder.is_dir():
            return str(folder)
    return str(Path.home())


def error_markdown(title: str, message: str, details: str = "") -> str:
    body = f"# {title}\n\n{message}"
    if details:
        safe_details = details.replace("```", "``\u200b`")
        body += f"\n\n```text\n{safe_details}\n```"
    return body


# ---------------------------------------------------------------------------
# Page identity, history, and breadcrumbs
# ---------------------------------------------------------------------------


def entry_id_from_page(page_id: str) -> Optional[str]:
    if page_id.startswith("glossary:edit:"):
        return page_id.split(":", 2)[2]
    if page_id.startswith("glossary:run:"):
        return page_id.split(":", 2)[2]
    return None


def context_entry_id() -> Optional[str]:
    page_id = as_string(STATE.get("page_id"))
    page_entry_id = entry_id_from_page(page_id)
    if page_entry_id:
        return page_entry_id
    active = RUNTIME.get("active_run") or RUNTIME.get("last_result")
    if active:
        return as_string(active.get("entry_id"))
    return None


def entry_crumb(entry_id: Optional[str]) -> Dict[str, str]:
    entry = find_entry(entry_id or "")
    label = entry.get("name") if entry else "Entry"
    return {"id": f"glossary:edit:{entry_id}", "label": as_string(label)}


def breadcrumbs_for(page_id: str) -> List[Dict[str, str]]:
    home = {"id": "glossary:home", "label": "Glossary"}
    agents = {"id": "glossary:agents", "label": "Agents"}
    if page_id == "glossary:home":
        return []
    if page_id == "glossary:agents":
        return [home]
    if page_id.startswith("glossary:agent:"):
        return [home, agents]
    if page_id.startswith("glossary:edit:"):
        return [home]

    entry_id = context_entry_id()
    entry_page = entry_crumb(entry_id) if entry_id else None
    if page_id.startswith("glossary:run:"):
        return [home] + ([entry_page] if entry_page else [])
    if page_id == "glossary:running":
        crumbs = [home]
        if entry_page:
            crumbs.append(entry_page)
            crumbs.append(
                {
                    "id": f"glossary:run:{entry_id}",
                    "label": "Run",
                }
            )
        return crumbs
    if page_id == "glossary:result":
        crumbs = [home]
        if entry_page:
            crumbs.append(entry_page)
            crumbs.append(
                {
                    "id": f"glossary:run:{entry_id}",
                    "label": "Run",
                }
            )
            crumbs.append({"id": "glossary:running", "label": "Running"})
        return crumbs
    if page_id == "glossary:save":
        return breadcrumbs_for("glossary:result")
    if page_id == "glossary:error":
        return [home]
    return [home]


def page_payload(
    page_id: str,
    title: str,
    history: str,
    preserve_state: bool = True,
) -> Dict[str, Any]:
    page: Dict[str, Any] = {
        "id": page_id,
        "title": title,
        "history": history,
        "preserveState": preserve_state,
    }
    crumbs = breadcrumbs_for(page_id)
    if crumbs:
        page["breadcrumbs"] = crumbs
    return page


def navigate_to(
    page_id: str,
    history: str = "push",
    clear_query: bool = True,
) -> None:
    with STATE_LOCK:
        current = as_string(STATE.get("page_id"))
        actual_history = history
        stack = STATE.setdefault("route_stack", ["glossary:home"])
        if history == "push":
            if page_id == current:
                actual_history = "none"
            else:
                stack.append(page_id)
        elif history == "replace":
            if stack:
                stack[-1] = page_id
                if len(stack) > 1 and stack[-2] == page_id:
                    stack.pop()
            else:
                stack.append(page_id)
        STATE["page_id"] = page_id

    if clear_query:
        command("setQuery", text="")
    render_page(0, actual_history)


def navigate_existing(page_id: str) -> None:
    with STATE_LOCK:
        stack = STATE.setdefault("route_stack", ["glossary:home"])
        if page_id in stack:
            index = max(index for index, value in enumerate(stack) if value == page_id)
            del stack[index + 1 :]
        elif page_id == "glossary:home":
            STATE["route_stack"] = ["glossary:home"]
        else:
            STATE["route_stack"] = ["glossary:home", page_id]
        STATE["page_id"] = page_id
    command("setQuery", text="")
    render_page(0, "none")


# ---------------------------------------------------------------------------
# Home and agent list pages
# ---------------------------------------------------------------------------


def data_warning_banner() -> Optional[Dict[str, Any]]:
    if not STATE.get("data_error"):
        return None
    return {
        "id": "glossary-data-warning",
        "style": "warning",
        "title": "Data recovery notice",
        "message": as_string(STATE["data_error"]),
        "icon": "warning",
    }


def entry_item(entry: Dict[str, Any]) -> Dict[str, Any]:
    agent = find_agent(as_string(entry.get("agent_id")))
    agent_name = agent.get("name") if agent else "Missing agent"
    item: Dict[str, Any] = {
        "id": f"entry:{entry.get('id')}",
        "title": as_string(entry.get("name")),
        "subtitle": snippet(as_string(entry.get("prompt")))
        or "No prompt text yet",
        "icon": "file" if entry_needs_file(entry) else "terminal",
        "accessories": [
            {"text": as_string(agent_name), "icon": "terminal"},
        ],
        "actions": [
            {"id": "default", "title": "Run", "icon": "run"},
            {"id": "edit", "title": "Edit", "icon": "edit"},
            {"id": "duplicate", "title": "Duplicate", "icon": "copy"},
            {
                "id": "delete",
                "title": "Delete",
                "icon": "delete",
                "destructive": True,
                "confirm": {
                    "title": "Delete this glossary entry?",
                    "message": "The saved prompt cannot be recovered from the plugin.",
                    "confirmLabel": "Delete",
                },
            },
        ],
    }
    return item


def render_home(rev: int, page_history: str = "none") -> None:
    with STATE_LOCK:
        query = as_string(STATE.get("home_query")).strip().lower()
        entries = list(STATE.get("entries", []))

    visible: List[Dict[str, Any]] = []
    for entry in entries:
        agent = find_agent(as_string(entry.get("agent_id")))
        agent_name = as_string(agent.get("name")) if agent else "missing agent"
        searchable = f"{entry.get('name', '')} {agent_name}".lower()
        if query and query not in searchable:
            continue
        visible.append(entry_item(entry))

    frame: Dict[str, Any] = {
        "type": "render",
        "rev": rev,
        "view": "list",
        "page": page_payload(
            "glossary:home",
            "CLI Agent Glossary",
            page_history,
            preserve_state=True,
        ),
        "elementId": "glossary-entry-list",
        "placeholder": "Filter entries by name or agent…",
        "emptyText": "No glossary entries",
        "items": visible,
        "actions": [
            {"id": "new-entry", "title": "New Entry", "icon": "add"},
            {"id": "manage-agents", "title": "Manage Agents", "icon": "settings"},
        ],
        "floatingAction": [
            {"id": "new-entry", "title": "New Entry", "icon": "add"},
            {"id": "manage-agents", "title": "Manage Agents", "icon": "settings"},
        ],
    }

    if not visible:
        if entries and query:
            frame["empty"] = {
                "icon": "search",
                "title": "No matching entries",
                "hint": "Filter by an entry name or agent preset.",
                "action": {"id": "clear-filter", "title": "Clear filter", "icon": "close"},
            }
        else:
            frame["empty"] = {
                "icon": "code",
                "title": "Your glossary is empty",
                "hint": "Save a prompt template, then fill its variables whenever you run it.",
                "action": {"id": "new-entry", "title": "New Entry", "icon": "add"},
            }

    warning = data_warning_banner()
    if warning:
        frame["banners"] = [warning]
    send(frame)


def agent_item(agent: Dict[str, Any]) -> Dict[str, Any]:
    agent_id = as_string(agent.get("id"))
    accessories: List[Dict[str, Any]] = [
        {"text": safe_output_filename(agent.get("output_filename")), "icon": "file"},
    ]
    if agent_id == BUILTIN_AGENT_ID:
        accessories.append({"text": "Built-in", "icon": "star"})
    actions: List[Dict[str, Any]] = [
        {"id": "default", "title": "Edit", "icon": "edit"},
        {"id": "duplicate", "title": "Duplicate", "icon": "copy"},
    ]
    if agent_id != BUILTIN_AGENT_ID:
        actions.append(
            {
                "id": "delete",
                "title": "Delete",
                "icon": "delete",
                "destructive": True,
                "confirm": {
                    "title": "Delete this agent preset?",
                    "message": "Entries using it will no longer be runnable until reassigned.",
                    "confirmLabel": "Delete",
                },
            }
        )
    binary = " ".join(as_string(token) for token in agent.get("binary", []))
    return {
        "id": f"agent:{agent_id}",
        "title": as_string(agent.get("name")),
        "subtitle": binary or "No binary tokens configured",
        "icon": "terminal",
        "accessories": accessories,
        "actions": actions,
    }


def render_agents(rev: int, page_history: str = "none") -> None:
    with STATE_LOCK:
        query = as_string(STATE.get("agents_query")).strip().lower()
        agents = list(STATE.get("agents", []))
    visible = []
    for agent in agents:
        searchable = " ".join(
            [
                as_string(agent.get("name")),
                *[as_string(token) for token in agent.get("binary", [])],
            ]
        ).lower()
        if query and query not in searchable:
            continue
        visible.append(agent_item(agent))

    frame: Dict[str, Any] = {
        "type": "render",
        "rev": rev,
        "view": "list",
        "page": page_payload(
            "glossary:agents",
            "Agent Presets",
            page_history,
            preserve_state=True,
        ),
        "elementId": "glossary-agent-list",
        "placeholder": "Filter agent presets…",
        "emptyText": "No agent presets",
        "items": visible,
        "actions": [{"id": "new-agent", "title": "New Agent", "icon": "add"}],
        "floatingAction": {"id": "new-agent", "title": "New Agent", "icon": "add"},
    }
    if not visible:
        frame["empty"] = {
            "icon": "terminal",
            "title": "No matching agent presets" if agents else "No agent presets yet",
            "hint": "Define the binary and flag tokens used by your command-line agent.",
            "action": {"id": "new-agent", "title": "New Agent", "icon": "add"},
        }
    warning = data_warning_banner()
    if warning:
        frame["banners"] = [warning]
    send(frame)


# ---------------------------------------------------------------------------
# Entry and agent forms
# ---------------------------------------------------------------------------


def default_entry_draft(entry_id: str) -> Dict[str, Any]:
    entry = find_entry(entry_id)
    first_agent = STATE["agents"][0]["id"] if STATE.get("agents") else ""
    if entry:
        return {
            "entry-name": as_string(entry.get("name")),
            "entry-agent": as_string(entry.get("agent_id")),
            "entry-needs-file": entry_needs_file(entry),
            "entry-prompt": as_string(entry.get("prompt")),
            "form_error": "",
        }
    return {
        "entry-name": "",
        "entry-agent": first_agent,
        "entry-needs-file": False,
        "entry-prompt": "",
        "form_error": "",
    }


def get_entry_draft(entry_id: str) -> Dict[str, Any]:
    with STATE_LOCK:
        drafts = STATE.setdefault("entry_drafts", {})
        if entry_id not in drafts:
            drafts[entry_id] = default_entry_draft(entry_id)
        return drafts[entry_id]


def agent_options(selected_id: str = "") -> List[Dict[str, str]]:
    options = [
        {"value": as_string(agent.get("id")), "label": as_string(agent.get("name"))}
        for agent in STATE.get("agents", [])
    ]
    if selected_id and not any(option["value"] == selected_id for option in options):
        options.append({"value": selected_id, "label": "Missing preset: " + selected_id})
    return options


def detected_description(prompt: str, needs_file: bool) -> str:
    names = raw_variables(prompt)
    implied = needs_file and "file" not in names
    if implied:
        names.insert(0, "file")
    if not names:
        return "Detected variables: none. This prompt will run as-is."
    rendered = []
    for name in names:
        rendered.append(f"{{{name}}}" + (" (file picker)" if name == "file" else ""))
    suffix = " The file checkbox implies {file}." if implied else ""
    return "Detected variables in run-form order: " + ", ".join(rendered) + "." + suffix


def render_entry_form(
    entry_id: str,
    rev: int,
    page_history: str = "none",
    field_errors: Optional[Dict[str, str]] = None,
    form_error: str = "",
) -> None:
    draft = get_entry_draft(entry_id)
    entry = find_entry(entry_id)
    is_new = entry_id == "new" or entry is None
    title = "New Entry" if is_new else "Edit Entry"
    display_title = title if is_new else f"Edit: {as_string(entry.get('name'))}"
    field_errors = field_errors or {}
    form_error = form_error or as_string(draft.get("form_error"))
    selected_agent = as_string(draft.get("entry-agent"))
    needs_file = bool(draft.get("entry-needs-file")) or "file" in raw_variables(
        as_string(draft.get("entry-prompt"))
    )
    fields: List[Dict[str, Any]] = [
        {
            "id": "entry-name",
            "type": "text",
            "label": "Entry name",
            "placeholder": "OCR image",
            "value": as_string(draft.get("entry-name")),
            "required": True,
            "section": "entry-details",
        },
        {
            "id": "entry-agent",
            "type": "dropdown",
            "label": "Agent preset",
            "value": selected_agent,
            "required": True,
            "options": agent_options(selected_agent),
            "section": "entry-details",
        },
        {
            "id": "entry-needs-file",
            "type": "checkbox",
            "label": "Needs file input",
            "value": needs_file,
            "watch": True,
            "description": (
                "Adds the reserved {file} variable and inserts the preset's file "
                "flag automatically."
            ),
            "section": "entry-details",
        },
        {
            "id": "entry-prompt",
            "type": "textarea",
            "label": "Prompt text",
            "placeholder": "Describe what the coding agent should do…",
            "value": as_string(draft.get("entry-prompt")),
            "required": True,
            "watch": True,
            "description": detected_description(
                as_string(draft.get("entry-prompt")), needs_file
            ),
            "section": "entry-details",
        },
    ]
    for field in fields:
        if field["id"] in field_errors:
            field["error"] = field_errors[field["id"]]

    form: Dict[str, Any] = {
        "title": title,
        "sections": [
            {
                "id": "entry-details",
                "title": "Template",
                "description": "Only the prompt belongs here; output flags are added when it runs.",
            }
        ],
        "submitLabel": "Create Entry" if is_new else "Save Entry",
        "fields": fields,
    }
    if form_error:
        form["error"] = form_error

    frame: Dict[str, Any] = {
        "type": "render",
        "rev": rev,
        "view": "form",
        "page": page_payload(
            f"glossary:edit:{entry_id}",
            display_title,
            page_history,
            preserve_state=not is_new,
        ),
        "elementId": "glossary-entry-form",
        "placeholder": "Editing glossary entry…",
        "form": form,
        "actions": [
            {"id": "manage-agents", "title": "Manage Agents", "icon": "settings"}
        ],
    }
    if not is_new:
        frame["actions"].extend(
            [
                {"id": "duplicate-entry", "title": "Duplicate Entry", "icon": "copy"},
                {
                    "id": "delete-entry",
                    "title": "Delete Entry",
                    "icon": "delete",
                    "destructive": True,
                    "confirm": {
                        "title": "Delete this glossary entry?",
                        "message": "The saved prompt cannot be recovered from the plugin.",
                        "confirmLabel": "Delete",
                    },
                },
            ]
        )
    send(frame)


def default_agent_draft(agent_id: str) -> Dict[str, Any]:
    agent = find_agent(agent_id)
    if agent:
        return {
            "agent-name": as_string(agent.get("name")),
            "agent-binary": tokens_for_display(agent.get("binary", [])),
            "agent-file-flag": tokens_for_display(agent.get("file_flag", [])),
            "agent-output-flag": tokens_for_display(agent.get("output_flag", [])),
            "agent-trailing-flags": tokens_for_display(agent.get("trailing_flags", [])),
            "agent-output-filename": safe_output_filename(agent.get("output_filename")),
            "form_error": "",
        }
    return {
        "agent-name": "",
        "agent-binary": "",
        "agent-file-flag": "",
        "agent-output-flag": "-o\n{output}",
        "agent-trailing-flags": "",
        "agent-output-filename": "result.md",
        "form_error": "",
    }


def get_agent_draft(agent_id: str) -> Dict[str, Any]:
    with STATE_LOCK:
        drafts = STATE.setdefault("agent_drafts", {})
        if agent_id not in drafts:
            drafts[agent_id] = default_agent_draft(agent_id)
        return drafts[agent_id]


def render_agent_form(
    agent_id: str,
    rev: int,
    page_history: str = "none",
    field_errors: Optional[Dict[str, str]] = None,
    form_error: str = "",
) -> None:
    draft = get_agent_draft(agent_id)
    agent = find_agent(agent_id)
    is_new = agent_id == "new" or agent is None
    field_errors = field_errors or {}
    form_error = form_error or as_string(draft.get("form_error"))
    fields: List[Dict[str, Any]] = [
        {
            "id": "agent-name",
            "type": "text",
            "label": "Agent name",
            "value": as_string(draft.get("agent-name")),
            "placeholder": "Claude Code",
            "required": True,
            "section": "agent-definition",
        },
        {
            "id": "agent-binary",
            "type": "textarea",
            "label": "Binary tokens",
            "value": as_string(draft.get("agent-binary")),
            "placeholder": "claude\n-c",
            "required": True,
            "description": "One argv token per line. The process is never run through a shell.",
            "section": "agent-definition",
        },
        {
            "id": "agent-file-flag",
            "type": "textarea",
            "label": "File flag tokens",
            "value": as_string(draft.get("agent-file-flag")),
            "placeholder": "-i\n{file}",
            "description": "Inserted only for entries that need a file.",
            "section": "agent-definition",
        },
        {
            "id": "agent-output-flag",
            "type": "textarea",
            "label": "Output flag tokens",
            "value": as_string(draft.get("agent-output-flag")),
            "placeholder": "-o\n{output}",
            "required": True,
            "description": "Use {output}; it resolves to this run's scratch output path.",
            "section": "agent-definition",
        },
        {
            "id": "agent-trailing-flags",
            "type": "textarea",
            "label": "Trailing flag tokens",
            "value": as_string(draft.get("agent-trailing-flags")),
            "placeholder": "--skip-git-repo-check",
            "description": "Optional tokens appended after the prompt argument.",
            "section": "agent-definition",
        },
        {
            "id": "agent-output-filename",
            "type": "text",
            "label": "Output filename",
            "value": as_string(draft.get("agent-output-filename"), "result.md"),
            "required": True,
            "description": "Kept inside the per-run scratch folder; the default is result.md.",
            "section": "agent-definition",
        },
    ]
    for field in fields:
        if field["id"] in field_errors:
            field["error"] = field_errors[field["id"]]

    form: Dict[str, Any] = {
        "title": "New Agent" if is_new else "Edit Agent",
        "sections": [
            {
                "id": "agent-definition",
                "title": "Command definition",
                "description": "All values become argv tokens; placeholders are expanded without shell parsing.",
            }
        ],
        "submitLabel": "Create Agent" if is_new else "Save Agent",
        "fields": fields,
    }
    if form_error:
        form["error"] = form_error

    frame: Dict[str, Any] = {
        "type": "render",
        "rev": rev,
        "view": "form",
        "page": page_payload(
            f"glossary:agent:{agent_id}",
            "New Agent" if is_new else f"Edit: {agent.get('name')}",
            page_history,
            preserve_state=not is_new,
        ),
        "elementId": "glossary-agent-form",
        "placeholder": "Editing agent preset…",
        "form": form,
        "actions": [{"id": "back-agents", "title": "Back to Agents", "icon": "list"}],
    }
    if not is_new and agent_id != BUILTIN_AGENT_ID:
        frame["actions"].append(
            {
                "id": "delete-agent",
                "title": "Delete Agent",
                "icon": "delete",
                "destructive": True,
                "confirm": {
                    "title": "Delete this agent preset?",
                    "message": "Entries using it will no longer be runnable until reassigned.",
                    "confirmLabel": "Delete",
                },
            }
        )
    send(frame)


# ---------------------------------------------------------------------------
# Run form and clipboard support
# ---------------------------------------------------------------------------


def new_run_draft(entry_id: str, carry: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    entry = find_entry(entry_id)
    carry = carry or {}
    values: Dict[str, Any] = {}
    for name in entry_variables(entry or {"prompt": "", "needs_file": False}):
        values[name] = as_string(carry.get(name))
    return {
        "entry_id": entry_id,
        "values": values,
        "run_dir": str(new_run_directory()),
        "form_error": "",
        "field_errors": {},
        "banner": "",
    }


def get_run_draft(entry_id: str) -> Dict[str, Any]:
    with STATE_LOCK:
        drafts = STATE.setdefault("run_drafts", {})
        if entry_id not in drafts:
            drafts[entry_id] = new_run_draft(entry_id)
        return drafts[entry_id]


def reset_run_draft(entry_id: str, carry: Optional[Dict[str, Any]] = None) -> None:
    with STATE_LOCK:
        STATE.setdefault("run_drafts", {})[entry_id] = new_run_draft(entry_id, carry)


def read_clipboard_text() -> Tuple[Optional[str], Optional[str]]:
    try:
        import win32clipboard  # type: ignore
        import win32con  # type: ignore
    except ImportError as exc:
        return None, f"The clipboard text dependency is unavailable: {exc}"

    opened = False
    try:
        win32clipboard.OpenClipboard()
        opened = True
        if win32clipboard.IsClipboardFormatAvailable(win32con.CF_UNICODETEXT):
            value = win32clipboard.GetClipboardData(win32con.CF_UNICODETEXT)
            return as_string(value), None
        if win32clipboard.IsClipboardFormatAvailable(win32con.CF_TEXT):
            value = win32clipboard.GetClipboardData(win32con.CF_TEXT)
            if isinstance(value, bytes):
                return value.decode("utf-8", errors="replace"), None
            return as_string(value), None
        return None, None
    except Exception as exc:
        return None, f"Could not read text from the clipboard: {exc}"
    finally:
        if opened:
            try:
                win32clipboard.CloseClipboard()
            except Exception:
                pass


def paste_clipboard_to_run(entry_id: str) -> Tuple[Optional[str], str]:
    draft = get_run_draft(entry_id)
    run_dir = Path(as_string(draft.get("run_dir")))
    run_dir.mkdir(parents=True, exist_ok=True)

    # Image first: ImageGrab handles copied screenshots and other Windows
    # bitmap clipboard formats.  A returned list means copied files, not an
    # image, so it intentionally falls through to the text check.
    try:
        from PIL import ImageGrab  # type: ignore

        image = ImageGrab.grabclipboard()
        if image is not None and hasattr(image, "save"):
            path = run_dir / f"clipboard-image-{uuid.uuid4().hex[:8]}.png"
            image.save(str(path), "PNG")
            return str(path), "Clipboard image saved as a PNG file."
    except Exception as exc:
        log("clipboard image read failed:", exc)

    text, text_error = read_clipboard_text()
    if text is not None and text.strip():
        path = run_dir / f"clipboard-text-{uuid.uuid4().hex[:8]}.txt"
        path.write_text(text, encoding="utf-8", newline="\n")
        return str(path), "Clipboard text saved as a UTF-8 text file."
    if text_error:
        return None, text_error
    return None, "Clipboard is empty or unsupported. Copy an image or plain text and try again."


def render_run_form(
    entry_id: str,
    rev: int,
    page_history: str = "none",
    field_errors: Optional[Dict[str, str]] = None,
    form_error: str = "",
) -> None:
    entry = find_entry(entry_id)
    if not entry:
        render_plugin_error(rev, "Entry not found", f"No glossary entry exists for `{entry_id}`.")
        return
    draft = get_run_draft(entry_id)
    field_errors = field_errors or draft.get("field_errors") or {}
    form_error = form_error or as_string(draft.get("form_error"))
    variables = entry_variables(entry)
    fields: List[Dict[str, Any]] = []
    for name in variables:
        field_id = field_id_for_variable(name)
        if name == "file":
            field: Dict[str, Any] = {
                "id": field_id,
                "type": "filepicker",
                "label": "File input",
                "value": as_string(draft.get("values", {}).get(name)),
                "required": True,
                "description": "Browse for a file, or use the Paste from clipboard action above.",
                "section": "run-variables",
            }
        else:
            field = {
                "id": field_id,
                "type": "textarea",
                "label": variable_label(name),
                "placeholder": f"Value for {{{name}}}…",
                "value": as_string(draft.get("values", {}).get(name)),
                "required": True,
                "description": f"Substituted directly into the prompt as {{{name}}}.",
                "section": "run-variables",
            }
        if field_id in field_errors:
            field["error"] = field_errors[field_id]
        fields.append(field)

    variable_description = (
        "Fill each required value before starting the agent."
        if variables
        else "This prompt has no variables; submit it to run as-is."
    )
    form: Dict[str, Any] = {
        "title": f"Run: {entry.get('name')}",
        "sections": [
            {
                "id": "run-variables",
                "title": "Prompt variables",
                "description": variable_description,
            }
        ],
        "submitLabel": "Run",
        "fields": fields,
    }
    if form_error:
        form["error"] = form_error

    frame: Dict[str, Any] = {
        "type": "render",
        "rev": rev,
        "view": "form",
        "page": page_payload(
            f"glossary:run:{entry_id}",
            f"Run: {entry.get('name')}",
            page_history,
            preserve_state=True,
        ),
        "elementId": "glossary-run-form",
        "placeholder": "Fill variables, then run…",
        "form": form,
        "actions": [
            {"id": "back-entry", "title": "Back to Entry", "icon": "edit"}
        ],
    }
    if entry_needs_file(entry):
        frame["actions"].insert(
            0,
            {"id": "paste-file", "title": "Use from clipboard", "icon": "paste"},
        )
        frame["floatingAction"] = {
            "id": "paste-file",
            "title": "Use from clipboard",
            "icon": "paste",
        }
    banner = as_string(draft.get("banner"))
    if banner:
        frame["banners"] = [
            {
                "id": "glossary-clipboard-status",
                "style": "success" if "saved" in banner.lower() else "error",
                "title": "Clipboard file",
                "message": banner,
                "icon": "clipboard",
            }
        ]
    send(frame)


# ---------------------------------------------------------------------------
# Process execution and result pages
# ---------------------------------------------------------------------------


def append_run_log(context: Dict[str, Any], source: str, text: str, level: str = "info") -> None:
    clean = as_string(text).rstrip("\r\n")
    if not clean:
        return
    with context["lock"]:
        context["logs"].append(
            {
                "id": f"{source}-{uuid.uuid4().hex}",
                "source": source,
                "level": level,
                "text": clean,
            }
        )
        if source == "stderr":
            context["stderr_tail"].append(clean)
            context["stderr_tail"] = context["stderr_tail"][-80:]
        context["logs"] = context["logs"][-120:]


def read_process_stream(stream: Any, source: str, context: Dict[str, Any]) -> None:
    try:
        for line in iter(stream.readline, ""):
            append_run_log(context, source, line, "error" if source == "stderr" else "info")
    except Exception as exc:
        append_run_log(context, "plugin", f"Could not read {source}: {exc}", "error")
    finally:
        try:
            stream.close()
        except Exception:
            pass


def running_tail(context: Dict[str, Any], limit: int = 18) -> str:
    with context["lock"]:
        lines = list(context.get("logs", []))[-limit:]
    if not lines:
        return "(waiting for stdout/stderr…)"
    return "\n".join(
        f"[{as_string(line.get('source')).upper()}] {as_string(line.get('text'))}"
        for line in lines
    )


def operation_detail(context: Dict[str, Any]) -> str:
    status = as_string(context.get("status"), "running")
    command_text = display_command(context.get("command", [])) or "(not available)"
    detail = (
        f"Command: {command_text}\n\n"
        f"Scratch folder:\n{context.get('run_dir')}\n\n"
        f"Live stdout/stderr tail ({status}):\n{running_tail(context)}"
    )
    return detail


def render_running(context: Dict[str, Any], page_history: str = "none") -> None:
    entry_name = as_string(context.get("entry", {}).get("name"), "agent run")
    active = (
        RUNTIME.get("active_run") is context
        and not context.get("finished")
        and not context["cancel_event"].is_set()
    )
    operation: Dict[str, Any] = {
        "id": as_string(context.get("id")),
        "title": f"Running {entry_name}",
        "detail": operation_detail(context),
        "cancellable": bool(active),
    }
    frame: Dict[str, Any] = {
        "type": "render",
        "rev": 0,
        "view": "operation",
        "page": page_payload(
            "glossary:running",
            "Running",
            page_history,
            preserve_state=True,
        ),
        "elementId": "glossary-running-operation",
        "operation": operation,
    }
    if not active:
        frame["actions"] = [
            {"id": "view-result", "title": "View result", "icon": "open"},
            {"id": "back-list", "title": "Back to list", "icon": "list"},
        ]
    send(frame)


def build_agent_command(
    entry: Dict[str, Any],
    agent: Dict[str, Any],
    values: Dict[str, Any],
    output_path: Path,
) -> List[str]:
    substitutions: Dict[str, Any] = dict(values)
    substitutions["output"] = str(output_path)
    argv: List[str] = []
    argv.extend(
        substitute_placeholders(as_string(token), substitutions)
        for token in agent.get("binary", [])
    )
    if entry_needs_file(entry):
        argv.extend(
            substitute_placeholders(as_string(token), substitutions)
            for token in agent.get("file_flag", [])
        )
    argv.extend(
        substitute_placeholders(as_string(token), substitutions)
        for token in agent.get("output_flag", [])
    )
    argv.append(substitute_placeholders(as_string(entry.get("prompt")), substitutions))
    argv.extend(
        substitute_placeholders(as_string(token), substitutions)
        for token in agent.get("trailing_flags", [])
    )
    return argv


def terminate_process(context: Dict[str, Any]) -> None:
    process = context.get("process")
    if process is None:
        return
    try:
        if process.poll() is None:
            process.terminate()
    except Exception as exc:
        append_run_log(context, "plugin", f"Could not terminate agent: {exc}", "error")


def wait_for_output(path: Path) -> bool:
    deadline = time.monotonic() + OUTPUT_WAIT_SECONDS
    while time.monotonic() < deadline:
        if path.exists():
            return True
        time.sleep(0.1)
    return path.exists()


def finish_context(
    context: Dict[str, Any],
    status: str,
    returncode: Optional[int] = None,
    content: Optional[str] = None,
    error: str = "",
) -> None:
    with context["lock"]:
        context["status"] = status
        context["returncode"] = returncode
        context["content"] = content
        context["error"] = error
        context["finished"] = True

    with STATE_LOCK:
        if RUNTIME.get("active_run") is context:
            RUNTIME["active_run"] = None
        RUNTIME["last_result"] = context
        current_page = as_string(STATE.get("page_id"))

    if CLOSING.is_set():
        return
    if current_page == "glossary:running":
        with STATE_LOCK:
            stack = STATE.setdefault("route_stack", ["glossary:home"])
            if stack and stack[-1] == "glossary:running":
                stack.append("glossary:result")
            STATE["page_id"] = "glossary:result"
        command("setQuery", text="")
        render_result(0, "push")
    else:
        style = "success" if status == "success" else "error"
        command(
            "toast",
            text=(
                "Agent run finished successfully."
                if status == "success"
                else f"Agent run ended: {status.replace('_', ' ')}."
            ),
            style=style,
        )


def run_worker(context: Dict[str, Any]) -> None:
    process: Optional[subprocess.Popen[str]] = None
    stdout_thread: Optional[threading.Thread] = None
    stderr_thread: Optional[threading.Thread] = None
    timed_out = False
    cancelled = False
    try:
        append_run_log(context, "plugin", "Starting agent process…")
        try:
            process = subprocess.Popen(
                context["command"],
                cwd=str(context["run_dir"]),
                # Keep the agent isolated from Tabame's newline-delimited
                # plugin protocol. Otherwise the child can consume stdin
                # events intended for this process.
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
                bufsize=1,
            )
            context["process"] = process
        except FileNotFoundError as exc:
            binary = as_string(context["command"][0] if context["command"] else "agent")
            finish_context(
                context,
                "binary_not_found",
                error=(
                    f"The agent binary `{binary}` was not found on PATH. "
                    "Install it or edit this agent preset.\n\n"
                    f"OS error: {exc}"
                ),
            )
            return
        except Exception as exc:
            finish_context(
                context,
                "process_start_failed",
                error=f"The agent process could not be started: {exc}",
            )
            return

        stdout_thread = threading.Thread(
            target=read_process_stream,
            args=(process.stdout, "stdout", context),
            name="cli-glossary-stdout",
            daemon=True,
        )
        stderr_thread = threading.Thread(
            target=read_process_stream,
            args=(process.stderr, "stderr", context),
            name="cli-glossary-stderr",
            daemon=True,
        )
        stdout_thread.start()
        stderr_thread.start()

        started = time.monotonic()
        while process.poll() is None:
            if context["cancel_event"].is_set():
                cancelled = True
                append_run_log(context, "plugin", "Cancellation requested; terminating agent…", "warn")
                terminate_process(context)
                break
            if time.monotonic() - started >= RUN_TIMEOUT_SECONDS:
                timed_out = True
                append_run_log(
                    context,
                    "plugin",
                    f"Timed out after {RUN_TIMEOUT_SECONDS} seconds; terminating agent…",
                    "error",
                )
                terminate_process(context)
                break
            if not CLOSING.is_set():
                render_running(context)
            time.sleep(0.35)

        try:
            returncode = process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            terminate_process(context)
            returncode = process.wait(timeout=5)

        if stdout_thread:
            stdout_thread.join(timeout=2)
        if stderr_thread:
            stderr_thread.join(timeout=2)

        if timed_out:
            finish_context(
                context,
                "timeout",
                returncode=returncode,
                error=f"The agent did not finish within {RUN_TIMEOUT_SECONDS} seconds.",
            )
            return
        if cancelled or context["cancel_event"].is_set():
            finish_context(context, "cancelled", returncode=returncode, error="The run was cancelled.")
            return
        if returncode != 0:
            finish_context(
                context,
                "process_failed",
                returncode=returncode,
                error=f"The agent exited with non-zero code {returncode}.",
            )
            return

        output_path = Path(context["output_path"])
        if not wait_for_output(output_path):
            finish_context(
                context,
                "result_missing",
                returncode=returncode,
                error=(
                    f"{output_path.name} did not appear after the agent exited "
                    f"(waited {OUTPUT_WAIT_SECONDS} seconds)."
                ),
            )
            return
        try:
            result = output_path.read_text(encoding="utf-8", errors="replace")
        except Exception as exc:
            finish_context(
                context,
                "result_read_failed",
                returncode=returncode,
                error=f"Could not read {output_path.name}: {exc}",
            )
            return
        if not result.strip():
            finish_context(
                context,
                "result_empty",
                returncode=returncode,
                content=result,
                error=f"{output_path.name} was created but contains no text.",
            )
            return
        finish_context(context, "success", returncode=returncode, content=result)
    except Exception as exc:
        log("run worker failed:", exc)
        finish_context(context, "internal_error", error=f"Unexpected run error: {exc}")


def result_status_info(status: str) -> Tuple[str, str]:
    return {
        "success": ("Success", "#22C55E"),
        "binary_not_found": ("Binary not found", "#EF4444"),
        "process_start_failed": ("Could not start", "#EF4444"),
        "process_failed": ("Process failed", "#EF4444"),
        "timeout": ("Timed out", "#F97316"),
        "cancelled": ("Cancelled", "#F59E0B"),
        "result_missing": ("Result missing", "#EF4444"),
        "result_empty": ("Result empty", "#F97316"),
        "result_read_failed": ("Read failed", "#EF4444"),
        "internal_error": ("Plugin error", "#EF4444"),
    }.get(status, (status.replace("_", " ").title(), "#EF4444"))


def result_error_details(context: Dict[str, Any]) -> str:
    with context["lock"]:
        stderr = "\n".join(context.get("stderr_tail", []))
        logs = running_tail(context, limit=24)
        status = as_string(context.get("status"))
        return stderr or logs if status != "binary_not_found" else as_string(context.get("error"))


def result_markdown(context: Dict[str, Any]) -> str:
    status = as_string(context.get("status"))
    if status == "success":
        return as_string(context.get("content"))
    title, _ = result_status_info(status)
    message = as_string(context.get("error")) or "The run did not produce a usable result."
    details = result_error_details(context)
    if details == message:
        details = ""
    return error_markdown(f"Agent run: {title}", message, details)


def result_copy_text(context: Dict[str, Any]) -> str:
    if as_string(context.get("status")) == "success":
        return as_string(context.get("content"))
    return result_markdown(context)


def result_actions(context: Dict[str, Any]) -> List[Dict[str, Any]]:
    output_path = Path(context.get("output_path")) if context.get("output_path") else None
    actions: List[Dict[str, Any]] = [
        {"id": "copy-result", "title": "Copy", "icon": "copy"},
    ]
    if output_path and output_path.exists():
        actions.extend(
            [
                {"id": "save-as", "title": "Save As", "icon": "download"},
                {"id": "open-result", "title": "Open result.md", "icon": "open"},
            ]
        )
    entry_id = as_string(context.get("entry_id"))
    if find_entry(entry_id):
        actions.append({"id": "run-again", "title": "Run again", "icon": "run"})
        actions.append({"id": "back-entry", "title": "Back to entry", "icon": "edit"})
    actions.append({"id": "back-list", "title": "Back to list", "icon": "list"})
    return actions


def render_result(rev: int, page_history: str = "none") -> None:
    context = RUNTIME.get("last_result")
    if not context:
        render_plugin_error(rev, "No result", "There is no completed agent run to display.")
        return
    status = as_string(context.get("status"), "internal_error")
    status_label, status_color = result_status_info(status)
    output_path = Path(context["output_path"]) if context.get("output_path") else None
    metadata: List[Dict[str, Any]] = [
        {"label": "Status", "text": status_label, "color": status_color},
        {"label": "Agent", "text": as_string(context.get("agent", {}).get("name"))},
    ]
    if output_path:
        metadata.append({"label": "Output", "text": str(output_path), "icon": "file"})
    if context.get("returncode") is not None:
        metadata.append({"label": "Exit code", "text": str(context.get("returncode"))})
    detail = {
        "markdown": result_markdown(context),
        "wide": True,
        "metadata": metadata,
    }
    actions = result_actions(context)
    frame: Dict[str, Any] = {
        "type": "render",
        "rev": rev,
        "view": "detail",
        "page": page_payload(
            "glossary:result",
            "Result",
            page_history,
            preserve_state=True,
        ),
        "elementId": "glossary-result-detail",
        "detail": detail,
        "actions": actions,
    }
    frame["floatingAction"] = [
        {"id": "copy-result", "title": "Copy", "icon": "copy"},
        {"id": "run-again", "title": "Run again", "icon": "run"},
    ]
    send(frame)


# ---------------------------------------------------------------------------
# Save As utility page
# ---------------------------------------------------------------------------


def render_save_as(
    rev: int,
    page_history: str = "none",
    field_errors: Optional[Dict[str, str]] = None,
    form_error: str = "",
) -> None:
    context = RUNTIME.get("save_context")
    if not context:
        render_plugin_error(rev, "Save unavailable", "There is no result file to save.")
        return
    field_errors = field_errors or {}
    draft = STATE.get("save_draft") or {
        "save-folder": default_save_folder(),
        "save-filename": safe_output_filename(context.get("output_path", "result.md")),
        "form_error": "",
    }
    form_error = form_error or as_string(draft.get("form_error"))
    fields: List[Dict[str, Any]] = [
        {
            "id": "save-folder",
            "type": "folderpicker",
            "label": "Destination folder",
            "value": as_string(draft.get("save-folder")),
            "required": True,
            "section": "save-destination",
        },
        {
            "id": "save-filename",
            "type": "text",
            "label": "Filename",
            "value": as_string(draft.get("save-filename"), "result.md"),
            "required": True,
            "description": "Use a filename only, not a folder path.",
            "section": "save-destination",
        },
    ]
    for field in fields:
        if field["id"] in field_errors:
            field["error"] = field_errors[field["id"]]
    form: Dict[str, Any] = {
        "title": "Save result as",
        "sections": [
            {
                "id": "save-destination",
                "title": "Destination",
                "description": "The original result remains in its run scratch folder.",
            }
        ],
        "submitLabel": "Save",
        "fields": fields,
    }
    if form_error:
        form["error"] = form_error
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "page": page_payload(
                "glossary:save",
                "Save result as",
                page_history,
                preserve_state=True,
            ),
            "elementId": "glossary-save-form",
            "placeholder": "Choose a destination…",
            "form": form,
            "actions": [{"id": "cancel-save", "title": "Cancel", "icon": "close"}],
        }
    )


# ---------------------------------------------------------------------------
# Error page and routing dispatch
# ---------------------------------------------------------------------------


def render_plugin_error(rev: int, title: str, message: str) -> None:
    with STATE_LOCK:
        STATE["page_id"] = "glossary:error"
        stack = STATE.setdefault("route_stack", ["glossary:home"])
        if stack:
            stack[-1] = "glossary:error"
        else:
            stack.append("glossary:error")
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "page": page_payload("glossary:error", title, "replace", True),
            "elementId": "glossary-error-detail",
            "detail": {"markdown": error_markdown(title, message)},
            "actions": [{"id": "back-list", "title": "Back to list", "icon": "list"}],
        }
    )


def render_page(rev: int = 0, page_history: str = "none") -> None:
    try:
        page_id = as_string(STATE.get("page_id"), "glossary:home")
        if page_id == "glossary:home":
            render_home(rev, page_history)
        elif page_id == "glossary:agents":
            render_agents(rev, page_history)
        elif page_id.startswith("glossary:edit:"):
            render_entry_form(page_id.split(":", 2)[2], rev, page_history)
        elif page_id.startswith("glossary:agent:"):
            render_agent_form(page_id.split(":", 2)[2], rev, page_history)
        elif page_id.startswith("glossary:run:"):
            render_run_form(page_id.split(":", 2)[2], rev, page_history)
        elif page_id == "glossary:running":
            context = RUNTIME.get("active_run") or RUNTIME.get("last_result")
            if context:
                render_running(context, page_history)
            else:
                render_plugin_error(rev, "No active run", "There is no agent run in progress.")
        elif page_id == "glossary:result":
            render_result(rev, page_history)
        elif page_id == "glossary:save":
            render_save_as(rev, page_history)
        elif page_id == "glossary:error":
            render_plugin_error(rev, "Glossary error", "The current page could not be restored.")
        else:
            navigate_existing("glossary:home")
    except Exception as exc:
        log("render failed:", exc)
        render_plugin_error(rev, "Glossary error", str(exc))


# ---------------------------------------------------------------------------
# CRUD and form submit handlers
# ---------------------------------------------------------------------------


def entry_id_from_item(item_id: str) -> str:
    return item_id.split(":", 1)[1] if item_id.startswith("entry:") else item_id


def agent_id_from_item(item_id: str) -> str:
    return item_id.split(":", 1)[1] if item_id.startswith("agent:") else item_id


def update_entry_draft_from_values(entry_id: str, values: Dict[str, Any]) -> Dict[str, Any]:
    draft = get_entry_draft(entry_id)
    for key in ("entry-name", "entry-agent", "entry-needs-file", "entry-prompt"):
        if key in values:
            draft[key] = values[key]
    return draft


def submit_entry(entry_id: str, values: Dict[str, Any], rev: int) -> None:
    draft = update_entry_draft_from_values(entry_id, values)
    name = as_string(draft.get("entry-name")).strip()
    agent_id = as_string(draft.get("entry-agent")).strip()
    prompt = as_string(draft.get("entry-prompt"))
    needs_file = bool(draft.get("entry-needs-file")) or "file" in raw_variables(prompt)
    field_errors: Dict[str, str] = {}
    if not name:
        field_errors["entry-name"] = "Enter a name for this glossary entry."
    if not agent_id or not find_agent(agent_id):
        field_errors["entry-agent"] = "Choose an available agent preset."
    if not prompt.strip():
        field_errors["entry-prompt"] = "Enter the prompt text the agent should receive."
    with STATE_LOCK:
        duplicate = any(
            as_string(entry.get("name")).strip().lower() == name.lower()
            and as_string(entry.get("id")) != entry_id
            for entry in STATE.get("entries", [])
        )
    if name and duplicate:
        field_errors["entry-name"] = "Entry names must be unique."
    if field_errors:
        draft["form_error"] = "Please fix the highlighted entry fields."
        draft["entry-needs-file"] = needs_file
        render_entry_form(entry_id, rev, "replace", field_errors, draft["form_error"])
        return

    saved_id = entry_id if entry_id != "new" and find_entry(entry_id) else new_id("entry")
    saved = {
        "id": saved_id,
        "name": name,
        "agent_id": agent_id,
        "needs_file": needs_file,
        "prompt": prompt,
    }
    with STATE_LOCK:
        entries = STATE["entries"]
        for index, existing in enumerate(entries):
            if existing.get("id") == saved_id:
                entries[index] = saved
                break
        else:
            entries.append(saved)
        STATE.setdefault("entry_drafts", {}).pop(entry_id, None)
    save_entries()
    command("toast", text="Glossary entry saved.", style="success")
    navigate_to("glossary:home", "replace")


def update_agent_draft_from_values(agent_id: str, values: Dict[str, Any]) -> Dict[str, Any]:
    draft = get_agent_draft(agent_id)
    for key in (
        "agent-name",
        "agent-binary",
        "agent-file-flag",
        "agent-output-flag",
        "agent-trailing-flags",
        "agent-output-filename",
    ):
        if key in values:
            draft[key] = values[key]
    return draft


def submit_agent(agent_id: str, values: Dict[str, Any], rev: int) -> None:
    draft = update_agent_draft_from_values(agent_id, values)
    name = as_string(draft.get("agent-name")).strip()
    binary = parse_token_field(draft.get("agent-binary"))
    file_flag = parse_token_field(draft.get("agent-file-flag"))
    output_flag = parse_token_field(draft.get("agent-output-flag"))
    trailing_flags = parse_token_field(draft.get("agent-trailing-flags"))
    output_filename = safe_output_filename(draft.get("agent-output-filename"))
    field_errors: Dict[str, str] = {}
    if not name:
        field_errors["agent-name"] = "Enter a name for this agent preset."
    if not binary:
        field_errors["agent-binary"] = "Add at least one binary token."
    if not output_flag:
        field_errors["agent-output-flag"] = "Add the output flag tokens, including {output}."
    elif not any("{output}" in token for token in output_flag):
        field_errors["agent-output-flag"] = "The output flag must include the {output} placeholder."
    if not as_string(draft.get("agent-output-filename")).strip():
        field_errors["agent-output-filename"] = "Enter an output filename."
    with STATE_LOCK:
        duplicate = any(
            as_string(agent.get("name")).strip().lower() == name.lower()
            and as_string(agent.get("id")) != agent_id
            for agent in STATE.get("agents", [])
        )
    if name and duplicate:
        field_errors["agent-name"] = "Agent names must be unique."
    if field_errors:
        draft["form_error"] = "Please fix the highlighted agent fields."
        render_agent_form(agent_id, rev, "replace", field_errors, draft["form_error"])
        return

    saved_id = agent_id if agent_id != "new" and find_agent(agent_id) else new_id("agent")
    saved = {
        "id": saved_id,
        "name": name,
        "binary": binary,
        "file_flag": file_flag,
        "output_flag": output_flag,
        "trailing_flags": trailing_flags,
        "output_filename": output_filename,
    }
    with STATE_LOCK:
        agents = STATE["agents"]
        for index, existing in enumerate(agents):
            if existing.get("id") == saved_id:
                agents[index] = saved
                break
        else:
            agents.append(saved)
        STATE.setdefault("agent_drafts", {}).pop(agent_id, None)
    save_agents()
    command("toast", text="Agent preset saved.", style="success")
    navigate_to("glossary:agents", "replace")


def submit_run(entry_id: str, values: Dict[str, Any], rev: int) -> None:
    entry = find_entry(entry_id)
    if not entry:
        render_plugin_error(rev, "Entry not found", "This glossary entry was deleted.")
        return
    draft = get_run_draft(entry_id)
    variables = entry_variables(entry)
    resolved: Dict[str, Any] = {}
    field_errors: Dict[str, str] = {}
    for name in variables:
        field_id = field_id_for_variable(name)
        if name == "file":
            value = as_string(values.get(field_id)).strip()
            if not value:
                # A frame action can re-render the same form while the host
                # still reports the old empty filepicker value.  Prefer the
                # clipboard path saved by this plugin in that case.
                value = as_string(draft.get("values", {}).get(name)).strip()
            value = as_string(value).strip()
            if not value:
                field_errors[field_id] = "Choose a file or paste one from the clipboard."
            elif not Path(value).is_file():
                field_errors[field_id] = "The selected file no longer exists. Browse or paste it again."
        else:
            value = values.get(field_id, draft.get("values", {}).get(name, ""))
            value = as_string(value)
            if not value.strip():
                field_errors[field_id] = f"Enter a value for {{{name}}}."
        resolved[name] = value

    agent = find_agent(as_string(entry.get("agent_id")))
    if not agent:
        field_errors["run-agent"] = "This entry's agent preset is missing. Edit the entry first."
    elif not agent.get("binary"):
        field_errors["run-agent"] = "The selected agent has no binary tokens. Edit the agent preset."
    elif entry_needs_file(entry) and not agent.get("file_flag"):
        field_errors["run-agent"] = "This agent has no file flag configured for a file entry."
    elif entry_needs_file(entry) and not any(
        "{file}" in as_string(token) for token in agent.get("file_flag", [])
    ):
        field_errors["run-agent"] = "The file flag must include the {file} placeholder."
    if not agent or not agent.get("output_flag"):
        field_errors["run-agent"] = "This agent has no output flag configured. Edit the agent preset."
    elif not any(
        "{output}" in as_string(token) for token in agent.get("output_flag", [])
    ):
        field_errors["run-agent"] = "The output flag must include the {output} placeholder."

    with STATE_LOCK:
        draft["values"] = resolved
        draft["field_errors"] = field_errors
    if field_errors:
        draft["form_error"] = field_errors.get(
            "run-agent",
            "Please fix the highlighted run fields before submitting.",
        )
        render_run_form(entry_id, rev, "replace", field_errors, draft["form_error"])
        return

    draft["form_error"] = ""
    draft["banner"] = ""
    run_dir = Path(as_string(draft.get("run_dir")))
    run_dir.mkdir(parents=True, exist_ok=True)
    output_filename = safe_output_filename(agent.get("output_filename"))
    output_path = run_dir / output_filename
    try:
        argv = build_agent_command(entry, agent, resolved, output_path)
    except Exception as exc:
        draft["form_error"] = f"Could not construct the agent command: {exc}"
        render_run_form(entry_id, rev, "replace", {}, draft["form_error"])
        return
    if not argv or not argv[0].strip():
        draft["form_error"] = "The agent preset has no executable binary token."
        render_run_form(entry_id, rev, "replace", {}, draft["form_error"])
        return

    context: Dict[str, Any] = {
        "id": new_id("run"),
        "entry_id": entry_id,
        "entry": copy.deepcopy(entry),
        "agent": copy.deepcopy(agent),
        "values": copy.deepcopy(resolved),
        "command": argv,
        "run_dir": str(run_dir),
        "output_path": str(output_path),
        "status": "running",
        "returncode": None,
        "content": None,
        "error": "",
        "logs": [],
        "stderr_tail": [],
        "process": None,
        "finished": False,
        "cancel_event": threading.Event(),
        "lock": threading.RLock(),
    }
    with STATE_LOCK:
        RUNTIME["active_run"] = context
        STATE.setdefault("run_drafts", {}).pop(entry_id, None)
    navigate_to("glossary:running", "push")
    worker = threading.Thread(target=run_worker, args=(context,), name="cli-glossary-run", daemon=True)
    context["worker"] = worker
    worker.start()


def submit_save(values: Dict[str, Any], rev: int) -> None:
    context = RUNTIME.get("save_context")
    if not context:
        render_plugin_error(rev, "Save unavailable", "There is no result file to save.")
        return
    draft = STATE.get("save_draft") or {}
    folder = as_string(values.get("save-folder", draft.get("save-folder"))).strip()
    filename = as_string(values.get("save-filename", draft.get("save-filename"))).strip()
    draft.update({"save-folder": folder, "save-filename": filename})
    STATE["save_draft"] = draft
    field_errors: Dict[str, str] = {}
    if not folder or not Path(folder).is_dir():
        field_errors["save-folder"] = "Choose an existing destination folder."
    if not filename:
        field_errors["save-filename"] = "Enter a filename."
    elif "/" in filename or "\\" in filename or filename in (".", ".."):
        field_errors["save-filename"] = "Enter a filename only, without folder separators."
    source = Path(context.get("output_path"))
    if not source.is_file():
        field_errors["save-filename"] = "The original result file is no longer available."
    if field_errors:
        draft["form_error"] = "Please choose a valid destination."
        render_save_as(rev, "replace", field_errors, draft["form_error"])
        return
    destination = Path(folder) / filename
    try:
        if destination.resolve() != source.resolve():
            shutil.copyfile(str(source), str(destination))
        command("toast", text=f"Saved result to {destination}", style="success")
        navigate_to("glossary:result", "replace")
    except Exception as exc:
        draft["form_error"] = f"Could not save the result: {exc}"
        render_save_as(rev, "replace", {}, draft["form_error"])


# ---------------------------------------------------------------------------
# Actions, navigation, and event loop
# ---------------------------------------------------------------------------


def duplicate_entry(entry_id: str) -> None:
    entry = find_entry(entry_id)
    if not entry:
        return
    duplicate = copy.deepcopy(entry)
    duplicate["id"] = new_id("entry")
    duplicate["name"] = as_string(entry.get("name")) + " copy"
    with STATE_LOCK:
        STATE["entries"].append(duplicate)
    save_entries()
    command("toast", text="Entry duplicated.", style="success")
    navigate_to(f"glossary:edit:{duplicate['id']}", "push")


def delete_entry(entry_id: str) -> None:
    with STATE_LOCK:
        before = len(STATE["entries"])
        STATE["entries"] = [entry for entry in STATE["entries"] if entry.get("id") != entry_id]
        deleted = len(STATE["entries"]) != before
        STATE.setdefault("entry_drafts", {}).pop(entry_id, None)
    if not deleted:
        return
    save_entries()
    command("toast", text="Glossary entry deleted.", style="success")
    navigate_to("glossary:home", "replace")


def duplicate_agent(agent_id: str) -> None:
    agent = find_agent(agent_id)
    if not agent:
        return
    duplicate = copy.deepcopy(agent)
    duplicate["id"] = new_id("agent")
    duplicate["name"] = as_string(agent.get("name")) + " copy"
    with STATE_LOCK:
        STATE["agents"].append(duplicate)
    save_agents()
    command("toast", text="Agent preset duplicated.", style="success")
    navigate_to(f"glossary:agent:{duplicate['id']}", "push")


def delete_agent(agent_id: str) -> None:
    if agent_id == BUILTIN_AGENT_ID:
        command("toast", text="The built-in Codex preset cannot be deleted.", style="info")
        return
    with STATE_LOCK:
        if any(as_string(entry.get("agent_id")) == agent_id for entry in STATE["entries"]):
            in_use = True
        else:
            in_use = False
        if in_use:
            render_plugin_error(
                0,
                "Agent preset is in use",
                "Reassign the glossary entries using this preset before deleting it.",
            )
            return
        before = len(STATE["agents"])
        STATE["agents"] = [agent for agent in STATE["agents"] if agent.get("id") != agent_id]
        deleted = len(STATE["agents"]) != before
    if not deleted:
        return
    save_agents()
    command("toast", text="Agent preset deleted.", style="success")
    navigate_to("glossary:agents", "replace")


def handle_home_action(item_id: str, action: str) -> None:
    if not item_id:
        if action == "new-entry":
            STATE["entry_drafts"]["new"] = default_entry_draft("new")
            navigate_to("glossary:edit:new", "push")
        elif action == "manage-agents":
            navigate_to("glossary:agents", "push")
        elif action == "clear-filter":
            STATE["home_query"] = ""
            command("setQuery", text="")
            render_home(0, "none")
        return
    entry_id = entry_id_from_item(item_id)
    if not find_entry(entry_id):
        render_plugin_error(0, "Entry not found", "This glossary entry was deleted.")
        return
    if action in ("default", "run"):
        get_run_draft(entry_id)
        navigate_to(f"glossary:run:{entry_id}", "push")
    elif action == "edit":
        navigate_to(f"glossary:edit:{entry_id}", "push")
    elif action == "duplicate":
        duplicate_entry(entry_id)
    elif action == "delete":
        delete_entry(entry_id)


def handle_agents_action(item_id: str, action: str) -> None:
    if not item_id:
        if action == "new-agent":
            STATE["agent_drafts"]["new"] = default_agent_draft("new")
            navigate_to("glossary:agent:new", "push")
        return
    agent_id = agent_id_from_item(item_id)
    if not find_agent(agent_id):
        render_plugin_error(0, "Agent not found", "This agent preset was deleted.")
        return
    if action in ("default", "edit"):
        navigate_to(f"glossary:agent:{agent_id}", "push")
    elif action == "duplicate":
        duplicate_agent(agent_id)
    elif action == "delete":
        delete_agent(agent_id)


def handle_entry_form_action(entry_id: str, action: str) -> None:
    if action == "manage-agents":
        navigate_to("glossary:agents", "push")
    elif action in ("delete-entry", "delete") and entry_id != "new":
        delete_entry(entry_id)
    elif action == "duplicate-entry" and entry_id != "new":
        duplicate_entry(entry_id)


def handle_agent_form_action(agent_id: str, action: str) -> None:
    if action == "back-agents":
        navigate_to("glossary:agents", "replace")
    elif action in ("delete-agent", "delete") and agent_id != "new":
        delete_agent(agent_id)


def handle_run_action(
    entry_id: str,
    action: str,
    values: Optional[Dict[str, Any]] = None,
) -> None:
    if action == "paste-file":
        draft = get_run_draft(entry_id)
        entry = find_entry(entry_id)
        if entry and isinstance(values, dict):
            for name in entry_variables(entry):
                field_id = field_id_for_variable(name)
                if field_id in values and name != "file":
                    draft.setdefault("values", {})[name] = as_string(values[field_id])
        path, message = paste_clipboard_to_run(entry_id)
        if path:
            draft.setdefault("values", {})["file"] = path
            draft["banner"] = f"{message} Using: {path}"
            draft["form_error"] = ""
            draft["field_errors"] = {}
        else:
            draft["banner"] = ""
            draft["form_error"] = message
        render_run_form(entry_id, 0, "none")
    elif action == "back-entry":
        navigate_to(f"glossary:edit:{entry_id}", "replace")


def handle_running_action(action: str) -> None:
    if action == "view-result" and RUNTIME.get("last_result"):
        navigate_to("glossary:result", "replace")
    elif action == "back-list":
        navigate_existing("glossary:home")


def handle_result_action(action: str) -> None:
    context = RUNTIME.get("last_result")
    if not context:
        return
    if action == "copy-result":
        command("copy", text=result_copy_text(context))
    elif action == "save-as":
        if not Path(context.get("output_path")).is_file():
            render_plugin_error(0, "Save unavailable", "The result file is no longer available.")
            return
        RUNTIME["save_context"] = context
        STATE["save_draft"] = {
            "save-folder": default_save_folder(),
            "save-filename": safe_output_filename(context.get("output_path")),
            "form_error": "",
        }
        navigate_to("glossary:save", "push")
    elif action == "open-result":
        path = Path(context.get("output_path"))
        if path.is_file():
            command("open", path=str(path))
    elif action == "run-again":
        entry_id = as_string(context.get("entry_id"))
        if find_entry(entry_id):
            reset_run_draft(entry_id, context.get("values", {}))
            navigate_to(f"glossary:run:{entry_id}", "push")
    elif action == "back-entry":
        entry_id = as_string(context.get("entry_id"))
        if find_entry(entry_id):
            navigate_existing(f"glossary:edit:{entry_id}")
        else:
            navigate_existing("glossary:home")
    elif action == "back-list":
        navigate_existing("glossary:home")


def handle_save_action(action: str) -> None:
    if action == "cancel-save":
        navigate_to("glossary:result", "replace")


def handle_action(message: Dict[str, Any]) -> None:
    item_id = as_string(message.get("id"))
    action = as_string(message.get("action"), "default")
    page_id = as_string(STATE.get("page_id"), "glossary:home")
    if page_id == "glossary:home":
        handle_home_action(item_id, action)
    elif page_id == "glossary:agents":
        handle_agents_action(item_id, action)
    elif page_id.startswith("glossary:edit:"):
        handle_entry_form_action(page_id.split(":", 2)[2], action)
    elif page_id.startswith("glossary:agent:"):
        handle_agent_form_action(page_id.split(":", 2)[2], action)
    elif page_id.startswith("glossary:run:"):
        handle_run_action(page_id.split(":", 2)[2], action)
    elif page_id == "glossary:running":
        handle_running_action(action)
    elif page_id == "glossary:result":
        handle_result_action(action)
    elif page_id == "glossary:save":
        handle_save_action(action)
    elif page_id == "glossary:error" and action == "back-list":
        navigate_existing("glossary:home")


def handle_submit(message: Dict[str, Any]) -> None:
    values = message.get("values")
    if not isinstance(values, dict):
        values = {}
    rev = message_rev(message)
    page_id = as_string(STATE.get("page_id"), "glossary:home")
    if page_id.startswith("glossary:edit:"):
        submit_entry(page_id.split(":", 2)[2], values, rev)
    elif page_id.startswith("glossary:agent:"):
        submit_agent(page_id.split(":", 2)[2], values, rev)
    elif page_id.startswith("glossary:run:"):
        entry_id = page_id.split(":", 2)[2]
        if as_string(message.get("button")) == "paste-file":
            handle_run_action(entry_id, "paste-file", values)
        else:
            submit_run(entry_id, values, rev)
    elif page_id == "glossary:save":
        submit_save(values, rev)


def handle_change(message: Dict[str, Any]) -> None:
    page_id = as_string(STATE.get("page_id"), "")
    values = message.get("values")
    if not isinstance(values, dict):
        return
    if page_id.startswith("glossary:edit:"):
        entry_id = page_id.split(":", 2)[2]
        update_entry_draft_from_values(entry_id, values)
        render_entry_form(entry_id, 0, "none")


def handle_query(message: Dict[str, Any], initial: bool = False) -> None:
    text = as_string(message.get("text", message.get("query", "")))
    rev = message_rev(message)
    page_id = as_string(STATE.get("page_id"), "glossary:home")
    if page_id == "glossary:home":
        STATE["home_query"] = text
    elif page_id == "glossary:agents":
        STATE["agents_query"] = text
    render_page(rev, "none")


def handle_back(message: Dict[str, Any]) -> None:
    target = as_string(message.get("toPageId"))
    with STATE_LOCK:
        stack = STATE.setdefault("route_stack", ["glossary:home"])
        if target and target in stack:
            index = max(index for index, value in enumerate(stack) if value == target)
            del stack[index + 1 :]
            destination = target
        elif len(stack) > 1:
            stack.pop()
            destination = stack[-1]
        else:
            return
        STATE["page_id"] = destination
    command("setQuery", text="")
    render_page(0, "none")


def handle_navigate(message: Dict[str, Any]) -> None:
    target = as_string(message.get("targetPageId"))
    if not target:
        return
    if target == "glossary:home" or target in STATE.get("route_stack", []):
        navigate_existing(target)
    elif target.startswith(
        ("glossary:edit:", "glossary:agent:", "glossary:run:")
    ) or target in {"glossary:agents", "glossary:result", "glossary:running"}:
        navigate_existing(target)


def handle_cancel(message: Dict[str, Any]) -> None:
    operation_id = as_string(message.get("id"))
    context = RUNTIME.get("active_run")
    if context and as_string(context.get("id")) == operation_id:
        context["cancel_event"].set()
        append_run_log(context, "plugin", "Cancel requested…", "warn")
        terminate_process(context)
        render_running(context)


def handle_close() -> None:
    CLOSING.set()
    context = RUNTIME.get("active_run")
    if context:
        context["cancel_event"].set()
        terminate_process(context)


def handle_message(message: Dict[str, Any]) -> bool:
    message_type = as_string(message.get("type"))
    if message_type == "close":
        handle_close()
        return False
    if message_type == "init":
        with STATE_LOCK:
            STATE["page_id"] = "glossary:home"
            STATE["route_stack"] = ["glossary:home"]
            STATE["home_query"] = as_string(message.get("query"))
        render_page(message_rev(message), "none")
    elif message_type == "query":
        handle_query(message)
    elif message_type == "action":
        handle_action(message)
    elif message_type == "submit":
        handle_submit(message)
    elif message_type == "change":
        handle_change(message)
    elif message_type == "back":
        handle_back(message)
    elif message_type == "navigate":
        handle_navigate(message)
    elif message_type == "cancel":
        handle_cancel(message)
    elif message_type in ("focus", "select", "tab"):
        # Selection is owned by Tabame; all interactive content already has
        # stable ids and does not require a preview refresh here. Focus is a
        # host lifecycle notification and needs no state change.
        return True
    else:
        render_plugin_error(0, "Unsupported event", f"The plugin received `{message_type}`.")
    return True


def main() -> None:
    cleanup_run_directories()
    load_data()
    for line in sys.stdin:
        if CLOSING.is_set():
            break
        stripped = line.strip()
        if not stripped:
            continue
        try:
            message = json.loads(stripped)
            if not isinstance(message, dict):
                raise ValueError("message must be a JSON object")
        except Exception as exc:
            log("malformed stdin message:", exc)
            render_plugin_error(0, "Malformed event", str(exc))
            continue
        try:
            if not handle_message(message):
                break
        except Exception as exc:
            log("event handler failed:", exc)
            render_plugin_error(message_rev(message), "Glossary error", str(exc))


if __name__ == "__main__":
    main()
