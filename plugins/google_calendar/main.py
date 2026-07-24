#!/usr/bin/env python3
"""
Google Calendar plugin for Tabame.

Setup (one-time, per user):
  1. In Google Cloud Console, create a project, enable the "Google Calendar API",
     and create an OAuth Client ID of type "Desktop app".
  2. Download the client secret JSON and save it in this plugin's folder as
     "client_secret.json".
  3. Type `cal` in the launcher and pick "Connect Google Calendar" — a browser
     window opens for you to sign in. The token is then stored securely via
     Tabame's storage command (Windows Credential Manager), not on disk.

Usage once connected:
  cal                      -> upcoming events (next 14 days)
  cal <text>                -> search events matching <text>
  cal add <free text>       -> quick-add an event via Google's natural language
                                parser, e.g. "cal add Lunch with Bob tomorrow 1pm"
  Enter on an event         -> open it in Google Calendar (browser)
  Ctrl+K on an event        -> Copy link / Delete
  Ctrl+K (frame)             -> Refresh / Sign out
"""

import datetime
import json
import os
import sys
import threading
import uuid


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# Lazy import of Google libraries so a missing/failed pip install still lets
# the process speak the protocol well enough to show a helpful error instead
# of crashing silently.
# ---------------------------------------------------------------------------
GOOGLE_IMPORT_ERROR = None
try:
    from google.auth.transport.requests import Request as GoogleRequest
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from googleapiclient.discovery import build
    from googleapiclient.errors import HttpError
except Exception as e:  # pragma: no cover
    GOOGLE_IMPORT_ERROR = str(e)

SCOPES = ["https://www.googleapis.com/auth/calendar"]
CLIENT_SECRET_FILE = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "client_secret.json"
)
TOKEN_KEY = "token"
CALENDAR_ID = "primary"
UPCOMING_DAYS = 14
MAX_RESULTS = 20

# ---------------------------------------------------------------------------
# Protocol plumbing
# ---------------------------------------------------------------------------
_out_lock = threading.Lock()


def send(frame):
    with _out_lock:
        sys.stdout.write(json.dumps(frame) + "\n")
        sys.stdout.flush()


_pending_lock = threading.Lock()
_pending = {}  # requestId -> {"event": Event, "value": Any}


def storage_get(key, secret=False, timeout=5.0):
    req_id = uuid.uuid4().hex
    ev = threading.Event()
    with _pending_lock:
        _pending[req_id] = {"event": ev, "value": None}
    send(
        {
            "type": "command",
            "command": "storage",
            "op": "get",
            "key": key,
            "secret": secret,
            "requestId": req_id,
        }
    )
    got = ev.wait(timeout)
    with _pending_lock:
        entry = _pending.pop(req_id, None)
    if not got or not entry:
        return None
    return entry["value"]


def storage_set(key, value_obj, secret=False):
    send(
        {
            "type": "command",
            "command": "storage",
            "op": "set",
            "key": key,
            "value": json.dumps(value_obj),
            "secret": secret,
        }
    )


def storage_delete(key, secret=False):
    send(
        {
            "type": "command",
            "command": "storage",
            "op": "delete",
            "key": key,
            "secret": secret,
        }
    )


def toast(text, style="info"):
    send({"type": "command", "command": "toast", "text": text, "style": style})


# Track the most recent query so background threads (OAuth, actions) know
# what to re-render, and so a slow response can bail out if it's gone stale.
_state_lock = threading.Lock()
_state = {"rev": 0, "text": "", "events_by_id": {}}


def is_stale(rev):
    if rev == 0:
        return False
    with _state_lock:
        return rev != _state["rev"]


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------
def load_credentials():
    raw = storage_get(TOKEN_KEY, secret=True)
    if not raw:
        return None
    try:
        data = json.loads(raw)
    except Exception:
        return None
    try:
        creds = Credentials(
            token=data.get("token"),
            refresh_token=data.get("refresh_token"),
            token_uri=data.get("token_uri"),
            client_id=data.get("client_id"),
            client_secret=data.get("client_secret"),
            scopes=data.get("scopes") or SCOPES,
        )
    except Exception as e:
        log("bad stored credentials:", e)
        return None
    if creds.expired and creds.refresh_token:
        try:
            creds.refresh(GoogleRequest())
            save_credentials(creds)
        except Exception as e:
            log("token refresh failed:", e)
            return None
    return creds


def save_credentials(creds):
    storage_set(
        TOKEN_KEY,
        {
            "token": creds.token,
            "refresh_token": creds.refresh_token,
            "token_uri": creds.token_uri,
            "client_id": creds.client_id,
            "client_secret": creds.client_secret,
            "scopes": list(creds.scopes) if creds.scopes else SCOPES,
        },
        secret=True,
    )


def get_service():
    creds = load_credentials()
    if not creds:
        return None
    return build("calendar", "v3", credentials=creds, cache_discovery=False)


def run_oauth_flow():
    if not os.path.exists(CLIENT_SECRET_FILE):
        toast(
            "Missing client_secret.json in the plugin folder — see setup instructions",
            "error",
        )
        render_events(0, _state["text"])
        return
    try:
        toast("Opening your browser to sign in to Google…", "progress")
        flow = InstalledAppFlow.from_client_secrets_file(CLIENT_SECRET_FILE, SCOPES)
        creds = flow.run_local_server(port=0, open_browser=True)
        save_credentials(creds)
        toast("Connected to Google Calendar", "success")
    except Exception as e:
        log("oauth error:", e)
        toast(f"Sign-in failed: {e}", "error")
    render_events(0, _state["text"])


def sign_out():
    storage_delete(TOKEN_KEY, secret=True)
    with _state_lock:
        _state["events_by_id"] = {}
    toast("Signed out of Google Calendar")
    render_events(0, _state["text"])


# ---------------------------------------------------------------------------
# Formatting
# ---------------------------------------------------------------------------
def parse_event_dt(node):
    if not node:
        return None, False
    if "date" in node:
        return datetime.date.fromisoformat(node["date"]), True
    if "dateTime" in node:
        return datetime.datetime.fromisoformat(node["dateTime"]), False
    return None, False


def day_label(d):
    today = (
        d
        if isinstance(d, datetime.date) and not isinstance(d, datetime.datetime)
        else d.date()
    )
    now_today = datetime.date.today()
    if today == now_today:
        return "Today"
    if today == now_today + datetime.timedelta(days=1):
        return "Tomorrow"
    return d.strftime("%a, %b %d")


def format_when(ev):
    s, s_all_day = parse_event_dt(ev.get("start"))
    e, _ = parse_event_dt(ev.get("end"))
    if s is None:
        return "", "Later"
    label = day_label(s)
    if s_all_day:
        return f"{label} · All day", label
    time_str = s.strftime("%H:%M")
    if e:
        time_str += f"\u2013{e.strftime('%H:%M')}"
    return f"{label} · {time_str}", label


def build_item(ev):
    title = ev.get("summary") or "(No title)"
    subtitle, section = format_when(ev)
    accessories = []
    loc = ev.get("location")
    if loc:
        accessories.append({"text": loc, "icon": "location"})
    if ev.get("attendees"):
        accessories.append({"text": f"{len(ev['attendees'])} guests", "icon": "person"})

    meta = []
    if ev.get("location"):
        meta.append({"label": "Location", "text": ev["location"], "icon": "location"})
    if ev.get("organizer", {}).get("email"):
        meta.append(
            {"label": "Organizer", "text": ev["organizer"]["email"], "icon": "person"}
        )
    if ev.get("attendees"):
        names = ", ".join(a.get("email", "") for a in ev["attendees"][:6])
        meta.append({"label": "Guests", "text": names})
    if ev.get("htmlLink"):
        meta.append(
            {"label": "Link", "text": "Open in Google Calendar", "url": ev["htmlLink"]}
        )

    desc = ev.get("description") or "_No description._"
    preview_md = f"## {title}\n\n{desc}"

    return {
        "id": ev["id"],
        "title": title,
        "subtitle": subtitle,
        "icon": "calendar",
        "section": section,
        "accessories": accessories,
        "actions": [
            {"id": "open", "title": "Open in Google Calendar", "icon": "open"},
            {"id": "copy", "title": "Copy link", "icon": "copy"},
            {
                "id": "delete",
                "title": "Delete event",
                "icon": "trash",
                "destructive": True,
                "confirm": {
                    "title": "Delete this event?",
                    "message": title,
                    "confirmLabel": "Delete",
                },
            },
        ],
        "preview": {"markdown": preview_md, "metadata": meta},
    }


FRAME_ACTIONS = [
    {"id": "refresh", "title": "Refresh", "icon": "refresh"},
    {
        "id": "signout",
        "title": "Sign out of Google Calendar",
        "icon": "lock",
        "confirm": {
            "title": "Sign out?",
            "message": "You'll need to reconnect to see events again.",
            "confirmLabel": "Sign out",
        },
    },
]


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
def render_connect_prompt(rev):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "items": [],
            "empty": {
                "icon": "lock",
                "title": "Not connected",
                "hint": "Connect your Google account to see and manage your calendar.",
                "action": {
                    "id": "connect",
                    "title": "Connect Google Calendar",
                    "icon": "link",
                },
            },
            "actions": [
                {"id": "connect", "title": "Connect Google Calendar", "icon": "link"}
            ],
        }
    )


def render_missing_deps(rev):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "detail": {
                "markdown": (
                    "# Google Calendar plugin\n\n"
                    "Required Python packages failed to load:\n\n"
                    f"```\n{GOOGLE_IMPORT_ERROR}\n```\n\n"
                    "Check that `pip` is available on PATH so Tabame can install "
                    "`google-auth`, `google-auth-oauthlib` and `google-api-python-client`."
                )
            },
        }
    )


def render_setup_help(rev):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "detail": {
                "markdown": (
                    "# Set up Google Calendar\n\n"
                    "1. In [Google Cloud Console](https://console.cloud.google.com/apis/credentials), "
                    "create a project and enable the **Google Calendar API**.\n"
                    "2. Create an **OAuth Client ID** of type **Desktop app**.\n"
                    "3. Add yourself as Test user under APIs & Serv -> OAuth Cons. -> Audience \n"
                    "4. Download the client secret JSON and save it in this plugin's folder as "
                    "`client_secret.json`.\n"
                    "5. Come back and type `cal` again, then choose **Connect Google Calendar**."
                )
            },
        }
    )


def render_error(rev, message):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "items": [],
            "empty": {
                "icon": "error",
                "title": "Something went wrong",
                "hint": message,
            },
            "actions": FRAME_ACTIONS,
        }
    )


def render_events(rev, text):
    if is_stale(rev):
        return

    if GOOGLE_IMPORT_ERROR:
        render_missing_deps(rev)
        return

    if not os.path.exists(CLIENT_SECRET_FILE):
        render_setup_help(rev)
        return

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "items": [],
            "loading": True,
            "loadingText": "Loading calendar…",
        }
    )

    try:
        service = get_service()
    except Exception as e:
        log("get_service failed:", e)
        render_error(rev, str(e))
        return

    if service is None:
        render_connect_prompt(rev)
        return

    if is_stale(rev):
        return

    try:
        if text.strip().lower().startswith("add "):
            quick_text = text.strip()[4:].strip()
            if not quick_text:
                send(
                    {
                        "type": "render",
                        "rev": rev,
                        "view": "list",
                        "items": [],
                        "emptyText": 'Type what to add, e.g. "add Lunch with Bob tomorrow 1pm"',
                    }
                )
                return
            ev = (
                service.events()
                .quickAdd(calendarId=CALENDAR_ID, text=quick_text)
                .execute()
            )
            with _state_lock:
                _state["events_by_id"][ev["id"]] = ev
            toast(f"Added: {ev.get('summary', quick_text)}", "success")
            send(
                {
                    "type": "render",
                    "rev": 0,
                    "view": "list",
                    "items": [build_item(ev)],
                    "preview": {"enabled": True},
                    "actions": FRAME_ACTIONS,
                }
            )
            return

        now_iso = datetime.datetime.utcnow().isoformat() + "Z"
        kwargs = dict(
            calendarId=CALENDAR_ID,
            timeMin=now_iso,
            maxResults=MAX_RESULTS,
            singleEvents=True,
            orderBy="startTime",
        )
        query = text.strip()
        if query:
            kwargs["q"] = query
        else:
            time_max = (
                datetime.datetime.utcnow() + datetime.timedelta(days=UPCOMING_DAYS)
            ).isoformat() + "Z"
            kwargs["timeMax"] = time_max

        result = service.events().list(**kwargs).execute()
        events = result.get("items", [])

        if is_stale(rev):
            return

        with _state_lock:
            _state["events_by_id"] = {ev["id"]: ev for ev in events}

        items = [build_item(ev) for ev in events]
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "list",
                "items": items,
                "preview": {"enabled": True},
                "placeholder": 'Search events, or "add <text>" to create one…',
                "emptyText": "No upcoming events"
                if not query
                else f'No events matching "{query}"',
                "actions": FRAME_ACTIONS,
            }
        )
    except HttpError as e:
        log("HttpError:", e)
        render_error(rev, f"Google Calendar API error: {e}")
    except Exception as e:
        log("render_events failed:", e)
        render_error(rev, str(e))


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
def handle_action(item_id, action):
    if action == "connect" or (item_id == "" and action == "connect"):
        threading.Thread(target=run_oauth_flow, daemon=True).start()
        return
    if item_id == "" and action == "refresh":
        render_events(0, _state["text"])
        return
    if item_id == "" and action == "signout":
        threading.Thread(target=sign_out, daemon=True).start()
        return

    with _state_lock:
        ev = _state["events_by_id"].get(item_id)
    if not ev:
        return

    if action in ("default", "open"):
        link = ev.get("htmlLink")
        if link:
            send({"type": "command", "command": "open", "url": link})
        return

    if action == "copy":
        link = ev.get("htmlLink", "")
        send({"type": "command", "command": "copy", "text": link})
        return

    if action == "delete":

        def do_delete():
            try:
                service = get_service()
                if service is None:
                    toast("Not connected", "error")
                    return
                service.events().delete(
                    calendarId=CALENDAR_ID, eventId=ev["id"]
                ).execute()
                with _state_lock:
                    _state["events_by_id"].pop(ev["id"], None)
                toast("Event deleted", "success")
            except Exception as e:
                log("delete failed:", e)
                toast(f"Delete failed: {e}", "error")
            render_events(0, _state["text"])

        threading.Thread(target=do_delete, daemon=True).start()
        return


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
def main():
    for line in sys.stdin:
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

        elif t in ("init", "query"):
            text = msg.get("text", msg.get("query", ""))
            rev = msg.get("rev", 0)
            with _state_lock:
                _state["rev"] = rev
                _state["text"] = text
            threading.Thread(
                target=render_events, args=(rev, text), daemon=True
            ).start()

        elif t == "action":
            item_id = msg.get("id", "")
            action = msg.get("action", "default")
            handle_action(item_id, action)

        elif t == "storage":
            req_id = msg.get("requestId")
            if req_id:
                with _pending_lock:
                    entry = _pending.get(req_id)
                if entry:
                    entry["value"] = msg.get("value")
                    entry["event"].set()

        # select / tab / back / loadMore: not used by this plugin

    sys.exit(0)


if __name__ == "__main__":
    main()
