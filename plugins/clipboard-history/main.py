#!/usr/bin/env python3
"""Clipboard History — Tabame's saved-history browser (keyword: cb)."""

import json
import sys
from pathlib import Path

PAGE_SIZE = 30
PREVIEW_LIMIT = 2500
state = {"query": "", "rev": 0, "entries": [], "has_more": False}


def send(message):
    sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def request_history(offset=0):
    send(
        {
            "type": "command",
            "command": "clipboardHistory",
            "op": "list",
            "requestId": "history",
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


def item(entry):
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
            "items": [item(entry) for entry in state["entries"]],
        }
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
            state.update(
                query=message.get("text", message.get("query", "")),
                rev=message.get("rev", 0),
                entries=[],
                has_more=False,
            )
            request_history()
        elif (
            kind == "clipboardHistory"
            and message.get("requestId") == "history"
            and message.get("op") == "list"
        ):
            entries = message.get("entries", [])
            state["entries"].extend(entries if isinstance(entries, list) else [])
            state["has_more"] = message.get("hasMore") is True
            render()
            if state["entries"]:
                send(
                    {
                        "type": "command",
                        "command": "clipboardHistory",
                        "op": "entry",
                        "requestId": "preview",
                        "id": state["entries"][0]["id"],
                    }
                )
        elif (
            kind == "clipboardHistory"
            and message.get("requestId") == "preview"
            and message.get("op") == "entry"
        ):
            full_entry = message.get("entry")
            if not isinstance(full_entry, dict):
                continue
            for index, existing in enumerate(state["entries"]):
                if existing.get("id") == full_entry.get("id"):
                    state["entries"][index] = full_entry
                    render()
                    break
        elif kind == "select":
            selected_id = message.get("id", "")
            if selected_id:
                send(
                    {
                        "type": "command",
                        "command": "clipboardHistory",
                        "op": "entry",
                        "requestId": "preview",
                        "id": selected_id,
                    }
                )
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
