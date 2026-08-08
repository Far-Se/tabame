# qBittorrent — Tabame launcher plugin

Type **`qbit`** in the launcher to browse qBittorrent torrents, inspect their
stats, pause or resume transfers, open download folders, and optionally open
the full WebUI.

## Install

1. Copy this folder to `%localappdata%\Tabame\plugins\qbittorrent\`.
2. Make sure Node.js 18+ is on `PATH`. Tabame installs the small `undici`
   dependency from `package.json` the first time the plugin starts.
3. Reopen the launcher and type **`qbit`**. The setup screen asks for the
   qBittorrent WebUI URL, optional WebUI credentials, and an optional HTTP(S)
   proxy.

The plugin talks to qBittorrent's HTTP API directly. It does not need the
Tabame browser connector or a browser extension. When credentials are entered,
it logs in through `/api/v2/auth/login`, keeps the returned `SID` cookie for the
plugin session, and uses the API for torrent lists, details, and mutations. Leave
both credential fields blank only when qBittorrent WebUI authentication is
disabled.

The qBittorrent WebUI itself polls `/api/v2/sync/maindata?rid=0`, but a plugin
does not need to load that page to use the API. This plugin uses the smaller
paged and detail endpoints directly, which avoids downloading the entire torrent
snapshot on every search.

The proxy is used by the direct API client. Do not put proxy credentials in a
committed config file. For unattended/local setup, the following environment
variables are also supported when the corresponding config value is absent:

- `QBIT_URL`
- `QBIT_USERNAME`
- `QBIT_PASSWORD`
- `QBIT_PROXY`

The password is stored in the plugin's local `config.json` when entered through
the setup form; keep that file private.

## Controls

- **All / Active / Downloading / Seeding / Completed** — browse and search
  torrents by name, category, or hash.
- **Enter** on a torrent — show detailed stats and the file list.
- **Preview → Save path → Open folder** or **Ctrl+K → Open download folder** —
  asks Windows to open qBittorrent's reported `save_path`.
- **Ctrl+K → Open WebUI** — optionally opens the configured WebUI in the default
  browser. The launcher does not open a tab just to read torrent data.
- **Ctrl+K → Pause/Resume**, **Recheck**, and **Copy hash** — available on each
  torrent where qBittorrent supports the operation.
- **Ctrl+R** — refresh the current torrent list or test the API connection on
  the root screen.

Opening a folder uses the path reported by qBittorrent on the local machine.
For a remote qBittorrent server, that path belongs to the server and may not be
available on the Windows machine running Tabame.
