"""Renders the 'nice image' shown for a currency conversion: a dark,
trading-app style card with a converted amount, a rate area-chart, and
a stats row (period high/low/open, inverse rate).

Everything is drawn at 2x resolution and downscaled at the end so lines,
curves and text all come out anti-aliased. Layout mirrors stock_render.py
so a "curr" card and a "stock" card feel like siblings.
"""

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
        path = os.path.join(FONT_DIR, name)
        try:
            _FONT_CACHE[key] = ImageFont.truetype(path, size * SCALE)
        except OSError:
            # No fonts/ folder shipped with this plugin (copy it over from
            # the stock plugin for a nicer look) — fall back gracefully.
            try:
                _FONT_CACHE[key] = ImageFont.load_default(size=size * SCALE)
            except TypeError:
                _FONT_CACHE[key] = ImageFont.load_default()
    return _FONT_CACHE[key]


def S(v):
    return v * SCALE


# ---- palette (dark, trading-terminal feel — same as stock_render.py) ------
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

CURRENCY_SYMBOLS = {
    "USD": "$",
    "EUR": "€",
    "GBP": "£",
    "JPY": "¥",
    "CAD": "C$",
    "AUD": "A$",
    "CHF": "CHF ",
}


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


def _draw_trend_arrow(draw, x, y_center, size, color, up):
    """Draws a small filled triangle instead of a Unicode ↑/↓ glyph, since
    Lato (and PIL's bitmap fallback font) don't reliably contain those
    codepoints and render a tofu box instead."""
    half = size / 2
    if up:
        pts = [
            (x, y_center - half),
            (x - half, y_center + half),
            (x + half, y_center + half),
        ]
    else:
        pts = [
            (x, y_center + half),
            (x - half, y_center - half),
            (x + half, y_center - half),
        ]
    draw.polygon(pts, fill=color)
    return size


def _fmt_rate(v):
    """FX rates span wildly different magnitudes (0.86 EUR/GBP vs 155 JPY/USD)
    so pick a precision that keeps them readable."""
    av = abs(v)
    if av >= 100:
        return f"{v:,.2f}"
    if av >= 1:
        return f"{v:,.4f}"
    return f"{v:,.6f}"


def _fmt_amount(v, code):
    symbol = CURRENCY_SYMBOLS.get(code)
    if symbol:
        return f"{symbol}{v:,.2f}"
    return f"{v:,.2f} {code}"


def render_chart(data, out_path):
    """data keys:
    from_code, to_code, amount, converted, rate, rate_change, rate_change_pct,
    period_label, as_of, points (list of (datetime, rate)),
    period_high, period_low, period_open, inverse_rate, tick_format
    (strftime string for x-axis labels)
    """
    FW, FH = (
        960,
        520,
    )  # final (post-downscale) size — no volume strip, so shorter than stock's
    W, H = S(FW), S(FH)
    canvas = _vertical_gradient((W, H), BG_TOP, BG_BOTTOM).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    up = data["rate_change"] >= 0
    trend = GREEN if up else RED
    trend_dim = GREEN_DIM if up else RED_DIM

    f_pair = font("bold", 38)
    f_name = font("regular", 19)
    f_price = font("bold", 40)
    f_change = font("bold", 20)
    f_chip = font("bold", 16)
    f_asof = font("regular", 15)
    f_axis = font("regular", 15)
    f_stat_label = font("regular", 16)
    f_stat_value = font("bold", 20)

    pad = S(40)

    # ---- header ----
    pair_text = f"{data['from_code']} / {data['to_code']}"
    draw.text((pad, pad), pair_text, font=f_pair, fill=TEXT_WHITE)
    sw = _text_w(draw, pair_text, f_pair)

    chip_text = "ECB REF"
    chip_pad_x, chip_pad_y = S(10), S(5)
    chip_w = _text_w(draw, chip_text, f_chip) + chip_pad_x * 2
    chip_h = S(24)
    chip_x = pad + sw + S(14)
    chip_y = pad + S(6)
    chip = _round_card((chip_w, chip_h), chip_h // 2, CHIP_BG)
    canvas.alpha_composite(chip, (int(chip_x), int(chip_y)))
    draw.text(
        (chip_x + chip_pad_x, chip_y + chip_h / 2 - S(9)),
        chip_text,
        font=f_chip,
        fill=AXIS_TEXT,
    )

    subtitle = f"1 {data['from_code']} = {_fmt_rate(data['rate'])} {data['to_code']}"
    draw.text((pad, pad + S(48)), subtitle, font=f_name, fill=TEXT_MUTED)

    price_text = f"{_fmt_amount(data['amount'], data['from_code'])} = {_fmt_amount(data['converted'], data['to_code'])}"
    pw = _text_w(draw, price_text, f_price)
    px = max(W - pad - pw, pad)
    draw.text((px, pad), price_text, font=f_price, fill=TEXT_WHITE)

    change_text = (
        f"{_fmt_rate(abs(data['rate_change']))}  ({abs(data['rate_change_pct']):.2f}%)"
    )
    cw = _text_w(draw, change_text, f_change)
    arrow_size = S(13)
    arrow_gap = S(8)
    change_y = pad + S(52)
    text_bbox = draw.textbbox((0, 0), change_text, font=f_change)
    text_h = text_bbox[3] - text_bbox[1]
    row_center_y = change_y + text_h / 2
    text_x = W - pad - cw
    arrow_x = text_x - arrow_gap - arrow_size / 2
    _draw_trend_arrow(draw, arrow_x, row_center_y, arrow_size, trend, up)
    draw.text((text_x, change_y), change_text, font=f_change, fill=trend)

    period_text = f"{data['period_label']} · {data['as_of']}"
    ptw = _text_w(draw, period_text, f_asof)
    draw.text((W - pad - ptw, pad + S(82)), period_text, font=f_asof, fill=TEXT_MUTED)

    # ---- chart area (taller than stock's since there's no volume strip) ----
    chart_top = S(160)
    chart_bottom = S(375)
    chart_left = pad
    chart_right = W - pad

    points = data["points"]
    if len(points) >= 2:
        rates = [p[1] for p in points]
        p_min, p_max = min(rates), max(rates)
        if p_max == p_min:
            span_pad = p_max * 0.01 if p_max else 1
            p_max += span_pad
            p_min -= span_pad
        p_span = p_max - p_min

        for i in range(4):
            t = i / 3
            y = chart_bottom - t * (chart_bottom - chart_top)
            draw.line([chart_left, y, chart_right, y], fill=GRID_COLOR, width=S(1))
            lvl = p_min + t * p_span
            label = _fmt_rate(lvl)
            lw = _text_w(draw, label, f_axis)
            draw.text((chart_right - lw, y - S(20)), label, font=f_axis, fill=AXIS_TEXT)

        n = len(points)

        def xy(i):
            x = chart_left + (i / (n - 1)) * (chart_right - chart_left)
            y = chart_bottom - (rates[i] - p_min) / p_span * (chart_bottom - chart_top)
            return x, y

        coords = [xy(i) for i in range(n)]

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

        draw.line(coords, fill=trend, width=S(3), joint="curve")

        hi_i = (
            rates.index(p_max)
            if p_max in rates
            else max(range(n), key=lambda i: rates[i])
        )
        lo_i = (
            rates.index(p_min)
            if p_min in rates
            else min(range(n), key=lambda i: rates[i])
        )
        for idx in (hi_i, lo_i):
            x, y = coords[idx]
            draw.ellipse([x - S(4), y - S(4), x + S(4), y + S(4)], fill=TEXT_WHITE)

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

    # ---- stats card ----
    card_top = S(420)
    card_h = H - card_top - S(16)
    card = _round_card((int(W - pad * 2), int(card_h)), S(22), CARD_BG)
    canvas.alpha_composite(card, (int(pad), int(card_top)))

    stats = [
        ("Period High", _fmt_rate(data["period_high"])),
        ("Period Low", _fmt_rate(data["period_low"])),
        ("Period Open", _fmt_rate(data["period_open"])),
        (
            "Inverse Rate",
            f"1 {data['to_code']} = {_fmt_rate(data['inverse_rate'])} {data['from_code']}",
        ),
    ]

    # Vertically center the label+value block inside the card instead of
    # pinning it to fixed offsets from the top (which left it hugging the
    # bottom of the card with a big empty gap above it).
    label_bbox = draw.textbbox((0, 0), "Period High", font=f_stat_label)
    value_bbox = draw.textbbox((0, 0), "0.00", font=f_stat_value)
    label_h = label_bbox[3] - label_bbox[1]
    value_h = value_bbox[3] - value_bbox[1]
    row_gap = S(10)
    content_h = label_h + row_gap + value_h
    top_pad = max((card_h - content_h) / 2, S(14))
    label_y = card_top + top_pad - label_bbox[1]
    value_y = card_top + top_pad + label_h + row_gap - value_bbox[1]

    col_w = (W - pad * 2) / len(stats)
    for i, (label, value) in enumerate(stats):
        cx = pad + col_w * i + col_w / 2
        lw = _text_w(draw, label, f_stat_label)
        draw.text((cx - lw / 2, label_y), label, font=f_stat_label, fill=TEXT_MUTED)
        vw = _text_w(draw, value, f_stat_value)
        vx = cx - vw / 2
        # last column's value can be wide ("1 EUR = 1.081234 USD") — keep it on-card
        vx = max(min(vx, W - pad - vw - S(8)), pad + S(8))
        draw.text((vx, value_y), value, font=f_stat_value, fill=TEXT_WHITE)
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
    """Render every favorite pair into one vertically stacked PNG."""
    if not data_items:
        raise ValueError("Your favorites list is empty. Add a pair first.")
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
    draw.text((32, 16), "FAVORITE PAIRS", font=font("bold", 13), fill=TEXT_WHITE)
    draw.text(
        (32, 46),
        f"{len(cards)} pair{'s' if len(cards) != 1 else ''} · {data_items[0]['period_label']}",
        font=font("regular", 8),
        fill=TEXT_MUTED,
    )
    y = header_height
    for card in cards:
        image.paste(card, (0, y))
        y += card.height + gap
    image.save(out_path, "PNG")
    return out_path
