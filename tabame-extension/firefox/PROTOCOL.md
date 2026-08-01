# Tabame browser bridge protocol

Protocol version: **1**

Transport: WebSocket at `ws://127.0.0.1:17373/tabame`. Every message is one
JSON object. Tabame's optional app-owned browser bridge owns the server; the
extension is the reconnecting client. The server remains available independently
of launcher-plugin lifetimes while the setting is enabled.

## Session

The extension's first message must be:

```json
{
  "type": "hello",
  "protocol": 1,
  "token": "<pairing token>",
  "extensionVersion": "0.1.0",
  "userAgent": "..."
}
```

The server checks the WebSocket `Origin`, protocol version, and token before
replying:

```json
{ "type": "welcome", "protocol": 1, "serverVersion": "0.1.0" }
```

Either peer may then exchange `ping` / `pong` frames. The extension sends a
heartbeat from Firefox's MV3 background event page and uses an alarm to
reconnect after suspension.

## Requests

Launcher to extension:

```json
{
  "type": "request",
  "id": "uuid",
  "method": "tabs.list",
  "params": {},
  "timeoutMs": 30000
}
```

`timeoutMs` is optional and clamped to 1-60 seconds.

Successful response:

```json
{
  "type": "response",
  "id": "uuid",
  "ok": true,
  "result": {}
}
```

Failed response:

```json
{
  "type": "response",
  "id": "uuid",
  "ok": false,
  "error": "Human-readable message"
}
```

### Allowlisted methods

| Method | Parameters | Result |
|---|---|---|
| `bridge.ping` | - | Connector and browser version |
| `tabs.list` | - | All tabs, including optional group metadata |
| `tabs.audible` | - | Audible tabs, group metadata, and current candidate |
| `tabs.activate` | `tabId` | Updated tab |
| `tabs.close` | `tabId` | Completion |
| `tabs.mute` | `tabId`, optional `muted` | Updated tab |
| `tabs.pin` | `tabId`, optional `pinned` | Updated tab |
| `tabs.reload` | `tabId` | Completion |
| `tabs.duplicate` | `tabId` | New tab |
| `tabs.open` | `url`, optional `active` | New tab |
| `javascript.execute` | `code`, optional `tabId`, `input`, `world`, `allFrames`/`frameIds`, `injectImmediately` | Runs plugin-supplied JavaScript in an HTTP(S) tab and returns its JSON-serializable result |

`tabs.open` accepts only HTTP and HTTPS URLs.

### Plugin-owned JavaScript

`javascript.execute` is the generic building block for browser-backed plugins.
The extension does not contain site-specific fetchers. A plugin can open or
select a tab with the tab methods above, send its own task script, consume the
result, and close temporary tabs itself.

```json
{
  "type": "request",
  "id": "uuid",
  "method": "javascript.execute",
  "params": {
    "tabId": 42,
    "code": "return { title: document.title, url: location.href, selector: input.selector };",
    "input": { "selector": "main" },
    "world": "USER_SCRIPT"
  }
}
```

- `code` is required, may use `await`, and returns a value with `return`.
  It is capped at 128 KiB.
- `input` is any JSON value exposed to the script as the local `input`
  variable. Results must be JSON-serializable and are capped at 192 KiB.
- `tabId` defaults to the active tab in the last-focused window.
- `world` is `USER_SCRIPT` by default or `MAIN` when page JavaScript globals
  are required.
- `allFrames: true` or `frameIds: [...]` targets frames; they are mutually
  exclusive. The top frame is the default.
- `injectImmediately: true` skips the normal `document_idle` preference.
- The result object contains `tabId`, `pageUrl`, `world`, the first-frame
  `result`, all per-frame `results`, and `executedAt`.

The connector only injects into HTTP(S) pages. Firefox exposes the
`userScripts` API after its optional permission is granted from the extension
popup or Add-ons Manager. Arbitrary browser-page code is a powerful capability,
so only install Tabame plugins you trust.

## Events

The extension debounces browser tab changes and pushes:

```json
{
  "type": "event",
  "event": "tabs.changed",
  "data": {
    "reason": "updated",
    "at": "2026-07-29T12:00:00.000Z"
  }
}
```

Event reasons are `activated`, `created`, `removed`, and `updated`. Events are
hints; consumers should request a fresh snapshot rather than treating them as a
complete event log.



