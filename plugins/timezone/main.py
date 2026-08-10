#!/usr/bin/env python3
"""Timezone Converter plugin for the Tabame launcher.

Grammar (after the `tz` keyword):
    tz 3 PM                 -> your local 3 PM shown across world zones
    tz 11:30 PM PT          -> Pacific time converted to local (+ world zones)
    tz 9 AM ET to CET       -> convert between two zones
    tz now in Tokyo         -> current time in Tokyo
    tz PT                   -> current time in Pacific Time
    tz noon UTC             -> word times work too (noon / midnight / now)

The bundled timezones.json catalog provides Windows/IANA region names and
aliases. IANA zones use Python's zoneinfo database (tzdata is installed by the
plugin manifest on Windows), with the catalog offset as a dependency-free
fallback. Explicit abbreviations (PST, PDT, EEST, ...) are always fixed.
"""

import json
import re
import subprocess
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

LOCAL_TZ = datetime.now().astimezone().tzinfo
TIMEZONE_DATA_FILE = Path(__file__).with_name("timezones.json")


def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def copy_to_clipboard(text):
    p = subprocess.Popen(["cmd", "/c", "clip"], stdin=subprocess.PIPE)
    p.communicate(text.encode("utf-16-le"))


# --- DST rules (built-in, no tzdata needed) ---------------------------------


def _nth_sunday(year, month, n):
    d = date(year, month, 1)
    d += timedelta(days=(6 - d.weekday()) % 7)
    return d + timedelta(days=7 * (n - 1))


def _last_sunday(year, month):
    nxt = date(year + 1, 1, 1) if month == 12 else date(year, month + 1, 1)
    d = nxt - timedelta(days=1)
    return d - timedelta(days=(d.weekday() + 1) % 7)


def _dst_active(rule, d):
    y = d.year
    if rule == "US":  # 2nd Sunday of March -> 1st Sunday of November
        return _nth_sunday(y, 3, 2) <= d < _nth_sunday(y, 11, 1)
    if rule == "EU":  # last Sunday of March -> last Sunday of October
        return _last_sunday(y, 3) <= d < _last_sunday(y, 10)
    if rule == "AU":  # southern hemisphere: 1st Sunday Oct -> 1st Sunday April
        return d >= _nth_sunday(y, 10, 1) or d < _nth_sunday(y, 4, 1)
    if rule == "NZ":  # last Sunday Sept -> 1st Sunday April
        return d >= _last_sunday(y, 9) or d < _nth_sunday(y, 4, 1)
    return False


# --- zone table ---------------------------------------------------------------


def _zone(name, std, std_lbl, dst=None, dst_lbl=None, rule=None, iana=None):
    return {
        "name": name,
        "std": std,
        "std_lbl": std_lbl,
        "dst": dst,
        "dst_lbl": dst_lbl,
        "rule": rule,
        "iana": iana,
    }


_UTC = _zone("UTC", 0, "UTC")
_PT = _zone("Pacific Time", -480, "PST", -420, "PDT", "US")
_MT = _zone("Mountain Time", -420, "MST", -360, "MDT", "US")
_CT = _zone("Central Time", -360, "CST", -300, "CDT", "US")
_ET = _zone("Eastern Time", -300, "EST", -240, "EDT", "US")
_UK = _zone("United Kingdom", 0, "GMT", 60, "BST", "EU")
_CET = _zone("Central Europe", 60, "CET", 120, "CEST", "EU")
_EET = _zone("Eastern Europe", 120, "EET", 180, "EEST", "EU")
_MSK = _zone("Moscow", 180, "MSK")
_TRT = _zone("Istanbul", 180, "TRT")
_GST = _zone("Dubai", 240, "GST")
_IST = _zone("India", 330, "IST")
_CN = _zone("China", 480, "CST")
_SGT = _zone("Singapore", 480, "SGT")
_HKT = _zone("Hong Kong", 480, "HKT")
_JST = _zone("Japan", 540, "JST")
_KST = _zone("Korea", 540, "KST")
_AET = _zone("Sydney", 600, "AEST", 660, "AEDT", "AU")
_NZT = _zone("New Zealand", 720, "NZST", 780, "NZDT", "NZ")

ALIASES = {
    "UTC": _UTC,
    "GMT": _UTC,
    "Z": _UTC,
    "PT": _PT,
    "PACIFIC": _PT,
    "LA": _PT,
    "LOS ANGELES": _PT,
    "SEATTLE": _PT,
    "SF": _PT,
    "SAN FRANCISCO": _PT,
    "PST": _zone("Pacific Standard", -480, "PST"),
    "PDT": _zone("Pacific Daylight", -420, "PDT"),
    "MT": _MT,
    "MOUNTAIN": _MT,
    "DENVER": _MT,
    "MST": _zone("Mountain Standard", -420, "MST"),
    "MDT": _zone("Mountain Daylight", -360, "MDT"),
    "CT": _CT,
    "CENTRAL": _CT,
    "CHICAGO": _CT,
    "CST": _zone("Central Standard (US)", -360, "CST"),
    "CDT": _zone("Central Daylight", -300, "CDT"),
    "ET": _ET,
    "EASTERN": _ET,
    "NYC": _ET,
    "NEW YORK": _ET,
    "TORONTO": _ET,
    "MIAMI": _ET,
    "EST": _zone("Eastern Standard", -300, "EST"),
    "EDT": _zone("Eastern Daylight", -240, "EDT"),
    "UK": _UK,
    "LONDON": _UK,
    "BST": _zone("British Summer", 60, "BST"),
    "CET": _CET,
    "PARIS": _CET,
    "BERLIN": _CET,
    "MADRID": _CET,
    "ROME": _CET,
    "AMSTERDAM": _CET,
    "STOCKHOLM": _CET,
    "WARSAW": _CET,
    "CEST": _zone("Central Europe Summer", 120, "CEST"),
    "EET": _EET,
    "BUCHAREST": _EET,
    "ATHENS": _EET,
    "HELSINKI": _EET,
    "KYIV": _EET,
    "KIEV": _EET,
    "EEST": _zone("Eastern Europe Summer", 180, "EEST"),
    "ISTANBUL": _TRT,
    "TRT": _TRT,
    "MSK": _MSK,
    "MOSCOW": _MSK,
    "GST": _GST,
    "DUBAI": _GST,
    "IST": _IST,
    "INDIA": _IST,
    "DELHI": _IST,
    "MUMBAI": _IST,
    "CHINA": _CN,
    "BEIJING": _CN,
    "SHANGHAI": _CN,
    "SGT": _SGT,
    "SINGAPORE": _SGT,
    "HKT": _HKT,
    "HONG KONG": _HKT,
    "JST": _JST,
    "TOKYO": _JST,
    "JAPAN": _JST,
    "KST": _KST,
    "SEOUL": _KST,
    "AET": _AET,
    "SYDNEY": _AET,
    "MELBOURNE": _AET,
    "AEST": _zone("Australian Eastern Standard", 600, "AEST"),
    "AEDT": _zone("Australian Eastern Daylight", 660, "AEDT"),
    "NZ": _NZT,
    "AUCKLAND": _NZT,
    "NZST": _zone("New Zealand Standard", 720, "NZST"),
    "NZDT": _zone("New Zealand Daylight", 780, "NZDT"),
}

# --- bundled region catalog ---------------------------------------------------


def _normalize_alias(value):
    return re.sub(r"\s+", " ", str(value).strip().upper())


def _catalog_label(entry):
    text = str(entry.get("text") or "").strip()
    label = re.sub(r"^\([^)]*\)\s*", "", text).strip()
    return label or str(entry.get("value") or "Unnamed region")


def _entry_zone_key(entry):
    for zone_name in entry.get("utc") or []:
        if isinstance(zone_name, str) and zone_name.strip():
            return zone_name.strip()
    return None


def _catalog_aliases(entry):
    label = _catalog_label(entry)
    candidates = [entry.get("value"), label]
    candidates.extend(part.strip() for part in label.split(","))
    candidates.extend(entry.get("utc") or [])
    for candidate in candidates:
        alias = _normalize_alias(candidate) if candidate else ""
        if alias:
            yield alias


def _load_timezone_catalog():
    try:
        with TIMEZONE_DATA_FILE.open(encoding="utf-8") as catalog_file:
            data = json.load(catalog_file)
    except (OSError, json.JSONDecodeError):
        return []
    if not isinstance(data, list):
        return []
    return [
        entry
        for entry in data
        if isinstance(entry, dict) and entry.get("value") and "offset" in entry
    ]


def _prefer_catalog_entry(candidate, current):
    """Prefer a standard entry when JSON contains standard/daylight duplicates."""
    return bool(current.get("isdst")) and not bool(candidate.get("isdst"))


def _build_catalog(catalog):
    selected = {}
    order = []
    for entry in catalog:
        key = _entry_zone_key(entry) or _normalize_alias(entry["value"])
        if key not in selected:
            order.append(key)
            selected[key] = entry
        elif _prefer_catalog_entry(entry, selected[key]):
            selected[key] = entry

    specs_by_key = {}
    specs = []
    for key in order:
        entry = selected[key]
        minutes = int(round(float(entry.get("offset", 0)) * 60))
        spec = _zone(
            _catalog_label(entry),
            minutes,
            str(entry.get("abbr") or "UTC"),
            iana=_entry_zone_key(entry),
        )
        spec["catalog_key"] = key
        spec["catalog_value"] = str(entry["value"])
        specs_by_key[key] = spec
        specs.append(spec)

    aliases = {}
    for entry in catalog:
        key = _entry_zone_key(entry) or _normalize_alias(entry["value"])
        spec = specs_by_key[key]
        for alias in _catalog_aliases(entry):
            aliases.setdefault(alias, spec)
    return specs, aliases


_ZONEINFO_CACHE = {}
TIMEZONE_CATALOG = _load_timezone_catalog()
CATALOG_SPECS, CATALOG_ALIASES = _build_catalog(TIMEZONE_CATALOG)
for _alias, _spec in CATALOG_ALIASES.items():
    # Keep the hand-written aliases for ambiguous abbreviations such as CST/IST.
    ALIASES.setdefault(_alias, _spec)

MAX_ALIAS_WORDS = max((len(alias.split()) for alias in ALIASES), default=1)


# zones offered when no explicit destination is given
_FALLBACK_WORLD = [
    ("UTC", _UTC),
    ("New York", _ET),
    ("Los Angeles", _PT),
    ("London", _UK),
    ("Paris", _CET),
    ("Bucharest", _EET),
    ("Dubai", _GST),
    ("India", _IST),
    ("Tokyo", _JST),
    ("Sydney", _AET),
]
WORLD = [(spec["name"], spec) for spec in CATALOG_SPECS] or _FALLBACK_WORLD


def _load_zoneinfo(key):
    if key in _ZONEINFO_CACHE:
        return _ZONEINFO_CACHE[key]
    try:
        from zoneinfo import ZoneInfo

        zone = ZoneInfo(key)
    except Exception:
        zone = None
    _ZONEINFO_CACHE[key] = zone
    return zone


def spec_tz(spec, on_date):
    """Materialize a zone spec using IANA data or its catalog fallback."""
    if spec.get("iana"):
        zone = _load_zoneinfo(spec["iana"])
        if zone is not None:
            return zone
    if spec["dst"] is not None and _dst_active(spec["rule"], on_date):
        return timezone(timedelta(minutes=spec["dst"]), spec["dst_lbl"])
    return timezone(timedelta(minutes=spec["std"]), spec["std_lbl"])


def resolve_token(token, on_date):
    """Resolve a (normalized, upper-case) token to (tzinfo, display_name, spec).

    Returns None when the token is not a known zone; raises ValueError for an
    IANA-style name that cannot be loaded.
    """
    token = _normalize_alias(token)
    if token in ("LOCAL", "HERE"):
        return LOCAL_TZ, "Local", None
    spec = ALIASES.get(token)
    if spec is not None:
        return spec_tz(spec, on_date), spec["name"], spec
    if "/" in token:
        # Re-case "europe/london" -> "Europe/London"
        key = "/".join(
            "_".join(w.capitalize() for w in part.split("_"))
            for part in token.split("/")
        )
        zone = _load_zoneinfo(key)
        if zone is not None:
            return zone, key, None
        raise ValueError(
            f"Couldn't load IANA zone `{token}` — install the `tzdata` package "
            "or use a region from the bundled catalog."
        )
    return None


# --- time parsing -------------------------------------------------------------

TIME_FORMATS = [
    ("%I:%M:%S %p", True),
    ("%I:%M %p", False),
    ("%I %p", False),
    ("%H:%M:%S", True),
    ("%H:%M", False),
    ("%H", False),
]

WORD_TIMES = {"NOON": "12:00 PM", "MIDNIGHT": "12:00 AM"}


def parse_time(text):
    """Parse a time string -> (hour, minute, second, has_seconds) or None."""
    t = text.strip().upper().replace("A.M.", "AM").replace("P.M.", "PM")
    t = re.sub(r"(?<=\d)\s*(AM|PM)\b", r" \1", t)  # "5PM" -> "5 PM"
    t = WORD_TIMES.get(t, t)
    if t == "NOW":
        return "now"
    for fmt, has_seconds in TIME_FORMATS:
        try:
            p = datetime.strptime(t, fmt)
            return (p.hour, p.minute, p.second, has_seconds)
        except ValueError:
            pass
    return None


# --- query parsing --------------------------------------------------------------


def parse_query(query):
    """Returns (base_datetime, src_desc, src_spec, dst_target, has_seconds).

    dst_target is (tzinfo, name) when the user asked for a specific
    destination ("... to CET"), including a zone-only query such as
    "Los Angeles". A zone-only query uses the current local time as its source.
    """
    today = datetime.now().date()
    q = re.sub(r"\s+", " ", query.strip().upper())

    parts = re.split(r"\s+(?:TO|IN)\s+|\s*(?:->|→)\s*", q, maxsplit=1)
    src_part = parts[0].strip()
    dst_target = None
    if len(parts) > 1 and parts[1].strip():
        resolved = resolve_token(parts[1], today)
        if resolved is None:
            raise ValueError(f"Unknown timezone: `{parts[1].strip()}`")
        dst_target = (resolved[0], resolved[1])

    # Peel the longest known source timezone off the end. Catalog names such
    # as "Central America Standard Time" can be several words long.
    src_tz, src_desc, src_spec = None, "Local", None
    tokens = src_part.split(" ") if src_part else []
    for n in range(min(len(tokens), MAX_ALIAS_WORDS), 0, -1):
        resolved = resolve_token(" ".join(tokens[-n:]), today)
        if resolved is not None:
            src_tz, src_desc, src_spec = resolved
            tokens = tokens[:-n]
            break

    time_text = " ".join(tokens).strip()
    tz = src_tz if src_tz is not None else LOCAL_TZ

    if not time_text:
        if src_tz is not None and src_spec is not None and dst_target is None:
            # A zone-only query means "show the current local time there". Keep
            # the local wall-clock datetime as the source so the destination
            # branch renders the requested zone instead of treating it as the
            # source of a full world comparison.
            base = datetime.now(timezone.utc).astimezone(LOCAL_TZ)
            return base, "Local", None, (src_tz, src_desc), False
        base = datetime.now(timezone.utc).astimezone(tz)
        return base, src_desc, src_spec, dst_target, False

    parsed = parse_time(time_text)
    if parsed is None:
        raise ValueError(f"Couldn't parse the time: `{time_text}`")
    if parsed == "now":
        base = datetime.now(timezone.utc).astimezone(tz)
        return base, src_desc, src_spec, dst_target, False

    h, m, s, has_seconds = parsed
    base = datetime(today.year, today.month, today.day, h, m, s, tzinfo=tz)
    return base, src_desc, src_spec, dst_target, has_seconds


# --- rendering -----------------------------------------------------------------

USAGE_MD = (
    "### Usage\n\n"
    "- `3 PM` — your local time across world zones\n"
    "- `11:30 PM PT` — Pacific → local\n"
    "- `9 AM ET to CET` — zone → zone\n"
    "- `now in Tokyo`, `noon UTC`, `PT`\n"
    "- `Los Angeles` or `Kathmandu` — current local time in that zone\n\n"
    "Zones: `PT` `MT` `CT` `ET` `UTC` `UK` `CET` `EET` `IST` `JST` `AEST`…\n"
    "The bundled catalog also accepts Windows region names, city names, and IANA IDs\n"
    "such as `Cairo`, `Kathmandu`, `America/Sao_Paulo`, or `Pacific/Fiji`."
)

LAST = {"frame": None, "copies": {}}


def fmt_time(dt, has_seconds):
    s = dt.strftime("%I:%M:%S %p" if has_seconds else "%I:%M %p")
    return s.lstrip("0")


def fmt_offset(dt):
    minutes = int(dt.utcoffset().total_seconds() // 60)
    sign = "+" if minutes >= 0 else "-"
    minutes = abs(minutes)
    return f"UTC{sign}{minutes // 60}" + (
        f":{minutes % 60:02d}" if minutes % 60 else ""
    )


def tz_abbr(dt):
    name = dt.tzname() or ""
    return name if 0 < len(name) <= 5 else fmt_offset(dt)


def make_item(idx, label, target_tz, base, src_line, has_seconds):
    dt = base.astimezone(target_tz)
    time_str = fmt_time(dt, has_seconds)
    day_shift = (dt.date() - base.date()).days

    accessories = [{"text": fmt_offset(dt)}]
    if day_shift:
        accessories.append({"text": f"{day_shift:+d} day"})

    copy_str = f"{time_str} {tz_abbr(dt)} — {dt.strftime('%a, %b %d')}"
    shift_note = f"  *({day_shift:+d} day)*" if day_shift else ""
    preview = (
        f"## {label} — {tz_abbr(dt)}\n\n"
        f"# {time_str}\n\n"
        f"{dt.strftime('%A, %B %d')}{shift_note}\n\n"
        f"`{fmt_offset(dt)}`\n\n"
        f"---\n\n"
        f"**Source:** {src_line}\n\n"
        f"{USAGE_MD}"
    )
    item = {
        "id": f"i{idx}",
        "title": time_str,
        "subtitle": f"{label} · {tz_abbr(dt)}",
        "icon": "clock",
        "accessories": accessories,
        "actions": [{"id": "copy", "title": "Copy time", "icon": "copy"}],
        "preview": {"markdown": preview, "wide": False},
    }
    return item, copy_str


def render(rev, query):
    try:
        base, src_desc, src_spec, dst_target, has_seconds = parse_query(query)
    except Exception as e:
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "detail",
                "detail": {"markdown": f"# Timezone Converter\n\n> {e}\n\n{USAGE_MD}"},
            }
        )
        return

    src_line = (
        f"{fmt_time(base, has_seconds)} {tz_abbr(base)} ({src_desc}), "
        f"{base.strftime('%a, %b %d')}"
    )

    # Decide which zones to show.
    targets = []
    if dst_target is not None:
        targets.append((dst_target[1], dst_target[0]))
        if (
            base.astimezone(LOCAL_TZ).utcoffset()
            != base.astimezone(dst_target[0]).utcoffset()
        ):
            targets.append(("Local", LOCAL_TZ))
    else:
        targets.append(("Local", LOCAL_TZ))
        for label, spec in WORLD:
            if spec is src_spec:
                continue
            targets.append((label, spec_tz(spec, base.date())))

    items, copies = [], {}
    seen = set()
    for idx, (label, tz) in enumerate(targets):
        item, copy_str = make_item(idx, label, tz, base, src_line, has_seconds)
        key = (label, item["title"])
        if key in seen:
            continue
        seen.add(key)
        items.append(item)
        copies[item["id"]] = copy_str

    frame = {
        "type": "render",
        "rev": rev,
        "view": "list",
        "preview": {"enabled": True, "wide": False},
        "emptyText": "Type a time or timezone, e.g. 3 PM PT or Los Angeles",
        "items": items,
    }
    LAST["frame"] = frame
    LAST["copies"] = copies
    send(frame)


def handle_action(item_id, action_name):
    if action_name not in ("default", "copy"):
        return
    text = LAST["copies"].get(item_id)
    if text is None or LAST["frame"] is None:
        return
    copy_to_clipboard(text)

    # Re-send the same list with a "copied" badge on the acted item, so the
    # results stay on screen instead of being replaced by a confirmation page.
    frame = json.loads(json.dumps(LAST["frame"]))
    frame["rev"] = 0
    for item in frame["items"]:
        if item["id"] == item_id:
            item["accessories"] = [
                a for a in item.get("accessories", []) if a.get("text") != "✓ copied"
            ]
            item["accessories"].append({"text": "✓ copied"})
    send(frame)


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
        elif t in ("init", "query"):
            try:
                render(msg.get("rev", 0), msg.get("text", msg.get("query", "")))
            except Exception as e:
                print(f"render error: {e}", file=sys.stderr, flush=True)
        elif t == "action":
            try:
                handle_action(msg.get("id", ""), msg.get("action", "default"))
            except Exception as e:
                print(f"action error: {e}", file=sys.stderr, flush=True)


if __name__ == "__main__":
    main()
