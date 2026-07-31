# Spotify plugin for Tabame

Search Spotify and control playback from the launcher: tracks, artists,
albums, playlists, queue, devices, recently played, top tracks, liked songs.

## Install

1. Copy this whole `spotify-plugin` folder into
   `%localappdata%\Tabame\plugins\spotify\` (rename the folder to `spotify`,
   or anything you like).
2. Make sure `python` is on your `PATH`. Tabame will auto-install `requests`
   on first launch.

## One-time Spotify setup (free, ~1 minute)

1. Go to the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard)
   and click **Create app**.
   The Spotify account that owns a Development Mode app must have an active
   **Premium** subscription.
2. Fill in any name/description. For **Redirect URI**, add exactly:
   ```
   http://127.0.0.1:8888/callback
   ```
   (If you change `redirect_port` in `config.json`, use that port instead.)
3. Save, then open the app and copy the **Client ID**.
4. In the plugin folder, copy `config.example.json` to `config.json` and
   fill in your Client ID:
   ```json
   { "client_id": "YOUR_CLIENT_ID", "redirect_port": 8888 }
   ```
5. Open the launcher, type `sp`, and choose **Connect Spotify Account**. Your
   browser opens Spotify's login/consent screen; approve it and you're
   connected. No client secret is needed (this uses PKCE), and your refresh
   token is stored in Windows Credential Manager, not in a plain file.

### If Spotify returns 403 Forbidden

Spotify can allow an account to finish the login flow but deny every API
request afterward. In the Developer Dashboard, open the app, then go to
**Settings > Users Management** and add the exact Spotify account that signs
in to the plugin. The app owner must also have Premium. After changing either
setting, use **Disconnect Account**, then connect again so Spotify issues a new
token with the requested permissions.

## Using it

Type `sp` to open the plugin.

- Type anything to see a **"Search Spotify for ..."** shortcut, or matching
  commands (Now Playing, Playlists, Liked Songs, etc.).
- **Search** results are grouped into Tracks / Artists / Albums / Playlists.
  `Enter` plays a track, opens an artist's top tracks, or opens a
  playlist/album's track list. Ctrl+K on any item for more actions (queue,
  save, open in Spotify, copy link, play album/playlist).
- **Now Playing** shows a live-updating view (refreshes every few seconds)
  with play/pause, next/previous, shuffle, repeat, volume, and quick jumps
  to the queue or device list.
- **Devices**, **Recently Played**, **Top Tracks** (4 weeks / 6 months / all
  time), **Your Playlists**, **Liked Songs**, and **Queue** are all separate
  screens reachable from the root menu.
- **Disconnect Account** clears the stored token.

## Notes

- Playback control requires an active Spotify device (phone, desktop app, or
  web player) — Spotify's API can't start playback on a device that isn't
  already open somewhere.
- Set `"dev": true` in `plugin.json` while developing for hot reload + a
  debug console.
