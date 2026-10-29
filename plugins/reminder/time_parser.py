"""Small, deterministic time grammar; all clock times are local Windows time."""

from dataclasses import dataclass
from datetime import datetime, timedelta
import math
import re


MONTHS = {
    name: index
    for index, names in enumerate((
        ("jan", "january"), ("feb", "february"), ("mar", "march"),
        ("apr", "april"), ("may",), ("jun", "june"), ("jul", "july"),
        ("aug", "august"), ("sep", "sept", "september"),
        ("oct", "october"), ("nov", "november"), ("dec", "december"),
    ), 1)
    for name in names
}
CLOCK = re.compile(
    r"(?:(\d{1,2})(?::(\d{2}))?\s*(am|pm)|(\d{1,2}):(\d{2}))(?=\s|$)",
    re.IGNORECASE,
)
DURATION = re.compile(r"(?:\d+\s*[dhms]\s*)+", re.IGNORECASE)


@dataclass(frozen=True)
class Preview:
    due: float
    message: str
    expression: str


def clock_prefix(text):
    match = CLOCK.match(text)
    if not match:
        raise ValueError("Finish the time: try 8pm, 8:30pm, or 20:30.")
    hour, minute, meridiem, hour24, minute24 = match.groups()
    if meridiem:
        hour, minute = int(hour), int(minute or 0)
        if not 1 <= hour <= 12:
            raise ValueError("AM/PM hours must be between 1 and 12.")
        hour = hour % 12 + (12 if meridiem.lower() == "pm" else 0)
    else:
        hour, minute = int(hour24), int(minute24)
    if hour > 23 or minute > 59:
        raise ValueError("Use hours 0–23 and minutes 00–59.")
    return hour, minute, match.end()


def parse(text, now=None):
    """Parse the longest supported leading time, leaving the message untouched."""
    now = now or datetime.now()
    text = text.strip()
    duration = DURATION.match(text)
    if duration and (duration.end() == len(text) or text[duration.end() - 1].isspace()):
        parts = re.findall(r"(\d+)\s*([dhms])", duration.group(), re.IGNORECASE)
        units = [unit.lower() for _, unit in parts]
        if len(set(units)) != len(units):
            raise ValueError("Use each duration unit once, for example 8h5m.")
        seconds = sum(int(value) * {"d": 86400, "h": 3600, "m": 60, "s": 1}[unit.lower()]
                      for value, unit in parts)
        if not 0 < seconds <= 366 * 10 * 86400:
            raise ValueError("Use a duration greater than zero and no longer than 10 years.")
        end = duration.end()
        # Task Scheduler boundaries use whole seconds. Round upward so its
        # helper never mistakes a truncated trigger for an early logon check.
        return Preview(math.ceil(now.timestamp() + seconds), text[end:].strip(), text[:end].strip())

    tomorrow = re.match(r"tomorrow(?:\s+|$)", text, re.IGNORECASE)
    date = re.match(r"(\d{1,2})\s+([a-z]+)(?:\s+(\d{4}))?(?:\s+|$)", text, re.IGNORECASE)
    if date and date.group(2).lower() in ("am", "pm"):
        date = None
    if tomorrow:
        hour, minute, end = clock_prefix(text[tomorrow.end():])
        due = (now + timedelta(days=1)).replace(hour=hour, minute=minute, second=0, microsecond=0)
        end += tomorrow.end()
    elif date:
        day, month_name, year = date.groups()
        month = MONTHS.get(month_name.lower())
        if not month:
            raise ValueError("Finish the month, for example 2 Nov 12:40.")
        hour, minute, end = clock_prefix(text[date.end():])
        end += date.end()
        # A leap-year template rejects impossible dates while allowing Feb 29.
        try:
            datetime(2000, month, int(day))
        except ValueError:
            raise ValueError("That day does not exist in this month.") from None
        due = None
        for candidate_year in ([int(year)] if year else range(now.year, min(now.year + 9, 10000))):
            try:
                candidate = datetime(candidate_year, month, int(day), hour, minute)
            except ValueError:
                continue
            if candidate > now:
                due = candidate
                break
        if due is None:
            raise ValueError("Choose a valid date and time in the future.")
    else:
        hour, minute, end = clock_prefix(text)
        due = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
        if due <= now:
            due += timedelta(days=1)

    timestamp = due.timestamp()
    if datetime.fromtimestamp(timestamp) != due:
        raise ValueError("That local time is skipped by daylight saving time. Choose another time.")
    return Preview(timestamp, text[end:].strip(), text[:end].strip())
