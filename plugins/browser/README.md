# Browser — Tabame launcher plugin

Control Chromium or Firefox through the companion **Tabame Connector** extension.

## Install

1. Copy this folder to `%localappdata%\Tabame\plugins\browser\`.
2. Make sure Node.js is on `PATH`.
3. Install the companion **Tabame Connector** extension:
   - [Chrome Web Store](https://chromewebstore.google.com/detail/tabame-connector/affgkglfpdpkdfolkogkaplllgmmkhdd?authuser=0&hl=en)
   - [Firefox Add-ons](https://addons.mozilla.org/en-US/firefox/addon/tabame-connector-for-firefox/)

   For local development, load `tabame-extension` as an unpacked Chromium
   extension, or load `tabame-extension/firefox/manifest.json` from Firefox's
   `about:debugging` page. Enable **Allow User Scripts** in Chromium when
   that toggle is shown; Firefox requests its optional permission in the
   extension popup.

4. Open **Launcher Plugins** and enable **Persistent browser connector**.
5. Reopen the Tabame launcher and type **`browser`**.
6. Open **Connection & pairing**, copy the token, and paste it into the
   extension popup.

The optional connector is owned by Tabame rather than this plugin. Once enabled,
it stays paired while Tabame is running, so browser plugins open without waiting
for an extension reconnect.

Tabame stores its random pairing token in
`%localappdata%\Tabame\browser-bridge.json`. Browser-capable launcher plugins
such as `browser` and `bwt` use the app-owned bridge, so the browser extension
is paired once per Windows account/browser profile. Existing
`plugins\browser\bridge-config.json` credentials migrate automatically.

## Commands

- **Codex usage** — plugin-owned logic opens ChatGPT Codex analytics in an
  inactive temporary tab, sends its extraction JavaScript through
  `javascript.execute`, and closes the tab.
- **All browser tabs** — searchable list with favicons and tab state.
- **Playing audio** — audible tabs with the best current candidate first.
- **Connection & pairing** — live status, extension version, port, and token.

Tab actions are available through Enter and Ctrl+K: focus, close, mute/unmute,
pin/unpin, reload, duplicate, and copy URL.

## Bridge

- WebSocket: `ws://127.0.0.1:17373/tabame`
- Protocol: JSON request/response frames, version 1
- Authentication: generated 256-bit token
- Origin policy: `chrome-extension://` and `moz-extension://` origins only
- Lifetime: the server stays active while Tabame is running and the optional
  **Persistent browser connector** setting is enabled
- Site-specific tasks live in plugins; the extension exposes the generic
  `javascript.execute` method documented in `tabame-extension/PROTOCOL.md`
