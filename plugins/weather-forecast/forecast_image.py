"""Data-driven weather artwork. No remote fonts, icons, or image service."""

from datetime import datetime
from functools import lru_cache
import math
import os
from pathlib import Path
from zoneinfo import ZoneInfo

from PIL import Image, ImageDraw, ImageFont

INK = "#F1F6FF"
MUTED = "#AEC2DD"
BLUE = "#81CDFF"
GOLD = "#FFD18C"
PANEL = "#142D4A"
LINE = "#29425E"
WIDTH, HEIGHT = 1120, 1640


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def fmt(value, suffix="", digits=0):
    return f"{value:.{digits}f}{suffix}" if number(value) else "—"


def temperature(value, unit):
    return value * 9 / 5 + 32 if number(value) and unit == "fahrenheit" else value


def condition(code, day=True):
    if code == 0:
        return "Clear sky" if day else "Clear night"
    if code == 1:
        return "Mostly clear"
    if code == 2:
        return "Partly cloudy"
    if code == 3:
        return "Overcast"
    if code in (45, 48):
        return "Fog"
    if code in (51, 53, 55):
        return "Drizzle"
    if code in (56, 57):
        return "Freezing drizzle"
    if code in (61, 63, 65):
        return "Rain"
    if code in (66, 67):
        return "Freezing rain"
    if code in (71, 73, 75, 77):
        return "Snow"
    if code in (80, 81, 82):
        return "Rain showers"
    if code in (85, 86):
        return "Snow showers"
    if code in (95, 96, 99):
        return "Thunderstorms"
    return "Unavailable"


@lru_cache(maxsize=48)
def font(size, bold=False):
    windows = Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts"
    candidates = [
        windows / ("segoeuib.ttf" if bold else "segoeui.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else
             "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
        Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else
             "/System/Library/Fonts/Supplemental/Arial.ttf"),
    ]
    for path in candidates:
        if path.is_file():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default(size=size)


def text(draw, xy, value, size=24, fill=INK, bold=False, anchor=None, width=None):
    value = str(value)
    face = font(size, bold)
    if width:
        original = value
        while value and draw.textlength(value, font=face) > width:
            original = original[:-1]
            value = original + "…"
    draw.text(xy, value, font=face, fill=fill, anchor=anchor)


def icon(draw, x, y, size, code, day=True, background=PANEL):
    """Small hand-drawn weather symbols, scaled from a 100-unit coordinate grid."""
    scale = size / 100

    def ellipse(box, fill):
        draw.ellipse(tuple((x if i % 2 == 0 else y) + v * scale for i, v in enumerate(box)), fill=fill)

    def line(points, fill, weight=4):
        draw.line([(x + a * scale, y + b * scale) for a, b in points], fill=fill,
                  width=max(1, round(weight * scale)))

    if code is None:
        text(draw, (x + size / 2, y + size / 2), "—", round(size * .4), MUTED, anchor="mm")
        return
    if code in (0, 1, 2):
        if day:
            for n in range(8):
                angle = n * math.pi / 4
                line([(42 + math.cos(angle) * 29, 37 + math.sin(angle) * 29),
                      (42 + math.cos(angle) * 37, 37 + math.sin(angle) * 37)], GOLD)
            ellipse((21, 16, 63, 58), GOLD)
        else:
            ellipse((18, 10, 70, 62), "#DFE8FF")
            ellipse((36, 3, 77, 47), background)
            ellipse((78, 16, 82, 20), GOLD)
        if code == 0:
            return
    cloud = "#C8D8EC" if code in (1, 2) else "#96AEC9"
    ellipse((16, 43, 61, 77), cloud)
    ellipse((36, 27, 77, 76), cloud)
    ellipse((58, 44, 94, 77), cloud)
    draw.rectangle((x + 35 * scale, y + 55 * scale, x + 77 * scale, y + 77 * scale), fill=cloud)
    if code in (45, 48):
        for yy in (79, 89):
            line([(15, yy), (85, yy)], MUTED, 3)
    elif code in (71, 73, 75, 77, 85, 86):
        for xx in (29, 54, 78):
            line([(xx - 4, 88), (xx + 4, 88)], INK, 2)
            line([(xx, 84), (xx, 92)], INK, 2)
    elif code in (95, 96, 99):
        draw.polygon([(x + a * scale, y + b * scale) for a, b in
                      ((51, 65), (38, 86), (52, 86), (43, 103), (70, 77), (56, 77))], fill=GOLD)
    elif code in (51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82):
        for xx in (30, 54, 78):
            line([(xx, 84), (xx - 5, 95)], BLUE, 4)


def at(group, key, index):
    values = group.get(key, [])
    return values[index] if isinstance(values, list) and index < len(values) else None


def render_forecast(data, city, unit, target, fetched_at, stale=False):
    """Render a PNG and return an accessible text summary for the launcher."""
    zone = ZoneInfo(data.get("timezone") or "UTC")
    local = lambda stamp: datetime.fromtimestamp(stamp, zone) if number(stamp) else None
    current = data.get("current", {})
    hourly, daily = data.get("hourly", {}), data.get("daily", {})
    now = local(current.get("time")) or local(fetched_at)
    imperial = unit == "fahrenheit"
    degrees, wind_unit, rain_unit = ("°F", "mph", "in") if imperial else ("°C", "km/h", "mm")
    temp = lambda value: fmt(temperature(value, unit), "°")
    wind = lambda value: fmt(value / 1.609344 if number(value) and imperial else value)
    rain = lambda value: fmt(value / 25.4 if number(value) and imperial else value, digits=2 if imperial else 1)

    image = Image.new("RGB", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(image)
    # Quiet atmospheric gradient, kept below the data's contrast level.
    for y in range(HEIGHT):
        t = min(y / 780, 1)
        draw.line((0, y, WIDTH, y), fill=(round(25 - 14 * t), round(55 - 33 * t), round(88 - 48 * t)))
    text(draw, (42, 28), "WEATHER / FORECAST", 20, BLUE, True)
    text(draw, (1078, 28), "FREEDOM UNIT · °F" if imperial else "CELSIUS · °C", 18, MUTED, anchor="ra")
    text(draw, (42, 66), city["name"], 48, bold=True, width=770)
    region = ", ".join(dict.fromkeys(v for v in [city.get("admin1"), city.get("country")] if v and v != city["name"]))
    text(draw, (44, 130), region, 22, MUTED, width=740)
    text(draw, (44, 168), now.strftime("%A, %d %B · %H:%M %Z"), 20, MUTED)
    current_temperature = temp(current.get("temperature_2m"))
    temperature_size = 110
    while draw.textlength(current_temperature, font=font(temperature_size, True)) > 265 and temperature_size > 48:
        temperature_size -= 2
    text(draw, (36, 195), current_temperature, temperature_size, bold=True)
    text(draw, (325, 225), condition(current.get("weather_code"), current.get("is_day") != 0), 28, width=470)
    text(draw, (328, 272), f"High {temp(at(daily, 'temperature_2m_max', 0))}   Low {temp(at(daily, 'temperature_2m_min', 0))}", 23, MUTED)
    icon(draw, 855, 133, 170, current.get("weather_code"), current.get("is_day") != 0, "#193758")
    sunrise, sunset = local(at(daily, "sunrise", 0)), local(at(daily, "sunset", 0))
    text(draw, (44, 336), f"SUNRISE  {sunrise.strftime('%H:%M') if sunrise else '—'}     SUNSET  {sunset.strftime('%H:%M') if sunset else '—'}", 20, GOLD)
    text(draw, (1075, 336), "7 DAYS / 24 HOURS", 18, MUTED, anchor="ra")

    metrics = [("FEELS LIKE", temp(current.get("apparent_temperature"))),
               ("WIND", f"{wind(current.get('wind_speed_10m'))} {wind_unit}"),
               ("HUMIDITY", fmt(current.get("relative_humidity_2m"), "%")),
               ("UV MAX TODAY", fmt(at(daily, "uv_index_max", 0), digits=1))]
    for i, (label, value) in enumerate(metrics):
        x = 40 + i * 264
        draw.rounded_rectangle((x, 385, x + 248, 484), 18, fill=PANEL)
        text(draw, (x + 20, 399), label, 16, MUTED, True)
        text(draw, (x + 20, 429), value, 30, bold=True)

    draw.rounded_rectangle((40, 506, 1080, 1028), 22, fill=PANEL)
    text(draw, (62, 526), "THE NEXT 24 HOURS", 22, bold=True)
    text(draw, (1058, 531), "City local time · blue = rain / snow chance", 17, MUTED, anchor="ra")
    # Unix times avoid DST duplicate/missing-hour ambiguity in data selection.
    stamps = hourly.get("time", [])
    start = next((i for i, stamp in enumerate(stamps) if number(stamp) and stamp >= now.timestamp() - 3599), len(stamps))
    indexes = list(range(start, min(start + 24, len(stamps))))
    temps = [temperature(at(hourly, "temperature_2m", i), unit) for i in indexes]
    valid = [v for v in temps if number(v)]
    low, high = (min(valid) - 2, max(valid) + 2) if valid else (0, 1)
    for row in range(2):
        top = 578 + row * 223
        points = []
        for col, i in enumerate(indexes[row * 12:(row + 1) * 12]):
            x = 86 + col * 86
            date = local(stamps[i])
            text(draw, (x, top), date.strftime("%H:%M"), 18, MUTED, anchor="ma")
            icon(draw, x - 24, top + 30, 48, at(hourly, "weather_code", i), at(hourly, "is_day", i) != 0)
            value = temperature(at(hourly, "temperature_2m", i), unit)
            if number(value):
                y = top + 143 - (value - low) / (high - low) * 42
                points.append((x, y))
                text(draw, (x, y - 31), fmt(value, "°"), 23, bold=True, anchor="ma")
            else:
                if len(points) > 1:
                    draw.line(points, fill=GOLD, width=3)
                points = []
            chance = at(hourly, "precipitation_probability", i)
            if number(chance):
                draw.rounded_rectangle((x - 22, top + 174 - max(0, min(chance, 100)) * .16, x + 22, top + 176), 2, fill="#29557A")
            text(draw, (x, top + 181), fmt(chance, "%"), 18, BLUE, anchor="ma")
        if len(points) > 1:
            draw.line(points, fill=GOLD, width=3)
        for x, y in points:
            draw.ellipse((x - 3, y - 3, x + 3, y + 3), fill=GOLD)
    if not indexes:
        text(draw, (62, 620), "Hourly forecast unavailable", 24, MUTED)

    draw.rounded_rectangle((40, 1050, 1080, 1559), 22, fill=PANEL)
    text(draw, (62, 1070), "THE WEEK AHEAD", 22, bold=True)
    text(draw, (1058, 1075), "Daily low → high", 18, MUTED, anchor="ra")
    for x, label in [(62, "DAY"), (250, "CONDITIONS"), (535, degrees), (869, f"PRECIP · {rain_unit}"), (1023, wind_unit.upper())]:
        text(draw, (x, 1120), label, 15, MUTED, True, anchor="ma" if x >= 535 else None)
    lows = [temperature(v, unit) for v in daily.get("temperature_2m_min", [])[:7] if number(v)]
    highs = [temperature(v, unit) for v in daily.get("temperature_2m_max", [])[:7] if number(v)]
    minimum, maximum = (min(lows), max(highs)) if lows and highs else (0, 1)
    span = max(maximum - minimum, 1)
    for i, stamp in enumerate(daily.get("time", [])[:7]):
        y = 1152 + i * 56
        if i:
            draw.line((62, y - 6, 1058, y - 6), fill=LINE)
        date = local(stamp)
        text(draw, (62, y + 6), "Today" if i == 0 else date.strftime("%a %d"), 22, bold=i == 0)
        code = at(daily, "weather_code", i)
        icon(draw, 181, y - 5, 48, code)
        text(draw, (250, y + 8), condition(code), 19, MUTED, width=244)
        lo, hi = temperature(at(daily, "temperature_2m_min", i), unit), temperature(at(daily, "temperature_2m_max", i), unit)
        text(draw, (535, y + 6), fmt(lo, "°"), 22, MUTED, anchor="ma")
        draw.rounded_rectangle((575, y + 17, 732, y + 25), 4, fill=LINE)
        if number(lo) and number(hi):
            left, right = 575 + (lo - minimum) / span * 157, 575 + (hi - minimum) / span * 157
            draw.rounded_rectangle((left, y + 17, max(left + 5, right), y + 25), 4, fill=GOLD)
        text(draw, (775, y + 6), fmt(hi, "°"), 22, bold=True, anchor="ma")
        text(draw, (869, y), fmt(at(daily, "precipitation_probability_max", i), "%"), 20, BLUE, anchor="ma")
        text(draw, (869, y + 26), rain(at(daily, "precipitation_sum", i)), 15, MUTED, anchor="ma")
        text(draw, (1023, y + 6), wind(at(daily, "wind_speed_10m_max", i)), 20, MUTED, anchor="ma")

    updated = local(fetched_at).strftime("%d %b %H:%M %Z")
    text(draw, (42, 1580), "Open-Meteo · CC BY 4.0", 18, MUTED)
    text(draw, (1078, 1580), f"{'CACHED / OFFLINE · ' if stale else 'Updated '}{updated}", 17, GOLD if stale else MUTED, anchor="ra")
    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(".tmp")
    image.save(temporary, format="PNG", optimize=True)
    temporary.replace(target)
    return f"{city['name']}: {temp(current.get('temperature_2m'))}{degrees[-1]}, {condition(current.get('weather_code'), current.get('is_day') != 0)}."
