#!/usr/bin/env python3
"""Tabame launcher plugin: stock [ticker] [period]

period examples: 1d, 5d, 2w, 2m, 1y, 5y, ytd, max
Shows a dark, trading-app style card: price + change over the selected
period, an area chart, a volume strip, and a stats row (day/52w range,
volume, previous close).

Uses Yahoo Finance's public chart endpoint (no API key) for data, renders
a PNG with Pillow, and serves it over a small local HTTP server so it can
be embedded as a normal https://... image in a markdown detail view.
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

from stock_render import render_chart, render_watchlist

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(HERE, ".cache")
os.makedirs(CACHE_DIR, exist_ok=True)

CHART_URL_TMPL = "https://query1.finance.yahoo.com/v8/finance/chart/{ticker}"
BROWSER_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)

CURRENCY_SYMBOLS = {
    "USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥",
    "CAD": "C$", "AUD": "A$", "CHF": "CHF ",
}

PERIOD_PRESETS = [
    ("1d", "1D"), ("5d", "5D"), ("1m", "1M"),
    ("6m", "6M"), ("1y", "1Y"), ("5y", "5Y"),
]


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
DEFAULT_TICKER = CONFIG.get("defaultTicker", "")
DEFAULT_PERIOD = CONFIG.get("defaultPeriod", "1m")


# --------------------------------------------------------------------------
# Query parsing: "stock [ticker] [period]"
# --------------------------------------------------------------------------
_PERIOD_RE = re.compile(r"^\d+[dwmy]$")


def parse_query(text):
    tokens = text.strip().split()
    period_token = None
    if tokens:
        last = tokens[-1].lower()
        if last in ("ytd", "max") or _PERIOD_RE.match(last):
            period_token = tokens.pop().lower()
    ticker = "".join(tokens).upper()
    if not ticker:
        ticker = DEFAULT_TICKER
    if not period_token:
        period_token = DEFAULT_PERIOD
    return ticker, period_token


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
        start = _add_months(today, -240)
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
    end = today + datetime.timedelta(days=1)

    total_days = (end - start).days
    if total_days <= 1:
        interval, tick_format = "5m", "%H:%M"
    elif total_days <= 7:
        interval, tick_format = "15m", "%a %d"
    elif total_days <= 60:
        interval, tick_format = "60m", "%b %d"
    elif total_days <= 730:
        interval, tick_format = "1d", "%b %d"
    else:
        interval, tick_format = "1wk", "%b '%y"
    return start, end, interval, label, tick_format


# --------------------------------------------------------------------------
# Yahoo Finance fetch
# --------------------------------------------------------------------------
def http_json(url, params):
    q = urllib.parse.urlencode(params)
    req = urllib.request.Request(f"{url}?{q}", headers={"User-Agent": BROWSER_UA})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_chart(ticker, start, end, interval):
    p1 = int(datetime.datetime.combine(start, datetime.time.min, tzinfo=datetime.timezone.utc).timestamp())
    p2 = int(datetime.datetime.combine(end, datetime.time.min, tzinfo=datetime.timezone.utc).timestamp())
    url = CHART_URL_TMPL.format(ticker=urllib.parse.quote(ticker))
    params = {
        "period1": p1, "period2": p2, "interval": interval,
        "includePrePost": "false", "events": "div,splits",
    }
    return http_json(url, params)


def build_data(ticker, raw, label, tick_format):
    result = (raw.get("chart") or {}).get("result") or []
    err = (raw.get("chart") or {}).get("error")
    if err or not result:
        msg = (err or {}).get("description") if err else None
        raise ValueError(msg or f"No data found for **{ticker}**. Check the symbol and try again.")

    r = result[0]
    meta = r.get("meta") or {}
    timestamps = r.get("timestamp") or []
    indicators = (r.get("indicators") or {})
    quote = (indicators.get("quote") or [{}])[0]
    closes_raw = quote.get("close") or []
    opens_raw = quote.get("open") or []
    volumes_raw = quote.get("volume") or []

    tz = None
    gmtoffset = meta.get("gmtoffset")
    if gmtoffset is not None:
        tz = datetime.timezone(datetime.timedelta(seconds=gmtoffset))

    points, volumes = [], []
    prev_close_bar = None
    for i, ts in enumerate(timestamps):
        c = closes_raw[i] if i < len(closes_raw) else None
        if c is None:
            continue
        dt = datetime.datetime.fromtimestamp(ts, tz=datetime.timezone.utc)
        if tz is not None:
            dt = dt.astimezone(tz)
        points.append((dt, c))
        v = volumes_raw[i] if i < len(volumes_raw) else 0
        o = opens_raw[i] if i < len(opens_raw) else None
        bar_up = (c >= o) if o is not None else (c >= (prev_close_bar if prev_close_bar is not None else c))
        volumes.append((dt, v or 0, bar_up))
        prev_close_bar = c

    currency = meta.get("currency", "USD")
    currency_symbol = CURRENCY_SYMBOLS.get(currency, currency + " ")

    price = meta.get("regularMarketPrice")
    if price is None:
        price = points[-1][1] if points else meta.get("previousClose", 0)
    start_price = points[0][1] if points else meta.get("previousClose", price)
    change = price - start_price
    change_pct = (change / start_price * 100) if start_price else 0.0

    rmt = meta.get("regularMarketTime")
    if rmt:
        dt = datetime.datetime.fromtimestamp(rmt, tz=datetime.timezone.utc)
        if tz is not None:
            dt = dt.astimezone(tz)
        as_of = dt.strftime("%b %d, %I:%M %p") + (f" {meta.get('timezone', '')}" if meta.get("timezone") else "")
    else:
        as_of = "Latest"

    day_high = meta.get("regularMarketDayHigh", price)
    day_low = meta.get("regularMarketDayLow", price)
    prev_close = meta.get("chartPreviousClose") or meta.get("previousClose") or start_price
    day_volume = meta.get("regularMarketVolume") or (volumes[-1][1] if volumes else 0)
    week52_high = meta.get("fiftyTwoWeekHigh", day_high)
    week52_low = meta.get("fiftyTwoWeekLow", day_low)

    return {
        "symbol": meta.get("symbol", ticker),
        "name": meta.get("longName") or meta.get("shortName") or ticker,
        "exchange": meta.get("fullExchangeName") or meta.get("exchangeName") or "",
        "currency_symbol": currency_symbol,
        "price": price,
        "change": change,
        "change_pct": change_pct,
        "period_label": label,
        "as_of": as_of,
        "points": points,
        "volumes": volumes,
        "day_high": day_high,
        "day_low": day_low,
        "prev_close": prev_close,
        "day_volume": day_volume,
        "week52_high": week52_high,
        "week52_low": week52_low,
        "tick_format": tick_format,
    }


# --------------------------------------------------------------------------
# Frame builders
# --------------------------------------------------------------------------
def instructions_frame(rev):
    lines = [
        "# Stocks",
        "",
        "Type a ticker and press **Enter**:",
        "",
        "- `stock AAPL` — default period (" + DEFAULT_PERIOD.upper() + ")",
        "- `stock AAPL 1d` — 1 day",
        "- `stock AAPL 2m` — 2 months",
        "- `stock AAPL 1y` — 1 year",
        "- `stock AAPL ytd` / `stock AAPL max`",
        "- `stock watch 1m` — render your watchlist",
    ]
    if DEFAULT_TICKER:
        lines.append("")
        lines.append(f"No ticker? Defaults to **{DEFAULT_TICKER}**.")
    send({
        "type": "render",
        "rev": rev,
        "view": "detail",
        "inputMode": "submit",
        "placeholder": "ticker, then optionally a period",
        "detail": {"markdown": "\n".join(lines)},
    })


def loading_frame(rev, ticker, label):
    send({
        "type": "render",
        "rev": rev,
        "view": "detail",
        "inputMode": "submit",
        "loading": True,
        "loadingText": f"Fetching {label} chart for {ticker}…",
        "detail": {"markdown": ""},
    })


def error_frame(rev, message):
    send({
        "type": "render",
        "rev": rev,
        "view": "detail",
        "inputMode": "submit",
        "placeholder": "ticker, then optionally a period",
        "detail": {"markdown": f"# Couldn't load that\n\n{message}"},
    })


def result_frame(rev, data, img_filename):
    url = image_url(img_filename)
    md = f"![{data['symbol']} chart]({url})"
    actions = [
        {"id": f"period_{tok}", "title": lbl, "icon": "chart"}
        for tok, lbl in PERIOD_PRESETS
    ]
    send({
        "type": "render",
        "rev": rev,
        "view": "detail",
        "inputMode": "submit",
        "placeholder": "ticker, then optionally a period",
        "wide": True,
        "detail": {
            "markdown": md,
            "metadata": [
                {"label": "Symbol", "text": data["symbol"]},
                {"label": "Exchange", "text": data["exchange"] or "-"},
                {"label": "Prev Close", "text": f"{data['currency_symbol']}{data['prev_close']:,.2f}"},
                {
                    "label": "Watchlist",
                    "text": "Watching" if data["symbol"] in WATCHLIST else "Not watched",
                    "actions": [{
                        "id": "watch_remove" if data["symbol"] in WATCHLIST else "watch_add",
                        "title": "Remove from watchlist" if data["symbol"] in WATCHLIST else "Add to watchlist",
                        "icon": "trash" if data["symbol"] in WATCHLIST else "star",
                        **({"destructive": True, "confirm": True} if data["symbol"] in WATCHLIST else {}),
                    }],
                },
            ],
        },
        "actions": actions,
    })


# --------------------------------------------------------------------------
# Main processing
# --------------------------------------------------------------------------
WATCHLIST = []
STATE = {"last_ticker": DEFAULT_TICKER, "last_period": DEFAULT_PERIOD, "last_data": None, "last_image": None}


def save_watchlist():
    send({"type": "command", "command": "storage", "op": "set", "key": "watchlist", "value": WATCHLIST})


def render_watch(rev, text):
    period_token = parse_watch_period(text)
    if not WATCHLIST:
        error_frame(rev, "Your watchlist is empty. Open a stock and use the **Add to watchlist** button at the bottom.")
        return
    start, end, interval, label, tick_format = resolve_period(period_token)
    loading_frame(rev, "watchlist", label)
    data_items, failures = [], []
    for ticker in WATCHLIST:
        try:
            data_items.append(build_data(ticker, fetch_chart(ticker, start, end, interval), label, tick_format))
        except Exception as e:
            log("watch fetch failed:", ticker, repr(e))
            failures.append(ticker)
    if not data_items:
        error_frame(rev, "Couldn't load any watched stocks. Please try again.")
        return
    img_name = "watchlist.png"
    render_watchlist(data_items, os.path.join(CACHE_DIR, img_name), CACHE_DIR)
    markdown = f"![Watchlist chart]({image_url(img_name)})"
    if failures:
        markdown += "\n\nCouldn't load: " + ", ".join(failures)
    send({"type": "render", "rev": rev, "view": "detail", "inputMode": "submit", "placeholder": "ticker, watch, then optionally a period", "wide": True, "detail": {"markdown": markdown}})


def process(rev, text):
    stripped = text.strip()
    if stripped.lower() == "watch" or stripped.lower().startswith("watch "):
        render_watch(rev, text)
        return
    ticker, period_token = parse_query(text)

    if not ticker:
        instructions_frame(rev)
        return

    start, end, interval, label, tick_format = resolve_period(period_token)

    STATE["last_ticker"] = ticker
    STATE["last_period"] = period_token

    loading_frame(rev, ticker, label)

    try:
        raw = fetch_chart(ticker, start, end, interval)
        data = build_data(ticker, raw, label, tick_format)

        img_name = "stock.png"
        render_chart(data, os.path.join(CACHE_DIR, img_name))
        STATE["last_data"] = data
        STATE["last_image"] = img_name
        result_frame(rev, data, img_name)

    except ValueError as e:
        error_frame(rev, str(e))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            error_frame(rev, f"No data found for **{ticker}**. Check the symbol and try again.")
        else:
            error_frame(rev, f"Yahoo Finance returned an error ({e.code}). Try again in a moment.")
    except urllib.error.URLError as e:
        error_frame(rev, f"Network error: {e}")
    except Exception as e:
        log("error:", repr(e))
        error_frame(rev, f"```\n{e}\n```")


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
            send({"type": "command", "command": "storage", "op": "get", "key": "watchlist", "requestId": "watchlist"})
            initial_text = msg.get("query", "") or ""
            if initial_text.strip():
                process(0, initial_text)
            else:
                instructions_frame(0)
        elif t == "query":
            pass  # waiting for Enter (inputMode: submit)
        elif t == "submitQuery":
            process(msg.get("rev", 0), msg.get("text", ""))
        elif t == "action":
            action_id = msg.get("action") or msg.get("id") or ""
            if action_id.startswith("period_"):
                tok = action_id[len("period_"):]
                process(0, f"{STATE['last_ticker']} {tok}")
            elif action_id == "watch_add" and STATE["last_data"]:
                symbol = STATE["last_data"]["symbol"].upper()
                if symbol not in WATCHLIST:
                    WATCHLIST.append(symbol)
                    save_watchlist()
                result_frame(0, STATE["last_data"], STATE["last_image"])
            elif action_id == "watch_remove" and STATE["last_data"]:
                symbol = STATE["last_data"]["symbol"].upper()
                if symbol in WATCHLIST:
                    WATCHLIST.remove(symbol)
                    save_watchlist()
                result_frame(0, STATE["last_data"], STATE["last_image"])
        elif t == "storage" and msg.get("requestId") == "watchlist":
            stored = msg.get("value")
            if isinstance(stored, list):
                WATCHLIST[:] = [str(symbol).upper() for symbol in stored if str(symbol).strip()]
        elif t == "back":
            instructions_frame(0)


if __name__ == "__main__":
    main()
