#!/usr/bin/env python3
"""
Tabame Launcher Plugin: Image Converter
Keyword: img

Convert single images or whole folders between PNG, JPEG, WebP, BMP, GIF,
TIFF, ICO and PDF, with resize / rotate / flip / grayscale, per-format
quality options, and batch processing with background completion.
"""
import sys
import os
import re
import json
import threading

def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()

def log(*a):
    print(*a, file=sys.stderr, flush=True)

try:
    from PIL import Image
    PIL_IMPORT_ERROR = None
except Exception as e:  # pragma: no cover
    Image = None
    PIL_IMPORT_ERROR = str(e)

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif", ".tiff", ".tif", ".ico"}
THUMBNAIL_EXTS = {".png", ".jpg", ".jpeg", ".bmp"}  # safe to use as file:// icons

FORMATS = {
    "png":  {"title": "PNG",  "subtitle": "Lossless \u00b7 transparency supported",      "ext": "png",  "icon": "image"},
    "jpg":  {"title": "JPEG", "subtitle": "Lossy \u00b7 smaller files, no transparency",  "ext": "jpg",  "icon": "image"},
    "webp": {"title": "WebP", "subtitle": "Modern format \u00b7 lossy or lossless",       "ext": "webp", "icon": "image"},
    "bmp":  {"title": "BMP",  "subtitle": "Uncompressed bitmap",                          "ext": "bmp",  "icon": "image"},
    "gif":  {"title": "GIF",  "subtitle": "256 colors \u00b7 simple, wide support",       "ext": "gif",  "icon": "image"},
    "tiff": {"title": "TIFF", "subtitle": "High quality \u00b7 archival / print",         "ext": "tiff", "icon": "image"},
    "ico":  {"title": "ICO",  "subtitle": "Windows icon \u00b7 multiple sizes embedded",  "ext": "ico",  "icon": "app"},
    "pdf":  {"title": "PDF",  "subtitle": "Document \u00b7 single or multi-page",         "ext": "pdf",  "icon": "document"},
}

MAX_RECENTS = 8

state = {
    "screen": "root",          # root | formatSelect | optionsForm | pickFileForm | pickFolderForm | settingsForm | result
    "batch": False,
    "filePath": None,
    "folderPath": None,
    "lastBrowsedFolder": None,
    "targetFormat": None,
    "lastResult": None,
    "settings": {"default_quality": 85},
    "recents": [],
}

# ---------------------------------------------------------------- helpers --

def expand(p):
    return os.path.normpath(os.path.expanduser(os.path.expandvars(p.strip().strip('"'))))

def is_image_file(path):
    return os.path.isfile(path) and os.path.splitext(path)[1].lower() in IMAGE_EXTS

def human_size(n):
    n = float(n)
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.0f}{unit}" if unit == "B" else f"{n:.1f}{unit}"
        n /= 1024
    return f"{n:.1f}TB"

def thumb_icon(path):
    ext = os.path.splitext(path)[1].lower()
    return f"file://{path}" if ext in THUMBNAIL_EXTS else "image"

def strip_prefix(item_id):
    return item_id.split(":", 1)[1] if ":" in item_id else item_id

def unique_path(path):
    if not os.path.exists(path):
        return path
    base, ext = os.path.splitext(path)
    i = 2
    while os.path.exists(f"{base} ({i}){ext}"):
        i += 1
    return f"{base} ({i}){ext}"

def list_images_in_folder(folder, recursive=False):
    out = []
    if recursive:
        for root, _dirs, files in os.walk(folder):
            for f in files:
                if os.path.splitext(f)[1].lower() in IMAGE_EXTS:
                    out.append(os.path.join(root, f))
    else:
        try:
            for f in os.listdir(folder):
                fp = os.path.join(folder, f)
                if is_image_file(fp):
                    out.append(fp)
        except OSError:
            pass
    return sorted(out)

def push_recent(path):
    r = state["recents"]
    if path in r:
        r.remove(path)
    r.insert(0, path)
    state["recents"] = r[:MAX_RECENTS]
    send({"type": "command", "command": "storage", "op": "set",
          "key": "recents", "value": json.dumps(state["recents"])})

# ------------------------------------------------------------- conversion --

def apply_transforms(im, opts):
    rotate = int(opts.get("rotate") or 0)
    if rotate:
        im = im.rotate(-rotate, expand=True)

    flip = opts.get("flip") or "none"
    if flip == "horizontal":
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    elif flip == "vertical":
        im = im.transpose(Image.FLIP_TOP_BOTTOM)

    resize = opts.get("resize") or "none"
    if resize != "none":
        w, h = im.size
        if resize == "custom":
            nw, nh = opts.get("width"), opts.get("height")
            keep = opts.get("keep_aspect", True)
            if nw and not nh and keep:
                nh = round(h * (nw / w))
            elif nh and not nw and keep:
                nw = round(w * (nh / h))
            if nw and nh:
                im = im.resize((max(1, int(nw)), max(1, int(nh))), Image.LANCZOS)
        else:
            pct = int(str(resize).rstrip("%")) / 100.0
            im = im.resize((max(1, round(w * pct)), max(1, round(h * pct))), Image.LANCZOS)

    if opts.get("grayscale"):
        im = im.convert("L")
    return im

def save_as(im, fmt, out_path, opts):
    if fmt == "jpg":
        if im.mode in ("RGBA", "P", "LA"):
            bg = Image.new("RGB", im.size, (255, 255, 255))
            rgba = im.convert("RGBA")
            bg.paste(rgba, mask=rgba.split()[-1])
            im = bg
        elif im.mode != "RGB":
            im = im.convert("RGB")
        im.save(out_path, "JPEG", quality=int(opts.get("quality", 85)),
                 optimize=True, progressive=bool(opts.get("progressive", False)))
    elif fmt == "png":
        im.save(out_path, "PNG", optimize=True,
                 compress_level=int(opts.get("compress_level", 6)))
    elif fmt == "webp":
        if opts.get("lossless"):
            im.save(out_path, "WEBP", lossless=True)
        else:
            im.save(out_path, "WEBP", quality=int(opts.get("quality", 85)))
    elif fmt == "bmp":
        if im.mode not in ("RGB", "L"):
            im = im.convert("RGB")
        im.save(out_path, "BMP")
    elif fmt == "gif":
        im = im.convert("P", palette=Image.ADAPTIVE)
        im.save(out_path, "GIF")
    elif fmt == "tiff":
        comp = opts.get("compression", "tiff_lzw")
        im.save(out_path, "TIFF", compression=None if comp == "none" else comp)
    elif fmt == "ico":
        sizes_raw = opts.get("sizes") or ["16", "32", "48", "256"]
        sizes = [(int(s), int(s)) for s in sizes_raw]
        if im.mode != "RGBA":
            im = im.convert("RGBA")
        im.save(out_path, "ICO", sizes=sizes)
    elif fmt == "pdf":
        if im.mode != "RGB":
            im = im.convert("RGB")
        im.save(out_path, "PDF", resolution=100.0)
    else:
        raise ValueError(f"Unsupported target format: {fmt}")

def convert_one(src, fmt, opts, out_dir=None, overwrite=False):
    im = Image.open(src)
    im.load()
    orig_size = os.path.getsize(src)
    orig_dims = im.size
    im = apply_transforms(im, opts)

    ext = FORMATS[fmt]["ext"]
    base = os.path.splitext(os.path.basename(src))[0]
    suffix = opts.get("suffix") or ""
    target_dir = out_dir or os.path.dirname(src) or "."
    os.makedirs(target_dir, exist_ok=True)
    out_path = os.path.join(target_dir, f"{base}{suffix}.{ext}")
    if not overwrite:
        out_path = unique_path(out_path)

    save_as(im, fmt, out_path, opts)
    new_size = os.path.getsize(out_path)
    return {
        "src": src, "out": out_path,
        "orig_size": orig_size, "new_size": new_size,
        "orig_dims": orig_dims, "new_dims": im.size,
    }

def combine_pdf(files, out_path, opts):
    imgs = []
    for f in files:
        im = Image.open(f)
        im.load()
        im = apply_transforms(im, opts)
        if im.mode != "RGB":
            im = im.convert("RGB")
        imgs.append(im)
    if not imgs:
        raise ValueError("No images to combine")
    first, rest = imgs[0], imgs[1:]
    first.save(out_path, "PDF", save_all=True, append_images=rest, resolution=100.0)
    return out_path

# ------------------------------------------------------------------ views --

def render_root(text, rev):
    text = (text or "")

    if PIL_IMPORT_ERROR:
        send({"type": "render", "rev": rev, "view": "detail",
              "detail": {"markdown": "# Missing dependency\n\nPillow failed to install:\n\n"
                                      f"```\n{PIL_IMPORT_ERROR}\n```\n\nReopen the launcher to retry."}})
        return

    root_actions = [
        {"id": "pick_file", "title": "Pick image file", "icon": "file"},
        {"id": "pick_folder", "title": "Batch convert a folder", "icon": "folder"},
        {"id": "paste_clip", "title": "Use path from clipboard", "icon": "paste"},
        {"id": "settings", "title": "Settings", "icon": "settings"},
    ]

    if not text.strip():
        # Expose the frame-level actions as ordinary rows when the user has
        # entered only the plugin keyword, so they are immediately selectable.
        items = [
            {"id": f"root_action:{action['id']}", "title": action["title"],
             "icon": action["icon"], "section": "Actions"}
            for action in root_actions
        ]
        for p in state["recents"]:
            if os.path.exists(p):
                items.append({
                    "id": f"file:{p}", "title": os.path.basename(p), "subtitle": p,
                    "icon": thumb_icon(p), "section": "Recent",
                    "actions": [
                        {"id": "reveal", "title": "Reveal in folder", "icon": "folder"},
                        {"id": "copy_path", "title": "Copy path", "icon": "copy"},
                    ],
                })
        send({
            "type": "render", "rev": rev, "view": "list",
            "placeholder": "Type or paste an image / folder path\u2026",
            "emptyText": "Paste a path, or pick a file / folder below",
            "items": items,
            "actions": root_actions,
        })
        return

    # power-user shorthand: "photo.png to jpg"
    m = re.match(r"^(.*\S)\s+to\s+(\w+)\s*$", text.strip(), re.IGNORECASE)
    if m:
        cand = expand(m.group(1))
        fk = m.group(2).lower()
        if fk in FORMATS and is_image_file(cand):
            quick_convert(cand, fk, rev)
            return

    resolved = expand(text)

    if os.path.isdir(resolved):
        state["lastBrowsedFolder"] = resolved
        items = []
        try:
            entries = sorted(os.listdir(resolved))
        except OSError:
            entries = []
        for name in entries:
            fp = os.path.join(resolved, name)
            if os.path.isdir(fp):
                items.append({"id": f"dir:{fp}", "title": name + "/", "subtitle": fp,
                              "icon": "folder", "section": "Folders"})
        for name in entries:
            fp = os.path.join(resolved, name)
            if is_image_file(fp):
                items.append({
                    "id": f"file:{fp}", "title": name,
                    "subtitle": human_size(os.path.getsize(fp)),
                    "icon": thumb_icon(fp), "section": "Images",
                    "actions": [
                        {"id": "reveal", "title": "Reveal in folder", "icon": "folder"},
                        {"id": "copy_path", "title": "Copy path", "icon": "copy"},
                    ],
                })
        send({
            "type": "render", "rev": rev, "view": "list",
            "placeholder": "Type or paste an image / folder path\u2026",
            "emptyText": "No images in this folder",
            "items": items,
            "actions": [{"id": "batch_here", "title": "Batch convert all images in this folder",
                         "icon": "folder"}] + root_actions,
        })
        return

    if is_image_file(resolved):
        try:
            with Image.open(resolved) as im:
                dims, mode = im.size, im.mode
        except Exception:
            dims, mode = None, None
        subtitle = (f"{dims[0]}\u00d7{dims[1]} \u00b7 {mode} \u00b7 {human_size(os.path.getsize(resolved))}"
                    if dims else human_size(os.path.getsize(resolved)))
        item = {
            "id": f"file:{resolved}", "title": os.path.basename(resolved), "subtitle": subtitle,
            "icon": thumb_icon(resolved),
            "actions": [
                {"id": "reveal", "title": "Reveal in folder", "icon": "folder"},
                {"id": "copy_path", "title": "Copy path", "icon": "copy"},
            ],
            "preview": {"markdown": f"**{os.path.basename(resolved)}**\n\n{subtitle}"},
        }
        send({
            "type": "render", "rev": rev, "view": "list",
            "preview": {"enabled": True},
            "placeholder": "Type or paste an image / folder path\u2026",
            "items": [item],
        })
        return

    send({
        "type": "render", "rev": rev, "view": "list",
        "placeholder": "Type or paste an image / folder path\u2026",
        "emptyText": f"No file or folder found at:\n{resolved}",
        "items": [],
        "actions": root_actions,
    })

def render_format_select(rev):
    src_label = (os.path.basename(state["folderPath"].rstrip(os.sep)) + "/") \
        if state["batch"] else os.path.basename(state["filePath"])
    items = [
        {"id": f"fmt:{key}", "title": f"Convert to {meta['title']}",
         "subtitle": meta["subtitle"], "icon": meta["icon"]}
        for key, meta in FORMATS.items()
    ]
    send({
        "type": "render", "rev": rev, "view": "list", "canGoBack": True,
        "placeholder": f"Choose a format for {src_label}",
        "items": items,
    })

def build_fields(fmt, batch):
    fields = [
        {"id": "resize", "type": "dropdown", "label": "Resize", "value": "none",
         "options": ["none", "50%", "75%", "150%", "200%", "custom"]},
        {"id": "width", "type": "number", "label": "Custom width (px)"},
        {"id": "height", "type": "number", "label": "Custom height (px)"},
        {"id": "keep_aspect", "type": "checkbox", "label": "Keep aspect ratio", "value": True},
        {"id": "rotate", "type": "dropdown", "label": "Rotate", "value": "0",
         "options": ["0", "90", "180", "270"]},
        {"id": "flip", "type": "dropdown", "label": "Flip", "value": "none",
         "options": ["none", "horizontal", "vertical"]},
        {"id": "grayscale", "type": "checkbox", "label": "Convert to grayscale", "value": False},
    ]
    if fmt in ("jpg", "webp"):
        fields.append({"id": "quality", "type": "number", "label": "Quality",
                        "value": state["settings"].get("default_quality", 85), "min": 1, "max": 100})
    if fmt == "jpg":
        fields.append({"id": "progressive", "type": "checkbox", "label": "Progressive JPEG", "value": False})
    if fmt == "webp":
        fields.append({"id": "lossless", "type": "checkbox", "label": "Lossless", "value": False,
                        "description": "Ignores quality when enabled"})
    if fmt == "png":
        fields.append({"id": "compress_level", "type": "number", "label": "Compression level (0\u20139)",
                        "value": 6, "min": 0, "max": 9})
    if fmt == "tiff":
        fields.append({"id": "compression", "type": "dropdown", "label": "Compression", "value": "tiff_lzw",
                        "options": ["none", "tiff_lzw", "tiff_deflate", "jpeg"]})
    if fmt == "ico":
        fields.append({"id": "sizes", "type": "tags", "label": "Icon sizes (px)",
                        "value": ["16", "32", "48", "256"],
                        "options": ["16", "24", "32", "48", "64", "128", "256"]})
    if fmt == "pdf" and batch:
        fields.append({"id": "combine", "type": "checkbox",
                        "label": "Combine into one multi-page PDF", "value": True})
    if batch:
        fields.append({"id": "include_subfolders", "type": "checkbox",
                        "label": "Include subfolders", "value": False})
    fields.append({"id": "suffix", "type": "text", "label": "Filename suffix",
                    "placeholder": "e.g. _converted"})
    fields.append({"id": "overwrite", "type": "checkbox", "label": "Overwrite if file exists", "value": False})
    fields.append({"id": "out_dir", "type": "folderpicker",
                    "label": "Output folder", "description": "Leave empty to use the source location"})
    return fields

def render_options_form(rev):
    fmt = state["targetFormat"]
    meta = FORMATS[fmt]
    src_label = (os.path.basename(state["folderPath"].rstrip(os.sep)) + "/") \
        if state["batch"] else os.path.basename(state["filePath"])
    send({
        "type": "render", "rev": rev, "view": "form", "canGoBack": True,
        "form": {
            "title": f"Convert {src_label} \u2192 {meta['title']}",
            "submitLabel": "Convert",
            "fields": build_fields(fmt, state["batch"]),
        },
    })

def render_single_result(res):
    state["screen"] = "result"
    ratio = (1 - res["new_size"] / res["orig_size"]) * 100 if res["orig_size"] else 0
    send({
        "type": "render", "rev": 0, "view": "detail", "canGoBack": True,
        "detail": {
            "markdown": f"# Converted\n\n**{os.path.basename(res['src'])}** \u2192 "
                        f"**{os.path.basename(res['out'])}**",
            "metadata": [
                {"label": "Original size", "text": human_size(res["orig_size"])},
                {"label": "New size", "text": human_size(res["new_size"])},
                {"label": "Size change", "text": f"{'-' if ratio > 0 else '+'}{abs(ratio):.0f}%",
                 "color": "#22C55E" if ratio > 0 else "#EF4444"},
                {"label": "Dimensions",
                 "text": f"{res['orig_dims'][0]}\u00d7{res['orig_dims'][1]} \u2192 "
                         f"{res['new_dims'][0]}\u00d7{res['new_dims'][1]}"},
                {"separator": True},
                {"label": "Output path", "text": res["out"]},
            ],
        },
        "actions": [
            {"id": "open_file", "title": "Open converted file", "icon": "open"},
            {"id": "open_folder", "title": "Reveal in folder", "icon": "folder"},
            {"id": "copy_out_path", "title": "Copy output path", "icon": "copy"},
            {"id": "delete_original", "title": "Delete original", "icon": "trash", "destructive": True,
             "confirm": {"title": "Delete original file?", "message": "This cannot be undone.",
                         "confirmLabel": "Delete"}},
            {"id": "convert_another", "title": "Convert another", "icon": "refresh"},
        ],
    })

def render_batch_started(count, fmt):
    send({
        "type": "render", "rev": 0, "view": "detail", "canGoBack": True,
        "detail": {"markdown": f"# Converting in background\n\n{count} image(s) \u2192 "
                                f"{FORMATS[fmt]['title']}\n\nYou'll get a notification when it's done. "
                                "You can keep using the launcher."},
    })

# --------------------------------------------------------------- actions --

def quick_convert(path, fmt, rev):
    send({"type": "render", "rev": rev, "view": "list", "loading": True, "items": [],
          "loadingText": f"Converting to {FORMATS[fmt]['title']}\u2026"})
    try:
        opts = {"resize": "none", "rotate": "0", "flip": "none", "grayscale": False,
                "quality": state["settings"].get("default_quality", 85)}
        res = convert_one(path, fmt, opts, None, False)
        state["filePath"] = path
        state["targetFormat"] = fmt
        state["batch"] = False
        state["lastResult"] = res
        push_recent(res["out"])
        render_single_result(res)
    except Exception as e:
        send({"type": "render", "rev": 0, "view": "detail", "canGoBack": True,
              "detail": {"markdown": f"# Conversion failed\n\n```\n{e}\n```"}})

def run_conversion(opts):
    fmt = state["targetFormat"]
    out_dir = opts.get("out_dir") or None
    overwrite = bool(opts.get("overwrite"))

    if not state["batch"]:
        send({"type": "render", "rev": 0, "view": "list", "loading": True, "items": [],
              "loadingText": "Converting\u2026"})

        def work():
            try:
                res = convert_one(state["filePath"], fmt, opts, out_dir, overwrite)
                state["lastResult"] = res
                push_recent(res["out"])
                render_single_result(res)
            except Exception as e:
                send({"type": "render", "rev": 0, "view": "detail", "canGoBack": True,
                      "detail": {"markdown": f"# Conversion failed\n\n```\n{e}\n```"}})

        threading.Thread(target=work, daemon=True).start()
        return

    folder = state["folderPath"]
    files = list_images_in_folder(folder, recursive=bool(opts.get("include_subfolders")))
    if not files:
        send({"type": "render", "rev": 0, "view": "detail", "canGoBack": True,
              "detail": {"markdown": "# No images found in that folder."}})
        return

    render_batch_started(len(files), fmt)

    def work():
        send({"type": "command", "command": "background", "timeout": 240})
        send({"type": "command", "command": "hide"})
        results, errors = [], []
        try:
            if fmt == "pdf" and opts.get("combine"):
                out = os.path.join(out_dir or folder, "combined.pdf")
                if not overwrite:
                    out = unique_path(out)
                combine_pdf(files, out, opts)
                results.append(out)
            else:
                for f in files:
                    try:
                        r = convert_one(f, fmt, opts, out_dir, overwrite)
                        results.append(r["out"])
                    except Exception as e:
                        errors.append(f"{os.path.basename(f)}: {e}")
        except Exception as e:
            errors.append(str(e))

        msg = f"Converted {len(results)}/{len(files)} image(s)"
        if errors:
            msg += f" \u00b7 {len(errors)} failed"
        send({"type": "command", "command": "notify", "title": "Image Converter", "text": msg})
        if results:
            push_recent(results[-1])

    threading.Thread(target=work, daemon=True).start()

def handle_frame_action(action):
    if action == "pick_file":
        state["screen"] = "pickFileForm"
        send({"type": "render", "rev": 0, "view": "form", "canGoBack": True,
              "form": {"title": "Pick an image", "submitLabel": "Continue",
                       "fields": [{"id": "file", "type": "filepicker", "label": "Image file",
                                   "required": True}]}})
        return
    if action == "pick_folder":
        state["screen"] = "pickFolderForm"
        send({"type": "render", "rev": 0, "view": "form", "canGoBack": True,
              "form": {"title": "Batch convert folder", "submitLabel": "Continue",
                       "fields": [{"id": "folder", "type": "folderpicker",
                                   "label": "Folder with images", "required": True}]}})
        return
    if action == "batch_here":
        folder = state.get("lastBrowsedFolder")
        if folder:
            state["folderPath"] = folder
            state["batch"] = True
            state["screen"] = "formatSelect"
            render_format_select(0)
        return
    if action == "paste_clip":
        send({"type": "command", "command": "clipboardRead", "requestId": "clip1"})
        return
    if action == "settings":
        state["screen"] = "settingsForm"
        s = state["settings"]
        send({"type": "render", "rev": 0, "view": "form", "canGoBack": True,
              "form": {"title": "Image Converter Settings", "submitLabel": "Save",
                       "fields": [{"id": "default_quality", "type": "number",
                                   "label": "Default JPEG / WebP quality",
                                   "value": s.get("default_quality", 85), "min": 1, "max": 100}]}})
        return

def handle_result_action(action):
    res = state["lastResult"]
    if not res:
        return
    if action == "convert_another":
        reset_to_root()
    elif action == "open_file":
        send({"type": "command", "command": "open", "path": res["out"]})
    elif action == "open_folder":
        send({"type": "command", "command": "open", "path": os.path.dirname(res["out"])})
    elif action == "copy_out_path":
        send({"type": "command", "command": "copy", "text": res["out"]})
        send({"type": "command", "command": "toast", "text": "Path copied"})
    elif action == "delete_original":
        try:
            os.remove(res["src"])
            send({"type": "command", "command": "toast", "text": "Original deleted"})
        except Exception as e:
            send({"type": "command", "command": "toast", "text": f"Could not delete: {e}", "style": "error"})

def handle_action(item_id, action):
    if item_id == "":
        handle_frame_action(action)
        return

    if item_id.startswith("root_action:") and action == "default":
        handle_frame_action(item_id.split(":", 1)[1])
        return

    if action == "reveal":
        target = strip_prefix(item_id)
        send({"type": "command", "command": "open", "path": os.path.dirname(target)})
        return
    if action == "copy_path":
        target = strip_prefix(item_id)
        send({"type": "command", "command": "copy", "text": target})
        send({"type": "command", "command": "toast", "text": "Path copied"})
        return

    if action == "default":
        if item_id.startswith("dir:"):
            send({"type": "command", "command": "setQuery", "text": item_id[4:] + os.sep})
            return
        if item_id.startswith("file:"):
            state["filePath"] = item_id[5:]
            state["batch"] = False
            state["screen"] = "formatSelect"
            render_format_select(0)
            return
        if item_id.startswith("fmt:"):
            state["targetFormat"] = item_id[4:]
            state["screen"] = "optionsForm"
            render_options_form(0)
            return

    if state["screen"] == "result":
        handle_result_action(action)

def handle_submit(values, _button):
    scr = state["screen"]
    if scr == "pickFileForm":
        path = expand(values.get("file") or "")
        if is_image_file(path):
            state["filePath"] = path
            state["batch"] = False
            state["screen"] = "formatSelect"
            render_format_select(0)
        else:
            send({"type": "render", "rev": 0, "view": "detail", "canGoBack": True,
                  "detail": {"markdown": "# Not a supported image\n\nPick a PNG, JPEG, WebP, "
                                         "BMP, GIF, TIFF or ICO file."}})
        return

    if scr == "pickFolderForm":
        folder = expand(values.get("folder") or "")
        if os.path.isdir(folder):
            state["folderPath"] = folder
            state["batch"] = True
            state["screen"] = "formatSelect"
            render_format_select(0)
        else:
            send({"type": "render", "rev": 0, "view": "detail", "canGoBack": True,
                  "detail": {"markdown": "# Folder not found"}})
        return

    if scr == "settingsForm":
        try:
            state["settings"]["default_quality"] = int(values.get("default_quality") or 85)
        except (TypeError, ValueError):
            pass
        send({"type": "command", "command": "storage", "op": "set",
              "key": "settings", "value": json.dumps(state["settings"])})
        send({"type": "command", "command": "toast", "text": "Settings saved"})
        reset_to_root()
        return

    if scr == "optionsForm":
        run_conversion(values)
        return

def handle_back(rev):
    scr = state["screen"]
    if scr in ("formatSelect", "pickFileForm", "pickFolderForm", "settingsForm"):
        state["screen"] = "root"
        render_root("", rev)
    elif scr == "optionsForm":
        state["screen"] = "formatSelect"
        render_format_select(rev)
    elif scr == "result":
        reset_to_root()
    else:
        state["screen"] = "root"
        render_root("", rev)

def reset_to_root():
    state["screen"] = "root"
    state["filePath"] = None
    state["folderPath"] = None
    state["targetFormat"] = None
    state["batch"] = False
    send({"type": "command", "command": "setQuery", "text": ""})
    render_root("", 0)

# --------------------------------------------------------------------- io --

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
            send({"type": "command", "command": "storage", "op": "get",
                  "key": "recents", "requestId": "init_recents"})
            send({"type": "command", "command": "storage", "op": "get",
                  "key": "settings", "requestId": "init_settings"})
            render_root(msg.get("query", ""), msg.get("rev", 0))

        elif t == "query":
            if state["screen"] == "root":
                render_root(msg.get("text", ""), msg.get("rev", 0))

        elif t == "action":
            handle_action(msg.get("id", ""), msg.get("action", "default"))

        elif t == "submit":
            handle_submit(msg.get("values", {}), msg.get("button"))

        elif t == "back":
            handle_back(msg.get("rev", 0))

        elif t == "storage":
            rid, val = msg.get("requestId"), msg.get("value")
            if rid == "init_recents" and val:
                try:
                    state["recents"] = json.loads(val)
                except Exception:
                    pass
            elif rid == "init_settings" and val:
                try:
                    state["settings"].update(json.loads(val))
                except Exception:
                    pass

        elif t == "clipboard":
            if msg.get("requestId") == "clip1":
                send({"type": "command", "command": "setQuery", "text": msg.get("text", "")})

        # select / tab / loadMore: not used by this plugin

if __name__ == "__main__":
    main()
