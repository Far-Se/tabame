# Browser — Tabame launcher plugin

Control Chromium through the companion **Tabame Connector** extension.

## Install

1. Copy this folder to `%localappdata%\Tabame\plugins\browser\`.
2. Make sure Node.js is on `PATH`.
3. Load `extension/tabame-connector` as an unpacked Chromium extension.
4. Open **Launcher Plugins** and enable **Persistent browser connector**.
5. Reopen the Tabame launcher and type **`browser`**.
6. Open **Connection & pairing**, copy the token, and paste it into the
   extension popup.

The optional connector is owned by Tabame rather than this plugin. Once enabled,
it stays paired while Tabame is running, so browser plugins open without waiting
for an extension reconnect.

Tabame stores its random pairing token in
`%localappdata%\Tabame\browser-bridge.json`. Browser-capable launcher plugins
such as `browser` and `bwt` use the app-owned bridge, so the Chromium extension
is paired once per Windows account/browser profile. Existing
`plugins\browser\bridge-config.json` credentials migrate automatically.

## Commands

- **Codex usage** — opens ChatGPT Codex analytics in an inactive temporary tab,
  waits for the page, reads `(\d+)% … remaining`, and closes the tab.
- **All browser tabs** — searchable list with favicons and tab state.
- **Playing audio** — audible tabs with the best current candidate first.
- **Connection & pairing** — live status, extension version, port, and token.

Tab actions are available through Enter and Ctrl+K: focus, close, mute/unmute,
pin/unpin, reload, duplicate, and copy URL.

## Bridge

- WebSocket: `ws://127.0.0.1:17373/tabame`
- Protocol: JSON request/response frames, version 1
- Authentication: generated 256-bit token
- Origin policy: `chrome-extension://` origins only
- Lifetime: the server stays active while Tabame is running and the optional
  **Persistent browser connector** setting is enabled
