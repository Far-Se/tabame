#!/usr/bin/env python3
import json
import re
import sys
from datetime import datetime

from croniter import croniter


def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# ── Cron parsing & validation ───────────────────────────────────────────────

CRON_FIELD_NAMES = ["minute", "hour", "day of month", "month", "day of week"]
CRON_ALIASES = {
    "@yearly": "0 0 1 1 *",
    "@annually": "0 0 1 1 *",
    "@monthly": "0 0 1 * *",
    "@weekly": "0 0 * * 0",
    "@daily": "0 0 * * *",
    "@midnight": "0 0 * * *",
    "@hourly": "0 * * * *",
}

MONTH_ALIASES = {
    "jan": 1,
    "feb": 2,
    "mar": 3,
    "apr": 4,
    "may": 5,
    "jun": 6,
    "jul": 7,
    "aug": 8,
    "sep": 9,
    "oct": 10,
    "nov": 11,
    "dec": 12,
}
DOW_ALIASES = {
    "sun": 0,
    "mon": 1,
    "tue": 2,
    "wed": 3,
    "thu": 4,
    "fri": 5,
    "sat": 6,
}


def expand_alias(expr: str) -> str:
    expr = expr.strip().lower()
    return CRON_ALIASES.get(expr, expr)


def validate_cron(expr: str) -> tuple[bool, str | None]:
    """Returns (is_valid, error_message)."""
    expr = expand_alias(expr)
    parts = expr.split()
    if len(parts) != 5:
        return False, f"Expected 5 fields, got {len(parts)}"

    for i, part in enumerate(parts):
        # Check for invalid characters
        if not re.match(r"^[\d,\-*/?LW#]+$", part, re.IGNORECASE):
            return False, f"Invalid characters in {CRON_FIELD_NAMES[i]}: '{part}'"

    try:
        croniter(expr)
    except Exception as e:
        return False, str(e)

    return True, None


def describe_field(part: str, name: str) -> str:
    """Human-readable description of a single cron field."""
    part = part.strip().lower()

    if part == "*":
        return "every " + name
    if part == "?":
        return "no specific " + name
    if re.match(r"^\*/\d+$", part):
        step = part.split("/")[1]
        return f"every {step} {name}s"
    if "/" in part:
        base, step = part.split("/")
        if base == "*":
            return f"every {step} {name}s"
        return f"every {step} {name}s starting at {base}"
    if "-" in part and "," not in part:
        start, end = part.split("-")
        return f"{name} {start} through {end}"
    if "," in part:
        items = part.split(",")
        return f"{name}s {', '.join(items)}"

    # Special cases
    if name == "day of week" and part in DOW_ALIASES:
        return part.capitalize()
    if name == "month" and part in MONTH_ALIASES:
        return part.capitalize()

    return f"{name} {part}"


def describe_cron(expr: str) -> str:
    """Generate a human-readable description of a cron expression."""
    expr = expand_alias(expr)
    parts = expr.split()

    # Special aliases
    for alias, value in CRON_ALIASES.items():
        if expr == value:
            return f"Runs {alias.replace('@', '')} ({value})"

    descriptions = []
    for part, name in zip(parts, CRON_FIELD_NAMES):
        descriptions.append(describe_field(part, name))

    # Build a more natural sentence
    minute, hour, dom, month, dow = parts

    # Common patterns
    if minute == "0" and hour == "0" and dom == "1" and month == "*" and dow == "*":
        return "At midnight on the 1st of every month"
    if minute == "0" and hour == "0" and dom == "*" and month == "*" and dow == "0":
        return "At midnight every Sunday"
    if minute == "0" and hour == "0" and dom == "*" and month == "*" and dow == "*":
        return "At midnight every day"
    if minute == "0" and hour == "*" and dom == "*" and month == "*" and dow == "*":
        return "At the start of every hour"

    # Build from components
    time_parts = []
    if minute != "*":
        time_parts.append(f":{minute.zfill(2)}")
    if hour != "*":
        time_parts.insert(0, f"at {hour}")
    elif minute != "*":
        time_parts.insert(0, "at *")

    date_parts = []
    if dom != "*" and dom != "?":
        date_parts.append(f"on day {dom}")
    if month != "*":
        date_parts.append(f"in {describe_field(month, 'month').replace('month ', '')}")
    if dow != "*" and dow != "?":
        date_parts.append(f"on {describe_field(dow, 'day of week')}")

    result = " ".join(
        filter(
            None,
            [
                " ".join(time_parts) if time_parts else "",
                " ".join(date_parts) if date_parts else "every day",
            ],
        )
    ).strip()

    if not result:
        return "Runs: " + " | ".join(descriptions)

    # Clean up
    result = result.replace("at * :", "at *:")
    return result.capitalize()


def get_next_runs(expr: str, count: int = 5) -> list[str]:
    """Get the next N run times for a cron expression."""
    expr = expand_alias(expr)
    itr = croniter(expr, datetime.now())
    runs = []
    for _ in range(count):
        dt = itr.get_next(datetime)
        # Format: "Today, 14:30" or "Fri, Jul 25, 09:00"
        now = datetime.now()
        if dt.date() == now.date():
            date_str = "Today"
        elif (dt.date() - now.date()).days == 1:
            date_str = "Tomorrow"
        else:
            date_str = dt.strftime("%a, %b %d")
        runs.append(f"{date_str} at {dt.strftime('%H:%M')}")
    return runs


# ── Natural language to cron ─────────────────────────────────────────────────

NL_PATTERNS = [
    # Every N units
    (r"every\s+(\d+)\s+(min|minute|minutes)", lambda m: f"*/{m.group(1)} * * * *"),
    (r"every\s+(\d+)\s+(hour|hours)", lambda m: f"0 */{m.group(1)} * * *"),
    (r"every\s+(\d+)\s+(day|days)", lambda m: f"0 0 */{m.group(1)} * *"),
    # Every unit
    (r"every\s+(min|minute)", lambda m: "* * * * *"),
    (r"every\s+(hour|hr)", lambda m: "0 * * * *"),
    (r"every\s+(day|daily|night|midnight)", lambda m: "0 0 * * *"),
    (r"every\s+(week|weekly|sunday|sun)", lambda m: "0 0 * * 0"),
    (r"every\s+(mon|monday)", lambda m: "0 0 * * 1"),
    (r"every\s+(tue|tuesday)", lambda m: "0 0 * * 2"),
    (r"every\s+(wed|wednesday)", lambda m: "0 0 * * 3"),
    (r"every\s+(thu|thursday)", lambda m: "0 0 * * 4"),
    (r"every\s+(fri|friday)", lambda m: "0 0 * * 5"),
    (r"every\s+(sat|saturday)", lambda m: "0 0 * * 6"),
    (r"every\s+month", lambda m: "0 0 1 * *"),
    (r"every\s+year", lambda m: "0 0 1 1 *"),
    # At specific times
    (r"at\s+(\d{1,2}):(\d{2})\s*(am|pm)?", lambda m: parse_at_time(m)),
    (
        r"at\s+(noon|midnight)",
        lambda m: "0 12 * * *" if m.group(1) == "noon" else "0 0 * * *",
    ),
    # On specific days
    (r"on\s+(mon|monday)s?", lambda m: "0 0 * * 1"),
    (r"on\s+(tue|tuesday)s?", lambda m: "0 0 * * 2"),
    (r"on\s+(wed|wednesday)s?", lambda m: "0 0 * * 3"),
    (r"on\s+(thu|thursday)s?", lambda m: "0 0 * * 4"),
    (r"on\s+(fri|friday)s?", lambda m: "0 0 * * 5"),
    (r"on\s+(sat|saturday)s?", lambda m: "0 0 * * 6"),
    (r"on\s+(sun|sunday)s?", lambda m: "0 0 * * 0"),
]


def parse_at_time(m):
    hour = int(m.group(1))
    minute = int(m.group(2))
    ampm = m.group(3)
    if ampm:
        if ampm.lower() == "pm" and hour != 12:
            hour += 12
        elif ampm.lower() == "am" and hour == 12:
            hour = 0
    return f"{minute} {hour} * * *"


def nl_to_cron(text: str) -> str | None:
    """Convert natural language to cron expression."""
    text = text.lower().strip()
    for pattern, fn in NL_PATTERNS:
        m = re.match(pattern, text)
        if m:
            return fn(m)
    return None


# ── Render functions ────────────────────────────────────────────────────────


def render_root(rev: int, text: str):
    """Show the main cron interface."""
    text = text.strip()

    if not text:
        # Empty state: show examples and help
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "list",
                "placeholder": "Enter a cron expression or natural language...",
                "empty": {
                    "icon": "clock",
                    "title": "Cron Parser & Generator",
                    "hint": "Type a cron expression (e.g. '0 9 * * 1-5') or natural language (e.g. 'every day at 9am', 'every Monday')",
                },
                "items": [
                    {
                        "id": "example-1",
                        "title": "Every weekday at 9 AM",
                        "subtitle": "0 9 * * 1-5",
                        "icon": "clock",
                        "actions": [
                            {"id": "use", "title": "Use this", "icon": "check"}
                        ],
                    },
                    {
                        "id": "example-2",
                        "title": "Every 15 minutes",
                        "subtitle": "*/15 * * * *",
                        "icon": "clock",
                        "actions": [
                            {"id": "use", "title": "Use this", "icon": "check"}
                        ],
                    },
                    {
                        "id": "example-3",
                        "title": "First day of every month at midnight",
                        "subtitle": "0 0 1 * *",
                        "icon": "clock",
                        "actions": [
                            {"id": "use", "title": "Use this", "icon": "check"}
                        ],
                    },
                    {
                        "id": "example-4",
                        "title": "Every Sunday at 2:30 PM",
                        "subtitle": "30 14 * * 0",
                        "icon": "clock",
                        "actions": [
                            {"id": "use", "title": "Use this", "icon": "check"}
                        ],
                    },
                ],
            }
        )
        return

    # Check if it's a natural language query
    nl_result = nl_to_cron(text)
    if nl_result and not looks_like_cron(text):
        # Show the generated cron
        valid, err = validate_cron(nl_result)
        if valid:
            runs = get_next_runs(nl_result, 5)
            send(
                {
                    "type": "render",
                    "rev": rev,
                    "view": "list",
                    "items": [
                        {
                            "id": "generated-cron",
                            "title": nl_result,
                            "subtitle": f"Generated from: {text}",
                            "icon": "check",
                            "accessories": [{"text": "Generated", "color": "#22C55E"}],
                            "actions": [
                                {
                                    "id": "copy",
                                    "title": "Copy expression",
                                    "icon": "copy",
                                },
                                {
                                    "id": "detail",
                                    "title": "View details",
                                    "icon": "info",
                                },
                            ],
                            "preview": {
                                "markdown": f"## Generated Cron Expression\n\n```\n{nl_result}\n```\n\n**From:** {text}\n\n### Next 5 runs\n\n"
                                + "\n".join(f"- {r}" for r in runs),
                            },
                        }
                    ],
                }
            )
            return
        else:
            send(
                {
                    "type": "render",
                    "rev": rev,
                    "view": "list",
                    "emptyText": f"Could not parse: {err}",
                    "items": [],
                }
            )
            return

    # Treat as cron expression
    expr = expand_alias(text)
    valid, err = validate_cron(expr)

    if not valid:
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "detail",
                "detail": {
                    "markdown": f"## Invalid Cron Expression\n\n```\n{text}\n```\n\n**Error:** {err}\n\n### Valid formats\n\n- Standard 5-field cron: `min hour dom month dow`\n- Special aliases: `@yearly`, `@monthly`, `@weekly`, `@daily`, `@hourly`\n\n### Field ranges\n\n| Field | Range | Special chars |\n|-------|-------|---------------|\n| Minute | 0-59 | `*` `,` `-` `/` |\n| Hour | 0-23 | `*` `,` `-` `/` |\n| Day of month | 1-31 | `*` `,` `-` `/` `L` `W` |\n| Month | 1-12 | `*` `,` `-` `/` |\n| Day of week | 0-6 (0=Sun) | `*` `,` `-` `/` `L` `#` |\n",
                },
            }
        )
        return

    # Valid cron — show details
    description = describe_cron(expr)
    runs = get_next_runs(expr, 8)

    items = [
        {
            "id": "expr",
            "title": expr,
            "subtitle": description,
            "icon": "clock",
            "accessories": [{"text": "Valid", "color": "#22C55E"}],
            "actions": [
                {"id": "copy", "title": "Copy expression", "icon": "copy"},
                {"id": "copy-desc", "title": "Copy description", "icon": "copy"},
            ],
        },
    ]

    # Add next runs as items
    for i, run in enumerate(runs):
        items.append(
            {
                "id": f"run-{i}",
                "title": run,
                "subtitle": f"Run {i + 1}",
                "icon": "calendar",
                "section": "Next Runs",
            }
        )

    # Add field breakdown
    parts = expr.split()
    field_details = []
    for part, name in zip(parts, CRON_FIELD_NAMES):
        field_details.append(f"- **{name}:** `{part}` — {describe_field(part, name)}")

    preview_md = f"""## Cron Expression
{expr}

### Description
{description}

### Field Breakdown
{chr(10).join(field_details)}

### Next 8 Runs
{chr(10).join(f"- {r}" for r in runs)}
"""

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "preview": {"enabled": True},
            "items": items,
        }
    )


def looks_like_cron(text: str) -> bool:
    """Heuristic: does this look like a cron expression vs natural language?"""
    text = text.strip().lower()
    # Starts with @alias
    if text.startswith("@"):
        return True
    # Has 5 space-separated parts with cron-like chars
    parts = text.split()
    if len(parts) == 5:
        cron_chars = set("0123456789,*-/?LW#")
        if all(set(p).issubset(cron_chars) for p in parts):
            return True
    return False


def render_detail(rev: int, expr: str):
    """Show full detail view for a cron expression."""
    expr = expand_alias(expr)
    description = describe_cron(expr)
    runs = get_next_runs(expr, 10)
    parts = expr.split()

    field_details = []
    for part, name in zip(parts, CRON_FIELD_NAMES):
        field_details.append(f"- **{name}:** `{part}` — {describe_field(part, name)}")

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "canGoBack": True,
            "detail": {
                "markdown": f"""# Cron: `{expr}`

{description}

## Field Breakdown
{chr(10).join(field_details)}

## Next 10 Runs
{chr(10).join(f"- **{i + 1}.** {r}" for i, r in enumerate(runs))}

## Quick Reference

| Alias | Expression | Meaning |
|-------|-----------|---------|
| `@yearly` | `0 0 1 1 *` | Once a year |
| `@monthly` | `0 0 1 * *` | Once a month |
| `@weekly` | `0 0 * * 0` | Once a week |
| `@daily` | `0 0 * * *` | Once a day |
| `@hourly` | `0 * * * *` | Once an hour |
""",
                "metadata": [
                    {"label": "Expression", "text": expr, "icon": "clock"},
                    {"label": "Description", "text": description},
                    {
                        "label": "Next run",
                        "text": runs[0] if runs else "—",
                        "color": "#22C55E",
                    },
                ],
            },
            "actions": [
                {"id": "copy", "title": "Copy expression", "icon": "copy"},
                {"id": "copy-desc", "title": "Copy description", "icon": "copy"},
            ],
        }
    )


# ── Main loop ───────────────────────────────────────────────────────────────


def handle_action(item_id: str, action: str, text: str):
    if action == "copy" and item_id == "expr":
        send({"type": "command", "command": "copy", "text": text.strip()})
        send({"type": "command", "command": "hide"})
    elif action == "copy" and item_id == "generated-cron":
        # Extract the cron from the text (first line/trimmed)
        cron = text.strip().split()[0] if text.strip() else ""
        send({"type": "command", "command": "copy", "text": cron})
        send({"type": "command", "command": "hide"})
    elif action == "copy-desc":
        expr = expand_alias(text.strip())
        send({"type": "command", "command": "copy", "text": describe_cron(expr)})
        send({"type": "command", "command": "hide"})
    elif action == "detail":
        render_detail(0, text.strip())
    elif action == "use" and item_id.startswith("example-"):
        examples = {
            "example-1": "0 9 * * 1-5",
            "example-2": "*/15 * * * *",
            "example-3": "0 0 1 * *",
            "example-4": "30 14 * * 0",
        }
        if item_id in examples:
            send({"type": "command", "command": "setQuery", "text": examples[item_id]})
    elif action == "default":
        # Enter on a run item does nothing special; on the main item copies
        if item_id == "expr":
            handle_action(item_id, "copy", text)
        elif item_id == "generated-cron":
            handle_action(item_id, "copy", text)
        elif item_id.startswith("example-"):
            handle_action(item_id, "use", text)


def main():
    current_text = ""
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
            current_text = msg.get("query", "")
            render_root(msg.get("rev", 0), current_text)
        elif t == "query":
            current_text = msg.get("text", "")
            render_root(msg.get("rev", 0), current_text)
        elif t == "action":
            handle_action(msg.get("id", ""), msg.get("action", "default"), current_text)
        elif t == "back":
            render_root(0, current_text)


if __name__ == "__main__":
    main()
