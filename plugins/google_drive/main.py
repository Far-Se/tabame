#!/usr/bin/env python3
"""
Tabame launcher plugin — Google Drive
Keyword: gdrive

Search Drive by filename, browse into folders, open results in the
browser, copy their link, or reveal metadata in the preview pane.
Sign-in uses Google's standard desktop OAuth loopback flow (a browser
tab opens once; after that the plugin stays signed in using a stored
refresh token).
"""

import json
import os
import sys
import threading

PLUGIN_DIR = os.path.dirname(os.path.abspath(__file__))
CLIENT_SECRET_PATH = os.path.join(PLUGIN_DIR, "client_secret.json")
SCOPES = ["https://www.googleapis.com/auth/drive.readonly"]
STORAGE_KEY = "gdrive_token"

FOLDER_MIME = "application/vnd.google-apps.folder"

state = {
    "text": "",
    "creds": None,  # google.oauth2.credentials.Credentials once signed in
    "checked_storage": False,
    "auth_pending": False,
    "files": {},  # last rendered file id -> file dict, for actions
    "folder_stack": [],  # [{"id","name"}, ...] — empty = unrestricted search
}


# ---------------------------------------------------------------- protocol --


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def toast(text, style="info"):
    send({"type": "command", "command": "toast", "text": text, "style": style})


# ------------------------------------------------------------------ config --


def client_secret_available():
    return os.path.isfile(CLIENT_SECRET_PATH)


# --------------------------------------------------------- token <-> storage --


def creds_to_dict(creds):
    return {
        "token": creds.token,
        "refresh_token": creds.refresh_token,
        "token_uri": creds.token_uri,
        "client_id": creds.client_id,
        "client_secret": creds.client_secret,
        "scopes": creds.scopes,
    }


def dict_to_creds(d):
    from google.oauth2.credentials import Credentials

    return Credentials(
        token=d.get("token"),
        refresh_token=d.get("refresh_token"),
        token_uri=d.get("token_uri"),
        client_id=d.get("client_id"),
        client_secret=d.get("client_secret"),
        scopes=d.get("scopes"),
    )


def request_token_from_storage():
    send(
        {
            "type": "command",
            "command": "storage",
            "op": "get",
            "key": STORAGE_KEY,
            "secret": True,
            "requestId": "boot",
        }
    )


def save_token_to_storage(creds):
    send(
        {
            "type": "command",
            "command": "storage",
            "op": "set",
            "key": STORAGE_KEY,
            "secret": True,
            "value": json.dumps(creds_to_dict(creds)),
        }
    )


def clear_token_storage():
    send(
        {
            "type": "command",
            "command": "storage",
            "op": "delete",
            "key": STORAGE_KEY,
            "secret": True,
        }
    )


def ensure_fresh(creds):
    from google.auth.transport.requests import Request

    if creds and creds.expired and creds.refresh_token:
        creds.refresh(Request())
        save_token_to_storage(creds)
    return creds


# ---------------------------------------------------------------- rendering --


def render_message(text, subtitle=""):
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "list",
            "items": [
                {"id": "status", "title": text, "subtitle": subtitle, "icon": "cloud"}
            ],
        }
    )


def render_connect_prompt(rev):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "emptyText": "Not connected",
            "items": [
                {
                    "id": "connect",
                    "title": "Connect Google Drive",
                    "subtitle": "Sign in with your Google account to search Drive",
                    "icon": "cloud",
                    "actions": [{"id": "default", "title": "Connect", "icon": "open"}],
                },
                {
                    "id": "info",
                    "title": "Press Ctrl+K and read README.md",
                    "subtitle": "To get your client_secrets.json file.",
                    "icon": "gear",
                    # "actions": [{"id": "default", "title": "Connect", "icon": "open"}],
                },
            ],
        }
    )


def logout_action():
    """Frame-level Ctrl+K action shown while a Drive account is connected."""
    return [{"id": "signout", "title": "Log out", "icon": "power"}]


def pick_icon(mime):
    if "folder" in mime:
        return "folder"
    if "spreadsheet" in mime:
        return "grid"
    if "presentation" in mime:
        return "image"
    if "document" in mime or "pdf" in mime or "text" in mime:
        return "note"
    if "image" in mime:
        return "image"
    return "file"


def human_size(n):
    try:
        n = int(n)
    except (TypeError, ValueError):
        return ""
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.0f}{unit}"
        n /= 1024
    return f"{n:.1f}TB"


def breadcrumb():
    names = ["My Drive"] + [f["name"] for f in state["folder_stack"]]
    return " › ".join(names)


def enter_folder(folder_id, name):
    state["folder_stack"].append({"id": folder_id, "name": name})
    state["text"] = ""
    do_search(0, "")


def go_up():
    if state["folder_stack"]:
        state["folder_stack"].pop()
    state["text"] = ""
    do_search(0, "")


# -------------------------------------------------------------------- drive --


def build_service(creds):
    from googleapiclient.discovery import build

    return build("drive", "v3", credentials=creds, cache_discovery=False)


def do_search(rev, query):
    creds = state.get("creds")
    if not creds:
        render_connect_prompt(rev)
        return

    try:
        creds = ensure_fresh(creds)
        state["creds"] = creds
        service = build_service(creds)

        browsing = bool(state["folder_stack"])
        current_folder_id = state["folder_stack"][-1]["id"] if browsing else None

        clauses = ["trashed = false"]
        if current_folder_id:
            clauses.append(f"'{current_folder_id}' in parents")
        q = query.strip()
        if q:
            safe = q.replace("\\", "\\\\").replace("'", "\\'")
            clauses.append(f"name contains '{safe}'")
        drive_query = " and ".join(clauses)

        results = (
            service.files()
            .list(
                q=drive_query,
                pageSize=50 if browsing else 25,
                orderBy="folder,name" if browsing else "modifiedTime desc",
                fields="files(id,name,mimeType,modifiedTime,webViewLink,"
                "webContentLink,size,owners,iconLink,thumbnailLink)",
            )
            .execute()
        )
        files = results.get("files", [])
        state["files"] = {f["id"]: f for f in files}

        if not files and not browsing:
            send(
                {
                    "type": "render",
                    "rev": rev,
                    "view": "list",
                    "emptyText": "No files found",
                    "actions": logout_action(),
                    "items": [],
                }
            )
            return

        items = []
        if browsing:
            parent_name = (
                state["folder_stack"][-2]["name"]
                if len(state["folder_stack"]) > 1
                else "My Drive"
            )
            items.append(
                {
                    "id": "..",
                    "title": "⬆ Up",
                    "subtitle": f"Back to {parent_name}",
                    "icon": "folder",
                    "section": breadcrumb(),
                    "actions": [{"id": "default", "title": "Up", "icon": "folder"}],
                }
            )

        for f in files:
            owner = (f.get("owners") or [{}])[0].get("displayName", "")
            mime = f.get("mimeType", "")
            is_folder = mime == FOLDER_MIME
            is_image = mime.startswith("image/")
            thumb = f.get("thumbnailLink")

            preview = {
                "metadata": [
                    {"label": "Name", "text": f["name"]},
                    {"label": "Type", "text": "Folder" if is_folder else mime},
                    {"label": "Owner", "text": owner or "—"},
                    {"label": "Modified", "text": (f.get("modifiedTime") or "")[:10]},
                    {"label": "Size", "text": human_size(f.get("size", 0))},
                    {
                        "label": "Link",
                        "text": "Open in Drive",
                        "url": f.get("webViewLink", ""),
                    },
                ]
            }
            if is_image and thumb:
                # Larger thumbnail than Drive's default ~220px, still fast to load.
                preview["image"] = {
                    "url": thumb.replace("=s220", "=s600"),
                    "width": 260,
                }

            if is_folder:
                actions = [
                    {"id": "default", "title": "Browse", "icon": "folder"},
                    {"id": "open_browser", "title": "Open in Browser", "icon": "open"},
                    {"id": "copy_link", "title": "Copy Link", "icon": "copy"},
                ]
            else:
                actions = [
                    {"id": "default", "title": "Open in Browser", "icon": "open"},
                    {"id": "copy_link", "title": "Copy Link", "icon": "copy"},
                    {"id": "download", "title": "Download", "icon": "download"},
                ]

            item = {
                "id": f["id"],
                "title": f["name"],
                "subtitle": owner,
                "icon": pick_icon(mime),
                "accessories": [{"text": (f.get("modifiedTime") or "")[:10]}],
                "actions": actions,
                "preview": preview,
            }
            if browsing:
                item["section"] = breadcrumb()
            items.append(item)

        if not items:
            send(
                {
                    "type": "render",
                    "rev": rev,
                    "view": "list",
                    "emptyText": "Empty folder",
                    "canGoBack": browsing,
                    "actions": logout_action(),
                    "items": [],
                }
            )
            return

        send(
            {
                "type": "render",
                "rev": rev,
                "view": "list",
                "preview": {"enabled": True},
                "canGoBack": browsing,
                "actions": logout_action(),
                "items": items,
            }
        )

    except Exception as e:
        log("search error:", e)
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "list",
                "emptyText": f"Drive error: {e}",
                "actions": logout_action(),
                "items": [],
            }
        )


# ---------------------------------------------------------------------- auth --


def start_oauth_flow():
    if state.get("auth_pending"):
        return
    state["auth_pending"] = True

    def worker():
        try:
            from google_auth_oauthlib.flow import InstalledAppFlow

            if not client_secret_available():
                toast("Missing client_secret.json in the plugin folder", "error")
                return

            flow = InstalledAppFlow.from_client_secrets_file(CLIENT_SECRET_PATH, SCOPES)
            toast("Opening browser to sign in…", "info")
            creds = flow.run_local_server(
                port=0,
                open_browser=True,
                success_message="Signed in — you can close this tab.",
            )
            state["creds"] = creds
            save_token_to_storage(creds)
            toast("Connected to Google Drive", "success")
            do_search(0, state.get("text", ""))
        except Exception as e:
            log("oauth error:", e)
            toast(f"Sign-in failed: {e}", "error")
        finally:
            state["auth_pending"] = False

    threading.Thread(target=worker, daemon=True).start()


# ------------------------------------------------------------------- actions --


def handle_action(item_id, action):
    if item_id == "connect" and action == "default":
        render_message("Connecting…", "A browser window will open to sign in")
        start_oauth_flow()
        return

    if action == "signout" and item_id in ("", "signout"):
        state["creds"] = None
        clear_token_storage()
        toast("Disconnected from Google Drive")
        do_search(0, state.get("text", ""))
        return

    if item_id == "..":
        go_up()
        return

    f = state.get("files", {}).get(item_id)
    if not f:
        return

    is_folder = f.get("mimeType") == FOLDER_MIME

    if action == "default":
        if is_folder:
            enter_folder(f["id"], f["name"])
        else:
            send(
                {"type": "command", "command": "open", "url": f.get("webViewLink", "")}
            )
            send({"type": "command", "command": "hide"})
    elif action == "open_browser":
        send({"type": "command", "command": "open", "url": f.get("webViewLink", "")})
        send({"type": "command", "command": "hide"})
    elif action == "copy_link":
        send({"type": "command", "command": "copy", "text": f.get("webViewLink", "")})
        toast("Link copied")
    elif action == "download":
        link = f.get("webContentLink") or f.get("webViewLink", "")
        send({"type": "command", "command": "open", "url": link})
        send({"type": "command", "command": "hide"})


# --------------------------------------------------------------------- main --


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

        elif t == "init":
            state["text"] = msg.get("query", "")
            render_message("Loading…")
            request_token_from_storage()

        elif t == "query":
            state["text"] = msg.get("text", "")
            rev = msg.get("rev", 0)
            if state["checked_storage"]:
                do_search(rev, state["text"])
            else:
                render_message("Loading…")

        elif t == "storage":
            if msg.get("requestId") == "boot":
                state["checked_storage"] = True
                val = msg.get("value")
                if val:
                    try:
                        state["creds"] = dict_to_creds(json.loads(val))
                    except Exception as e:
                        log("stored token unreadable:", e)
                do_search(0, state.get("text", ""))

        elif t == "action":
            handle_action(msg.get("id", ""), msg.get("action", "default"))

        elif t == "back":
            go_up()

        # "select" / "loadMore": not needed for this plugin.


if __name__ == "__main__":
    main()
