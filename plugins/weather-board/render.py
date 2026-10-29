"""Draw an accurate, shareable PNG forecast from live data (no browser required)."""

import math
import os
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from forecast import (at, condition, direction, hour_indices, local_time, number,
                      percent, precipitation, temperature, wind)

WIDTH, HEIGHT = 1440, 1580
INK = "#f3f7fc"
MUTED = "#a1b5ca"
BLUE = "#8bd5ff"
GOLD = "#ffd387"
LINE = "#2c4259"
PANEL = "#132a40"


@lru_cache(maxsize=48)
def font(size, bold=False):
    names = ("segoeuib.ttf", "arialbd.ttf") if bold else ("segoeui.ttf", "arial.ttf")
    for name in names:
        try:
            return ImageFont.truetype(str(Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts" / name), size)
        except OSError:
            pass
    for name in (("DejaVuSans-Bold.ttf",) if bold else ("DejaVuSans.ttf",)):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default(size=size)


def weather_icon(canvas, x, y, size, code, day=True):
    """Small vector shapes rendered at 3x for crisp icons at any size."""
    scale = 3
    icon = Image.new("RGBA", (size * scale, size * scale))
    draw = ImageDraw.Draw(icon)
    unit = size * scale / 100

    def oval(box, color):
        draw.ellipse(tuple(v * unit for v in box), fill=color)

    def line(points, color, width=3):
        draw.line([(a * unit, b * unit) for a, b in points], fill=color, width=max(1, round(width * unit)))

    if code is None or code not in range(100):
        draw.text((50 * unit, 50 * unit), "?", font=font(round(45 * unit)), fill=MUTED, anchor="mm")
    elif code in (0, 1, 2):
        cx, cy = (42, 39) if code in (1, 2) else (50, 48)
        if day:
            for angle in range(0, 360, 45):
                r = math.radians(angle)
                line([(cx + 28 * math.cos(r), cy + 28 * math.sin(r)),
                      (cx + 35 * math.cos(r), cy + 35 * math.sin(r))], GOLD, 3)
            oval((cx - 21, cy - 21, cx + 21, cy + 21), "#ffd387")
            oval((cx - 15, cy - 16, cx + 10, cy + 7), "#ffdfaa")
        else:
            oval((cx - 24, cy - 24, cx + 24, cy + 24), "#d7e9ff")
            # Erase the moon's cutout, retaining transparent sky beneath it.
            oval((cx - 8, cy - 31, cx + 32, cy + 9), (0, 0, 0, 0))
            line([(79, 15), (79, 25)], "#b5d6ff", 2)
            line([(74, 20), (84, 20)], "#b5d6ff", 2)
    if code is not None and code != 0 and code in range(100):
        # Cloud silhouette, shared by overcast, showers, snow and fog.
        oval((12, 40, 55, 75), "#a4c5df")
        oval((31, 25, 77, 73), "#d0e3f3")
        oval((56, 42, 93, 75), "#bdd7eb")
        draw.rounded_rectangle((26 * unit, 52 * unit, 80 * unit, 75 * unit), radius=9 * unit, fill="#bdd7eb")
        if code in (45, 48):
            line([(16, 82), (85, 82)], "#99b7cf", 3)
            line([(25, 91), (72, 91)], "#99b7cf", 3)
        elif code in (71, 73, 75, 77, 85, 86):
            for sx in (29, 52, 75):
                for angle in (0, 60, 120):
                    r = math.radians(angle)
                    line([(sx - 5 * math.cos(r), 87 - 5 * math.sin(r)),
                          (sx + 5 * math.cos(r), 87 + 5 * math.sin(r))], "#dceeff", 2)
        elif code >= 95:
            draw.polygon([(54 * unit, 64 * unit), (39 * unit, 85 * unit),
                          (51 * unit, 85 * unit), (44 * unit, 99 * unit),
                          (67 * unit, 76 * unit), (54 * unit, 76 * unit)], fill=GOLD)
        elif code >= 51:
            for sx in (28, 51, 74):
                line([(sx, 81), (sx - 4, 91)], "#7bcaff", 3)
    icon = icon.resize((size, size), Image.Resampling.LANCZOS)
    canvas.paste(icon, (round(x), round(y)), icon)


def render_forecast(city, data, units, output, fetched, stale=False, sample=False):
    image = Image.new("RGB", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(image)
    # A quiet atmospheric sky with a warmer light source for daylight.
    day = data["current"].get("is_day", 1) == 1
    for y in range(HEIGHT):
        mix = min(y / 850, 1)
        top = (29, 61, 88) if day else (24, 39, 72)
        color = tuple(round(a * (1 - mix) + b * mix) for a, b in zip(top, (11, 24, 39)))
        draw.line((0, y, WIDTH, y), fill=color)
    glow = Image.new("RGBA", image.size)
    gd = ImageDraw.Draw(glow)
    gd.ellipse((850, -210, 1550, 410), fill=(127, 177, 207, 42) if day else (111, 138, 219, 35))
    image = Image.alpha_composite(image.convert("RGBA"), glow.filter(ImageFilter.GaussianBlur(100))).convert("RGB")
    draw = ImageDraw.Draw(image)

    def text(x, y, value, size=24, color=INK, bold=False, anchor="la", width=None):
        value = str(value)
        face = font(size, bold)
        if width is not None:
            while value and draw.textlength(value, font=face) > width:
                value = value[:-2].rstrip() + "…"
        draw.text((x, y), value, font=face, fill=color, anchor=anchor)

    def rule(y, x1=64, x2=1376):
        draw.line((x1, y, x2, y), fill=LINE, width=1)

    current, daily, hourly = data["current"], data["daily"], data["hourly"]
    now = local_time(current["time"], data)
    text(64, 41, "WEATHER BOARD" + ("  /  ILLUSTRATIVE PREVIEW" if sample else ""), 22, BLUE, True)
    unit_label = "FREEDOM UNIT  /  °F" if units == "fahrenheit" else "CELSIUS  /  °C"
    text(1376, 41, unit_label, 21, MUTED, anchor="ra")
    text(64, 82, city["name"], 54, bold=True, width=900)
    location = " · ".join(dict.fromkeys(str(city[k]) for k in ("admin1", "country") if city.get(k)))
    text(66, 153, location, 24, MUTED, width=900)
    text(66, 189, now.strftime("%A, %d %B · %H:%M") + " local", 22, MUTED)

    hero = temperature(current.get("temperature_2m"), units)
    text(57, 220, hero, 122)
    hero_right = 62 + draw.textlength(hero, font=font(122)) + 35
    text(hero_right, 251, condition(current.get("weather_code"), day), 31, bold=True, width=760 - hero_right)
    text(hero_right, 300, "Feels like " + temperature(current.get("apparent_temperature"), units), 25, MUTED)
    text(hero_right, 337, f'High {temperature(at(daily, "temperature_2m_max", 0), units)}  /  Low {temperature(at(daily, "temperature_2m_min", 0), units)}', 24, MUTED)
    weather_icon(image, 1060, 112, 260, current.get("weather_code"), day)
    draw = ImageDraw.Draw(image)

    sunrise = at(daily, "sunrise", 0)
    sunset = at(daily, "sunset", 0)
    sun_time = lambda stamp: local_time(stamp, data).strftime("%H:%M") if number(stamp) and stamp > 0 else "—"
    metrics = [
        ("WIND", wind(current.get("wind_speed_10m"), units), direction(current.get("wind_direction_10m"))),
        ("GUSTS", wind(current.get("wind_gusts_10m"), units), "current"),
        ("HUMIDITY", percent(current.get("relative_humidity_2m")), "relative"),
        ("PRECIPITATION", percent(at(daily, "precipitation_probability_max", 0)), "today's chance"),
        ("SUNRISE", sun_time(sunrise), "local time"),
        ("SUNSET", sun_time(sunset), "local time"),
    ]
    draw.rounded_rectangle((48, 399, 1392, 525), radius=20, fill=PANEL)
    for i, (label, value, foot) in enumerate(metrics):
        x = 72 + i * 224
        if i:
            draw.line((x - 20, 424, x - 20, 501), fill=LINE)
        text(x, 416, label, 18, MUTED, True)
        text(x, 445, value, 30, bold=True)
        text(x, 487, foot, 18, MUTED)

    text(64, 559, "The next 24 hours", 30, bold=True)
    text(1376, 568, "Precipitation chance + wind beneath each hour", 20, MUTED, anchor="ra")
    indices = hour_indices(data)
    all_temps = [at(hourly, "temperature_2m", i) for i in indices if number(at(hourly, "temperature_2m", i))]
    low, high = (min(all_temps), max(all_temps)) if all_temps else (0, 1)
    spread = max(high - low, 4)
    for row in range(2):
        y = 612 + row * 225
        draw.rounded_rectangle((48, y, 1392, y + 210), radius=18, fill=PANEL)
        points = []
        for col, i in enumerate(indices[row * 12:(row + 1) * 12]):
            x = 104 + col * 112
            stamp = local_time(hourly["time"][i], data)
            label = "Now" if row == 0 and col == 0 else stamp.strftime("%H:%M")
            text(x, y + 13, label, 21, BLUE if label == "Now" else MUTED, anchor="ma")
            weather_icon(image, x - 24, y + 43, 48, at(hourly, "weather_code", i), at(hourly, "is_day", i) == 1)
            draw = ImageDraw.Draw(image)
            value = at(hourly, "temperature_2m", i)
            text(x, y + 91, temperature(value, units), 29, bold=True, anchor="ma")
            if number(value):
                points.append((x, y + 148 - (value - low) / spread * 22))
            else:
                points.append(None)
            text(x, y + 158, percent(at(hourly, "precipitation_probability", i)), 21, BLUE, anchor="ma")
            text(x, y + 185, wind(at(hourly, "wind_speed_10m", i), units), 17, MUTED, anchor="ma")
        for a, b in zip(points, points[1:]):
            if a is not None and b is not None:
                draw.line((a, b), fill=GOLD, width=3)
        for point in points:
            if point:
                px, py = point
                draw.ellipse((px - 3, py - 3, px + 3, py + 3), fill=GOLD)

    text(64, 1085, "Your week ahead", 30, bold=True)
    speed_unit = "mph" if units == "fahrenheit" else "km/h"
    for x, label in ((725, "LOW / HIGH"), (1010, "PRECIP."), (1190, "WIND " + speed_unit), (1350, "UV")):
        text(x, 1096, label, 18, MUTED, True, anchor="ma")
    lows = [v for v in daily.get("temperature_2m_min", []) if number(v)]
    highs = [v for v in daily.get("temperature_2m_max", []) if number(v)]
    week_min, week_max = min(lows, default=0), max(highs, default=1)
    week_span = max(week_max - week_min, 1)
    for i, stamp in enumerate(daily["time"][:7]):
        y = 1140 + i * 51
        if i == 0:
            draw.rounded_rectangle((48, y - 3, 1392, y + 46), radius=12, fill=PANEL)
        date = local_time(stamp, data)
        text(68, y + 7, "Today" if i == 0 else date.strftime("%a"), 23, bold=i == 0)
        text(160, y + 10, date.strftime("%d %b"), 19, MUTED)
        weather_icon(image, 267, y - 2, 44, at(daily, "weather_code", i))
        draw = ImageDraw.Draw(image)
        text(329, y + 8, condition(at(daily, "weather_code", i)), 21, width=240)
        lo, hi = at(daily, "temperature_2m_min", i), at(daily, "temperature_2m_max", i)
        text(635, y + 7, temperature(lo, units), 23, MUTED, anchor="ra")
        draw.rounded_rectangle((660, y + 18, 815, y + 28), radius=5, fill=LINE)
        if number(lo) and number(hi):
            start = 660 + (lo - week_min) / week_span * 155
            end = max(start + 6, 660 + (hi - week_min) / week_span * 155)
            draw.rounded_rectangle((start, y + 18, end, y + 28), radius=5, fill=GOLD)
        text(843, y + 7, temperature(hi, units), 23, bold=True)
        text(1010, y + 1, percent(at(daily, "precipitation_probability_max", i)), 22, BLUE, anchor="ma")
        text(1010, y + 27, precipitation(at(daily, "precipitation_sum", i), units), 15, MUTED, anchor="ma")
        text(1190, y + 7, wind(at(daily, "wind_speed_10m_max", i), units, False), 23, anchor="ma")
        uv = at(daily, "uv_index_max", i)
        text(1350, y + 7, f"{uv:.0f}" if number(uv) else "—", 23, GOLD if number(uv) and uv >= 6 else MUTED, anchor="ma")
        if i < 6:
            rule(y + 48)

    rule(1513)
    text(64, 1534, "SAMPLE DATA  /  Not a live forecast" if sample else "OPEN-METEO  /  Weather data · CC BY 4.0", 18, MUTED)
    stamp = local_time(fetched, data).strftime("%d %b, %H:%M %Z")
    text(1376, 1534, ("SAVED FORECAST · " if stale else "Updated ") + stamp, 18, GOLD if stale else MUTED, anchor="ra")
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    temp = output.with_suffix(".tmp")
    image.save(temp, format="PNG", optimize=True)
    temp.replace(output)
    return output
