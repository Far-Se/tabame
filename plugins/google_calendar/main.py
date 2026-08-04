#!/usr/bin/env python3
"""A practical Google Calendar plugin for the Tabame launcher.

The launcher and this process exchange newline-delimited JSON over stdin/stdout.
All Google API work runs on worker threads so storage replies and lifecycle
messages can still be handled by the main stdin loop.
"""

import base64
import datetime as dt
import hashlib
import json
import os
import re
import secrets
import sys
import threading
import uuid
from urllib.parse import quote


def log(*parts):
    print(*parts, file=sys.stderr, flush=True)


_OUT_LOCK = threading.Lock()


def send(message):
    with _OUT_LOCK:
        sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def toast(text, style="info"):
    send({"type": "command", "command": "toast", "text": text, "style": style})


BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CLIENT_SECRET_FILE = os.path.join(BASE_DIR, "client_secret.json")
README_FILE = os.path.join(BASE_DIR, "README.md")
SCOPES = ["https://www.googleapis.com/auth/calendar"]
TOKEN_KEY = "google-calendar-token"
AGENDA_DAYS = 30
MAX_RESULTS_PER_CALENDAR = 2500
DEFAULT_COLOR = "#4285F4"
TIME_PATTERN = r"^([01]\d|2[0-3]):[0-5]\d$"


GOOGLE_IMPORT_ERROR = None
try:
    from google.auth.transport.requests import Request as GoogleRequest
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import Flow
    from googleapiclient.discovery import build
    from googleapiclient.errors import HttpError
except Exception as error:  # pragma: no cover - exercised by a real install
    GOOGLE_IMPORT_ERROR = str(error)
    HttpError = Exception


_STATE_LOCK = threading.RLock()
_STATE = {
    "rev": 0,
    "query": "",
    "mode": "month",
    "date": dt.date.today().isoformat(),
    "screen": "calendar",
    "events": {},
    "calendars": [],
    "load_generation": 0,
    "detail_event_id": None,
    "form_event_id": None,
    "service": None,
    "oauth_nonce": None,
    "oauth_verifier": None,
}

_SERVICE_LOCK = threading.Lock()
_API_LOCK = threading.Lock()
_PENDING_LOCK = threading.Lock()
_PENDING = {}


def storage_get(key, secret=False, timeout=8.0):
    request_id = uuid.uuid4().hex
    ready = threading.Event()
    with _PENDING_LOCK:
        _PENDING[request_id] = {"event": ready, "value": None}
    send(
        {
            "type": "command",
            "command": "storage",
            "op": "get",
            "key": key,
            "secret": secret,
            "requestId": request_id,
        }
    )
    received = ready.wait(timeout)
    with _PENDING_LOCK:
        result = _PENDING.pop(request_id, None)
    if not received or result is None:
        return None
    return result["value"]


def storage_set(key, value, secret=False):
    send(
        {
            "type": "command",
            "command": "storage",
            "op": "set",
            "key": key,
            "value": value,
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


def save_credentials(credentials):
    payload = {
        "token": credentials.token,
        "refresh_token": credentials.refresh_token,
        "token_uri": credentials.token_uri,
        "client_id": credentials.client_id,
        "client_secret": credentials.client_secret,
        "scopes": list(credentials.scopes or SCOPES),
    }
    storage_set(TOKEN_KEY, json.dumps(payload), secret=True)


def load_credentials():
    raw = storage_get(TOKEN_KEY, secret=True)
    if not raw:
        return None
    try:
        values = json.loads(raw)
        credentials = Credentials(
            token=values.get("token"),
            refresh_token=values.get("refresh_token"),
            token_uri=values.get("token_uri"),
            client_id=values.get("client_id"),
            client_secret=values.get("client_secret"),
            scopes=values.get("scopes") or SCOPES,
        )
        if credentials.expired and credentials.refresh_token:
            credentials.refresh(GoogleRequest())
            save_credentials(credentials)
        return credentials if credentials.valid else None
    except Exception as error:
        log("Could not load Google credentials:", error)
        return None


def get_service():
    with _STATE_LOCK:
        cached = _STATE["service"]
    if cached is not None:
        return cached

    with _SERVICE_LOCK:
        with _STATE_LOCK:
            cached = _STATE["service"]
        if cached is not None:
            return cached
        credentials = load_credentials()
        if credentials is None:
            return None
        service = build("calendar", "v3", credentials=credentials, cache_discovery=False)
        with _STATE_LOCK:
            _STATE["service"] = service
        return service


def read_client_config():
    with open(CLIENT_SECRET_FILE, encoding="utf-8") as source:
        payload = json.load(source)
    config = payload.get("installed") or payload.get("web")
    if not isinstance(config, dict) or not config.get("client_id"):
        raise ValueError("client_secret.json is not a Google OAuth client file")
    return config


def begin_oauth_flow():
    if not os.path.exists(CLIENT_SECRET_FILE):
        render_setup_help(0)
        return
    try:
        config = read_client_config()
        nonce = uuid.uuid4().hex
        verifier = secrets.token_urlsafe(64)
        challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode("ascii")).digest()).decode("ascii")
        challenge = challenge.rstrip("=")
        with _STATE_LOCK:
            _STATE["oauth_nonce"] = nonce
            _STATE["oauth_verifier"] = verifier
        auth_uri = config.get("auth_uri") or "https://accounts.google.com/o/oauth2/auth"
        authorization_url = (
            f"{auth_uri}?client_id={quote(config['client_id'], safe='')}"
            "&redirect_uri={redirectUri}"
            "&response_type=code"
            f"&scope={quote(' '.join(SCOPES), safe='')}"
            "&access_type=offline"
            "&prompt=consent"
            f"&code_challenge={challenge}"
            "&code_challenge_method=S256"
            f"&state={nonce}.{{redirectUri}}"
        )
        send(
            {
                "type": "command",
                "command": "oauth",
                "requestId": "google-calendar-oauth",
                "authorizationUrl": authorization_url,
                "timeout": 300,
            }
        )
        toast("Complete sign-in in your browser…", "progress")
    except Exception as error:
        log("Could not start OAuth:", error)
        with _STATE_LOCK:
            _STATE["oauth_nonce"] = None
            _STATE["oauth_verifier"] = None
        toast(f"Could not start sign-in: {error}", "error")
        render_connect_prompt(0)


def handle_oauth(message):
    if message.get("requestId") != "google-calendar-oauth":
        return
    if message.get("error"):
        with _STATE_LOCK:
            _STATE["oauth_nonce"] = None
            _STATE["oauth_verifier"] = None
        toast(f"Sign-in failed: {message['error']}", "error")
        render_connect_prompt(0)
        return
    code = message.get("code")
    state = str(message.get("state") or "")
    with _STATE_LOCK:
        nonce = _STATE.get("oauth_nonce")
        verifier = _STATE.get("oauth_verifier")
        _STATE["oauth_nonce"] = None
        _STATE["oauth_verifier"] = None
    prefix = f"{nonce}." if nonce else ""
    if not code or not prefix or not verifier or not state.startswith(prefix):
        toast("Google sign-in returned an invalid callback", "error")
        render_connect_prompt(0)
        return
    redirect_uri = state[len(prefix) :]

    def exchange():
        try:
            flow = Flow.from_client_secrets_file(
                CLIENT_SECRET_FILE,
                scopes=SCOPES,
                state=state,
                code_verifier=verifier,
            )
            flow.redirect_uri = redirect_uri
            flow.fetch_token(code=code)
            save_credentials(flow.credentials)
            with _STATE_LOCK:
                _STATE["service"] = None
            toast("Google Calendar connected", "success")
            start_calendar_load(0)
        except Exception as error:
            log("OAuth token exchange failed:", error)
            toast(f"Sign-in failed: {error}", "error")
            render_connect_prompt(0)

    threading.Thread(target=exchange, daemon=True).start()


def sign_out():
    storage_delete(TOKEN_KEY, secret=True)
    with _STATE_LOCK:
        _STATE["service"] = None
        _STATE["events"] = {}
        _STATE["calendars"] = []
    toast("Signed out of Google Calendar", "success")
    render_connect_prompt(0)


def parse_date(value, fallback=None):
    try:
        return dt.date.fromisoformat(str(value))
    except (TypeError, ValueError):
        return fallback or dt.date.today()


def local_timezone():
    return dt.datetime.now().astimezone().tzinfo


def as_google_boundary(day):
    value = dt.datetime.combine(day, dt.time.min, tzinfo=local_timezone())
    return value.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def parse_google_time(node):
    if not node:
        return None, False
    if node.get("date"):
        return dt.date.fromisoformat(node["date"]), True
    raw = node.get("dateTime")
    if not raw:
        return None, False
    value = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    if value.tzinfo is not None:
        value = value.astimezone()
    return value, False


def host_datetime(value):
    """Send local wall-clock values because the calendar host displays them as-is."""
    if isinstance(value, dt.datetime):
        if value.tzinfo is not None:
            value = value.astimezone().replace(tzinfo=None)
        return value.isoformat(timespec="seconds")
    return value.isoformat()


def event_url(event):
    return event.get("htmlLink") or ""


def conference_url(event):
    if event.get("hangoutLink"):
        return event["hangoutLink"]
    for entry in event.get("conferenceData", {}).get("entryPoints", []):
        if entry.get("entryPointType") == "video" and entry.get("uri"):
            return entry["uri"]
    return ""


def calendar_options(calendars=None):
    if calendars is None:
        with _STATE_LOCK:
            calendars = list(_STATE["calendars"])
    if not calendars:
        return [{"value": "primary", "label": "Primary calendar"}]
    writable = [calendar for calendar in calendars if calendar.get("writable", True)]
    if not writable:
        return [{"value": "primary", "label": "Primary calendar"}]
    return [
        {
            "value": calendar["id"],
            "label": calendar["summary"] + (" (primary)" if calendar.get("primary") else ""),
        }
        for calendar in writable
    ]


def selected_calendars(service):
    calendars = []
    page_token = None
    while True:
        arguments = {"pageToken": page_token} if page_token else {}
        response = service.calendarList().list(**arguments).execute()
        for item in response.get("items", []):
            if item.get("primary") or item.get("selected"):
                calendars.append(
                    {
                        "id": item["id"],
                        "summary": item.get("summaryOverride") or item.get("summary") or item["id"],
                        "color": item.get("backgroundColor") or DEFAULT_COLOR,
                        "primary": bool(item.get("primary")),
                        "writable": item.get("accessRole") in {"writer", "owner"},
                    }
                )
        page_token = response.get("nextPageToken")
        if not page_token:
            break
    calendars.sort(key=lambda item: (not item["primary"], item["summary"].casefold()))
    return calendars or [
        {
            "id": "primary",
            "summary": "Primary calendar",
            "color": DEFAULT_COLOR,
            "primary": True,
            "writable": True,
        }
    ]


def visible_range(anchor, mode):
    if mode == "agenda":
        return anchor, anchor + dt.timedelta(days=AGENDA_DAYS)
    month_start = anchor.replace(day=1)
    leading = month_start.weekday()
    start = month_start - dt.timedelta(days=leading)
    return start, start + dt.timedelta(days=42)


def fetch_events(service, anchor, mode, query):
    calendars = selected_calendars(service)
    range_start, range_end = visible_range(anchor, mode)
    wrappers = []
    for calendar in calendars:
        try:
            page_token = None
            while True:
                arguments = {
                    "calendarId": calendar["id"],
                    "timeMin": as_google_boundary(range_start),
                    "timeMax": as_google_boundary(range_end),
                    "singleEvents": True,
                    "orderBy": "startTime",
                    "showDeleted": False,
                    "maxResults": MAX_RESULTS_PER_CALENDAR,
                }
                if page_token:
                    arguments["pageToken"] = page_token
                if query:
                    arguments["q"] = query
                response = service.events().list(**arguments).execute()
                for event in response.get("items", []):
                    if event.get("status") != "cancelled" and event.get("start"):
                        item_id = f"event:{calendar['id']}:{event['id']}"
                        wrappers.append(
                            {
                                "id": item_id,
                                "calendar_id": calendar["id"],
                                "calendar_name": calendar["summary"],
                                "color": calendar["color"],
                                "writable": calendar["writable"],
                                "event": event,
                            }
                        )
                page_token = response.get("nextPageToken")
                if not page_token:
                    break
        except HttpError as error:
            if calendar["primary"]:
                raise
            log(f"Skipping calendar {calendar['summary']}:", error)
    wrappers.sort(key=event_sort_key)
    return calendars, wrappers


def event_sort_key(wrapper):
    start, _ = parse_google_time(wrapper["event"].get("start"))
    if isinstance(start, dt.date) and not isinstance(start, dt.datetime):
        return dt.datetime.combine(start, dt.time.min)
    if isinstance(start, dt.datetime):
        return start.replace(tzinfo=None)
    return dt.datetime.max


def event_item(wrapper):
    event = wrapper["event"]
    start, all_day = parse_google_time(event.get("start"))
    end, _ = parse_google_time(event.get("end"))
    title = event.get("summary") or "(Untitled event)"
    location = event.get("location") or ""
    join_url = conference_url(event)
    actions = [
        {"id": "default", "title": "View details", "icon": "info"},
        {"id": "open", "title": "Open in Google Calendar", "icon": "open"},
    ]
    if join_url:
        actions.append(
            {"id": "join", "title": "Join meeting", "icon": "video", "shortcut": "ctrl+j"}
        )
    if wrapper["writable"]:
        actions.append({"id": "edit", "title": "Edit event", "icon": "edit"})
    actions.append({"id": "copy-details", "title": "Copy event details", "icon": "copy"})
    if wrapper["writable"]:
        actions.append(
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
            }
        )
    item = {
        "id": wrapper["id"],
        "title": title,
        "subtitle": wrapper["calendar_name"],
        "icon": "calendar",
        "start": host_datetime(start),
        "allDay": all_day,
        "color": wrapper["color"],
        "actions": actions,
    }
    if end is not None:
        item["end"] = host_datetime(end)
    if location:
        item["location"] = location
    return item


def frame_actions(calendars=None):
    return [
        {"id": "new", "title": "New event", "icon": "add", "shortcut": "ctrl+n"},
        {
            "id": "quick-add",
            "title": "Quick add with natural language",
            "icon": "bolt",
            "parameters": [
                {
                    "id": "text",
                    "type": "text",
                    "label": "Event",
                    "placeholder": "Lunch with Alex tomorrow at 1pm",
                    "required": True,
                },
                {
                    "id": "calendar",
                    "type": "dropdown",
                    "label": "Calendar",
                    "required": True,
                    "value": calendar_options(calendars)[0]["value"],
                    "options": calendar_options(calendars),
                },
            ],
        },
        {"id": "refresh", "title": "Refresh calendars", "icon": "refresh", "shortcut": "ctrl+r"},
        {"id": "open-calendar", "title": "Open Google Calendar", "icon": "open"},
        {
            "id": "signout",
            "title": "Sign out",
            "icon": "lock",
            "destructive": True,
            "confirm": {
                "title": "Sign out of Google Calendar?",
                "message": "Your cached credential will be removed from Windows Credential Manager.",
                "confirmLabel": "Sign out",
            },
        },
    ]


def calendar_frame(rev, items, anchor, mode, query, calendars=None, loading=False, select_id=None):
    frame = {
        "type": "render",
        "rev": rev,
        "view": "calendar",
        "page": {"id": "gcal:calendar", "title": "Google Calendar", "history": "replace", "preserveState": True},
        "elementId": "google-calendar",
        "calendar": {
            "mode": mode,
            "date": anchor.isoformat(),
            "weekStart": "monday",
            "days": AGENDA_DAYS,
        },
        "placeholder": "Filter this date range…",
        "items": items,
        "actions": frame_actions(calendars),
        "loading": loading,
        "loadingText": "Loading Google Calendar…",
        "emptyText": f'No events matching "{query}"' if query else "No events in this date range",
    }
    if select_id:
        frame["selectId"] = select_id
    send(frame)


def query_parts(text):
    stripped = text.strip()
    lowered = stripped.casefold()
    if lowered == "agenda":
        return "agenda", ""
    if lowered.startswith("agenda "):
        return "agenda", stripped[7:].strip()
    if lowered == "month":
        return "month", ""
    if lowered.startswith("month "):
        return "month", stripped[6:].strip()
    return None, stripped


def start_calendar_load(rev, text=None, mode=None, date_value=None, select_id=None):
    if GOOGLE_IMPORT_ERROR:
        render_missing_dependencies(rev)
        return
    if not os.path.exists(CLIENT_SECRET_FILE):
        render_setup_help(rev)
        return

    with _STATE_LOCK:
        if text is not None:
            requested_mode, search_query = query_parts(text)
            _STATE["query"] = search_query
            if requested_mode:
                _STATE["mode"] = requested_mode
        if mode in {"month", "agenda"}:
            _STATE["mode"] = mode
        if date_value is not None:
            _STATE["date"] = parse_date(date_value).isoformat()
        _STATE["rev"] = rev
        _STATE["screen"] = "calendar"
        _STATE["detail_event_id"] = None
        _STATE["form_event_id"] = None
        _STATE["load_generation"] += 1
        generation = _STATE["load_generation"]
        anchor = parse_date(_STATE["date"])
        active_mode = _STATE["mode"]
        query = _STATE["query"]
        calendars = list(_STATE["calendars"])

    calendar_frame(rev, [], anchor, active_mode, query, calendars, loading=True)

    def load():
        try:
            service = get_service()
            if service is None:
                with _STATE_LOCK:
                    current = generation == _STATE["load_generation"]
                if current:
                    render_connect_prompt(rev)
                return
            with _API_LOCK:
                loaded_calendars, wrappers = fetch_events(service, anchor, active_mode, query)
            with _STATE_LOCK:
                if generation != _STATE["load_generation"]:
                    return
                _STATE["calendars"] = loaded_calendars
                _STATE["events"] = {wrapper["id"]: wrapper for wrapper in wrappers}
            calendar_frame(
                rev,
                [event_item(wrapper) for wrapper in wrappers],
                anchor,
                active_mode,
                query,
                loaded_calendars,
                select_id=select_id,
            )
        except HttpError as error:
            log("Google Calendar API error:", error)
            with _STATE_LOCK:
                current = generation == _STATE["load_generation"]
            if current:
                render_error(rev, f"Google Calendar API error: {error}")
        except Exception as error:
            log("Calendar load failed:", error)
            with _STATE_LOCK:
                current = generation == _STATE["load_generation"]
            if current:
                render_error(rev, str(error))

    threading.Thread(target=load, daemon=True).start()


def render_missing_dependencies(rev):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "detail": {
                "markdown": (
                    "# Google Calendar could not start\n\n"
                    "The required Google packages failed to load:\n\n"
                    f"```\n{GOOGLE_IMPORT_ERROR}\n```\n\n"
                    "Reopen the launcher after checking that Python and pip are available on PATH."
                )
            },
        }
    )


def render_setup_help(rev):
    with _STATE_LOCK:
        _STATE["screen"] = "setup"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "page": {"id": "gcal:setup", "title": "Set up Google Calendar", "history": "replace"},
            "detail": {
                "markdown": (
                    "# Set up Google Calendar\n\n"
                    "Google requires a personal Desktop OAuth client. Create one, enable the "
                    "**Google Calendar API**, and save the downloaded JSON here as "
                    "`client_secret.json`.\n\nOpen the included README for the exact steps."
                ),
                "metadata": [{"label": "Expected file", "text": CLIENT_SECRET_FILE, "icon": "file"}],
            },
            "actions": [{"id": "open-readme", "title": "Open setup guide", "icon": "book"}],
        }
    )


def render_connect_prompt(rev):
    with _STATE_LOCK:
        _STATE["screen"] = "connect"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": {"id": "gcal:connect", "title": "Google Calendar", "history": "replace"},
            "items": [],
            "empty": {
                "icon": "calendar",
                "title": "Connect Google Calendar",
                "hint": "Sign in once to browse and manage all calendars selected in Google Calendar.",
                "action": {"id": "connect", "title": "Connect", "icon": "link"},
            },
            "actions": [
                {"id": "connect", "title": "Connect Google Calendar", "icon": "link"},
                {"id": "open-readme", "title": "Open setup guide", "icon": "book"},
            ],
        }
    )


def render_error(rev, message):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": {"id": "gcal:error", "title": "Google Calendar", "history": "replace"},
            "items": [],
            "empty": {"icon": "error", "title": "Calendar unavailable", "hint": message},
            "actions": [
                {"id": "refresh", "title": "Try again", "icon": "refresh"},
                {"id": "open-calendar", "title": "Open Google Calendar", "icon": "open"},
            ],
        }
    )


def format_event_when(wrapper):
    event = wrapper["event"]
    start, all_day = parse_google_time(event.get("start"))
    end, _ = parse_google_time(event.get("end"))
    if start is None:
        return "Time unavailable"
    if all_day:
        return start.strftime("%A, %B %d · all day")
    text = start.strftime("%A, %B %d · %H:%M")
    if isinstance(end, dt.datetime):
        text += "–" + end.strftime("%H:%M")
    return text


def event_clipboard_text(wrapper):
    event = wrapper["event"]
    parts = [event.get("summary") or "(Untitled event)", format_event_when(wrapper)]
    if event.get("location"):
        parts.append(event["location"])
    if conference_url(event):
        parts.append(conference_url(event))
    elif event_url(event):
        parts.append(event_url(event))
    return "\n".join(parts)


def render_event_detail(item_id, rev=0):
    with _STATE_LOCK:
        wrapper = _STATE["events"].get(item_id)
        _STATE["screen"] = "detail"
        _STATE["detail_event_id"] = item_id
    if wrapper is None:
        toast("That event is no longer in the current calendar range", "error")
        start_calendar_load(0)
        return
    event = wrapper["event"]
    title = event.get("summary") or "(Untitled event)"
    description = event.get("description") or "_No description._"
    metadata = [
        {"label": "When", "text": format_event_when(wrapper), "icon": "clock"},
        {"label": "Calendar", "text": wrapper["calendar_name"], "color": wrapper["color"]},
    ]
    if event.get("location"):
        map_url = "https://www.google.com/maps/search/?api=1&query=" + quote(event["location"])
        metadata.append({"label": "Location", "text": event["location"], "url": map_url})
    if event.get("organizer", {}).get("email"):
        metadata.append({"label": "Organizer", "text": event["organizer"]["email"], "icon": "person"})
    attendees = [attendee.get("email") for attendee in event.get("attendees", []) if attendee.get("email")]
    if attendees:
        metadata.append({"label": "Guests", "text": ", ".join(attendees[:12]), "icon": "people"})
    if conference_url(event):
        metadata.append({"label": "Meeting", "text": "Join video call", "url": conference_url(event)})
    if event_url(event):
        metadata.append({"label": "Google Calendar", "text": "Open event", "url": event_url(event)})
    actions = [
        {"id": "detail:open", "title": "Open in Google Calendar", "icon": "open"},
        {"id": "detail:copy", "title": "Copy event details", "icon": "copy"},
    ]
    if wrapper["writable"]:
        actions.insert(1, {"id": "detail:edit", "title": "Edit event", "icon": "edit"})
    if conference_url(event):
        actions.insert(0, {"id": "detail:join", "title": "Join meeting", "icon": "video"})
    if wrapper["writable"]:
        actions.append(
            {
                "id": "detail:delete",
                "title": "Delete event",
                "icon": "trash",
                "destructive": True,
                "confirm": {"title": "Delete this event?", "message": title, "confirmLabel": "Delete"},
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "page": {
                "id": f"gcal:detail:{item_id}",
                "title": title,
                "history": "push",
                "breadcrumbs": [{"id": "gcal:calendar", "label": "Calendar"}],
            },
            "canGoBack": True,
            "detail": {"markdown": f"# {title}\n\n{description}", "metadata": metadata},
            "actions": actions,
        }
    )


def rounded_start_time():
    now = dt.datetime.now() + dt.timedelta(minutes=30)
    minute = 30 if now.minute < 30 else 0
    if minute == 0:
        now += dt.timedelta(hours=1)
    return now.replace(minute=minute, second=0, microsecond=0).strftime("%H:%M")


def event_form_values(wrapper=None):
    if wrapper is None:
        with _STATE_LOCK:
            anchor = parse_date(_STATE["date"])
        day = max(anchor, dt.date.today())
        return {
            "calendar": calendar_options()[0]["value"],
            "title": "",
            "date": day.isoformat(),
            "all_day": False,
            "start_time": rounded_start_time(),
            "duration": 60,
            "location": "",
            "guests": "",
            "description": "",
        }
    event = wrapper["event"]
    start, all_day = parse_google_time(event.get("start"))
    end, _ = parse_google_time(event.get("end"))
    if isinstance(start, dt.datetime) and isinstance(end, dt.datetime):
        duration = max(1, int((end - start).total_seconds() // 60))
    else:
        duration = 60
    day = start.date() if isinstance(start, dt.datetime) else start
    guests = ", ".join(
        attendee.get("email", "") for attendee in event.get("attendees", []) if attendee.get("email")
    )
    return {
        "calendar": wrapper["calendar_id"],
        "title": event.get("summary") or "",
        "date": day.isoformat() if day else dt.date.today().isoformat(),
        "all_day": all_day,
        "start_time": start.strftime("%H:%M") if isinstance(start, dt.datetime) else rounded_start_time(),
        "duration": duration,
        "location": event.get("location") or "",
        "guests": guests,
        "description": event.get("description") or "",
    }


def render_event_form(item_id=None, rev=0, values=None, errors=None, form_error=None):
    errors = errors or {}
    with _STATE_LOCK:
        wrapper = _STATE["events"].get(item_id) if item_id else None
        _STATE["screen"] = "form"
        _STATE["form_event_id"] = item_id
    values = values or event_form_values(wrapper)
    editing = wrapper is not None
    available_calendars = calendar_options()
    if editing:
        available_calendars = [
            {"value": wrapper["calendar_id"], "label": wrapper["calendar_name"]}
        ]

    def field_error(field_id):
        return {"error": errors[field_id]} if field_id in errors else {}

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "page": {
                "id": "gcal:edit" if editing else "gcal:new",
                "title": "Edit event" if editing else "New event",
                "history": "push",
                "preserveState": True,
                "breadcrumbs": [{"id": "gcal:calendar", "label": "Calendar"}],
            },
            "canGoBack": True,
            "form": {
                "title": "Edit event" if editing else "New event",
                **({"error": form_error} if form_error else {}),
                "sections": [
                    {"id": "event", "title": "Event"},
                    {"id": "people", "title": "Place and people", "collapsible": True},
                    {"id": "notes", "title": "Notes", "collapsible": True},
                ],
                "submitLabel": "Save changes" if editing else "Create event",
                "fields": [
                    {
                        "id": "calendar",
                        "type": "dropdown",
                        "label": "Calendar",
                        "section": "event",
                        "required": True,
                        "value": values.get("calendar", available_calendars[0]["value"]),
                        "options": available_calendars,
                    },
                    {
                        "id": "title",
                        "type": "text",
                        "label": "Title",
                        "section": "event",
                        "required": True,
                        "maxLength": 256,
                        "value": values.get("title", ""),
                        **field_error("title"),
                    },
                    {
                        "id": "date",
                        "type": "date",
                        "label": "Date",
                        "section": "event",
                        "required": True,
                        "value": values.get("date", dt.date.today().isoformat()),
                        **field_error("date"),
                    },
                    {
                        "id": "all_day",
                        "type": "checkbox",
                        "label": "All day",
                        "section": "event",
                        "value": bool(values.get("all_day")),
                    },
                    {
                        "id": "start_time",
                        "type": "text",
                        "label": "Start time",
                        "section": "event",
                        "required": True,
                        "value": values.get("start_time", rounded_start_time()),
                        "placeholder": "09:30",
                        "pattern": TIME_PATTERN,
                        "validationMessage": "Use 24-hour HH:MM format",
                        "visibleWhen": {"field": "all_day", "equals": False},
                        **field_error("start_time"),
                    },
                    {
                        "id": "duration",
                        "type": "number",
                        "label": "Duration (minutes)",
                        "section": "event",
                        "required": True,
                        "min": 1,
                        "max": 10080,
                        "value": values.get("duration", 60),
                        "visibleWhen": {"field": "all_day", "equals": False},
                        **field_error("duration"),
                    },
                    {
                        "id": "location",
                        "type": "text",
                        "label": "Location or meeting link",
                        "section": "people",
                        "value": values.get("location", ""),
                    },
                    {
                        "id": "guests",
                        "type": "text",
                        "label": "Guests",
                        "section": "people",
                        "value": values.get("guests", ""),
                        "description": "Comma-separated email addresses. Saving sends invitation updates.",
                        **field_error("guests"),
                    },
                    {
                        "id": "description",
                        "type": "textarea",
                        "label": "Description",
                        "section": "notes",
                        "value": values.get("description", ""),
                    },
                ],
            },
        }
    )


def validate_event_values(values):
    errors = {}
    if not str(values.get("title", "")).strip():
        errors["title"] = "Give the event a title"
    day = parse_date(values.get("date"), fallback=None)
    try:
        day = dt.date.fromisoformat(str(values.get("date")))
    except (TypeError, ValueError):
        errors["date"] = "Choose a valid date"
        day = None
    all_day = bool(values.get("all_day"))
    start_time = str(values.get("start_time", ""))
    if not all_day and not re.fullmatch(TIME_PATTERN, start_time):
        errors["start_time"] = "Use 24-hour HH:MM format"
    try:
        duration = int(values.get("duration", 0))
        if not 1 <= duration <= 10080:
            raise ValueError
    except (TypeError, ValueError):
        errors["duration"] = "Duration must be between 1 and 10,080 minutes"
        duration = None
    guests = [part.strip() for part in str(values.get("guests", "")).split(",") if part.strip()]
    invalid = [email for email in guests if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email)]
    if invalid:
        errors["guests"] = "Invalid email: " + invalid[0]
    return errors, day, duration, guests


def google_event_body(values, day, duration, guests):
    all_day = bool(values.get("all_day"))
    if all_day:
        start = {"date": day.isoformat()}
        end = {"date": (day + dt.timedelta(days=1)).isoformat()}
    else:
        start_clock = dt.time.fromisoformat(str(values["start_time"]))
        start_value = dt.datetime.combine(day, start_clock, tzinfo=local_timezone())
        end_value = start_value + dt.timedelta(minutes=duration)
        start = {"dateTime": start_value.isoformat(timespec="seconds")}
        end = {"dateTime": end_value.isoformat(timespec="seconds")}
    return {
        "summary": str(values.get("title", "")).strip(),
        "description": str(values.get("description", "")).strip(),
        "location": str(values.get("location", "")).strip(),
        "attendees": [{"email": email} for email in guests],
        "start": start,
        "end": end,
    }


def submit_event(values):
    with _STATE_LOCK:
        item_id = _STATE["form_event_id"]
        wrapper = _STATE["events"].get(item_id) if item_id else None
    errors, day, duration, guests = validate_event_values(values)
    if errors:
        render_event_form(item_id, values=values, errors=errors, form_error="Please fix the highlighted fields.")
        return
    with _STATE_LOCK:
        _STATE["screen"] = "saving"

    def save():
        try:
            toast("Saving event…", "progress")
            service = get_service()
            if service is None:
                raise RuntimeError("Google Calendar is not connected")
            body = google_event_body(values, day, duration, guests)
            calendar_id = str(values.get("calendar") or "primary")
            if wrapper is None:
                with _API_LOCK:
                    event = service.events().insert(
                        calendarId=calendar_id, body=body, sendUpdates="all"
                    ).execute()
                toast(f"Created {event.get('summary') or 'event'}", "success")
            else:
                with _API_LOCK:
                    event = service.events().patch(
                        calendarId=wrapper["calendar_id"],
                        eventId=wrapper["event"]["id"],
                        body=body,
                        sendUpdates="all",
                    ).execute()
                toast(f"Updated {event.get('summary') or 'event'}", "success")
            with _STATE_LOCK:
                _STATE["date"] = day.isoformat()
            start_calendar_load(0)
        except Exception as error:
            log("Save event failed:", error)
            toast(f"Could not save event: {error}", "error")
            render_event_form(item_id, values=values, form_error=str(error))

    threading.Thread(target=save, daemon=True).start()


def quick_add(parameters):
    text = str(parameters.get("text", "")).strip()
    calendar_id = str(parameters.get("calendar") or "primary")
    if not text:
        toast("Describe the event to add", "error")
        return

    def add():
        try:
            toast("Adding event…", "progress")
            service = get_service()
            if service is None:
                raise RuntimeError("Google Calendar is not connected")
            with _API_LOCK:
                event = service.events().quickAdd(calendarId=calendar_id, text=text).execute()
            event_start, _ = parse_google_time(event.get("start"))
            if isinstance(event_start, dt.datetime):
                event_day = event_start.date()
            elif isinstance(event_start, dt.date):
                event_day = event_start
            else:
                event_day = dt.date.today()
            with _STATE_LOCK:
                _STATE["date"] = event_day.isoformat()
            toast(f"Added {event.get('summary') or text}", "success")
            start_calendar_load(0)
        except Exception as error:
            log("Quick add failed:", error)
            toast(f"Could not add event: {error}", "error")

    threading.Thread(target=add, daemon=True).start()


def delete_event(item_id):
    with _STATE_LOCK:
        wrapper = _STATE["events"].get(item_id)
    if wrapper is None:
        return

    def delete():
        try:
            toast("Deleting event…", "progress")
            service = get_service()
            if service is None:
                raise RuntimeError("Google Calendar is not connected")
            with _API_LOCK:
                service.events().delete(
                    calendarId=wrapper["calendar_id"],
                    eventId=wrapper["event"]["id"],
                    sendUpdates="all",
                ).execute()
            toast("Event deleted", "success")
            start_calendar_load(0)
        except Exception as error:
            log("Delete failed:", error)
            toast(f"Could not delete event: {error}", "error")

    threading.Thread(target=delete, daemon=True).start()


def open_url(url):
    if url:
        send({"type": "command", "command": "open", "url": url})


def handle_action(message):
    action = message.get("action", "default")
    item_id = message.get("id", "")

    if action == "connect":
        begin_oauth_flow()
        return
    if action == "open-readme":
        send({"type": "command", "command": "open", "path": README_FILE})
        return
    if action == "new":
        render_event_form()
        return
    if action == "quick-add":
        quick_add(message.get("parameters") or {})
        return
    if action == "refresh":
        start_calendar_load(0)
        return
    if action == "open-calendar":
        open_url("https://calendar.google.com/calendar/u/0/r")
        return
    if action == "signout":
        threading.Thread(target=sign_out, daemon=True).start()
        return

    with _STATE_LOCK:
        if not item_id and _STATE["screen"] == "detail":
            item_id = _STATE["detail_event_id"] or ""
        wrapper = _STATE["events"].get(item_id)
    if wrapper is None:
        return
    event = wrapper["event"]

    if action == "default":
        render_event_detail(item_id)
    elif action in {"open", "detail:open"}:
        open_url(event_url(event))
    elif action in {"join", "detail:join"}:
        open_url(conference_url(event))
    elif action in {"edit", "detail:edit"}:
        render_event_form(item_id)
    elif action in {"copy-details", "detail:copy"}:
        send({"type": "command", "command": "copy", "text": event_clipboard_text(wrapper)})
    elif action in {"delete", "detail:delete"}:
        delete_event(item_id)


def handle_back():
    start_calendar_load(0)


def handle_navigate(message):
    if message.get("targetPageId") == "gcal:calendar":
        start_calendar_load(0)


def handle_storage(message):
    request_id = message.get("requestId")
    if not request_id:
        return
    with _PENDING_LOCK:
        pending = _PENDING.get(request_id)
    if pending is not None:
        pending["value"] = message.get("value")
        pending["event"].set()


def main():
    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue
        message = {}
        try:
            message = json.loads(line)
            message_type = message.get("type")
            if message_type == "close":
                break
            if message_type in {"init", "query"}:
                text = message.get("text", message.get("query", ""))
                start_calendar_load(message.get("rev", 0), text=text)
            elif message_type == "calendarNavigate":
                start_calendar_load(
                    message.get("rev", 0),
                    mode=message.get("mode"),
                    date_value=message.get("date"),
                )
            elif message_type == "action":
                handle_action(message)
            elif message_type == "submit":
                with _STATE_LOCK:
                    screen = _STATE["screen"]
                if screen == "form":
                    submit_event(message.get("values") or {})
            elif message_type == "back":
                handle_back()
            elif message_type == "navigate":
                handle_navigate(message)
            elif message_type == "storage":
                handle_storage(message)
            elif message_type == "oauth":
                handle_oauth(message)
        except Exception as error:
            log("Message handler failed:", error)
            send(
                {
                    "type": "render",
                    "rev": message.get("rev", 0) if isinstance(message, dict) else 0,
                    "view": "detail",
                    "detail": {"markdown": f"# Calendar error\n\n```\n{error}\n```"},
                }
            )


if __name__ == "__main__":
    main()
