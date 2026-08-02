# qBittorrent — Tabame launcher plugin

Type **`qbit`** in the launcher to browse qBittorrent torrents, inspect their
stats, open the qBittorrent WebUI in a browser tab, and open a torrent's
download folder.

## Install

1. Copy this folder to `%localappdata%\Tabame\plugins\qbittorrent\`.
2. Make sure Node.js 18+ is on `PATH`. Tabame installs the small `undici`
   dependency from `package.json` the first time the plugin starts.
3. Enable **Persistent browser connector** in Tabame's Launcher Plugins
   settings and pair the `tabame-extension` browser extension if you want the
   plugin to reuse the WebUI's logged-in browser session.
4. Reopen the launcher and type **`qbit`**. The first screen asks for the
   qBittorrent WebUI URL and an optional HTTP(S) proxy.

The browser connector keeps the qBittorrent WebUI in a normal browser tab. API
requests made through that tab are same-origin, so qBittorrent's WebUI login
cookie is reused without adding qBittorrent credentials to this plugin.

The proxy field is used for direct API fallback requests when the browser
connector is unavailable. Tabame cannot change a browser tab's proxy on a
per-tab basis, so configure the browser's own proxy as well when the WebUI is
only reachable through a proxy. Do not put proxy credentials in a committed
config file.

## Controls

- **All / Active / Downloading / Seeding / Completed** — browse and search
  torrents by name, category, or hash.
- **Enter** on a torrent — show detailed stats and the file list.
- **Preview → Save path → Open folder** or **Ctrl+K → Open download folder** —
  asks Windows to open qBittorrent's reported `save_path`.
- **Ctrl+K → Open WebUI tab** — focuses the existing qBittorrent tab or opens
  one and hides the launcher.
- **Ctrl+K → Pause/Resume**, **Recheck**, and **Copy hash** — available on each
  torrent where qBittorrent supports the operation.
- **Ctrl+R** — refresh the current torrent list.

Opening a folder uses the path reported by qBittorrent on the local machine.
For a remote qBittorrent server, that path belongs to the server and may not be
available on the Windows machine running Tabame.
