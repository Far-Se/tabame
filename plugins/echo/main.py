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
    echo form               -> a form view (v3 fields, validation, buttons)
    echo empty              -> a custom empty state (with a call-to-action)
    echo chat               -> submit-mode input + streaming detail.append
    echo more               -> a paginated list (hasMore / loadMore)
    echo storage            -> persistent storage + background finish + notify
    Tab on a list item       -> autocompletes the query via a setQuery command
    Ctrl+K                   -> item actions + frame actions (shortcuts, confirm)
"""

import json
import sys
import threading
import time


def send(obj):
    """Write one JSON frame and flush so Tabame sees it immediately."""
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


# id -> title of the items in the last frame, so actions can resolve them.
LAST_ITEMS = {}

# Small demo state: which sub-screen owns the query line, pagination depth,
# the storage-backed counter, and a background worker handle.
STATE = {"screen": "root", "pages": 1, "counter": None}
BG_THREAD = None

# Frame-level actions (v3): available from Ctrl+K on any view, with direct
# keyboard shortcuts and a confirm-gated destructive entry.
FRAME_ACTIONS = [
    {"id": "frame:refresh", "title": "Refresh", "icon": "refresh", "shortcut": "ctrl+r"},
    {
        "id": "frame:reset",
        "title": "Reset demo counter",
        "icon": "delete",
        "destructive": True,
        "confirm": {
            "title": "Reset counter?",
            "message": "Sets the counter stored in .tabame-store.json back to zero.",
            "confirmLabel": "Reset",
        },
    },
]


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
            {"id": "copy", "title": "Copy title", "icon": "copy", "shortcut": "ctrl+shift+c"},
            {"id": "paste", "title": "Paste title", "icon": "paste"},
            {"id": "toast", "title": "Show a toast", "icon": "bell"},
            {"id": "reverse", "title": "Reverse text", "icon": "refresh"},
        ],
        "preview": preview
        if isinstance(preview, dict)
        else ({"markdown": preview} if preview else None),
    }


def render_list(text, rev, with_preview):
    words = text.split() or ["grid", "detail", "preview", "form", "empty", "chat", "more", "storage"]
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
            "placeholder": "echo <words> — try grid / detail / form / chat / more / storage",
            "preview": {"enabled": with_preview},
            "actions": FRAME_ACTIONS,
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


def render_form(rev, message_error=None):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            # Escape sends {"type":"back"} instead of exiting; we return to the list.
            "canGoBack": True,
            "actions": FRAME_ACTIONS,
            "form": {
                "title": "Echo something back",
                "submitLabel": "Echo it",
                # v3: multiple buttons; the submit message carries the pressed id.
                "buttons": [
                    {"id": "echo", "label": "Echo it"},
                    {"id": "discard", "label": "Discard", "destructive": True},
                ],
                "fields": [
                    {
                        "id": "message",
                        "type": "text",
                        "label": "Message",
                        "placeholder": "What should I echo?",
                        "required": True,
                        "description": "Required — validated by the host before submit.",
                        # Plugin-side validation: re-render the same form with an error.
                        **({"error": message_error} if message_error else {}),
                    },
                    {"id": "notes", "type": "textarea", "label": "Notes"},
                    {
                        "id": "repeat",
                        "type": "number",
                        "label": "Repeat",
                        "value": 1,
                        "min": 1,
                        "max": 5,
                        "description": "1–5 times",
                    },
                    {"id": "when", "type": "date", "label": "When"},
                    {"id": "attachment", "type": "filepicker", "label": "Attachment"},
                    {
                        "id": "voice",
                        "type": "dropdown",
                        "label": "Voice",
                        "value": "plain",
                        # v3: watch → every change sends {"type":"change"}.
                        "watch": True,
                        "options": [
                            "plain",
                            {"value": "loud", "label": "LOUD"},
                            {"value": "quiet", "label": "quiet…"},
                        ],
                    },
                    {
                        "id": "flavors",
                        "type": "tags",
                        "label": "Flavors",
                        "options": ["bold", "italic", "code", "plain"],
                        "value": ["plain"],
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
                # v3: a call-to-action; clicking sends an action with an empty id.
                "action": {"id": "empty:form", "title": "Open the form", "icon": "edit"},
            },
        }
    )


def render_chat_home(rev):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "canGoBack": True,
            # v3: submit-mode input — keystrokes stay local, Enter delivers the
            # whole line as {"type":"submitQuery"}.
            "inputMode": "submit",
            "placeholder": "Type a question and press Enter…",
            "detail": {
                "markdown": "# Chat demo\n\nType something and press **Enter** — "
                "the answer streams in via `detail.append`.\n\nEscape goes back."
            },
        }
    )


def stream_answer(prompt):
    """Streams a fake LLM answer chunk by chunk on a worker thread, so the
    stdin loop stays responsive (a real plugin would relay API tokens)."""

    def run():
        send(
            {
                "type": "render",
                "rev": 0,
                "view": "detail",
                "canGoBack": True,
                "inputMode": "submit",
                "placeholder": "Ask another question…",
                "detail": {"markdown": f"# {prompt}\n\n"},
            }
        )
        answer = (
            f"You asked about **{prompt}**. This reply arrives word by word "
            "through streaming `detail.append` frames, the way an LLM plugin "
            "would relay tokens. The view keeps itself pinned to the bottom "
            "while you are reading the end of the document. "
        ) * 3
        for word in answer.split():
            time.sleep(0.04)
            send(
                {
                    "type": "render",
                    "rev": 0,
                    "view": "detail",
                    "canGoBack": True,
                    "inputMode": "submit",
                    "detail": {"append": word + " "},
                }
            )

    threading.Thread(target=run, daemon=True).start()


PAGE_SIZE = 20
MAX_PAGES = 5


def render_more(rev):
    count = STATE["pages"] * PAGE_SIZE
    items = []
    for i in range(count):
        LAST_ITEMS[f"m{i}"] = f"Item {i + 1}"
        items.append(
            {
                "id": f"m{i}",
                "title": f"Item {i + 1}",
                "subtitle": f"page {i // PAGE_SIZE + 1}",
                "icon": "list",
                "section": f"Page {i // PAGE_SIZE + 1}",
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            # v3: scrolling near the end sends {"type":"loadMore"}.
            "hasMore": STATE["pages"] < MAX_PAGES,
            "placeholder": f"Paginated list — {STATE['pages']}/{MAX_PAGES} pages loaded",
            "items": items,
        }
    )


def render_storage(rev, select_id=None):
    counter = STATE["counter"]
    LAST_ITEMS["inc"] = "Increment counter"
    LAST_ITEMS["bg"] = "Finish in background"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "actions": FRAME_ACTIONS,
            # v3: keep the highlight where the plugin wants it after a refresh.
            **({"selectId": select_id} if select_id else {}),
            "items": [
                {
                    "id": "inc",
                    "title": f"Counter: **{counter if counter is not None else '…'}**",
                    "subtitle": "Enter increments — persisted via the `storage` command",
                    "icon": "add",
                },
                {
                    "id": "bg",
                    "title": "Finish in background + notify",
                    "subtitle": "hides the launcher, works 3s, then fires a Windows notification",
                    "icon": "bell",
                },
            ],
        }
    )


def request_counter():
    """Asks the host for the stored counter; the reply arrives as a
    {"type":"storage"} message handled in main()."""
    send({"type": "command", "command": "storage", "op": "get", "key": "counter", "requestId": "counter"})


def save_counter():
    send({"type": "command", "command": "storage", "op": "set", "key": "counter", "value": STATE["counter"]})


def handle_submit(values, button):
    if button == "discard":
        send({"type": "command", "command": "toast", "text": "Discarded", "style": "error"})
        STATE["screen"] = "root"
        handle_query("", 0)
        return
    message = values.get("message") or ""
    if message.strip().lower() == "bad":
        # Plugin-side validation demo: reject and show an inline field error.
        render_form(0, message_error='"bad" is not echo-worthy — try anything else')
        return
    voice = values.get("voice", "plain")
    if voice == "loud":
        message = message.upper() + "!!!"
    elif voice == "quiet":
        message = message.lower() + "…"
    repeat = int(values.get("repeat") or 1)
    message = " ".join([message] * max(1, min(5, repeat)))
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
                    {"label": "When", "text": str(values.get("when") or "—"), "icon": "calendar"},
                    {"label": "Flavors", "text": ", ".join(values.get("flavors") or []) or "—", "icon": "tag"},
                    {"label": "File", "text": str(values.get("attachment") or "—"), "icon": "file"},
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
    STATE["screen"] = "root"
    if stripped.startswith("grid"):
        render_grid(text, rev)
    elif stripped.startswith("detail"):
        render_detail(text, rev)
    elif stripped.startswith("form"):
        render_form(rev)
    elif stripped.startswith("empty"):
        render_empty(rev)
    elif stripped.startswith("chat"):
        STATE["screen"] = "chat"
        render_chat_home(rev)
    elif stripped.startswith("more"):
        STATE["screen"] = "more"
        render_more(rev)
    elif stripped.startswith("storage"):
        STATE["screen"] = "storage"
        render_storage(rev)
        if STATE["counter"] is None:
            request_counter()
    elif stripped.startswith("preview"):
        render_list(text[len("preview") :].strip(), rev, with_preview=True)
    else:
        render_list(text, rev, with_preview=False)


def start_background_finish():
    """Demonstrates `background` + `notify`: ask for shutdown grace, hide the
    launcher, keep working on a thread, then fire a native notification."""
    global BG_THREAD
    send({"type": "command", "command": "background", "timeout": 15})
    send({"type": "command", "command": "toast", "text": "Working in background…", "style": "progress"})
    send({"type": "command", "command": "hide"})

    def run():
        time.sleep(3)
        send(
            {
                "type": "command",
                "command": "notify",
                "title": "Echo demo",
                "text": "Background work finished 3s after the launcher closed.",
            }
        )

    BG_THREAD = threading.Thread(target=run, daemon=True)
    BG_THREAD.start()


def handle_action(msg, last_items):
    action = msg.get("action", "default")
    item_id = msg.get("id", "?")
    title = last_items.get(item_id, item_id)

    # Frame-level actions arrive with whatever item id was highlighted (or ""
    # from the empty-state button / detail views) and the action's own id.
    if action == "frame:refresh":
        send({"type": "command", "command": "toast", "text": "Refreshed", "style": "info"})
        if STATE["screen"] == "storage":
            render_storage(0)
            request_counter()
        return
    if action == "frame:reset":
        STATE["counter"] = 0
        save_counter()
        send({"type": "command", "command": "toast", "text": "Counter reset"})
        if STATE["screen"] == "storage":
            render_storage(0, select_id="inc")
        return
    if action == "empty:form":
        render_form(0)
        return

    # Storage screen items.
    if STATE["screen"] == "storage" and action == "default":
        if item_id == "inc":
            STATE["counter"] = (STATE["counter"] or 0) + 1
            save_counter()
            render_storage(0, select_id="inc")
            return
        if item_id == "bg":
            start_background_finish()
            return

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
            # Let a pending background job (see start_background_finish) finish
            # inside the grace window before exiting.
            if BG_THREAD is not None and BG_THREAD.is_alive():
                BG_THREAD.join(timeout=10)
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
            handle_submit(msg.get("values", {}), msg.get("button"))
        elif kind == "submitQuery":
            # Chat screen: Enter delivered the whole query line at once.
            if STATE["screen"] == "chat":
                stream_answer(msg.get("text", ""))
        elif kind == "loadMore":
            # Pagination: answer with a longer list (echoing the rev).
            STATE["pages"] = min(MAX_PAGES, STATE["pages"] + 1)
            render_more(msg.get("rev", 0))
        elif kind == "change":
            # A watched form field changed — a real plugin would re-render
            # dependent fields; the demo just surfaces it.
            send(
                {
                    "type": "command",
                    "command": "toast",
                    "text": f"{msg.get('id')} → {msg.get('values', {}).get(msg.get('id'))}",
                    "style": "info",
                }
            )
        elif kind == "storage":
            # Reply to our `storage get` request.
            if msg.get("requestId") == "counter":
                value = msg.get("value")
                STATE["counter"] = int(value) if isinstance(value, (int, float)) else 0
                if STATE["screen"] == "storage":
                    render_storage(0)
        elif kind == "back":
            # Escape on a canGoBack frame: return to the root list.
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
