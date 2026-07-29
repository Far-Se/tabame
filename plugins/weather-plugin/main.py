#!/usr/bin/env python3
"""Tabame launcher plugin: wide weather + 7-day forecast image.

Protocol: newline-delimited JSON over stdin/stdout (see tbm-plugin skill).
Data source: Open-Meteo (no API key required).
"""

import glob
import json
import math
import os
import sys
import threading
import time
import urllib.parse
import urllib.request
from datetime import datetime

from PIL import Image, ImageDraw, ImageFont

# --------------------------------------------------------------------------
# stdout / stderr helpers
# --------------------------------------------------------------------------

_send_lock = threading.Lock()


def send(frame):
    with _send_lock:
        sys.stdout.write(json.dumps(frame) + "\n")
        sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# --------------------------------------------------------------------------
# paths / config
# --------------------------------------------------------------------------

PLUGIN_DIR = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(PLUGIN_DIR, "cache")
CONFIG_PATH = os.path.join(PLUGIN_DIR, "config.json")
os.makedirs(CACHE_DIR, exist_ok=True)


def load_config():
    """Returns the last-searched location (+ unit), or None if nobody has
    searched yet. There is no hardcoded default city -- this is a general
    plugin, first run just asks the person to type a city."""
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            if "lat" in cfg and "lon" in cfg:
                return {
                    "name": cfg.get("name", ""),
                    "lat": cfg["lat"],
                    "lon": cfg["lon"],
                    "unit": cfg.get("unit", "c"),
                }
        except Exception as e:
            log("config load failed:", e)
    return None


def save_config(loc):
    try:
        with open(CONFIG_PATH, "w", encoding="utf-8") as f:
            json.dump(loc, f)
    except Exception as e:
        log("config save failed:", e)


# --------------------------------------------------------------------------
# fonts
# --------------------------------------------------------------------------

_font_cache = {}


def font(size, weight="regular"):
    key = (size, weight)
    if key in _font_cache:
        return _font_cache[key]
    candidates = {
        "bold": [
            "seguisb.ttf",
            "Segoe UI Semibold.ttf",
            "arialbd.ttf",
            "DejaVuSans-Bold.ttf",
        ],
        "regular": [
            "segoeui.ttf",
            "Segoe UI.ttf",
            "arial.ttf",
            "DejaVuSans.ttf",
        ],
    }.get(weight, ["segoeui.ttf", "arial.ttf", "DejaVuSans.ttf"])
    f = None
    for name in candidates:
        try:
            f = ImageFont.truetype(name, size)
            break
        except Exception:
            continue
    if f is None:
        f = ImageFont.load_default()
    _font_cache[key] = f
    return f


def text_w(draw, txt, f):
    bbox = draw.textbbox((0, 0), txt, font=f)
    return bbox[2] - bbox[0]


# --------------------------------------------------------------------------
# units
# --------------------------------------------------------------------------


def c_to_unit(c, unit):
    if unit == "f":
        return round(c * 9 / 5 + 32)
    return round(c)


def parse_query(text, previous_unit):
    """Splits a trailing ' f' / ' c' (or bare 'f' / 'c') unit switch off the
    end of a typed query. Returns (location_text, unit)."""
    text = (text or "").strip()
    low = text.lower()
    unit = None
    if low == "f":
        return "", "f"
    if low == "c":
        return "", "c"
    if low.endswith(" f"):
        unit = "f"
        text = text[:-2].strip()
    elif low.endswith(" c"):
        unit = "c"
        text = text[:-2].strip()
    if unit is None:
        unit = previous_unit
    return text, unit


# --------------------------------------------------------------------------
# weather code -> condition family
# --------------------------------------------------------------------------

WEATHER_CODES = {
    0: ("Clear sky", "clear"),
    1: ("Mainly clear", "partly_cloudy"),
    2: ("Partly cloudy", "partly_cloudy"),
    3: ("Overcast", "overcast"),
    45: ("Fog", "fog"),
    48: ("Rime fog", "fog"),
    51: ("Light drizzle", "drizzle"),
    53: ("Drizzle", "drizzle"),
    55: ("Dense drizzle", "drizzle"),
    56: ("Freezing drizzle", "drizzle"),
    57: ("Freezing drizzle", "drizzle"),
    61: ("Slight rain", "rain"),
    63: ("Rain", "rain"),
    65: ("Heavy rain", "rain"),
    66: ("Freezing rain", "rain"),
    67: ("Freezing rain", "rain"),
    71: ("Slight snow", "snow"),
    73: ("Snow", "snow"),
    75: ("Heavy snow", "snow"),
    77: ("Snow grains", "snow"),
    80: ("Rain showers", "showers"),
    81: ("Rain showers", "showers"),
    82: ("Violent showers", "showers"),
    85: ("Snow showers", "snow"),
    86: ("Snow showers", "snow"),
    95: ("Thunderstorm", "thunder"),
    96: ("Thunderstorm", "thunder"),
    99: ("Thunderstorm", "thunder"),
}


def weather_info(code):
    return WEATHER_CODES.get(int(code), ("Unknown", "cloudy"))


# --------------------------------------------------------------------------
# icon drawing (flat vector-style, drawn directly with PIL primitives)
# --------------------------------------------------------------------------


def draw_cloud_shape(draw, cx, cy, w, fill):
    h = w * 0.62
    draw.ellipse(
        [cx - 0.38 * w, cy - 0.60 * h, cx + 0.02 * w, cy + 0.02 * h], fill=fill
    )
    draw.ellipse(
        [cx - 0.12 * w, cy - 0.78 * h, cx + 0.30 * w, cy - 0.06 * h], fill=fill
    )
    draw.ellipse(
        [cx + 0.10 * w, cy - 0.52 * h, cx + 0.46 * w, cy + 0.04 * h], fill=fill
    )
    draw.rounded_rectangle(
        [cx - 0.42 * w, cy - 0.28 * h, cx + 0.46 * w, cy + 0.20 * h],
        radius=0.20 * h,
        fill=fill,
    )


def draw_cloud_icon(draw, cx, cy, size, dense=False):
    back = (150, 158, 168) if dense else (170, 178, 188)
    front = (222, 227, 233) if dense else (236, 239, 243)
    draw_cloud_shape(draw, cx - 0.10 * size, cy - 0.06 * size, size * 0.80, back)
    draw_cloud_shape(draw, cx + 0.10 * size, cy + 0.08 * size, size * 0.74, front)


def draw_sun(draw, cx, cy, r, fill):
    for i in range(8):
        ang = math.radians(i * 45)
        x1 = cx + math.cos(ang) * r * 1.35
        y1 = cy + math.sin(ang) * r * 1.35
        x2 = cx + math.cos(ang) * r * 1.85
        y2 = cy + math.sin(ang) * r * 1.85
        draw.line([x1, y1, x2, y2], fill=fill, width=max(3, int(r * 0.16)))
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)


def draw_moon(draw, cx, cy, r, fill, shade):
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)
    for dx, dy, rr in [(-0.30, -0.20, 0.20), (0.28, 0.10, 0.24), (-0.05, 0.38, 0.15)]:
        draw.ellipse(
            [
                cx + dx * r - rr * r,
                cy + dy * r - rr * r,
                cx + dx * r + rr * r,
                cy + dy * r + rr * r,
            ],
            fill=shade,
        )


def draw_rain(draw, cx, cy, w, color, heavy=False):
    n = 5 if heavy else 4
    for i in range(n):
        x = cx - 0.34 * w + i * (0.68 * w / (n - 1))
        y0 = cy + 0.20 * w
        y1 = y0 + (0.30 * w if heavy else 0.18 * w)
        draw.line([x, y0, x - 0.06 * w, y1], fill=color, width=max(2, int(w * 0.035)))


def draw_snow(draw, cx, cy, w, color):
    for i in range(4):
        x = cx - 0.32 * w + i * (0.64 * w / 3)
        y = cy + 0.22 * w + (0.10 * w if i % 2 else 0)
        rr = 0.045 * w
        draw.ellipse([x - rr, y - rr, x + rr, y + rr], fill=color)


def draw_bolt(draw, cx, cy, w, color):
    pts = [
        (cx + 0.06 * w, cy + 0.10 * w),
        (cx - 0.10 * w, cy + 0.42 * w),
        (cx + 0.02 * w, cy + 0.42 * w),
        (cx - 0.10 * w, cy + 0.75 * w),
        (cx + 0.18 * w, cy + 0.32 * w),
        (cx + 0.05 * w, cy + 0.32 * w),
    ]
    draw.polygon(pts, fill=color)


def draw_fog(draw, cx, cy, w, color):
    for dy in (0.06, 0.20, 0.34):
        y = cy + dy * w
        draw.line(
            [cx - 0.40 * w, y, cx + 0.40 * w, y],
            fill=color,
            width=max(2, int(w * 0.045)),
        )


def draw_weather_icon(draw, family, cx, cy, size, is_day=True):
    """Draws a flat weather glyph centered roughly at (cx, cy), bounding ~size."""
    if family == "clear":
        if is_day:
            draw_sun(draw, cx, cy, size * 0.33, (255, 178, 54))
        else:
            draw_moon(draw, cx, cy, size * 0.31, (226, 228, 238), (196, 199, 216))
        return
    if family == "partly_cloudy":
        if is_day:
            draw_sun(
                draw, cx + size * 0.14, cy - size * 0.16, size * 0.22, (255, 193, 79)
            )
        else:
            draw_moon(
                draw,
                cx + size * 0.14,
                cy - size * 0.16,
                size * 0.20,
                (226, 228, 238),
                (196, 199, 216),
            )
        draw_cloud_icon(
            draw, cx - size * 0.06, cy + size * 0.10, size * 0.85, dense=False
        )
        return
    if family == "overcast":
        draw_cloud_icon(draw, cx, cy, size, dense=True)
        return
    if family == "cloudy":
        draw_cloud_icon(draw, cx, cy, size, dense=False)
        return
    if family == "fog":
        draw_cloud_icon(draw, cx, cy - size * 0.10, size * 0.85, dense=False)
        draw_fog(draw, cx, cy + size * 0.14, size, (200, 205, 212))
        return
    if family in ("drizzle", "rain"):
        draw_cloud_icon(draw, cx, cy - size * 0.14, size * 0.85, dense=True)
        draw_rain(
            draw, cx, cy - size * 0.02, size, (94, 150, 226), heavy=(family == "rain")
        )
        return
    if family == "showers":
        draw_sun(draw, cx + size * 0.16, cy - size * 0.24, size * 0.16, (255, 193, 79))
        draw_cloud_icon(draw, cx, cy - size * 0.10, size * 0.85, dense=True)
        draw_rain(draw, cx, cy - size * 0.02, size, (94, 150, 226), heavy=True)
        return
    if family == "snow":
        draw_cloud_icon(draw, cx, cy - size * 0.14, size * 0.85, dense=True)
        draw_snow(draw, cx, cy, size, (235, 240, 246))
        return
    if family == "thunder":
        draw_cloud_icon(draw, cx, cy - size * 0.18, size * 0.85, dense=True)
        draw_bolt(draw, cx, cy - size * 0.05, size, (255, 205, 60))
        return
    draw_cloud_icon(draw, cx, cy, size, dense=False)


# --------------------------------------------------------------------------
# hourly-responsive sky gradient
# --------------------------------------------------------------------------

SKY_KEYFRAMES = [
    (0, (10, 16, 42), (24, 30, 64)),
    (4, (12, 18, 46), (30, 36, 74)),
    (5, (60, 60, 100), (150, 120, 130)),
    (6, (255, 158, 110), (140, 150, 205)),
    (7, (130, 175, 230), (200, 220, 245)),
    (9, (75, 155, 225), (175, 210, 245)),
    (12, (60, 145, 225), (170, 205, 245)),
    (15, (70, 150, 222), (190, 205, 235)),
    (17, (110, 150, 205), (235, 190, 140)),
    (19, (240, 130, 95), (110, 85, 140)),
    (21, (45, 40, 90), (18, 18, 46)),
    (24, (10, 16, 42), (24, 30, 64)),
]


def _lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def sky_gradient_colors(local_hour_float):
    h = local_hour_float % 24
    for i in range(len(SKY_KEYFRAMES) - 1):
        h0, t0, b0 = SKY_KEYFRAMES[i]
        h1, t1, b1 = SKY_KEYFRAMES[i + 1]
        if h0 <= h <= h1:
            t = 0 if h1 == h0 else (h - h0) / (h1 - h0)
            return _lerp(t0, t1, t), _lerp(b0, b1, t)
    return SKY_KEYFRAMES[0][1], SKY_KEYFRAMES[0][2]


def tint_toward_grey(color, amount):
    grey = (128, 132, 138)
    return _lerp(color, grey, amount)


def render_sky(w, h, local_hour_float, family):
    top, bottom = sky_gradient_colors(local_hour_float)
    overcast_amount = {
        "overcast": 0.45,
        "cloudy": 0.25,
        "rain": 0.4,
        "drizzle": 0.3,
        "showers": 0.25,
        "snow": 0.35,
        "fog": 0.5,
        "thunder": 0.55,
    }.get(family, 0.0)
    if overcast_amount:
        top = tint_toward_grey(top, overcast_amount)
        bottom = tint_toward_grey(bottom, overcast_amount * 0.7)
    img = Image.new("RGB", (w, h), top)
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        row = _lerp(top, bottom, t)
        for x in range(0, w, 4):
            px[x, y] = row
            for dx in range(1, 4):
                if x + dx < w:
                    px[x + dx, y] = row
    return img


# --------------------------------------------------------------------------
# UI helpers
# --------------------------------------------------------------------------


def rounded_card(base_rgba, box, radius=24, fill=(255, 255, 255, 225)):
    overlay = Image.new("RGBA", base_rgba.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    d.rounded_rectangle(box, radius=radius, fill=fill)
    return Image.alpha_composite(base_rgba, overlay)


def temp_bar(draw, x0, x1, y, tmax, tmin, global_max, global_min, height=5):
    span = max(1, global_max - global_min)
    lo = (tmin - global_min) / span
    hi = (tmax - global_min) / span
    full_w = x1 - x0
    draw.rounded_rectangle(
        [x0, y, x1, y + height], radius=height // 2, fill=(224, 228, 233)
    )
    bx0 = x0 + full_w * max(0, lo)
    bx1 = x0 + full_w * min(1, hi)
    draw.rounded_rectangle(
        [bx0, y, bx1, y + height], radius=height // 2, fill=(90, 160, 235)
    )


MOON_PHASES = [
    "New Moon",
    "Waxing Crescent",
    "First Quarter",
    "Waxing Gibbous",
    "Full Moon",
    "Waning Gibbous",
    "Last Quarter",
    "Waning Crescent",
]


def moon_phase_name(dt):
    ref = datetime(2000, 1, 6, 18, 14)
    days = (dt.replace(tzinfo=None) - ref).total_seconds() / 86400.0
    cycle = 29.530588
    pos = (days % cycle) / cycle
    idx = int(pos * 8 + 0.5) % 8
    return MOON_PHASES[idx]


# --------------------------------------------------------------------------
# data fetching
# --------------------------------------------------------------------------


def http_json(url):
    req = urllib.request.Request(
        url, headers={"User-Agent": "tabame-weather-plugin/1.0"}
    )
    with urllib.request.urlopen(req, timeout=12) as resp:
        return json.loads(resp.read().decode("utf-8"))


def geocode(name):
    url = "https://geocoding-api.open-meteo.com/v1/search?" + urllib.parse.urlencode(
        {"name": name, "count": 1, "language": "en", "format": "json"}
    )
    data = http_json(url)
    results = data.get("results") or []
    if not results:
        return None
    r = results[0]
    parts = [r.get("name")]
    if r.get("admin1") and r.get("admin1") != r.get("name"):
        parts.append(r["admin1"])
    if r.get("country"):
        parts.append(r["country"])
    return {
        "name": ", ".join(p for p in parts if p),
        "lat": r["latitude"],
        "lon": r["longitude"],
    }


def fetch_forecast(lat, lon):
    params = {
        "latitude": lat,
        "longitude": lon,
        "current": "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m",
        "hourly": "temperature_2m,weather_code,wind_speed_10m,precipitation_probability",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset",
        "timezone": "auto",
        "forecast_days": 8,
        "wind_speed_unit": "kmh",
    }
    url = "https://api.open-meteo.com/v1/forecast?" + urllib.parse.urlencode(params)
    return http_json(url)


# --------------------------------------------------------------------------
# image rendering -- compact, non-scrolling layout
# --------------------------------------------------------------------------

W, H = 1400, 680
MARGIN = 30
LEFT_W = 1000
RIGHT_X0 = MARGIN + LEFT_W + 30  # 1080
RIGHT_X1 = W - MARGIN  # 1550

CUR_TOP = 34
STATS_TOP, STATS_H = 236, 96
HOURLY_TOP, HOURLY_H = 350, 240
PANEL_BOTTOM = HOURLY_TOP + HOURLY_H  # 590, right panel bottom aligns here
FOOTER_Y = 610


def build_image(location_name, data, unit="c"):
    cur = data["current"]
    hourly = data["hourly"]
    daily = data["daily"]
    utc_offset = data.get("utc_offset_seconds", 0)
    now_local = datetime.utcfromtimestamp(time.time() + utc_offset)
    local_hour_float = now_local.hour + now_local.minute / 60.0

    cur_family = weather_info(cur["weather_code"])[1]
    is_day = bool(cur.get("is_day", 1))

    base = render_sky(W, H, local_hour_float, cur_family).convert("RGBA")
    draw = ImageDraw.Draw(base)

    text_white = (255, 255, 255)
    text_white_dim = (232, 238, 248)
    text_dark = (35, 42, 55)
    text_dim = (110, 118, 132)
    deg = "\u00b0F" if unit == "f" else "\u00b0C"

    # ---- top-left: date/time + unit (location moved to the footer) ----
    f_date = font(22, "regular")
    date_str = now_local.strftime("%A, %B %d").replace(" 0", " ")
    draw.text(
        (MARGIN, CUR_TOP),
        f"{date_str} \u2022 {now_local.strftime('%I:%M %p').lstrip('0')} \u2022 {deg}",
        font=f_date,
        fill=text_white_dim,
    )

    # ---- big current temperature + icon + condition ----
    f_temp = font(118, "bold")
    f_degsym = font(46, "bold")
    temp_val = c_to_unit(cur["temperature_2m"], unit)
    temp_txt = str(temp_val)
    ty = CUR_TOP + 32
    draw.text((MARGIN, ty), temp_txt, font=f_temp, fill=text_white)
    tw = text_w(draw, temp_txt, f_temp)
    draw.text((MARGIN + tw + 4, ty + 6), "\u00b0", font=f_degsym, fill=text_white)

    icon_cx = MARGIN + tw + 130
    icon_cy = ty + 78
    draw_weather_icon(draw, cur_family, icon_cx, icon_cy, 130, is_day=is_day)

    cond_label = weather_info(cur["weather_code"])[0]
    f_cond = font(32, "bold")
    f_hl = font(21, "regular")
    cond_x = icon_cx + 100
    draw.text((cond_x, ty + 26), cond_label, font=f_cond, fill=text_white)
    hi = c_to_unit(daily["temperature_2m_max"][0], unit)
    lo = c_to_unit(daily["temperature_2m_min"][0], unit)
    draw.text(
        (cond_x, ty + 70), f"H:{hi}\u00b0  L:{lo}\u00b0", font=f_hl, fill=text_white_dim
    )

    # ---- stats card ----
    stats_box = [MARGIN, STATS_TOP, MARGIN + LEFT_W, STATS_TOP + STATS_H]
    base = rounded_card(base, stats_box, radius=22)
    draw = ImageDraw.Draw(base)

    stats = [
        ("Feels like", f"{c_to_unit(cur['apparent_temperature'], unit)}\u00b0"),
        ("Humidity", f"{round(cur['relative_humidity_2m'])}%"),
        ("Wind", f"{round(cur['wind_speed_10m'])} km/h"),
        ("Rain chance", f"{_current_hour_precip(hourly, now_local)}%"),
    ]
    col_w = LEFT_W / 4
    f_stat_label = font(18, "regular")
    f_stat_val = font(27, "bold")
    for i, (label, val) in enumerate(stats):
        cx0 = MARGIN + i * col_w + 36
        draw.text((cx0, STATS_TOP + 18), label, font=f_stat_label, fill=text_dim)
        draw.text((cx0, STATS_TOP + 44), val, font=f_stat_val, fill=text_dark)
        if i > 0:
            draw.line(
                [
                    MARGIN + i * col_w,
                    STATS_TOP + 14,
                    MARGIN + i * col_w,
                    STATS_TOP + STATS_H - 14,
                ],
                fill=(215, 219, 225),
                width=2,
            )

    # ---- hourly forecast card ----
    hourly_box = [MARGIN, HOURLY_TOP, MARGIN + LEFT_W, HOURLY_TOP + HOURLY_H]
    base = rounded_card(base, hourly_box, radius=22)
    draw = ImageDraw.Draw(base)
    draw.text(
        (MARGIN + 30, HOURLY_TOP + 16),
        "Hourly forecast",
        font=font(21, "bold"),
        fill=text_dark,
    )

    idx0 = _current_hour_index(hourly, now_local)
    n_hours = 8
    slot_w = (LEFT_W - 60) / n_hours
    hy0 = HOURLY_TOP + 62
    for i in range(n_hours):
        hi_idx = idx0 + i
        if hi_idx >= len(hourly["time"]):
            break
        cx = MARGIN + 30 + slot_w * i + slot_w / 2
        t = datetime.fromisoformat(hourly["time"][hi_idx])
        label = "Now" if i == 0 else t.strftime("%I %p").lstrip("0")
        fam = weather_info(hourly["weather_code"][hi_idx])[1]
        temp = c_to_unit(hourly["temperature_2m"][hi_idx], unit)
        wind = round(hourly["wind_speed_10m"][hi_idx])

        if i == 0:
            draw.rounded_rectangle(
                [cx - slot_w / 2 + 6, hy0 - 12, cx + slot_w / 2 - 6, hy0 + 158],
                radius=14,
                outline=(90, 160, 235),
                width=2,
            )
        lc = (60, 130, 225) if i == 0 else text_dim
        f_hour_label = font(18, "bold" if i == 0 else "regular")
        lw = text_w(draw, label, f_hour_label)
        draw.text((cx - lw / 2, hy0), label, font=f_hour_label, fill=lc)

        draw_weather_icon(
            draw, fam, cx, hy0 + 58, 58, is_day=is_day if i == 0 else True
        )

        f_htemp = font(25, "bold")
        tstr = f"{temp}\u00b0"
        tw2 = text_w(draw, tstr, f_htemp)
        draw.text((cx - tw2 / 2, hy0 + 96), tstr, font=f_htemp, fill=text_dark)

        f_wind = font(15, "regular")
        wstr = f"\u2197 {wind} km/h"
        ww = text_w(draw, wstr, f_wind)
        draw.text((cx - ww / 2, hy0 + 128), wstr, font=f_wind, fill=text_dim)

    # ---- 7-day forecast panel (right column, spans the same height as the
    # current-weather + stats + hourly stack on the left) ----
    panel_box = [RIGHT_X0, CUR_TOP, RIGHT_X1, PANEL_BOTTOM]
    base = rounded_card(base, panel_box, radius=22)
    draw = ImageDraw.Draw(base)
    draw.text(
        (RIGHT_X0 + 30, CUR_TOP + 16),
        "7-day forecast",
        font=font(21, "bold"),
        fill=text_dark,
    )

    all_hi = [c_to_unit(v, unit) for v in daily["temperature_2m_max"][:7]]
    all_lo = [c_to_unit(v, unit) for v in daily["temperature_2m_min"][:7]]
    gmax, gmin = max(all_hi), min(all_lo)

    row_top = CUR_TOP + 62
    row_h = (PANEL_BOTTOM - 14 - row_top) / 7
    for i in range(7):
        y = row_top + i * row_h
        day_raw = daily["time"][i]
        d = (
            datetime.fromisoformat(day_raw)
            if "T" in day_raw
            else datetime.strptime(day_raw, "%Y-%m-%d")
        )
        day_label = "Today" if i == 0 else d.strftime("%a")
        fam, label = weather_info(daily["weather_code"][i])

        f_day = font(19, "bold")
        draw.text(
            (RIGHT_X0 + 30, y + row_h / 2 - 12), day_label, font=f_day, fill=text_dark
        )

        draw_weather_icon(draw, fam, RIGHT_X0 + 135, y + row_h / 2, 38, is_day=True)

        f_cond2 = font(16, "regular")
        # draw.text(
        #     (RIGHT_X0 + 168, y + row_h / 2 - 9), label, font=f_cond2, fill=text_dim
        # )

        f_hi = font(19, "bold")
        f_lo = font(19, "regular")
        hiv_s, lov_s = f"{all_hi[i]}\u00b0", f"{all_lo[i]}\u00b0"
        draw.text(
            (RIGHT_X1 - 26 - text_w(draw, hiv_s, f_hi), y + row_h / 2 - 12),
            hiv_s,
            font=f_hi,
            fill=text_dark,
        )
        draw.text(
            (
                RIGHT_X1
                - 26
                - text_w(draw, hiv_s, f_hi)
                - text_w(draw, lov_s, f_lo)
                - 34,
                y + row_h / 2 - 12,
            ),
            lov_s,
            font=f_lo,
            fill=text_dim,
        )
        temp_bar(
            draw,
            RIGHT_X0 + 30,
            RIGHT_X1 - 30,
            y + row_h - 16,
            all_hi[i],
            all_lo[i],
            gmax,
            gmin,
        )

        if i < 6:
            draw.line(
                [RIGHT_X0 + 30, y + row_h, RIGHT_X1 - 30, y + row_h],
                fill=(228, 231, 236),
                width=1,
            )

    # ---- footer: location + sunrise / sunset / moon (all on the sky, small) ----
    sunrise = datetime.fromisoformat(daily["sunrise"][0])
    sunset = datetime.fromisoformat(daily["sunset"][0])
    phase = moon_phase_name(now_local)
    f_foot = ImageFont.truetype(
        "segoeui.ttf", 20
    )  # Standard font (supports Romanian diacritics)
    f_sym = ImageFont.truetype(
        "seguisym.ttf", 20
    )  # Symbol font (supports symbols/emojis)

    items = [
        ("\U0001f4cd", location_name),  # Icon, Text
        ("\u2600", sunrise.strftime("%I:%M %p").lstrip("0")),
        ("\u2614", sunset.strftime("%I:%M %p").lstrip("0")),
        ("\u263d", phase),
    ]

    # Calculate total width by measuring icons and text with their respective fonts
    total_w = 0
    for icon, val in items:
        total_w += text_w(draw, icon, f_sym) + text_w(draw, f" {val}", f_foot)
    total_w += 60 * (len(items) - 1)

    x = (W - total_w) / 2

    for icon, val in items:
        # 1. Draw the emoji/symbol
        draw.text((x, FOOTER_Y), icon, font=f_sym, fill=text_white_dim)
        x += text_w(draw, icon, f_sym)

        # 2. Draw the text (with Romanian diacritics)
        text_str = f" {val}"
        draw.text((x, FOOTER_Y), text_str, font=f_foot, fill=text_white_dim)
        x += text_w(draw, text_str, f_foot) + 60

    return base.convert("RGB")


def _current_hour_index(hourly, now_local):
    times = hourly["time"]
    target = now_local.strftime("%Y-%m-%dT%H:00")
    for i, t in enumerate(times):
        if t >= target:
            return max(0, i)
    return 0


def _current_hour_precip(hourly, now_local):
    idx = _current_hour_index(hourly, now_local)
    probs = hourly.get("precipitation_probability") or []
    if idx < len(probs):
        return round(probs[idx])
    return 0


# --------------------------------------------------------------------------
# render pipeline (network + image build off the stdin thread)
# --------------------------------------------------------------------------

state = {"location": load_config()}  # None until the person searches a city


def cleanup_old_images(keep=2):
    files = sorted(
        glob.glob(os.path.join(CACHE_DIR, "weather_*.png")), key=os.path.getmtime
    )
    for f in files[:-keep] if len(files) > keep else []:
        try:
            os.remove(f)
        except Exception:
            pass


def frame_actions():
    return [
        {"id": "refresh", "title": "Refresh", "icon": "refresh", "shortcut": "ctrl+r"},
        {"id": "open_image", "title": "Open image", "icon": "open"},
    ]


PLACEHOLDER = "Type a city name (add \u2018 f\u2019 for \u00b0F, \u2018 c\u2019 for \u00b0C)\u2026"


def send_prompt_frame(rev, message):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "wide": True,
            "inputMode": "submit",
            "placeholder": PLACEHOLDER,
            "detail": {"markdown": message},
        }
    )


def do_render(rev, query_text):
    prev_unit = (state["location"] or {}).get("unit", "c")
    loc_text, unit = parse_query(query_text, prev_unit)

    if not loc_text and not state["location"]:
        send_prompt_frame(
            rev, "### Weather\n\nType a city name above and press Enter to get started."
        )
        return

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "loading": True,
            "wide": True,
            "loadingText": "Fetching weather\u2026",
            "inputMode": "submit",
            "placeholder": PLACEHOLDER,
            "detail": {"markdown": ""},
        }
    )
    try:
        loc = dict(state["location"]) if state["location"] else None
        if loc_text:
            found = geocode(loc_text)
            if found is None:
                send(
                    {
                        "type": "render",
                        "rev": rev,
                        "view": "detail",
                        "inputMode": "submit",
                        "placeholder": PLACEHOLDER,
                        "detail": {
                            "markdown": f"### Couldn't find \u201c{loc_text}\u201d\n\nTry a different city name."
                        },
                        "actions": frame_actions() if state["location"] else None,
                    }
                )
                return
            loc = found

        loc["unit"] = unit
        state["location"] = loc
        save_config(loc)

        data = fetch_forecast(loc["lat"], loc["lon"])
        img = build_image(loc["name"], data, unit=unit)
        fname = f"weather_{int(time.time())}.png"
        path = os.path.join(CACHE_DIR, fname)
        img.save(path, "PNG")
        cleanup_old_images()

        file_url = "file:///" + path.replace("\\", "/")
        md = f"![{loc['name']} weather]({file_url})"
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "detail",
                "inputMode": "submit",
                "placeholder": PLACEHOLDER,
                "wide": True,
                "detail": {"markdown": md},
                "actions": frame_actions(),
            }
        )
    except Exception as e:
        log("render failed:", repr(e))
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "detail",
                "inputMode": "submit",
                "placeholder": PLACEHOLDER,
                "detail": {
                    "markdown": f"### Couldn't load the weather\n\n```\n{e}\n```"
                },
                "actions": frame_actions() if state["location"] else None,
            }
        )


def async_render(rev, query_text):
    threading.Thread(target=do_render, args=(rev, query_text), daemon=True).start()


def last_image_path():
    files = sorted(
        glob.glob(os.path.join(CACHE_DIR, "weather_*.png")), key=os.path.getmtime
    )
    return files[-1] if files else None


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
            rev = msg.get("rev", 0)
            async_render(rev, "")
        elif t == "submitQuery":
            rev = msg.get("rev", 0)
            text = (msg.get("text") or "").strip()
            async_render(rev, text)
        elif t == "action":
            action = msg.get("action", "default")
            if action == "refresh":
                async_render(0, "")
            elif action == "open_image":
                p = last_image_path()
                if p:
                    send(
                        {
                            "type": "command",
                            "command": "open",
                            "url": "file:///" + p.replace("\\", "/"),
                        }
                    )
        # "query" is not sent while inputMode is "submit"; ignore other events.


if __name__ == "__main__":
    main()
