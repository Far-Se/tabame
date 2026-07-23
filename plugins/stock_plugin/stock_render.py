"""Renders the 'nice image' shown for a stock query: a dark, trading-app
style card with a price area-chart, a volume strip, and a stats row.

Everything is drawn at 2x resolution and downscaled at the end so lines,
curves and text all come out anti-aliased.
"""

import datetime
import os

from PIL import Image, ImageChops, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_DIR = os.path.join(HERE, "fonts")

SCALE = 2  # supersampling factor for the whole canvas

_FONT_CACHE = {}


def font(weight, size):
    key = (weight, size)
    if key not in _FONT_CACHE:
        name = "Lato-Bold.ttf" if weight == "bold" else "Lato-Regular.ttf"
        _FONT_CACHE[key] = ImageFont.truetype(
            os.path.join(FONT_DIR, name), size * SCALE
        )
    return _FONT_CACHE[key]


def S(v):
    return v * SCALE


# ---- palette (dark, trading-terminal feel) --------------------------------
BG_TOP = (20, 24, 34)
BG_BOTTOM = (11, 13, 19)
CARD_BG = (30, 35, 47, 235)
GRID_COLOR = (255, 255, 255, 26)
AXIS_TEXT = (140, 148, 163, 255)
TEXT_WHITE = (235, 238, 242, 255)
TEXT_MUTED = (140, 148, 163, 255)
GREEN = (22, 199, 132, 255)
GREEN_DIM = (22, 199, 132, 40)
RED = (246, 70, 93, 255)
RED_DIM = (246, 70, 93, 40)
CHIP_BG = (255, 255, 255, 22)


def _vertical_gradient(size, top, bottom):
    w, h = size
    base = Image.new("RGB", (1, h), color=0)
    d = ImageDraw.Draw(base)
    for y in range(h):
        t = y / max(h - 1, 1)
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        d.point((0, y), fill=(r, g, b))
    return base.resize((w, h))


def _text_w(draw, text, f):
    bbox = draw.textbbox((0, 0), text, font=f)
    return bbox[2] - bbox[0]


def _round_card(size, radius, fill):
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, size[0], size[1]], radius=radius, fill=fill)
    return img


def _fmt_price(v, currency_symbol):
    return f"{currency_symbol}{v:,.2f}"


def _fmt_compact(n):
    n = float(n)
    for unit, div in (("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if abs(n) >= div:
            return f"{n / div:,.2f}{unit}"
    return f"{n:,.0f}"


def render_chart(data, out_path):
    """data keys:
    symbol, name, exchange, currency_symbol, price, change, change_pct,
    period_label, as_of, points (list of (datetime, close)),
    volumes (list of (datetime, volume, up:bool)),
    day_high, day_low, prev_close, day_volume, week52_high, week52_low,
    tick_format (strftime string for x-axis labels)
    """
    FW, FH = 960, 600  # final (post-downscale) size
    W, H = S(FW), S(FH)
    canvas = _vertical_gradient((W, H), BG_TOP, BG_BOTTOM).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    up = data["change"] >= 0
    trend = GREEN if up else RED
    trend_dim = GREEN_DIM if up else RED_DIM
    arrow = "↑" if up else "↓"

    f_symbol = font("bold", 40)
    f_name = font("regular", 19)
    f_price = font("bold", 46)
    f_change = font("bold", 20)
    f_chip = font("bold", 16)
    f_asof = font("regular", 15)
    f_axis = font("regular", 15)
    f_stat_label = font("regular", 16)
    f_stat_value = font("bold", 20)

    pad = S(40)

    # ---- header ----
    draw.text((pad, pad), data["symbol"], font=f_symbol, fill=TEXT_WHITE)
    sw = _text_w(draw, data["symbol"], f_symbol)
    exch = data.get("exchange") or ""
    if exch:
        chip_pad_x, chip_pad_y = S(10), S(5)
        chip_w = _text_w(draw, exch, f_chip) + chip_pad_x * 2
        chip_h = S(24)
        chip_x = pad + sw + S(14)
        chip_y = pad + S(8)
        chip = _round_card((chip_w, chip_h), chip_h // 2, CHIP_BG)
        canvas.alpha_composite(chip, (int(chip_x), int(chip_y)))
        draw.text(
            (chip_x + chip_pad_x, chip_y + chip_h / 2 - S(9)),
            exch,
            font=f_chip,
            fill=AXIS_TEXT,
        )
    draw.text((pad, pad + S(48)), data["name"], font=f_name, fill=TEXT_MUTED)

    price_text = _fmt_price(data["price"], data["currency_symbol"])
    pw = _text_w(draw, price_text, f_price)
    draw.text((W - pad - pw, pad), price_text, font=f_price, fill=TEXT_WHITE)

    change_text = f"{arrow} {_fmt_price(abs(data['change']), data['currency_symbol'])}  ({abs(data['change_pct']):.2f}%)"
    cw = _text_w(draw, change_text, f_change)
    draw.text((W - pad - cw, pad + S(54)), change_text, font=f_change, fill=trend)

    period_text = f"{data['period_label']} · {data['as_of']}"
    ptw = _text_w(draw, period_text, f_asof)
    draw.text((W - pad - ptw, pad + S(84)), period_text, font=f_asof, fill=TEXT_MUTED)

    # ---- chart area ----
    chart_top = S(170)
    chart_bottom = S(350)
    chart_left = pad
    chart_right = W - pad

    points = data["points"]
    if len(points) >= 2:
        closes = [p[1] for p in points]
        p_min, p_max = min(closes), max(closes)
        if p_max == p_min:
            p_max += 1
            p_min -= 1
        p_span = p_max - p_min

        # Gridlines + price labels (4 horizontal lines).
        for i in range(4):
            t = i / 3
            y = chart_bottom - t * (chart_bottom - chart_top)
            draw.line([chart_left, y, chart_right, y], fill=GRID_COLOR, width=S(1))
            lvl = p_min + t * p_span
            label = _fmt_price(lvl, data["currency_symbol"])
            lw = _text_w(draw, label, f_axis)
            draw.text((chart_right - lw, y - S(20)), label, font=f_axis, fill=AXIS_TEXT)

        n = len(points)

        def xy(i):
            x = chart_left + (i / (n - 1)) * (chart_right - chart_left)
            y = chart_bottom - (closes[i] - p_min) / p_span * (chart_bottom - chart_top)
            return x, y

        coords = [xy(i) for i in range(n)]

        # Area fill under the line, shaded by trend color.
        area = coords + [(chart_right, chart_bottom), (chart_left, chart_bottom)]
        grad = Image.new(
            "RGBA",
            (int(chart_right - chart_left), int(chart_bottom - chart_top)),
            (0, 0, 0, 0),
        )
        gd = ImageDraw.Draw(grad)
        for gy in range(grad.height):
            t = 1 - (gy / max(grad.height - 1, 1))
            a = int(trend_dim[3] * t)
            gd.line([(0, gy), (grad.width, gy)], fill=(trend[0], trend[1], trend[2], a))
        mask = Image.new("L", (int(W), int(H)), 0)
        md = ImageDraw.Draw(mask)
        md.polygon(area, fill=255)
        mask_crop = mask.crop(
            (int(chart_left), int(chart_top), int(chart_right), int(chart_bottom))
        )
        grad_alpha = grad.split()[3]
        grad.putalpha(ImageChops.multiply(grad_alpha, mask_crop))
        canvas.alpha_composite(grad, (int(chart_left), int(chart_top)))

        # The line itself.
        draw.line(coords, fill=trend, width=S(3), joint="curve")

        # Mark the period high/low points.
        hi_i = closes.index(p_max)
        lo_i = closes.index(p_min)
        for idx, label in ((hi_i, "H"), (lo_i, "L")):
            x, y = coords[idx]
            draw.ellipse([x - S(4), y - S(4), x + S(4), y + S(4)], fill=TEXT_WHITE)

        # X-axis tick labels.
        tick_idxs = sorted(set([0, n // 4, n // 2, (3 * n) // 4, n - 1]))
        for i in tick_idxs:
            x, _ = coords[i]
            label = points[i][0].strftime(data["tick_format"])
            lw = _text_w(draw, label, f_axis)
            lx = min(max(x - lw / 2, chart_left), chart_right - lw)
            draw.text((lx, chart_bottom + S(10)), label, font=f_axis, fill=AXIS_TEXT)
    else:
        msg = "Not enough data for this period"
        f_msg = font("regular", 18)
        mw = _text_w(draw, msg, f_msg)
        draw.text(
            ((W - mw) / 2, (chart_top + chart_bottom) / 2),
            msg,
            font=f_msg,
            fill=TEXT_MUTED,
        )

    # ---- volume strip ----
    vol_top = S(395)
    vol_bottom = S(440)
    volumes = data.get("volumes") or []
    if volumes:
        draw.text((chart_left, vol_top - S(17)), "Volume", font=f_axis, fill=AXIS_TEXT)
        vmax = max(v[1] for v in volumes) or 1
        n = len(volumes)
        bar_w = max((chart_right - chart_left) / n * 0.7, S(1))
        for i, (_, vol, bar_up) in enumerate(volumes):
            x = chart_left + (i / max(n - 1, 1)) * (chart_right - chart_left)
            h = (vol / vmax) * (vol_bottom - vol_top)
            color = (
                (GREEN[0], GREEN[1], GREEN[2], 150)
                if bar_up
                else (RED[0], RED[1], RED[2], 150)
            )
            draw.rectangle(
                [x - bar_w / 2, vol_bottom - h, x + bar_w / 2, vol_bottom], fill=color
            )

    # ---- stats card ----
    card_top = S(460)
    card_h = H - card_top - S(30)
    card = _round_card((int(W - pad * 2), int(card_h)), S(22), CARD_BG)
    canvas.alpha_composite(card, (int(pad), int(card_top)))

    stats = [
        ("Day High", _fmt_price(data["day_high"], data["currency_symbol"])),
        ("Day Low", _fmt_price(data["day_low"], data["currency_symbol"])),
        ("Prev Close", _fmt_price(data["prev_close"], data["currency_symbol"])),
        ("Volume", _fmt_compact(data["day_volume"])),
        ("52W High", _fmt_price(data["week52_high"], data["currency_symbol"])),
        ("52W Low", _fmt_price(data["week52_low"], data["currency_symbol"])),
    ]
    col_w = (W - pad * 2) / len(stats)
    for i, (label, value) in enumerate(stats):
        cx = pad + col_w * i + col_w / 2
        lw = _text_w(draw, label, f_stat_label)
        draw.text(
            (cx - lw / 2, card_top + S(20)), label, font=f_stat_label, fill=TEXT_MUTED
        )
        vw = _text_w(draw, value, f_stat_value)
        draw.text(
            (cx - vw / 2, card_top + S(46)), value, font=f_stat_value, fill=TEXT_WHITE
        )
        if i > 0:
            draw.line(
                [
                    pad + col_w * i,
                    card_top + S(16),
                    pad + col_w * i,
                    card_top + card_h - S(16),
                ],
                fill=(255, 255, 255, 24),
                width=S(1),
            )

    final = canvas.resize((FW, FH), Image.LANCZOS)
    final.convert("RGB").save(out_path, "PNG")
    return out_path


def render_watchlist(data_items, out_path, cache_dir):
    """Render every watched stock into one vertically stacked PNG."""
    if not data_items:
        raise ValueError("Your watchlist is empty. Add a stock first.")
    cards = []
    for index, data in enumerate(data_items):
        card_path = os.path.join(cache_dir, f"watch-card-{index}.png")
        render_chart(data, card_path)
        with Image.open(card_path) as card:
            cards.append(card.convert("RGB").copy())
    header_height, gap = 76, 16
    width = max(card.width for card in cards)
    height = header_height + sum(card.height for card in cards) + gap * (len(cards) - 1)
    image = _vertical_gradient((width, height), BG_TOP, BG_BOTTOM).convert("RGB")
    draw = ImageDraw.Draw(image)
    draw.text((32, 16), "WATCHLIST", font=font("bold", 13), fill=TEXT_WHITE)
    draw.text(
        (32, 46),
        f"{len(cards)} stock{'s' if len(cards) != 1 else ''} · {data_items[0]['period_label']}",
        font=font("regular", 8),
        fill=TEXT_MUTED,
    )
    y = header_height
    for card in cards:
        image.paste(card, (0, y))
        y += card.height + gap
    image.save(out_path, "PNG")
    return out_path
