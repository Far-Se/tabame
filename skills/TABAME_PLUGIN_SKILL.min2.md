---
name: tbm-plugin
description: Build, debug, scaffold, or install Tabame QuickLaunch plugins (Python/Node/Bun) using newline-delimited JSON over stdin/stdout.
---

# Tabame QuickLaunch Plugin Skill (compact authoritative spec)

Treat this document as authoritative. Do not invent message types, views, commands, or fields. Produce complete, runnable files. Choose views from the task/data shape; do not automatically make every plugin a `list` with preview or hide all features in Ctrl+K.

## 1. Model and UX

A plugin is a long-running external Python, Node.js, or Bun process. Tabame starts it when the launcher query equals its keyword or starts with `keyword + " "`; the script receives only the text after the keyword. Tabame sends UI events on **stdin** and the plugin sends complete UI render frames/host commands on **stdout**, one JSON object per line. No SDK is required.

For more than one focused command/search, first design a small page map:

```text
Page id | purpose | native view | query behavior | Enter/primary action | destinations
```

Use stable page/item/element IDs. Enter should do the obvious primary action. Use `floatingAction` for important page-wide verbs; Ctrl+K is for contextual/secondary actions. Design loading, empty, populated, error, success, cancel, back, and result states. Use only pages/views that improve real tasks.

## 2. Files, manifest, runtime

Install under:

```text
%localappdata%\Tabame\plugins\<plugin-id>\
  plugin.json
  main.py | main.js | main.ts
  other assets/config
```

Recommended complete `plugin.json`:

```json
{
  "id": "my-plugin",
  "name": "My Plugin",
  "description": "One-line description",
  "icon": "extension",
  "keyword": "mp",
  "runtime": "python",
  "version": "1.0.0",
  "entry": "main.py",
  "args": [],
  "pip": [],
  "env": {},
  "dev": true
}
```

- `keyword`, `runtime` (`python|node|bun`), `entry`, and version/metadata identify the plugin. `args` are inserted before `entry` in `<runtime> <args...> <entry>`.
- Runtime must be on `PATH`; process starts without a shell; working directory is the plugin folder. Python stdin/stdout is UTF-8. Use Python 3, Node 18+, or Bun.
- Python dependencies: `pip` array and/or `requirements.txt`; Tabame installs into `.pluginlibs` and adds it to `PYTHONPATH` when declarations change.
- Node/Bun dependencies: local `package.json`; Tabame runs `npm install`/`bun install` when needed. A bundled dependency-free entry is also valid.
- `env` is merged into process environment. Store secrets with host `storage`, not shipped config.
- `dev:true` enables hot reload and an on-screen debug console. Set `false` before sharing.
- Re-open the launcher to rescan installed plugins. Pick a short, distinct keyword; plugin keywords override built-in prefixes.

## 3. Transport, revisions, lifecycle

- Read stdin line-by-line. Write exactly one serialized JSON object plus `\n`; flush after every write.
- **stdout is protocol-only**. Debug/logging goes to stderr.
- `init` is normally followed by `query` with the same text. Read `msg.text ?? msg.query ?? ""`.
- Query-sensitive render: echo the event's `rev`. Tabame drops frames older than the newest query.
- Action results, async pushes, background refreshes, progress, and streamed chunks: use `rev:0` (always accepted).
- Commands and `action` events have no `rev`.
- Exit on `close` and stdin EOF. Normal shutdown has about 2 seconds of grace; with `background`, keep the worker alive and join it before exiting.
- Keep the stdin loop responsive; slow/streaming work must run asynchronously/a worker thread.

## 4. Tabame → plugin events (stdin)

All are JSON objects with `type`:

| Type               | Important fields / meaning                                                                                                 |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| `init`             | `query`, `protocol` (currently 11), `theme:{accent,text,background,dark}`, `locale`                                        |
| `query`            | `text`, `rev`; each keystroke unless `inputMode:"submit"`                                                                  |
| `submitQuery`      | `text`, `rev`; Enter in submit mode                                                                                        |
| `select`           | `id`, `rev`                                                                                                                |
| `action`           | `id` (`""` for frame/empty action), `action` (`"default"` for Enter), optional `ids` bulk selection, optional `parameters` |
| `toggle`           | tree `id`, `expanded`, `rev`                                                                                               |
| `chartSelect`      | `seriesId`, `index`, `value`, `rev`                                                                                        |
| `cancel`           | operation `id`, `rev`                                                                                                      |
| `submit`           | form `values:{fieldId:value}`, optional `button`                                                                           |
| `change`           | watched form field `id`, all current `values`                                                                              |
| `loadMore`         | `rev`; return the full accumulated list                                                                                    |
| `tab`              | highlighted `id` or `""`, `rev`; usually respond with `setQuery`                                                           |
| `back`             | `rev`, optional `fromPageId`, `toPageId`; render previous destination                                                      |
| `navigate`         | breadcrumb `targetPageId`, `rev`                                                                                           |
| `kanbanMove`       | `id`, `columnId`, `index`, `rev`                                                                                           |
| `calendarNavigate` | `date:"yyyy-mm-dd"`, `mode:"month"                                                                                         | "agenda"`, `rev`                            |
| `storage`          | reply: `requestId`, `key`+`value` or `keys`                                                                                |
| `clipboard`        | reply: `requestId`, `text`                                                                                                 |
| `clipboardHistory` | reply to history operation; includes operation data/error and `requestId` when supplied                                    |
| `oauth`            | reply: `requestId`, plus `code/state/error` callback fields                                                                |
| `browserBridge`    | reply: `requestId`, `ok`, `result                                                                                          | error`; unsolicited events: `event`, `data` |
| `close`            | stop and exit                                                                                                              |

Interactive events may also contain `pageId`, `panelId`, and `elementId`; dispatch using this scope, especially in dashboards.

## 5. Plugin → Tabame messages (stdout)

Only:

```json
{"type":"render", "rev":0, "view":"detail", "detail":{"markdown":"Ready"}}
{"type":"command", "command":"toast", "text":"Done"}
```

### Host commands

| `command`          | Fields / behavior                                                                                                                                         |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `copy`             | `text`; clipboard + toast                                                                                                                                 |
| `paste`            | `text`; clipboard, hide launcher, reactivate prior window, Ctrl+V                                                                                         |
| `open`             | `url` or `path`; default handler                                                                                                                          |
| `hide`             | hide launcher; sends `close` (send `background` first for long-running work)                                                                                                                          |
| `toast`            | `text`, optional `style:success                                                                                                                           | error                                                                         | info                                                                                                                         | progress`, optional `progress:0..1`; progress toast stays until replaced                                                                                                                             |
| `setQuery`         | `text`; rewrites post-keyword query and triggers `query`                                                                                                  |
| `clipboardRead`    | optional `requestId`; reply is `clipboard`                                                                                                                |
| `clipboardHistory` | `op:list                                                                                                                                                  | entry                                                                         | copy`, optional `requestId,offset,limit,query,id`; list has `hasMore`, entry is bounded preview, copy restores full original |
| `notify`           | optional `title`, required `text`; native Windows notification                                                                                            |
| `storage`          | `op:set                                                                                                                                                   | get                                                                           | delete                                                                                                                       | keys`, optional `key,value,secret,requestId`; plain values use `.tabame-store.json`; `secret:true`stores strings in Windows Credential Manager and secrets are not returned by`keys`; get/keys reply |
| `background`       | optional `timeout` seconds (default 30, max 300); send **before** `hide`; detached process may use `storage`/`notify`, but UI frames/commands are dropped |
| `oauth`            | `authorizationUrl` containing literal `{redirectUri}`, optional `requestId,timeout`; exchange returned code yourself; store tokens as secrets             |
| `browserBridge`    | `op:status                                                                                                                                                | request`, required `requestId`for requests, optional`method,params,timeoutMs` |

Commands are fire-and-forget unless documented with a reply. Several commands may be sent in sequence. `hide`/`paste` end the UI and send `close`; for long-running work, send `background` first, then `notify` on completion. A `copy` immediately followed by `hide` may hide its toast.

Browser-owned JS uses `browserBridge` method `javascript.execute` with `params:{tabId?,code,input?,world?,allFrames?,frameIds?,injectImmediately?}`. `code` is required, may `await`, and returns through `return` (128 KiB maximum). `input` may be any JSON value; returned data must be JSON-serializable (192 KiB maximum). Default tab is active, default world is `USER_SCRIPT`; use `MAIN` only when page globals are required. Only HTTP(S) tabs are scriptable and Chromium “Allow User Scripts” must be enabled. Related methods include `tabs.open/list/close`.

## 6. Render frame

Core shape (omit irrelevant fields):

```jsonc
{
  "type": "render",
  "rev": 0,
  "view": "list",
  "page": {
    "id": "plugin:home",
    "title": "Home",
    "history": "none",
    "preserveState": true,
    "breadcrumbs": [{ "id": "root", "label": "Home" }],
  },
  "elementId": "results",
  "placeholder": "Search…",
  "loading": false,
  "loadingText": "Loading…",
  "emptyText": "No results",
  "empty": {
    "icon": "search",
    "title": "Nothing found",
    "hint": "Try another query",
    "action": { "id": "create", "title": "Create", "icon": "add" },
  },
  "preview": { "enabled": true, "wide": true },
  "canGoBack": false,
  "actions": [],
  "floatingAction": { "id": "create", "title": "Create", "icon": "add" },
  "selectId": "item-1",
  "hasMore": false,
  "inputMode": "submit",
  "selection": { "enabled": true, "max": 20 },
  "items": [],
}
```

Supported `view` values:

```text
list grid detail chat form table tree timeline chart operation dashboard
kanban diff log calendar gallery
```

Additional view fields:

```jsonc
{
  "grid": { "columns": 4, "aspectRatio": 1.0 },
  "detail": {
    "markdown": "# Text",
    "append": "stream chunk",
    "metadata": [],
    "wide": true,
  },
  "form": {},
  "columns": [
    { "id": "status", "label": "Status", "width": 120, "align": "end" },
  ],
  "chart": {
    "title": "Latency",
    "series": [
      { "id": "p95", "label": "p95", "values": [24, 31], "color": "#63A0EA" },
    ],
  },
  "operation": {
    "id": "job-1",
    "title": "Working",
    "detail": "…",
    "progress": 0.4,
    "cancellable": true,
  },
  "dashboard": { "layout": "stack", "panels": [] },
  "kanban": {
    "columns": [
      { "id": "todo", "title": "To do", "color": "#63A0EA", "limit": 5 },
    ],
  },
  "diff": {
    "mode": "unified",
    "oldLabel": "Before",
    "newLabel": "After",
    "text": "-old\n+new",
    "lines": [{ "type": "add", "text": "new", "oldLine": null, "newLine": 1 }],
  },
  "log": {
    "follow": true,
    "wrap": false,
    "lines": [
      {
        "id": "1",
        "timestamp": "10:42",
        "level": "info",
        "source": "worker",
        "text": "Ready",
      },
    ],
  },
  "calendar": {
    "mode": "month",
    "date": "2026-08-01",
    "weekStart": "monday",
    "days": 30,
  },
  "gallery": {
    "columns": 4,
    "aspectRatio": 1.15,
    "fit": "cover",
    "showLabels": true,
  },
}
```

Rules:

- `loading` may be bool or `{progress:0..1}`. `loadingText` is spinner text; `empty` overrides `emptyText`.
- `preview` works only on list/grid and uses each selected item's preview. Frame `wide:false` keeps normal launcher width.
- `inputMode:"submit"` suppresses per-keystroke queries; Enter sends `submitQuery`. A second Enter on unchanged text can activate the selected item.
- `hasMore:true` causes `loadMore`; respond with old+new items, not only the new page.
- `selection:true|{enabled,max}` enables bulk IDs in `action.ids`.
- `selectId` preserves/moves highlight after refresh/reorder.
- `detail.append` appends to current markdown for streaming; use `rev:0`.
- `diff.lines[].type` is `add|remove|context|header`. Log levels are `trace|debug|info|warn|error|success`; lines may also be plain strings.
- Table column IDs `title`/`subtitle` read those item fields automatically; use `align:"end"` for numbers.
- A dashboard panel is `{id,title,height?:96..640,view,...normalViewFields}`. Give panels/children stable `elementId`s.

## 7. Items, metadata, actions

Item shape (fields depend on view):

```jsonc
{
  "id": "stable-unique-id",
  "title": "Main **text**",
  "subtitle": "Secondary `text`",
  "icon": "star",
  "section": "Today",
  "lines": 1,
  "progress": 0.6,
  "tileColor": "#0EA5E9",
  "cells": { "status": "Healthy", "latency": "42 ms" },
  "depth": 1,
  "expanded": true,
  "timestamp": "10:42",
  "column": "review",
  "start": "2026-08-04T09:30:00",
  "end": "2026-08-04T10:15:00",
  "allDay": false,
  "color": "#8B5CF6",
  "location": "Studio A",
  "media": {
    "url": "https://…",
    "type": "image",
    "thumbnail": "https://…",
    "duration": "02:18",
    "size": 2480000,
    "width": 1920,
    "height": 1080,
  },
  "images": ["https://…"],
  "accessories": [{ "text": "IT", "color": "#8250DF", "icon": "clock" }],
  "actions": [],
  "preview": {
    "markdown": "## Details",
    "image": { "url": "https://…", "width": 160 },
    "metadata": [],
  },
}
```

- Every item needs a stable unique string `id`. Keep same-section items adjacent.
- `icon`: supported name, hex swatch, `data:image/...` (max 2 MB), or `file://`/`https://` raster/SVG.
- `title/subtitle` support only `**bold**` and inline `` `code` ``.
- Tree uses visible flattened nodes with `depth` 0..12 and `expanded`; handle `toggle` and re-render all visible nodes.
- Calendar accepts `start` or all-day alias `date`; optional details may also be nested in `calendar`.
- Gallery `media` may be an object or image URL string; types: `image|video|audio|file`.

Metadata entry for item preview or detail:

```jsonc
{
  "label": "Status",
  "text": "Active",
  "color": "#22C55E",
  "icon": "check",
  "image": "https://…",
  "width": 132,
  "height": 176,
  "url": "https://…",
  "sparkline": [12, 14, 11, 9],
  "actions": [],
}
```

Use `{"separator":true}` for a divider. `text` is required unless `sparkline` exists. Metadata actions send a normal `action` for the selected item, or `id:""` in detail.

Action shape (item, frame, floating, metadata, empty CTA):

```jsonc
{
  "id": "delete",
  "title": "Delete",
  "icon": "trash",
  "shortcut": "ctrl+shift+d",
  "destructive": true,
  "confirm": {
    "title": "Delete?",
    "message": "Cannot be undone",
    "confirmLabel": "Delete",
  },
  "parameters": [
    {
      "id": "environment",
      "type": "dropdown",
      "label": "Environment",
      "required": true,
      "options": ["staging", "production"],
    },
  ],
}
```

- Enter always sends `action:"default"`. An explicitly listed action with `id:"default"` may add title/icon/confirmation.
- Item actions appear first in Ctrl+K, then frame actions. Frame/floating/empty actions use `id:""`.
- Shortcut must be lowercase and include Ctrl and/or Alt; allowed keys include letters, digits, F1–F12, Enter, Space, Delete, arrows.
- Confirm destructive actions. `confirm:true` uses a generic prompt.
- Compact `parameters` return in `action.parameters`; use a full form for complex/validated editing.

## 8. Pages and navigation

Use `page` on conceptual destinations:

```json
{
  "id": "issues:item:ENG-42",
  "title": "Issue",
  "history": "push",
  "preserveState": true,
  "breadcrumbs": [
    { "id": "issues:home", "label": "Home" },
    { "id": "issues:board:ENG", "label": "ENG" }
  ]
}
```

- IDs describe stable destinations, never transient query/loading/selection state.
- `history:"push"` = forward drill-down; `replace` = redirect/same-depth replacement; `none` = no history change. Root usually uses none/omits history.
- Breadcrumbs contain ancestors only; Tabame adds current title. Handle `navigate.targetPageId`.
- Handle `back.toPageId` when present, otherwise your own previous route. `canGoBack:true` is only for a manual sub-screen outside page history. Never make an inescapable back-capable frame.
- `preserveState:true` restores selection/scroll/form values; false intentionally resets.
- When query meaning changes between pages, send `setQuery` (often empty) and set a page-specific `placeholder`.

## 9. Choosing views

| Task/data shape                             | View        |
| ------------------------------------------- | ----------- |
| short search/results with dominant identity | `list`      |
| visual/spatial choices                      | `grid`      |
| compare same fields across records          | `table`     |
| hierarchy                                   | `tree`      |
| chronological/causal events                 | `timeline`  |
| trend/outliers                              | `chart`     |
| overview of 2–5 related surfaces            | `dashboard` |
| workflow stages/draggable cards             | `kanban`    |
| read one substantial result/help/error      | `detail`    |
| collect/edit values                         | `form`      |
| conversation feed                           | `chat`      |
| one prominent long-running job              | `operation` |
| before/after source                         | `diff`      |
| diagnostics/output stream                   | `log`       |
| dates/events                                | `calendar`  |
| media assets                                | `gallery`   |

Use list/grid preview only for cheap adjacent-item comparison; use a real detail page for long content, actions, history, or a destination worth returning to. Use `accessories` for terse scan facts, metadata for aligned facts, table for repeated comparable fields, operation/progress/log for work state, and rich empty states for recoverable zero results.

### Form schema

```jsonc
{
  "view": "form",
  "form": {
    "title": "New Issue",
    "error": "Optional form error",
    "sections": [
      {
        "id": "main",
        "title": "Issue",
        "description": "Required",
        "collapsible": false,
      },
    ],
    "submitLabel": "Create",
    "buttons": [
      { "id": "create", "label": "Create" },
      { "id": "delete", "label": "Delete", "destructive": true },
    ],
    "fields": [
      {
        "id": "title",
        "type": "text",
        "label": "Title",
        "value": "",
        "placeholder": "Summary…",
        "required": true,
        "description": "Hint",
        "error": "Optional field error",
        "section": "main",
        "minLength": 1,
        "maxLength": 200,
        "pattern": ".*",
        "validationMessage": "Invalid",
      },
      {
        "id": "count",
        "type": "number",
        "label": "Count",
        "value": 1,
        "min": 1,
        "max": 10,
      },
      {
        "id": "team",
        "type": "combobox",
        "label": "Team",
        "options": ["eng", { "value": "ops", "label": "Operations" }],
        "watch": true,
        "optionsLoading": false,
        "allowCustom": false,
        "visibleWhen": { "field": "urgent", "equals": true },
        "enabledWhen": { "field": "title", "truthy": true },
      },
    ],
  },
}
```

Field types: `text,password,textarea,dropdown,combobox,checkbox,number,date,filepicker,folderpicker,tags`; unknown falls back to text. Submitted values are strings (dates use `yyyy-mm-dd`), booleans, numbers/null, or string arrays (`tags`). `required`, number bounds, and text `minLength/maxLength/pattern` are host-validated. Conditions support `{field,equals?,notEquals?,in?,truthy?}`. `watch:true` emits `change`; async comboboxes re-render options with `optionsLoading`. Re-rendering the same field IDs preserves typed values; changing the field set resets them. Multiple buttons put their ID in `submit.button`.

## 10. Async, persistence, background, errors

- Slow query: immediately render loading with the query `rev`, then result with the same `rev`; stale results are dropped.
- Streaming: render a base `detail`/chat frame, then `detail.append` chunks with `rev:0` from a worker so stdin remains responsive.
- Pagination: on `loadMore`, append data and re-render the **entire list so far**; preserve selection with stable IDs/`selectId`.
- Storage: correlate `get/keys` using `requestId`; tokens/API keys use `secret:true`.
- Work after UI closes: for uploads, syncs, or video conversion, send `background` before `hide`, keep a non-daemon worker alive through `close`, join it before exit, then send `notify` with the completion message.
- Browser/API/filesystem/process work is allowed by the runtime. Prefer host commands for clipboard/open/hide. Catch malformed input and operational errors; do not crash. Render a useful `detail` error and/or error toast.
- OAuth: keep state validation and code exchange in the plugin; authorization URL must contain `{redirectUri}`.

## 11. Icons

Common valid names (case-insensitive; trailing `_rounded/_outlined/_sharp/_filled` is ignored):

```text
search star favorite heart home settings gear folder file document link globe world cloud sun weather moon bolt flash terminal code calculator calc clock timer calendar mail email message chat person user people image photo music video play download upload copy content_copy clipboard paste edit pencil delete trash add plus remove minus check close info warning error help tag label bookmark money currency cart shop chart graph database server wifi bluetooth battery power lock unlock key shield bell flag location map translate language palette color brush emoji grid list menu app window extension plugin refresh sync gamepad game book note run open
```

Unknown names fall back to a generic plugin icon.

## 12. Minimal protocol templates

### Python

```python
import json, sys, threading
state = {"text": ""}

def send(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()

def render(rev, text):
    state["text"] = text
    send({"type":"render","rev":rev,"view":"list","placeholder":"Search…",
          "items":[{"id":"result","title":text or "Ready","icon":"star",
                    "actions":[{"id":"copy","title":"Copy","icon":"copy"}]}]})

def handle(msg):
    t = msg.get("type")
    if t in ("init", "query"):
        render(msg.get("rev", 0), msg.get("text", msg.get("query", "")))
    elif t == "action":
        if msg.get("action") == "copy":
            send({"type":"command","command":"copy","text":state["text"]})
        else:
            send({"type":"render","rev":0,"view":"detail",
                  "detail":{"markdown":f"# Action\n\n`{msg.get('action','default')}`"}})

for line in sys.stdin:
    try:
        msg = json.loads(line)
        if msg.get("type") == "close": break
        handle(msg)
    except Exception as e:
        print(e, file=sys.stderr, flush=True)
```

### Node.js / Bun

```js
"use strict";
const send = (o) => process.stdout.write(JSON.stringify(o) + "\n");
let lastText = "";
function handle(m) {
  if (m.type === "init" || m.type === "query") {
    const text = m.text ?? m.query ?? "";
    lastText = text;
    send({
      type: "render",
      rev: m.rev ?? 0,
      view: "list",
      placeholder: "Search…",
      items: [
        {
          id: "result",
          title: text || "Ready",
          icon: "star",
          actions: [{ id: "copy", title: "Copy", icon: "copy" }],
        },
      ],
    });
  } else if (m.type === "action") {
    if (m.action === "copy")
      send({ type: "command", command: "copy", text: lastText });
    else
      send({
        type: "render",
        rev: 0,
        view: "detail",
        detail: { markdown: `# Action\n\n\`${m.action ?? "default"}\`` },
      });
  }
}
let buf = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buf += chunk;
  for (let i; (i = buf.indexOf("\n")) >= 0;) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    try {
      const m = JSON.parse(line);
      if (m.type === "close") process.exit(0);
      handle(m);
    } catch (e) {
      console.error(e);
    }
  }
});
process.stdin.on("end", () => process.exit(0));
```

These are transport smoke tests, not mandatory product architecture.

## 13. Non-negotiable checklist

1. Output `plugin.json` plus every complete source/config file; no pseudocode or omitted handlers.
2. One JSON line per protocol message; flush; protocol-only stdout; stderr for logs.
3. Echo query `rev`; use `rev:0` for action/async/stream/progress results.
4. Stable unique item IDs and stable page/panel/element IDs.
5. Handle all events the chosen views/actions can emit, plus `close` and EOF.
6. Use documented fields only. Use host commands instead of shelling out for clipboard/open/hide.
7. For multi-page plugins: page map, native views, route state, history, back, breadcrumbs, query contracts, and visible primary actions.
8. Do not block stdin; async/streaming work uses workers and catches errors.
9. Full accumulated items on `loadMore`; complete visible tree/kanban/calendar after changes.
10. Confirm destructive actions; shortcuts include Ctrl/Alt; secrets use `storage secret:true`.
11. Send `background` before `hide` when work must continue.
12. Develop with `dev:true`, share with `dev:false`.

## 14. Expected answer when asked to build a plugin

Before code, provide a compact page map for non-trivial plugins. Then return:

1. Folder/file tree.
2. Complete `plugin.json`.
3. Complete runnable source files and any dependency/config files.
4. Brief explanation of routes, events/actions, persistence/auth, loading/error states, and install/use steps.

The finished result must be ready to copy into `%localappdata%\Tabame\plugins\<id>\` and run after reopening the launcher.
