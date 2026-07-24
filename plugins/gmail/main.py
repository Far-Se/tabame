#!/usr/bin/env python3
"""
Gmail plugin for Tabame.

Setup (one-time, per user):
  1. In Google Cloud Console, create a project, enable the "Gmail API", and
     create an OAuth Client ID of type "Desktop app".
  2. Download the client secret JSON and save it in this plugin's folder as
     "client_secret.json".
  3. Type `mail` in the launcher and pick "Connect Gmail" — a browser window
     opens for you to sign in. The token is stored securely via Tabame's
     storage command (Windows Credential Manager), not on disk.

Usage once connected:
  mail                       -> recent inbox messages
  mail <gmail search syntax>  -> searches all mail, e.g. "mail from:boss is:unread"
  Enter on a message           -> read it in-app
  Ctrl+K on a message           -> Reply / Mark read-unread / Star / Archive / Delete
  Ctrl+K (frame)                 -> Compose / Refresh / Sign out
"""

import base64
import datetime
import email.utils
import html as htmlmod
import json
import os
import re
import sys
import threading
import uuid


def log(*a):
    print(*a, file=sys.stderr, flush=True)


GOOGLE_IMPORT_ERROR = None
try:
    from email.mime.text import MIMEText

    from google.auth.transport.requests import Request as GoogleRequest
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from googleapiclient.discovery import build
    from googleapiclient.errors import HttpError
except Exception as e:  # pragma: no cover
    GOOGLE_IMPORT_ERROR = str(e)

SCOPES = [
    "https://www.googleapis.com/auth/gmail.modify",
    "https://www.googleapis.com/auth/gmail.send",
]
CLIENT_SECRET_FILE = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "client_secret.json"
)
TOKEN_KEY = "token"
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
_pending = {}


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


_state_lock = threading.Lock()
_state = {
    "rev": 0,
    "text": "",
    "messages_by_id": {},  # id -> message resource (metadata or full format)
    "current_message": None,
    "last_rendered_frame": None,  # last list/detail frame sent (for push_screen)
    "nav_stack": [],
    "form_mode": None,  # "compose" or ("reply", msg_id, thread_id, message_id_hdr, references_hdr)
}


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
    return build("gmail", "v1", credentials=creds, cache_discovery=False)


def run_oauth_flow():
    if not os.path.exists(CLIENT_SECRET_FILE):
        toast(
            "Missing client_secret.json in the plugin folder — see setup instructions",
            "error",
        )
        render_messages(0, _state["text"])
        return
    try:
        toast("Opening your browser to sign in to Google…", "progress")
        flow = InstalledAppFlow.from_client_secrets_file(CLIENT_SECRET_FILE, SCOPES)
        creds = flow.run_local_server(port=0, open_browser=True)
        save_credentials(creds)
        toast("Connected to Gmail", "success")
    except Exception as e:
        log("oauth error:", e)
        toast(f"Sign-in failed: {e}", "error")
    render_messages(0, _state["text"])


def sign_out():
    storage_delete(TOKEN_KEY, secret=True)
    with _state_lock:
        _state["messages_by_id"] = {}
        _state["current_message"] = None
    toast("Signed out of Gmail")
    render_messages(0, _state["text"])


# ---------------------------------------------------------------------------
# Message parsing helpers
# ---------------------------------------------------------------------------
def get_header(headers, name):
    for h in headers or []:
        if h.get("name", "").lower() == name.lower():
            return h.get("value", "")
    return ""


def mail_day_label(d):
    today = datetime.date.today()
    dd = d.date() if isinstance(d, datetime.datetime) else d
    if dd == today:
        return "Today"
    if dd == today - datetime.timedelta(days=1):
        return "Yesterday"
    return d.strftime("%b %d")


def format_when(date_raw):
    try:
        dt = email.utils.parsedate_to_datetime(date_raw)
    except Exception:
        return (date_raw or ""), "Older"
    local = dt.astimezone() if dt.tzinfo else dt
    label = mail_day_label(local)
    text = (
        local.strftime("%H:%M")
        if label in ("Today", "Yesterday")
        else local.strftime("%b %d")
    )
    return text, label


def decode_b64(data):
    if not data:
        return ""
    data = data.replace("-", "+").replace("_", "/")
    padded = data + "=" * (-len(data) % 4)
    try:
        return base64.b64decode(padded).decode("utf-8", errors="replace")
    except Exception:
        return ""


def find_part(payload, mime):
    if not payload:
        return None
    if payload.get("mimeType") == mime and payload.get("body", {}).get("data"):
        return payload["body"]["data"]
    for part in payload.get("parts", []) or []:
        d = find_part(part, mime)
        if d:
            return d
    return None


def strip_html(raw_html):
    text = re.sub(r"<(script|style)[^>]*>.*?</\1>", "", raw_html, flags=re.S | re.I)
    text = re.sub(r"<br\s*/?>", "\n", text, flags=re.I)
    text = re.sub(r"</p>", "\n\n", text, flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    return htmlmod.unescape(text).strip()


def md_safe_body(text):
    return "  \n".join(text.split("\n"))


# ---------------------------------------------------------------------------
# Inline / attached images
# ---------------------------------------------------------------------------
CACHE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache")
IMAGE_EXT = {
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/png": ".png",
    "image/gif": ".gif",
    "image/webp": ".webp",
    "image/bmp": ".bmp",
}


def msg_cache_dir(message_id):
    d = os.path.join(CACHE_DIR, message_id)
    os.makedirs(d, exist_ok=True)
    return d


def to_file_url(path):
    import pathlib

    return pathlib.Path(os.path.abspath(path)).as_uri()


def walk_parts(payload):
    """Yield every leaf MIME part (no sub-parts of its own)."""
    if not payload:
        return
    parts = payload.get("parts")
    if parts:
        for p in parts:
            yield from walk_parts(p)
    else:
        yield payload


def collect_images(service, message_id, payload):
    """Download embedded/attached images to a local cache folder.
    Returns (cid_map: {content-id -> file:// url}, image_list: [{filename,url}],
    other_attachment_names: [filename]). Only images physically embedded in the
    message are ever fetched — remote http(s) images referenced in HTML are
    intentionally never auto-loaded, since doing so would leak a read receipt
    to the sender (the classic email tracking-pixel problem)."""
    cid_map, image_list, other_names = {}, [], []
    cache_dir = msg_cache_dir(message_id)
    for part in walk_parts(payload):
        mime = part.get("mimeType", "")
        filename = part.get("filename") or ""
        body = part.get("body", {}) or {}
        content_id = get_header(part.get("headers", []), "Content-ID").strip("<>")

        if not mime.startswith("image/"):
            if filename:
                other_names.append(filename)
            continue

        size = body.get("size", 0)
        if size and size <= 60:
            continue  # near-certainly a 1x1 tracking pixel

        raw_bytes = None
        data = body.get("data")
        att_id = body.get("attachmentId")
        try:
            if data:
                raw_bytes = base64.b64decode(
                    data.replace("-", "+").replace("_", "/") + "=" * (-len(data) % 4)
                )
            elif att_id:
                att = (
                    service.users()
                    .messages()
                    .attachments()
                    .get(userId="me", messageId=message_id, id=att_id)
                    .execute()
                )
                adata = att["data"]
                raw_bytes = base64.b64decode(
                    adata.replace("-", "+").replace("_", "/") + "=" * (-len(adata) % 4)
                )
        except Exception as e:
            log("image fetch failed:", e)
            continue
        if not raw_bytes:
            continue

        part_id = part.get("partId") or content_id or str(len(image_list))
        fname = f"{part_id}{IMAGE_EXT.get(mime, '.bin')}"
        fpath = os.path.join(cache_dir, fname)
        try:
            if not os.path.exists(fpath):
                with open(fpath, "wb") as f:
                    f.write(raw_bytes)
        except Exception as e:
            log("image cache write failed:", e)
            continue

        url = to_file_url(fpath)
        image_list.append(
            {"filename": filename or f"image{IMAGE_EXT.get(mime, '')}", "url": url}
        )
        if content_id:
            cid_map[content_id] = url
    return cid_map, image_list, other_names


def html_to_markdown(raw_html, cid_map):
    """Strip HTML to readable markdown, inlining any <img> that references a
    locally embedded image (cid:...). Images from remote URLs are dropped
    rather than fetched (see collect_images docstring)."""
    used = set()

    def repl(m):
        tag = m.group(0)
        src_match = re.search(r'src=["\']([^"\']+)["\']', tag, flags=re.I)
        if not src_match or not src_match.group(1).startswith("cid:"):
            return ""
        cid = src_match.group(1)[4:]
        url = cid_map.get(cid)
        if not url:
            return ""
        used.add(url)
        alt_match = re.search(r'alt=["\']([^"\']*)["\']', tag, flags=re.I)
        alt = alt_match.group(1) if alt_match else ""
        return f"\n\n![{alt}]({url})\n\n"

    html_with_images = re.sub(r"<img\b[^>]*>", repl, raw_html, flags=re.I)
    return strip_html(html_with_images), used


def build_detail_body(service, message_id, payload):
    """Returns full markdown body text including any embedded images."""
    cid_map, image_list, other_names = collect_images(service, message_id, payload)

    plain = find_part(payload, "text/plain")
    htmlraw = find_part(payload, "text/html")
    used_urls = set()

    if plain:
        body_md = md_safe_body(decode_b64(plain))
    elif htmlraw:
        body_md, used_urls = html_to_markdown(decode_b64(htmlraw), cid_map)
    else:
        data = payload.get("body", {}).get("data") if payload else None
        body_md = md_safe_body(decode_b64(data)) if data else "_(No readable content)_"

    leftover_images = [img for img in image_list if img["url"] not in used_urls]
    if leftover_images:
        gallery = "\n\n---\n\n## Images\n\n" + "\n\n".join(
            f"![{img['filename']}]({img['url']})" for img in leftover_images
        )
        body_md += gallery

    if other_names:
        names = ", ".join(other_names)
        body_md += f"\n\n---\n\n*Also has {len(other_names)} attachment(s): {names}*"

    return body_md


# ---------------------------------------------------------------------------
# Navigation stack (list <-> detail <-> form)
# ---------------------------------------------------------------------------
def push_screen(frame):
    if not frame:
        return
    with _state_lock:
        _state["nav_stack"].append(dict(frame))


def pop_screen():
    with _state_lock:
        stack = _state["nav_stack"]
        frame = stack.pop() if stack else None
    if frame:
        frame = dict(frame)
        frame["rev"] = 0
        send(frame)
        with _state_lock:
            _state["last_rendered_frame"] = frame
    else:
        render_messages(0, _state["text"])


# ---------------------------------------------------------------------------
# List item building
# ---------------------------------------------------------------------------
def build_item(msg):
    headers = msg.get("payload", {}).get("headers", [])
    subject = get_header(headers, "Subject") or "(No subject)"
    from_raw = get_header(headers, "From")
    from_name, from_addr = email.utils.parseaddr(from_raw)
    display_from = from_name or from_addr or "Unknown sender"
    date_raw = get_header(headers, "Date")
    when_text, section = format_when(date_raw)
    labels = msg.get("labelIds") or []
    unread = "UNREAD" in labels
    starred = "STARRED" in labels
    snippet = msg.get("snippet", "")

    accessories = []
    if unread:
        accessories.append({"text": "Unread", "color": "#2563EB"})
    if starred:
        accessories.append({"text": "\u2605", "color": "#F59E0B"})
    accessories.append({"text": when_text})

    return {
        "id": msg["id"],
        "title": f"**{subject}**" if unread else subject,
        "subtitle": f"{display_from} \u2014 {snippet}",
        "icon": "mail",
        "section": section,
        "accessories": accessories,
        "actions": [
            {"id": "reply", "title": "Reply", "icon": "mail"},
            {
                "id": "toggle_read",
                "title": "Mark as read" if unread else "Mark as unread",
                "icon": "email",
            },
            {
                "id": "toggle_star",
                "title": "Remove star" if starred else "Star",
                "icon": "star",
            },
            {"id": "archive", "title": "Archive", "icon": "folder"},
            {"id": "browser", "title": "Open in Gmail", "icon": "open"},
            {
                "id": "delete",
                "title": "Delete",
                "icon": "trash",
                "destructive": True,
                "confirm": {
                    "title": "Delete this email?",
                    "message": subject,
                    "confirmLabel": "Delete",
                },
            },
        ],
        "preview": {
            "markdown": f"**{display_from}**\n\n{snippet}",
            "metadata": [
                {"label": "From", "text": from_raw},
                {"label": "Date", "text": date_raw},
            ],
        },
    }


LIST_FRAME_ACTIONS = [
    {"id": "compose", "title": "Compose", "icon": "mail"},
    {"id": "refresh", "title": "Refresh", "icon": "refresh"},
    {
        "id": "signout",
        "title": "Sign out of Gmail",
        "icon": "lock",
        "confirm": {
            "title": "Sign out?",
            "message": "You'll need to reconnect to see mail again.",
            "confirmLabel": "Sign out",
        },
    },
]


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
def render_connect_prompt(rev):
    frame = {
        "type": "render",
        "rev": rev,
        "view": "list",
        "items": [],
        "empty": {
            "icon": "lock",
            "title": "Not connected",
            "hint": "Connect your Gmail account to search, read and send mail.",
            "action": {"id": "connect", "title": "Connect Gmail", "icon": "link"},
        },
        "actions": [{"id": "connect", "title": "Connect Gmail", "icon": "link"}],
    }
    send(frame)
    with _state_lock:
        _state["last_rendered_frame"] = frame
        _state["nav_stack"] = []


def render_missing_deps(rev):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "detail": {
                "markdown": (
                    "# Gmail plugin\n\nRequired Python packages failed to load:\n\n"
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
                    "# Set up Gmail\n\n"
                    "1. In [Google Cloud Console](https://console.cloud.google.com/apis/credentials), "
                    "create a project and enable the **Gmail API**.\n"
                    "2. Create an **OAuth Client ID** of type **Desktop app**.\n"
                    "3. Download the client secret JSON and save it in this plugin's folder as "
                    "`client_secret.json`.\n"
                    "4. Come back and type `mail` again, then choose **Connect Gmail**."
                )
            },
        }
    )


def render_error(rev, message):
    frame = {
        "type": "render",
        "rev": rev,
        "view": "list",
        "items": [],
        "empty": {"icon": "error", "title": "Something went wrong", "hint": message},
        "actions": LIST_FRAME_ACTIONS,
    }
    send(frame)
    with _state_lock:
        _state["last_rendered_frame"] = frame


def render_messages(rev, text, reset_stack=True):
    if is_stale(rev):
        return
    if reset_stack:
        with _state_lock:
            _state["nav_stack"] = []
            _state["current_message"] = None

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
            "loadingText": "Loading mail…",
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
        query = text.strip()
        kwargs = dict(userId="me", maxResults=MAX_RESULTS)
        if query:
            kwargs["q"] = query
        else:
            kwargs["labelIds"] = ["INBOX"]

        list_resp = service.users().messages().list(**kwargs).execute()
        refs = list_resp.get("messages", [])

        messages = []
        for ref in refs:
            if is_stale(rev):
                return
            msg = (
                service.users()
                .messages()
                .get(
                    userId="me",
                    id=ref["id"],
                    format="metadata",
                    metadataHeaders=["From", "Subject", "Date", "Message-ID"],
                )
                .execute()
            )
            messages.append(msg)

        if is_stale(rev):
            return

        with _state_lock:
            for m in messages:
                _state["messages_by_id"][m["id"]] = m

        items = [build_item(m) for m in messages]
        frame = {
            "type": "render",
            "rev": rev,
            "view": "list",
            "items": items,
            "preview": {"enabled": True},
            "placeholder": "Search all mail, or leave empty for inbox…",
            "emptyText": "Inbox zero \U0001f389"
            if not query
            else f'No mail matching "{query}"',
            "actions": LIST_FRAME_ACTIONS,
        }
        send(frame)
        with _state_lock:
            _state["last_rendered_frame"] = frame
    except HttpError as e:
        log("HttpError:", e)
        render_error(rev, f"Gmail API error: {e}")
    except Exception as e:
        log("render_messages failed:", e)
        render_error(rev, str(e))


def open_detail(message_id):
    def work():
        try:
            service = get_service()
            if service is None:
                render_connect_prompt(0)
                return
            full = (
                service.users()
                .messages()
                .get(userId="me", id=message_id, format="full")
                .execute()
            )
            with _state_lock:
                _state["current_message"] = full
                _state["messages_by_id"][message_id] = full

            headers = full.get("payload", {}).get("headers", [])
            subject = get_header(headers, "Subject") or "(No subject)"
            from_raw = get_header(headers, "From")
            to_raw = get_header(headers, "To")
            date_raw = get_header(headers, "Date")
            body_md = build_detail_body(service, message_id, full.get("payload", {}))
            md = (
                f"# {subject}\n\n"
                f"**From:** {from_raw}  \n**To:** {to_raw}  \n**Date:** {date_raw}\n\n---\n\n"
                f"{body_md}"
            )
            labels = full.get("labelIds") or []
            unread = "UNREAD" in labels
            starred = "STARRED" in labels

            push_screen(_state["last_rendered_frame"])
            frame = {
                "type": "render",
                "rev": 0,
                "view": "detail",
                "canGoBack": True,
                "detail": {"markdown": md, "wide": True},
                "actions": [
                    {"id": "reply", "title": "Reply", "icon": "mail"},
                    {
                        "id": "toggle_read",
                        "title": "Mark as unread" if not unread else "Mark as read",
                        "icon": "email",
                    },
                    {
                        "id": "toggle_star",
                        "title": "Remove star" if starred else "Star",
                        "icon": "star",
                    },
                    {"id": "archive", "title": "Archive", "icon": "folder"},
                    {"id": "browser", "title": "Open in Gmail", "icon": "open"},
                    {
                        "id": "delete",
                        "title": "Delete",
                        "icon": "trash",
                        "destructive": True,
                        "confirm": {
                            "title": "Delete this email?",
                            "message": subject,
                            "confirmLabel": "Delete",
                        },
                    },
                ],
            }
            send(frame)
            with _state_lock:
                _state["last_rendered_frame"] = frame
        except Exception as e:
            log("open_detail failed:", e)
            toast(f"Couldn't open message: {e}", "error")

    threading.Thread(target=work, daemon=True).start()


# ---------------------------------------------------------------------------
# Compose / reply
# ---------------------------------------------------------------------------
def start_compose():
    push_screen(_state["last_rendered_frame"])
    with _state_lock:
        _state["form_mode"] = "compose"
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "form",
            "canGoBack": True,
            "form": {
                "title": "New message",
                "submitLabel": "Send",
                "fields": [
                    {
                        "id": "to",
                        "type": "text",
                        "label": "To",
                        "placeholder": "someone@example.com",
                        "required": True,
                    },
                    {
                        "id": "subject",
                        "type": "text",
                        "label": "Subject",
                        "required": True,
                    },
                    {
                        "id": "body",
                        "type": "textarea",
                        "label": "Message",
                        "required": True,
                    },
                ],
            },
        }
    )


def start_reply(msg):
    headers = msg.get("payload", {}).get("headers", [])
    from_raw = get_header(headers, "From")
    _, from_addr = email.utils.parseaddr(from_raw)
    subject = get_header(headers, "Subject") or ""
    reply_subject = subject if subject.lower().startswith("re:") else f"Re: {subject}"
    message_id_hdr = get_header(headers, "Message-ID")
    thread_id = msg.get("threadId")

    push_screen(_state["last_rendered_frame"])
    with _state_lock:
        _state["form_mode"] = (
            "reply",
            msg.get("id"),
            thread_id,
            message_id_hdr,
            message_id_hdr,
        )
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "form",
            "canGoBack": True,
            "form": {
                "title": "Reply",
                "submitLabel": "Send",
                "fields": [
                    {
                        "id": "to",
                        "type": "text",
                        "label": "To",
                        "value": from_addr,
                        "required": True,
                    },
                    {
                        "id": "subject",
                        "type": "text",
                        "label": "Subject",
                        "value": reply_subject,
                        "required": True,
                    },
                    {
                        "id": "body",
                        "type": "textarea",
                        "label": "Message",
                        "required": True,
                    },
                ],
            },
        }
    )


def send_email(to, subject, body, thread_id=None, in_reply_to=None, references=None):
    service = get_service()
    if service is None:
        raise RuntimeError("Not connected")
    msg = MIMEText(body)
    msg["to"] = to
    msg["subject"] = subject
    if in_reply_to:
        msg["In-Reply-To"] = in_reply_to
        msg["References"] = references or in_reply_to
    raw = base64.urlsafe_b64encode(msg.as_bytes()).decode("utf-8")
    body_obj = {"raw": raw}
    if thread_id:
        body_obj["threadId"] = thread_id
    service.users().messages().send(userId="me", body=body_obj).execute()


def handle_form_submit(values):
    with _state_lock:
        mode = _state.get("form_mode")
    to = (values.get("to") or "").strip()
    subject = (values.get("subject") or "").strip()
    body = (values.get("body") or "").strip()
    if not to or not subject or not body:
        toast("Please fill in all fields", "error")
        return
    try:
        if isinstance(mode, tuple) and mode[0] == "reply":
            _, _msg_id, thread_id, message_id_hdr, references_hdr = mode
            send_email(
                to,
                subject,
                body,
                thread_id=thread_id,
                in_reply_to=message_id_hdr,
                references=references_hdr,
            )
        else:
            send_email(to, subject, body)
        toast("Message sent", "success")
    except Exception as e:
        log("send failed:", e)
        toast(f"Send failed: {e}", "error")
        return
    pop_screen()


# ---------------------------------------------------------------------------
# Mutations (archive / delete / star / read)
# ---------------------------------------------------------------------------
def mutate_message(message_id, action):
    try:
        service = get_service()
        if service is None:
            toast("Not connected", "error")
            return
        with _state_lock:
            cached = (
                _state["messages_by_id"].get(message_id)
                or _state.get("current_message")
                or {}
            )
        labels = cached.get("labelIds") or []

        if action == "toggle_read":
            unread = "UNREAD" in labels
            body = (
                {"removeLabelIds": ["UNREAD"]}
                if unread
                else {"addLabelIds": ["UNREAD"]}
            )
            service.users().messages().modify(
                userId="me", id=message_id, body=body
            ).execute()
            toast("Marked as read" if unread else "Marked as unread", "success")
        elif action == "toggle_star":
            starred = "STARRED" in labels
            body = (
                {"removeLabelIds": ["STARRED"]}
                if starred
                else {"addLabelIds": ["STARRED"]}
            )
            service.users().messages().modify(
                userId="me", id=message_id, body=body
            ).execute()
            toast("Star removed" if starred else "Starred", "success")
        elif action == "archive":
            service.users().messages().modify(
                userId="me", id=message_id, body={"removeLabelIds": ["INBOX"]}
            ).execute()
            toast("Archived", "success")
        elif action == "delete":
            service.users().messages().trash(userId="me", id=message_id).execute()
            toast("Moved to trash", "success")
    except Exception as e:
        log("mutate_message failed:", e)
        toast(f"Action failed: {e}", "error")
        return
    render_messages(0, _state["text"])


# ---------------------------------------------------------------------------
# Action dispatch
# ---------------------------------------------------------------------------
def handle_action(item_id, action):
    if action == "connect":
        threading.Thread(target=run_oauth_flow, daemon=True).start()
        return
    if item_id == "" and action == "refresh":
        threading.Thread(
            target=lambda: render_messages(0, _state["text"]), daemon=True
        ).start()
        return
    if item_id == "" and action == "signout":
        threading.Thread(target=sign_out, daemon=True).start()
        return
    if item_id == "" and action == "compose":
        start_compose()
        return

    with _state_lock:
        target_id = item_id or ((_state.get("current_message") or {}).get("id"))
    if not target_id:
        return

    if action == "default":
        open_detail(target_id)
        return

    if action == "reply":
        with _state_lock:
            msg = _state["messages_by_id"].get(target_id) or _state.get(
                "current_message"
            )
        if msg:
            start_reply(msg)
        return

    if action == "browser":
        send(
            {
                "type": "command",
                "command": "open",
                "url": f"https://mail.google.com/mail/u/0/#all/{target_id}",
            }
        )
        return

    if action in ("toggle_read", "toggle_star", "archive", "delete"):
        threading.Thread(
            target=lambda: mutate_message(target_id, action), daemon=True
        ).start()
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
                target=render_messages, args=(rev, text), daemon=True
            ).start()

        elif t == "action":
            handle_action(msg.get("id", ""), msg.get("action", "default"))

        elif t == "submit":
            values = msg.get("values", {})
            threading.Thread(
                target=handle_form_submit, args=(values,), daemon=True
            ).start()

        elif t == "back":
            threading.Thread(target=pop_screen, daemon=True).start()

        elif t == "storage":
            req_id = msg.get("requestId")
            if req_id:
                with _pending_lock:
                    entry = _pending.get(req_id)
                if entry:
                    entry["value"] = msg.get("value")
                    entry["event"].set()

        # select / tab / loadMore: not used by this plugin

    sys.exit(0)


if __name__ == "__main__":
    main()
