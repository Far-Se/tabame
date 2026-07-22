---
name: tbm-plugin
description: Author a Tabame launcher plugin — an external Python/Node/Bun script that extends the app launcher, talking newline-delimited JSON over stdin/stdout. Use when the user wants to build, scaffold, debug, or install a Tabame launcher plugin, add a new launcher keyword backed by a script, or asks about the plugin render-frame protocol.
---

# Tabame Launcher Plugin — Authoring Skill

> **How to use this document.** Paste it into an AI chatbot (ChatGPT, Claude, etc.)
> and then say what you want, e.g. _"Using this spec, write a Python plugin that
> searches my Zotero library"_. This file is the **complete** specification — the
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

There is **no SDK** — just read lines from stdin and print lines to stdout. No
third-party packages are needed for the protocol itself; if your plugin's own
logic wants extra libraries, see §4.1.

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

| Field         | Required | Default       | Meaning                                                                                                                                          |
| ------------- | -------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `keyword`     | **yes**  | —             | What the user types to launch the plugin, e.g. `"weather"`. Keep it short and unique.                                                            |
| `runtime`     | **yes**  | —             | Command resolved on the system `PATH`: `"python"`, `"node"`, or `"bun"`.                                                                         |
| `entry`       | **yes**  | —             | Script filename, relative to the plugin folder, e.g. `"main.py"` / `"main.js"`.                                                                  |
| `id`          | no       | folder name   | Stable identifier.                                                                                                                               |
| `name`        | no       | folder name   | Human title shown in the launcher's discovery hint.                                                                                              |
| `description` | no       | `""`          | One-line description.                                                                                                                            |
| `icon`        | no       | `"extension"` | Icon for the discovery hint (see §11).                                                                                                           |
| `args`        | no       | `[]`          | Extra command-line arguments inserted **before** `entry`.                                                                                        |
| `pip`         | no       | `[]`          | **Python only.** Packages to auto-install into the plugin's own `.pluginlibs` folder on first run (see §4.1). e.g. `["requests", "pillow>=10"]`. |
| `env`         | no       | `{}`          | Extra environment variables handed to the process, e.g. `{"API_BASE": "https://…"}`. Merged on top of Tabame's defaults.                         |
| `dev`         | no       | `false`       | Development mode: hot reload + on-screen debug console (see below). Turn it off before sharing the plugin.                                       |

The launch command is effectively:

```
<runtime> <args...> <entry>
```

Example for a Bun + TypeScript plugin: `"runtime": "bun"`, `"entry": "main.ts"`.

**Installing / reloading:** drop the folder into the `plugins` directory, then
just **re-open the launcher** — it rescans the plugins folder every time it opens,
so you don't need to restart Tabame. Fix your script, reopen the launcher, and the
new version runs.

### Dev mode (`"dev": true`)

While you're building a plugin, set `"dev": true` in `plugin.json`. Two things
happen while your plugin is active:

- **Hot reload** — Tabame watches the plugin folder and restarts your process
  whenever a file changes (saves are debounced; `__pycache__`, `node_modules`,
  `.git`, `.log`/`.tmp` files are ignored). After the restart the current query
  is replayed, so you stay right where you were testing.
- **Debug console** — a collapsible console strip appears under your plugin's
  view showing, live: everything you print to **stderr**, malformed stdout
  lines, frames dropped by the `rev` staleness rule, accepted frames, commands,
  and process starts/crashes. Click the strip to expand it. This is the fastest
  way to see _why_ a frame you sent didn't show up.

Set `dev` back to `false` (or remove it) before sharing the plugin.

### Activation rule

The plugin activates when the launcher query **equals the keyword** or **starts
with `keyword + " "`**. So keyword `weather` matches `weather` and `weather rome`
but **not** `weatherman`. Your script receives the text _after_ the keyword (the
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

### 4.1 Third-party packages (dependencies)

The runtime resolves imports from the plugin folder, so how you add a library
depends on the runtime.

**Python — declare them and Tabame installs them.** List packages in a `"pip"`
array in `plugin.json`, and/or drop a `requirements.txt` next to your script:

```json
{
  "keyword": "img",
  "runtime": "python",
  "entry": "main.py",
  "pip": ["requests", "pillow>=10"]
}
```

On the first launch (and again whenever the list or `requirements.txt` changes),
Tabame runs `pip install --target .pluginlibs …` into a `.pluginlibs` folder
inside the plugin, shows an "Installing dependencies…" spinner while it works,
then puts `.pluginlibs` on `PYTHONPATH`. Your script just imports normally:

```python
import requests          # resolved from .pluginlibs, no sys.path juggling
```

Notes:

- Installs are cached — pip only re-runs when your declared set changes, so
  normal launches stay instant.
- `.pluginlibs` is self-contained inside the plugin folder, so the plugin stays
  portable. It's ignored by the dev-mode file watcher (no reload storms).
- `pip` must be available for your `runtime` (Tabame calls `<runtime> -m pip`).
  If an install fails, the launcher shows the pip error instead of your UI.
- No network/opaque-install worries? You can still vendor packages yourself by
  running `pip install --target .pluginlibs <pkg>` in the plugin folder by hand —
  Tabame adds `.pluginlibs` to `PYTHONPATH` whenever it exists.

**Node.js / Bun — ship a `package.json` and Tabame installs it for you.** If the
plugin folder has a `package.json` but no (up-to-date) `node_modules`, Tabame runs
`npm install` (or `bun install` for the Bun runtime) in the folder on the first
launch, showing an "Installing dependencies…" spinner, then starts your script.
Node resolves `require`/`import` from that local `node_modules`, so you just:

```json
{ "keyword": "fonts", "runtime": "node", "entry": "main.js" }
```

with a `package.json` listing your deps:

```json
{ "dependencies": { "puppeteer": "^23.0.0" } }
```

Notes:

- The install is cached (keyed on `package.json`) and only re-runs when your
  `package.json` changes, so normal launches stay instant.
- `npm`/`bun` must be on `PATH`; on failure the launcher shows the install error.
  Guard your own `require()` of a heavy dependency (or lazy-load it) so a missing
  package renders a friendly message rather than crashing the process.
- You can still `npm install` by hand in the folder, or **bundle to a single
  dependency-free file** so there's nothing to install at all:

  ```
  esbuild main.js --bundle --platform=node --format=cjs --outfile=main.bundle.js
  ```

  Then point `entry` at the bundle: `"entry": "main.bundle.js"`. (Bun users can
  also `bun build main.js --target=node --outfile=main.bundle.js`.)

**Custom env vars** for any runtime go in the `"env"` object of `plugin.json`
(e.g. an API base URL), and are readable via `os.environ` / `process.env`.

---

## 5. The protocol

**One JSON object per line, both directions. Always flush stdout after writing.**

### 5.1 Messages Tabame sends you (stdin)

| Message       | When                                                                                                             | Fields                                                                                                                                                                                       |
| ------------- | ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `init`        | Once, right after your process starts                                                                            | `query`: initial text after the keyword; `protocol`: int protocol version (currently 5); `theme`: `{accent, text, background, dark}` — hex colors + dark-mode flag; `locale`: e.g. `"en-US"` |
| `query`       | On every keystroke while the keyword is active (not sent in `inputMode: "submit"`)                               | `text`: current text after the keyword; `rev`: integer generation counter                                                                                                                    |
| `submitQuery` | **Enter** while the frame declared `inputMode: "submit"` — the whole query line at once (chat-style input)       | `text`, `rev`                                                                                                                                                                                |
| `select`      | When the highlighted item changes                                                                                | `id`: the selected item's id; `rev`                                                                                                                                                          |
| `action`      | On **Enter** (fires `action` = `"default"`), a **Ctrl+K** pick, an action **shortcut**, or the empty state's CTA | `id`: the item's id (`""` for frame-level actions and the empty-state button); `action`: `"default"` or the chosen action's id                                                               |
| `submit`      | When the user submits a **form** view                                                                            | `values`: `{fieldId: value}` (strings, booleans, numbers, string lists — see §8); `button`: the pressed `form.buttons` id (absent for the default CTA)                                       |
| `change`      | A form field with `"watch": true` changed                                                                        | `id`: the field's id; `values`: all current field values                                                                                                                                     |
| `loadMore`    | The user scrolled near the end of a frame with `hasMore: true`                                                   | `rev` — answer with a longer item list                                                                                                                                                       |
| `storage`     | Reply to a `storage` command with `op` `get`/`keys`                                                              | `requestId` (echoed), and `key`+`value` or `keys`                                                                                                                                            |
| `clipboard`   | Reply to a `clipboardRead` command                                                                               | `requestId` (echoed), `text`                                                                                                                                                                 |
| `back`        | **Escape** on a frame that declared `canGoBack: true`                                                            | `rev` — respond by rendering the previous screen                                                                                                                                             |
| `tab`         | **Tab** pressed                                                                                                  | `id`: the highlighted item's id (`""` if none); `rev` — typically answered with a `setQuery` command                                                                                         |
| `close`       | When the plugin is being shut down                                                                               | —                                                                                                                                                                                            |

Example stdin lines:

```json
{"type":"init","query":"rome","protocol":3,"theme":{"accent":"#63A0EA","text":"#E8E8E8","background":"#1B1D23","dark":true},"locale":"en-US"}
{"type":"query","text":"rome","rev":1}
{"type":"select","id":"item-2","rev":1}
{"type":"action","id":"item-2","action":"copy"}
{"type":"tab","id":"item-2","rev":1}
{"type":"back","rev":1}
{"type":"close"}
```

Notes:

- `init` is immediately followed by a `query` with the same text. You can treat
  both the same way (read `text`, falling back to `query`).
- Use `theme` to generate images/SVGs that match the launcher (accent color,
  dark vs light), and `protocol` to detect host capabilities.
- `action` messages **have no `rev`**.
- Pressing **Enter** always sends `action:"default"`, whether or not you listed a
  `"default"` action on the item.

### 5.2 Messages you send Tabame (stdout)

Two message types are meaningful: **render frames** and **commands**.

```json
{"type":"render", ...}
{"type":"command","command":"...", ...}
```

Any other line you print to **stdout** is treated as diagnostic log output (it is
written to Tabame's `errors.log`, not shown). **Put debug prints on stderr**, and
only ever print protocol messages to stdout.

#### Commands — asking Tabame to do things

Instead of shelling out to `clip`/`start` yourself, ask the host:

| Command         | Fields                                          | Effect                                                                                                                                                                                                                                                                                                                                                      |
| --------------- | ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `copy`          | `text`                                          | Puts `text` on the clipboard and shows a "Copied to clipboard" toast.                                                                                                                                                                                                                                                                                       |
| `paste`         | `text`                                          | Puts `text` on the clipboard, **hides the launcher**, re-activates the previously focused window, and sends **Ctrl+V** — i.e. types the text where the user was working.                                                                                                                                                                                    |
| `open`          | `url` (or `path`)                               | Opens a URL in the default browser, or a file/folder with its default handler.                                                                                                                                                                                                                                                                              |
| `hide`          | —                                               | Hides the launcher.                                                                                                                                                                                                                                                                                                                                         |
| `toast`         | `text`, `style`?, `progress`?                   | Shows a transient chip over the results area. `style`: `"success"` (default), `"error"`, `"info"`, or `"progress"`. A `progress` toast **stays pinned** (with a spinner, or a determinate ring when `progress` 0–1 is given) until a later `toast` replaces it — re-send to update it in place.                                                             |
| `setQuery`      | `text`                                          | Rewrites the search field's **post-keyword** text (the keyword stays). Use it to autocomplete after a `tab` message or to drill down while keeping the query bar in sync. Triggers a normal `query` event back to you.                                                                                                                                      |
| `clipboardRead` | `requestId`?                                    | Asks for the clipboard's text; the host answers with a `{"type":"clipboard","requestId","text"}` message.                                                                                                                                                                                                                                                   |
| `notify`        | `title`?, `text`                                | Fires a **native Windows notification** (works even while finishing in the background — see `background`). `title` defaults to the plugin name.                                                                                                                                                                                                             |
| `storage`       | `op`, `key`?, `value`?, `secret`?, `requestId`? | Per-plugin persistent key-value store. `op` is `"set"`, `"get"`, `"delete"`, or `"keys"`. Plain values live in `.tabame-store.json` in the plugin folder; `"secret": true` routes the value to the **Windows Credential Manager** instead (strings only; not listed by `keys`). `get`/`keys` reply with a `{"type":"storage"}` message echoing `requestId`. |
| `background`    | `timeout`?                                      | Requests shutdown grace: after the launcher hides / the user leaves, the process is **not killed** for up to `timeout` seconds (default 30, max 300) so it can finish work. While detached it can still use `storage` and `notify`, but frames and UI commands are dropped. Send it **before** `hide`.                                                      |

Example stdout lines:

```json
{"type":"command","command":"copy","text":"#FF8800"}
{"type":"command","command":"open","url":"https://example.com"}
{"type":"command","command":"toast","text":"Issue created"}
{"type":"command","command":"hide"}
```

Notes:

- Commands are fire-and-forget: **no `rev`**, no response.
- Combine effects by printing several lines — the classic "Enter = copy and
  dismiss" is `copy` followed by `hide`.
- `hide` and `paste` close the launcher, which **shuts your plugin down** (you
  get `close`). Print any final frames/commands before or immediately with them;
  don't expect to keep running afterwards.
- A `copy` followed by `hide` skips the toast — the launcher is gone before it
  would render.

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
  "type": "render", // required, always "render"
  "rev": 0, // echo the query's rev, or 0 for unsolicited
  "view": "list", // "list" | "grid" | "detail" | "form"   (default "list")
  "loading": false, // bool, or {"progress": 0.4} for a determinate spinner
  "loadingText": "Searching…", // caption shown under the spinner while loading
  "emptyText": "No results", // shown when items is empty and not loading
  "empty": { "icon": "cloud", "title": "No issues", "hint": "Try a filter" }, // richer empty state
  "placeholder": "Search issues…", // search-field hint while this frame is shown
  "grid": { "columns": 4, "aspectRatio": 1.0 }, // only used by "grid" view
  "detail": { "markdown": "# Hi", "metadata": [/* see §7.1 */] }, // only used by "detail" view
  "form": {/* see §8, form */}, // only used by "form" view
  "preview": { "enabled": true }, // split preview pane (list/grid)
  "canGoBack": false, // Escape sends {"type":"back"} instead of exiting
  "actions": [/* frame-level Ctrl+K actions, see §9 */],
  "selectId": "item-3", // move the highlight to this item
  "hasMore": false, // more items exist -> loadMore events
  "inputMode": "submit", // Enter submits the query (chat-style)
  "items": [/* see §7 */],
}
```

| Field              | Type           | Notes                                                                                                                                                                                                                                                                            |
| ------------------ | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `view`             | string         | `"list"` (rows), `"grid"` (tiles), `"detail"` (full-width markdown), or `"form"` (inputs). Default `list`.                                                                                                                                                                       |
| `loading`          | bool or object | When truthy and `items` empty, a spinner is shown. `{"progress": 0..1}` makes it determinate.                                                                                                                                                                                    |
| `loadingText`      | string         | Optional caption shown **under the spinner** while `loading`. Use this (not `emptyText`) for "Searching…"-style progress text — `emptyText` is only shown when _not_ loading.                                                                                                    |
| `emptyText`        | string         | Message when there are no items. Default `"No results"`.                                                                                                                                                                                                                         |
| `empty`            | object         | Richer empty state: `{icon?, title?, hint?, action?}` — icon name (§11), bold title, dimmed hint, and an optional call-to-action button (`{id, title, icon?}`; clicking sends `{"type":"action","id":"","action":<id>}`). Overrides `emptyText`.                                 |
| `placeholder`      | string         | Replaces the search field's hint text while this frame is shown (good affordance for sub-screens).                                                                                                                                                                               |
| `grid.columns`     | int 1–12       | Number of columns in grid view. Default 4.                                                                                                                                                                                                                                       |
| `grid.aspectRatio` | number         | Tile width/height ratio. Default 1.0.                                                                                                                                                                                                                                            |
| `detail.markdown`  | string         | Markdown body for detail view. (You may also pass `"detail": "..."` as a plain string.)                                                                                                                                                                                          |
| `detail.append`    | string         | **Streaming:** a chunk added to the _end_ of the markdown currently on screen instead of replacing the document — send many small `append` frames (`rev: 0`) to stream an answer token by token. The view stays pinned to the bottom while the user is reading the end. See §13. |
| `detail.metadata`  | array          | Key-value rows rendered under the markdown. See §7.1.                                                                                                                                                                                                                            |
| `detail.wide`      | bool           | Widens the launcher window for the document (like the split preview does), restoring it when you leave. Default false.                                                                                                                                                           |
| `form`             | object         | The form definition when `view` is `"form"`. See §8.                                                                                                                                                                                                                             |
| `preview.enabled`  | bool           | When `true` (list/grid only), a split preview pane appears on the right showing the **selected item's** preview. The launcher window widens automatically and restores when you leave. (You may also pass `"preview": true`.)                                                    |
| `canGoBack`        | bool           | When `true`, **Escape sends `{"type":"back"}`** (render your previous screen) instead of exiting the plugin. Leave it false on your root screen. Default false.                                                                                                                  |
| `actions`          | array          | **Frame-level actions** shown in the Ctrl+K palette regardless of the highlighted item (refresh, create, sign out…), after the item's own actions. Same shape as item actions (§9), fired with an empty `id`.                                                                    |
| `selectId`         | string         | Moves the highlight to the item with this id — keep the cursor on the same row after a refresh/reorder (`rev: 0` re-render).                                                                                                                                                     |
| `hasMore`          | bool           | List/grid: more items exist. Scrolling near the end sends `{"type":"loadMore","rev"}`; answer with a **longer full list** (a "Loading more…" footer shows meanwhile). See §13.                                                                                                   |
| `inputMode`        | string         | `"submit"`: keystrokes are **not** streamed to you; Enter sends one `{"type":"submitQuery","text","rev"}` with the whole line. A second Enter on unchanged text fires the selected item's default action instead. Right for chat/LLM plugins.                                    |
| `items`            | array          | The rows/tiles. See §7.                                                                                                                                                                                                                                                          |

---

## 7. Item reference

```jsonc
{
  "id": "unique-id", // stable, unique within the frame
  "title": "Main text", // supports **bold** and `code` spans
  "subtitle": "Secondary text", // same markdown-lite subset
  "icon": "star", // icon name, #RRGGBB swatch, or file://... / https://...  (see §11)
  "section": "Today", // list view: group header (see below)
  "lines": 1, // list view: subtitle wrap lines, 1–3
  "progress": 0.6, // list view: thin progress bar under the row (0..1)
  "tileColor": "#0EA5E9", // grid view: fill the tile with this color
  "accessories": [{ "text": "IT", "color": "#8250DF", "icon": "clock" }], // trailing chips
  "actions": [
    // populate the Ctrl+K menu
    { "id": "copy", "title": "Copy", "icon": "copy" },
  ],
  "preview": {
    // shown in the preview pane when selected
    "markdown": "## Details...",
    "image": { "url": "https://example.com/poster.webp", "width": 160 }, // right of markdown
    "metadata": [/* see §7.1 */],
  },
}
```

| Field         | Type               | Notes                                                                                                                                                                                                                                                                                                |
| ------------- | ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`          | string             | **Give every item a stable, unique id.** It's echoed back in `select`/`action`.                                                                                                                                                                                                                      |
| `title`       | string             | Primary line. May contain `**bold**` and `` `code` `` spans — anything more is literal text.                                                                                                                                                                                                         |
| `subtitle`    | string             | Secondary line (dimmed). Same markdown-lite subset.                                                                                                                                                                                                                                                  |
| `icon`        | string             | Icon name (§11), a `#RRGGBB` color (renders a swatch), or a `file://` / `https://` **raster** image (PNG/JPG; no SVG).                                                                                                                                                                               |
| `section`     | string             | List view: items are grouped under a slim header whenever this value differs from the previous item's. Keep items with the same section adjacent.                                                                                                                                                    |
| `lines`       | int 1–3            | List view: how many lines the subtitle may wrap to. Default 1.                                                                                                                                                                                                                                       |
| `progress`    | number 0–1         | List view: renders a thin progress bar under the row (downloads, timers).                                                                                                                                                                                                                            |
| `tileColor`   | string             | Grid view: fills the tile with this `#RRGGBB` color; label flips black/white for contrast. Perfect for color pickers.                                                                                                                                                                                |
| `accessories` | array              | Trailing badges. Each is a bare string or `{"text", "color"?, "icon"?}` — `color` tints the chip, `icon` is a §11 name.                                                                                                                                                                              |
| `actions`     | array              | Entries for the item's **Ctrl+K** menu. Each: `{id, title, icon?, shortcut?, destructive?, confirm?}` — see §9 for the last three.                                                                                                                                                                   |
| `preview`     | object/string/null | Shown in the preview pane while this item is selected: `{"markdown"?, "image": {"url", "width"?}, "metadata"?}` or a plain markdown string. `image` is an HTTP(S) raster displayed to the right of markdown; `width` is 48–280 px (default 160). Only visible when the frame sets `preview.enabled`. |

### 7.1 Metadata entries (`preview.metadata` / `detail.metadata`)

Structured facts render better than markdown tables. Each entry is one aligned
key-value row:

```jsonc
[
  { "label": "Status", "text": "In Progress", "color": "#8250DF" }, // colored dot + tinted text
  { "label": "Assignee", "text": "far-se", "icon": "person" }, // icon before the value
  { "separator": true }, // thin divider
  { "label": "Docs", "text": "tailwindcss.com", "url": "https://..." }, // clickable link
  { "label": "Trend", "sparkline": [12, 14, 11, 9], "text": "−3°" }, // inline mini-chart
  {
    "label": "Poster",
    "text": "Poster Name",
    "image": "https://example.com/poster.webp",
    "width": 180,
  }, // remote image
  {
    "label": "Site",
    "text": "Example",
    "actions": [{ "id": "open", "title": "Open", "icon": "open" }],
  }, // action button
]
```

| Field       | Notes                                                                                                                                                                                                          |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `label`     | Left column, dimmed.                                                                                                                                                                                           |
| `text`      | Right column value. Required unless `sparkline` is present.                                                                                                                                                    |
| `color`     | `#RRGGBB` — tints the value and draws a small dot before it (or tints the sparkline/icon).                                                                                                                     |
| `icon`      | Icon name (§11) shown before the value.                                                                                                                                                                        |
| `image`     | HTTP(S) URL of a raster image (PNG, JPG, or WebP), shown above the value. Invalid URLs or failed loads leave the text visible.                                                                                 |
| `width`     | Image width in px (48–280); used with `image`. Default 132.                                                                                                                                                    |
| `actions`   | Buttons below the value. Same shape and behavior as Ctrl+K actions: `{id, title, icon?, destructive?, confirm?}`. Clicking one sends an `action` message for the selected item (or `id: ""` in a detail view). |
| `url`       | Makes the value a clickable link (opens in the default browser).                                                                                                                                               |
| `sparkline` | Array of ≥2 numbers, drawn as a small axis-free line chart before the value text.                                                                                                                              |
| `separator` | `{"separator": true}` renders a divider row.                                                                                                                                                                   |

---

## 8. View types

### list

Vertical rows: icon + title + subtitle + optional trailing accessory badges. The
default and the right choice for most plugins. Extras: `section` headers to
group rows, `lines` for wrapping subtitles, `progress` for a thin bar under a
row, and colored/iconed accessories (§7).

### grid

Tiles laid out in `grid.columns` columns; each tile shows the icon over the title
and subtitle. Good for emoji/color/image pickers. Arrow keys move in 2-D. Give a
tile `tileColor` to turn it into a filled swatch (labels auto-contrast). Items
with a `section` are grouped under slim headers, exactly like the list view
(keep same-section items adjacent).

### detail

A single full-width, scrollable **markdown document** (`detail.markdown`), plus
an optional `detail.metadata` key-value block (§7.1) underneath. No item list.
Use it for long content, article-style results, confirmations, help, or error
messages. Supports standard markdown: headings, lists, **bold**, `code`, fenced
code blocks, and > quotes. Markdown **links are clickable** and open in the
default browser.

- **Text is selectable** (so users can copy from your answers), fenced code
  blocks grow a hover **copy button**, and **images open in a zoomable
  lightbox** on click.
- **Keyboard**: ↑/↓ scroll the document, PageUp/PageDown jump by a page
  (Home/End stay with the search field's caret).
- **`"wide": true`** widens the launcher window for the document — right for
  long-form answers (the text column is capped at a readable width).
- The query line keeps working: each keystroke still sends you `query`, so a
  "markdown answer" plugin can simply re-render the document per query. For
  chat-style input use `inputMode: "submit"` instead, and stream long answers
  with `detail.append` (§13).

### form

A titled stack of inputs. Submitting sends you `{"type":"submit","values":{...}}`;
**Escape cancels** — exiting the plugin, or sending `{"type":"back"}` when the
frame set `canGoBack: true`. Enter in a single-line field submits.

```jsonc
{
  "type": "render",
  "rev": 0,
  "view": "form",
  "form": {
    "title": "New Issue",
    "submitLabel": "Create", // optional, default "Submit"
    "buttons": [
      // optional — replaces the single CTA
      { "id": "create", "label": "Create" },
      { "id": "delete", "label": "Delete", "destructive": true },
    ],
    "fields": [
      {
        "id": "title",
        "type": "text",
        "label": "Title",
        "placeholder": "Summary…",
        "required": true,
        "description": "Shown under the field",
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
        "options": ["bug", "feature", { "value": "docs", "label": "Docs" }],
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

- Field `type` is one of `text`, `password`, `textarea`, `dropdown`, `checkbox`,
  `number`, `date`, `filepicker`, `folderpicker`, `tags` (unknown types fall
  back to `text`); `value` sets the initial value.
- `values` in the `submit` message maps field ids to strings (text-likes,
  dropdowns, dates as `yyyy-mm-dd`, picked paths), booleans (checkboxes),
  numbers (`number`, null when empty), or string arrays (`tags`).
- **Validation:** `required: true` fields must be non-empty (checked before the
  submit reaches you, with an inline error); `number` bounds (`min`/`max`) are
  enforced the same way. For your own server-side validation, re-render the
  same form with an `"error": "…"` string on the offending field — typed values
  survive because the field set is unchanged.
- `description` renders a dimmed hint under the field.
- `"watch": true` sends you `{"type":"change","id",<values>}` on every change of
  that field — re-render the form to update dependent dropdowns.
- `buttons` replaces the single CTA with several; the `submit` message then
  carries the pressed button's id as `"button"`. `destructive: true` renders it
  in the danger tint.
- After a submit, respond with a new frame (a confirmation `detail`, back to a
  `list`, …) and/or commands (§5.2) — e.g. `toast` + `hide`.
- Re-rendering the _same_ form (same field ids) keeps what the user has typed;
  changing the field set resets it.
- Great for create-flows and for a settings screen that writes `config.json`
  (or better: the `storage` command, §5.2).

### preview pane (split)

Set `"preview": {"enabled": true}` on a `list` or `grid` frame. The launcher
shows the items on the left and, on the right, the **selected item's**
`preview.markdown` and/or `preview.metadata` (§7.1). As the user arrows through
items, the pane updates from each item's `preview`. The window widens to fit and
restores when the plugin exits. (Ignored for `detail` and `form` views.)

---

## 9. Actions & Ctrl+K

- Each item can carry an `actions` array, and the **frame** can carry its own
  `actions` array (frame-level: refresh, create, sign out…). Both appear in the
  **Ctrl+K** palette — the item's first, then the frame's under a divider.
  Frame actions also work on `detail` and `form` views (which have no items).
- **Enter** on an item sends `{"type":"action","id":<item>,"action":"default"}`.
  Treat `"default"` as "the primary thing this item does" (open it, run it,
  create it, drill into it…).
- Picking a Ctrl+K entry sends `{"type":"action","id":<item>,"action":<that id>}`;
  frame-level actions arrive with `"id": ""`.
- **You decide what each action does.** Common patterns: open a URL, copy text,
  toggle state, delete, or navigate your own internal screens.
- After handling an action, respond with a **command** (§5.2 — e.g. `copy` +
  `hide` for "copy and dismiss", or `open` for a link) and/or a new render frame
  (with `rev: 0`) — e.g. a confirmation `detail` frame, or an updated list.

Each action (item- or frame-level) supports:

```jsonc
{
  "id": "delete",
  "title": "Delete issue",
  "icon": "trash",
  "shortcut": "ctrl+shift+d", // fires directly, without opening Ctrl+K
  "destructive": true, // danger tint in the palette
  "confirm": {
    // host-shown "are you sure?" gate
    "title": "Delete this issue?",
    "message": "This cannot be undone.",
    "confirmLabel": "Delete",
  },
}
```

- `shortcut` — lowercase `mod+key` (`ctrl`/`alt`/`shift` + a letter, digit,
  `f1`–`f12`, or `enter`/`space`/`delete`/arrows…). Must include **Ctrl and/or
  Alt** (bare or Shift-only combos would collide with typing and are ignored).
- `confirm` — `true` for a generic prompt, or the object above. The action only
  reaches you after the user accepts. Listing an action with `"id": "default"`
  and a `confirm` also gates Enter on the item.
- `destructive` — pairs naturally with `confirm`; tints the palette row red.

---

## 10. Selection, keyboard, lifecycle notes

- **Selection is owned by the launcher.** You don't set the selected index; you
  react to `select` events if you want to (e.g. lazy-load a preview). Because the
  frame already carries each item's `preview`, handling `select` is usually
  optional.
- **Navigation keys** (arrows) are handled by the launcher and don't reach you.
- **Enter** and **Ctrl+K** reach you as `action` messages; **Tab** reaches you
  as a `tab` message (answer with a `setQuery` command to autocomplete).
- **Escape** exits the whole plugin (you get `close`) — _unless_ the current
  frame set `"canGoBack": true`, in which case you get `{"type":"back"}` and
  should render the previous screen (see §13).
- Keep the event loop responsive. If an operation is slow, first emit a
  `loading:true` frame (echoing the rev), then emit the result frame.

---

## 11. Icons

`icon` accepts a **name** from the list below (case-insensitive; a trailing
`_rounded`/`_outlined`/`_sharp`/`_filled` is ignored). Unknown names fall back to
a generic plugin icon. You can also pass:

- a **hex color** (`#F80`, `#FF8800`, `#AARRGGBB`) — renders a rounded color
  swatch (color pickers, tag colors), or
- a `file://` or `https://` URL to a **raster** image (PNG/JPG — **not SVG**).

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

**Clipboard, opening URLs, hiding the launcher** — use **commands** (§5.2);
don't shell out:

```python
send({"type": "command", "command": "copy", "text": value})
send({"type": "command", "command": "open", "url": "https://example.com"})
send({"type": "command", "command": "hide"})
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
send({"type":"render","rev":rev,"view":"list","loading":True,"items":[],"loadingText":"Searching…"})
results = do_slow_search(text)     # network, etc.
send({"type":"render","rev":rev,"view":"list","items":[to_item(r) for r in results]})
```

(Use `loadingText` for the caption under the spinner — `emptyText` only shows when
the frame is _not_ loading.)
Both frames carry the same `rev`, so if the user kept typing, Tabame drops the
stale result automatically.

### Multi-command plugins (internal state machine)

The launcher gives you one query line, so a plugin with several "commands" should
keep its own screen state:

1. Start on a **root** screen that lists your commands as items (filter them by
   the query text). Render it **without** `canGoBack` so Escape exits.
2. When the user presses Enter on a command (`action:"default"`), switch your
   internal `screen` variable and render that command's view **with
   `"canGoBack": true`**.
3. On sub-screens, treat the query text as that screen's search/input.
4. Escape on a `canGoBack` frame sends you `{"type":"back"}` — reset `screen`
   to root and re-render. No "◀ Back" items needed.

Sketch:

```python
state = {"screen": "root"}

def handle_action(item_id, action):
    if item_id.startswith("cmd:"):
        state["screen"] = item_id[4:]      # drill into a command
        return render(0, "")               # sub-screen frames set canGoBack: true
    # ... item-specific actions (open, copy, create) ...

def handle_back():
    state["screen"] = "root"
    render(0, "")                           # root frame omits canGoBack
```

Pair drill-downs with a `setQuery` command (e.g. `setQuery: ""`) to clear the
sub-screen's search text, and set `placeholder` so the user knows what the
query now filters.

### Streaming answers (chat / LLM plugins)

Combine `inputMode: "submit"` with `detail.append`: render an intro `detail`
frame with `"inputMode": "submit"`, wait for `{"type":"submitQuery"}`, then
stream the answer chunk by chunk **from a worker thread** so the stdin loop
stays responsive:

```python
def on_submit_query(prompt):
    def run():
        send({"type":"render","rev":0,"view":"detail","inputMode":"submit",
              "canGoBack":True,"detail":{"markdown":f"# {prompt}\n\n"}})
        for token in call_llm_stream(prompt):
            send({"type":"render","rev":0,"view":"detail","inputMode":"submit",
                  "canGoBack":True,"detail":{"append":token}})
    threading.Thread(target=run, daemon=True).start()
```

The view keeps itself pinned to the bottom while the user is reading the end of
the document (scrolling up detaches the follow).

### Pagination (`hasMore` / `loadMore`)

For large result sets, render the first page with `"hasMore": true`. When the
user scrolls near the end you get `{"type":"loadMore","rev"}` — answer with the
**full list so far plus the next page** (same `rev`), keeping `hasMore` until
everything is loaded. Pair with `selectId` if you re-order.

### Persistent state & secrets

Use the `storage` command instead of hand-rolled files: `set`/`delete` are
fire-and-forget; `get`/`keys` answer with a `{"type":"storage"}` message —
correlate with `requestId`. Tokens go in with `"secret": true` (Credential
Manager, never a plaintext file):

```python
send({"type":"command","command":"storage","op":"set","key":"token",
      "value":"sk-…","secret":True})
send({"type":"command","command":"storage","op":"get","key":"token",
      "secret":True,"requestId":"tok"})
# later, on stdin: {"type":"storage","requestId":"tok","key":"token","value":"sk-…"}
```

### Finishing work after the launcher closes

For uploads/syncs that outlive the UI: send `background` (grace in seconds),
then `hide`; keep working (a thread is fine) and fire `notify` when done. Join
the worker before exiting on `close`:

```python
send({"type":"command","command":"background","timeout":60})
send({"type":"command","command":"hide"})
# … work …
send({"type":"command","command":"notify","title":"Sync","text":"Done — 42 items."})
```

### Error handling

Never crash on bad input or a failed request. Catch errors and show them:

````python
try:
    ...
except Exception as e:
    send({"type":"render","rev":rev,"view":"detail",
          "detail":{"markdown":f"# Error\n\n```\n{e}\n```"}})
````

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
- [ ] Use **commands** (§5.2) for clipboard / open / hide / toast — don't shell out to `clip`/`start`.
- [ ] Remember the working directory is the **plugin folder** (put `config.json` there).
- [ ] Need libraries? Tabame auto-installs them on first run — **Python:** `"pip"` / `requirements.txt`; **Node/Bun:** a `package.json` (§4.1). Lazy-load heavy deps so a failed install degrades gracefully.
- [ ] Icons must be a name from §11, a `#RRGGBB` color, or a `file://`/`https://` **raster** image.
- [ ] Prefer `metadata` rows (§7.1) over markdown tables for structured facts.
- [ ] Keep items sharing a `section` adjacent — headers appear on value _changes_ (lists **and** grids).
- [ ] Set `canGoBack: true` on sub-screens (and handle `back`); leave it off your root screen.
- [ ] Never set `canGoBack` on a frame you can't navigate away from — Escape would be trapped.
- [ ] Action `shortcut`s must include Ctrl and/or Alt; bare/Shift-only combos are ignored.
- [ ] Gate destructive actions with `"confirm"` (and mark them `"destructive": true`).
- [ ] Streaming: do slow/streamed work on a **thread**; every `detail.append` frame uses `rev: 0`.
- [ ] `loadMore` answers must contain the full list (old pages + new), not just the new page.
- [ ] Secrets go through `storage` with `"secret": true` — never into `config.json` you ship.
- [ ] Send `background` **before** `hide` when work must outlive the launcher, and join workers on `close`.
- [ ] Develop with `"dev": true` (hot reload + debug console); set it back to `false` before sharing.

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
{
  "name": "My Plugin",
  "keyword": "mp",
  "runtime": "python",
  "entry": "main.py",
  "icon": "star"
}
```

### 15.2 Node.js / Bun template

```js
"use strict";

function send(frame) {
  process.stdout.write(JSON.stringify(frame) + "\n");
}
function log(...a) {
  console.error(...a);
} // debug -> stderr

function render(rev, text) {
  const words = text.split(/\s+/).filter(Boolean);
  const list = words.length ? words : ["type", "something"];
  const items = list.map((w, i) => ({
    id: `w${i}`,
    title: w,
    subtitle: `${w.length} chars`,
    icon: "tag",
    accessories: [{ text: String(w.length) }],
    actions: [
      { id: "default", title: "Open", icon: "open" },
      { id: "copy", title: "Copy", icon: "copy" },
    ],
    preview: { markdown: `## ${w}\n\nLength: **${w.length}**` },
  }));
  send({
    type: "render",
    rev,
    view: "list",
    preview: { enabled: true },
    emptyText: "Nothing to show",
    items,
  });
}

function handleAction(id, action) {
  send({
    type: "render",
    rev: 0,
    view: "detail",
    detail: {
      markdown: `# Action\n\n- item: \`${id}\`\n- action: \`${action}\``,
    },
  });
}

let buf = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buf += chunk;
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      continue;
    }
    if (msg.type === "close") process.exit(0);
    else if (msg.type === "init" || msg.type === "query")
      render(msg.rev || 0, msg.text != null ? msg.text : msg.query || "");
    else if (msg.type === "action")
      handleAction(msg.id || "", msg.action || "default");
  }
});
process.stdin.on("end", () => process.exit(0));
```

`plugin.json`

```json
{
  "name": "My Plugin",
  "keyword": "mp",
  "runtime": "node",
  "entry": "main.js",
  "icon": "star"
}
```

---

## 16. Ready-to-use prompt

Paste this document into your chatbot, then add a request like:

> Using the Tabame Launcher Plugin spec above, write a **<Python|Node>** plugin.
> Keyword: `<keyword>`. It should: `<describe what it does — data source, what each
item shows, what Enter does, what Ctrl+K actions to offer, and whether to use a
list / grid / detail / preview pane>`. Read any secrets from `config.json` in the
> plugin folder. Follow every rule in §14 and give me both `plugin.json` and the
> script, plus the exact folder to drop them in.

The chatbot should return a complete, ready-to-install plugin.
