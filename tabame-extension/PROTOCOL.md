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
heartbeat inside Chromium's 30-second MV3 service-worker activity window.

## Requests

Launcher to extension:

```json
{
  "type": "request",
  "id": "uuid",
  "method": "tabs.list",
  "params": {}
}
```

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
| `bridge.ping` | — | Connector and browser version |
| `tabs.list` | — | All tabs, including optional group metadata |
| `tabs.audible` | — | Audible tabs, group metadata, and current candidate |
| `tabs.activate` | `tabId` | Updated tab |
| `tabs.close` | `tabId` | Completion |
| `tabs.mute` | `tabId`, optional `muted` | Updated tab |
| `tabs.pin` | `tabId`, optional `pinned` | Updated tab |
| `tabs.reload` | `tabId` | Completion |
| `tabs.duplicate` | `tabId` | New tab |
| `tabs.open` | `url`, optional `active` | New tab |
| `codex.usage` | — | Remaining/used percentage and timestamp |

`tabs.open` accepts only HTTP and HTTPS URLs. There is intentionally no generic
JavaScript-evaluation method.

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
