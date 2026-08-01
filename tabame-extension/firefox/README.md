# Tabame Connector for Firefox

Firefox extension for the Tabame browser bridge. It provides the same tab
control, live tab events, and trusted plugin JavaScript execution as the
Chromium extension in the parent folder.

## Install temporarily

1. Open `about:debugging#/runtime/this-firefox` in Firefox.
2. Click **This Firefox**, then **Load Temporary Add-on**.
3. Select `tabame-extension/firefox/manifest.json`.
4. Open the **Tabame Connector** toolbar popup.
5. Paste the token from Tabame's **browser** plugin and save. Firefox will ask
   for the optional `userScripts` permission; allow it if browser plugins
   need to execute JavaScript in pages.
6. In Tabame, enable **Persistent browser connector**, then open
   **Connection & pairing** if you need to copy the token.

Temporary add-ons are removed when Firefox exits. For a persistent install,
package and sign the extension through Mozilla Add-ons.

## Capabilities

- List open tabs with title, URL, favicon, active/pinned/audio state, and groups.
- Focus, close, reload, duplicate, pin/unpin, and mute/unmute tabs.
- Identify audible tabs and push debounced tab-change events.
- Execute trusted plugin JavaScript in HTTP(S) tabs through Firefox's
  `userScripts` API.
- Maintain the authenticated loopback WebSocket connection to Tabame.

The wire protocol is documented in [PROTOCOL.md](PROTOCOL.md) and is shared with
the Chromium extension.

## Security

- The bridge is loopback-only at `ws://127.0.0.1:17373/tabame`.
- The first frame must contain Tabame's generated pairing token.
- Requests use the same allowlist as the Chromium extension.
- The `userScripts` permission is optional and requested only from the popup;
  review the plugins you install before granting it.

