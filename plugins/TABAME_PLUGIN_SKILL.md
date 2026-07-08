# Tabame Launcher Plugin — Authoring Skill

> **How to use this document.** Paste it into an AI chatbot (ChatGPT, Claude, etc.)
> and then say what you want, e.g. *"Using this spec, write a Python plugin that
> searches my Zotero library"*. This file is the **complete** specification — the
> chatbot needs nothing else. If you're the AI reading this: treat everything
> below as authoritative. Do not invent fields or message types that aren't
> documented here. When in doubt, prefer the `list` view and copy one of the full
> templates in §15.

---

## 1. What a plugin is

Tabame's launcher can be extended with **plugins** — external scripts written in
**Python, Node.js, or Bun**. A plugin is a normal script that Tabame launches as a
long-running child process when the user types the plugin's **keyword** in the
launcher.

The conversation is **newline-delimited JSON over stdin/stdout**:

- **Tabame → your script (stdin):** UI events — the user's query text, selection
  changes, actions, and a shutdown signal.
- **Your script → Tabame (stdout):** **render frames** — JSON objects that fully
  describe what the launcher should display right now.

Your script is the source of truth for the UI. Every time you want the launcher
to show something different, you print a new render frame. The process stays
alive the whole time the plugin's keyword owns the query, and is shut down when
the user leaves it.

There is **no SDK and no dependencies** required — just read lines from stdin and
print lines to stdout.

---

## 2. Quick start (minimal example)

A plugin is a folder with a `plugin.json` and a script. Minimal Python plugin
that echoes the query as a single-item list:

`plugin.json`
```json
{
  "name": "Hello",
  "keyword": "hi",
  "runtime": "python",
  "entry": "main.py"
}
```

`main.py`
```python
import sys, json

def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    msg = json.loads(line)
    if msg["type"] == "close":
        break
    if msg["type"] in ("init", "query"):
        text = msg.get("text", msg.get("query", ""))
        rev = msg.get("rev", 0)
        send({
            "type": "render",
            "rev": rev,
            "view": "list",
            "items": [
                {"id": "1", "title": f"You typed: {text}", "subtitle": "hello world", "icon": "star"}
            ],
        })
```

Install it to `%localappdata%\Tabame\plugins\hello\`, open the launcher, and type
`hi something`.

---

## 3. Folder layout & manifest

Each plugin lives in its own folder under:

```
%localappdata%\Tabame\plugins\<your-plugin-id>\
    plugin.json      ← manifest (required)
    main.py          ← your script (any name; must match "entry")
    ...               ← anything else your script needs (config, assets)
```

### `plugin.json` fields

| Field | Required | Default | Meaning |
|---|---|---|---|
| `keyword` | **yes** | — | What the user types to launch the plugin, e.g. `"weather"`. Keep it short and unique. |
| `runtime` | **yes** | — | Command resolved on the system `PATH`: `"python"`, `"node"`, or `"bun"`. |
| `entry` | **yes** | — | Script filename, relative to the plugin folder, e.g. `"main.py"` / `"main.js"`. |
| `id` | no | folder name | Stable identifier. |
| `name` | no | folder name | Human title shown in the launcher's discovery hint. |
| `description` | no | `""` | One-line description. |
| `icon` | no | `"extension"` | Icon for the discovery hint (see §11). |
| `args` | no | `[]` | Extra command-line arguments inserted **before** `entry`. |

The launch command is effectively:
```
<runtime> <args...> <entry>
```
Example for a Bun + TypeScript plugin: `"runtime": "bun"`, `"entry": "main.ts"`.

**Installing / reloading:** drop the folder into the `plugins` directory, then
just **re-open the launcher** — it rescans the plugins folder every time it opens,
so you don't need to restart Tabame. Fix your script, reopen the launcher, and the
new version runs.

### Activation rule

The plugin activates when the launcher query **equals the keyword** or **starts
with `keyword + " "`**. So keyword `weather` matches `weather` and `weather rome`
but **not** `weatherman`. Your script receives the text *after* the keyword (the
`weather ` prefix is stripped). Plugin keywords take precedence over the
launcher's built-in prefixes, so pick a keyword that isn't a common word you also
search for.

---

## 4. Runtime & environment

- The runtime (`python`/`node`/`bun`) **must be installed and on the system
  `PATH`**. Tabame does not bundle a runtime. If it isn't found, the launcher
  shows an error instead of your UI.
- Your script's **working directory is the plugin folder**. Relative paths
  (config files, assets) resolve there.
- The process is started **without a shell**. Don't rely on shell features in
  your entry command.
- On Windows, Tabame sets `PYTHONIOENCODING=utf-8` and `PYTHONUTF8=1` so Python
  stdout/stdin is UTF-8. Node/Bun default to UTF-8 already.
- Use `node` 18+ or `bun` (both provide a global `fetch`), or any Python 3.

---

## 5. The protocol

**One JSON object per line, both directions. Always flush stdout after writing.**

### 5.1 Messages Tabame sends you (stdin)

| Message | When | Fields |
|---|---|---|
| `init` | Once, right after your process starts | `query`: the initial text after the keyword |
| `query` | On every keystroke while the keyword is active | `text`: current text after the keyword; `rev`: integer generation counter |
| `select` | When the highlighted item changes | `id`: the selected item's id; `rev` |
| `action` | On **Enter** (fires `action` = `"default"`) or when the user picks a **Ctrl+K** action | `id`: the item's id; `action`: `"default"` or the chosen action's id |
| `close` | When the plugin is being shut down | — |

Example stdin lines:
```json
{"type":"init","query":"rome"}
{"type":"query","text":"rome","rev":1}
{"type":"select","id":"item-2","rev":1}
{"type":"action","id":"item-2","action":"copy"}
{"type":"close"}
```

Notes:
- `init` is immediately followed by a `query` with the same text. You can treat
  both the same way (read `text`, falling back to `query`).
- `action` messages **have no `rev`**.
- Pressing **Enter** always sends `action:"default"`, whether or not you listed a
  `"default"` action on the item.

### 5.2 Messages you send Tabame (stdout)

Only **render frames** are meaningful:
```json
{"type":"render", ...}
```
Any other line you print to **stdout** is treated as diagnostic log output (it is
written to Tabame's `errors.log`, not shown). **Put debug prints on stderr**, and
only ever print render frames to stdout.

### 5.3 The `rev` staleness rule (important)

Every `query`/`select` carries a `rev` that increases as the user types. When you
send a render frame **in response to a query, echo that query's `rev`**. Tabame
**drops any frame whose `rev` is older than the latest query** — this prevents a
slow response to "rom" from overwriting the fresh results for "rome".

- Responding to a query → echo its `rev`.
- Sending an **unsolicited** frame (result of an action, a background refresh, an
  async result you always want shown) → use **`rev: 0`**, which is always
  accepted.

### 5.4 Lifecycle

1. User types the keyword → your process starts → you get `init` then `query`.
2. User keeps typing → you get `query` events (same process, no restart).
3. User moves the selection → you get `select` events.
4. User presses Enter or picks a Ctrl+K action → you get `action`.
5. User leaves the keyword / presses Esc / closes the launcher → you get `close`,
   then the process is terminated (~2s grace period, then killed).

**Handle shutdown:** exit on `close`, and also exit when stdin reaches EOF.

---

## 6. Render frame reference

```jsonc
{
  "type": "render",              // required, always "render"
  "rev": 0,                       // echo the query's rev, or 0 for unsolicited
  "view": "list",                // "list" | "grid" | "detail"   (default "list")
  "loading": false,               // show a spinner when true and items is empty
  "emptyText": "No results",     // shown when items is empty and not loading
  "grid": { "columns": 4, "aspectRatio": 1.0 },   // only used by "grid" view
  "detail": { "markdown": "# Hi" },                // only used by "detail" view
  "preview": { "enabled": true },                  // split preview pane (list/grid)
  "items": [ /* see §7 */ ]
}
```

| Field | Type | Notes |
|---|---|---|
| `view` | string | `"list"` (rows), `"grid"` (tiles), or `"detail"` (full-width markdown). Default `list`. |
| `loading` | bool | When `true` and `items` empty, a spinner is shown. Use it before a slow fetch. |
| `emptyText` | string | Message when there are no items. Default `"No results"`. |
| `grid.columns` | int 1–12 | Number of columns in grid view. Default 4. |
| `grid.aspectRatio` | number | Tile width/height ratio. Default 1.0. |
| `detail.markdown` | string | Markdown body for detail view. (You may also pass `"detail": "..."` as a plain string.) |
| `preview.enabled` | bool | When `true` (list/grid only), a split preview pane appears on the right showing the **selected item's** preview. The launcher window widens automatically and restores when you leave. (You may also pass `"preview": true`.) |
| `items` | array | The rows/tiles. See §7. |

---

## 7. Item reference

```jsonc
{
  "id": "unique-id",             // stable, unique within the frame
  "title": "Main text",
  "subtitle": "Secondary text",
  "icon": "star",                // icon name, or file://... / https://...  (see §11)
  "accessories": [ { "text": "IT" } ],       // trailing chips (string or {text})
  "actions": [                                 // populate the Ctrl+K menu
    { "id": "copy", "title": "Copy", "icon": "copy" }
  ],
  "preview": { "markdown": "## Details..." }  // shown in the preview pane when selected
}
```

| Field | Type | Notes |
|---|---|---|
| `id` | string | **Give every item a stable, unique id.** It's echoed back in `select`/`action`. |
| `title` | string | Primary line. |
| `subtitle` | string | Secondary line (dimmed). |
| `icon` | string | Icon name (§11), or a `file://` / `https://` **raster** image (PNG/JPG; no SVG). |
| `accessories` | array | Trailing badges. Each is `{"text":"..."}` or a bare string. |
| `actions` | array | Entries for the item's **Ctrl+K** menu. Each: `{id, title, icon?}`. `icon` optional. |
| `preview` | object/string/null | Markdown shown in the preview pane while this item is selected. `{"markdown":"..."}` or a plain string. Only visible when the frame sets `preview.enabled`. |

---

## 8. View types

### list
Vertical rows: icon + title + subtitle + optional trailing accessory badges. The
default and the right choice for most plugins.

### grid
Tiles laid out in `grid.columns` columns; each tile shows the icon over the title
and subtitle. Good for emoji/color/image pickers. Arrow keys move in 2-D.

### detail
A single full-width, scrollable **markdown** view (`detail.markdown`). No item
list. Use it for long content, confirmations, help, or error messages. Supports
standard markdown: headings, lists, **bold**, `code`, fenced code blocks, and
> quotes. Markdown **links render but are not clickable** — to actually open a
URL, expose it as an item **action** and open it yourself (see §12), don't rely
on the user tapping a link.

### preview pane (split)
Set `"preview": {"enabled": true}` on a `list` or `grid` frame. The launcher
shows the items on the left and, on the right, the **selected item's**
`preview.markdown`. As the user arrows through items, the pane updates from each
item's `preview`. The window widens to fit and restores when the plugin exits.
(Ignored for `detail` view.)

---

## 9. Actions & Ctrl+K

- Each item can carry an `actions` array. These appear in a **Ctrl+K** command
  palette for the highlighted item.
- **Enter** on an item sends `{"type":"action","id":<item>,"action":"default"}`.
  Treat `"default"` as "the primary thing this item does" (open it, run it,
  create it, drill into it…).
- Picking a Ctrl+K entry sends `{"type":"action","id":<item>,"action":<that id>}`.
- **You decide what each action does.** Common patterns: open a URL, copy text,
  toggle state, delete, or navigate your own internal screens.
- After handling an action, you'll usually want to **print a new render frame**
  (with `rev: 0`) — e.g. a confirmation `detail` frame, or an updated list.

---

## 10. Selection, keyboard, lifecycle notes

- **Selection is owned by the launcher.** You don't set the selected index; you
  react to `select` events if you want to (e.g. lazy-load a preview). Because the
  frame already carries each item's `preview`, handling `select` is usually
  optional.
- **Navigation keys** (arrows) are handled by the launcher and don't reach you.
- **Enter** and **Ctrl+K** reach you as `action` messages.
- **Escape** exits the whole plugin (you get `close`). There is **no built-in
  "back"** — if your plugin has multiple screens, provide your own back
  affordance (see §13).
- Keep the event loop responsive. If an operation is slow, first emit a
  `loading:true` frame (echoing the rev), then emit the result frame.

---

## 11. Icons

`icon` accepts a **name** from the list below (case-insensitive; a trailing
`_rounded`/`_outlined`/`_sharp`/`_filled` is ignored). Unknown names fall back to
a generic plugin icon. You can also pass a `file://` or `https://` URL to a
**raster** image (PNG/JPG — **not SVG**).

Available names:

```
search  star  favorite  heart  home  settings  gear  folder  file  document
link  globe  world  cloud  sun  weather  moon  bolt  flash  terminal  code
calculator  calc  clock  timer  calendar  mail  email  message  chat  person
user  people  image  photo  music  video  play  download  upload  copy
content_copy  clipboard  paste  edit  pencil  delete  trash  add  plus  remove
minus  check  close  info  warning  error  help  tag  label  bookmark  money
currency  cart  shop  chart  graph  database  server  wifi  bluetooth  battery
power  lock  unlock  key  shield  bell  flag  location  map  translate  language
palette  color  brush  emoji  grid  list  menu  app  window  extension  plugin
refresh  sync  gamepad  game  book  note  run  open
```

---

## 12. Doing real work

Because your plugin is an ordinary process, it can do anything the runtime can —
network requests, filesystem access, spawning tools. Some recipes:

**HTTP / APIs** — use the runtime's HTTP client (`requests`/`urllib` in Python,
global `fetch` in Node 18+/Bun). Read secrets from a `config.json` in the plugin
folder (the working directory) or from environment variables.

**Open a URL in the browser (Windows):**
- Python: `subprocess.Popen(["cmd", "/c", "start", "", url])`
- Node: `require('child_process').spawn('cmd', ['/c','start','',url], {detached:true}).unref()`

**Copy text to the clipboard (Windows):**
- Python:
  ```python
  import subprocess
  p = subprocess.Popen(["cmd", "/c", "clip"], stdin=subprocess.PIPE)
  p.communicate(text.encode("utf-16-le"))  # or utf-8; clip accepts both
  ```
- Node:
  ```js
  const c = require('child_process').spawn('cmd', ['/c','clip']);
  c.stdin.write(text); c.stdin.end();
  ```

**Config file** — read `config.json` from the current working directory:
```python
import json, os
cfg = {}
if os.path.exists("config.json"):
    cfg = json.load(open("config.json", encoding="utf-8"))
```

---

## 13. Patterns

### Async loading
For slow work, echo the rev and show a spinner first, then the result:
```python
send({"type":"render","rev":rev,"view":"list","loading":True,"items":[],"emptyText":"Searching…"})
results = do_slow_search(text)     # network, etc.
send({"type":"render","rev":rev,"view":"list","items":[to_item(r) for r in results]})
```
Both frames carry the same `rev`, so if the user kept typing, Tabame drops the
stale result automatically.

### Multi-command plugins (internal state machine)
The launcher gives you one query line, so a plugin with several "commands" should
keep its own screen state:

1. Start on a **root** screen that lists your commands as items (filter them by
   the query text).
2. When the user presses Enter on a command (`action:"default"`), switch your
   internal `screen` variable and render that command's view.
3. On sub-screens, treat the query text as that screen's search/input.
4. Because Escape exits the whole plugin, add a **"◀ Back"** item (or a Ctrl+K
   `back` action) that resets `screen` to root.

Sketch:
```python
state = {"screen": "root"}

def handle_action(item_id, action):
    if item_id.startswith("cmd:"):
        state["screen"] = item_id[4:]      # drill into a command
        return render(0, "")
    if item_id == "nav:back" or action == "back":
        state["screen"] = "root"
        return render(0, "")
    # ... item-specific actions (open, copy, create) ...
```

### Error handling
Never crash on bad input or a failed request. Catch errors and show them:
```python
try:
    ...
except Exception as e:
    send({"type":"render","rev":rev,"view":"detail",
          "detail":{"markdown":f"# Error\n\n```\n{e}\n```"}})
```

---

## 14. Rules & gotchas checklist

- [ ] **stdout is only for render frames.** Send logs/debug to **stderr**.
- [ ] **Flush stdout** after every frame (Python `flush=True`; Node `process.stdout.write` is fine but end each with `\n`).
- [ ] **One JSON object per line**, no embedded newlines in the serialized frame.
- [ ] **Echo `rev`** for query responses; use **`rev: 0`** for action results / async pushes.
- [ ] **Give every item a stable unique `id`.**
- [ ] **Handle `close` and stdin EOF** by exiting.
- [ ] **Read stdin line by line**; don't block waiting for all input.
- [ ] Keep the keyword **short and distinct**.
- [ ] Only use documented `view` values, message types, and fields.
- [ ] Remember the working directory is the **plugin folder** (put `config.json` there).
- [ ] Icons must be a name from §11 or a `file://`/`https://` **raster** image.

---

## 15. Full templates

### 15.1 Python template

```python
#!/usr/bin/env python3
import sys, json

def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()

def log(*a):                       # debug -> stderr (safe)
    print(*a, file=sys.stderr, flush=True)

def render(rev, text):
    # Build items based on `text`. Replace with your real logic.
    words = text.split() or ["type", "something"]
    items = []
    for i, w in enumerate(words):
        items.append({
            "id": f"w{i}",
            "title": w,
            "subtitle": f"{len(w)} chars",
            "icon": "tag",
            "accessories": [{"text": str(len(w))}],
            "actions": [
                {"id": "default", "title": "Open", "icon": "open"},
                {"id": "copy", "title": "Copy", "icon": "copy"},
            ],
            "preview": {"markdown": f"## {w}\n\nLength: **{len(w)}**"},
        })
    send({
        "type": "render",
        "rev": rev,
        "view": "list",
        "preview": {"enabled": True},
        "emptyText": "Nothing to show",
        "items": items,
    })

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
        # "select": optional; previews are per-item already.

if __name__ == "__main__":
    main()
```

`plugin.json`
```json
{ "name": "My Plugin", "keyword": "mp", "runtime": "python", "entry": "main.py", "icon": "star" }
```

### 15.2 Node.js / Bun template

```js
'use strict';

function send(frame) {
  process.stdout.write(JSON.stringify(frame) + '\n');
}
function log(...a) { console.error(...a); }   // debug -> stderr

function render(rev, text) {
  const words = text.split(/\s+/).filter(Boolean);
  const list = words.length ? words : ['type', 'something'];
  const items = list.map((w, i) => ({
    id: `w${i}`,
    title: w,
    subtitle: `${w.length} chars`,
    icon: 'tag',
    accessories: [{ text: String(w.length) }],
    actions: [
      { id: 'default', title: 'Open', icon: 'open' },
      { id: 'copy', title: 'Copy', icon: 'copy' },
    ],
    preview: { markdown: `## ${w}\n\nLength: **${w.length}**` },
  }));
  send({ type: 'render', rev, view: 'list', preview: { enabled: true }, emptyText: 'Nothing to show', items });
}

function handleAction(id, action) {
  send({ type: 'render', rev: 0, view: 'detail',
    detail: { markdown: `# Action\n\n- item: \`${id}\`\n- action: \`${action}\`` } });
}

let buf = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  buf += chunk;
  let i;
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    let msg;
    try { msg = JSON.parse(line); } catch { continue; }
    if (msg.type === 'close') process.exit(0);
    else if (msg.type === 'init' || msg.type === 'query') render(msg.rev || 0, msg.text != null ? msg.text : (msg.query || ''));
    else if (msg.type === 'action') handleAction(msg.id || '', msg.action || 'default');
  }
});
process.stdin.on('end', () => process.exit(0));
```

`plugin.json`
```json
{ "name": "My Plugin", "keyword": "mp", "runtime": "node", "entry": "main.js", "icon": "star" }
```

---

## 16. Ready-to-use prompt

Paste this document into your chatbot, then add a request like:

> Using the Tabame Launcher Plugin spec above, write a **<Python|Node>** plugin.
> Keyword: `<keyword>`. It should: `<describe what it does — data source, what each
> item shows, what Enter does, what Ctrl+K actions to offer, and whether to use a
> list / grid / detail / preview pane>`. Read any secrets from `config.json` in the
> plugin folder. Follow every rule in §14 and give me both `plugin.json` and the
> script, plus the exact folder to drop them in.

The chatbot should return a complete, ready-to-install plugin.
