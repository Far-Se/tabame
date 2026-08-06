#!/usr/bin/env python3
"""
Tabame launcher plugin: Image Resizer
Keyword: resize

Root screen is a form. User picks either individual image file(s) or a
folder (bulk mode), a target width/height, whether to keep aspect ratio,
an optional custom output name (only used when a single image is being
resized), and an optional output folder.

Default output name when no custom name is given:
    <original_stem>_<width>x<height><ext>
"""

import json
import os
import re
import sys
import threading

from PIL import Image

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".bmp", ".gif", ".webp", ".tiff", ".tif"}

state = {"lastOutDir": None}


def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


FORM = {
    "title": "Resize Images",
    "submitLabel": "Resize",
    "fields": [
        {
            "id": "files",
            "type": "filepicker",
            "label": "Image file(s)",
            "description": "Pick one or more images. Leave empty if using a folder below.",
        },
        {
            "id": "folder",
            "type": "folderpicker",
            "label": "Or: folder of images (bulk)",
            "description": "Every image inside gets resized.",
        },
        {
            "id": "width",
            "type": "number",
            "label": "Width (px)",
            "required": True,
            "min": 1,
        },
        {
            "id": "height",
            "type": "number",
            "label": "Height (px)",
            "description": "Leave empty to auto-calculate from each image's aspect ratio.",
            "min": 1,
        },
        {
            "id": "keepAspect",
            "type": "checkbox",
            "label": "Keep aspect ratio (fit within box, don't stretch)",
            "description": "Only used when both width and height are given.",
            "value": True,
        },
        {
            "id": "customName",
            "type": "text",
            "label": "Custom output name (single file only)",
            "placeholder": "leave empty for auto name (name_WxH.ext)",
        },
        {
            "id": "outFolder",
            "type": "folderpicker",
            "label": "Save to folder (optional)",
            "description": "Default: same folder as each source image.",
        },
    ],
}


def render_form(rev):
    send({"type": "render", "rev": rev, "view": "form", "form": FORM})


def render_error(msg):
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "detail": {"markdown": f"# Couldn't resize\n\n{msg}"},
            "actions": [{"id": "again", "title": "Back to form", "icon": "refresh"}],
        }
    )


def split_paths(value):
    if not value:
        return []
    parts = re.split(r"[\n;]+", value)
    return [p.strip().strip('"') for p in parts if p.strip()]


def collect_images(files_value, folder_value):
    paths = split_paths(files_value)

    folder_value = (folder_value or "").strip().strip('"')
    if folder_value and os.path.isdir(folder_value):
        for name in sorted(os.listdir(folder_value)):
            ext = os.path.splitext(name)[1].lower()
            if ext in IMAGE_EXTS:
                paths.append(os.path.join(folder_value, name))

    seen = set()
    result = []
    for p in paths:
        if p in seen:
            continue
        seen.add(p)
        if os.path.isfile(p) and os.path.splitext(p)[1].lower() in IMAGE_EXTS:
            result.append(p)
    return result


def build_output_path(src, width, height, out_folder, custom_name, is_single):
    src_dir, base = os.path.split(src)
    stem, ext = os.path.splitext(base)
    target_dir = out_folder if out_folder and os.path.isdir(out_folder) else src_dir

    if is_single and custom_name:
        name = custom_name.strip()
        if not os.path.splitext(name)[1]:
            name += ext
        return os.path.join(target_dir, name)

    return os.path.join(target_dir, f"{stem}_{width}x{height}{ext}")


def resize_one(src, width, height, keep_aspect, out_folder, custom_name, is_single):
    with Image.open(src) as im:
        orig_w, orig_h = im.size

        if height is None:
            # Auto height: preserve this image's own aspect ratio from width alone.
            effective_height = max(1, round(width * orig_h / orig_w))
        else:
            effective_height = height

        out_path = build_output_path(
            src, width, effective_height, out_folder, custom_name, is_single
        )

        img = im.convert(im.mode)
        if height is None:
            # Aspect ratio is already exact, no need to fit/crop.
            img = img.resize((width, effective_height), Image.LANCZOS)
        elif keep_aspect:
            img.thumbnail((width, effective_height), Image.LANCZOS)
        else:
            img = img.resize((width, effective_height), Image.LANCZOS)

        if out_path.lower().endswith((".jpg", ".jpeg")) and img.mode in (
            "RGBA",
            "P",
            "LA",
        ):
            img = img.convert("RGB")

        os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
        img.save(out_path)

    return out_path


def handle_submit(values):
    files_value = values.get("files") or ""
    folder_value = values.get("folder") or ""
    width = values.get("width")
    height = values.get("height")
    keep_aspect = bool(values.get("keepAspect"))
    custom_name = (values.get("customName") or "").strip()
    out_folder = (values.get("outFolder") or "").strip()

    if not width:
        render_error("Please provide a width.")
        return

    height = height if height else None

    images = collect_images(files_value, folder_value)
    if not images:
        render_error(
            "No valid image files found. Pick file(s), or a folder that "
            "contains images (png, jpg, bmp, gif, webp, tiff)."
        )
        return

    is_single = len(images) == 1

    def work():
        send(
            {
                "type": "command",
                "command": "toast",
                "text": f"Resizing {len(images)} image(s)…",
                "style": "progress",
            }
        )

        results = []
        for src in images:
            try:
                out = resize_one(
                    src,
                    int(width),
                    int(height) if height is not None else None,
                    keep_aspect,
                    out_folder,
                    custom_name,
                    is_single,
                )
                results.append((src, out, None))
            except Exception as e:
                log("resize failed for", src, ":", e)
                results.append((src, None, str(e)))

        ok = [r for r in results if r[2] is None]
        failed = [r for r in results if r[2] is not None]

        lines = [
            "# Resize complete",
            "",
            f"**{len(ok)}** succeeded, **{len(failed)}** failed.",
            "",
        ]
        for src, out, err in results:
            if err:
                lines.append(f"- ❌ `{os.path.basename(src)}` — {err}")
            else:
                lines.append(
                    f"- ✅ `{os.path.basename(src)}` → `{os.path.basename(out)}`"
                )

        send(
            {
                "type": "command",
                "command": "toast",
                "text": f"Done — {len(ok)} resized"
                + (f", {len(failed)} failed" if failed else ""),
                "style": "success" if not failed else "error",
            }
        )

        actions = [{"id": "again", "title": "Resize more", "icon": "refresh"}]
        if ok:
            actions.insert(
                0, {"id": "openFolder", "title": "Open output folder", "icon": "folder"}
            )
            state["lastOutDir"] = os.path.dirname(ok[0][1])

        send(
            {
                "type": "render",
                "rev": 0,
                "view": "detail",
                "detail": {"markdown": "\n".join(lines)},
                "actions": actions,
            }
        )

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
            render_form(msg.get("rev", 0))
        elif t == "submit":
            handle_submit(msg.get("values", {}))
        elif t == "action":
            action = msg.get("action")
            if action == "again":
                render_form(0)
            elif action == "openFolder" and state.get("lastOutDir"):
                send(
                    {"type": "command", "command": "open", "path": state["lastOutDir"]}
                )


if __name__ == "__main__":
    main()
