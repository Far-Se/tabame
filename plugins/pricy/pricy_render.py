"""Render the image shown for a Pricy product comparison."""

from __future__ import annotations

import datetime as _dt
import math
import os
from typing import Any

from PIL import Image, ImageDraw, ImageFont, ImageOps


SCALE = 2
WIDTH = 1400
HEIGHT = 760

_FONT_CACHE: dict[tuple[int, bool], ImageFont.FreeTypeFont | ImageFont.ImageFont] = {}


def _scale(value: float) -> int:
    return int(round(value * SCALE))


def _font(size: int, bold: bool = False):
    key = (size, bold)
    if key in _FONT_CACHE:
        return _FONT_CACHE[key]

    windows_dir = os.environ.get("WINDIR", r"C:\Windows")
    candidates = (
        ("segoeuib.ttf", "arialbd.ttf", "calibrib.ttf")
        if bold
        else ("segoeui.ttf", "arial.ttf", "calibri.ttf")
    )
    result = None
    for name in candidates:
        path = os.path.join(windows_dir, "Fonts", name)
        if os.path.isfile(path):
            try:
                result = ImageFont.truetype(path, _scale(size))
                break
            except OSError:
                pass

    if result is None:
        result = ImageFont.load_default()
    _FONT_CACHE[key] = result
    return result


def _color(value: Any, fallback: tuple[int, int, int]) -> tuple[int, int, int]:
    if not isinstance(value, str):
        return fallback
    raw = value.strip().lstrip("#")
    if len(raw) == 3:
        raw = "".join(ch * 2 for ch in raw)
    if len(raw) == 8:
        raw = raw[2:]
    if len(raw) != 6:
        return fallback
    try:
        return tuple(int(raw[i : i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        return fallback


def _palette(theme: dict[str, Any] | None) -> dict[str, tuple[int, int, int]]:
    theme = theme or {}
    dark = bool(theme.get("dark", True))
    if dark:
        defaults = {
            "background": (19, 22, 29),
            "panel": (29, 34, 44),
            "panel_alt": (36, 42, 54),
            "text": (242, 245, 249),
            "muted": (157, 168, 183),
            "grid": (57, 66, 82),
            "accent": (106, 168, 255),
            "accent_soft": (38, 72, 116),
            "green": (59, 211, 148),
            "red": (241, 117, 129),
            "gold": (246, 190, 76),
        }
    else:
        defaults = {
            "background": (246, 248, 251),
            "panel": (255, 255, 255),
            "panel_alt": (238, 243, 248),
            "text": (29, 35, 44),
            "muted": (101, 113, 128),
            "grid": (216, 224, 234),
            "accent": (45, 107, 205),
            "accent_soft": (221, 234, 252),
            "green": (25, 157, 102),
            "red": (205, 71, 85),
            "gold": (190, 132, 13),
        }

    return {
        **defaults,
        "background": _color(theme.get("background"), defaults["background"]),
        "text": _color(theme.get("text"), defaults["text"]),
        "accent": _color(theme.get("accent"), defaults["accent"]),
    }


def _rounded_rectangle(draw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(
        tuple(_scale(v) for v in box),
        radius=_scale(radius),
        fill=fill,
        outline=outline,
        width=max(1, _scale(width)),
    )


def _text(draw, position, value, size, fill, bold=False, anchor=None):
    kwargs = {"font": _font(size, bold), "fill": fill}
    if anchor is not None:
        kwargs["anchor"] = anchor
    draw.text(tuple(_scale(v) for v in position), str(value), **kwargs)


def _text_width(draw, value, size, bold=False) -> float:
    return draw.textlength(str(value), font=_font(size, bold)) / SCALE


def _truncate(draw, value, max_width, size, bold=False) -> str:
    value = str(value or "")
    if _text_width(draw, value, size, bold) <= max_width:
        return value
    suffix = "..."
    while value and _text_width(draw, value + suffix, size, bold) > max_width:
        value = value[:-1]
    return value + suffix if value else suffix


def _price(value: Any, currency: Any = "RON") -> str:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return "-"
    currency = str(currency or "RON").upper()
    return f"{number:,.2f} {currency}"


def _domain(record: dict[str, Any]) -> str:
    return str(record.get("domain") or record.get("store") or "store")


def _draw_logo(canvas, draw, logo, domain, x, y, size, colors):
    """Draw a favicon or a deterministic letter fallback."""
    _rounded_rectangle(draw, (x, y, x + size, y + size), 9, colors["panel_alt"])
    if logo is not None:
        try:
            image = ImageOps.contain(
                logo.convert("RGBA"),
                (_scale(size - 8), _scale(size - 8)),
                method=Image.Resampling.LANCZOS,
            )
            image_x = _scale(x) + (_scale(size) - image.width) // 2
            image_y = _scale(y) + (_scale(size) - image.height) // 2
            canvas.paste(image, (image_x, image_y), image)
            return
        except Exception:
            pass

    initial = (domain or "?").strip().lstrip("www.")[:1].upper() or "?"
    _text(draw, (x + size / 2, y + size / 2 + 1), initial, 15, colors["accent"], True, "mm")


def _parse_timestamp(value: Any) -> _dt.datetime | None:
    if isinstance(value, (int, float)):
        number = float(value)
        if number > 10_000_000_000:
            number /= 1000
        try:
            return _dt.datetime.fromtimestamp(number, tz=_dt.timezone.utc)
        except (OverflowError, OSError, ValueError):
            return None
    if not isinstance(value, str):
        return None
    try:
        return _dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _history_points(history):
    points = []
    for entry in history or []:
        if not isinstance(entry, dict):
            continue
        try:
            value = float(entry.get("price"))
        except (TypeError, ValueError):
            continue
        stamp = _parse_timestamp(entry.get("timestamp"))
        if stamp is not None and math.isfinite(value):
            points.append((stamp, value))
    return sorted(points, key=lambda point: point[0])


def _draw_history(draw, canvas, history, x, y, width, height, colors, currency):
    points = _history_points(history)
    left = x + 52
    right = x + width - 20
    top = y + 48
    bottom = y + height - 44

    if not points:
        _text(draw, (x + width / 2, y + height / 2), "No price history returned", 16, colors["muted"], anchor="mm")
        return

    values = [value for _, value in points]
    minimum = min(values)
    maximum = max(values)
    span = maximum - minimum
    if span <= 0:
        span = max(abs(maximum) * 0.08, 1.0)
        minimum -= span / 2
        maximum += span / 2

    for index in range(5):
        ratio = index / 4
        line_y = bottom - ratio * (bottom - top)
        draw.line(
            (_scale(left), _scale(line_y), _scale(right), _scale(line_y)),
            fill=colors["grid"],
            width=_scale(1),
        )
        label = _price(minimum + ratio * (maximum - minimum), currency)
        _text(draw, (x + 3, line_y - 7), label, 10, colors["muted"])

    def point_at(index, value):
        x_value = left + (index / max(len(points) - 1, 1)) * (right - left)
        y_value = bottom - ((value - minimum) / (maximum - minimum)) * (bottom - top)
        return _scale(x_value), _scale(y_value)

    # Keep the chart readable when the endpoint returns a very dense series.
    step = max(1, math.ceil(len(points) / 180))
    sampled = points[::step]
    if sampled[-1] != points[-1]:
        sampled.append(points[-1])
    sampled_points = []
    for index, (_, value) in enumerate(sampled):
        original_index = min(index * step, len(points) - 1)
        sampled_points.append(point_at(original_index, value))

    area = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    area_draw = ImageDraw.Draw(area)
    area_polygon = sampled_points + [(sampled_points[-1][0], _scale(bottom)), (sampled_points[0][0], _scale(bottom))]
    area_draw.polygon(area_polygon, fill=(*colors["accent"], 42))
    canvas.alpha_composite(area)
    draw.line(sampled_points, fill=colors["accent"], width=_scale(3), joint="curve")

    last_x, last_y = sampled_points[-1]
    draw.ellipse(
        (last_x - _scale(5), last_y - _scale(5), last_x + _scale(5), last_y + _scale(5)),
        fill=colors["accent"],
        outline=colors["background"],
        width=_scale(2),
    )

    first_date = points[0][0].strftime("%b %d, %Y")
    last_date = points[-1][0].strftime("%b %d, %Y")
    _text(draw, (left, bottom + 16), first_date, 10, colors["muted"])
    _text(draw, (right, bottom + 16), last_date, 10, colors["muted"], anchor="ra")
    _text(draw, (x + 2, y + 10), f"Low {_price(min(values), currency)}", 11, colors["green"], True)
    _text(draw, (x + width - 2, y + 10), f"High {_price(max(values), currency)}", 11, colors["red"], True, "ra")


def render_price_card(
    output_path: str,
    product_url: str,
    lowest: dict[str, Any],
    alternatives: list[dict[str, Any]],
    history: list[dict[str, Any]],
    logos: dict[str, Any],
    theme: dict[str, Any] | None = None,
) -> None:
    """Create a comparison card with store alternatives and price history."""
    colors = _palette(theme)
    canvas = Image.new("RGBA", (_scale(WIDTH), _scale(HEIGHT)), (*colors["background"], 255))
    draw = ImageDraw.Draw(canvas)

    # Header.
    _rounded_rectangle(draw, (28, 24, WIDTH - 28, 124), 18, colors["panel"])
    _text(draw, (52, 43), "CURRENT LOWEST", 11, colors["muted"], True)
    _text(draw, (52, 62), _price(lowest.get("price"), lowest.get("currency")), 29, colors["text"], True)
    lowest_domain = _domain(lowest)
    _draw_logo(canvas, draw, logos.get(lowest_domain), lowest_domain, 286, 50, 48, colors)
    _text(draw, (348, 57), "Lowest at", 11, colors["muted"])
    _text(draw, (348, 75), _truncate(draw, lowest_domain, 180, 17, True), 17, colors["text"], True)
    _text(draw, (570, 43), "PRODUCT", 11, colors["muted"], True)
    _text(draw, (570, 62), _truncate(draw, product_url, 570, 16), 16, colors["text"])
    _text(draw, (570, 88), "365-day price history and current alternatives", 12, colors["muted"])
    _text(draw, (WIDTH - 52, 45), "PRICY", 16, colors["accent"], True, "ra")
    _text(draw, (WIDTH - 52, 69), "PRICE CHECK", 10, colors["muted"], True, "ra")

    # Main panels.
    _rounded_rectangle(draw, (28, 144, 506, HEIGHT - 28), 18, colors["panel"])
    _rounded_rectangle(draw, (526, 144, WIDTH - 28, HEIGHT - 28), 18, colors["panel"])
    _text(draw, (54, 166), "BEST ALTERNATIVES", 13, colors["text"], True)
    _text(draw, (54, 188), "Available stores first, then unavailable offers", 11, colors["muted"])

    visible = alternatives[:9]
    max_price = max(
        [float(item.get("price")) for item in visible if item.get("price") is not None] or [1.0]
    )
    min_price = min(
        [float(item.get("price")) for item in visible if item.get("price") is not None] or [0.0]
    )
    price_span = max(max_price - min_price, 1.0)
    row_y = 211
    for index, item in enumerate(visible):
        row_top = row_y + index * 47
        if index % 2 == 0:
            _rounded_rectangle(draw, (44, row_top - 3, 490, row_top + 40), 10, colors["panel_alt"])
        domain = _domain(item)
        _draw_logo(canvas, draw, logos.get(domain), domain, 54, row_top + 2, 32, colors)
        _text(draw, (99, row_top + 5), _truncate(draw, domain, 160, 14, True), 14, colors["text"], True)
        available = bool(item.get("isAvailable", True))
        status = "Available" if available else "Unavailable"
        if item.get("isSecondHand"):
            status = "Second-hand"
        _text(draw, (99, row_top + 24), status, 10, colors["green"] if available else colors["muted"])
        try:
            current_price = float(item.get("price"))
        except (TypeError, ValueError):
            current_price = None
        _text(
            draw,
            (471, row_top + 7),
            _price(current_price, item.get("currency")),
            13,
            colors["text"] if available else colors["muted"],
            True,
            "ra",
        )
        if current_price is not None:
            ratio = max(0.0, min(1.0, (current_price - min_price) / price_span))
            bar_width = 74 * (1.0 - ratio * 0.75)
            draw.rounded_rectangle(
                (_scale(393), _scale(row_top + 29), _scale(393 + bar_width), _scale(row_top + 32)),
                radius=_scale(2),
                fill=colors["green"] if available else colors["grid"],
            )

    if len(alternatives) > len(visible):
        _text(draw, (54, 211 + len(visible) * 47 + 5), f"+ {len(alternatives) - len(visible)} more offers", 11, colors["muted"])

    # History chart.
    _text(draw, (552, 166), "PRICE HISTORY", 13, colors["text"], True)
    _text(draw, (552, 188), "Pricy data for the last 365 days", 11, colors["muted"])
    _draw_history(draw, canvas, history, 552, 211, 786, 422, colors, lowest.get("currency"))

    _text(draw, (54, HEIGHT - 48), "Data provided by pricy.ro", 10, colors["muted"])
    _text(draw, (WIDTH - 52, HEIGHT - 48), "Open an alternative from the metadata rows", 10, colors["muted"], anchor="ra")

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    canvas.convert("RGB").resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS).save(output_path, format="PNG", optimize=True)
