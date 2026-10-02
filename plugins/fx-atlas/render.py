"""Data-driven, high-resolution exchange cards. All chart points are observations."""

import os
from datetime import date
from decimal import Decimal, ROUND_HALF_UP
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

WIDTH, HEIGHT = 1440, 740
RENDER_VERSION = 3
ZERO_DIGITS = set("BIF CLP DJF GNF ISK JPY KMF KRW PYG RWF UGX UYI VND VUV XAF XOF XPF".split())
THREE_DIGITS = set("BHD IQD JOD KWD LYD OMR TND".split())
FOUR_DIGITS = {"CLF", "UYW"}


def money(value, currency, grouped=True):
    digits = 0 if currency in ZERO_DIGITS else 3 if currency in THREE_DIGITS else 4 if currency in FOUR_DIGITS else 2
    rounded = Decimal(str(value)).quantize(Decimal(1).scaleb(-digits), rounding=ROUND_HALF_UP)
    return format(rounded, f",.{digits}f" if grouped else f".{digits}f")


def rate_text(value):
    value = Decimal(str(value))
    if not value:
        return "0"
    # Six significant digits remain legible even for very small exchange rates.
    digits = max(0, 5 - value.adjusted())
    text = f"{value:,.{digits}f}"
    return text.rstrip("0").rstrip(".") if "." in text else text


@lru_cache(maxsize=96)
def font(size, style="regular"):
    fonts = Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts"
    names = {"regular": "segoeui.ttf", "bold": "seguisb.ttf", "display": "georgia.ttf"}
    for candidate in (fonts / names[style], "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(str(candidate), size)
        except OSError:
            pass
    return ImageFont.load_default(size=size)


def render_card(quote, amount, base, target, days, output, dark=True):
    """Render a PNG without inventing missing history or interpolated observations."""
    palette = (
        {"bg": "#151D1C", "panel": "#1D2926", "ink": "#F1F0E5", "muted": "#A6B7AF",
         "line": "#35483F", "accent": "#B8D4AD", "negative": "#E5AE93", "chip": "#2D3F34"}
        if dark else
        {"bg": "#F3F1E8", "panel": "#E8EBDD", "ink": "#233B30", "muted": "#586A5C",
         "line": "#CBD2C3", "accent": "#3B684C", "negative": "#965333", "chip": "#D9E3CE"}
    )
    p = palette
    im = Image.new("RGB", (WIDTH, HEIGHT), p["bg"])
    draw = ImageDraw.Draw(im)

    def text(x, y, value, size=24, color=None, style="regular", anchor=None, max_width=None):
        value = str(value)
        face = font(size, style)
        while max_width and draw.textlength(value, font=face) > max_width and size > 14:
            size -= 1
            face = font(size, style)
        draw.text((x, y), value, font=face, fill=color or p["ink"], anchor=anchor)

    def line(x1, y1, x2, y2, color=None, width=1):
        draw.line((x1, y1, x2, y2), fill=color or p["line"], width=width)

    def date_label(value):
        return date.fromisoformat(value).strftime("%d %b")

    rate = Decimal(str(quote["rate"]))
    result = amount * rate
    observations = quote["history"]
    values = [float(row["rate"]) for row in observations]
    enough = len(values) >= 2
    change = (values[-1] / values[0] - 1) * 100 if enough else 0
    trend = p["accent"] if change >= 0 else p["negative"]

    # One conversion row beside a compact three-line reference block.
    original = money(amount, base)
    if Decimal(original.replace(",", "")) != amount:
        original = format(amount, ",f")
    text(64, 80, f"{original} {base} = {money(result, target)} {target}",
         50, style="display", anchor="lm", max_width=790)

    draw.rounded_rectangle((896, 16, 1376, 140), radius=20, fill=p["panel"])
    text(928, 28, f"1 {base} = {rate_text(rate)} {target}", 26, style="bold", max_width=416)
    text(928, 67, f"1 {target} = {rate_text(1 / rate)} {base}", 23, max_width=416)
    rate_label = "Cached rate" if quote.get("stale") else "Rate date"
    text(928, 104, f"{rate_label}  {quote['date']}", 21, p["muted"])

    line(64, 160, 1376, 160)
    text(64, 186, "RATE HISTORY", 22, style="bold")
    text(276, 187, f"{target} per 1 {base}", 22, p["muted"])
    badge = f"{change:+.2f}%   /   {days}D" if enough else f"{days}D WINDOW"
    draw.rounded_rectangle((1110, 178, 1376, 222), radius=22, fill=p["chip"])
    text(1243, 185, badge, 23, trend, "bold", anchor="ma")

    left, right, top, bottom = 64, 1234, 268, 492
    if enough:
        lo, hi = min(values), max(values)
        padding = max((hi - lo) * 0.18, abs(hi) * 0.0003, 1e-12)
        low, high = lo - padding, hi + padding
        start = date.fromisoformat(observations[0]["date"]).toordinal()
        end = date.fromisoformat(observations[-1]["date"]).toordinal()
        points = [
            (left + (date.fromisoformat(row["date"]).toordinal() - start) / max(1, end - start) * (right - left),
             bottom - (float(row["rate"]) - low) / (high - low) * (bottom - top))
            for row in observations
        ]

        # A translucent area integrates the chart into the canvas, without a glow.
        mask = Image.new("L", im.size)
        ImageDraw.Draw(mask).polygon([(left, bottom), *points, (right, bottom)], fill=255)
        wash = Image.new("RGB", im.size, trend)
        alpha = Image.new("L", im.size)
        alpha_draw = ImageDraw.Draw(alpha)
        for y in range(top, bottom + 1):
            opacity = int(48 * (1 - (y - top) / (bottom - top)) + 3)
            alpha_draw.line((left, y, right, y), fill=opacity)
        im.paste(wash, (0, 0), ImageChops.multiply(mask, alpha))
        draw = ImageDraw.Draw(im)

        for n in range(4):
            y = top + n * (bottom - top) / 3
            line(left, y, right, y)
            text(1376, y - 13, rate_text(high - n * (high - low) / 3), 21, p["muted"], anchor="ra", max_width=126)
        for n in range(5):
            x = left + n * (right - left) / 4
            for y in range(top, bottom, 9):
                line(x, y, x, y + 2)

        # Straight segments preserve actual observations; no fabricated spline peaks.
        draw.line(points, fill=trend, width=4, joint="curve")
        x, y = points[-1]
        draw.ellipse((x - 9, y - 9, x + 9, y + 9), fill=p["bg"], outline=trend, width=3)
        draw.ellipse((x - 3, y - 3, x + 3, y + 3), fill=trend)
        text(left, 508, date_label(observations[0]["date"]), 21, p["muted"])
        middle = date.fromordinal((start + end) // 2).isoformat()
        text((left + right) / 2, 508, date_label(middle), 21, p["muted"], anchor="ma")
        text(right, 508, date_label(observations[-1]["date"]), 21, p["muted"], anchor="ra")
    else:
        if base == target:
            text(64, 304, "Same currency. Same value.", 33, p["muted"])
            text(64, 360, "An identity conversion always uses a rate of one.", 24, p["muted"])
        else:
            text(64, 304, "History is unavailable for this pair.", 33, p["muted"])
            text(64, 360, "The conversion uses the dated reference rate above.", 24, p["muted"])

    line(64, 562, 1376, 562)
    stats = [
        (64, "PERIOD LOW", rate_text(min(values)) if enough else "—"),
        (438, "PERIOD HIGH", rate_text(max(values)) if enough else "—"),
        (812, "PERIOD CHANGE", f"{change:+.2f}%" if enough else "—"),
    ]
    for x, label, value in stats:
        text(x, 584, label, 18, p["muted"])
        text(x, 612, value, 35, trend if "CHANGE" in label else p["ink"], max_width=325)
    text(1376, 590, f"{len(values)} observations", 21, p["muted"], anchor="ra")
    text(1376, 627, f"{days}-day window", 21, p["muted"], anchor="ra")
    line(64, 680, 1376, 680)
    source = "Identity rate · no market quote" if base == target else "Frankfurter · daily reference rates · fees excluded"
    text(64, 698, source, 19, p["muted"])
    text(1376, 698, "Tabame Launcher", 19, p["accent"], "bold", anchor="ra")
    Path(output).parent.mkdir(parents=True, exist_ok=True)
    im.save(output, "PNG", optimize=True)
    return result
