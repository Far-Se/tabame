---
name: tbm-plugin-search-browse
description: Author a Tabame QuickLaunch plugin for searching, filtering, browsing, and selecting data using list/grid/table/tree/gallery views, split previews, detail pages, pagination, and Ctrl+K actions. Use for contacts, bookmarks, files, packages, media, commands, API search, dictionaries, and similar result-oriented plugins.
---

# Tabame QuickLaunch Plugin — Search & Browse Skill

> Treat this document as authoritative for this plugin category. Do not invent
> fields, views, commands, or message types. This skill intentionally covers
> search/browse plugins rather than every Tabame capability.

## 1. When to use this skill

Use this skill when the plugin's main job is to let the user type a query, scan
results, inspect a selected result, and perform an action.

Typical plugins:

- contacts, bookmarks, notes, documentation, dictionaries;
- files, applications, packages, repositories, browser tabs;
- image/media libraries and emoji/color pickers;
- API-backed search, command palettes, converters with multiple results;
- hierarchical browsers such as folders or categories.

Choose the dominant view from the data shape:

| Need                                       | View            |
| ------------------------------------------ | --------------- |
| Scan short results with one dominant label | `list`          |
| Pick a visual/spatial option               | `grid`          |
| Compare the same fields across records     | `table`         |
| Browse a hierarchy                         | `tree`          |
| Browse media assets                        | `gallery`       |
| Read one result in depth                   | `detail`        |
| Quickly inspect adjacent list/grid results | split `preview` |

A split preview is a modifier for `list` and `grid`, not the architecture of
all plugins. Use a proper `detail` page when the selected content is long, has
its own actions, or deserves page history.

---

## 2. Plugin model

A Tabame plugin is an external **Python, Node.js, or Bun** process. Tabame starts
it when the launcher's query equals the plugin keyword or begins with
`keyword + " "`.

Communication is newline-delimited JSON:

- **Tabame → plugin stdin:** query, selection, action, navigation, pagination,
  tree-toggle, and shutdown events.
- **Plugin → Tabame stdout:** complete render frames and host commands.

There is no SDK. Read one JSON object per line and write one JSON object per
line. The process remains alive while the keyword owns the query.

### Non-negotiable transport rules

1. stdout is only for protocol JSON. Send debug logs to stderr.
2. End every message with `\n` and flush stdout.
3. Exit on `close` and stdin EOF.
4. Catch malformed input and request failures; do not crash the process.
5. Give every item a stable, unique string `id`.
6. Only use fields documented here.

---

## 3. Folder and manifest

Install each plugin under:

```text
%localappdata%\Tabame\plugins\<plugin-id>\
    plugin.json
    main.py / main.js / main.ts
    optional assets, config, package.json, requirements.txt
```

`plugin.json`:

```json
{
  "id": "docs-search",
  "name": "Docs Search",
  "description": "Search local documentation",
  "keyword": "docs",
  "runtime": "python",
  "version": "1.0.0",
  "entry": "main.py",
  "icon": "search",
  "args": [],
  "pip": [],
  "env": {},
  "dev": true
}
```

Fields:

| Field         | Required | Meaning                                            |
| ------------- | -------- | -------------------------------------------------- |
| `keyword`     | yes      | Short unique activation keyword.                   |
| `runtime`     | yes      | `python`, `node`, or `bun`; must be on `PATH`.     |
| `version`     | yes      | Start with `1.0.0`.                                |
| `entry`       | yes      | Script path relative to plugin folder.             |
| `id`          | yes      | Stable plugin identifier; normally folder name.    |
| `name`        | yes      | Human-readable title.                              |
| `description` | yes      | One-line description.                              |
| `icon`        | yes      | Icon name, color, data URI, or file/HTTPS image.   |
| `args`        | no       | Arguments inserted before `entry`.                 |
| `pip`         | no       | Python packages auto-installed into `.pluginlibs`. |
| `env`         | no       | Extra environment variables.                       |
| `dev`         | no       | Hot reload and debug console while developing.     |

The launch command is effectively:

```text
<runtime> <args...> <entry>
```

The working directory is the plugin folder. Relative paths resolve there. The
process is started without a shell.

### Dependencies

Python dependencies may be listed in `pip` and/or `requirements.txt`. Tabame
installs them into `.pluginlibs` and adds that directory to `PYTHONPATH`.

Node/Bun plugins may ship `package.json`; Tabame runs `npm install` or
`bun install` when needed. A bundled dependency-free entry file is also valid.

Set `dev` to `false` before sharing the plugin.

---

## 4. Relevant inbound messages

Tabame sends JSON objects on stdin.

### `init`

Sent once after process start:

```json
{
  "type": "init",
  "query": "initial text",
  "protocol": 11,
  "theme": {
    "accent": "#63A0EA",
    "text": "#E8E8E8",
    "background": "#1B1D23",
    "dark": true
  },
  "locale": "en-US"
}
```

`init` is normally followed by a `query` containing the same text. Treat both
through the same query handler. On `init`, read `query`; on `query`, read `text`.

### `query`

Sent on each keystroke while the keyword is active:

```json
{ "type": "query", "text": "flutter", "rev": 7 }
```

Use the `rev` staleness rule in section 6.

### `select`

Sent when the highlighted item changes:

```json
{ "type": "select", "id": "pkg:flutter", "rev": 7 }
```

Usually no handler is required because each item's preview is already present
in the frame. Handle it only for lazy preview loading or selection-dependent
work.

### `action`

Sent for Enter, Ctrl+K, action shortcuts, floating actions, and empty-state CTAs:

```json
{"type":"action","id":"pkg:flutter","action":"default"}
{"type":"action","id":"pkg:flutter","action":"copy-name"}
{"type":"action","id":"","action":"refresh"}
```

`action` has no `rev`. Optional fields:

- `ids`: bulk-selected item IDs;
- `parameters`: values collected from an action's compact parameter form;
- `pageId`, `panelId`, `elementId`: event scope when applicable.

Enter always arrives as `action: "default"`, whether or not the item explicitly
lists a default action.

### `tab`

```json
{ "type": "tab", "id": "pkg:flutter", "rev": 7 }
```

Use `setQuery` to autocomplete from the selected item.

### `loadMore`

Sent near the end of a frame with `hasMore: true`:

```json
{ "type": "loadMore", "rev": 7 }
```

Respond with the **complete list accumulated so far plus the new page**, not
only the new items.

### `toggle`

Tree disclosure event:

```json
{ "type": "toggle", "id": "folder:src", "expanded": true, "rev": 7 }
```

Update your tree state and render the complete flattened visible tree.

### `back` and `navigate`

```json
{"type":"back","rev":7,"fromPageId":"docs:item:42","toPageId":"docs:results"}
{"type":"navigate","targetPageId":"docs:home","rev":7}
```

Use these for detail pages and breadcrumbs. Render the target route yourself.

### `close`

```json
{ "type": "close" }
```

Stop workers and exit. Also exit when stdin reaches EOF.

---

## 5. Host commands

Commands are stdout messages with no `rev`:

```json
{ "type": "command", "command": "copy", "text": "value" }
```

Relevant commands:

| Command            | Fields                               | Effect                                                        |
| ------------------ | ------------------------------------ | ------------------------------------------------------------- |
| `copy`             | `text`                               | Copy and show a toast.                                        |
| `paste`            | `text`                               | Copy, hide launcher, reactivate previous window, send Ctrl+V. |
| `open`             | `url` or `path`                      | Open URL/file/folder with default handler.                    |
| `hide`             | —                                    | Hide launcher.                                                |
| `toast`            | `text`, optional `style`, `progress` | Show success/error/info/progress feedback.                    |
| `setQuery`         | `text`                               | Replace post-keyword query; triggers another `query`.         |
| `clipboardRead`    | optional `requestId`                 | Request clipboard text; reply is `clipboard`.                 |
| `clipboardHistory` | `op`, request/paging fields          | Read Tabame clipboard history.                                |

Examples:

```python
send({"type":"command", "command":"copy", "text": value})
send({"type":"command", "command":"open", "url": url})
send({"type":"command", "command":"setQuery", "text": suggestion})
send({"type":"command", "command":"toast", "text":"Refreshed", "style":"success"})
```

Combine commands by printing multiple lines. `paste` and `hide` close the
launcher, so emit everything needed before them.

---

## 6. The `rev` staleness rule

Every `query`, `select`, `loadMore`, and `toggle` carries a `rev`. When rendering
because of a query, echo that query's `rev`:

```json
{"type":"render","rev":7,...}
```

Tabame drops a frame whose `rev` is older than the latest query. This prevents a
slow response for `flu` from replacing results for `flutter`.

Rules:

- direct query/loading response → echo the triggering `rev`;
- action result, navigation, background refresh, lazy preview push → `rev: 0`;
- loading and final frames for one request use the same query `rev`.

For genuinely concurrent searches, also cancel or ignore old work inside the
plugin when practical; host-side dropping protects the UI but not wasted work.

---

## 7. Render frame structure

A render frame fully describes what Tabame displays:

```jsonc
{
  "type": "render",
  "rev": 0,
  "view": "list",
  "page": {
    "id": "docs:results",
    "title": "Results",
    "history": "none",
    "preserveState": true,
    "breadcrumbs": [{ "id": "docs:home", "label": "Home" }],
  },
  "elementId": "results",
  "placeholder": "Search docs…",
  "loading": false,
  "loadingText": "Searching…",
  "emptyText": "No results",
  "empty": {
    "icon": "search",
    "title": "No matches",
    "hint": "Try a shorter query",
    "action": { "id": "clear", "title": "Clear query", "icon": "close" },
  },
  "preview": { "enabled": true, "wide": true },
  "actions": [],
  "floatingAction": { "id": "refresh", "title": "Refresh", "icon": "refresh" },
  "selection": { "enabled": true, "max": 50 },
  "selectId": "item-42",
  "hasMore": false,
  "items": [],
}
```

Important fields:

| Field            | Notes                                                      |
| ---------------- | ---------------------------------------------------------- |
| `type`           | Always `render`.                                           |
| `rev`            | Query rev or `0` for unsolicited/action/navigation frames. |
| `view`           | One of the views covered in this skill.                    |
| `page`           | Stable destination identity and history behavior.          |
| `elementId`      | Stable source ID returned on scoped events.                |
| `placeholder`    | Context-specific search-field hint.                        |
| `loading`        | Boolean or `{ "progress": 0..1 }`.                         |
| `loadingText`    | Caption under spinner.                                     |
| `emptyText`      | Simple empty message when not loading.                     |
| `empty`          | Rich empty state; overrides `emptyText`.                   |
| `preview`        | Split preview settings for list/grid.                      |
| `actions`        | Frame-level Ctrl+K actions.                                |
| `floatingAction` | Discoverable frame-level button(s).                        |
| `selection`      | Bulk selection enabled or `{enabled,max}`.                 |
| `selectId`       | Restore/move highlight after refresh.                      |
| `hasMore`        | Enables `loadMore`.                                        |
| `items`          | Complete current item collection.                          |

### Page identity and history

Use stable conceptual IDs:

```json
{
  "page": {
    "id": "packages:item:flutter",
    "title": "Flutter",
    "history": "push",
    "preserveState": true,
    "breadcrumbs": [
      { "id": "packages:home", "label": "Packages" },
      { "id": "packages:results", "label": "Results" }
    ]
  }
}
```

- Do not include query text, loading status, or selection in `page.id`.
- Use `history: "push"` for forward drill-down.
- Use `replace` for redirects/same-depth replacement.
- Use `none` for refreshes or frames that should not alter history.
- Breadcrumbs list ancestors only; Tabame adds the current page title.
- Handle `back.toPageId` and `navigate.targetPageId`.
- Use `canGoBack: true` only for temporary manual sub-screens outside page
  history. Never create a back-capable dead end.

---

## 8. Items, previews, and metadata

General item shape:

```jsonc
{
  "id": "pkg:flutter",
  "title": "Flutter",
  "subtitle": "UI toolkit for building applications",
  "icon": "extension",
  "section": "Frameworks",
  "lines": 2,
  "progress": 0.6,
  "tileColor": "#0EA5E9",
  "cells": { "version": "3.35", "license": "BSD", "downloads": "2.1M" },
  "depth": 1,
  "expanded": true,
  "media": {
    "url": "https://example.com/poster.webp",
    "type": "image",
    "thumbnail": "https://example.com/thumb.webp",
    "duration": "02:18",
    "size": 2480000,
    "width": 1920,
    "height": 1080,
  },
  "accessories": [{ "text": "Popular", "color": "#63A0EA", "icon": "star" }],
  "actions": [
    { "id": "copy-name", "title": "Copy name", "icon": "copy" },
    { "id": "open-site", "title": "Open site", "icon": "open" },
  ],
  "preview": {
    "markdown": "## Flutter\n\nCross-platform UI toolkit.",
    "image": { "url": "https://example.com/logo.png", "width": 120 },
    "metadata": [
      { "label": "Version", "text": "3.35" },
      { "label": "License", "text": "BSD", "icon": "document" },
      { "label": "Trend", "text": "+12%", "sparkline": [8, 9, 12, 11, 15] },
      { "label": "Docs", "text": "flutter.dev", "url": "https://flutter.dev" },
    ],
  },
}
```

Item rules:

- `id` must be stable and unique within the frame.
- `title` and `subtitle` support only `**bold**` and inline `` `code` ``.
- `section` groups adjacent list/grid items when its value changes.
- `lines` controls subtitle wrap in list view, from 1 to 3.
- `progress` is a per-row 0–1 progress bar.
- `cells` keys correspond to table column IDs.
- `depth` and `expanded` describe visible tree nodes.
- `media` is used by gallery; a source string is shorthand for an image.
- `accessories` are concise trailing chips, not a replacement for structured
  metadata.
- `preview` is displayed only when the frame enables split preview.

### Metadata entries

Use metadata instead of markdown tables for aligned facts:

```jsonc
[
  { "label": "Status", "text": "Ready", "color": "#22C55E" },
  { "label": "Owner", "text": "Team Core", "icon": "people" },
  { "separator": true },
  { "label": "Homepage", "text": "example.com", "url": "https://example.com" },
  { "label": "Trend", "text": "−3%", "sparkline": [12, 14, 11, 9] },
  {
    "label": "Source",
    "text": "Open repository",
    "actions": [{ "id": "open-source", "title": "Open", "icon": "open" }],
  },
]
```

Supported metadata fields: `label`, `text`, `color`, `icon`, `image`, `width`,
`height`, `actions`, `url`, `sparkline`, and `separator`.

---

## 9. Search/browse views

### `list`

Best for quick scanning when each result has one primary identity. Use:

- `section` for meaningful groups;
- `accessories` for terse status, age, owner, or count;
- `lines` for a slightly longer subtitle;
- `progress` for item-local progress;
- split preview when adjacent-result inspection is useful.

Do not dump many database fields into the subtitle. Use a table or preview
metadata instead.

### `grid`

Best for visual options such as emoji, colors, apps, themes, or presets.

```jsonc
{
  "view": "grid",
  "grid": { "columns": 5, "aspectRatio": 1.0 },
  "items": [
    { "id": "red", "title": "Red", "icon": "#EF4444", "tileColor": "#EF4444" },
  ],
}
```

Arrow keys move in two dimensions. `section` grouping works like list view.

### `table`

Best when users compare the same fields across many records:

```jsonc
{
  "view": "table",
  "columns": [
    { "id": "title", "label": "Package", "width": 220 },
    { "id": "version", "label": "Version" },
    { "id": "license", "label": "License" },
    { "id": "downloads", "label": "Downloads", "align": "end" },
  ],
  "items": [
    {
      "id": "pkg:flutter",
      "title": "Flutter",
      "cells": { "version": "3.35", "license": "BSD", "downloads": "2.1M" },
    },
  ],
}
```

Keep the identity column first and use `align: "end"` for numbers. Table rows
support actions, selection, and pagination.

### `tree`

The plugin sends the currently visible flattened nodes:

```jsonc
{
  "view": "tree",
  "items": [
    {
      "id": "folder:src",
      "title": "src",
      "icon": "folder",
      "depth": 0,
      "expanded": true,
    },
    { "id": "file:main", "title": "main.py", "icon": "file", "depth": 1 },
  ],
}
```

A `toggle` event asks the plugin to expand/collapse. Insert or remove descendants
and re-render the full visible tree. Use tree only when parentage matters.

### `gallery`

Use for image/video/audio/file collections:

```jsonc
{
  "view": "gallery",
  "gallery": {
    "columns": 4,
    "aspectRatio": 1.15,
    "fit": "cover",
    "showLabels": true,
  },
  "items": [
    {
      "id": "media:1",
      "title": "Screenshot",
      "media": { "url": "file:///C:/images/shot.png", "type": "image" },
    },
  ],
}
```

Gallery supports keyboard selection, actions, bulk selection, and pagination.

### `detail`

Use a full page for long content or a destination with its own actions/history:

```jsonc
{
  "view": "detail",
  "detail": {
    "markdown": "# Result title\n\nLong-form **Markdown** content.",
    "metadata": [{ "label": "Source", "text": "Local index" }],
    "wide": true,
  },
  "actions": [{ "id": "copy-all", "title": "Copy all", "icon": "copy" }],
}
```

Detail supports headings, lists, bold, inline/fenced code, block quotes, links,
selectable text, code-block copy buttons, and image lightboxes.

### Split preview

Enable only on list/grid:

```json
{ "preview": { "enabled": true, "wide": true } }
```

The selected item's `preview` is shown on the right. `wide` belongs to the frame,
not the item preview. Set `wide: false` to keep normal launcher width.

---

## 10. Actions and Ctrl+K

Item actions and frame actions use the same shape:

```jsonc
{
  "id": "delete",
  "title": "Remove bookmark",
  "icon": "trash",
  "shortcut": "ctrl+shift+d",
  "destructive": true,
  "confirm": {
    "title": "Remove this bookmark?",
    "message": "This cannot be undone.",
    "confirmLabel": "Remove",
  },
  "parameters": [
    {
      "id": "format",
      "type": "dropdown",
      "label": "Format",
      "required": true,
      "options": ["plain", "markdown"],
    },
  ],
}
```

Behavior:

- Enter on an item sends `action: "default"`.
- Ctrl+K shows selected-item actions first, then frame actions.
- Frame actions arrive with `id: ""`.
- `floatingAction` displays important frame-level action(s) without requiring
  Ctrl+K.
- Action shortcuts must include Ctrl and/or Alt.
- `confirm` gates the event before it reaches the plugin.
- Mark destructive actions with both `destructive: true` and `confirm`.
- Compact `parameters` are suitable for one small choice. Use a dedicated form
  skill for substantial input workflows.

After an action, send host commands and/or a new frame with `rev: 0`.

---

## 11. Loading, empty states, and pagination

### Async search

Render immediately, then perform slow work:

```python
send({
    "type": "render", "rev": rev, "view": "list",
    "loading": True, "loadingText": "Searching…", "items": []
})
results = search(text)
send({
    "type": "render", "rev": rev, "view": "list",
    "preview": {"enabled": True},
    "items": [to_item(x) for x in results]
})
```

Both frames use the same query `rev`.

### Rich empty state

```jsonc
{
  "empty": {
    "icon": "search",
    "title": "No matching packages",
    "hint": "Try removing a filter",
    "action": { "id": "clear", "title": "Clear filters", "icon": "close" },
  },
  "items": [],
}
```

The CTA sends `action` with `id: ""` and the action ID.

### Pagination

- First page: render items and `hasMore: true`.
- On `loadMore`, fetch the next page.
- Re-render old items plus new items.
- Keep `hasMore: true` until no more results remain.
- Preserve selection with stable IDs and `selectId` when needed.

---

## 12. Complete Python example: package search with preview and detail

This template demonstrates the focused architecture for this skill:

- live query filtering;
- list + split preview;
- Enter opens a detail page;
- Ctrl+K actions copy/open;
- Tab autocompletes;
- page history and back navigation;
- loading/empty states;
- correct `rev` handling.

`plugin.json`:

```json
{
  "id": "package-browser",
  "name": "Package Browser",
  "description": "Search and inspect packages",
  "keyword": "pkg",
  "runtime": "python",
  "version": "1.0.0",
  "entry": "main.py",
  "icon": "search",
  "dev": true
}
```

`main.py`:

````python
#!/usr/bin/env python3
import json
import sys

PACKAGES = [
    {
        "id": "flutter",
        "name": "Flutter",
        "summary": "UI toolkit for building applications",
        "version": "3.35",
        "license": "BSD-3-Clause",
        "url": "https://flutter.dev",
        "tags": ["ui", "dart", "cross-platform"],
    },
    {
        "id": "requests",
        "name": "Requests",
        "summary": "Friendly HTTP library for Python",
        "version": "2.32",
        "license": "Apache-2.0",
        "url": "https://requests.readthedocs.io",
        "tags": ["python", "http"],
    },
    {
        "id": "express",
        "name": "Express",
        "summary": "Minimal web framework for Node.js",
        "version": "5.1",
        "license": "MIT",
        "url": "https://expressjs.com",
        "tags": ["node", "web", "server"],
    },
]

state = {
    "query": "",
    "page": "packages:results",
    "selected": None,
}


def send(message):
    sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def find_package(item_id):
    package_id = item_id.removeprefix("pkg:")
    return next((p for p in PACKAGES if p["id"] == package_id), None)


def filtered_packages(text):
    q = text.strip().lower()
    if not q:
        return PACKAGES
    return [
        p for p in PACKAGES
        if q in p["name"].lower()
        or q in p["summary"].lower()
        or any(q in tag for tag in p["tags"])
    ]


def package_item(package):
    return {
        "id": f"pkg:{package['id']}",
        "title": package["name"],
        "subtitle": package["summary"],
        "icon": "extension",
        "accessories": [
            {"text": package["version"]},
            {"text": package["license"], "icon": "document"},
        ],
        "actions": [
            {"id": "default", "title": "Open details", "icon": "open"},
            {"id": "copy-name", "title": "Copy name", "icon": "copy"},
            {"id": "open-site", "title": "Open website", "icon": "globe"},
        ],
        "preview": {
            "markdown": (
                f"## {package['name']}\n\n"
                f"{package['summary']}\n\n"
                f"**Tags:** {', '.join(package['tags'])}"
            ),
            "metadata": [
                {"label": "Version", "text": package["version"]},
                {"label": "License", "text": package["license"]},
                {"label": "Website", "text": package["url"], "url": package["url"]},
            ],
        },
    }


def render_results(rev=0):
    state["page"] = "packages:results"
    matches = filtered_packages(state["query"])
    frame = {
        "type": "render",
        "rev": rev,
        "view": "list",
        "page": {
            "id": "packages:results",
            "title": "Packages",
            "history": "none",
            "preserveState": True,
        },
        "elementId": "package-results",
        "placeholder": "Search packages…",
        "preview": {"enabled": True, "wide": True},
        "empty": {
            "icon": "search",
            "title": "No packages found",
            "hint": "Try a name, description, or tag",
            "action": {"id": "clear-query", "title": "Clear query", "icon": "close"},
        },
        "actions": [
            {"id": "refresh", "title": "Refresh", "icon": "refresh"},
        ],
        "items": [package_item(p) for p in matches],
    }
    if state["selected"]:
        frame["selectId"] = state["selected"]
    send(frame)


def render_detail(package):
    state["page"] = f"packages:item:{package['id']}"
    state["selected"] = f"pkg:{package['id']}"
    send({
        "type": "render",
        "rev": 0,
        "view": "detail",
        "page": {
            "id": state["page"],
            "title": package["name"],
            "history": "push",
            "preserveState": True,
            "breadcrumbs": [
                {"id": "packages:results", "label": "Packages"},
            ],
        },
        "placeholder": "Filter packages…",
        "detail": {
            "wide": True,
            "markdown": (
                f"# {package['name']}\n\n"
                f"{package['summary']}\n\n"
                f"## Tags\n\n"
                + "\n".join(f"- `{tag}`" for tag in package["tags"])
            ),
            "metadata": [
                {"label": "Version", "text": package["version"]},
                {"label": "License", "text": package["license"]},
                {"label": "Website", "text": package["url"], "url": package["url"]},
            ],
        },
        "actions": [
            {"id": "copy-name", "title": "Copy name", "icon": "copy"},
            {"id": "open-site", "title": "Open website", "icon": "globe"},
        ],
    })


def handle_query(msg):
    state["query"] = msg.get("text", msg.get("query", ""))
    # Query text belongs to the results page. A query while on detail returns to results.
    render_results(msg.get("rev", 0))


def handle_action(msg):
    item_id = msg.get("id", "")
    action = msg.get("action", "default")

    if not item_id:
        if action == "clear-query":
            send({"type": "command", "command": "setQuery", "text": " "})
        elif action == "refresh":
            send({"type": "command", "command": "toast", "text": "Packages refreshed"})
            render_results(0)
        elif action in ("copy-name", "open-site") and state["selected"]:
            package = find_package(state["selected"])
            if package:
                perform_item_action(package, action)
        return

    package = find_package(item_id)
    if not package:
        return
    state["selected"] = item_id
    if action == "default":
        render_detail(package)
    else:
        perform_item_action(package, action)


def perform_item_action(package, action):
    if action == "copy-name":
        send({"type": "command", "command": "copy", "text": package["name"]})
    elif action == "open-site":
        send({"type": "command", "command": "open", "url": package["url"]})


def handle_tab(msg):
    package = find_package(msg.get("id", ""))
    if package:
        send({"type": "command", "command": "setQuery", "text": package["name"]})


def handle_back_or_navigate(msg):
    target = msg.get("toPageId") or msg.get("targetPageId")
    if not target or target == "packages:results":
        render_results(0)


def main():
    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError as error:
            log("Invalid stdin JSON:", error)
            continue

        event = msg.get("type")
        try:
            if event == "close":
                break
            if event in ("init", "query"):
                handle_query(msg)
            elif event == "select":
                state["selected"] = msg.get("id")
            elif event == "action":
                handle_action(msg)
            elif event == "tab":
                handle_tab(msg)
            elif event in ("back", "navigate"):
                handle_back_or_navigate(msg)
        except Exception as error:
            log("Handler error:", error)
            send({
                "type": "render",
                "rev": 0,
                "view": "detail",
                "detail": {"markdown": f"# Error\n\n```\n{error}\n```"},
                "canGoBack": True,
            })


if __name__ == "__main__":
    main()
````

For a real API search, replace `filtered_packages()` with async/network work.
Show a loading frame first and keep the stdin loop responsive, using a worker
thread if the request may block for noticeable time.

---

## 13. Node/Bun event-loop equivalent

When generating Node.js or Bun instead of Python, use a buffered line parser:

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
    // Dispatch init/query/select/action/tab/loadMore/toggle/back/navigate here.
  }
});
process.stdin.on("end", () => process.exit(0));
```

Node 18+ and Bun provide global `fetch`.

---

## 14. Icons

`icon` accepts a case-insensitive built-in name, a hex color, a `data:image/...`
URI up to 2 MB, or a `file://`/`https://` raster or SVG image.

Built-in names:

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

Unknown names fall back to a generic plugin icon.

---

## 15. Search/browse checklist

Before returning a plugin, verify:

- [ ] `plugin.json` includes stable `id`, name, description, keyword, runtime,
      version, entry, and icon.
- [ ] stdout contains only one-line protocol JSON; logs use stderr.
- [ ] Every write ends with a newline and is flushed.
- [ ] Query responses echo `rev`; action/navigation pushes use `rev: 0`.
- [ ] Every result has a stable unique ID.
- [ ] The chosen view matches the data shape.
- [ ] Split preview is used only for list/grid and provides useful content.
- [ ] Long content opens as a real detail page.
- [ ] Enter performs the obvious primary item action.
- [ ] Ctrl+K contains contextual alternatives, not the only discoverable path.
- [ ] Frame-wide actions use `id: ""`; primary page verbs may use
      `floatingAction`.
- [ ] Loading, empty, populated, and error states are rendered.
- [ ] `loadMore` returns the complete accumulated list.
- [ ] Tree toggles re-render the complete visible flattened tree.
- [ ] Back/breadcrumb events restore the requested page.
- [ ] Destructive actions use confirmation.
- [ ] `close` and EOF terminate the process.
- [ ] `dev` is false before distribution.

---

## 16. Ready-to-use request

After this skill, the user may provide a request like:

> Build a Tabame QuickLaunch **search/browse plugin** in `<Python|Node|Bun>`.
> Keyword: `<keyword>`. Data source: `<API/files/local data>`. Users should be
> able to `<search/filter/browse>`, inspect `<preview/detail information>`, and
> perform `<primary and Ctrl+K actions>`. Choose list, grid, table, tree, gallery,
> detail, and split preview only where they fit the data. Return a page map,
> `plugin.json`, every complete source file, dependency files, install path, and
> a short interaction walkthrough. Follow this skill exactly and do not invent
> protocol fields.
