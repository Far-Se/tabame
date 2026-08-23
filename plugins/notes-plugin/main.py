#!/usr/bin/env python3
"""
Notes — a Tabame launcher plugin.

Keyword: note

  note                          -> browse notes (Latest 5, then Pinned / Today / This Week / Older)
  note buy milk #shopping       -> quick-add a note titled "buy milk", tagged #shopping
  note !call mom #family        -> leading "!" pins the new note
  note some search text         -> filters existing notes by title/body/tag/category

Enter on a note opens it (detail view). Ctrl+K on any note: Edit, Move to
Category, Pin/Unpin, Copy content, Duplicate, Delete. Ctrl+N (frame action)
opens a blank full editor form for longer notes.

Storage: plain notes.json and categories.json in the plugin folder (working
directory). Existing notes are kept compatible and start in Uncategorized.
"""

import json
import os
import re
import sys
import uuid
from datetime import datetime, timedelta

STORE_PATH = "notes.json"
CATEGORY_STORE_PATH = "categories.json"
DEFAULT_CATEGORY_ID = "uncategorized"

STATE = {
    "screen": "root",
    "query": "",
    "category_id": None,
    "return_screen": "root",
    "return_query": "",
}


# --------------------------------------------------------------------------
# stdout / stderr helpers
# --------------------------------------------------------------------------


def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def cmd(command, **fields):
    send({"type": "command", "command": command, **fields})


# --------------------------------------------------------------------------
# storage
# --------------------------------------------------------------------------


def load_notes():
    if not os.path.exists(STORE_PATH):
        return []
    try:
        with open(STORE_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, list):
                notes = []
                for note in data:
                    if not isinstance(note, dict) or not note.get("id"):
                        continue
                    note.setdefault("title", "")
                    note.setdefault("body", "")
                    note.setdefault("tags", [])
                    note.setdefault("pinned", False)
                    note.setdefault("created", now_iso())
                    note.setdefault("updated", note["created"])
                    note.setdefault("categoryId", DEFAULT_CATEGORY_ID)
                    if not isinstance(note["tags"], list):
                        note["tags"] = []
                    notes.append(note)
                return notes
    except Exception as e:
        log("load_notes failed:", e)
    return []


def save_notes(notes):
    try:
        tmp = STORE_PATH + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(notes, f, ensure_ascii=False, indent=2)
        os.replace(tmp, STORE_PATH)
    except Exception as e:
        log("save_notes failed:", e)


def default_categories():
    return [{"id": DEFAULT_CATEGORY_ID, "name": "Uncategorized"}]


def load_categories():
    if not os.path.exists(CATEGORY_STORE_PATH):
        return default_categories()
    try:
        with open(CATEGORY_STORE_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        raw_categories = data.get("categories", []) if isinstance(data, dict) else data
        categories = []
        seen_ids = set()
        for category in raw_categories if isinstance(raw_categories, list) else []:
            if not isinstance(category, dict):
                continue
            category_id = str(category.get("id", "")).strip()
            name = str(category.get("name", "")).strip()
            if not category_id or not name or category_id in seen_ids:
                continue
            categories.append({"id": category_id, "name": name})
            seen_ids.add(category_id)
        if DEFAULT_CATEGORY_ID not in seen_ids:
            categories.insert(0, default_categories()[0])
        return categories or default_categories()
    except Exception as e:
        log("load_categories failed:", e)
        return default_categories()


def save_categories(categories):
    try:
        tmp = CATEGORY_STORE_PATH + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(categories, f, ensure_ascii=False, indent=2)
        os.replace(tmp, CATEGORY_STORE_PATH)
    except Exception as e:
        log("save_categories failed:", e)


CATEGORIES = load_categories()


def find_category(category_id):
    for category in CATEGORIES:
        if category["id"] == category_id:
            return category
    return None


def category_id_for(note):
    category_id = note.get("categoryId") or DEFAULT_CATEGORY_ID
    return category_id if find_category(category_id) else DEFAULT_CATEGORY_ID


def category_name_for(note):
    category = find_category(category_id_for(note))
    return category["name"] if category else "Uncategorized"


def category_options(selected=None):
    return [
        {"value": category["id"], "label": category["name"]}
        for category in CATEGORIES
    ]


def create_category(name):
    name = (name or "").strip()
    if not name:
        return None, "Enter a category name."
    for category in CATEGORIES:
        if category["name"].casefold() == name.casefold():
            return category, "That category already exists."
    category = {"id": f"category-{new_id()}", "name": name}
    CATEGORIES.append(category)
    save_categories(CATEGORIES)
    return category, None


def find_note(notes, note_id):
    for n in notes:
        if n["id"] == note_id:
            return n
    return None


def new_id():
    return uuid.uuid4().hex[:12]


def now_iso():
    return datetime.now().isoformat(timespec="seconds")


def fmt_dt(iso):
    try:
        d = datetime.fromisoformat(iso)
        return d.strftime("%b %d, %Y %H:%M")
    except Exception:
        return iso or "—"


# --------------------------------------------------------------------------
# quick-add parsing
# --------------------------------------------------------------------------

TAG_RE = re.compile(r"#(\w+)")


def parse_quick(text):
    """Parse launcher-line syntax: leading '!' pins, #tag tokens become tags."""
    t = text.strip()
    pinned = False
    if t.startswith("!"):
        pinned = True
        t = t[1:].strip()
    tags = TAG_RE.findall(t)
    title = TAG_RE.sub("", t)
    title = re.sub(r"\s+", " ", title).strip()
    return title, tags, pinned


# --------------------------------------------------------------------------
# rendering helpers
# --------------------------------------------------------------------------

DELETE_CONFIRM = lambda title: {
    "title": "Delete this note?",
    "message": title or "(untitled)",
    "confirmLabel": "Delete",
}


def note_actions(n):
    return [
        {"id": "edit", "title": "Edit", "icon": "edit", "shortcut": "ctrl+e"},
        {
            "id": "move",
            "title": "Move to category",
            "icon": "folder",
            "parameters": [
                {
                    "id": "category",
                    "type": "dropdown",
                    "label": "Category",
                    "required": True,
                    "value": category_id_for(n),
                    "options": category_options(),
                }
            ],
        },
        {
            "id": "unpin" if n["pinned"] else "pin",
            "title": "Unpin" if n["pinned"] else "Pin",
            "icon": "star",
        },
        {
            "id": "copy",
            "title": "Copy content",
            "icon": "copy",
            "shortcut": "ctrl+shift+c",
        },
        {"id": "duplicate", "title": "Duplicate", "icon": "copy"},
        {
            "id": "delete",
            "title": "Delete",
            "icon": "trash",
            "destructive": True,
            "shortcut": "ctrl+shift+d",
            "confirm": DELETE_CONFIRM(n["title"]),
        },
    ]


def note_preview(n):
    body = n["body"].strip() if n["body"] else ""
    md = f"# {n['title'] or '(untitled)'}\n\n" + (
        body if body else "*No additional content*"
    )
    meta = [
        {
            "label": "Status",
            "text": "Pinned" if n["pinned"] else "Not pinned",
            "icon": "star",
            "color": "#F5B400" if n["pinned"] else None,
        },
        {"label": "Category", "text": category_name_for(n), "icon": "folder"},
        {"label": "Tags", "text": ", ".join(n["tags"]) if n["tags"] else "—"},
        {"separator": True},
        {"label": "Created", "text": fmt_dt(n["created"])},
        {"label": "Updated", "text": fmt_dt(n["updated"])},
        {
            "label": "Actions",
            "text": "Note content",
            "actions": [{"id": "copy", "title": "Copy", "icon": "copy"}],
        },
    ]
    # drop the None color key rather than sending an invalid value
    for row in meta:
        if row.get("color") is None:
            row.pop("color", None)
    return md, meta


def note_item(n):
    body = (n["body"] or "").strip().replace("\n", " ")
    subtitle = (
        (body[:80] + "…") if len(body) > 80 else (body or "No additional content")
    )
    accessories = [{"text": category_name_for(n), "icon": "folder"}]
    if n["pinned"]:
        accessories.append({"text": "Pinned", "icon": "star", "color": "#F5B400"})
    for t in n["tags"][:4]:
        accessories.append({"text": t, "icon": "tag"})
    md, meta = note_preview(n)
    return {
        "id": n["id"],
        "title": n["title"] or "(untitled)",
        "subtitle": subtitle,
        "icon": "note",
        "lines": 2,
        "accessories": accessories,
        "actions": note_actions(n),
        "preview": {"markdown": md, "metadata": meta},
    }


def matches_query(n, q):
    q = q.lower()
    if q in (n["title"] or "").lower():
        return True
    if q in (n["body"] or "").lower():
        return True
    if q in category_name_for(n).lower():
        return True
    return any(q in tag.lower() for tag in n["tags"])


def updated_key(note):
    return note.get("updated") or note.get("created") or ""


def group_sections(notes):
    pinned = [n for n in notes if n["pinned"]]
    rest = [n for n in notes if not n["pinned"]]

    def by_updated_desc(items):
        return sorted(items, key=updated_key, reverse=True)

    pinned = by_updated_desc(pinned)
    rest = by_updated_desc(rest)

    today = datetime.now().date()
    week_cutoff = today - timedelta(days=7)

    todays, this_week, older = [], [], []
    for n in rest:
        try:
            d = datetime.fromisoformat(n["updated"]).date()
        except Exception:
            d = today
        if d == today:
            todays.append(n)
        elif d >= week_cutoff:
            this_week.append(n)
        else:
            older.append(n)

    sections = []
    if pinned:
        sections.append(("Pinned", pinned))
    if todays:
        sections.append(("Today", todays))
    if this_week:
        sections.append(("This Week", this_week))
    if older:
        sections.append(("Older", older))
    return sections


ROOT_FRAME_ACTIONS = [
    {
        "id": "newblank",
        "title": "New note (full editor)",
        "icon": "note",
        "shortcut": "ctrl+n",
    },
    {
        "id": "newcategory",
        "title": "New category",
        "icon": "folder",
        "parameters": [
            {
                "id": "name",
                "type": "text",
                "label": "Category name",
                "required": True,
            }
        ],
    },
    {"id": "categories", "title": "Browse categories", "icon": "folder"},
]


def category_actions(category):
    actions = [
        {
            "id": "rename",
            "title": "Rename category",
            "icon": "edit",
            "parameters": [
                {
                    "id": "name",
                    "type": "text",
                    "label": "Category name",
                    "required": True,
                    "value": category["name"],
                }
            ],
        }
    ]
    if category["id"] != DEFAULT_CATEGORY_ID:
        actions.append(
            {
                "id": "delete",
                "title": "Delete category",
                "icon": "trash",
                "destructive": True,
                "confirm": {
                    "title": f"Delete {category['name']}?",
                    "message": "Notes in it will move to Uncategorized.",
                    "confirmLabel": "Delete",
                },
            }
        )
    return actions


def category_item(category, notes):
    count = sum(1 for note in notes if category_id_for(note) == category["id"])
    return {
        "id": f"category:{category['id']}",
        "title": category["name"],
        "subtitle": f"{count} note{'s' if count != 1 else ''}",
        "icon": "folder",
        "accessories": [{"text": str(count), "icon": "note"}],
        "actions": category_actions(category),
    }


def render_root(rev, query, select_id=None):
    STATE["screen"] = "root"
    STATE["query"] = query
    notes = load_notes()
    q = query.strip()
    items = []

    if q:
        title_q, tags_q, pinned_q = parse_quick(q)
        if title_q or tags_q:
            bits = []
            if tags_q:
                bits.append("tags: " + ", ".join(tags_q))
            if pinned_q:
                bits.append("pinned")
            items.append(
                {
                    "id": f"new:{q}",
                    "title": f"Create note: {title_q or q}",
                    "subtitle": " · ".join(bits) if bits else "Press Enter to add",
                    "icon": "add",
                    "actions": [{"id": "default", "title": "Create", "icon": "add"}],
                }
            )
        matches = [n for n in notes if matches_query(n, q)]
        matches = sorted(matches, key=updated_key, reverse=True)
        matches.sort(key=lambda n: 0 if n["pinned"] else 1)
        for n in matches:
            items.append(note_item(n))

        frame = {
            "type": "render",
            "rev": rev,
            "view": "list",
            "preview": {"enabled": True},
            "placeholder": "Search notes, or type to quick-add… (#tag, ! to pin)",
            "emptyText": "No matches — press Enter to create",
            "actions": ROOT_FRAME_ACTIONS,
            "floatingAction": ROOT_FRAME_ACTIONS[:2],
            "items": items,
        }
    else:
        ordered = sorted(notes, key=updated_key, reverse=True)
        latest = ordered[:5]
        latest_ids = {n["id"] for n in latest}
        sections = [("Latest", latest)] if latest else []
        sections.extend(group_sections([n for n in ordered if n["id"] not in latest_ids]))
        for name, ns in sections:
            for n in ns:
                it = note_item(n)
                it["section"] = name
                items.append(it)

        frame = {
            "type": "render",
            "rev": rev,
            "view": "list",
            "preview": {"enabled": True},
            "placeholder": "Search notes, or type to quick-add… (#tag, ! to pin)",
            "empty": {
                "icon": "note",
                "title": "No notes yet",
                "hint": "Type to quick-add, or press Ctrl+N for the full editor",
                "action": {"id": "newblank", "title": "New note", "icon": "add"},
            },
            "actions": ROOT_FRAME_ACTIONS,
            "floatingAction": ROOT_FRAME_ACTIONS[:2],
            "items": items,
        }

    if select_id:
        frame["selectId"] = select_id
    send(frame)


def render_categories(rev, query=""):
    STATE["screen"] = "categories"
    STATE["category_id"] = None
    STATE["query"] = query
    notes = load_notes()
    q = query.strip().lower()
    categories = [
        category
        for category in CATEGORIES
        if not q or q in category["name"].lower()
    ]
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "preview": {"enabled": True},
            "placeholder": "Filter categories...",
            "emptyText": "No categories match that filter",
            "actions": ROOT_FRAME_ACTIONS[:2],
            "floatingAction": ROOT_FRAME_ACTIONS[:2],
            "items": [category_item(category, notes) for category in categories],
        }
    )


def render_category_notes(rev, category_id, query=""):
    category = find_category(category_id)
    if not category:
        render_categories(rev)
        return
    STATE["screen"] = f"category:{category_id}"
    STATE["category_id"] = category_id
    STATE["query"] = query
    notes = [
        note
        for note in load_notes()
        if category_id_for(note) == category_id
        and (not query.strip() or matches_query(note, query.strip()))
    ]
    notes.sort(key=updated_key, reverse=True)
    items = [note_item(note) for note in notes]
    frame = {
        "type": "render",
        "rev": rev,
        "view": "list",
        "canGoBack": True,
        "preview": {"enabled": True},
        "placeholder": f"Filter {category['name']} notes...",
        "empty": {
            "icon": "folder",
            "title": f"No notes in {category['name']}",
            "hint": "Create a note here or move an existing note into this category",
            "action": {"id": "newnotehere", "title": "New note", "icon": "add"},
        },
        "actions": [
            {
                "id": "newnotehere",
                "title": "New note here",
                "icon": "add",
            },
            {"id": "categories", "title": "Back to categories", "icon": "folder"},
        ],
        "floatingAction": {"id": "newnotehere", "title": "New note", "icon": "add"},
        "items": items,
    }
    if query.strip() and not items:
        frame["emptyText"] = f'No notes in {category["name"]} match "{query.strip()}"'
        frame.pop("empty", None)
    send(frame)


def open_categories():
    cmd("setQuery", text="")
    render_categories(0)


def open_detail(note_id):
    notes = load_notes()
    n = find_note(notes, note_id)
    if not n:
        STATE["screen"] = "root"
        render_root(0, STATE.get("query", ""))
        cmd("toast", text="That note is gone.", style="error")
        return
    STATE["screen"] = f"detail:{note_id}"
    md, meta = note_preview(n)
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "canGoBack": True,
            "detail": {"markdown": md, "metadata": meta, "wide": True},
            "actions": note_actions(n),
        }
    )


def open_form(note=None, category_id=DEFAULT_CATEGORY_ID):
    STATE["return_screen"] = STATE.get("screen", "root")
    STATE["return_query"] = STATE.get("query", "")
    if note is None:
        STATE["screen"] = "form:new"
        title, values = (
            "New Note",
            {
                "title": "",
                "body": "",
                "tags": [],
                "pinned": False,
                "categoryId": category_id,
            },
        )
    else:
        STATE["screen"] = f"form:edit:{note['id']}"
        title, values = "Edit Note", note

    fields = [
        {
            "id": "title",
            "type": "text",
            "label": "Title",
            "placeholder": "Note title…",
            "required": True,
            "value": values["title"],
        },
        {
            "id": "body",
            "type": "textarea",
            "label": "Body",
            "placeholder": "Write your note…",
            "value": values["body"],
        },
        {
            "id": "tags",
            "type": "tags",
            "label": "Tags",
            "value": values["tags"],
        },
        {
            "id": "category",
            "type": "dropdown",
            "label": "Category",
            "required": True,
            "value": category_id_for(values),
            "options": category_options(),
        },
        {
            "id": "pinned",
            "type": "checkbox",
            "label": "Pinned",
            "value": values["pinned"],
        },
    ]
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "form",
            "canGoBack": True,
            "form": {"title": title, "submitLabel": "Save", "fields": fields},
        }
    )


# --------------------------------------------------------------------------
# action handling
# --------------------------------------------------------------------------


def quick_add(raw):
    title, tags, pinned = parse_quick(raw)
    if not title and not tags:
        return
    notes = load_notes()
    ts = now_iso()
    n = {
        "id": new_id(),
        "title": title or raw.strip(),
        "body": "",
        "tags": tags,
        "pinned": pinned,
        "categoryId": DEFAULT_CATEGORY_ID,
        "created": ts,
        "updated": ts,
    }
    notes.append(n)
    save_notes(notes)
    cmd("setQuery", text="")
    render_root(0, "", select_id=n["id"])
    cmd("toast", text=f"Added: {n['title']}")


def refresh_current(select_id=None):
    screen = STATE.get("screen", "root")
    query = STATE.get("query", "")
    if screen == "root":
        render_root(0, query, select_id=select_id)
    elif screen == "categories":
        render_categories(0, query)
    elif screen.startswith("category:"):
        render_category_notes(0, screen.split(":", 1)[1], query)
    else:
        render_root(0, query, select_id=select_id)


def return_from_form(select_id=None):
    previous = STATE.pop("return_screen", "root")
    previous_query = STATE.pop("return_query", "")
    if previous == "root":
        STATE["screen"] = "root"
        render_root(0, previous_query, select_id=select_id)
    elif previous == "categories":
        render_categories(0, previous_query)
    elif previous.startswith("category:"):
        render_category_notes(0, previous.split(":", 1)[1], previous_query)
    elif previous.startswith("detail:"):
        open_detail(select_id or previous.split(":", 1)[1])
    else:
        STATE["screen"] = "root"
        render_root(0, previous_query, select_id=select_id)


def handle_note_action(note_id, action, from_detail, parameters=None):
    parameters = parameters or {}
    notes = load_notes()
    n = find_note(notes, note_id)
    if not n:
        if from_detail:
            STATE["screen"] = "root"
            render_root(0, STATE.get("query", ""))
        else:
            refresh_current()
        cmd("toast", text="That note is gone.", style="error")
        return

    if action == "edit":
        open_form(n)

    elif action == "move":
        target_id = parameters.get("category") or DEFAULT_CATEGORY_ID
        target = find_category(target_id)
        if not target:
            cmd("toast", text="Choose a valid category.", style="error")
            return
        n["categoryId"] = target["id"]
        n["updated"] = now_iso()
        save_notes(notes)
        if from_detail:
            open_detail(note_id)
        else:
            refresh_current(select_id=note_id)
        cmd("toast", text=f"Moved to {target['name']}")

    elif action in ("pin", "unpin"):
        n["pinned"] = action == "pin"
        n["updated"] = now_iso()
        save_notes(notes)
        if from_detail:
            open_detail(note_id)
        else:
            refresh_current(select_id=note_id)

    elif action == "copy":
        cmd("copy", text=n["body"] or "")

    elif action == "duplicate":
        ts = now_iso()
        dup = dict(n)
        dup["id"] = new_id()
        dup["title"] = (n["title"] or "(untitled)") + " (copy)"
        dup["created"] = ts
        dup["updated"] = ts
        notes.append(dup)
        save_notes(notes)
        if from_detail:
            open_detail(dup["id"])
        else:
            refresh_current(select_id=dup["id"])
        cmd("toast", text="Note duplicated")

    elif action == "delete":
        notes = [x for x in notes if x["id"] != note_id]
        save_notes(notes)
        STATE["screen"] = "root" if from_detail else STATE.get("screen", "root")
        refresh_current()
        cmd("toast", text="Note deleted")


def handle_action(item_id, action, parameters=None):
    parameters = parameters or {}
    if item_id == "":
        if action == "newblank":
            screen = STATE.get("screen", "root")
            category_id = (
                screen.split(":", 1)[1]
                if screen.startswith("category:")
                else DEFAULT_CATEGORY_ID
            )
            open_form(None, category_id=category_id)
            return
        if action == "newnotehere":
            screen = STATE.get("screen", "root")
            if screen.startswith("category:"):
                open_form(None, category_id=screen.split(":", 1)[1])
            return
        if action == "newcategory":
            category, error = create_category(parameters.get("name"))
            if error:
                cmd("toast", text=error, style="error")
            else:
                cmd("toast", text=f"Created category: {category['name']}")
            refresh_current()
            return
        if action == "categories":
            open_categories()
            return
        screen = STATE["screen"]
        if screen.startswith("detail:"):
            note_id = screen.split(":", 1)[1]
            handle_note_action(
                note_id, action, from_detail=True, parameters=parameters
            )
        return

    if item_id.startswith("new:"):
        if action == "default":
            quick_add(item_id[4:])
        return

    if item_id.startswith("category:"):
        category_id = item_id.split(":", 1)[1]
        category = find_category(category_id)
        if not category:
            refresh_current()
            return
        if action == "default":
            cmd("setQuery", text="")
            render_category_notes(0, category_id)
            return
        if action == "rename":
            name = (parameters.get("name") or "").strip()
            if not name:
                cmd("toast", text="Enter a category name.", style="error")
                return
            duplicate = next(
                (
                    other
                    for other in CATEGORIES
                    if other["id"] != category_id
                    and other["name"].casefold() == name.casefold()
                ),
                None,
            )
            if duplicate:
                cmd("toast", text="That category already exists.", style="error")
                return
            category["name"] = name
            save_categories(CATEGORIES)
            cmd("toast", text="Category renamed")
            refresh_current()
            return
        if action == "delete" and category_id != DEFAULT_CATEGORY_ID:
            notes = load_notes()
            for note in notes:
                if note.get("categoryId") == category_id:
                    note["categoryId"] = DEFAULT_CATEGORY_ID
            save_notes(notes)
            CATEGORIES[:] = [
                item for item in CATEGORIES if item["id"] != category_id
            ]
            save_categories(CATEGORIES)
            cmd("toast", text="Category deleted; notes moved to Uncategorized")
            if STATE.get("screen") == f"category:{category_id}":
                open_categories()
            else:
                refresh_current()
            return
        return

    if action == "default":
        open_detail(item_id)
    else:
        handle_note_action(
            item_id, action, from_detail=False, parameters=parameters
        )


def handle_submit(values):
    notes = load_notes()
    screen = STATE["screen"]
    title = (values.get("title") or "").strip()
    body = values.get("body") or ""
    tags = values.get("tags") or []
    if isinstance(tags, str):
        tags = [tags]
    pinned = bool(values.get("pinned"))
    category_id = values.get("category") or DEFAULT_CATEGORY_ID
    if not find_category(category_id):
        category_id = DEFAULT_CATEGORY_ID
    ts = now_iso()

    if screen == "form:new":
        n = {
            "id": new_id(),
            "title": title or "(untitled)",
            "body": body,
            "tags": tags,
            "pinned": pinned,
            "categoryId": category_id,
            "created": ts,
            "updated": ts,
        }
        notes.append(n)
        save_notes(notes)
        select_id = n["id"]
    elif screen.startswith("form:edit:"):
        note_id = screen.split(":", 2)[2]
        n = find_note(notes, note_id)
        if n:
            n["title"] = title or "(untitled)"
            n["body"] = body
            n["tags"] = tags
            n["pinned"] = pinned
            n["categoryId"] = category_id
            n["updated"] = ts
            save_notes(notes)
        select_id = note_id
    else:
        select_id = None

    return_from_form(select_id=select_id)
    cmd("toast", text="Note saved")


def handle_back():
    screen = STATE.get("screen", "root")
    if screen.startswith("form:"):
        previous = STATE.pop("return_screen", "root")
        previous_query = STATE.pop("return_query", "")
        if previous.startswith("detail:"):
            open_detail(previous.split(":", 1)[1])
        elif previous.startswith("category:"):
            render_category_notes(0, previous.split(":", 1)[1], previous_query)
        elif previous == "categories":
            render_categories(0, previous_query)
        else:
            render_root(0, previous_query)
    elif screen.startswith("detail:") or screen == "categories":
        STATE["screen"] = "root"
        render_root(0, STATE.get("query", ""))
    elif screen.startswith("category:"):
        open_categories()
    else:
        STATE["screen"] = "root"
        render_root(0, STATE.get("query", ""))


# --------------------------------------------------------------------------
# main loop
# --------------------------------------------------------------------------


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue

        t = msg.get("type")
        try:
            if t == "close":
                break
            elif t in ("init", "query"):
                text = msg.get("text", msg.get("query", ""))
                rev = msg.get("rev", 0)
                if STATE["screen"] == "root":
                    render_root(rev, text)
                elif STATE["screen"] == "categories":
                    render_categories(rev, text)
                elif STATE["screen"].startswith("category:"):
                    render_category_notes(
                        rev, STATE["screen"].split(":", 1)[1], text
                    )
                else:
                    STATE["query"] = text
            elif t == "action":
                handle_action(
                    msg.get("id", ""),
                    msg.get("action", "default"),
                    msg.get("parameters") or {},
                )
            elif t == "submit":
                handle_submit(msg.get("values", {}))
            elif t == "back":
                handle_back()
            # "select", "tab", "change", "loadMore" are not used by this plugin.
        except Exception as e:
            log("unhandled error:", e)
            send(
                {
                    "type": "render",
                    "rev": 0,
                    "view": "detail",
                    "canGoBack": True,
                    "detail": {"markdown": f"# Error\n\n```\n{e}\n```"},
                }
            )


if __name__ == "__main__":
    main()
