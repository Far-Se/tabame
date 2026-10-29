"""Tabame's forecast plugin: asynchronous NDJSON UI and Open-Meteo data."""

import hashlib
import json
import math
from pathlib import Path
import queue
import ssl
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

import certifi


ROOT = Path(__file__).resolve().parent
CACHE = ROOT / ".cache"
TTL = 600
# Match the working weather plugins: use certifi's maintained CA bundle.
SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())


def send(message):
    print(json.dumps(message, ensure_ascii=True, allow_nan=False), flush=True)


def command(name, **fields):
    send({"type": "command", "command": name, **fields})


def get_json(base, params):
    url = base + "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, headers={"User-Agent": "Tabame-Weather-Forecast/1.0", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=15, context=SSL_CONTEXT) as response:
            payload = response.read(4 * 1024 * 1024 + 1)
        if len(payload) > 4 * 1024 * 1024:
            raise ValueError("The weather service returned too much data.")
        result = json.loads(payload)
        if not isinstance(result, dict) or result.get("error"):
            raise ValueError("The weather service could not complete this request.")
        return result
    except urllib.error.HTTPError as error:
        if error.code == 429:
            raise ValueError("The weather service is busy. Please wait a moment and refresh.") from error
        raise ValueError(f"The weather service returned HTTP {error.code}. Try again shortly.") from error
    except urllib.error.URLError as error:
        if isinstance(error.reason, ssl.SSLCertVerificationError):
            raise ValueError("Open-Meteo's secure connection could not be verified. Check your system clock and certificate trust, then try again.") from error
        raise ValueError("Could not reach Open-Meteo. Check your connection and try again.") from error
    except TimeoutError as error:
        raise ValueError("Could not reach Open-Meteo. Check your connection and try again.") from error


def valid_city(value):
    if not isinstance(value, dict) or not isinstance(value.get("name"), str) or not value["name"].strip():
        return False
    for key, limit in [("latitude", 90), ("longitude", 180)]:
        coordinate = value.get(key)
        if isinstance(coordinate, bool) or not isinstance(coordinate, (int, float)) or not math.isfinite(coordinate) or abs(coordinate) > limit:
            return False
    return True


def city_record(city):
    return {key: city.get(key) for key in ("id", "name", "latitude", "longitude", "admin1", "country", "timezone")}


def cache_key(city):
    return hashlib.sha256(f"{city['latitude']},{city['longitude']}".encode()).hexdigest()[:20]


def valid_forecast(data):
    return (isinstance(data, dict) and isinstance(data.get("current"), dict)
            and isinstance(data.get("hourly"), dict) and isinstance(data.get("daily"), dict)
            and isinstance(data["current"].get("time"), (int, float))
            and isinstance(data["hourly"].get("time"), list)
            and bool(data["daily"].get("time")))


def fetch_forecast(city, force=False):
    path = CACHE / f"{cache_key(city)}.json"
    cached = None
    try:
        stored = json.loads(path.read_text(encoding="utf-8"))
        if (isinstance(stored, dict) and valid_forecast(stored.get("data"))
                and isinstance(stored.get("fetched_at"), (int, float))
                and math.isfinite(stored["fetched_at"])):
            cached = stored
    except (OSError, ValueError, TypeError):
        pass
    if cached and not force and 0 <= time.time() - cached["fetched_at"] < TTL:
        return {**cached, "stale": False, "warning": ""}
    try:
        data = get_json("https://api.open-meteo.com/v1/forecast", {
            "latitude": city["latitude"], "longitude": city["longitude"],
            "timezone": "auto", "timeformat": "unixtime", "forecast_days": 7,
            "temperature_unit": "celsius", "wind_speed_unit": "kmh", "precipitation_unit": "mm",
            "current": "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,wind_speed_10m",
            "hourly": "temperature_2m,weather_code,precipitation_probability,is_day",
            "daily": "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_probability_max,precipitation_sum,wind_speed_10m_max",
        })
        if not valid_forecast(data):
            raise ValueError("The weather service returned an incomplete forecast. Please refresh.")
        result = {"data": data, "fetched_at": time.time()}
        # Cache forecast data only. Preference storage is host-owned.
        try:
            CACHE.mkdir(parents=True, exist_ok=True)
            temporary = path.with_suffix(f".{threading.get_ident()}.tmp")
            temporary.write_text(json.dumps(result, allow_nan=False), encoding="utf-8")
            temporary.replace(path)
        except OSError as error:
            print(f"Weather cache could not be saved: {error}", file=sys.stderr)
        return {**result, "stale": False, "warning": ""}
    except (ValueError, OSError) as error:
        if cached:
            return {**cached, "stale": True, "warning": str(error)}
        raise


class WeatherPlugin:
    def __init__(self):
        self.events = queue.Queue()
        self.preferences = {"unit": "celsius", "city": None}
        self.ready = False
        self.query = ""
        self.rev = 0
        self.generation = 0
        self.timer = None
        self.cities = {}
        self.forecast = None
        self.image = None
        self.summary = ""
        self.page = "weather:search"
        self.keep_search_empty = False
        self.skip_empty_query = False

    def frame(self, view="list", **fields):
        frame = {
            "type": "render", "rev": self.rev, "view": view,
            "page": {"id": self.page, "title": "Weather Forecast" if self.page.endswith("forecast") else "Find a city",
                     "history": "replace", "preserveState": True},
            "placeholder": "Search a city, e.g. London or Paris, France…",
            "canGoBack": self.page == "weather:search" and bool(self.preferences["city"]),
            "actions": self.actions(), **fields,
        }
        send(frame)

    def actions(self):
        unit = self.preferences["unit"]
        actions = [{"id": "units", "title": "Use Celsius (°C)" if unit == "fahrenheit" else "Use Freedom Unit (°F)", "icon": "sun"}]
        if self.preferences["city"]:
            actions += [{"id": "refresh", "title": "Refresh forecast", "icon": "refresh", "shortcut": "ctrl+r"},
                        {"id": "search", "title": "Change city", "icon": "search"}]
        if self.image and self.page == "weather:forecast":
            actions += [{"id": "copy", "title": "Copy forecast image", "icon": "copy"},
                        {"id": "open", "title": "Open forecast image", "icon": "image"}]
        actions.append({"id": "source", "title": "Weather data source", "icon": "globe"})
        return actions

    def persist(self):
        command("storage", op="set", key="preferences", value=self.preferences)

    def cancel(self):
        self.generation += 1
        if self.timer:
            self.timer.cancel()
            self.timer = None
        return self.generation

    def work(self, kind, function, delay=0):
        generation = self.generation

        def run():
            try:
                result = function()
                self.events.put({"type": "result", "kind": kind, "generation": generation, "result": result})
            except Exception as error:
                print(f"Weather {kind}: {error}", file=sys.stderr)
                self.events.put({"type": "result", "kind": kind, "generation": generation, "error": str(error)})

        self.timer = threading.Timer(delay, run)
        self.timer.daemon = True
        self.timer.start()

    def welcome(self):
        self.page = "weather:search"
        self.frame(empty={"icon": "weather", "title": "Your weather, at a glance",
                          "hint": "Type a city above, then press Enter on a match. We will remember your city and units."})

    def search(self, value):
        self.query = value.strip()[:200]
        self.cancel()
        self.cities = {}
        if not self.ready:
            self.frame(loading=True, loadingText="Restoring your city and units…")
            return
        if not self.query:
            if self.preferences["city"] and not self.keep_search_empty:
                self.load_weather()
            else:
                self.welcome()
            return
        self.keep_search_empty = False
        self.page = "weather:search"
        if len(self.query) < 2:
            self.frame(empty={"icon": "search", "title": "Keep typing", "hint": "Enter at least two characters to find a city."})
            return
        query = self.query
        self.frame(loading=True, loadingText=f"Finding {query}…")
        self.work("search", lambda: get_json("https://geocoding-api.open-meteo.com/v1/search",
                                            {"name": query, "count": 8, "language": "en", "format": "json"}), .35)

    def show_cities(self, data):
        self.cities = {}
        items = []
        for city in data.get("results", []):
            if not valid_city(city):
                continue
            item_id = f"city:{city.get('id', cache_key(city))}"
            if item_id in self.cities:
                continue
            self.cities[item_id] = city_record(city)
            region = ", ".join(dict.fromkeys(str(v) for v in [city.get("admin1"), city.get("country")] if v))
            items.append({"id": item_id, "title": city["name"], "subtitle": region,
                          "icon": "location", "accessories": [{"text": "View forecast"}],
                          "actions": [{"id": "default", "title": "View and remember city", "icon": "weather"}]})
        self.frame(items=items, empty={"icon": "search", "title": "No matching cities",
                                      "hint": "Try a nearby city or add a country, such as Paris, France."})

    def load_weather(self, force=False):
        self.cancel()
        self.page = "weather:forecast"
        city = dict(self.preferences["city"])
        self.forecast = None
        self.image = None
        self.frame(loading=True, loadingText=f"Loading the forecast for {city['name']}…")
        self.work("forecast", lambda: {**fetch_forecast(city, force), "city": city})

    def draw_weather(self):
        self.cancel()
        bundle = self.forecast
        unit = self.preferences["unit"]
        generation = self.generation

        def draw():
            try:
                from forecast_image import render_forecast
            except ImportError as error:
                raise ValueError("Weather image dependencies are missing. Reopen the launcher so Tabame can install Pillow and tzdata.") from error
            # Unique paths prevent Flutter from showing an old cached image after refresh.
            target = CACHE / f"forecast-{time.time_ns()}-{generation}.png"
            summary = render_forecast(bundle["data"], bundle["city"], unit, target,
                                      bundle["fetched_at"], bundle["stale"])
            return {"path": target, "summary": summary}

        self.frame(loading=True, loadingText="Drawing your forecast…")
        self.work("image", draw)

    def show_weather(self):
        self.page = "weather:forecast"
        banners = []
        if self.forecast["stale"]:
            age = max(0, round((time.time() - self.forecast["fetched_at"]) / 60))
            banners.append({"id": "cached", "style": "warning", "title": f"Cached forecast · {age} minutes old",
                            "message": self.forecast["warning"], "actions": [{"id": "refresh", "title": "Try again", "icon": "refresh"}]})
        self.frame("detail", detail={"wide": True, "markdown": f"![Weather forecast]({self.image.as_uri()})\n\n{self.summary}\n\nClick the image to zoom. Type another city to search. [Weather data: Open-Meteo](https://open-meteo.com/) · CC BY 4.0"},
                   banners=banners)
        # Bound generated image storage, retaining recent images for the lightbox.
        try:
            images = sorted(CACHE.glob("forecast-*.png"), key=lambda path: path.stat().st_mtime, reverse=True)
            for path in images[12:]:
                if path != self.image:
                    path.unlink(missing_ok=True)
            forecasts = sorted(CACHE.glob("*.json"), key=lambda path: path.stat().st_mtime, reverse=True)
            for path in forecasts[12:]:
                path.unlink(missing_ok=True)
        except OSError:
            pass

    def error(self, message):
        self.image = None
        self.frame(empty={"icon": "cloud", "title": "Weather unavailable", "hint": message,
                          "action": {"id": "retry", "title": "Try again", "icon": "refresh"}})

    def action(self, message):
        action = message.get("action", "default")
        item = message.get("id", "")
        self.rev = 0
        if action == "default" and item in self.cities:
            self.preferences["city"] = self.cities[item]
            self.forecast = None
            self.persist()
            self.keep_search_empty = False
            self.query = ""
            self.skip_empty_query = True
            self.load_weather()
            command("setQuery", text="")
        elif action == "units":
            self.preferences["unit"] = "celsius" if self.preferences["unit"] == "fahrenheit" else "fahrenheit"
            self.persist()
            if self.page == "weather:forecast" and self.forecast:
                self.draw_weather()
            else:
                self.search(self.query)
        elif action in ("refresh", "retry"):
            if self.page == "weather:search" and self.query:
                self.search(self.query)
            elif self.preferences["city"]:
                self.load_weather(force=True)
            else:
                self.welcome()
        elif action == "search":
            self.keep_search_empty = True
            self.query = ""
            self.skip_empty_query = True
            self.cancel()
            self.welcome()
            command("setQuery", text="")
        elif action in ("copy", "open") and self.image and self.page == "weather:forecast":
            command("copyImage" if action == "copy" else "open", path=str(self.image))
        elif action == "source":
            command("open", url="https://open-meteo.com/")

    def handle(self, message):
        event = message.get("type")
        if event == "init":
            self.query = str(message.get("query", ""))
            command("storage", op="get", key="preferences", requestId="weather-preferences")
            self.frame(loading=True, loadingText="Restoring your city and units…")
        elif event == "storage" and message.get("requestId") == "weather-preferences":
            stored = message.get("value")
            if isinstance(stored, dict):
                if stored.get("unit") in ("celsius", "fahrenheit"):
                    self.preferences["unit"] = stored["unit"]
                if valid_city(stored.get("city")):
                    self.preferences["city"] = city_record(stored["city"])
            self.ready = True
            self.search(self.query)
        elif event == "query":
            self.rev = message.get("rev", 0)
            value = str(message.get("text", "")).strip()[:200]
            # setQuery echoes an empty query after choosing a city; keep the active fetch.
            skip = self.skip_empty_query and not value
            self.skip_empty_query = False
            if skip:
                return
            self.search(value)
        elif event == "action" and self.ready:
            self.action(message)
        elif event in ("back", "navigate") and self.preferences["city"]:
            self.rev = message.get("rev", 0)
            self.query = ""
            self.keep_search_empty = False
            self.skip_empty_query = True
            self.load_weather()
            command("setQuery", text="")
        elif event == "result" and message.get("generation") == self.generation:
            if "error" in message:
                self.error(message["error"])
            elif message["kind"] == "search":
                self.show_cities(message["result"])
            elif message["kind"] == "forecast":
                self.forecast = message["result"]
                self.draw_weather()
            elif message["kind"] == "image":
                self.image = message["result"]["path"]
                self.summary = message["result"]["summary"]
                self.show_weather()

    def run(self):
        def read_input():
            try:
                for line in sys.stdin:
                    try:
                        message = json.loads(line)
                        if isinstance(message, dict):
                            self.events.put(message)
                    except (ValueError, TypeError):
                        print("Ignoring malformed weather plugin event.", file=sys.stderr)
            finally:
                self.events.put({"type": "close"})

        threading.Thread(target=read_input, daemon=True).start()
        while True:
            message = self.events.get()
            if message.get("type") == "close":
                self.cancel()
                return
            try:
                self.handle(message)
            except Exception as error:
                print(f"Weather event: {error}", file=sys.stderr)
                self.error("Something went wrong loading this forecast. Try again or search for another city.")


if __name__ == "__main__":
    WeatherPlugin().run()
