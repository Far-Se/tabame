#!/usr/bin/env python3
"""
Tabame "mail" plugin.

Multi-account email client over IMAP or POP3 (receiving) and SMTP (sending).
Works with Gmail, Yahoo, and any custom mail server. No third-party packages
required -- everything is done with the Python standard library.

Screens (kept in STATE["screen"]):
  root        -> list of configured accounts
  add_account -> form to add a new account
  inbox       -> list of messages for the selected account
  email       -> full message detail
  compose     -> new email / reply form

Credentials are never held in STATE longer than needed for one operation --
passwords are fetched from Tabame's secure storage (Windows Credential
Manager) on demand via request_password().
"""

import sys
import json
import threading
import uuid
import ssl
import re
import imaplib
import poplib
import smtplib
from datetime import date, timedelta
from email import message_from_bytes
from email.header import decode_header
from email.mime.text import MIMEText
from email.utils import parsedate_to_datetime, parseaddr, formatdate, formataddr
from html.parser import HTMLParser

FETCH_LIMIT = 40

PROVIDER_PRESETS = {
    "gmail": {
        "protocol": "imap",
        "recv_host": "imap.gmail.com", "recv_port": 993, "recv_security": "ssl",
        "smtp_host": "smtp.gmail.com", "smtp_port": 587, "smtp_security": "starttls",
    },
    "yahoo": {
        "protocol": "imap",
        "recv_host": "imap.mail.yahoo.com", "recv_port": 993, "recv_security": "ssl",
        "smtp_host": "smtp.mail.yahoo.com", "smtp_port": 587, "smtp_security": "starttls",
    },
}

STATE = {
    "screen": "root",
    "loaded": False,
    "accounts": [],
    "query": "",
    "account_id": None,
    "messages": [],
    "inbox_loading": False,
    "current_uid": None,
    "current_email": None,
    "email_loading": False,
    "compose_account_id": None,
    "compose_return": "root",
    "compose_in_reply_to": None,
}
PENDING = {}
LOCK = threading.Lock()


# --------------------------------------------------------------------------
# Protocol plumbing
# --------------------------------------------------------------------------

def send(frame):
    with LOCK:
        sys.stdout.write(json.dumps(frame) + "\n")
        sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def request_storage(key, secret, callback):
    req_id = str(uuid.uuid4())
    PENDING[req_id] = callback
    send({"type": "command", "command": "storage", "op": "get",
          "key": key, "secret": secret, "requestId": req_id})


def request_password(account_id, callback):
    request_storage(f"pwd:{account_id}", True, callback)


def save_accounts():
    send({"type": "command", "command": "storage", "op": "set",
          "key": "accounts", "value": json.dumps(STATE["accounts"])})


def save_password(account_id, password):
    send({"type": "command", "command": "storage", "op": "set",
          "key": f"pwd:{account_id}", "value": password, "secret": True})


def delete_password(account_id):
    send({"type": "command", "command": "storage", "op": "delete",
          "key": f"pwd:{account_id}", "secret": True})


def toast(text, style=None):
    frame = {"type": "command", "command": "toast", "text": text}
    if style:
        frame["style"] = style
    send(frame)


# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------

def get_account(acc_id):
    for a in STATE["accounts"]:
        if a["id"] == acc_id:
            return a
    return None


def get_message(uid):
    for m in STATE["messages"]:
        if m["uid"] == uid:
            return m
    return None


def decode_mime(s):
    if not s:
        return ""
    out = []
    for text, enc in decode_header(s):
        if isinstance(text, bytes):
            try:
                out.append(text.decode(enc or "utf-8", errors="replace"))
            except (LookupError, TypeError):
                out.append(text.decode("utf-8", errors="replace"))
        else:
            out.append(text)
    return "".join(out)


def parse_email_date(date_hdr):
    if not date_hdr:
        return None
    try:
        return parsedate_to_datetime(date_hdr)
    except Exception:
        return None


def short_date(date_hdr):
    dt = parse_email_date(date_hdr)
    return dt.strftime("%b %d, %H:%M") if dt else ""


def bucket_label(date_hdr):
    dt = parse_email_date(date_hdr)
    if not dt:
        return "Unknown date"
    d = dt.date()
    today = date.today()
    if d == today:
        return "Today"
    if d == today - timedelta(days=1):
        return "Yesterday"
    if d >= today - timedelta(days=7):
        return "This week"
    return "Older"


def normalize_email_text(text, keep_blank_lines=True):
    """Remove MIME/HTML layout whitespace without changing visible line breaks."""
    text = (text or "").replace("\r\n", "\n").replace("\r", "\n")
    text = text.replace("\u00a0", " ").replace("\u200b", "")
    lines = []
    blank = True
    for raw_line in text.split("\n"):
        line = re.sub(r"[\t\f\v ]+", " ", raw_line).strip()
        if not line:
            if keep_blank_lines and not blank:
                lines.append("")
            blank = True
            continue
        lines.append(line)
        blank = False
    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines)


def md_safe_body(text):
    """Render email text as prose without letting it become Markdown blocks."""
    rendered = []
    for line in normalize_email_text(text).split("\n"):
        if not line:
            rendered.append("")
            continue
        line = re.sub(r"([\\`*_\[\]<>|~])", r"\\\1", line)
        line = re.sub(r"^(\d+)([.)])(\s)", r"\1\\\2\3", line)
        if re.match(r"^(?:#{1,6}\s|>\s?|[-+]\s)", line) or re.fullmatch(r"[-=]{3,}", line):
            line = "\\" + line
        rendered.append(line + "  ")
    return "\n".join(rendered).rstrip()


def reply_subject(subject):
    s = subject or ""
    return s if s.lower().startswith("re:") else f"Re: {s}"


def extract_email_addr(from_field):
    _, addr = parseaddr(from_field or "")
    return addr or (from_field or "")


def quote_body(body, from_field, date_hdr):
    if not body:
        return ""
    quoted = "\n".join(f"> {line}" for line in body.splitlines())
    header = f"On {date_hdr}, {from_field} wrote:" if (date_hdr or from_field) else "Original message:"
    return f"\n\n\n{header}\n{quoted}"


class _TextExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
        self.ignored_depth = 0

    def handle_data(self, data):
        if not self.ignored_depth:
            self.parts.append(data)

    def handle_starttag(self, tag, attrs):
        if tag in ("head", "script", "style"):
            self.ignored_depth += 1
            return
        if self.ignored_depth:
            return
        if tag in ("br", "p", "div", "tr", "li", "blockquote", "section", "article"):
            self.parts.append("\n")
        elif tag in ("td", "th"):
            self.parts.append(" ")

    def handle_endtag(self, tag):
        if tag in ("head", "script", "style"):
            self.ignored_depth = max(0, self.ignored_depth - 1)
            return
        if self.ignored_depth:
            return
        if tag in ("p", "div", "tr", "li", "blockquote", "section", "article"):
            self.parts.append("\n")
        elif tag in ("td", "th"):
            self.parts.append(" ")


def html_to_text(html_str):
    p = _TextExtractor()
    try:
        p.feed(html_str)
    except Exception:
        return html_str
    return normalize_email_text("".join(p.parts), keep_blank_lines=False)


def extract_body(msg):
    if msg.is_multipart():
        text_part = None
        html_part = None
        for part in msg.walk():
            ctype = part.get_content_type()
            disp = str(part.get("Content-Disposition") or "")
            if "attachment" in disp:
                continue
            if ctype == "text/plain" and text_part is None:
                text_part = part
            elif ctype == "text/html" and html_part is None:
                html_part = part
        chosen = text_part or html_part
        if chosen is None:
            return "(this message has no readable text content)"
        payload = chosen.get_payload(decode=True) or b""
        charset = chosen.get_content_charset() or "utf-8"
        text = payload.decode(charset, errors="replace").replace("\r\n", "\n").replace("\r", "\n")
        return html_to_text(text) if chosen is html_part else text
    payload = msg.get_payload(decode=True) or b""
    charset = msg.get_content_charset() or "utf-8"
    text = payload.decode(charset, errors="replace").replace("\r\n", "\n").replace("\r", "\n")
    return html_to_text(text) if msg.get_content_type() == "text/html" else text


# --------------------------------------------------------------------------
# IMAP / POP3 / SMTP
# --------------------------------------------------------------------------

def imap_connect(acc, pwd):
    host, port, sec = acc["recv_host"], acc["recv_port"], acc["recv_security"]
    if sec == "ssl":
        conn = imaplib.IMAP4_SSL(host, port)
    else:
        conn = imaplib.IMAP4(host, port)
        if sec == "starttls":
            conn.starttls(ssl.create_default_context())
    conn.login(acc["username"], pwd)
    return conn


def imap_fetch_summaries(conn, limit=FETCH_LIMIT):
    conn.select("INBOX")
    _, data = conn.uid("search", None, "ALL")
    ids = data[0].split() if data and data[0] else []
    ids = ids[-limit:]
    ids.reverse()
    messages = []
    for uid in ids:
        _, msgdata = conn.uid(
            "fetch", uid, "(FLAGS BODY.PEEK[HEADER.FIELDS (SUBJECT FROM DATE)])"
        )
        flags, header_bytes = (), b""
        if msgdata and msgdata[0] and isinstance(msgdata[0], tuple):
            meta, header_bytes = msgdata[0][0], msgdata[0][1]
            meta_s = meta.decode(errors="replace") if isinstance(meta, bytes) else str(meta)
            flags = tuple(re.findall(r"\\\w+", meta_s))
        msg = message_from_bytes(header_bytes)
        messages.append({
            "uid": uid.decode(),
            "subject": decode_mime(msg.get("Subject", "")) or "(no subject)",
            "from": decode_mime(msg.get("From", "")),
            "date": msg.get("Date", ""),
            "seen": "\\Seen" in flags,
        })
    return messages


def imap_fetch_full(conn, uid):
    conn.select("INBOX")
    u = uid.encode() if isinstance(uid, str) else uid
    _, msgdata = conn.uid("fetch", u, "(RFC822)")
    if not msgdata or not msgdata[0]:
        raise RuntimeError("message not found (it may have been deleted on the server)")
    return msgdata[0][1]


def imap_set_seen(conn, uid, seen):
    conn.select("INBOX")
    u = uid.encode() if isinstance(uid, str) else uid
    conn.uid("store", u, "+FLAGS" if seen else "-FLAGS", "(\\Seen)")


def imap_delete(conn, uid):
    conn.select("INBOX")
    u = uid.encode() if isinstance(uid, str) else uid
    conn.uid("store", u, "+FLAGS", "(\\Deleted)")
    conn.expunge()


def pop3_connect(acc, pwd):
    host, port, sec = acc["recv_host"], acc["recv_port"], acc["recv_security"]
    if sec == "ssl":
        conn = poplib.POP3_SSL(host, port)
    else:
        conn = poplib.POP3(host, port)
        if sec == "starttls":
            conn.stls(context=ssl.create_default_context())
    conn.user(acc["username"])
    conn.pass_(pwd)
    return conn


def pop3_fetch_summaries(conn, limit=FETCH_LIMIT):
    count, _ = conn.stat()
    start = max(1, count - limit + 1)
    messages = []
    for i in range(count, start - 1, -1):
        try:
            _, lines, _octets = conn.top(i, 0)
        except Exception:
            continue
        msg = message_from_bytes(b"\r\n".join(lines))
        messages.append({
            "uid": str(i),
            "subject": decode_mime(msg.get("Subject", "")) or "(no subject)",
            "from": decode_mime(msg.get("From", "")),
            "date": msg.get("Date", ""),
            "seen": True,
        })
    return messages


def pop3_fetch_full(conn, index):
    _, lines, _octets = conn.retr(index)
    return b"\r\n".join(lines)


def smtp_send(acc, pwd, to, cc, subject, body, in_reply_to):
    msg = MIMEText(body, "plain", "utf-8")
    msg["Subject"] = subject
    msg["From"] = formataddr((acc["name"], acc["email"]))
    msg["To"] = to
    if cc:
        msg["Cc"] = cc
    msg["Date"] = formatdate(localtime=True)
    if in_reply_to:
        msg["In-Reply-To"] = in_reply_to
        msg["References"] = in_reply_to
    recipients = [a.strip() for a in to.split(",") if a.strip()]
    if cc:
        recipients += [a.strip() for a in cc.split(",") if a.strip()]

    host, port, sec = acc["smtp_host"], acc["smtp_port"], acc["smtp_security"]
    if sec == "ssl":
        server = smtplib.SMTP_SSL(host, port, timeout=20)
    else:
        server = smtplib.SMTP(host, port, timeout=20)
        if sec == "starttls":
            server.starttls(context=ssl.create_default_context())
    try:
        server.login(acc["username"], pwd)
        server.sendmail(acc["email"], recipients, msg.as_string())
    finally:
        try:
            server.quit()
        except Exception:
            pass


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------

def account_item(acc):
    proto = acc["protocol"].upper()
    return {
        "id": acc["id"],
        "title": acc["name"],
        "subtitle": f"{acc['email']} · {proto}",
        "icon": "mail",
        "accessories": [{"text": proto, "color": "#3B82F6" if acc["protocol"] == "imap" else "#8250DF"}],
        "actions": [
            {"id": "compose", "title": "Compose new email", "icon": "edit"},
            {"id": "test", "title": "Test connection", "icon": "bolt"},
            {"id": "remove", "title": "Remove account", "icon": "trash", "destructive": True,
             "confirm": {"title": "Remove this account?",
                         "message": "This deletes the stored credentials from this device.",
                         "confirmLabel": "Remove"}},
        ],
    }


def render_root(rev):
    q = STATE.get("query", "").strip().lower()
    accounts = STATE["accounts"]
    filtered = [a for a in accounts
                if not q or q in a["name"].lower() or q in a["email"].lower()]
    frame = {
        "type": "render", "rev": rev, "view": "list",
        "placeholder": "Search accounts, or add a new one…",
        "actions": [{"id": "add", "title": "Add account", "icon": "add"}],
        "items": [account_item(a) for a in filtered],
    }
    if not accounts:
        frame["empty"] = {
            "icon": "mail", "title": "No email accounts yet",
            "hint": "Add Gmail, Yahoo, or any IMAP/POP3 + SMTP server.",
            "action": {"id": "add", "title": "Add account", "icon": "add"},
        }
    elif not filtered:
        frame["emptyText"] = "No accounts match your search"
    send(frame)


def build_msg_actions(m, acc):
    actions = [{"id": "reply", "title": "Reply", "icon": "edit"}]
    if acc and acc["protocol"] == "imap":
        if m.get("seen", True):
            actions.append({"id": "mark_unread", "title": "Mark as unread", "icon": "mail"})
        else:
            actions.append({"id": "mark_read", "title": "Mark as read", "icon": "check"})
    actions.append({"id": "delete", "title": "Delete", "icon": "trash", "destructive": True,
                     "confirm": {"title": "Delete this email?",
                                 "message": "This deletes it on the mail server.",
                                 "confirmLabel": "Delete"}})
    return actions


def render_inbox(rev):
    acc = get_account(STATE["account_id"])
    q = STATE.get("query", "").strip().lower()
    msgs = STATE["messages"]
    filtered = [m for m in msgs
                if not q or q in m["subject"].lower() or q in m["from"].lower()]
    items = []
    for m in filtered:
        badges = [{"text": "Unread", "color": "#3B82F6"}] if not m.get("seen", True) else []
        items.append({
            "id": m["uid"],
            "title": m["subject"],
            "subtitle": m["from"],
            "icon": "mail" if not m.get("seen", True) else "check",
            "section": bucket_label(m.get("date", "")),
            "accessories": badges + [{"text": short_date(m.get("date", ""))}],
            "actions": build_msg_actions(m, acc),
        })
    frame = {
        "type": "render", "rev": rev, "view": "list", "canGoBack": True,
        "placeholder": f"Search {acc['name']}…" if acc else "Search…",
        "actions": [
            {"id": "compose", "title": "Compose new email", "icon": "edit"},
            {"id": "refresh", "title": "Refresh", "icon": "refresh"},
        ],
        "items": items,
        "emptyText": "No matching emails" if q else "No emails in this inbox",
    }
    if STATE.get("inbox_loading"):
        frame["loading"] = True
        frame["loadingText"] = "Fetching inbox…"
        frame["items"] = []
    send(frame)


def render_email(rev):
    e = STATE.get("current_email")
    if STATE.get("email_loading") or not e:
        send({"type": "render", "rev": rev, "view": "detail", "canGoBack": True,
              "loading": True, "loadingText": "Loading email…", "detail": {"markdown": ""}})
        return
    body = e["body"]
    truncated = len(body) > 20000
    md = f"# {e['subject']}\n\n" + md_safe_body(body[:20000])
    if truncated:
        md += "\n\n*(message truncated)*"
    metadata = [
        {"label": "From", "text": e["from"] or "—"},
        {"label": "To", "text": e["to"] or "—"},
    ]
    if e.get("cc"):
        metadata.append({"label": "Cc", "text": e["cc"]})
    metadata.append({"label": "Date", "text": e["date"] or "—"})

    acc = get_account(STATE["account_id"])
    actions = [
        {"id": "reply", "title": "Reply", "icon": "edit"},
        {"id": "delete", "title": "Delete", "icon": "trash", "destructive": True,
         "confirm": {"title": "Delete this email?", "message": "This deletes it on the mail server.",
                     "confirmLabel": "Delete"}},
    ]
    if acc and acc["protocol"] == "imap":
        actions.append({"id": "mark_unread", "title": "Mark as unread", "icon": "mail"})

    send({"type": "render", "rev": rev, "view": "detail", "canGoBack": True, "wide": True,
          "detail": {"markdown": md, "metadata": metadata}, "actions": actions})


def render_account_form(draft, errors=None):
    errors = errors or {}
    provider = draft.get("provider", "gmail")
    fields = [
        {"id": "name", "type": "text", "label": "Account name",
         "placeholder": "e.g. Personal Gmail", "required": True, "value": draft.get("name", "")},
        {"id": "email", "type": "text", "label": "Email address",
         "placeholder": "you@example.com", "required": True, "value": draft.get("email", "")},
        {"id": "provider", "type": "dropdown", "label": "Provider", "watch": True, "value": provider,
         "options": ["gmail", "yahoo", {"value": "custom", "label": "Custom / other server"}]},
        {"id": "protocol", "type": "dropdown", "label": "Receive via", "value": draft.get("protocol", "imap"),
         "options": [{"value": "imap", "label": "IMAP"}, {"value": "pop3", "label": "POP3"}]},
        {"id": "username", "type": "text", "label": "Login username (if different from email)",
         "value": draft.get("username", "")},
        {"id": "password", "type": "password", "label": "Password / app password", "required": True,
         "description": "Gmail and Yahoo require an app-specific password, not your normal login password."},
        {"id": "recv_host", "type": "text", "label": "Incoming server host", "required": True,
         "value": draft.get("recv_host", "")},
        {"id": "recv_port", "type": "number", "label": "Incoming server port",
         "value": draft.get("recv_port", 993)},
        {"id": "recv_security", "type": "dropdown", "label": "Incoming encryption",
         "value": draft.get("recv_security", "ssl"),
         "options": [{"value": "ssl", "label": "SSL/TLS"}, {"value": "starttls", "label": "STARTTLS"},
                     {"value": "none", "label": "None"}]},
        {"id": "smtp_host", "type": "text", "label": "Outgoing (SMTP) host", "required": True,
         "value": draft.get("smtp_host", "")},
        {"id": "smtp_port", "type": "number", "label": "Outgoing (SMTP) port",
         "value": draft.get("smtp_port", 587)},
        {"id": "smtp_security", "type": "dropdown", "label": "Outgoing encryption",
         "value": draft.get("smtp_security", "starttls"),
         "options": [{"value": "ssl", "label": "SSL/TLS"}, {"value": "starttls", "label": "STARTTLS"},
                     {"value": "none", "label": "None"}]},
    ]
    for f in fields:
        if f["id"] in errors:
            f["error"] = errors[f["id"]]
    send({"type": "render", "rev": 0, "view": "form", "canGoBack": True,
          "form": {"title": "Add email account", "submitLabel": "Save account", "fields": fields}})


def render_compose(to, subject, body, cc="", errors=None):
    errors = errors or {}
    acc = get_account(STATE.get("compose_account_id"))
    fields = [
        {"id": "to", "type": "text", "label": "To", "placeholder": "recipient@example.com",
         "required": True, "value": to},
        {"id": "cc", "type": "text", "label": "Cc", "value": cc},
        {"id": "subject", "type": "text", "label": "Subject", "required": True, "value": subject},
        {"id": "body", "type": "textarea", "label": "Message", "required": True, "value": body},
    ]
    for f in fields:
        if f["id"] in errors:
            f["error"] = errors[f["id"]]
    send({"type": "render", "rev": 0, "view": "form", "canGoBack": True,
          "form": {"title": f"New email · {acc['email']}" if acc else "New email",
                   "submitLabel": "Send", "fields": fields}})


def render_current(rev):
    screen = STATE["screen"]
    if screen == "root":
        render_root(rev)
    elif screen == "inbox":
        render_inbox(rev)
    elif screen == "email":
        render_email(rev)
    # add_account / compose ignore stray query re-renders; their own frames stand.


# --------------------------------------------------------------------------
# Actions / navigation
# --------------------------------------------------------------------------

def open_inbox(acc):
    STATE["screen"] = "inbox"
    STATE["account_id"] = acc["id"]
    STATE["query"] = ""
    STATE["messages"] = []
    STATE["inbox_loading"] = True
    render_inbox(0)
    send({"type": "command", "command": "setQuery", "text": " "})
    request_password(acc["id"], lambda pwd: threading.Thread(
        target=do_fetch_inbox, args=(acc, pwd), daemon=True).start())


def do_fetch_inbox(acc, pwd):
    try:
        if acc["protocol"] == "imap":
            conn = imap_connect(acc, pwd)
            msgs = imap_fetch_summaries(conn)
            try:
                conn.logout()
            except Exception:
                pass
        else:
            conn = pop3_connect(acc, pwd)
            msgs = pop3_fetch_summaries(conn)
            try:
                conn.quit()
            except Exception:
                pass
        if STATE["screen"] == "inbox" and STATE["account_id"] == acc["id"]:
            STATE["messages"] = msgs
            STATE["inbox_loading"] = False
            render_inbox(0)
    except Exception as e:
        log("inbox fetch error:", e)
        if STATE["screen"] == "inbox" and STATE["account_id"] == acc["id"]:
            STATE["inbox_loading"] = False
            toast(f"Couldn't connect: {e}", "error")
            render_inbox(0)


def open_email(acc, m):
    STATE["screen"] = "email"
    STATE["current_uid"] = m["uid"]
    STATE["current_email"] = None
    STATE["email_loading"] = True
    render_email(0)
    request_password(acc["id"], lambda pwd: threading.Thread(
        target=do_fetch_email, args=(acc, m, pwd), daemon=True).start())


def do_fetch_email(acc, m, pwd):
    try:
        if acc["protocol"] == "imap":
            conn = imap_connect(acc, pwd)
            raw = imap_fetch_full(conn, m["uid"])
            if not m.get("seen", True):
                try:
                    imap_set_seen(conn, m["uid"], True)
                    m["seen"] = True
                except Exception:
                    pass
            try:
                conn.logout()
            except Exception:
                pass
        else:
            conn = pop3_connect(acc, pwd)
            raw = pop3_fetch_full(conn, int(m["uid"]))
            try:
                conn.quit()
            except Exception:
                pass
        msg = message_from_bytes(raw)
        parsed = {
            "uid": m["uid"],
            "subject": decode_mime(msg.get("Subject", "")) or "(no subject)",
            "from": decode_mime(msg.get("From", "")),
            "to": decode_mime(msg.get("To", "")),
            "cc": decode_mime(msg.get("Cc", "")),
            "date": msg.get("Date", ""),
            "message_id": msg.get("Message-ID", ""),
            "body": extract_body(msg),
        }
        if STATE["screen"] == "email" and STATE.get("current_uid") == m["uid"]:
            STATE["current_email"] = parsed
            STATE["email_loading"] = False
            render_email(0)
    except Exception as e:
        log("email fetch error:", e)
        if STATE["screen"] == "email" and STATE.get("current_uid") == m["uid"]:
            STATE["email_loading"] = False
            toast(f"Couldn't load email: {e}", "error")


def delete_message(acc, m):
    toast("Deleting…", "progress")
    request_password(acc["id"], lambda pwd: threading.Thread(
        target=do_delete, args=(acc, m, pwd), daemon=True).start())


def do_delete(acc, m, pwd):
    try:
        if acc["protocol"] == "imap":
            conn = imap_connect(acc, pwd)
            imap_delete(conn, m["uid"])
            try:
                conn.logout()
            except Exception:
                pass
        else:
            conn = pop3_connect(acc, pwd)
            conn.dele(int(m["uid"]))
            conn.quit()
        STATE["messages"] = [x for x in STATE["messages"] if x["uid"] != m["uid"]]
        toast("Email deleted")
        STATE["screen"] = "inbox"
        render_inbox(0)
    except Exception as e:
        log("delete error:", e)
        toast(f"Delete failed: {e}", "error")


def toggle_seen(acc, m, seen, then_render):
    request_password(acc["id"], lambda pwd: threading.Thread(
        target=do_toggle_seen, args=(acc, m, pwd, seen, then_render), daemon=True).start())


def do_toggle_seen(acc, m, pwd, seen, then_render):
    try:
        conn = imap_connect(acc, pwd)
        imap_set_seen(conn, m["uid"], seen)
        try:
            conn.logout()
        except Exception:
            pass
        m["seen"] = seen
        if then_render == "inbox" and STATE["screen"] == "inbox":
            render_inbox(0)
        elif then_render == "email" and STATE["screen"] == "email":
            render_email(0)
    except Exception as e:
        log("toggle seen error:", e)
        toast(f"Failed: {e}", "error")


def open_compose(acc, to, subject, body, return_screen, cc="", in_reply_to=None):
    STATE["screen"] = "compose"
    STATE["compose_account_id"] = acc["id"]
    STATE["compose_return"] = return_screen
    STATE["compose_in_reply_to"] = in_reply_to
    render_compose(to, subject, body, cc)


def do_send(acc, pwd, to, cc, subject, body, in_reply_to):
    try:
        smtp_send(acc, pwd, to, cc, subject, body, in_reply_to)
        toast("Email sent")
        STATE["screen"] = STATE.get("compose_return", "root")
        render_current(0)
    except Exception as e:
        log("send error:", e)
        toast(f"Send failed: {e}", "error")


def do_test_connection(acc, pwd):
    try:
        if acc["protocol"] == "imap":
            conn = imap_connect(acc, pwd)
            conn.select("INBOX")
            try:
                conn.logout()
            except Exception:
                pass
        else:
            conn = pop3_connect(acc, pwd)
            conn.stat()
            conn.quit()
        toast(f"{acc['name']}: connected successfully")
    except Exception as e:
        log("test connection error:", e)
        toast(f"{acc['name']}: connection failed — {e}", "error")


def remove_account(acc):
    STATE["accounts"] = [a for a in STATE["accounts"] if a["id"] != acc["id"]]
    save_accounts()
    delete_password(acc["id"])
    if STATE["account_id"] == acc["id"]:
        STATE["screen"] = "root"
    render_root(0)
    toast(f"Removed {acc['name']}")


def handle_account_submit(values):
    provider = values.get("provider", "custom")
    account = {
        "id": str(uuid.uuid4())[:8],
        "name": values.get("name", "").strip(),
        "email": values.get("email", "").strip(),
        "provider": provider,
        "protocol": values.get("protocol", "imap"),
        "username": (values.get("username") or values.get("email", "")).strip(),
        "recv_host": values.get("recv_host", "").strip(),
        "recv_security": values.get("recv_security", "ssl"),
        "smtp_host": values.get("smtp_host", "").strip(),
        "smtp_security": values.get("smtp_security", "starttls"),
    }
    try:
        account["recv_port"] = int(values.get("recv_port") or 993)
    except (TypeError, ValueError):
        account["recv_port"] = 993
    try:
        account["smtp_port"] = int(values.get("smtp_port") or 587)
    except (TypeError, ValueError):
        account["smtp_port"] = 587

    password = values.get("password", "")
    STATE["accounts"].append(account)
    save_accounts()
    save_password(account["id"], password)
    STATE["screen"] = "root"
    STATE["query"] = ""
    render_root(0)
    send({"type": "command", "command": "setQuery", "text": " "})
    toast(f"Added {account['name']}")
    threading.Thread(target=do_test_connection, args=(account, password), daemon=True).start()


# --------------------------------------------------------------------------
# Event handlers
# --------------------------------------------------------------------------

def on_init(_msg):
    send({"type": "render", "rev": 0, "view": "list",
          "loading": True, "loadingText": "Loading accounts…", "items": []})
    request_storage("accounts", False, on_accounts_loaded)


def on_accounts_loaded(value):
    try:
        STATE["accounts"] = json.loads(value) if value else []
    except Exception:
        STATE["accounts"] = []
    STATE["loaded"] = True
    render_root(0)


def on_query(rev):
    if not STATE.get("loaded"):
        send({"type": "render", "rev": rev, "view": "list",
              "loading": True, "loadingText": "Loading accounts…", "items": []})
        return
    render_current(rev)


def handle_root_action(item_id, action):
    if item_id == "":
        if action == "add":
            render_account_form({})
            STATE["screen"] = "add_account"
        return
    acc = get_account(item_id)
    if not acc:
        return
    if action == "default":
        open_inbox(acc)
    elif action == "compose":
        open_compose(acc, "", "", "", return_screen="root")
    elif action == "test":
        request_password(acc["id"], lambda pwd: threading.Thread(
            target=do_test_connection, args=(acc, pwd), daemon=True).start())
    elif action == "remove":
        remove_account(acc)


def handle_inbox_action(item_id, action):
    acc = get_account(STATE["account_id"])
    if item_id == "":
        if action == "compose":
            open_compose(acc, "", "", "", return_screen="inbox")
        elif action == "refresh":
            open_inbox(acc)
        return
    m = get_message(item_id)
    if not m or not acc:
        return
    if action == "default":
        open_email(acc, m)
    elif action == "reply":
        open_compose(acc, extract_email_addr(m["from"]), reply_subject(m["subject"]), "",
                      return_screen="inbox")
    elif action == "mark_read":
        toggle_seen(acc, m, True, then_render="inbox")
    elif action == "mark_unread":
        toggle_seen(acc, m, False, then_render="inbox")
    elif action == "delete":
        delete_message(acc, m)


def handle_email_action(_item_id, action):
    acc = get_account(STATE["account_id"])
    e = STATE.get("current_email")
    if not acc or not e:
        return
    if action == "reply":
        body = quote_body(e["body"], e["from"], e["date"])
        open_compose(acc, extract_email_addr(e["from"]), reply_subject(e["subject"]), body,
                     return_screen="email", in_reply_to=e.get("message_id"))
    elif action == "delete":
        m = get_message(e["uid"]) or {"uid": e["uid"]}
        delete_message(acc, m)
    elif action == "mark_unread":
        m = get_message(e["uid"]) or {"uid": e["uid"]}
        toggle_seen(acc, m, False, then_render="email")


def handle_action(item_id, action):
    screen = STATE["screen"]
    if screen == "root":
        handle_root_action(item_id, action)
    elif screen == "inbox":
        handle_inbox_action(item_id, action)
    elif screen == "email":
        handle_email_action(item_id, action)


def handle_submit_msg(values, _button):
    if STATE["screen"] == "add_account":
        handle_account_submit(values)
    elif STATE["screen"] == "compose":
        acc = get_account(STATE.get("compose_account_id"))
        if not acc:
            return
        to = values.get("to", "").strip()
        cc = values.get("cc", "").strip()
        subject = values.get("subject", "").strip()
        body = values.get("body", "")
        toast("Sending…", "progress")
        request_password(acc["id"], lambda pwd: threading.Thread(
            target=do_send, args=(acc, pwd, to, cc, subject, body,
                                   STATE.get("compose_in_reply_to")), daemon=True).start())


def handle_change(field_id, values):
    if STATE["screen"] == "add_account" and field_id == "provider":
        provider = values.get("provider", "custom")
        draft = dict(values)
        preset = PROVIDER_PRESETS.get(provider)
        if preset:
            draft.update(preset)
        else:
            draft["recv_host"] = ""
            draft["smtp_host"] = ""
        render_account_form(draft)


def handle_back():
    screen = STATE["screen"]
    if screen == "inbox":
        STATE["screen"] = "root"
        render_root(0)
    elif screen == "email":
        STATE["screen"] = "inbox"
        render_inbox(0)
    elif screen == "add_account":
        STATE["screen"] = "root"
        render_root(0)
    elif screen == "compose":
        STATE["screen"] = STATE.get("compose_return", "root")
        render_current(0)
    else:
        STATE["screen"] = "root"
        render_root(0)


# --------------------------------------------------------------------------
# Main loop
# --------------------------------------------------------------------------

def dispatch(msg, t):
    if t in ("init", "query"):
        STATE["query"] = msg.get("text", msg.get("query", ""))
        if t == "init":
            on_init(msg)
        else:
            on_query(msg.get("rev", 0))
    elif t == "action":
        handle_action(msg.get("id", ""), msg.get("action", "default"))
    elif t == "submit":
        handle_submit_msg(msg.get("values", {}), msg.get("button"))
    elif t == "change":
        handle_change(msg.get("id", ""), msg.get("values", {}))
    elif t == "back":
        handle_back()
    elif t == "storage":
        cb = PENDING.pop(msg.get("requestId"), None)
        if cb:
            cb(msg.get("value"))
    # "select", "tab", "loadMore", "clipboard": unused by this plugin.


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
        try:
            dispatch(msg, t)
        except Exception as e:
            log("dispatch error:", e)


if __name__ == "__main__":
    main()
