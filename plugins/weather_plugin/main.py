#!/usr/bin/env python3
"""Tabame launcher plugin: weather [city] [weekly|w] [f]

Shows a generated "nice image" weather card - today's weather by default,
or a 7-day strip when "weekly" (or "w") is in the query. A trailing "f"
requests Fahrenheit for that query.

Uses Open-Meteo (no API key required) for geocoding + forecast, renders a
PNG with Pillow, and serves it over a small local HTTP server so it can be
embedded as a normal https://... image in a markdown detail view.
"""

import functools
import http.server
import json
import os
import socket
import sys
import threading
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from weather_render import render_today, render_weekly

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(HERE, ".cache")
os.makedirs(CACHE_DIR, exist_ok=True)

GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search"
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"

WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
MONTHS = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
]


def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# --------------------------------------------------------------------------
# Tiny local image server (127.0.0.1 only) so generated PNGs can be embedded
# as an http:// image in markdown, which the launcher's webview can load.
# --------------------------------------------------------------------------
class _Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # keep stderr quiet


def _free_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def start_image_server():
    port = _free_port()
    handler = functools.partial(_Handler, directory=CACHE_DIR)
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    return port


IMAGE_PORT = start_image_server()


def image_url(filename):
    # cache-bust so a refreshed query always shows the new image
    return f"http://127.0.0.1:{IMAGE_PORT}/{filename}?t={int(time.time() * 1000)}"


# --------------------------------------------------------------------------
# Config (optional default city so "weather" alone with no city still works)
# --------------------------------------------------------------------------
def load_config():
    path = os.path.join(HERE, "config.json")
    if os.path.exists(path):
        try:
            with open(path, encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            log("config load failed:", e)
    return {}


CONFIG = load_config()
DEFAULT_CITY = CONFIG.get("defaultCity", "")
UNITS = CONFIG.get("units", "celsius")  # "celsius" or "fahrenheit"


# --------------------------------------------------------------------------
# Query parsing: "weather [city] [weekly|w] [f]"
# --------------------------------------------------------------------------
def parse_query(text):
    tokens = text.strip().split()
    period = "today"
    units = "fahrenheit" if UNITS == "fahrenheit" else "celsius"
    if tokens and tokens[-1].lower() == "f":
        units = "fahrenheit"
        tokens = tokens[:-1]
    if tokens and tokens[-1].lower() in ("weekly", "w"):
        period = "weekly"
        tokens = tokens[:-1]
    city = " ".join(tokens).strip()
    if not city:
        city = DEFAULT_CITY
    return city, period, units


# --------------------------------------------------------------------------
# Open-Meteo fetches
# --------------------------------------------------------------------------
def http_json(url, params):
    q = urllib.parse.urlencode(params)
    req = urllib.request.Request(
        f"{url}?{q}", headers={"User-Agent": "tabame-weather-plugin"}
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode("utf-8"))


def geocode(city):
    data = http_json(
        GEOCODE_URL, {"name": city, "count": 1, "language": "en", "format": "json"}
    )
    results = data.get("results") or []
    if not results:
        return None
    r = results[0]
    return {
        "name": r.get("name", city),
        "country": r.get("country", ""),
        "admin1": r.get("admin1", ""),
        "latitude": r["latitude"],
        "longitude": r["longitude"],
        "timezone": r.get("timezone", "auto"),
    }


def fetch_forecast(lat, lon, tz, units):
    temp_unit = "fahrenheit" if units == "fahrenheit" else "celsius"
    params = {
        "latitude": lat,
        "longitude": lon,
        "timezone": tz or "auto",
        "temperature_unit": temp_unit,
        "wind_speed_unit": "kmh" if temp_unit == "celsius" else "mph",
        "current": "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
        "forecast_days": 7,
    }
    return http_json(FORECAST_URL, params)


def unit_suffix(units):
    return "°F" if units == "fahrenheit" else "°C"


def weekday_label(date_str):
    import datetime

    d = datetime.date.fromisoformat(date_str)
    return WEEKDAYS[d.weekday()]


def today_date_label():
    import datetime

    d = datetime.date.today()
    return f"{WEEKDAYS[d.weekday()]}day, {MONTHS[d.month - 1]} {d.day}"


# --------------------------------------------------------------------------
# Frame builders
# --------------------------------------------------------------------------
def instructions_frame(rev):
    lines = [
        "# Weather",
        "",
        "Type a city and press **Enter**:",
        "",
        "- `weather Gorgonia` — today's weather",
        "- `weather Gorgonia weekly` (or `w`) — 7-day forecast",
        "- Add `f` at the end for Fahrenheit, e.g. `weather Gorgonia f`",
    ]
    if DEFAULT_CITY:
        lines.append("")
        lines.append(f"No city? Defaults to **{DEFAULT_CITY}**.")
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "inputMode": "submit",
            "placeholder": "city name, then optionally 'weekly'",
            "detail": {"markdown": "\n".join(lines)},
        }
    )


def loading_frame(rev, city, period):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "inputMode": "submit",
            "loading": True,
            "loadingText": f"Fetching {period} weather for {city}…",
            "detail": {"markdown": ""},
        }
    )


def error_frame(rev, message):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "inputMode": "submit",
            "placeholder": "city name, then optionally 'weekly'",
            "detail": {"markdown": f"# Couldn't get weather\n\n{message}"},
        }
    )


def weather_frame(rev, city_label, period, img_filename, metadata):
    url = image_url(img_filename)
    md = f"![Weather for {city_label}]({url})"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "inputMode": "submit",
            "placeholder": "city name, then optionally 'weekly'",
            "wide": True,
            "detail": {
                "markdown": md,
                "metadata": metadata,
            },
            "actions": [
                {
                    "id": "toggle",
                    "title": "Switch today/weekly",
                    "icon": "refresh",
                    "shortcut": "ctrl+t",
                },
            ],
        }
    )


# --------------------------------------------------------------------------
# Main processing
# --------------------------------------------------------------------------
STATE = {"last_city": DEFAULT_CITY, "last_period": "today", "last_units": UNITS}


def process(rev, text):
    city, period, units = parse_query(text)

    if not city:
        instructions_frame(rev)
        return

    STATE["last_city"] = city
    STATE["last_period"] = period
    STATE["last_units"] = units

    loading_frame(rev, city, period)

    try:
        place = geocode(city)
        if not place:
            error_frame(
                rev, f"No place found for **{city}**. Try a different spelling."
            )
            return

        forecast = fetch_forecast(
            place["latitude"], place["longitude"], place["timezone"], units
        )
        location_bits = [place["name"]]
        if place.get("admin1"):
            location_bits.append(place["admin1"])
        if place.get("country"):
            location_bits.append(place["country"])
        city_label = ", ".join(location_bits)

        if period == "weekly":
            daily = forecast["daily"]
            days = []
            for i in range(min(7, len(daily["time"]))):
                days.append(
                    {
                        "label": weekday_label(daily["time"][i]),
                        "weather_code": daily["weather_code"][i],
                        "temp_max": daily["temperature_2m_max"][i],
                        "temp_min": daily["temperature_2m_min"][i],
                        "precip_prob": daily.get(
                            "precipitation_probability_max", [0] * 7
                        )[i]
                        or 0,
                    }
                )
            img_name = "weekly.png"
            render_weekly(
                {"city": city_label, "days": days}, os.path.join(CACHE_DIR, img_name)
            )

            metadata = [
                {"label": "Location", "text": city_label, "icon": "location"},
                {
                    "label": "This week",
                    "text": f"{round(min(d['temp_min'] for d in days))}{unit_suffix(units)} – {round(max(d['temp_max'] for d in days))}{unit_suffix(units)}",
                },
            ]
            weather_frame(rev, city_label, period, img_name, metadata)
        else:
            cur = forecast["current"]
            daily = forecast["daily"]
            data = {
                "city": city_label,
                "date_label": today_date_label(),
                "temp": cur["temperature_2m"],
                "feels_like": cur["apparent_temperature"],
                "humidity": cur["relative_humidity_2m"],
                "wind": cur["wind_speed_10m"],
                "wind_unit": "mph" if units == "fahrenheit" else "km/h",
                "weather_code": cur["weather_code"],
                "temp_min": daily["temperature_2m_min"][0],
                "temp_max": daily["temperature_2m_max"][0],
                "precip_prob": daily.get("precipitation_probability_max", [0])[0] or 0,
            }
            img_name = "today.png"
            render_today(data, os.path.join(CACHE_DIR, img_name))

            metadata = [
                {"label": "Location", "text": city_label, "icon": "location"},
                {
                    "label": "Feels like",
                    "text": f"{round(data['feels_like'])}{unit_suffix(units)}",
                },
                {"label": "Humidity", "text": f"{data['humidity']}%"},
                {"label": "Wind", "text": f"{round(data['wind'])} {data['wind_unit']}"},
            ]
            weather_frame(rev, city_label, period, img_name, metadata)

    except urllib.error.URLError as e:
        error_frame(rev, f"Network error: {e}")
    except Exception as e:
        log("error:", repr(e))
        error_frame(rev, f"```\n{e}\n```")


def toggle_period():
    other = "today" if STATE["last_period"] == "weekly" else "weekly"
    fahrenheit = " f" if STATE["last_units"] == "fahrenheit" else ""
    text = f"{STATE['last_city']} {other}{fahrenheit}".strip()
    process(0, text)


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
            initial_text = msg.get("query", "") or ""
            if initial_text.strip():
                process(0, initial_text)
            else:
                instructions_frame(0)
        elif t == "query":
            # Only reached before our first frame sets inputMode:submit.
            # Don't hit the API on every keystroke - just wait for Enter.
            pass
        elif t == "submitQuery":
            process(msg.get("rev", 0), msg.get("text", ""))
        elif t == "action":
            if msg.get("action") == "toggle":
                toggle_period()
        elif t == "back":
            instructions_frame(0)


if __name__ == "__main__":
    main()
