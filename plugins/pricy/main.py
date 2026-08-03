#!/usr/bin/env python3
"""Tabame launcher plugin for current prices and Pricy price history.

Usage: type ``pricy <product-url>`` and press Enter.
"""

from __future__ import annotations

import concurrent.futures
import functools
import http.server
import io
import json
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

from PIL import Image
from pricy_render import render_price_card

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(HERE, ".cache")
IMAGE_NAME = "pricy-comparison.png"
PRICY_BASE = "https://www.pricy.ro"

CHROME_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)

ENDPOINTS = {
    "lowest": "/api/extension/currentlowestprice",
    "alternatives": "/api/extension/alternatives",
    "history": "/ExtensionHtml/GetPriceHistory",
}


class PricyError(Exception):
    """An expected request or response error that can be shown to the user."""


class _ImageHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, _format, *_args):
        return


STATE: dict[str, Any] = {
    "theme": {"dark": True},
    "last_url": "",
    "last_data": None,
    "image_server": None,
    "stop": threading.Event(),
}


def send(frame: dict[str, Any]) -> None:
    """Write exactly one protocol frame/command to stdout."""
    sys.stdout.write(
        json.dumps(frame, ensure_ascii=False, separators=(",", ":")) + "\n"
    )
    sys.stdout.flush()


def log(*values: Any) -> None:
    print(*values, file=sys.stderr, flush=True)


def _image_url() -> str | None:
    server = STATE.get("image_server")
    if server is None:
        try:
            handler = functools.partial(_ImageHandler, directory=CACHE_DIR)
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            STATE["image_server"] = server
        except OSError as exc:
            log("image server failed:", exc)
            return None
    return (
        f"http://127.0.0.1:{server.server_address[1]}/{IMAGE_NAME}?t={time.time_ns()}"
    )


def _stop_image_server() -> None:
    server = STATE.get("image_server")
    if server is not None:
        try:
            server.shutdown()
            server.server_close()
        except OSError:
            pass
        STATE["image_server"] = None


def _format_error(value: Any) -> str:
    message = str(value).strip() or "Unknown error"
    message = message.replace("`", "'")
    return message[:1200]


def _error_frame(rev: int, message: Any) -> None:
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "inputMode": "submit",
            "placeholder": "Paste a product URL",
            "detail": {
                "markdown": "# Could not load that\n\n" + _format_error(message),
            },
        }
    )


def _instructions_frame(rev: int) -> None:
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "inputMode": "submit",
            "placeholder": "Paste a product URL",
            "detail": {
                "markdown": (
                    "# Pricy\n\n"
                    "Compare a product across Romanian stores. Paste a product URL "
                    "and press **Enter**.\n\n"
                    "The result includes the current lowest price, store alternatives, "
                    "and a 365-day price history graph."
                )
            },
        }
    )


def _loading_frame(rev: int, product_url: str) -> None:
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "inputMode": "submit",
            "loading": True,
            "loadingText": "Fetching prices and price history...",
            "placeholder": "Paste a product URL",
            "detail": {
                "markdown": f"# Checking price\n\n`{product_url}`",
            },
        }
    )


def _normalize_product_url(text: Any) -> str:
    value = str(text or "").strip()
    if not value:
        raise PricyError("Paste a product URL after `pricy`.")
    if any(character.isspace() for character in value):
        raise PricyError("The product URL must not contain spaces.")
    if "://" not in value:
        value = "https://" + value
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme.lower() not in ("http", "https") or not parsed.hostname:
        raise PricyError("Use a complete HTTP or HTTPS product URL.")
    return value


def _request_json(endpoint_name: str, product_url: str) -> Any:
    params: list[tuple[str, str]] = [("url", product_url), ("currency", "1")]
    if endpoint_name == "alternatives":
        params.append(("includeUrls", "true"))
    elif endpoint_name == "history":
        params.append(("period", "365"))

    query = urllib.parse.urlencode(params)
    request = urllib.request.Request(
        PRICY_BASE + ENDPOINTS[endpoint_name] + "?" + query,
        headers={
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "en-US,en;q=0.9",
            "Referer": product_url,
            "User-Agent": CHROME_USER_AGENT,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            raw = response.read()
    except urllib.error.HTTPError as exc:
        raise PricyError(f"{endpoint_name} returned HTTP {exc.code}.") from exc
    except urllib.error.URLError as exc:
        raise PricyError(f"Could not reach {endpoint_name}: {exc.reason}.") from exc
    try:
        return json.loads(raw.decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise PricyError(f"{endpoint_name} returned invalid JSON.") from exc


def _fetch_payloads(product_url: str) -> tuple[dict[str, Any], list[str]]:
    payloads: dict[str, Any] = {}
    errors: dict[str, str] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        futures = {
            executor.submit(_request_json, name, product_url): name
            for name in ENDPOINTS
        }
        for future in concurrent.futures.as_completed(futures):
            name = futures[future]
            try:
                payloads[name] = future.result()
            except Exception as exc:
                errors[name] = _format_error(exc)
                log(f"{name} request failed:", exc)

    if "lowest" in errors and "alternatives" in errors:
        raise PricyError("Pricy could not return the current price or alternatives.")
    warnings = [
        f"{name.capitalize()} unavailable: {message}"
        for name, message in errors.items()
    ]
    return payloads, warnings


def _unwrap(payload: Any, keys: tuple[str, ...]) -> Any:
    current = payload
    for _ in range(3):
        if isinstance(current, dict):
            for key in keys:
                if key in current:
                    current = current[key]
                    break
            else:
                break
        else:
            break
    return current


def _number(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        text = str(value).strip()
        if "," in text and "." not in text:
            text = text.replace(",", ".")
        else:
            text = text.replace(",", "")
        number = float(text)
        return number if number == number else None
    except (TypeError, ValueError):
        return None


def _bool(value: Any, default: bool = True) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        if value.strip().lower() in ("false", "0", "no", "n"):
            return False
        if value.strip().lower() in ("true", "1", "yes", "y"):
            return True
    if value is None:
        return default
    return bool(value)


def _host_from_url(value: Any) -> str:
    if not isinstance(value, str) or not value:
        return ""
    parsed = urllib.parse.urlsplit(value if "://" in value else "//" + value)
    host = parsed.hostname or ""
    return host.lower().removeprefix("www.")


def _domain(record: dict[str, Any]) -> str:
    from_url = _host_from_url(record.get("originalUrl") or record.get("original_url"))
    if from_url:
        return from_url
    store = str(record.get("store") or "").strip().lower()
    return _host_from_url(store) or store.removeprefix("www.")


def _record(record: Any, fallback_currency: str = "RON") -> dict[str, Any] | None:
    if not isinstance(record, dict):
        return None
    price = _number(record.get("price"))
    if price is None:
        return None
    result = dict(record)
    result["price"] = price
    result["currency"] = str(record.get("currency") or fallback_currency).upper()
    result["store"] = str(record.get("store") or "Unknown store")
    result["domain"] = _domain(result)
    result["isAvailable"] = _bool(record.get("isAvailable"), True)
    result["isSecondHand"] = _bool(record.get("isSecondHand"), False)
    return result


def _alternatives(payload: Any) -> list[dict[str, Any]]:
    raw = _unwrap(payload, ("alternatives", "items", "results", "data"))
    if not isinstance(raw, list):
        return []
    records = [item for item in (_record(value) for value in raw) if item is not None]
    return sorted(
        records,
        key=lambda item: (
            not bool(item.get("isAvailable", True)),
            bool(item.get("isSecondHand", False)),
            float(item.get("price", float("inf"))),
        ),
    )


def _lowest(payload: Any) -> dict[str, Any] | None:
    raw = _unwrap(payload, ("lowestPrice", "currentLowestPrice", "result", "data"))
    if isinstance(raw, list):
        raw = raw[0] if raw else None
    return _record(raw) if raw else None


def _history(payload: Any) -> list[dict[str, Any]]:
    raw = _unwrap(payload, ("priceHistory", "history", "items", "data"))
    if not isinstance(raw, list):
        return []
    result = []
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        price = _number(entry.get("price"))
        timestamp = entry.get("timestamp") or entry.get("date") or entry.get("time")
        if price is not None and timestamp is not None:
            result.append({"timestamp": timestamp, "price": price})
    return result


def _redirect_url(record: dict[str, Any]) -> str:
    for key in ("originalUrl", "original_url", "url"):
        value = record.get(key)
        if not isinstance(value, str) or not value:
            continue
        absolute = urllib.parse.urljoin(PRICY_BASE, value)
        parsed = urllib.parse.urlsplit(absolute)
        if parsed.scheme in ("http", "https") and parsed.netloc:
            return absolute
    url_id = record.get("urlId")
    if url_id:
        return f"{PRICY_BASE}/r/{urllib.parse.quote(str(url_id), safe='')}?source=AlternativeProducts"
    return ""


def _logo_url(domain: str) -> str:
    if not re.fullmatch(r"[a-z0-9.-]+", domain or ""):
        return ""
    return f"https://productimages.pricy.ro/favicons/{domain}.png"


def _fetch_logo(domain: str):
    url = _logo_url(domain)
    if not url:
        return None
    request = urllib.request.Request(url, headers={"User-Agent": CHROME_USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=6) as response:
            raw = response.read(512 * 1024 + 1)
        if len(raw) > 512 * 1024:
            return None
        return Image.open(io.BytesIO(raw)).convert("RGBA")
    except Exception as exc:
        log(f"logo unavailable for {domain}:", exc)
        return None


def _fetch_logos(records: list[dict[str, Any]]) -> dict[str, Any]:
    domains = sorted(
        {str(record.get("domain") or "") for record in records if record.get("domain")}
    )
    if not domains:
        return {}
    result: dict[str, Any] = {}
    with concurrent.futures.ThreadPoolExecutor(
        max_workers=min(8, len(domains))
    ) as executor:
        futures = {executor.submit(_fetch_logo, domain): domain for domain in domains}
        for future in concurrent.futures.as_completed(futures):
            domain = futures[future]
            try:
                result[domain] = future.result()
            except Exception as exc:
                log(f"logo task failed for {domain}:", exc)
                result[domain] = None
    return result


def _metadata_row(label: str, record: dict[str, Any], url: str = "") -> dict[str, Any]:
    row: dict[str, Any] = {
        "label": label,
        "text": f"{record.get('store', 'Unknown store')} - {record.get('price', 0):,.2f} {record.get('currency', 'RON')}",
        "icon": "shop",
    }
    logo = _logo_url(str(record.get("domain") or ""))
    if logo:
        row["image"] = logo
        row["width"] = 48
        row["height"] = 48
    if url:
        row["url"] = url
    return row


def _result_frame(rev: int, data: dict[str, Any]) -> None:
    lowest = data["lowest"]
    product_url = data["product_url"]
    image_url = _image_url()
    markdown = "# Price comparison\n\n"
    if image_url:
        markdown += f"![Pricy price comparison]({image_url})\n\n"
    else:
        markdown += "The comparison image was generated, but the local image server could not be started.\n\n"
    markdown += f"Product: <{product_url}>\n\nData: [Pricy.ro]({PRICY_BASE})"

    metadata: list[dict[str, Any]] = [
        _metadata_row("Lowest price", lowest, _redirect_url(lowest)),
        {
            "label": "Store",
            "text": lowest.get("store", "Unknown store"),
            "icon": "shop",
        },
        {"separator": True},
    ]
    for index, alternative in enumerate(data["top_alternatives"], start=1):
        metadata.append(
            _metadata_row(
                f"Alternative #{index}", alternative, _redirect_url(alternative)
            )
        )
    if data["warnings"]:
        metadata.append({"separator": True})
        metadata.append(
            {"label": "Note", "text": "; ".join(data["warnings"]), "icon": "info"}
        )

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "inputMode": "submit",
            "placeholder": "Paste another product URL",
            "detail": {"wide": True, "markdown": markdown, "metadata": metadata},
            "actions": [
                {
                    "id": "refresh",
                    "title": "Refresh prices",
                    "icon": "refresh",
                    "shortcut": "ctrl+r",
                },
                {
                    "id": "open-lowest",
                    "title": "Open lowest-price store",
                    "icon": "open",
                },
                {"id": "copy-url", "title": "Copy product URL", "icon": "copy"},
            ],
        }
    )


def _process(rev: int, text: Any) -> None:
    product_url = _normalize_product_url(text)
    STATE["last_url"] = product_url
    _loading_frame(rev, product_url)

    payloads, warnings = _fetch_payloads(product_url)
    alternatives = _alternatives(payloads.get("alternatives"))
    lowest = _lowest(payloads.get("lowest"))
    if lowest is None and alternatives:
        lowest = dict(alternatives[0])
    if lowest is None:
        raise PricyError(
            "Pricy did not return a current lowest price for this product."
        )
    if not alternatives:
        alternatives = [dict(lowest)]
    elif not any(item.get("domain") == lowest.get("domain") for item in alternatives):
        alternatives = [dict(lowest), *alternatives]

    history = _history(payloads.get("history"))
    logo_records = [lowest, *alternatives[:9]]
    logos = _fetch_logos(logo_records)
    output_path = os.path.join(CACHE_DIR, IMAGE_NAME)
    render_price_card(
        output_path,
        product_url,
        lowest,
        alternatives,
        history,
        logos,
        STATE.get("theme"),
    )
    data = {
        "product_url": product_url,
        "lowest": lowest,
        "alternatives": alternatives,
        "top_alternatives": alternatives[:3],
        "history": history,
        "warnings": warnings,
        "image_path": output_path,
    }
    STATE["last_data"] = data
    _result_frame(rev, data)


def _handle_action(action: Any) -> None:
    action_id = str(action or "default")
    data = STATE.get("last_data")
    if action_id == "refresh" and STATE.get("last_url"):
        try:
            _process(0, STATE["last_url"])
        except Exception as exc:
            log("refresh failed:", exc)
            _error_frame(0, exc)
        return
    if not data:
        return
    if action_id == "open-lowest":
        url = _redirect_url(data["lowest"])
        if url:
            send({"type": "command", "command": "open", "url": url})
            send({"type": "command", "command": "hide"})
    elif action_id == "copy-url":
        send({"type": "command", "command": "copy", "text": data["product_url"]})
        send({"type": "command", "command": "toast", "text": "Product URL copied"})


def _handle_message(message: dict[str, Any]) -> bool:
    message_type = message.get("type")
    if message_type == "close":
        STATE["stop"].set()
        return False
    if message_type == "init":
        theme = message.get("theme")
        if isinstance(theme, dict):
            STATE["theme"] = theme
        initial_text = str(message.get("query") or "").strip()
        if initial_text:
            try:
                _process(0, initial_text)
            except Exception as exc:
                log("initial request failed:", exc)
                _error_frame(0, exc)
        else:
            _instructions_frame(0)
        return True
    if message_type == "submitQuery":
        try:
            _process(int(message.get("rev") or 0), message.get("text", ""))
        except Exception as exc:
            log("request failed:", exc)
            _error_frame(int(message.get("rev") or 0), exc)
        return True
    if message_type == "action":
        _handle_action(message.get("action"))
        return True
    if message_type == "back":
        _instructions_frame(0)
        return True
    # In submit mode keystrokes are intentionally not fetched one by one.
    return True


def main() -> None:
    try:
        for line in sys.stdin:
            if STATE["stop"].is_set():
                break
            line = line.strip()
            if not line:
                continue
            try:
                message = json.loads(line)
            except json.JSONDecodeError as exc:
                log("ignoring malformed input:", exc)
                continue
            if not isinstance(message, dict):
                log("ignoring non-object input")
                continue
            try:
                if not _handle_message(message):
                    break
            except Exception as exc:
                log("message handler failed:", exc)
                _error_frame(int(message.get("rev") or 0), exc)
    finally:
        _stop_image_server()


if __name__ == "__main__":
    main()
