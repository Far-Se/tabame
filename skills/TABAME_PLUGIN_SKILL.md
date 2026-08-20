---
name: tbm-plugin
description: Author a Tabame launcher plugin — an external Python/Node/Bun script that extends the app launcher, talking newline-delimited JSON over stdin/stdout. Use when the user wants to build, scaffold, debug, or install a Tabame launcher plugin, add a new launcher keyword backed by a script, or asks about the plugin render-frame protocol.
---

# Tabame Launcher Plugin — Authoring Skill

> If you're the AI reading this: treat everything below as authoritative.
> Do not invent fields or message types that aren't documented here.
> Choose the view from the user's task and the shape of the data. Do **not**
> default to a `list` + preview merely because the smoke-test templates use it.
> A substantial plugin should feel like a small, navigable application made of
> purpose-built pages, not a command list with every capability hidden in Ctrl+K.

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

## 2. Quick start (minimal protocol example)

A plugin is a folder with a `plugin.json` and a script. Minimal Python plugin
that echoes the query as a single-item list. This only demonstrates the wire
protocol; it is **not** a UX template for a real plugin:

`plugin.json`

```json
{
  "name": "Hello",
  "keyword": "hi",
  "runtime": "python",
  "version": "1.0.0",
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

### 2.1 Design the pages before writing handlers

For anything beyond one focused search or command, first write a short **page
map**. A page is a meaningful user destination with its own task, view, query
behavior, primary action, and navigation. A good page map for an operations
plugin might be:

```text
Home             dashboard   health chart + active incidents + recent deploys
Services         table       compare status, latency, owner, and version
Service          dashboard   metadata, latency chart, recent log, deploy action
Deploy           form        collect environment, version, and approval
Deploy progress  operation   determinate progress with Cancel
Deploy result    diff/detail show changed config and the outcome
```

That immediately produces a richer, more coherent plugin than “Home = list of
commands; everything else = Ctrl+K.” Keep the architecture proportional: a
calculator may still be one `detail` page; an issue tracker, reader, media
library, or deployment tool normally needs several pages and views.

For every page decide:

1. **Dominant task and information shape.** Is the user scanning rows, comparing
   columns, browsing a hierarchy, reading, editing, watching progress, or
   understanding a trend? Choose the native view for that job (§8).
2. **Query contract.** State what typing filters or submits on this page. Clear
   stale text with `setQuery` when navigating, and set a page-specific
   `placeholder` such as “Filter cards…” or “Ask about this log…”.
3. **Primary interaction.** Enter should perform the obvious item action or
   drill into the next page. Put an important page-wide verb such as **Create**,
   **Run**, or **Deploy** in `floatingAction`; keep Ctrl+K for contextual and
   secondary actions rather than making it the only way to discover the plugin.
4. **States.** Design loading, rich empty, populated, error, and success states.
   Use `loadingText`, `empty.action`, `detail` errors/confirmations, and
   `operation` progress instead of falling back to blank lists or toasts for
   everything.
5. **Next destinations.** Decide where Enter, submit, cancel, back, breadcrumbs,
   and successful actions go. The plugin owns this state machine and must render
   every destination.

Use the `page` object on real destinations:

- Give each conceptual page a stable id such as `issues:home`,
  `issues:board:ENG`, or `issues:item:ENG-42`. Do not include the current query,
  selection, loading status, or other transient state in the id.
- Use `history: "push"` for a forward drill-down, `"replace"` for a redirect or
  same-depth replacement, and `"none"` when a frame should not alter history.
  The root is normally the first stable page and does not need manual back.
- List **ancestors only** in `breadcrumbs`; Tabame adds the current page title.
  Breadcrumb clicks send `navigate`. Handle `navigate.targetPageId` by restoring
  your matching route/state and rendering it.
- Handle `back` by rendering `toPageId` when supplied, or your previous route.
  `canGoBack: true` is still useful for a manual sub-screen that is not represented
  in page history. Never set it on a screen from which your plugin cannot return.
- Keep `preserveState: true` when revisiting a page should restore selection,
  scroll position, or form values. Set it false only for an intentional reset,
  such as a fresh create form.
- Give independently interactive surfaces stable `elementId`s. Dashboard panel
  events also include `panelId`; dispatch with `pageId` + `panelId` + `elementId`
  instead of guessing from item ids.

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
| `version`     | **yes**  | —             | Current version, use "1.0.0" for start.                                                                                                          |
| `entry`       | **yes**  | —             | Script filename, relative to the plugin folder, e.g. `"main.py"` / `"main.js"`.                                                                  |
| `id`          | **yes**  | folder name   | Stable identifier.                                                                                                                               |
| `name`        | **yes**  | folder name   | Human title shown in the launcher's discovery hint.                                                                                              |
| `description` | **yes**  | `""`          | One-line description.                                                                                                                            |
| `icon`        | **yes**  | `"extension"` | Icon for the discovery hint (see §11).                                                                                                           |
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
  "version": "1.0.0",
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

| Message         | When                                                                                                             | Fields                                                                                                                                                                                                                    |
| --------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `init`          | Once, right after your process starts                                                                            | `query`: initial text after the keyword; `protocol`: int protocol version (currently 13); `theme`: `{accent, text, background, dark}` — hex colors + dark-mode flag; `locale`: e.g. `"en-US"`                             |
| `query`         | On every keystroke while the keyword is active (not sent in `inputMode: "submit"`)                               | `text`: current text after the keyword; `rev`: integer generation counter                                                                                                                                                 |
| `submitQuery`   | **Enter** while the frame declared `inputMode: "submit"` — the whole query line at once (chat-style input)       | `text`, `rev`                                                                                                                                                                                                             |
| `select`        | When the highlighted item changes                                                                                | `id`: the selected item's id; `rev`                                                                                                                                                                                       |
| `action`        | On **Enter** (fires `action` = `"default"`), a **Ctrl+K** pick, an action **shortcut**, or the empty state's CTA | `id`: the item's id (`""` for frame-level actions and the empty-state button); `action`: `"default"` or the chosen action's id; optional `ids`: bulk-selected IDs; optional `parameters`: values collected for the action |
| `toggle`        | A tree disclosure was activated                                                                                  | `id`, `expanded`, `rev` — render the expanded/collapsed children yourself                                                                                                                                                 |
| `chartSelect`   | A point on an interactive chart was clicked                                                                      | `seriesId`, `index`, `value`, `rev`                                                                                                                                                                                       |
| `chartRangeSelect` | A range was dragged on a chart with `selectableRange:true`                                                     | `startIndex`, `endIndex`, `rev`, plus the common event scope                                                                                                                                                               |
| `toolbarChange` | A filter, scope, sort, or view control changed                                                                    | `id`, optional `value`, `values`, or `direction`, `rev`, plus the common event scope                                                                                                                                        |
| `tableSort`     | A sortable table header was clicked                                                                               | `columnId`, `direction` (`asc` or `desc`), `rev`, plus the common event scope                                                                                                                                               |
| `edit`          | An editable list or table value was committed                                                                     | item `id`, `field` (`title`, `subtitle`, or cell id), `value`, `rev`, plus the common event scope                                                                                                                            |
| `drop`          | Files were dropped on a declared page drop zone                                                                   | drop-zone `id`, absolute `paths`, `rev`, plus the common event scope                                                                                                                                                        |
| `cancel`        | The user cancelled a declared operation                                                                          | `id`, `rev`                                                                                                                                                                                                               |
| `oauth`         | Reply to an `oauth` command                                                                                      | `requestId` (echoed), plus provider callback query fields such as `code`, `state`, or `error`                                                                                                                             |
| `submit`        | When the user submits a **form** view                                                                            | `values`: `{fieldId: value}` (strings, booleans, numbers, string lists — see §8); `button`: the pressed `form.buttons` id (absent for the default CTA)                                                                    |
| `change`        | A form field with `"watch": true` changed                                                                        | `id`: the field's id; `values`: all current field values                                                                                                                                                                  |
| `validate`      | A form field with `validate:true` settled after its debounce                                                      | `id`, all current `values`, `rev`, plus scope; answer by re-rendering with `validating`, `valid`, or `error`                                                                                                                 |
| `loadMore`      | The user scrolled near the end of a frame with `hasMore: true`                                                   | `rev` — answer with a longer item list                                                                                                                                                                                    |
| `storage`       | Reply to a `storage` command with `op` `get`/`keys`                                                              | `requestId` (echoed), and `key`+`value` or `keys`                                                                                                                                                                         |
| `clipboard`     | Reply to a `clipboardRead` command                                                                               | `requestId` (echoed), `text`                                                                                                                                                                                              |
| `browserBridge` | Reply/event from the optional app-owned Chromium bridge                                                          | Replies echo `requestId` with `ok` and `result`/`error`; events carry `event` and `data`                                                                                                                                  |
| `back`          | **Escape/back button** when `canGoBack: true` or page history has a previous entry                              | `rev`, optional `fromPageId`/`toPageId`, plus scope — render the previous screen                                                                                                                                           |
| `navigate`      | A page breadcrumb was activated                                                                                  | `targetPageId`, `rev`, plus the common event scope                                                                                                                                                                        |
| `kanbanMove`    | A kanban card was dropped in a column                                                                            | `id`, `columnId`, `index`, `rev`, plus the common event scope                                                                                                                                                              |
| `calendarNavigate` | Calendar date or mode navigation was activated                                                                | `date` (`yyyy-mm-dd`), `mode` (`month` or `agenda`), `rev`, plus the common event scope                                                                                                                                    |
| `tab`           | **Tab** pressed                                                                                                  | `id`: the highlighted item's id (`""` if none); `rev` — typically answered with a `setQuery` command                                                                                                                      |
| `close`         | When the plugin is being shut down                                                                               | —                                                                                                                                                                                                                         |

Example stdin lines:

```json
{"type":"init","query":"rome","protocol":13,"theme":{"accent":"#63A0EA","text":"#E8E8E8","background":"#1B1D23","dark":true},"locale":"en-US"}
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
- Interactive v10 events may also carry `pageId`, `panelId`, and `elementId`.
  These identify the exact page, dashboard panel, and frame element that
  produced the event. They are additive; v8 plugins may ignore them.

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

| Command            | Fields                                                   | Effect                                                                                                                                                                                                                                                                                                                                                                                               |
| ------------------ | -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `copy`             | `text`                                                   | Puts `text` on the clipboard and shows a "Copied to clipboard" toast.                                                                                                                                                                                                                                                                                                                                |
| `paste`            | `text`                                                   | Puts `text` on the clipboard, **hides the launcher**, re-activates the previously focused window, and sends **Ctrl+V** — i.e. types the text where the user was working.                                                                                                                                                                                                                             |
| `open`             | `url` (or `path`)                                        | Opens a URL in the default browser, or a file/folder with its default handler.                                                                                                                                                                                                                                                                                                                       |
| `hide`             | —                                                        | Hides the launcher.                                                                                                                                                                                                                                                                                                                                                                                  |
| `toast`            | `text`, `style`?, `progress`?                            | Shows a transient chip over the results area. `style`: `"success"` (default), `"error"`, `"info"`, or `"progress"`. A `progress` toast **stays pinned** (with a spinner, or a determinate ring when `progress` 0–1 is given) until a later `toast` replaces it — re-send to update it in place.                                                                                                      |
| `setQuery`         | `text`                                                   | Rewrites the search field's **post-keyword** text (the keyword stays). Use it to autocomplete after a `tab` message or to drill down while keeping the query bar in sync. Triggers a normal `query` event back to you.                                                                                                                                                                               |
| `clipboardRead`    | `requestId`?                                             | Asks for the clipboard's text; the host answers with a `{"type":"clipboard","requestId","text"}` message.                                                                                                                                                                                                                                                                                            |
| `clipboardHistory` | `op`, `requestId`?, `offset`?, `limit`?, `query`?, `id`? | Reads Tabame's saved history. `op: "list"` replies with compact entries and `hasMore`; `"entry"` returns a bounded 12k preview; `"copy"` restores the complete original. Replies use `{"type":"clipboardHistory", ...}`.                                                                                                                                                                             |
| `notify`           | `title`?, `text`                                         | Fires a **native Windows notification** (works even while finishing in the background — see `background`). `title` defaults to the plugin name.                                                                                                                                                                                                                                                      |
| `storage`          | `op`, `key`?, `value`?, `secret`?, `requestId`?          | Per-plugin persistent key-value store. `op` is `"set"`, `"get"`, `"delete"`, or `"keys"`. Plain values live in `.tabame-store.json` in the plugin folder; `"secret": true` routes the value to the **Windows Credential Manager** instead (strings only; not listed by `keys`). `get`/`keys` reply with a `{"type":"storage"}` message echoing `requestId`.                                          |
| `background`       | `timeout`?                                               | Requests shutdown grace: after the launcher hides / the user leaves, the process is **not killed** for up to `timeout` seconds (default 30, max 300) so it can finish work. While detached it can still use `storage` and `notify`, but frames and UI commands are dropped. Send it **before** `hide`.                                                                                               |
| `oauth`            | `authorizationUrl`, `requestId`?, `timeout`?             | Starts a host-owned ephemeral loopback callback listener and opens the authorization URL. `authorizationUrl` **must** include the literal `{redirectUri}` placeholder; Tabame URL-encodes and substitutes it. It replies with `{"type":"oauth",...}`. Exchange the returned code yourself and store tokens using `storage` with `secret: true`.                                                      |
| `browserBridge`    | `op`, `requestId`, `method`?, `params`?, `timeoutMs`?    | Uses Tabame's optional persistent Chromium connector. `op:"status"` returns enabled/running/connected state plus pairing metadata. `op:"request"` forwards an allowlisted browser method—including generic `javascript.execute`—and replies with `{"type":"browserBridge","requestId","ok","result"}` (or `error`). Connection and tab-change events arrive as unsolicited `browserBridge` messages. |

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
- `hide` and `paste` close the launcher and send `close`. For long-running work,
  send `background` first; the process then remains alive during the grace
  period and can still send `notify`. Without `background`, expect shutdown.
- A `copy` followed by `hide` skips the toast — the launcher is gone before it
  would render.

#### Plugin-owned browser JavaScript

Browser-capable plugins can keep site-specific tasks in the plugin instead of
adding them to Tabame or the companion extension. Send a `browserBridge`
request with method `javascript.execute`:

```json
{
  "type": "command",
  "command": "browserBridge",
  "op": "request",
  "requestId": "page-title-1",
  "method": "javascript.execute",
  "params": {
    "tabId": 42,
    "code": "return { title: document.title, url: location.href, selector: input.selector };",
    "input": { "selector": "main" }
  },
  "timeoutMs": 30000
}
```

The reply arrives on stdin as
`{"type":"browserBridge","requestId":"page-title-1","ok":true,"result":...}`.

- `code` is required, may use `await`, and returns data with `return` (128 KiB
  maximum).
- `input` is any JSON value available to the script as `input`. Returned data
  must be JSON-serializable (192 KiB maximum).
- `tabId` defaults to the active tab. Use `tabs.open`, `tabs.list`, and
  `tabs.close` to let the plugin own temporary-tab lifecycle.
- `world` is `"USER_SCRIPT"` by default; request `"MAIN"` only when access to
  page JavaScript globals is necessary.
- `allFrames:true` or `frameIds:[...]` targets frames. The top frame is the
  default. `injectImmediately:true` skips the normal `document_idle` preference.
- Only HTTP(S) tabs are scriptable. Chromium's **Allow User Scripts** toggle
  must be enabled for the companion extension.

This capability can read and change authenticated pages in the connected
profile. Only install browser-capable plugins you trust. See
`tabame-extension/PROTOCOL.md` and `plugins/browser/main.js` for the complete
contract and a working temporary-tab data fetcher.

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
  "view": "list", // list|grid|detail|chat|form|table|tree|timeline|chart|operation|dashboard|kanban|diff|log|calendar|gallery
  "page": { // optional stable identity + host state restoration
    "id": "issues",
    "title": "Issues",
    "history": "push", // none|push|replace
    "preserveState": true,
    "breadcrumbs": [{"id":"root","label":"Home"}],
  },
  "elementId": "results", // source id included in events
  "loading": false, // bool, or {"progress": 0.4} for a determinate spinner
  "loadingText": "Searching…", // caption shown under the spinner while loading
  "emptyText": "No results", // shown when items is empty and not loading
  "empty": { "icon": "cloud", "title": "No issues", "hint": "Try a filter" }, // richer empty state
  "placeholder": "Search issues…", // search-field hint while this frame is shown
  "grid": { "columns": 4, "aspectRatio": 1.0 }, // only used by "grid" view
  "detail": { "markdown": "# Hi", "metadata": [/* see §7.1 */] }, // only used by "detail" view
  "form": {/* see §8, form */}, // only used by "form" view
  "preview": { "enabled": true, "wide": false, "resizable": true, "initialWidth": 360 },
  "toolbar": {
    "filters": [{"id":"status","label":"Status","multiple":true,"values":["open"],"options":["open","closed"]}],
    "scope": {"value":"all","options":["all","mine"]},
    "sort": {"value":"updated","direction":"desc","options":["updated","name"]},
    "view": {"value":"list","options":[{"value":"list","label":"List","icon":"list"},{"value":"grid","label":"Grid","icon":"grid"}]}
  },
  "banners": [{"id":"offline","style":"warning","title":"Offline","message":"Showing cached data","dismissible":true,"actions":[]}],
  "dropZone": {"id":"attachments","label":"Drop attachments","extensions":["png","pdf"],"multiple":true},
  "canGoBack": false, // manually enables back; page history can also enable it
  "actions": [/* frame-level Ctrl+K actions, see §9 */],
  "floatingAction": { "id": "run", "title": "Run", "icon": "play" }, // bottom-right button; an array is also accepted
  "selectId": "item-3", // move the highlight to this item
  "hasMore": false, // more items exist -> loadMore events
  "inputMode": "submit", // Enter submits the query (chat-style)
  "selection": { "enabled": true, "max": 20 }, // Ctrl+Space or row checkbox; actions receive ids
  "columns": [{ "id": "status", "label": "Status", "align": "end", "sortable":true, "editable":true }],
  "table": {"resizable":true,"stickyHeader":true,"columnVisibility":true,"sortColumn":"status","sortDirection":"asc"},
  "chart": {
    "title": "Latency", "type":"area", "showAxes":true, "showGrid":true,
    "showLegend":true, "tooltips":true, "selectableRange":true,
    "xLabels":["Mon","Tue"], "xTitle":"Day", "yTitle":"ms",
    "series": [
      { "id": "p95", "label": "p95", "values": [24, 31], "color": "#63A0EA" },
    ],
  },
  "operation": {
    "id": "deploy-42",
    "title": "Deploying",
    "progress": 0.4,
    "cancellable": true,
  },
  "dashboard": {
    "layout": "stack",
    "panels": [/* normal view payloads, see below */],
  },
  "kanban": {"columns":[{"id":"todo","title":"To do","color":"#63A0EA","limit":5}]},
  "diff": {"mode":"unified","oldLabel":"Before","newLabel":"After","text":"-old\n+new"},
  "log": {"follow":true,"wrap":false,"lines":[{"id":"1","level":"info","text":"Ready"}]},
  "calendar": {"mode":"month","date":"2026-08-01","weekStart":"monday","days":30},
  "gallery": {"columns":4,"aspectRatio":1.15,"fit":"cover","showLabels":true},
  "items": [/* see §7 */],
}
```

| Field              | Type           | Notes                                                                                                                                                                                                                                                                            |
| ------------------ | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `view`             | string         | `"list"` (rows), `"grid"` (tiles), `"detail"` (full-width markdown), `"chat"` (message feed), `"form"` (inputs), `"table"`, `"tree"`, `"timeline"`, `"chart"`, `"operation"`, `"dashboard"`, `"kanban"`, `"diff"`, `"log"`, `"calendar"`, or `"gallery"`. Default `list`.                       |
| `page`             | object         | Optional `{id,title?,history?:"none"|"push"|"replace",preserveState?,breadcrumbs?}`. Stable ids let Tabame restore selection, scroll, and form values. Breadcrumb clicks send `navigate`.                                                                                       |
| `elementId`        | string         | Stable id for this frame inside its page. Returned as `elementId` on scoped events. Dashboard events additionally carry their panel's `panelId`.                                                                                                                               |
| `selection`        | bool/object    | Enable bulk selection. `Enter` and `Ctrl+Space` toggle the highlighted item; list/table/tree/timeline also expose a pointer checkbox. `{max}` caps the selection count. Selected IDs arrive in `action.ids`.                                                                     |
| `columns`          | array          | `table` columns: `{id,label,width?,minWidth?,maxWidth?,align?,sortable?,editable?,visible?}`. Items provide matching string values in `cells`.                                                                                                                                  |
| `table`            | object         | Table behavior: `{resizable?,stickyHeader?,columnVisibility?,sortColumn?,sortDirection?:"asc"|"desc"}`. Sorting sends `tableSort`; plugins remain responsible for ordering the next frame.                                                                                 |
| `chart`            | object         | Data plus `{type?:"line"|"area"|"bar",showAxes?,showGrid?,showLegend?,tooltips?,selectableRange?,xLabels?,xTitle?,yTitle?,minY?,maxY?,series:[...]}`. Interactions send `chartSelect` or `chartRangeSelect`.                                                      |
| `toolbar`          | object         | Standard `filters` array plus optional `scope`, `sort`, and `view` controls. Each control has stable `id`, `label?`, `options`, and `value` or multi `values`; changes send `toolbarChange`.                                                                                       |
| `banners`/`banner` | object/array   | In-context callouts `{id?,style?:"info"|"success"|"warning"|"error",title?,message?,icon?,dismissible?,actions?}`. Actions use the normal action event.                                                                                                                |
| `dropZone`         | object         | Page file target `{id,label?,hint?,extensions?,multiple?,maxFiles?}`. A completed OS drop sends `drop` with accepted absolute paths.                                                                                                                                             |
| `operation`        | object         | A visible long-running operation `{id,title,detail?,progress?:0..1,cancellable?:bool}`. A cancellable operation sends `cancel`.                                                                                                                                                  |
| `dashboard`        | object         | Only for `view: "dashboard"`. `{layout:"stack" \| "tabs",panels:[...]}` composes independently scrollable normal view payloads. Each panel has `id`, `title`, optional `height` (96–640), plus `view` and that view's fields.                                                                                                                |
| `kanban`           | object         | `{columns:[{id,title,color?,limit?}]}`. Items use `column` (or `section`) to choose a column. Dropping a card sends `kanbanMove`.                                                                                                                                                |
| `diff`             | object/string  | Unified or split source comparison. `{mode:"unified"|"split",oldLabel?,newLabel?,text?}` or `lines:[{type,text,oldLine?,newLine?}]`.                                                                                                                                         |
| `log`              | object/array   | Structured stream `{follow?,wrap?,lines:[string|{id?,timestamp?,level?,source?,text}]}`. Levels: trace/debug/info/warn/error/success.                                                                                                                                             |
| `calendar`         | object         | Calendar options: `{mode?:"month"|"agenda",date?:"yyyy-mm-dd",weekStart?:"monday"|"sunday",days?:1..90}`. Header navigation sends `calendarNavigate`.                                                                                                                     |
| `gallery`          | object         | Media grid options: `{columns?:2..8,aspectRatio?:0.5..2.5,fit?:"cover"|"contain",showLabels?:bool}`.                                                                                                                                                                         |
| `loading`          | bool or object | When truthy and `items` empty, a spinner is shown. `{"progress":0..1}` is determinate; `{"style":"skeleton","count":6}` renders shape-matched placeholders.                                                                                                              |
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
| `preview.wide`     | bool           | Controls whether an enabled split preview widens the launcher window. Default true. Set false on the frame's `preview` object to keep the normal window width; item-level `preview` objects only provide content and do not control window sizing.                               |
| `preview.resizable` | bool          | Adds a draggable divider. Optional `initialWidth`, `minWidth`, and `maxWidth` control and constrain the preview width.                                                                                                                                                            |
| `canGoBack`        | bool           | Manually makes **Escape send `{"type":"back"}`** instead of exiting. Page history can independently enable native back. Use this for non-page sub-screens, leave it false on the root, and handle the event. Default false.                                                                                                      |
| `actions`          | array          | **Frame-level actions** shown in the Ctrl+K palette regardless of the highlighted item (refresh, create, sign out…), after the item's own actions. Same shape as item actions (§9), fired with an empty `id`.                                                                    |
| `floatingAction`   | object/array   | One or more prominent bottom-right buttons using the normal action shape (§9). Clicking dispatches a frame-level `action` with `id:""`; bulk-selected item IDs are included in `action.ids`.                                                                                |
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
  "cells": {"status":"Healthy", "latency":"42 ms"}, // table columns
  "editable": ["title", "status"], // true enables title/subtitle/all cells; commit sends edit
  "depth": 1, "expanded": true, // tree indentation/disclosure state
  "timestamp": "10:42", // timeline leading label
  "column": "review", // kanban column id
  "start": "2026-08-04T09:30:00", // calendar; `date` is accepted as an all-day alias
  "end": "2026-08-04T10:15:00", // calendar, optional
  "allDay": false, "color": "#8B5CF6", "location": "Studio A",
  "media": { // gallery; a plain source string is shorthand for an image
    "url": "https://example.com/poster.webp",
    "type": "image", // image|video|audio|file
    "thumbnail": "https://example.com/thumb.webp",
    "duration": "02:18", "size": 2480000, "width": 1920, "height": 1080,
  },
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
| `icon`        | string             | Icon name (§11), a `#RRGGBB` color (renders a swatch), a `data:image/...` URI (up to 2 MB), or a `file://` / `https://` raster or SVG image.                                                                                                                                                         |
| `section`     | string             | List view: items are grouped under a slim header whenever this value differs from the previous item's. Keep items with the same section adjacent.                                                                                                                                                    |
| `lines`       | int 1–3            | List view: how many lines the subtitle may wrap to. Default 1.                                                                                                                                                                                                                                       |
| `progress`    | number 0–1         | List view: renders a thin progress bar under the row (downloads, timers).                                                                                                                                                                                                                            |
| `tileColor`   | string             | Grid view: fills the tile with this `#RRGGBB` color; label flips black/white for contrast. Perfect for color pickers.                                                                                                                                                                                |
| `cells`       | object             | Table view values keyed by `columns[].id`. Keep `title` useful as the row's identity even when the same fact also appears in a cell.                                                                                                                                                                  |
| `editable`    | bool/array         | Enables double-click inline editing. `true` enables title, subtitle, and all cells; an array names only allowed fields. A committed value sends `edit`; re-render the authoritative item value.                                                                                                      |
| `depth`/`expanded` | int/bool       | Tree view indentation (0–12) and whether this node currently shows its children. The plugin updates and re-renders these after `toggle`.                                                                                                                                                              |
| `timestamp`   | string             | Timeline view's leading time or status label, such as `10:42`, `Yesterday`, or `Failed`.                                                                                                                                                                                                              |
| `column`      | string             | Kanban destination column id. `section` is accepted as a concise fallback.                                                                                                                                                                                                                             |
| `start`/`date` | ISO-8601 string   | Calendar item start. Use `start` for timed events; `date` is an all-day-friendly alias. May instead be nested inside a `calendar` object.                                                                                                                                                           |
| `end`/`allDay`/`color`/`location` | mixed | Optional calendar event details. `end` must not precede `start`; `color` is a hex tint. These may also be nested inside `calendar`.                                                                                                                                                                  |
| `media`       | object/string      | Gallery media. Object: `{url,type?,thumbnail?,duration?,size?,width?,height?}`; type is image/video/audio/file. Audio/video tiles expose host playback, seek, buffering, and error controls. Sources support HTTP(S), `file://`, and `data:image/...` up to 2 MB.                                      |
| `accessories` | array              | Trailing badges. Each is a bare string or `{"text", "color"?, "icon"?}` — `color` tints the chip, `icon` is a §11 name.                                                                                                                                                                              |
| `actions`     | array              | Entries for the item's **Ctrl+K** menu. Each: `{id, title, icon?, shortcut?, destructive?, confirm?}` — see §9 for the last three.                                                                                                                                                                   |
| `preview`     | object/string/null | Shown in the preview pane while this item is selected: `{"markdown"?, "image": {"url", "width"?}, "metadata"?, "diff"?}` or a plain markdown string. `diff` accepts the same `{text|lines, mode?, oldLabel?, newLabel?}` payload as the `diff` view. `image` is an HTTP(S) raster displayed to the right of markdown; `width` is 48–280 px (default 160). Only visible when the frame sets `preview.enabled`. |

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
| `height`    | Image height in px (48–280); used with `image`. Default 176.                                                                                                                                                   |
| `actions`   | Buttons below the value. Same shape and behavior as Ctrl+K actions: `{id, title, icon?, destructive?, confirm?}`. Clicking one sends an `action` message for the selected item (or `id: ""` in a detail view). |
| `url`       | Makes the value a clickable link (opens in the default browser).                                                                                                                                               |
| `sparkline` | Array of ≥2 numbers, drawn as a small axis-free line chart before the value text.                                                                                                                              |
| `separator` | `{"separator": true}` renders a divider row.                                                                                                                                                                   |

---

## 8. View types

### Choose by information shape, not by template familiarity

`list` is one tool, not the plugin shell. Pick the view that makes the page's
main question easiest to answer:

| User's question or task | Best starting view | Verbal example |
| ----------------------- | ------------------ | -------------- |
| “Which short result do I want?” | `list` | Commands, contacts, search matches, or notifications with one dominant label. |
| “Which visual/spatial choice do I want?” | `grid` | Theme, color, emoji, application, or preset picker. |
| “How do these records compare across fields?” | `table` | Services by status/latency/owner, packages by version/license/size, expenses by date/vendor/amount. |
| “Where is this in a hierarchy?” | `tree` | Files, nested categories, bookmarks, organization units, or dependency nodes. |
| “What happened, and in what order?” | `timeline` | Incident history, order tracking, Git activity, audit trail, or project milestones. |
| “How is a metric changing?” | `chart` | CPU/latency history, spending by month, habit streak, download rate, or build duration. |
| “What is the current state of several related things?” | `dashboard` | A project home with summary, chart, recent activity, and open work; a service home with health, deploys, and logs. |
| “What stage is each work item in?” | `kanban` | Issues, editorial pipeline, sales leads, personal tasks, or release checklist. |
| “What does this one thing say?” | `detail` | Article, issue, package README, error explanation, report, help, or action result. |
| “What values must I provide or edit?” | `form` | Create issue, configure account, rename columns, export options, or deployment parameters. |
| “What are we saying back and forth?” | `chat` | Assistant, team thread, support conversation, or iterative query session. |
| “How far has the long-running work progressed?” | `operation` | Deploy, download, indexing, migration, sync, or export with optional cancel. |
| “What changed?” | `diff` | Config edit, generated patch, version comparison, migration preview, or before/after text. |
| “What is the live diagnostic stream?” | `log` | Build output, server tail, test runner, device events, or command execution. |
| “What happens on a date?” | `calendar` | Meetings, deadlines, releases, shifts, reminders, or content schedule. |
| “Which media asset do I want?” | `gallery` | Photos, screenshots, album art, clips, recordings, or design assets. |

The split `preview` pane is a **modifier for list/grid**, not a universal second
page. Use it when a quick glance helps the user decide among adjacent items and
the preview is cheap to provide. Navigate to a proper `detail` page when the
content is long, deserves a readable width, has its own actions/history, or is
a destination the user may return to. Do not duplicate the row subtitle in a
mostly empty preview just to fill the right side.

### Build workflows, not a collection of disconnected views

Views become valuable when they form an intentional page flow. Examples:

- **Issue tracker:** a `dashboard` home summarizes counts and activity; Enter on
  the work panel opens a `kanban` board; Enter on a card opens `detail`; Edit
  opens a `form`; Activity opens a `timeline`. Bulk close/move uses `selection`
  on a `table` or list, not dozens of repeated Ctrl+K operations.
- **Deployment tool:** a `table` compares services; a service `dashboard`
  combines metadata, a latency `chart`, recent `log` lines, and a visible Deploy
  `floatingAction`; Deploy opens a `form`, then an `operation`, then a `diff` or
  `detail` result. Cancel is the operation's native event.
- **Media library:** start with `gallery`, use sections for albums and
  `hasMore` for paging; Enter opens a wide `detail` page with metadata; Edit
  opens a `form`; a bulk Export floating action consumes `action.ids`.
- **Knowledge/files plugin:** browse folders as a `tree`, compare search results
  in a `table`, read the chosen document in `detail`, and show revisions in a
  `timeline` leading to a `diff` page.
- **Planner:** use `calendar` as the natural home, an agenda `timeline` for the
  selected day, a `form` to create/edit events, and a compact `dashboard` for
  overdue work plus a completion chart.

Do not add views just to reach a quota. A view earns its page when it improves a
real task. Conversely, do not flatten a naturally rich workflow into rows just
because rows are easier to generate.

### Use the rest of the UI deliberately

- Make **Enter** the obvious primary item verb. Use item `actions` for
  contextual alternatives and frame `actions` for page-wide utilities such as
  Refresh, Settings, Import, and Sign out.
- Use `floatingAction` for one or two important, discoverable page verbs. A
  Create button should not exist only inside Ctrl+K. Use an action's compact
  `parameters` for a small one-shot choice; use a full `form` page when fields
  need explanation, validation, dependencies, or editing.
- Use `selection` when users reasonably act on several items. Name bulk actions
  for the group (“Archive 6”), read `action.ids`, and keep destructive actions
  confirmed.
- Use `accessories` for terse scan facts (status, age, owner), `section` for
  meaningful groups, `progress` for row-local progress, and metadata for aligned
  facts. Do not turn subtitles into unscannable database dumps.
- Use a `dashboard` only for a true overview or multi-surface workspace. Prefer
  2–5 purposeful panels. `stack` reads like a report; `tabs` fit peer surfaces
  that do not need simultaneous comparison. Give every panel a stable `id`, a
  useful `title`, an intentional `height`, and its own `elementId` when it emits
  events.
- Preserve context after refreshes with stable item ids and `selectId`. Use
  `hasMore` rather than rendering an enormous collection, and use the rich
  `empty` state with a recovery or create action when zero items is actionable.
- Show work in the surface where it matters: `loading` for a page fetch,
  per-item `progress` for several concurrent jobs, `operation` for one prominent
  cancellable job, `log` for diagnostic output, and a final `detail`/`diff` for
  the durable result.

### list

Vertical rows: icon + title + subtitle + optional trailing accessory badges. The
right choice for quick scanning when every item has one dominant identity.
Extras: `section` headers to group rows, `lines` for wrapping subtitles,
`progress` for a thin bar under a row, and colored/iconed accessories (§7).

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

### chat

A scrollable conversation feed. Each item is a message: `title` is the author,
`subtitle` is the body, `icon` may be an avatar URL, and `accessories` can show
a timestamp. `images` may contain HTTP(S) image-attachment URLs. Use `inputMode: "submit"` for a chat composer; Enter sends the
whole message as `submitQuery`. New messages follow the bottom while the user
is already reading the latest message.

### form

A titled stack of inputs. Submitting sends you `{"type":"submit","values":{...}}`;
**Escape cancels** — exiting the plugin, or sending `{"type":"back"}` when the
frame enabled manual back or page history has a previous entry. Enter in a
single-line field submits.

```jsonc
{
  "type": "render",
  "rev": 0,
  "view": "form",
  "form": {
    "title": "New Issue",
    "error": "Please review the highlighted fields", // optional form-level error
    "sections": [
      {"id":"main","title":"Issue","description":"Required details"},
      {"id":"advanced","title":"Advanced","collapsible":true},
    ],
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
        "type": "combobox",
        "label": "Team",
        "value": "eng",
        "watch": true,
        "optionsLoading": false,
        "allowCustom": false,
        "section": "main",
        "visibleWhen": {"field":"urgent","equals":true},
        "enabledWhen": {"field":"title","truthy":true},
        "options": ["eng", { "value": "ops", "label": "Operations" }],
      },
      { "id": "urgent", "type": "checkbox", "label": "Urgent", "value": true },
      { "id": "starts", "type": "datetime", "label": "Starts" },
      { "id": "accent", "type": "color", "label": "Color", "value": "#63A0EA" },
      { "id": "volume", "type": "slider", "label": "Volume", "min": 0, "max": 100, "step": 5 },
      { "id": "mode", "type": "radio", "label": "Mode", "options": ["fast", "safe"] },
      { "id": "targets", "type": "multiselect", "label": "Targets", "options": ["web", "desktop"] },
      { "id": "app", "type": "apppicker", "label": "Application" },
      { "id": "hotkey", "type": "shortcut", "label": "Shortcut" },
      { "id": "config", "type": "json", "label": "Configuration", "rows": 8 },
      { "id": "files", "type": "dropzone", "label": "Files", "multiple": true, "extensions": ["json"] },
    ],
  },
}
```

- Field `type` is one of `text`, `password`, `textarea`, `dropdown`, `combobox`, `checkbox`,
  `number`, `date`, `time`, `datetime`, `filepicker`, `folderpicker`, `dropzone`,
  `tags`, `multiselect`, `radio`, `slider`, `color`, `apppicker`, `shortcut`,
  `code`, or `json` (unknown types fall back to `text`); `value` sets the initial value.
- `values` in the `submit` message maps field ids to strings (text-likes,
  dropdowns, ISO-like date/time values, colors, app launch targets, shortcuts,
  code/JSON, picked paths), booleans (checkboxes), numbers (`number`/`slider`,
  null when empty), or string arrays (`tags`, `multiselect`, multi-file/dropzone).
- **Validation:** `required: true` fields must be non-empty (checked before the
  submit reaches you, with an inline error); `number` bounds (`min`/`max`) are
  enforced the same way. For your own server-side validation, re-render the
  same form with an `"error": "…"` string on the offending field — typed values
  survive because the field set is unchanged.
- `description` renders a dimmed hint under the field.
- `sections` groups fields by their `section` id; a section may be
  `collapsible:true`. `visibleWhen` and `enabledWhen` support
  `{field,equals?,notEquals?,in?,truthy?}` conditions evaluated against current
  values.
- `combobox` filters its options as the user types. Pair it with `watch:true`
  and re-rendered `options` for async search; `optionsLoading:true` shows a
  spinner and `allowCustom:true` accepts a value outside the option list.
- Text validation supports `minLength`, `maxLength`, `pattern`, and an optional
  `validationMessage`, in addition to `required` and number `min`/`max`.
- `validate:true` debounces by `validationDebounceMs` (default 400) and sends a
  `validate` event. Re-render with `validating:true` while checking, then
  `valid:true` or an `error`; JSON fields are also parsed locally before submit.
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

### table

Dense, aligned records for **comparison**. Declare frame `columns` as
`{id,label,width?,align?}` and put each record's remaining values in item
`cells`. Column ids `title` and `subtitle` use those item fields automatically.
Use `align:"end"` for numbers and keep the identity column first. Tables are
better than accessories when users must compare the same 3–6 facts across many
records; they are worse than a list when most cells would be blank or verbose.
They support normal selection, item actions, bulk `selection`, and paging.

### tree

A hierarchy represented as the **currently visible flattened nodes**. Each item
declares `depth` and `expanded`; a disclosure sends `toggle` with the requested
state. Your plugin loads/inserts or removes descendants and re-renders the
complete visible tree. Use it when parentage itself matters (folders,
categories, dependencies), not as decorative indentation for unrelated groups.
Enter should normally open the node's page; disclosure should only expand or
collapse it.

### timeline

Chronological or causal events with a leading `timestamp`, icon, title,
subtitle, and accessories. Sort deliberately (newest-first for an activity feed,
oldest-first for a process story) and keep the direction consistent. A timeline
explains sequence better than a date accessory on ordinary rows: incident phases,
shipment checkpoints, commits, approvals, and audit events are natural fits.

### chart

Compact quantitative comparison. `chart.series` contains stable series ids and
index-aligned numeric `values`; clicking a point sends `chartSelect`, which can
drill into a filtered `table`, `timeline`, or `detail` page. Use charts for
shape, trend, and outliers, and pair them with a title and a nearby factual panel
when exact numbers matter. A chart should answer a named question (“Did p95
latency regress?”), not merely decorate a dashboard.

### operation

A prominent long-running job with `id`, `title`, optional `detail`, determinate
`progress` (or indeterminate when omitted), and `cancellable`. Use the standalone
`operation` view when the job is the page's whole purpose. The same `operation`
field can accompany another view as a progress bar above its content—for example,
a table that remains browsable during sync. Update with `rev:0`; handle `cancel`
and render a durable success/error `detail`, `diff`, or refreshed destination
when the job finishes.

### dashboard

A composition page whose panels reuse normal view payloads. Use `layout:"stack"`
for a scrollable report where panels should be read together, or `"tabs"` for
peer workspaces that deserve the same area. Each panel has `id`, `title`, optional
`height` (96–640), `view`, and that view's normal fields. Good combinations are:

- status `detail` + trend `chart` + incident `timeline`;
- summary `chart` + comparable records `table` + recent `log`;
- media `gallery` + queue `list` + active `operation`.

Panels are independently scrollable and interactive. Events include the outer
`pageId`, the panel's `panelId`, and its child `elementId`; use that scope to
dispatch actions, selection, submits, toggles, chart points, and pagination.
Avoid a dashboard of six tiny lists. If one panel becomes the user's main task,
Enter or a visible action should open it as a full page in its native view.

### preview pane (split)

Set `"preview": {"enabled": true}` on a `list` or `grid` frame. The launcher
shows the items on the left and, on the right, the **selected item's**
`preview.markdown`, `preview.metadata` (§7.1), and/or `preview.diff`. As the user arrows through
items, the pane updates from each item's `preview`. The window widens to fit and
restores when the plugin exits. Set `"preview": {"enabled": true, "wide": false}`
on the **frame** to keep the normal launcher width. A `wide` field inside an
item's `preview` is ignored because item previews contain content only. (The
frame preview is ignored for `detail` and `form` views.)

### kanban

Horizontal workflow columns with draggable cards. Declare columns in
`kanban.columns`; cards are normal items with a `column` id (`section` is an
accepted fallback). A drop sends
`{"type":"kanbanMove","id","columnId","index","rev",...scope}`. Re-render
the complete board after applying the move.

### diff

Selectable source comparison in `unified` or `split` mode. `diff.text` accepts
a unified-diff string. For precise line numbers use
`diff.lines:[{type:"add"|"remove"|"context"|"header",text,oldLine?,newLine?}]`.
The same payload may be nested under `item.preview.diff` to render the built-in
diff widget in a list or grid preview pane.

### log

Dense selectable output for builds, services, and diagnostics. `log.lines` may
contain strings or `{id?,timestamp?,level?,source?,text}` objects. With
`follow:true` the view stays at the end while the user is already following it;
scrolling upward detaches. `wrap:false` keeps each line compact.

### calendar

Month grid or chronological agenda. Configure it with
`calendar:{mode,date,weekStart,days}` and give each item a `start` (or `date`),
plus optional `end`, `allDay`, `color`, and `location`. The header's previous,
next, today, and month/agenda controls send
`{"type":"calendarNavigate","date":"yyyy-mm-dd","mode":"month"|"agenda","rev",...scope}`;
update your date/mode state and re-render the complete frame.

### gallery

Responsive media tiles for image, video, audio, and file results. Configure the
grid with `gallery:{columns,aspectRatio,fit,showLabels}`. Each item supplies a
`media` object; non-image types normally provide a `thumbnail`. Gallery supports
normal item actions, keyboard selection, bulk selection, and `hasMore` paging.

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
- `floatingAction` renders one action object (or an array) as persistent
  bottom-right buttons. They use the same confirmation, parameter, shortcut,
  and bulk-selection dispatch path, but do not need the Ctrl+K palette.

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
  "parameters": [
    {
      "id": "environment",
      "type": "dropdown",
      "label": "Environment",
      "required": true,
      "options": ["staging", "production"],
    },
  ], // compact host form; values return in action.parameters
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
- **Escape** exits the whole plugin (you get `close`) unless the current frame
  set `"canGoBack": true` **or** page history has a previous entry. In either
  back-capable case you get `{"type":"back"}` (with page ids when available)
  and should render the previous screen (see §13).
- Keep the event loop responsive. If an operation is slow, first emit a
  `loading:true` frame (echoing the rev), then emit the result frame.

---

## 11. Icons

`icon` accepts a **name** from the list below (case-insensitive; a trailing
`_rounded`/`_outlined`/`_sharp`/`_filled` is ignored). Unknown names fall back to
a generic plugin icon. You can also pass:

- a **hex color** (`#F80`, `#FF8800`, `#AARRGGBB`) — renders a rounded color
  swatch (color pickers, tag colors), or
- a `data:image/...` URI (base64 or percent-encoded, up to 2 MB), or
- a `file://` or `https://` URL to a raster image (PNG/JPG/WebP) or SVG.

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

### Multi-page plugins (route/state machine)

The launcher supplies the chrome and events; the plugin still owns routes and
data state. Do not make the root a list of verbs unless the product truly is a
small command dispatcher. A rich plugin usually starts on its natural home
(`dashboard`, `calendar`, `gallery`, `kanban`, etc.) and navigates to other
purpose-built pages.

1. Give every route a stable `page.id` and a render function. Keep the current
   route/entity in plugin state.
2. Forward navigation renders the destination with `page.history:"push"`.
   Clear or rewrite the query with `setQuery` if its meaning changes.
3. Handle `back` by rendering `toPageId` when present; otherwise pop your own
   route stack. Handle breadcrumb `navigate` by rendering `targetPageId`.
4. Use each destination's native view. For example: home dashboard → projects
   table → project kanban → task detail → edit form.
5. Keep page ids and item ids stable so host-restored scroll, selection, and form
   state remain useful after a re-render.

Sketch:

```python
state = {"page_id": "ops:home", "route_stack": ["ops:home"]}
routes = {
    "ops:home": render_dashboard,
    "ops:services": render_services_table,
    "ops:deploy": render_deploy_form,
}

def go(page_id, *, forward=False, clear_query=True):
    if page_id not in routes:
        page_id = "ops:home"
    if forward:
        state["route_stack"].append(page_id)
    state["page_id"] = page_id
    if clear_query:
        send({"type":"command", "command":"setQuery", "text":""})
    routes[page_id](0)  # emitted frame declares matching page.id/history

def handle_back(msg):
    target = msg.get("toPageId")
    if target in state["route_stack"]:
        state["route_stack"] = state["route_stack"][:state["route_stack"].index(target) + 1]
    elif not target and len(state["route_stack"]) > 1:
        state["route_stack"].pop()
        target = state["route_stack"][-1]
    go(target or "ops:home", clear_query=True)

def handle_navigate(msg):
    target = msg.get("targetPageId", "ops:home")
    if target in state["route_stack"]:
        state["route_stack"] = state["route_stack"][:state["route_stack"].index(target) + 1]
    go(target, clear_query=True)
```

Use `canGoBack:true` for temporary manual sub-screens that are outside the page
history model. Page-history destinations already expose native back chrome; in
both cases, never render a back-capable dead end.

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

If an action may outlive the UI (for example, an upload, sync, or video
conversion), declare background work before hiding the launcher. Tabame sends
`close` but keeps the Python/Node/Bun process supervised for the requested grace
period, so a worker can finish. Send `notify` when it completes; this becomes a
native desktop notification even though the launcher is closed. Use a non-daemon
worker or join it before exiting on `close`:

```python
send({"type":"command","command":"background","timeout":300})
send({"type":"command","command":"hide"})
# … work …
send({"type":"command","command":"notify","title":"Conversion","text":"Finished successfully."})
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
- [ ] For a multi-workflow plugin, write a page map and choose each page's view
      from its real task/data shape — do not ship the smoke-test list + preview
      as the product architecture.
- [ ] Give conceptual destinations stable `page.id`s; handle `back.toPageId` and
      `navigate.targetPageId`; use `push`/`replace`/`none` intentionally.
- [ ] Keep primary navigation and primary page verbs discoverable through Enter,
      page chrome, and `floatingAction`; do not bury the whole product in Ctrl+K.
- [ ] Use **commands** (§5.2) for clipboard / open / hide / toast — don't shell out to `clip`/`start`.
- [ ] Remember the working directory is the **plugin folder** (put `config.json` there).
- [ ] Need libraries? Tabame auto-installs them on first run — **Python:** `"pip"` / `requirements.txt`; **Node/Bun:** a `package.json` (§4.1). Lazy-load heavy deps so a failed install degrades gracefully.
- [ ] Icons must be a name from §11, a `#RRGGBB` color, a `data:image/...` URI (up to 2 MB), or a `file://`/`https://` raster or SVG image.
- [ ] Prefer `metadata` rows (§7.1) over markdown tables for structured facts.
- [ ] Keep items sharing a `section` adjacent — headers appear on value _changes_ (lists **and** grids).
- [ ] Dispatch dashboard interactions with `pageId`/`panelId`/`elementId` scope.
- [ ] Use `canGoBack: true` only for manual sub-screens outside page history (and handle `back`); leave it off your root screen.
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

The templates below are protocol smoke tests: they demonstrate a correct event
loop, stable ids, and action dispatch. They intentionally use the smallest
possible UI. **Do not preserve their list + preview screen as the architecture
of a real multi-workflow plugin.** Start from the page map in §2.1 and replace
`render()` with route-specific render functions using the view guidance in §8.

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
> Keyword: `<keyword>`. It should: `<describe the users, data source, major tasks,
> and desired workflows>`. Before coding, provide a compact page map: each page's
> stable id, purpose, native view, what the query does, Enter/primary action, and
> destinations. Choose from **all** documented views according to §8; do not
> default to list + preview or hide primary navigation in Ctrl+K. Use proper page
> history, breadcrumbs, visible floating actions, forms, loading/empty/error
> states, and scoped dashboard panels where they improve the workflow—without
> adding irrelevant views merely for variety. Read secrets through `storage`
> with `secret:true`. Follow every rule in §14 and give me `plugin.json`, the
> complete script, install path, and a short walkthrough of the finished pages.

The chatbot should return a complete, ready-to-install plugin.
