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
    echo form               -> rich v9 form sections, conditions, async combobox
    echo form legacy        -> original flat form for comparison
    echo empty              -> a custom empty state (with a call-to-action)
    echo chat               -> submit-mode input + streaming detail.append
    echo more               -> a paginated list (hasMore / loadMore)
    echo storage            -> persistent storage + background finish + notify
    echo bulk               -> multi-select + batch action IDs
    echo table              -> structured table cells
    echo tree               -> expandable tree + toggle events
    echo timeline           -> timestamped timeline rows
    echo chart              -> clickable multi-series chart
    echo operation          -> cancellable long-running operation
    echo params             -> action parameter form + confirmation gate
    echo oauth              -> host-owned OAuth callback + secret-storage pattern
    echo dashboard          -> stacked markdown + table + chart + operation panels
    echo tabs               -> the same composite result as tabs
    echo pages              -> page IDs, breadcrumbs, history, restored state
    echo kanban             -> draggable workflow cards + kanbanMove events
    echo diff               -> unified diff (add "split" for side-by-side)
    echo log                -> structured log levels, append action, wrapping
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


def event_scope(msg):
    parts = []
    for key in ("pageId", "panelId", "elementId"):
        if msg.get(key):
            parts.append(f"{key}={msg[key]}")
    return ", ".join(parts) or "legacy scope"


# id -> title of the items in the last frame, so actions can resolve them.
LAST_ITEMS = {}

# Small demo state: which sub-screen owns the query line, pagination depth,
# the storage-backed counter, and a background worker handle.
STATE = {
    "screen": "root",
    "pages": 1,
    "counter": None,
    "tree_expanded": False,
    "operation": None,
    "dashboard_sync_cancelled": False,
    "page_topic": None,
    "form_values": {},
    "form_request": 0,
    "kanban_cards": [
        {"id": "card:spec", "title": "Write protocol spec", "column": "done", "owner": "Docs"},
        {"id": "card:form", "title": "Polish rich forms", "column": "review", "owner": "UI"},
        {"id": "card:scope", "title": "Verify scoped events", "column": "doing", "owner": "Runtime"},
        {"id": "card:logs", "title": "Add log viewer demo", "column": "todo", "owner": "Echo"},
        {"id": "card:diff", "title": "Exercise split diff", "column": "todo", "owner": "QA"},
    ],
    "log_wrap": False,
    "log_lines": [
        {"id": "log:1", "timestamp": "09:41:02", "level": "info", "source": "echo", "text": "Protocol v9 demo initialized"},
        {"id": "log:2", "timestamp": "09:41:03", "level": "debug", "source": "router", "text": "Registered page and scoped-event demos"},
        {"id": "log:3", "timestamp": "09:41:04", "level": "warn", "source": "worker", "text": "This warning is intentional and demonstrates level tinting"},
        {"id": "log:4", "timestamp": "09:41:05", "level": "success", "source": "render", "text": "Kanban, diff, and log frames are ready"},
    ],
}
BG_THREAD = None

# Frame-level actions (v3): available from Ctrl+K on any view, with direct
# keyboard shortcuts and a confirm-gated destructive entry.
FRAME_ACTIONS = [
    {
        "id": "frame:refresh",
        "title": "Refresh",
        "icon": "refresh",
        "shortcut": "ctrl+r",
    },
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
            {
                "id": "copy",
                "title": "Copy title",
                "icon": "copy",
                "shortcut": "ctrl+shift+c",
            },
            {"id": "paste", "title": "Paste title", "icon": "paste"},
            {"id": "toast", "title": "Show a toast", "icon": "bell"},
            {"id": "reverse", "title": "Reverse text", "icon": "refresh"},
        ],
        "preview": preview
        if isinstance(preview, dict)
        else ({"markdown": preview} if preview else None),
    }


def render_list(text, rev, with_preview):
    words = text.split() or [
        "grid",
        "detail",
        "preview",
        "form",
        "empty",
        "chat",
        "more",
        "storage",
        "bulk",
        "table",
        "tree",
        "timeline",
        "chart",
        "operation",
        "params",
        "oauth",
        "tabs",
        "dashboard",
        "pages",
        "kanban",
        "diff",
        "log",
    ]
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
            "page": {
                "id": "echo:root",
                "title": "Echo demo",
                "history": "replace",
                "preserveState": True,
            },
            "elementId": "echo-results",
            "emptyText": "Nothing to echo yet",
            "placeholder": "Try pages / form / dashboard / kanban / diff / log",
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


PAGE_TOPICS = [
    ("navigation", "Page identity", "Stable IDs preserve selection and scroll position", "home"),
    ("breadcrumbs", "Breadcrumb navigation", "Click the Demos crumb to return here", "link"),
    ("scope", "Scoped events", "Events identify their page, panel, and element", "extension"),
    ("forms", "Rich forms", "Sections, conditions, async choices, and validation", "edit"),
    ("kanban", "Kanban", "Drag cards within and between workflow columns", "grid"),
    ("diff", "Diff", "Selectable unified and split source comparison", "code"),
    ("logs", "Logs", "Dense structured diagnostics with follow and wrap", "terminal"),
    ("state", "State restoration", "Open this item, then go back to restore the cursor", "refresh"),
    ("dashboard", "Connected panels", "Nested controls and data emit scoped events", "chart"),
    ("history", "Host history", "Escape follows the page stack before leaving", "clock"),
    ("elements", "Element identity", "Independent widgets can reuse item IDs safely", "extension"),
    ("compat", "Additive protocol", "Older plugins can ignore all v9 scope fields", "check"),
]


def render_pages(rev):
    STATE["screen"] = "pages"
    STATE["page_topic"] = None
    items = []
    for key, title, subtitle, icon in PAGE_TOPICS:
        item_id = f"page:{key}"
        LAST_ITEMS[item_id] = title
        items.append(
            {
                "id": item_id,
                "title": title,
                "subtitle": subtitle,
                "icon": icon,
                "accessories": [{"text": key, "color": "#0EA5E9"}],
                "actions": [{"id": "default", "title": "Open page", "icon": "open"}],
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": {
                "id": "pages:home",
                "title": "Protocol v9 pages",
                "history": "push",
                "preserveState": True,
            },
            "elementId": "page-topic-list",
            "canGoBack": True,
            "placeholder": "Open a topic, then Escape or click its breadcrumb",
            "items": items,
        }
    )


def render_page_topic(topic, rev=0):
    match = next((entry for entry in PAGE_TOPICS if entry[0] == topic), PAGE_TOPICS[0])
    key, title, subtitle, _ = match
    STATE["screen"] = "pages-detail"
    STATE["page_topic"] = key
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "page": {
                "id": f"pages:topic:{key}",
                "title": title,
                "history": "push",
                "preserveState": True,
                "breadcrumbs": [{"id": "pages:home", "label": "Demos"}],
            },
            "elementId": "topic-document",
            "canGoBack": True,
            "detail": {
                "markdown": (
                    f"# {title}\n\n{subtitle}.\n\n"
                    "This document has a stable page ID. Return with **Escape**, the back button, "
                    "or the **Demos** breadcrumb. The host restores the list's selection and scroll offset."
                ),
                "metadata": [
                    {"label": "Page ID", "text": f"pages:topic:{key}", "icon": "link"},
                    {"label": "Element", "text": "topic-document", "icon": "extension"},
                    {"label": "History", "text": "push", "color": "#10B981"},
                ],
            },
        }
    )


def render_legacy_form(rev, message_error=None):
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


def render_rich_form(rev, message_error=None, options_loading=False, recipient_options=None):
    if recipient_options is None:
        recipient_options = [
            {"value": "ada", "label": "Ada Lovelace"},
            {"value": "grace", "label": "Grace Hopper"},
            {"value": "margaret", "label": "Margaret Hamilton"},
            {"value": "alan", "label": "Alan Turing"},
        ]
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "page": {
                "id": "form:rich",
                "title": "Rich form",
                "history": "push",
                "preserveState": True,
                "breadcrumbs": [{"id": "pages:home", "label": "Demos"}],
            },
            "elementId": "echo-form",
            "canGoBack": True,
            "actions": FRAME_ACTIONS,
            "form": {
                "title": "Compose a protocol-v9 echo",
                **(
                    {"error": "The server rejected one value. Your other fields were preserved."}
                    if message_error
                    else {}
                ),
                "sections": [
                    {
                        "id": "content",
                        "title": "Content",
                        "description": "Required message and optional notes",
                    },
                    {
                        "id": "style",
                        "title": "Style",
                        "description": "Conditional formatting controls",
                        "collapsible": True,
                    },
                    {
                        "id": "delivery",
                        "title": "Delivery",
                        "description": "Async recipient search and scheduling",
                        "collapsible": True,
                    },
                ],
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
                        "section": "content",
                        "minLength": 3,
                        "maxLength": 60,
                        "pattern": r".*\S.*",
                        "validationMessage": "Use 3–60 non-blank characters",
                        "description": "Try 'bad' to see server validation preserve state.",
                        **({"error": message_error} if message_error else {}),
                    },
                    {
                        "id": "include_notes",
                        "type": "checkbox",
                        "label": "Add private notes",
                        "section": "content",
                    },
                    {
                        "id": "notes",
                        "type": "textarea",
                        "label": "Notes",
                        "section": "content",
                        "visibleWhen": {"field": "include_notes", "equals": True},
                    },
                    {
                        "id": "repeat",
                        "type": "number",
                        "label": "Repeat",
                        "value": 1,
                        "min": 1,
                        "max": 5,
                        "section": "style",
                        "enabledWhen": {"field": "message", "truthy": True},
                        "description": "Enabled after the message is non-empty",
                    },
                    {
                        "id": "voice",
                        "type": "dropdown",
                        "label": "Voice",
                        "value": "plain",
                        "section": "style",
                        "watch": True,
                        "options": [
                            "plain",
                            {"value": "loud", "label": "LOUD"},
                            {"value": "quiet", "label": "quiet…"},
                        ],
                    },
                    {
                        "id": "decorate",
                        "type": "checkbox",
                        "label": "Decorate the result",
                        "section": "style",
                    },
                    {
                        "id": "flavors",
                        "type": "tags",
                        "label": "Flavors",
                        "section": "style",
                        "options": ["bold", "italic", "code", "plain"],
                        "value": ["plain"],
                        "visibleWhen": {"field": "decorate", "equals": True},
                    },
                    {
                        "id": "recipient",
                        "type": "combobox",
                        "label": "Recipient",
                        "placeholder": "Type a name to search…",
                        "section": "delivery",
                        "watch": True,
                        "allowCustom": True,
                        "optionsLoading": options_loading,
                        "options": recipient_options,
                        "description": "Echo asynchronously re-renders matching choices.",
                    },
                    {
                        "id": "schedule",
                        "type": "checkbox",
                        "label": "Schedule delivery",
                        "section": "delivery",
                    },
                    {
                        "id": "when",
                        "type": "date",
                        "label": "Delivery date",
                        "section": "delivery",
                        "visibleWhen": {"field": "schedule", "equals": True},
                    },
                    {
                        "id": "attachment",
                        "type": "filepicker",
                        "label": "Attachment",
                        "section": "delivery",
                    },
                    {
                        "id": "protocol",
                        "type": "text",
                        "label": "Protocol",
                        "value": "v9 · scoped + stateful",
                        "section": "delivery",
                        "readOnly": True,
                    },
                    {
                        "id": "copy",
                        "type": "checkbox",
                        "label": "Copy result to clipboard",
                        "section": "delivery",
                    },
                ],
            },
        }
    )


def refresh_recipient_options(values):
    STATE["form_values"] = values
    STATE["form_request"] += 1
    request = STATE["form_request"]
    render_rich_form(0, options_loading=True, recipient_options=[])

    def finish():
        time.sleep(0.25)
        if STATE["screen"] != "form" or STATE["form_request"] != request:
            return
        query = str(values.get("recipient") or "").strip().lower()
        people = [
            ("ada", "Ada Lovelace"),
            ("grace", "Grace Hopper"),
            ("margaret", "Margaret Hamilton"),
            ("alan", "Alan Turing"),
            ("barbara", "Barbara Liskov"),
            ("donald", "Donald Knuth"),
        ]
        options = [
            {"value": value, "label": label}
            for value, label in people
            if not query or query in value or query in label.lower()
        ]
        render_rich_form(0, recipient_options=options)

    threading.Thread(target=finish, daemon=True).start()


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
                "action": {
                    "id": "empty:form",
                    "title": "Open the form",
                    "icon": "edit",
                },
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
    send(
        {
            "type": "command",
            "command": "storage",
            "op": "get",
            "key": "counter",
            "requestId": "counter",
        }
    )


def save_counter():
    send(
        {
            "type": "command",
            "command": "storage",
            "op": "set",
            "key": "counter",
            "value": STATE["counter"],
        }
    )


def handle_submit(values, button, msg=None):
    msg = msg or {}
    if msg.get("panelId") == "controls":
        send(
            {
                "type": "command",
                "command": "toast",
                "text": f"Panel form submitted · {event_scope(msg)}",
                "style": "success",
            }
        )
        render_dashboard(0, tabs=STATE["screen"] == "tabs")
        return
    if button == "discard":
        send(
            {
                "type": "command",
                "command": "toast",
                "text": "Discarded",
                "style": "error",
            }
        )
        STATE["screen"] = "root"
        handle_query("", 0)
        return
    message = values.get("message") or ""
    if message.strip().lower() == "bad":
        # Plugin-side validation demo: reject and show an inline field error.
        render_rich_form(0, message_error='"bad" is not echo-worthy — try anything else')
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
            "page": {
                "id": "form:result",
                "title": "Echo result",
                "history": "push",
                "breadcrumbs": [
                    {"id": "pages:home", "label": "Demos"},
                    {"id": "form:rich", "label": "Rich form"},
                ],
            },
            "elementId": "echo-result",
            "canGoBack": True,
            "detail": {
                "markdown": f"# Echoed\n\n> {message or '(nothing)'}",
                "metadata": [
                    {"label": "Voice", "text": str(voice), "icon": "chat"},
                    {
                        "label": "When",
                        "text": str(values.get("when") or "—"),
                        "icon": "calendar",
                    },
                    {
                        "label": "Flavors",
                        "text": ", ".join(values.get("flavors") or []) or "—",
                        "icon": "tag",
                    },
                    {
                        "label": "File",
                        "text": str(values.get("attachment") or "—"),
                        "icon": "file",
                    },
                    {
                        "label": "Copied",
                        "text": "yes" if values.get("copy") else "no",
                        "color": "#10B981" if values.get("copy") else "#F43F5E",
                    },
                ],
            },
        }
    )


def render_bulk(rev):
    """Protocol v7 multi-selection: Ctrl+Space or a row checkbox marks items;
    batch actions receive every marked ID in `action.ids`."""
    items = []
    for i, name in enumerate(["api", "dashboard", "worker", "docs"]):
        entry = item(f"bulk:{name}", name, "Select several, then Ctrl+K", "server")
        entry["actions"] = [
            {
                "id": "bulk:archive",
                "title": "Archive selected",
                "icon": "delete",
                "destructive": True,
                "confirm": {
                    "title": "Archive selected demos?",
                    "message": "The batch IDs are sent to Echo.",
                    "confirmLabel": "Archive",
                },
            },
        ]
        items.append(entry)
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "selection": {"enabled": True, "max": 3},
            "actions": [
                {
                    "id": "bulk:archive",
                    "title": "Archive selected",
                    "icon": "delete",
                    "destructive": True,
                    "confirm": True,
                }
            ],
            "items": items,
        }
    )


def render_table(rev):
    rows = [
        ("Build API", "Passing", "2m ago"),
        ("Deploy worker", "Running", "now"),
        ("Publish docs", "Queued", "5m ago"),
    ]
    items = []
    for i, (name, status, when) in enumerate(rows):
        LAST_ITEMS[f"table:{i}"] = name
        items.append(
            {
                "id": f"table:{i}",
                "title": name,
                "subtitle": status,
                "icon": "list",
                "cells": {"status": status, "updated": when},
                "actions": [{"id": "default", "title": "Inspect", "icon": "open"}],
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "table",
            "canGoBack": True,
            "columns": [
                {"id": "title", "label": "Job"},
                {"id": "status", "label": "Status"},
                {"id": "updated", "label": "Updated", "align": "end"},
            ],
            "items": items,
        }
    )


def render_tree(rev):
    expanded = STATE["tree_expanded"]
    items = [
        {
            "id": "tree:src",
            "title": "src",
            "subtitle": "folder",
            "icon": "folder",
            "depth": 0,
            "expanded": expanded,
        }
    ]
    if expanded:
        items.extend(
            [
                {
                    "id": "tree:main",
                    "title": "main.py",
                    "subtitle": "4.2 KB",
                    "icon": "file",
                    "depth": 1,
                },
                {
                    "id": "tree:ui",
                    "title": "ui",
                    "subtitle": "folder",
                    "icon": "folder",
                    "depth": 1,
                    "expanded": False,
                },
            ]
        )
    items.append(
        {
            "id": "tree:readme",
            "title": "README.md",
            "subtitle": "1.1 KB",
            "icon": "document",
            "depth": 0,
        }
    )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "tree",
            "canGoBack": True,
            "items": items,
        }
    )


def render_timeline(rev):
    events = [
        ("09:41", "Deployment started", "worker-42 began a staged rollout"),
        ("09:43", "Health checks passed", "p95 latency stayed below target"),
        ("09:45", "Deployment complete", "all instances are serving traffic"),
    ]
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "timeline",
            "canGoBack": True,
            "items": [
                {
                    "id": f"event:{i}",
                    "title": title,
                    "subtitle": detail,
                    "icon": "clock",
                    "timestamp": when,
                }
                for i, (when, title, detail) in enumerate(events)
            ],
        }
    )


def render_chart(rev):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "chart",
            "canGoBack": True,
            "chart": {
                "title": "API latency (ms) — click a point",
                "series": [
                    {
                        "id": "p50",
                        "label": "p50",
                        "color": "#0EA5E9",
                        "values": [34, 29, 37, 31, 28, 33, 30],
                    },
                    {
                        "id": "p95",
                        "label": "p95",
                        "color": "#F59E0B",
                        "values": [92, 88, 115, 104, 81, 98, 89],
                    },
                ],
            },
        }
    )


def render_kanban(rev):
    items = []
    for card in STATE["kanban_cards"]:
        LAST_ITEMS[card["id"]] = card["title"]
        items.append(
            {
                "id": card["id"],
                "title": card["title"],
                "subtitle": f"Owner: {card['owner']}",
                "icon": "check" if card["column"] == "done" else "note",
                "column": card["column"],
                "accessories": [{"text": card["owner"], "color": "#8250DF"}],
                "actions": [{"id": "default", "title": "Inspect card", "icon": "open"}],
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "kanban",
            "page": {
                "id": "views:kanban",
                "title": "Kanban",
                "history": "push",
                "breadcrumbs": [{"id": "pages:home", "label": "Demos"}],
            },
            "elementId": "workflow-board",
            "canGoBack": True,
            "kanban": {
                "columns": [
                    {"id": "todo", "title": "To do", "color": "#64748B", "limit": 4},
                    {"id": "doing", "title": "In progress", "color": "#0EA5E9", "limit": 3},
                    {"id": "review", "title": "Review", "color": "#F59E0B", "limit": 2},
                    {"id": "done", "title": "Done", "color": "#10B981"},
                ]
            },
            "items": items,
        }
    )


def move_kanban_card(item_id, column_id, index, scope):
    cards = STATE["kanban_cards"]
    old_index = next((i for i, card in enumerate(cards) if card["id"] == item_id), None)
    if old_index is None:
        return
    old_column = cards[old_index]["column"]
    old_column_index = [card["id"] for card in cards if card["column"] == old_column].index(item_id)
    card = cards.pop(old_index)
    if old_column == column_id and old_column_index < index:
        index -= 1
    card["column"] = column_id
    destination_indices = [i for i, candidate in enumerate(cards) if candidate["column"] == column_id]
    if index >= len(destination_indices):
        insert_at = destination_indices[-1] + 1 if destination_indices else len(cards)
    else:
        insert_at = destination_indices[max(0, index)]
    cards.insert(insert_at, card)
    send(
        {
            "type": "command",
            "command": "toast",
            "text": f"Moved {card['title']} to {column_id} · {scope}",
            "style": "success",
        }
    )
    render_kanban(0)


def render_diff(rev, split=False):
    lines = [
        {"type": "header", "text": "@@ launcher plugin protocol @@"},
        {"type": "context", "text": "  view: dashboard", "oldLine": 41, "newLine": 41},
        {"type": "remove", "text": "- protocol: 8", "oldLine": 42},
        {"type": "add", "text": "+ protocol: 9", "newLine": 42},
        {"type": "add", "text": "+ page: { id, history, breadcrumbs }", "newLine": 43},
        {"type": "add", "text": "+ scope: { pageId, panelId, elementId }", "newLine": 44},
        {"type": "context", "text": "  preserveState: true", "oldLine": 43, "newLine": 45},
    ]
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "diff",
            "page": {
                "id": "views:diff:split" if split else "views:diff:unified",
                "title": "Split diff" if split else "Unified diff",
                "history": "replace",
                "breadcrumbs": [{"id": "pages:home", "label": "Demos"}],
            },
            "elementId": "protocol-diff",
            "canGoBack": True,
            "actions": [
                {
                    "id": "diff:toggle",
                    "title": "Use unified mode" if split else "Use split mode",
                    "icon": "code",
                }
            ],
            "diff": {
                "mode": "split" if split else "unified",
                "oldLabel": "Protocol v8",
                "newLabel": "Protocol v9",
                "lines": lines,
            },
        }
    )


def render_log(rev):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "log",
            "page": {
                "id": "views:log",
                "title": "Structured log",
                "history": "push",
                "breadcrumbs": [{"id": "pages:home", "label": "Demos"}],
            },
            "elementId": "runtime-log",
            "canGoBack": True,
            "actions": [
                {"id": "log:append", "title": "Append log entry", "icon": "add"},
                {
                    "id": "log:wrap",
                    "title": "Disable wrapping" if STATE["log_wrap"] else "Enable wrapping",
                    "icon": "document",
                },
                {"id": "log:clear", "title": "Reset sample log", "icon": "refresh"},
            ],
            "log": {
                "follow": True,
                "wrap": STATE["log_wrap"],
                "lines": STATE["log_lines"],
            },
        }
    )


def append_log_line():
    index = len(STATE["log_lines"]) + 1
    levels = ["trace", "debug", "info", "warn", "error", "success"]
    level = levels[(index - 1) % len(levels)]
    STATE["log_lines"].append(
        {
            "id": f"log:{index}",
            "timestamp": time.strftime("%H:%M:%S"),
            "level": level,
            "source": "action",
            "text": f"Appended interactive line {index}; follow mode keeps the latest output visible",
        }
    )
    render_log(0)


def render_dashboard(rev, tabs=False):
    """Protocol v9 composite result with independently scoped panel events."""
    LAST_ITEMS["dash:build"] = "Build"
    LAST_ITEMS["dash:test"] = "Tests"
    panels = [
        {
            "id": "summary",
            "title": "Summary",
            "height": 180,
            "view": "detail",
            "elementId": "release-summary",
            "detail": {
                "markdown": "# Release health\n\n**All checks are green.** This markdown panel lives beside structured data.",
                "metadata": [
                    {"label": "Version", "text": "v9 demo", "color": "#10B981"},
                    {"label": "Owner", "text": "Echo"},
                ],
            },
        },
        {
            "id": "jobs",
            "title": "Jobs",
            "height": 190,
            "view": "table",
            "elementId": "release-jobs",
            "actions": [
                {"id": "dashboard:rerun", "title": "Rerun jobs", "icon": "refresh"}
            ],
            "columns": [
                {"id": "title", "label": "Job"},
                {"id": "status", "label": "Status"},
                {"id": "duration", "label": "Duration", "align": "end"},
            ],
            "items": [
                {
                    "id": "dash:build",
                    "title": "Build",
                    "cells": {"status": "Passed", "duration": "42s"},
                    "icon": "check",
                },
                {
                    "id": "dash:test",
                    "title": "Tests",
                    "cells": {"status": "Passed", "duration": "1m 18s"},
                    "icon": "check",
                },
            ],
        },
        {
            "id": "latency",
            "title": "Latency",
            "height": 230,
            "view": "chart",
            "elementId": "release-latency",
            "chart": {
                "title": "p95 latency",
                "series": [
                    {
                        "id": "p95",
                        "label": "p95",
                        "color": "#F59E0B",
                        "values": [102, 94, 88, 107, 91, 85],
                    }
                ],
            },
        },
        {
            "id": "controls",
            "title": "Release controls",
            "height": 390,
            "view": "form",
            "elementId": "release-controls",
            "form": {
                "title": "Connected panel form",
                "sections": [
                    {"id": "target", "title": "Target"},
                    {"id": "safety", "title": "Safety", "collapsible": True},
                ],
                "submitLabel": "Apply",
                "fields": [
                    {
                        "id": "channel",
                        "type": "dropdown",
                        "label": "Channel",
                        "value": "staging",
                        "watch": True,
                        "section": "target",
                        "options": ["staging", "production"],
                    },
                    {
                        "id": "freeze",
                        "type": "checkbox",
                        "label": "Enable deployment freeze",
                        "watch": True,
                        "section": "safety",
                    },
                    {
                        "id": "reason",
                        "type": "text",
                        "label": "Freeze reason",
                        "required": True,
                        "section": "safety",
                        "visibleWhen": {"field": "freeze", "equals": True},
                    },
                ],
            },
        },
    ]
    if not STATE["dashboard_sync_cancelled"]:
        panels.append(
            {
                "id": "sync",
                "title": "Background sync",
                "height": 86,
                "view": "operation",
                "elementId": "release-sync",
                "operation": {
                    "id": "dashboard:sync",
                    "title": "Syncing release notes",
                    "detail": "3 of 5 repositories complete",
                    "progress": 0.6,
                    "cancellable": True,
                },
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "dashboard",
            "page": {
                "id": "dashboard:tabs" if tabs else "dashboard:stack",
                "title": "Scoped dashboard",
                "history": "replace",
                "breadcrumbs": [{"id": "pages:home", "label": "Demos"}],
            },
            "elementId": "release-dashboard",
            "canGoBack": True,
            "dashboard": {"layout": "tabs" if tabs else "stack", "panels": panels},
        }
    )


def render_operation(rev):
    operation = STATE["operation"]
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "operation": operation,
            "items": [
                {
                    "id": "operation:start",
                    "title": "Start demo deployment",
                    "subtitle": "Shows progress updates and a cancellable operation bar",
                    "icon": "run",
                }
            ],
        }
    )


def start_operation():
    if STATE["operation"] is not None:
        return
    STATE["operation"] = {
        "id": "echo:deploy",
        "title": "Deploying Echo demo",
        "detail": "Preparing rollout",
        "progress": 0.0,
        "cancellable": True,
    }
    render_operation(0)

    def run():
        for step in range(1, 11):
            time.sleep(0.35)
            operation = STATE["operation"]
            if operation is None:
                return
            operation.update(
                {"progress": step / 10, "detail": f"Rolling out step {step}/10"}
            )
            render_operation(0)
        STATE["operation"] = None
        send(
            {
                "type": "command",
                "command": "toast",
                "text": "Demo deployment finished",
                "style": "success",
            }
        )
        render_operation(0)

    threading.Thread(target=run, daemon=True).start()


def render_params(rev):
    LAST_ITEMS["params:deploy"] = "Deploy Echo demo"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "items": [
                {
                    "id": "params:deploy",
                    "title": "Deploy Echo demo",
                    "subtitle": "Opens an action parameter form, then a confirmation",
                    "icon": "upload",
                    "actions": [
                        {
                            "id": "default",
                            "title": "Deploy…",
                            "icon": "upload",
                            "destructive": True,
                            "parameters": [
                                {
                                    "id": "environment",
                                    "type": "dropdown",
                                    "label": "Environment",
                                    "required": True,
                                    "options": ["staging", "production"],
                                },
                                {
                                    "id": "note",
                                    "type": "text",
                                    "label": "Change note",
                                    "required": True,
                                },
                            ],
                            "confirm": {
                                "title": "Deploy with these settings?",
                                "message": "This is a demo confirmation gate.",
                                "confirmLabel": "Deploy",
                            },
                        }
                    ],
                }
            ],
        }
    )


def render_oauth(rev, result=None):
    LAST_ITEMS["oauth:start"] = "Start OAuth demo"
    subtitle = "Uses Tabame's loopback callback; no token is written until a provider returns one."
    if result:
        subtitle = result
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "items": [
                {
                    "id": "oauth:start",
                    "title": "Start OAuth demo",
                    "subtitle": subtitle,
                    "icon": "lock",
                    "actions": [
                        {
                            "id": "default",
                            "title": "Authorize in browser",
                            "icon": "open",
                        }
                    ],
                }
            ],
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
        STATE["screen"] = "form"
        STATE["form_values"] = {}
        STATE["form_request"] += 1
        if "legacy" in stripped:
            render_legacy_form(rev)
        else:
            render_rich_form(rev)
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
    elif stripped.startswith("bulk"):
        STATE["screen"] = "bulk"
        render_bulk(rev)
    elif stripped.startswith("table"):
        STATE["screen"] = "table"
        render_table(rev)
    elif stripped.startswith("tree"):
        STATE["screen"] = "tree"
        render_tree(rev)
    elif stripped.startswith("timeline"):
        STATE["screen"] = "timeline"
        render_timeline(rev)
    elif stripped.startswith("chart"):
        STATE["screen"] = "chart"
        render_chart(rev)
    elif stripped.startswith("operation"):
        STATE["screen"] = "operation"
        render_operation(rev)
    elif stripped.startswith("params"):
        STATE["screen"] = "params"
        render_params(rev)
    elif stripped.startswith("oauth"):
        STATE["screen"] = "oauth"
        render_oauth(rev)
    elif stripped.startswith("dashboard"):
        STATE["screen"] = "dashboard"
        STATE["dashboard_sync_cancelled"] = False
        render_dashboard(rev)
    elif stripped.startswith("tabs"):
        STATE["screen"] = "tabs"
        STATE["dashboard_sync_cancelled"] = False
        render_dashboard(rev, tabs=True)
    elif stripped.startswith("pages"):
        render_pages(rev)
    elif stripped.startswith("kanban"):
        STATE["screen"] = "kanban"
        render_kanban(rev)
    elif stripped.startswith("diff"):
        STATE["screen"] = "diff"
        render_diff(rev, split="split" in stripped)
    elif stripped.startswith("log"):
        STATE["screen"] = "log"
        render_log(rev)
    elif stripped.startswith("preview"):
        render_list(text[len("preview") :].strip(), rev, with_preview=True)
    else:
        render_list(text, rev, with_preview=False)


def start_background_finish():
    """Demonstrates `background` + `notify`: ask for shutdown grace, hide the
    launcher, keep working on a thread, then fire a native notification."""
    global BG_THREAD
    send({"type": "command", "command": "background", "timeout": 15})
    send(
        {
            "type": "command",
            "command": "toast",
            "text": "Working in background…",
            "style": "progress",
        }
    )
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

    # Make the feature demos work with Enter as well as their explicit Ctrl+K
    # action rows.
    if action == "default" and item_id in {"params:deploy", "oauth:start"}:
        action = item_id

    # Opening a result from the root list should behave exactly like typing
    # that result after the `echo` keyword (for example, clicking "table"
    # opens the same table view as `echo table`).
    if STATE["screen"] == "root" and action == "default":
        handle_query(title.strip("*`"), 0)
        return

    if STATE["screen"] == "pages" and action == "default" and item_id.startswith("page:"):
        render_page_topic(item_id.split(":", 1)[1])
        return
    if STATE["screen"] == "kanban" and action == "default":
        send(
            {
                "type": "command",
                "command": "toast",
                "text": f"Card action · {event_scope(msg)}",
                "style": "info",
            }
        )
        return
    if STATE["screen"] == "diff" and action == "diff:toggle":
        current_page = msg.get("pageId", "")
        render_diff(0, split=not current_page.endswith(":split"))
        return
    if STATE["screen"] == "log":
        if action == "log:append":
            append_log_line()
            return
        if action == "log:wrap":
            STATE["log_wrap"] = not STATE["log_wrap"]
            render_log(0)
            return
        if action == "log:clear":
            STATE["log_lines"] = STATE["log_lines"][:4]
            render_log(0)
            return
    if STATE["screen"] in {"dashboard", "tabs"} and (
        action == "dashboard:rerun" or (action == "default" and msg.get("panelId"))
    ):
        send(
            {
                "type": "command",
                "command": "toast",
                "text": f"Dashboard event: {item_id or action} · {event_scope(msg)}",
                "style": "info",
            }
        )
        return

    # The structured demos should keep their interaction surface on screen.
    # Multi-select pointer clicks are handled by the host; Enter simply
    # reminds the user where the batch action lives.
    if STATE["screen"] == "bulk" and action == "default":
        send(
            {
                "type": "command",
                "command": "toast",
                "text": "Select rows, then use Ctrl+K → Archive selected.",
                "style": "info",
            }
        )
        return
    if STATE["screen"] == "tree" and action == "default":
        return
    if STATE["screen"] in {"table", "timeline"} and action == "default":
        send(
            {
                "type": "render",
                "rev": 0,
                "view": "detail",
                "canGoBack": True,
                "detail": {
                    "markdown": f"# {STATE['screen'].title()} selection\n\nYou selected **{title}**. Escape returns to the interactive demo."
                },
            }
        )
        return

    # Frame-level actions arrive with whatever item id was highlighted (or ""
    # from the empty-state button / detail views) and the action's own id.
    if action == "frame:refresh":
        send(
            {
                "type": "command",
                "command": "toast",
                "text": "Refreshed",
                "style": "info",
            }
        )
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
        STATE["screen"] = "form"
        render_rich_form(0)
        return

    if action == "bulk:archive":
        ids = msg.get("ids") or ([item_id] if item_id else [])
        send(
            {
                "type": "command",
                "command": "toast",
                "text": f"Batch action received {len(ids)} IDs: {', '.join(ids)}",
                "style": "info",
            }
        )
        render_bulk(0)
        return
    if action == "params:deploy":
        parameters = msg.get("parameters", {})
        send(
            {
                "type": "render",
                "rev": 0,
                "view": "detail",
                "canGoBack": True,
                "detail": {
                    "markdown": "# Parameterized action received\n\n```json\n"
                    + json.dumps(parameters, indent=2)
                    + "\n```"
                },
            }
        )
        return
    if action == "oauth:start":
        # example.com intentionally has no real provider endpoint: this is a
        # safe wire-protocol demo. Replace it with your provider's authorize URL.
        send(
            {
                "type": "command",
                "command": "oauth",
                "requestId": "echo-oauth",
                "authorizationUrl": "https://example.com/authorize?redirect_uri={redirectUri}&state=echo-demo",
            }
        )
        send(
            {
                "type": "command",
                "command": "toast",
                "text": "Browser authorization demo started",
                "style": "info",
            }
        )
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
    if (
        STATE["screen"] == "operation"
        and item_id == "operation:start"
        and action == "default"
    ):
        start_operation()
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
            handle_submit(msg.get("values", {}), msg.get("button"), msg)
        elif kind == "submitQuery":
            # Chat screen: Enter delivered the whole query line at once.
            if STATE["screen"] == "chat":
                stream_answer(msg.get("text", ""))
        elif kind == "loadMore":
            # Pagination: answer with a longer list (echoing the rev).
            STATE["pages"] = min(MAX_PAGES, STATE["pages"] + 1)
            render_more(msg.get("rev", 0))
        elif kind == "toggle":
            # Tree disclosure state remains plugin-owned; the host only reports
            # which node was toggled and the requested expansion state.
            if msg.get("id") == "tree:src":
                STATE["tree_expanded"] = bool(msg.get("expanded"))
                render_tree(msg.get("rev", 0))
        elif kind == "chartSelect":
            send(
                {
                    "type": "command",
                    "command": "toast",
                    "text": (
                        f"Chart point: {msg.get('seriesId')}[{msg.get('index')}] = {msg.get('value')}"
                        f" · {event_scope(msg)}"
                    ),
                    "style": "info",
                }
            )
        elif kind == "kanbanMove":
            if STATE["screen"] == "kanban":
                move_kanban_card(
                    msg.get("id", ""),
                    msg.get("columnId", "todo"),
                    max(0, int(msg.get("index", 0))),
                    event_scope(msg),
                )
        elif kind == "cancel":
            if msg.get("id") == "echo:deploy":
                STATE["operation"] = None
                send(
                    {
                        "type": "command",
                        "command": "toast",
                        "text": "Demo deployment cancelled",
                        "style": "error",
                    }
                )
                render_operation(0)
            elif msg.get("id") == "dashboard:sync":
                STATE["dashboard_sync_cancelled"] = True
                send(
                    {
                        "type": "command",
                        "command": "toast",
                        "text": "Dashboard sync cancelled",
                        "style": "error",
                    }
                )
                render_dashboard(0, tabs=STATE["screen"] == "tabs")
        elif kind == "oauth":
            if msg.get("requestId") == "echo-oauth":
                if msg.get("code"):
                    # Real integrations exchange this code, then persist the
                    # resulting token with storage + secret: true.
                    send(
                        {
                            "type": "command",
                            "command": "storage",
                            "op": "set",
                            "key": "oauth-token",
                            "value": "demo-token",
                            "secret": True,
                        }
                    )
                    render_oauth(0, "Callback received; demo token stored securely.")
                else:
                    render_oauth(
                        0,
                        f"OAuth callback: {msg.get('error', 'no authorization code returned')}",
                    )
        elif kind == "change":
            if STATE["screen"] == "form" and msg.get("id") == "recipient":
                refresh_recipient_options(msg.get("values", {}))
                continue
            # A watched form field changed — a real plugin would re-render
            # dependent fields; the demo just surfaces it.
            send(
                {
                    "type": "command",
                    "command": "toast",
                    "text": (
                        f"{msg.get('id')} → {msg.get('values', {}).get(msg.get('id'))}"
                        f" · {event_scope(msg)}"
                    ),
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
            target = msg.get("toPageId")
            source = msg.get("fromPageId")
            if target == "pages:home" or STATE["screen"] == "pages-detail":
                render_pages(0)
            elif target == "form:rich" or source == "form:result":
                STATE["screen"] = "form"
                render_rich_form(0)
            else:
                handle_query("", 0)
        elif kind == "navigate":
            target = msg.get("targetPageId", "")
            if target == "pages:home":
                render_pages(0)
            elif target == "form:rich":
                STATE["screen"] = "form"
                render_rich_form(0)
            elif target.startswith("pages:topic:"):
                render_page_topic(target.rsplit(":", 1)[-1])
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
