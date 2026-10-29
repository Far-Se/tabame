"""Weather Board: Tabame NDJSON plugin and standalone forecast image exporter."""

import argparse
import hashlib
import json
import queue
import sys
import threading
import time
from pathlib import Path

from forecast import (city_key, city_label, condition, fetch_forecast, number,
                      search_cities, temperature, valid_city, valid_forecast)

ROOT = Path(__file__).resolve().parent
FRESH_SECONDS = 10 * 60
MAX_CACHE_AGE = 24 * 60 * 60
STATE_KEY = "weather-board-state-v1"


class WeatherBoard:
    def __init__(self):
        self.lock = threading.RLock()
        self.jobs = queue.Queue(maxsize=1)
        self.timer = None
        self.closed = False
        self.ready = False
        self.requested_state = False
        self.generation = 0
        self.query = ""
        self.rev = 0
        self.city = None
        self.units = "celsius"
        self.cache = None
        self.cities = {}
        self.image_path = None
        self.force_refresh = False
        threading.Thread(target=self.worker, daemon=True).start()

    def send(self, message):
        # Called under the same lock by the event loop and background worker.
        if not self.closed:
            sys.stdout.write(json.dumps(message, ensure_ascii=True, allow_nan=False) + "\n")
            sys.stdout.flush()

    def command(self, command, **fields):
        self.send({"type": "command", "command": command, **fields})

    def frame(self, rev, view="list", **fields):
        self.send({
            "type": "render", "rev": rev, "view": view,
            "page": {"id": "weather-board", "title": "Weather Board", "history": "replace"},
            "placeholder": "Search a city, e.g. Paris, France…",
            "toolbar": {"filters": [{
                "id": "units", "label": "Units", "value": self.units,
                "options": [{"value": "celsius", "label": "Celsius · °C"},
                            {"value": "fahrenheit", "label": "Freedom Unit · °F"}],
            }]},
            "actions": [
                {"id": "refresh", "title": "Refresh forecast", "icon": "refresh", "shortcut": "ctrl+r"},
                {"id": "home", "title": "Last city", "icon": "home"},
                {"id": "celsius", "title": "Use Celsius (°C)", "icon": "sun"},
                {"id": "fahrenheit", "title": "Use Freedom Unit (°F)", "icon": "flag"},
                {"id": "copy-image", "title": "Copy forecast image", "icon": "copy"},
                {"id": "open-image", "title": "Open forecast image", "icon": "image"},
            ],
            **fields,
        })

    def persist(self):
        self.command("storage", op="set", key=STATE_KEY, value={
            "units": self.units, "city": self.city, "cache": self.cache,
        })

    def restore(self, value):
        if isinstance(value, dict):
            if value.get("units") in ("celsius", "fahrenheit"):
                self.units = value["units"]
            if valid_city(value.get("city")):
                self.city = value["city"]
            cached = value.get("cache")
            if (isinstance(cached, dict) and number(cached.get("fetched"))
                    and isinstance(cached.get("cityKey"), str)
                    and valid_forecast(cached.get("data"))):
                self.cache = cached
        self.ready = True
        self.handle_query(self.query, self.rev)

    def cache_for(self, city):
        if (self.cache and self.cache["cityKey"] == city_key(city)
                and 0 <= time.time() - self.cache["fetched"] <= MAX_CACHE_AGE):
            return self.cache
        return None

    def invalidate(self):
        self.generation += 1
        if self.timer:
            self.timer.cancel()
            self.timer = None
        self.cities = {}
        self.image_path = None
        return self.generation

    def enqueue(self, job):
        with self.lock:
            if self.closed or job[0] != self.generation:
                return
            try:
                self.jobs.get_nowait()
            except queue.Empty:
                pass
            self.jobs.put_nowait(job)

    def schedule(self, kind, payload, rev, delay=0):
        job = (self.generation, rev, kind, payload, self.units)
        if delay:
            self.timer = threading.Timer(delay, self.enqueue, (job,))
            self.timer.daemon = True
            self.timer.start()
        else:
            self.enqueue(job)

    def handle_query(self, query, rev):
        self.query, self.rev = str(query).strip()[:200], rev
        self.invalidate()
        if not self.ready:
            self.frame(rev, loading=True, loadingText="Restoring your city and units…", items=[])
            return
        if self.query:
            if len(self.query) < 2:
                self.frame(rev, items=[], canGoBack=bool(self.city), empty={
                    "icon": "search", "title": "Keep typing…", "hint": "Enter at least two letters of a city or postal code.",
                })
                return
            self.frame(rev, loading=True, loadingText="Finding your city…", items=[], canGoBack=bool(self.city))
            self.schedule("search", self.query, rev, delay=0.35)
        elif self.city:
            self.load_city(self.city, rev, force=self.force_refresh)
        else:
            self.welcome(rev)

    def welcome(self, rev):
        self.frame(rev, "detail", detail={"markdown": (
            "# A little outlook for your day\n\n"
            "Search for a city above, then choose the matching location.\n\n"
            "Your forecast image includes **24 hours** and **seven days**, with temperatures, "
            "precipitation, wind, UV, and sunrise / sunset.\n\n"
            "Use the **Units** selector for **Celsius** or **Freedom Unit (Fahrenheit)**. "
            "Your city and units are saved automatically. Next time, just type **weatherboard**.\n\n"
            "Weather by [Open-Meteo](https://open-meteo.com/). No API key needed."
        )})

    def load_city(self, city, rev, force=False):
        cached = self.cache_for(city)
        self.frame(rev, loading=True, loadingText=f'Preparing the forecast for {city["name"]}…', items=[])
        self.schedule("forecast", {"city": city, "cache": cached, "force": force}, rev)

    def render_board(self, city, cached, units, stale):
        # Lazy import lets a missing Pillow dependency produce a useful UI error.
        from render import render_forecast

        digest = hashlib.sha256(json.dumps([city, cached, units, stale], sort_keys=True).encode()).hexdigest()[:20]
        path = ROOT / ".cache" / f"forecast-{digest}.png"
        if not path.exists():
            render_forecast(city, cached["data"], units, path, cached["fetched"], stale)
        return path

    def show_board(self, rev, city, cached, path, stale=False, warning=None):
        self.image_path = path
        current = cached["data"]["current"]
        summary = (f'{city["name"]}: {temperature(current.get("temperature_2m"), self.units)}'
                   f'{"F" if self.units == "fahrenheit" else "C"}, '
                   f'{condition(current.get("weather_code"), current.get("is_day") == 1)}')
        # Escape markdown metacharacters from location data.
        summary = summary.replace("\\", "\\\\").replace("[", "\\[").replace("]", "\\]")
        banners = []
        if stale:
            banners.append({"id": "cached", "style": "warning", "title": "Showing a saved forecast",
                            "message": warning or "The weather service is unavailable. Check the update date on the image.",
                            "actions": [{"id": "refresh", "title": "Retry", "icon": "refresh"}]})
        self.frame(rev, "detail", detail={"wide": True, "markdown": (
            f'![{summary}]({path.as_uri()})\n\n'
            f'{summary}. Click the image to zoom.\n\n'
            '[Weather: Open-Meteo](https://open-meteo.com/) · '
            '[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) · '
            'Location data: GeoNames'
        )}, banners=banners, floatingAction=[
            {"id": "refresh", "title": "Refresh", "icon": "refresh"},
            {"id": "copy-image", "title": "Copy image", "icon": "copy"},
        ])

    def show_error(self, rev, message):
        self.frame(rev, "detail", canGoBack=bool(self.city), detail={"markdown": (
            "# Weather is taking a rain check\n\n" + message +
            "\n\nRetry below, or search for another city above. Your saved city and units are kept."
        )}, floatingAction={"id": "retry", "title": "Try again", "icon": "refresh"})

    def worker(self):
        while True:
            generation, rev, kind, payload, units = self.jobs.get()
            with self.lock:
                if self.closed:
                    return
                if generation != self.generation:
                    continue
            try:
                if kind == "search":
                    result = search_cities(payload)
                    with self.lock:
                        if generation != self.generation or self.closed:
                            continue
                        self.cities = {"city:" + city_key(city): city for city in result}
                        self.frame(rev, items=[{
                            "id": key, "title": city["name"], "subtitle": city_label(city), "icon": "location",
                            "accessories": [{"text": str(city.get("country_code", ""))}],
                            "actions": [{"id": "default", "title": "Show forecast", "icon": "weather"}],
                        } for key, city in self.cities.items()], canGoBack=bool(self.city), empty={
                            "icon": "search", "title": "No matching cities",
                            "hint": "Try a nearby city or add a country, for example Paris, France.",
                        })
                else:
                    city, cached = payload["city"], payload["cache"]
                    stale, warning = False, None
                    if payload["force"] or not cached or time.time() - cached["fetched"] >= FRESH_SECONDS:
                        try:
                            data = fetch_forecast(city)
                            cached = {"cityKey": city_key(city), "fetched": time.time(), "data": data}
                        except ValueError as exc:
                            if cached is None:
                                raise
                            stale, warning = True, str(exc)
                    with self.lock:
                        if generation != self.generation or self.closed:
                            continue
                    path = self.render_board(city, cached, units, stale)
                    with self.lock:
                        if generation != self.generation or self.closed:
                            continue
                        self.cache = cached
                        self.force_refresh = False
                        self.persist()
                        self.show_board(rev, city, cached, path, stale, warning)
                    # Keep a small, bounded set of generated images; unique filenames
                    # prevent Flutter's image cache from showing an older forecast.
                    for old in sorted((ROOT / ".cache").glob("forecast-*.png"), key=lambda p: p.stat().st_mtime, reverse=True)[8:]:
                        try:
                            old.unlink()
                        except OSError:
                            pass
            except Exception as exc:
                with self.lock:
                    if generation != self.generation or self.closed:
                        continue
                    print(f"Weather Board: {type(exc).__name__}: {exc}", file=sys.stderr)
                    if isinstance(exc, ImportError):
                        message = "A plugin dependency is missing. Reopen the launcher so Tabame can install Pillow, tzdata, and certifi."
                    elif isinstance(exc, ValueError):
                        message = str(exc)
                    else:
                        message = "The forecast could not be prepared. Please retry."
                    self.show_error(rev, message)

    def handle(self, message):
        if not isinstance(message, dict):
            return
        kind = message.get("type")
        raw_rev = message.get("rev", 0)
        rev = raw_rev if isinstance(raw_rev, int) and raw_rev >= 0 else 0
        if kind in ("init", "query"):
            if not self.requested_state:
                self.requested_state = True
                self.command("storage", op="get", key=STATE_KEY, requestId="weather-board-restore")
            self.handle_query(message.get("text", message.get("query", "")), rev)
        elif kind == "storage" and message.get("requestId") == "weather-board-restore" and not self.ready:
            self.restore(message.get("value"))
        elif kind in ("back", "navigate"):
            self.go_home(rev)
        elif kind == "toolbarChange" and message.get("id") == "units":
            self.set_units(message.get("value"), rev)
        elif kind == "action":
            action, item = message.get("action"), message.get("id")
            if action == "default" and item in self.cities:
                self.city = self.cities[item]
                self.persist()
                self.go_home(0)
            elif action in ("celsius", "fahrenheit"):
                self.set_units(action, 0)
            elif action == "home":
                self.go_home(0)
            elif action == "retry":
                if self.query:
                    self.handle_query(self.query, 0)
                else:
                    self.refresh()
            elif action in ("refresh", "default"):
                self.refresh()
            elif action in ("copy-image", "open-image"):
                if self.image_path and self.image_path.exists():
                    self.command("copyImage" if action == "copy-image" else "open", path=str(self.image_path))
                else:
                    self.command("toast", text="Choose a city and wait for its forecast image.", style="info")

    def set_units(self, units, rev):
        if units in ("celsius", "fahrenheit") and self.ready:
            self.units = units
            self.persist()
            self.handle_query(self.query, rev)

    def go_home(self, rev):
        if self.query:
            self.command("setQuery", text="")
        self.handle_query("", rev)

    def refresh(self):
        if self.city:
            self.force_refresh = True
            if self.query:
                self.command("setQuery", text="")
            self.query = ""
            self.invalidate()
            self.load_city(self.city, 0, force=True)
        else:
            self.welcome(0)

    def run(self):
        try:
            for line in sys.stdin:
                try:
                    message = json.loads(line)
                    if isinstance(message, dict) and message.get("type") == "close":
                        break
                    with self.lock:
                        self.handle(message)
                except (json.JSONDecodeError, TypeError, ValueError) as exc:
                    print(f"Weather Board ignored invalid input: {exc}", file=sys.stderr)
        finally:
            with self.lock:
                self.closed = True
                self.invalidate()
        # Network work runs on a daemon: close and stdin EOF exit immediately.


def main():
    parser = argparse.ArgumentParser(description="Tabame Weather Board")
    parser.add_argument("--preview", metavar="CITY", help="Export a live forecast PNG for the first city match")
    parser.add_argument("--demo", action="store_true", help="Export a clearly labeled illustrative forecast (no network)")
    parser.add_argument("--units", choices=("celsius", "fahrenheit"), default="celsius")
    parser.add_argument("--output", type=Path, default=ROOT / ".cache" / "preview.png")
    args = parser.parse_args()
    if args.preview or args.demo:
        from render import render_forecast

        try:
            if args.demo:
                from sample import sample_forecast

                city, data = sample_forecast()
            else:
                cities = search_cities(args.preview)
                if not cities:
                    raise ValueError("No matching city. Try adding a country name.")
                city = cities[0]
                data = fetch_forecast(city)
            fetched = data["current"]["time"] if args.demo else time.time()
            output = render_forecast(city, data, args.units, args.output.resolve(), fetched, sample=args.demo)
            print(f"{city_label(city)}\n{output}")
        except (ValueError, OSError) as exc:
            print(str(exc), file=sys.stderr)
            return 1
    else:
        WeatherBoard().run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
