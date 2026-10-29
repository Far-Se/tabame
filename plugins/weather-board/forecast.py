"""Open-Meteo requests and presentation-independent weather helpers."""

import json
import math
import ssl
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


CONDITIONS = {
    0: "Clear sky", 1: "Mostly clear", 2: "Partly cloudy", 3: "Overcast",
    45: "Fog", 48: "Freezing fog", 51: "Light drizzle", 53: "Drizzle",
    55: "Heavy drizzle", 56: "Freezing drizzle", 57: "Freezing drizzle",
    61: "Light rain", 63: "Rain", 65: "Heavy rain", 66: "Freezing rain",
    67: "Freezing rain", 71: "Light snow", 73: "Snow", 75: "Heavy snow",
    77: "Snow grains", 80: "Rain showers", 81: "Rain showers",
    82: "Heavy showers", 85: "Snow showers", 86: "Heavy snow showers",
    95: "Thunderstorms", 96: "Storms with hail", 97: "Heavy thunderstorms",
    99: "Storms with hail",
}


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def condition(code, is_day=True):
    if code in (0, 1) and not is_day:
        return "Clear night" if code == 0 else "Mostly clear"
    return CONDITIONS.get(code, "Conditions unavailable")


@lru_cache(maxsize=1)
def https_context():
    import certifi

    # Explicitly use Mozilla's CA bundle rather than the Windows/system store.
    # Certificate-chain and hostname verification remain enabled.
    return ssl.create_default_context(cafile=certifi.where())


def fetch_json(base, params):
    request = Request(base + "?" + urlencode(params), headers={
        "User-Agent": "Tabame-Weather-Board/1.0", "Accept": "application/json",
    })
    try:
        with urlopen(request, timeout=12, context=https_context()) as response:
            raw = response.read(2_000_001)
        if len(raw) > 2_000_000:
            raise ValueError("Weather service returned an oversized response.")
        data = json.loads(raw)
        if not isinstance(data, dict) or data.get("error"):
            raise ValueError("Weather service could not complete this request.")
        return data
    except HTTPError as exc:
        if exc.code == 429:
            raise ValueError("Weather service is busy. Please try again in a minute.") from exc
        raise ValueError(f"Weather service returned HTTP {exc.code}. Please try again.") from exc
    except URLError as exc:
        if isinstance(exc.reason, ssl.SSLCertVerificationError):
            raise ValueError("The weather service's HTTPS certificate could not be verified. Check your computer's date/time or retry later.") from exc
        raise ValueError("Could not reach the weather service. Check your connection and retry.") from exc
    except (TimeoutError, OSError) as exc:
        raise ValueError("Could not reach the weather service. Check your connection and retry.") from exc
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise ValueError("Weather service returned an unreadable response.") from exc


def valid_city(city):
    return (isinstance(city, dict) and isinstance(city.get("name"), str)
            and bool(city["name"].strip()) and number(city.get("latitude"))
            and number(city.get("longitude")) and -90 <= city["latitude"] <= 90
            and -180 <= city["longitude"] <= 180)


def city_key(city):
    return f'{city["latitude"]:.5f},{city["longitude"]:.5f}'


def city_label(city):
    return ", ".join(dict.fromkeys(str(city[key]) for key in ("name", "admin1", "country") if city.get(key)))


def search_cities(query):
    data = fetch_json("https://geocoding-api.open-meteo.com/v1/search", {
        "name": query[:200], "count": 8, "language": "en", "format": "json",
    })
    results = data.get("results", [])
    return [city for city in results if valid_city(city)] if isinstance(results, list) else []


def valid_forecast(data):
    if not isinstance(data, dict):
        return False
    current, hourly, daily = (data.get(key) for key in ("current", "hourly", "daily"))
    if not all(isinstance(part, dict) for part in (current, hourly, daily)):
        return False
    if not number(current.get("time")) or not number(current.get("temperature_2m")):
        return False
    for part, required in ((hourly, ("temperature_2m", "weather_code")),
                           (daily, ("temperature_2m_min", "temperature_2m_max", "weather_code"))):
        times = part.get("time")
        if not isinstance(times, list) or not times or not all(number(t) for t in times):
            return False
        if any(not isinstance(part.get(key), list) or len(part[key]) != len(times) for key in required):
            return False
    return True


def fetch_forecast(city):
    data = fetch_json("https://api.open-meteo.com/v1/forecast", {
        "latitude": city["latitude"], "longitude": city["longitude"],
        "timezone": "auto", "timeformat": "unixtime", "forecast_days": 7,
        "temperature_unit": "celsius", "wind_speed_unit": "kmh", "precipitation_unit": "mm",
        "current": "temperature_2m,apparent_temperature,relative_humidity_2m,is_day,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,precipitation",
        "hourly": "temperature_2m,precipitation_probability,weather_code,wind_speed_10m,is_day",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_probability_max,precipitation_sum,wind_speed_10m_max",
    })
    if not valid_forecast(data):
        raise ValueError("The weather service returned an incomplete forecast. Please retry.")
    return data


def local_time(timestamp, data):
    try:
        tz = ZoneInfo(data.get("timezone", "UTC"))
    except (ZoneInfoNotFoundError, ValueError, TypeError):
        tz = timezone(timedelta(seconds=data.get("utc_offset_seconds", 0)))
    return datetime.fromtimestamp(timestamp, tz)


def at(series, key, index):
    values = series.get(key, [])
    return values[index] if isinstance(values, list) and 0 <= index < len(values) else None


def temperature(value, units):
    if not number(value):
        return "—"
    return f'{(value * 9 / 5 + 32 if units == "fahrenheit" else value):.0f}°'


def wind(value, units, suffix=True):
    if not number(value):
        return "—"
    imperial = units == "fahrenheit"
    return f'{(value / 1.609344 if imperial else value):.0f}' + ((" mph" if imperial else " km/h") if suffix else "")


def percent(value):
    return f"{value:.0f}%" if number(value) else "—"


def precipitation(value, units):
    if not number(value):
        return "—"
    return f"{value / 25.4:.2f} in" if units == "fahrenheit" else f"{value:.1f} mm"


def direction(value):
    return ("N", "NE", "E", "SE", "S", "SW", "W", "NW")[round(value / 45) % 8] if number(value) else ""


def hour_indices(data):
    # Start with the current hour, in absolute time even across a DST boundary.
    current = data["current"]["time"]
    times = data["hourly"]["time"]
    start = max((i for i, stamp in enumerate(times) if stamp <= current), default=0)
    return list(range(start, min(start + 24, len(times))))
