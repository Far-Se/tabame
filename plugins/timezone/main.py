#!/usr/bin/env python3
"""Timezone Converter plugin for the Tabame launcher.

Grammar (after the `tz` keyword):
    tz 3 PM                 -> your local 3 PM shown across world zones
    tz 11:30 PM PT          -> Pacific time converted to local (+ world zones)
    tz 9 AM ET to CET       -> convert between two zones
    tz now in Tokyo         -> current time in Tokyo
    tz PT                   -> current time in Pacific Time
    tz noon UTC             -> word times work too (noon / midnight / now)

DST for the generic zones (PT, ET, CET, EET, ...) is computed with built-in
US/EU/AU rules, so no tzdata package is required. Explicit abbreviations
(PST, PDT, EEST, ...) are always their fixed offset.
"""

import json
import re
import subprocess
import sys
from datetime import date, datetime, timedelta, timezone

LOCAL_TZ = datetime.now().astimezone().tzinfo


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


def _zone(name, std, std_lbl, dst=None, dst_lbl=None, rule=None):
    return {
        "name": name,
        "std": std,
        "std_lbl": std_lbl,
        "dst": dst,
        "dst_lbl": dst_lbl,
        "rule": rule,
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

# zones offered when no explicit destination is given
WORLD = [
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


def spec_tz(spec, on_date):
    """Materialize a zone spec into a fixed-offset tzinfo for a given date."""
    if spec["dst"] is not None and _dst_active(spec["rule"], on_date):
        return timezone(timedelta(minutes=spec["dst"]), spec["dst_lbl"])
    return timezone(timedelta(minutes=spec["std"]), spec["std_lbl"])


def resolve_token(token, on_date):
    """Resolve a (normalized, upper-case) token to (tzinfo, display_name, spec).

    Returns None when the token is not a known zone; raises ValueError for an
    IANA-style name that cannot be loaded.
    """
    token = token.strip()
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
        try:
            from zoneinfo import ZoneInfo

            return ZoneInfo(key), key, None
        except Exception:
            raise ValueError(
                f"Couldn't load IANA zone `{token}` — Python's zoneinfo needs the "
                "`tzdata` package on Windows (`pip install tzdata`). "
                "Abbreviations like `PT`, `ET`, `CET` or city names work without it."
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
    destination ("... to CET"), else None.
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

    # Peel a source timezone off the end (1 or 2 words, e.g. "NEW YORK").
    src_tz, src_desc, src_spec = None, "Local", None
    tokens = src_part.split(" ") if src_part else []
    for n in (2, 1):
        if len(tokens) >= n:
            resolved = resolve_token(" ".join(tokens[-n:]), today)
            if resolved is not None:
                src_tz, src_desc, src_spec = resolved
                tokens = tokens[:-n]
                break

    time_text = " ".join(tokens).strip()
    tz = src_tz if src_tz is not None else LOCAL_TZ

    if not time_text:
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
    "- `now in Tokyo`, `noon UTC`, `PT`\n\n"
    "Zones: `PT` `MT` `CT` `ET` `UTC` `UK` `CET` `EET` `IST` `JST` `AEST`…\n"
    "or city names: `Paris`, `Tokyo`, `NYC`, `Bucharest`, `Sydney`."
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
        "preview": {"markdown": preview},
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
        "emptyText": "Type a time, e.g. 3 PM PT",
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
