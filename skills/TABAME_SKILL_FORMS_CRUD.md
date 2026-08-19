---
name: tbm-plugin-forms-crud
description: Author a Tabame QuickLaunch plugin for creating, editing, organizing, and acting on records using list/table/kanban/calendar views, full forms, Ctrl+K, floating actions, confirmations, bulk selection, page history, and persistent storage. Use for task managers, issue trackers, settings, CRUD tools, planners, and record-management plugins.
---

# Tabame QuickLaunch Plugin — Forms & Record Management Skill

> Treat this document as authoritative for record-management plugins. Do not
> invent fields, commands, or events. This skill focuses on list/form workflows,
> Ctrl+K actions, validation, page navigation, bulk operations, and persistence.

## 1. When to use this skill

Use this skill when a plugin manages records rather than only searching them.

Typical plugins:

- tasks, notes, issues, bookmarks, contacts, inventory;
- settings/configuration editors;
- create/edit/delete workflows;
- planners and calendars;
- kanban boards and approval queues;
- small administrative tools and API-backed CRUD clients.

Common page flow:

```text
Home/list       list/table/kanban/calendar   browse and choose records
Record detail   detail                       inspect one record
Create/Edit     form                         enter validated values
Success         detail or previous page      show result and return
```

Use visible primary interactions:

- Enter opens the selected record or performs its obvious default action.
- `floatingAction` exposes important verbs such as Create or Add.
- Ctrl+K contains contextual alternatives such as Edit, Duplicate, Archive,
  Delete, Export, or page-wide Refresh/Settings.
- A full `form` is preferred when fields need explanation, validation,
  conditional visibility, dependencies, or editing.
- An action's compact `parameters` are only for a small one-shot choice.

---

## 2. Plugin model and transport

A Tabame plugin is a long-running Python, Node.js, or Bun process activated by a
keyword. It exchanges newline-delimited JSON through stdin/stdout.

- stdin receives UI events;
- stdout sends complete render frames and host commands;
- stderr is for logs.

Rules:

1. One JSON object per line.
2. Flush after every stdout message.
3. Never print debug text to stdout.
4. Handle `close` and EOF.
5. Use stable item, page, panel, and element IDs.
6. Do not block the stdin loop with slow requests.

---

## 3. Folder, manifest, runtime, and dependencies

```text
%localappdata%\Tabame\plugins\<plugin-id>\
    plugin.json
    main.py / main.js / main.ts
    optional config/assets/dependency files
```

Example manifest:

```json
{
  "id": "task-manager",
  "name": "Task Manager",
  "description": "Create and manage local tasks",
  "keyword": "task",
  "runtime": "python",
  "version": "1.0.0",
  "entry": "main.py",
  "icon": "check",
  "args": [],
  "pip": [],
  "env": {},
  "dev": true
}
```

Required fields are `keyword`, `runtime`, `version`, `entry`, `id`, `name`,
`description`, and `icon`. `runtime` is `python`, `node`, or `bun` and must be on
`PATH`. The process starts in the plugin folder without a shell.

Python dependencies may be declared in `pip` or `requirements.txt`; Tabame
installs them into `.pluginlibs`. Node/Bun dependencies belong in
`package.json`; Tabame runs the matching installer when needed.

During development, `dev: true` enables hot reload and the on-screen debug
console. Disable it before sharing.

---

## 4. Relevant inbound messages

### Query and lifecycle

```json
{"type":"init","query":"","protocol":13,"theme":{"accent":"#63A0EA","text":"#E8E8E8","background":"#1B1D23","dark":true},"locale":"en-US"}
{"type":"query","text":"urgent","rev":4}
{"type":"close"}
```

`init` is followed by a `query`. Treat both through the same query route.

### `action`

```json
{"type":"action","id":"task:42","action":"default"}
{"type":"action","id":"task:42","action":"edit"}
{"type":"action","id":"","action":"create"}
{"type":"action","id":"","action":"archive-selected","ids":["task:1","task:2"]}
```

Optional `parameters` contains values from compact action inputs. `action` has
no `rev`; action-result frames should normally use `rev: 0`.

### `submit`

Sent when a form is submitted:

```json
{
  "type": "submit",
  "values": {
    "title": "Fix login",
    "description": "Reproduce and patch the issue",
    "priority": "high",
    "urgent": true,
    "estimate": 3,
    "labels": ["bug", "auth"]
  },
  "button": "save"
}
```

`button` is absent when the default submit CTA was used. Validate server-side
business rules and either re-render the form with errors or navigate to a result.

### `change`

A field with `watch: true` changed:

```json
{
  "type": "change",
  "id": "project",
  "values": { "project": "core", "assignee": "" }
}
```

Re-render the same form with updated options/conditions. Keep field IDs stable so
entered values survive.

### `select`

```json
{ "type": "select", "id": "task:42", "rev": 4 }
```

Optional for record workflows unless lazy data loading is needed.

### `back` and `navigate`

```json
{"type":"back","rev":4,"fromPageId":"tasks:edit:42","toPageId":"tasks:item:42"}
{"type":"navigate","targetPageId":"tasks:home","rev":4}
```

The plugin owns its routes and renders the destination.

### `kanbanMove`

```json
{
  "type": "kanbanMove",
  "id": "task:42",
  "columnId": "done",
  "index": 0,
  "rev": 4
}
```

Apply the move and render the complete board.

### `calendarNavigate`

```json
{
  "type": "calendarNavigate",
  "date": "2026-08-01",
  "mode": "month",
  "rev": 4
}
```

Update date/mode state and render the complete calendar frame.

### `storage`

Reply to a `storage` `get`/`keys` command:

```json
{"type":"storage","requestId":"load-tasks","key":"tasks","value":[...]}
```

Correlate with `requestId`.

---

## 5. `rev` and route rules

- Query/filter responses echo the latest query `rev`.
- Action, submit, storage, navigation, and unsolicited refresh frames use
  `rev: 0`.
- A loading frame and its final query result use the same query `rev`.
- Stable page IDs represent conceptual destinations, never transient state.
- Use `history: "push"` for forward navigation, `replace` for redirects, and
  `none` for refreshes.
- Handle `back.toPageId` and `navigate.targetPageId`.
- Clear stale query text with `setQuery` when navigating to a page where typing
  has a different meaning.

Example page IDs:

```text
tasks:home
tasks:item:42
tasks:create
tasks:edit:42
tasks:board
tasks:calendar
```

---

## 6. Host commands for record workflows

```json
{
  "type": "command",
  "command": "toast",
  "text": "Task saved",
  "style": "success"
}
```

Relevant commands:

| Command    | Fields                                      | Use                                            |
| ---------- | ------------------------------------------- | ---------------------------------------------- |
| `copy`     | `text`                                      | Copy field/record content.                     |
| `paste`    | `text`                                      | Paste into the previous app and hide launcher. |
| `open`     | `url` or `path`                             | Open linked resource.                          |
| `hide`     | —                                           | Dismiss launcher.                              |
| `toast`    | `text`, optional `style`, `progress`        | Feedback after create/update/delete.           |
| `setQuery` | `text`                                      | Reset/rewrite post-keyword query.              |
| `storage`  | `op`, `key`, `value`, `secret`, `requestId` | Persistent plugin state and secrets.           |
| `notify`   | optional `title`, `text`                    | Native Windows notification.                   |

Storage operations:

```python
send({
    "type": "command", "command": "storage",
    "op": "set", "key": "tasks", "value": tasks
})
send({
    "type": "command", "command": "storage",
    "op": "get", "key": "tasks", "requestId": "load-tasks"
})
send({
    "type": "command", "command": "storage",
    "op": "delete", "key": "tasks"
})
```

Plain values live in `.tabame-store.json`. Use `secret: true` for string secrets,
which are stored through Windows Credential Manager and are not returned by
`keys`.

---

## 7. Shared frame and item fields

Example list frame:

```jsonc
{
  "type": "render",
  "rev": 0,
  "view": "list",
  "page": {
    "id": "tasks:home",
    "title": "Tasks",
    "history": "none",
    "preserveState": true,
  },
  "elementId": "task-list",
  "placeholder": "Filter tasks…",
  "loading": false,
  "loadingText": "Loading tasks…",
  "empty": {
    "icon": "check",
    "title": "No tasks",
    "hint": "Create your first task",
    "action": { "id": "create", "title": "Create task", "icon": "add" },
  },
  "selection": { "enabled": true, "max": 100 },
  "actions": [
    { "id": "refresh", "title": "Refresh", "icon": "refresh" },
    { "id": "archive-selected", "title": "Archive selected", "icon": "folder" },
  ],
  "floatingAction": { "id": "create", "title": "Create", "icon": "add" },
  "items": [],
}
```

General record item:

```jsonc
{
  "id": "task:42",
  "title": "Fix login",
  "subtitle": "Authentication fails after token expiry",
  "icon": "warning",
  "section": "Today",
  "accessories": [
    { "text": "High", "color": "#EF4444" },
    { "text": "Core", "icon": "people" },
  ],
  "cells": { "status": "In progress", "owner": "Alex", "due": "Aug 8" },
  "column": "doing",
  "start": "2026-08-08T10:00:00",
  "end": "2026-08-08T11:00:00",
  "allDay": false,
  "color": "#EF4444",
  "location": "Online",
  "actions": [
    { "id": "default", "title": "Open", "icon": "open" },
    { "id": "edit", "title": "Edit", "icon": "edit" },
    { "id": "duplicate", "title": "Duplicate", "icon": "copy" },
    {
      "id": "delete",
      "title": "Delete",
      "icon": "trash",
      "destructive": true,
      "confirm": true,
    },
  ],
}
```

Use `accessories` for terse scan facts and metadata on detail pages for aligned
record facts.

---

## 8. List, table, detail, kanban, and calendar

### `list`

Use when each record has one dominant title and a few concise scan facts. Group
adjacent records with `section`. Enter should open the record or perform the most
obvious action.

### `table`

Use when the same 3–6 fields must be compared:

```jsonc
{
  "view": "table",
  "columns": [
    { "id": "title", "label": "Task", "width": 260 },
    { "id": "status", "label": "Status" },
    { "id": "owner", "label": "Owner" },
    { "id": "estimate", "label": "Hours", "align": "end" },
  ],
  "items": [
    {
      "id": "task:42",
      "title": "Fix login",
      "cells": { "status": "Doing", "owner": "Alex", "estimate": "3" },
    },
  ],
}
```

List/table both support selection and item actions.

### `detail`

Use for one record, a success/error result, or a confirmation:

```jsonc
{
  "view": "detail",
  "page": {
    "id": "tasks:item:42",
    "title": "Fix login",
    "history": "push",
    "preserveState": true,
    "breadcrumbs": [{ "id": "tasks:home", "label": "Tasks" }],
  },
  "detail": {
    "wide": true,
    "markdown": "# Fix login\n\nAuthentication fails after token expiry.",
    "metadata": [
      { "label": "Status", "text": "In progress", "color": "#F59E0B" },
      { "label": "Owner", "text": "Alex", "icon": "person" },
      { "label": "Due", "text": "August 8, 2026", "icon": "calendar" },
    ],
  },
  "actions": [
    { "id": "edit", "title": "Edit", "icon": "edit" },
    {
      "id": "delete",
      "title": "Delete",
      "icon": "trash",
      "destructive": true,
      "confirm": true,
    },
  ],
  "floatingAction": { "id": "edit", "title": "Edit", "icon": "edit" },
}
```

Frame-level actions on detail arrive with `id: ""`; retain the current record ID
in plugin state.

### `kanban`

```jsonc
{
  "view": "kanban",
  "kanban": {
    "columns": [
      { "id": "todo", "title": "To do", "color": "#64748B" },
      { "id": "doing", "title": "Doing", "color": "#3B82F6", "limit": 5 },
      { "id": "done", "title": "Done", "color": "#22C55E" },
    ],
  },
  "items": [{ "id": "task:42", "title": "Fix login", "column": "doing" }],
}
```

A drop sends `kanbanMove`. Persist the new column/order, then render the complete
board.

### `calendar`

```jsonc
{
  "view": "calendar",
  "calendar": {
    "mode": "month",
    "date": "2026-08-01",
    "weekStart": "monday",
    "days": 30,
  },
  "items": [
    {
      "id": "event:1",
      "title": "Release",
      "start": "2026-08-08T10:00:00",
      "end": "2026-08-08T11:00:00",
      "color": "#8B5CF6",
      "location": "Online",
    },
  ],
}
```

The calendar header sends `calendarNavigate`; update mode/date and re-render.

---

## 9. Full form reference

A form frame:

```jsonc
{
  "type": "render",
  "rev": 0,
  "view": "form",
  "page": {
    "id": "tasks:create",
    "title": "New Task",
    "history": "push",
    "preserveState": false,
    "breadcrumbs": [{ "id": "tasks:home", "label": "Tasks" }],
  },
  "placeholder": "New task…",
  "form": {
    "title": "New Task",
    "error": "Please review the highlighted fields",
    "sections": [
      { "id": "main", "title": "Task", "description": "Required details" },
      { "id": "advanced", "title": "Advanced", "collapsible": true },
    ],
    "submitLabel": "Create",
    "buttons": [
      { "id": "save", "label": "Save" },
      { "id": "save-close", "label": "Save and close" },
      { "id": "delete", "label": "Delete", "destructive": true },
    ],
    "fields": [
      {
        "id": "title",
        "type": "text",
        "label": "Title",
        "placeholder": "Summary…",
        "required": true,
        "minLength": 3,
        "maxLength": 120,
        "description": "Shown in the task list",
        "section": "main",
      },
      {
        "id": "description",
        "type": "textarea",
        "label": "Description",
        "section": "main",
      },
      {
        "id": "secret",
        "type": "password",
        "label": "API key",
        "section": "advanced",
      },
      {
        "id": "estimate",
        "type": "number",
        "label": "Estimate",
        "value": 1,
        "min": 0,
        "max": 100,
        "section": "main",
      },
      {
        "id": "due",
        "type": "date",
        "label": "Due date",
        "value": "2026-08-08",
        "section": "main",
      },
      {
        "id": "attachment",
        "type": "filepicker",
        "label": "Attachment",
        "section": "advanced",
      },
      {
        "id": "output",
        "type": "folderpicker",
        "label": "Output folder",
        "section": "advanced",
      },
      {
        "id": "labels",
        "type": "tags",
        "label": "Labels",
        "value": ["bug"],
        "options": ["bug", "feature", { "value": "docs", "label": "Docs" }],
        "section": "main",
      },
      {
        "id": "project",
        "type": "combobox",
        "label": "Project",
        "value": "core",
        "watch": true,
        "optionsLoading": false,
        "allowCustom": false,
        "options": ["core", { "value": "ops", "label": "Operations" }],
        "section": "main",
      },
      {
        "id": "priority",
        "type": "dropdown",
        "label": "Priority",
        "value": "normal",
        "options": ["low", "normal", "high"],
        "section": "main",
        "enabledWhen": { "field": "title", "truthy": true },
      },
      {
        "id": "urgent",
        "type": "checkbox",
        "label": "Urgent",
        "value": false,
        "section": "main",
      },
      {
        "id": "reason",
        "type": "textarea",
        "label": "Urgency reason",
        "section": "main",
        "visibleWhen": { "field": "urgent", "equals": true },
      },
    ],
  },
}
```

### Supported field types

- `text`
- `password`
- `textarea`
- `dropdown`
- `combobox`
- `checkbox`
- `number`
- `date`
- `filepicker`
- `folderpicker`
- `tags`

Unknown field types fall back to text.

### Values sent on submit

- text/password/textarea/dropdown/combobox/date/file/folder → string;
- checkbox → boolean;
- number → number, or null when empty;
- tags → string array.

### Validation

Host validation supports:

- `required`;
- number `min`/`max`;
- text `minLength`, `maxLength`, `pattern`;
- custom `validationMessage`.

For business/server validation, re-render the same form and put an `error` on the
form or offending field. Keep the field set and IDs unchanged so typed values
survive.

### Sections and conditions

- `sections` groups fields; sections may be `collapsible`.
- `visibleWhen` and `enabledWhen` accept
  `{field, equals?, notEquals?, in?, truthy?}`.
- `watch: true` sends `change` with all current values.
- A watched combobox can be re-rendered with new `options` and
  `optionsLoading: true/false` for async options.
- `allowCustom: true` permits a value outside the option list.

### Buttons

`buttons` replaces the single default CTA. The submitted button ID appears as
`submit.button`. `destructive: true` applies danger styling; the plugin still
owns business logic and should show confirmation where appropriate before
presenting destructive form paths.

---

## 10. Actions, Ctrl+K, floating actions, and bulk selection

Action shape:

```jsonc
{
  "id": "move",
  "title": "Move tasks",
  "icon": "folder",
  "shortcut": "ctrl+shift+m",
  "destructive": false,
  "confirm": false,
  "parameters": [
    {
      "id": "status",
      "type": "dropdown",
      "label": "Destination",
      "required": true,
      "options": ["todo", "doing", "done"],
    },
  ],
}
```

Rules:

- Enter sends `default` for the highlighted item.
- Item Ctrl+K actions arrive with that item ID.
- Frame actions/floating actions arrive with `id: ""`.
- Bulk-selected IDs arrive in `action.ids`.
- Shortcuts require Ctrl and/or Alt.
- Destructive actions should use `destructive: true` plus `confirm`.
- A listed action with ID `default` and a confirmation gates Enter.
- `parameters` values arrive in `action.parameters`.

Selection:

```json
{ "selection": { "enabled": true, "max": 50 } }
```

Use it when users reasonably perform the same action on several records. Name
bulk actions clearly and operate on `action.ids`, not only the highlighted item.

---

## 11. Complete Python example: task list + create/edit form + Ctrl+K

This example provides a complete local task manager skeleton. It demonstrates:

- list filtering;
- detail, create, and edit routes;
- page history and breadcrumbs;
- form validation;
- floating Create/Edit actions;
- Ctrl+K complete/edit/delete actions;
- destructive confirmation;
- bulk completion;
- persistent state using Tabame `storage`.

`plugin.json`:

```json
{
  "id": "local-tasks",
  "name": "Local Tasks",
  "description": "Create and manage tasks",
  "keyword": "task",
  "runtime": "python",
  "version": "1.0.0",
  "entry": "main.py",
  "icon": "check",
  "dev": true
}
```

`main.py`:

````python
#!/usr/bin/env python3
import json
import sys
import uuid

state = {
    "tasks": [],
    "loaded": False,
    "storage_requested": False,
    "query": "",
    "page": "tasks:home",
    "current_id": None,
}


def send(message):
    sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def storage_get():
    send({
        "type": "command",
        "command": "storage",
        "op": "get",
        "key": "tasks",
        "requestId": "load-tasks",
    })


def storage_save():
    send({
        "type": "command",
        "command": "storage",
        "op": "set",
        "key": "tasks",
        "value": state["tasks"],
    })


def task_by_item_id(item_id):
    raw_id = item_id.removeprefix("task:")
    return next((t for t in state["tasks"] if t["id"] == raw_id), None)


def filtered_tasks():
    query = state["query"].strip().lower()
    if not query:
        return state["tasks"]
    return [
        task for task in state["tasks"]
        if query in task["title"].lower()
        or query in task.get("description", "").lower()
        or query in task.get("priority", "").lower()
    ]


def task_item(task):
    completed = task.get("completed", False)
    priority = task.get("priority", "normal")
    priority_color = {
        "low": "#22C55E",
        "normal": "#3B82F6",
        "high": "#EF4444",
    }.get(priority, "#3B82F6")

    return {
        "id": f"task:{task['id']}",
        "title": task["title"],
        "subtitle": task.get("description") or "No description",
        "icon": "check" if completed else "note",
        "section": "Completed" if completed else "Open",
        "accessories": [
            {"text": priority.title(), "color": priority_color},
            *([{"text": task["due"], "icon": "calendar"}] if task.get("due") else []),
        ],
        "actions": [
            {"id": "default", "title": "Open", "icon": "open"},
            {"id": "toggle-complete", "title": "Reopen" if completed else "Complete", "icon": "check"},
            {"id": "edit", "title": "Edit", "icon": "edit"},
            {
                "id": "delete",
                "title": "Delete",
                "icon": "trash",
                "destructive": True,
                "confirm": {
                    "title": "Delete this task?",
                    "message": "This cannot be undone.",
                    "confirmLabel": "Delete",
                },
            },
        ],
    }


def render_home(rev=0, history="none"):
    state["page"] = "tasks:home"
    state["current_id"] = None

    if not state["loaded"]:
        send({
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": {"id": "tasks:home", "title": "Tasks", "history": history},
            "loading": True,
            "loadingText": "Loading tasks…",
            "items": [],
        })
        return

    tasks = sorted(filtered_tasks(), key=lambda t: (t.get("completed", False), t["title"].lower()))
    send({
        "type": "render",
        "rev": rev,
        "view": "list",
        "page": {
            "id": "tasks:home",
            "title": "Tasks",
            "history": history,
            "preserveState": True,
        },
        "elementId": "task-list",
        "placeholder": "Filter tasks…",
        "selection": {"enabled": True, "max": 100},
        "empty": {
            "icon": "check",
            "title": "No tasks",
            "hint": "Create your first task",
            "action": {"id": "create", "title": "Create task", "icon": "add"},
        },
        "actions": [
            {"id": "create", "title": "Create task", "icon": "add"},
            {"id": "complete-selected", "title": "Complete selected", "icon": "check"},
        ],
        "floatingAction": {"id": "create", "title": "Create", "icon": "add"},
        "items": [task_item(task) for task in tasks],
    })


def render_detail(task, history="push"):
    state["page"] = f"tasks:item:{task['id']}"
    state["current_id"] = task["id"]
    send({
        "type": "render",
        "rev": 0,
        "view": "detail",
        "page": {
            "id": state["page"],
            "title": task["title"],
            "history": history,
            "preserveState": True,
            "breadcrumbs": [{"id": "tasks:home", "label": "Tasks"}],
        },
        "detail": {
            "wide": True,
            "markdown": f"# {task['title']}\n\n{task.get('description') or '_No description_'}",
            "metadata": [
                {"label": "Status", "text": "Completed" if task.get("completed") else "Open"},
                {"label": "Priority", "text": task.get("priority", "normal").title()},
                *([{"label": "Due", "text": task["due"], "icon": "calendar"}] if task.get("due") else []),
            ],
        },
        "actions": [
            {"id": "toggle-complete", "title": "Reopen" if task.get("completed") else "Complete", "icon": "check"},
            {"id": "edit", "title": "Edit", "icon": "edit"},
            {"id": "delete", "title": "Delete", "icon": "trash", "destructive": True, "confirm": True},
        ],
        "floatingAction": {"id": "edit", "title": "Edit", "icon": "edit"},
    })


def render_form(task=None, error=None, history="push"):
    editing = task is not None
    page_id = f"tasks:edit:{task['id']}" if editing else "tasks:create"
    state["page"] = page_id
    state["current_id"] = task["id"] if editing else None

    form = {
        "title": "Edit Task" if editing else "New Task",
        "submitLabel": "Save" if editing else "Create",
        "fields": [
            {
                "id": "title",
                "type": "text",
                "label": "Title",
                "value": task["title"] if editing else "",
                "required": True,
                "minLength": 3,
                "maxLength": 120,
            },
            {
                "id": "description",
                "type": "textarea",
                "label": "Description",
                "value": task.get("description", "") if editing else "",
            },
            {
                "id": "priority",
                "type": "dropdown",
                "label": "Priority",
                "value": task.get("priority", "normal") if editing else "normal",
                "options": ["low", "normal", "high"],
            },
            {
                "id": "due",
                "type": "date",
                "label": "Due date",
                "value": task.get("due", "") if editing else "",
            },
            {
                "id": "completed",
                "type": "checkbox",
                "label": "Completed",
                "value": task.get("completed", False) if editing else False,
            },
        ],
    }
    if error:
        form["error"] = error

    send({
        "type": "render",
        "rev": 0,
        "view": "form",
        "page": {
            "id": page_id,
            "title": form["title"],
            "history": history,
            "preserveState": editing,
            "breadcrumbs": [
                {"id": "tasks:home", "label": "Tasks"},
                *([{"id": f"tasks:item:{task['id']}", "label": task["title"]}] if editing else []),
            ],
        },
        "form": form,
    })


def save_form(values):
    title = str(values.get("title", "")).strip()
    if len(title) < 3:
        current = next((t for t in state["tasks"] if t["id"] == state["current_id"]), None)
        render_form(current, "Title must contain at least 3 characters", history="none")
        return

    if state["current_id"]:
        task = next((t for t in state["tasks"] if t["id"] == state["current_id"]), None)
        if not task:
            render_home(0)
            return
        task.update({
            "title": title,
            "description": str(values.get("description", "")),
            "priority": str(values.get("priority", "normal")),
            "due": str(values.get("due", "")),
            "completed": bool(values.get("completed", False)),
        })
    else:
        task = {
            "id": uuid.uuid4().hex,
            "title": title,
            "description": str(values.get("description", "")),
            "priority": str(values.get("priority", "normal")),
            "due": str(values.get("due", "")),
            "completed": bool(values.get("completed", False)),
        }
        state["tasks"].append(task)

    storage_save()
    send({"type": "command", "command": "toast", "text": "Task saved", "style": "success"})
    render_detail(task, history="replace")


def delete_task(task):
    state["tasks"] = [t for t in state["tasks"] if t["id"] != task["id"]]
    storage_save()
    send({"type": "command", "command": "toast", "text": "Task deleted", "style": "success"})
    render_home(0, history="replace")


def toggle_task(task):
    task["completed"] = not task.get("completed", False)
    storage_save()
    if state["page"].startswith("tasks:item:"):
        render_detail(task, history="none")
    else:
        render_home(0)


def handle_action(message):
    item_id = message.get("id", "")
    action = message.get("action", "default")
    ids = message.get("ids") or []

    if not item_id:
        if action == "create":
            send({"type": "command", "command": "setQuery", "text": " "})
            render_form()
        elif action == "complete-selected":
            selected = {value.removeprefix("task:") for value in ids}
            for task in state["tasks"]:
                if task["id"] in selected:
                    task["completed"] = True
            storage_save()
            render_home(0)
        elif state["current_id"]:
            task = next((t for t in state["tasks"] if t["id"] == state["current_id"]), None)
            if task:
                if action == "edit":
                    render_form(task)
                elif action == "toggle-complete":
                    toggle_task(task)
                elif action == "delete":
                    delete_task(task)
        return

    task = task_by_item_id(item_id)
    if not task:
        return
    if action == "default":
        render_detail(task)
    elif action == "edit":
        render_form(task)
    elif action == "toggle-complete":
        toggle_task(task)
    elif action == "delete":
        delete_task(task)


def handle_navigation(message):
    target = message.get("toPageId") or message.get("targetPageId") or "tasks:home"
    if target == "tasks:home":
        render_home(0)
        return
    if target.startswith("tasks:item:"):
        task_id = target.split(":", 2)[2]
        task = next((t for t in state["tasks"] if t["id"] == task_id), None)
        if task:
            render_detail(task, history="none")
            return
    render_home(0)


def main():
    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError as error:
            log("Invalid stdin JSON:", error)
            continue

        event = message.get("type")
        try:
            if event == "close":
                break
            elif event == "storage" and message.get("requestId") == "load-tasks":
                value = message.get("value")
                state["tasks"] = value if isinstance(value, list) else []
                state["loaded"] = True
                render_home(0)
            elif event in ("init", "query"):
                if not state["storage_requested"]:
                    state["storage_requested"] = True
                    storage_get()
                # The query filters only the home page. A setQuery command used
                # before opening a form may emit a later query event; do not let
                # that event navigate away from the form/detail route.
                if state["page"] == "tasks:home":
                    state["query"] = message.get("text", message.get("query", ""))
                    render_home(message.get("rev", 0))
            elif event == "action":
                handle_action(message)
            elif event == "submit":
                save_form(message.get("values") or {})
            elif event in ("back", "navigate"):
                handle_navigation(message)
        except Exception as error:
            log("Handler error:", error)
            send({
                "type": "render",
                "rev": 0,
                "view": "detail",
                "canGoBack": True,
                "detail": {"markdown": f"# Error\n\n```\n{error}\n```"},
            })


if __name__ == "__main__":
    main()
````

### Notes about the example

- It requests storage on the first `init/query`. The loading frame remains
  until the storage reply.
- Re-rendering the same edit form preserves field state because field IDs remain
  stable.
- In production, carefully decide whether query events should be processed while
  a form/detail page is visible. You may route query behavior by current page.
- The built-in confirmation belongs on the action, so the delete handler only
  runs after the user accepts.

---

## 12. Node/Bun event-loop equivalent

```js
"use strict";

function send(message) {
  process.stdout.write(JSON.stringify(message) + "\n");
}
function log(...args) {
  console.error(...args);
}

let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  let newline;
  while ((newline = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, newline).trim();
    buffer = buffer.slice(newline + 1);
    if (!line) continue;

    let message;
    try {
      message = JSON.parse(line);
    } catch (error) {
      log("Invalid stdin JSON", error);
      continue;
    }

    if (message.type === "close") process.exit(0);
    // Dispatch init/query/action/submit/change/storage/back/navigate,
    // kanbanMove, and calendarNavigate here.
  }
});
process.stdin.on("end", () => process.exit(0));
```

---

## 13. Error, loading, and success states

- Initial/remote load: render `loading: true` and `loadingText`.
- Empty collection: use rich `empty` with a Create action.
- Form validation: re-render the same form with `error`.
- Successful save/delete: send a toast and render the durable destination.
- Request failure: render a detail error page or the same form with a clear
  error; do not rely only on a toast for failures that need action.
- Keep the stdin loop responsive; move slow network/file work to a worker.

Example error:

````python
send({
    "type": "render",
    "rev": 0,
    "view": "detail",
    "detail": {"markdown": f"# Save failed\n\n```\n{error}\n```"},
    "canGoBack": True,
})
````

---

## 14. Icons

`icon` accepts a built-in name, a hex color, a `data:image/...` URI up to 2 MB,
or a `file://`/`https://` raster or SVG image.

```text
search star favorite heart home settings gear folder file document link globe
world cloud sun weather moon bolt flash terminal code calculator calc clock timer
calendar mail email message chat person user people image photo music video play
download upload copy content_copy clipboard paste edit pencil delete trash add
plus remove minus check close info warning error help tag label bookmark money
currency cart shop chart graph database server wifi bluetooth battery power lock
unlock key shield bell flag location map translate language palette color brush
emoji grid list menu app window extension plugin refresh sync gamepad game book
note run open
```

---

## 15. Forms/CRUD checklist

- [ ] The page map identifies browse, detail, create/edit, and result routes.
- [ ] Each route has a stable `page.id` and intentional history behavior.
- [ ] Enter performs the obvious record action.
- [ ] Create/Edit is visible through `floatingAction`, not hidden only in Ctrl+K.
- [ ] Ctrl+K includes contextual secondary actions.
- [ ] Destructive actions are marked and confirmed.
- [ ] Forms use documented field types and stable field IDs.
- [ ] Host validation and server/business validation are both handled.
- [ ] Watched fields re-render dependent options without changing the field set.
- [ ] Submit values are treated according to their documented types.
- [ ] Bulk actions read `action.ids`.
- [ ] Kanban/calendar events update state and render the complete view.
- [ ] Persistent normal values use storage; secrets use `secret: true`.
- [ ] Query frames echo `rev`; action/submit/storage/navigation frames use `0`.
- [ ] Loading, empty, populated, validation-error, failure, and success states
      exist.
- [ ] stdout is protocol-only; logs use stderr; `close`/EOF exit cleanly.
- [ ] `dev` is disabled before distribution.

---

## 16. Ready-to-use request

> Build a Tabame QuickLaunch **forms/record-management plugin** in
> `<Python|Node|Bun>`. Keyword: `<keyword>`. Records are `<describe records and
data source>`. Users must be able to `<browse/create/edit/delete/organize>`.
> Use list/table/kanban/calendar only where each fits; use detail pages and full
> forms for record workflows. Make Create/Edit discoverable with Enter or
> floating actions, and use Ctrl+K for contextual alternatives, confirmations,
> and bulk actions. Persist `<state/secrets>` with Tabame storage. Return a page
> map, `plugin.json`, all complete source/dependency files, install path, and an
> interaction walkthrough. Follow this skill exactly and invent no fields.
