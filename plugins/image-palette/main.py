#!/usr/bin/env python3
"""
Tabame plugin: Color Palette
Keyword: palette

Type/paste an image path (or a file:// URI) after the keyword, or hit
Ctrl+K -> "Browse for an image..." to pick one via a filepicker form.
Renders the dominant colors as a grid of filled swatches; Enter copies
the hex code, Ctrl+K on a swatch offers rgb() too.
"""
import sys
import os
import json
import threading
from urllib.parse import unquote

try:
    from PIL import Image
    _IMPORT_ERROR = None
except Exception as e:  # missing/failed install -> degrade gracefully
    Image = None
    _IMPORT_ERROR = str(e)

_stdout_lock = threading.Lock()

BROWSE_ACTION = {"id": "browse", "title": "Browse for image…", "icon": "folder", "shortcut": "ctrl+o"}


def send(frame):
    with _stdout_lock:
        sys.stdout.write(json.dumps(frame) + "\n")
        sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def parse_path(text):
    """Accepts a plain path, a quoted path, or a file:// URI (incl. Windows drive letters)."""
    text = (text or "").strip().strip('"').strip("'")
    if text.lower().startswith("file://"):
        text = unquote(text[7:])
        if text.startswith("/") and len(text) > 2 and text[2] == ":":
            text = text[1:]  # file:///C:/... -> C:/...
    return text


def root_frame(rev):
    return {
        "type": "render", "rev": rev, "view": "list",
        "placeholder": "path to an image, or Ctrl+K to browse",
        "emptyText": "Paste/type an image path, or Ctrl+K to browse",
        "items": [{
            "id": "browse",
            "title": "Browse for an image…",
            "subtitle": "or paste/type a file path after the keyword",
            "icon": "folder",
            "actions": [BROWSE_ACTION],
        }],
    }


def error_frame(rev, message):
    return {
        "type": "render", "rev": rev, "view": "list",
        "items": [], "emptyText": message,
        "actions": [BROWSE_ACTION],
    }


def browse_form_frame():
    return {
        "type": "render", "rev": 0, "view": "form", "canGoBack": True,
        "form": {
            "title": "Choose an image",
            "submitLabel": "Extract palette",
            "fields": [
                {"id": "image", "type": "filepicker", "label": "Image file"},
                {"id": "count", "type": "number", "label": "Number of colors", "value": 8, "min": 2, "max": 16},
            ],
        },
    }


def build_palette_frame(rev, path, n=8):
    if not os.path.isfile(path):
        return error_frame(rev, f"Can't find: {path}")
    try:
        img = Image.open(path).convert("RGB")
        img.thumbnail((200, 200))
        quant = img.quantize(colors=n)
        palette = quant.getpalette()
        counts = quant.getcolors() or []
        counts.sort(reverse=True)
        total = sum(c for c, _ in counts) or 1
    except Exception as e:
        log("palette extraction failed:", e)
        return error_frame(rev, f"Couldn't read that image: {e}")

    items = []
    for count, idx in counts[:n]:
        r, g, b = palette[idx * 3: idx * 3 + 3]
        hexcode = f"#{r:02X}{g:02X}{b:02X}"
        pct = count / total * 100
        items.append({
            "id": hexcode,
            "title": hexcode,
            "subtitle": f"rgb({r}, {g}, {b})",
            "tileColor": hexcode,
            "accessories": [{"text": f"{pct:.0f}%"}],
            "actions": [
                {"id": "copy_hex", "title": "Copy hex", "icon": "copy"},
                {"id": "copy_rgb", "title": "Copy rgb()", "icon": "copy"},
            ],
        })

    return {
        "type": "render", "rev": rev, "view": "grid",
        "grid": {"columns": min(len(items), 4) or 1, "aspectRatio": 1.2},
        "placeholder": "path to an image, or Ctrl+K to browse",
        "items": items,
        "actions": [BROWSE_ACTION],
    }


def handle_query(text, rev):
    text = (text or "").strip()
    if not text:
        send(root_frame(rev))
        return
    path = parse_path(text)

    def work():
        send({"type": "render", "rev": rev, "view": "grid", "loading": True,
              "loadingText": "Reading image…", "items": []})
        send(build_palette_frame(rev, path))

    threading.Thread(target=work, daemon=True).start()


def handle_action(item_id, action):
    # The root screen's only item IS "browse" — Enter on it sends action:"default"
    # (per spec, Enter always fires "default" regardless of the item's own actions),
    # so catch it by item id too, not just by the Ctrl+K action id.
    if action == "browse" or item_id == "browse":
        send(browse_form_frame())
        return
    color = item_id  # hex code was used as the item id
    if action in ("default", "copy_hex"):
        send({"type": "command", "command": "copy", "text": color})
        send({"type": "command", "command": "toast", "text": f"Copied {color}"})
    elif action == "copy_rgb":
        try:
            r, g, b = int(color[1:3], 16), int(color[3:5], 16), int(color[5:7], 16)
            rgb_text = f"rgb({r}, {g}, {b})"
        except Exception:
            rgb_text = color
        send({"type": "command", "command": "copy", "text": rgb_text})
        send({"type": "command", "command": "toast", "text": f"Copied {rgb_text}"})


def handle_submit(values):
    path = parse_path(values.get("image", ""))
    try:
        n = int(values.get("count") or 8)
    except (TypeError, ValueError):
        n = 8
    if not path:
        send(error_frame(0, "No image selected"))
        return

    def work():
        send({"type": "render", "rev": 0, "view": "grid", "loading": True,
              "loadingText": "Reading image…", "items": []})
        send(build_palette_frame(0, path, n))
        send({"type": "command", "command": "setQuery", "text": path})

    threading.Thread(target=work, daemon=True).start()


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
            rev = msg.get("rev", 0)
            if Image is None:
                send(error_frame(rev, f"Pillow isn't available: {_IMPORT_ERROR}"))
                continue
            handle_query(msg.get("text", msg.get("query", "")), rev)

        elif t == "action":
            if Image is None:
                send(error_frame(0, f"Pillow isn't available: {_IMPORT_ERROR}"))
                continue
            handle_action(msg.get("id", ""), msg.get("action", "default"))

        elif t == "submit":
            if Image is None:
                send(error_frame(0, f"Pillow isn't available: {_IMPORT_ERROR}"))
                continue
            handle_submit(msg.get("values", {}))

        elif t == "back":
            send(root_frame(msg.get("rev", 0)))

        # "select": not needed — grid tiles are already self-explanatory.


if __name__ == "__main__":
    main()
