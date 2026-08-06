#!/usr/bin/env python3
"""
xPrice Dashboard - a native Tabame dashboard plugin.

Usage: type xprice2 <product url> in the launcher.

The lookup flow intentionally mirrors plugins/xprice:
  1. Open xprice.ro in a temporary inactive browser tab.
  2. Submit the product URL through Tabame's browser bridge.
  3. Extract JSON-LD product data, store offers, and price history.
  4. Render the result with native dashboard, detail, chart, and table views.
"""

import json
import os
import queue
import re
import sys
import threading
import time
import urllib.request
from datetime import datetime
from html import unescape
from itertools import count

XPRICE_URL = "https://xprice.ro/"
REQUEST_TIMEOUT = 30
READY_TIMEOUT = 20
NAV_TIMEOUT = 25

URL_RE = re.compile(r"https?://\S+")

# ---------------------------------------------------------------------------
# Site-specific browser scripts
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
const nativeSetter = Object.getOwnPropertyDescriptor(
  window.HTMLInputElement.prototype,
  "value"
).set;
nativeSetter.call(field, targetUrl);
field.dispatchEvent(new Event("input", { bubbles: true }));
field.dispatchEvent(new Event("change", { bubbles: true }));
const form = field.closest("form");
if (!form) {
  throw new Error("Could not find the search form on xprice.ro.");
}
const submitBtn = form.querySelector(
  'button[type="submit"], input[type="submit"]'
);
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
const ldScripts = Array.from(
  document.querySelectorAll('script[type="application/ld+json"]')
);
for (const node of ldScripts) {
  try {
    const parsed = JSON.parse(node.textContent);
    if (parsed && parsed["@type"] === "Product") {
      product = parsed;
      break;
    }
  } catch (err) {
    // Ignore malformed JSON-LD blocks.
  }
}

if (!product) {
  throw new Error("This does not look like an xPrice product history page.");
}

const metaDescription = document.querySelector('meta[name="description"]');
const rawOffers = (product.offers && product.offers.offers) || [];
const offers = rawOffers
  .map((offer) => ({
    seller:
      offer.seller && offer.seller.name ? offer.seller.name : "Magazin",
    price: toNumber(offer.price),
    url: offer.url || null,
  }))
  .filter((offer) => offer.price !== null && offer.url);

const bars = Array.from(document.querySelectorAll(".hist-graph .bar"))
  .map((el) => {
    const date = el.getAttribute("data-date");
    const intPart = toNumber(el.getAttribute("data-price-int"));
    const decPart = toNumber(el.getAttribute("data-price-decimals")) || 0;
    const price = intPart === null ? null : intPart + decPart / 100;
    return { date, price };
  })
  .filter((point) => point.date && point.price !== null);

return {
  name: product.name || document.title,
  description:
    product.description ||
    (metaDescription && metaDescription.content) ||
    null,
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
    return {key: value for key, value in kwargs.items() if value is not None}


def truncate(value, max_len):
    value = str(value or "")
    return value if len(value) <= max_len else value[: max_len - 1] + "\u2026"


def escape_markdown(value):
    text = str(value or "").replace(chr(96), "\\" + chr(96))
    return re.sub(r"([\\*_{}\[\]()#+!|>])", r"\\\1", text)


def extract_url(text):
    match = URL_RE.search((text or "").strip())
    return match.group(0) if match else None


def clean_description(value, max_len=720):
    text = unescape(str(value or ""))
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return truncate(text, max_len)


def compact_date(value):
    value = str(value or "")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed.strftime("%d.%m")
    except (TypeError, ValueError):
        return value[:10]


def sorted_offers(data):
    return sorted(
        [
            offer
            for offer in (data.get("offers") or [])
            if offer.get("price") is not None
        ],
        key=lambda offer: offer["price"],
    )


class BrowserBridge:
    """Adapter for Tabame's app-owned Chromium bridge."""

    def __init__(self):
        self._pending = {}
        self._lock = threading.Lock()
        self._counter = count()
        self.enabled = False
        self.running = False
        self.connected = False
        self.port = 17373
        self.token = ""
        self.start_error = None

    def call_host(self, op, fields=None, timeout=REQUEST_TIMEOUT):
        fields = fields or {}
        request_id = (
            f"xprice2-{os.getpid()}-{int(time.time() * 1000)}-"
            f"{next(self._counter)}"
        )
        response_queue = queue.Queue(maxsize=1)
        with self._lock:
            self._pending[request_id] = response_queue
        command(
            "browserBridge",
            op=op,
            requestId=request_id,
            timeoutMs=int(timeout * 1000),
            **fields,
        )
        try:
            ok, payload = response_queue.get(timeout=timeout + 2)
        except queue.Empty:
            with self._lock:
                self._pending.pop(request_id, None)
            raise TimeoutError(f"Tabame browser bridge timed out: {op}")
        if not ok:
            raise RuntimeError(payload or "Browser bridge request failed")
        return payload

    def request(self, method, params=None, timeout=REQUEST_TIMEOUT):
        return self.call_host(
            "request",
            {"method": method, "params": params or {}},
            timeout,
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
        if status.get("port") is not None:
            try:
                self.port = int(status["port"])
            except (TypeError, ValueError):
                pass
        token = status.get("token")
        if isinstance(token, str):
            self.token = token

        if status.get("error"):
            self.start_error = str(status["error"])
        elif not self.enabled:
            self.start_error = (
                "The persistent browser connector is disabled. "
                "Enable it in Launcher Plugins."
            )
        elif not self.running:
            self.start_error = "The persistent browser connector is starting."
        else:
            self.start_error = None

    def handle_host_message(self, message):
        request_id = message.get("requestId")
        if request_id:
            with self._lock:
                response_queue = self._pending.pop(request_id, None)
            if response_queue is not None:
                ok = bool(message.get("ok"))
                response_queue.put(
                    (
                        ok,
                        message.get("result")
                        if ok
                        else message.get("error"),
                    )
                )
            return
        if message.get("event") == "connection.changed":
            self.apply_status(message.get("data") or {})


bridge = BrowserBridge()
state = {
    "query": "",
    "last_url": None,
    "last_result": None,
}

# ---------------------------------------------------------------------------
# Tab lifecycle
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
        current_url = tab.get("url") or ""
        if current_url and current_url != original_url:
            if tab.get("status") == "complete":
                return tab
        time.sleep(0.3)
    raise TimeoutError(
        "xprice.ro did not redirect to a product page. "
        "Check that the link is valid."
    )

# ---------------------------------------------------------------------------
# Native dashboard rendering
# ---------------------------------------------------------------------------


def render_root(rev, text):
    url = extract_url(text)
    if url:
        item = {
            "id": "lookup",
            "title": "Open xPrice dashboard",
            "subtitle": truncate(url, 90),
            "icon": "chart",
            "actions": [
                {
                    "id": "default",
                    "title": "Open dashboard",
                    "icon": "chart",
                }
            ],
        }
        render(
            rev,
            "list",
            page={
                "id": "xprice2:home",
                "title": "xPrice Dashboard",
                "history": "replace",
            },
            items=[item],
            placeholder="Paste a product URL\u2026",
            emptyText="Paste a product link to compare its prices",
        )
        return

    render(
        rev,
        "list",
        page={
            "id": "xprice2:home",
            "title": "xPrice Dashboard",
            "history": "replace",
        },
        items=[],
        placeholder="Paste a product URL\u2026",
        empty={
            "icon": "chart",
            "title": "Compare a product",
            "hint": "Paste an eMAG, Altex, PC Garage, or other product URL.",
        },
    )


def render_error(rev, error, title):
    render(
        rev,
        "detail",
        canGoBack=True,
        detail={
            "markdown": (
                f"# {title}\n\n"
                f"{escape_markdown(str(error))}\n\n"
                "Open **Connection & pairing** if the browser connector "
                "is disabled or offline."
            )
        },
        actions=[
            {"id": "retry", "title": "Try again", "icon": "refresh"},
            {
                "id": "connection",
                "title": "Connection & pairing",
                "icon": "key",
            },
        ],
    )


def render_connection():
    try:
        bridge.refresh_status()
    except Exception as err:
        log("status refresh failed:", err)

    token_display = (
        " ".join(bridge.token[i : i + 6] for i in range(0, len(bridge.token), 6))
        if bridge.token
        else "Not available while the connector is disabled"
    )
    if not bridge.enabled:
        markdown = (
            "# Persistent browser connector is off\n\n"
            "Open **Launcher Plugins** and enable **Persistent browser connector**."
        )
    elif bridge.connected:
        markdown = (
            "# Browser connector is online\n\n"
            "xprice2 can now open xprice.ro and read product pages.\n\n"
            "Use **Escape** to go back."
        )
    else:
        markdown = (
            "# Pair the Chromium extension\n\n"
            "1. Load tabame-extension from chrome://extensions.\n"
            "2. Enable Allow User Scripts if shown.\n"
            "3. Click the Tabame Connector toolbar icon.\n"
            "4. Paste the token below and keep the default port.\n"
            "5. Click Save & connect.\n\n"
            "### Pairing token\n\n"
            f"    {token_display}"
        )

    status_text = (
        "Disabled"
        if not bridge.enabled
        else ("Connected" if bridge.connected else "Waiting for extension")
    )
    status_color = (
        "#929AA5"
        if not bridge.enabled
        else ("#7FC58B" if bridge.connected else "#D6A467")
    )
    metadata = [
        meta(label="Status", text=status_text, color=status_color),
        meta(label="Address", text=f"127.0.0.1:{bridge.port}", icon="server"),
    ]
    if bridge.start_error:
        metadata.append(
            meta(label="Bridge error", text=bridge.start_error, color="#D57C78")
        )

    actions = []
    if bridge.enabled and bridge.token:
        actions.append(
            {"id": "copy_token", "title": "Copy pairing token", "icon": "key"}
        )
    actions.extend(
        [
            {"id": "copy_address", "title": "Copy bridge address", "icon": "copy"},
            {"id": "refresh_status", "title": "Refresh status", "icon": "refresh"},
        ]
    )
    render(
        0,
        "detail",
        canGoBack=True,
        detail={"markdown": markdown, "metadata": metadata},
        actions=actions,
    )


def dashboard_summary(data, offers, history):
    name = data.get("name") or "Produs"
    description = clean_description(data.get("description"))
    best_offer = offers[0] if offers else None
    best_price = best_offer["price"] if best_offer else None

    if description:
        markdown = f"# {escape_markdown(name)}\n\n{escape_markdown(description)}"
    else:
        markdown = (
            f"# {escape_markdown(name)}\n\n"
            "Descrierea nu este disponibilă pentru acest produs."
        )

    metadata = [
        meta(
            label="Cel mai bun preț",
            text=f"{best_price:.2f} RON" if best_price is not None else "Nespecificat",
            color="#7FC58B",
        ),
        meta(
            label="Magazin",
            text=best_offer.get("seller") if best_offer else "Nespecificat",
            icon="shop",
        ),
        meta(label="Alternative", text=f"{len(offers)} magazine", icon="cart"),
    ]
    if history:
        metadata.append(
            meta(label="Istoric", text=f"{len(history)} puncte", icon="chart")
        )
        metadata.append(
            meta(
                label="Interval",
                text=(
                    f"{compact_date(history[0].get('date'))} - "
                    f"{compact_date(history[-1].get('date'))}"
                ),
                icon="calendar",
            )
        )
    if data.get("lowPrice") is not None or data.get("highPrice") is not None:
        metadata.append({"separator": True})
        if data.get("lowPrice") is not None:
            metadata.append(
                meta(label="Minim xPrice", text=f"{data['lowPrice']:.2f} RON")
            )
        if data.get("highPrice") is not None:
            metadata.append(
                meta(label="Maxim xPrice", text=f"{data['highPrice']:.2f} RON")
            )
    return markdown, metadata


def dashboard_chart_panel(history):
    if len(history) < 2:
        return {
            "id": "history",
            "title": "Istoric preț",
            "height": 180,
            "view": "detail",
            "elementId": "history-empty",
            "detail": {
                "markdown": (
                    "Nu există suficiente date pentru a desena istoricul "
                    "prețului."
                )
            },
        }

    values = [point["price"] for point in history]
    period = (
        f"{compact_date(history[0].get('date'))} - "
        f"{compact_date(history[-1].get('date'))}"
    )
    return {
        "id": "history",
        "title": f"Istoric preț · {period}",
        "height": 280,
        "view": "chart",
        "elementId": "history-chart",
        "chart": {
            "title": "Cum s-a schimbat prețul",
            "series": [
                {
                    "id": "price",
                    "label": "RON",
                    "values": values,
                    "color": "#73A9D2",
                }
            ],
        },
    }


def dashboard_offers_panel(offers):
    columns = [
        {"id": "title", "label": "Magazin"},
        {"id": "price", "label": "Preț", "align": "end"},
        {"id": "difference", "label": "Față de minim", "align": "end"},
    ]
    best_price = offers[0]["price"] if offers else None
    items = []
    for index, offer in enumerate(offers):
        price = offer["price"]
        difference = (
            "minim"
            if index == 0 or best_price is None
            else f"+{price - best_price:.2f} RON"
        )
        items.append(
            {
                "id": f"offer-{index}",
                "title": offer.get("seller") or "Magazin",
                "subtitle": "Cel mai ieftin" if index == 0 else "",
                "icon": "shop",
                "cells": {
                    "price": f"{price:.2f} RON",
                    "difference": difference,
                },
                "actions": [
                    {"id": "default", "title": "Deschide oferta", "icon": "open"},
                    {"id": "copy", "title": "Copiază linkul", "icon": "copy"},
                ],
            }
        )
    return {
        "id": "offers",
        "title": "Compară magazinele",
        "height": max(220, 76 + len(items) * 44),
        "view": "table",
        "elementId": "offers-table",
        "columns": columns,
        "items": items,
    }


def render_dashboard(rev, data, history_mode="push"):
    offers = sorted_offers(data)
    history = [
        point
        for point in (data.get("history") or [])
        if point.get("price") is not None
    ]
    name = data.get("name") or "Produs"
    summary_markdown, summary_metadata = dashboard_summary(data, offers, history)
    panels = [
        {
            "id": "summary",
            "title": "Produs",
            "height": 240,
            "view": "detail",
            "elementId": "product-summary",
            "detail": {
                "markdown": summary_markdown,
                "metadata": summary_metadata,
            },
        },
        dashboard_chart_panel(history),
        dashboard_offers_panel(offers),
    ]
    actions = [
        {"id": "open_product", "title": "Deschide pagina xPrice", "icon": "open"},
        {"id": "copy_top3", "title": "Copiază top 3 linkuri", "icon": "copy"},
    ]
    render(
        rev,
        "dashboard",
        page={
            "id": "xprice2:product",
            "title": name,
            "history": history_mode,
            "preserveState": True,
            "breadcrumbs": [{"id": "xprice2:home", "label": "Lookup"}],
        },
        elementId="product-dashboard",
        placeholder="Paste another product URL\u2026",
        dashboard={"layout": "stack", "panels": panels},
        actions=actions,
        floatingAction={"id": "refresh", "title": "Refresh prices", "icon": "refresh"},
    )

# ---------------------------------------------------------------------------
# Workflow
# ---------------------------------------------------------------------------


def run_lookup(url, history_mode="push"):
    state["last_url"] = url
    tab_id = None
    try:
        render(0, "list", loading=True, loadingText="Opening xprice.ro\u2026", items=[])
        tab = bridge.request(
            "tabs.open",
            {"url": XPRICE_URL, "active": False},
            timeout=20,
        )
        tab_id = tab.get("id") if isinstance(tab, dict) else None
        if not isinstance(tab_id, int):
            raise RuntimeError("Chromium did not return a temporary tab id.")

        initial_tab = wait_for_tab_ready(tab_id)
        render(
            0,
            "list",
            loading=True,
            loadingText="Submitting the product link\u2026",
            items=[],
        )
        bridge.request(
            "javascript.execute",
            {
                "tabId": tab_id,
                "code": SUBMIT_SCRIPT,
                "input": {"productUrl": url},
            },
            timeout=20,
        )

        render(
            0,
            "list",
            loading=True,
            loadingText="Waiting for the price page to load\u2026",
            items=[],
        )
        wait_for_navigation(tab_id, initial_tab.get("url") or XPRICE_URL)
        wait_for_tab_ready(tab_id)

        render(
            0,
            "list",
            loading=True,
            loadingText="Reading history and store alternatives\u2026",
            items=[],
        )
        execution = bridge.request(
            "javascript.execute",
            {"tabId": tab_id, "code": EXTRACT_SCRIPT},
            timeout=30,
        )
        data = execution.get("result") if isinstance(execution, dict) else None
        if not data or not data.get("offers"):
            raise RuntimeError(
                "xPrice did not return price data for this link. "
                "Make sure it is a valid product page URL."
            )

        state["last_result"] = data
        render_dashboard(0, data, history_mode=history_mode)
    except Exception as err:
        log("lookup failed:", repr(err))
        render_error(0, err, "Price lookup failed")
    finally:
        if isinstance(tab_id, int):
            try:
                bridge.request("tabs.close", {"tabId": tab_id}, timeout=10)
            except Exception as close_err:
                log("could not close temporary tab:", close_err)


def offer_for_id(item_id):
    if not item_id.startswith("offer-"):
        return None
    try:
        index = int(item_id[len("offer-") :])
    except ValueError:
        return None
    offers = sorted_offers(state.get("last_result") or {})
    return offers[index] if 0 <= index < len(offers) else None


def handle_action(item_id, action):
    try:
        if item_id == "lookup":
            url = extract_url(state.get("query", ""))
            if not url:
                render_error(
                    0,
                    "Type or paste a product link after the xprice2 keyword.",
                    "No product link found",
                )
                return
            run_lookup(url, history_mode="push")
            return

        if action == "retry":
            last_url = state.get("last_url")
            if last_url:
                run_lookup(last_url, history_mode="replace")
            else:
                render_root(0, state.get("query", ""))
            return

        if action == "refresh":
            last_url = state.get("last_url")
            if last_url:
                run_lookup(last_url, history_mode="replace")
            return

        if action == "connection" or action == "refresh_status":
            render_connection()
            return

        offer = offer_for_id(item_id)
        if offer is not None:
            if action == "copy" and offer.get("url"):
                command("copy", text=offer["url"])
                return
            if offer.get("url"):
                command("open", url=offer["url"])
                command("hide")
            return

        if action == "open_product":
            result = state.get("last_result") or {}
            if result.get("pageUrl"):
                command("open", url=result["pageUrl"])
                command("hide")
            return

        if action == "copy_top3":
            lines = [
                f"{offer['seller']} - {offer['price']:.2f} RON - {offer['url']}"
                for offer in sorted_offers(state.get("last_result") or {})[:3]
            ]
            if lines:
                command("copy", text="\n".join(lines))
            return

        if action == "copy_token" and bridge.token:
            command("copy", text=bridge.token)
            command("toast", text="Pairing token copied", style="success")
            return

        if action == "copy_address":
            command("copy", text=f"127.0.0.1:{bridge.port}")
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


def handle_line(message):
    message_type = message.get("type")
    if message_type == "close":
        shutdown()
        return
    if message_type == "browserBridge":
        bridge.handle_host_message(message)
        return
    if message_type in ("init", "query"):
        text = message.get("text")
        if text is None:
            text = message.get("query", "")
        state["query"] = text or ""
        rev = message.get("rev", 0)
        threading.Thread(
            target=render_root,
            args=(rev, state["query"]),
            daemon=True,
        ).start()
        return
    if message_type == "action":
        item_id = str(message.get("id") or "")
        action = message.get("action") or "default"
        threading.Thread(
            target=handle_action,
            args=(item_id, action),
            daemon=True,
        ).start()
        return
    if message_type == "back":
        threading.Thread(target=handle_back, daemon=True).start()
        return
    if message_type == "navigate":
        target = message.get("targetPageId")
        if target == "xprice2:home":
            threading.Thread(
                target=handle_back,
                daemon=True,
            ).start()


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
            message = json.loads(line)
        except json.JSONDecodeError:
            log("ignoring malformed launcher message")
            continue
        try:
            handle_line(message)
        except Exception as err:
            log("message handling failed:", repr(err))
    shutdown()


if __name__ == "__main__":
    main()
