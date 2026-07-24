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
import sys
import threading

try:
    import requests
except ImportError:
    requests = None

API_BASE = "https://discord.com/api/v10"
MESSAGE_LIMIT = 30

_out_lock = threading.Lock()
_message_refresh_stop = threading.Event()


def send(frame):
    with _out_lock:
        sys.stdout.write(json.dumps(frame) + "\n")
        sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


state = {
    "screen": "loading",  # loading | need_token | guilds | channels | messages
    "token": None,
    "guilds": [],
    "channels": [],
    "guild_id": None,
    "guild_name": "",
    "channel_id": None,
    "channel_name": "",
    "messages": [],
    "last_channel": None,
    "startup_token_ready": False,
    "startup_channel_ready": False,
    "opened_from_saved_channel": False,
}


# ---------------------------------------------------------------- Discord API


class ApiError(Exception):
    pass


def _headers():
    return {
        "Authorization": state["token"],
        "Content-Type": "application/json",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
    }


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


def api_post(path, payload):
    if requests is None:
        raise ApiError("The 'requests' package failed to install.")
    r = requests.post(f"{API_BASE}{path}", headers=_headers(), json=payload, timeout=15)
    if r.status_code == 401:
        raise ApiError("Token rejected (401). It may be expired or wrong.")
    if r.status_code == 429:
        raise ApiError("Rate limited by Discord (429). Wait a bit and retry.")
    if not r.ok:
        raise ApiError(f"Discord API error {r.status_code}: {r.text[:200]}")
    return r.json()


# ---------------------------------------------------------------- render helpers


def render_error(rev, title, err, can_go_back=True):
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
            "form": {
                "title": "Connect your Discord account",
                "submitLabel": "Connect",
                "fields": [field],
            },
        }
    )


def render_guilds(rev, filter_text=""):
    state["screen"] = "guilds"
    items = []
    ft = (filter_text or "").strip().lower()
    for g in state["guilds"]:
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
            "actions": [
                {"id": "refresh", "title": "Refresh servers", "icon": "refresh"}
            ],
        }
    )


def render_channels(rev, filter_text=""):
    state["screen"] = "channels"
    items = []
    ft = (filter_text or "").strip().lower()
    for c in state["channels"]:
        name = c.get("name", "unknown")
        if ft and ft not in name.lower():
            continue
        items.append(
            {
                "id": f"channel:{c['id']}",
                "title": f"# {name}",
                "subtitle": c.get("topic") or "",
                "icon": "chat",
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
            "actions": [
                {"id": "refresh", "title": "Refresh channels", "icon": "refresh"}
            ],
        }
    )


def format_messages_markdown():
    if not state["messages"]:
        return f"# #{state['channel_name']}\n\n_No messages yet._"
    lines = [f"# #{state['channel_name']}", ""]
    for m in reversed(state["messages"]):  # API returns newest first
        author = m.get("author", {}).get("username", "unknown")
        content = m.get("content") or "*[no text content]*"
        ts = (m.get("timestamp") or "")[:16].replace("T", " ")
        content = content.replace("\n", "\n> ")
        lines.append(f"**{author}** · _{ts}_")
        lines.append(f"> {content}")
        lines.append("")
    return "\n".join(lines)


def message_avatar(author):
    avatar = author.get("avatar")
    author_id = author.get("id")
    if avatar and author_id:
        return f"https://cdn.discordapp.com/avatars/{author_id}/{avatar}.png?size=64"
    return "person"


def message_items():
    items = []
    for message in reversed(state["messages"]):  # API returns newest first
        author = message.get("author", {})
        content = message.get("content") or "[no text content]"
        attachments = message.get("attachments") or []
        image_urls = []
        file_names = []
        for attachment in attachments:
            content_type = attachment.get("content_type") or ""
            filename = attachment.get("filename", "attachment")
            is_image = content_type.startswith("image/") or filename.lower().endswith(
                (".png", ".jpg", ".jpeg", ".gif", ".webp")
            )
            if is_image and attachment.get("url"):
                image_urls.append(attachment["url"])
            else:
                file_names.append(filename)
        if file_names:
            label = ", ".join(file_names)
            content = (
                f"{content}\nattachment: {label}"
                if message.get("content")
                else f"attachment: {label}"
            )
        timestamp = message.get("timestamp") or ""
        items.append(
            {
                "id": f"message:{message['id']}",
                "title": author.get("global_name") or author.get("username", "unknown"),
                "subtitle": content,
                "icon": message_avatar(author),
                "images": image_urls,
                "section": timestamp[:10],
                "accessories": [{"text": timestamp[11:16]}]
                if len(timestamp) >= 16
                else [],
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
            "detail": {"wide": False},
            "emptyText": f"No messages in #{state['channel_name']} yet",
            "items": message_items(),
            "actions": [
                {"id": "refresh", "title": "Refresh messages", "icon": "refresh"}
            ],
        }
    )


def stop_message_refresh():
    global _message_refresh_stop
    _message_refresh_stop.set()


def start_message_refresh(channel_id):
    global _message_refresh_stop
    stop_message_refresh()
    stop = threading.Event()
    _message_refresh_stop = stop

    def work():
        while not stop.wait(1):
            if state["screen"] != "messages" or state["channel_id"] != channel_id:
                return
            try:
                state["messages"] = api_get(
                    f"/channels/{channel_id}/messages", params={"limit": MESSAGE_LIMIT}
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
            state["guilds"] = api_get("/users/@me/guilds")
            render_guilds(rev)
        except ApiError as e:
            render_error(rev, "Couldn't load servers", e, can_go_back=False)

    threading.Thread(target=work, daemon=True).start()


def load_channels_async(rev, guild_id, guild_name):
    state["guild_id"] = guild_id
    state["guild_name"] = guild_name
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
            # type 0 = text, 5 = announcement
            state["channels"] = [c for c in all_channels if c.get("type") in (0, 5)]
            render_channels(rev)
        except ApiError as e:
            render_error(rev, "Couldn't load channels", e)

    threading.Thread(target=work, daemon=True).start()


def load_messages_async(rev, channel_id, channel_name):
    stop_message_refresh()
    state["channel_id"] = channel_id
    state["channel_name"] = channel_name
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "chat",
            "loading": True,
            "canGoBack": True,
            "loadingText": f"Loading #{channel_name}…",
            "detail": {"wide": False},
            "items": [],
        }
    )

    def work():
        try:
            state["messages"] = api_get(
                f"/channels/{channel_id}/messages", params={"limit": MESSAGE_LIMIT}
            )
            render_messages(rev)
            start_message_refresh(channel_id)
        except ApiError as e:
            render_error(rev, f"Couldn't load #{channel_name}", e)

    threading.Thread(target=work, daemon=True).start()


def send_message_async(text):
    channel_id = state["channel_id"]
    channel_name = state["channel_name"]
    if not text.strip():
        return

    def work():
        try:
            api_post(f"/channels/{channel_id}/messages", {"content": text})
            state["messages"] = api_get(
                f"/channels/{channel_id}/messages", params={"limit": MESSAGE_LIMIT}
            )
            render_messages(0)
        except ApiError as e:
            render_error(0, f"Couldn't send to #{channel_name}", e)

    threading.Thread(target=work, daemon=True).start()


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
        load_messages_async(rev, last["id"], last["name"])
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
    open_last_channel_or_guilds(0)


def handle_submit(msg):
    if state["screen"] != "need_token":
        return
    values = msg.get("values", {})
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


def handle_action(msg):
    item_id = msg.get("id", "")
    action = msg.get("action", "default")

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
        return

    if state["screen"] == "channels" and item_id.startswith("channel:"):
        cid = item_id.split(":", 1)[1]
        chan = next((c for c in state["channels"] if c["id"] == cid), None)
        channel_name = chan.get("name", "channel") if chan else "channel"
        state["last_channel"] = {
            "id": cid,
            "name": channel_name,
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
        load_messages_async(0, cid, channel_name)
        return


def handle_back(msg):
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
            elif t == "action":
                handle_action(msg)
            elif t == "back":
                handle_back(msg)
        except Exception as e:
            log("unhandled error:", repr(e))
            render_error(0, "Something went wrong", e)


if __name__ == "__main__":
    main()
