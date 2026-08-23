#!/usr/bin/env python3
"""Windows screen-clip reverse image search for the Tabame launcher.

The plugin follows Tabame's newline-delimited JSON protocol. It deliberately
keeps the capture step local: Windows' ms-screenclip URI writes the selected
area to the image clipboard, and Pillow converts that clipboard bitmap to a
temporary PNG for the selected search engine.
"""

import base64
import ctypes
import hashlib
import io
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import threading
import time
from typing import Any, Dict, Iterable, List, Optional, Tuple
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen
import uuid


try:
    from PIL import Image, ImageGrab

    PIL_AVAILABLE = True
except ImportError:
    Image = None  # type: ignore
    ImageGrab = None  # type: ignore
    PIL_AVAILABLE = False


USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/144.0.0.0 Safari/537.36"
)
SCREENCLIP_URI = "ms-screenclip:"
PLUGIN_DIR = Path.cwd()
CAPTURE_DIR = Path(tempfile.gettempdir()) / "tabame-search-by-image"
MAX_HTTP_RESPONSE = 2 * 1024 * 1024
SEND_LOCK = threading.Lock()
STATE_LOCK = threading.Lock()
STOP_EVENT = threading.Event()

STATE: Dict[str, Any] = {
    "page": "home",
    "page_history": "none",
    "capture_path": None,
    "capture_info": None,
    "busy": False,
    "busy_kind": "",
    "busy_label": "",
    "last_result_url": None,
    "last_result_urls": [],
    "last_engine": None,
}


# The ids and landing pages mirror the reference extension's engine registry.
# "auto" means that the reference source exposes a direct HTTP upload flow
# which this standalone plugin can reproduce without browser DOM access.
ENGINE_CATALOG: List[Dict[str, Any]] = [
    {
        "id": "googleLens",
        "name": "Google Lens",
        "category": "General",
        "url": "https://lens.google.com/",
        "mode": "manual",
    },
    {
        "id": "bing",
        "name": "Bing Visual Search",
        "category": "General",
        "url": "https://www.bing.com/images",
        "mode": "auto",
    },
    {
        "id": "yandex",
        "name": "Yandex Images",
        "category": "General",
        "url": "https://yandex.com/images/",
        "mode": "auto",
    },
    {
        "id": "googleImages",
        "name": "Google Images (legacy)",
        "category": "General",
        "url": "https://www.google.com/images",
        "mode": "auto",
    },
    {
        "id": "tineye",
        "name": "TinEye",
        "category": "General",
        "url": "https://www.tineye.com/",
        "mode": "manual",
    },
    {
        "id": "saucenao",
        "name": "SauceNAO",
        "category": "Anime & Art",
        "url": "https://saucenao.com/",
        "mode": "manual",
    },
    {
        "id": "iqdb",
        "name": "IQDB",
        "category": "Anime & Art",
        "url": "https://iqdb.org/",
        "mode": "manual",
    },
    {
        "id": "ascii2d",
        "name": "Ascii2D",
        "category": "Anime & Art",
        "url": "https://ascii2d.net/",
        "mode": "manual",
    },
    {
        "id": "whatanime",
        "name": "WhatAnime / trace.moe",
        "category": "Anime & Art",
        "url": "https://trace.moe/",
        "mode": "manual",
    },
    {
        "id": "pinterest",
        "name": "Pinterest visual search",
        "category": "Visual discovery",
        "url": "https://www.pinterest.com/",
        "mode": "auto",
    },
    {
        "id": "lenso",
        "name": "Lenso.ai",
        "category": "Visual discovery",
        "url": "https://lenso.ai/en/",
        "mode": "manual",
    },
    {
        "id": "kagi",
        "name": "Kagi Images",
        "category": "Visual discovery",
        "url": "https://kagi.com/images",
        "mode": "manual",
    },
    {
        "id": "baidu",
        "name": "Baidu Image Search",
        "category": "Regional",
        "url": "https://graph.baidu.com/pcpage/index?tpl_from=pc",
        "mode": "manual",
    },
    {
        "id": "sogou",
        "name": "Sogou Images",
        "category": "Regional",
        "url": "https://pic.sogou.com/",
        "mode": "manual",
    },
    {
        "id": "qihoo",
        "name": "Qihoo 360 Images",
        "category": "Regional",
        "url": "https://st.so.com/",
        "mode": "manual",
    },
    {
        "id": "taobao",
        "name": "Taobao visual search",
        "category": "Shopping",
        "url": "https://www.taobao.com/",
        "mode": "manual",
    },
    {
        "id": "alibabaChina",
        "name": "Alibaba 1688",
        "category": "Shopping",
        "url": "https://www.1688.com/",
        "mode": "manual",
    },
    {
        "id": "pimeyes",
        "name": "PimEyes",
        "category": "People & identity",
        "url": "https://pimeyes.com/en",
        "mode": "manual",
    },
    {
        "id": "lexica",
        "name": "Lexica",
        "category": "AI & design",
        "url": "https://lexica.art/",
        "mode": "manual",
    },
    {
        "id": "freepik",
        "name": "Freepik",
        "category": "Stock & design",
        "url": "https://www.freepik.com/search",
        "mode": "manual",
    },
    {
        "id": "icons8",
        "name": "Icons8",
        "category": "Stock & design",
        "url": "https://icons8.com/",
        "mode": "manual",
    },
    {
        "id": "unsplash",
        "name": "Unsplash visual search",
        "category": "Stock & design",
        "url": "https://unsplash.com/",
        "mode": "auto",
    },
    {
        "id": "getty",
        "name": "Getty Images",
        "category": "Stock & design",
        "url": "https://www.gettyimages.com/",
        "mode": "manual",
    },
    {
        "id": "istock",
        "name": "iStock",
        "category": "Stock & design",
        "url": "https://www.istockphoto.com/",
        "mode": "manual",
    },
    {
        "id": "shutterstock",
        "name": "Shutterstock",
        "category": "Stock & design",
        "url": "https://www.shutterstock.com/images",
        "mode": "manual",
    },
    {
        "id": "adobestock",
        "name": "Adobe Stock",
        "category": "Stock & design",
        "url": "https://stock.adobe.com/",
        "mode": "manual",
    },
    {
        "id": "depositphotos",
        "name": "Depositphotos",
        "category": "Stock & design",
        "url": "https://depositphotos.com/search/",
        "mode": "manual",
    },
    {
        "id": "dreamstime",
        "name": "Dreamstime",
        "category": "Stock & design",
        "url": "https://www.dreamstime.com/",
        "mode": "manual",
    },
    {
        "id": "alamy",
        "name": "Alamy",
        "category": "Stock & design",
        "url": "https://www.alamy.com/",
        "mode": "manual",
    },
    {
        "id": "123rf",
        "name": "123RF",
        "category": "Stock & design",
        "url": "https://www.123rf.com/",
        "mode": "manual",
    },
    {
        "id": "esearch",
        "name": "EUIPO eSearch",
        "category": "Trademark & design",
        "url": "https://euipo.europa.eu/eSearch/",
        "mode": "manual",
    },
    {
        "id": "tmview",
        "name": "TMview",
        "category": "Trademark & design",
        "url": "https://www.tmdn.org/tmview/#/tmview",
        "mode": "manual",
    },
    {
        "id": "branddb",
        "name": "WIPO Global Brand Database",
        "category": "Trademark & design",
        "url": "https://branddb.wipo.int/en/similarlogo",
        "mode": "manual",
    },
    {
        "id": "madridMonitor",
        "name": "WIPO Madrid Monitor",
        "category": "Trademark & design",
        "url": "https://www3.wipo.int/madrid/monitor/en/",
        "mode": "manual",
    },
    {
        "id": "auTrademark",
        "name": "IP Australia trademarks",
        "category": "Trademark & design",
        "url": "https://search.ipaustralia.gov.au/trademarks/search/advanced",
        "mode": "manual",
    },
    {
        "id": "auDesign",
        "name": "IP Australia designs",
        "category": "Trademark & design",
        "url": "https://search.ipaustralia.gov.au/designs/search/advanced",
        "mode": "manual",
    },
    {
        "id": "nzTrademark",
        "name": "IPONZ TradeMark Check",
        "category": "Trademark & design",
        "url": "https://app.iponz.govt.nz/app/TradeMarkCheck",
        "mode": "manual",
    },
    {
        "id": "jpDesign",
        "name": "Japan design search",
        "category": "Trademark & design",
        "url": "https://www.graphic-image.inpit.go.jp/",
        "mode": "manual",
    },
    {
        "id": "stocksy",
        "name": "Stocksy",
        "category": "Specialized",
        "url": "https://www.stocksy.com/",
        "mode": "manual",
    },
    {
        "id": "pond5",
        "name": "Pond5",
        "category": "Specialized",
        "url": "https://www.pond5.com/stock-images/",
        "mode": "manual",
    },
    {
        "id": "pixta",
        "name": "PIXTA",
        "category": "Specialized",
        "url": "https://www.pixtastock.com/",
        "mode": "manual",
    },
    {
        "id": "ikea",
        "name": "IKEA visual search",
        "category": "Specialized",
        "url": "https://www.ikea.com/",
        "mode": "manual",
    },
    {
        "id": "repostSleuth",
        "name": "Reddit Repost Sleuth",
        "category": "Specialized",
        "url": "https://repostsleuth.com/search",
        "mode": "manual",
    },
    {
        "id": "shein",
        "name": "SHEIN visual search",
        "category": "Shopping",
        "url": "https://m.shein.com/presearch",
        "mode": "manual",
    },
    {
        "id": "lykdat",
        "name": "LykDat",
        "category": "Shopping",
        "url": "https://lykdat.com/",
        "mode": "manual",
    },
    {
        "id": "wildberries",
        "name": "Wildberries visual search",
        "category": "Shopping",
        "url": "https://www.wildberries.ru/",
        "mode": "manual",
    },
    {
        "id": "vcg",
        "name": "VCG",
        "category": "Specialized",
        "url": "https://vcg.com/",
        "mode": "manual",
    },
]

ENGINE_BY_ID = {engine["id"]: engine for engine in ENGINE_CATALOG}
AUTO_ENGINE_IDS = [
    engine["id"] for engine in ENGINE_CATALOG if engine["mode"] == "auto"
]


def send(frame: Dict[str, Any]) -> None:
    """Write exactly one flushed protocol frame to stdout."""

    payload = json.dumps(frame, ensure_ascii=False, separators=(",", ":"))
    with SEND_LOCK:
        sys.stdout.write(payload + "\n")
        sys.stdout.flush()


def log(*values: Any) -> None:
    print(*values, file=sys.stderr, flush=True)


def command(name: str, **fields: Any) -> None:
    payload: Dict[str, Any] = {"type": "command", "command": name}
    payload.update(fields)
    send(payload)


def load_config() -> Dict[str, Any]:
    config_path = PLUGIN_DIR / "config.json"
    if not config_path.exists():
        return {}
    try:
        with config_path.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
        return value if isinstance(value, dict) else {}
    except Exception as exc:
        log("Could not read config.json:", exc)
        return {}


CONFIG = load_config()
try:
    _capture_timeout = int(CONFIG.get("capture_timeout_seconds", 120))
except (TypeError, ValueError):
    _capture_timeout = 120
CAPTURE_TIMEOUT = max(10, min(600, _capture_timeout))
yandex_host = str(CONFIG.get("yandex_host", "yandex.com")).strip().lower()
if not re.fullmatch(r"[a-z0-9.-]+", yandex_host):
    yandex_host = "yandex.com"


def enabled_engine_ids() -> List[str]:
    configured = CONFIG.get("engines")
    if not isinstance(configured, list):
        configured = CONFIG.get("enabled_engines")
    if not isinstance(configured, list):
        return [engine["id"] for engine in ENGINE_CATALOG]

    wanted = {str(item) for item in configured}
    return [engine["id"] for engine in ENGINE_CATALOG if engine["id"] in wanted]


ENABLED_ENGINE_IDS = enabled_engine_ids()


def page_payload(page_id: str, title: str) -> Dict[str, Any]:
    with STATE_LOCK:
        history = STATE.get("page_history", "none")
        STATE["page_history"] = "none"
    return {
        "id": page_id,
        "title": title,
        "history": history,
        "preserveState": True,
    }


def set_route(page: str, history: str = "none") -> None:
    with STATE_LOCK:
        STATE["page"] = page
        STATE["page_history"] = history


def capture_path() -> Optional[Path]:
    value = STATE.get("capture_path")
    return Path(value) if value else None


def capture_description() -> str:
    info = STATE.get("capture_info") or {}
    if not info:
        return "No capture yet"
    return "{}×{} PNG · {}".format(
        info.get("width", "?"), info.get("height", "?"), info.get("size", "unknown size")
    )


def render_home(rev: int, text: str = "") -> None:
    items: List[Dict[str, Any]] = [
        {
            "id": "capture",
            "title": "Capture an area",
            "subtitle": "Open Windows Screen Snipping through ms-screenclip:",
            "icon": "image",
            "actions": [
                {"id": "capture", "title": "Capture an area", "icon": "image"},
                {
                    "id": "use_clipboard",
                    "title": "Use current clipboard image",
                    "icon": "clipboard",
                },
            ],
            "preview": {
                "markdown": (
                    "## Capture an area\n\n"
                    "Press **Enter**, select a region in Windows Screen Snipping, "
                    "and the image will be ready for reverse search."
                )
            },
        },
        {
            "id": "use_clipboard",
            "title": "Use current clipboard image",
            "subtitle": "Use an image you already copied",
            "icon": "clipboard",
            "actions": [
                {"id": "use_clipboard", "title": "Read clipboard image", "icon": "clipboard"},
                {"id": "capture", "title": "Capture an area", "icon": "image"},
            ],
        },
    ]

    if capture_path() is not None:
        items.extend(
            [
                {
                    "id": "last_capture",
                    "title": "Last capture ready",
                    "subtitle": capture_description(),
                    "icon": "check",
                    "accessories": [{"text": "READY", "color": "#16A34A"}],
                    "actions": [
                        {"id": "open_engines", "title": "Choose an engine", "icon": "search"},
                        {"id": "open_capture", "title": "Open capture file", "icon": "open"},
                        {"id": "copy_path", "title": "Copy capture path", "icon": "copy"},
                    ],
                    "preview": {
                        "markdown": (
                            "## Capture ready\n\n"
                            "Use **Enter** to choose a search engine.\n\n"
                            "File: `{}`"
                        ).format(str(capture_path()).rstrip())
                    },
                },
                {
                    "id": "open_engines",
                    "title": "Choose a search engine",
                    "subtitle": "Search the last captured area",
                    "icon": "search",
                },
            ]
        )

    query = text.strip().lower()
    if query:
        items = [
            item
            for item in items
            if query in (item["title"] + " " + item.get("subtitle", "")).lower()
        ]

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": page_payload("sbi:home", "Search by image"),
            "preview": {"enabled": True, "wide": False},
            "placeholder": "Capture an area or use a clipboard image…",
            "empty": {
                "icon": "image",
                "title": "No matching actions",
                "hint": "Try `capture` or clear the query.",
            },
            "floatingAction": {"id": "capture", "title": "Capture", "icon": "image"},
            "items": items,
        }
    )


def engine_matches(engine: Dict[str, Any], query: str) -> bool:
    if not query:
        return True
    searchable = " ".join(
        [engine["id"], engine["name"], engine["category"], engine["mode"]]
    ).lower()
    return all(token in searchable for token in query.lower().split())


def render_engines(rev: int, text: str = "") -> None:
    if capture_path() is None:
        set_route("home", "replace")
        render_home(rev, text)
        return

    items: List[Dict[str, Any]] = []
    for engine_id in ENABLED_ENGINE_IDS:
        engine = ENGINE_BY_ID.get(engine_id)
        if not engine or not engine_matches(engine, text):
            continue
        is_auto = engine["mode"] == "auto"
        item: Dict[str, Any] = {
            "id": "engine:" + engine["id"],
            "title": engine["name"],
            "subtitle": (
                "Automatic upload and result tab"
                if is_auto
                else "Open upload page; paste the capture with Ctrl+V"
            ),
            "section": engine["category"],
            "icon": "search" if is_auto else "image",
            "accessories": [
                {
                    "text": "AUTO" if is_auto else "PASTE",
                    "color": "#16A34A" if is_auto else "#64748B",
                }
            ],
            "actions": [
                {
                    "id": "search",
                    "title": "Search with " + engine["name"],
                    "icon": "search",
                },
                {
                    "id": "open_upload",
                    "title": "Open upload page",
                    "icon": "open",
                },
                {"id": "copy_path", "title": "Copy capture path", "icon": "copy"},
            ],
            "preview": {
                "markdown": (
                    "## {}\n\n"
                    "**Category:** {}\n\n"
                    "**Mode:** {}\n\n"
                    "Capture: `{}`"
                ).format(
                    engine["name"],
                    engine["category"],
                    "automatic upload" if is_auto else "browser upload / paste",
                    str(capture_path()),
                )
            },
        }
        items.append(item)

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": page_payload("sbi:engines", "Search engines"),
            "preview": {"enabled": True, "wide": False, "resizable": True},
            "placeholder": "Filter engines…",
            "banners": [
                {
                    "id": "capture-ready",
                    "style": "success",
                    "title": "Capture ready",
                    "message": capture_description() + ". Choose an engine below.",
                }
            ],
            "empty": {
                "icon": "search",
                "title": "No matching engines",
                "hint": "Clear the query or update config.json.",
            },
            "actions": [
                {"id": "capture_new", "title": "Capture a new area", "icon": "image"},
                {
                    "id": "search_all_auto",
                    "title": "Search all automatic engines",
                    "icon": "search",
                },
                {"id": "open_capture", "title": "Open capture file", "icon": "open"},
                {"id": "copy_path", "title": "Copy capture path", "icon": "copy"},
            ],
            "floatingAction": {
                "id": "search_all_auto",
                "title": "Search automatic",
                "icon": "search",
            },
            "items": items,
        }
    )


def markdown_escape(value: Any) -> str:
    return str(value).replace("\\", "\\\\").replace("[", "\\[").replace("]", "\\]")


def render_result(
    rev: int,
    engine_name: str,
    result_url: Optional[str] = None,
    result_urls: Optional[List[Dict[str, str]]] = None,
    error: Optional[str] = None,
) -> None:
    if error:
        body = "# Search failed\n\n{}\n\nThe upload page will open so you can paste the capture manually.".format(
            markdown_escape(error)
        )
    elif result_urls is not None:
        lines = [
            "# {} results".format(markdown_escape(engine_name)),
            "",
            "The service returned {} visual matches.".format(len(result_urls)),
            "",
        ]
        for index, result in enumerate(result_urls[:30], start=1):
            label = markdown_escape(result.get("text") or "Visual match {}".format(index))
            page = result.get("page", "")
            image = result.get("image", "")
            if page:
                lines.append("{}. [{}]({})".format(index, label, page))
            if image:
                lines.append("   [Open matched image]({})".format(image))
        body = "\n".join(lines)
    else:
        body = (
            "# {}\n\n"
            "The search is ready in your browser.\n\n"
            "[Open search results]({})"
        ).format(markdown_escape(engine_name), result_url or "")

    actions: List[Dict[str, Any]] = [
        {"id": "back_engines", "title": "Back to search engines", "icon": "search"}
    ]
    if result_url:
        actions.insert(0, {"id": "open_result", "title": "Open results", "icon": "open"})
        actions.insert(1, {"id": "copy_result", "title": "Copy results URL", "icon": "copy"})

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "page": page_payload("sbi:result:" + (STATE.get("last_engine") or "unknown"), engine_name),
            "detail": {"markdown": body, "wide": True},
            "actions": actions,
            "floatingAction": (
                {"id": "open_result", "title": "Open results", "icon": "open"}
                if result_url
                else {"id": "back_engines", "title": "Back", "icon": "search"}
            ),
        }
    )


def render_error(rev: int, title: str, message: str) -> None:
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "page": page_payload("sbi:error", title),
            "detail": {
                "markdown": "# {}\n\n{}".format(
                    markdown_escape(title), markdown_escape(message)
                )
            },
            "actions": [{"id": "back_engines", "title": "Back", "icon": "search"}],
            "floatingAction": {"id": "back_engines", "title": "Back", "icon": "search"},
        }
    )


def render_busy(rev: int, label: str) -> None:
    page = STATE.get("page", "home")
    on_engine_page = page in ("engines", "search", "search_all")
    page_id = "sbi:engines" if on_engine_page else "sbi:home"
    title = "Search engines" if on_engine_page else "Search by image"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "page": page_payload(page_id, title),
            "loading": True,
            "loadingText": label,
            "items": [],
        }
    )


def get_clipboard_sequence() -> Optional[int]:
    if sys.platform != "win32":
        return None
    try:
        user32 = ctypes.windll.user32
        user32.GetClipboardSequenceNumber.restype = ctypes.c_uint
        return int(user32.GetClipboardSequenceNumber())
    except Exception as exc:
        log("Clipboard sequence lookup failed:", exc)
        return None


def grab_clipboard_image() -> Any:
    if not PIL_AVAILABLE or ImageGrab is None:
        raise RuntimeError("Pillow is not available; let Tabame finish installing the plugin dependency.")
    image = ImageGrab.grabclipboard()
    if image is None or isinstance(image, list) or not hasattr(image, "save"):
        return None
    return image


def clipboard_image_signature(image: Any) -> Optional[str]:
    if image is None or not hasattr(image, "size") or not hasattr(image, "tobytes"):
        return None
    try:
        digest = hashlib.sha256()
        digest.update("{}x{}|".format(image.size[0], image.size[1]).encode("ascii"))
        digest.update(image.tobytes())
        return digest.hexdigest()
    except Exception:
        return None


def start_screenclip() -> None:
    if sys.platform != "win32":
        # //TODO: Implement multiplatform
        raise RuntimeError("This plugin's capture source is Windows ms-screenclip.")
    try:
        os.startfile(SCREENCLIP_URI)  # type: ignore[attr-defined]
    except OSError as exc:
        raise RuntimeError("Could not open Windows Screen Snipping: {}".format(exc)) from exc


def capture_image_from_screenclip() -> Any:
    before = get_clipboard_sequence()
    try:
        before_image = grab_clipboard_image()
    except Exception:
        before_image = None
    before_signature = clipboard_image_signature(before_image)
    start_screenclip()
    deadline = time.monotonic() + CAPTURE_TIMEOUT

    while time.monotonic() < deadline and not STOP_EVENT.is_set():
        current = get_clipboard_sequence()
        sequence_changed = (
            before is not None and current is not None and current != before
        )
        if sequence_changed:
            image = grab_clipboard_image()
            if image is not None:
                return image
        elif before is None:
            try:
                image = grab_clipboard_image()
            except Exception:
                image = None
            if clipboard_image_signature(image) not in (None, before_signature):
                return image
        time.sleep(0.15)

    raise RuntimeError(
        "No new image was captured. Select a region in Screen Snipping, or press Escape and try again."
    )


def save_clipboard_image(image: Any) -> Tuple[Path, Dict[str, Any]]:
    CAPTURE_DIR.mkdir(parents=True, exist_ok=True)
    path = CAPTURE_DIR / "capture-{}.png".format(uuid.uuid4().hex[:12])
    image.save(str(path), "PNG")
    width, height = image.size
    info = {
        "width": int(width),
        "height": int(height),
        "size": format_bytes(path.stat().st_size),
    }
    return path, info


def format_bytes(size: int) -> str:
    value = float(size)
    for unit in ("B", "KB", "MB", "GB"):
        if value < 1024 or unit == "GB":
            return "{:.1f} {}".format(value, unit)
        value /= 1024
    return "{:.1f} GB".format(value)


def set_capture(path: Path, info: Dict[str, Any]) -> None:
    with STATE_LOCK:
        STATE["capture_path"] = str(path)
        STATE["capture_info"] = info
        STATE["busy"] = False
        STATE["busy_kind"] = ""
        STATE["busy_label"] = ""
        STATE["page"] = "engines"
        STATE["page_history"] = "push"


def finish_busy() -> None:
    with STATE_LOCK:
        STATE["busy"] = False
        STATE["busy_kind"] = ""
        STATE["busy_label"] = ""


def capture_worker(use_screenclip: bool) -> None:
    try:
        image = capture_image_from_screenclip() if use_screenclip else grab_clipboard_image()
        if image is None:
            raise RuntimeError("The clipboard does not contain an image.")
        path, info = save_clipboard_image(image)
        set_capture(path, info)
        if STOP_EVENT.is_set():
            return
        command("setQuery", text="")
        render_engines(0, "")
    except Exception as exc:
        finish_busy()
        log("Capture failed:", exc)
        if not STOP_EVENT.is_set():
            render_error(0, "Capture failed", str(exc))


def start_capture(use_screenclip: bool = True) -> None:
    with STATE_LOCK:
        if STATE["busy"]:
            command("toast", text="A capture or search is already running.", style="info")
            return
        STATE["busy"] = True
        STATE["busy_kind"] = "capture"
        STATE["busy_label"] = "Waiting for Windows Screen Snipping…"
    render_busy(0, "Waiting for Windows Screen Snipping…")
    threading.Thread(
        target=capture_worker,
        args=(use_screenclip,),
        name="sbi-capture",
        daemon=True,
    ).start()


def multipart_body(
    fields: Iterable[Tuple[str, str]] = (),
    file_field: Optional[Tuple[str, str, bytes, str]] = None,
) -> Tuple[bytes, str]:
    boundary = "----TabameSearchByImage{}".format(uuid.uuid4().hex)
    chunks: List[bytes] = []

    for name, value in fields:
        chunks.extend(
            [
                ("--" + boundary + "\r\n").encode("ascii"),
                ('Content-Disposition: form-data; name="{}"\r\n\r\n'.format(name)).encode(
                    "utf-8"
                ),
                str(value).encode("utf-8"),
                b"\r\n",
            ]
        )

    if file_field is not None:
        name, filename, data, content_type = file_field
        chunks.extend(
            [
                ("--" + boundary + "\r\n").encode("ascii"),
                (
                    'Content-Disposition: form-data; name="{}"; filename="{}"\r\n'
                    "Content-Type: {}\r\n\r\n"
                ).format(name, filename, content_type).encode("utf-8"),
                data,
                b"\r\n",
            ]
        )

    chunks.append(("--" + boundary + "--\r\n").encode("ascii"))
    return b"".join(chunks), "multipart/form-data; boundary={}".format(boundary)


def http_request(
    url: str,
    method: str = "GET",
    data: Optional[bytes] = None,
    content_type: Optional[str] = None,
    headers: Optional[Dict[str, str]] = None,
) -> Tuple[int, str, bytes]:
    request_headers = {
        "User-Agent": USER_AGENT,
        "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
    }
    if content_type:
        request_headers["Content-Type"] = content_type
    if headers:
        request_headers.update(headers)

    request = Request(url, data=data, headers=request_headers, method=method)
    try:
        with urlopen(request, timeout=35) as response:
            body = response.read(MAX_HTTP_RESPONSE + 1)
            if len(body) > MAX_HTTP_RESPONSE:
                body = body[:MAX_HTTP_RESPONSE]
            return int(response.status), response.geturl(), body
    except HTTPError as exc:
        body = exc.read(MAX_HTTP_RESPONSE)
        message = body.decode("utf-8", errors="replace")[:500].replace("\n", " ")
        raise RuntimeError("HTTP {} from {}: {}".format(exc.code, url, message)) from exc
    except URLError as exc:
        raise RuntimeError("Network error for {}: {}".format(url, exc.reason)) from exc


def image_bytes(path: Path) -> bytes:
    return path.read_bytes()


def prepare_bing_jpeg(path: Path) -> bytes:
    if not PIL_AVAILABLE or Image is None:
        raise RuntimeError("Pillow is required for Bing's image upload.")

    with Image.open(str(path)) as source:
        image = source.convert("RGB")
        image.thumbnail((4096, 4096), Image.LANCZOS)
        for quality in (88, 78, 68, 58, 48):
            output = io.BytesIO()
            image.save(output, format="JPEG", quality=quality, optimize=True)
            value = output.getvalue()
            if len(value) <= 600 * 1024:
                return value

        image.thumbnail((2048, 2048), Image.LANCZOS)
        output = io.BytesIO()
        image.save(output, format="JPEG", quality=42, optimize=True)
        return output.getvalue()


def search_google_images(path: Path) -> Dict[str, Any]:
    body, content_type = multipart_body(
        fields=[
            ("image_url", ""),
            ("sbisrc", "Google Chrome 110.0.5481.78 (Official) Windows"),
        ],
        file_field=("encoded_image", "capture.png", image_bytes(path), "image/png"),
    )
    status, result_url, _ = http_request(
        "https://www.google.com/searchbyimage/upload",
        method="POST",
        data=body,
        content_type=content_type,
        headers={"Origin": "https://www.google.com", "Referer": "https://www.google.com/"},
    )
    if status != 200:
        raise RuntimeError("Google Images returned HTTP {}".format(status))
    if not result_url or result_url.endswith("/searchbyimage/upload"):
        raise RuntimeError("Google Images did not return a result URL.")
    return {"kind": "url", "url": result_url}


def search_bing(path: Path) -> Dict[str, Any]:
    jpeg = prepare_bing_jpeg(path)
    encoded = base64.b64encode(jpeg).decode("ascii")
    filename = "capture.jpg"
    upload_url = (
        "https://www.bing.com/images/search?view=detailv2&iss=sbiupload"
        "&FORM=SBIHMP&sbifnm="
        + quote(filename)
    )
    body, content_type = multipart_body(fields=[("imageBin", encoded)])
    status, result_url, _ = http_request(
        upload_url,
        method="POST",
        data=body,
        content_type=content_type,
        headers={"Origin": "https://www.bing.com", "Referer": "https://www.bing.com/images"},
    )
    if status != 200 or not result_url or "sbiupload" in result_url:
        raise RuntimeError("Bing did not return a visual-search result URL.")
    return {"kind": "url", "url": result_url}


def yandex_result_url(host: str, response: Dict[str, Any]) -> str:
    try:
        params = response["blocks"][0]["params"]
        cbir_id = str(params["cbirId"])
        original_url = str(params.get("originalImageUrl", ""))
    except (KeyError, IndexError, TypeError) as exc:
        raise RuntimeError("Yandex returned an unexpected upload response.") from exc
    return (
        "https://{}/images/search?cbir_id={}&rpt=imageview&tabInt=1&url={}"
    ).format(host, quote(cbir_id), quote(original_url, safe=""))


def search_yandex(path: Path) -> Dict[str, Any]:
    hosts = [yandex_host]
    if yandex_host == "yandex.com":
        hosts.append("yandex.ru")
    last_error: Optional[Exception] = None
    for host in hosts:
        request_json = quote(
            '{"blocks":[{"block":"cbir-uploader__get-cbir-id"}]}', safe=""
        )
        upload_url = (
            "https://{}/images/touch/search?rpt=imageview&format=json&request={}"
        ).format(host, request_json)
        body, content_type = multipart_body(
            file_field=("upfile", "capture.png", image_bytes(path), "image/png")
        )
        try:
            status, _, response_body = http_request(
                upload_url,
                method="POST",
                data=body,
                content_type=content_type,
                headers={
                    "X-Requested-With": "XMLHttpRequest",
                    "Accept": "application/json, text/javascript, */*; q=0.01",
                    "Referer": "https://{}/images/".format(host),
                },
            )
            if status != 200:
                raise RuntimeError("Yandex returned HTTP {}".format(status))
            payload = json.loads(response_body.decode("utf-8", errors="replace"))
            return {"kind": "url", "url": yandex_result_url(host, payload)}
        except Exception as exc:
            last_error = exc
            log("Yandex host failed:", host, exc)
    raise RuntimeError(str(last_error or "Yandex upload failed."))


def search_pinterest(path: Path) -> Dict[str, Any]:
    body, content_type = multipart_body(
        fields=[("x", "0"), ("y", "0"), ("w", "1"), ("h", "1"), ("base_scheme", "https")],
        file_field=("image", "capture.png", image_bytes(path), "image/png"),
    )
    status, _, response_body = http_request(
        "https://api.pinterest.com/v3/visual_search/extension/image/",
        method="PUT",
        data=body,
        content_type=content_type,
        headers={"Origin": "https://www.pinterest.com", "Referer": "https://www.pinterest.com/"},
    )
    try:
        response = json.loads(response_body.decode("utf-8", errors="replace"))
    except json.JSONDecodeError as exc:
        raise RuntimeError("Pinterest returned invalid JSON.") from exc
    if status != 200 or response.get("status") != "success":
        raise RuntimeError("Pinterest visual search failed.")

    results: List[Dict[str, str]] = []
    for item in response.get("data", []) or []:
        if not isinstance(item, dict) or not item.get("id"):
            continue
        results.append(
            {
                "page": "https://pinterest.com/pin/{}/".format(item["id"]),
                "image": str(item.get("image_large_url", "")),
                "text": str(item.get("description", "") or "Pinterest visual match"),
            }
        )
    return {"kind": "results", "results": results}


def search_unsplash(path: Path) -> Dict[str, Any]:
    content_type = "image/png"
    status, _, response_body = http_request(
        "https://unsplash.com/napi/search/by_image/upload?content_type=" + quote(content_type),
        headers={"Accept": "application/json", "Referer": "https://unsplash.com/"},
    )
    if status != 200:
        raise RuntimeError("Unsplash upload setup returned HTTP {}".format(status))
    try:
        search_data = json.loads(response_body.decode("utf-8", errors="replace"))
        fields = search_data["fields"]
        upload_url = search_data["url"]
    except (KeyError, TypeError, json.JSONDecodeError) as exc:
        raise RuntimeError("Unsplash returned an unexpected upload setup response.") from exc

    form_fields = [(str(key), str(value)) for key, value in fields.items()]
    body, form_content_type = multipart_body(
        fields=form_fields,
        file_field=("file", "capture.png", image_bytes(path), content_type),
    )
    upload_status, _, _ = http_request(
        upload_url,
        method=str(search_data.get("method", "POST")),
        data=body,
        content_type=form_content_type,
    )
    if upload_status not in (200, 201, 204):
        raise RuntimeError("Unsplash image upload returned HTTP {}".format(upload_status))

    result_body, result_content_type = multipart_body(fields=[("upload", str(fields["key"]))])
    result_status, _, result_response = http_request(
        "https://unsplash.com/napi/search/by_image",
        method="POST",
        data=result_body,
        content_type=result_content_type,
        headers={"Accept": "application/json", "Referer": "https://unsplash.com/"},
    )
    if result_status != 201:
        raise RuntimeError("Unsplash visual search returned HTTP {}".format(result_status))
    try:
        result = json.loads(result_response.decode("utf-8", errors="replace"))
        visual_id = result["uuid"]
    except (KeyError, TypeError, json.JSONDecodeError) as exc:
        raise RuntimeError("Unsplash returned an unexpected result response.") from exc
    return {"kind": "url", "url": "https://unsplash.com/s/visual/" + str(visual_id)}


def perform_search(engine_id: str, path: Path) -> Dict[str, Any]:
    if engine_id == "googleImages":
        return search_google_images(path)
    if engine_id == "bing":
        return search_bing(path)
    if engine_id == "yandex":
        return search_yandex(path)
    if engine_id == "pinterest":
        return search_pinterest(path)
    if engine_id == "unsplash":
        return search_unsplash(path)
    raise RuntimeError("No automatic upload flow is configured for this engine.")


def open_manual_engine(engine: Dict[str, Any]) -> None:
    # The screenshot remains in the Windows clipboard after capture. Do not
    # copy the path before opening the page, otherwise Ctrl+V would paste text.
    command("open", url=engine["url"])
    command("hide")


def search_worker(engine_id: str) -> None:
    engine = ENGINE_BY_ID[engine_id]
    path = capture_path()
    try:
        if path is None or not path.exists():
            raise RuntimeError("The capture file is no longer available.")
        result = perform_search(engine_id, path)
        if STOP_EVENT.is_set():
            return
        finish_busy()
        with STATE_LOCK:
            STATE["last_engine"] = engine_id
        if result.get("kind") == "url":
            with STATE_LOCK:
                STATE["last_result_url"] = result.get("url")
                STATE["last_result_urls"] = []
            command("open", url=result.get("url"))
            command("hide")
        else:
            with STATE_LOCK:
                STATE["page"] = "result"
                STATE["page_history"] = "push"
                STATE["last_result_url"] = None
                STATE["last_result_urls"] = result.get("results", [])
            render_result(0, engine["name"], result_urls=result.get("results", []))
    except Exception as exc:
        finish_busy()
        log("Automatic search failed:", engine_id, exc)
        if not STOP_EVENT.is_set():
            open_manual_engine(engine)


def start_search(engine_id: str) -> None:
    engine = ENGINE_BY_ID.get(engine_id)
    path = capture_path()
    if not engine:
        render_error(0, "Unknown engine", engine_id)
        return
    if path is None or not path.exists():
        render_error(0, "No capture", "Capture an area before choosing a search engine.")
        return
    if engine["mode"] != "auto":
        open_manual_engine(engine)
        return

    with STATE_LOCK:
        if STATE["busy"]:
            command("toast", text="A capture or search is already running.", style="info")
            return
        STATE["busy"] = True
        STATE["busy_kind"] = "search"
        STATE["busy_label"] = "Uploading to {}…".format(engine["name"])
        STATE["page"] = "search"
        STATE["page_history"] = "push"
        STATE["last_engine"] = engine_id
    render_busy(0, "Uploading to {}…".format(engine["name"]))
    threading.Thread(
        target=search_worker,
        args=(engine_id,),
        name="sbi-search-" + engine_id,
        daemon=True,
    ).start()


def search_all_worker() -> None:
    path = capture_path()
    urls: List[str] = []
    failures: List[str] = []
    if path is None or not path.exists():
        finish_busy()
        render_error(0, "No capture", "Capture an area before searching.")
        return

    auto_ids = [engine_id for engine_id in AUTO_ENGINE_IDS if engine_id in ENABLED_ENGINE_IDS]
    for index, engine_id in enumerate(auto_ids, start=1):
        if STOP_EVENT.is_set():
            return
        engine = ENGINE_BY_ID[engine_id]
        with STATE_LOCK:
            STATE["busy_label"] = "Searching {} ({}/{})…".format(
                engine["name"], index, len(auto_ids)
            )
        render_busy(0, STATE["busy_label"])
        try:
            result = perform_search(engine_id, path)
            if result.get("kind") == "url" and result.get("url"):
                urls.append(str(result["url"]))
            elif result.get("kind") == "results":
                with STATE_LOCK:
                    STATE["last_result_urls"] = result.get("results", [])
        except Exception as exc:
            failures.append("{}: {}".format(engine["name"], exc))
            log("Automatic search failed:", engine_id, exc)

    finish_busy()
    if urls:
        for url in urls:
            command("open", url=url)
        command("hide")
        return

    details = "No automatic engine returned a result."
    if failures:
        details += "\n\n" + "\n".join(failures[:5])
    render_error(0, "Automatic search failed", details)


def start_search_all() -> None:
    path = capture_path()
    if path is None or not path.exists():
        render_error(0, "No capture", "Capture an area before searching.")
        return
    with STATE_LOCK:
        if STATE["busy"]:
            command("toast", text="A capture or search is already running.", style="info")
            return
        STATE["busy"] = True
        STATE["busy_kind"] = "search_all"
        STATE["busy_label"] = "Searching automatic engines…"
        STATE["page"] = "search_all"
        STATE["page_history"] = "push"
    render_busy(0, "Searching automatic engines…")
    threading.Thread(target=search_all_worker, name="sbi-search-all", daemon=True).start()


def copy_capture_path() -> None:
    path = capture_path()
    if path:
        command("copy", text=str(path))


def open_capture() -> None:
    path = capture_path()
    if path:
        command("open", path=str(path))


def handle_back() -> None:
    page = STATE.get("page")
    if page in ("result", "error", "search", "search_all") and capture_path():
        set_route("engines", "none")
        render_engines(0, "")
    elif page == "engines":
        set_route("home", "none")
        render_home(0, "")


def handle_action(message: Dict[str, Any]) -> None:
    item_id = str(message.get("id", ""))
    action = str(message.get("action", "default"))

    if item_id.startswith("engine:"):
        engine_id = item_id.split(":", 1)[1]
        if action in ("default", "search"):
            start_search(engine_id)
        elif action == "open_upload":
            engine = ENGINE_BY_ID.get(engine_id)
            if engine:
                open_manual_engine(engine)
        elif action == "copy_path":
            copy_capture_path()
        return

    if item_id in ("capture", "capture_new") or action in ("capture", "capture_new"):
        start_capture(True)
    elif item_id == "use_clipboard" or action == "use_clipboard":
        start_capture(False)
    elif item_id in ("last_capture", "open_engines") or action == "open_engines":
        if capture_path():
            set_route("engines", "push")
            render_engines(0, "")
        else:
            render_error(0, "No capture", "Capture an area before choosing an engine.")
    elif item_id == "open_capture" or action == "open_capture":
        open_capture()
    elif item_id == "copy_path" or action == "copy_path":
        copy_capture_path()
    elif item_id == "search_all_auto" or action == "search_all_auto":
        start_search_all()
    elif item_id == "back_engines" or action == "back_engines":
        handle_back()
    elif item_id == "open_result" or action == "open_result":
        url = STATE.get("last_result_url")
        if url:
            command("open", url=url)
    elif item_id == "copy_result" or action == "copy_result":
        url = STATE.get("last_result_url")
        if url:
            command("copy", text=url)


def render_current(rev: int, text: str) -> None:
    page = STATE.get("page", "home")
    if page == "engines":
        render_engines(rev, text)
    elif page == "home":
        render_home(rev, text)
    else:
        # Query edits on a result/progress page return to the useful filter
        # destination instead of leaving an empty dead-end screen.
        if capture_path():
            set_route("engines", "replace")
            render_engines(rev, text)
        else:
            set_route("home", "replace")
            render_home(rev, text)


def handle_message(message: Dict[str, Any]) -> bool:
    message_type = message.get("type")
    if message_type == "close":
        STOP_EVENT.set()
        return False
    if message_type in ("init", "query"):
        text = message.get("text", message.get("query", ""))
        render_current(int(message.get("rev", 0) or 0), str(text or ""))
    elif message_type == "action":
        handle_action(message)
    elif message_type == "back":
        handle_back()
    return True


def main() -> None:
    for line in sys.stdin:
        if STOP_EVENT.is_set():
            break
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
            if not isinstance(message, dict):
                continue
            if not handle_message(message):
                break
        except Exception as exc:
            log("Protocol handler failed:", exc)
            try:
                render_error(0, "Plugin error", str(exc))
            except Exception:
                log("Could not render plugin error:", exc)


if __name__ == "__main__":
    main()
