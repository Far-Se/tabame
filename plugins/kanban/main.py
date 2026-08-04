#!/usr/bin/env python3
"""Professional, local-first Kanban workspace for the Tabame launcher."""

import copy
import datetime as dt
import json
import re
import shlex
import sys
import uuid


STORAGE_KEY = "workspace-v1"
STORAGE_REQUEST = "kanban-workspace-load"
PAGE_SIZE = 7
ACTIVITY_PAGE_SIZE = 10

PRIORITIES = {
    "urgent": ("Urgent", "#EF4444"),
    "high": ("High", "#F97316"),
    "medium": ("Medium", "#F59E0B"),
    "low": ("Low", "#3B82F6"),
    "none": ("No priority", "#64748B"),
}

BOARD_COLORS = {
    "blue": "#3B82F6",
    "violet": "#8B5CF6",
    "emerald": "#10B981",
    "amber": "#F59E0B",
    "rose": "#F43F5E",
    "slate": "#64748B",
}

TEMPLATES = {
    "standard": [
        ("backlog", "Backlog", "#64748B", None),
        ("ready", "Ready", "#3B82F6", None),
        ("doing", "In progress", "#8B5CF6", 3),
        ("review", "Review", "#F59E0B", 2),
        ("done", "Done", "#10B981", None),
    ],
    "simple": [
        ("todo", "To do", "#64748B", None),
        ("doing", "Doing", "#3B82F6", 3),
        ("done", "Done", "#10B981", None),
    ],
    "editorial": [
        ("ideas", "Ideas", "#64748B", None),
        ("drafting", "Drafting", "#3B82F6", 3),
        ("editing", "Editing", "#F59E0B", 2),
        ("scheduled", "Scheduled", "#8B5CF6", None),
        ("published", "Published", "#10B981", None),
    ],
}

STATE = {
    "loaded": False,
    "load_requested": False,
    "workspace": {"version": 1, "boards": []},
    "screen": "boards",
    "board_id": None,
    "card_id": None,
    "card_return": "board",
    "form_mode": None,
    "query": "",
    "board_pages": 1,
    "activity_pages": 1,
    "archive_pages": 1,
    "select_id": None,
}


# ---------------------------------------------------------------- protocol


def send(message):
    sys.stdout.write(json.dumps(message, ensure_ascii=False, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def log(*values):
    print(*values, file=sys.stderr, flush=True)


def command(name, **fields):
    send({"type": "command", "command": name, **fields})


def toast(text, style="success"):
    command("toast", text=text, style=style)


def new_id(prefix):
    return f"{prefix}-{uuid.uuid4().hex[:10]}"


def now_iso():
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def today_iso(offset=0):
    return (dt.date.today() + dt.timedelta(days=offset)).isoformat()


def markdown_escape(value):
    return re.sub(r"([\\`*_{}\[\]()#+.!|>~-])", r"\\\1", str(value or ""))


# ---------------------------------------------------------------- data model


def template_columns(template="standard"):
    source = TEMPLATES.get(template, TEMPLATES["standard"])
    return [
        {"id": key, "title": title, "color": color, "limit": limit}
        for key, title, color, limit in source
    ]


def default_workspace():
    board_id = "starter-board"
    cards = [
        {
            "id": "card-capture",
            "title": "Capture your next idea",
            "description": "Use **Ctrl+N** anywhere on this board to create a card.",
            "column": "backlog",
            "priority": "medium",
            "assignee": "You",
            "due": None,
            "estimate": 2,
            "tags": ["getting-started"],
        },
        {
            "id": "card-filter",
            "title": "Try a focused board filter",
            "description": "Type `priority:high`, `tag:getting-started`, or ordinary words in the launcher query.",
            "column": "ready",
            "priority": "high",
            "assignee": "You",
            "due": today_iso(1),
            "estimate": 1,
            "tags": ["getting-started"],
        },
        {
            "id": "card-details",
            "title": "Open a card for full details",
            "description": "Press **Enter** for metadata and richer actions, or **Ctrl+K** directly on the board.",
            "column": "ready",
            "priority": "medium",
            "assignee": "You",
            "due": today_iso(3),
            "estimate": 2,
            "tags": ["getting-started", "details"],
        },
        {
            "id": "card-drag",
            "title": "Drag this card to Review",
            "description": "Cards can be reordered inside a column or moved across the workflow.",
            "column": "doing",
            "priority": "urgent",
            "assignee": "You",
            "due": today_iso(),
            "estimate": 3,
            "tags": ["getting-started", "drag-drop"],
        },
        {
            "id": "card-wip",
            "title": "Keep work in progress intentional",
            "description": "Column limits are enforced when cards are dropped. Rename columns and tune limits in Board settings.",
            "column": "doing",
            "priority": "low",
            "assignee": "Unassigned",
            "due": None,
            "estimate": 3,
            "tags": ["workflow"],
        },
        {
            "id": "card-actions",
            "title": "Explore contextual actions",
            "description": "Quick-move, reprioritize, duplicate, copy, archive, or delete from **Ctrl+K**.",
            "column": "review",
            "priority": "medium",
            "assignee": "You",
            "due": today_iso(5),
            "estimate": 1,
            "tags": ["getting-started"],
        },
        {
            "id": "card-backup",
            "title": "Back up your workspace",
            "description": "Export the board or whole workspace as JSON, then import it from the clipboard later.",
            "column": "done",
            "priority": "low",
            "assignee": "You",
            "due": today_iso(-1),
            "estimate": 1,
            "tags": ["backup"],
        },
        {
            "id": "card-activity",
            "title": "Review paginated activity",
            "description": "Open Activity from **Ctrl+K**. Moves and edits are recorded automatically.",
            "column": "done",
            "priority": "none",
            "assignee": "You",
            "due": None,
            "estimate": 1,
            "tags": ["history"],
        },
    ]
    created = now_iso()
    for card in cards:
        card.update({"archived": False, "created": created, "updated": created})
    activities = []
    for index in range(15):
        card = cards[index % len(cards)]
        activities.append(
            {
                "id": f"starter-activity-{index}",
                "kind": "created" if index < len(cards) else "updated",
                "text": (
                    f"Created “{card['title']}”"
                    if index < len(cards)
                    else f"Prepared “{card['title']}” for the starter workflow"
                ),
                "cardId": card["id"],
                "at": (dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=index * 7))
                .replace(microsecond=0)
                .isoformat(),
            }
        )
    return {
        "version": 1,
        "boards": [
            {
                "id": board_id,
                "name": "Starter workspace",
                "description": "A practical walkthrough—rename it, or create a clean board from Ctrl+N.",
                "color": BOARD_COLORS["blue"],
                "columns": template_columns(),
                "cards": cards,
                "activity": activities,
                "created": created,
                "updated": created,
            }
        ],
    }


def clean_text(value, fallback="", maximum=4000):
    if not isinstance(value, str):
        return fallback
    return value.strip()[:maximum]


def clean_hex(value, fallback="#3B82F6"):
    return value.upper() if isinstance(value, str) and re.fullmatch(r"#[0-9A-Fa-f]{6}", value) else fallback


def normalize_board(raw, fallback_id=None):
    if not isinstance(raw, dict):
        return None
    board_id = clean_text(raw.get("id"), fallback_id or new_id("board"), 80)
    name = clean_text(raw.get("name"), "Untitled board", 80)
    raw_columns = raw.get("columns") if isinstance(raw.get("columns"), list) else []
    columns = []
    seen_columns = set()
    for index, value in enumerate(raw_columns):
        if not isinstance(value, dict):
            continue
        column_id = clean_text(value.get("id"), f"column-{index + 1}", 50)
        if not column_id or column_id in seen_columns:
            continue
        seen_columns.add(column_id)
        limit = value.get("limit")
        limit = int(limit) if isinstance(limit, (int, float)) and 1 <= int(limit) <= 999 else None
        columns.append(
            {
                "id": column_id,
                "title": clean_text(value.get("title"), column_id.title(), 50),
                "color": clean_hex(value.get("color"), "#64748B"),
                "limit": limit,
            }
        )
    if not columns:
        columns = template_columns()
    valid_columns = {column["id"] for column in columns}
    cards = []
    seen_cards = set()
    for value in raw.get("cards", []) if isinstance(raw.get("cards"), list) else []:
        if not isinstance(value, dict):
            continue
        card_id = clean_text(value.get("id"), new_id("card"), 80)
        if card_id in seen_cards:
            card_id = new_id("card")
        seen_cards.add(card_id)
        priority = value.get("priority") if value.get("priority") in PRIORITIES else "none"
        tags = value.get("tags") if isinstance(value.get("tags"), list) else []
        estimate = value.get("estimate")
        estimate = int(estimate) if isinstance(estimate, (int, float)) and 0 < int(estimate) <= 999 else None
        due = clean_text(value.get("due"), "", 10) or None
        try:
            if due:
                dt.date.fromisoformat(due)
        except ValueError:
            due = None
        cards.append(
            {
                "id": card_id,
                "title": clean_text(value.get("title"), "Untitled card", 140),
                "description": clean_text(value.get("description"), "", 8000),
                "column": value.get("column") if value.get("column") in valid_columns else columns[0]["id"],
                "priority": priority,
                "assignee": clean_text(value.get("assignee"), "", 80),
                "due": due,
                "estimate": estimate,
                "tags": list(dict.fromkeys(clean_text(tag, "", 40) for tag in tags if clean_text(tag, "", 40)))[:20],
                "archived": bool(value.get("archived", False)),
                "created": clean_text(value.get("created"), now_iso(), 40),
                "updated": clean_text(value.get("updated"), now_iso(), 40),
            }
        )
    activity = []
    for value in raw.get("activity", []) if isinstance(raw.get("activity"), list) else []:
        if not isinstance(value, dict):
            continue
        activity.append(
            {
                "id": clean_text(value.get("id"), new_id("activity"), 80),
                "kind": clean_text(value.get("kind"), "updated", 30),
                "text": clean_text(value.get("text"), "Board updated", 300),
                "cardId": clean_text(value.get("cardId"), "", 80) or None,
                "at": clean_text(value.get("at"), now_iso(), 40),
            }
        )
    return {
        "id": board_id,
        "name": name,
        "description": clean_text(raw.get("description"), "", 500),
        "color": clean_hex(raw.get("color")),
        "columns": columns,
        "cards": cards,
        "activity": activity[:250],
        "created": clean_text(raw.get("created"), now_iso(), 40),
        "updated": clean_text(raw.get("updated"), now_iso(), 40),
    }


def normalize_workspace(raw):
    if not isinstance(raw, dict) or not isinstance(raw.get("boards"), list):
        return None
    boards = []
    seen = set()
    for value in raw["boards"]:
        board = normalize_board(value)
        if board is None:
            continue
        if board["id"] in seen:
            board["id"] = new_id("board")
        seen.add(board["id"])
        boards.append(board)
    return {"version": 1, "boards": boards}


def boards():
    return STATE["workspace"]["boards"]


def find_board(board_id=None):
    target = board_id or STATE["board_id"]
    return next((board for board in boards() if board["id"] == target), None)


def find_card(board, card_id=None):
    if board is None:
        return None
    target = card_id or STATE["card_id"]
    return next((card for card in board["cards"] if card["id"] == target), None)


def find_column(board, column_id):
    return next((column for column in board["columns"] if column["id"] == column_id), None)


def save_workspace():
    command("storage", op="set", key=STORAGE_KEY, value=STATE["workspace"])


def touch_board(board, text, kind="updated", card=None):
    stamp = now_iso()
    board["updated"] = stamp
    if card is not None:
        card["updated"] = stamp
    board["activity"].insert(
        0,
        {
            "id": new_id("activity"),
            "kind": kind,
            "text": text,
            "cardId": card.get("id") if card else None,
            "at": stamp,
        },
    )
    del board["activity"][250:]


def clone_board(source):
    board = copy.deepcopy(source)
    board["id"] = new_id("board")
    board["name"] = f"{source['name']} copy"[:80]
    card_ids = {}
    for card in board["cards"]:
        old_id = card["id"]
        card["id"] = new_id("card")
        card_ids[old_id] = card["id"]
    for entry in board["activity"]:
        entry["id"] = new_id("activity")
        if entry.get("cardId") in card_ids:
            entry["cardId"] = card_ids[entry["cardId"]]
    stamp = now_iso()
    board["created"] = stamp
    board["updated"] = stamp
    touch_board(board, f"Duplicated from “{source['name']}”", "created")
    return board


# ---------------------------------------------------------------- formatting and filters


def format_when(value):
    try:
        instant = dt.datetime.fromisoformat(value)
        if instant.tzinfo is None:
            instant = instant.replace(tzinfo=dt.timezone.utc)
        delta = dt.datetime.now(dt.timezone.utc) - instant.astimezone(dt.timezone.utc)
        seconds = max(0, int(delta.total_seconds()))
        if seconds < 60:
            return "just now"
        if seconds < 3600:
            return f"{seconds // 60}m ago"
        if seconds < 86400:
            return f"{seconds // 3600}h ago"
        if seconds < 604800:
            return f"{seconds // 86400}d ago"
        return instant.date().strftime("%b %d, %Y")
    except (TypeError, ValueError):
        return "recently"


def due_label(card):
    if not card.get("due"):
        return None
    try:
        date = dt.date.fromisoformat(card["due"])
    except ValueError:
        return None
    difference = (date - dt.date.today()).days
    if difference < 0 and card.get("column") != "done":
        return f"Overdue {abs(difference)}d" if difference < -1 else "Overdue"
    if difference == 0:
        return "Today"
    if difference == 1:
        return "Tomorrow"
    if 1 < difference <= 7:
        return date.strftime("%a")
    return date.strftime("%b %d")


def parse_filter(text):
    try:
        tokens = shlex.split(text)
    except ValueError:
        tokens = text.split()
    filters = []
    terms = []
    for token in tokens:
        if ":" in token:
            key, value = token.split(":", 1)
            if key.lower() in {"priority", "assignee", "tag", "column", "due"} and value:
                filters.append((key.lower(), value.lower()))
                continue
        terms.append(token.lower())
    return filters, terms


def card_matches(board, card, query):
    if card.get("archived"):
        return False
    filters, terms = parse_filter(query)
    column = find_column(board, card["column"])
    haystack = " ".join(
        [
            card["title"],
            card.get("description", ""),
            card.get("assignee", ""),
            " ".join(card.get("tags", [])),
            column["title"] if column else card["column"],
        ]
    ).lower()
    if not all(term in haystack for term in terms):
        return False
    for key, value in filters:
        if key == "priority" and card.get("priority", "none") != value:
            return False
        if key == "assignee" and value not in card.get("assignee", "").lower():
            return False
        if key == "tag" and not any(value in tag.lower() for tag in card.get("tags", [])):
            return False
        if key == "column" and value not in f"{card['column']} {column['title'] if column else ''}".lower():
            return False
        if key == "due":
            due = card.get("due")
            if value == "none" and due:
                return False
            if value != "none" and not due:
                return False
            if due:
                date = dt.date.fromisoformat(due)
                days = (date - dt.date.today()).days
                if value == "overdue" and days >= 0:
                    return False
                if value == "today" and days != 0:
                    return False
                if value == "week" and not 0 <= days <= 7:
                    return False
    return True


def board_counts(board):
    active = [card for card in board["cards"] if not card.get("archived")]
    done_ids = {column["id"] for column in board["columns"] if column["id"] in {"done", "published"}}
    done = sum(card["column"] in done_ids for card in active)
    return len(active), done


def column_options(board):
    return [{"value": column["id"], "label": column["title"]} for column in board["columns"]]


def priority_options():
    return [{"value": key, "label": label} for key, (label, _) in PRIORITIES.items()]


def card_summary(board, card):
    column = find_column(board, card["column"])
    tags = " ".join(f"#{tag}" for tag in card.get("tags", []))
    lines = [f"- [ ] {card['title']}"]
    lines.append(f"  Status: {column['title'] if column else card['column']}")
    lines.append(f"  Priority: {PRIORITIES[card.get('priority', 'none')][0]}")
    if card.get("assignee"):
        lines.append(f"  Assignee: {card['assignee']}")
    if card.get("due"):
        lines.append(f"  Due: {card['due']}")
    if tags:
        lines.append(f"  Tags: {tags}")
    return "\n".join(lines)


# ---------------------------------------------------------------- rendering


def render_loading(rev):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": {"id": "kanban:boards", "title": "Kanban Workspace", "history": "push"},
            "loading": True,
            "wide": True,
            "loadingText": "Loading your workspace…",
            "items": [],
        }
    )


def request_workspace(rev):
    render_loading(rev)
    if not STATE["load_requested"]:
        STATE["load_requested"] = True
        command("storage", op="get", key=STORAGE_KEY, requestId=STORAGE_REQUEST)


def page(page_id, title, breadcrumbs=None, history="push"):
    return {
        "id": page_id,
        "title": title,
        "history": history,
        "preserveState": True,
        **({"breadcrumbs": breadcrumbs} if breadcrumbs else {}),
    }


def render_boards(rev=0):
    STATE["screen"] = "boards"
    query = STATE["query"].strip().lower()
    filtered = [
        board
        for board in sorted(boards(), key=lambda value: value.get("updated", ""), reverse=True)
        if not query or query in f"{board['name']} {board.get('description', '')}".lower()
    ]
    shown = filtered[: STATE["board_pages"] * PAGE_SIZE]
    items = []
    for board in shown:
        total, done = board_counts(board)
        archived = sum(bool(card.get("archived")) for card in board["cards"])
        progress = done / total if total else 0
        items.append(
            {
                "id": board["id"],
                "title": board["name"],
                "subtitle": board.get("description") or "No description",
                "icon": "grid",
                "lines": 2,
                "progress": progress,
                "accessories": [
                    {"text": f"{total} cards", "color": board["color"]},
                    {"text": f"{round(progress * 100)}% done", "icon": "check"},
                ],
                "actions": [
                    {"id": "default", "title": "Open board", "icon": "open"},
                    {"id": "duplicate-board", "title": "Duplicate board", "icon": "copy"},
                    {"id": "export-board", "title": "Copy board JSON", "icon": "clipboard"},
                    {
                        "id": "delete-board",
                        "title": "Delete board",
                        "icon": "trash",
                        "destructive": True,
                        "confirm": {
                            "title": f"Delete {board['name']}?",
                            "message": "The board, cards, archive, and activity will be permanently removed.",
                            "confirmLabel": "Delete board",
                        },
                    },
                ],
                "preview": {
                    "markdown": f"## {markdown_escape(board['name'])}\n\n{board.get('description') or '_No description_'}",
                    "metadata": [
                        {"label": "Active cards", "text": str(total), "icon": "note"},
                        {"label": "Completed", "text": str(done), "color": "#10B981"},
                        {"label": "Archived", "text": str(archived), "icon": "database"},
                        {"label": "Updated", "text": format_when(board.get("updated")), "icon": "clock"},
                    ],
                },
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": page("kanban:boards", "Boards"),
            "elementId": "board-index",
            "preview": {"enabled": True},
            "placeholder": "Search boards…",
            "hasMore": len(shown) < len(filtered),
            "wide": True,
            "empty": {
                "icon": "grid",
                "title": "No boards found" if query else "Create your first board",
                "hint": "Clear the search or create a board" if query else "Start with a focused workflow in seconds",
                "action": {"id": "new-board", "title": "New board", "icon": "plus"},
            },
            "actions": [
                {"id": "new-board", "title": "New board", "icon": "plus", "shortcut": "ctrl+n"},
                {"id": "import-board", "title": "Import board from clipboard", "icon": "paste"},
                {
                    "id": "import-workspace",
                    "title": "Replace workspace from clipboard",
                    "icon": "upload",
                    "destructive": True,
                    "confirm": {
                        "title": "Replace the whole workspace?",
                        "message": "Export a backup first. Valid workspace JSON on the clipboard will replace every board.",
                        "confirmLabel": "Read clipboard",
                    },
                },
                {"id": "export-workspace", "title": "Copy workspace backup", "icon": "download"},
                {"id": "help", "title": "Kanban help", "icon": "help"},
            ],
            "items": items,
        }
    )


def card_actions(board, card):
    if card.get("archived"):
        return [
            {"id": "default", "title": "Open card", "icon": "open"},
            {"id": "restore-card", "title": "Restore to board", "icon": "refresh"},
            {"id": "copy-card", "title": "Copy card summary", "icon": "copy"},
            {
                "id": "delete-card",
                "title": "Delete permanently",
                "icon": "trash",
                "destructive": True,
                "confirm": True,
            },
        ]
    actions = [
        {"id": "default", "title": "Open card", "icon": "open"},
        {"id": "edit-card", "title": "Edit card", "icon": "edit"},
        {
            "id": "move-card",
            "title": "Move to column",
            "icon": "grid",
            "parameters": [
                {
                    "id": "column",
                    "type": "dropdown",
                    "label": "Destination",
                    "required": True,
                    "value": card["column"],
                    "options": column_options(board),
                }
            ],
        },
        {
            "id": "set-priority",
            "title": "Set priority",
            "icon": "flag",
            "parameters": [
                {
                    "id": "priority",
                    "type": "dropdown",
                    "label": "Priority",
                    "required": True,
                    "value": card.get("priority", "none"),
                    "options": priority_options(),
                }
            ],
        },
        {"id": "duplicate-card", "title": "Duplicate card", "icon": "copy"},
        {"id": "copy-card", "title": "Copy card summary", "icon": "clipboard"},
    ]
    done_column = next((column for column in board["columns"] if column["id"] in {"done", "published"}), None)
    if done_column and card["column"] != done_column["id"]:
        actions.insert(
            2,
            {
                "id": "complete-card",
                "title": f"Move to {done_column['title']}",
                "icon": "check",
                "shortcut": "ctrl+enter",
            },
        )
    actions.extend(
        [
            {
                "id": "archive-card",
                "title": "Archive card",
                "icon": "database",
                "destructive": True,
                "confirm": {"title": "Archive this card?", "message": "You can restore it from Archived cards."},
            },
            {
                "id": "delete-card",
                "title": "Delete permanently",
                "icon": "trash",
                "destructive": True,
                "confirm": True,
            },
        ]
    )
    return actions


def card_item(board, card):
    priority = card.get("priority", "none")
    priority_label, priority_color = PRIORITIES[priority]
    due = due_label(card)
    subtitle_parts = []
    if card.get("assignee"):
        subtitle_parts.append(card["assignee"])
    if due:
        subtitle_parts.append(due)
    if card.get("estimate"):
        subtitle_parts.append(f"{card['estimate']} pt")
    accessories = [{"text": priority_label, "color": priority_color, "icon": "flag"}]
    if due:
        accessories.append(
            {"text": due, "color": "#EF4444" if due.startswith("Overdue") else "#64748B", "icon": "calendar"}
        )
    for tag in card.get("tags", [])[:2]:
        accessories.append({"text": tag, "icon": "tag"})
    return {
        "id": card["id"],
        "title": card["title"],
        "subtitle": " · ".join(subtitle_parts) or "Unassigned",
        "icon": "check" if card["column"] in {"done", "published"} else "note",
        "column": card["column"],
        "accessories": accessories,
        "actions": card_actions(board, card),
    }


def render_board(rev=0, history="push"):
    STATE["screen"] = "board"
    board = find_board()
    if board is None:
        STATE["screen"] = "boards"
        STATE["board_id"] = None
        render_boards(rev)
        return
    visible = [card for card in board["cards"] if card_matches(board, card, STATE["query"])]
    select_id = STATE.pop("select_id", None)
    payload = {
        "type": "render",
        "rev": rev,
        "view": "kanban",
        "page": page(
            f"kanban:board:{board['id']}",
            board["name"],
            [{"id": "kanban:boards", "label": "Boards"}],
            history,
        ),
        "wide": True,
        "elementId": "kanban-board",
        "canGoBack": True,
        "placeholder": "Filter cards · priority:high  tag:bug  due:week…",
        "empty": {
            "icon": "search" if STATE["query"] else "note",
            "title": "No matching cards" if STATE["query"] else "This board is ready",
            "hint": "Try fewer filters" if STATE["query"] else "Create the first card with Ctrl+N",
            "action": {"id": "clear-filter" if STATE["query"] else "new-card", "title": "Clear filter" if STATE["query"] else "New card", "icon": "refresh" if STATE["query"] else "plus"},
        },
        "kanban": {
            "columns": [
                {key: value for key, value in column.items() if value is not None}
                for column in board["columns"]
            ]
        },
        "actions": [
            {"id": "new-card", "title": "New card", "icon": "plus", "shortcut": "ctrl+n"},
            {"id": "activity", "title": "Activity", "icon": "clock"},
            {"id": "archive", "title": "Archived cards", "icon": "database"},
            {"id": "board-settings", "title": "Board settings", "icon": "settings"},
            {"id": "export-board", "title": "Copy board JSON", "icon": "download"},
            {"id": "clear-filter", "title": "Clear filter", "icon": "refresh"},
            {
                "id": "archive-completed",
                "title": "Archive completed cards",
                "icon": "database",
                "destructive": True,
                "confirm": {"title": "Archive completed cards?", "message": "They remain available in Archived cards."},
            },
        ],
        "items": [card_item(board, card) for card in visible],
    }
    if select_id:
        payload["selectId"] = select_id
    send(payload)


def render_card_detail(rev=0):
    STATE["screen"] = "card"
    board = find_board()
    card = find_card(board)
    if card is None:
        render_board(rev)
        return
    column = find_column(board, card["column"])
    priority_label, priority_color = PRIORITIES[card.get("priority", "none")]
    breadcrumbs = [
        {"id": "kanban:boards", "label": "Boards"},
        {"id": f"kanban:board:{board['id']}", "label": board["name"]},
    ]
    if STATE["card_return"] == "archive":
        breadcrumbs.append({"id": f"kanban:archive:{board['id']}", "label": "Archived"})
    elif STATE["card_return"] == "activity":
        breadcrumbs.append({"id": f"kanban:activity:{board['id']}", "label": "Activity"})
    body = card.get("description") or "_No description yet._"
    tags = " ".join(f"`#{markdown_escape(tag)}`" for tag in card.get("tags", []))
    if tags:
        body += f"\n\n{tags}"
    metadata = [
        {"label": "Status", "text": column["title"] if column else card["column"], "color": column["color"] if column else board["color"]},
        {"label": "Priority", "text": priority_label, "color": priority_color},
        {"label": "Assignee", "text": card.get("assignee") or "Unassigned", "icon": "person"},
        {"label": "Due", "text": card.get("due") or "No due date", "icon": "calendar"},
        {"label": "Estimate", "text": f"{card['estimate']} points" if card.get("estimate") else "Not estimated", "icon": "timer"},
        {"separator": True},
        {"label": "Created", "text": format_when(card.get("created")), "icon": "clock"},
        {"label": "Updated", "text": format_when(card.get("updated")), "icon": "refresh"},
    ]
    actions = [{key: value for key, value in action.items() if key != "default"} for action in card_actions(board, card) if action["id"] != "default"]
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "page": page(
                f"kanban:card:{board['id']}:{card['id']}",
                card["title"],
                breadcrumbs,
            ),
            "elementId": "card-detail",
            "canGoBack": True,
            "wide": True,
            "placeholder": "Card details",
            "detail": {"markdown": f"# {markdown_escape(card['title'])}\n\n{body}", "metadata": metadata, "wide": True},
            "actions": actions,
        }
    )


def activity_icon(kind):
    return {
        "created": "plus",
        "moved": "grid",
        "updated": "edit",
        "archived": "database",
        "restored": "refresh",
        "deleted": "trash",
        "duplicated": "copy",
    }.get(kind, "clock")


def render_activity(rev=0):
    STATE["screen"] = "activity"
    board = find_board()
    if board is None:
        render_boards(rev)
        return
    query = STATE["query"].strip().lower()
    filtered = [entry for entry in board["activity"] if not query or query in entry["text"].lower()]
    shown = filtered[: STATE["activity_pages"] * ACTIVITY_PAGE_SIZE]
    items = []
    for entry in shown:
        card = find_card(board, entry.get("cardId"))
        item = {
            "id": f"activity:{entry['id']}",
            "title": entry["text"],
            "subtitle": format_when(entry.get("at")),
            "icon": activity_icon(entry.get("kind")),
            "accessories": [{"text": entry.get("kind", "updated").title()}],
        }
        if card:
            item["actions"] = [{"id": "default", "title": "Open related card", "icon": "open"}]
        items.append(item)
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": page(
                f"kanban:activity:{board['id']}",
                "Activity",
                [
                    {"id": "kanban:boards", "label": "Boards"},
                    {"id": f"kanban:board:{board['id']}", "label": board["name"]},
                ],
            ),
            "wide": True,
            "elementId": "activity-list",
            "canGoBack": True,
            "placeholder": "Search activity…",
            "hasMore": len(shown) < len(filtered),
            "empty": {"icon": "clock", "title": "No activity found", "hint": "Board changes will appear here"},
            "actions": [
                {"id": "export-activity", "title": "Copy activity JSON", "icon": "copy"},
                {
                    "id": "clear-activity",
                    "title": "Clear activity",
                    "icon": "trash",
                    "destructive": True,
                    "confirm": True,
                },
            ],
            "items": items,
        }
    )


def render_archive(rev=0):
    STATE["screen"] = "archive"
    board = find_board()
    if board is None:
        render_boards(rev)
        return
    query = STATE["query"].strip().lower()
    archived = [
        card
        for card in board["cards"]
        if card.get("archived") and (not query or query in f"{card['title']} {card.get('description', '')}".lower())
    ]
    shown = archived[: STATE["archive_pages"] * PAGE_SIZE]
    items = []
    for card in shown:
        priority_label, priority_color = PRIORITIES[card.get("priority", "none")]
        items.append(
            {
                "id": card["id"],
                "title": card["title"],
                "subtitle": f"Archived · updated {format_when(card.get('updated'))}",
                "icon": "database",
                "accessories": [{"text": priority_label, "color": priority_color}],
                "actions": card_actions(board, card),
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": page(
                f"kanban:archive:{board['id']}",
                "Archived cards",
                [
                    {"id": "kanban:boards", "label": "Boards"},
                    {"id": f"kanban:board:{board['id']}", "label": board["name"]},
                ],
            ),
            "wide": True,
            "elementId": "archive-list",
            "canGoBack": True,
            "placeholder": "Search archived cards…",
            "hasMore": len(shown) < len(archived),
            "empty": {"icon": "database", "title": "Archive is empty", "hint": "Archived cards stay recoverable here"},
            "items": items,
        }
    )


def render_board_form(rev=0):
    STATE["screen"] = "board-form"
    editing = STATE["form_mode"] == "edit-board"
    board = find_board() if editing else None
    fields = [
        {
            "id": "name",
            "type": "text",
            "label": "Board name",
            "value": board["name"] if board else "",
            "placeholder": "Product launch",
            "required": True,
            "maxLength": 80,
        },
        {
            "id": "description",
            "type": "textarea",
            "label": "Description",
            "value": board.get("description", "") if board else "",
            "placeholder": "What outcome does this board support?",
            "maxLength": 500,
        },
        {
            "id": "color",
            "type": "dropdown",
            "label": "Accent",
            "value": next((name for name, color in BOARD_COLORS.items() if board and board["color"] == color), "blue"),
            "options": [{"value": name, "label": name.title()} for name in BOARD_COLORS],
        },
    ]
    sections = [{"id": "board", "title": "Board", "description": "Name and visual identity"}]
    for field in fields:
        field["section"] = "board"
    if not editing:
        fields.append(
            {
                "id": "template",
                "type": "dropdown",
                "label": "Workflow template",
                "value": "standard",
                "section": "workflow",
                "options": [
                    {"value": "standard", "label": "Standard · Backlog to Done"},
                    {"value": "simple", "label": "Simple · To do / Doing / Done"},
                    {"value": "editorial", "label": "Editorial · Ideas to Published"},
                ],
            }
        )
        sections.append({"id": "workflow", "title": "Workflow", "description": "Choose a starting column set"})
    else:
        sections.append(
            {
                "id": "columns",
                "title": "Columns & WIP limits",
                "description": "Leave a limit empty for unlimited work",
                "collapsible": True,
            }
        )
        for column in board["columns"]:
            fields.extend(
                [
                    {
                        "id": f"column-title:{column['id']}",
                        "type": "text",
                        "label": f"{column['title']} name",
                        "value": column["title"],
                        "required": True,
                        "maxLength": 50,
                        "section": "columns",
                    },
                    {
                        "id": f"column-limit:{column['id']}",
                        "type": "number",
                        "label": f"{column['title']} WIP limit",
                        "value": column.get("limit"),
                        "min": 1,
                        "max": 999,
                        "section": "columns",
                    },
                ]
            )
    breadcrumbs = [{"id": "kanban:boards", "label": "Boards"}]
    if board:
        breadcrumbs.append({"id": f"kanban:board:{board['id']}", "label": board["name"]})
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "page": page(
                f"kanban:board-form:{board['id'] if board else 'new'}",
                "Board settings" if editing else "New board",
                breadcrumbs,
            ),
            "wide": True,
            "elementId": "board-form",
            "canGoBack": True,
            "form": {
                "title": "Board settings" if editing else "Create a board",
                "sections": sections,
                "submitLabel": "Save changes" if editing else "Create board",
                "fields": fields,
            },
        }
    )


def render_card_form(rev=0):
    STATE["screen"] = "card-form"
    board = find_board()
    editing = STATE["form_mode"] == "edit-card"
    card = find_card(board) if editing else None
    if board is None:
        render_boards(rev)
        return
    existing_tags = sorted({tag for value in board["cards"] for tag in value.get("tags", [])})
    default_column = board["columns"][0]["id"]
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "page": page(
                f"kanban:card-form:{board['id']}:{card['id'] if card else 'new'}",
                "Edit card" if editing else "New card",
                [
                    {"id": "kanban:boards", "label": "Boards"},
                    {"id": f"kanban:board:{board['id']}", "label": board["name"]},
                    *(
                        [{"id": f"kanban:card:{board['id']}:{card['id']}", "label": card["title"]}]
                        if card
                        else []
                    ),
                ],
            ),
            "wide": True,
            "elementId": "card-form",
            "canGoBack": True,
            "form": {
                "title": "Edit card" if editing else "Create a card",
                "sections": [
                    {"id": "work", "title": "Work", "description": "What needs to happen?"},
                    {"id": "planning", "title": "Planning", "description": "Ownership, timing, and sizing"},
                ],
                "submitLabel": "Save changes" if editing else "Create card",
                "fields": [
                    {
                        "id": "title",
                        "type": "text",
                        "label": "Title",
                        "value": card["title"] if card else "",
                        "placeholder": "Clear, outcome-oriented summary",
                        "required": True,
                        "maxLength": 140,
                        "section": "work",
                    },
                    {
                        "id": "description",
                        "type": "textarea",
                        "label": "Description (Markdown)",
                        "value": card.get("description", "") if card else "",
                        "placeholder": "Context, acceptance criteria, links…",
                        "maxLength": 8000,
                        "section": "work",
                    },
                    {
                        "id": "column",
                        "type": "dropdown",
                        "label": "Column",
                        "value": card["column"] if card else default_column,
                        "required": True,
                        "options": column_options(board),
                        "section": "planning",
                    },
                    {
                        "id": "priority",
                        "type": "dropdown",
                        "label": "Priority",
                        "value": card.get("priority", "none") if card else "none",
                        "options": priority_options(),
                        "section": "planning",
                    },
                    {
                        "id": "assignee",
                        "type": "text",
                        "label": "Assignee",
                        "value": card.get("assignee", "") if card else "",
                        "placeholder": "Name or team",
                        "maxLength": 80,
                        "section": "planning",
                    },
                    {
                        "id": "due",
                        "type": "date",
                        "label": "Due date",
                        "value": card.get("due") if card else None,
                        "section": "planning",
                    },
                    {
                        "id": "estimate",
                        "type": "number",
                        "label": "Estimate (points)",
                        "value": card.get("estimate") if card else None,
                        "min": 1,
                        "max": 999,
                        "section": "planning",
                    },
                    {
                        "id": "tags",
                        "type": "tags",
                        "label": "Tags",
                        "value": card.get("tags", []) if card else [],
                        "options": existing_tags,
                        "section": "planning",
                    },
                ],
            },
        }
    )


def render_help(rev=0):
    STATE["screen"] = "help"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "page": page("kanban:help", "Help", [{"id": "kanban:boards", "label": "Boards"}]),
            "elementId": "kanban-help",
            "canGoBack": True,
            "wide": True,
            "detail": {
                "wide": True,
                "markdown": (
                    "# Kanban Workspace\n\n"
                    "A focused, keyboard-friendly project space that stays local to Tabame.\n\n"
                    "## Fast workflow\n\n"
                    "- Press **Ctrl+N** to create a board or card.\n"
                    "- Drag cards to reorder or move them. WIP-limited columns reject overflow.\n"
                    "- Press **Enter** for details and **Ctrl+K** for contextual actions.\n"
                    "- Use **Escape**, the back button, or breadcrumbs to navigate.\n\n"
                    "## Board filters\n\n"
                    "Combine ordinary words with structured filters:\n\n"
                    "```text\npriority:urgent\nassignee:alex\ntag:bug\ncolumn:review\ndue:overdue\ndue:today\ndue:week\n```\n\n"
                    "Quoted phrases work too: `assignee:\"Design team\" checkout`.\n\n"
                    "## Safety and portability\n\n"
                    "Archive is recoverable; permanent deletion is confirmed. Export board or workspace JSON from Ctrl+K for backups, and import it from the board index."
                ),
                "metadata": [
                    {"label": "Persistence", "text": "Tabame plugin storage", "icon": "database"},
                    {"label": "Network", "text": "None", "color": "#10B981"},
                    {"label": "Runtime", "text": "Python · no dependencies", "icon": "code"},
                ],
            },
            "actions": [{"id": "new-board", "title": "Create a board", "icon": "plus", "shortcut": "ctrl+n"}],
        }
    )


def render_current(rev=0):
    if not STATE["loaded"]:
        request_workspace(rev)
        return
    screen = STATE["screen"]
    if screen == "boards":
        render_boards(rev)
    elif screen == "board":
        render_board(rev)
    elif screen == "card":
        render_card_detail(rev)
    elif screen == "activity":
        render_activity(rev)
    elif screen == "archive":
        render_archive(rev)
    elif screen == "board-form":
        render_board_form(rev)
    elif screen == "card-form":
        render_card_form(rev)
    elif screen == "help":
        render_help(rev)
    else:
        STATE["screen"] = "boards"
        render_boards(rev)


def navigate(screen, board_id=None, card_id=None, card_return=None):
    had_query = bool(STATE["query"])
    STATE["screen"] = screen
    if board_id is not None:
        STATE["board_id"] = board_id
    if card_id is not None:
        STATE["card_id"] = card_id
    if card_return is not None:
        STATE["card_return"] = card_return
    STATE["query"] = ""
    render_current(0)
    if had_query:
        command("setQuery", text="")


# ---------------------------------------------------------------- mutations and actions


def can_enter_column(board, card, column_id):
    column = find_column(board, column_id)
    if column is None:
        return False, "That column no longer exists"
    is_existing_card = any(other is card or other["id"] == card["id"] for other in board["cards"])
    if (is_existing_card and card["column"] == column_id) or column.get("limit") is None:
        return True, None
    count = sum(
        other["column"] == column_id and not other.get("archived") and other["id"] != card["id"]
        for other in board["cards"]
    )
    if count >= column["limit"]:
        return False, f"{column['title']} is at its WIP limit ({column['limit']})"
    return True, None


def move_card(board, card, column_id, index=None, visible_ids=None):
    allowed, reason = can_enter_column(board, card, column_id)
    if not allowed:
        toast(reason, "error")
        return False
    old_column = card["column"]
    old_title = find_column(board, old_column)
    new_title = find_column(board, column_id)
    old_visible_index = None
    if visible_ids and card["id"] in visible_ids:
        old_visible_index = [
            card_id
            for card_id in visible_ids
            if (find_card(board, card_id) or {}).get("column") == old_column
        ].index(card["id"])
    board["cards"].remove(card)
    card["column"] = column_id
    destination = [
        value
        for value in board["cards"]
        if value["column"] == column_id
        and not value.get("archived")
        and (visible_ids is None or value["id"] in visible_ids)
    ]
    if index is None:
        index = len(destination)
    if old_column == column_id and old_visible_index is not None and old_visible_index < index:
        index -= 1
    index = max(0, int(index))
    if destination and index < len(destination):
        insert_at = board["cards"].index(destination[index])
    elif destination:
        insert_at = board["cards"].index(destination[-1]) + 1
    else:
        all_target = [value for value in board["cards"] if value["column"] == column_id]
        insert_at = board["cards"].index(all_target[-1]) + 1 if all_target else len(board["cards"])
    board["cards"].insert(insert_at, card)
    if old_column != column_id:
        touch_board(
            board,
            f"Moved “{card['title']}” from {old_title['title'] if old_title else old_column} to {new_title['title']}",
            "moved",
            card,
        )
    else:
        touch_board(board, f"Reordered “{card['title']}” in {new_title['title']}", "moved", card)
    save_workspace()
    STATE["select_id"] = card["id"]
    return True


def export_board(board):
    command(
        "copy",
        text=json.dumps({"format": "tabame-kanban-board-v1", "board": board}, ensure_ascii=False, indent=2),
    )


def export_workspace():
    command(
        "copy",
        text=json.dumps(
            {"format": "tabame-kanban-workspace-v1", "workspace": STATE["workspace"]},
            ensure_ascii=False,
            indent=2,
        ),
    )


def handle_board_index_action(item_id, action):
    board = find_board(item_id) if item_id else None
    if action == "new-board":
        STATE["form_mode"] = "new-board"
        navigate("board-form")
    elif action == "help":
        navigate("help")
    elif action == "export-workspace":
        export_workspace()
    elif action == "import-workspace":
        command("clipboardRead", requestId="kanban-import-workspace")
    elif action == "import-board":
        command("clipboardRead", requestId="kanban-import-board")
    elif board and action in {"default", "open-board"}:
        navigate("board", board_id=board["id"])
    elif board and action == "duplicate-board":
        duplicate = clone_board(board)
        boards().insert(0, duplicate)
        save_workspace()
        STATE["board_id"] = duplicate["id"]
        navigate("board")
        toast("Board duplicated")
    elif board and action == "export-board":
        export_board(board)
    elif board and action == "delete-board":
        boards().remove(board)
        save_workspace()
        render_boards(0)
        toast("Board deleted")


def resolve_activity_card(board, activity_item_id):
    activity_id = activity_item_id.split(":", 1)[-1]
    entry = next((value for value in board["activity"] if value["id"] == activity_id), None)
    return find_card(board, entry.get("cardId")) if entry else None


def handle_card_action(board, card, action, parameters=None):
    parameters = parameters if isinstance(parameters, dict) else {}
    origin_screen = STATE["screen"]
    if action in {"default", "open-card"}:
        navigate("card", card_id=card["id"], card_return=STATE["screen"] if STATE["screen"] in {"archive", "activity"} else "board")
        return
    if action == "edit-card" and not card.get("archived"):
        STATE["card_id"] = card["id"]
        STATE["form_mode"] = "edit-card"
        navigate("card-form")
        return
    if action == "copy-card":
        command("copy", text=card_summary(board, card))
        return
    if action == "move-card":
        destination = parameters.get("column")
        if destination and move_card(board, card, destination):
            render_card_detail(0) if origin_screen == "card" else render_board(0)
            toast(f"Moved to {find_column(board, destination)['title']}")
        return
    if action == "complete-card":
        destination = next((value for value in board["columns"] if value["id"] in {"done", "published"}), None)
        if destination and move_card(board, card, destination["id"]):
            render_card_detail(0) if origin_screen == "card" else render_board(0)
            toast(f"Moved to {destination['title']}")
        return
    if action == "set-priority":
        priority = parameters.get("priority")
        if priority in PRIORITIES:
            card["priority"] = priority
            touch_board(board, f"Set “{card['title']}” priority to {PRIORITIES[priority][0]}", "updated", card)
            save_workspace()
            render_current(0)
            toast("Priority updated")
        return
    if action == "duplicate-card":
        duplicate = copy.deepcopy(card)
        duplicate["id"] = new_id("card")
        duplicate["title"] = f"{card['title']} copy"[:140]
        duplicate["archived"] = False
        duplicate["created"] = now_iso()
        duplicate["updated"] = duplicate["created"]
        board["cards"].insert(board["cards"].index(card) + 1, duplicate)
        touch_board(board, f"Duplicated “{card['title']}”", "duplicated", duplicate)
        save_workspace()
        STATE["select_id"] = duplicate["id"]
        render_board(0)
        toast("Card duplicated")
        return
    if action == "archive-card":
        card["archived"] = True
        touch_board(board, f"Archived “{card['title']}”", "archived", card)
        save_workspace()
        if STATE["screen"] == "card":
            navigate("archive", card_return="archive")
        else:
            render_current(0)
        toast("Card archived")
        return
    if action == "restore-card":
        card["archived"] = False
        touch_board(board, f"Restored “{card['title']}”", "restored", card)
        save_workspace()
        STATE["select_id"] = card["id"]
        navigate("board", card_return="board")
        toast("Card restored")
        return
    if action == "delete-card":
        title = card["title"]
        board["cards"].remove(card)
        touch_board(board, f"Deleted “{title}”", "deleted")
        save_workspace()
        if STATE["screen"] == "card":
            navigate("archive" if STATE["card_return"] == "archive" else "board")
        else:
            render_current(0)
        toast("Card permanently deleted")


def handle_board_action(item_id, action, parameters):
    board = find_board()
    if board is None:
        navigate("boards")
        return
    card = find_card(board, item_id) if item_id else find_card(board)
    if item_id and card:
        handle_card_action(board, card, action, parameters)
        return
    if action == "new-card":
        STATE["form_mode"] = "new-card"
        STATE["card_id"] = None
        navigate("card-form")
    elif action == "activity":
        STATE["activity_pages"] = 1
        navigate("activity")
    elif action == "archive":
        STATE["archive_pages"] = 1
        navigate("archive")
    elif action == "board-settings":
        STATE["form_mode"] = "edit-board"
        navigate("board-form")
    elif action == "export-board":
        export_board(board)
    elif action == "clear-filter":
        STATE["query"] = ""
        command("setQuery", text="")
        render_board(0)
    elif action == "archive-completed":
        done_ids = {column["id"] for column in board["columns"] if column["id"] in {"done", "published"}}
        completed = [card for card in board["cards"] if not card.get("archived") and card["column"] in done_ids]
        for value in completed:
            value["archived"] = True
        if completed:
            touch_board(board, f"Archived {len(completed)} completed card{'s' if len(completed) != 1 else ''}", "archived")
            save_workspace()
            render_board(0)
            toast(f"Archived {len(completed)} completed card{'s' if len(completed) != 1 else ''}")
        else:
            toast("No completed cards to archive", "info")


def handle_action(message):
    item_id = message.get("id", "")
    action = message.get("action", "default")
    parameters = message.get("parameters", {})
    screen = STATE["screen"]
    if screen in {"boards", "help"}:
        handle_board_index_action(item_id, action)
    elif screen == "board":
        handle_board_action(item_id, action, parameters)
    elif screen == "card":
        board = find_board()
        card = find_card(board)
        if card:
            handle_card_action(board, card, action, parameters)
    elif screen == "activity":
        board = find_board()
        if action == "default" and item_id:
            card = resolve_activity_card(board, item_id)
            if card:
                navigate("card", card_id=card["id"], card_return="activity")
        elif action == "export-activity":
            command("copy", text=json.dumps(board["activity"], ensure_ascii=False, indent=2))
        elif action == "clear-activity":
            board["activity"] = []
            save_workspace()
            render_activity(0)
            toast("Activity cleared")
    elif screen == "archive":
        board = find_board()
        card = find_card(board, item_id)
        if card:
            handle_card_action(board, card, action, parameters)


def handle_board_submit(values):
    editing = STATE["form_mode"] == "edit-board"
    board = find_board() if editing else None
    name = clean_text(values.get("name"), "", 80)
    if not name:
        render_board_form(0)
        return
    color = BOARD_COLORS.get(values.get("color"), BOARD_COLORS["blue"])
    if editing and board:
        old_name = board["name"]
        board["name"] = name
        board["description"] = clean_text(values.get("description"), "", 500)
        board["color"] = color
        for column in board["columns"]:
            column["title"] = clean_text(values.get(f"column-title:{column['id']}"), column["title"], 50)
            limit = values.get(f"column-limit:{column['id']}")
            column["limit"] = int(limit) if isinstance(limit, (int, float)) and limit >= 1 else None
        touch_board(board, f"Updated board settings for “{old_name}”", "updated")
        save_workspace()
        navigate("board")
        toast("Board settings saved")
        return
    board = {
        "id": new_id("board"),
        "name": name,
        "description": clean_text(values.get("description"), "", 500),
        "color": color,
        "columns": template_columns(values.get("template", "standard")),
        "cards": [],
        "activity": [],
        "created": now_iso(),
        "updated": now_iso(),
    }
    touch_board(board, f"Created board “{name}”", "created")
    boards().insert(0, board)
    save_workspace()
    STATE["board_id"] = board["id"]
    STATE["screen"] = "board"
    STATE["query"] = ""
    render_board(0, history="replace")
    toast("Board created")


def handle_card_submit(values):
    board = find_board()
    if board is None:
        navigate("boards")
        return
    editing = STATE["form_mode"] == "edit-card"
    card = find_card(board) if editing else None
    title = clean_text(values.get("title"), "", 140)
    if not title:
        render_card_form(0)
        return
    column_id = values.get("column")
    if find_column(board, column_id) is None:
        column_id = board["columns"][0]["id"]
    priority = values.get("priority") if values.get("priority") in PRIORITIES else "none"
    tags = values.get("tags") if isinstance(values.get("tags"), list) else []
    estimate = values.get("estimate")
    estimate = int(estimate) if isinstance(estimate, (int, float)) and estimate >= 1 else None
    if editing and card:
        if card["column"] != column_id:
            allowed, reason = can_enter_column(board, card, column_id)
            if not allowed:
                toast(reason, "error")
                render_card_form(0)
                return
        old_title = card["title"]
        card.update(
            {
                "title": title,
                "description": clean_text(values.get("description"), "", 8000),
                "column": column_id,
                "priority": priority,
                "assignee": clean_text(values.get("assignee"), "", 80),
                "due": clean_text(values.get("due"), "", 10) or None,
                "estimate": estimate,
                "tags": list(dict.fromkeys(clean_text(tag, "", 40) for tag in tags if clean_text(tag, "", 40)))[:20],
            }
        )
        touch_board(board, f"Updated “{old_title}”", "updated", card)
        save_workspace()
        STATE["card_return"] = "board"
        navigate("card", card_id=card["id"])
        toast("Card saved")
        return
    stamp = now_iso()
    card = {
        "id": new_id("card"),
        "title": title,
        "description": clean_text(values.get("description"), "", 8000),
        "column": column_id,
        "priority": priority,
        "assignee": clean_text(values.get("assignee"), "", 80),
        "due": clean_text(values.get("due"), "", 10) or None,
        "estimate": estimate,
        "tags": list(dict.fromkeys(clean_text(tag, "", 40) for tag in tags if clean_text(tag, "", 40)))[:20],
        "archived": False,
        "created": stamp,
        "updated": stamp,
    }
    allowed, reason = can_enter_column(board, card, column_id)
    if not allowed:
        toast(reason, "error")
        render_card_form(0)
        return
    board["cards"].append(card)
    touch_board(board, f"Created “{title}”", "created", card)
    save_workspace()
    STATE["select_id"] = card["id"]
    navigate("board")
    toast("Card created")


def handle_submit(message):
    values = message.get("values") if isinstance(message.get("values"), dict) else {}
    if STATE["screen"] == "board-form":
        handle_board_submit(values)
    elif STATE["screen"] == "card-form":
        handle_card_submit(values)


def handle_kanban_move(message):
    if STATE["screen"] != "board":
        return
    board = find_board()
    card = find_card(board, message.get("id"))
    if card is None:
        return
    visible = [value["id"] for value in board["cards"] if card_matches(board, value, STATE["query"])]
    if move_card(board, card, message.get("columnId"), message.get("index", 0), visible):
        render_board(0)


def handle_load_more(message):
    rev = message.get("rev", 0)
    if STATE["screen"] == "boards":
        STATE["board_pages"] += 1
        render_boards(rev)
    elif STATE["screen"] == "activity":
        STATE["activity_pages"] += 1
        render_activity(rev)
    elif STATE["screen"] == "archive":
        STATE["archive_pages"] += 1
        render_archive(rev)


def navigate_page(target):
    if target == "kanban:boards":
        navigate("boards")
        return
    match = re.fullmatch(r"kanban:board:(.+)", target)
    if match and find_board(match.group(1)):
        navigate("board", board_id=match.group(1))
        return
    match = re.fullmatch(r"kanban:(activity|archive):(.+)", target)
    if match and find_board(match.group(2)):
        STATE[f"{match.group(1)}_pages"] = 1
        navigate(match.group(1), board_id=match.group(2))
        return
    match = re.fullmatch(r"kanban:card:([^:]+):(.+)", target)
    if match and find_card(find_board(match.group(1)), match.group(2)):
        navigate("card", board_id=match.group(1), card_id=match.group(2))
        return
    if target == "kanban:help":
        navigate("help")


def handle_back(message):
    target = message.get("toPageId")
    if target:
        navigate_page(target)
        return
    screen = STATE["screen"]
    if screen == "board":
        navigate("boards")
    elif screen == "board-form":
        navigate("board" if STATE["form_mode"] == "edit-board" and STATE["board_id"] else "boards")
    elif screen in {"activity", "archive"}:
        navigate("board" if STATE["board_id"] else "boards")
    elif screen == "card":
        navigate(STATE["card_return"] if STATE["card_return"] in {"activity", "archive"} else "board")
    elif screen == "card-form":
        navigate("card" if STATE["form_mode"] == "edit-card" else "board")
    else:
        navigate("boards")


def handle_clipboard(message):
    request_id = message.get("requestId")
    text = message.get("text", "")
    try:
        data = json.loads(text)
    except (TypeError, json.JSONDecodeError):
        toast("Clipboard does not contain valid JSON", "error")
        return
    if request_id == "kanban-import-workspace":
        raw = data.get("workspace") if isinstance(data, dict) and "workspace" in data else data
        workspace = normalize_workspace(raw)
        if workspace is None:
            toast("This is not a Kanban workspace backup", "error")
            return
        STATE["workspace"] = workspace
        STATE["board_id"] = None
        save_workspace()
        navigate("boards")
        toast(f"Imported {len(workspace['boards'])} board{'s' if len(workspace['boards']) != 1 else ''}")
    elif request_id == "kanban-import-board":
        raw = data.get("board") if isinstance(data, dict) and "board" in data else None
        board = normalize_board(raw) if raw else None
        if board is None:
            toast("This is not an exported Kanban board", "error")
            return
        existing_ids = {value["id"] for value in boards()}
        if board["id"] in existing_ids:
            board = clone_board(board)
        boards().insert(0, board)
        touch_board(board, "Imported board from clipboard", "created")
        save_workspace()
        STATE["board_id"] = board["id"]
        navigate("board")
        toast("Board imported")


# ---------------------------------------------------------------- event loop


def handle_message(message):
    kind = message.get("type")
    if kind in {"init", "query"}:
        STATE["query"] = message.get("text", message.get("query", "")) or ""
        if STATE["screen"] == "boards":
            STATE["board_pages"] = 1
        elif STATE["screen"] == "activity":
            STATE["activity_pages"] = 1
        elif STATE["screen"] == "archive":
            STATE["archive_pages"] = 1
        render_current(message.get("rev", 0))
    elif kind == "storage" and message.get("requestId") == STORAGE_REQUEST:
        workspace = normalize_workspace(message.get("value"))
        if workspace is None:
            workspace = default_workspace()
            STATE["workspace"] = workspace
            save_workspace()
        else:
            STATE["workspace"] = workspace
        STATE["loaded"] = True
        render_current(0)
    elif kind == "action":
        handle_action(message)
    elif kind == "submit":
        handle_submit(message)
    elif kind == "kanbanMove":
        handle_kanban_move(message)
    elif kind == "loadMore":
        handle_load_more(message)
    elif kind == "navigate":
        navigate_page(message.get("targetPageId", ""))
    elif kind == "back":
        handle_back(message)
    elif kind == "clipboard":
        handle_clipboard(message)


def render_error(error):
    log("Kanban error:", repr(error))
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "page": page("kanban:error", "Kanban error", [{"id": "kanban:boards", "label": "Boards"}]),
            "canGoBack": True,
            "wide": True,
            "detail": {
                "markdown": "# Something went wrong\n\nYour saved workspace was not changed. Return to **Boards** and try again.",
                "metadata": [{"label": "Error", "text": str(error)[:300], "color": "#EF4444"}],
            },
        }
    )


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
            if not isinstance(message, dict):
                continue
            if message.get("type") == "close":
                break
            handle_message(message)
        except json.JSONDecodeError:
            log("Ignored malformed JSON input")
        except Exception as error:  # A plugin error should stay inside its UI.
            render_error(error)


if __name__ == "__main__":
    main()
