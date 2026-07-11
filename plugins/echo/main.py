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
  dropped. See render() below for the full frame shape. You can also
  print {"type": "command", "command": ...} lines to have Tabame copy or
  paste text, open a URL, hide the launcher, or show a toast — see
  handle_action() below.

Try these queries after typing the `echo ` keyword in the launcher:
    echo hello              -> a plain list (sections, colored badges, progress)
    echo grid               -> a grid of color-swatch tiles (tileColor)
    echo detail             -> a full-width markdown view + metadata rows
    echo preview something   -> a list with a live preview pane (metadata + sparkline)
    echo form               -> a form view (canGoBack: Escape returns to the list)
    echo empty              -> a custom empty state
    Tab on a list item       -> autocompletes the query via a setQuery command
"""

import json
import sys


def send(obj):
    """Write one JSON frame and flush so Tabame sees it immediately."""
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


# id -> title of the items in the last frame, so actions can resolve them.
LAST_ITEMS = {}


def item(item_id, title, subtitle, icon, preview=None, accessories=None):
    LAST_ITEMS[item_id] = title
    return {
        "id": item_id,
        "title": title,
        "subtitle": subtitle,
        "icon": icon,
        "accessories": accessories or [],
        "actions": [
            {"id": "default", "title": "Open", "icon": "open"},
            {"id": "copy", "title": "Copy title", "icon": "copy"},
            {"id": "paste", "title": "Paste title", "icon": "paste"},
            {"id": "toast", "title": "Show a toast", "icon": "bell"},
            {"id": "reverse", "title": "Reverse text", "icon": "refresh"},
        ],
        "preview": preview
        if isinstance(preview, dict)
        else ({"markdown": preview} if preview else None),
    }


def render_list(text, rev, with_preview):
    words = text.split() or ["grid", "detail", "preview", "form", "empty"]
    items = []
    for i, word in enumerate(words):
        preview = {
            "markdown": f"## {word}\n\n> Live preview for `{word}` — [docs](https://example.com).",
            "metadata": [
                {"label": "Length", "text": str(len(word)), "color": "#0EA5E9"},
                {"label": "Upper", "text": word.upper(), "icon": "tag"},
                {"separator": True},
                {
                    "label": "Trend",
                    "sparkline": [len(w) for w in words] * 2,
                    "text": "chars",
                },
                {
                    "label": "Search",
                    "text": "google it",
                    "url": f"https://google.com/search?q={word}",
                },
            ],
        }
        entry = item(
            f"w{i}",
            f"**{word}**" if i == 0 else word,
            f"word #{i + 1} · `{len(word)}` chars",
            "tag",
            preview=preview,
            accessories=[
                {
                    "text": str(len(word)),
                    "color": "#8250DF" if len(word) > 4 else "#0EA5E9",
                }
            ],
        )
        entry["section"] = "Long words" if len(word) > 4 else "Short words"
        if i == 0:
            entry["progress"] = 0.6
        items.append(entry)
    # Section headers appear on value changes, so keep same-section items adjacent.
    items.sort(key=lambda it: it["section"])
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "emptyText": "Nothing to echo yet",
            "placeholder": "echo <words> — try grid / detail / form / empty",
            "preview": {"enabled": with_preview},
            "items": items,
        }
    )


def render_grid(text, rev):
    # tileColor turns each tile into a filled swatch; labels auto-contrast.
    swatches = [
        ("Sky", "#0EA5E9"),
        ("Violet", "#8250DF"),
        ("Amber", "#F59E0B"),
        ("Rose", "#F43F5E"),
        ("Emerald", "#10B981"),
        ("Slate", "#334155"),
        ("Zinc", "#E4E4E7"),
        ("Ink", "#111827"),
    ]
    items = []
    for i, (name, hex_color) in enumerate(swatches):
        entry = item(
            f"g{i}", name, hex_color, None, preview=f"### {name}\n`{hex_color}`"
        )
        entry["tileColor"] = hex_color
        items.append(entry)
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
    body = text[len("detail") :].strip() or "the detail view"
    # 'echo detail wide' → widened window + a longer document to scroll
    # (arrows / PageUp / PageDown).
    wide = body.startswith("wide")
    filler = (
        "\n\n".join(
            f"## Section {n}\n\nParagraph {n} — hold ↓ or press PageDown to scroll."
            for n in range(1, 9)
        )
        if wide
        else ""
    )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "detail": {
                "wide": wide,
                "markdown": (
                    f"# Detail view\n\n"
                    f"You are looking at **{body}** rendered as full-width markdown.\n\n"
                    f"Links are clickable: [tabame on GitHub](https://github.com/Far-Se/tabame).\n\n"
                    f"```\nType 'echo detail wide' for the widened document view.\n```"
                    + (f"\n\n{filler}" if filler else "")
                ),
                "metadata": [
                    {"label": "Status", "text": "Rendered", "color": "#10B981"},
                    {"label": "View", "text": "detail", "icon": "document"},
                    {"separator": True},
                    {
                        "label": "Spec",
                        "text": "TABAME_PLUGIN_SKILL.md",
                        "url": "https://github.com/Far-Se/tabame",
                    },
                ],
            },
        }
    )


def render_form(rev):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            # Escape sends {"type":"back"} instead of exiting; we return to the list.
            "canGoBack": True,
            "form": {
                "title": "Echo something back",
                "submitLabel": "Echo it",
                "fields": [
                    {
                        "id": "message",
                        "type": "text",
                        "label": "Message",
                        "placeholder": "What should I echo?",
                    },
                    {"id": "notes", "type": "textarea", "label": "Notes"},
                    {
                        "id": "voice",
                        "type": "dropdown",
                        "label": "Voice",
                        "value": "plain",
                        "options": [
                            "plain",
                            {"value": "loud", "label": "LOUD"},
                            {"value": "quiet", "label": "quiet…"},
                        ],
                    },
                    {
                        "id": "copy",
                        "type": "checkbox",
                        "label": "Copy result to clipboard",
                    },
                ],
            },
        }
    )


def render_empty(rev):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "items": [],
            "empty": {
                "icon": "cloud",
                "title": "Nothing here",
                "hint": "This is a custom empty state — try 'echo hello' instead",
            },
        }
    )


def handle_submit(values):
    message = values.get("message", "")
    voice = values.get("voice", "plain")
    if voice == "loud":
        message = message.upper() + "!!!"
    elif voice == "quiet":
        message = message.lower() + "…"
    if values.get("copy"):
        send({"type": "command", "command": "copy", "text": message})
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "detail": {
                "markdown": f"# Echoed\n\n> {message or '(nothing)'}",
                "metadata": [
                    {"label": "Voice", "text": str(voice), "icon": "chat"},
                    {
                        "label": "Copied",
                        "text": "yes" if values.get("copy") else "no",
                        "color": "#10B981" if values.get("copy") else "#F43F5E",
                    },
                ],
            },
        }
    )


def handle_query(text, rev):
    stripped = text.strip().lower()
    if stripped.startswith("grid"):
        render_grid(text, rev)
    elif stripped.startswith("detail"):
        render_detail(text, rev)
    elif stripped.startswith("form"):
        render_form(rev)
    elif stripped.startswith("empty"):
        render_empty(rev)
    elif stripped.startswith("preview"):
        render_list(text[len("preview") :].strip(), rev, with_preview=True)
    else:
        render_list(text, rev, with_preview=False)


def handle_action(msg, last_items):
    action = msg.get("action", "default")
    item_id = msg.get("id", "?")
    title = last_items.get(item_id, item_id)

    # Commands: ask Tabame to perform side effects instead of shelling out.
    if action == "copy":
        send({"type": "command", "command": "copy", "text": title})
        return
    if action == "paste":
        send({"type": "command", "command": "paste", "text": title})
        return
    if action == "toast":
        send(
            {"type": "command", "command": "toast", "text": f"Hello from echo: {title}"}
        )
        return

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
        if kind == "init":
            # Handshake: theme + protocol version, useful for generating
            # launcher-matching visuals. Logged to stderr as a demo.
            theme = msg.get("theme", {})
            print(
                f"init: protocol={msg.get('protocol')} accent={theme.get('accent')} dark={theme.get('dark')}",
                file=sys.stderr,
                flush=True,
            )
            handle_query(msg.get("text", msg.get("query", "")), msg.get("rev", 0))
        elif kind == "query":
            handle_query(msg.get("text", msg.get("query", "")), msg.get("rev", 0))
        elif kind == "action":
            handle_action(msg, LAST_ITEMS)
        elif kind == "submit":
            handle_submit(msg.get("values", {}))
        elif kind == "back":
            # Escape on the form (canGoBack): return to the root list.
            handle_query("", 0)
        elif kind == "tab":
            # Autocomplete: replace the query with the highlighted item's title.
            title = LAST_ITEMS.get(msg.get("id", ""))
            if title:
                send(
                    {
                        "type": "command",
                        "command": "setQuery",
                        "text": title.strip("*`"),
                    }
                )
        # "select" needs no work here — previews are supplied per-item.


if __name__ == "__main__":
    main()
