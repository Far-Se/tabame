# Browser Tabs — Tabame launcher plugin

Type **`bwt`** to immediately list every tab in the paired Chromium profile.
There is no command menu or drill-down: the tab list is the plugin's root view.

## Pairing

Pair the `tabame-extension` extension once through the main `browser`
plugin. Tabame's app-owned bridge stores its shared pairing data in:

```text
%localappdata%\Tabame\browser-bridge.json
```

No second token or extension configuration is required.

## Install

1. Copy this folder to `%localappdata%\Tabame\plugins\bwt\`.
2. Ensure Node.js is on `PATH`.
3. Open **Launcher Plugins** and enable **Persistent browser connector**.
4. Reopen the launcher and type **`bwt`**.

## Controls

- Type after `bwt` to filter by tab title or URL.
- Grouped tabs show the Chromium group name as a color-matched tag; group names
  are also searchable.
- **Enter** focuses the selected tab and hides the launcher.
- **Ctrl+K** offers mute/unmute, pin/unpin, reload, duplicate, copy URL, and
  confirmed close.
- **Ctrl+R** refreshes the tab snapshot.
- Tab creation, removal, activation, title, URL, favicon, and audio changes
  refresh the list automatically.
