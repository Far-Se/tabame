#!/usr/bin/env python3
"""
To-Do & Reminders — a Tabame launcher plugin.

Quick-add syntax (typed after the `todo` keyword):
    todo Buy milk tomorrow 5pm !h #errands

  !h / !high        priority: high
  !m / !med         priority: medium
  !l / !low         priority: low
  #tag              one or more tags
  today             due today
  tomorrow / tmrw   due tomorrow
  mon..sun          due next occurrence of that weekday
  +3d / +2h / +1w   due N days/hours/weeks from now
  2026-07-22        explicit date (YYYY-MM-DD)
  7/22 or 7-22      explicit date (month/day, this year or next)
  5pm / 5:30pm      time of day (24h "17:00" also works)

Everything else in the query becomes the task title.

Storage: a plain tasks.json file in the plugin folder (not the opaque
.tabame-store.json), so a separate script can read/notify on due tasks
even when the launcher isn't running — see reminder_watcher.py.
"""

import datetime
import json
import os
import re
import sys
import uuid

TASKS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tasks.json")

PRIORITY_COLORS = {"high": "#EF4444", "medium": "#F59E0B", "low": "#3B82F6"}
SECTION_ORDER = [
    "Overdue",
    "Today",
    "Tomorrow",
    "This Week",
    "Later",
    "No Due Date",
    "Done",
]
PRIORITY_RANK = {"high": 0, "medium": 1, "low": 2, None: 3}

WEEKDAY_MAP = {
    "mon": 0,
    "monday": 0,
    "tue": 1,
    "tues": 1,
    "tuesday": 1,
    "wed": 2,
    "weds": 2,
    "wednesday": 2,
    "thu": 3,
    "thur": 3,
    "thurs": 3,
    "thursday": 3,
    "fri": 4,
    "friday": 4,
    "sat": 5,
    "saturday": 5,
    "sun": 6,
    "sunday": 6,
}

state = {
    "screen": "list",
    "editing_id": None,
    "hide_done": True,
    "query": "",
    "tasks": [],
}


# ---------------------------------------------------------------- protocol


def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# ---------------------------------------------------------------- storage


def load_tasks():
    if os.path.exists(TASKS_FILE):
        try:
            with open(TASKS_FILE, encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            log("load_tasks error:", e)
    return []


def save_tasks():
    try:
        with open(TASKS_FILE, "w", encoding="utf-8") as f:
            json.dump(state["tasks"], f, indent=2)
    except Exception as e:
        log("save_tasks error:", e)


def find_task(task_id):
    for t in state["tasks"]:
        if t["id"] == task_id:
            return t
    return None


def new_task(title, notes, due_dt, has_time, priority, tags):
    return {
        "id": uuid.uuid4().hex[:8],
        "title": title,
        "notes": notes or "",
        "due": due_dt.isoformat() if due_dt else None,
        "has_time": has_time,
        "priority": priority,
        "tags": tags or [],
        "done": False,
        "created": datetime.datetime.now().isoformat(),
        "completed": None,
        "notified": False,
    }


# ---------------------------------------------------------------- parsing


def parse_time_token(tok):
    tok = tok.strip().lower()
    m = re.fullmatch(r"(\d{1,2})(:(\d{2}))?\s*(am|pm)", tok)
    if m:
        hour = int(m.group(1)) % 12
        minute = int(m.group(3) or 0)
        if m.group(4) == "pm":
            hour += 12
        if 0 <= hour < 24 and 0 <= minute < 60:
            return (hour, minute)
        return None
    m = re.fullmatch(r"([01]?\d|2[0-3]):([0-5]\d)", tok)
    if m:
        return (int(m.group(1)), int(m.group(2)))
    return None


def next_weekday(idx):
    today = datetime.date.today()
    days_ahead = (idx - today.weekday()) % 7
    if days_ahead == 0:
        days_ahead = 7
    return today + datetime.timedelta(days=days_ahead)


def parse_quick_add(text):
    """Returns (title, due_dt_or_None, has_time, priority_or_None, tags_list)."""
    tokens = text.split()
    title_tokens = []
    priority = None
    tags = []
    date_part = None
    time_part = None

    for tok in tokens:
        low = tok.lower()
        if low in ("!h", "!high"):
            priority = "high"
            continue
        if low in ("!m", "!med", "!medium"):
            priority = "medium"
            continue
        if low in ("!l", "!low"):
            priority = "low"
            continue
        if len(tok) > 1 and tok[0] == "#" and re.fullmatch(r"[\w-]+", tok[1:]):
            tags.append(tok[1:].lower())
            continue
        if low == "today":
            date_part = datetime.date.today()
            continue
        if low in ("tomorrow", "tmrw"):
            date_part = datetime.date.today() + datetime.timedelta(days=1)
            continue
        if low in WEEKDAY_MAP:
            date_part = next_weekday(WEEKDAY_MAP[low])
            continue
        m = re.fullmatch(r"\+(\d+)([dhw])", low)
        if m:
            n, unit = int(m.group(1)), m.group(2)
            now = datetime.datetime.now()
            if unit == "d":
                date_part = (now + datetime.timedelta(days=n)).date()
            elif unit == "h":
                target = now + datetime.timedelta(hours=n)
                date_part, time_part = target.date(), (target.hour, target.minute)
            elif unit == "w":
                date_part = (now + datetime.timedelta(weeks=n)).date()
            continue
        m = re.fullmatch(r"(\d{4})-(\d{2})-(\d{2})", tok)
        if m:
            try:
                date_part = datetime.date(
                    int(m.group(1)), int(m.group(2)), int(m.group(3))
                )
            except ValueError:
                pass
            continue
        m = re.fullmatch(r"(\d{1,2})[/-](\d{1,2})", tok)
        if m:
            mo, da = int(m.group(1)), int(m.group(2))
            yr = datetime.date.today().year
            try:
                cand = datetime.date(yr, mo, da)
                if cand < datetime.date.today():
                    cand = datetime.date(yr + 1, mo, da)
                date_part = cand
            except ValueError:
                pass
            continue
        t = parse_time_token(tok)
        if t is not None:
            time_part = t
            continue
        title_tokens.append(tok)

    due_dt = None
    has_time = False
    if date_part or time_part:
        d = date_part or datetime.date.today()
        if time_part:
            due_dt = datetime.datetime.combine(d, datetime.time(*time_part))
            has_time = True
        else:
            due_dt = datetime.datetime.combine(d, datetime.time(9, 0))

    return " ".join(title_tokens).strip(), due_dt, has_time, priority, tags


# ---------------------------------------------------------------- formatting


def fmt_time(dt):
    h = dt.hour % 12 or 12
    return f"{h}:{dt.minute:02d} {'AM' if dt.hour < 12 else 'PM'}"


def format_due(due_dt, has_time):
    today = datetime.date.today()
    d = due_dt.date()
    diff = (d - today).days
    if diff == 0:
        day_str = "Today"
    elif diff == 1:
        day_str = "Tomorrow"
    elif diff == -1:
        day_str = "Yesterday"
    elif -7 < diff < 0:
        day_str = f"{-diff}d overdue"
    elif 0 < diff < 7:
        day_str = due_dt.strftime("%A")
    else:
        day_str = due_dt.strftime("%b %d") + (
            f", {due_dt.year}" if due_dt.year != today.year else ""
        )
    return f"{day_str} {fmt_time(due_dt)}" if has_time else day_str


def section_for(t):
    if t["done"]:
        return "Done"
    if not t.get("due"):
        return "No Due Date"
    diff = (
        datetime.datetime.fromisoformat(t["due"]).date() - datetime.date.today()
    ).days
    if diff < 0:
        return "Overdue"
    if diff == 0:
        return "Today"
    if diff == 1:
        return "Tomorrow"
    if diff < 7:
        return "This Week"
    return "Later"


# ---------------------------------------------------------------- rendering


def build_actions(t):
    actions = [
        {"id": "edit", "title": "Edit", "icon": "edit"},
        {"id": "snooze", "title": "Snooze 1 Day", "icon": "clock"},
        {"id": "due_today", "title": "Set Due: Today", "icon": "calendar"},
        {"id": "due_tomorrow", "title": "Set Due: Tomorrow", "icon": "calendar"},
    ]
    if t.get("due"):
        actions.append({"id": "clear_due", "title": "Clear Due Date", "icon": "close"})
    for p in ("high", "medium", "low"):
        if t.get("priority") != p:
            actions.append(
                {
                    "id": f"priority_{p}",
                    "title": f"Priority: {p.capitalize()}",
                    "icon": "flag",
                }
            )
    if t.get("priority"):
        actions.append(
            {"id": "priority_none", "title": "Clear Priority", "icon": "flag"}
        )
    actions.append(
        {
            "id": "delete",
            "title": "Delete Task",
            "icon": "trash",
            "destructive": True,
            "confirm": {
                "title": "Delete this task?",
                "message": t["title"],
                "confirmLabel": "Delete",
            },
        }
    )
    return actions


def build_preview(t):
    due_dt = datetime.datetime.fromisoformat(t["due"]) if t.get("due") else None
    md = f"## {t['title']}\n\n" + (t.get("notes") or "_No notes_")
    meta = [
        {
            "label": "Status",
            "text": "Done" if t["done"] else "Active",
            "color": "#22C55E" if t["done"] else "#F59E0B",
        },
        {
            "label": "Due",
            "text": format_due(due_dt, t.get("has_time", False)) if due_dt else "—",
            "icon": "calendar",
        },
        {
            "label": "Priority",
            "text": t["priority"].capitalize() if t.get("priority") else "None",
            "color": PRIORITY_COLORS.get(t.get("priority")),
        },
        {
            "label": "Tags",
            "text": ", ".join(f"#{x}" for x in t.get("tags", [])) or "—",
            "icon": "tag",
        },
        {"separator": True},
        {
            "label": "Created",
            "text": datetime.datetime.fromisoformat(t["created"]).strftime(
                "%b %d, %Y %I:%M %p"
            ),
        },
    ]
    if t["done"] and t.get("completed"):
        meta.append(
            {
                "label": "Completed",
                "text": datetime.datetime.fromisoformat(t["completed"]).strftime(
                    "%b %d, %Y %I:%M %p"
                ),
            }
        )
    return {"markdown": md, "metadata": meta}


def build_item(t):
    due_dt = datetime.datetime.fromisoformat(t["due"]) if t.get("due") else None
    overdue = (not t["done"]) and due_dt and due_dt < datetime.datetime.now()
    accessories = []
    if t.get("priority"):
        accessories.append(
            {
                "text": t["priority"].capitalize(),
                "color": PRIORITY_COLORS[t["priority"]],
            }
        )
    if due_dt:
        chip = {"text": format_due(due_dt, t.get("has_time", False)), "icon": "clock"}
        if overdue:
            chip["color"] = "#EF4444"
        accessories.append(chip)
    for tag in t.get("tags", [])[:3]:
        accessories.append({"text": f"#{tag}", "icon": "tag"})

    icon = "check" if t["done"] else PRIORITY_COLORS.get(t.get("priority"), "#94A3B8")
    subtitle = t.get("notes", "")[:90]
    return {
        "id": t["id"],
        "title": ("✓ " if t["done"] else "") + t["title"],
        "subtitle": subtitle,
        "icon": icon,
        "section": section_for(t),
        "lines": 2 if subtitle else 1,
        "accessories": accessories,
        "actions": build_actions(t),
        "preview": build_preview(t),
    }


QUICKADD_SYNTAX_MD = """## Quick-add syntax

| Token | Meaning |
|---|---|
| `!h` / `!high` | priority: high |
| `!m` / `!med` / `!medium` | priority: medium |
| `!l` / `!low` | priority: low |
| `#tag` | one or more tags |
| `today` | due today |
| `tomorrow` / `tmrw` | due tomorrow |
| `mon` … `sun` | due next occurrence of that weekday |
| `+3d` / `+2h` / `+1w` | due N days / hours / weeks from now |
| `2026-07-22` | explicit date |
| `7/22` or `7-22` | explicit date, month/day |
| `5pm`, `5:30pm`, `17:00` | time of day |

Anything left over becomes the title."""


def build_quickadd_preview(title, due_dt, has_time, priority, tags):
    parsed = [
        {"label": "Title", "text": title or "—"},
        {
            "label": "Due",
            "text": format_due(due_dt, has_time) if due_dt else "—",
            "icon": "calendar",
        },
        {
            "label": "Priority",
            "text": priority.capitalize() if priority else "None",
            "color": PRIORITY_COLORS.get(priority),
        },
        {
            "label": "Tags",
            "text": ", ".join(f"#{x}" for x in tags) or "—",
            "icon": "tag",
        },
        {"separator": True},
    ]
    return {"markdown": QUICKADD_SYNTAX_MD, "metadata": parsed}


def render_list(rev, query):
    state["screen"] = "list"
    q = query.strip()
    items = []

    if q:
        title, due_dt, has_time, priority, tags = parse_quick_add(q)
        if title:
            parts = []
            if due_dt:
                parts.append(format_due(due_dt, has_time))
            if priority:
                parts.append(f"!{priority}")
            if tags:
                parts.append(" ".join(f"#{x}" for x in tags))
            subtitle = "Press Enter to add" + (
                " · " + " · ".join(parts) if parts else ""
            )
            items.append(
                {
                    "id": "__quickadd__",
                    "title": f"Add: {title}",
                    "subtitle": subtitle,
                    "icon": "add",
                    "section": "Add New",
                    "actions": [{"id": "default", "title": "Add", "icon": "add"}],
                    "preview": build_quickadd_preview(
                        title, due_dt, has_time, priority, tags
                    ),
                }
            )

    def matches(t):
        if not q:
            return True
        hay = (
            t["title"] + " " + t.get("notes", "") + " " + " ".join(t.get("tags", []))
        ).lower()
        return q.lower() in hay

    visible = [
        t
        for t in state["tasks"]
        if matches(t) and (not t["done"] or not state["hide_done"])
    ]

    def sort_key(t):
        return (
            SECTION_ORDER.index(section_for(t)),
            t.get("due") or "9999",
            PRIORITY_RANK.get(t.get("priority")),
            t["created"],
        )

    visible.sort(key=sort_key)
    items.extend(build_item(t) for t in visible)

    empty_text = (
        "No tasks match — type to add one"
        if q
        else "No tasks yet — type something and press Enter to add"
    )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "preview": {"enabled": True},
            "placeholder": "Add a task, or search… (try: Buy milk tomorrow 5pm !h #errands)",
            "emptyText": empty_text,
            "actions": [
                {
                    "id": "add_full",
                    "title": "New Task (Full Form)",
                    "icon": "add",
                    "shortcut": "ctrl+n",
                },
                {
                    "id": "toggle_hide_done",
                    "title": "Show Completed"
                    if state["hide_done"]
                    else "Hide Completed",
                    "icon": "check",
                },
                {
                    "id": "clear_completed",
                    "title": "Clear Completed Tasks",
                    "icon": "trash",
                    "destructive": True,
                    "confirm": {
                        "title": "Clear completed?",
                        "message": "Permanently delete all completed tasks.",
                        "confirmLabel": "Clear",
                    },
                },
            ],
            "items": items,
        }
    )


def form_fields(prefill=None, error_field=None, error_msg=None):
    prefill = prefill or {}
    existing_tags = sorted({tag for t in state["tasks"] for tag in t.get("tags", [])})
    fields = [
        {
            "id": "title",
            "type": "text",
            "label": "Title",
            "placeholder": "What needs to be done?",
            "required": True,
        },
        {"id": "notes", "type": "textarea", "label": "Notes"},
        {"id": "due", "type": "date", "label": "Due date"},
        {
            "id": "due_time",
            "type": "text",
            "label": "Due time",
            "placeholder": "e.g. 17:00 or 5pm (optional)",
        },
        {
            "id": "priority",
            "type": "dropdown",
            "label": "Priority",
            "value": "none",
            "options": ["none", "low", "medium", "high"],
        },
        {"id": "tags", "type": "tags", "label": "Tags", "options": existing_tags},
    ]
    for f in fields:
        if f["id"] in prefill:
            f["value"] = prefill[f["id"]]
        if f["id"] == error_field:
            f["error"] = error_msg
    return fields


def render_form_add(rev, error_field=None, error_msg=None):
    state["screen"] = "form_add"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "canGoBack": True,
            "form": {
                "title": "New Task",
                "submitLabel": "Add Task",
                "fields": form_fields(error_field=error_field, error_msg=error_msg),
            },
        }
    )


def render_form_edit(rev, t, error_field=None, error_msg=None):
    state["screen"] = "form_edit"
    due_dt = datetime.datetime.fromisoformat(t["due"]) if t.get("due") else None
    prefill = {
        "title": t["title"],
        "notes": t.get("notes", ""),
        "priority": t.get("priority") or "none",
        "tags": t.get("tags", []),
    }
    if due_dt:
        prefill["due"] = due_dt.date().isoformat()
        if t.get("has_time"):
            prefill["due_time"] = due_dt.strftime("%H:%M")
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "canGoBack": True,
            "form": {
                "title": "Edit Task",
                "submitLabel": "Save Changes",
                "fields": form_fields(
                    prefill=prefill, error_field=error_field, error_msg=error_msg
                ),
            },
        }
    )


# ---------------------------------------------------------------- handlers


def handle_action(item_id, action):
    if item_id == "__quickadd__" and action == "default":
        title, due_dt, has_time, priority, tags = parse_quick_add(state["query"])
        if not title:
            send(
                {
                    "type": "command",
                    "command": "toast",
                    "text": "Type a task title first",
                    "style": "error",
                }
            )
            return
        state["tasks"].append(new_task(title, "", due_dt, has_time, priority, tags))
        save_tasks()
        send({"type": "command", "command": "setQuery", "text": ""})
        send(
            {
                "type": "command",
                "command": "toast",
                "text": f"Added \u201c{title}\u201d",
            }
        )
        state["query"] = ""
        render_list(0, "")
        return

    if item_id == "":
        if action == "add_full":
            render_form_add(0)
        elif action == "toggle_hide_done":
            state["hide_done"] = not state["hide_done"]
            render_list(0, state["query"])
        elif action == "clear_completed":
            state["tasks"] = [t for t in state["tasks"] if not t["done"]]
            save_tasks()
            send(
                {
                    "type": "command",
                    "command": "toast",
                    "text": "Completed tasks cleared",
                }
            )
            render_list(0, state["query"])
        return

    t = find_task(item_id)
    if not t:
        render_list(0, state["query"])
        return

    if action == "default":
        t["done"] = not t["done"]
        t["completed"] = datetime.datetime.now().isoformat() if t["done"] else None
    elif action == "edit":
        state["editing_id"] = item_id
        render_form_edit(0, t)
        return
    elif action == "snooze":
        base = (
            datetime.datetime.fromisoformat(t["due"])
            if t.get("due")
            else datetime.datetime.now()
        )
        t["due"] = (base + datetime.timedelta(days=1)).isoformat()
        t["notified"] = False
    elif action == "due_today":
        t["due"] = datetime.datetime.combine(
            datetime.date.today(), datetime.time(9, 0)
        ).isoformat()
        t["has_time"] = False
        t["notified"] = False
    elif action == "due_tomorrow":
        t["due"] = datetime.datetime.combine(
            datetime.date.today() + datetime.timedelta(days=1), datetime.time(9, 0)
        ).isoformat()
        t["has_time"] = False
        t["notified"] = False
    elif action == "clear_due":
        t["due"] = None
        t["has_time"] = False
    elif action.startswith("priority_"):
        p = action.split("_", 1)[1]
        t["priority"] = None if p == "none" else p
    elif action == "delete":
        state["tasks"] = [x for x in state["tasks"] if x["id"] != item_id]
        save_tasks()
        send({"type": "command", "command": "toast", "text": "Task deleted"})
        render_list(0, state["query"])
        return
    else:
        return

    save_tasks()
    render_list(0, state["query"])


def handle_submit(values, button):
    if state["screen"] not in ("form_add", "form_edit"):
        return

    title = (values.get("title") or "").strip()
    notes = (values.get("notes") or "").strip()
    due_date_str = values.get("due")
    due_time_str = (values.get("due_time") or "").strip()
    priority = values.get("priority")
    if priority == "none":
        priority = None
    tags = [x.lower() for x in (values.get("tags") or [])]

    parsed_time = None
    if due_time_str:
        parsed_time = parse_time_token(due_time_str)
        if parsed_time is None:
            err = ("Use a format like 17:00 or 5pm", values.get("title"))
            renderer = (
                render_form_add
                if state["screen"] == "form_add"
                else (
                    lambda rev, error_field=None, error_msg=None: render_form_edit(
                        rev, find_task(state["editing_id"]), error_field, error_msg
                    )
                )
            )
            renderer(
                0, error_field="due_time", error_msg="Use a format like 17:00 or 5pm"
            )
            return

    due_dt, has_time = None, False
    if due_date_str:
        y, m, d = map(int, due_date_str.split("-"))
        base_date = datetime.date(y, m, d)
        if parsed_time:
            due_dt, has_time = (
                datetime.datetime.combine(base_date, datetime.time(*parsed_time)),
                True,
            )
        else:
            due_dt = datetime.datetime.combine(base_date, datetime.time(9, 0))
    elif parsed_time:
        cand = datetime.datetime.combine(
            datetime.date.today(), datetime.time(*parsed_time)
        )
        if cand < datetime.datetime.now():
            cand += datetime.timedelta(days=1)
        due_dt, has_time = cand, True

    if state["screen"] == "form_add":
        state["tasks"].append(new_task(title, notes, due_dt, has_time, priority, tags))
        save_tasks()
        send(
            {
                "type": "command",
                "command": "toast",
                "text": f"Added \u201c{title}\u201d",
            }
        )
    else:
        t = find_task(state["editing_id"])
        if t:
            t.update(
                {
                    "title": title,
                    "notes": notes,
                    "due": due_dt.isoformat() if due_dt else None,
                    "has_time": has_time,
                    "priority": priority,
                    "tags": tags,
                    "notified": False,
                }
            )
            save_tasks()
            send({"type": "command", "command": "toast", "text": "Saved changes"})

    state["screen"] = "list"
    render_list(0, state["query"])


# ---------------------------------------------------------------- main loop


def main():
    state["tasks"] = load_tasks()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue

        try:
            t = msg.get("type")
            if t == "close":
                break
            elif t in ("init", "query"):
                state["query"] = msg.get("text", msg.get("query", ""))
                if state["screen"] == "list":
                    render_list(msg.get("rev", 0), state["query"])
            elif t == "action":
                handle_action(msg.get("id", ""), msg.get("action", "default"))
            elif t == "submit":
                handle_submit(msg.get("values", {}), msg.get("button"))
            elif t == "back":
                render_list(msg.get("rev", 0), state["query"])
        except Exception as e:
            log("handler error:", e)
            send(
                {
                    "type": "render",
                    "rev": 0,
                    "view": "detail",
                    "detail": {"markdown": f"# Error\n\n```\n{e}\n```"},
                }
            )


if __name__ == "__main__":
    main()
