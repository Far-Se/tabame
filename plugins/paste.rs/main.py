import json
import sys
import threading
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from tkinter import Tk, filedialog

API_URL = "https://paste.rs/"
PLUGIN_DIR = Path.cwd()
HISTORY_PATH = PLUGIN_DIR / "history.json"
MAX_HISTORY = 50

state = {
    "screen": "root",
    "query": "",
    "last_rev": 0,
    "uploading": False,
}


def send(message):
    sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def command(name, **kwargs):
    send({"type": "command", "command": name, **kwargs})


def load_history():
    try:
        with HISTORY_PATH.open("r", encoding="utf-8") as f:
            history = json.load(f)
        return history if isinstance(history, list) else []
    except (OSError, json.JSONDecodeError):
        return []


def save_history(history):
    trimmed_history = history[:MAX_HISTORY]
    temp_path = HISTORY_PATH.with_suffix(".tmp")

    with temp_path.open("w", encoding="utf-8") as f:
        json.dump(trimmed_history, f, ensure_ascii=False, indent=2)

    temp_path.replace(HISTORY_PATH)


def add_history(url, source, size, partial=False, path=None):
    entry = {
        "id": url.rsplit("/", 1)[-1],
        "url": url,
        "source": source,
        "size": size,
        "partial": partial,
        "createdAt": datetime.now(timezone.utc).isoformat(),
    }

    if path:
        entry["path"] = path

    history = load_history()
    history = [item for item in history if item.get("url") != url]
    history.insert(0, entry)
    save_history(history)

    return entry


def upload_bytes(data):
    request = urllib.request.Request(
        API_URL,
        data=data,
        method="POST",
        headers={
            "Content-Type": "application/octet-stream",
            "User-Agent": "Tabame-paste.rs-plugin/1.0",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            status = response.getcode()
            url = response.read().decode("utf-8", errors="replace").strip()

    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace").strip()
        raise RuntimeError(
            f"paste.rs returned HTTP {error.code}: {body or error.reason}"
        )

    except urllib.error.URLError as error:
        raise RuntimeError(f"Could not reach paste.rs: {error.reason}")

    if status not in (201, 206):
        raise RuntimeError(f"paste.rs returned unexpected HTTP status {status}")

    if not url.startswith(("http://", "https://")):
        raise RuntimeError("paste.rs did not return a valid paste URL")

    return url, status == 206


def relative_time(iso_time):
    try:
        then = datetime.fromisoformat(iso_time.replace("Z", "+00:00"))
        seconds = max(0, int((datetime.now(timezone.utc) - then).total_seconds()))
    except (TypeError, ValueError):
        return ""

    if seconds < 60:
        return "just now"
    if seconds < 3600:
        return f"{seconds // 60}m ago"
    if seconds < 86400:
        return f"{seconds // 3600}h ago"
    return f"{seconds // 86400}d ago"


def format_size(size):
    units = ["B", "KB", "MB", "GB"]
    value = float(size)

    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.1f} {unit}" if unit != "B" else f"{int(value)} B"
        value /= 1024

    return f"{int(size)} B"


def root_items(query):
    query_lower = query.strip().lower()

    items = [
        {
            "id": "upload-text",
            "title": "Upload typed text",
            "subtitle": "Paste code, notes, logs, or any other text into a textarea",
            "icon": "code",
            "section": "Upload",
            "actions": [
                {"id": "default", "title": "Open text editor", "icon": "edit"},
            ],
        },
        {
            "id": "upload-file",
            "title": "Upload file",
            "subtitle": "Choose a local file and upload its raw contents",
            "icon": "file",
            "section": "Upload",
            "actions": [
                {"id": "default", "title": "Choose file", "icon": "folder"},
            ],
        },
        {
            "id": "history",
            "title": "Paste history",
            "subtitle": f"{len(load_history())}/50 saved links",
            "icon": "clock",
            "section": "Browse",
            "actions": [
                {"id": "default", "title": "Open history", "icon": "clock"},
            ],
        },
    ]

    if not query_lower:
        return items

    return [
        item
        for item in items
        if query_lower in item["title"].lower()
        or query_lower in item["subtitle"].lower()
    ]


def render_root(rev=0, query=""):
    state["screen"] = "root"
    state["query"] = query
    state["last_rev"] = rev

    if state["uploading"]:
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "list",
                "loading": True,
                "items": [],
                "emptyText": "Uploading to paste.rs…",
            }
        )
        return

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "items": root_items(query),
            "placeholder": "Choose an upload option or browse history",
            "empty": {
                "icon": "search",
                "title": "No matching actions",
                "hint": "Clear the query to see available actions",
            },
        }
    )


def render_text_form():
    state["screen"] = "text-form"

    send(
        {
            "type": "render",
            "rev": 0,
            "view": "form",
            "canGoBack": True,
            "form": {
                "title": "Upload typed text",
                "submitLabel": "Upload to paste.rs",
                "fields": [
                    {
                        "id": "content",
                        "type": "textarea",
                        "label": "Text or code",
                        "placeholder": "Paste or type your code, logs, notes, or text here…",
                    }
                ],
            },
        }
    )


def history_items(query):
    query_lower = query.strip().lower()
    items = []

    for entry in load_history():
        url = entry.get("url", "")
        source = entry.get("source", "Text")
        size = entry.get("size", 0)
        created = relative_time(entry.get("createdAt", ""))
        partial = bool(entry.get("partial"))

        searchable = " ".join(
            [
                entry.get("id", ""),
                url,
                source,
                entry.get("path", ""),
            ]
        ).lower()

        if query_lower and query_lower not in searchable:
            continue

        items.append(
            {
                "id": f"history:{url}",
                "title": entry.get("id", url),
                "subtitle": f"{source} · {format_size(size)} · {created}",
                "icon": "warning" if partial else "link",
                "section": "History",
                "accessories": [
                    {
                        "text": "Partial" if partial else "Saved",
                        "color": "F59E0B" if partial else "22C55E",
                    }
                ],
                "actions": [
                    {"id": "default", "title": "Open paste", "icon": "open"},
                    {"id": "copy", "title": "Copy link", "icon": "copy"},
                    {"id": "delete", "title": "Remove from history", "icon": "delete"},
                ],
                "preview": {
                    "markdown": f"## {entry.get('id', 'Paste')}\n\n`{url}`",
                    "metadata": [
                        {
                            "label": "Status",
                            "text": "Partial upload" if partial else "Uploaded",
                            "color": "F59E0B" if partial else "22C55E",
                        },
                        {"label": "Source", "text": source},
                        {"label": "Size", "text": format_size(size)},
                        {"label": "Created", "text": entry.get("createdAt", "")},
                        {"label": "URL", "text": url, "url": url},
                    ],
                },
            }
        )

    return items


def render_history(rev=0, query=""):
    state["screen"] = "history"
    state["query"] = query
    state["last_rev"] = rev

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "preview": {"enabled": True, "wide": False},
            "placeholder": "Filter saved pastes",
            "items": history_items(query),
            "empty": {
                "icon": "clock",
                "title": "No saved pastes",
                "hint": "Upload text or a file first",
            },
        }
    )


def render_result(entry):
    state["screen"] = "result"

    partial_note = ""
    if entry["partial"]:
        partial_note = "\n\n> **Warning:** paste.rs accepted only part of this upload."

    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "canGoBack": True,
            "detail": {
                "markdown": (
                    "# Paste uploaded\n\n"
                    f"[{entry['url']}]({entry['url']})"
                    f"{partial_note}"
                ),
                "metadata": [
                    {"label": "Source", "text": entry["source"]},
                    {"label": "Size", "text": format_size(entry["size"])},
                    {"label": "URL", "text": entry["url"], "url": entry["url"]},
                ],
            },
        }
    )


def render_error(message):
    state["screen"] = "error"

    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "canGoBack": True,
            "detail": {
                "markdown": f"# Upload failed\n\n`{message}`",
            },
        }
    )


def run_upload(data, source, path=None):
    try:
        url, partial = upload_bytes(data)
        entry = add_history(url, source, len(data), partial, path)

        command("copy", text=url)
        command("toast", text="Paste URL copied to clipboard")
        render_result(entry)

    except Exception as error:
        log("Upload error:", error)
        render_error(str(error))

    finally:
        state["uploading"] = False


def upload_text(text):
    if not isinstance(text, str) or not text.strip():
        command("toast", text="Enter some text before uploading")
        render_text_form()
        return

    state["uploading"] = True

    send(
        {
            "type": "render",
            "rev": 0,
            "view": "list",
            "loading": True,
            "items": [],
            "emptyText": "Uploading text to paste.rs…",
        }
    )

    threading.Thread(
        target=run_upload,
        args=(text.encode("utf-8"), "Typed text"),
        daemon=True,
    ).start()


def choose_file():
    try:
        root = Tk()
        root.withdraw()
        root.attributes("-topmost", True)

        path = filedialog.askopenfilename(title="Choose a file to upload to paste.rs")

        root.destroy()

    except Exception as error:
        render_error(f"Could not open the file picker: {error}")
        return

    if not path:
        command("toast", text="No file selected")
        render_root(0, "")
        return

    try:
        data = Path(path).read_bytes()
    except OSError as error:
        render_error(f"Could not read file: {error}")
        return

    state["uploading"] = True

    send(
        {
            "type": "render",
            "rev": 0,
            "view": "list",
            "loading": True,
            "items": [],
            "emptyText": f"Uploading {Path(path).name}…",
        }
    )

    threading.Thread(
        target=run_upload,
        args=(data, Path(path).name, path),
        daemon=True,
    ).start()


def delete_history_item(url):
    history = load_history()
    save_history([item for item in history if item.get("url") != url])

    command("toast", text="Removed from local history")
    render_history(0, state["query"])


def handle_action(item_id, action):
    if item_id == "upload-text":
        command("setQuery", text="")
        render_text_form()
        return

    if item_id == "upload-file":
        choose_file()
        return

    if item_id == "history":
        command("setQuery", text="")
        render_history(0, "")
        return

    if item_id.startswith("history:"):
        url = item_id[len("history:") :]

        if action == "copy":
            command("copy", text=url)
            return

        if action == "delete":
            delete_history_item(url)
            return

        command("open", url=url)


def handle_submit(values):
    if state["screen"] == "text-form":
        upload_text(values.get("content", ""))


def handle_back():
    if state["screen"] != "root":
        command("setQuery", text="")
        render_root(0, "")


def main():
    for line in sys.stdin:
        line = line.strip()

        if not line:
            continue

        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue

        message_type = message.get("type")

        if message_type == "close":
            break

        if message_type in ("init", "query"):
            query = message.get("text", message.get("query", ""))
            rev = message.get("rev", 0)

            if state["screen"] == "root":
                render_root(rev, query)
            elif state["screen"] == "history":
                render_history(rev, query)
            else:
                state["query"] = query
                state["last_rev"] = rev

        elif message_type == "action":
            handle_action(
                message.get("id", ""),
                message.get("action", "default"),
            )

        elif message_type == "submit":
            handle_submit(message.get("values", {}))

        elif message_type == "back":
            handle_back()


if __name__ == "__main__":
    main()
