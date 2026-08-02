#!/usr/bin/env python3
"""
xPrice Lookup — a Tabame launcher plugin.

Usage: type `xprice <product url>` in the launcher.

Flow:
  1. Open xprice.ro in a temporary, inactive browser tab (via Tabame's
     app-owned browserBridge — this plugin never opens its own WebSocket).
  2. Paste the pasted URL into `input[name="product_link"]` and submit
     the form.
  3. Wait for the redirect to the product's price-history page.
  4. Extract the product name/image and the AggregateOffer list from the
     page's JSON-LD, plus the day-by-day price history from the
     `.hist-graph .bar` elements.
  5. Render a single PNG "price card" with Pillow: product photo, price
     history line chart, and a ranked list of alternative stores.
  6. Show the card in a detail frame, with the 3 cheapest links as
     clickable metadata rows and Ctrl+K actions to open/copy them.

Every temporary tab is closed in a `finally` block, and every browser
request is validated before use, per the plugin's browser-bridge
contract.
"""

import io
import json
import os
import queue
import re
import sys
import textwrap
import threading
import time
import urllib.request
from datetime import datetime
from itertools import count
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

XPRICE_URL = "https://xprice.ro/"
REQUEST_TIMEOUT = 30
READY_TIMEOUT = 20
NAV_TIMEOUT = 25

URL_RE = re.compile(r"https?://\S+")

# ---------------------------------------------------------------------------
# Site-specific browser scripts. Data flows in through the bridge's `input`
# and back out through the script's `return` value — nothing is inferred
# from selectors that weren't confirmed to exist on the target pages.
# ---------------------------------------------------------------------------

SUBMIT_SCRIPT = r"""
const targetUrl = input && input.productUrl;
if (!targetUrl) {
  throw new Error("No product URL was provided.");
}
const field = document.querySelector('input[name="product_link"]');
if (!field) {
  throw new Error("Could not find the product link field on xprice.ro.");
}
const nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value").set;
nativeSetter.call(field, targetUrl);
field.dispatchEvent(new Event("input", { bubbles: true }));
field.dispatchEvent(new Event("change", { bubbles: true }));
const form = field.closest("form");
if (!form) {
  throw new Error("Could not find the search form on xprice.ro.");
}
const submitBtn = form.querySelector('button[type="submit"], input[type="submit"]');
if (submitBtn) {
  submitBtn.click();
} else if (typeof form.requestSubmit === "function") {
  form.requestSubmit();
} else {
  form.submit();
}
return { submitted: true, startUrl: location.href };
"""

EXTRACT_SCRIPT = r"""
function toNumber(value) {
  if (value === undefined || value === null) return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

let product = null;
const ldScripts = Array.from(document.querySelectorAll('script[type="application/ld+json"]'));
for (const node of ldScripts) {
  try {
    const parsed = JSON.parse(node.textContent);
    if (parsed && parsed["@type"] === "Product") {
      product = parsed;
      break;
    }
  } catch (err) {
    // ignore malformed JSON-LD blocks
  }
}

if (!product) {
  throw new Error("This does not look like an xPrice product history page.");
}

const rawOffers = (product.offers && product.offers.offers) || [];
const offers = rawOffers
  .map((offer) => ({
    seller: offer.seller && offer.seller.name ? offer.seller.name : "Magazin",
    price: toNumber(offer.price),
    url: offer.url || null,
  }))
  .filter((offer) => offer.price !== null && offer.url);

const bars = Array.from(document.querySelectorAll(".hist-graph .bar")).map((el) => {
  const date = el.getAttribute("data-date");
  const intPart = toNumber(el.getAttribute("data-price-int"));
  const decPart = toNumber(el.getAttribute("data-price-decimals")) || 0;
  const price = intPart === null ? null : intPart + decPart / 100;
  return { date, price };
}).filter((point) => point.date && point.price !== null);

return {
  name: product.name || document.title,
  image: product.image || null,
  pageUrl: location.href,
  lowPrice: toNumber(product.offers && product.offers.lowPrice),
  highPrice: toNumber(product.offers && product.offers.highPrice),
  offers,
  history: bars,
};
"""

# ---------------------------------------------------------------------------
# Protocol plumbing
# ---------------------------------------------------------------------------


def send(message):
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()


def command(name, **fields):
    send({"type": "command", "command": name, **fields})


def render(rev, view, **fields):
    send({"type": "render", "rev": rev, "view": view, **fields})


def log(*parts):
    print(*parts, file=sys.stderr, flush=True)


def meta(**kwargs):
    return {k: v for k, v in kwargs.items() if v is not None}


def truncate(value, max_len):
    value = str(value or "")
    return value if len(value) <= max_len else value[: max_len - 1] + "…"


def escape_markdown(value):
    return re.sub(r"([\\`*_{}\[\]()#+\-.!|>])", r"\\\1", str(value or ""))


def extract_url(text):
    match = URL_RE.search((text or "").strip())
    return match.group(0) if match else None


class BrowserBridge:
    """Thin adapter for Tabame's app-owned browser bridge.

    The plugin never opens its own WebSocket — it asks Tabame to forward an
    allowlisted browser request via `browserBridge` commands, and correlates
    the asynchronous reply (which arrives on stdin) by requestId.
    """

    def __init__(self):
        self._pending = {}
        self._lock = threading.Lock()
        self._counter = count()
        self.enabled = False
        self.running = False
        self.connected = False
        self.port = 17373
        self.token = ""
        self.client_info = {}
        self.start_error = None

    def call_host(self, op, fields=None, timeout=REQUEST_TIMEOUT):
        fields = fields or {}
        request_id = (
            f"xprice-{os.getpid()}-{int(time.time() * 1000)}-{next(self._counter)}"
        )
        q = queue.Queue(maxsize=1)
        with self._lock:
            self._pending[request_id] = q
        command(
            "browserBridge",
            op=op,
            requestId=request_id,
            timeoutMs=int(timeout * 1000),
            **fields,
        )
        try:
            ok, payload = q.get(timeout=timeout + 2)
        except queue.Empty:
            with self._lock:
                self._pending.pop(request_id, None)
            raise TimeoutError(f"Tabame browser bridge timed out: {op}")
        if not ok:
            raise RuntimeError(payload or "Browser bridge request failed")
        return payload

    def request(self, method, params=None, timeout=REQUEST_TIMEOUT):
        return self.call_host(
            "request", {"method": method, "params": params or {}}, timeout
        )

    def refresh_status(self):
        status = self.call_host("status", {}, timeout=10)
        self.apply_status(status)
        return status

    def apply_status(self, status):
        status = status or {}
        self.enabled = bool(status.get("enabled"))
        self.running = bool(status.get("running"))
        self.connected = bool(status.get("connected"))
        port = status.get("port")
        try:
            if port is not None:
                self.port = int(port)
        except (TypeError, ValueError):
            pass
        token = status.get("token")
        if isinstance(token, str):
            self.token = token
        self.client_info = {
            "extensionVersion": str(status.get("extensionVersion") or "unknown"),
            "browser": str(status.get("browser") or "unknown"),
        }
        if status.get("error"):
            self.start_error = str(status.get("error"))
        elif not self.enabled:
            self.start_error = "The persistent browser connector is disabled. Enable it in Launcher Plugins."
        elif not self.running:
            self.start_error = "The persistent browser connector is starting."
        else:
            self.start_error = None

    def handle_host_message(self, message):
        request_id = message.get("requestId")
        if request_id:
            with self._lock:
                q = self._pending.pop(request_id, None)
            if q is not None:
                ok = bool(message.get("ok"))
                q.put((ok, message.get("result") if ok else message.get("error")))
            return
        if message.get("event") == "connection.changed":
            self.apply_status(message.get("data") or {})


bridge = BrowserBridge()

state = {
    "query": "",
    "last_url": None,
    "last_result": None,
    "last_image_path": None,
}

# ---------------------------------------------------------------------------
# Tab lifecycle helpers
# ---------------------------------------------------------------------------


def get_tab(tab_id):
    snapshot = bridge.request("tabs.list", {}, timeout=15)
    for tab in (snapshot or {}).get("tabs", []) or []:
        if tab.get("id") == tab_id:
            return tab
    return None


def wait_for_tab_ready(tab_id, timeout=READY_TIMEOUT):
    deadline = time.time() + timeout
    while time.time() < deadline:
        tab = get_tab(tab_id)
        if tab is None:
            raise RuntimeError("The xPrice browser tab was closed.")
        if tab.get("status") == "complete":
            return tab
        time.sleep(0.25)
    raise TimeoutError("The xPrice page did not finish loading in time.")


def wait_for_navigation(tab_id, original_url, timeout=NAV_TIMEOUT):
    deadline = time.time() + timeout
    while time.time() < deadline:
        tab = get_tab(tab_id)
        if tab is None:
            raise RuntimeError("The xPrice browser tab was closed.")
        url = tab.get("url") or ""
        if url and url != original_url and tab.get("status") == "complete":
            return tab
        time.sleep(0.3)
    raise TimeoutError(
        "xprice.ro did not redirect to a product page. Check that the link is valid."
    )


# ---------------------------------------------------------------------------
# Image generation
# ---------------------------------------------------------------------------


def load_font(size, bold=False):
    candidates = (
        ["arialbd.ttf", "DejaVuSans-Bold.ttf", "LiberationSans-Bold.ttf"]
        if bold
        else ["arial.ttf", "DejaVuSans.ttf", "LiberationSans-Regular.ttf"]
    )
    for name in candidates:
        try:
            return ImageFont.truetype(name, size)
        except Exception:
            continue
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def draw_history_chart(draw, history, x, y, w, h, font):
    draw.rectangle([x, y, x + w, y + h], outline="#3A3D46", width=2)
    if len(history) < 2:
        draw.text(
            (x + 16, y + h // 2 - 10),
            "Nu există suficient istoric de preț",
            font=font,
            fill="#8A7F88",
        )
        return

    prices = [p["price"] for p in history]
    lo, hi = min(prices), max(prices)
    if hi == lo:
        hi = lo + 1
    pad = 16
    plot_w = w - pad * 2
    plot_h = h - pad * 2
    n = len(history)

    def point(i, price):
        px = x + pad + (plot_w * i / (n - 1))
        py = y + pad + plot_h * (1 - (price - lo) / (hi - lo))
        return (px, py)

    pts = [point(i, p["price"]) for i, p in enumerate(history)]
    draw.line(pts, fill="#63A0EA", width=4, joint="curve")
    for px, py in pts:
        draw.ellipse([px - 3, py - 3, px + 3, py + 3], fill="#63A0EA")

    draw.text((x + pad, y + pad - 4), f"{hi:.2f} RON", font=font, fill="#E8E8E8")
    draw.text((x + pad, y + h - pad - 20), f"{lo:.2f} RON", font=font, fill="#E8E8E8")

    first_label, last_label = history[0]["date"], history[-1]["date"]
    draw.text((x + pad, y + h + 8), first_label, font=font, fill="#8A7F88")
    tw = draw.textlength(last_label, font=font)
    draw.text((x + w - pad - tw, y + h + 8), last_label, font=font, fill="#8A7F88")


def draw_offers(draw, offers, x, y, w, row_h, font, font_bold):
    rank_colors = {0: "#1F3D2E", 1: "#2A2E1F", 2: "#2E241A"}
    price_colors = {0: "#3D9B72"}
    for i, offer in enumerate(offers):
        ry = y + i * row_h
        bg = rank_colors.get(i)
        if bg:
            draw.rectangle([x, ry, x + w, ry + row_h - 6], fill=bg)
        draw.text((x + 12, ry + 10), f"#{i + 1}", font=font_bold, fill="#E8E8E8")
        draw.text(
            (x + 64, ry + 10), truncate(offer["seller"], 30), font=font, fill="#E8E8E8"
        )
        price_text = f"{offer['price']:.2f} RON"
        tw = draw.textlength(price_text, font=font_bold)
        draw.text(
            (x + w - 16 - tw, ry + 8),
            price_text,
            font=font_bold,
            fill=price_colors.get(i, "#E8E8E8"),
        )


def generate_image(data):
    name = data.get("name") or "Produs"
    offers = sorted(
        [o for o in (data.get("offers") or []) if o.get("price") is not None],
        key=lambda o: o["price"],
    )
    history = [h for h in (data.get("history") or []) if h.get("price") is not None]

    width, height = 1200, 1300
    card = Image.new("RGB", (width, height), "#1B1D23")
    draw = ImageDraw.Draw(card)

    title_font = load_font(38, bold=True)
    section_font = load_font(26, bold=True)
    text_font = load_font(22)
    small_font = load_font(18)

    margin = 40
    y = margin
    thumb_size = 220

    thumb_box = (margin, y, margin + thumb_size, y + thumb_size)
    pasted = False
    image_url = data.get("image")
    if image_url:
        try:
            req = urllib.request.Request(
                image_url, headers={"User-Agent": "Mozilla/5.0"}
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                raw = resp.read()
            product_img = Image.open(io.BytesIO(raw)).convert("RGB")
            product_img.thumbnail((thumb_size - 20, thumb_size - 20))
            draw.rectangle(thumb_box, fill="#FFFFFF")
            offset = (
                margin + (thumb_size - product_img.width) // 2,
                y + (thumb_size - product_img.height) // 2,
            )
            card.paste(product_img, offset)
            pasted = True
        except Exception as err:
            log("product image download failed:", err)
    if not pasted:
        draw.rectangle(thumb_box, outline="#3A3D46", width=2)
        draw.text(
            (margin + 20, y + thumb_size // 2 - 10),
            "Fără imagine",
            font=text_font,
            fill="#8A7F88",
        )

    title_x = margin + thumb_size + 30
    title_lines = textwrap.wrap(name, width=28)[:4]
    ty = y + 4
    for line in title_lines:
        draw.text((title_x, ty), line, font=title_font, fill="#E8E8E8")
        ty += 46

    stats = []
    if data.get("lowPrice") is not None:
        stats.append(f"Min: {data['lowPrice']:.2f} RON")
    if data.get("highPrice") is not None:
        stats.append(f"Max: {data['highPrice']:.2f} RON")
    stats.append(f"{len(offers)} magazine")
    draw.text(
        (title_x, y + thumb_size - 34),
        "  ·  ".join(stats),
        font=text_font,
        fill="#8A7F88",
    )

    y += thumb_size + 40
    draw.text((margin, y), "Istoric preț", font=section_font, fill="#E8E8E8")
    y += 40
    chart_h = 320
    draw_history_chart(
        draw, history, margin, y, width - margin * 2, chart_h, small_font
    )
    y += chart_h + 60

    draw.text((margin, y), "Unde găsești mai ieftin", font=section_font, fill="#E8E8E8")
    y += 44
    row_h = 46
    visible_offers = offers[:10]
    draw_offers(
        draw,
        visible_offers,
        margin,
        y,
        width - margin * 2,
        row_h,
        text_font,
        section_font,
    )
    y += row_h * len(visible_offers) + 30

    footer = (
        f"Generat de plugin-ul xPrice · {datetime.now().strftime('%d.%m.%Y %H:%M')}"
    )
    draw.text((margin, height - margin - 20), footer, font=small_font, fill="#5A5D66")

    cache_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cache")
    os.makedirs(cache_dir, exist_ok=True)
    out_path = os.path.join(cache_dir, f"xprice_{int(time.time() * 1000)}.png")
    card.save(out_path, "PNG")
    return out_path


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------


def render_root(rev, text):
    url = extract_url(text)
    if url:
        item = {
            "id": "lookup",
            "title": "Look up price on xPrice",
            "subtitle": truncate(url, 80),
            "icon": "chart",
            "actions": [{"id": "lookup", "title": "Look up price", "icon": "chart"}],
        }
        render(
            rev,
            "list",
            items=[item],
            placeholder="Paste a product URL…",
            emptyText="Paste a product link to look up its price",
        )
    else:
        render(
            rev,
            "list",
            items=[],
            placeholder="Paste a product URL…",
            empty={
                "icon": "link",
                "title": "Paste a product link",
                "hint": "e.g. an eMAG, Altex, or PC Garage product page URL",
            },
        )


def render_error(rev, error, title):
    message = str(error)
    render(
        rev,
        "detail",
        canGoBack=True,
        detail={
            "markdown": (
                f"# {title}\n\n{escape_markdown(message)}\n\n"
                "Open **Connection & pairing** if the browser connector is disabled or offline."
            ),
        },
        actions=[
            {"id": "retry", "title": "Try again", "icon": "refresh"},
            {"id": "connection", "title": "Connection & pairing", "icon": "key"},
        ],
    )


def render_connection():
    try:
        bridge.refresh_status()
    except Exception as err:
        log("status refresh failed:", err)

    token = bridge.token
    token_display = (
        " ".join(token[i : i + 6] for i in range(0, len(token), 6))
        if token
        else "Not available while the connector is disabled"
    )
    if not bridge.enabled:
        md = (
            "# Persistent browser connector is off\n\n"
            "Open **Launcher Plugins** and enable **Persistent browser connector**."
        )
    elif bridge.connected:
        md = (
            "# Browser connector is online\n\n"
            "This plugin can now open xprice.ro and read product pages.\n\n"
            "Use **Escape** to go back."
        )
    else:
        md = (
            "# Pair the Chromium extension\n\n"
            "1. Load `tabame-extension` from `chrome://extensions`.\n"
            "2. Enable **Allow User Scripts** if shown.\n"
            "3. Click the **Tabame Connector** toolbar icon.\n"
            "4. Paste the token below and keep the default port.\n"
            "5. Click **Save & connect**.\n\n"
            "### Pairing token\n\n"
            f"`{token_display}`"
        )

    status_text = (
        "Disabled"
        if not bridge.enabled
        else ("Connected" if bridge.connected else "Waiting for extension")
    )
    status_color = (
        "#8A7F88"
        if not bridge.enabled
        else ("#3D9B72" if bridge.connected else "#D18B47")
    )
    metadata = [
        meta(label="Status", text=status_text, color=status_color),
        meta(label="Address", text=f"127.0.0.1:{bridge.port}", icon="server"),
    ]
    if bridge.start_error:
        metadata.append(
            meta(label="Bridge error", text=bridge.start_error, color="#C86464")
        )

    actions = []
    if bridge.enabled and token:
        actions.append(
            {"id": "copy_token", "title": "Copy pairing token", "icon": "key"}
        )
    actions.append(
        {"id": "copy_address", "title": "Copy bridge address", "icon": "copy"}
    )
    actions.append(
        {"id": "refresh_status", "title": "Refresh status", "icon": "refresh"}
    )

    render(
        0,
        "detail",
        canGoBack=True,
        detail={"markdown": md, "metadata": metadata},
        actions=actions,
    )


def render_result(rev, data, image_path):
    name = data.get("name") or "Produs"
    offers = sorted(
        [o for o in (data.get("offers") or []) if o.get("price") is not None],
        key=lambda o: o["price"],
    )
    top3 = offers[:3]
    image_uri = Path(image_path).resolve().as_uri()

    md_lines = [
        f"# {escape_markdown(name)}",
        "",
        f"![{escape_markdown(name)}]({image_uri})",
    ]

    metadata = []
    rank_labels = ["#1 cel mai ieftin", "#2 cel mai ieftin", "#3 cel mai ieftin"]
    for i, offer in enumerate(top3):
        metadata.append(
            meta(
                label=rank_labels[i] if i < len(rank_labels) else f"#{i + 1}",
                text=f"{offer['seller']} · {offer['price']:.2f} RON",
                url=offer.get("url"),
                color="#3D9B72" if i == 0 else None,
            )
        )
    if data.get("lowPrice") is not None or data.get("highPrice") is not None:
        metadata.append({"separator": True})
        if data.get("lowPrice") is not None:
            metadata.append(
                meta(label="Preț minim", text=f"{data['lowPrice']:.2f} RON")
            )
        if data.get("highPrice") is not None:
            metadata.append(
                meta(label="Preț maxim", text=f"{data['highPrice']:.2f} RON")
            )
    if data.get("pageUrl"):
        metadata.append(
            meta(label="Pagina xPrice", text="Deschide", url=data["pageUrl"])
        )

    actions = []
    if top3:
        actions.append(
            {"id": "open_cheapest", "title": "Open cheapest offer", "icon": "open"}
        )
        actions.append({"id": "copy_top3", "title": "Copy top 3 links", "icon": "copy"})
    actions.append({"id": "refresh", "title": "Look up again", "icon": "refresh"})

    render(
        rev,
        "detail",
        canGoBack=True,
        detail={"wide": True, "markdown": "\n".join(md_lines), "metadata": metadata},
        actions=actions,
    )


# ---------------------------------------------------------------------------
# Workflow
# ---------------------------------------------------------------------------


def run_lookup(url):
    state["last_url"] = url
    tab_id = None
    try:
        render(0, "list", loading=True, loadingText="Opening xprice.ro…", items=[])
        tab = bridge.request(
            "tabs.open", {"url": XPRICE_URL, "active": False}, timeout=20
        )
        tab_id = tab.get("id") if isinstance(tab, dict) else None
        if not isinstance(tab_id, int):
            raise RuntimeError("Chromium did not return a temporary tab id.")

        initial_tab = wait_for_tab_ready(tab_id)

        render(
            0,
            "list",
            loading=True,
            loadingText="Submitting the product link…",
            items=[],
        )
        bridge.request(
            "javascript.execute",
            {"tabId": tab_id, "code": SUBMIT_SCRIPT, "input": {"productUrl": url}},
            timeout=20,
        )

        render(
            0,
            "list",
            loading=True,
            loadingText="Waiting for the price page to load…",
            items=[],
        )
        wait_for_navigation(tab_id, initial_tab.get("url") or XPRICE_URL)
        wait_for_tab_ready(tab_id)

        render(
            0,
            "list",
            loading=True,
            loadingText="Reading price history and alternatives…",
            items=[],
        )
        execution = bridge.request(
            "javascript.execute", {"tabId": tab_id, "code": EXTRACT_SCRIPT}, timeout=30
        )
        data = execution.get("result") if isinstance(execution, dict) else None
        if not data or not data.get("offers"):
            raise RuntimeError(
                "xPrice did not return price data for this link. Make sure it is a valid product page URL."
            )

        render(
            0, "list", loading=True, loadingText="Building the price card…", items=[]
        )
        image_path = generate_image(data)

        state["last_result"] = data
        state["last_image_path"] = image_path
        render_result(0, data, image_path)
    except Exception as err:
        log("lookup failed:", repr(err))
        render_error(0, err, "Price lookup failed")
    finally:
        if isinstance(tab_id, int):
            try:
                bridge.request("tabs.close", {"tabId": tab_id}, timeout=10)
            except Exception as close_err:
                log("could not close temporary tab:", close_err)


def handle_action(item_id, action):
    try:
        if item_id == "lookup":
            url = extract_url(state.get("query", ""))
            if not url:
                render_error(
                    0,
                    "Type or paste a product link after the xprice keyword.",
                    "No product link found",
                )
                return
            run_lookup(url)
            return

        if action == "retry":
            last_url = state.get("last_url")
            if last_url:
                run_lookup(last_url)
            else:
                render_root(0, state.get("query", ""))
            return

        if action == "refresh":
            last_url = state.get("last_url")
            if last_url:
                run_lookup(last_url)
            return

        if action == "connection":
            render_connection()
            return

        if action == "refresh_status":
            render_connection()
            return

        if action == "open_cheapest":
            result = state.get("last_result") or {}
            offers = sorted(
                [o for o in (result.get("offers") or []) if o.get("price") is not None],
                key=lambda o: o["price"],
            )
            if offers and offers[0].get("url"):
                command("open", url=offers[0]["url"])
                command("hide")
            return

        if action == "copy_top3":
            result = state.get("last_result") or {}
            offers = sorted(
                [o for o in (result.get("offers") or []) if o.get("price") is not None],
                key=lambda o: o["price"],
            )[:3]
            lines = [
                f"{o['seller']} - {o['price']:.2f} RON - {o['url']}" for o in offers
            ]
            command("copy", text="\n".join(lines))
            return

        if action == "copy_token" and bridge.token:
            command("copy", text=bridge.token)
            command("toast", text="Pairing token copied", style="success")
            return

        if action == "copy_address":
            command("copy", text=f"127.0.0.1:{bridge.port}")
            return
    except Exception as err:
        log("action failed:", repr(err))
        render_error(0, err, "Action failed")


def handle_back():
    render_root(0, state.get("query", ""))


def bridge_start():
    try:
        bridge.refresh_status()
    except Exception as err:
        log("initial status fetch failed:", err)


def handle_line(msg):
    msg_type = msg.get("type")
    if msg_type == "close":
        shutdown()
        return
    if msg_type == "browserBridge":
        bridge.handle_host_message(msg)
        return
    if msg_type in ("init", "query"):
        text = msg.get("text")
        if text is None:
            text = msg.get("query", "")
        state["query"] = text or ""
        rev = msg.get("rev", 0)
        threading.Thread(
            target=render_root, args=(rev, state["query"]), daemon=True
        ).start()
        return
    if msg_type == "action":
        item_id = str(msg.get("id") or "")
        action = msg.get("action") or "default"
        threading.Thread(
            target=handle_action, args=(item_id, action), daemon=True
        ).start()
        return
    if msg_type == "back":
        threading.Thread(target=handle_back, daemon=True).start()
        return


_shutting_down = False


def shutdown():
    global _shutting_down
    if _shutting_down:
        return
    _shutting_down = True
    sys.exit(0)


def main():
    threading.Thread(target=bridge_start, daemon=True).start()
    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            log("ignoring malformed launcher message")
            continue
        handle_line(msg)
    shutdown()


if __name__ == "__main__":
    main()
