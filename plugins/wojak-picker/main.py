#!/usr/bin/env python3
"""Wojak Picker for the Tabame launcher.

This is a small, dependency-light port of the Raycast Wojak Picker. The
manifest is bundled for offline browsing; a refresh action can update it from
the public CDN (in memory only, for the current session). Nothing is cached
to disk: gallery thumbnails point straight at their remote URL, and copying
an image to the clipboard is delegated to Tabame's `copyImage` command,
which downloads the image host-side and places it on the clipboard.
"""

from __future__ import annotations

import json
import sys
import threading
from difflib import SequenceMatcher
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

PLUGIN_DIR = Path(__file__).resolve().parent
BUNDLED_MANIFEST = PLUGIN_DIR / "wojaks.json"
REMOTE_MANIFEST_URL = (
    "https://cdn.jsdelivr.net/gh/itsMeOnli/wojak-assets@main/wojaks.json"
)

ALL_CATEGORIES = "All Categories"
PAGE_SIZE = 100
CATEGORY_STORAGE_KEY = "selected-category"
CATEGORY_STORAGE_REQUEST = "wojak-picker:selected-category"


STATE = {
    "wojaks": [],
    "by_id": {},
    "categories": [ALL_CATEGORIES],
    "category_pools": {ALL_CATEGORIES: []},
    "category": ALL_CATEGORIES,
    "query": "",
    "visible_count": PAGE_SIZE,
    "rev": 0,
    "source": "bundled",
    "error": "",
    "search_cache": {},
    "closed": False,
}


SEND_LOCK = threading.Lock()


def log(*values):
    """Write diagnostics to stderr; stdout is reserved for protocol messages."""

    print(*values, file=sys.stderr, flush=True)


def send(message):
    """Send exactly one flushed JSON protocol message."""

    payload = json.dumps(message, ensure_ascii=False, separators=(",", ":")) + "\n"
    with SEND_LOCK:
        sys.stdout.write(payload)
        sys.stdout.flush()


def send_command(command_name, **fields):
    send({"type": "command", "command": command_name, **fields})


def normalized_text(value):
    return " ".join(str(value or "").casefold().split())


def normalize_item(raw):
    if not isinstance(raw, dict):
        return None

    def pick(*keys):
        for key in keys:
            value = raw.get(key)
            if value not in (None, ""):
                return value
        return ""

    filename = str(pick("filename", "fileName"))
    item_id = str(pick("id") or filename)
    full_url = str(pick("fullUrl", "full_url", "url"))
    thumb_url = str(pick("thumbUrl", "thumb_url", "thumbnail") or full_url)
    if not item_id or not full_url:
        return None

    name = str(pick("name") or Path(filename or item_id).stem or item_id)
    category = str(pick("category") or "Uncategorized")
    filename = filename or Path(item_id).name
    source_page_url = str(pick("sourcePageUrl", "source_page_url"))

    return {
        "id": item_id,
        "name": name,
        "category": category,
        "filename": filename,
        "thumbUrl": thumb_url,
        "fullUrl": full_url,
        "sourcePageUrl": source_page_url,
    }


def extract_items(payload):
    if isinstance(payload, list):
        raw_items = payload
    elif isinstance(payload, dict):
        raw_items = (
            payload.get("data") or payload.get("items") or payload.get("wojaks") or []
        )
    else:
        raw_items = []

    items = []
    seen = set()
    for raw in raw_items:
        item = normalize_item(raw)
        if item is None or item["id"] in seen:
            continue
        seen.add(item["id"])
        items.append(item)
    return items


def load_manifest(path):
    payload = json.loads(path.read_text(encoding="utf-8"))
    items = extract_items(payload)
    if not items:
        raise ValueError(f"No valid Wojaks found in {path.name}")
    return items


def load_initial_library():
    try:
        items = load_manifest(BUNDLED_MANIFEST)
        rebuild_library(items, "bundled")
        return
    except (OSError, ValueError, json.JSONDecodeError) as error:
        log(f"Could not load {BUNDLED_MANIFEST.name}: {error}")

    STATE["error"] = "The bundled Wojak manifest is missing or invalid."


def rebuild_library(items, source):
    category_pools = {ALL_CATEGORIES: list(items)}
    for item in items:
        category_pools.setdefault(item["category"], []).append(item)

    categories = [ALL_CATEGORIES] + sorted(
        (category for category in category_pools if category != ALL_CATEGORIES),
        key=str.casefold,
    )

    STATE.update(
        {
            "wojaks": items,
            "by_id": {item["id"]: item for item in items},
            "categories": categories,
            "category_pools": category_pools,
            "source": source,
            "search_cache": {},
            "error": "",
        }
    )
    if STATE["category"] not in categories:
        STATE["category"] = ALL_CATEGORIES


def subsequence_score(query, text):
    """Return a compactness score for characters appearing in order."""

    positions = []
    cursor = 0
    for character in query:
        position = text.find(character, cursor)
        if position < 0:
            return 0.0
        positions.append(position)
        cursor = position + 1

    if not positions:
        return 0.0
    span = positions[-1] - positions[0] + 1
    coverage = len(query) / max(len(text), 1)
    compactness = len(query) / max(span, 1)
    return min(1.0, coverage * 0.35 + compactness * 0.65)


def fuzzy_field_score(query, value):
    text = normalized_text(value)
    if not query or not text:
        return 0.0
    if text == query:
        return 1.0
    if query in text:
        start = text.find(query)
        boundary = start == 0 or text[start - 1] in " _-."
        density = len(query) / max(len(text), 1)
        return min(1.0, 0.82 + min(0.12, density * 0.12) + (0.05 if boundary else 0.0))

    scores = []
    for part in query.split():
        if part in text:
            scores.append(0.78)
            continue
        subsequence = subsequence_score(part, text)
        ratio = SequenceMatcher(None, part, text).ratio()
        scores.append(max(subsequence, ratio * 0.78))
    return sum(scores) / len(scores) if scores else 0.0


def search_library(pool, query):
    query = normalized_text(query)
    if not query:
        return list(pool)
    # Match Fuse.js's minMatchCharLength: one-character queries are not useful
    # across a four-thousand-image library.
    if len(query.replace(" ", "")) < 2:
        return []

    scored = []
    for item in pool:
        name_score = fuzzy_field_score(query, item["name"])
        category_score = fuzzy_field_score(query, item["category"])
        filename_score = fuzzy_field_score(query, item["filename"])
        score = name_score * 0.7 + category_score * 0.2 + filename_score * 0.1
        if score >= 0.22 or max(name_score, category_score, filename_score) >= 0.72:
            scored.append((score, item))

    scored.sort(
        key=lambda entry: (-entry[0], entry[1]["name"].casefold(), entry[1]["id"])
    )
    return [item for _, item in scored]


def filtered_wojaks():
    category = STATE["category"]
    query = normalized_text(STATE["query"])
    cache_key = (category, query)
    cached = STATE["search_cache"].get(cache_key)
    if cached is not None:
        return cached

    pool = STATE["category_pools"].get(category, STATE["wojaks"])
    results = search_library(pool, query)

    # Keep the Raycast extension's helpful behavior: a category-specific miss
    # falls back to the whole library instead of appearing broken.
    if query and not results and category != ALL_CATEGORIES:
        fallback_key = (ALL_CATEGORIES, query)
        results = STATE["search_cache"].get(fallback_key)
        if results is None:
            results = search_library(STATE["wojaks"], query)
            STATE["search_cache"][fallback_key] = results

    STATE["search_cache"][cache_key] = results
    return results


def item_frame(item):
    actions = [
        {"id": "copy-image", "title": "Copy Image to Clipboard", "icon": "copy"},
        {
            "id": "copy-url",
            "title": "Copy Source URL",
            "icon": "link",
            "shortcut": "ctrl+shift+c",
        },
        {
            "id": "open-image",
            "title": "Open Source Image",
            "icon": "open",
            "shortcut": "ctrl+o",
        },
    ]
    if item["sourcePageUrl"]:
        actions.append(
            {
                "id": "open-category",
                "title": "Open Category Page",
                "icon": "globe",
                "shortcut": "ctrl+shift+o",
            }
        )

    return {
        "id": item["id"],
        "title": item["name"],
        "subtitle": item["category"],
        "icon": "image",
        "accessories": [{"text": item["category"]}],
        "media": {"url": item["thumbUrl"], "type": "image"},
        "actions": actions,
    }


def base_frame(rev):
    return {
        "type": "render",
        "rev": rev,
        "view": "gallery",
        "page": {
            "id": "wojak:library",
            "title": "Wojak Picker",
            "history": "none",
            "preserveState": True,
        },
        "elementId": "wojak-results",
        "placeholder": "Search wojaks by name, filename, or category",
        "gallery": {
            "columns": 6,
            "aspectRatio": 1.0,
            "fit": "contain",
            "showLabels": True,
        },
        "toolbar": {
            "filters": [
                {
                    "id": "category",
                    "label": "Category",
                    "multiple": False,
                    "value": STATE["category"],
                    "options": STATE["categories"],
                }
            ]
        },
        "actions": [
            {
                "id": "refresh",
                "title": "Refresh Library",
                "icon": "refresh",
                "shortcut": "ctrl+r",
            }
        ],
    }


def render(rev=None, loading=False, loading_text=""):
    if rev is None:
        rev = STATE["rev"]
    else:
        STATE["rev"] = rev

    frame = base_frame(rev)
    if loading:
        frame["loading"] = True
        frame["loadingText"] = loading_text or "Refreshing Wojak library..."
        frame["items"] = []
        frame["hasMore"] = False
        send(frame)
        return

    results = filtered_wojaks()
    visible = results[: STATE["visible_count"]]
    frame["items"] = [item_frame(item) for item in visible]
    frame["hasMore"] = len(visible) < len(results)
    frame["empty"] = (
        {
            "icon": "error",
            "title": "Couldn't load Wojaks",
            "hint": STATE["error"],
        }
        if not STATE["wojaks"] and STATE["error"]
        else {
            "icon": "search",
            "title": "No Wojaks found",
            "hint": "Try a different search term or category.",
        }
    )

    send(frame)


def fetch_remote_manifest():
    request = Request(
        REMOTE_MANIFEST_URL,
        headers={"Accept": "application/json", "User-Agent": "Tabame-Wojak-Picker/1.0"},
    )
    with urlopen(request, timeout=25) as response:
        raw = response.read(20 * 1024 * 1024 + 1)
    if len(raw) > 20 * 1024 * 1024:
        raise ValueError("The remote manifest is larger than 20 MB")
    items = extract_items(json.loads(raw.decode("utf-8")))
    if not items:
        raise ValueError("The remote manifest contained no valid Wojaks")
    return items


def refresh_library():
    render(0, loading=True, loading_text="Refreshing Wojak library...")
    try:
        items = fetch_remote_manifest()
        rebuild_library(items, "remote")
        STATE["visible_count"] = PAGE_SIZE
        STATE["error"] = ""
        render(0)
        send_command(
            "toast", text=f"Library refreshed: {len(items):,} Wojaks", style="success"
        )
    except (HTTPError, URLError, OSError, ValueError, json.JSONDecodeError) as error:
        STATE["error"] = f"Refresh failed: {error}"
        log(STATE["error"])
        render(0)
        send_command("toast", text=STATE["error"], style="error")


def handle_action(message):
    item_id = str(message.get("id") or "")
    action = str(message.get("action") or "default")

    if item_id == "" and action == "refresh":
        refresh_library()
        return

    item = STATE["by_id"].get(item_id)
    if item is None:
        send_command(
            "toast",
            text="That Wojak is no longer in the current library",
            style="error",
        )
        return

    if action in {"default", "copy-image"}:
        send_command("copyImage", url=item["fullUrl"])
        send_command("toast", text=f"Copied {item['name']}", style="success")
        send_command("hide")
        return

    if action == "copy-url":
        send_command("copy", text=item["fullUrl"])
        return
    if action == "open-image":
        send_command("open", url=item["fullUrl"])
        return
    if action == "open-category" and item["sourcePageUrl"]:
        send_command("open", url=item["sourcePageUrl"])


def handle_storage(message):
    if message.get("requestId") != CATEGORY_STORAGE_REQUEST:
        return
    stored_category = message.get("value")
    if stored_category in STATE["categories"] and stored_category != STATE["category"]:
        STATE["category"] = stored_category
        STATE["visible_count"] = PAGE_SIZE
        render(0)


def handle_message(message):
    message_type = message.get("type")
    if message_type == "close":
        STATE["closed"] = True
        return False

    if message_type in {"init", "query"}:
        if message_type == "init":
            send_command(
                "storage",
                op="get",
                key=CATEGORY_STORAGE_KEY,
                requestId=CATEGORY_STORAGE_REQUEST,
            )
        STATE["query"] = str(message.get("text", message.get("query", "")) or "")
        STATE["visible_count"] = PAGE_SIZE
        render(int(message.get("rev", 0) or 0))
    elif message_type == "toolbarChange" and message.get("id") == "category":
        category = message.get("value")
        if category in STATE["categories"]:
            STATE["category"] = category
            STATE["visible_count"] = PAGE_SIZE
            send_command(
                "storage",
                op="set",
                key=CATEGORY_STORAGE_KEY,
                value=category,
            )
        render(int(message.get("rev", STATE["rev"]) or 0))
    elif message_type == "loadMore":
        results = filtered_wojaks()
        if STATE["visible_count"] < len(results):
            STATE["visible_count"] += PAGE_SIZE
        render(int(message.get("rev", STATE["rev"]) or 0))
    elif message_type == "action":
        handle_action(message)
    elif message_type == "storage":
        handle_storage(message)
    return True


def main():
    load_initial_library()
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            message = json.loads(line)
            if not isinstance(message, dict):
                raise ValueError("protocol message must be a JSON object")
            if not handle_message(message):
                return
        except json.JSONDecodeError as error:
            log(f"Ignoring malformed JSON input: {error}")
        except Exception as error:  # Keep one bad event from killing the plugin.
            log(f"Plugin event failed: {error}")
            send(
                {
                    "type": "render",
                    "rev": int(STATE.get("rev", 0) or 0),
                    "view": "detail",
                    "detail": {"markdown": f"# Wojak Picker error\n\n`{error}`"},
                }
            )


if __name__ == "__main__":
    main()
