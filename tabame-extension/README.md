# Tabame Connector

Manifest V3 Chromium extension that gives the Tabame launcher controlled access
to the current browser profile. The bridge is loopback-only, authenticates with
a generated token, and accepts requests only while Tabame's optional persistent
browser connector is enabled.

## Install

1. Open `chrome://extensions` (or the equivalent page in Edge/Brave/Vivaldi).
2. Enable **Developer mode**.
3. Choose **Load unpacked** and select this `extension/tabame-connector` folder.
4. Install the companion launcher plugin from `plugins/browser`.
5. In Tabame, open **Launcher Plugins** and enable **Persistent browser
   connector**.
6. Type `browser` and open **Connection & pairing**.
7. Copy the token, click the extension icon, paste the token, and save.

The bridge remains available while Tabame is running, independently of whether
a browser launcher plugin is open. Turning the setting off closes the loopback
server and disconnects the extension.

Chromium may ask for local-network permission the first time the extension
connects. The connection only targets `127.0.0.1:17373`.

## Capabilities

- List every open tab with title, URL, favicon, active/pinned/audio state.
- Focus, close, reload, duplicate, pin/unpin, and mute/unmute tabs.
- Identify all audible tabs and the best current-playing candidate.
- Open a temporary inactive ChatGPT analytics tab, read the Codex remaining
  percentage, and close the temporary tab.
- Push tab-change events to the launcher for live refreshes.
- Maintain the connection while Tabame is running and wake periodically after
  Chromium suspends the MV3 service worker.

## Security

- Server binds to `127.0.0.1`, never the LAN.
- WebSocket upgrade requests must come from a `chrome-extension://` origin.
- The first frame must contain the 256-bit local pairing token.
- Requests use a small allowlist; the bridge does not support arbitrary script
  execution or arbitrary URL schemes.
- The token is generated locally in
  `%localappdata%\Tabame\browser-bridge.json` and is stored in Chromium's
  extension-local storage after pairing. All Tabame browser plugins use the
  same token and port.

The versioned request/response and event schema is documented in
[`PROTOCOL.md`](PROTOCOL.md).

## Professional roadmap

- Provide a signed native messaging host for packaged browser installation.
- Add optional, separately granted capabilities for bookmarks, history,
  downloads, reading list, and current-page/selection handoff.
- Add named browser sessions and tab-group save/restore.
- Add multi-profile discovery and an explicit incognito policy.
- Add a permission dashboard, audit log, token rotation, and extension update
  compatibility checks before wider distribution.
