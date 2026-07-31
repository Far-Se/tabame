#!/usr/bin/env python3
"""
Spotify plugin for Tabame.

Search tracks/artists/albums/playlists, control playback (play, pause,
next, previous, shuffle, repeat, volume), browse playlists & liked songs,
see recently played & top tracks, manage the queue, and switch devices.

Auth: Authorization Code + PKCE (no client secret required). Register a
Spotify app at https://developer.spotify.com/dashboard, add the redirect
URI printed in the setup screen (default http://127.0.0.1:8888/callback),
and put the Client ID in config.json next to this script.
"""
import sys
import os
import json
import time
import uuid
import base64
import hashlib
import secrets
import threading
import urllib.parse as urlparse
from http.server import BaseHTTPRequestHandler, HTTPServer

try:
    import requests
except ImportError:
    requests = None

API_BASE = "https://api.spotify.com/v1"
TOKEN_URL = "https://accounts.spotify.com/api/token"
AUTH_URL = "https://accounts.spotify.com/authorize"
SCOPES = (
    "user-read-private user-read-playback-state user-modify-playback-state "
    "user-read-currently-playing user-read-recently-played user-top-read "
    "playlist-read-private playlist-read-collaborative "
    "playlist-modify-public playlist-modify-private "
    "user-library-read user-library-modify"
)

# ---------------------------------------------------------------- IO -----

def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def toast(text, style="success"):
    send({"type": "command", "command": "toast", "text": text, "style": style})


def open_url(url):
    if url:
        send({"type": "command", "command": "open", "url": url})


# ------------------------------------------------------------ config -----

def load_config():
    cfg = {"redirect_port": 8888}
    if os.path.exists("config.json"):
        try:
            with open("config.json", "r", encoding="utf-8") as f:
                cfg.update(json.load(f))
        except Exception as e:
            log("config load error:", e)
    return cfg


CONFIG = load_config()

SETUP_MARKDOWN = """# Connect Spotify

This plugin needs a free Spotify app registration (no cost, takes a minute).

1. Open the **Spotify Developer Dashboard** (action below) and create an app.
2. In the app's settings, add this **Redirect URI** exactly:
   `http://127.0.0.1:{port}/callback`
3. Copy the **Client ID**.
4. Create a file named `config.json` next to `main.py` in this plugin's
   folder with:

```
{{"client_id": "YOUR_CLIENT_ID", "redirect_port": {port}}}
```

5. Reopen the launcher and type `sp` again.
""".format(port=CONFIG.get("redirect_port", 8888))

# ------------------------------------------------------------- state -----

state = {"screen": "root"}
NAV_STACK = []
ITEM_DATA = {}

REFRESH_TOKEN = None
ACCESS_TOKEN = None
TOKEN_EXPIRY = 0
USER_PROFILE = {}
TOKEN_LOCK = threading.Lock()

POLL_STOP = threading.Event()
POLL_THREAD = None


def navigate(new_screen, **updates):
    NAV_STACK.append(dict(state))
    state.clear()
    state["screen"] = new_screen
    state.update(updates)


def go_back():
    if state.get("screen") == "now_playing":
        stop_polling()
    prev = NAV_STACK.pop() if NAV_STACK else {"screen": "root"}
    state.clear()
    state.update(prev)
    if state.get("screen") == "now_playing":
        start_polling()
    dispatch_render(0, "")


# --------------------------------------------------------- storage -----

def storage_set(key, value, secret=False):
    send({"type": "command", "command": "storage", "op": "set", "key": key, "value": value, "secret": secret})


def storage_delete(key, secret=False):
    send({"type": "command", "command": "storage", "op": "delete", "key": key, "secret": secret})


def storage_get(key, secret=False, timeout=5.0):
    """Blocking read: sends the storage command and reads stdin lines until
    the matching reply arrives (or timeout). Only safe to call from the main
    stdin-processing thread, before other messages are expected."""
    req_id = uuid.uuid4().hex[:10]
    send({"type": "command", "command": "storage", "op": "get", "key": key, "secret": secret, "requestId": req_id})
    deadline = time.time() + timeout
    while time.time() < deadline:
        line = sys.stdin.readline()
        if not line:
            return None
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        if msg.get("type") == "storage" and msg.get("requestId") == req_id:
            return msg.get("value")
        if msg.get("type") == "close":
            sys.exit(0)
        # otherwise drop it (rare stray keystroke during the near-instant read)
    return None


def load_credentials():
    global REFRESH_TOKEN
    if not CONFIG.get("client_id"):
        return
    try:
        REFRESH_TOKEN = storage_get("refresh_token", secret=True)
    except Exception as e:
        log("credential load error:", e)
        REFRESH_TOKEN = None


# ------------------------------------------------------------- auth -----

class SpotifyAuthError(Exception):
    pass


class SpotifyApiError(Exception):
    pass


def spotify_error_message(resp):
    """Return Spotify's useful error body plus Development Mode guidance."""
    message = ""
    reason = ""
    try:
        payload = resp.json()
        error = payload.get("error", payload) if isinstance(payload, dict) else payload
        if isinstance(error, dict):
            message = str(error.get("message") or "")
            reason = str(error.get("reason") or "")
        elif error:
            message = str(error)
    except (ValueError, TypeError):
        message = (resp.text or "").strip()

    detail = message or resp.reason or "Request denied"
    if reason:
        detail = f"{detail} ({reason})"

    if resp.status_code == 403:
        if "scope" in f"{message} {reason}".lower():
            return (
                f"Spotify denied this request (403: {detail}). Disconnect and "
                "reconnect the account so the required permissions can be granted."
            )
        return (
            f"Spotify denied this app (403: {detail}). In Spotify Development "
            "Mode, the app owner must have Premium and the signed-in Spotify "
            "account must be added under Dashboard > App > Settings > Users "
            "Management. Fix that, then disconnect and reconnect."
        )
    if resp.status_code == 429 and reason == "QUOTA_EXCEEDED":
        return "Spotify's shared Development Mode API quota has been exceeded. Try again later."
    return f"Spotify API error {resp.status_code}: {detail}"


def raise_for_spotify_status(resp):
    if resp.status_code >= 400:
        raise SpotifyApiError(spotify_error_message(resp))


def pkce_pair():
    verifier = base64.urlsafe_b64encode(secrets.token_bytes(64)).rstrip(b"=").decode("ascii")[:128]
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode("ascii")).digest()).rstrip(b"=").decode("ascii")
    return verifier, challenge


class _CallbackHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        qs = urlparse.urlparse(self.path).query
        params = urlparse.parse_qs(qs)
        self.server.auth_code = params.get("code", [None])[0]
        self.server.auth_error = params.get("error", [None])[0]
        self.server.auth_state = params.get("state", [None])[0]
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(b"<html><body><h2>Spotify connected. You can close this tab.</h2></body></html>")

    def log_message(self, fmt, *args):
        pass


def do_connect():
    if not CONFIG.get("client_id"):
        toast("Missing client_id in config.json", style="error")
        return
    verifier, challenge = pkce_pair()
    port = CONFIG.get("redirect_port", 8888)
    redirect_uri = f"http://127.0.0.1:{port}/callback"
    state_token = secrets.token_hex(8)
    params = {
        "client_id": CONFIG["client_id"],
        "response_type": "code",
        "redirect_uri": redirect_uri,
        "code_challenge_method": "S256",
        "code_challenge": challenge,
        "scope": SCOPES,
        "state": state_token,
        "show_dialog": "true",
    }
    auth_url = AUTH_URL + "?" + urlparse.urlencode(params)

    try:
        httpd = HTTPServer(("127.0.0.1", port), _CallbackHandler)
    except OSError as e:
        toast(f"Can't listen on port {port}: {e}", style="error")
        return
    httpd.auth_code = None
    httpd.auth_error = None
    httpd.auth_state = None
    httpd.timeout = 120

    t = threading.Thread(target=httpd.handle_request, daemon=True)
    t.start()

    open_url(auth_url)
    toast("Waiting for Spotify authorization in your browser…", style="progress")

    def finish():
        t.join(timeout=125)
        try:
            httpd.server_close()
        except Exception:
            pass
        if httpd.auth_error:
            toast(f"Spotify auth failed: {httpd.auth_error}", style="error")
            return
        if httpd.auth_state != state_token:
            toast("Spotify auth failed: callback state did not match.", style="error")
            return
        code = httpd.auth_code
        if not code:
            toast("Spotify authorization timed out.", style="error")
            return
        try:
            resp = requests.post(TOKEN_URL, data={
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirect_uri,
                "client_id": CONFIG["client_id"],
                "code_verifier": verifier,
            }, timeout=15)
            raise_for_spotify_status(resp)
            tok = resp.json()
        except Exception as e:
            toast(f"Spotify auth error: {e}", style="error")
            return
        global ACCESS_TOKEN, TOKEN_EXPIRY, REFRESH_TOKEN
        ACCESS_TOKEN = tok.get("access_token")
        TOKEN_EXPIRY = time.time() + tok.get("expires_in", 3600) - 60
        REFRESH_TOKEN = tok.get("refresh_token")

        try:
            profile_resp = sp_request("GET", "/me")
            raise_for_spotify_status(profile_resp)
            global USER_PROFILE
            USER_PROFILE = profile_resp.json()
        except Exception as e:
            ACCESS_TOKEN = None
            TOKEN_EXPIRY = 0
            REFRESH_TOKEN = None
            storage_delete("refresh_token", secret=True)
            toast("Spotify connected, but API access was denied.", style="error")
            send({
                "type": "render", "rev": 0, "view": "detail",
                "detail": {"markdown": f"### Spotify access denied\n\n{e}"},
                "actions": [
                    {"id": "open_dashboard", "title": "Open Spotify Developer Dashboard", "icon": "open"},
                    {"id": "retry_connect", "title": "Try connecting again", "icon": "refresh"},
                ],
            })
            return

        if REFRESH_TOKEN:
            storage_set("refresh_token", REFRESH_TOKEN, secret=True)
        toast("Spotify connected!")
        state.clear()
        state["screen"] = "root"
        NAV_STACK.clear()
        render_root(0, "")

    threading.Thread(target=finish, daemon=True).start()


def do_disconnect():
    global REFRESH_TOKEN, ACCESS_TOKEN, TOKEN_EXPIRY, USER_PROFILE
    storage_delete("refresh_token", secret=True)
    REFRESH_TOKEN = None
    ACCESS_TOKEN = None
    TOKEN_EXPIRY = 0
    USER_PROFILE = {}
    toast("Disconnected from Spotify")
    state.clear()
    state["screen"] = "root"
    NAV_STACK.clear()
    render_root(0, "")


def ensure_token():
    global ACCESS_TOKEN, TOKEN_EXPIRY, REFRESH_TOKEN
    with TOKEN_LOCK:
        if ACCESS_TOKEN and time.time() < TOKEN_EXPIRY:
            return ACCESS_TOKEN
        if not REFRESH_TOKEN:
            return None
        try:
            resp = requests.post(TOKEN_URL, data={
                "grant_type": "refresh_token",
                "refresh_token": REFRESH_TOKEN,
                "client_id": CONFIG.get("client_id", ""),
            }, timeout=15)
        except Exception as e:
            log("refresh error:", e)
            return None
        if resp.status_code != 200:
            log("refresh failed:", resp.status_code, resp.text)
            return None
        tok = resp.json()
        ACCESS_TOKEN = tok.get("access_token")
        TOKEN_EXPIRY = time.time() + tok.get("expires_in", 3600) - 60
        if tok.get("refresh_token"):
            REFRESH_TOKEN = tok["refresh_token"]
            storage_set("refresh_token", REFRESH_TOKEN, secret=True)
        return ACCESS_TOKEN


def sp_request(method, path, **kwargs):
    token = ensure_token()
    if not token:
        raise SpotifyAuthError("Not connected to Spotify. Go back and choose \"Connect Spotify Account\".")
    headers = kwargs.pop("headers", {})
    headers["Authorization"] = f"Bearer {token}"
    url = path if path.startswith("http") else API_BASE + path
    resp = requests.request(method, url, headers=headers, timeout=15, **kwargs)
    if resp.status_code == 401:
        global TOKEN_EXPIRY
        TOKEN_EXPIRY = 0
        token = ensure_token()
        if not token:
            raise SpotifyAuthError("Spotify session expired. Please reconnect.")
        headers["Authorization"] = f"Bearer {token}"
        resp = requests.request(method, url, headers=headers, timeout=15, **kwargs)
    if resp.status_code in (403, 429):
        log("Spotify API denied request:", method, path, resp.status_code, resp.text[:500])
        raise SpotifyApiError(spotify_error_message(resp))
    return resp


def get_market():
    global USER_PROFILE
    if not USER_PROFILE:
        try:
            resp = sp_request("GET", "/me")
            if resp.status_code == 200:
                USER_PROFILE = resp.json()
        except Exception:
            pass
    return USER_PROFILE.get("country", "US")


# ------------------------------------------------------- item builders -----

def fmt_duration(ms):
    s = int((ms or 0) // 1000)
    return f"{s // 60}:{s % 60:02d}"


def track_item(track, idx=0, context_uri=None):
    track = track or {}
    artists = ", ".join(a.get("name", "") for a in track.get("artists", []) or [])
    album = (track.get("album") or {}).get("name", "")
    images = (track.get("album") or {}).get("images") or []
    icon = images[-1]["url"] if images else "music"
    uri = track.get("uri", "")
    ext_url = (track.get("external_urls") or {}).get("spotify", "")
    tid = track.get("id") or uri or str(idx)
    item_id = f"track:{tid}:{idx}"
    ITEM_DATA[item_id] = {
        "type": "track", "id": tid, "uri": uri, "url": ext_url,
        "idx": idx, "context_uri": context_uri,
    }
    actions = [{"id": "default", "title": "Play", "icon": "play"}]
    actions.append({"id": "queue", "title": "Add to Queue", "icon": "add"})
    actions.append({"id": "save", "title": "Save to Liked Songs", "icon": "heart"})
    if ext_url:
        actions.append({"id": "open", "title": "Open in Spotify", "icon": "open"})
        actions.append({"id": "copy", "title": "Copy Link", "icon": "copy"})
    preview = {"markdown": f"### {track.get('name', 'Unknown')}\n\n**Artist:** {artists}\n\n**Album:** {album}"}
    if images:
        preview["image"] = {"url": images[0]["url"], "width": 180}
    return {
        "id": item_id,
        "title": track.get("name", "Unknown"),
        "subtitle": f"{artists} — {album}" if album else artists,
        "icon": icon,
        "accessories": [{"text": fmt_duration(track.get("duration_ms", 0))}],
        "actions": actions,
        "preview": preview,
    }


def artist_item(a, idx=0):
    a = a or {}
    images = a.get("images") or []
    icon = images[-1]["url"] if images else "person"
    ext_url = (a.get("external_urls") or {}).get("spotify", "")
    item_id = f"artist:{a.get('id')}:{idx}"
    ITEM_DATA[item_id] = {"type": "artist", "id": a.get("id"), "name": a.get("name", ""), "url": ext_url}
    genres = ", ".join((a.get("genres") or [])[:3])
    followers = (a.get("followers") or {}).get("total")
    return {
        "id": item_id,
        "title": a.get("name", "Unknown"),
        "subtitle": genres or "Artist",
        "icon": icon,
        "section": "Artists",
        "accessories": [{"text": f"{followers:,} followers"}] if followers else [],
        "actions": [
            {"id": "default", "title": "View Top Tracks", "icon": "star"},
            {"id": "open", "title": "Open in Spotify", "icon": "open"},
        ],
        "preview": {"markdown": f"### {a.get('name','')}\n\n{genres}"},
    }


def album_item(al, idx=0):
    al = al or {}
    images = al.get("images") or []
    icon = images[-1]["url"] if images else "music"
    artists = ", ".join(a.get("name", "") for a in al.get("artists", []) or [])
    ext_url = (al.get("external_urls") or {}).get("spotify", "")
    item_id = f"album:{al.get('id')}:{idx}"
    ITEM_DATA[item_id] = {"type": "album", "id": al.get("id"), "name": al.get("name", ""), "uri": al.get("uri", ""), "url": ext_url}
    year = (al.get("release_date") or "")[:4]
    return {
        "id": item_id,
        "title": al.get("name", "Unknown"),
        "subtitle": f"{artists} · {year}" if year else artists,
        "icon": icon,
        "section": "Albums",
        "actions": [
            {"id": "default", "title": "View Tracks", "icon": "open"},
            {"id": "play", "title": "Play Album", "icon": "play"},
            {"id": "open", "title": "Open in Spotify", "icon": "open"},
        ],
        "preview": {"markdown": f"### {al.get('name','')}\n\n**Artist:** {artists}\n\n**Year:** {year}",
                     "image": {"url": images[0]["url"], "width": 180} if images else None},
    }


def playlist_item(pl, idx=0):
    pl = pl or {}
    images = pl.get("images") or []
    icon = images[0]["url"] if images else "list"
    ext_url = (pl.get("external_urls") or {}).get("spotify", "")
    item_id = f"playlist:{pl.get('id')}:{idx}"
    ITEM_DATA[item_id] = {"type": "playlist", "id": pl.get("id"), "name": pl.get("name", ""), "uri": pl.get("uri", ""), "url": ext_url}
    total = (pl.get("items") or pl.get("tracks") or {}).get("total", 0)
    owner = (pl.get("owner") or {}).get("display_name", "")
    return {
        "id": item_id,
        "title": pl.get("name", "Unknown"),
        "subtitle": f"{total} tracks · {owner}" if owner else f"{total} tracks",
        "icon": icon,
        "section": "Playlists",
        "actions": [
            {"id": "default", "title": "View Tracks", "icon": "open"},
            {"id": "play", "title": "Play Playlist", "icon": "play"},
            {"id": "open", "title": "Open in Spotify", "icon": "open"},
        ],
    }


def device_item(d, idx=0):
    d = d or {}
    icon_map = {"Computer": "terminal", "Smartphone": "app", "Speaker": "music", "TV": "window", "GameConsole": "gamepad"}
    icon = icon_map.get(d.get("type", ""), "power")
    item_id = f"device:{d.get('id')}:{idx}"
    ITEM_DATA[item_id] = {"type": "device", "id": d.get("id"), "name": d.get("name", "")}
    vol = d.get("volume_percent")
    return {
        "id": item_id,
        "title": d.get("name", "Unknown device"),
        "subtitle": "Active now" if d.get("is_active") else d.get("type", "Device"),
        "icon": icon,
        "accessories": [{"text": f"{vol}%"}] if vol is not None else [],
        "actions": [{"id": "default", "title": "Switch to this device", "icon": "power"}],
    }


# ---------------------------------------------------- playback actions -----

def play_track(uris=None, context_uri=None, offset=None):
    body = {}
    if context_uri:
        body["context_uri"] = context_uri
        if offset is not None:
            body["offset"] = offset
    elif uris:
        body["uris"] = uris
    try:
        resp = sp_request("PUT", "/me/player/play", json=body)
        if resp.status_code == 404:
            toast("No active Spotify device. Open Spotify on a device first.", style="error")
        elif resp.status_code >= 400:
            toast(f"Playback error ({resp.status_code})", style="error")
        else:
            toast("Playing")
    except SpotifyAuthError as e:
        toast(str(e), style="error")
    except Exception as e:
        toast(f"Error: {e}", style="error")


def add_to_queue(uri):
    try:
        resp = sp_request("POST", "/me/player/queue", params={"uri": uri})
        if resp.status_code in (200, 204):
            toast("Added to queue")
        elif resp.status_code == 404:
            toast("No active device.", style="error")
        else:
            toast(f"Queue error ({resp.status_code})", style="error")
    except Exception as e:
        toast(f"Error: {e}", style="error")


def save_track(track_uri):
    if not track_uri:
        return
    try:
        resp = sp_request("PUT", "/me/library", params={"uris": track_uri})
        if resp.status_code in (200, 204):
            toast("Saved to Liked Songs")
        else:
            toast(spotify_error_message(resp), style="error")
    except Exception as e:
        toast(f"Error: {e}", style="error")


def transfer_playback(device_id, name):
    try:
        resp = sp_request("PUT", "/me/player", json={"device_ids": [device_id], "play": True})
        if resp.status_code in (200, 204):
            toast(f"Switched to {name}")
        else:
            toast(f"Error ({resp.status_code})", style="error")
    except Exception as e:
        toast(f"Error: {e}", style="error")
    go_back()


def toggle_play():
    playing = state.get("_is_playing", False)
    try:
        if playing:
            sp_request("PUT", "/me/player/pause")
        else:
            sp_request("PUT", "/me/player/play", json={})
    except Exception as e:
        toast(f"Error: {e}", style="error")


def adjust_volume(delta):
    cur = state.get("_volume", 50)
    newv = max(0, min(100, cur + delta))
    try:
        sp_request("PUT", "/me/player/volume", params={"volume_percent": newv})
    except Exception as e:
        toast(f"Error: {e}", style="error")


# ------------------------------------------------------------ renders -----

def render_root(rev, query):
    if not CONFIG.get("client_id"):
        send({
            "type": "render", "rev": rev, "view": "detail",
            "detail": {"markdown": SETUP_MARKDOWN},
            "actions": [{"id": "open_dashboard", "title": "Open Spotify Developer Dashboard", "icon": "open"}],
        })
        return

    q = (query or "").strip().lower()
    items = []
    connected = REFRESH_TOKEN is not None

    if not connected:
        items.append({
            "id": "cmd:connect", "title": "Connect Spotify Account",
            "subtitle": "Sign in to search, browse and control playback",
            "icon": "link", "actions": [{"id": "default", "title": "Connect", "icon": "link"}],
        })
        send({"type": "render", "rev": rev, "view": "list", "placeholder": "Connect your Spotify account…",
              "emptyText": "No matches", "items": items})
        return

    if q:
        items.append({
            "id": f"cmd:search:{query}",
            "title": f'Search Spotify for "{query}"',
            "subtitle": "Tracks, artists, albums & playlists",
            "icon": "search",
            "actions": [{"id": "default", "title": "Search", "icon": "search"}],
        })

    entries = [
        ("cmd:search", "Search", "Find tracks, artists, albums, playlists", "search"),
        ("cmd:now_playing", "Now Playing", "See and control what's playing", "play"),
        ("cmd:playlists", "Your Playlists", "Browse your playlists", "list"),
        ("cmd:liked", "Liked Songs", "Your saved tracks", "heart"),
        ("cmd:recent", "Recently Played", "Your listening history", "clock"),
        ("cmd:top_short", "Top Tracks · Last 4 Weeks", "", "star"),
        ("cmd:top_medium", "Top Tracks · Last 6 Months", "", "star"),
        ("cmd:top_long", "Top Tracks · All Time", "", "star"),
        ("cmd:queue", "Queue", "What's playing next", "list"),
        ("cmd:devices", "Devices", "Switch playback device", "power"),
        ("cmd:disconnect", "Disconnect Account", "Sign out of Spotify", "close"),
    ]
    for id_, title, subtitle, icon in entries:
        if q and q not in title.lower():
            continue
        items.append({
            "id": id_, "title": title, "subtitle": subtitle, "icon": icon,
            "actions": [{"id": "default", "title": "Open", "icon": "open"}],
        })

    send({"type": "render", "rev": rev, "view": "list",
          "placeholder": "Search Spotify or type a command…",
          "emptyText": "No matches", "items": items})


def render_search(rev, query):
    q = (query or "").strip()
    if not q:
        send({"type": "render", "rev": rev, "view": "list", "canGoBack": True,
              "placeholder": "Search tracks, artists, albums, playlists…",
              "emptyText": "Type to search Spotify", "items": []})
        return
    try:
        resp = sp_request("GET", "/search", params={"q": q, "type": "track,artist,album,playlist", "limit": 6})
        resp.raise_for_status()
        data = resp.json()
    except SpotifyAuthError as e:
        send({"type": "render", "rev": rev, "view": "detail", "canGoBack": True,
              "detail": {"markdown": f"### Not connected\n\n{e}"}})
        return
    except Exception as e:
        send({"type": "render", "rev": rev, "view": "list", "canGoBack": True,
              "emptyText": f"Search error: {e}", "items": []})
        return

    items = []
    for i, t in enumerate((data.get("tracks") or {}).get("items") or []):
        it = track_item(t, idx=i)
        it["section"] = "Tracks"
        items.append(it)
    for i, a in enumerate((data.get("artists") or {}).get("items") or []):
        items.append(artist_item(a, idx=i))
    for i, al in enumerate((data.get("albums") or {}).get("items") or []):
        items.append(album_item(al, idx=i))
    for i, pl in enumerate((data.get("playlists") or {}).get("items") or []):
        if pl:
            items.append(playlist_item(pl, idx=i))

    send({"type": "render", "rev": rev, "view": "list", "canGoBack": True,
          "placeholder": "Search tracks, artists, albums, playlists…",
          "preview": {"enabled": True}, "emptyText": "No results", "items": items})


def render_now_playing(rev):
    try:
        resp = sp_request("GET", "/me/player")
        if resp.status_code == 204 or not resp.content:
            send({"type": "render", "rev": rev, "view": "detail", "canGoBack": True,
                  "detail": {"markdown": "### Nothing playing\n\nStart playback on a device, then press Refresh."},
                  "actions": [{"id": "refresh", "title": "Refresh", "icon": "refresh"},
                              {"id": "devices", "title": "Devices", "icon": "power"}]})
            return
        data = resp.json()
    except SpotifyAuthError as e:
        send({"type": "render", "rev": rev, "view": "detail", "canGoBack": True,
              "detail": {"markdown": f"### Not connected\n\n{e}"}})
        return
    except Exception as e:
        send({"type": "render", "rev": rev, "view": "detail", "canGoBack": True,
              "detail": {"markdown": f"### Error\n\n{e}"}})
        return

    item = data.get("item") or {}
    is_playing = data.get("is_playing", False)
    progress_ms = data.get("progress_ms", 0) or 0
    duration_ms = item.get("duration_ms", 0) or 1
    device = data.get("device") or {}
    shuffle = data.get("shuffle_state", False)
    repeat = data.get("repeat_state", "off")
    artists = ", ".join(a.get("name", "") for a in item.get("artists", []) or [])
    album = (item.get("album") or {}).get("name", "")
    images = (item.get("album") or {}).get("images") or []
    ext_url = (item.get("external_urls") or {}).get("spotify", "")

    pct = int((progress_ms / duration_ms) * 20) if duration_ms else 0
    bar = "\u2588" * pct + "\u2591" * (20 - pct)
    md = (
        f"# {item.get('name', '—')}\n\n**{artists}**\n{album}\n\n"
        f"`{bar}` {fmt_duration(progress_ms)} / {fmt_duration(duration_ms)}\n\n"
        f"Device: {device.get('name', 'Unknown')} · Shuffle: {'On' if shuffle else 'Off'} · "
        f"Repeat: {repeat.capitalize()}"
    )

    state["_is_playing"] = is_playing
    state["_shuffle"] = shuffle
    state["_repeat"] = repeat
    state["_volume"] = device.get("volume_percent") or 50
    state["_now_url"] = ext_url

    repeat_next_label = {"off": "Repeat: All", "context": "Repeat: One", "track": "Repeat: Off"}.get(repeat, "Repeat")
    actions = [
        {"id": "toggle_play", "title": "Pause" if is_playing else "Play", "icon": "play"},
        {"id": "next", "title": "Next Track", "icon": "run"},
        {"id": "prev", "title": "Previous Track", "icon": "run"},
        {"id": "shuffle", "title": f"Shuffle: {'Off' if shuffle else 'On'}", "icon": "sync"},
        {"id": "repeat", "title": repeat_next_label, "icon": "refresh"},
        {"id": "vol_up", "title": "Volume Up", "icon": "bolt"},
        {"id": "vol_down", "title": "Volume Down", "icon": "bolt"},
        {"id": "queue_view", "title": "View Queue", "icon": "list"},
        {"id": "devices", "title": "Switch Device", "icon": "power"},
        {"id": "refresh", "title": "Refresh", "icon": "refresh"},
    ]
    if ext_url:
        actions.append({"id": "open", "title": "Open in Spotify", "icon": "open"})

    metadata = []
    if images:
        metadata.append({"label": "Album Art", "image": images[0]["url"], "width": 200})

    send({"type": "render", "rev": rev, "view": "detail", "canGoBack": True,
          "detail": {"markdown": md, "metadata": metadata}, "actions": actions})


def render_devices(rev):
    if "devices_cache" not in state:
        try:
            resp = sp_request("GET", "/me/player/devices")
            resp.raise_for_status()
            state["devices_cache"] = resp.json().get("devices", [])
        except Exception as e:
            send({"type": "render", "rev": rev, "view": "detail", "canGoBack": True,
                  "detail": {"markdown": f"### Error loading devices\n\n{e}"}})
            return
    items = [device_item(d, i) for i, d in enumerate(state["devices_cache"])]
    send({"type": "render", "rev": rev, "view": "list", "canGoBack": True,
          "placeholder": "Devices", "emptyText": "No devices found — open Spotify somewhere first.",
          "items": items})


def render_recent(rev):
    if "recent_cache" not in state:
        try:
            resp = sp_request("GET", "/me/player/recently-played", params={"limit": 30})
            resp.raise_for_status()
            state["recent_cache"] = resp.json().get("items", [])
        except Exception as e:
            send({"type": "render", "rev": rev, "view": "detail", "canGoBack": True,
                  "detail": {"markdown": f"### Error\n\n{e}"}})
            return
    items = []
    for i, entry in enumerate(state["recent_cache"]):
        it = track_item(entry.get("track") or {}, idx=i)
        played_at = (entry.get("played_at") or "")[:16].replace("T", " ")
        if played_at:
            it["subtitle"] = f"{it['subtitle']} · {played_at}"
        items.append(it)
    send({"type": "render", "rev": rev, "view": "list", "canGoBack": True,
          "placeholder": "Recently played", "preview": {"enabled": True},
          "emptyText": "No recent history", "items": items})


def render_top(rev):
    rng = state.get("time_range", "medium_term")
    cache_key = f"top_cache_{rng}"
    if cache_key not in state:
        try:
            resp = sp_request("GET", "/me/top/tracks", params={"limit": 30, "time_range": rng})
            resp.raise_for_status()
            state[cache_key] = resp.json().get("items", [])
        except Exception as e:
            send({"type": "render", "rev": rev, "view": "detail", "canGoBack": True,
                  "detail": {"markdown": f"### Error\n\n{e}"}})
            return
    items = [track_item(t, idx=i) for i, t in enumerate(state[cache_key])]
    send({"type": "render", "rev": rev, "view": "list", "canGoBack": True,
          "placeholder": "Top tracks", "preview": {"enabled": True},
          "emptyText": "No top tracks yet", "items": items})


def render_playlists(rev, query=""):
    if "playlists_cache" not in state:
        try:
            resp = sp_request("GET", "/me/playlists", params={"limit": 50})
            resp.raise_for_status()
            state["playlists_cache"] = resp.json().get("items", [])
        except Exception as e:
            send({"type": "render", "rev": rev, "view": "detail", "canGoBack": True,
                  "detail": {"markdown": f"### Error\n\n{e}"}})
            return
    q = (query or "").strip().lower()
    items = []
    for i, pl in enumerate(state["playlists_cache"]):
        if q and q not in (pl.get("name") or "").lower():
            continue
        items.append(playlist_item(pl, idx=i))
    send({"type": "render", "rev": rev, "view": "list", "canGoBack": True,
          "placeholder": "Filter playlists…", "emptyText": "No playlists found", "items": items})


def render_playlist_tracks(rev, query=""):
    pid = state.get("playlist_id")
    cache_key = f"pt_cache_{pid}"
    if cache_key not in state:
        try:
            resp = sp_request("GET", f"/playlists/{pid}/items", params={"limit": 50})
            raise_for_spotify_status(resp)
            state[cache_key] = [
                it.get("item") or it.get("track")
                for it in resp.json().get("items", [])
                if it.get("item") or it.get("track")
            ]
        except Exception as e:
            send({"type": "render", "rev": rev, "view": "detail", "canGoBack": True,
                  "detail": {"markdown": f"### Error\n\n{e}"}})
            return
    tracks = state[cache_key]
    q = (query or "").strip().lower()
    items = []
    for i, t in enumerate(tracks):
        title = (t.get("name") or "").lower()
        artists = ", ".join(a.get("name", "") for a in t.get("artists", []) or []).lower()
        if q and q not in title and q not in artists:
            continue
        items.append(track_item(t, idx=i, context_uri=state.get("playlist_uri")))
    name = state.get("playlist_name", "playlist")
    send({"type": "render", "rev": rev, "view": "list", "canGoBack": True,
          "placeholder": f"Filter {name}…", "preview": {"enabled": True},
          "emptyText": "No tracks", "items": items})


def render_liked(rev, query=""):
    if "liked_cache" not in state:
        try:
            resp = sp_request("GET", "/me/tracks", params={"limit": 50})
            resp.raise_for_status()
            state["liked_cache"] = [it.get("track") for it in resp.json().get("items", []) if it.get("track")]
        except Exception as e:
            send({"type": "render", "rev": rev, "view": "detail", "canGoBack": True,
                  "detail": {"markdown": f"### Error\n\n{e}"}})
            return
    tracks = state["liked_cache"]
    q = (query or "").strip().lower()
    items = []
    for i, t in enumerate(tracks):
        title = (t.get("name") or "").lower()
        artists = ", ".join(a.get("name", "") for a in t.get("artists", []) or []).lower()
        if q and q not in title and q not in artists:
            continue
        items.append(track_item(t, idx=i))
    send({"type": "render", "rev": rev, "view": "list", "canGoBack": True,
          "placeholder": "Filter Liked Songs…", "preview": {"enabled": True},
          "emptyText": "No liked songs", "items": items})


def render_queue(rev):
    if "queue_cache" not in state:
        try:
            resp = sp_request("GET", "/me/player/queue")
            resp.raise_for_status()
            state["queue_cache"] = resp.json()
        except Exception as e:
            send({"type": "render", "rev": rev, "view": "detail", "canGoBack": True,
                  "detail": {"markdown": f"### Error\n\n{e}"}})
            return
    data = state["queue_cache"]
    items = []
    current = data.get("currently_playing")
    if current:
        it = track_item(current, idx=0)
        it["section"] = "Now Playing"
        items.append(it)
    for i, t in enumerate((data.get("queue") or [])[:20]):
        it = track_item(t, idx=i + 1)
        it["section"] = "Up Next"
        items.append(it)
    send({"type": "render", "rev": rev, "view": "list", "canGoBack": True,
          "placeholder": "Queue", "preview": {"enabled": True},
          "emptyText": "Queue is empty", "items": items})


def render_artist_tracks(rev, query=""):
    aid = state.get("artist_id")
    cache_key = f"artist_top_{aid}"
    if cache_key not in state:
        try:
            name = state.get("artist_name", "")
            resp = sp_request("GET", "/search", params={
                "q": f'artist:"{name}"', "type": "track", "limit": 30,
            })
            raise_for_spotify_status(resp)
            tracks = (resp.json().get("tracks") or {}).get("items", [])
            state[cache_key] = [
                track for track in tracks
                if any(artist.get("id") == aid for artist in track.get("artists", []))
            ]
        except Exception as e:
            send({"type": "render", "rev": rev, "view": "detail", "canGoBack": True,
                  "detail": {"markdown": f"### Error\n\n{e}"}})
            return
    items = [track_item(t, idx=i) for i, t in enumerate(state[cache_key])]
    name = state.get("artist_name", "artist")
    send({"type": "render", "rev": rev, "view": "list", "canGoBack": True,
          "placeholder": f"Top tracks · {name}", "preview": {"enabled": True},
          "emptyText": "No tracks found", "items": items})


def render_album_tracks(rev, query=""):
    alid = state.get("album_id")
    cache_key = f"album_tracks_{alid}"
    if cache_key not in state:
        try:
            resp = sp_request("GET", f"/albums/{alid}/tracks", params={"market": get_market(), "limit": 50})
            resp.raise_for_status()
            state[cache_key] = resp.json().get("items", [])
        except Exception as e:
            send({"type": "render", "rev": rev, "view": "detail", "canGoBack": True,
                  "detail": {"markdown": f"### Error\n\n{e}"}})
            return
    items = [track_item(t, idx=i) for i, t in enumerate(state[cache_key])]
    name = state.get("album_name", "album")
    send({"type": "render", "rev": rev, "view": "list", "canGoBack": True,
          "placeholder": f"Tracks · {name}", "preview": {"enabled": True},
          "emptyText": "No tracks found", "items": items})


def dispatch_render(rev, text):
    scr = state.get("screen", "root")
    if scr == "root":
        render_root(rev, text)
    elif scr == "search":
        render_search(rev, text)
    elif scr == "now_playing":
        render_now_playing(rev)
    elif scr == "devices":
        render_devices(rev)
    elif scr == "recent":
        render_recent(rev)
    elif scr == "top":
        render_top(rev)
    elif scr == "playlists":
        render_playlists(rev, text)
    elif scr == "playlist_tracks":
        render_playlist_tracks(rev, text)
    elif scr == "artist_tracks":
        render_artist_tracks(rev, text)
    elif scr == "album_tracks":
        render_album_tracks(rev, text)
    elif scr == "liked":
        render_liked(rev, text)
    elif scr == "queue":
        render_queue(rev)
    else:
        render_root(rev, text)


# --------------------------------------------------------- polling -----

def start_polling():
    global POLL_THREAD
    POLL_STOP.clear()

    def loop():
        while not POLL_STOP.is_set():
            if POLL_STOP.wait(4):
                break
            if state.get("screen") == "now_playing":
                try:
                    render_now_playing(0)
                except Exception:
                    pass

    POLL_THREAD = threading.Thread(target=loop, daemon=True)
    POLL_THREAD.start()


def stop_polling():
    POLL_STOP.set()


# ------------------------------------------------------------ actions -----

def handle_root_command(item_id):
    if item_id == "cmd:connect":
        do_connect()
        return
    if item_id == "cmd:disconnect":
        do_disconnect()
        return
    if item_id.startswith("cmd:search:"):
        q = item_id[len("cmd:search:"):]
        navigate("search")
        send({"type": "render", "rev": 0, "view": "list", "loading": True, "canGoBack": True,
              "placeholder": "Search tracks, artists, albums, playlists…", "items": []})
        send({"type": "command", "command": "setQuery", "text": q})
        return
    if item_id == "cmd:search":
        navigate("search")
        render_search(0, "")
        return
    if item_id == "cmd:now_playing":
        navigate("now_playing")
        render_now_playing(0)
        start_polling()
        return
    if item_id == "cmd:playlists":
        navigate("playlists")
        render_playlists(0, "")
        return
    if item_id == "cmd:liked":
        navigate("liked")
        render_liked(0, "")
        return
    if item_id == "cmd:recent":
        navigate("recent")
        render_recent(0)
        return
    if item_id in ("cmd:top_short", "cmd:top_medium", "cmd:top_long"):
        rng = {"cmd:top_short": "short_term", "cmd:top_medium": "medium_term", "cmd:top_long": "long_term"}[item_id]
        navigate("top", time_range=rng)
        render_top(0)
        return
    if item_id == "cmd:queue":
        navigate("queue")
        render_queue(0)
        return
    if item_id == "cmd:devices":
        navigate("devices")
        render_devices(0)
        return


def handle_frame_action(scr, action):
    if scr == "root" and action == "open_dashboard":
        open_url("https://developer.spotify.com/dashboard")
        return
    if scr == "root" and action == "retry_connect":
        do_connect()
        return
    if scr != "now_playing":
        return
    if action == "toggle_play":
        toggle_play()
    elif action == "next":
        try:
            sp_request("POST", "/me/player/next")
        except Exception as e:
            toast(f"Error: {e}", style="error")
    elif action == "prev":
        try:
            sp_request("POST", "/me/player/previous")
        except Exception as e:
            toast(f"Error: {e}", style="error")
    elif action == "shuffle":
        cur = state.get("_shuffle", False)
        try:
            sp_request("PUT", "/me/player/shuffle", params={"state": str(not cur).lower()})
        except Exception as e:
            toast(f"Error: {e}", style="error")
    elif action == "repeat":
        cur = state.get("_repeat", "off")
        nxt = {"off": "context", "context": "track", "track": "off"}.get(cur, "off")
        try:
            sp_request("PUT", "/me/player/repeat", params={"state": nxt})
        except Exception as e:
            toast(f"Error: {e}", style="error")
    elif action == "vol_up":
        adjust_volume(10)
    elif action == "vol_down":
        adjust_volume(-10)
    elif action == "queue_view":
        navigate("queue")
        render_queue(0)
        return
    elif action == "devices":
        navigate("devices")
        render_devices(0)
        return
    elif action == "open":
        open_url(state.get("_now_url"))
        return
    elif action == "refresh":
        pass
    render_now_playing(0)


def handle_item_action(data, action):
    typ = data.get("type")
    if typ == "track":
        if action == "default":
            if data.get("context_uri"):
                play_track(context_uri=data["context_uri"], offset={"position": data.get("idx", 0)})
            else:
                play_track(uris=[data["uri"]])
        elif action == "queue":
            add_to_queue(data.get("uri", ""))
        elif action == "save":
            save_track(data.get("uri"))
        elif action == "open":
            open_url(data.get("url"))
        elif action == "copy":
            send({"type": "command", "command": "copy", "text": data.get("url", "")})
    elif typ == "artist":
        if action == "default":
            navigate("artist_tracks", artist_id=data["id"], artist_name=data["name"])
            render_artist_tracks(0, "")
        elif action == "open":
            open_url(data.get("url"))
    elif typ == "album":
        if action == "default":
            navigate("album_tracks", album_id=data["id"], album_name=data["name"])
            render_album_tracks(0, "")
        elif action == "play":
            play_track(context_uri=data["uri"])
        elif action == "open":
            open_url(data.get("url"))
    elif typ == "playlist":
        if action == "default":
            navigate("playlist_tracks", playlist_id=data["id"], playlist_name=data["name"], playlist_uri=data["uri"])
            render_playlist_tracks(0, "")
        elif action == "play":
            play_track(context_uri=data["uri"])
        elif action == "open":
            open_url(data.get("url"))
    elif typ == "device":
        if action == "default":
            transfer_playback(data["id"], data["name"])


def handle_action(item_id, action):
    try:
        if item_id.startswith("cmd:"):
            handle_root_command(item_id)
            return
        if item_id == "":
            handle_frame_action(state.get("screen", "root"), action)
            return
        data = ITEM_DATA.get(item_id)
        if not data:
            return
        handle_item_action(data, action)
    except Exception as e:
        log("action error:", e)
        toast(f"Error: {e}", style="error")


# --------------------------------------------------------------- main -----

def main():
    if requests is None:
        send({"type": "render", "rev": 0, "view": "detail",
              "detail": {"markdown": "### Missing dependency\n\nThe `requests` package failed to install."}})

    while True:
        line = sys.stdin.readline()
        if not line:
            break
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        t = msg.get("type")
        if t == "close":
            break
        elif t == "init":
            load_credentials()
            dispatch_render(msg.get("rev", 0), msg.get("text", msg.get("query", "")))
        elif t in ("query", "submitQuery"):
            dispatch_render(msg.get("rev", 0), msg.get("text", ""))
        elif t == "action":
            handle_action(msg.get("id", ""), msg.get("action", "default"))
        elif t == "back":
            go_back()
        # select / tab / loadMore / storage / clipboard: not used

    stop_polling()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        log("fatal:", e)
