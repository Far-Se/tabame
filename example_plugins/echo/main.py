#!/usr/bin/env python3
"""Echo Demo — a reference Tabame launcher plugin.

Protocol (newline-delimited JSON on stdin/stdout):

  Tabame -> plugin (stdin), one JSON object per line:
    {"type": "init",   "query": "..."}
    {"type": "query",  "text": "...", "rev": N}      # on every keystroke
    {"type": "select", "id": "...",  "rev": N}       # highlight changed
    {"type": "action", "id": "...",  "action": "default" | "<id>"}
    {"type": "close"}

  plugin -> Tabame (stdout): print one "render" frame whenever the UI
  should change. Always echo back the latest `rev` so stale frames are
  dropped. See render() below for the full frame shape.

Try these queries after typing the `echo ` keyword in the launcher:
    echo hello              -> a plain list
    echo grid               -> a grid of tiles
    echo detail             -> a full-width markdown view
    echo preview something   -> a list with a live preview pane
"""

import json
import sys


def send(obj):
    """Write one JSON frame and flush so Tabame sees it immediately."""
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def item(item_id, title, subtitle, icon, preview=None, accessories=None):
    return {
        "id": item_id,
        "title": title,
        "subtitle": subtitle,
        "icon": icon,
        "accessories": accessories or [],
        "actions": [
            {"id": "default", "title": "Open", "icon": "open"},
            {"id": "copy", "title": "Copy title", "icon": "copy"},
            {"id": "reverse", "title": "Reverse text", "icon": "refresh"},
        ],
        "preview": {"markdown": preview} if preview else None,
    }


def render_list(text, rev, with_preview):
    words = text.split() or ["type", "something", "after", "echo"]
    items = []
    for i, word in enumerate(words):
        preview = (
            f"## {word}\n\n"
            f"- length: **{len(word)}**\n"
            f"- upper: `{word.upper()}`\n"
            f"- index: {i}\n\n"
            f"> Live preview for `{word}`."
        )
        items.append(
            item(
                f"w{i}",
                word,
                f"word #{i + 1} · {len(word)} chars",
                "tag",
                preview=preview,
                accessories=[{"text": str(len(word))}],
            )
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "emptyText": "Nothing to echo yet",
            "preview": {"enabled": with_preview},
            "items": items,
        }
    )


def render_grid(text, rev):
    swatches = [
        ("Sun", "weather", "yellow"),
        ("Cloud", "cloud", "grey"),
        ("Bolt", "bolt", "amber"),
        ("Star", "star", "gold"),
        ("Heart", "heart", "red"),
        ("Music", "music", "violet"),
        ("Code", "code", "green"),
        ("Globe", "globe", "blue"),
    ]
    items = [
        item(f"g{i}", name, colour, icon, preview=f"### {name}\nA {colour} tile.")
        for i, (name, icon, colour) in enumerate(swatches)
    ]
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "grid",
            "grid": {"columns": 4, "aspectRatio": 1.0},
            "items": items,
        }
    )


def render_detail(text, rev):
    body = text[len("detail"):].strip() or "the detail view"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "detail": {
                "markdown": (
                    f"# Detail view\n\n"
                    f"You are looking at **{body}** rendered as full-width markdown.\n\n"
                    f"## Features\n\n"
                    f"1. Lists\n2. Grids\n3. Detail\n4. Preview panes\n\n"
                    f"```\nType 'echo grid' or 'echo preview x' to switch layouts.\n```"
                )
            },
        }
    )


def handle_query(text, rev):
    stripped = text.strip().lower()
    if stripped.startswith("grid"):
        render_grid(text, rev)
    elif stripped.startswith("detail"):
        render_detail(text, rev)
    elif stripped.startswith("preview"):
        render_list(text[len("preview"):].strip(), rev, with_preview=True)
    else:
        render_list(text, rev, with_preview=False)


def handle_action(msg):
    action = msg.get("action", "default")
    item_id = msg.get("id", "?")
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "detail": {
                "markdown": (
                    f"# Action fired\n\n"
                    f"- item: `{item_id}`\n"
                    f"- action: `{action}`\n\n"
                    f"Keep typing to return to the results."
                )
            },
        }
    )


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue

        kind = msg.get("type")
        if kind == "close":
            break
        if kind in ("init", "query"):
            handle_query(msg.get("text", msg.get("query", "")), msg.get("rev", 0))
        elif kind == "action":
            handle_action(msg)
        # "select" needs no work here — previews are supplied per-item.


if __name__ == "__main__":
    main()
