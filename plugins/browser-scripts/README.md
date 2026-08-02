# Browser Scripts — AI-friendly Tabame plugin example

This folder is a small, runnable reference for an AI tool generating a
browser-capable Tabame launcher plugin. It demonstrates the same Codex Usage
workflow as `plugins\browser`, but keeps the browser bridge adapter and the
site-specific script together in one easy-to-copy plugin.

## What it demonstrates

- `browserBridge` commands are sent to Tabame as launcher protocol commands;
  the plugin does not open its own WebSocket.
- `javascript.execute` runs plugin-owned JavaScript in a connected HTTP(S) tab.
- `input` passes JSON from the plugin process into the page script.
- `tabs.open` + `tabs.list` + `tabs.close` give the plugin ownership of a
  temporary-tab lifecycle.
- Slow work starts with a loading render frame and query revisions are echoed.
- Every browser request is validated, and temporary tabs are closed in `finally`.

The plugin includes two examples:

- **Inspect active tab** — the smallest `javascript.execute` call, using the
  current active tab and returning title, URL, selection, and a text sample.
- **Codex usage** — opens ChatGPT analytics in an inactive temporary tab, waits
  for the dynamic page, extracts the allowance with page JavaScript, validates
  the result, and closes the temporary tab.

## Install and try it

1. Copy this folder to `%localappdata%\Tabame\plugins\browser-scripts\`.
2. Make sure Node.js 18+ is on `PATH`.
3. Load `tabame-extension` as an unpacked Chromium extension. Enable
   **Allow User Scripts** on its details page when Chromium shows that option.
4. Open **Launcher Plugins** and enable **Persistent browser connector**.
5. Reopen the launcher and type **`browser-scripts`**.
6. Open **Connection & pairing** and pair the extension if it is not connected.

The connector is owned by Tabame and its pairing token is per Windows account.
Do not commit or publish the token displayed by the connection screen.

## How to adapt this example

For a new browser plugin, an AI tool can generally:

1. Copy `plugin.json` and choose a unique `name`, `keyword`, and `id`.
2. Keep the `BrowserBridge` adapter and the newline-delimited stdin/stdout
   event loop.
3. Replace `CODEX_USAGE_SCRIPT` with a page-specific function that returns
   JSON using `return`.
4. Use `input` for selectors, limits, or other data supplied by the plugin.
5. Choose the target tab: omit `tabId` for the active tab, or use `tabs.open`
   and `tabs.list` for a temporary tab.
6. Validate `execution.result` in Node before rendering it.
7. Close plugin-owned temporary tabs in a `finally` block.

The essential request sent by the adapter looks like this:

```json
{
  "type": "command",
  "command": "browserBridge",
  "op": "request",
  "requestId": "page-title-1",
  "method": "javascript.execute",
  "params": {
    "tabId": 42,
    "code": "return { title: document.title, selector: input.selector };",
    "input": { "selector": "main" }
  },
  "timeoutMs": 30000
}
```

The reply arrives on stdin as a `browserBridge` message with the same
`requestId`; successful data is in `result`. Only use page scripts with sites
and accounts the user trusts. See `plugins\TABAME_PLUGIN_SKILL.md` and
`tabame-extension\chrome\PROTOCOL.md` for the complete contract.
