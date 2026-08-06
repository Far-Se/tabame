#!/usr/bin/env python3
"""Clipboard History — Tabame's saved-history browser (keyword: cb)."""

import json
import sys
from pathlib import Path

PAGE_SIZE = 30
PREVIEW_LIMIT = 400  # the list command already returns a bounded text summary

state = {
    "query": "",
    "rev": 0,
    "entries": [],  # compact entries, in display order
    "entries_by_id": {},  # id -> compact entry, O(1) lookup
    "has_more": False,
    "item_cache": {},  # id -> already-rendered item dict (memoized)
    "history_request_id": "",
}


def send(message):
    sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def request_history(offset=0):
    send(
        {
            "type": "command",
            "command": "clipboardHistory",
            "op": "list",
            "requestId": state["history_request_id"],
            "offset": offset,
            "limit": PAGE_SIZE,
            "query": state["query"],
        }
    )


def compact_text(value, limit=52):
    value = " ".join((value or "").split())
    return value if len(value) <= limit else value[: limit - 1] + "…"


def preview_markdown(entry):
    if entry.get("type") == "image":
        image_path = entry.get("imagePath", "")
        if image_path:
            try:
                image_url = Path(image_path).resolve().as_uri()
                return f"## Image clipboard item\n\n![Clipboard image]({image_url})\n\nUse **Copy** to restore the original image."
            except (OSError, ValueError):
                pass
        return "## Image clipboard item\n\nThe cached image is unavailable. Use **Copy** to restore the original image."

    # The history list intentionally returns only a short text summary. Keep
    # the preview bounded as well: fetching the full entry on hover makes the
    # host reread and parse the entire history file for every focused item.
    text = entry.get("text", "")
    total = entry.get("textLength", len(text))

    if len(text) > PREVIEW_LIMIT:
        text = text[:PREVIEW_LIMIT] + "\n\n… Preview truncated"
    suffix = (
        "\n\n> Preview is bounded; Copy always restores the complete item."
        if total > len(text)
        else ""
    )
    return "## Clipboard preview\n\n```text\n" + text + "\n```" + suffix


def build_item(entry):
    entry_type = entry.get("type", "text")
    text = entry.get("text", "")
    total = entry.get("textLength", len(text))
    title = (
        "Image clipboard item"
        if entry_type == "image"
        else (compact_text(text) or "(empty text)")
    )
    kind = (
        "IMAGE"
        if entry_type == "image"
        else "RICH TEXT"
        if entry_type == "richText"
        else "TEXT"
    )
    return {
        "id": entry["id"],
        "title": title,
        "subtitle": f"{kind} · {total:,} chars",
        "icon": "image" if entry_type == "image" else "clipboard",
        "accessories": [{"text": "PINNED"}] if entry.get("pinned") else [],
        "actions": [
            {"id": "copy", "title": "Copy", "icon": "copy", "shortcut": "ctrl+shift+c"}
        ],
        "preview": {
            "markdown": preview_markdown(entry),
            "metadata": [
                {"label": "Type", "text": kind, "icon": "clipboard"},
                {"label": "Size", "text": f"{total:,} characters", "icon": "file"},
                {
                    "label": "Saved",
                    "text": entry.get("createdAt", "")[:19].replace("T", " "),
                    "icon": "calendar",
                },
                {
                    "label": "Action",
                    "text": "Copy the full original",
                    "actions": [{"id": "copy", "title": "Copy", "icon": "copy"}],
                },
            ],
        },
    }


def get_item(entry):
    """Return the rendered item for `entry`, memoized.

    Without this, every render() call would rebuild (and re-serialize)
    preview markdown for *every* entry currently loaded even though the
    compact entries are unchanged. That O(n) rebuild adds unnecessary work as
    the history list grows. Here we build an item once and reuse it until its
    underlying compact data changes.
    """
    eid = entry["id"]
    cached = state["item_cache"].get(eid)
    if cached is not None:
        return cached
    built = build_item(entry)
    state["item_cache"][eid] = built
    return built


def render():
    send(
        {
            "type": "render",
            "rev": state["rev"],
            "view": "list",
            "placeholder": "cb [search clipboard history]",
            "preview": {"enabled": True},
            "hasMore": state["has_more"],
            "empty": {
                "icon": "clipboard",
                "title": "No clipboard history",
                "hint": "Copy some text while Clipboard History is enabled in Tabame.",
            },
            "items": [get_item(entry) for entry in state["entries"]],
        }
    )


def reset_state(query, rev):
    state.update(
        query=query,
        rev=rev,
        entries=[],
        entries_by_id={},
        has_more=False,
        item_cache={},
        history_request_id=f"history:{rev}",
    )


def main():
    for line in sys.stdin:
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        kind = message.get("type")
        if kind == "close":
            return
        if kind in ("init", "query"):
            reset_state(
                message.get("text", message.get("query", "")),
                message.get("rev", 0),
            )
            request_history()
        elif (
            kind == "clipboardHistory"
            and message.get("requestId") == state["history_request_id"]
            and message.get("op") == "list"
        ):
            entries = message.get("entries", [])
            if isinstance(entries, list):
                for entry in entries:
                    eid = entry.get("id")
                    if eid and eid not in state["entries_by_id"]:
                        state["entries"].append(entry)
                        state["entries_by_id"][eid] = entry
            state["has_more"] = message.get("hasMore") is True
            render()
        elif kind == "select":
            # The preview is already embedded in each rendered item. Do not
            # fetch the full clipboard entry on hover: the host's full-entry
            # lookup scans the history file and would stall the launcher.
            continue
        elif kind == "loadMore" and state["has_more"]:
            state["rev"] = message.get("rev", state["rev"])
            request_history(len(state["entries"]))
        elif kind == "action" and message.get("action") in ("default", "copy"):
            send(
                {
                    "type": "command",
                    "command": "clipboardHistory",
                    "op": "copy",
                    "id": message.get("id", ""),
                }
            )


if __name__ == "__main__":
    main()
