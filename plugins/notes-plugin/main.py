#!/usr/bin/env python3
"""
Notes — a Tabame launcher plugin.

Keyword: note

  note                          -> browse all notes (Pinned / Today / This Week / Older)
  note buy milk #shopping       -> quick-add a note titled "buy milk", tagged #shopping
  note !call mom #family        -> leading "!" pins the new note
  note some search text         -> filters existing notes by title/body/tag

Enter on a note opens it (detail view). Ctrl+K on any note: Edit, Pin/Unpin,
Copy content, Duplicate, Delete. Ctrl+N (frame action) opens a blank full
editor form for longer notes.

Storage: plain notes.json in the plugin folder (working directory).
"""

import sys
import json
import os
import re
import uuid
from datetime import datetime, timedelta

STORE_PATH = "notes.json"

STATE = {"screen": "root", "query": ""}


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
                return data
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
            "id": "unpin" if n["pinned"] else "pin",
            "title": "Unpin" if n["pinned"] else "Pin",
            "icon": "star",
        },
        {"id": "copy", "title": "Copy content", "icon": "copy", "shortcut": "ctrl+shift+c"},
        {"id": "duplicate", "title": "Duplicate", "icon": "copy"},
        {
            "id": "delete",
            "title": "Delete",
            "icon": "trash",
            "destructive": True,
            "confirm": DELETE_CONFIRM(n["title"]),
        },
    ]


def note_preview(n):
    body = n["body"].strip() if n["body"] else ""
    md = f"# {n['title'] or '(untitled)'}\n\n" + (body if body else "*No additional content*")
    meta = [
        {
            "label": "Status",
            "text": "Pinned" if n["pinned"] else "Not pinned",
            "icon": "star",
            "color": "#F5B400" if n["pinned"] else None,
        },
        {"label": "Tags", "text": ", ".join(n["tags"]) if n["tags"] else "—"},
        {"separator": True},
        {"label": "Created", "text": fmt_dt(n["created"])},
        {"label": "Updated", "text": fmt_dt(n["updated"])},
    ]
    # drop the None color key rather than sending an invalid value
    for row in meta:
        if row.get("color") is None:
            row.pop("color", None)
    return md, meta


def note_item(n):
    body = (n["body"] or "").strip().replace("\n", " ")
    subtitle = (body[:80] + "…") if len(body) > 80 else (body or "No additional content")
    accessories = []
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
    return any(q in tag.lower() for tag in n["tags"])


def group_sections(notes):
    pinned = [n for n in notes if n["pinned"]]
    rest = [n for n in notes if not n["pinned"]]

    def by_updated_desc(items):
        return sorted(items, key=lambda n: n["updated"], reverse=True)

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
    {"id": "newblank", "title": "New note (full editor)", "icon": "note", "shortcut": "ctrl+n"},
]


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
            items.append({
                "id": f"new:{q}",
                "title": f"Create note: {title_q or q}",
                "subtitle": " · ".join(bits) if bits else "Press Enter to add",
                "icon": "add",
                "actions": [{"id": "default", "title": "Create", "icon": "add"}],
            })
        matches = [n for n in notes if matches_query(n, q)]
        matches = sorted(matches, key=lambda n: n["updated"], reverse=True)
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
            "items": items,
        }
    else:
        sections = group_sections(notes)
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
            "items": items,
        }

    if select_id:
        frame["selectId"] = select_id
    send(frame)


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
    send({
        "type": "render",
        "rev": 0,
        "view": "detail",
        "canGoBack": True,
        "detail": {"markdown": md, "metadata": meta, "wide": True},
        "actions": note_actions(n),
    })


def open_form(note=None):
    if note is None:
        STATE["screen"] = "form:new"
        title, values = "New Note", {"title": "", "body": "", "tags": [], "pinned": False}
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
            "id": "pinned",
            "type": "checkbox",
            "label": "Pinned",
            "value": values["pinned"],
        },
    ]
    send({
        "type": "render",
        "rev": 0,
        "view": "form",
        "canGoBack": True,
        "form": {"title": title, "submitLabel": "Save", "fields": fields},
    })


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
        "created": ts,
        "updated": ts,
    }
    notes.append(n)
    save_notes(notes)
    cmd("setQuery", text="")
    render_root(0, "", select_id=n["id"])
    cmd("toast", text=f"Added: {n['title']}")


def handle_note_action(note_id, action, from_detail):
    notes = load_notes()
    n = find_note(notes, note_id)
    if not n:
        if from_detail:
            STATE["screen"] = "root"
            render_root(0, STATE.get("query", ""))
        else:
            render_root(0, STATE.get("query", ""))
        cmd("toast", text="That note is gone.", style="error")
        return

    if action == "edit":
        open_form(n)

    elif action in ("pin", "unpin"):
        n["pinned"] = action == "pin"
        n["updated"] = now_iso()
        save_notes(notes)
        if from_detail:
            open_detail(note_id)
        else:
            render_root(0, STATE.get("query", ""), select_id=note_id)

    elif action == "copy":
        text = n["title"] + ("\n\n" + n["body"] if n["body"] else "")
        cmd("copy", text=text)

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
            render_root(0, STATE.get("query", ""), select_id=dup["id"])
        cmd("toast", text="Note duplicated")

    elif action == "delete":
        notes = [x for x in notes if x["id"] != note_id]
        save_notes(notes)
        STATE["screen"] = "root"
        render_root(0, STATE.get("query", ""))
        cmd("toast", text="Note deleted")


def handle_action(item_id, action):
    if item_id == "":
        if action == "newblank":
            open_form(None)
            return
        screen = STATE["screen"]
        if screen.startswith("detail:"):
            note_id = screen.split(":", 1)[1]
            handle_note_action(note_id, action, from_detail=True)
        return

    if item_id.startswith("new:"):
        if action == "default":
            quick_add(item_id[4:])
        return

    if action == "default":
        open_detail(item_id)
    else:
        handle_note_action(item_id, action, from_detail=False)


def handle_submit(values):
    notes = load_notes()
    screen = STATE["screen"]
    title = (values.get("title") or "").strip()
    body = values.get("body") or ""
    tags = values.get("tags") or []
    pinned = bool(values.get("pinned"))
    ts = now_iso()

    if screen == "form:new":
        n = {
            "id": new_id(),
            "title": title or "(untitled)",
            "body": body,
            "tags": tags,
            "pinned": pinned,
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
            n["updated"] = ts
            save_notes(notes)
        select_id = note_id
    else:
        select_id = None

    STATE["screen"] = "root"
    render_root(0, STATE.get("query", ""), select_id=select_id)
    cmd("toast", text="Note saved")


def handle_back():
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
                else:
                    STATE["query"] = text
            elif t == "action":
                handle_action(msg.get("id", ""), msg.get("action", "default"))
            elif t == "submit":
                handle_submit(msg.get("values", {}))
            elif t == "back":
                handle_back()
            # "select", "tab", "change", "loadMore" are not used by this plugin.
        except Exception as e:
            log("unhandled error:", e)
            send({
                "type": "render",
                "rev": 0,
                "view": "detail",
                "canGoBack": True,
                "detail": {"markdown": f"# Error\n\n```\n{e}\n```"},
            })


if __name__ == "__main__":
    main()
