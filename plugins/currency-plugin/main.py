#!/usr/bin/env python3
"""
Currency Converter — Tabame launcher plugin.

Usage in launcher:  fx 100 usd eur   |   fx usd gbp   |   fx eur
Data source: Frankfurter (frankfurter.app), free & keyless, ECB daily rates.
NOTE: only daily (not intraday) history is available for free without an
API key, so the timeframe tabs are 1W/1M/3M/1Y/5Y/All rather than 1D.

The card itself (flags, price, change badge, gradient area chart, range
tabs, Open/High/Low/52W footer) is drawn as a PNG with Pillow and embedded
in the detail view via markdown image syntax, since Tabame's render schema
has no raw-SVG/canvas surface for custom pixel-level graphics.
"""

import json
import math
import os
import re
import sys
import threading
import time
import urllib.parse
import urllib.request
from datetime import date, timedelta
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

PLUGIN_DIR = os.path.dirname(os.path.abspath(__file__))
BASE = "https://api.frankfurter.app"

DEFAULT_TARGET = "EUR"
RANGE_DAYS = {"1W": 7, "1M": 30, "3M": 90, "1Y": 365, "5Y": 365 * 5}
RANGE_ORDER = ["1W", "1M", "3M", "1Y", "5Y", "All"]

CUR_NAMES = {
    "USD": "US Dollar",
    "EUR": "Euro",
    "GBP": "British Pound",
    "JPY": "Japanese Yen",
    "CHF": "Swiss Franc",
    "CAD": "Canadian Dollar",
    "AUD": "Australian Dollar",
    "CNY": "Chinese Yuan",
    "INR": "Indian Rupee",
    "RON": "Romanian Leu",
    "SEK": "Swedish Krona",
    "NOK": "Norwegian Krone",
    "PLN": "Polish Zloty",
}

state = {"amount": 1.0, "from": "USD", "to": "EUR", "range": "1W", "rate": None}
lock = threading.Lock()
latest_rev = 0
_cache_counter = int(time.time() * 1000)


# ---------------------------------------------------------------- protocol


def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# ------------------------------------------------------------------ data


def fetch_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 TabameFX"})
    with urllib.request.urlopen(req, timeout=8) as r:
        return json.loads(r.read().decode("utf-8"))


def latest_rate(frm, to):
    data = fetch_json(
        f"{BASE}/latest?from={urllib.parse.quote(frm)}&to={urllib.parse.quote(to)}"
    )
    return data["rates"][to]


def history(frm, to, start, end):
    url = f"{BASE}/{start}..{end}?from={urllib.parse.quote(frm)}&to={urllib.parse.quote(to)}"
    data = fetch_json(url)
    items = sorted(data.get("rates", {}).items())
    dates = [d for d, _ in items if to in items[0][1]] if items else []
    dates = [d for d, v in items if to in v]
    values = [v[to] for _, v in items if to in v]
    return dates, values


def range_dates(range_key):
    end = date.today()
    if range_key == "All":
        start = date(1999, 1, 4)
    else:
        start = end - timedelta(days=RANGE_DAYS.get(range_key, 7))
    return start.isoformat(), end.isoformat()


def compute_52w(frm, to):
    end = date.today()
    start = end - timedelta(days=365)
    _, values = history(frm, to, start.isoformat(), end.isoformat())
    if not values:
        return None, None
    return min(values), max(values)


# ------------------------------------------------------------------ query


# Typed shortcuts for range, e.g. "fx 100 usd ron 1w" or "usd eur all" —
# faster than the ctrl+k "Change timeframe" action. Note "all" intentionally
# takes priority over the (unsupported) ALL currency code, since range intent
# is far more common when someone types it in this context.
_RANGE_ALIASES = {
    "1w": "1W",
    "1m": "1M",
    "3m": "3M",
    "1y": "1Y",
    "5y": "5Y",
    "all": "All",
}


def parse_query(text):
    text = (text or "").strip()
    if not text:
        return None
    amount = None
    codes = []
    range_key = None
    for tok in re.split(r"\s+", text):
        tl = tok.lower()
        if tl in ("to", "in", "as", "->", "for"):
            continue
        if tl in _RANGE_ALIASES:
            range_key = _RANGE_ALIASES[tl]
            continue
        try:
            amount = float(tok.replace(",", ""))
            continue
        except ValueError:
            pass
        if re.fullmatch(r"[A-Za-z]{3}", tok):
            codes.append(tok.upper())
    if not codes:
        return None
    frm = codes[0]
    to = (
        codes[1]
        if len(codes) > 1
        else (state["to"] if state["to"] != frm else DEFAULT_TARGET)
    )
    if to == frm:
        to = DEFAULT_TARGET if DEFAULT_TARGET != frm else "USD"
    return (amount if amount is not None else 1.0), frm, to, range_key


# ------------------------------------------------------------------- fonts

_FONT_DIRS = [
    r"C:\Windows\Fonts",
    "/usr/share/fonts/truetype/dejavu",
    "/usr/share/fonts/TTF",
    "/System/Library/Fonts",
]
_BOLD = [
    "seguisb.ttf",
    "segoeuib.ttf",
    "arialbd.ttf",
    "DejaVuSans-Bold.ttf",
    "Arial Bold.ttf",
]
_REG = ["segoeui.ttf", "arial.ttf", "DejaVuSans.ttf", "Arial.ttf"]

_font_cache = {}


def get_font(size, bold=False):
    key = (size, bold)
    if key in _font_cache:
        return _font_cache[key]
    for d in _FONT_DIRS:
        for n in _BOLD if bold else _REG:
            p = os.path.join(d, n)
            if os.path.exists(p):
                try:
                    f = ImageFont.truetype(p, size)
                    _font_cache[key] = f
                    return f
                except Exception:
                    pass
    try:
        f = ImageFont.truetype("arial.ttf", size)
    except Exception:
        try:
            f = ImageFont.load_default(size=size)
        except Exception:
            f = ImageFont.load_default()
    _font_cache[key] = f
    return f


# -------------------------------------------------------------- flag icons


def _circular(size, draw_fn):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    dd = ImageDraw.Draw(im)
    draw_fn(dd, size)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size, size], fill=255)
    im.putalpha(mask)
    return im


def _us(dd, size):
    dd.rectangle([0, 0, size, size], fill=(178, 34, 52))
    sh = size / 13
    for i in range(13):
        if i % 2 == 1:
            dd.rectangle([0, i * sh, size, (i + 1) * sh], fill=(255, 255, 255))
    dd.rectangle([0, 0, size * 0.55, size * 7 / 13], fill=(50, 49, 100))
    for row in range(4):
        for col in range(5):
            sx = size * 0.06 + col * size * 0.10
            sy = size * 0.06 + row * size * 0.12
            dd.ellipse([sx, sy, sx + 3, sy + 3], fill=(255, 255, 255))


def _eu(dd, size):
    dd.rectangle([0, 0, size, size], fill=(0, 51, 153))
    cx = cy = size / 2
    r = size * 0.32
    for k in range(12):
        ang = math.pi * 2 * k / 12
        sx, sy = cx + r * math.cos(ang), cy + r * math.sin(ang)
        dd.ellipse([sx - 3, sy - 3, sx + 3, sy + 3], fill=(255, 204, 0))


def _generic(code):
    h = sum(ord(c) for c in code)
    palette = [
        (0, 122, 255),
        (147, 51, 234),
        (16, 163, 127),
        (234, 88, 12),
        (219, 39, 119),
    ]
    color = palette[h % len(palette)]

    def _f(dd, size):
        dd.rectangle([0, 0, size, size], fill=color)
        f = get_font(int(size * 0.34), bold=True)
        txt = code[:2]
        bbox = dd.textbbox((0, 0), txt, font=f)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        dd.text(
            ((size - tw) / 2 - bbox[0], (size - th) / 2 - bbox[1]),
            txt,
            font=f,
            fill=(255, 255, 255),
        )

    return _f


def paste_flag(img, cx, cy, r, code):
    size = int(r * 2)
    fn = _us if code == "USD" else _eu if code == "EUR" else _generic(code)
    fimg = _circular(size, fn)
    img.paste(fimg, (int(cx - r), int(cy - r)), fimg)


# -------------------------------------------------------------------- card


def _fmt_amount(v):
    if v == 0:
        return "0"
    av = abs(v)
    if av >= 1000:
        return f"{v:,.2f}"
    if av >= 1:
        return f"{v:,.4f}"
    return f"{v:.6f}"


def draw_card(frm, to, rate, amount, dates, values, range_key, lo52, hi52, out_path):
    W, H = 1040, 620
    margin = 22
    pad = 46
    img = Image.new("RGB", (W, H), (10, 12, 18))
    d = ImageDraw.Draw(img, "RGBA")
    d.rounded_rectangle(
        [margin, margin, W - margin, H - margin],
        radius=26,
        outline=(38, 42, 52),
        width=2,
    )

    # flags
    fx_cx, fx_cy, fx_r = pad + 34, pad + 34, 30
    paste_flag(img, fx_cx - 10, fx_cy, fx_r, frm)
    paste_flag(img, fx_cx + 20, fx_cy + 18, int(fx_r * 0.62), to)

    f_title = get_font(30, bold=True)
    f_sub = get_font(17)
    d.text((pad + 86, pad + 2), f"{frm} / {to}", font=f_title, fill=(235, 236, 240))
    d.text(
        (pad + 86, pad + 36),
        f"{CUR_NAMES.get(frm, frm)} / {CUR_NAMES.get(to, to)}",
        font=f_sub,
        fill=(150, 155, 168),
    )

    change = (values[-1] - values[0]) if len(values) > 1 else 0.0
    changepct = (change / values[0] * 100) if values and values[0] else 0.0
    up = change >= 0
    color = (46, 213, 152) if up else (240, 95, 95)
    right_edge = W - margin - 24

    # --- row 1: the actual converted value (the whole point of the query) ---
    converted = rate * amount
    f_conv = get_font(32, bold=True)
    conv_str = f"{amount:g} {frm} = {_fmt_amount(converted)} {to}"
    bbox = d.textbbox((0, 0), conv_str, font=f_conv)
    tw = bbox[2] - bbox[0]
    conv_y = pad - 4
    d.text((right_edge - tw, conv_y), conv_str, font=f_conv, fill=(255, 255, 255))

    # --- row 2: change badge + change amount/pct, sized first so nothing overlaps ---
    f_chg = get_font(18, bold=True)
    chg_str = f"{'+' if up else ''}{change:.4f} ({'+' if up else ''}{changepct:.2f}%)"
    bbox2 = d.textbbox((0, 0), chg_str, font=f_chg)
    chg_tw, chg_th = bbox2[2] - bbox2[0], bbox2[3] - bbox2[1]
    badge_d = 28
    gap = 8
    chg_y = conv_y + 46
    badge_x0 = right_edge - chg_tw - gap - badge_d
    badge_y0 = chg_y + (chg_th // 2) - badge_d // 2
    d.rounded_rectangle(
        [badge_x0, badge_y0, badge_x0 + badge_d, badge_y0 + badge_d],
        radius=8,
        fill=(*color, 45),
    )
    cx, cy = badge_x0 + badge_d / 2, badge_y0 + badge_d / 2
    if up:
        d.polygon([(cx, cy - 6), (cx - 5, cy + 4), (cx + 5, cy + 4)], fill=color)
    else:
        d.polygon([(cx, cy + 6), (cx - 5, cy - 4), (cx + 5, cy - 4)], fill=color)
    d.text((right_edge - chg_tw, chg_y - bbox2[1]), chg_str, font=f_chg, fill=color)

    # --- row 3: the plain unit rate, small and muted, underneath ---
    f_rate = get_font(16)
    rate_str = f"1 {frm} = {rate:.4f} {to}"
    bbox3r = d.textbbox((0, 0), rate_str, font=f_rate)
    tw3r = bbox3r[2] - bbox3r[0]
    rate_y = chg_y + badge_d + 6
    d.text((right_edge - tw3r, rate_y), rate_str, font=f_rate, fill=(150, 155, 168))

    # range tabs
    tx, ty = pad, rate_y + 40
    f_tab = get_font(16, bold=True)
    for t in RANGE_ORDER:
        bbox3 = d.textbbox((0, 0), t, font=f_tab)
        tw3 = bbox3[2] - bbox3[0]
        bw = tw3 + 24
        if t == range_key:
            d.rounded_rectangle([tx, ty, tx + bw, ty + 32], radius=9, fill=(*color, 35))
            d.text((tx + 12, ty + 7), t, font=f_tab, fill=color)
        else:
            d.text((tx + 12, ty + 7), t, font=f_tab, fill=(140, 145, 158))
        tx += bw + 14

    # chart
    c_top, c_bottom = ty + 56, H - margin - 118
    c_left, c_right = pad, W - margin - 78
    if values:
        vmin, vmax = min(values), max(values)
        vr = (vmax - vmin) or (abs(vmax) * 0.002 or 0.01)
        pv = vr * 0.15
        vmin, vmax = vmin - pv, vmax + pv
        n = len(values)

        def xy(i, v):
            x = c_left + (c_right - c_left) * (i / (n - 1) if n > 1 else 0)
            y = c_bottom - (c_bottom - c_top) * (
                (v - vmin) / (vmax - vmin) if vmax > vmin else 0.5
            )
            return x, y

        pts = [xy(i, v) for i, v in enumerate(values)]
        f_axis = get_font(14)
        for gi in range(5):
            gy = c_top + (c_bottom - c_top) * gi / 4
            d.line([(c_left, gy), (c_right, gy)], fill=(36, 40, 50), width=1)
            gv = vmax - (vmax - vmin) * gi / 4
            d.text(
                (c_right + 10, gy - 7), f"{gv:.4f}", font=f_axis, fill=(130, 135, 148)
            )
        if len(pts) > 1:
            poly = pts + [(c_right, c_bottom), (c_left, c_bottom)]
            d.polygon(poly, fill=(*color, 45))
            d.line(pts, fill=color, width=3, joint="curve")
        ex, ey = pts[-1]
        d.ellipse([ex - 6, ey - 6, ex + 6, ey + 6], fill=color)
        d.ellipse([ex - 12, ey - 12, ex + 12, ey + 12], outline=(*color, 130), width=2)
        idxs = [0, n // 2, n - 1] if n > 2 else list(range(n))
        for i in idxs:
            lx, _ = pts[i]
            lbl = dates[i][5:] if dates and i < len(dates) else ""
            d.text((lx - 22, c_bottom + 12), lbl, font=f_axis, fill=(130, 135, 148))

    # footer — reserve its own band, well clear of the source line beneath it
    source_y = H - margin - 26
    fy = source_y - 62
    d.line([(pad, fy), (W - margin, fy)], fill=(32, 36, 45), width=1)
    f_lab, f_val = get_font(14), get_font(18, bold=True)
    stats = [
        ("Open", values[0] if values else rate, (200, 205, 216)),
        ("High", max(values) if values else rate, (100, 220, 165)),
        ("Low", min(values) if values else rate, (240, 120, 120)),
        ("52W High", hi52 if hi52 is not None else rate, (200, 205, 216)),
        ("52W Low", lo52 if lo52 is not None else rate, (200, 205, 216)),
    ]
    sx = pad
    col_w = (W - 2 * pad) // len(stats)
    for label, val, vcol in stats:
        d.text((sx, fy + 14), label, font=f_lab, fill=(130, 135, 148))
        d.text((sx, fy + 34), f"{val:.4f}", font=f_val, fill=vcol)
        sx += col_w

    d.text(
        (pad, source_y),
        "Source: Frankfurter (ECB)",
        font=f_lab,
        fill=(110, 114, 126),
    )

    img.save(out_path, "PNG")


def next_cache_path():
    # A strictly unique filename per render — reusing a small pool of names
    # (e.g. alternating cache_0/cache_1) lets image widgets that cache by
    # path/URL keep showing a stale bitmap even after the file on disk changes.
    global _cache_counter
    _cache_counter += 1
    return os.path.join(PLUGIN_DIR, f"cache_{_cache_counter}.png")


def cleanup_cache(keep_path):
    # Keep the current image plus the previous one (in case a frame that's
    # still fading out references it), delete anything older.
    try:
        files = [
            f
            for f in os.listdir(PLUGIN_DIR)
            if f.startswith("cache_") and f.endswith(".png")
        ]
        files = sorted(
            files, key=lambda f: os.path.getmtime(os.path.join(PLUGIN_DIR, f))
        )
        for f in files[:-2]:
            try:
                os.remove(os.path.join(PLUGIN_DIR, f))
            except OSError:
                pass
    except Exception:
        pass


# ------------------------------------------------------------------ frames


def default_list_frame(rev):
    pairs = [
        ("USD", "EUR"),
        ("USD", "GBP"),
        ("EUR", "GBP"),
        ("USD", "JPY"),
        ("GBP", "EUR"),
    ]
    items = []
    for f, t in pairs:
        items.append(
            {
                "id": f"{f}{t}",
                "title": f"{f} / {t}",
                "subtitle": f"{CUR_NAMES.get(f, f)} → {CUR_NAMES.get(t, t)}",
                "icon": "currency",
                "actions": [{"id": "default", "title": "Convert", "icon": "open"}],
            }
        )
    items.append(
        {
            "id": f"infoX",
            "title": f"For different graph timeline",
            "subtitle": f"Add at the end 1W, 1M, 3M, 1Y, 5Y, All",
            "icon": "gear",
            "actions": [{"id": "default", "title": "Convert", "icon": "open"}],
        }
    )
    return {
        "type": "render",
        "rev": rev,
        "view": "list",
        "placeholder": "e.g. 100 usd eur 1y, or usd to gbp 5y",
        "emptyText": "Type an amount, two currency codes, and optionally a range (e.g. 100 usd eur 1y)",
        "items": items,
    }


def build_frame(rev, amount, frm, to, range_key, can_go_back=False):
    try:
        rate = latest_rate(frm, to)
    except Exception as e:
        return {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "detail": {"markdown": f"# Couldn't fetch rate\n\n```\n{e}\n```"},
        }

    start, end = range_dates(range_key)
    try:
        dates, values = history(frm, to, start, end)
    except Exception:
        dates, values = [], []
    if not values:
        dates, values = [end], [rate]

    try:
        lo52, hi52 = compute_52w(frm, to)
    except Exception:
        lo52, hi52 = None, None

    img_path = next_cache_path()
    try:
        draw_card(frm, to, rate, amount, dates, values, range_key, lo52, hi52, img_path)
        cleanup_cache(img_path)
        uri = Path(img_path).resolve().as_uri()
        md = f"![{frm}/{to} chart]({uri})"
    except Exception as e:
        log("draw_card failed:", e)
        md = f"# {frm} / {to}\n\nRate: **{rate:.4f}**"

    converted = rate * amount
    meta = [
        {"label": "Converted", "text": f"{amount:g} {frm} = {converted:,.4f} {to}"},
        {"label": "Rate", "text": f"1 {frm} = {rate:.6f} {to}"},
        {"separator": True},
        {"label": "Range", "text": range_key},
        {"label": "Open", "text": f"{values[0]:.4f}"},
        {"label": "High", "text": f"{max(values):.4f}"},
        {"label": "Low", "text": f"{min(values):.4f}"},
    ]
    if lo52 is not None:
        meta.append({"label": "52W High", "text": f"{hi52:.4f}"})
        meta.append({"label": "52W Low", "text": f"{lo52:.4f}"})
    meta.append(
        {
            "label": "Source",
            "text": "Frankfurter (ECB)",
            "url": "https://www.frankfurter.app",
        }
    )

    state.update(
        {"amount": amount, "from": frm, "to": to, "range": range_key, "rate": rate}
    )

    return {
        "type": "render",
        "rev": rev,
        "view": "detail",
        "canGoBack": can_go_back,
        "placeholder": "e.g. 100 usd eur 1y, or usd to gbp 5y",
        "detail": {"markdown": md, "metadata": meta},
        "actions": [
            {
                "id": "range",
                "title": "Change timeframe",
                "icon": "chart",
                "parameters": [
                    {
                        "id": "range",
                        "type": "dropdown",
                        "label": "Timeframe",
                        "required": True,
                        "options": RANGE_ORDER,
                    }
                ],
            },
            {
                "id": "swap",
                "title": "Swap currencies",
                "icon": "refresh",
                "shortcut": "ctrl+s",
            },
            {
                "id": "copy",
                "title": "Copy converted amount",
                "icon": "copy",
                "shortcut": "ctrl+c",
            },
        ],
    }


# -------------------------------------------------------------------- main


def handle_query(text, rev):
    time.sleep(0.15)  # light debounce while typing
    with lock:
        if rev != latest_rev:
            return
    parsed = parse_query(text)
    if not parsed:
        send(default_list_frame(rev))
        return
    amount, frm, to, range_key = parsed
    frame = build_frame(rev, amount, frm, to, range_key or state.get("range", "1W"))
    with lock:
        if rev != latest_rev:
            return
    send(frame)


def handle_action(msg):
    action = msg.get("action", "default")
    item_id = msg.get("id", "")

    if item_id and action == "default" and len(item_id) == 6 and item_id.isalpha():
        frm, to = item_id[:3], item_id[3:]
        send(build_frame(0, 1.0, frm, to, state.get("range", "1W"), can_go_back=True))
        return

    if action == "range":
        params = msg.get("parameters") or {}
        rk = params.get("range", state.get("range", "1W"))
        send(
            build_frame(
                0, state["amount"], state["from"], state["to"], rk, can_go_back=True
            )
        )
        return

    if action == "swap":
        frm, to = state["to"], state["from"]
        send(
            {
                "type": "command",
                "command": "setQuery",
                "text": f"{state['amount']:g} {frm} {to}",
            }
        )
        send(build_frame(0, state["amount"], frm, to, state.get("range", "1W")))
        return

    if action in ("copy", "default"):
        rate = state.get("rate")
        if rate is None:
            return
        converted = state["amount"] * rate
        txt = f"{converted:,.4f}"
        send({"type": "command", "command": "copy", "text": txt})
        send(
            {
                "type": "command",
                "command": "toast",
                "text": f"Copied {txt} {state.get('to', '')}",
                "style": "success",
            }
        )
        return


def main():
    global latest_rev
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
            text = msg.get("text", msg.get("query", ""))
            rev = msg.get("rev", 0)
            with lock:
                latest_rev = rev
            threading.Thread(target=handle_query, args=(text, rev), daemon=True).start()
        elif t == "action":
            try:
                handle_action(msg)
            except Exception as e:
                send(
                    {
                        "type": "render",
                        "rev": 0,
                        "view": "detail",
                        "detail": {"markdown": f"# Error\n\n```\n{e}\n```"},
                    }
                )
        elif t == "back":
            send(default_list_frame(0))


if __name__ == "__main__":
    main()
