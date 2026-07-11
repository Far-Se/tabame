---
name: tbm-plugin
description: Author a Tabame launcher plugin — an external Python/Node/Bun script that extends the app launcher, talking newline-delimited JSON over stdin/stdout. Use when the user wants to build, scaffold, debug, or install a Tabame launcher plugin, add a new launcher keyword backed by a script, or asks about the plugin render-frame protocol.
---

# Tabame Launcher Plugin Authoring

Tabame's launcher is extensible with **plugins**: standalone scripts (Python, Node.js, or Bun) that Tabame runs as a long-lived child process when the user types the plugin's **keyword**. Communication is **newline-delimited JSON over stdin/stdout** — no SDK, no dependencies.

- **Tabame → script (stdin):** UI events (`init`, `query`, `select`, `action`, `close`).
- **Script → Tabame (stdout):** **render frames** — JSON objects that fully describe what the launcher shows right now.

The script is the source of truth for the UI: every time you want the launcher to display something different, you print a new render frame.

## Authoritative references (read these)

The complete, authoritative protocol spec lives in the repo. **Read it before writing non-trivial plugins** — do not invent fields or message types not documented there:

- **Full spec:** [plugins/TABAME_PLUGIN_SKILL.md](../../../plugins/TABAME_PLUGIN_SKILL.md) — every message type, render-frame field, item field, view type, icon name, and pattern.
- **Working examples** to copy from:
  - `plugins/echo/` — Python demo exercising list/grid/detail/preview + actions.
  - `plugins/linear/` — Node.js plugin with an HTTP API and `config.json` secrets.
  - `plugins/caniuse/` — Node.js plugin with fetched data and detail views.

When a detail isn't covered below, consult the full spec rather than guessing.

## Workflow for building a plugin

1. **Clarify the shape** (only if unspecified): keyword, runtime, data source, what each item shows, what **Enter** does, what **Ctrl+K** actions to offer, and which view (list / grid / detail / preview pane).
2. **Pick a runtime** the user has on `PATH`: `python`, `node` (18+), or `bun`. Tabame bundles none.
3. **Scaffold the folder** with `plugin.json` + entry script. Start from the matching template in §15 of the full spec, or copy the closest `plugins/` plugin.
4. **Implement the event loop** (see contract below).
5. **Install & test:** drop the folder in `%localappdata%\Tabame\plugins\<id>\`, reopen the launcher (it rescans on every open — no restart), and type the keyword.

## `plugin.json` (manifest)

```json
{
  "keyword": "weather", // required — what the user types; short & unique
  "runtime": "python", // required — "python" | "node" | "bun" (on PATH)
  "entry": "main.py", // required — script filename in the plugin folder
  "id": "weather", // optional — defaults to folder name
  "name": "Weather", // optional — shown in the discovery hint
  "description": "", // optional
  "icon": "cloud", // optional — icon name (see spec §11)
  "args": [], // optional — CLI args inserted BEFORE entry
  "enabled": true, // optional — defaults to true; set false (or toggle
  //   from the Launcher Plugins manager) to hide the
  //   plugin without deleting it
  "dev": false // optional — true enables dev mode: hot-restart on file
  //   save + a live debug console (stderr, dropped frames,
  //   commands) under the plugin view. Turn off before sharing.
}
```

Launch is effectively `<runtime> <args...> <entry>`, started **without a shell**, with the **working directory set to the plugin folder** (so `config.json`/assets resolve relatively). Activation: the query **equals the keyword** or **starts with `keyword + " "`**; the keyword prefix is stripped before your script sees the text.

## The protocol contract (essentials)

**One JSON object per line, both directions. Flush stdout after every frame.**

Messages you receive on **stdin**:

| Message  | When                                                | Key fields                         |
| -------- | --------------------------------------------------- | ---------------------------------- |
| `init`   | Once at startup                                     | `query`, `protocol` (2), `theme` (`{accent,text,background,dark}` hex + flag), `locale` |
| `query`  | Every keystroke                                     | `text`, `rev` (generation counter) |
| `select` | Highlighted item changed                            | `id`, `rev`                        |
| `action` | **Enter** (`action:"default"`) or a **Ctrl+K** pick | `id`, `action` (no `rev`)          |
| `submit` | User submits a `form` view                          | `values` (`{fieldId: value}`)      |
| `back`   | Escape on a frame with `canGoBack: true`            | `rev` — render the previous screen |
| `tab`    | Tab pressed                                          | `id` of highlighted item, `rev` — answer with `setQuery` |
| `close`  | Shutting down                                       | —                                  |

Minimal render frame you print to **stdout**:

```json
{
  "type": "render",
  "rev": 1,
  "view": "list",
  "items": [
    { "id": "1", "title": "Hello", "subtitle": "world", "icon": "star" }
  ]
}
```

Full frame/item fields are documented in spec §6–§8: views `list`/`grid`/`detail`/`form`; frame `loading` (bool or `{progress}`), `emptyText`, `empty` (`{icon,title,hint}`), `placeholder`, `canGoBack`, `grid`, `detail` (`{markdown, metadata, wide}` — a markdown-only document view with no list; ↑/↓/PageUp/PageDown scroll it, `wide: true` widens the window), `form`, `preview`; item `accessories` (tintable via `color`, own `icon`), `actions`, `preview` (`{markdown, metadata}`), `section` headers, `lines` (subtitle wrap), `progress` bar, grid `tileColor`, and `**bold**`/`` `code` `` spans in title/subtitle. `metadata` entries (spec §7.1) are aligned key-value rows supporting `color` dots, `icon`, clickable `url`, `sparkline` arrays, and `{"separator":true}` dividers. Icons accept a §11 name, a `#RRGGBB` color swatch, or a raster URL.

You can also print **commands** — side effects the host executes for you (spec §5.2). No `rev`, fire-and-forget; combine by printing several lines (e.g. `copy` then `hide`):

```json
{"type":"command","command":"copy","text":"..."}   // clipboard + "Copied" toast
{"type":"command","command":"paste","text":"..."}  // clipboard + hide + Ctrl+V into the previous window
{"type":"command","command":"open","url":"..."}    // URL or file/folder path
{"type":"command","command":"hide"}                 // hide the launcher (your process gets `close`)
{"type":"command","command":"toast","text":"..."}  // transient confirmation chip
{"type":"command","command":"setQuery","text":"..."} // rewrite post-keyword search text (autocomplete)
```

## Non-negotiable rules (get these right)

- **stdout is protocol messages only** (render frames and commands). Any other stdout line is treated as a diagnostic log. Send all debug output to **stderr**.
- **Echo `rev`** on frames responding to a `query`/`select`; use **`rev: 0`** for unsolicited pushes (action results, async/background refreshes). Tabame **drops frames with a stale `rev`**, so a slow response to "rom" can't overwrite fresh results for "rome".
- **Flush stdout** after every frame; **one JSON object per line**, no embedded newlines.
- **Every item needs a stable, unique `id`** — it's echoed back in `select`/`action`.
- **Exit on `close` and on stdin EOF.** After `close`, ~2s grace then the process is killed.
- **Read stdin line by line**; never block for all input.
- **Escape exits the whole plugin** unless the frame set `"canGoBack": true` — then you get `{"type":"back"}` and should render the previous screen. Keep your own `screen` state; leave `canGoBack` off the root screen (and never set it on a screen you can't leave, or Escape is trapped).
- **Slow work:** emit a `loading:true` frame (echoing the rev) first, then the result frame.
- **Never crash on bad input** — wrap handlers in try/except and render the error as a `detail` frame.
- **Icons** must be a name from spec §11 (case-insensitive), a `#RRGGBB` color swatch, or a `file://`/`https://` **raster** (PNG/JPG, no SVG).
- On Windows, Tabame sets `PYTHONIOENCODING=utf-8` / `PYTHONUTF8=1` for Python; Node/Bun are UTF-8 already.

## Doing real work

The plugin is an ordinary process: HTTP (`requests`/`urllib`, or global `fetch` in Node 18+/Bun), filesystem, spawning tools. Read secrets from a `config.json` in the plugin folder (the CWD) or env vars — see `plugins/linear/config.example.json`. To open a URL, copy/paste text, hide the launcher, or show a toast, print a **command** (see above) — don't shell out to `cmd /c start`/`clip`. Markdown links in `detail`/`preview` are clickable and open in the default browser; metadata entries can carry a `url` for the same effect.

## Deliverables

When done, hand the user both `plugin.json` and the script, the exact install path (`%localappdata%\Tabame\plugins\<id>\`), and the reminder to reopen the launcher to load it.
