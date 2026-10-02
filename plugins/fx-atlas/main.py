#!/usr/bin/env python3
"""FX Atlas: Tabame's JSON-lines protocol, daily rates, and a rendered receipt."""

import argparse
import hashlib
import json
import math
import re
import sys
import threading
import time
from datetime import date, timedelta
from decimal import Decimal, InvalidOperation
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent
CACHE = ROOT / ".cache"
API = "https://api.frankfurter.dev/v2"
RANGES = (7, 30, 90, 365)
HELP = (
    "Use **`100 EUR USD`**, **`250 USD to RON`**, or **`EUR/GBP`**. "
    "Add **`7d`**, **`30d`**, **`90d`**, or **`365d`** for history.\n\n"
    "Use a decimal point; commas are thousands separators (`1,250.50`). "
    "Currency codes are three letters. The default is `100 EUR USD`."
)


class RateError(Exception):
    pass


def parse_query(text, default_days=30):
    text = text.strip().upper()
    if len(text) > 120:
        raise ValueError("Keep the conversion under 120 characters.")
    days = default_days
    match = re.search(r"\s+(7|30|90|365)D$", text)
    if match:
        days = int(match[1])
        text = text[:match.start()]
    if not text:
        return Decimal("100"), "EUR", "USD", days
    text = re.sub(r"\s*(?:/|→|\bTO\b|\bIN\b)\s*", " ", text).strip()
    parts = text.split()
    if len(parts) == 2 and all(re.fullmatch(r"[A-Z]{3}", part) for part in parts):
        parts.insert(0, "1")
    if len(parts) != 3 or not all(re.fullmatch(r"[A-Z]{3}", part) for part in parts[1:]):
        raise ValueError("Enter an amount followed by two currency codes.")
    raw = parts[0]
    if not re.fullmatch(r"[+-]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,8})?", raw):
        raise ValueError("Use a decimal point, for example 1250.50 or 1,250.50.")
    try:
        amount = Decimal(raw.replace(",", ""))
    except InvalidOperation as exc:
        raise ValueError("That amount could not be read.") from exc
    if abs(amount) > Decimal("1000000000000"):
        raise ValueError("The maximum amount is 1,000,000,000,000.")
    return amount, parts[1], parts[2], days


def request_json(route, params=None):
    url = API + route + ("?" + urlencode(params) if params else "")
    request = Request(url, headers={"Accept": "application/json", "User-Agent": "Tabame-FX-Atlas/1.0"})
    try:
        with urlopen(request, timeout=12) as response:
            data = response.read(4_000_001)
            if len(data) > 4_000_000:
                raise RateError("The rate service returned an unexpectedly large response.")
            return json.loads(data)
    except HTTPError as exc:
        if exc.code in (400, 404, 422):
            raise ValueError("This currency pair is not available. Check both currency codes.") from exc
        raise RateError("The rate service is busy. Please try Refresh shortly.") from exc
    except (URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
        raise RateError("Could not reach the rate service. Check your connection and try Refresh.") from exc


def validate_row(row, base, target):
    if not isinstance(row, dict) or row.get("base") != base or row.get("quote") != target:
        raise RateError("The rate service returned a different currency pair.")
    try:
        date.fromisoformat(row["date"])
        value = float(row["rate"])
        if not math.isfinite(value) or value <= 0:
            raise ValueError()
    except (KeyError, TypeError, ValueError, OverflowError) as exc:
        raise RateError("The rate service returned an invalid observation.") from exc
    return {"date": row["date"], "rate": str(row["rate"])}


def read_cache(path, base, target):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if data["base"] != base or data["quote"] != target:
            return None
        validate_row(data, base, target)
        if not isinstance(data["history"], list) or len(data["history"]) > 400:
            return None
        for row in data["history"]:
            validate_row({**row, "base": base, "quote": target}, base, target)
        if not math.isfinite(float(data["fetched"])):
            return None
        return data
    except (OSError, ValueError, KeyError, TypeError, RateError):
        return None


def fetch_quote(base, target, days, force=False):
    CACHE.mkdir(parents=True, exist_ok=True)
    cache_path = CACHE / f"rates-{base}-{target}-{days}.json"
    cached = read_cache(cache_path, base, target)
    ttl = 3600 if cached and cached["history"] else 60
    if cached and not force and 0 <= time.time() - cached["fetched"] < ttl:
        return {**cached, "stale": False}
    try:
        if base == target:
            # Validate even identity conversions: AAA -> AAA must not look supported.
            request_json(f"/currency/{base}")
            return {"base": base, "quote": target, "rate": "1", "date": date.today().isoformat(),
                    "history": [], "fetched": time.time(), "stale": False}
        latest = validate_row(request_json(f"/rate/{base}/{target}"), base, target)
        end = date.fromisoformat(latest["date"])
        start = end - timedelta(days=days)
        history_error = False
        try:
            rows = request_json("/rates", {"base": base, "quotes": target,
                                           "from": start.isoformat(), "to": end.isoformat()})
            if not isinstance(rows, list):
                raise RateError("History was not returned as observations.")
            observations = {}
            for row in rows:
                item = validate_row(row, base, target)
                if start.isoformat() <= item["date"] <= end.isoformat():
                    observations[item["date"]] = item
            observations[latest["date"]] = latest
            history = sorted(observations.values(), key=lambda row: row["date"])
        except (RateError, ValueError):
            history = []
            history_error = True
        quote = {**latest, "base": base, "quote": target, "history": history,
                 "fetched": time.time(), "history_error": history_error, "stale": False}
        # Rates are a disposable local cache, not user preferences or secrets.
        try:
            temporary = cache_path.with_suffix(".tmp")
            temporary.write_text(json.dumps(quote), encoding="utf-8")
            temporary.replace(cache_path)
        except OSError:
            pass
        return quote
    except RateError:
        if cached:
            return {**cached, "stale": True}
        raise


def artifact(quote, amount, base, target, days, dark):
    from render import RENDER_VERSION, render_card
    signature = json.dumps([RENDER_VERSION, quote, str(amount), base, target, days, dark], sort_keys=True)
    name = hashlib.sha256(signature.encode()).hexdigest()[:20]
    output = CACHE / f"card-{name}.png"
    if not output.exists():
        render_card(quote, amount, base, target, days, output, dark)
    # Bound generated images while retaining recent images for the host's lightbox.
    cards = sorted(CACHE.glob("card-*.png"), key=lambda path: path.stat().st_mtime, reverse=True)
    for old in cards[40:]:
        if old != output:
            try:
                old.unlink()
            except OSError:
                pass
    return output


class Plugin:
    def __init__(self):
        self.lock = threading.Condition(threading.RLock())
        self.pending = None
        self.serial = 0
        self.closed = False
        self.query = ""
        self.days = 30
        self.dark = True
        self.result = None
        self.worker = threading.Thread(target=self.work, daemon=True)
        self.worker.start()

    def send(self, message):
        with self.lock:
            if not self.closed:
                print(json.dumps(message, ensure_ascii=True), flush=True)

    def command(self, command, **fields):
        self.send({"type": "command", "command": command, **fields})

    def frame(self, rev, **fields):
        self.send({"type": "render", "rev": rev, "view": "detail",
                   "page": {"id": "fx-atlas:converter", "title": "FX Atlas", "history": "none"},
                   "placeholder": "100 EUR USD · optional 7d / 30d / 90d / 365d", **fields})

    def schedule(self, text, rev=0, force=False):
        with self.lock:
            self.serial += 1
            self.query = text
            self.result = None
            self.pending = (self.serial, text, rev, force, self.dark, self.days, time.monotonic() + .25)
            self.frame(rev, loading=True, loadingText="Preparing your exchange card…",
                       detail={"markdown": "", "wide": True})
            self.lock.notify()

    def work(self):
        while True:
            with self.lock:
                while not self.closed:
                    if self.pending:
                        delay = self.pending[-1] - time.monotonic()
                        if delay <= 0:
                            break
                        self.lock.wait(delay)
                    else:
                        self.lock.wait()
                if self.closed:
                    return
                serial, text, rev, force, dark, default_days, _ = self.pending
                self.pending = None
            try:
                amount, base, target, days = parse_query(text, default_days)
                from render import money
                quote = fetch_quote(base, target, days, force)
                with self.lock:
                    if serial != self.serial or self.closed:
                        continue
                path = artifact(quote, amount, base, target, days, dark)
                converted = money(amount * Decimal(quote["rate"]), target, grouped=False)
                with self.lock:
                    if serial != self.serial or self.closed:
                        continue
                    self.days = days
                    self.result = {"amount": amount, "base": base, "target": target, "days": days,
                                   "converted": converted, "path": path, "date": quote["date"]}
                    actions = [
                        {"id": "default", "title": "Copy converted value", "icon": "copy"},
                        {"id": "copy-summary", "title": "Copy conversion with rate date", "icon": "copy"},
                        {"id": "copy-image", "title": "Copy chart image", "icon": "image"},
                        {"id": "open-image", "title": "Open chart image", "icon": "open"},
                        {"id": "swap", "title": "Swap currencies", "icon": "sync", "shortcut": "ctrl+shift+s"},
                        {"id": "refresh", "title": "Refresh rates", "icon": "refresh", "shortcut": "ctrl+r"},
                        {"id": "theme", "title": "Switch image theme", "icon": "palette"},
                        {"id": "source", "title": "About the rate source", "icon": "info"},
                    ]
                    for period in RANGES:
                        actions.append({"id": f"range-{period}", "title": f"Show {period}-day history", "icon": "calendar"})
                    banners = []
                    if quote.get("stale"):
                        banners.append({"id": "offline", "style": "warning", "title": "Saved reference rate",
                                        "message": f"Refresh failed. Showing cached data dated {quote['date']}.",
                                        "actions": [{"id": "refresh", "title": "Retry", "icon": "refresh"}]})
                    if quote.get("history_error"):
                        banners.append({"id": "history", "style": "warning", "title": "History unavailable",
                                        "message": "The latest rate loaded, but the history request failed. Refresh to retry."})
                    alt = f"{amount} {base} = {converted} {target}. Reference rate dated {quote['date']}."
                    self.frame(rev, detail={"wide": True, "markdown": f"![{alt}]({path.as_uri()})"},
                               actions=actions, banners=banners,
                               toolbar={"scope": {"value": f"{days}D", "options": [f"{period}D" for period in RANGES]}},
                               floatingAction=[{"id": "default", "title": "Copy value", "icon": "copy"},
                                               {"id": "swap", "title": "Swap", "icon": "sync"}])
            except Exception as exc:
                with self.lock:
                    if serial != self.serial or self.closed:
                        continue
                    if isinstance(exc, ImportError):
                        message = "Pillow is required to draw the exchange card. Reopen the launcher to install the declared dependency."
                    elif isinstance(exc, (ValueError, RateError)):
                        message = str(exc)
                    else:
                        print(f"FX Atlas: {type(exc).__name__}: {exc}", file=sys.stderr, flush=True)
                        message = "The exchange card could not be created. Please try Refresh."
                    self.frame(rev, detail={"markdown": f"## FX Atlas\n\n{message}\n\n{HELP}"},
                               actions=[{"id": "refresh", "title": "Refresh", "icon": "refresh"}],
                               floatingAction={"id": "example", "title": "Try 100 EUR USD", "icon": "currency"})

    def set_range(self, value):
        try:
            days = int(str(value).upper().removesuffix("D"))
        except ValueError:
            return
        if days not in RANGES:
            return
        # Keep the visible query authoritative, including an explicit range suffix.
        with self.lock:
            self.days = days
            query = re.sub(r"\s+(7|30|90|365)d$", "", self.query.strip(), flags=re.I)
            self.serial += 1
            self.pending = None
            self.result = None
        self.command("setQuery", text=f"{query or '100 EUR USD'} {days}d")

    def action(self, action):
        if action == "refresh":
            self.schedule(self.query, force=True)
        elif action == "example":
            self.command("setQuery", text="100 EUR USD")
        elif action == "source":
            self.command("open", url="https://frankfurter.dev/")
        elif action == "theme":
            self.dark = not self.dark
            self.schedule(self.query)
        elif action.startswith("range-"):
            self.set_range(action[6:])
        else:
            with self.lock:
                result = self.result
                if result is None:
                    return
                if action in ("default", "copy-summary"):
                    value = result["converted"]
                    if action == "copy-summary":
                        value = (f"{result['amount']} {result['base']} = {value} {result['target']} "
                                 f"(reference rate {result['date']}; Frankfurter; fees excluded)")
                    self.command("copy", text=value)
                elif action == "copy-image":
                    self.command("copyImage", path=str(result["path"]))
                elif action == "open-image":
                    self.command("open", url=result["path"].as_uri())
                elif action == "swap":
                    self.serial += 1
                    self.pending = None
                    self.result = None
                    self.command("setQuery", text=f"{result['amount']} {result['target']} {result['base']} {result['days']}d")

    def run(self):
        try:
            for line in sys.stdin:
                try:
                    message = json.loads(line)
                    if not isinstance(message, dict):
                        continue
                    kind = message.get("type")
                    if kind == "close":
                        break
                    if kind == "init":
                        self.dark = message.get("theme", {}).get("dark", True)
                    if kind in ("init", "query"):
                        text = message.get("text", message.get("query", ""))
                        if isinstance(text, str):
                            self.schedule(text, message.get("rev", 0))
                    elif kind == "action":
                        self.action(str(message.get("action", "default")))
                    elif kind == "toolbarChange" and message.get("id") == "scope":
                        self.set_range(message.get("value", "30D"))
                except (ValueError, TypeError, AttributeError) as exc:
                    print(f"FX Atlas ignored malformed input: {type(exc).__name__}", file=sys.stderr, flush=True)
        finally:
            with self.lock:
                self.closed = True
                self.pending = None
                self.lock.notify()
            # HTTP has a timeout; the daemon never holds launcher shutdown open.
            self.worker.join(timeout=.2)


def main():
    parser = argparse.ArgumentParser(description="FX Atlas currency converter")
    parser.add_argument("--snapshot", metavar="QUERY", help="Render an actual exchange card without the launcher")
    parser.add_argument("--output", default=str(ROOT / "preview.png"))
    parser.add_argument("--light", action="store_true")
    args = parser.parse_args()
    if args.snapshot is not None:
        from render import money, render_card
        amount, base, target, days = parse_query(args.snapshot)
        quote = fetch_quote(base, target, days, force=True)
        output = Path(args.output).resolve()
        result = render_card(quote, amount, base, target, days, output, not args.light)
        print(json.dumps({"path": str(output), "rate": quote["rate"], "rate_date": quote["date"],
                          "converted": money(result, target), "currency": target,
                          "observations": len(quote["history"]), "cached": quote.get("stale", False)}))
    else:
        Plugin().run()


if __name__ == "__main__":
    main()
