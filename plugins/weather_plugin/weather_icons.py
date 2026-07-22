"""Simple vector-style weather icons drawn with Pillow.

No external icon assets are needed - everything is drawn with basic
shapes at a supersampled resolution then downscaled for smooth edges.
"""

from PIL import Image, ImageDraw

SUN_YELLOW = (255, 185, 60, 255)
SUN_YELLOW_SOFT = (255, 200, 90, 255)
CLOUD_WHITE = (255, 255, 255, 255)
CLOUD_GRAY = (200, 206, 215, 255)
CLOUD_DARK = (150, 158, 170, 255)
RAIN_BLUE = (86, 150, 235, 255)
SNOW_WHITE = (255, 255, 255, 255)
BOLT_YELLOW = (255, 210, 60, 255)
FOG_GRAY = (210, 216, 224, 255)

SUPERSAMPLE = 4


def _canvas(size):
    s = size * SUPERSAMPLE
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def _finish(img, size):
    return img.resize((size, size), Image.LANCZOS)


def _draw_cloud(draw, cx, cy, w, color, shadow=None):
    """Draw a puffy cloud centered at (cx, cy) with total width w."""
    r1 = w * 0.20
    r2 = w * 0.26
    r3 = w * 0.18
    base_y = cy + w * 0.06
    body_h = w * 0.20
    draw.ellipse([cx - w * 0.36, base_y - r1, cx - w * 0.36 + 2 * r1, base_y + r1], fill=color)
    draw.ellipse([cx - w * 0.08, base_y - r2 * 1.3, cx - w * 0.08 + 2 * r2, base_y + r2 * 0.7], fill=color)
    draw.ellipse([cx + w * 0.18, base_y - r3, cx + w * 0.18 + 2 * r3, base_y + r3], fill=color)
    draw.rounded_rectangle(
        [cx - w * 0.42, base_y - body_h * 0.2, cx + w * 0.42, base_y + body_h],
        radius=body_h * 0.9,
        fill=color,
    )


def draw_clear(size):
    img, d = _canvas(size)
    s = size * SUPERSAMPLE
    cx, cy = s / 2, s / 2
    r = s * 0.24
    for i in range(12):
        import math
        ang = math.radians(i * 30)
        x1, y1 = cx + math.cos(ang) * r * 1.35, cy + math.sin(ang) * r * 1.35
        x2, y2 = cx + math.cos(ang) * r * 1.75, cy + math.sin(ang) * r * 1.75
        d.line([x1, y1, x2, y2], fill=SUN_YELLOW, width=int(s * 0.035))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=SUN_YELLOW)
    return _finish(img, size)


def draw_partly_cloudy(size):
    img, d = _canvas(size)
    s = size * SUPERSAMPLE
    cx, cy = s * 0.36, s * 0.38
    r = s * 0.19
    import math
    for i in range(8):
        ang = math.radians(i * 45 + 20)
        x1, y1 = cx + math.cos(ang) * r * 1.3, cy + math.sin(ang) * r * 1.3
        x2, y2 = cx + math.cos(ang) * r * 1.62, cy + math.sin(ang) * r * 1.62
        d.line([x1, y1, x2, y2], fill=SUN_YELLOW_SOFT, width=int(s * 0.03))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=SUN_YELLOW_SOFT)
    _draw_cloud(d, s * 0.54, s * 0.58, s * 0.72, CLOUD_WHITE)
    return _finish(img, size)


def draw_cloudy(size):
    img, d = _canvas(size)
    s = size * SUPERSAMPLE
    _draw_cloud(d, s * 0.44, s * 0.46, s * 0.62, CLOUD_DARK)
    _draw_cloud(d, s * 0.56, s * 0.60, s * 0.72, CLOUD_GRAY)
    return _finish(img, size)


def draw_fog(size):
    img, d = _canvas(size)
    s = size * SUPERSAMPLE
    _draw_cloud(d, s * 0.5, s * 0.40, s * 0.62, CLOUD_GRAY)
    for i, y in enumerate([0.62, 0.74, 0.86]):
        w = s * (0.62 - i * 0.06)
        d.rounded_rectangle(
            [s * 0.5 - w / 2, s * y, s * 0.5 + w / 2, s * y + s * 0.05],
            radius=s * 0.025,
            fill=FOG_GRAY,
        )
    return _finish(img, size)


def draw_rain(size):
    img, d = _canvas(size)
    s = size * SUPERSAMPLE
    _draw_cloud(d, s * 0.5, s * 0.38, s * 0.68, CLOUD_DARK)
    for x in [0.32, 0.48, 0.64, 0.80]:
        d.line(
            [s * x, s * 0.62, s * (x - 0.06), s * 0.86],
            fill=RAIN_BLUE,
            width=int(s * 0.035),
        )
    return _finish(img, size)


def draw_snow(size):
    img, d = _canvas(size)
    s = size * SUPERSAMPLE
    _draw_cloud(d, s * 0.5, s * 0.38, s * 0.68, CLOUD_GRAY)
    import math
    for x in [0.34, 0.5, 0.66]:
        cxp, cyp = s * x, s * 0.78
        r = s * 0.05
        for i in range(6):
            ang = math.radians(i * 60)
            d.line(
                [cxp, cyp, cxp + math.cos(ang) * r, cyp + math.sin(ang) * r],
                fill=SNOW_WHITE,
                width=int(s * 0.018),
            )
    return _finish(img, size)


def draw_thunder(size):
    img, d = _canvas(size)
    s = size * SUPERSAMPLE
    _draw_cloud(d, s * 0.5, s * 0.36, s * 0.68, CLOUD_DARK)
    bolt = [
        (s * 0.54, s * 0.56),
        (s * 0.42, s * 0.76),
        (s * 0.50, s * 0.76),
        (s * 0.44, s * 0.94),
        (s * 0.62, s * 0.70),
        (s * 0.53, s * 0.70),
    ]
    d.polygon(bolt, fill=BOLT_YELLOW)
    return _finish(img, size)


_DRAW_FUNCS = {
    "clear": draw_clear,
    "partly_cloudy": draw_partly_cloudy,
    "cloudy": draw_cloudy,
    "fog": draw_fog,
    "rain": draw_rain,
    "snow": draw_snow,
    "thunder": draw_thunder,
}

_CODE_TO_CATEGORY = {
    0: "clear",
    1: "partly_cloudy",
    2: "partly_cloudy",
    3: "cloudy",
    45: "fog",
    48: "fog",
    51: "rain",
    53: "rain",
    55: "rain",
    56: "rain",
    57: "rain",
    61: "rain",
    63: "rain",
    65: "rain",
    66: "rain",
    67: "rain",
    71: "snow",
    73: "snow",
    75: "snow",
    77: "snow",
    80: "rain",
    81: "rain",
    82: "rain",
    85: "snow",
    86: "snow",
    95: "thunder",
    96: "thunder",
    99: "thunder",
}

_CODE_TO_TEXT = {
    0: "Clear sky",
    1: "Mostly clear",
    2: "Partly cloudy",
    3: "Overcast",
    45: "Foggy",
    48: "Rime fog",
    51: "Light drizzle",
    53: "Drizzle",
    55: "Dense drizzle",
    56: "Freezing drizzle",
    57: "Freezing drizzle",
    61: "Light rain",
    63: "Rain",
    65: "Heavy rain",
    66: "Freezing rain",
    67: "Freezing rain",
    71: "Light snow",
    73: "Snow",
    75: "Heavy snow",
    77: "Snow grains",
    80: "Rain showers",
    81: "Rain showers",
    82: "Violent showers",
    85: "Snow showers",
    86: "Snow showers",
    95: "Thunderstorm",
    96: "Thunderstorm + hail",
    99: "Thunderstorm + hail",
}


def category_for_code(code):
    return _CODE_TO_CATEGORY.get(code, "cloudy")


def text_for_code(code):
    return _CODE_TO_TEXT.get(code, "Unknown")


def icon_image(code, size):
    fn = _DRAW_FUNCS[category_for_code(code)]
    return fn(size)
