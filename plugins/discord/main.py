#!/usr/bin/env python3
"""
Discord plugin for Tabame.

Browses your servers -> text channels -> recent messages, and lets you send
a message into a channel. Uses the Discord HTTP API directly with a user
token (the same token you'd find under Application > Local Storage > "token"
in Discord's web client devtools).

NOTE: automating a Discord *user* account like this ("self-botting") is
against Discord's Terms of Service and can get the account flagged or
banned. This plugin does nothing to hide that automation from Discord - use
at your own risk, on an account you're comfortable putting at risk.
"""

import json
import mimetypes
import os
import re
import shlex
import sys
import threading
import time
import uuid
from datetime import datetime, timezone
from urllib.parse import quote, unquote

try:
    import requests
except ImportError:
    requests = None

try:
    import websocket
except ImportError:
    websocket = None

API_BASE = "https://discord.com/api/v10"
GATEWAY_URL = "wss://gateway.discord.gg/?v=10&encoding=json"
MESSAGE_LIMIT = 50
MESSAGE_REFRESH_SECONDS = 15.0
REACTION_CHOICES = ["\U0001f44d", "\u2764\ufe0f", "\U0001f602", "\U0001f389", "\U0001f525", "\U0001f440"]
EMOJI_ALIAS_RE = re.compile(r"(?<!<):([A-Za-z0-9_]{2,32}):(?![0-9]+>)")
CUSTOM_EMOJI_RE = re.compile(r"^<a?:([A-Za-z0-9_]+):(\d+)>$")
CUSTOM_EMOJI_TOKEN_RE = re.compile(r"^([A-Za-z0-9_]+):(\d+)$")
MENTION_RE = re.compile(r"<@!?(\d+)>")
IMAGE_URL_RE = re.compile(
    r"https?://\S+\.(?:png|jpe?g|gif|webp)(?:\?\S*)?", re.IGNORECASE
)

_out_lock = threading.Lock()
_send_lock = threading.Lock()
_message_refresh_stop = threading.Event()
_gateway_stop = threading.Event()
_gateway_socket_lock = threading.Lock()
_gateway_socket = None
_gateway_thread = None


def send(frame):
    with _out_lock:
        sys.stdout.write(json.dumps(frame) + "\n")
        sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


state = {
    "screen": "loading",  # loading | need_token | guilds | channels | dms | forum_posts | messages | pins | slash_command
    "token": None,
    "guilds": [],
    "channels": [],
    "guild_id": None,
    "guild_name": "",
    "channel_id": None,
    "channel_name": "",
    "channel_topic": "",
    "channel_kind": "guild",
    "channel_type": 0,
    "channel_parent_id": None,
    "channel_categories": {},
    "messages": [],
    "messages_has_more": False,
    "message_search": None,
    "message_search_total": 0,
    "unread_counts": {},
    "typing_users": {},
    "dm_channels": [],
    "forum_threads": [],
    "forum_channel_id": None,
    "forum_channel_name": "",
    "last_channel": None,
    "current_user": {},
    "startup_token_ready": False,
    "startup_channel_ready": False,
    "opened_from_saved_channel": False,
    "emojis": {},
    "emoji_guild_id": None,
    "interaction_session_id": uuid.uuid4().hex,
    "pending_slash_command": None,
    "error_back_screen": None,
    "gateway_connected": False,
    "gateway_session_id": None,
    "gateway_resume_url": None,
    "gateway_sequence": None,
    "ack_token": None,
}


# ---------------------------------------------------------------- Discord API


class ApiError(Exception):
    pass


def _headers(json_content=True):
    headers = {
        "Authorization": state["token"],
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
    }
    if json_content:
        headers["Content-Type"] = "application/json"
    return headers


def api_get(path, params=None):
    if requests is None:
        raise ApiError("The 'requests' package failed to install.")
    r = requests.get(f"{API_BASE}{path}", headers=_headers(), params=params, timeout=15)
    if r.status_code == 401:
        raise ApiError("Token rejected (401). It may be expired or wrong.")
    if r.status_code == 429:
        raise ApiError("Rate limited by Discord (429). Wait a bit and retry.")
    if not r.ok:
        raise ApiError(f"Discord API error {r.status_code}: {r.text[:200]}")
    return r.json()


def api_post(path, payload, expect_json=True):
    if requests is None:
        raise ApiError("The 'requests' package failed to install.")
    r = requests.post(f"{API_BASE}{path}", headers=_headers(), json=payload, timeout=15)
    if r.status_code == 401:
        raise ApiError("Token rejected (401). It may be expired or wrong.")
    if r.status_code == 429:
        raise ApiError("Rate limited by Discord (429). Wait a bit and retry.")
    if not r.ok:
        raise ApiError(f"Discord API error {r.status_code}: {r.text[:200]}")
    if expect_json and r.content:
        return r.json()
    return None


def api_post_multipart(path, file_path, content="", reply_to=None):
    """Send a message with one local attachment through Discord's multipart API."""
    if requests is None:
        raise ApiError("The 'requests' package failed to install.")
    if not file_path or not os.path.isfile(file_path):
        raise ApiError("Choose an existing file to upload.")
    filename = os.path.basename(file_path)
    payload = {
        "content": expand_custom_emojis(content or ""),
        "attachments": [{"id": "0", "filename": filename}],
    }
    if reply_to:
        payload["message_reference"] = {
            "message_id": str(reply_to),
            "channel_id": str(state["channel_id"]),
            "fail_if_not_exists": False,
        }
    mime_type = mimetypes.guess_type(filename)[0] or "application/octet-stream"
    with open(file_path, "rb") as handle:
        response = requests.post(
            f"{API_BASE}{path}",
            headers=_headers(json_content=False),
            data={"payload_json": json.dumps(payload)},
            files={"files[0]": (filename, handle, mime_type)},
            timeout=60,
        )
    if response.status_code == 401:
        raise ApiError("Token rejected (401). It may be expired or wrong.")
    if response.status_code == 429:
        raise ApiError("Rate limited by Discord (429). Wait a bit and retry.")
    if not response.ok:
        raise ApiError(f"Discord API error {response.status_code}: {response.text[:200]}")
    return response.json() if response.content else None


def api_put(path, payload=None, expect_json=False):
    if requests is None:
        raise ApiError("The 'requests' package failed to install.")
    r = requests.put(f"{API_BASE}{path}", headers=_headers(), json=payload, timeout=15)
    if r.status_code == 401:
        raise ApiError("Token rejected (401). It may be expired or wrong.")
    if r.status_code == 429:
        raise ApiError("Rate limited by Discord (429). Wait a bit and retry.")
    if not r.ok:
        raise ApiError(f"Discord API error {r.status_code}: {r.text[:200]}")
    if expect_json and r.content:
        return r.json()
    return None


def api_patch(path, payload, expect_json=True):
    if requests is None:
        raise ApiError("The 'requests' package failed to install.")
    r = requests.patch(f"{API_BASE}{path}", headers=_headers(), json=payload, timeout=15)
    if r.status_code == 401:
        raise ApiError("Token rejected (401). It may be expired or wrong.")
    if r.status_code == 429:
        raise ApiError("Rate limited by Discord (429). Wait a bit and retry.")
    if not r.ok:
        raise ApiError(f"Discord API error {r.status_code}: {r.text[:200]}")
    if expect_json and r.content:
        return r.json()
    return None


def api_delete(path):
    if requests is None:
        raise ApiError("The 'requests' package failed to install.")
    r = requests.delete(f"{API_BASE}{path}", headers=_headers(), timeout=15)
    if r.status_code == 401:
        raise ApiError("Token rejected (401). It may be expired or wrong.")
    if r.status_code == 429:
        raise ApiError("Rate limited by Discord (429). Wait a bit and retry.")
    if not r.ok:
        raise ApiError(f"Discord API error {r.status_code}: {r.text[:200]}")


# ---------------------------------------------------------------- page helpers


def page_info(page_id, title, history="push", breadcrumbs=None):
    page = {"id": page_id, "title": title, "history": history, "preserveState": True}
    if breadcrumbs:
        page["breadcrumbs"] = breadcrumbs
    return page


def breadcrumb(page_id, label):
    return {"id": page_id, "label": label}


def common_actions(include_refresh=True):
    actions = []
    if include_refresh:
        actions.append({"id": "refresh", "title": "Refresh", "icon": "refresh", "shortcut": "ctrl+r"})
    actions.append({"id": "sign_out", "title": "Sign out", "icon": "lock", "destructive": True,
                    "confirm": {"title": "Sign out of Discord?", "message": "The saved token and last channel will be cleared.",
                                "confirmLabel": "Sign out"}})
    return actions


# ---------------------------------------------------------------- render helpers


def local_timestamp(timestamp):
    """Convert a Discord UTC timestamp (e.g. '2026-07-25T12:01:23.456000+00:00')
    to the local machine's time. Returns (date_str, time_str), each "" on
    failure/empty input."""
    if not timestamp:
        return "", ""
    try:
        dt = datetime.fromisoformat(timestamp)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        local = dt.astimezone()
    except ValueError:
        return "", ""
    return local.strftime("%Y-%m-%d"), local.strftime("%H:%M")


def render_error(rev, title, err, can_go_back=True, back_screen=None):
    state["screen"] = "error"
    state["error_back_screen"] = back_screen
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "canGoBack": can_go_back,
            "detail": {"markdown": f"# {title}\n\n```\n{err}\n```"},
        }
    )


def render_token_form(error=None):
    state["screen"] = "need_token"
    field = {
        "id": "token",
        "type": "password",
        "label": "Discord token",
        "placeholder": "paste your token here",
        "required": True,
        "description": (
            "From the Discord web app: DevTools > Application > Local "
            'Storage > discord.com > "token". Stored locally via Tabame\'s '
            "secret storage, never written to a plain file."
        ),
    }
    if error:
        field["error"] = error
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "form",
            "page": page_info("discord:connect", "Connect", history="none"),
            "form": {
                "title": "Connect your Discord account",
                "submitLabel": "Connect",
                "fields": [field],
            },
        }
    )


def render_guilds(rev, filter_text=""):
    state["screen"] = "guilds"
    items = [
        {
            "id": "dms",
            "title": "Direct messages",
            "subtitle": "Open your conversations",
            "icon": "person",
            "section": "Personal",
            "actions": [{"id": "default", "title": "Open direct messages", "icon": "open"}],
        }
    ]
    ft = (filter_text or "").strip().lower()
    for g in sorted(state["guilds"], key=lambda guild: (guild.get("name") or "").casefold()):
        name = g.get("name", "Unknown server")
        if ft and ft not in name.lower():
            continue
        icon_hash = g.get("icon")
        icon = "server"
        if icon_hash:
            icon = f"https://cdn.discordapp.com/icons/{g['id']}/{icon_hash}.png?size=64"
        items.append(
            {
                "id": f"guild:{g['id']}",
                "title": name,
                "subtitle": "Open channels",
                "icon": icon,
                "actions": [
                    {"id": "default", "title": "Open channels", "icon": "open"}
                ],
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "emptyText": "No matching servers"
            if ft
            else "No servers found on this account",
            "placeholder": "Filter servers…",
            "items": items,
            "page": page_info("discord:home", "Servers", history="none"),
            "actions": common_actions(),
            "empty": {
                "icon": "server",
                "title": "No servers found",
                "hint": "Your account has no servers matching this filter.",
            },
        }
    )


def render_channels(rev, filter_text=""):
    state["screen"] = "channels"
    items = []
    ft = (filter_text or "").strip().lower()
    channels = sorted(state["channels"], key=lambda channel: channel.get("position", 0))
    for c in channels:
        name = c.get("name", "unknown")
        if ft and ft not in name.lower():
            continue
        parent_id = c.get("parent_id")
        section = state["channel_categories"].get(parent_id, "Text channels")
        channel_type = c.get("type")
        if channel_type == 15:
            default_subtitle = "Forum"
        elif channel_type in (10, 11, 12):
            default_subtitle = "Thread"
            section = state["channel_categories"].get(parent_id, "Threads")
        else:
            default_subtitle = "Announcement channel" if channel_type == 5 else "Text channel"
        subtitle = c.get("topic") or default_subtitle
        accessories = []
        if channel_type == 5:
            accessories.append({"text": "news", "icon": "bell", "color": "#E6A23C"})
        if channel_type == 15:
            accessories.append({"text": "forum", "icon": "chat", "color": "#7AA2F7"})
        unread = state["unread_counts"].get(str(c.get("id")), 0)
        if unread:
            accessories.append({"text": str(unread), "icon": "bell", "color": "#E6A23C"})
        items.append(
            {
                "id": f"channel:{c['id']}",
                "title": f"# {name}",
                "subtitle": subtitle,
                "icon": "chat",
                "section": section,
                "lines": 2,
                "accessories": accessories,
                "actions": [{"id": "default", "title": "Open channel", "icon": "open"}],
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "emptyText": "No matching channels" if ft else "No text channels found",
            "placeholder": f"Filter #channels in {state['guild_name']}…",
            "items": items,
            "page": page_info(
                f"discord:guild:{state['guild_id']}:channels",
                state["guild_name"],
                breadcrumbs=[breadcrumb("discord:home", "Servers")],
            ),
            "actions": [
                {"id": "refresh", "title": "Refresh channels", "icon": "refresh", "shortcut": "ctrl+r"},
                {"id": "dms", "title": "Direct messages", "icon": "person"},
                {"id": "servers", "title": "All servers", "icon": "server"},
                *common_actions(include_refresh=False),
            ],
            "empty": {
                "icon": "chat",
                "title": "No text channels",
                "hint": "This server does not expose any readable text channels, threads, or forums.",
            },
        }
    )


def dm_display_name(channel):
    recipients = [user for user in channel.get("recipients") or [] if isinstance(user, dict)]
    if channel.get("name"):
        return channel["name"]
    names = [mention_display_name(user) for user in recipients]
    if channel.get("type") == 3 and names:
        return ", ".join(names)
    return names[0] if names else "Direct message"


def render_dms(rev, filter_text=""):
    state["screen"] = "dms"
    items = []
    ft = (filter_text or "").strip().casefold()
    channels = sorted(
        state["dm_channels"],
        key=lambda channel: (channel.get("last_message_id") or "", dm_display_name(channel).casefold()),
        reverse=True,
    )
    for channel in channels:
        channel_id = str(channel.get("id") or "")
        name = dm_display_name(channel)
        if not channel_id or (ft and ft not in name.casefold()):
            continue
        recipients = [user for user in channel.get("recipients") or [] if isinstance(user, dict)]
        avatar = message_avatar(recipients[0]) if recipients else "person"
        accessories = []
        unread = state["unread_counts"].get(channel_id, 0)
        if unread:
            accessories.append({"text": str(unread), "icon": "bell", "color": "#E6A23C"})
        items.append(
            {
                "id": f"dm:{channel_id}",
                "title": name,
                "subtitle": "Group DM" if channel.get("type") == 3 else "Direct message",
                "icon": avatar,
                "accessories": accessories,
                "section": "Direct messages",
                "actions": [{"id": "default", "title": "Open conversation", "icon": "open"}],
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "emptyText": "No matching conversations" if ft else "No direct messages found",
            "placeholder": "Filter direct messages…",
            "items": items,
            "page": page_info(
                "discord:dms",
                "Direct messages",
                breadcrumbs=[breadcrumb("discord:home", "Servers")],
            ),
            "actions": [
                {"id": "refresh_dms", "title": "Refresh conversations", "icon": "refresh", "shortcut": "ctrl+r"},
                {"id": "servers", "title": "All servers", "icon": "server"},
                *common_actions(include_refresh=False),
            ],
            "empty": {
                "icon": "person",
                "title": "No direct messages",
                "hint": "Your account does not have any open DM conversations.",
            },
        }
    )


def embed_text_lines(embed):
    """Pull the human-readable text out of a Discord embed. Bots commonly send
    an empty `content` and put everything - title, description, fields - in
    an embed instead, which is why plain content-only rendering was showing
    '[no text content]' for them."""
    lines = []
    author_name = (embed.get("author") or {}).get("name")
    if author_name:
        lines.append(f"**{author_name}**")
    title = embed.get("title")
    if title:
        lines.append(f"**{title}**")
    description = embed.get("description")
    if description:
        lines.append(description)
    for field in embed.get("fields") or []:
        name = (field.get("name") or "").strip()
        value = (field.get("value") or "").strip()
        if name and value:
            lines.append(f"**{name}**: {value}")
        elif value:
            lines.append(value)
    footer_text = (embed.get("footer") or {}).get("text")
    if footer_text:
        lines.append(f"_{footer_text}_")
    return lines


def embed_image_urls(embed):
    urls = []
    image_url = (embed.get("image") or {}).get("url")
    if image_url:
        urls.append(image_url)
    thumb_url = (embed.get("thumbnail") or {}).get("url")
    if thumb_url and thumb_url != image_url:
        urls.append(thumb_url)
    return urls


def mention_display_name(user):
    member = user.get("member") or {}
    return (
        member.get("nick")
        or user.get("global_name")
        or user.get("display_name")
        or user.get("username")
        or user.get("name")
        or str(user.get("id") or "unknown")
    )


def expand_message_mentions(text, message):
    """Replace Discord mention tokens with the names in the message payload."""
    if not text or "<@" not in text:
        return text
    mentions = {
        str(user.get("id")): user
        for user in message.get("mentions") or []
        if isinstance(user, dict) and user.get("id")
    }
    if not mentions:
        return text

    def replace(match):
        user = mentions.get(match.group(1))
        return f"@{mention_display_name(user)}" if user else match.group(0)

    return MENTION_RE.sub(replace, text)


def message_display(message):
    """Combine a message's raw content, embeds, attachments, and any bare
    image link typed in the text into (text, image_urls, file_names)."""
    content = message.get("content") or ""
    text_parts = [content] if content else []
    image_urls = []

    for embed in message.get("embeds") or []:
        text_parts.extend(embed_text_lines(embed))
        image_urls.extend(embed_image_urls(embed))

    poll = message.get("poll")
    if isinstance(poll, dict):
        question = (poll.get("question") or {}).get("text") if isinstance(poll.get("question"), dict) else poll.get("question")
        if question:
            text_parts.append(f"Poll: {question}")
        answers = []
        for answer in poll.get("answers") or []:
            if not isinstance(answer, dict):
                continue
            answer_text = answer.get("poll_media", {}).get("text") if isinstance(answer.get("poll_media"), dict) else None
            if answer_text:
                answers.append(str(answer_text))
        if answers:
            text_parts.append("Options: " + " · ".join(answers))

    sticker_names = [
        str(sticker.get("name"))
        for sticker in message.get("sticker_items") or []
        if isinstance(sticker, dict) and sticker.get("name")
    ]
    if sticker_names:
        text_parts.append("Sticker: " + ", ".join(sticker_names))

    component_labels = []
    for row in message.get("components") or []:
        components = row.get("components") if isinstance(row, dict) else None
        for component in components or []:
            if not isinstance(component, dict):
                continue
            label = component.get("label") or component.get("placeholder")
            if label:
                component_labels.append(str(label))
    if component_labels:
        text_parts.append("Buttons: " + " · ".join(component_labels))

    file_names = []
    for attachment in message.get("attachments") or []:
        content_type = attachment.get("content_type") or ""
        filename = attachment.get("filename", "attachment")
        is_image = content_type.startswith("image/") or filename.lower().endswith(
            (".png", ".jpg", ".jpeg", ".gif", ".webp")
        )
        if is_image and attachment.get("url"):
            image_urls.append(attachment["url"])
        else:
            file_names.append(filename)

    if content:
        image_urls.extend(IMAGE_URL_RE.findall(content))

    image_urls = list(dict.fromkeys(image_urls))  # dedupe, preserve order
    text = "\n".join(part for part in text_parts if part).strip()
    text = expand_message_mentions(text, message)
    return text, image_urls, file_names


def message_reply_preview(message):
    reference = message.get("referenced_message")
    reference_info = message.get("message_reference") or {}
    reference_id = reference_info.get("message_id")
    if not isinstance(reference, dict) and reference_id:
        reference = next(
            (candidate for candidate in state["messages"] if str(candidate.get("id")) == str(reference_id)),
            None,
        )

    if not isinstance(reference, dict):
        if not reference_id:
            return None
        return {"author": "Reply", "text": "Original message unavailable."}

    author = reference.get("author") or {}
    text, image_urls, file_names = message_display(reference)
    if text:
        quote_text = " ".join(text.split())
    elif image_urls:
        quote_text = "Image"
    elif file_names:
        quote_text = f"Attachment: {', '.join(file_names)}"
    else:
        quote_text = "Empty message"
    if len(quote_text) > 180:
        quote_text = f"{quote_text[:177].rstrip()}..."
    return {
        "author": mention_display_name(author),
        "text": quote_text,
        "icon": message_avatar(author),
    }


def format_messages_markdown():
    if not state["messages"]:
        return f"# #{state['channel_name']}\n\n_No messages yet._"
    lines = [f"# #{state['channel_name']}", ""]
    for m in reversed(state["messages"]):  # API returns newest first
        author = m.get("author", {}).get("username", "unknown")
        text, image_urls, file_names = message_display(m)
        date_part, time_part = local_timestamp(m.get("timestamp") or "")
        ts = f"{date_part} {time_part}".strip()
        lines.append(f"**{author}** · _{ts}_")
        if text:
            lines.append(f"> {text.replace(chr(10), chr(10) + '> ')}")
        for url in image_urls:
            lines.append(f"> ![]({url})")
        if file_names:
            lines.append(f"> attachment: {', '.join(file_names)}")
        if not text and not image_urls and not file_names:
            lines.append("> _[no text content]_")
        lines.append("")
    return "\n".join(lines)


def message_avatar(author):
    avatar = author.get("avatar")
    author_id = author.get("id")
    if avatar and author_id:
        return f"https://cdn.discordapp.com/avatars/{author_id}/{avatar}.png?size=64"
    return "person"


def reaction_accessories(message):
    accessories = []
    for reaction in message.get("reactions") or []:
        if not isinstance(reaction, dict):
            continue
        emoji = reaction.get("emoji") or {}
        label = emoji.get("name") or "?"
        count = reaction.get("count", 0)
        if count:
            accessories.append({
                "text": f"{label} {count}",
                "icon": "heart",
                "color": "#7AA2F7" if reaction.get("me") else "#E6A0B5",
            })
    return accessories


def message_actions(message, text):
    actions = [
        {"id": "copy", "title": "Copy message", "icon": "copy"},
        {
            "id": "reply",
            "title": "Reply",
            "icon": "reply",
            "parameters": [
                {
                    "id": "content",
                    "type": "textarea",
                    "label": "Reply",
                    "placeholder": "Write a reply…",
                    "required": True,
                    "minLength": 1,
                    "maxLength": 2000,
                }
            ],
        },
        {
            "id": "react",
            "title": "Add reaction",
            "icon": "heart",
            "parameters": [
                {
                    "id": "emoji",
                    "type": "combobox",
                    "label": "Reaction",
                    "placeholder": "👍 or :server_emoji:",
                    "description": "Type :emoji_name: for a server emoji, or paste <:name:id>.",
                    "options": REACTION_CHOICES,
                    "value": REACTION_CHOICES[0],
                    "allowCustom": True,
                    "required": True,
                }
            ],
        },
        {
            "id": "pin",
            "title": "Pin message",
            "icon": "pin",
            "destructive": False,
            "confirm": {
                "title": "Pin this message?",
                "message": "Pinned messages are visible to everyone with access to this channel.",
                "confirmLabel": "Pin",
            },
        },
    ]
    links = []
    for embed in message.get("embeds") or []:
        if isinstance(embed, dict) and embed.get("url"):
            links.append(("Open embed", embed["url"]))
    for row in message.get("components") or []:
        components = row.get("components") if isinstance(row, dict) else None
        for component in components or []:
            if isinstance(component, dict) and component.get("url"):
                links.append((component.get("label") or "Open link", component["url"]))
    seen_links = set()
    for label, url in links:
        if url in seen_links:
            continue
        seen_links.add(url)
        actions.append({"id": f"open_url:{quote(str(url), safe='')}", "title": str(label), "icon": "open"})
    poll = message.get("poll")
    if isinstance(poll, dict):
        for answer in poll.get("answers") or []:
            if not isinstance(answer, dict) or not answer.get("answer_id"):
                continue
            media = answer.get("poll_media") or {}
            label = media.get("text") or f"Option {answer['answer_id']}"
            actions.append({"id": f"poll_vote:{answer['answer_id']}", "title": f"Vote: {label}", "icon": "check"})
    author_id = (message.get("author") or {}).get("id")
    current_user_id = state.get("current_user", {}).get("id")
    if author_id and current_user_id and author_id == current_user_id and not str(message.get("id", "")).startswith("pending:"):
        actions.extend(
            [
                {
                    "id": "edit",
                    "title": "Edit message",
                    "icon": "edit",
                    "parameters": [
                        {
                            "id": "content",
                            "type": "textarea",
                            "label": "Message",
                            "value": text,
                            "required": True,
                            "minLength": 1,
                            "maxLength": 2000,
                        }
                    ],
                },
                {
                    "id": "delete",
                    "title": "Delete message",
                    "icon": "delete",
                    "destructive": True,
                    "confirm": {
                        "title": "Delete this message?",
                        "message": "This cannot be undone.",
                        "confirmLabel": "Delete",
                    },
                },
            ]
        )
    return actions


def message_items():
    items = []
    for message in reversed(state["messages"]):  # API returns newest first
        author = message.get("author", {})
        text, image_urls, file_names = message_display(message)
        reply = message_reply_preview(message)
        subtitle_parts = []
        if text:
            subtitle_parts.append(text)
        if file_names:
            subtitle_parts.append(f"attachment: {', '.join(file_names)}")
        if not subtitle_parts and not image_urls:
            subtitle_parts.append("[no text content]")
        timestamp = message.get("timestamp") or ""
        local_date, local_time = local_timestamp(timestamp)
        accessories = [{"text": local_time}] if local_time else []
        if message.get("edited_timestamp"):
            accessories.append({"text": "edited"})
        accessories.extend(reaction_accessories(message))
        if message.get("pending"):
            accessories.append({"text": "sending...", "icon": "clock"})
        items.append(
            {
                "id": f"message:{message['id']}",
                "title": mention_display_name(author),
                "subtitle": "\n".join(subtitle_parts),
                "icon": message_avatar(author),
                "images": image_urls,
                "section": local_date,
                "accessories": accessories,
                "lines": 3,
                "reply": reply,
                "actions": message_actions(message, text),
            }
        )
    return items


def render_messages(rev=0):
    state["screen"] = "messages"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "chat",
            "canGoBack": True,
            "inputMode": "submit",
            "placeholder": f"Message #{state['channel_name']}…",
            "wide": True,
            "detail": {"wide": True},
            "emptyText": f"No messages in #{state['channel_name']} yet",
            "items": message_items(),
            "page": page_info(
                f"discord:channel:{state['channel_id']}",
                f"# {state['channel_name']}",
                breadcrumbs=[
                    breadcrumb("discord:home", "Servers"),
                    breadcrumb(
                        f"discord:guild:{state['guild_id']}:channels",
                        state["guild_name"],
                    ),
                ],
            ),
            "actions": [
                {"id": "refresh", "title": "Refresh messages", "icon": "refresh", "shortcut": "ctrl+r"},
                {"id": "channels", "title": "Channel list", "icon": "list"},
                {"id": "servers", "title": "All servers", "icon": "server"},
                *common_actions(include_refresh=False),
            ],
            "empty": {
                "icon": "chat",
                "title": f"#{state['channel_name']} is quiet",
                "hint": "Send the first message with the composer above.",
            },
        }
    )


def current_typing_text():
    now = time.time()
    active = []
    for user_id, started in list(state["typing_users"].items()):
        if now - started > 8:
            state["typing_users"].pop(user_id, None)
            continue
        user = state.get("typing_user_cache", {}).get(user_id) or {}
        active.append(mention_display_name(user) if user else "Someone")
    if not active:
        return None
    if len(active) == 1:
        return f"{active[0]} is typing…"
    if len(active) == 2:
        return f"{active[0]} and {active[1]} are typing…"
    return f"{active[0]} and {len(active) - 1} others are typing…"


def channel_page_info():
    if state["channel_kind"] == "dm":
        return page_info(
            f"discord:dm:{state['channel_id']}",
            state["channel_name"],
            breadcrumbs=[breadcrumb("discord:home", "Servers"), breadcrumb("discord:dms", "Direct messages")],
        )
    return page_info(
        f"discord:channel:{state['channel_id']}",
        f"# {state['channel_name']}",
        breadcrumbs=[
            breadcrumb("discord:home", "Servers"),
            breadcrumb(f"discord:guild:{state['guild_id']}:channels", state["guild_name"]),
        ],
    )


def mention_options():
    users = {}
    for message in state.get("messages", []):
        for user in [message.get("author")] + list(message.get("mentions") or []):
            if isinstance(user, dict) and user.get("id"):
                users[str(user["id"])] = user
    return [
        {"value": f"<@{user_id}>", "label": f"@{mention_display_name(user)}"}
        for user_id, user in sorted(users.items(), key=lambda entry: mention_display_name(entry[1]).casefold())
    ]


# This definition intentionally sits next to the original simple renderer so
# older cached plugin processes can be upgraded without changing their page
# identity.  It adds the chat toolbar and pagination while retaining the same
# chat protocol shape.
def render_messages(rev=0):
    state["screen"] = "messages"
    is_dm = state["channel_kind"] == "dm"
    channel_prefix = "" if is_dm else "#"
    title = state["channel_name"] if is_dm else f"# {state['channel_name']}"
    search_query = state.get("message_search")
    actions = [
        {"id": "refresh", "title": "Refresh messages", "icon": "refresh", "shortcut": "ctrl+r"},
        {
            "id": "search",
            "title": "Search messages",
            "icon": "search",
            "parameters": [
                {
                    "id": "query",
                    "type": "text",
                    "label": "Search",
                    "placeholder": "Find messages in this channel…",
                    "required": True,
                    "minLength": 1,
                    "maxLength": 100,
                }
            ],
        },
        {
            "id": "attach",
            "title": "Attach file",
            "icon": "paperclip",
            "parameters": [
                {"id": "file", "type": "filepicker", "label": "File", "required": True},
                {
                    "id": "content",
                    "type": "textarea",
                    "label": "Message",
                    "placeholder": "Add a caption (optional)…",
                    "maxLength": 2000,
                },
            ],
        },
        {
            "id": "mention",
            "title": "Mention someone",
            "icon": "person",
            "parameters": [
                {
                    "id": "user",
                    "type": "combobox",
                    "label": "User",
                    "placeholder": "Choose a user…",
                    "options": mention_options(),
                    "allowCustom": True,
                    "required": True,
                }
            ],
        },
        {"id": "view_pins", "title": "Pinned messages", "icon": "pin"},
    ]
    if search_query:
        actions.insert(1, {"id": "clear_search", "title": "Clear search", "icon": "close"})
    if is_dm:
        actions.append({"id": "dms", "title": "Direct messages", "icon": "person"})
    else:
        actions.extend(
            [
                {"id": "channels", "title": "Channel list", "icon": "list"},
                {"id": "servers", "title": "All servers", "icon": "server"},
            ]
        )
    actions.extend(common_actions(include_refresh=False))
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "chat",
            "canGoBack": True,
            "inputMode": "submit",
            "placeholder": f"Message {channel_prefix}{state['channel_name']}…",
            "wide": True,
            "detail": {"wide": True},
            "emptyText": f"No messages in {title} yet",
            "items": message_items(),
            "hasMore": bool(state["messages_has_more"] and not search_query),
            "typing": current_typing_text(),
            "page": channel_page_info(),
            "actions": actions,
            "empty": {
                "icon": "chat",
                "title": f"{title} is quiet",
                "hint": "Send the first message with the composer above.",
            },
        }
    )


def stop_message_refresh():
    global _message_refresh_stop
    _message_refresh_stop.set()


def message_list(raw):
    if isinstance(raw, list):
        return [item for item in raw if isinstance(item, dict) and item.get("id")]
    if isinstance(raw, dict) and isinstance(raw.get("messages"), list):
        return message_list(raw["messages"])
    return []


def set_message_history(raw, has_more=None):
    messages = message_list(raw)
    state["messages"] = messages
    if has_more is None:
        has_more = len(messages) >= MESSAGE_LIMIT
    state["messages_has_more"] = bool(has_more)


def merge_gateway_message(message):
    message_id = str(message.get("id") or "")
    if not message_id:
        return
    existing = next(
        (index for index, candidate in enumerate(state["messages"]) if str(candidate.get("id")) == message_id),
        None,
    )
    if existing is None:
        state["messages"].insert(0, message)
    else:
        state["messages"][existing] = message


def remove_gateway_message(message_id):
    state["messages"] = [
        message for message in state["messages"] if str(message.get("id")) != str(message_id)
    ]


def start_message_refresh(channel_id):
    global _message_refresh_stop
    stop_message_refresh()
    stop = threading.Event()
    _message_refresh_stop = stop

    def work():
        while not stop.wait(MESSAGE_REFRESH_SECONDS):
            if (
                state["screen"] != "messages"
                or state["channel_id"] != channel_id
                or state.get("message_search")
            ):
                return
            if state.get("gateway_connected"):
                continue
            try:
                set_message_history(
                    api_get(
                        f"/channels/{channel_id}/messages", params={"limit": MESSAGE_LIMIT}
                    )
                )
                render_messages(0)
            except ApiError as e:
                # Keep the conversation on screen and retry on the next tick.
                log("message refresh failed:", e)

    threading.Thread(target=work, daemon=True).start()


# ---------------------------------------------------------------- async loaders


def load_guilds_async(rev):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "loading": True,
            "items": [],
            "loadingText": "Loading your servers…",
        }
    )

    def work():
        try:
            state["current_user"] = api_get("/users/@me")
            state["guilds"] = api_get("/users/@me/guilds")
            start_gateway()
            render_guilds(rev)
        except ApiError as e:
            render_error(rev, "Couldn't load servers", e, can_go_back=False)

    threading.Thread(target=work, daemon=True).start()


def load_channels_async(rev, guild_id, guild_name):
    state["guild_id"] = guild_id
    state["guild_name"] = guild_name
    state["emojis"] = {}
    state["emoji_guild_id"] = None
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "loading": True,
            "canGoBack": True,
            "items": [],
            "loadingText": f"Loading channels in {guild_name}…",
        }
    )

    def work():
        try:
            all_channels = api_get(f"/guilds/{guild_id}/channels")
            # 0=text, 5=announcement, 10-12=threads, 15=forum.
            state["channels"] = [c for c in all_channels if c.get("type") in (0, 5, 10, 11, 12, 15)]
            state["channel_categories"] = {
                c.get("id"): c.get("name", "Channels")
                for c in all_channels
                if c.get("type") == 4 and c.get("id")
            }
            render_channels(rev)
        except ApiError as e:
            render_error(rev, "Couldn't load channels", e, back_screen="guilds")

    threading.Thread(target=work, daemon=True).start()


def load_messages_async(rev, channel_id, channel_name, channel_topic=""):
    stop_message_refresh()
    state["channel_id"] = channel_id
    state["channel_name"] = channel_name
    state["channel_topic"] = channel_topic or ""
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "chat",
            "loading": True,
            "canGoBack": True,
            "loadingText": f"Loading #{channel_name}…",
            "wide": True,
            "detail": {"wide": True},
            "items": [],
        }
    )

    def work():
        try:
            if not state.get("current_user"):
                state["current_user"] = api_get("/users/@me")
            start_gateway()
            set_message_history(
                api_get(f"/channels/{channel_id}/messages", params={"limit": MESSAGE_LIMIT})
            )
            if state["messages"]:
                mark_channel_read_async(channel_id, state["messages"][0].get("id"))
            render_messages(rev)
            start_message_refresh(channel_id)
        except ApiError as e:
            back_screen = "channels"
            if "Missing Access" in str(e):
                forget_saved_channel(channel_id)
                back_screen = "guilds"
            render_error(
                rev, f"Couldn't load #{channel_name}", e, back_screen=back_screen
            )

    threading.Thread(target=work, daemon=True).start()


def load_messages_async(
    rev, channel_id, channel_name, channel_topic="", channel_kind="guild", channel_type=0, parent_id=None
):
    """Open either a guild channel/thread or a DM conversation."""
    stop_message_refresh()
    state["channel_id"] = str(channel_id)
    state["channel_name"] = channel_name or "conversation"
    state["channel_topic"] = channel_topic or ""
    state["channel_kind"] = channel_kind
    state["channel_type"] = channel_type or 0
    state["channel_parent_id"] = parent_id
    state["messages"] = []
    state["messages_has_more"] = False
    state["message_search"] = None
    state["message_search_total"] = 0
    state["unread_counts"][str(channel_id)] = 0
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "chat",
            "loading": True,
            "canGoBack": True,
            "loadingText": f"Loading {channel_name}…",
            "wide": True,
            "detail": {"wide": True},
            "items": [],
        }
    )

    def work():
        try:
            if not state.get("current_user"):
                state["current_user"] = api_get("/users/@me")
            start_gateway()
            set_message_history(
                api_get(f"/channels/{channel_id}/messages", params={"limit": MESSAGE_LIMIT})
            )
            if state["messages"]:
                mark_channel_read_async(channel_id, state["messages"][0].get("id"))
            render_messages(rev)
            start_message_refresh(str(channel_id))
        except ApiError as e:
            back_screen = "dms" if channel_kind == "dm" else "channels"
            if "Missing Access" in str(e):
                forget_saved_channel(str(channel_id))
                back_screen = "guilds"
            render_error(rev, f"Couldn't load {channel_name}", e, back_screen=back_screen)

    threading.Thread(target=work, daemon=True).start()


def load_more_messages_async():
    if (
        state["screen"] != "messages"
        or state.get("message_search")
        or not state.get("messages_has_more")
        or not state["messages"]
    ):
        return
    channel_id = state["channel_id"]
    before = state["messages"][-1].get("id")
    if not before:
        state["messages_has_more"] = False
        render_messages(0)
        return

    def work():
        try:
            older = message_list(
                api_get(
                    f"/channels/{channel_id}/messages",
                    params={"limit": MESSAGE_LIMIT, "before": before},
                )
            )
            known = {str(message.get("id")) for message in state["messages"]}
            state["messages"].extend(message for message in older if str(message.get("id")) not in known)
            state["messages_has_more"] = len(older) >= MESSAGE_LIMIT
            render_messages(0)
        except ApiError as e:
            log("message history load failed:", e)

    threading.Thread(target=work, daemon=True).start()


def load_dms_async(rev=0):
    stop_message_refresh()
    send({"type": "render", "rev": rev, "view": "list", "loading": True, "items": [], "loadingText": "Loading direct messages…"})

    def work():
        try:
            state["dm_channels"] = [
                channel
                for channel in message_list(api_get("/users/@me/channels"))
                if channel.get("type") in (1, 3)
            ]
            render_dms(rev)
        except ApiError as e:
            render_error(rev, "Couldn't load direct messages", e, can_go_back=True, back_screen="guilds")

    threading.Thread(target=work, daemon=True).start()


def render_forum_posts(rev=0):
    state["screen"] = "forum_posts"
    items = []
    for thread in state["forum_threads"]:
        if not isinstance(thread, dict) or not thread.get("id"):
            continue
        title = thread.get("name") or "Untitled post"
        message_count = thread.get("message_count") or thread.get("total_message_sent")
        subtitle = "Forum post"
        if message_count is not None:
            subtitle = f"{message_count} messages"
        items.append(
            {
                "id": f"thread:{thread['id']}",
                "title": title,
                "subtitle": subtitle,
                "icon": "chat",
                "accessories": ([{"text": "active", "icon": "dot"}] if not thread.get("archived") else []),
                "actions": [{"id": "default", "title": "Open post", "icon": "open"}],
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "emptyText": "No active forum posts",
            "placeholder": f"Filter posts in {state['forum_channel_name']}…",
            "items": items,
            "page": page_info(
                f"discord:forum:{state['forum_channel_id']}",
                state["forum_channel_name"],
                breadcrumbs=[breadcrumb("discord:home", "Servers"), breadcrumb(f"discord:guild:{state['guild_id']}:channels", state["guild_name"])],
            ),
            "actions": [
                {"id": "refresh_forum", "title": "Refresh posts", "icon": "refresh", "shortcut": "ctrl+r"},
                {
                    "id": "new_post",
                    "title": "New post",
                    "icon": "plus",
                    "parameters": [
                        {"id": "name", "type": "text", "label": "Post title", "required": True, "maxLength": 100},
                        {"id": "content", "type": "textarea", "label": "Message", "required": True, "maxLength": 2000},
                    ],
                },
                {"id": "channels", "title": "Channel list", "icon": "list"},
                *common_actions(include_refresh=False),
            ],
            "empty": {"icon": "chat", "title": "No forum posts", "hint": "Create the first post in this forum."},
        }
    )


def load_forum_posts_async(rev, forum_id, forum_name):
    stop_message_refresh()
    state["forum_channel_id"] = str(forum_id)
    state["forum_channel_name"] = forum_name or "Forum"
    send({"type": "render", "rev": rev, "view": "list", "loading": True, "canGoBack": True, "items": [], "loadingText": f"Loading {forum_name}…"})

    def work():
        try:
            result = api_get(f"/channels/{forum_id}/threads/active")
            state["forum_threads"] = result.get("threads", []) if isinstance(result, dict) else []
            render_forum_posts(rev)
        except ApiError as e:
            render_error(rev, f"Couldn't load {forum_name}", e, back_screen="channels")

    threading.Thread(target=work, daemon=True).start()


def render_pins(rev=0):
    state["screen"] = "pins"
    items = []
    for message in state.get("pinned_messages", []):
        author = message.get("author") or {}
        text, image_urls, file_names = message_display(message)
        subtitle = text or ("Image" if image_urls else ", ".join(file_names) or "[no text content]")
        items.append(
            {
                "id": f"pin:{message.get('id')}",
                "title": mention_display_name(author),
                "subtitle": subtitle,
                "icon": message_avatar(author),
                "images": image_urls,
                "lines": 3,
                "actions": [
                    {"id": "copy", "title": "Copy message", "icon": "copy"},
                    {"id": "unpin", "title": "Unpin message", "icon": "pin", "destructive": True},
                ],
            }
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "emptyText": "No pinned messages",
            "items": items,
            "page": page_info(
                f"discord:pins:{state['channel_id']}",
                "Pinned messages",
                breadcrumbs=[channel_page_info()],
            ),
            "actions": [
                {"id": "refresh_pins", "title": "Refresh pins", "icon": "refresh"},
                {"id": "back_to_channel", "title": "Back to channel", "icon": "chat"},
                *common_actions(include_refresh=False),
            ],
            "empty": {"icon": "pin", "title": "Nothing pinned", "hint": "Pin a message from its hover actions."},
        }
    )


def load_pins_async(rev=0):
    channel_id = state["channel_id"]
    send({"type": "render", "rev": rev, "view": "list", "loading": True, "canGoBack": True, "items": [], "loadingText": "Loading pinned messages…"})

    def work():
        try:
            state["pinned_messages"] = message_list(api_get(f"/channels/{channel_id}/pins"))
            render_pins(rev)
        except ApiError as e:
            render_error(rev, "Couldn't load pinned messages", e, back_screen="messages")

    threading.Thread(target=work, daemon=True).start()


def search_messages_async(query):
    query = str(query or "").strip()
    if not query:
        return
    channel_id = state["channel_id"]

    def work():
        try:
            result = api_get(
                f"/channels/{channel_id}/messages/search",
                params={"content": query, "limit": MESSAGE_LIMIT},
            )
            raw_messages = result.get("messages", []) if isinstance(result, dict) else result
            flattened = []
            for group in raw_messages or []:
                if isinstance(group, list):
                    flattened.extend(message_list(group))
                elif isinstance(group, dict):
                    flattened.append(group)
            state["messages"] = flattened
            state["message_search"] = query
            state["message_search_offset"] = len(flattened)
            state["message_search_total"] = result.get("total_results", len(flattened)) if isinstance(result, dict) else len(flattened)
            state["messages_has_more"] = len(flattened) < state["message_search_total"]
            stop_message_refresh()
            render_messages(0)
        except ApiError as e:
            render_error(0, "Couldn't search messages", e, back_screen="messages")

    threading.Thread(target=work, daemon=True).start()


def _gateway_send(payload):
    with _gateway_socket_lock:
        socket = _gateway_socket
    if socket is None:
        return False
    try:
        socket.send(json.dumps(payload))
        return True
    except Exception as error:
        log("gateway send failed:", error)
        return False


def _gateway_reaction(message, emoji, delta, user_id=None):
    if not isinstance(message, dict):
        return
    name = emoji.get("name") if isinstance(emoji, dict) else None
    emoji_id = str(emoji.get("id")) if isinstance(emoji, dict) and emoji.get("id") else None
    reactions = message.setdefault("reactions", [])
    match = next(
        (
            reaction
            for reaction in reactions
            if isinstance(reaction, dict)
            and str((reaction.get("emoji") or {}).get("id") or "") == str(emoji_id or "")
            and (reaction.get("emoji") or {}).get("name") == name
        ),
        None,
    )
    if match is None and delta > 0:
        match = {"count": 0, "me": False, "emoji": emoji}
        reactions.append(match)
    if match is None:
        return
    match["count"] = max(0, int(match.get("count", 0)) + delta)
    if user_id and str(user_id) == str((state.get("current_user") or {}).get("id")):
        match["me"] = delta > 0
    if match["count"] == 0:
        reactions.remove(match)


def _gateway_dispatch(event_type, data):
    if event_type == "READY":
        state["current_user"] = data.get("user") or state.get("current_user") or {}
        state["gateway_session_id"] = data.get("session_id")
        state["gateway_resume_url"] = data.get("resume_gateway_url") or GATEWAY_URL
        state["gateway_connected"] = True
        return

    channel_id = str(data.get("channel_id") or "") if isinstance(data, dict) else ""
    current_channel = str(state.get("channel_id") or "")
    if event_type in ("MESSAGE_CREATE", "MESSAGE_UPDATE"):
        author = data.get("author") or {}
        if channel_id == current_channel and state["screen"] == "messages" and not state.get("message_search"):
            # A successful send can race the optimistic placeholder. Remove a
            # matching pending row before inserting the gateway copy.
            if event_type == "MESSAGE_CREATE":
                pending_content = data.get("content") or ""
                state["messages"] = [
                    message
                    for message in state["messages"]
                    if not (message.get("pending") and message.get("content") == pending_content)
                ]
            merge_gateway_message(data)
            render_messages(0)
        elif event_type == "MESSAGE_CREATE":
            if str(author.get("id")) != str((state.get("current_user") or {}).get("id")):
                state["unread_counts"][channel_id] = state["unread_counts"].get(channel_id, 0) + 1
                if state["screen"] == "channels" and data.get("guild_id") == state.get("guild_id"):
                    render_channels(0)
                elif state["screen"] == "dms":
                    render_dms(0)
        return

    if event_type == "MESSAGE_DELETE":
        if channel_id == current_channel:
            remove_gateway_message(data.get("id"))
            if state["screen"] == "messages":
                render_messages(0)
        return

    if event_type in ("MESSAGE_REACTION_ADD", "MESSAGE_REACTION_REMOVE") and channel_id == current_channel:
        message = next(
            (candidate for candidate in state["messages"] if str(candidate.get("id")) == str(data.get("message_id"))),
            None,
        )
        if message:
            _gateway_reaction(
                message,
                data.get("emoji") or {},
                1 if event_type.endswith("ADD") else -1,
                data.get("user_id"),
            )
            if state["screen"] == "messages":
                render_messages(0)
        return

    if event_type == "MESSAGE_REACTION_REMOVE_ALL" and channel_id == current_channel:
        message = next(
            (candidate for candidate in state["messages"] if str(candidate.get("id")) == str(data.get("message_id"))),
            None,
        )
        if message:
            message["reactions"] = []
            if state["screen"] == "messages":
                render_messages(0)
        return

    if event_type == "MESSAGE_REACTION_REMOVE_EMOJI" and channel_id == current_channel:
        message = next(
            (candidate for candidate in state["messages"] if str(candidate.get("id")) == str(data.get("message_id"))),
            None,
        )
        if message:
            emoji = data.get("emoji") or {}
            message["reactions"] = [
                reaction
                for reaction in message.get("reactions") or []
                if (reaction.get("emoji") or {}).get("id") != emoji.get("id")
                or (reaction.get("emoji") or {}).get("name") != emoji.get("name")
            ]
            if state["screen"] == "messages":
                render_messages(0)
        return

    if event_type == "TYPING_START" and channel_id == current_channel:
        user_id = str(data.get("user_id") or "")
        if user_id:
            state.setdefault("typing_user_cache", {})[user_id] = (data.get("member") or {}).get("user") or {}
            state["typing_users"][user_id] = time.time()
            if state["screen"] == "messages":
                render_messages(0)


def _gateway_worker():
    global _gateway_socket
    backoff = 1.0
    while not _gateway_stop.is_set() and state.get("token"):
        if websocket is None:
            log("websocket-client is unavailable; using REST refresh fallback")
            return
        socket = None
        try:
            gateway_url = state.get("gateway_resume_url") or GATEWAY_URL
            socket = websocket.create_connection(gateway_url, timeout=30, enable_multithread=True)
            socket.settimeout(1)
            with _gateway_socket_lock:
                _gateway_socket = socket
            hello = json.loads(socket.recv())
            if hello.get("op") != 10:
                raise ApiError("Discord gateway did not send Hello.")
            interval = max(1.0, float(hello.get("d", {}).get("heartbeat_interval", 41250)) / 1000.0)
            session_id = state.get("gateway_session_id")
            sequence = state.get("gateway_sequence")
            if session_id and sequence is not None:
                _gateway_send({"op": 6, "d": {"token": state["token"], "session_id": session_id, "seq": sequence}})
            else:
                _gateway_send(
                    {
                        "op": 2,
                        "d": {
                            "token": state["token"],
                            "properties": {"os": "windows", "browser": "tabame", "device": "tabame"},
                            "presence": {"status": "online", "since": 0, "activities": [], "afk": False},
                        },
                    }
                )
            backoff = 1.0
            next_heartbeat = time.monotonic() + interval
            while not _gateway_stop.is_set() and state.get("token"):
                now = time.monotonic()
                if now >= next_heartbeat:
                    _gateway_send({"op": 1, "d": state.get("gateway_sequence")})
                    next_heartbeat = now + interval
                try:
                    raw = socket.recv()
                except Exception as error:
                    timeout_type = getattr(websocket, "WebSocketTimeoutException", None)
                    if timeout_type and isinstance(error, timeout_type):
                        continue
                    raise
                if not raw:
                    raise ApiError("Discord gateway closed the connection.")
                packet = json.loads(raw)
                if packet.get("s") is not None:
                    state["gateway_sequence"] = packet["s"]
                op = packet.get("op")
                if op == 0:
                    _gateway_dispatch(packet.get("t"), packet.get("d") or {})
                elif op == 1:
                    _gateway_send({"op": 1, "d": state.get("gateway_sequence")})
                elif op == 7:
                    break
                elif op == 9:
                    state["gateway_session_id"] = None
                    state["gateway_sequence"] = None
                    break
        except Exception as error:
            if not _gateway_stop.is_set():
                state["gateway_connected"] = False
                log("gateway connection failed:", error)
        finally:
            with _gateway_socket_lock:
                if _gateway_socket is socket:
                    _gateway_socket = None
            if socket is not None:
                try:
                    socket.close()
                except Exception:
                    pass
        state["gateway_connected"] = False
        if _gateway_stop.wait(backoff):
            return
        backoff = min(backoff * 2, 30.0)


def stop_gateway():
    global _gateway_stop, _gateway_thread, _gateway_socket
    _gateway_stop.set()
    with _gateway_socket_lock:
        socket = _gateway_socket
        _gateway_socket = None
    if socket is not None:
        try:
            socket.close()
        except Exception:
            pass
    state["gateway_connected"] = False
    _gateway_thread = None


def start_gateway():
    global _gateway_stop, _gateway_thread
    if websocket is None or not state.get("token"):
        return
    if _gateway_thread is not None and _gateway_thread.is_alive():
        return
    _gateway_stop = threading.Event()
    _gateway_thread = threading.Thread(target=_gateway_worker, daemon=True, name="discord-gateway")
    _gateway_thread.start()


def mark_channel_read_async(channel_id=None, message_id=None):
    channel_id = str(channel_id or state.get("channel_id") or "")
    message_id = str(message_id or "")
    if not channel_id or not message_id or message_id.startswith("pending:"):
        return

    channel_type = state.get("channel_type", 0)
    flags = 0
    if state.get("channel_kind") != "dm":
        flags |= 1  # IS_GUILD_CHANNEL
    if channel_type in (10, 11, 12):
        flags |= 2  # IS_THREAD
    payload = {"token": state.get("ack_token"), "last_viewed": (datetime.now(timezone.utc) - datetime(2015, 1, 1, tzinfo=timezone.utc)).days}
    if flags:
        payload["flags"] = flags

    def work():
        try:
            result = api_post(f"/channels/{channel_id}/messages/{message_id}/ack", payload)
            if isinstance(result, dict) and "token" in result:
                state["ack_token"] = result.get("token")
            state["unread_counts"][channel_id] = 0
        except ApiError as error:
            # Read acknowledgements are best-effort; the chat itself remains
            # usable if Discord's private read-state route changes.
            log("read acknowledgement failed:", error)

    threading.Thread(target=work, daemon=True, name="discord-read-ack").start()


def forget_saved_channel(channel_id):
    last = state.get("last_channel")
    if not isinstance(last, dict) or last.get("id") != channel_id:
        return
    state["last_channel"] = None
    state["opened_from_saved_channel"] = False
    send(
        {
            "type": "command",
            "command": "storage",
            "op": "delete",
            "key": "discord_last_channel",
        }
    )


def load_guild_emojis():
    guild_id = state["guild_id"]
    if not guild_id:
        return {}
    if state["emoji_guild_id"] == guild_id:
        return state["emojis"]

    emojis = api_get(f"/guilds/{guild_id}/emojis")
    state["emojis"] = {
        emoji.get("name"): emoji
        for emoji in emojis
        if isinstance(emoji, dict) and emoji.get("name") and emoji.get("id")
    }
    state["emoji_guild_id"] = guild_id
    return state["emojis"]


def expand_custom_emojis(text):
    """Convert :server_emoji: aliases to Discord's custom emoji markup."""
    if ":" not in text or not state["guild_id"]:
        return text
    emojis = load_guild_emojis()

    def replace(match):
        emoji = emojis.get(match.group(1))
        if not emoji:
            return match.group(0)
        prefix = "a" if emoji.get("animated") else ""
        return f"<{prefix}:{emoji['name']}:{emoji['id']}>"

    return EMOJI_ALIAS_RE.sub(replace, text)


def slash_command_options(command, option_values):
    """Convert Tabame form values (or typed positional values) to Discord options."""
    options = command.get("options") or []
    values = []
    for index, option in enumerate(options):
        option_type = option.get("type")
        if option_type in (1, 2):
            raise ApiError("Commands with subcommands are not supported yet.")
        field_id = f"option:{option['name']}"
        argument = option_values.get(field_id)
        if argument is None or argument == "":
            if option.get("required"):
                raise ApiError(f"/{command['name']} needs: {option['name']}")
            continue
        option_type = option.get("type")
        value = argument
        try:
            if option_type == 4:  # integer
                value = int(argument)
            elif option_type == 10:  # number
                value = float(argument)
            elif option_type == 5:  # boolean
                if isinstance(argument, bool):
                    value = argument
                elif str(argument).lower() in ("true", "false"):
                    value = str(argument).lower() == "true"
                else:
                    raise ValueError
        except ValueError as e:
            kind = "true or false" if option_type == 5 else "a number"
            raise ApiError(f"{option.get('name')} must be {kind}") from e
        values.append({"type": option_type, "name": option["name"], "value": value})
    return values


def slash_command_payload(command, option_values, channel_id):
    """Build the interaction payload for a flat Discord slash command."""
    values = slash_command_options(command, option_values)
    options = command.get("options") or []
    if len(option_values) > len(options):
        raise ApiError(f"/{command['name']} accepts {len(options)} option(s)")

    data = {
        "version": command["version"],
        "id": command["id"],
        "name": command["name"],
        "type": command.get("type", 1),
    }
    if values:
        data["options"] = values
    return {
        "type": 2,
        "application_id": command["application_id"],
        "guild_id": state["guild_id"],
        "channel_id": channel_id,
        "session_id": state["interaction_session_id"],
        "nonce": str(time.time_ns()),
        "data": data,
    }


def command_candidates(result):
    if isinstance(result, list):
        return result
    if not isinstance(result, dict):
        return []
    for key in ("application_commands", "commands"):
        commands = result.get(key)
        if isinstance(commands, list):
            return commands
    return []


def matching_slash_commands(commands, name):
    commands = [command for command in commands if isinstance(command, dict)]
    exact = [
        command
        for command in commands
        if command.get("name", "").casefold() == name.casefold()
    ]
    if exact:
        return exact

    # Treat punctuation as optional while searching: /ytdl can select /yt-dlp.
    normalized_name = re.sub(r"[^a-z0-9]", "", name.casefold())
    if not normalized_name:
        return []
    return [
        command
        for command in commands
        if re.sub(r"[^a-z0-9]", "", command.get("name", "").casefold()).startswith(
            normalized_name
        )
    ]


def search_application_commands(path, queries):
    """Collect command candidates from Discord's tokenized search endpoint.

    Returns (commands, errors). errors holds one entry per failed query so
    callers can tell "we looked and found nothing" apart from "the lookup
    itself failed" instead of treating both the same way.
    """
    commands = []
    seen_ids = set()
    errors = []
    for query in queries:
        try:
            result = api_get(
                path,
                params={
                    "type": 1,
                    "query": query,
                    "limit": 25,
                    "include_applications": "true",
                },
            )
        except ApiError as e:
            log("slash command search failed:", e)
            errors.append(str(e))
            continue
        for command in command_candidates(result):
            command_id = command.get("id") if isinstance(command, dict) else None
            if command_id and command_id not in seen_ids:
                seen_ids.add(command_id)
                commands.append(command)
    return commands, errors


def find_slash_command(name, channel_id):
    """Find a command even when Discord splits its name into search tokens."""
    queries = list(dict.fromkeys((name, name[:2], "")))
    channel_path = f"/channels/{channel_id}/application-commands/search"
    channel_commands, channel_errors = search_application_commands(
        channel_path, queries
    )
    matches = matching_slash_commands(channel_commands, name)

    guild_errors = []
    if not matches and state["guild_id"]:
        guild_path = f"/guilds/{state['guild_id']}/application-commands/search"
        guild_commands, guild_errors = search_application_commands(guild_path, queries)
        matches = matching_slash_commands(guild_commands, name)

    if not matches:
        all_errors = channel_errors + guild_errors
        attempted = len(queries) * (2 if state["guild_id"] else 1)
        if all_errors and len(all_errors) == attempted:
            # Every single search call failed - the lookup itself is broken
            # (bad token, rate limit, etc), not "command doesn't exist".
            raise ApiError(f"Couldn't look up /{name}: {all_errors[0]}")
        raise ApiError(f"No /{name} command is available in this channel.")
    if len(matches) > 1:
        names = ", ".join(f"/{command.get('name', '?')}" for command in matches[:5])
        raise ApiError(f"More than one command matches /{name}: {names}")
    return matches[0]


def form_field_for_option(option):
    option_type = option.get("type")
    field = {
        "id": f"option:{option['name']}",
        "label": option.get("name", "Option"),
        "required": bool(option.get("required")),
    }
    if option.get("description"):
        field["description"] = option["description"]
    if option_type == 5:
        field["type"] = "checkbox"
        field["value"] = False
    elif option_type in (4, 10):
        field["type"] = "number"
    elif option.get("choices"):
        field["type"] = "dropdown"
        field["options"] = [
            {
                "value": str(choice["value"]),
                "label": choice.get("name", str(choice["value"])),
            }
            for choice in option["choices"]
        ]
    else:
        field["type"] = "text"
        if option_type in (6, 7, 8, 9, 11):
            field["description"] = (
                field.get("description", "") + " Enter its Discord ID."
            ).strip()
    return field


def render_slash_command_form(command):
    state["screen"] = "slash_command"
    state["pending_slash_command"] = command
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "form",
            "canGoBack": True,
            "form": {
                "title": f"/{command['name']}",
                "submitLabel": "Run command",
                "fields": [
                    form_field_for_option(option)
                    for option in command.get("options") or []
                ],
            },
        }
    )


def execute_slash_command_async(command, option_values, channel_id, channel_name):
    def work():
        try:
            api_post(
                "/interactions",
                slash_command_payload(command, option_values, channel_id),
                expect_json=False,
            )
            set_message_history(
                api_get(f"/channels/{channel_id}/messages", params={"limit": MESSAGE_LIMIT})
            )
            render_messages(0)
            start_message_refresh(channel_id)
        except (ApiError, ValueError) as e:
            render_error(
                0,
                f"Couldn't run /{command.get('name', 'command')}",
                e,
                back_screen="messages",
            )

    threading.Thread(target=work, daemon=True).start()


def handle_slash_command_async(text, channel_id, channel_name):
    try:
        parts = shlex.split(text[1:])
    except ValueError as e:
        raise ApiError(f"Couldn't read slash command: {e}") from e
    if not parts:
        raise ApiError("Type a slash command, for example /yt-dlp")
    if not state["guild_id"]:
        raise ApiError("Slash commands need a server channel.")

    name, arguments = parts[0], parts[1:]
    command = find_slash_command(name, channel_id)
    if not arguments and command.get("options"):
        stop_message_refresh()
        render_slash_command_form(command)
        return
    if len(arguments) > len(command.get("options") or []):
        raise ApiError(f"/{name} accepts {len(command.get('options') or [])} option(s)")
    option_values = {
        f"option:{option['name']}": argument
        for option, argument in zip(command.get("options") or [], arguments)
    }
    execute_slash_command_async(command, option_values, channel_id, channel_name)


def send_message_async(text):
    channel_id = state["channel_id"]
    channel_name = state["channel_name"]
    if not text.strip():
        return

    def work():
        if text.lstrip().startswith("/"):
            try:
                handle_slash_command_async(text.lstrip(), channel_id, channel_name)
            except (ApiError, ValueError) as e:
                render_error(0, f"Couldn't send to #{channel_name}", e, back_screen="messages")
            return

        pending_id = f"pending:{uuid.uuid4().hex}"
        pending = {
            "id": pending_id,
            "content": text,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "pending": True,
            "author": state.get("current_user") or {"username": "You"},
        }
        with _send_lock:
            if state["screen"] == "messages" and state["channel_id"] == channel_id:
                state["messages"].insert(0, pending)
                render_messages(0)
        try:
            with _send_lock:
                api_post(
                    f"/channels/{channel_id}/messages",
                    {"content": expand_custom_emojis(text)},
                )
                state["messages"] = api_get(
                    f"/channels/{channel_id}/messages", params={"limit": MESSAGE_LIMIT}
                )
            if state["screen"] == "messages" and state["channel_id"] == channel_id:
                render_messages(0)
        except (ApiError, ValueError) as e:
            state["messages"] = [message for message in state["messages"] if message.get("id") != pending_id]
            if state["screen"] == "messages" and state["channel_id"] == channel_id:
                render_error(0, f"Couldn't send to #{channel_name}", e, back_screen="messages")

    threading.Thread(target=work, daemon=True).start()


# ---------------------------------------------------------------- sending


def send_message_async(text, reply_to=None, file_path=None):
    channel_id = state["channel_id"]
    channel_name = state["channel_name"]
    text = str(text or "")
    if not text.strip() and not file_path:
        return

    def work():
        if text.lstrip().startswith("/") and not file_path and not reply_to:
            try:
                handle_slash_command_async(text.lstrip(), channel_id, channel_name)
            except (ApiError, ValueError) as e:
                render_error(0, f"Couldn't send to {channel_name}", e, back_screen="messages")
            return

        pending_id = f"pending:{uuid.uuid4().hex}"
        pending = {
            "id": pending_id,
            "content": text,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "pending": True,
            "author": state.get("current_user") or {"username": "You"},
        }
        if file_path:
            pending["attachments"] = [{"filename": os.path.basename(file_path), "content_type": "application/octet-stream"}]
        with _send_lock:
            if state["screen"] == "messages" and state["channel_id"] == channel_id:
                state["messages"].insert(0, pending)
                render_messages(0)
        try:
            with _send_lock:
                if file_path:
                    created = api_post_multipart(channel_id_path(channel_id), file_path, text, reply_to=reply_to)
                else:
                    payload = {"content": expand_custom_emojis(text)}
                    if reply_to:
                        payload["message_reference"] = {
                            "message_id": str(reply_to),
                            "channel_id": str(channel_id),
                            "fail_if_not_exists": False,
                        }
                    created = api_post(f"/channels/{channel_id}/messages", payload)
            state["messages"] = [message for message in state["messages"] if message.get("id") != pending_id]
            if isinstance(created, dict) and created.get("id"):
                merge_gateway_message(created)
            try:
                set_message_history(
                    api_get(f"/channels/{channel_id}/messages", params={"limit": MESSAGE_LIMIT})
                )
            except ApiError as refresh_error:
                # The POST already succeeded; keep the optimistic/returned
                # message visible and let the gateway or the next refresh fill
                # in the rest of the conversation.
                log("message refresh after send failed:", refresh_error)
            if state["screen"] == "messages" and state["channel_id"] == channel_id:
                state["message_search"] = None
                render_messages(0)
                start_message_refresh(channel_id)
        except (ApiError, ValueError) as e:
            state["messages"] = [message for message in state["messages"] if message.get("id") != pending_id]
            if state["screen"] == "messages" and state["channel_id"] == channel_id:
                render_error(0, f"Couldn't send to {channel_name}", e, back_screen="messages")

    threading.Thread(target=work, daemon=True).start()


def channel_id_path(channel_id):
    return f"/channels/{channel_id}/messages"


# ---------------------------------------------------------------- dispatch


def open_last_channel_or_guilds(rev=0):
    last = state["last_channel"]
    if (
        isinstance(last, dict)
        and isinstance(last.get("id"), str)
        and isinstance(last.get("name"), str)
    ):
        state["guild_id"] = last.get("guild_id")
        state["guild_name"] = last.get("guild_name") or "server"
        state["opened_from_saved_channel"] = True
        load_messages_async(rev, last["id"], last["name"], last.get("topic", ""))
    else:
        state["opened_from_saved_channel"] = False
        load_guilds_async(rev)


def handle_init(msg):
    state["startup_token_ready"] = False
    state["startup_channel_ready"] = False
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "list",
            "loading": True,
            "items": [],
            "loadingText": "Checking saved credentials…",
        }
    )
    send(
        {
            "type": "command",
            "command": "storage",
            "op": "get",
            "key": "discord_token",
            "secret": True,
            "requestId": "tok_init",
        }
    )
    send(
        {
            "type": "command",
            "command": "storage",
            "op": "get",
            "key": "discord_last_channel",
            "requestId": "last_channel_init",
        }
    )


def handle_storage(msg):
    request_id = msg.get("requestId")
    if request_id == "tok_init":
        state["token"] = msg.get("value") or None
        state["startup_token_ready"] = True
    elif request_id == "last_channel_init":
        value = msg.get("value")
        state["last_channel"] = value if isinstance(value, dict) else None
        state["startup_channel_ready"] = True
    else:
        return
    if not (state["startup_token_ready"] and state["startup_channel_ready"]):
        return
    if not state["token"]:
        render_token_form()
        return
    start_gateway()
    open_last_channel_or_guilds(0)


def handle_submit(msg):
    values = msg.get("values", {})
    if state["screen"] == "need_token":
        token = (values.get("token") or "").strip()
        if not token:
            render_token_form(error="Token is required")
            return
        state["token"] = token
        send(
            {
                "type": "command",
                "command": "storage",
                "op": "set",
                "key": "discord_token",
                "value": token,
                "secret": True,
            }
        )
        open_last_channel_or_guilds(0)
    elif state["screen"] == "slash_command" and state["pending_slash_command"]:
        command = state["pending_slash_command"]
        state["pending_slash_command"] = None
        execute_slash_command_async(
            command, values, state["channel_id"], state["channel_name"]
        )


def handle_query(msg):
    text = msg.get("text", "")
    rev = msg.get("rev", 0)
    if state["screen"] == "guilds":
        render_guilds(rev, text)
    elif state["screen"] == "channels":
        render_channels(rev, text)
    # "messages" screen uses inputMode: submit, so query isn't sent there.


def handle_submit_query(msg):
    if state["screen"] == "messages":
        send_message_async(msg.get("text", ""))


def sign_out():
    stop_message_refresh()
    state["token"] = None
    state["current_user"] = {}
    state["last_channel"] = None
    state["opened_from_saved_channel"] = False
    send({"type": "command", "command": "storage", "op": "delete", "key": "discord_token"})
    send({"type": "command", "command": "storage", "op": "delete", "key": "discord_last_channel"})
    render_token_form()


def resolve_reaction_emoji(value):
    token = str(value or "").strip()
    if not token:
        raise ApiError("Choose or type an emoji.")

    custom_markup = CUSTOM_EMOJI_RE.fullmatch(token)
    if custom_markup:
        return f"{custom_markup.group(1)}:{custom_markup.group(2)}"

    custom_token = CUSTOM_EMOJI_TOKEN_RE.fullmatch(token)
    if custom_token:
        return token

    if token.startswith(":") and token.endswith(":") and len(token) > 2:
        name = token[1:-1]
        emojis = load_guild_emojis()
        emoji = emojis.get(name)
        if emoji is None:
            emoji = next(
                (candidate for key, candidate in emojis.items() if key.casefold() == name.casefold()),
                None,
            )
        if emoji is None:
            raise ApiError(f"Unknown server emoji :{name}:.")
        return f"{emoji['name']}:{emoji['id']}"

    return token


def handle_message_action_async(message_id, action, parameters):
    message = next(
        (candidate for candidate in state["messages"] if str(candidate.get("id")) == message_id),
        None,
    )
    if not message:
        return
    channel_id = state["channel_id"]
    channel_name = state["channel_name"]
    author_id = (message.get("author") or {}).get("id")
    current_user_id = state.get("current_user", {}).get("id")

    if action == "copy":
        text, image_urls, file_names = message_display(message)
        copy_text = text or (", ".join(file_names) if file_names else "")
        if not copy_text and image_urls:
            copy_text = "\n".join(image_urls)
        if copy_text:
            send({"type": "command", "command": "copy", "text": copy_text})
        return

    if action in ("edit", "delete") and author_id != current_user_id:
        render_error(0, "That action is only available for your own messages", "Discord denied the request.", back_screen="messages")
        return
    if action not in ("react", "edit", "delete"):
        return

    def work():
        try:
            if action == "react":
                emoji = resolve_reaction_emoji(parameters.get("emoji") or REACTION_CHOICES[0])
                api_put(
                    f"/channels/{channel_id}/messages/{message_id}/reactions/{quote(emoji, safe='')}/@me",
                    None,
                )
            elif action == "edit":
                content = str(parameters.get("content") or "").strip()
                if not content:
                    raise ApiError("Message cannot be empty.")
                api_patch(f"/channels/{channel_id}/messages/{message_id}", {"content": content})
            elif action == "delete":
                api_delete(f"/channels/{channel_id}/messages/{message_id}")
            else:
                return
            state["messages"] = api_get(
                f"/channels/{channel_id}/messages", params={"limit": MESSAGE_LIMIT}
            )
            if state["screen"] == "messages" and state["channel_id"] == channel_id:
                render_messages(0)
        except (ApiError, ValueError) as e:
            if state["screen"] == "messages" and state["channel_id"] == channel_id:
                render_error(0, f"Couldn't {action} message in #{channel_name}", e, back_screen="messages")

    threading.Thread(target=work, daemon=True).start()


def handle_action(msg):
    item_id = msg.get("id", "")
    action = msg.get("action", "default")
    parameters = msg.get("parameters")
    if not isinstance(parameters, dict):
        parameters = {}

    if item_id.startswith("message:"):
        handle_message_action_async(item_id.split(":", 1)[1], action, parameters)
        return

    if action == "sign_out" and item_id == "":
        sign_out()
        return

    if action == "servers" and item_id == "":
        stop_message_refresh()
        state["opened_from_saved_channel"] = False
        load_guilds_async(0)
        send({"type": "command", "command": "setQuery", "text": ""})
        return

    if action == "channels" and item_id == "" and state["guild_id"]:
        stop_message_refresh()
        load_channels_async(0, state["guild_id"], state["guild_name"])
        send({"type": "command", "command": "setQuery", "text": ""})
        return

    if action == "refresh" and item_id == "":
        if state["screen"] == "guilds":
            load_guilds_async(0)
        elif state["screen"] == "channels":
            load_channels_async(0, state["guild_id"], state["guild_name"])
        elif state["screen"] == "messages":
            load_messages_async(0, state["channel_id"], state["channel_name"])
        return

    if state["screen"] == "guilds" and item_id.startswith("guild:"):
        gid = item_id.split(":", 1)[1]
        guild = next((g for g in state["guilds"] if g["id"] == gid), None)
        load_channels_async(0, gid, guild.get("name", "server") if guild else "server")
        send({"type": "command", "command": "setQuery", "text": ""})
        return

    if state["screen"] == "channels" and item_id.startswith("channel:"):
        cid = item_id.split(":", 1)[1]
        chan = next((c for c in state["channels"] if c["id"] == cid), None)
        channel_name = chan.get("name", "channel") if chan else "channel"
        channel_topic = chan.get("topic", "") if chan else ""
        state["last_channel"] = {
            "id": cid,
            "name": channel_name,
            "topic": channel_topic,
            "guild_id": state["guild_id"],
            "guild_name": state["guild_name"],
        }
        state["opened_from_saved_channel"] = False
        send(
            {
                "type": "command",
                "command": "storage",
                "op": "set",
                "key": "discord_last_channel",
                "value": state["last_channel"],
            }
        )
        load_messages_async(0, cid, channel_name, channel_topic)
        send({"type": "command", "command": "setQuery", "text": ""})
        return


def handle_navigate(msg):
    target = msg.get("targetPageId", "")
    if target == "discord:home":
        stop_message_refresh()
        state["opened_from_saved_channel"] = False
        if state["guilds"]:
            render_guilds(0)
        else:
            load_guilds_async(0)
        send({"type": "command", "command": "setQuery", "text": ""})
        return

    prefix = "discord:guild:"
    suffix = ":channels"
    if target.startswith(prefix) and target.endswith(suffix):
        guild_id = target[len(prefix) : -len(suffix)]
        guild = next((item for item in state["guilds"] if item.get("id") == guild_id), None)
        if guild:
            stop_message_refresh()
            load_channels_async(0, guild_id, guild.get("name", "server"))
            send({"type": "command", "command": "setQuery", "text": ""})


def handle_back(msg):
    target = msg.get("toPageId")
    if state["screen"] == "error":
        back_screen = state["error_back_screen"]
        state["error_back_screen"] = None
        if back_screen == "channels":
            render_channels(0)
        elif back_screen == "guilds":
            render_guilds(0)
        elif back_screen == "messages":
            render_messages(0)
            start_message_refresh(state["channel_id"])
        return
    if target == "discord:home":
        stop_message_refresh()
        state["opened_from_saved_channel"] = False
        if state["guilds"]:
            render_guilds(0)
        else:
            load_guilds_async(0)
        return
    if target and target.startswith("discord:guild:") and target.endswith(":channels"):
        if state["guild_id"]:
            stop_message_refresh()
            render_channels(0)
        return
    if state["screen"] == "channels":
        load_guilds_async(0)
    elif state["screen"] == "messages":
        stop_message_refresh()
        if state["opened_from_saved_channel"]:
            state["last_channel"] = None
            state["opened_from_saved_channel"] = False
            send(
                {
                    "type": "command",
                    "command": "storage",
                    "op": "delete",
                    "key": "discord_last_channel",
                }
            )
        if state["guild_id"]:
            load_channels_async(0, state["guild_id"], state["guild_name"])
        else:
            render_guilds(0)
    elif state["screen"] == "slash_command":
        state["pending_slash_command"] = None
        render_messages(0)
        start_message_refresh(state["channel_id"])


def remember_last_channel(channel_id, channel_name, topic="", kind="guild", channel_type=0, parent_id=None):
    state["last_channel"] = {
        "id": str(channel_id),
        "name": channel_name,
        "topic": topic or "",
        "kind": kind,
        "type": channel_type or 0,
        "parent_id": parent_id,
        "guild_id": state.get("guild_id"),
        "guild_name": state.get("guild_name") or "server",
    }
    send({"type": "command", "command": "storage", "op": "set", "key": "discord_last_channel", "value": state["last_channel"]})


def open_last_channel_or_guilds(rev=0):
    last = state.get("last_channel")
    if isinstance(last, dict) and isinstance(last.get("id"), str) and isinstance(last.get("name"), str):
        state["guild_id"] = last.get("guild_id")
        state["guild_name"] = last.get("guild_name") or "server"
        state["opened_from_saved_channel"] = True
        load_messages_async(
            rev,
            last["id"],
            last["name"],
            last.get("topic", ""),
            last.get("kind", "guild"),
            last.get("type", 0),
            last.get("parent_id"),
        )
    else:
        state["opened_from_saved_channel"] = False
        load_guilds_async(rev)


def create_forum_post_async(name, content):
    forum_id = state["forum_channel_id"]
    if not str(name or "").strip() or not str(content or "").strip():
        return

    def work():
        try:
            api_post(
                f"/channels/{forum_id}/threads",
                {
                    "name": str(name).strip(),
                    "auto_archive_duration": 1440,
                    "message": {"content": expand_custom_emojis(str(content).strip())},
                },
            )
            load_forum_posts_async(0, forum_id, state["forum_channel_name"])
        except ApiError as e:
            render_error(0, "Couldn't create forum post", e, back_screen="forum_posts")

    threading.Thread(target=work, daemon=True).start()


def handle_message_action_async(message_id, action, parameters):
    message = next(
        (candidate for candidate in state.get("messages", []) if str(candidate.get("id")) == str(message_id)),
        None,
    )
    if not message:
        return
    channel_id = state["channel_id"]
    channel_name = state["channel_name"]
    author_id = (message.get("author") or {}).get("id")
    current_user_id = state.get("current_user", {}).get("id")

    if action == "copy":
        text, image_urls, file_names = message_display(message)
        copy_text = text or (", ".join(file_names) if file_names else "")
        if not copy_text and image_urls:
            copy_text = "\n".join(image_urls)
        if copy_text:
            send({"type": "command", "command": "copy", "text": copy_text})
        return
    if action.startswith("open_url:"):
        send({"type": "command", "command": "open", "url": unquote(action.split(":", 1)[1])})
        return
    if action == "reply":
        send_message_async(parameters.get("content", ""), reply_to=message_id)
        return
    if action in ("edit", "delete") and author_id != current_user_id:
        render_error(0, "That action is only available for your own messages", "Discord denied the request.", back_screen="messages")
        return
    if not action.startswith("poll_vote:") and action not in ("react", "edit", "delete", "pin"):
        return

    def work():
        try:
            if action == "react":
                emoji = resolve_reaction_emoji(parameters.get("emoji") or REACTION_CHOICES[0])
                api_put(f"/channels/{channel_id}/messages/{message_id}/reactions/{quote(emoji, safe='')}/@me", None)
            elif action == "edit":
                content = str(parameters.get("content") or "").strip()
                if not content:
                    raise ApiError("Message cannot be empty.")
                api_patch(f"/channels/{channel_id}/messages/{message_id}", {"content": expand_custom_emojis(content)})
            elif action == "delete":
                api_delete(f"/channels/{channel_id}/messages/{message_id}")
            elif action == "pin":
                api_put(f"/channels/{channel_id}/pins/{message_id}", None)
            elif action.startswith("poll_vote:"):
                answer_id = action.split(":", 1)[1]
                api_put(f"/channels/{channel_id}/polls/{message_id}/answers/{answer_id}", None)
            set_message_history(api_get(f"/channels/{channel_id}/messages", params={"limit": MESSAGE_LIMIT}))
            if state["screen"] == "messages" and state["channel_id"] == channel_id:
                render_messages(0)
        except (ApiError, ValueError) as e:
            if state["screen"] == "messages" and state["channel_id"] == channel_id:
                render_error(0, f"Couldn't {action} message in {channel_name}", e, back_screen="messages")

    threading.Thread(target=work, daemon=True).start()


def handle_pin_action_async(message_id, action):
    message = next(
        (candidate for candidate in state.get("pinned_messages", []) if str(candidate.get("id")) == str(message_id)),
        None,
    )
    if not message:
        return
    if action == "copy":
        text, image_urls, file_names = message_display(message)
        send({"type": "command", "command": "copy", "text": text or "\n".join(image_urls) or ", ".join(file_names)})
        return
    if action != "unpin":
        return

    def work():
        try:
            api_delete(f"/channels/{state['channel_id']}/pins/{message_id}")
            load_pins_async(0)
        except ApiError as e:
            render_error(0, "Couldn't unpin message", e, back_screen="pins")

    threading.Thread(target=work, daemon=True).start()


def handle_action(msg):
    item_id = msg.get("id", "")
    action = msg.get("action", "default")
    parameters = msg.get("parameters")
    if not isinstance(parameters, dict):
        parameters = {}

    if item_id.startswith("message:"):
        handle_message_action_async(item_id.split(":", 1)[1], action, parameters)
        return
    if item_id.startswith("pin:"):
        handle_pin_action_async(item_id.split(":", 1)[1], action)
        return

    if action == "sign_out" and item_id == "":
        sign_out()
        return
    if action in ("servers",) and item_id == "":
        stop_message_refresh()
        state["opened_from_saved_channel"] = False
        load_guilds_async(0)
        send({"type": "command", "command": "setQuery", "text": ""})
        return
    if action in ("dms",) and item_id == "":
        load_dms_async(0)
        send({"type": "command", "command": "setQuery", "text": ""})
        return
    if action == "channels" and item_id == "" and state.get("guild_id"):
        stop_message_refresh()
        load_channels_async(0, state["guild_id"], state["guild_name"])
        send({"type": "command", "command": "setQuery", "text": ""})
        return
    if action == "refresh" and item_id == "":
        if state["screen"] == "guilds":
            load_guilds_async(0)
        elif state["screen"] == "channels":
            load_channels_async(0, state["guild_id"], state["guild_name"])
        elif state["screen"] == "dms":
            load_dms_async(0)
        elif state["screen"] == "messages":
            load_messages_async(0, state["channel_id"], state["channel_name"], state.get("channel_topic", ""), state.get("channel_kind", "guild"), state.get("channel_type", 0), state.get("channel_parent_id"))
        elif state["screen"] == "pins":
            load_pins_async(0)
        return
    if action == "refresh_dms" and item_id == "":
        load_dms_async(0)
        return
    if action == "refresh_forum" and item_id == "":
        load_forum_posts_async(0, state["forum_channel_id"], state["forum_channel_name"])
        return
    if action == "refresh_pins" and item_id == "":
        load_pins_async(0)
        return
    if action == "search" and item_id == "":
        search_messages_async(parameters.get("query"))
        return
    if action == "clear_search" and item_id == "":
        load_messages_async(0, state["channel_id"], state["channel_name"], state.get("channel_topic", ""), state.get("channel_kind", "guild"), state.get("channel_type", 0), state.get("channel_parent_id"))
        return
    if action == "attach" and item_id == "":
        send_message_async(parameters.get("content", ""), file_path=parameters.get("file"))
        return
    if action == "mention" and item_id == "":
        value = str(parameters.get("user") or "").strip()
        if value:
            send({"type": "command", "command": "setQuery", "text": f"{value} "})
        return
    if action == "view_pins" and item_id == "":
        load_pins_async(0)
        return
    if action == "back_to_channel" and item_id == "":
        state["screen"] = "messages"
        render_messages(0)
        start_message_refresh(state["channel_id"])
        return
    if action == "new_post" and item_id == "":
        create_forum_post_async(parameters.get("name", ""), parameters.get("content", ""))
        return

    if state["screen"] == "guilds" and item_id == "dms":
        load_dms_async(0)
        send({"type": "command", "command": "setQuery", "text": ""})
        return
    if state["screen"] == "guilds" and item_id.startswith("guild:"):
        gid = item_id.split(":", 1)[1]
        guild = next((g for g in state["guilds"] if g.get("id") == gid), None)
        load_channels_async(0, gid, guild.get("name", "server") if guild else "server")
        send({"type": "command", "command": "setQuery", "text": ""})
        return
    if state["screen"] == "dms" and item_id.startswith("dm:"):
        cid = item_id.split(":", 1)[1]
        channel = next((c for c in state["dm_channels"] if str(c.get("id")) == cid), None)
        name = dm_display_name(channel or {})
        state["guild_id"] = None
        state["guild_name"] = ""
        remember_last_channel(cid, name, kind="dm", channel_type=(channel or {}).get("type", 1))
        state["opened_from_saved_channel"] = False
        load_messages_async(0, cid, name, channel_kind="dm", channel_type=(channel or {}).get("type", 1))
        send({"type": "command", "command": "setQuery", "text": ""})
        return
    if state["screen"] == "channels" and item_id.startswith("channel:"):
        cid = item_id.split(":", 1)[1]
        channel = next((c for c in state["channels"] if str(c.get("id")) == cid), None) or {}
        channel_name = channel.get("name", "channel")
        channel_type = channel.get("type", 0)
        if channel_type == 15:
            load_forum_posts_async(0, cid, channel_name)
            return
        remember_last_channel(cid, channel_name, channel.get("topic", ""), channel_type=channel_type, parent_id=channel.get("parent_id"))
        state["opened_from_saved_channel"] = False
        load_messages_async(0, cid, channel_name, channel.get("topic", ""), channel_type=channel_type, parent_id=channel.get("parent_id"))
        send({"type": "command", "command": "setQuery", "text": ""})
        return
    if state["screen"] == "forum_posts" and item_id.startswith("thread:"):
        tid = item_id.split(":", 1)[1]
        thread = next((candidate for candidate in state["forum_threads"] if str(candidate.get("id")) == tid), None) or {}
        name = thread.get("name", "post")
        remember_last_channel(tid, name, kind="guild", channel_type=thread.get("type", 11), parent_id=state["forum_channel_id"])
        state["opened_from_saved_channel"] = False
        load_messages_async(0, tid, name, channel_kind="guild", channel_type=thread.get("type", 11), parent_id=state["forum_channel_id"])
        send({"type": "command", "command": "setQuery", "text": ""})


def handle_load_more(msg):
    if state["screen"] == "messages":
        load_more_messages_async()


def handle_submit(msg):
    values = msg.get("values", {})
    if state["screen"] == "need_token":
        token = str(values.get("token") or "").strip()
        if not token:
            render_token_form(error="Token is required")
            return
        state["token"] = token
        send({"type": "command", "command": "storage", "op": "set", "key": "discord_token", "value": token, "secret": True})
        start_gateway()
        open_last_channel_or_guilds(0)
    elif state["screen"] == "slash_command" and state["pending_slash_command"]:
        command = state["pending_slash_command"]
        state["pending_slash_command"] = None
        execute_slash_command_async(command, values, state["channel_id"], state["channel_name"])


def handle_query(msg):
    text = msg.get("text", "")
    rev = msg.get("rev", 0)
    if state["screen"] == "guilds":
        render_guilds(rev, text)
    elif state["screen"] == "channels":
        render_channels(rev, text)
    elif state["screen"] == "dms":
        render_dms(rev, text)


def handle_submit_query(msg):
    if state["screen"] == "messages":
        send_message_async(msg.get("text", ""))


def sign_out():
    stop_message_refresh()
    stop_gateway()
    state["token"] = None
    state["current_user"] = {}
    state["last_channel"] = None
    state["opened_from_saved_channel"] = False
    state["unread_counts"] = {}
    send({"type": "command", "command": "storage", "op": "delete", "key": "discord_token"})
    send({"type": "command", "command": "storage", "op": "delete", "key": "discord_last_channel"})
    render_token_form()


def handle_navigate(msg):
    target = msg.get("targetPageId", "")
    if target == "discord:home":
        stop_message_refresh()
        state["opened_from_saved_channel"] = False
        if state.get("guilds"):
            render_guilds(0)
        else:
            load_guilds_async(0)
        send({"type": "command", "command": "setQuery", "text": ""})
        return
    if target == "discord:dms":
        load_dms_async(0)
        return
    prefix = "discord:guild:"
    suffix = ":channels"
    if target.startswith(prefix) and target.endswith(suffix):
        guild_id = target[len(prefix) : -len(suffix)]
        guild = next((item for item in state["guilds"] if item.get("id") == guild_id), None)
        if guild:
            stop_message_refresh()
            load_channels_async(0, guild_id, guild.get("name", "server"))
        return
    if target.startswith("discord:dm:"):
        channel_id = target.split(":", 2)[2]
        channel = next((c for c in state.get("dm_channels", []) if str(c.get("id")) == channel_id), None)
        if channel:
            state["guild_id"] = None
            state["guild_name"] = ""
            load_messages_async(0, channel_id, dm_display_name(channel), channel_kind="dm", channel_type=channel.get("type", 1))
        return
    if target.startswith("discord:forum:") and state.get("forum_channel_id"):
        load_forum_posts_async(0, state["forum_channel_id"], state["forum_channel_name"])


def handle_back(msg):
    target = msg.get("toPageId")
    if state["screen"] == "error":
        back_screen = state.get("error_back_screen")
        state["error_back_screen"] = None
        if back_screen == "channels":
            render_channels(0)
        elif back_screen == "dms":
            render_dms(0)
        elif back_screen == "forum_posts":
            render_forum_posts(0)
        elif back_screen == "pins":
            render_pins(0)
        elif back_screen == "messages":
            render_messages(0)
            start_message_refresh(state["channel_id"])
        else:
            render_guilds(0)
        return
    if target == "discord:home":
        stop_message_refresh()
        state["opened_from_saved_channel"] = False
        if state.get("guilds"):
            render_guilds(0)
        else:
            load_guilds_async(0)
        return
    if target == "discord:dms":
        load_dms_async(0)
        return
    if target and target.startswith("discord:guild:") and target.endswith(":channels"):
        if state.get("guild_id"):
            stop_message_refresh()
            render_channels(0)
        return
    if state["screen"] == "channels" or state["screen"] == "dms":
        load_guilds_async(0)
    elif state["screen"] == "forum_posts":
        load_channels_async(0, state["guild_id"], state["guild_name"])
    elif state["screen"] == "pins":
        state["screen"] = "messages"
        render_messages(0)
        start_message_refresh(state["channel_id"])
    elif state["screen"] == "messages":
        stop_message_refresh()
        if state.get("opened_from_saved_channel"):
            state["last_channel"] = None
            state["opened_from_saved_channel"] = False
            send({"type": "command", "command": "storage", "op": "delete", "key": "discord_last_channel"})
        if state.get("channel_kind") == "dm":
            load_dms_async(0)
        elif state.get("guild_id"):
            load_channels_async(0, state["guild_id"], state["guild_name"])
        else:
            render_guilds(0)
    elif state["screen"] == "slash_command":
        state["pending_slash_command"] = None
        render_messages(0)
        start_message_refresh(state["channel_id"])


def load_more_messages_async():
    if state["screen"] != "messages":
        return
    channel_id = state["channel_id"]
    if state.get("message_search"):
        query = state["message_search"]
        offset = int(state.get("message_search_offset", len(state["messages"])))

        def search_work():
            try:
                result = api_get(
                    f"/channels/{channel_id}/messages/search",
                    params={"content": query, "limit": MESSAGE_LIMIT, "offset": offset},
                )
                raw_messages = result.get("messages", []) if isinstance(result, dict) else result
                extra = []
                for group in raw_messages or []:
                    if isinstance(group, list):
                        extra.extend(message_list(group))
                    elif isinstance(group, dict):
                        extra.append(group)
                known = {str(message.get("id")) for message in state["messages"]}
                state["messages"].extend(message for message in extra if str(message.get("id")) not in known)
                state["message_search_offset"] = offset + len(extra)
                total = result.get("total_results", state["message_search_offset"]) if isinstance(result, dict) else state["message_search_offset"]
                state["message_search_total"] = total
                state["messages_has_more"] = state["message_search_offset"] < total
                render_messages(0)
            except ApiError as e:
                log("message search pagination failed:", e)

        threading.Thread(target=search_work, daemon=True).start()
        return
    if not state.get("messages_has_more") or not state["messages"]:
        return
    before = state["messages"][-1].get("id")
    if not before:
        state["messages_has_more"] = False
        render_messages(0)
        return

    def history_work():
        try:
            older = message_list(api_get(f"/channels/{channel_id}/messages", params={"limit": MESSAGE_LIMIT, "before": before}))
            known = {str(message.get("id")) for message in state["messages"]}
            state["messages"].extend(message for message in older if str(message.get("id")) not in known)
            state["messages_has_more"] = len(older) >= MESSAGE_LIMIT
            render_messages(0)
        except ApiError as e:
            log("message history load failed:", e)

    threading.Thread(target=history_work, daemon=True).start()


def handle_focus(msg):
    if state["screen"] == "messages" and state["messages"] and not state.get("message_search"):
        mark_channel_read_async(state["channel_id"], state["messages"][0].get("id"))


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
        try:
            if t == "close":
                stop_message_refresh()
                stop_gateway()
                break
            elif t == "init":
                handle_init(msg)
            elif t == "storage":
                handle_storage(msg)
            elif t == "submit":
                handle_submit(msg)
            elif t == "query":
                handle_query(msg)
            elif t == "submitQuery":
                handle_submit_query(msg)
            elif t == "loadMore":
                handle_load_more(msg)
            elif t == "focus":
                handle_focus(msg)
            elif t == "action":
                handle_action(msg)
            elif t == "back":
                handle_back(msg)
            elif t == "navigate":
                handle_navigate(msg)
        except Exception as e:
            log("unhandled error:", repr(e))
            render_error(0, "Something went wrong", e)


if __name__ == "__main__":
    main()
