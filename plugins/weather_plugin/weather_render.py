"""Renders the 'nice image' shown for a weather query - either a single
'today' card or a 7-day 'weekly' strip.
"""

import os
import math
from PIL import Image, ImageDraw, ImageFont

from weather_icons import icon_image, text_for_code

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_DIR = os.path.join(HERE, "fonts")

_FONT_CACHE = {}


def font(weight, size):
    key = (weight, size)
    if key not in _FONT_CACHE:
        name = "Lato-Bold.ttf" if weight == "bold" else "Lato-Regular.ttf"
        _FONT_CACHE[key] = ImageFont.truetype(os.path.join(FONT_DIR, name), size)
    return _FONT_CACHE[key]


# Background palette keyed by a rough "feel" of the current condition.
BG_TOP = (110, 176, 240)
BG_BOTTOM = (200, 227, 250)
CARD_WHITE = (255, 255, 255, 235)
TEXT_DARK = (35, 42, 55, 255)
TEXT_MUTED = (105, 114, 130, 255)
ACCENT = (255, 150, 60, 255)


def _vertical_gradient(size, top, bottom):
    w, h = size
    base = Image.new("RGB", (1, h), color=0)
    draw = ImageDraw.Draw(base)
    for y in range(h):
        t = y / max(h - 1, 1)
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        draw.point((0, y), fill=(r, g, b))
    return base.resize((w, h))


def _text_w(draw, text, f):
    bbox = draw.textbbox((0, 0), text, font=f)
    return bbox[2] - bbox[0]


def _centered_text(draw, cx, y, text, f, fill):
    w = _text_w(draw, text, f)
    draw.text((cx - w / 2, y), text, font=f, fill=fill)


def _round_card(size, radius, fill):
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, size[0], size[1]], radius=radius, fill=fill)
    return img


def render_today(data, out_path):
    """data: dict with city, country, temp, feels_like, humidity, wind,
    weather_code, temp_min, temp_max, precip_prob, date_label."""
    W, H = 820, 460
    canvas = _vertical_gradient((W, H), BG_TOP, BG_BOTTOM).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    f_city = font("bold", 34)
    f_date = font("regular", 20)
    f_temp = font("bold", 92)
    f_cond = font("bold", 26)
    f_label = font("regular", 18)
    f_value = font("bold", 22)

    pad = 40
    draw.text((pad, pad), data["city"], font=f_city, fill=(255, 255, 255, 255))
    draw.text((pad, pad + 44), data["date_label"], font=f_date, fill=(255, 255, 255, 230))

    icon_size = 150
    icon = icon_image(data["weather_code"], icon_size)
    canvas.paste(icon, (pad, 120), icon)

    temp_text = f"{round(data['temp'])}°"
    tw = _text_w(draw, temp_text, f_temp)
    draw.text((W - pad - tw, 100), temp_text, font=f_temp, fill=(255, 255, 255, 255))

    cond_text = text_for_code(data["weather_code"])
    cw = _text_w(draw, cond_text, f_cond)
    draw.text((W - pad - cw, 200), cond_text, font=f_cond, fill=(255, 255, 255, 235))

    lo_hi = f"H:{round(data['temp_max'])}°  L:{round(data['temp_min'])}°"
    lw = _text_w(draw, lo_hi, f_label)
    draw.text((W - pad - lw, 240), lo_hi, font=f_label, fill=(255, 255, 255, 210))

    # Stat card row at bottom.
    card_h = 120
    card_y = H - card_h - 30
    card = _round_card((W - pad * 2, card_h), 22, CARD_WHITE)
    canvas.alpha_composite(card, (pad, card_y))

    stats = [
        ("Feels like", f"{round(data['feels_like'])}°"),
        ("Humidity", f"{data['humidity']}%"),
        ("Wind", f"{round(data['wind'])} {data['wind_unit']}"),
        ("Rain chance", f"{data['precip_prob']}%"),
    ]
    col_w = (W - pad * 2) / len(stats)
    for i, (label, value) in enumerate(stats):
        cx = pad + col_w * i + col_w / 2
        _centered_text(draw, cx, card_y + 22, label, f_label, TEXT_MUTED)
        _centered_text(draw, cx, card_y + 50, value, f_value, TEXT_DARK)
        if i > 0:
            draw.line(
                [pad + col_w * i, card_y + 18, pad + col_w * i, card_y + card_h - 18],
                fill=(210, 214, 222, 255),
                width=2,
            )

    canvas.convert("RGB").save(out_path, "PNG")
    return out_path


def render_weekly(data, out_path):
    """data: dict with city, country, days: list of 7 dicts with
    label, weather_code, temp_min, temp_max, precip_prob."""
    days = data["days"]
    n = len(days)
    W = 140 * n + 60
    H = 430
    canvas = _vertical_gradient((W, H), BG_TOP, BG_BOTTOM).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    f_city = font("bold", 30)
    f_sub = font("regular", 18)
    f_day = font("bold", 20)
    f_temp_hi = font("bold", 24)
    f_temp_lo = font("regular", 20)
    f_pct = font("regular", 16)

    pad = 30
    draw.text((pad, 24), data["city"], font=f_city, fill=(255, 255, 255, 255))
    draw.text((pad, 62), "7-Day Forecast", font=f_sub, fill=(255, 255, 255, 220))

    col_w = (W - pad * 2) / n
    card_top = 120
    card_h = H - card_top - 30

    all_hi = [d["temp_max"] for d in days]
    all_lo = [d["temp_min"] for d in days]
    span_max, span_min = max(all_hi), min(all_lo)
    span = max(span_max - span_min, 1)
    bar_zone_top = card_top + 128    # just below the icon
    bar_zone_bottom = card_top + 188  # leaves room for hi/lo/rain text below

    for i, d in enumerate(days):
        cx = pad + col_w * i + col_w / 2
        card = _round_card((int(col_w - 14), card_h), 20, CARD_WHITE)
        canvas.alpha_composite(card, (int(pad + col_w * i + 7), card_top))

        _centered_text(draw, cx, card_top + 16, d["label"], f_day, TEXT_DARK)

        icon = icon_image(d["weather_code"], 64)
        canvas.paste(icon, (int(cx - 32), card_top + 46), icon)

        # Simple vertical range bar for hi/lo temps.
        y_hi = bar_zone_bottom - (d["temp_max"] - span_min) / span * (bar_zone_bottom - bar_zone_top)
        y_lo = bar_zone_bottom - (d["temp_min"] - span_min) / span * (bar_zone_bottom - bar_zone_top)
        draw.line([cx, y_hi, cx, y_lo], fill=ACCENT, width=6)
        draw.ellipse([cx - 4, y_hi - 4, cx + 4, y_hi + 4], fill=ACCENT)
        draw.ellipse([cx - 4, y_lo - 4, cx + 4, y_lo + 4], fill=(150, 170, 200, 255))

        hi_text = f"{round(d['temp_max'])}°"
        lo_text = f"{round(d['temp_min'])}°"
        _centered_text(draw, cx, card_top + card_h - 68, hi_text, f_temp_hi, TEXT_DARK)
        _centered_text(draw, cx, card_top + card_h - 42, lo_text, f_temp_lo, TEXT_MUTED)

        pct_text = f"Rain {d['precip_prob']}%"
        _centered_text(draw, cx, card_top + card_h - 20, pct_text, f_pct, TEXT_MUTED)

    canvas.convert("RGB").save(out_path, "PNG")
    return out_path
