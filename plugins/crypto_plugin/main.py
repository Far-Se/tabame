#!/usr/bin/env python3
"""Tabame launcher plugin: crypto [ticker] [period]

period examples: 1d, 5d, 2w, 2m, 1y, 5y, ytd, max
Shows a dark, crypto-app style card: price + change over the selected
period, an area chart, a volume strip, and a stats row (24h range,
market cap, 24h volume, all-time high/low).

Uses CoinGecko's public API (no key) for data, renders a PNG with Pillow,
and serves it over a small local HTTP server so it can be embedded as a
normal https://... image in a markdown detail view.
"""

import sys
import os
import re
import io
import json
import time
import datetime
import socket
import threading
import http.server
import functools
import urllib.request
import urllib.parse
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from crypto_render import render_chart
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(HERE, ".cache")
os.makedirs(CACHE_DIR, exist_ok=True)

API_BASE = "https://api.coingecko.com/api/v3"
SEARCH_URL = f"{API_BASE}/search"
COIN_URL_TMPL = API_BASE + "/coins/{id}"
CHART_URL_TMPL = API_BASE + "/coins/{id}/market_chart"

BROWSER_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)

CURRENCY_SYMBOLS = {
    "usd": "$", "eur": "€", "gbp": "£", "jpy": "¥",
    "cad": "C$", "aud": "A$", "chf": "CHF ",
}

PERIOD_PRESETS = [
    ("1d", "1D"), ("5d", "5D"), ("1m", "1M"),
    ("6m", "6M"), ("1y", "1Y"), ("5y", "5Y"),
]

# Fast-path ticker -> CoinGecko id map for common coins, so we can skip a
# /search round trip for the coins people ask about most.
COMMON_IDS = {
    "btc": "bitcoin", "eth": "ethereum", "usdt": "tether", "bnb": "binancecoin",
    "sol": "solana", "xrp": "ripple", "usdc": "usd-coin", "ada": "cardano",
    "doge": "dogecoin", "trx": "tron", "ton": "the-open-network",
    "avax": "avalanche-2", "shib": "shiba-inu", "dot": "polkadot",
    "link": "chainlink", "bch": "bitcoin-cash", "near": "near",
    "matic": "matic-network", "ltc": "litecoin", "icp": "internet-computer",
    "dai": "dai", "uni": "uniswap", "etc": "ethereum-classic", "xlm": "stellar",
    "atom": "cosmos", "xmr": "monero", "okb": "okb", "fil": "filecoin",
    "hbar": "hedera-hashgraph", "apt": "aptos", "arb": "arbitrum",
    "vet": "vechain", "mkr": "maker", "op": "optimism", "algo": "algorand",
    "aave": "aave", "sui": "sui", "pepe": "pepe", "sand": "the-sandbox",
    "mana": "decentraland", "ldo": "lido-dao", "inj": "injective-protocol",
    "tia": "celestia", "wld": "worldcoin-wld", "grt": "the-graph",
}


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
VS_CURRENCY = (CONFIG.get("currency") or "usd").lower()


# --------------------------------------------------------------------------
# Query parsing: "crypto [ticker] [period]"
# --------------------------------------------------------------------------
_PERIOD_RE = re.compile(r"^\d+[dwmy]$")


def parse_query(text):
    tokens = text.strip().split()
    period_token = None
    if tokens:
        last = tokens[-1].lower()
        if last in ("ytd", "max") or _PERIOD_RE.match(last):
            period_token = tokens.pop().lower()
    ticker = "".join(tokens).lower()
    if not ticker:
        ticker = DEFAULT_TICKER.lower()
    if not period_token:
        period_token = DEFAULT_PERIOD
    return ticker, period_token


def resolve_period(token):
    token = token.lower()
    today = datetime.date.today()
    if token == "ytd":
        days = max((today - datetime.date(today.year, 1, 1)).days, 1)
        label = "YTD"
    elif token == "max":
        days = "max"
        label = "MAX"
    else:
        n = int(token[:-1])
        unit = token[-1]
        if unit == "d":
            days, label = n, f"{n}D"
        elif unit == "w":
            days, label = n * 7, f"{n}W"
        elif unit == "m":
            days, label = n * 30, f"{n}M"
        else:  # 'y'
            days, label = n * 365, f"{n}Y"

    total_days = days if isinstance(days, int) else 3650
    if total_days <= 1:
        tick_format = "%H:%M"
    elif total_days <= 7:
        tick_format = "%a %d"
    elif total_days <= 90:
        tick_format = "%b %d"
    elif total_days <= 730:
        tick_format = "%b %d"
    else:
        tick_format = "%b '%y"
    return days, label, tick_format


# --------------------------------------------------------------------------
# CoinGecko fetches
# --------------------------------------------------------------------------
def http_json(url, params):
    q = urllib.parse.urlencode(params)
    req = urllib.request.Request(f"{url}?{q}", headers={"User-Agent": BROWSER_UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=12) as resp:
        return json.loads(resp.read().decode("utf-8"))


def resolve_coin_id(ticker):
    key = ticker.lower()
    if key in COMMON_IDS:
        return COMMON_IDS[key]
    data = http_json(SEARCH_URL, {"query": ticker})
    coins = data.get("coins") or []
    if not coins:
        return None
    exact = [c for c in coins if (c.get("symbol") or "").lower() == key]
    pool = exact or coins
    pool = sorted(pool, key=lambda c: (c.get("market_cap_rank") is None, c.get("market_cap_rank") or 10 ** 9))
    return pool[0]["id"]


def fetch_coin(coin_id):
    return http_json(COIN_URL_TMPL.format(id=coin_id), {
        "localization": "false", "tickers": "false", "market_data": "true",
        "community_data": "false", "developer_data": "false", "sparkline": "false",
    })


def fetch_market_chart(coin_id, days):
    return http_json(CHART_URL_TMPL.format(id=coin_id), {"vs_currency": VS_CURRENCY, "days": days})


def fetch_logo(url):
    if not url:
        return None
    try:
        req = urllib.request.Request(url, headers={"User-Agent": BROWSER_UA})
        with urllib.request.urlopen(req, timeout=6) as resp:
            raw = resp.read()
        return Image.open(io.BytesIO(raw)).convert("RGBA")
    except Exception as e:
        log("logo fetch failed:", e)
        return None


def build_data(ticker, coin_json, chart_json, label, tick_format):
    market = coin_json.get("market_data") or {}
    prices = chart_json.get("prices") or []
    volumes_raw = chart_json.get("total_volumes") or []

    points = []
    for ts_ms, price in prices:
        dt = datetime.datetime.fromtimestamp(ts_ms / 1000, tz=datetime.timezone.utc)
        points.append((dt, price))

    volumes = []
    prev_price = None
    for i, (ts_ms, vol) in enumerate(volumes_raw):
        dt = datetime.datetime.fromtimestamp(ts_ms / 1000, tz=datetime.timezone.utc)
        price_i = points[i][1] if i < len(points) else prev_price
        up = True if prev_price is None else (price_i >= prev_price)
        volumes.append((dt, vol or 0, up))
        prev_price = price_i

    currency_symbol = CURRENCY_SYMBOLS.get(VS_CURRENCY, VS_CURRENCY.upper() + " ")

    def cur(field, default=0):
        return (market.get(field) or {}).get(VS_CURRENCY, default)

    price = cur("current_price", points[-1][1] if points else 0)
    start_price = points[0][1] if points else price
    change = price - start_price
    change_pct = (change / start_price * 100) if start_price else 0.0

    last_updated = market.get("last_updated")
    if last_updated:
        try:
            dt = datetime.datetime.fromisoformat(last_updated.replace("Z", "+00:00"))
            as_of = dt.strftime("%b %d, %I:%M %p UTC")
        except ValueError:
            as_of = "Live"
    else:
        as_of = "Live"

    logo_url = ((coin_json.get("image") or {}).get("small")
                or (coin_json.get("image") or {}).get("thumb"))
    logo = fetch_logo(logo_url)

    return {
        "symbol": (coin_json.get("symbol") or ticker).upper(),
        "name": coin_json.get("name") or ticker,
        "rank": coin_json.get("market_cap_rank"),
        "currency_symbol": currency_symbol,
        "price": price,
        "change": change,
        "change_pct": change_pct,
        "period_label": label,
        "as_of": as_of,
        "points": points,
        "volumes": volumes,
        "high_24h": cur("high_24h", price),
        "low_24h": cur("low_24h", price),
        "market_cap": cur("market_cap", 0),
        "total_volume": cur("total_volume", 0),
        "ath": cur("ath", price),
        "atl": cur("atl", price),
        "tick_format": tick_format,
        "logo": logo,
    }


# --------------------------------------------------------------------------
# Frame builders
# --------------------------------------------------------------------------
def instructions_frame(rev):
    lines = [
        "# Crypto",
        "",
        "Type a ticker and press **Enter**:",
        "",
        "- `crypto BTC` — default period (" + DEFAULT_PERIOD.upper() + ")",
        "- `crypto ETH 1d` — 1 day",
        "- `crypto SOL 2m` — 2 months",
        "- `crypto DOGE 1y` — 1 year",
        "- `crypto BTC ytd` / `crypto BTC max`",
    ]
    if DEFAULT_TICKER:
        lines.append("")
        lines.append(f"No ticker? Defaults to **{DEFAULT_TICKER.upper()}**.")
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
        "loadingText": f"Fetching {label} chart for {ticker.upper()}…",
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
                {"label": "Name", "text": data["name"]},
                {"label": "Rank", "text": f"#{data['rank']}" if data["rank"] else "-"},
            ],
        },
        "actions": actions,
    })


# --------------------------------------------------------------------------
# Main processing
# --------------------------------------------------------------------------
STATE = {"last_ticker": DEFAULT_TICKER, "last_period": DEFAULT_PERIOD}


def process(rev, text):
    ticker, period_token = parse_query(text)

    if not ticker:
        instructions_frame(rev)
        return

    days, label, tick_format = resolve_period(period_token)

    STATE["last_ticker"] = ticker
    STATE["last_period"] = period_token

    loading_frame(rev, ticker, label)

    try:
        coin_id = resolve_coin_id(ticker)
        if not coin_id:
            error_frame(rev, f"No matching coin found for **{ticker.upper()}**.")
            return

        coin_json = fetch_coin(coin_id)
        chart_json = fetch_market_chart(coin_id, days)
        data = build_data(ticker, coin_json, chart_json, label, tick_format)

        img_name = "crypto.png"
        render_chart(data, os.path.join(CACHE_DIR, img_name))
        result_frame(rev, data, img_name)

    except urllib.error.HTTPError as e:
        if e.code == 429:
            error_frame(rev, "Rate limited by CoinGecko — try again in a moment.")
        elif e.code == 404:
            error_frame(rev, f"No data found for **{ticker.upper()}**.")
        else:
            error_frame(rev, f"CoinGecko returned an error ({e.code}). Try again in a moment.")
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
        elif t == "back":
            instructions_frame(0)


if __name__ == "__main__":
    main()
