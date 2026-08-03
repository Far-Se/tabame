#!/usr/bin/env python3
"""Local image background removal for the Tabame launcher.

The plugin deliberately keeps model imports lazy. That lets the root screen
remain useful while Tabame installs rembg's dependencies, and it means model
weights are downloaded only after the user chooses a model.
"""

from __future__ import annotations

import copy
import gc
import json
import os
import re
import sys
import threading
import time
import traceback
from pathlib import Path
from urllib.parse import unquote, urlparse

PLUGIN_DIR = Path(__file__).resolve().parent
MODEL_HOME = PLUGIN_DIR / "models"

SUPPORTED_EXTENSIONS = {
    ".png",
    ".jpg",
    ".jpeg",
    ".webp",
    ".bmp",
    ".tif",
    ".tiff",
}

MODEL_DEFINITIONS = {
    "birefnet": {
        "name": "BiRefNet",
        "session": "birefnet-general",
        "file": "BiRefNet-general-epoch_244.onnx",
        "icon": "brush",
        "license": "MIT",
        "card": "https://huggingface.co/ZhengPeng7/BiRefNet",
        "description": "High-detail, general-purpose foreground segmentation.",
    },
    "bria": {
        "name": "BRIA RMBG 2.0",
        "session": "bria-rmbg",
        "file": "bria-rmbg-2.0.onnx",
        "icon": "shield",
        "license": "CC BY-NC 4.0",
        "card": "https://huggingface.co/briaai/RMBG-2.0",
        "description": "Professional-grade general background removal with a soft alpha matte.",
    },
}

DEFAULT_SETTINGS = {
    "provider": "auto",
    "output_format": "png",
    "output_dir": "",
    "suffix": "_no_bg",
    "bg_mode": "transparent",
    "bg_color": "#FFFFFF",
    "post_process_mask": True,
    "alpha_matting": False,
    "alpha_matting_foreground_threshold": 240,
    "alpha_matting_background_threshold": 10,
    "alpha_matting_erode_size": 10,
    "only_mask": False,
    "save_mask": False,
    "crop_to_subject": False,
    "crop_padding": 0,
    "quality": 95,
    "png_compress": 6,
    "overwrite": False,
}

STATE = {
    "screen": "root",
    "input_path": None,
    "selected_model": "birefnet",
    "settings": copy.deepcopy(DEFAULT_SETTINGS),
    "last_options": None,
    "last_result": None,
    "last_error": "",
    "error_kind": "",
    "busy": False,
    "closing": False,
    "operation_id": 0,
}

OUTPUT_LOCK = threading.Lock()
SESSION_LOCK = threading.Lock()
SESSION = {
    "model_key": None,
    "provider": None,
    "value": None,
}


def log(*values):
    """Write diagnostics to stderr; stdout is reserved for protocol frames."""

    print(*values, file=sys.stderr, flush=True)


def send(frame):
    """Write exactly one flushed JSON protocol frame."""

    with OUTPUT_LOCK:
        if STATE["closing"]:
            return
        sys.stdout.write(
            json.dumps(frame, ensure_ascii=False, separators=(",", ":")) + "\n"
        )
        sys.stdout.flush()


def command(name, **fields):
    payload = {"type": "command", "command": name}
    payload.update(fields)
    send(payload)


def clear_query():
    command("setQuery", text="")


def bool_value(value, default=False):
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return bool(value)


def int_value(value, default, minimum=None, maximum=None):
    try:
        result = int(float(value))
    except (TypeError, ValueError):
        result = default
    if minimum is not None:
        result = max(minimum, result)
    if maximum is not None:
        result = min(maximum, result)
    return result


def normalise_settings(values=None, base=None):
    """Convert form/storage values into a safe, predictable settings object."""

    result = copy.deepcopy(base or DEFAULT_SETTINGS)
    if values:
        for key in result:
            if key in values:
                result[key] = values[key]

    provider = str(result.get("provider", "auto")).strip().lower()
    result["provider"] = provider if provider in {"auto", "cpu", "cuda"} else "auto"

    output_format = str(result.get("output_format", "png")).strip().lower()
    result["output_format"] = (
        output_format if output_format in {"png", "webp", "jpg"} else "png"
    )

    bg_mode = str(result.get("bg_mode", "transparent")).strip().lower()
    result["bg_mode"] = (
        bg_mode
        if bg_mode in {"transparent", "white", "black", "custom"}
        else "transparent"
    )

    result["output_dir"] = str(result.get("output_dir") or "").strip()
    result["suffix"] = str(result.get("suffix") or "_no_bg")
    result["bg_color"] = str(result.get("bg_color") or "#FFFFFF").strip()

    for key in (
        "post_process_mask",
        "alpha_matting",
        "only_mask",
        "save_mask",
        "crop_to_subject",
        "overwrite",
    ):
        result[key] = bool_value(result.get(key), DEFAULT_SETTINGS[key])

    result["alpha_matting_foreground_threshold"] = int_value(
        result.get("alpha_matting_foreground_threshold"), 240, 0, 255
    )
    result["alpha_matting_background_threshold"] = int_value(
        result.get("alpha_matting_background_threshold"), 10, 0, 255
    )
    result["alpha_matting_erode_size"] = int_value(
        result.get("alpha_matting_erode_size"), 10, 0, 64
    )
    result["crop_padding"] = int_value(result.get("crop_padding"), 0, 0, 2048)
    result["quality"] = int_value(result.get("quality"), 95, 1, 100)
    result["png_compress"] = int_value(result.get("png_compress"), 6, 0, 9)
    return result


def save_settings():
    command(
        "storage",
        op="set",
        key="settings",
        value=json.dumps(STATE["settings"], ensure_ascii=False),
    )


def request_settings():
    command("storage", op="get", key="settings", requestId="bgremove-settings")


def parse_stored_settings(value):
    if isinstance(value, dict):
        return value
    if isinstance(value, str) and value.strip():
        try:
            parsed = json.loads(value)
            return parsed if isinstance(parsed, dict) else {}
        except json.JSONDecodeError:
            log("Stored settings are not valid JSON")
    return {}


def human_size(size):
    value = float(max(0, size))
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if value < 1024 or unit == "TB":
            return f"{value:.1f} {unit}"
        value /= 1024
    return f"{value:.1f} TB"


def resolve_path(raw):
    if raw is None:
        return None
    text = str(raw).strip().strip('"').strip("'")
    if not text:
        return None
    if text.lower().startswith("file://"):
        parsed = urlparse(text)
        text = unquote(parsed.path)
        if os.name == "nt" and re.match(r"^/[A-Za-z]:", text):
            text = text[1:]
    text = os.path.expandvars(os.path.expanduser(text))
    try:
        return os.path.abspath(text)
    except (OSError, ValueError):
        return None


def supported_image(path):
    return bool(path) and Path(path).suffix.lower() in SUPPORTED_EXTENSIONS


def image_info(path):
    try:
        from PIL import Image

        with Image.open(path) as image:
            dimensions = f"{image.width}×{image.height}"
            image_format = image.format or Path(path).suffix.upper().lstrip(".")
            mode = image.mode
        return (
            f"{dimensions} · {image_format} · {mode} · "
            f"{human_size(os.path.getsize(path))}"
        )
    except Exception as exc:
        log("Could not inspect image:", exc)
        try:
            return human_size(os.path.getsize(path))
        except OSError:
            return "Image file"


def model_file(key):
    return MODEL_HOME / MODEL_DEFINITIONS[key]["file"]


def model_status(key):
    if SESSION["model_key"] == key and SESSION["value"] is not None:
        return "Ready in memory"
    path = model_file(key)
    if path.exists() and path.stat().st_size > 0:
        return f"Downloaded · {human_size(path.stat().st_size)}"
    return "Downloads automatically on first use"


def model_items():
    items = []
    for key, definition in MODEL_DEFINITIONS.items():
        selected = key == STATE["selected_model"]
        status = model_status(key)
        accessories = []
        if selected:
            accessories.append({"text": "Selected", "color": "#0EA5E9"})
        if status.startswith("Ready"):
            accessories.append({"text": "Ready", "color": "#10B981"})
        elif status.startswith("Downloaded"):
            accessories.append({"text": "Cached", "color": "#8250DF"})
        items.append(
            {
                "id": f"model:{key}",
                "title": definition["name"],
                "subtitle": f"{definition['description']} · {status}",
                "icon": definition["icon"],
                "accessories": accessories,
                "actions": [
                    {
                        "id": "default",
                        "title": f"Use {definition['name']}",
                        "icon": "check",
                    },
                    {
                        "id": "download",
                        "title": "Download / load model",
                        "icon": "download",
                    },
                    {"id": "info", "title": "Model details", "icon": "info"},
                ],
                "preview": {
                    "markdown": (
                        f"## {definition['name']}\n\n"
                        f"{definition['description']}\n\n"
                        f"**Session:** `{definition['session']}`\n\n"
                        f"**License:** `{definition['license']}`\n\n"
                        f"[Open the model card]({definition['card']})"
                    )
                },
            }
        )
    return items


def render_root(rev=0, query=""):
    items = [
        {
            "id": "pick",
            "title": "Choose an image",
            "subtitle": "Open a PNG, JPEG, WebP, BMP or TIFF file",
            "icon": "folder",
            "actions": [{"id": "default", "title": "Choose image", "icon": "file"}],
        }
    ]

    input_path = STATE["input_path"]
    if input_path and os.path.isfile(input_path):
        items.append(
            {
                "id": "input",
                "title": Path(input_path).name,
                "subtitle": image_info(input_path),
                "icon": "image",
                "actions": [
                    {
                        "id": "default",
                        "title": "Choose model and remove background",
                        "icon": "play",
                    },
                    {
                        "id": "change",
                        "title": "Choose another image",
                        "icon": "refresh",
                    },
                    {"id": "copy_path", "title": "Copy image path", "icon": "copy"},
                ],
                "preview": {
                    "markdown": (
                        f"## Ready to process\n\n`{input_path}`\n\n"
                        "Press Enter to choose a model."
                    )
                },
            }
        )
    elif query.strip():
        items.append(
            {
                "id": "path-error",
                "title": "Image path not found",
                "subtitle": "Choose a file or paste a supported image path",
                "icon": "error",
            }
        )

    definition = MODEL_DEFINITIONS[STATE["selected_model"]]
    items.extend(
        [
            {
                "id": "model",
                "title": f"Model: {definition['name']}",
                "subtitle": "Select a model; it downloads automatically when used",
                "icon": definition["icon"],
                "actions": [
                    {"id": "default", "title": "Choose model", "icon": "image"}
                ],
            },
            {
                "id": "settings",
                "title": "Removal settings",
                "subtitle": "Output, alpha matting, mask cleanup and cropping defaults",
                "icon": "settings",
                "actions": [
                    {"id": "default", "title": "Open settings", "icon": "settings"}
                ],
            },
            {
                "id": "help",
                "title": "How it works",
                "subtitle": "Local processing, model downloads and license notes",
                "icon": "help",
            },
        ]
    )

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "selectId": "input"
            if input_path and os.path.isfile(input_path)
            else "pick",
            "placeholder": "Type or paste an image path, or choose an action",
            "emptyText": "Choose an image to begin",
            "preview": {"enabled": True},
            "actions": [
                {"id": "pick", "title": "Choose image", "icon": "file"},
                {"id": "models", "title": "Choose model", "icon": "image"},
                {"id": "settings", "title": "Removal settings", "icon": "settings"},
                {"id": "help", "title": "How it works", "icon": "help"},
            ],
            "items": items,
        }
    )


def render_file_form(rev=0, error=None):
    field = {
        "id": "file",
        "type": "filepicker",
        "label": "Image file",
        "required": True,
        "description": "PNG, JPEG, WebP, BMP or TIFF",
    }
    if STATE["input_path"]:
        field["value"] = STATE["input_path"]
    if error:
        field["error"] = error
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "canGoBack": True,
            "placeholder": "Choose an image file",
            "form": {
                "title": "Choose an image",
                "submitLabel": "Continue",
                "fields": [field],
            },
        }
    )


def render_models(rev=0):
    items = model_items()
    if not STATE["input_path"]:
        items.insert(
            0,
            {
                "id": "choose-image",
                "title": "Choose an image first",
                "subtitle": "You can download a model now, then pick an image afterward",
                "icon": "file",
                "actions": [
                    {"id": "default", "title": "Choose image", "icon": "folder"}
                ],
            },
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "selectId": f"model:{STATE['selected_model']}",
            "placeholder": "Choose BiRefNet or BRIA RMBG 2.0",
            "preview": {"enabled": True},
            "actions": [
                {"id": "pick", "title": "Choose image", "icon": "file"},
                {"id": "settings", "title": "Removal settings", "icon": "settings"},
            ],
            "items": items,
        }
    )


def render_model_info(key):
    definition = MODEL_DEFINITIONS[key]
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "canGoBack": True,
            "detail": {
                "wide": True,
                "markdown": (
                    f"# {definition['name']}\n\n"
                    f"{definition['description']}\n\n"
                    f"The plugin uses rembg's `{definition['session']}` ONNX session. "
                    "The weight file is downloaded automatically on first use and "
                    "kept in the plugin's `models` folder.\n\n"
                    f"**License:** `{definition['license']}`\n\n"
                    f"[Open the model card]({definition['card']})"
                ),
                "metadata": [
                    {
                        "label": "Download status",
                        "text": model_status(key),
                        "icon": "download",
                    },
                    {"label": "Session", "text": definition["session"], "icon": "code"},
                ],
            },
            "actions": [
                {
                    "id": "use_model",
                    "title": f"Use {definition['name']}",
                    "icon": "check",
                },
                {"id": "back_models", "title": "Back to models", "icon": "refresh"},
            ],
        }
    )


def option_fields(settings, error_field=None, error=None):
    def field(definition):
        if definition["id"] == error_field and error:
            definition["error"] = error
        return definition

    return [
        field(
            {
                "id": "provider",
                "type": "dropdown",
                "label": "Execution provider",
                "value": settings["provider"],
                "options": [
                    {"value": "auto", "label": "Auto (recommended)"},
                    {"value": "cpu", "label": "CPU"},
                    {"value": "cuda", "label": "CUDA GPU"},
                ],
                "description": "CUDA requires a compatible onnxruntime-gpu installation.",
            }
        ),
        field(
            {
                "id": "output_format",
                "type": "dropdown",
                "label": "Output format",
                "value": settings["output_format"],
                "options": [
                    {"value": "png", "label": "PNG (best transparency)"},
                    {"value": "webp", "label": "WebP (smaller file)"},
                    {"value": "jpg", "label": "JPEG (requires a solid background)"},
                ],
            }
        ),
        field(
            {
                "id": "output_dir",
                "type": "folderpicker",
                "label": "Output folder",
                "value": settings["output_dir"],
                "description": "Leave empty to save beside the source image.",
            }
        ),
        field(
            {
                "id": "suffix",
                "type": "text",
                "label": "Filename suffix",
                "value": settings["suffix"],
                "placeholder": "_no_bg",
                "description": "Added before the output extension.",
            }
        ),
        field(
            {
                "id": "bg_mode",
                "type": "dropdown",
                "label": "Background",
                "value": settings["bg_mode"],
                "options": [
                    {"value": "transparent", "label": "Transparent"},
                    {"value": "white", "label": "White"},
                    {"value": "black", "label": "Black"},
                    {"value": "custom", "label": "Custom color"},
                ],
                "description": "Transparent is recommended for PNG or WebP.",
            }
        ),
        field(
            {
                "id": "bg_color",
                "type": "text",
                "label": "Custom background color",
                "value": settings["bg_color"],
                "placeholder": "#FFFFFF",
                "description": "Used when Background is Custom; enter #RRGGBB.",
            }
        ),
        field(
            {
                "id": "post_process_mask",
                "type": "checkbox",
                "label": "Smooth and clean the mask",
                "value": settings["post_process_mask"],
                "description": "Applies rembg's mask opening and smoothing pass.",
            }
        ),
        field(
            {
                "id": "alpha_matting",
                "type": "checkbox",
                "label": "Refine edges with alpha matting",
                "value": settings["alpha_matting"],
                "description": "Slower, but can improve hair and semi-transparent edges.",
            }
        ),
        field(
            {
                "id": "alpha_matting_foreground_threshold",
                "type": "number",
                "label": "Matting foreground threshold",
                "value": settings["alpha_matting_foreground_threshold"],
                "min": 0,
                "max": 255,
                "description": "0–255; higher values classify more pixels as foreground.",
            }
        ),
        field(
            {
                "id": "alpha_matting_background_threshold",
                "type": "number",
                "label": "Matting background threshold",
                "value": settings["alpha_matting_background_threshold"],
                "min": 0,
                "max": 255,
                "description": "0–255; lower values keep more uncertain edge pixels.",
            }
        ),
        field(
            {
                "id": "alpha_matting_erode_size",
                "type": "number",
                "label": "Matting erosion size",
                "value": settings["alpha_matting_erode_size"],
                "min": 0,
                "max": 64,
                "description": "Larger values create a wider transition zone around the subject.",
            }
        ),
        field(
            {
                "id": "only_mask",
                "type": "checkbox",
                "label": "Export the mask only",
                "value": settings["only_mask"],
                "description": "Writes a grayscale mask instead of a cutout image.",
            }
        ),
        field(
            {
                "id": "save_mask",
                "type": "checkbox",
                "label": "Save a separate mask",
                "value": settings["save_mask"],
                "description": "Adds a sibling *_mask.png file beside the cutout.",
            }
        ),
        field(
            {
                "id": "crop_to_subject",
                "type": "checkbox",
                "label": "Crop to the detected subject",
                "value": settings["crop_to_subject"],
            }
        ),
        field(
            {
                "id": "crop_padding",
                "type": "number",
                "label": "Crop padding (px)",
                "value": settings["crop_padding"],
                "min": 0,
                "max": 2048,
            }
        ),
        field(
            {
                "id": "quality",
                "type": "number",
                "label": "JPEG / WebP quality",
                "value": settings["quality"],
                "min": 1,
                "max": 100,
            }
        ),
        field(
            {
                "id": "png_compress",
                "type": "number",
                "label": "PNG compression level",
                "value": settings["png_compress"],
                "min": 0,
                "max": 9,
            }
        ),
        field(
            {
                "id": "overwrite",
                "type": "checkbox",
                "label": "Overwrite an existing output",
                "value": settings["overwrite"],
                "description": "Leave off to create a numbered filename instead.",
            }
        ),
    ]


def render_settings_form(rev=0, screen="settings", error_field=None, error=None):
    settings = normalise_settings(STATE["settings"])
    title = "Removal settings" if screen == "settings" else "Remove background"
    submit_label = "Save defaults" if screen == "settings" else "Remove background"
    model_name = MODEL_DEFINITIONS[STATE["selected_model"]]["name"]
    if screen == "options":
        title = f"Remove background with {model_name}"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "canGoBack": True,
            "placeholder": "Adjust background removal settings",
            "form": {
                "title": title,
                "submitLabel": submit_label,
                "fields": option_fields(settings, error_field, error),
            },
        }
    )


def render_help():
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "canGoBack": True,
            "detail": {
                "wide": True,
                "markdown": (
                    "# Background Remover\n\n"
                    "1. Choose an image or paste its path after `bgremove`.\n"
                    "2. Choose **BiRefNet** or **BRIA RMBG 2.0**. The selected "
                    "model downloads automatically on first use.\n"
                    "3. Adjust the output and edge settings, then press **Remove background**.\n\n"
                    "Models run locally through rembg's ONNX backend. The plugin "
                    "does not upload your image.\n\n"
                    "## Model licenses\n\n"
                    "[BiRefNet](https://huggingface.co/ZhengPeng7/BiRefNet) is MIT. "
                    "[BRIA RMBG 2.0](https://huggingface.co/briaai/RMBG-2.0) is "
                    "CC BY-NC 4.0 for non-commercial use. Review the license before "
                    "commercial deployment."
                ),
            },
            "actions": [
                {"id": "back_root", "title": "Back", "icon": "refresh"},
                {"id": "models", "title": "Choose model", "icon": "image"},
            ],
        }
    )


def render_loading(text):
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "list",
            "canGoBack": True,
            "loading": True,
            "loadingText": text,
            "items": [],
        }
    )


def sanitise_markdown_error(error):
    return str(error).replace("```", "'''\n")


def render_error(title, error, kind="process"):
    STATE["screen"] = "error"
    STATE["last_error"] = str(error)
    STATE["error_kind"] = kind
    hint = ""
    lowered = str(error).lower()
    if "onnxruntime" in lowered or "no onnxruntime" in lowered:
        hint = (
            "\n\nInstall or repair the plugin dependencies, then reopen the launcher."
        )
    elif "cuda" in lowered:
        hint = "\n\nChoose Auto or CPU, or install a compatible onnxruntime-gpu build."
    elif "permission" in lowered or "access is denied" in lowered:
        hint = "\n\nCheck that the source and output folders are writable."
    elif "model" in lowered or "download" in lowered:
        hint = "\n\nCheck the network connection and try the model again."
    markdown = f"# {title}\n\n```text\n{sanitise_markdown_error(error)}\n```{hint}"
    actions = [{"id": "back_root", "title": "Back to start", "icon": "home"}]
    if kind == "model":
        actions.insert(
            0, {"id": "retry_model", "title": "Try model again", "icon": "refresh"}
        )
        actions.insert(
            1, {"id": "models", "title": "Choose another model", "icon": "image"}
        )
    elif kind == "process":
        actions.insert(
            0, {"id": "retry_process", "title": "Try again", "icon": "refresh"}
        )
        actions.insert(
            1, {"id": "settings", "title": "Change settings", "icon": "settings"}
        )
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "canGoBack": True,
            "detail": {"wide": True, "markdown": markdown},
            "actions": actions,
        }
    )


def parse_color(value):
    text = str(value or "").strip()
    match = re.fullmatch(r"#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?", text)
    if not match:
        raise ValueError("Use a background color in #RRGGBB format.")
    rgb = match.group(1)
    alpha = int(match.group(2), 16) if match.group(2) else 255
    return (int(rgb[0:2], 16), int(rgb[2:4], 16), int(rgb[4:6], 16), alpha)


def background_color(settings):
    mode = settings["bg_mode"]
    if mode == "transparent":
        return None
    if mode == "white":
        return (255, 255, 255, 255)
    if mode == "black":
        return (0, 0, 0, 255)
    return parse_color(settings["bg_color"])


def validate_settings(settings):
    if settings["only_mask"] and settings["output_format"] == "jpg":
        return "output_format", "A mask cannot be exported as JPEG; choose PNG or WebP."
    if (
        not settings["only_mask"]
        and settings["output_format"] == "jpg"
        and settings["bg_mode"] == "transparent"
    ):
        return (
            "bg_mode",
            "JPEG needs a solid background; choose White, Black or Custom.",
        )
    if settings["bg_mode"] == "custom":
        try:
            parse_color(settings["bg_color"])
        except ValueError as exc:
            return "bg_color", str(exc)
    output_dir = resolve_path(settings["output_dir"])
    if output_dir and os.path.exists(output_dir) and not os.path.isdir(output_dir):
        return "output_dir", "The output path is a file, not a folder."
    return None


def safe_suffix(value):
    suffix = str(value or "_no_bg")
    suffix = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", suffix).strip()
    return suffix or "_no_bg"


def unique_path(path):
    path = Path(path)
    if not path.exists():
        return path
    for index in range(1, 10000):
        candidate = path.with_name(f"{path.stem}_{index}{path.suffix}")
        if not candidate.exists():
            return candidate
    raise RuntimeError(f"Could not find a free filename for {path.name}")


def output_path_for(source_path, settings):
    source = Path(source_path)
    output_dir = resolve_path(settings["output_dir"])
    directory = Path(output_dir) if output_dir else source.parent
    extension = {"png": ".png", "webp": ".webp", "jpg": ".jpg"}[
        settings["output_format"]
    ]
    candidate = directory / f"{source.stem}{safe_suffix(settings['suffix'])}{extension}"
    if not settings["overwrite"]:
        return unique_path(candidate)
    return candidate


def configure_model_home():
    MODEL_HOME.mkdir(parents=True, exist_ok=True)
    # rembg reads U2NET_HOME when its session modules are imported. It is set
    # immediately before the first lazy import so models stay with this plugin.
    os.environ["U2NET_HOME"] = str(MODEL_HOME)


def provider_argument(mode):
    if mode == "auto":
        return None
    import onnxruntime as ort

    available = list(ort.get_available_providers())
    if mode == "cuda":
        if "CUDAExecutionProvider" not in available:
            raise RuntimeError(
                "CUDAExecutionProvider is unavailable. Install a compatible "
                "onnxruntime-gpu build or choose Auto / CPU."
            )
        providers = ["CUDAExecutionProvider"]
        if "CPUExecutionProvider" in available:
            providers.append("CPUExecutionProvider")
        return providers
    if "CPUExecutionProvider" not in available:
        raise RuntimeError("CPUExecutionProvider is unavailable in onnxruntime.")
    return ["CPUExecutionProvider"]


def session_providers(session):
    inner = getattr(session, "inner_session", None)
    getter = getattr(inner, "get_providers", None)
    if callable(getter):
        try:
            return getter()
        except Exception:
            pass
    return []


def ensure_session(model_key, settings):
    provider = settings.get("provider", "auto")
    with SESSION_LOCK:
        if (
            SESSION["value"] is not None
            and SESSION["model_key"] == model_key
            and SESSION["provider"] == provider
        ):
            return SESSION["value"]

        configure_model_home()
        import onnxruntime as ort
        from rembg import new_session

        # Diagnostics: was the weight file already on disk, or does this
        # call have to download it? A first-time BiRefNet/BRIA download is
        # ~900MB-1GB and is network-bound, so CPU legitimately sits idle
        # during that phase - it is not something thread tuning can fix.
        target = model_file(model_key)
        pre_exists = target.exists()
        pre_size = target.stat().st_size if pre_exists else 0
        log(
            f"[ensure_session] model={model_key} provider={provider} "
            f"file_present_before={pre_exists} size_before={human_size(pre_size)}"
        )

        # Explicit thread config: leaving these at 0 lets onnxruntime guess,
        # which is usually fine, but pinning intra-op threads to the core
        # count guarantees CPUExecutionProvider actually fans out across
        # every core during inference instead of relying on autodetection.
        sess_opts = ort.SessionOptions()
        sess_opts.intra_op_num_threads = os.cpu_count() or 4
        sess_opts.inter_op_num_threads = 1
        sess_opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL

        providers = provider_argument(provider)
        started = time.perf_counter()
        if providers is None:
            loaded = new_session(
                MODEL_DEFINITIONS[model_key]["session"], sess_opts=sess_opts
            )
        else:
            loaded = new_session(
                MODEL_DEFINITIONS[model_key]["session"],
                sess_opts=sess_opts,
                providers=providers,
            )
        elapsed = time.perf_counter() - started

        post_size = target.stat().st_size if target.exists() else 0
        downloaded = not pre_exists or pre_size != post_size
        log(
            f"[ensure_session] done in {elapsed:.1f}s "
            f"(weights_downloaded_this_call={downloaded}, "
            f"final_size={human_size(post_size)})"
        )
        if downloaded and elapsed > 20:
            log(
                "[ensure_session] most of that time was almost certainly the "
                "network download, not CPU work - low CPU usage during it is expected."
            )
        elif not downloaded and elapsed > 20:
            log(
                "[ensure_session] weights were already cached on disk but the "
                "session still took a while to build - check for antivirus "
                "real-time scanning on the models/ folder, slow disk I/O, or "
                "try excluding the plugin's models directory from Defender."
            )

        old = SESSION["value"]
        SESSION["model_key"] = model_key
        SESSION["provider"] = provider
        SESSION["value"] = loaded
        if old is not None:
            del old
            gc.collect()
        return loaded


def output_image(image, destination, settings, background):
    from PIL import Image

    destination.parent.mkdir(parents=True, exist_ok=True)
    output_format = settings["output_format"]
    save_image = image
    if output_format == "jpg":
        if save_image.mode == "RGBA":
            color = background[:3] if background else (255, 255, 255)
            flattened = Image.new("RGB", save_image.size, color)
            flattened.paste(save_image, mask=save_image.getchannel("A"))
            save_image = flattened
        else:
            save_image = save_image.convert("RGB")
        save_image.save(
            destination,
            format="JPEG",
            quality=settings["quality"],
            optimize=True,
        )
    elif output_format == "webp":
        save_image.save(
            destination,
            format="WEBP",
            quality=settings["quality"],
            method=6,
        )
    else:
        save_image.save(
            destination,
            format="PNG",
            compress_level=settings["png_compress"],
        )


def crop_image(image, settings):
    if not settings["crop_to_subject"]:
        return image, None
    from PIL import Image

    if image.mode in {"RGBA", "LA"} or "A" in image.getbands():
        alpha = image.getchannel("A")
    elif image.mode == "L":
        alpha = image
    else:
        return image, None
    bbox = alpha.point(lambda value: 255 if value > 8 else 0).getbbox()
    if not bbox:
        return image, None
    padding = settings["crop_padding"]
    left = max(0, bbox[0] - padding)
    top = max(0, bbox[1] - padding)
    right = min(image.width, bbox[2] + padding)
    bottom = min(image.height, bbox[3] + padding)
    cropped = image.crop((left, top, right, bottom))
    return cropped, (left, top, right, bottom)


def process_image(source_path, model_key, settings):
    from io import BytesIO

    from PIL import Image, ImageOps

    configure_model_home()
    from rembg import remove

    session = ensure_session(model_key, settings)
    background = background_color(settings)
    destination = output_path_for(source_path, settings)

    with Image.open(source_path) as opened:
        source = ImageOps.exif_transpose(opened).convert("RGB")
        remove_options = {
            "alpha_matting": settings["alpha_matting"],
            "alpha_matting_foreground_threshold": settings[
                "alpha_matting_foreground_threshold"
            ],
            "alpha_matting_background_threshold": settings[
                "alpha_matting_background_threshold"
            ],
            "alpha_matting_erode_size": settings["alpha_matting_erode_size"],
            "post_process_mask": settings["post_process_mask"],
            "only_mask": settings["only_mask"],
            "session": session,
        }
        if background is not None and not settings["only_mask"]:
            remove_options["bgcolor"] = background

        result = remove(source, **remove_options)
        if not isinstance(result, Image.Image):
            result = Image.open(BytesIO(result)).copy()
        else:
            result = result.copy()

        saved_mask = None
        if settings["save_mask"] and not settings["only_mask"]:
            if background is None and "A" in result.getbands():
                saved_mask = result.getchannel("A")
            else:
                mask_options = dict(remove_options)
                mask_options.pop("bgcolor", None)
                mask_options["only_mask"] = True
                mask = remove(source, **mask_options)
                if isinstance(mask, Image.Image):
                    saved_mask = mask.convert("L")
                else:
                    saved_mask = Image.open(BytesIO(mask)).convert("L")

        result, crop_box = crop_image(result, settings)
        if saved_mask is not None and crop_box is not None:
            saved_mask = saved_mask.crop(crop_box)

        output_image(result, destination, settings, background)

        mask_destination = None
        if saved_mask is not None:
            mask_destination = destination.with_name(f"{destination.stem}_mask.png")
            if not settings["overwrite"]:
                mask_destination = unique_path(mask_destination)
            mask_destination.parent.mkdir(parents=True, exist_ok=True)
            saved_mask.save(mask_destination, format="PNG", compress_level=6)

        actual_providers = session_providers(session)
        provider_text = (
            ", ".join(actual_providers) if actual_providers else settings["provider"]
        )
        return {
            "source": str(source_path),
            "output": str(destination),
            "mask": str(mask_destination) if mask_destination else None,
            "model_key": model_key,
            "provider": provider_text,
            "source_size": source.size,
            "output_size": result.size,
            "source_bytes": os.path.getsize(source_path),
            "output_bytes": destination.stat().st_size,
            "only_mask": settings["only_mask"],
        }


def next_operation():
    STATE["operation_id"] += 1
    return STATE["operation_id"]


def operation_is_current(operation_id):
    return not STATE["closing"] and STATE["operation_id"] == operation_id


def start_model_load(model_key):
    if STATE["busy"]:
        command("toast", text="Another operation is already running", style="info")
        return
    if model_key not in MODEL_DEFINITIONS:
        return
    STATE["selected_model"] = model_key
    STATE["settings"]["model"] = model_key
    STATE["screen"] = "model_loading"
    STATE["busy"] = True
    operation_id = next_operation()
    definition = MODEL_DEFINITIONS[model_key]
    render_loading(f"Loading {definition['name']} — downloading the model if needed…")
    settings = copy.deepcopy(STATE["settings"])

    def worker():
        try:
            ensure_session(model_key, settings)
            if not operation_is_current(operation_id):
                return
            STATE["busy"] = False
            if STATE["input_path"]:
                STATE["screen"] = "options"
                clear_query()
                render_settings_form(0, screen="options")
            else:
                STATE["screen"] = "root"
                clear_query()
                command("toast", text=f"{definition['name']} is ready")
                render_root(0, "")
        except Exception as exc:
            log("Model load failed:\n" + traceback.format_exc())
            if operation_is_current(operation_id):
                STATE["busy"] = False
                render_error(f"Could not load {definition['name']}", exc, kind="model")

    threading.Thread(target=worker, name="bgremove-model", daemon=True).start()


def start_processing(settings):
    source_path = STATE["input_path"]
    model_key = STATE["selected_model"]
    if not source_path or not os.path.isfile(source_path):
        render_error(
            "No image selected", "Choose an image before removing its background."
        )
        return

    STATE["settings"] = normalise_settings(settings)
    STATE["settings"]["model"] = model_key
    STATE["last_options"] = copy.deepcopy(STATE["settings"])
    save_settings()
    STATE["screen"] = "processing"
    STATE["busy"] = True
    operation_id = next_operation()
    definition = MODEL_DEFINITIONS[model_key]
    render_loading(f"Running {definition['name']} — removing the background…")
    options = copy.deepcopy(STATE["settings"])

    def worker():
        try:
            result = process_image(source_path, model_key, options)
            if not operation_is_current(operation_id):
                return
            STATE["busy"] = False
            STATE["last_result"] = result
            STATE["screen"] = "result"
            render_result(result)
        except Exception as exc:
            log("Background removal failed:\n" + traceback.format_exc())
            if operation_is_current(operation_id):
                STATE["busy"] = False
                render_error("Background removal failed", exc, kind="process")

    threading.Thread(target=worker, name="bgremove-process", daemon=True).start()


def render_result(result):
    definition = MODEL_DEFINITIONS[result["model_key"]]
    source_width, source_height = result["source_size"]
    output_width, output_height = result["output_size"]
    output_label = "mask" if result["only_mask"] else "cutout"
    mask_path = result.get("mask")
    metadata = [
        {"label": "Model", "text": definition["name"], "icon": definition["icon"]},
        {"label": "Provider", "text": result["provider"], "icon": "bolt"},
        {
            "label": "Dimensions",
            "text": f"{source_width}×{source_height} → {output_width}×{output_height}",
            "icon": "image",
        },
        {
            "label": "Output size",
            "text": human_size(result["output_bytes"]),
            "icon": "download",
        },
        {"label": "Output path", "text": result["output"], "icon": "file"},
    ]
    if mask_path:
        metadata.append({"label": "Mask path", "text": mask_path, "icon": "image"})
    actions = [
        {"id": "open_file", "title": "Open output", "icon": "open"},
        {"id": "open_folder", "title": "Reveal in folder", "icon": "folder"},
        {"id": "copy_path", "title": "Copy output path", "icon": "copy"},
    ]
    if mask_path:
        actions.append({"id": "open_mask", "title": "Open saved mask", "icon": "image"})
    actions.extend(
        [
            {"id": "another", "title": "Remove another image", "icon": "refresh"},
            {"id": "settings", "title": "Change defaults", "icon": "settings"},
        ]
    )
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "canGoBack": True,
            "detail": {
                "wide": True,
                "markdown": (
                    f"# Background removed\n\n"
                    f"Created a **{output_label}** from `{Path(result['source']).name}`.\n\n"
                    f"Output: `{Path(result['output']).name}`"
                ),
                "metadata": metadata,
            },
            "actions": actions,
        }
    )


def open_file_form():
    STATE["screen"] = "file"
    clear_query()
    render_file_form(0)


def open_models():
    STATE["screen"] = "models"
    clear_query()
    render_models(0)


def open_settings():
    STATE["screen"] = "settings"
    clear_query()
    render_settings_form(0, screen="settings")


def open_root():
    STATE["screen"] = "root"
    STATE["busy"] = False
    clear_query()
    render_root(0, "")


def handle_root_action(item_id, action):
    if item_id in {"pick", "path-error"} or action == "pick":
        open_file_form()
        return
    if item_id == "input":
        if action == "copy_path":
            command("copy", text=STATE["input_path"] or "")
        elif action == "change":
            open_file_form()
        else:
            open_models()
        return
    if item_id == "model" or action == "models":
        open_models()
        return
    if item_id == "settings" or action == "settings":
        open_settings()
        return
    if item_id == "help" or action == "help":
        STATE["screen"] = "help"
        clear_query()
        render_help()


def handle_model_action(item_id, action):
    if item_id == "choose-image":
        open_file_form()
        return
    if item_id.startswith("model:"):
        key = item_id.split(":", 1)[1]
        if key not in MODEL_DEFINITIONS:
            return
        if action == "info":
            STATE["screen"] = "model_info"
            STATE["info_model"] = key
            clear_query()
            render_model_info(key)
        else:
            start_model_load(key)


def handle_result_action(action):
    result = STATE["last_result"]
    if not result:
        return
    if action == "open_file":
        command("open", path=result["output"])
    elif action == "open_folder":
        command("open", path=str(Path(result["output"]).parent))
    elif action == "copy_path":
        command("copy", text=result["output"])
        command("toast", text="Output path copied")
    elif action == "open_mask" and result.get("mask"):
        command("open", path=result["mask"])
    elif action == "another":
        STATE["input_path"] = None
        open_file_form()
    elif action == "settings":
        open_settings()


def handle_error_action(action):
    kind = STATE["error_kind"]
    if action == "retry_model" and kind == "model":
        start_model_load(STATE["selected_model"])
    elif action == "retry_process" and kind == "process" and STATE["last_options"]:
        start_processing(STATE["last_options"])
    elif action == "models":
        open_models()
    elif action == "settings":
        open_settings()
    elif action == "back_root":
        open_root()


def handle_action(item_id, action):
    if item_id == "":
        screen = STATE["screen"]
        if screen == "root":
            handle_root_action("", action)
        elif screen == "models":
            if action == "pick":
                open_file_form()
            elif action == "settings":
                open_settings()
        elif screen == "model_info":
            if action == "use_model":
                start_model_load(STATE.get("info_model", STATE["selected_model"]))
            elif action == "back_models":
                open_models()
        elif screen == "result":
            handle_result_action(action)
        elif screen == "error":
            handle_error_action(action)
        elif screen == "help":
            if action == "models":
                open_models()
            elif action == "back_root":
                open_root()
        return

    screen = STATE["screen"]
    if screen == "root":
        handle_root_action(item_id, action)
    elif screen == "models":
        handle_model_action(item_id, action)
    elif screen == "model_info":
        if action == "use_model":
            start_model_load(item_id)
    elif screen == "result":
        handle_result_action(action)
    elif screen == "error":
        handle_error_action(action)


def handle_file_submit(values):
    path = resolve_path(values.get("file"))
    if not path or not os.path.isfile(path):
        render_file_form(0, "Choose an existing image file.")
        return
    if not supported_image(path):
        render_file_form(0, "This file type is not supported by the plugin.")
        return
    STATE["input_path"] = path
    STATE["last_result"] = None
    STATE["last_error"] = ""
    STATE["screen"] = "models"
    clear_query()
    render_models(0)


def handle_form_submit(values):
    screen = STATE["screen"]
    if screen == "file":
        handle_file_submit(values)
        return
    if screen not in {"settings", "options"}:
        return

    settings = normalise_settings(values, STATE["settings"])
    validation = validate_settings(settings)
    if validation:
        render_settings_form(
            0, screen=screen, error_field=validation[0], error=validation[1]
        )
        return

    STATE["settings"] = settings
    save_settings()
    if screen == "settings":
        command("toast", text="Removal settings saved")
        open_root()
    else:
        start_processing(settings)


def handle_back():
    # Invalidate a worker that has not finished. The native model session may
    # still finish loading, but its result will be ignored by operation_id.
    if STATE["busy"]:
        next_operation()
        STATE["busy"] = False
    screen = STATE["screen"]
    if screen in {
        "file",
        "models",
        "model_info",
        "settings",
        "help",
        "result",
        "error",
    }:
        open_root()
    elif screen == "options":
        open_models()
    elif screen in {"model_loading", "processing"}:
        open_root()
    else:
        open_root()


def handle_query(text, rev):
    if STATE["screen"] != "root":
        return
    text = str(text or "")
    if text.strip():
        candidate = resolve_path(text)
        if candidate and os.path.isfile(candidate) and supported_image(candidate):
            STATE["input_path"] = candidate
    render_root(rev, text)


def handle_storage(message):
    if message.get("requestId") != "bgremove-settings":
        return
    stored = parse_stored_settings(message.get("value"))
    if stored:
        STATE["settings"] = normalise_settings(stored)
        selected = stored.get("model")
        if selected in MODEL_DEFINITIONS:
            STATE["selected_model"] = selected
    if STATE["screen"] == "root":
        render_root(0, "")


def main():
    request_settings()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            log("Ignoring invalid JSON input:", line[:200])
            continue

        message_type = message.get("type")
        if message_type == "close":
            STATE["closing"] = True
            next_operation()
            break
        try:
            if message_type == "init":
                handle_query(message.get("query", ""), message.get("rev", 0))
            elif message_type == "query":
                handle_query(message.get("text", ""), message.get("rev", 0))
            elif message_type == "action":
                handle_action(message.get("id", ""), message.get("action", "default"))
            elif message_type == "submit":
                handle_form_submit(message.get("values", {}))
            elif message_type == "back":
                handle_back()
            elif message_type == "storage":
                handle_storage(message)
            # select, tab, and other optional host messages are not needed.
        except Exception as exc:
            log("Unhandled plugin error:\n" + traceback.format_exc())
            if not STATE["closing"]:
                render_error("Plugin error", exc, kind="process")


if __name__ == "__main__":
    main()
