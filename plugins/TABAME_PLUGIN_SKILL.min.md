---
name: tbm-plugin-min
description: Author a Tabame launcher plugin — an external Python/Node/Bun script that extends the app launcher, talking newline-delimited JSON over stdin/stdout. Use when the user wants to build, scaffold, debug, or install a Tabame launcher plugin, add a new launcher keyword backed by a script, or asks about the plugin render-frame protocol.
---

# Tabame Launcher Plugin — Authoring Skill

> Authoritative. Don't invent fields/message types not documented here. When unsure, default to `list` view and copy §11's template.

## 1. Model

A plugin = folder with `plugin.json` + a script (Python/Node/Bun), launched as a long-running child process when the user types its `keyword` in the launcher. Protocol: **newline-delimited JSON, one object per line, both directions.**

- stdin (Tabame→script): UI events (query text, selection, actions, shutdown).
- stdout (script→Tabame): **render frames** — full description of what to show now. Re-print a frame whenever the UI should change. No SDK; just read/write lines. Process stays alive while the keyword owns the query; killed on exit (~2s grace).
- Working dir = plugin folder (relative paths resolve there). No shell. Node/Bun get global `fetch`; Python any version 3. Windows sets `PYTHONIOENCODING=utf-8`/`PYTHONUTF8=1` for Python.

## 2. Folder layout & manifest

```
%localappdata%\Tabame\plugins\<id>\
    plugin.json   ← required manifest
    main.py       ← script (any name; must match "entry")
    ...           ← config/assets, cwd for the script
```

`plugin.json` fields:

| Field         | Req | Default       | Meaning                                                                                                                              |
| ------------- | --- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `keyword`     | yes | —             | Trigger word user types. Short & unique.                                                                                             |
| `runtime`     | yes | —             | `"python"` \| `"node"` \| `"bun"` (resolved on PATH).                                                                                |
| `entry`       | yes | —             | Script path relative to folder.                                                                                                      |
| `id`          | no  | folder name   | Stable identifier.                                                                                                                   |
| `name`        | no  | folder name   | Shown in discovery hint.                                                                                                             |
| `description` | no  | `""`          | One-liner.                                                                                                                           |
| `icon`        | no  | `"extension"` | §7 icon name.                                                                                                                        |
| `args`        | no  | `[]`          | CLI args inserted before `entry`.                                                                                                    |
| `pip`         | no  | `[]`          | Python only — packages to auto-install (see §3).                                                                                     |
| `env`         | no  | `{}`          | Extra env vars, merged over Tabame defaults.                                                                                         |
| `dev`         | no  | `false`       | Hot reload + on-screen debug console (stderr, malformed lines, dropped/accepted frames, commands, crashes). Turn off before sharing. |

Launch = `<runtime> <args...> <entry>`. **Install/reload**: drop folder in `plugins`, reopen launcher (rescans every open, no restart needed).

**Activation**: query equals `keyword` or starts with `keyword + " "` (e.g. `weather` matches `weather rome`, not `weatherman`). Script receives text _after_ the keyword. Plugin keywords beat built-in launcher prefixes.

## 3. Dependencies

**Python**: declare in `plugin.json`'s `"pip"` array and/or a `requirements.txt`. First run (and on change) Tabame runs `pip install --target .pluginlibs …`, shows a spinner, puts `.pluginlibs` on `PYTHONPATH` — import normally. Cached; ignored by dev-mode watcher. Requires `pip` for that runtime (`<runtime> -m pip`); failure shows the pip error instead of your UI. Can also vendor by hand (`pip install --target .pluginlibs <pkg>`).

**Node/Bun**: ship a `package.json`; if `node_modules` is missing/stale, Tabame runs `npm install` (or `bun install`) on first launch, cached on `package.json` hash. `npm`/`bun` must be on PATH. Guard/lazy-load heavy `require()`s so a missing package degrades gracefully. Alternative: bundle to a dependency-free file (`esbuild main.js --bundle --platform=node --format=cjs --outfile=main.bundle.js`, or `bun build ... --target=node`) and point `entry` at it.

Custom env vars (any runtime): `"env"` object in `plugin.json` → `os.environ`/`process.env`.

## 4. Protocol — stdin (Tabame → script)

| Msg           | When                                                                                                                         | Fields                                                                                                                                                                                                                                                                         |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `init`        | once, at start                                                                                                               | `query` (initial text), `protocol` (int, currently 8), `theme` {accent,text,background,dark}, `locale` (e.g. `"en-US"`). Immediately followed by a `query` with same text — treat both alike (`text` falling back to `query`). Use `theme` for matching generated images/SVGs. |
| `query`       | every keystroke (not in `inputMode:"submit"`)                                                                                | `text`, `rev` (int, increases with typing)                                                                                                                                                                                                                                     |
| `submitQuery` | Enter, when frame set `inputMode:"submit"`                                                                                   | `text`, `rev`                                                                                                                                                                                                                                                                  |
| `select`      | highlighted item changed                                                                                                     | `id`, `rev`                                                                                                                                                                                                                                                                    |
| `action`      | Enter (`action:"default"`, always fires even if item lists no `"default"`), Ctrl+K pick, action shortcut, or empty-state CTA | `id` (`""` for frame-level/empty-state), `action`, optional `ids` (bulk selection), optional `parameters`. **No `rev`.**                                                                                                                                                       |
| `toggle`      | tree disclosure clicked                                                                                                      | `id`, `expanded`, `rev` — render children yourself                                                                                                                                                                                                                             |
| `chartSelect` | chart point clicked                                                                                                          | `seriesId`, `index`, `value`, `rev`                                                                                                                                                                                                                                            |
| `cancel`      | user cancelled a declared `operation`                                                                                        | `id`, `rev`                                                                                                                                                                                                                                                                    |
| `oauth`       | reply to `oauth` command                                                                                                     | `requestId` (echo), provider fields (`code`/`state`/`error`)                                                                                                                                                                                                                   |
| `submit`      | form submitted                                                                                                               | `values` {fieldId: value}, `button` (pressed `form.buttons` id, absent = default CTA)                                                                                                                                                                                          |
| `change`      | a `"watch":true` field changed                                                                                               | `id`, `values` (all current)                                                                                                                                                                                                                                                   |
| `loadMore`    | scrolled near end, `hasMore:true`                                                                                            | `rev` — answer with longer list                                                                                                                                                                                                                                                |
| `storage`     | reply to `storage` get/keys                                                                                                  | `requestId` (echo), `key`+`value` or `keys`                                                                                                                                                                                                                                    |
| `clipboard`   | reply to `clipboardRead`                                                                                                     | `requestId` (echo), `text`                                                                                                                                                                                                                                                     |
| `back`        | Escape on `canGoBack:true` frame                                                                                             | `rev` — render previous screen                                                                                                                                                                                                                                                 |
| `tab`         | Tab pressed                                                                                                                  | `id` (highlighted item, `""` if none), `rev` — typically answer with `setQuery`                                                                                                                                                                                                |
| `close`       | plugin shutting down                                                                                                         | —                                                                                                                                                                                                                                                                              |

```json
{"type":"init","query":"rome","protocol":8,"theme":{"accent":"#63A0EA","text":"#E8E8E8","background":"#1B1D23","dark":true},"locale":"en-US"}
{"type":"query","text":"rome","rev":1}
{"type":"action","id":"item-2","action":"copy"}
{"type":"close"}
```

## 5. Protocol — stdout (script → Tabame)

Only `{"type":"render",...}` and `{"type":"command","command":"...",...}` are meaningful. **Any other stdout line is treated as diagnostic log (written to errors.log, not shown) — put debug prints on stderr.**

### 5.1 Commands (fire-and-forget, no `rev`, no response unless noted)

| Command            | Fields                                                                           | Effect                                                                                                                                                                                          |
| ------------------ | -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `copy`             | `text`                                                                           | Clipboard + "Copied" toast.                                                                                                                                                                     |
| `paste`            | `text`                                                                           | Clipboard, hides launcher, refocuses previous window, sends Ctrl+V (types text there).                                                                                                          |
| `open`             | `url` or `path`                                                                  | Opens URL/file/folder with default handler.                                                                                                                                                     |
| `hide`             | —                                                                                | Hides launcher (shuts plugin down — you get `close`; print final output before/with it).                                                                                                        |
| `toast`            | `text`,`style`?(`success`\|`error`\|`info`\|`progress`),`progress`?              | Transient chip. `progress` style stays pinned (spinner or determinate ring); re-send to update.                                                                                                 |
| `setQuery`         | `text`                                                                           | Rewrites post-keyword search text (keyword stays); triggers a normal `query` back to you.                                                                                                       |
| `clipboardRead`    | `requestId`?                                                                     | Host replies `{"type":"clipboard","requestId","text"}`.                                                                                                                                         |
| `clipboardHistory` | `op`(`list`\|`entry`\|`copy`),`requestId`?,`offset`?,`limit`?,`query`?,`id`?     | Reads Tabame's clip history; `list`→compact+hasMore, `entry`→12k preview, `copy`→full original. Replies `{"type":"clipboardHistory",...}`.                                                      |
| `notify`           | `title`?,`text`                                                                  | Native Windows notification (works while backgrounded).                                                                                                                                         |
| `storage`          | `op`(`set`\|`get`\|`delete`\|`keys`),`key`?,`value`?,`secret`?,`requestId`?      | Per-plugin KV store, in `.tabame-store.json` unless `secret:true` (→ Windows Credential Manager, strings only, not in `keys`). `get`/`keys` reply `{"type":"storage",...}` echoing `requestId`. |
| `background`       | `timeout`?(default 30, max 300)                                                  | Grace period after hide/leave before kill, to finish work. While detached: `storage`/`notify` still work, UI commands dropped. Send before `hide`.                                              |
| `oauth`            | `authorizationUrl`(must contain literal `{redirectUri}`),`requestId`?,`timeout`? | Host loopback listener + opens auth URL; replies `{"type":"oauth",...}`. Exchange code yourself, store via `storage secret:true`.                                                               |
| `browserBridge`    | `op`,`requestId`,`method`?,`params`?,`timeoutMs`?                                | Uses the optional app-owned Chromium bridge. `status` returns connector/pairing state; `request` forwards an allowlisted method. Replies/events use `{"type":"browserBridge",...}`.             |

Notes: combine effects with multiple lines (`copy`+`hide` = copy-and-dismiss, but toast is skipped since launcher is already gone).

### 5.2 `rev` staleness rule

Echo the query's `rev` when responding to that query — Tabame **drops frames older than the latest query's rev** (prevents slow "rom" response overwriting fresh "rome" results). For unsolicited frames (action results, background refresh, async pushes) use **`rev: 0`** (always accepted).

### 5.3 Lifecycle

keyword typed → process starts → `init` then `query` → typing → `query`s (same process) → selection → `select` → Enter/Ctrl+K → `action` → leave/Esc/close → `close`, then killed (~2s grace). **Exit on `close` AND on stdin EOF.**

## 6. Render frame reference

```jsonc
{
  "type": "render", "rev": 0,
  "view": "list", // list|grid|detail|chat|form|table|tree|timeline|chart|operation|dashboard, default list
  "loading": false, // bool or {"progress":0.4} determinate
  "loadingText": "Searching…", // caption under spinner (shown only while loading; emptyText shown only when not loading)
  "emptyText": "No results",
  "empty": {"icon":"cloud","title":"No issues","hint":"Try a filter"}, // richer empty state incl. optional action {id,title,icon?}; overrides emptyText
  "placeholder": "Search issues…", // search field hint for this frame
  "grid": {"columns":4,"aspectRatio":1.0},
  "detail": {"markdown":"# Hi","metadata":[/*§6.1*/],"append":"…tok","wide":false},
  "form": {/*§7 form*/},
  "preview": {"enabled": true}, // or bare `true`
  "canGoBack": false, // Escape → {"type":"back"} instead of exiting; leave false on root screen; never true on a frame you can't navigate away from
  "actions": [/*frame-level Ctrl+K, §8, fired with id:""*/],
  "selectId": "item-3", // move highlight here after a rev:0 re-render
  "hasMore": false, // → loadMore events; answer with full list (old+new pages)
  "inputMode": "submit", // Enter sends whole line as submitQuery; 2nd Enter on unchanged text fires default action
  "selection": {"enabled": true, "max": 20}, // bulk select via Enter/Ctrl+Space/checkbox; ids in action.ids
  "columns": [{"id":"status","label":"Status","align":"end"}], // table view; items give matching `cells`
  "chart": {"title":"Latency","series":[{"id":"p95","label":"p95","values":[24,31],"color":"#63A0EA"}]}, // click→chartSelect
  "operation": {"id":"deploy-42","title":"Deploying","progress":0.4,"cancellable":true}, // cancellable→cancel event
  "dashboard": {"layout":"stack","panels":[{"id","title","height"?(96-640),/*+ view fields*/}]}, // independently-scrolling panels
  "items": [/*§6.2*/]
}
```

`view="list"|"grid"|"detail"|"chat"|"form"` are the common ones — see §7 for behavior of each.

### 6.1 Metadata entries (`preview.metadata` / `detail.metadata`)

Aligned key-value rows, preferred over markdown tables:

```jsonc
[
  { "label": "Status", "text": "In Progress", "color": "#8250DF" }, // dot + tint
  { "label": "Assignee", "text": "far-se", "icon": "person" },
  { "separator": true },
  { "label": "Docs", "text": "tailwindcss.com", "url": "https://..." }, // clickable
  { "label": "Trend", "sparkline": [12, 14, 11, 9], "text": "−3°" }, // mini-chart, needs ≥2 numbers
  {
    "label": "Poster",
    "text": "Poster Name",
    "image": "https://.../poster.webp",
    "width": 180,
  }, // 48–280px, default 132
  {
    "label": "Site",
    "text": "Example",
    "actions": [{ "id": "open", "title": "Open", "icon": "open" }],
  }, // buttons below value, same shape as Ctrl+K actions, fire `action` (id:"" in detail view)
]
```

### 6.2 Item reference

```jsonc
{
  "id": "unique-id", // stable, unique per frame; echoed in select/action
  "title": "Main text", // supports **bold** `code`, nothing else
  "subtitle": "Secondary text", // same markdown-lite
  "icon": "star", // §7 name | #RRGGBB | data:image/... | file://|https:// raster/SVG
  "section": "Today", // list/grid: group header on value change from prev item; keep same-section items adjacent
  "lines": 1, // list: subtitle wrap lines, 1–3
  "progress": 0.6, // list: thin progress bar, 0..1
  "tileColor": "#0EA5E9", // grid: fill tile, label auto-contrasts
  "accessories": [{ "text": "IT", "color": "#8250DF", "icon": "clock" }], // trailing chips; bare string ok too
  "actions": [{ "id": "copy", "title": "Copy", "icon": "copy" }], // Ctrl+K entries, §8
  "preview": {
    "markdown": "## Details...",
    "image": { "url": "...", "width": 160 },
    "metadata": [/*§6.1*/],
  }, // shown when selected; needs frame preview.enabled
}
```

## 7. View types

- **list** (default): icon+title+subtitle+accessories rows. Use `section`, `lines`, `progress`, colored accessories.
- **grid**: tiles in `grid.columns` cols, icon over title/subtitle. Arrow keys move 2-D. `tileColor` = filled swatch. Sections group like list.
- **detail**: single scrollable markdown doc (`detail.markdown`) + optional `detail.metadata`. No items. Supports headings/lists/bold/code/blockquotes; links clickable; text selectable; code blocks get copy button; images open in lightbox. ↑/↓ scroll, PageUp/PageDown jump page. `detail.wide:true` widens window. Query keystrokes still send `query` (re-render per query), or use `inputMode:"submit"` + stream via `detail.append` (§9) for chat-style.
- **chat**: message feed; item = message (`title`=author, `subtitle`=body, `icon`=avatar URL, `accessories`=timestamp, `images`=HTTP(S) attachment URLs). Pair with `inputMode:"submit"`; Enter → `submitQuery`. Auto-follows bottom while reading latest.
- **form**: see below.
- **preview pane (split)**: set frame-level `preview.enabled:true` on list/grid — items left, selected item's `preview.markdown`/`metadata` right. The window widens by default; set frame-level `preview.wide:false` to keep normal width. Item-level preview objects contain content only. Ignored for detail/form.

### Form

`submit` sends `{"type":"submit","values":{...},"button"?}`. Escape cancels (exits plugin, or sends `back` if `canGoBack:true`). Enter in single-line field submits.

```jsonc
{
  "type": "render",
  "rev": 0,
  "view": "form",
  "form": {
    "title": "New Issue",
    "submitLabel": "Create", // default "Submit"
    "buttons": [
      { "id": "create", "label": "Create" },
      { "id": "delete", "label": "Delete", "destructive": true },
    ], // optional, replaces single CTA
    "fields": [
      {
        "id": "title",
        "type": "text",
        "label": "Title",
        "placeholder": "Summary…",
        "required": true,
        "description": "hint under field",
      },
      { "id": "desc", "type": "textarea", "label": "Description" },
      { "id": "secret", "type": "password", "label": "API key" },
      {
        "id": "count",
        "type": "number",
        "label": "Count",
        "value": 1,
        "min": 1,
        "max": 10,
      },
      {
        "id": "due",
        "type": "date",
        "label": "Due date",
        "value": "2026-07-15",
      },
      { "id": "attach", "type": "filepicker", "label": "Attachment" },
      { "id": "outdir", "type": "folderpicker", "label": "Output folder" },
      {
        "id": "labels",
        "type": "tags",
        "label": "Labels",
        "value": ["bug"],
        "options": ["bug", { "value": "docs", "label": "Docs" }],
      },
      {
        "id": "team",
        "type": "dropdown",
        "label": "Team",
        "value": "eng",
        "watch": true,
        "options": ["eng", { "value": "ops", "label": "Operations" }],
      },
      { "id": "urgent", "type": "checkbox", "label": "Urgent", "value": true },
    ],
  },
}
```

Types (unknown → `text`): `text,password,textarea,dropdown,checkbox,number,date,filepicker,folderpicker,tags`. `submit.values`: strings (text-likes/dropdown/date `yyyy-mm-dd`/paths), bool (checkbox), number (null if empty), string[] (tags). `required` + `min`/`max` validated before you see submit (inline error); for your own validation re-render same form with `"error":"…"` on a field (typed values persist since field set unchanged). `watch:true` → `change` message on edit, re-render to update dependent fields. `buttons[].destructive:true` = danger tint. Re-rendering with the _same_ field ids preserves typed values; changing ids resets. Good for create-flows / settings (prefer `storage` command over writing `config.json` yourself).

## 8. Actions & Ctrl+K

Item `actions[]` + frame-level `actions[]` both populate Ctrl+K (item's first, then frame's after a divider; frame actions also work on detail/form). Enter → `action:"default"` always (even if unlisted). Ctrl+K pick → that action's id; frame-level arrives with `id:""`. You decide semantics (open/copy/toggle/delete/navigate). Respond with a command (§5.1) and/or new `rev:0` frame.

```jsonc
{
  "id": "delete",
  "title": "Delete issue",
  "icon": "trash",
  "shortcut": "ctrl+shift+d", // must include Ctrl and/or Alt; bare/Shift-only ignored
  "destructive": true, // red tint
  "confirm": {
    "title": "Delete this issue?",
    "message": "This cannot be undone.",
    "confirmLabel": "Delete",
  }, // or bare true; gates the action until accepted; listing on "default" also gates Enter
  "parameters": [
    {
      "id": "environment",
      "type": "dropdown",
      "label": "Environment",
      "required": true,
      "options": ["staging", "production"],
    },
  ], // compact host-shown form; values return in action.parameters
}
```

## 9. Selection, keyboard, lifecycle

Launcher owns selection (react to `select` optionally, e.g. lazy preview — usually unneeded since preview travels with the item). Arrow keys don't reach you. Enter/Ctrl+K → `action`; Tab → `tab` (answer with `setQuery` to autocomplete). Escape → exits (`close`) unless frame set `canGoBack:true` → you get `back`, render previous screen. Slow op: emit `loading:true` frame (echo rev) first, then result.

## 10. Icons

Name (case-insensitive, trailing `_rounded/_outlined/_sharp/_filled` ignored; unknown→generic) | hex color (`#F80`,`#FF8800`,`#AARRGGBB`, renders swatch) | `data:image/...` URI (≤2 MB) | `file://`/`https://` raster or SVG.

```
search star favorite heart home settings gear folder file document link globe world
cloud sun weather moon bolt flash terminal code calculator calc clock timer calendar
mail email message chat person user people image photo music video play download
upload copy content_copy clipboard paste edit pencil delete trash add plus remove
minus check close info warning error help tag label bookmark money currency cart shop
chart graph database server wifi bluetooth battery power lock unlock key shield bell
flag location map translate language palette color brush emoji grid list menu app
window extension plugin refresh sync gamepad game book note run open
```

## 11. Patterns

**HTTP/APIs**: runtime's client (`requests`/`urllib`, Node/Bun global `fetch`). Secrets from `config.json` in cwd or env vars.

**Config file**:

```python
import json, os
cfg = json.load(open("config.json", encoding="utf-8")) if os.path.exists("config.json") else {}
```

**Async loading** — echo rev, spinner, then result (same rev; stale results auto-dropped if user kept typing):

```python
send({"type":"render","rev":rev,"view":"list","loading":True,"items":[],"loadingText":"Searching…"})
results = do_slow_search(text)
send({"type":"render","rev":rev,"view":"list","items":[to_item(r) for r in results]})
```

**Multi-command state machine** (one query line, many internal "screens"): root screen lists commands as items (no `canGoBack`, so Esc exits). On `action:"default"` for `cmd:X`, set internal `screen=X`, render with `canGoBack:true`. On sub-screens treat query text as that screen's input. `back` message → reset `screen="root"`, re-render (no "◀ Back" item needed). Pair drill-down with `setQuery:""` + a `placeholder` describing the new filter.

**Streaming (chat/LLM)**: `inputMode:"submit"` + `detail.append`. Render intro `detail` frame with `inputMode:"submit"`; on `submitQuery`, stream from a **worker thread** (keep stdin loop responsive):

```python
def on_submit_query(prompt):
    def run():
        send({"type":"render","rev":0,"view":"detail","inputMode":"submit","canGoBack":True,"detail":{"markdown":f"# {prompt}\n\n"}})
        for token in call_llm_stream(prompt):
            send({"type":"render","rev":0,"view":"detail","inputMode":"submit","canGoBack":True,"detail":{"append":token}})
    threading.Thread(target=run, daemon=True).start()
```

View auto-pins to bottom unless user scrolled up.

**Pagination**: first page with `hasMore:true`; on `loadMore` answer with full list-so-far + next page (same rev), keep `hasMore` until done. Pair with `selectId` if reordering.

**Persistent state/secrets**: use `storage` command, not hand-rolled files. `set`/`delete` fire-and-forget; `get`/`keys` reply via `{"type":"storage"}` correlated by `requestId`. Tokens → `secret:true` (Credential Manager, never plaintext).

```python
send({"type":"command","command":"storage","op":"set","key":"token","value":"sk-…","secret":True})
send({"type":"command","command":"storage","op":"get","key":"token","secret":True,"requestId":"tok"})
```

**Outliving the launcher**: `background{timeout}` then `hide`; keep working (thread), `notify` when done; join worker on `close`.

```python
send({"type":"command","command":"background","timeout":60})
send({"type":"command","command":"hide"})
# … work …
send({"type":"command","command":"notify","title":"Sync","text":"Done — 42 items."})
```

**Error handling** — never crash; catch and render:

````python
try:
    ...
except Exception as e:
    send({"type":"render","rev":rev,"view":"detail","detail":{"markdown":f"# Error\n\n```\n{e}\n```"}})
````

## 12. Rules checklist

- stdout = render frames + commands ONLY; logs/debug → stderr.
- Flush stdout every frame; one JSON object per line, no embedded newlines.
- Echo `rev` for query responses; `rev:0` for action results/async pushes.
- Every item needs a stable unique `id`.
- Handle `close` AND stdin EOF by exiting; read stdin line-by-line, don't block.
- Keyword short & distinct. Only documented `view`/message/field values.
- Use commands (§5.1) for clipboard/open/hide/toast — never shell out.
- cwd = plugin folder (put `config.json` there).
- Deps auto-install: Python `pip`/`requirements.txt`; Node/Bun `package.json` (§3) — lazy-load heavy ones.
- Icons: §10 name, `#RRGGBB`, `data:image/...` URI (≤2 MB), or raster/SVG URL.
- Prefer `metadata` rows (§6.1) over markdown tables.
- Same-`section` items must stay adjacent.
- `canGoBack:true` on sub-screens only (handle `back`); never on a dead-end frame.
- Action `shortcut` needs Ctrl and/or Alt; bare/Shift-only ignored.
- Gate destructive actions with `confirm` + `destructive:true`.
- Streaming: work on a thread; every `detail.append` frame uses `rev:0`.
- `loadMore` replies carry the FULL list (old+new), not just the new page.
- Secrets → `storage` with `secret:true`, never in shipped `config.json`.
- `background` before `hide` for work that outlives the launcher; join workers on `close`.
- Build with `"dev":true` (hot reload+console); set `false` before sharing.

## 13. Python template

```python
#!/usr/bin/env python3
import sys, json

def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()

def log(*a):
    print(*a, file=sys.stderr, flush=True)  # debug -> stderr, safe

def render(rev, text):
    words = text.split() or ["type", "something"]
    items = [{
        "id": f"w{i}", "title": w, "subtitle": f"{len(w)} chars", "icon": "tag",
        "accessories": [{"text": str(len(w))}],
        "actions": [{"id": "default", "title": "Open", "icon": "open"},
                    {"id": "copy", "title": "Copy", "icon": "copy"}],
        "preview": {"markdown": f"## {w}\n\nLength: **{len(w)}**"},
    } for i, w in enumerate(words)]
    send({"type": "render", "rev": rev, "view": "list", "preview": {"enabled": True},
          "emptyText": "Nothing to show", "items": items})

def handle_action(item_id, action):
    send({"type": "render", "rev": 0, "view": "detail",
          "detail": {"markdown": f"# Action\n\n- item: `{item_id}`\n- action: `{action}`"}})

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
        if t == "close":
            break
        elif t in ("init", "query"):
            render(msg.get("rev", 0), msg.get("text", msg.get("query", "")))
        elif t == "action":
            handle_action(msg.get("id", ""), msg.get("action", "default"))

if __name__ == "__main__":
    main()
```

`plugin.json`: `{"name":"My Plugin","keyword":"mp","runtime":"python","entry":"main.py","icon":"star"}`

**Node/Bun**: same protocol/logic — `send()` = `process.stdout.write(JSON.stringify(frame)+"\n")`; buffer stdin chunks and split on `"\n"`; `msg.type==="close"` → `process.exit(0)`; also exit on stdin `"end"`. `runtime:"node"`, `entry:"main.js"` (or `"bun"`/`.ts`).

## 14. Prompt template for generating a plugin

> Using the Tabame Launcher Plugin spec above, write a **<Python|Node>** plugin. Keyword: `<keyword>`. It should: `<data source, what each item shows, what Enter does, what Ctrl+K actions to offer, list/grid/detail/preview>`. Read secrets from `config.json` in the plugin folder. Follow §12. Give `plugin.json` + script + the exact install folder.
