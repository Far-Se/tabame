#!/usr/bin/env python3
"""Bitwarden vault plugin for the Tabame launcher.

The plugin deliberately delegates vault cryptography and account management to
the official Bitwarden CLI. It keeps only the short-lived full-item data in
memory and stores the unlock session through Tabame's secret-storage command.
"""

from __future__ import annotations

import difflib
import json
import os
import subprocess
import sys
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple
from urllib.parse import urlsplit


PLUGIN_ID = "bitwarden"
DEFAULT_SERVER_URL = "https://vault.bitwarden.com"
CLI_DOCS_URL = "https://bitwarden.com/help/cli/"
HIDDEN_VALUE = "HIDDEN-VALUE"
SECRET_MASK = "••••••••"
NO_FOLDER = "__no_folder__"

ITEM_TYPE_LABELS = {
    1: "Login",
    2: "Secure Note",
    3: "Card",
    4: "Identity",
    5: "SSH Key",
}

ITEM_TYPE_ICONS = {
    1: "globe",
    2: "note",
    3: "money",
    4: "person",
    5: "key",
}

DEFAULT_GENERATOR_VALUES = {
    "type": "password",
    "length": 20,
    "uppercase": True,
    "lowercase": True,
    "number": True,
    "special": True,
    "minNumber": 1,
    "minSpecial": 1,
    "words": 3,
    "separator": "-",
    "capitalize": False,
    "includeNumber": False,
}


class BitwardenError(Exception):
    """A user-facing Bitwarden error."""


class CliNotFoundError(BitwardenError):
    pass


class VaultLockedError(BitwardenError):
    pass


class NotLoggedInError(BitwardenError):
    pass


class RePromptRequiredError(BitwardenError):
    pass


CONFIG: Dict[str, Any] = {
    "cli_path": "bw",
    "server_url": "",
    "server_certs_path": "",
    "sync_on_launch": False,
    "fetch_favicons": False,
}


def log(*parts: Any) -> None:
    """Write diagnostics to stderr; stdout is reserved for protocol messages."""

    print(*parts, file=sys.stderr, flush=True)


def load_config() -> None:
    CONFIG_PATH = Path.cwd() / "config.json"
    if CONFIG_PATH.exists():
        try:
            with CONFIG_PATH.open("r", encoding="utf-8") as handle:
                values = json.load(handle)
            if isinstance(values, dict):
                CONFIG.update(values)
        except Exception as error:  # pragma: no cover - defensive startup path
            log("Could not read config.json:", error)

    cli_path = os.environ.get("BITWARDEN_CLI_PATH") or os.environ.get("BW_CLI_PATH")
    if cli_path:
        CONFIG["cli_path"] = cli_path


load_config()


STDOUT_LOCK = threading.Lock()
CLI_LOCK = threading.Lock()
SESSION_LOAD_LOCK = threading.Lock()
API_CREDENTIALS_LOCK = threading.Lock()
PENDING_STORAGE_LOCK = threading.Lock()
STOP_EVENT = threading.Event()

PENDING_STORAGE: Dict[str, Dict[str, Any]] = {}

STATE_LOCK = threading.RLock()
STATE: Dict[str, Any] = {
    "route": "home",
    "route_stack": ["home"],
    "query": "",
    "current_rev": 0,
    "query_generation": 0,
    "items": [],
    "items_by_id": {},
    "folders": [],
    "details": {},
    "loaded": False,
    "home_load_in_progress": False,
    "detail_loads": set(),
    "session_loaded": False,
    "session_token": None,
    "api_credentials_loaded": False,
    "api_credentials": None,
    "server_checked": False,
    "selected_id": None,
    "generated_password": None,
    "generator_values": dict(DEFAULT_GENERATOR_VALUES),
}


def send(payload: Dict[str, Any]) -> None:
    """Send exactly one newline-delimited JSON protocol message."""

    if STOP_EVENT.is_set():
        return
    try:
        # Keep the wire format ASCII-safe on Windows even when the host has not
        # set PYTHONIOENCODING yet. JSON decoding restores vault names exactly.
        line = json.dumps(payload, ensure_ascii=True, separators=(",", ":"))
        with STDOUT_LOCK:
            sys.stdout.write(line + "\n")
            sys.stdout.flush()
    except (BrokenPipeError, OSError):
        STOP_EVENT.set()


def render(rev: int, view: str, **payload: Any) -> None:
    frame: Dict[str, Any] = {"type": "render", "rev": int(rev or 0), "view": view}
    frame.update(payload)
    send(frame)


def command(name: str, **payload: Any) -> None:
    send({"type": "command", "command": name, **payload})


def toast(text: str, style: str = "success") -> None:
    command("toast", text=text, style=style)


def page_for(route: str, history: str = "none") -> Dict[str, Any]:
    """Build the stable host page identity for a plugin route."""

    if route == "home":
        return {
            "id": "bw:home",
            "title": "Vault",
            "history": history,
            "preserveState": True,
        }
    if route == "setup":
        return {"id": "bw:setup", "title": "Connect Bitwarden", "history": history}
    if route == "locked":
        return {"id": "bw:unlock", "title": "Unlock Bitwarden", "history": history}
    if route == "api_setup":
        return {
            "id": "bw:api-setup",
            "title": "Bitwarden API Login",
            "history": history,
            "breadcrumbs": [{"id": "bw:home", "label": "Vault"}],
            "preserveState": True,
        }
    if route == "generate":
        return {
            "id": "bw:generate",
            "title": "Generate Password",
            "history": history,
            "breadcrumbs": [{"id": "bw:home", "label": "Vault"}],
            "preserveState": True,
        }
    if route == "create_login":
        return {
            "id": "bw:create-login",
            "title": "Create Login",
            "history": history,
            "breadcrumbs": [{"id": "bw:home", "label": "Vault"}],
            "preserveState": True,
        }
    if route == "create_folder":
        return {
            "id": "bw:create-folder",
            "title": "Create Folder",
            "history": history,
            "breadcrumbs": [{"id": "bw:home", "label": "Vault"}],
            "preserveState": True,
        }
    if route.startswith("item:"):
        item_id = route.split(":", 1)[1]
        with STATE_LOCK:
            item = STATE["items_by_id"].get(item_id) or STATE["details"].get(item_id) or {}
        return {
            "id": f"bw:item:{item_id}",
            "title": str(item.get("name") or "Item"),
            "history": history,
            "breadcrumbs": [{"id": "bw:home", "label": "Vault"}],
            "preserveState": True,
        }
    return {"id": "bw:error", "title": "Bitwarden", "history": history}


def route_can_go_back(route: str) -> bool:
    return route not in {"home", "setup", "locked"} and len(STATE["route_stack"]) > 1


def current_context() -> Tuple[str, str, int, int]:
    with STATE_LOCK:
        return (
            str(STATE["route"]),
            str(STATE["query"]),
            int(STATE["current_rev"]),
            int(STATE["query_generation"]),
        )


def invalidate_query(text: str = "", rev: int = 0) -> int:
    with STATE_LOCK:
        STATE["query"] = text
        STATE["current_rev"] = int(rev or 0)
        STATE["query_generation"] += 1
        return int(STATE["query_generation"])


def set_query(text: str) -> None:
    command("setQuery", text=text)


def set_route(route: str, push: bool = True) -> None:
    with STATE_LOCK:
        if push:
            if STATE["route_stack"][-1] != route:
                STATE["route_stack"].append(route)
        else:
            STATE["route_stack"] = [route]
        STATE["route"] = route
        STATE["query"] = ""
        STATE["current_rev"] = 0
        STATE["query_generation"] += 1


def go_home() -> None:
    with STATE_LOCK:
        STATE["route"] = "home"
        STATE["route_stack"] = ["home"]
        STATE["query"] = ""
        STATE["current_rev"] = 0
        STATE["query_generation"] += 1
    set_query("")
    render_route(0, "", history="replace")


def navigate_to(route: str) -> None:
    if route == "generate":
        with STATE_LOCK:
            STATE["generated_password"] = None
            STATE["generator_values"] = dict(DEFAULT_GENERATOR_VALUES)
    set_route(route, push=True)
    set_query("")
    render_route(0, "", history="push")


def handle_back(message: Dict[str, Any]) -> None:
    target_page_id = str(message.get("toPageId") or "")
    with STATE_LOCK:
        stack = list(STATE["route_stack"])
        route = str(STATE["route"])

    if len(stack) <= 1:
        return

    target_route: Optional[str] = None
    if target_page_id:
        target_route = route_from_page_id(target_page_id)
        if target_route in stack:
            stack = stack[: stack.index(target_route) + 1]
        else:
            target_route = None
    if target_route is None:
        stack.pop()
        target_route = stack[-1]

    with STATE_LOCK:
        STATE["route_stack"] = stack
        STATE["route"] = target_route
        STATE["query"] = ""
        STATE["current_rev"] = 0
        STATE["query_generation"] += 1
    set_query("")
    render_route(0, "", history="replace")


def route_from_page_id(page_id: str) -> Optional[str]:
    if page_id == "bw:home":
        return "home"
    if page_id == "bw:generate":
        return "generate"
    if page_id == "bw:api-setup":
        return "api_setup"
    if page_id == "bw:create-login":
        return "create_login"
    if page_id == "bw:create-folder":
        return "create_folder"
    if page_id.startswith("bw:item:"):
        return "item:" + page_id[len("bw:item:") :]
    return None


def handle_navigate(message: Dict[str, Any]) -> None:
    target = route_from_page_id(str(message.get("targetPageId") or ""))
    if target is None:
        return
    with STATE_LOCK:
        if target in STATE["route_stack"]:
            STATE["route_stack"] = STATE["route_stack"][: STATE["route_stack"].index(target) + 1]
            STATE["route"] = target
            STATE["query"] = ""
            STATE["current_rev"] = 0
            STATE["query_generation"] += 1
        else:
            STATE["route_stack"].append(target)
            STATE["route"] = target
            STATE["query"] = ""
            STATE["current_rev"] = 0
            STATE["query_generation"] += 1
    set_query("")
    render_route(0, "", history="replace")


# ---------------------------------------------------------------------------
# Bitwarden CLI and host storage


def storage_get(key: str, secret: bool = False, timeout: float = 4.0) -> Any:
    request_id = uuid.uuid4().hex[:12]
    event = threading.Event()
    pending = {"event": event, "value": None}
    with PENDING_STORAGE_LOCK:
        PENDING_STORAGE[request_id] = pending

    send(
        {
            "type": "command",
            "command": "storage",
            "op": "get",
            "key": key,
            "secret": secret,
            "requestId": request_id,
        }
    )
    event.wait(timeout)
    with PENDING_STORAGE_LOCK:
        result = PENDING_STORAGE.pop(request_id, pending)
    return result.get("value")


def storage_set(key: str, value: str, secret: bool = False) -> None:
    send(
        {
            "type": "command",
            "command": "storage",
            "op": "set",
            "key": key,
            "value": value,
            "secret": secret,
        }
    )


def storage_delete(key: str, secret: bool = False) -> None:
    send(
        {
            "type": "command",
            "command": "storage",
            "op": "delete",
            "key": key,
            "secret": secret,
        }
    )


def load_session_token() -> Optional[str]:
    with SESSION_LOAD_LOCK:
        with STATE_LOCK:
            if STATE["session_loaded"]:
                return STATE["session_token"]

        token = (os.environ.get("BW_SESSION") or "").strip()
        if not token:
            try:
                stored = storage_get("session_token", secret=True)
                token = str(stored or "").strip()
            except Exception as error:  # pragma: no cover - defensive host path
                log("Could not read stored Bitwarden session:", error)
                token = ""

        with STATE_LOCK:
            STATE["session_loaded"] = True
            STATE["session_token"] = token or None
        return token or None


def save_session_token(token: str) -> None:
    token = token.strip()
    with STATE_LOCK:
        STATE["session_loaded"] = True
        STATE["session_token"] = token or None
    if token:
        storage_set("session_token", token, secret=True)


def clear_session_token() -> None:
    with STATE_LOCK:
        STATE["session_loaded"] = True
        STATE["session_token"] = None
    storage_delete("session_token", secret=True)


def load_api_credentials() -> Optional[Tuple[str, str]]:
    """Load optional API credentials from env or Tabame's secret store."""

    with API_CREDENTIALS_LOCK:
        with STATE_LOCK:
            if STATE["api_credentials_loaded"]:
                credentials = STATE.get("api_credentials")
                return tuple(credentials) if credentials else None

        client_id = (os.environ.get("BW_CLIENTID") or "").strip()
        client_secret = (os.environ.get("BW_CLIENTSECRET") or "").strip()
        if not client_id:
            client_id = str(storage_get("client_id", secret=True) or "").strip()
        if not client_secret:
            client_secret = str(storage_get("client_secret", secret=True) or "").strip()
        credentials = (client_id, client_secret) if client_id and client_secret else None
        with STATE_LOCK:
            STATE["api_credentials_loaded"] = True
            STATE["api_credentials"] = credentials
        return credentials


def save_api_credentials(client_id: str, client_secret: str) -> None:
    client_id = client_id.strip()
    client_secret = client_secret.strip()
    with STATE_LOCK:
        STATE["api_credentials_loaded"] = True
        STATE["api_credentials"] = (client_id, client_secret)
    storage_set("client_id", client_id, secret=True)
    storage_set("client_secret", client_secret, secret=True)


def cli_environment(overrides: Optional[Dict[str, str]] = None) -> Dict[str, str]:
    env = os.environ.copy()
    with STATE_LOCK:
        token = STATE.get("session_token")
    if token:
        env["BW_SESSION"] = str(token)
    else:
        env.pop("BW_SESSION", None)
    env["BW_NOINTERACTION"] = "1"

    certs_path = str(CONFIG.get("server_certs_path") or "").strip()
    if certs_path:
        env["NODE_EXTRA_CA_CERTS"] = certs_path
    if overrides:
        env.update({str(key): str(value) for key, value in overrides.items()})
    return env


def run_bw(
    args: Iterable[str],
    *,
    input_text: Optional[str] = None,
    env_overrides: Optional[Dict[str, str]] = None,
    timeout: float = 60.0,
) -> subprocess.CompletedProcess[str]:
    cli_path = str(CONFIG.get("cli_path") or "bw").strip()
    if len(cli_path) >= 2 and cli_path[0] == cli_path[-1] and cli_path[0] in {'"', "'"}:
        cli_path = cli_path[1:-1]
    command_args = [cli_path, *[str(arg) for arg in args]]

    try:
        with CLI_LOCK:
            return subprocess.run(
                command_args,
                cwd=str(Path.cwd()),
                env=cli_environment(env_overrides),
                input=input_text,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=timeout,
                check=False,
                shell=False,
            )
    except FileNotFoundError as error:
        raise CliNotFoundError(
            f"Bitwarden CLI was not found at '{cli_path}'. Install it or set cli_path in config.json."
        ) from error
    except PermissionError as error:
        raise CliNotFoundError(f"Bitwarden CLI is not executable: '{cli_path}'.") from error
    except subprocess.TimeoutExpired as error:
        raise BitwardenError("Bitwarden CLI timed out. Check the CLI installation and network connection.") from error
    except OSError as error:
        raise BitwardenError(f"Could not start Bitwarden CLI: {error}") from error


def command_failure(result: subprocess.CompletedProcess[str]) -> str:
    message = (result.stderr or result.stdout or "Bitwarden CLI command failed").strip()
    if not message:
        message = "Bitwarden CLI command failed"
    return message[-1000:]


def json_command(args: Iterable[str], *, input_text: Optional[str] = None) -> Any:
    result = run_bw(args, input_text=input_text)
    if result.returncode != 0:
        raise BitwardenError(command_failure(result))
    try:
        return json.loads(result.stdout)
    except (TypeError, json.JSONDecodeError) as error:
        raise BitwardenError("Bitwarden CLI returned invalid JSON.") from error


def ensure_server_configuration() -> None:
    server_url = str(CONFIG.get("server_url") or "").strip().rstrip("/")
    if not server_url:
        return
    with STATE_LOCK:
        if STATE["server_checked"]:
            return
        STATE["server_checked"] = True

    try:
        result = run_bw(["config", "server"], timeout=20)
        if result.returncode != 0:
            raise BitwardenError(command_failure(result))
        current_server = (result.stdout or "").strip().rstrip("/")
        if current_server != server_url:
            changed = run_bw(["config", "server", server_url], timeout=20)
            if changed.returncode != 0:
                raise BitwardenError(command_failure(changed))
    except Exception:
        with STATE_LOCK:
            STATE["server_checked"] = False
        raise


def get_status() -> str:
    ensure_server_configuration()
    result = run_bw(["status"], timeout=20)
    if result.returncode != 0:
        message = command_failure(result)
        lowered = message.lower()
        with STATE_LOCK:
            has_token = bool(STATE.get("session_token"))
        if "not logged" in lowered or "unauthenticated" in lowered:
            raise NotLoggedInError("Bitwarden is not logged in. Run `bw login` in a terminal first.")
        if "locked" in lowered:
            raise VaultLockedError("Vault is locked.")
        if has_token and "session" in lowered:
            clear_session_token()
            retry = run_bw(["status"], timeout=20)
            if retry.returncode == 0:
                try:
                    payload = json.loads(retry.stdout)
                    status = str(payload.get("status") or "").lower()
                    if status == "unlocked":
                        return status
                    if status == "unauthenticated":
                        raise NotLoggedInError("Bitwarden is not logged in. Run `bw login` in a terminal first.")
                    if status == "locked":
                        raise VaultLockedError("The saved Bitwarden session expired. Unlock the vault again.")
                except json.JSONDecodeError:
                    pass
            raise VaultLockedError("The saved Bitwarden session expired. Unlock the vault again.")
        raise BitwardenError(message)

    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise BitwardenError("Bitwarden CLI returned invalid status data.") from error
    status = str(payload.get("status") or "").lower()
    if status == "unlocked":
        return "unlocked"
    if status == "locked":
        raise VaultLockedError("Vault is locked.")
    if status == "unauthenticated":
        raise NotLoggedInError("Bitwarden is not logged in. Run `bw login` in a terminal first.")
    raise BitwardenError(f"Unknown Bitwarden vault status: {status or 'empty response'}")


def list_items() -> List[Dict[str, Any]]:
    items = json_command(["list", "items"])
    if not isinstance(items, list):
        raise BitwardenError("Bitwarden returned an unexpected item list.")
    return [item for item in items if isinstance(item, dict) and item.get("id") and item.get("name")]


def list_folders() -> List[Dict[str, Any]]:
    folders = json_command(["list", "folders"])
    if not isinstance(folders, list):
        raise BitwardenError("Bitwarden returned an unexpected folder list.")
    return [folder for folder in folders if isinstance(folder, dict)]


def get_full_item(item_id: str) -> Dict[str, Any]:
    with STATE_LOCK:
        cached = STATE["details"].get(item_id)
    if isinstance(cached, dict):
        return cached
    item = json_command(["get", "item", item_id])
    if not isinstance(item, dict):
        raise BitwardenError("Bitwarden returned an unexpected item.")
    with STATE_LOCK:
        STATE["details"][item_id] = item
    return item


def encode_json(value: Dict[str, Any]) -> str:
    serialized = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    result = run_bw(["encode"], input_text=serialized, timeout=20)
    if result.returncode != 0:
        raise BitwardenError(command_failure(result))
    encoded = (result.stdout or "").strip()
    if not encoded:
        raise BitwardenError("Bitwarden CLI returned an empty encoded payload.")
    return encoded


# ---------------------------------------------------------------------------
# Vault data and render helpers


def item_type(item: Dict[str, Any]) -> int:
    try:
        return int(item.get("type") or 0)
    except (TypeError, ValueError):
        return 0


def item_type_label(item: Dict[str, Any]) -> str:
    return ITEM_TYPE_LABELS.get(item_type(item), "Item")


def first_uri(item: Dict[str, Any]) -> str:
    uris = (item.get("login") or {}).get("uris") or []
    for entry in uris:
        if isinstance(entry, dict) and entry.get("uri"):
            return str(entry["uri"])
    return ""


def favicon_for(item: Dict[str, Any]) -> Optional[str]:
    if not bool(CONFIG.get("fetch_favicons")) or item_type(item) != 1:
        return None
    uri = first_uri(item)
    try:
        parsed = urlsplit(uri if "://" in uri else f"https://{uri}")
        host = parsed.hostname
        if host:
            return f"https://icons.bitwarden.net/{host}/icon.png"
    except ValueError:
        pass
    return None


def item_icon(item: Dict[str, Any]) -> str:
    return favicon_for(item) or ITEM_TYPE_ICONS.get(item_type(item), "lock")


def folder_name(item: Dict[str, Any], folders: Optional[List[Dict[str, Any]]] = None) -> str:
    folder_id = item.get("folderId")
    if not folder_id:
        return "No folder"
    folder_list = folders
    if folder_list is None:
        with STATE_LOCK:
            folder_list = list(STATE["folders"])
    for folder in folder_list:
        if str(folder.get("id")) == str(folder_id):
            return str(folder.get("name") or "No folder")
    return "Unknown folder"


def searchable_values(item: Dict[str, Any], folders: List[Dict[str, Any]]) -> List[str]:
    values: List[str] = [
        str(item.get("name") or ""),
        item_type_label(item),
        folder_name(item, folders),
    ]
    login = item.get("login") or {}
    values.append(str(login.get("username") or ""))
    for uri in login.get("uris") or []:
        if isinstance(uri, dict):
            values.append(str(uri.get("uri") or ""))
    card = item.get("card") or {}
    values.extend([str(card.get("brand") or ""), str(card.get("number") or "")])
    identity = item.get("identity") or {}
    values.extend([str(identity.get("firstName") or ""), str(identity.get("lastName") or ""), str(identity.get("email") or "")])
    return [value for value in values if value]


def search_score(query: str, item: Dict[str, Any], folders: List[Dict[str, Any]]) -> Optional[float]:
    query = query.strip().casefold()
    if not query:
        return 0.0
    values = searchable_values(item, folders)
    haystack = " ".join(values).casefold()
    if query in haystack:
        return 10000.0 - float(haystack.index(query))

    score = 0.0
    for token in query.split():
        token_score = 0.0
        for value in values:
            candidate = value.casefold()
            if token in candidate:
                token_score = max(token_score, 700.0 - candidate.index(token))
            else:
                ratio = difflib.SequenceMatcher(None, token, candidate).ratio()
                token_score = max(token_score, ratio * 100.0)
        if token_score < 45.0:
            return None
        score += token_score
    return score


def item_row(item: Dict[str, Any], folders: List[Dict[str, Any]]) -> Dict[str, Any]:
    item_id = str(item.get("id") or "")
    label = item_type_label(item)
    login = item.get("login") or {}
    subtitle = str(login.get("username") or "")
    if not subtitle:
        subtitle = label

    accessories: List[Dict[str, Any]] = [{"text": label, "icon": ITEM_TYPE_ICONS.get(item_type(item), "lock")}]
    if item.get("folderId"):
        accessories.insert(0, {"text": folder_name(item, folders), "icon": "folder"})
    if item.get("favorite"):
        accessories.append({"text": "Favorite", "icon": "star", "color": "#63A0EA"})
    if item.get("reprompt") == 1:
        accessories.append({"text": "Re-prompt", "icon": "lock"})

    actions: List[Dict[str, Any]] = [
        {"id": "default", "title": "Show Details", "icon": "open"},
    ]
    if item_type(item) == 1:
        if login.get("password"):
            actions.extend(
                [
                    {"id": "copy_password", "title": "Copy Password", "icon": "key"},
                    {"id": "paste_password", "title": "Paste Password", "icon": "paste"},
                ]
            )
        if login.get("username"):
            actions.extend(
                [
                    {"id": "copy_username", "title": "Copy Username", "icon": "person"},
                    {"id": "paste_username", "title": "Paste Username", "icon": "paste"},
                ]
            )
        if login.get("totp"):
            actions.extend(
                [
                    {"id": "copy_totp", "title": "Copy TOTP", "icon": "clock"},
                    {"id": "paste_totp", "title": "Paste TOTP", "icon": "paste"},
                ]
            )
        if first_uri(item):
            actions.append({"id": "open_url", "title": "Open in Browser", "icon": "open"})
    if item.get("notes"):
        actions.append({"id": "copy_notes", "title": "Copy Notes", "icon": "note"})
    if item_type(item) == 3:
        card = item.get("card") or {}
        if card.get("number"):
            actions.append({"id": "copy_card_number", "title": "Copy Card Number", "icon": "copy"})
        if card.get("code"):
            actions.append({"id": "copy_card_code", "title": "Copy Security Code", "icon": "lock"})
    favorite_action = "remove_favorite" if item.get("favorite") else "add_favorite"
    actions.append(
        {
            "id": "toggle_favorite",
            "title": "Remove from Favorites" if favorite_action == "remove_favorite" else "Add to Favorites",
            "icon": "star",
        }
    )

    row: Dict[str, Any] = {
        "id": item_id,
        "title": str(item.get("name") or "Unnamed item"),
        "subtitle": subtitle,
        "icon": item_icon(item),
        "section": "Favorites" if item.get("favorite") else "Vault",
        "accessories": accessories,
        "actions": actions,
    }
    return row


def filtered_items(text: str) -> List[Dict[str, Any]]:
    with STATE_LOCK:
        items = list(STATE["items"])
        folders = list(STATE["folders"])
    scored: List[Tuple[float, Dict[str, Any]]] = []
    for item in items:
        score = search_score(text, item, folders)
        if score is not None:
            favorite_bonus = 500000.0 if item.get("favorite") else 0.0
            scored.append((favorite_bonus + score, item))
    scored.sort(key=lambda entry: (-entry[0], str(entry[1].get("name") or "").casefold()))
    return [item for _, item in scored]


def render_loading_home(rev: int, text: str = "Loading vault…") -> None:
    render(
        rev,
        "list",
        page=page_for("home"),
        loading=True,
        loadingText=text,
        placeholder="Search vault…",
        items=[],
    )


def home_actions() -> List[Dict[str, Any]]:
    return [
        {"id": "sync", "title": "Sync Vault", "icon": "refresh"},
        {"id": "generate", "title": "Generate Password", "icon": "key"},
        {"id": "create_login", "title": "Create Login", "icon": "add"},
        {"id": "create_folder", "title": "Create Folder", "icon": "folder"},
        {"id": "open_web_vault", "title": "Open Web Vault", "icon": "open"},
        {"id": "lock", "title": "Lock Vault", "icon": "lock"},
        {
            "id": "logout",
            "title": "Log Out",
            "icon": "close",
            "destructive": True,
            "confirm": {
                "title": "Log out of Bitwarden?",
                "message": "The saved unlock session will be removed from Tabame.",
                "confirmLabel": "Log Out",
            },
        },
    ]


def render_home(rev: int, text: str, history: str = "none") -> None:
    with STATE_LOCK:
        loaded = bool(STATE["loaded"])
        selected_id = STATE.get("selected_id")
    if not loaded:
        render_loading_home(rev)
        return

    selected = filtered_items(text)
    with STATE_LOCK:
        folders = list(STATE["folders"])
    rows = [item_row(item, folders) for item in selected]
    empty_payload: Dict[str, Any]
    if not rows:
        if text.strip():
            empty_payload = {
                "icon": "search",
                "title": "No matching vault items",
                "hint": "Try a different name, username, website, or card brand.",
            }
        else:
            empty_payload = {
                "icon": "lock",
                "title": "Your vault is empty",
                "hint": "Create a login item or sync the vault to load items.",
                "action": {"id": "create_login", "title": "Create Login", "icon": "add"},
            }

    payload: Dict[str, Any] = {
        "page": page_for("home", history),
        "placeholder": "Search vault…",
        "emptyText": "No matching vault items",
        "actions": home_actions(),
        "floatingAction": {"id": "create_login", "title": "Create Login", "icon": "add"},
        "items": rows,
    }
    if selected_id and any(row["id"] == selected_id for row in rows):
        payload["selectId"] = selected_id
    if not rows:
        payload["empty"] = empty_payload
    render(rev, "list", **payload)


def render_setup(rev: int, error: Optional[str] = None) -> None:
    server = str(CONFIG.get("server_url") or "Bitwarden Cloud")
    message = [
        "# Connect Bitwarden",
        "",
        "This plugin uses the official Bitwarden CLI and never stores your master password.",
        "",
        "1. Install the CLI and run `bw login` in a terminal.",
        "2. If you use a self-hosted server, set `server_url` in `config.json`.",
        "3. Return here and choose **Retry**.",
        "",
        f"Configured server: `{escape_markdown(server)}`",
        "",
        "After login, the plugin can unlock the vault and store only the short-lived session token in Tabame's secret storage.",
    ]
    if error:
        message = [f"## Setup issue", "", escape_markdown(error), ""] + message
    render(
        rev,
        "detail",
        page=page_for("setup"),
        detail={"markdown": "\n".join(message), "wide": True},
        actions=[
            {"id": "retry", "title": "Retry", "icon": "refresh"},
            {"id": "login_api", "title": "Sign In with API Key", "icon": "key"},
            {"id": "configure_api_login", "title": "Configure API Key", "icon": "settings"},
            {"id": "open_cli_docs", "title": "Open Bitwarden CLI Docs", "icon": "open"},
            {"id": "open_web_vault", "title": "Open Web Vault", "icon": "open"},
        ],
        placeholder="Bitwarden setup",
    )


def unlock_form(error: Optional[str] = None) -> Dict[str, Any]:
    form: Dict[str, Any] = {
        "title": "Unlock Bitwarden",
        "submitLabel": "Unlock",
        "sections": [{"id": "unlock", "title": "Master Password", "description": "The password is sent only to the local Bitwarden CLI."}],
        "fields": [
            {
                "id": "master_password",
                "type": "password",
                "label": "Master password",
                "required": True,
                "section": "unlock",
            }
        ],
    }
    if error:
        form["error"] = error
    return form


def render_unlock(rev: int, error: Optional[str] = None) -> None:
    render(
        rev,
        "form",
        page=page_for("locked"),
        placeholder="Unlock vault…",
        form=unlock_form(error),
        actions=[
            {"id": "open_cli_docs", "title": "Open Bitwarden CLI Docs", "icon": "open"},
            {"id": "login_api", "title": "Sign In with API Key", "icon": "key"},
            {
                "id": "logout",
                "title": "Log Out",
                "icon": "close",
                "destructive": True,
                "confirm": {
                    "title": "Log out of Bitwarden?",
                    "message": "The saved unlock session will be removed from Tabame.",
                    "confirmLabel": "Log Out",
                },
            },
        ],
    )


def api_setup_form(error: Optional[str] = None) -> Dict[str, Any]:
    form: Dict[str, Any] = {
        "title": "Bitwarden API Login",
        "submitLabel": "Save and Sign In",
        "sections": [
            {
                "id": "api",
                "title": "Personal API key",
                "description": "Create these values in Bitwarden Account Settings → Security → Keys.",
            }
        ],
        "fields": [
            {
                "id": "client_id",
                "type": "text",
                "label": "Client ID",
                "placeholder": "user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                "required": True,
                "section": "api",
            },
            {
                "id": "client_secret",
                "type": "password",
                "label": "Client secret",
                "required": True,
                "section": "api",
            },
        ],
    }
    if error:
        form["error"] = error
    return form


def render_api_setup_form(rev: int, error: Optional[str] = None) -> None:
    render(
        rev,
        "form",
        page=page_for("api_setup"),
        placeholder="Configure Bitwarden API login…",
        form=api_setup_form(error),
        actions=[
            {"id": "back", "title": "Back to Vault", "icon": "menu"},
            {"id": "open_web_vault", "title": "Open Web Vault", "icon": "open"},
        ],
    )


def field_specs(item: Dict[str, Any]) -> List[Dict[str, Any]]:
    fields: List[Dict[str, Any]] = []

    def add(
        key: str,
        label: str,
        value: Any,
        *,
        sensitive: bool = False,
        icon: Optional[str] = None,
        display: Optional[str] = None,
    ) -> None:
        if value is None or value == "":
            return
        raw = str(value)
        fields.append(
            {
                "key": key,
                "label": label,
                "value": raw,
                "sensitive": sensitive,
                "icon": icon,
                "display": display if display is not None else (SECRET_MASK if sensitive else raw),
            }
        )

    kind = item_type(item)
    if kind == 1:
        login = item.get("login") or {}
        add("login.username", "Username", login.get("username"), icon="person")
        add("login.password", "Password", login.get("password"), sensitive=True, icon="key")
        if login.get("totp"):
            add("login.totp", "Authenticator code", login.get("totp"), sensitive=True, icon="clock", display="Configured")
        for index, uri in enumerate(login.get("uris") or []):
            if isinstance(uri, dict):
                add(f"login.uri:{index}", f"Website {index + 1}", uri.get("uri"), icon="globe")
    elif kind == 3:
        card = item.get("card") or {}
        add("card.cardholderName", "Cardholder name", card.get("cardholderName"), icon="person")
        add("card.brand", "Brand", card.get("brand"), icon="tag")
        add("card.number", "Number", card.get("number"), sensitive=True, icon="money")
        add("card.expMonth", "Expiration month", card.get("expMonth"), icon="calendar")
        add("card.expYear", "Expiration year", card.get("expYear"), icon="calendar")
        add("card.code", "Security code", card.get("code"), sensitive=True, icon="lock")
    elif kind == 4:
        identity = item.get("identity") or {}
        identity_labels = {
            "title": "Title",
            "firstName": "First name",
            "middleName": "Middle name",
            "lastName": "Last name",
            "username": "Username",
            "company": "Company",
            "email": "Email",
            "phone": "Phone",
            "licenseNumber": "License number",
            "ssn": "Social Security number",
            "passportNumber": "Passport number",
            "country": "Country",
        }
        for key, label in identity_labels.items():
            add(
                f"identity.{key}",
                label,
                identity.get(key),
                sensitive=key in {"ssn", "passportNumber"},
                icon="person" if key in {"firstName", "lastName", "username"} else None,
            )
        address = ", ".join(
            str(identity.get(key)) for key in ("address1", "address2", "address3", "city", "state", "postalCode", "country") if identity.get(key)
        )
        add("identity.address", "Address", address, icon="location")
    elif kind == 5:
        key_data = item.get("sshKey") or {}
        add("ssh.publicKey", "Public key", key_data.get("publicKey"), icon="key")
        add("ssh.keyFingerprint", "Fingerprint", key_data.get("keyFingerprint"), icon="key")
        add("ssh.privateKey", "Private key", key_data.get("privateKey"), sensitive=True, icon="key")

    if item.get("notes"):
        add("notes", "Secure note", item.get("notes"), sensitive=True, icon="note", display="Available")

    for index, custom in enumerate(item.get("fields") or []):
        if not isinstance(custom, dict) or custom.get("type") == 3 or custom.get("value") in (None, ""):
            continue
        custom_type = custom.get("type")
        display = str(custom.get("value"))
        if custom_type == 2:
            display = "Yes" if str(custom.get("value")).lower() == "true" else "No"
        add(
            f"custom:{index}",
            str(custom.get("name") or "Custom field"),
            custom.get("value"),
            sensitive=custom_type == 1,
            icon="check" if custom_type == 2 else "tag",
            display=SECRET_MASK if custom_type == 1 else display,
        )
    return fields


def item_field_value(item: Dict[str, Any], key: str) -> Optional[str]:
    if key == "notes":
        value = item.get("notes")
        return str(value) if value is not None else None
    if key.startswith("login.uri:"):
        try:
            index = int(key.split(":", 1)[1])
            entry = ((item.get("login") or {}).get("uris") or [])[index]
            return str(entry.get("uri")) if isinstance(entry, dict) and entry.get("uri") else None
        except (IndexError, TypeError, ValueError):
            return None
    if key.startswith("custom:"):
        try:
            index = int(key.split(":", 1)[1])
            entry = (item.get("fields") or [])[index]
            return str(entry.get("value")) if isinstance(entry, dict) and entry.get("value") is not None else None
        except (IndexError, TypeError, ValueError):
            return None
    current: Any = item
    for part in key.split("."):
        if not isinstance(current, dict):
            return None
        current = current.get(part)
    return str(current) if current is not None and current != "" else None


def escape_markdown(value: Any) -> str:
    return str(value).replace("\\", "\\\\").replace("`", "\\`")


def detail_actions(item: Dict[str, Any]) -> List[Dict[str, Any]]:
    actions: List[Dict[str, Any]] = []
    kind = item_type(item)
    login = item.get("login") or {}
    if kind == 1:
        if login.get("password"):
            actions.extend(
                [
                    {"id": "copy_password", "title": "Copy Password", "icon": "key"},
                    {"id": "paste_password", "title": "Paste Password", "icon": "paste"},
                ]
            )
        if login.get("username"):
            actions.extend(
                [
                    {"id": "copy_username", "title": "Copy Username", "icon": "person"},
                    {"id": "paste_username", "title": "Paste Username", "icon": "paste"},
                ]
            )
        if login.get("totp"):
            actions.extend(
                [
                    {"id": "copy_totp", "title": "Copy TOTP", "icon": "clock"},
                    {"id": "paste_totp", "title": "Paste TOTP", "icon": "paste"},
                ]
            )
        if first_uri(item):
            actions.append({"id": "open_url", "title": "Open in Browser", "icon": "open"})
    if item.get("notes"):
        actions.extend(
            [
                {"id": "show_notes", "title": "Show Notes", "icon": "note"},
                {"id": "copy_notes", "title": "Copy Notes", "icon": "copy"},
            ]
        )
    if kind == 3:
        card = item.get("card") or {}
        if card.get("number"):
            actions.append({"id": "copy_card_number", "title": "Copy Card Number", "icon": "copy"})
        if card.get("code"):
            actions.append({"id": "copy_card_code", "title": "Copy Security Code", "icon": "lock"})
    favorite = bool(item.get("favorite"))
    actions.append(
        {
            "id": "toggle_favorite",
            "title": "Remove from Favorites" if favorite else "Add to Favorites",
            "icon": "star",
        }
    )
    return actions


def render_item_detail(rev: int, item_id: str, text: str, history: str = "none") -> None:
    with STATE_LOCK:
        item = STATE["details"].get(item_id) or STATE["items_by_id"].get(item_id)
    if not isinstance(item, dict):
        render_error(rev, "The selected Bitwarden item is no longer available.")
        return

    fields = field_specs(item)
    query = text.strip().casefold()
    if query:
        fields = [
            field
            for field in fields
            if query in str(field["label"]).casefold()
            or (not field["sensitive"] and query in str(field["value"]).casefold())
        ]

    metadata: List[Dict[str, Any]] = [
        {"label": "Type", "text": item_type_label(item), "icon": ITEM_TYPE_ICONS.get(item_type(item), "lock")},
        {"label": "Folder", "text": folder_name(item)},
        {"label": "Favorite", "text": "Yes" if item.get("favorite") else "No", "icon": "star"},
    ]
    for field in fields:
        entry: Dict[str, Any] = {
            "label": str(field["label"]),
            "text": str(field["display"]),
        }
        if field.get("icon"):
            entry["icon"] = field["icon"]
        entry["actions"] = [
            {"id": f"copy_field:{field['key']}", "title": f"Copy {field['label']}", "icon": "copy"},
            {"id": f"paste_field:{field['key']}", "title": f"Paste {field['label']}", "icon": "paste"},
        ]
        if field["key"].startswith("login.uri:"):
            entry["url"] = str(field["value"])
        metadata.append(entry)

    markdown = "# " + escape_markdown(item.get("name") or "Bitwarden item") + "\n\n"
    if query and not fields:
        markdown += "No fields match the current filter."
    else:
        markdown += "Use the field actions or Ctrl+K to copy a value. Sensitive values stay masked until an action requests them."

    payload: Dict[str, Any] = {
        "page": page_for(f"item:{item_id}", history),
        "canGoBack": route_can_go_back(f"item:{item_id}"),
        "placeholder": "Filter fields…",
        "detail": {"markdown": markdown, "metadata": metadata, "wide": True},
        "actions": detail_actions(item),
    }
    if item_type(item) == 1 and (item.get("login") or {}).get("password"):
        payload["floatingAction"] = {"id": "copy_password", "title": "Copy Password", "icon": "key"}
    render(rev, "detail", **payload)


def render_note_detail(item: Dict[str, Any]) -> None:
    name = escape_markdown(item.get("name") or "Secure note")
    notes = escape_markdown(item.get("notes") or "")
    render(
        0,
        "detail",
        page=page_for("item:" + str(item.get("id") or "")),
        canGoBack=True,
        detail={"markdown": f"# {name}\n\n```text\n{notes}\n```", "wide": True},
        actions=[
            {"id": "copy_notes", "title": "Copy Notes", "icon": "copy"},
        ],
    )


def render_error(rev: int, error: Any) -> None:
    message = str(error)
    route, _, _, _ = current_context()
    markdown = f"# Bitwarden error\n\n```text\n{escape_markdown(message)}\n```"
    actions: List[Dict[str, Any]] = [{"id": "retry", "title": "Retry", "icon": "refresh"}]
    if route != "home":
        actions.append({"id": "home", "title": "Back to Vault", "icon": "home"})
    render(
        rev,
        "detail",
        page=page_for(route),
        canGoBack=route_can_go_back(route),
        detail={"markdown": markdown, "wide": True},
        actions=actions,
    )


# ---------------------------------------------------------------------------
# Page rendering and background work


def activate_auth_route(route: str) -> None:
    with STATE_LOCK:
        STATE["route"] = route
        STATE["route_stack"] = [route]
        STATE["loaded"] = False
        STATE["items"] = []
        STATE["items_by_id"] = {}
        STATE["folders"] = []
        STATE["details"] = {}
        STATE["query"] = ""
        STATE["current_rev"] = 0
        STATE["query_generation"] += 1


def start_home_load(force_sync: bool = False) -> None:
    with STATE_LOCK:
        if STATE["home_load_in_progress"]:
            return
        STATE["home_load_in_progress"] = True
    thread = threading.Thread(target=load_home_worker, args=(force_sync,), daemon=True)
    thread.start()


def load_home_worker(force_sync: bool = False) -> None:
    try:
        load_session_token()
        status = get_status()
        if status == "unlocked":
            if force_sync or bool(CONFIG.get("sync_on_launch")):
                sync_result = run_bw(["sync"], timeout=120)
                if sync_result.returncode != 0:
                    raise BitwardenError(command_failure(sync_result))
            items = list_items()
            folders = list_folders()
            by_id = {str(item.get("id")): item for item in items if item.get("id")}
            with STATE_LOCK:
                STATE["items"] = items
                STATE["items_by_id"] = by_id
                STATE["folders"] = folders
                STATE["details"] = {}
                STATE["loaded"] = True
            route, text, rev, _ = current_context()
            if route == "home":
                render_home(rev, text)
            return
    except CliNotFoundError as error:
        with STATE_LOCK:
            route = STATE["route"]
            rev = int(STATE["current_rev"])
        if route == "home":
            activate_auth_route("setup")
            render_setup(rev, str(error))
        return
    except NotLoggedInError as error:
        with STATE_LOCK:
            route = STATE["route"]
            rev = int(STATE["current_rev"])
        if route == "home":
            activate_auth_route("setup")
            render_setup(rev, str(error))
        return
    except VaultLockedError as error:
        with STATE_LOCK:
            route = STATE["route"]
            rev = int(STATE["current_rev"])
        if route == "home":
            activate_auth_route("locked")
            render_unlock(rev, str(error) if str(error) != "Vault is locked." else None)
        return
    except Exception as error:
        route, _, rev, _ = current_context()
        if route == "home":
            render_error(rev, error)
        log("Bitwarden load failed:", error)
    finally:
        with STATE_LOCK:
            STATE["home_load_in_progress"] = False


def start_detail_load(item_id: str) -> None:
    with STATE_LOCK:
        if item_id in STATE["detail_loads"]:
            return
        STATE["detail_loads"].add(item_id)
    thread = threading.Thread(target=load_detail_worker, args=(item_id,), daemon=True)
    thread.start()


def load_detail_worker(item_id: str) -> None:
    try:
        get_full_item(item_id)
        route, text, rev, _ = current_context()
        if route == f"item:{item_id}":
            render_item_detail(rev, item_id, text)
    except Exception as error:
        route, _, rev, _ = current_context()
        if route == f"item:{item_id}":
            render_error(rev, error)
        log("Bitwarden item load failed:", error)
    finally:
        with STATE_LOCK:
            STATE["detail_loads"].discard(item_id)


def render_route(rev: int, text: str, history: str = "none") -> None:
    route, _, _, _ = current_context()
    if route == "home":
        with STATE_LOCK:
            loaded = bool(STATE["loaded"])
        if loaded:
            render_home(rev, text, history=history)
        else:
            render_loading_home(rev)
            start_home_load()
        return
    if route == "setup":
        render_setup(rev)
        return
    if route == "locked":
        render_unlock(rev)
        return
    if route == "api_setup":
        render_api_setup_form(rev)
        return
    if route == "generate":
        with STATE_LOCK:
            generated = STATE.get("generated_password")
            values = dict(STATE.get("generator_values") or DEFAULT_GENERATOR_VALUES)
        if generated:
            render_generator_result(rev, generated)
        else:
            render_generator_form(rev, values=values)
        return
    if route == "create_login":
        render_create_login_form(rev)
        return
    if route == "create_folder":
        render_create_folder_form(rev)
        return
    if route.startswith("item:"):
        item_id = route.split(":", 1)[1]
        with STATE_LOCK:
            has_detail = item_id in STATE["details"]
        if has_detail:
            render_item_detail(rev, item_id, text, history=history)
        else:
            render(
                rev,
                "detail",
                page=page_for(route, history),
                canGoBack=True,
                loading=True,
                loadingText="Loading item details…",
                detail={"markdown": "Loading item details…"},
            )
            start_detail_load(item_id)
        return
    render_error(rev, "Unknown plugin screen.")


def handle_query(message: Dict[str, Any]) -> None:
    text = message.get("text")
    if text is None:
        text = message.get("query") or ""
    text = str(text)
    rev = int(message.get("rev") or 0)
    with STATE_LOCK:
        STATE["query"] = text
        STATE["current_rev"] = rev
        route = STATE["route"]
        loaded = bool(STATE["loaded"])
    if route == "home" and not loaded:
        render_loading_home(rev)
        start_home_load()
    elif route.startswith("item:"):
        render_route(rev, text)
    else:
        render_route(rev, text)


# ---------------------------------------------------------------------------
# Forms and actions


def form_loading(route: str, title: str) -> None:
    if route == "locked":
        form = unlock_form()
    elif route == "generate":
        with STATE_LOCK:
            form = generator_form(dict(STATE.get("generator_values") or DEFAULT_GENERATOR_VALUES))
    elif route == "api_setup":
        form = api_setup_form()
    elif route == "create_login":
        form = create_login_form()
    else:
        form = create_folder_form()
    render(0, "form", page=page_for(route), loading=True, loadingText=title, form=form)


def normalize_int(value: Any, default: int, minimum: int, maximum: int) -> int:
    try:
        number = int(value)
    except (TypeError, ValueError):
        number = default
    return max(minimum, min(maximum, number))


def normalize_generator_values(values: Dict[str, Any]) -> Dict[str, Any]:
    result = dict(DEFAULT_GENERATOR_VALUES)
    result.update({key: value for key, value in values.items() if key in result})
    result["type"] = "passphrase" if str(result.get("type")).lower() == "passphrase" else "password"
    result["length"] = normalize_int(result.get("length"), 20, 5, 128)
    result["words"] = normalize_int(result.get("words"), 3, 3, 20)
    result["minNumber"] = normalize_int(result.get("minNumber"), 1, 0, 9)
    result["minSpecial"] = normalize_int(result.get("minSpecial"), 1, 0, 9)
    result["separator"] = str(result.get("separator") or "-")[:1] or "-"
    for key in ("uppercase", "lowercase", "number", "special", "capitalize", "includeNumber"):
        result[key] = bool(result.get(key))
    return result


def generator_form(values: Dict[str, Any], error: Optional[str] = None) -> Dict[str, Any]:
    values = normalize_generator_values(values)
    form: Dict[str, Any] = {
        "title": "Generate Password",
        "submitLabel": "Generate",
        "sections": [
            {"id": "type", "title": "Password type"},
            {"id": "password", "title": "Password options", "collapsible": True},
            {"id": "passphrase", "title": "Passphrase options", "collapsible": True},
        ],
        "fields": [
            {
                "id": "type",
                "type": "dropdown",
                "label": "Type",
                "value": values["type"],
                "options": [
                    {"value": "password", "label": "Password"},
                    {"value": "passphrase", "label": "Passphrase"},
                ],
                "section": "type",
            },
            {"id": "length", "type": "number", "label": "Length", "value": values["length"], "min": 5, "max": 128, "section": "password", "visibleWhen": {"field": "type", "equals": "password"}},
            {"id": "uppercase", "type": "checkbox", "label": "Uppercase characters", "value": values["uppercase"], "section": "password", "visibleWhen": {"field": "type", "equals": "password"}},
            {"id": "lowercase", "type": "checkbox", "label": "Lowercase characters", "value": values["lowercase"], "section": "password", "visibleWhen": {"field": "type", "equals": "password"}},
            {"id": "number", "type": "checkbox", "label": "Numbers", "value": values["number"], "section": "password", "visibleWhen": {"field": "type", "equals": "password"}},
            {"id": "minNumber", "type": "number", "label": "Minimum numbers", "value": values["minNumber"], "min": 0, "max": 9, "section": "password", "visibleWhen": {"field": "type", "equals": "password"}},
            {"id": "special", "type": "checkbox", "label": "Special characters", "value": values["special"], "section": "password", "visibleWhen": {"field": "type", "equals": "password"}},
            {"id": "minSpecial", "type": "number", "label": "Minimum special characters", "value": values["minSpecial"], "min": 0, "max": 9, "section": "password", "visibleWhen": {"field": "type", "equals": "password"}},
            {"id": "words", "type": "number", "label": "Number of words", "value": values["words"], "min": 3, "max": 20, "section": "passphrase", "visibleWhen": {"field": "type", "equals": "passphrase"}},
            {"id": "separator", "type": "text", "label": "Word separator", "value": values["separator"], "maxLength": 1, "section": "passphrase", "visibleWhen": {"field": "type", "equals": "passphrase"}},
            {"id": "capitalize", "type": "checkbox", "label": "Capitalize words", "value": values["capitalize"], "section": "passphrase", "visibleWhen": {"field": "type", "equals": "passphrase"}},
            {"id": "includeNumber", "type": "checkbox", "label": "Include a number", "value": values["includeNumber"], "section": "passphrase", "visibleWhen": {"field": "type", "equals": "passphrase"}},
        ],
    }
    if error:
        form["error"] = error
    return form


def build_generator_args(values: Dict[str, Any]) -> List[str]:
    values = normalize_generator_values(values)
    if values["type"] == "passphrase":
        args = ["generate", "--passphrase", "--words", str(values["words"]), "--separator", values["separator"]]
        if values["capitalize"]:
            args.append("--capitalize")
        if values["includeNumber"]:
            args.append("--includeNumber")
        return args

    if not any(values[key] for key in ("uppercase", "lowercase", "number", "special")):
        raise BitwardenError("Select at least one character set.")
    args = ["generate", "--length", str(values["length"])]
    for key in ("uppercase", "lowercase", "number", "special"):
        if values[key]:
            args.append(f"--{key}")
    if values["number"]:
        args.extend(["--minNumber", str(values["minNumber"])])
    if values["special"]:
        args.extend(["--minSpecial", str(values["minSpecial"])])
    return args


def render_generator_form(rev: int, values: Optional[Dict[str, Any]] = None, error: Optional[str] = None) -> None:
    with STATE_LOCK:
        current_values = dict(values or STATE.get("generator_values") or DEFAULT_GENERATOR_VALUES)
    render(
        rev,
        "form",
        page=page_for("generate"),
        placeholder="Generate a password…",
        form=generator_form(current_values, error),
        actions=[
            {"id": "back", "title": "Back to Vault", "icon": "menu"},
        ],
    )


def render_generator_result(rev: int, password: str) -> None:
    with STATE_LOCK:
        values = dict(STATE.get("generator_values") or DEFAULT_GENERATOR_VALUES)
    kind = "Passphrase" if values.get("type") == "passphrase" else "Password"
    markdown = f"# Generated {kind}\n\n```text\n{escape_markdown(password)}\n```\n\nUse **Copy** or **Paste** below, then regenerate when needed."
    render(
        rev,
        "detail",
        page=page_for("generate"),
        canGoBack=True,
        detail={"markdown": markdown, "wide": True},
        actions=[
            {"id": "copy", "title": "Copy", "icon": "copy"},
            {"id": "paste", "title": "Paste", "icon": "paste"},
            {"id": "regenerate", "title": "Regenerate", "icon": "refresh"},
            {"id": "edit_options", "title": "Edit Options", "icon": "settings"},
        ],
        floatingAction={"id": "copy", "title": "Copy", "icon": "copy"},
    )


def create_login_form(error: Optional[str] = None) -> Dict[str, Any]:
    with STATE_LOCK:
        folders = list(STATE["folders"])
    options: List[Any] = [{"value": NO_FOLDER, "label": "No folder"}]
    options.extend({"value": str(folder.get("id")), "label": str(folder.get("name") or "Unnamed folder")} for folder in folders if folder.get("id"))
    form: Dict[str, Any] = {
        "title": "Create Login",
        "submitLabel": "Create Login",
        "sections": [
            {"id": "login", "title": "Login details", "description": "Create a new login in the current Bitwarden vault."},
        ],
        "fields": [
            {"id": "name", "type": "text", "label": "Name", "placeholder": "GitHub, Gmail…", "required": True, "section": "login"},
            {"id": "folder_id", "type": "dropdown", "label": "Folder", "value": NO_FOLDER, "options": options, "section": "login"},
            {"id": "username", "type": "text", "label": "Username", "placeholder": "name@example.com", "section": "login"},
            {"id": "uri", "type": "text", "label": "Website URI", "placeholder": "https://example.com", "section": "login"},
            {"id": "password", "type": "password", "label": "Password", "required": True, "section": "login"},
        ],
    }
    if error:
        form["error"] = error
    return form


def render_create_login_form(rev: int, error: Optional[str] = None) -> None:
    render(
        rev,
        "form",
        page=page_for("create_login"),
        placeholder="Create a login…",
        form=create_login_form(error),
        actions=[
            {"id": "generate", "title": "Generate Password", "icon": "key"},
            {"id": "back", "title": "Back to Vault", "icon": "menu"},
        ],
    )


def create_folder_form(error: Optional[str] = None) -> Dict[str, Any]:
    form: Dict[str, Any] = {
        "title": "Create Folder",
        "submitLabel": "Create Folder",
        "fields": [
            {"id": "name", "type": "text", "label": "Folder name", "placeholder": "Personal, Work…", "required": True},
        ],
    }
    if error:
        form["error"] = error
    return form


def render_create_folder_form(rev: int, error: Optional[str] = None) -> None:
    render(
        rev,
        "form",
        page=page_for("create_folder"),
        placeholder="Create a folder…",
        form=create_folder_form(error),
        actions=[{"id": "back", "title": "Back to Vault", "icon": "menu"}],
    )


def api_login_worker(credentials: Optional[Tuple[str, str]] = None) -> None:
    try:
        credentials = credentials or load_api_credentials()
        if not credentials:
            raise BitwardenError("No saved API key. Choose Configure API Key first, or run `bw login` in a terminal.")
        client_id, client_secret = credentials
        ensure_server_configuration()
        clear_session_token()
        result = run_bw(
            ["login", "--apikey"],
            env_overrides={"BW_CLIENTID": client_id, "BW_CLIENTSECRET": client_secret},
            timeout=120,
        )
        if result.returncode != 0:
            raise BitwardenError(command_failure(result))
        with STATE_LOCK:
            STATE["session_token"] = None
            STATE["session_loaded"] = True
        activate_auth_route("locked")
        toast("Signed in to Bitwarden")
        render_unlock(0)
    except Exception as error:
        route, _, _, _ = current_context()
        if route == "api_setup":
            render_api_setup_form(str(error))
        else:
            if route != "setup":
                activate_auth_route("setup")
            render_setup(0, str(error))
        log("Bitwarden API login failed:", error)


def configure_api_worker(values: Dict[str, Any]) -> None:
    client_id = str(values.get("client_id") or "").strip()
    client_secret = str(values.get("client_secret") or "").strip()
    if not client_id or not client_secret:
        render_api_setup_form("Both the client ID and client secret are required.")
        return
    save_api_credentials(client_id, client_secret)
    api_login_worker((client_id, client_secret))


def unlock_worker(password: str) -> None:
    try:
        with STATE_LOCK:
            STATE["session_token"] = None
        result = run_bw(
            ["unlock", "--passwordenv", "BW_PASSWORD", "--raw"],
            env_overrides={"BW_PASSWORD": password},
            timeout=120,
        )
        if result.returncode != 0:
            raise BitwardenError(command_failure(result))
        token = (result.stdout or "").strip()
        if not token:
            raise BitwardenError("Bitwarden returned an empty unlock session.")
        save_session_token(token)
        toast("Vault unlocked")
        refresh_home()
    except Exception as error:
        render_unlock(0, str(error))
        log("Bitwarden unlock failed:", error)


def refresh_home(force_sync: bool = False) -> None:
    with STATE_LOCK:
        STATE["route"] = "home"
        STATE["route_stack"] = ["home"]
        STATE["query"] = ""
        STATE["current_rev"] = 0
        STATE["query_generation"] += 1
        STATE["loaded"] = False
    set_query("")
    render_loading_home(0, "Syncing vault…" if force_sync else "Loading vault…")
    start_home_load(force_sync)


def generate_worker(values: Dict[str, Any]) -> None:
    normalized = normalize_generator_values(values)
    try:
        result = run_bw(build_generator_args(normalized), timeout=60)
        if result.returncode != 0:
            raise BitwardenError(command_failure(result))
        password = (result.stdout or "").strip()
        if not password:
            raise BitwardenError("Bitwarden returned an empty generated value.")
        with STATE_LOCK:
            STATE["generator_values"] = normalized
            STATE["generated_password"] = password
        render_generator_result(0, password)
    except Exception as error:
        with STATE_LOCK:
            STATE["generator_values"] = normalized
            STATE["generated_password"] = None
        render_generator_form(0, normalized, str(error))
        log("Bitwarden password generation failed:", error)


def create_login_worker(values: Dict[str, Any]) -> None:
    name = str(values.get("name") or "").strip()
    password = str(values.get("password") or "")
    if not name:
        render_create_login_form(0, "A login name is required.")
        return
    if not password:
        render_create_login_form(0, "A password is required.")
        return
    try:
        item = json_command(["get", "template", "item"])
        login = json_command(["get", "template", "item.login"])
        if not isinstance(item, dict) or not isinstance(login, dict):
            raise BitwardenError("Bitwarden returned invalid login templates.")
        item["name"] = name
        item["type"] = 1
        folder_id = str(values.get("folder_id") or NO_FOLDER)
        item["folderId"] = None if folder_id == NO_FOLDER else folder_id
        item["notes"] = None
        login["username"] = str(values.get("username") or "") or None
        login["password"] = password
        login["totp"] = None
        login["fido2Credentials"] = None
        uri = str(values.get("uri") or "").strip()
        login["uris"] = [{"match": None, "uri": uri}] if uri else []
        item["login"] = login
        encoded = encode_json(item)
        created = json_command(["create", "item", encoded])
        created_name = str(created.get("name") if isinstance(created, dict) else name)
        toast(f"Login created: {created_name}")
        refresh_home()
    except Exception as error:
        render_create_login_form(0, str(error))
        log("Bitwarden login creation failed:", error)


def create_folder_worker(values: Dict[str, Any]) -> None:
    name = str(values.get("name") or "").strip()
    if not name:
        render_create_folder_form(0, "A folder name is required.")
        return
    try:
        folder = json_command(["get", "template", "folder"])
        if not isinstance(folder, dict):
            raise BitwardenError("Bitwarden returned an invalid folder template.")
        folder["name"] = name
        encoded = encode_json(folder)
        result = run_bw(["create", "folder", encoded])
        if result.returncode != 0:
            raise BitwardenError(command_failure(result))
        toast(f"Folder created: {name}")
        refresh_home()
    except Exception as error:
        render_create_folder_form(0, str(error))
        log("Bitwarden folder creation failed:", error)


def toggle_favorite(item_id: str) -> None:
    item = get_full_item(item_id)
    updated = dict(item)
    updated["favorite"] = not bool(item.get("favorite"))
    encoded = encode_json(updated)
    result = run_bw(["edit", "item", item_id, encoded])
    if result.returncode != 0:
        raise BitwardenError(command_failure(result))
    response: Any = None
    try:
        response = json.loads(result.stdout)
    except json.JSONDecodeError:
        response = updated
    if not isinstance(response, dict):
        response = updated
    with STATE_LOCK:
        STATE["details"][item_id] = response
        for index, cached in enumerate(STATE["items"]):
            if str(cached.get("id")) == item_id:
                STATE["items"][index] = {**cached, "favorite": response.get("favorite", updated["favorite"])}
                STATE["items_by_id"][item_id] = STATE["items"][index]
                break
    toast("Added to favorites" if updated["favorite"] else "Removed from favorites")
    route, text, rev, _ = current_context()
    if route == "home":
        render_home(rev, text)
    elif route == f"item:{item_id}":
        render_item_detail(rev, item_id, text)


def perform_copy(item_id: str, key: str, paste: bool = False) -> None:
    item = get_full_item(item_id)
    value: Optional[str]
    if key == "login.totp":
        result = run_bw(["get", "totp", item_id], timeout=30)
        if result.returncode != 0:
            raise BitwardenError(command_failure(result))
        value = (result.stdout or "").strip()
    else:
        value = item_field_value(item, key)
    if value in (None, ""):
        raise BitwardenError("That Bitwarden field is empty.")
    if value == HIDDEN_VALUE:
        raise RePromptRequiredError("This field requires a Bitwarden master-password re-prompt. Unlock the vault again and retry.")
    command("paste" if paste else "copy", text=value)


def perform_item_action(item_id: str, action: str) -> None:
    item = get_full_item(item_id)
    field_actions = {
        "copy_password": ("login.password", False),
        "paste_password": ("login.password", True),
        "copy_username": ("login.username", False),
        "paste_username": ("login.username", True),
        "copy_totp": ("login.totp", False),
        "paste_totp": ("login.totp", True),
        "copy_notes": ("notes", False),
        "copy_card_number": ("card.number", False),
        "copy_card_code": ("card.code", False),
    }
    if action in field_actions:
        key, paste = field_actions[action]
        perform_copy(item_id, key, paste)
        return
    if action.startswith("copy_field:") or action.startswith("paste_field:"):
        paste = action.startswith("paste_field:")
        key = action.split(":", 1)[1]
        perform_copy(item_id, key, paste)
        return
    if action == "default" or action == "show_details":
        navigate_to(f"item:{item_id}")
        return
    if action == "open_url":
        uri = first_uri(item)
        if not uri:
            raise BitwardenError("This login has no website URI.")
        command("open", url=uri)
        return
    if action == "show_notes":
        if not item.get("notes"):
            raise BitwardenError("This item has no notes.")
        render_note_detail(item)
        return
    if action == "toggle_favorite":
        toggle_favorite(item_id)
        return
    if action == "copy_id":
        command("copy", text=item_id)
        return
    raise BitwardenError(f"Unsupported Bitwarden action: {action}")


def open_web_vault() -> None:
    server = str(CONFIG.get("server_url") or "").strip().rstrip("/")
    command("open", url=server or DEFAULT_SERVER_URL)


def lock_vault_worker() -> None:
    try:
        result = run_bw(["lock"], timeout=30)
        if result.returncode != 0:
            message = command_failure(result)
            if "already locked" not in message.lower() and "vault is locked" not in message.lower():
                raise BitwardenError(message)
        clear_session_token()
        activate_auth_route("locked")
        toast("Vault locked")
        render_unlock(0)
    except Exception as error:
        render_error(0, error)
        log("Bitwarden lock failed:", error)


def logout_vault_worker() -> None:
    try:
        result = run_bw(["logout"], timeout=30)
        if result.returncode != 0:
            message = command_failure(result)
            if "not logged" not in message.lower():
                raise BitwardenError(message)
        clear_session_token()
        activate_auth_route("setup")
        toast("Logged out of Bitwarden")
        render_setup(0)
    except Exception as error:
        render_error(0, error)
        log("Bitwarden logout failed:", error)


def handle_frame_action(action: str, route: str) -> None:
    if action in {"home", "back"}:
        if action == "home":
            go_home()
        else:
            handle_back({})
        return
    if action in {"retry", "refresh"}:
        if route in {"setup", "locked", "home"}:
            refresh_home()
        elif route.startswith("item:"):
            item_id = route.split(":", 1)[1]
            with STATE_LOCK:
                STATE["details"].pop(item_id, None)
            render_route(0, "")
        return
    if action == "configure_api_login":
        navigate_to("api_setup")
        return
    if action == "login_api":
        toast("Signing in with Bitwarden API key…", style="progress")
        threading.Thread(target=api_login_worker, daemon=True).start()
        return
    if action == "sync":
        refresh_home(force_sync=True)
        return
    if action == "generate":
        if route == "create_login":
            navigate_to("generate")
        else:
            navigate_to("generate")
        return
    if action == "edit_options" and route == "generate":
        with STATE_LOCK:
            STATE["generated_password"] = None
        render_generator_form(0)
        return
    if action == "create_login":
        navigate_to("create_login")
        return
    if action == "create_folder":
        navigate_to("create_folder")
        return
    if action == "open_web_vault":
        open_web_vault()
        return
    if action == "open_cli_docs":
        command("open", url=CLI_DOCS_URL)
        return
    if action == "lock":
        threading.Thread(target=lock_vault_worker, daemon=True).start()
        return
    if action == "logout":
        threading.Thread(target=logout_vault_worker, daemon=True).start()
        return
    if route == "generate":
        with STATE_LOCK:
            password = STATE.get("generated_password")
            values = dict(STATE.get("generator_values") or DEFAULT_GENERATOR_VALUES)
        if action == "copy" and password:
            command("copy", text=password)
            return
        if action == "paste" and password:
            command("paste", text=password)
            return
        if action == "regenerate":
            form_loading("generate", "Generating password…")
            threading.Thread(target=generate_worker, args=(values,), daemon=True).start()
            return
    raise BitwardenError(f"Unsupported Bitwarden action: {action}")


def handle_action(message: Dict[str, Any]) -> None:
    action = str(message.get("action") or "default")
    item_id = str(message.get("id") or "")
    with STATE_LOCK:
        route = str(STATE["route"])
        if item_id:
            STATE["selected_id"] = item_id

    if item_id and route == "home":
        if action == "default":
            navigate_to(f"item:{item_id}")
        else:
            perform_item_action(item_id, action)
        return
    if item_id and route.startswith("item:"):
        perform_item_action(item_id, action)
        return
    if route.startswith("item:") and not item_id:
        perform_item_action(route.split(":", 1)[1], action)
        return
    handle_frame_action(action, route)


def handle_submit(message: Dict[str, Any]) -> None:
    values = message.get("values")
    if not isinstance(values, dict):
        values = {}
    with STATE_LOCK:
        route = str(STATE["route"])
    if route == "locked":
        password = str(values.get("master_password") or "")
        if not password:
            render_unlock(0, "Enter your master password.")
            return
        form_loading("locked", "Unlocking vault…")
        threading.Thread(target=unlock_worker, args=(password,), daemon=True).start()
        return
    if route == "generate":
        normalized = normalize_generator_values(values)
        with STATE_LOCK:
            STATE["generator_values"] = normalized
            STATE["generated_password"] = None
        form_loading("generate", "Generating password…")
        threading.Thread(target=generate_worker, args=(normalized,), daemon=True).start()
        return
    if route == "api_setup":
        form_loading("api_setup", "Signing in to Bitwarden…")
        threading.Thread(target=configure_api_worker, args=(dict(values),), daemon=True).start()
        return
    if route == "create_login":
        form_loading("create_login", "Creating login…")
        threading.Thread(target=create_login_worker, args=(dict(values),), daemon=True).start()
        return
    if route == "create_folder":
        form_loading("create_folder", "Creating folder…")
        threading.Thread(target=create_folder_worker, args=(dict(values),), daemon=True).start()
        return


def handle_storage_reply(message: Dict[str, Any]) -> None:
    request_id = str(message.get("requestId") or "")
    if not request_id:
        return
    with PENDING_STORAGE_LOCK:
        pending = PENDING_STORAGE.get(request_id)
        if pending is not None:
            pending["value"] = message.get("value")
            pending["event"].set()


def handle_message(message: Dict[str, Any]) -> None:
    message_type = message.get("type")
    if message_type == "close":
        STOP_EVENT.set()
        with PENDING_STORAGE_LOCK:
            for pending in PENDING_STORAGE.values():
                pending["event"].set()
        return
    if message_type == "storage":
        handle_storage_reply(message)
        return
    if message_type == "init":
        text = str(message.get("query") or "")
        with STATE_LOCK:
            STATE["query"] = text
            STATE["current_rev"] = 0
        render_loading_home(0, "Starting Bitwarden…")
        return
    if message_type in {"query", "submitQuery"}:
        if message_type == "submitQuery":
            handle_submit({"values": {"prompt": message.get("text") or ""}})
        else:
            handle_query(message)
        return
    if message_type == "select":
        with STATE_LOCK:
            STATE["selected_id"] = str(message.get("id") or "")
        return
    if message_type == "action":
        try:
            threading.Thread(target=handle_action, args=(message,), daemon=True).start()
        except Exception as error:  # pragma: no cover - thread creation failure
            render_error(0, error)
        return
    if message_type == "submit":
        try:
            threading.Thread(target=handle_submit, args=(message,), daemon=True).start()
        except Exception as error:  # pragma: no cover - thread creation failure
            render_error(0, error)
        return
    if message_type == "back":
        handle_back(message)
        return
    if message_type == "navigate":
        handle_navigate(message)
        return
    # The remaining protocol messages are not needed by this plugin. Ignore
    # them safely so a newer Tabame host cannot crash the process.


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
            handle_message(message)
            if STOP_EVENT.is_set():
                break
        except json.JSONDecodeError as error:
            log("Ignoring malformed launcher message:", error)
        except Exception as error:
            log("Bitwarden plugin message failed:", error)
            render_error(0, error)
    STOP_EVENT.set()
    with PENDING_STORAGE_LOCK:
        for pending in PENDING_STORAGE.values():
            pending["event"].set()


if __name__ == "__main__":
    main()
