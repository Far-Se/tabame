---
name: tbm-browser-connector-extension
description: Author, extend, or debug the Tabame Connector browser extension: a Manifest V3 Chromium extension that pairs with Tabame, maintains an authenticated loopback WebSocket, exposes the fixed browser-bridge method allowlist, executes trusted plugin-supplied JavaScript in HTTP(S) tabs, and pushes debounced tab-change events. Use for connector transport, pairing UI, tab operations, MV3 reconnection, userScripts execution, security, or Chromium/Firefox packaging. Do not use this skill to design a normal QuickLaunch plugin UI.
---

# Tabame Connector Browser Extension — Authoring Skill

> Treat the protocol sections in this document as authoritative. Do not invent
> message types, methods, event names, protocol versions, ports, paths, worlds,
> or size limits. The connector is intentionally generic: site-specific
> selectors, fetchers, scraping, and automation belong to the Tabame plugin that
> calls `javascript.execute`, not to the extension.

## 1. When to use this skill

Use this skill when the user wants to:

- create or repair the Tabame Connector Chromium extension;
- implement pairing-token storage or the extension popup;
- maintain the persistent WebSocket connection to Tabame;
- add or debug one of the existing allowlisted tab methods;
- implement trusted plugin-supplied JavaScript execution;
- handle Manifest V3 service-worker suspension and reconnection;
- push browser tab-change hints to Tabame;
- package or adapt the browser-specific Firefox version;
- audit connector security, validation, or error handling.

Do **not** use this skill for an ordinary Tabame QuickLaunch plugin. A launcher
plugin is a separate Python/Node/Bun process and communicates with Tabame through
newline-delimited JSON. The browser extension communicates with Tabame's
persistent browser-bridge server through WebSocket JSON messages.

Do not put these in the connector extension:

- site-specific API clients;
- selectors for YouTube, Gmail, Spotify, or another site;
- per-site login flows;
- launcher render frames or plugin UI state;
- business rules that belong to one plugin.

Those belong to the trusted launcher plugin. The extension should remain a
small browser capability layer.

---

## 2. Architecture and ownership

```text
Trusted QuickLaunch plugin
        │
        │ browserBridge command through Tabame
        ▼
Tabame persistent browser-bridge server
ws://127.0.0.1:17373/tabame
        ▲
        │ authenticated WebSocket JSON
        │
Tabame Connector extension
        │
        ▼
Current Chromium browser profile and HTTP(S) pages
```

Ownership rules:

1. **Tabame owns the WebSocket server.**
2. **The extension is the reconnecting WebSocket client.**
3. The server exists independently of individual launcher-plugin processes while
   Tabame's **Persistent browser connector** setting is enabled.
4. Disabling that setting closes the loopback server and disconnects the
   extension.
5. The extension stores the pairing token in extension-local storage.
6. Tabame generates the token locally in
   `%localappdata%\Tabame\browser-bridge.json`.
7. All locally installed Tabame browser plugins use the same connector token and
   port. There is no per-plugin browser credential in protocol version 1.

The server binds to `127.0.0.1`, not to a LAN interface. Chromium may still ask
for local-network permission on first connection; the target remains the local
machine.

---

## 3. Fixed protocol constants

```text
Protocol version: 1
WebSocket URL:    ws://127.0.0.1:17373/tabame
Transport unit:   one JSON object per WebSocket message
```

These values are protocol, not configuration defaults. Do not change them unless
Tabame's server protocol is changed at the same time and the user explicitly
requests a versioned migration.

The browser-extension transport is **not** newline-delimited JSON. Serialize one
JSON object into each WebSocket message.

---

## 4. Non-negotiable design rules

A correct connector extension must:

1. send `hello` as its first WebSocket message;
2. authenticate with the locally paired token;
3. wait for a valid `welcome` before treating the session as connected;
4. preserve request IDs exactly in responses;
5. expose only the documented method allowlist;
6. return a human-readable error for failed requests;
7. validate inputs before calling browser APIs;
8. accept only HTTP(S) URLs for `tabs.open`;
9. execute plugin code only in HTTP(S) tabs;
10. default arbitrary code to the `USER_SCRIPT` world;
11. use `MAIN` only when the caller explicitly requests it;
12. enforce code and result size limits;
13. treat tab-change events as invalidation hints, not as a complete log;
14. reconnect after the server disappears or the MV3 worker wakes;
15. keep site-specific behavior outside the extension;
16. never print or expose the pairing token in debug logs.

Unknown request methods must fail. They must not fall through to dynamic browser
API access such as `chrome[namespace][method]`.

---

## 5. Recommended project structure

The exact repository may differ. Inspect existing files before editing and
preserve its conventions. For a new Chromium implementation, a clear structure
is:

```text
tabame-extension/
    manifest.json
    background.js                 # MV3 service worker and startup
    bridge/
        connection.js             # socket/session/reconnect/heartbeat
        protocol.js               # validation, request dispatch, responses
    methods/
        tabs.js                   # allowlisted tab methods
        javascript-execute.js     # generic trusted-code execution
    popup/
        popup.html
        popup.js
        popup.css
    icons/
        ...
    firefox/
        ...                       # browser-specific package, if maintained
    README.md
    PROTOCOL.md
```

This is an implementation recommendation, not a required wire-protocol layout.
A smaller extension may keep the service worker in one file, but still separate
connection state, dispatch, browser methods, and popup concerns conceptually.

### Manifest guidance

The source specification establishes that the Chromium package is Manifest V3,
uses a service worker, stores pairing data locally, manages tabs, reads optional
tab-group metadata, and uses Chromium's user-script capability. The exact
manifest permissions and API availability are browser-version-specific and are
not defined by protocol version 1.

Therefore:

- preserve the repository's working manifest when modifying an existing build;
- request only permissions needed by implemented methods;
- do not broaden host access as a shortcut;
- verify permission names against the target browser before creating a new
  manifest from scratch;
- keep Chromium and Firefox manifests browser-specific rather than forcing one
  file to pretend their APIs are identical.

---

## 6. Pairing and popup behavior

The popup's main job is pairing and connection visibility. A practical popup
should have:

- a token input;
- a Save/Pair action;
- a status label such as Unpaired, Connecting, Connected, or Disconnected;
- a concise explanation that the token comes from Tabame's **Connection &
  pairing** page;
- no site-specific controls.

Pairing flow:

1. The user enables **Persistent browser connector** in Tabame.
2. The user opens the `browser` launcher plugin and its **Connection & pairing**
   page.
3. The user copies the generated token.
4. The user opens the extension popup, pastes the token, and saves it.
5. The extension stores it in extension-local storage.
6. The background worker closes any stale socket and reconnects with the new
   token.

Token rules:

- Treat the token as a secret.
- Store it only in extension-local storage.
- Trim accidental surrounding whitespace before saving.
- Do not include it in console output, telemetry, error strings, or status UI.
- A missing token means **unpaired**, not a crash loop.
- A changed token requires a new authenticated session.
- Do not attempt to read Tabame's local token file directly from the extension.

The protocol does not define a token-rotation message. Pairing changes occur by
saving a new token and reconnecting.

---

## 7. Session handshake

### 7.1 Extension → Tabame: `hello`

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

Field requirements:

- `type`: exactly `"hello"`;
- `protocol`: exactly `1`;
- `token`: the saved pairing token;
- `extensionVersion`: the installed extension version;
- `userAgent`: the browser user-agent string.

Send no request responses or events before this frame.

### 7.2 Tabame → extension: `welcome`

A successful server reply is:

```json
{
  "type": "welcome",
  "protocol": 1,
  "serverVersion": "0.1.0"
}
```

Only after a valid `welcome` should the extension mark the session as connected.
Validate at least:

- `type === "welcome"`;
- `protocol === 1`.

The server checks the WebSocket origin, protocol version, and token. An opened
socket is therefore not the same thing as an authenticated session.

### 7.3 Ping and pong

Either peer may send `ping` or `pong`. The extension sends a heartbeat within
Chromium's approximately 30-second Manifest V3 service-worker activity window.

Handle ping/pong without routing them through the request dispatcher. A ping
should receive a pong promptly. Heartbeats should not contain the pairing token.

---

## 8. Connection state machine

Keep explicit state rather than deriving everything from `socket.readyState`.
Recommended states:

```text
unpaired
  └─ token saved → disconnected

disconnected
  └─ connect → connecting

connecting
  ├─ socket open → authenticating
  └─ error/close → reconnect_wait

authenticating
  ├─ valid welcome → connected
  └─ invalid message/close → reconnect_wait

connected
  ├─ close/error → reconnect_wait
  └─ token changed → disconnected → connecting

reconnect_wait
  ├─ timer/wake → connecting
  └─ token removed → unpaired
```

Implementation safeguards:

- Maintain only one active socket.
- Maintain only one reconnect timer.
- Clear heartbeat and reconnect timers when replacing a connection.
- Use a connection generation number or compare socket identity so callbacks
  from an old socket cannot change current state.
- Reset reconnect backoff after a valid `welcome`, not merely after `open`.
- Use bounded backoff so a disabled Tabame server does not cause a tight loop.
- Reconnect when the worker starts or wakes and a token exists.
- Reconnect after the WebSocket closes while the connector setting is enabled.
- Do not queue an unbounded number of tab-change events while disconnected.

The extension cannot know from the socket alone whether Tabame is closed, the
connector setting is disabled, the token is wrong, or the protocol is
incompatible. Present a useful general disconnected state unless the server
provides a specific error.

### Reference connection skeleton

This demonstrates the protocol shape and lifecycle. Adapt storage and module
boundaries to the repository; do not replace a working project architecture
without reason.

```js
const BRIDGE_URL = "ws://127.0.0.1:17373/tabame";
const PROTOCOL = 1;
const HEARTBEAT_MS = 20_000; // inside the documented 30-second window
const RECONNECT_MAX_MS = 30_000;

let socket = null;
let sessionReady = false;
let heartbeatTimer = null;
let reconnectTimer = null;
let reconnectAttempt = 0;
let generation = 0;

function sendJson(message) {
  if (!socket || socket.readyState !== WebSocket.OPEN) return false;
  socket.send(JSON.stringify(message));
  return true;
}

function stopTimers() {
  if (heartbeatTimer) clearInterval(heartbeatTimer);
  if (reconnectTimer) clearTimeout(reconnectTimer);
  heartbeatTimer = null;
  reconnectTimer = null;
}

function scheduleReconnect(connectFn) {
  if (reconnectTimer) return;
  const delay = Math.min(1_000 * 2 ** reconnectAttempt, RECONNECT_MAX_MS);
  reconnectAttempt += 1;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    void connectFn();
  }, delay);
}

async function connectBridge() {
  const { pairingToken = "" } = await chrome.storage.local.get("pairingToken");
  const token = String(pairingToken).trim();
  if (!token) return; // unpaired

  generation += 1;
  const myGeneration = generation;

  stopTimers();
  sessionReady = false;
  if (socket) {
    try { socket.close(); } catch (_) {}
  }

  const ws = new WebSocket(BRIDGE_URL);
  socket = ws;

  ws.addEventListener("open", () => {
    if (myGeneration !== generation || socket !== ws) return;
    ws.send(JSON.stringify({
      type: "hello",
      protocol: PROTOCOL,
      token,
      extensionVersion: chrome.runtime.getManifest().version,
      userAgent: navigator.userAgent,
    }));
  });

  ws.addEventListener("message", async (event) => {
    if (myGeneration !== generation || socket !== ws) return;
    await handleSocketMessage(event.data);
  });

  ws.addEventListener("close", () => {
    if (myGeneration !== generation || socket !== ws) return;
    sessionReady = false;
    stopTimers();
    scheduleReconnect(connectBridge);
  });

  ws.addEventListener("error", () => {
    // close will drive reconnect; do not log the token or raw auth payload
  });
}

async function handleSocketMessage(raw) {
  let message;
  try {
    message = JSON.parse(raw);
  } catch (_) {
    return;
  }
  if (!message || typeof message !== "object" || Array.isArray(message)) return;

  if (!sessionReady) {
    if (message.type !== "welcome" || message.protocol !== PROTOCOL) {
      socket?.close();
      return;
    }
    sessionReady = true;
    reconnectAttempt = 0;
    heartbeatTimer = setInterval(() => sendJson({ type: "ping" }), HEARTBEAT_MS);
    return;
  }

  if (message.type === "ping") {
    sendJson({ type: "pong" });
    return;
  }
  if (message.type === "pong") return;

  if (message.type === "request") {
    await handleRequest(message);
  }
}
```

The skeleton intentionally leaves request methods in a separate dispatcher.

---

## 9. Request and response contract

### Request

Tabame sends:

```json
{
  "type": "request",
  "id": "uuid",
  "method": "tabs.list",
  "params": {},
  "timeoutMs": 30000
}
```

- `id` identifies the request and must be echoed unchanged.
- `method` must match the allowlist exactly.
- `params` is method-specific.
- `timeoutMs` is optional and is clamped to 1–60 seconds.

### Successful response

```json
{
  "type": "response",
  "id": "uuid",
  "ok": true,
  "result": {}
}
```

### Failed response

```json
{
  "type": "response",
  "id": "uuid",
  "ok": false,
  "error": "Human-readable message"
}
```

Response rules:

- Send exactly one response for every accepted request.
- Preserve `id` exactly.
- Never include both `result` and `error`.
- Convert browser runtime failures into concise, human-readable errors.
- Do not expose the pairing token, internal stack traces, or raw privileged
  objects.
- Unknown methods return an error; never silently ignore them.

### Reference dispatcher

```js
const METHOD_HANDLERS = Object.freeze({
  "bridge.ping": handleBridgePing,
  "tabs.list": handleTabsList,
  "tabs.audible": handleTabsAudible,
  "tabs.activate": handleTabsActivate,
  "tabs.close": handleTabsClose,
  "tabs.mute": handleTabsMute,
  "tabs.pin": handleTabsPin,
  "tabs.reload": handleTabsReload,
  "tabs.duplicate": handleTabsDuplicate,
  "tabs.open": handleTabsOpen,
  "javascript.execute": handleJavaScriptExecute,
});

function clampTimeout(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return 30_000;
  return Math.min(60_000, Math.max(1_000, Math.trunc(number)));
}

function withTimeout(promise, timeoutMs) {
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      setTimeout(() => reject(new Error("Browser request timed out")), timeoutMs);
    }),
  ]);
}

async function handleRequest(message) {
  const id = message.id;
  const method = message.method;

  if (typeof id !== "string" || !id) return;
  if (typeof method !== "string") {
    sendJson({ type: "response", id, ok: false, error: "Invalid method" });
    return;
  }

  const handler = METHOD_HANDLERS[method];
  if (!handler) {
    sendJson({
      type: "response",
      id,
      ok: false,
      error: `Unsupported method: ${method}`,
    });
    return;
  }

  try {
    const result = await withTimeout(
      Promise.resolve(handler(message.params ?? {})),
      clampTimeout(message.timeoutMs),
    );
    sendJson({ type: "response", id, ok: true, result });
  } catch (error) {
    sendJson({
      type: "response",
      id,
      ok: false,
      error: error instanceof Error ? error.message : "Browser request failed",
    });
  }
}
```

A production timeout helper should clear its timer after completion. The example
emphasizes the protocol flow rather than one required utility implementation.

---

## 10. Exact method allowlist

Protocol version 1 exposes only:

| Method | Parameters | Result purpose |
| --- | --- | --- |
| `bridge.ping` | none | Connector and browser version |
| `tabs.list` | none | All tabs, optional group metadata |
| `tabs.audible` | none | Audible tabs, group metadata, current candidate |
| `tabs.activate` | `tabId` | Updated tab |
| `tabs.close` | `tabId` | Completion |
| `tabs.mute` | `tabId`, optional `muted` | Updated tab |
| `tabs.pin` | `tabId`, optional `pinned` | Updated tab |
| `tabs.reload` | `tabId` | Completion |
| `tabs.duplicate` | `tabId` | New tab |
| `tabs.open` | `url`, optional `active` | New tab |
| `javascript.execute` | see §12 | JSON execution result |

Do not add bookmarks, history, downloads, reading list, arbitrary browser API
calls, or other capabilities under protocol version 1. Those appear only as
future roadmap ideas and require an explicit versioned design.

### Shared input validation

For tab methods:

- Require `tabId` where documented.
- Reject missing, non-numeric, or invalid tab IDs with a readable error.
- Treat optional booleans as booleans; do not use JavaScript truthiness to turn
  strings such as `"false"` into `true`.
- Catch errors for tabs that closed between listing and action.
- Return plain JSON-serializable data, not browser API objects with undefined or
  non-cloneable fields.

The source protocol describes the purpose of each result but does not define the
complete tab-result field schema. When modifying the existing connector, preserve
its established result shape and inspect its launcher consumers before changing
fields. Do not invent a new incompatible tab schema merely because the table
above is concise.

---

## 11. Tab operations

### `bridge.ping`

Return connector and browser version information. Keep the result stable and
JSON-serializable. This method verifies that request dispatch works; it is
separate from WebSocket `ping`/`pong` session frames.

### `tabs.list`

Return all open tabs. The connector's documented capabilities include:

- title;
- URL;
- favicon;
- active state;
- pinned state;
- audible/audio state;
- optional tab-group metadata.

Use one consistent normalization function for `tabs.list`, `tabs.audible`, and
methods returning updated/new tabs.

### `tabs.audible`

Return audible tabs, optional group metadata, and the current best-playing
candidate. The protocol does not specify the candidate-selection algorithm. If
an existing implementation exists, preserve it. If the user asks for a new
algorithm, define and test it explicitly rather than presenting an inference as
protocol.

### `tabs.activate`

Activate the requested tab and its containing window as required by the browser
implementation, then return the updated normalized tab.

### `tabs.close`

Close the requested tab and return a completion result. Do not attempt to return
an updated tab that no longer exists.

### `tabs.mute`

- Required: `tabId`.
- Optional: `muted`.
- Return the updated normalized tab.

When `muted` is omitted, preserve the current connector's established toggle or
default behavior; the protocol table does not further define it.

### `tabs.pin`

- Required: `tabId`.
- Optional: `pinned`.
- Return the updated normalized tab.

As with mute, preserve the existing behavior when the optional value is omitted.

### `tabs.reload`

Reload the tab and return completion. Handle a tab that disappears during the
operation.

### `tabs.duplicate`

Duplicate the requested tab and return the new normalized tab.

### `tabs.open`

- Required: `url`.
- Optional: `active`.
- Accept only URLs whose parsed protocol is `http:` or `https:`.
- Return the newly created normalized tab.

Do not accept `file:`, `javascript:`, `data:`, browser-internal URLs, extension
URLs, or shell paths.

Reference URL validation:

```js
function requireHttpUrl(value) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error("URL is required");
  }
  let url;
  try {
    url = new URL(value);
  } catch (_) {
    throw new Error("Invalid URL");
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error("Only HTTP and HTTPS URLs are allowed");
  }
  return url.href;
}
```

---

## 12. `javascript.execute`

This is the generic building block for browser-backed launcher plugins. It runs
JavaScript supplied by a trusted Tabame plugin. The extension must not contain
site-specific fetchers.

### Request example

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

### Parameters

| Field | Requirement |
| --- | --- |
| `code` | Required string; may use `await`; must return with `return`; maximum 128 KiB |
| `tabId` | Optional; defaults to active tab in last-focused window |
| `input` | Optional arbitrary JSON value exposed as local variable `input` |
| `world` | Optional; `USER_SCRIPT` by default, or `MAIN` |
| `allFrames` | Optional boolean; targets all frames |
| `frameIds` | Optional frame-ID array |
| `injectImmediately` | Optional boolean; skips normal `document_idle` preference |

`allFrames: true` and `frameIds: [...]` are mutually exclusive. The top frame is
the default target.

### Result

The result object contains:

- `tabId`;
- `pageUrl`;
- `world`;
- first-frame `result`;
- all per-frame `results`;
- `executedAt`.

The complete result must be JSON-serializable and no larger than 192 KiB.

### Execution rules

1. Require a non-empty code string.
2. Measure code size in bytes, not merely JavaScript character count.
3. Resolve the default tab from the active tab in the last-focused window.
4. Fetch/validate the target tab before injection.
5. Permit only target URLs using `http:` or `https:`.
6. Default to `USER_SCRIPT`.
7. Reject any world other than `USER_SCRIPT` or `MAIN`.
8. Reject simultaneous `allFrames` and `frameIds`.
9. Make `input` available to the supplied code without interpolating its text
   into the source string.
10. Support `await` and an explicit `return` value.
11. Normalize per-frame browser results into plain JSON.
12. Verify JSON serialization and the 192 KiB output limit before responding.
13. Return a readable error when browser policy, page type, permissions, or code
   execution prevents injection.

### Do not fake the browser API

The protocol defines the behavior but not the exact Chromium API call sequence.
When editing the real extension:

- inspect and preserve its working `userScripts` implementation;
- do not replace it with an invented API method;
- use Chromium's user-script sandbox for the default world;
- request `MAIN` only when the caller explicitly asks for page-JavaScript
  globals;
- preserve frame-result ordering and result envelope expected by existing
  launcher plugins.

Chromium must expose and allow its user-script capability. The user may need to
open the extension's Details page and enable **Allow User Scripts**. If it is not
available/enabled, return an actionable error rather than silently falling back
to a more privileged or unrelated mechanism.

### Security implications

Arbitrary plugin-supplied page code can read or modify authenticated pages in
the connected profile. This is intentional for trusted local plugins, but it is
powerful:

- do not run code from remote WebSocket peers;
- do not make the server reachable beyond loopback;
- do not add an unauthenticated execution path;
- do not silently upgrade `USER_SCRIPT` requests to `MAIN`;
- do not install browser-capable plugins from untrusted sources.

---

## 13. Tab-change events

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

Exact event name:

```text
tabs.changed
```

Allowed reasons:

```text
activated
created
removed
updated
```

Rules:

- Debounce noisy browser events.
- Send ISO-8601 time in `data.at`.
- Send only after a valid `welcome` session.
- Events are hints that browser state changed.
- Consumers must request a fresh snapshot such as `tabs.list` or
  `tabs.audible`; they must not reconstruct browser state solely from events.
- Do not create undocumented reasons for focus, navigation, title, favicon, or
  audio changes. Map them to the documented reason set.
- Do not queue unlimited stale events while disconnected. A later fresh
  snapshot is authoritative.

A simple debounce model may retain the latest reason and emit after a short
quiet period. If preserving every broad reason is important, coalesce them into
at most one event per reason within the debounce window; do not turn the event
channel into a high-volume tab log.

---

## 14. Manifest V3 lifecycle and reliability

The extension must maintain useful behavior even when Chromium suspends and
later wakes its service worker.

Required outcomes:

- On worker startup/wake, load the token and reconnect.
- While connected, send heartbeats inside the documented 30-second activity
  window.
- Browser tab events should wake the worker and allow it to re-establish the
  connection when needed.
- Closing or restarting Tabame should not permanently wedge the extension.
- Re-enabling the connector server should eventually produce a new authenticated
  session without reinstalling the extension.
- Saving a new token should restart pairing immediately.

Do not assume an in-memory socket, timer, or status survives worker suspension.
Persist only data that truly needs persistence, primarily the pairing token and
perhaps non-secret UI preferences. Connection state is ephemeral and should be
re-derived.

Test the packaged behavior, not only the service worker opened in DevTools;
DevTools can alter suspension behavior and hide lifecycle bugs.

---

## 15. Security model

The connector's security properties are part of the product behavior:

- server binds to `127.0.0.1` only;
- WebSocket upgrades must originate from a `chrome-extension://` origin;
- the first frame carries the local 256-bit pairing token;
- protocol version is checked;
- requests use a small explicit method allowlist;
- `tabs.open` accepts HTTP(S) only;
- code injection targets HTTP(S) pages only;
- arbitrary code defaults to `USER_SCRIPT` sandbox;
- `MAIN` requires an explicit request;
- token is stored in extension-local storage;
- locally installed browser-capable Tabame plugins are trusted code.

### Security review checklist

Before shipping, verify:

- [ ] No listener or server binds to a LAN/public interface.
- [ ] The token is never logged.
- [ ] `hello` is always first.
- [ ] Requests are ignored/rejected before `welcome`.
- [ ] The request dispatcher is a fixed map.
- [ ] Unknown methods cannot reach browser APIs.
- [ ] IDs, booleans, URLs, worlds, frame options, and size limits are validated.
- [ ] Non-HTTP(S) open and injection targets are rejected.
- [ ] `USER_SCRIPT` remains the default.
- [ ] Extension error responses do not leak secrets or stack traces.
- [ ] Popup HTML does not render token data through unsafe HTML insertion.
- [ ] Reconnect logs do not include full handshake payloads.
- [ ] All browser API results are reduced to intentional JSON fields.
- [ ] A malicious or malformed request cannot create an unbounded timer, event
      queue, source string, or response.

The protocol intentionally trusts local Tabame plugins after they gain bridge
access. Protocol version 1 does not provide per-plugin permission grants or an
audit log; those are roadmap concepts, not current features.

---

## 16. Chromium installation and pairing test

Development installation:

1. Open `chrome://extensions`, or the equivalent page in Edge, Brave, or
   Vivaldi.
2. Enable **Developer mode**.
3. Choose **Load unpacked** and select the `tabame-extension` folder.
4. Open the extension's **Details** page.
5. Enable **Allow User Scripts** when Chromium shows that option.
6. Install the companion launcher plugin from `plugins/browser`.
7. In Tabame's **Launcher Plugins**, enable **Persistent browser connector**.
8. Type `browser` and open **Connection & pairing**.
9. Copy the token.
10. Open the extension popup, paste the token, and save.
11. Confirm a valid `hello`/`welcome` session and test `bridge.ping`.

Chromium may request local-network access. Explain that the extension connects
only to `127.0.0.1:17373`.

---

## 17. Firefox package

The project uses a browser-specific package under `firefox/`, installed for
development through Firefox's `about:debugging` flow.

The supplied protocol documentation does not define Firefox manifest fields,
API substitutions, origin behavior, or JavaScript-execution implementation.
Therefore, when working on Firefox:

- preserve the same version-1 message contract where the existing package does;
- inspect the actual Firefox source before editing;
- adapt browser APIs explicitly rather than blindly copying Chromium code;
- keep Firefox-specific permissions and lifecycle logic in its package;
- do not claim Chromium's **Allow User Scripts** setup applies unchanged;
- state clearly when a requested capability is not supported by the existing
  Firefox implementation.

Do not invent browser parity that the repository does not implement.

---

## 18. Error handling

Errors should help the launcher plugin or user recover. Good examples:

```text
Pairing token is missing
Unsupported method: bookmarks.list
Tab 42 was not found
Only HTTP and HTTPS URLs are allowed
Cannot execute scripts on chrome:// pages
Allow User Scripts is disabled for the Tabame Connector extension
JavaScript code exceeds the 128 KiB limit
JavaScript result exceeds the 192 KiB limit
allFrames and frameIds cannot be used together
Browser request timed out
```

Avoid:

- raw browser API object dumps;
- full stack traces in protocol responses;
- errors containing the pairing token;
- generic `undefined` or `[object Object]` messages;
- pretending an operation succeeded when the tab disappeared.

Errors travel in:

```json
{
  "type": "response",
  "id": "same-request-id",
  "ok": false,
  "error": "Human-readable message"
}
```

---

## 19. Test matrix

### Pairing/session

- no saved token → unpaired, no tight reconnect loop;
- valid token → `hello`, `welcome`, connected;
- wrong token → disconnected/retry without leaking token;
- wrong protocol welcome → close/reject;
- non-JSON server message → ignored or cleanly rejected;
- server disabled and later re-enabled → reconnect;
- Tabame restarted → reconnect;
- token changed in popup → old socket closed, new handshake;
- ping from server → pong;
- periodic extension heartbeat → session remains active.

### Request dispatch

- each allowlisted method reaches only its handler;
- unknown method returns one failed response;
- missing/invalid request ID is handled safely;
- browser API rejection returns one failed response;
- request timeout is clamped to 1–60 seconds;
- every successful response preserves ID and contains `ok: true`.

### Tabs

- list across multiple windows;
- optional group metadata present and absent;
- activate background tab/window;
- close a tab that already disappeared;
- mute/unmute and optional-value behavior;
- pin/unpin and optional-value behavior;
- reload;
- duplicate;
- open valid HTTP and HTTPS URLs;
- reject invalid, `file:`, `data:`, `javascript:`, internal, and extension URLs;
- audible tabs and current-candidate behavior.

### JavaScript execution

- default active tab in last-focused window;
- explicit tab ID;
- `USER_SCRIPT` default;
- explicit `MAIN`;
- top frame default;
- `allFrames`;
- explicit `frameIds`;
- reject `allFrames` + `frameIds`;
- `injectImmediately` true/false;
- code uses `await`;
- code receives structured `input`;
- JSON scalar, object, list, and null results;
- non-serializable result;
- code at and above 128 KiB;
- result at and above 192 KiB;
- non-HTTP(S) target;
- missing/disabled user-script capability;
- page closes or navigates during execution;
- per-frame partial failure handling consistent with existing result schema.

### Events/lifecycle

- activated, created, removed, updated reasons;
- noisy update events are debounced;
- disconnected events do not create an unbounded queue;
- worker suspension and wake;
- behavior with DevTools closed;
- browser restart with saved token;
- local-network permission prompt does not lead to misleading success UI.

---

## 20. AI implementation workflow

When asked to build or modify this extension:

1. Read `README.md`, `PROTOCOL.md`, `manifest.json`, service-worker files,
   popup files, and existing browser-method modules.
2. Identify whether the request changes:
   - popup/pairing;
   - connection/session lifecycle;
   - one existing allowlisted method;
   - JavaScript execution;
   - events;
   - Chromium or Firefox packaging.
3. Write a small state/data-flow map before changing code.
4. Preserve the protocol constants and method names.
5. Preserve established response shapes not fully specified by the protocol.
6. Make the smallest coherent change.
7. Validate all new inputs and errors.
8. Keep site-specific logic in the caller plugin.
9. Return complete changed files, not disconnected snippets, when the user asks
   for implementation.
10. Include installation/test steps relevant to the changed behavior.
11. State any point that cannot be derived from the provided repository or
    protocol instead of guessing.

### Required output quality

A generated extension change should:

- run as a Manifest V3 extension in its target Chromium browser;
- have no placeholder handler for the requested feature;
- use one explicit request dispatcher;
- maintain only one active connection/reconnect loop;
- survive ordinary server disconnect/reconnect cycles;
- send protocol-compliant responses;
- avoid broad unrelated permissions;
- keep pairing/token handling private;
- include actionable errors;
- avoid adding site-specific automation to the connector.

---

## 21. Common mistakes

### Treating socket open as authentication

Wrong: mark connected in `onopen`.

Correct: send `hello`, then wait for valid `welcome`.

### Adding a generic browser API proxy

Wrong:

```js
chrome[params.namespace][params.method](...params.args)
```

Correct: use the fixed allowlist and explicit handlers.

### Putting scraping code in the extension

Wrong: add `youtube.getTitle`, `gmail.readInbox`, or selectors to the connector.

Correct: the launcher plugin calls `javascript.execute` with its own code.

### Allowing arbitrary URL schemes

Wrong: pass any string to the tab-create API.

Correct: parse and accept only HTTP(S).

### Falling back to a more privileged world

Wrong: if `USER_SCRIPT` fails, silently run in `MAIN`.

Correct: return an actionable error; `MAIN` must be explicit.

### Assuming tab events are full state

Wrong: update the plugin's complete state from `tabs.changed` reason alone.

Correct: event means “request a fresh snapshot.”

### Ignoring MV3 suspension

Wrong: connect once during install and trust global variables forever.

Correct: reconnect on worker startup/wake and heartbeat while connected.

### Inventing protocol-version-1 capabilities

Wrong: add bookmarks/history/downloads under arbitrary method names.

Correct: create a documented, explicitly versioned protocol change only when
requested across both server and extension.

---

## 22. Final checklist

Before considering the browser extension complete:

- [ ] WebSocket URL is exactly `ws://127.0.0.1:17373/tabame`.
- [ ] Protocol is exactly `1`.
- [ ] `hello` is first and contains token, extensionVersion, and userAgent.
- [ ] Connected status requires valid `welcome`.
- [ ] Ping/pong and heartbeat are implemented.
- [ ] Reconnect is bounded and cannot duplicate sockets/timers.
- [ ] Token is stored locally and never logged.
- [ ] Request IDs are echoed exactly.
- [ ] Only the 11 documented methods exist.
- [ ] `tabs.open` accepts only HTTP(S).
- [ ] JavaScript targets only HTTP(S) pages.
- [ ] `USER_SCRIPT` is default; `MAIN` is explicit.
- [ ] `allFrames` and `frameIds` are mutually exclusive.
- [ ] Code is limited to 128 KiB.
- [ ] JSON result is limited to 192 KiB.
- [ ] Tab events use `tabs.changed` and only four documented reasons.
- [ ] Events are debounced and treated as hints.
- [ ] Site-specific logic remains in launcher plugins.
- [ ] Errors are human-readable and secret-free.
- [ ] Chromium installation and Allow User Scripts steps are documented.
- [ ] Firefox differences are not guessed.
- [ ] The extension is tested with the MV3 worker allowed to suspend.

