#!/usr/bin/env python3
"""Tabame launcher plugin: curr [amount] [from] [to] [period]

Examples:
  curr 10 USD to eur   -> 10 USD converted to EUR, default chart period
  curr £100 to €       -> 100 GBP converted to EUR
  curr USD EUR         -> 1 USD converted to EUR
  curr eur             -> defaultAmount defaultFrom converted to EUR
  curr 10 usd eur 1y   -> same, with a 1 year rate chart
  curr watch           -> render all favorite pairs
  curr codes eu        -> browse currency codes matching "eu"

Shows a dark, trading-app style card: converted amount + rate over the
selected period, an area chart of the historical rate, and a stats row
(period high/low/open, inverse rate).

Uses the Frankfurter API (https://frankfurter.dev, ECB reference rates,
no API key) for data, renders a PNG with Pillow, and serves it over a
small local HTTP server so it can be embedded as a normal https://...
image in a markdown detail view.
"""

import sys
import os
import re
import json
import time
import calendar
import datetime
import socket
import threading
import http.server
import functools
import urllib.request
import urllib.parse
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from currency_render import render_chart, render_watchlist

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(HERE, ".cache")
os.makedirs(CACHE_DIR, exist_ok=True)

API_BASE = "https://api.frankfurter.dev/v1"
BROWSER_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)

PERIOD_PRESETS = [
    ("5d", "5D"), ("1m", "1M"), ("3m", "3M"),
    ("6m", "6M"), ("1y", "1Y"), ("5y", "5Y"),
]

CONNECTOR_WORDS = {"to", "in", "into", "as", "->", "="}

CURRENCY_SYMBOL_ALIASES = {
    "US$": "USD",
    "C$": "CAD",
    "A$": "AUD",
    "NZ$": "NZD",
    "HK$": "HKD",
    "S$": "SGD",
    "R$": "BRL",
    "€": "EUR",
    "£": "GBP",
    "₤": "GBP",
    "₹": "INR",
    "¥": "JPY",
    "￥": "JPY",
    "元": "CNY",
    "₩": "KRW",
    "₽": "RUB",
    "₺": "TRY",
    "₴": "UAH",
    "₦": "NGN",
    "₱": "PHP",
    "฿": "THB",
    "₪": "ILS",
    "₫": "VND",
    "₡": "CRC",
    "₲": "PYG",
    "₾": "GEL",
    "₸": "KZT",
    "₮": "MNT",
    "₭": "LAK",
    "₵": "GHS",
    "₨": "INR",
    "$": "USD",
}


def expand_currency_symbols(text):
    expanded = text
    for symbol, code in sorted(
        CURRENCY_SYMBOL_ALIASES.items(), key=lambda item: len(item[0]), reverse=True
    ):
        expanded = re.sub(re.escape(symbol), f" {code} ", expanded, flags=re.IGNORECASE)
    return expanded


def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# --------------------------------------------------------------------------
# Tiny local image server (127.0.0.1 only) so a generated PNG can be
# embedded as an http:// image in markdown.
# --------------------------------------------------------------------------
class _Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass


def _free_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def start_image_server():
    port = _free_port()
    handler = functools.partial(_Handler, directory=CACHE_DIR)
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    return port


IMAGE_PORT = start_image_server()


def image_url(filename):
    return f"http://127.0.0.1:{IMAGE_PORT}/{filename}?t={int(time.time() * 1000)}"


# --------------------------------------------------------------------------
# Config
# --------------------------------------------------------------------------
def load_config():
    path = os.path.join(HERE, "config.json")
    if os.path.exists(path):
        try:
            with open(path, encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            log("config load failed:", e)
    return {}


CONFIG = load_config()
DEFAULT_FROM = (CONFIG.get("defaultFrom") or "USD").upper()
DEFAULT_TO = (CONFIG.get("defaultTo") or "EUR").upper()
DEFAULT_AMOUNT = float(CONFIG.get("defaultAmount") or 1)
DEFAULT_PERIOD = CONFIG.get("defaultPeriod") or "1m"


# --------------------------------------------------------------------------
# Query parsing: "curr [amount] [from] [to] [period]"
# --------------------------------------------------------------------------
_PERIOD_RE = re.compile(r"^\d+[dwmy]$")
_NUM_RE = re.compile(r"^-?\d+(\.\d+)?$")


def parse_query(text):
    tokens = expand_currency_symbols(text.strip()).split()

    period_token = None
    if tokens:
        last = tokens[-1].lower()
        if last in ("ytd", "max") or _PERIOD_RE.match(last):
            period_token = tokens.pop().lower()

    amount = None
    codes = []
    for tok in tokens:
        low = tok.lower()
        if low in CONNECTOR_WORDS:
            continue
        cleaned = tok.replace(",", "")
        if amount is None and _NUM_RE.match(cleaned):
            amount = float(cleaned)
            continue
        code = tok.upper()
        if code not in codes:
            codes.append(code)

    if len(codes) >= 2:
        from_code, to_code = codes[0], codes[1]
    elif len(codes) == 1:
        # A single bare code reads as "how much is my usual amount in X"
        from_code, to_code = DEFAULT_FROM, codes[0]
    else:
        from_code, to_code = DEFAULT_FROM, DEFAULT_TO

    if amount is None:
        amount = DEFAULT_AMOUNT
    if not period_token:
        period_token = DEFAULT_PERIOD

    return amount, from_code, to_code, period_token


def parse_watch_period(text):
    tokens = text.strip().lower().split()
    if len(tokens) > 1 and (tokens[1] in ("ytd", "max") or _PERIOD_RE.match(tokens[1])):
        return tokens[1]
    return DEFAULT_PERIOD


def _add_months(d, delta):
    m = d.month - 1 + delta
    y = d.year + m // 12
    m = m % 12 + 1
    day = min(d.day, calendar.monthrange(y, m)[1])
    return datetime.date(y, m, day)


def resolve_period(token):
    today = datetime.date.today()
    token = token.lower()
    if token == "ytd":
        start = datetime.date(today.year, 1, 1)
        label = "YTD"
    elif token == "max":
        start = _add_months(today, -300)
        label = "MAX"
    else:
        n = int(token[:-1])
        unit = token[-1]
        if unit == "d":
            start = today - datetime.timedelta(days=n)
            label = f"{n}D"
        elif unit == "w":
            start = today - datetime.timedelta(weeks=n)
            label = f"{n}W"
        elif unit == "m":
            start = _add_months(today, -n)
            label = f"{n}M"
        else:  # 'y'
            start = _add_months(today, -12 * n)
            label = f"{n}Y"
    end = today

    total_days = (end - start).days
    if total_days <= 14:
        tick_format = "%a %d"
    elif total_days <= 120:
        tick_format = "%b %d"
    elif total_days <= 730:
        tick_format = "%b %Y"
    else:
        tick_format = "%Y"
    return start, end, label, tick_format


# --------------------------------------------------------------------------
# Frankfurter fetch (ECB reference rates, no API key, daily granularity)
# --------------------------------------------------------------------------
def http_json(url, params=None):
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": BROWSER_UA})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode("utf-8"))


_SYMBOLS_CACHE = {"data": None, "ts": 0}


def fetch_symbols():
    if _SYMBOLS_CACHE["data"] and time.time() - _SYMBOLS_CACHE["ts"] < 3600:
        return _SYMBOLS_CACHE["data"]
    data = http_json(f"{API_BASE}/currencies")
    _SYMBOLS_CACHE["data"] = data
    _SYMBOLS_CACHE["ts"] = time.time()
    return data


def fetch_series(from_code, to_code, start, end):
    url = f"{API_BASE}/{start.isoformat()}..{end.isoformat()}"
    return http_json(url, {"base": from_code, "symbols": to_code})


def build_data(from_code, to_code, amount, raw, label, tick_format):
    rates_by_date = raw.get("rates") or {}
    if not rates_by_date:
        raise ValueError(
            f"No rate data for **{from_code}/{to_code}**. Check the currency codes and try again."
        )

    points = []
    for date_str in sorted(rates_by_date.keys()):
        day = rates_by_date[date_str]
        v = day.get(to_code)
        if v is None:
            continue
        dt = datetime.datetime.strptime(date_str, "%Y-%m-%d")
        points.append((dt, float(v)))

    if not points:
        raise ValueError(
            f"No rate data for **{from_code}/{to_code}**. Check the currency codes and try again."
        )

    rate = points[-1][1]
    period_open = points[0][1]
    period_high = max(p[1] for p in points)
    period_low = min(p[1] for p in points)
    rate_change = rate - period_open
    rate_change_pct = (rate_change / period_open * 100) if period_open else 0.0
    as_of = points[-1][0].strftime("%b %d, %Y")

    return {
        "from_code": from_code,
        "to_code": to_code,
        "amount": amount,
        "converted": amount * rate,
        "rate": rate,
        "inverse_rate": (1 / rate) if rate else 0.0,
        "rate_change": rate_change,
        "rate_change_pct": rate_change_pct,
        "period_label": label,
        "as_of": as_of,
        "points": points,
        "period_high": period_high,
        "period_low": period_low,
        "period_open": period_open,
        "tick_format": tick_format,
    }


# --------------------------------------------------------------------------
# Frame builders
# --------------------------------------------------------------------------
def instructions_frame(rev):
    lines = [
        "# Currency",
        "",
        "Type an amount and two currencies, then press **Enter**:",
        "",
        "- `curr 10 USD to EUR` — convert 10 USD to EUR",
        "- `curr £100 to €` — symbols can be before or after the amount",
        "- `curr USD EUR` — convert 1 USD to EUR",
        f"- `curr EUR` — convert your default amount of **{DEFAULT_FROM}** to EUR",
        "- `curr 10 USD EUR 1y` — with a 1 year rate chart",
        "- `curr watch` — render your favorite pairs",
        "- `curr codes eu` — browse currency codes",
        "",
        f"No input? Defaults to **{DEFAULT_AMOUNT:g} {DEFAULT_FROM} → {DEFAULT_TO}**.",
    ]
    send({
        "type": "render",
        "rev": rev,
        "view": "detail",
        "inputMode": "submit",
        "placeholder": "amount, from, to, optionally a period",
        "detail": {"markdown": "\n".join(lines)},
    })


def loading_frame(rev, from_code, to_code, label):
    send({
        "type": "render",
        "rev": rev,
        "view": "detail",
        "inputMode": "submit",
        "loading": True,
        "loadingText": f"Fetching {label} rates for {from_code}/{to_code}…",
        "detail": {"markdown": ""},
    })


def error_frame(rev, message):
    send({
        "type": "render",
        "rev": rev,
        "view": "detail",
        "inputMode": "submit",
        "placeholder": "amount, from, to, optionally a period",
        "detail": {"markdown": f"# Couldn't load that\n\n{message}"},
    })


def pair_key(from_code, to_code):
    return f"{from_code}_{to_code}"


def result_frame(rev, data, img_filename):
    url = image_url(img_filename)
    md = f"![{data['from_code']}/{data['to_code']} chart]({url})"
    actions = [
        {"id": f"period_{tok}", "title": lbl, "icon": "chart"}
        for tok, lbl in PERIOD_PRESETS
    ]
    actions.append({"id": "swap", "title": "Swap currencies", "icon": "refresh"})
    key = pair_key(data["from_code"], data["to_code"])
    watching = key in FAVORITES
    send({
        "type": "render",
        "rev": rev,
        "view": "detail",
        "inputMode": "submit",
        "placeholder": "amount, from, to, optionally a period",
        "wide": True,
        "detail": {
            "markdown": md,
            "metadata": [
                {"label": "Pair", "text": f"{data['from_code']}/{data['to_code']}"},
                {"label": "As of", "text": data["as_of"]},
                {"label": "Source", "text": "Frankfurter (ECB reference rates)"},
                {
                    "label": "Favorites",
                    "text": "Watching" if watching else "Not watched",
                    "actions": [{
                        "id": "watch_remove" if watching else "watch_add",
                        "title": "Remove from favorites" if watching else "Add to favorites",
                        "icon": "trash" if watching else "star",
                        **({"destructive": True, "confirm": True} if watching else {}),
                    }],
                },
            ],
        },
        "actions": actions,
    })


def codes_frame(rev, filter_text):
    try:
        symbols = fetch_symbols()
    except Exception as e:
        log("symbols fetch failed:", repr(e))
        error_frame(rev, "Couldn't load the currency list. Try again in a moment.")
        return
    q = filter_text.strip().lower()
    items = []
    for code, name in sorted(symbols.items()):
        if q and q not in code.lower() and q not in name.lower():
            continue
        items.append({
            "id": code,
            "title": code,
            "subtitle": name,
            "icon": "tag",
            "actions": [{"id": "default", "title": f"Convert to {code}", "icon": "open"}],
        })
    send({
        "type": "render",
        "rev": rev,
        "view": "list",
        # default (unset) inputMode streams keystrokes as `query` messages,
        # which is what we want for live filtering
        "placeholder": "filter currency codes",
        "emptyText": "No matching currencies",
        "items": items[:200],
        "canGoBack": True,
    })


# --------------------------------------------------------------------------
# Main processing
# --------------------------------------------------------------------------
FAVORITES = []  # list of "FROM_TO" strings
STATE = {
    "last_amount": DEFAULT_AMOUNT,
    "last_from": DEFAULT_FROM,
    "last_to": DEFAULT_TO,
    "last_period": DEFAULT_PERIOD,
    "last_data": None,
    "last_image": None,
    "mode": "convert",  # or "codes"
}


def save_favorites():
    send({"type": "command", "command": "storage", "op": "set", "key": "favoritePairs", "value": FAVORITES})


def render_watch(rev, text):
    period_token = parse_watch_period(text)
    if not FAVORITES:
        error_frame(rev, "Your favorites list is empty. Open a pair and use the **Add to favorites** button at the bottom.")
        return
    start, end, label, tick_format = resolve_period(period_token)
    loading_frame(rev, "your", "favorites", label)
    data_items, failures = [], []
    for key in FAVORITES:
        from_code, _, to_code = key.partition("_")
        try:
            raw = fetch_series(from_code, to_code, start, end)
            data_items.append(build_data(from_code, to_code, 1, raw, label, tick_format))
        except Exception as e:
            log("watch fetch failed:", key, repr(e))
            failures.append(key.replace("_", "/"))
    if not data_items:
        error_frame(rev, "Couldn't load any favorite pairs. Please try again.")
        return
    img_name = "watchlist.png"
    render_watchlist(data_items, os.path.join(CACHE_DIR, img_name), CACHE_DIR)
    markdown = f"![Favorites chart]({image_url(img_name)})"
    if failures:
        markdown += "\n\nCouldn't load: " + ", ".join(failures)
    send({"type": "render", "rev": rev, "view": "detail", "inputMode": "submit", "placeholder": "amount, from, to, optionally a period", "wide": True, "detail": {"markdown": markdown}})


def convert(rev, amount, from_code, to_code, period_token):
    if from_code == to_code:
        error_frame(rev, "Pick two different currencies.")
        return

    start, end, label, tick_format = resolve_period(period_token)

    STATE["last_amount"] = amount
    STATE["last_from"] = from_code
    STATE["last_to"] = to_code
    STATE["last_period"] = period_token
    STATE["mode"] = "convert"

    loading_frame(rev, from_code, to_code, label)

    try:
        raw = fetch_series(from_code, to_code, start, end)
        data = build_data(from_code, to_code, amount, raw, label, tick_format)

        img_name = "currency.png"
        render_chart(data, os.path.join(CACHE_DIR, img_name))
        STATE["last_data"] = data
        STATE["last_image"] = img_name
        result_frame(rev, data, img_name)

    except ValueError as e:
        error_frame(rev, str(e))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            error_frame(rev, f"No data found for **{from_code}/{to_code}**. Check the codes and try again — `curr codes` lists them all.")
        else:
            error_frame(rev, f"Frankfurter returned an error ({e.code}). Try again in a moment.")
    except urllib.error.URLError as e:
        error_frame(rev, f"Network error: {e}")
    except Exception as e:
        log("error:", repr(e))
        error_frame(rev, f"```\n{e}\n```")


def process(rev, text):
    stripped = text.strip()
    low = stripped.lower()
    if low == "watch" or low.startswith("watch "):
        STATE["mode"] = "convert"
        render_watch(rev, text)
        return
    if low == "codes" or low.startswith("codes "):
        STATE["mode"] = "codes"
        filter_text = stripped[len("codes"):].strip()
        codes_frame(rev, filter_text)
        return

    amount, from_code, to_code, period_token = parse_query(text)
    if not text.strip():
        instructions_frame(rev)
        return
    convert(rev, amount, from_code, to_code, period_token)


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
            send({"type": "command", "command": "storage", "op": "get", "key": "favoritePairs", "requestId": "favorites"})
            initial_text = msg.get("query", "") or ""
            if initial_text.strip():
                process(0, initial_text)
            else:
                instructions_frame(0)
        elif t == "query":
            if STATE["mode"] == "codes":
                filter_text = msg.get("text", "")
                if filter_text.lower().startswith("codes"):
                    filter_text = filter_text[len("codes"):].strip()
                codes_frame(msg.get("rev", 0), filter_text)
            # else: waiting for Enter (inputMode: submit)
        elif t == "submitQuery":
            process(msg.get("rev", 0), msg.get("text", ""))
        elif t == "action":
            item_id = msg.get("id") or ""
            action_id = msg.get("action") or ""
            if STATE["mode"] == "codes" and action_id == "default" and item_id:
                to_code = item_id.upper()
                convert(0, STATE["last_amount"], STATE["last_from"], to_code, STATE["last_period"])
            elif action_id.startswith("period_"):
                tok = action_id[len("period_"):]
                convert(0, STATE["last_amount"], STATE["last_from"], STATE["last_to"], tok)
            elif action_id == "swap":
                convert(0, STATE["last_amount"], STATE["last_to"], STATE["last_from"], STATE["last_period"])
            elif action_id == "watch_add" and STATE["last_data"]:
                key = pair_key(STATE["last_data"]["from_code"], STATE["last_data"]["to_code"])
                if key not in FAVORITES:
                    FAVORITES.append(key)
                    save_favorites()
                result_frame(0, STATE["last_data"], STATE["last_image"])
            elif action_id == "watch_remove" and STATE["last_data"]:
                key = pair_key(STATE["last_data"]["from_code"], STATE["last_data"]["to_code"])
                if key in FAVORITES:
                    FAVORITES.remove(key)
                    save_favorites()
                result_frame(0, STATE["last_data"], STATE["last_image"])
        elif t == "storage" and msg.get("requestId") == "favorites":
            stored = msg.get("value")
            if isinstance(stored, list):
                FAVORITES[:] = [str(k).upper() for k in stored if str(k).strip()]
        elif t == "back":
            STATE["mode"] = "convert"
            instructions_frame(0)


if __name__ == "__main__":
    main()
