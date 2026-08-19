#!/usr/bin/env python3
"""Qalculate (qalc) Tabame plugin.

Wraps the qalculate-cli `qalc` binary as a live calculator: math, units,
currency conversion, dates, bases, equations, etc. See
https://qalculate.github.io/manual/qalc.html for the full expression syntax.
"""
import json
import os
import re
import shutil
import subprocess
import sys

# ---------------------------------------------------------------------------
# Protocol plumbing
# ---------------------------------------------------------------------------

def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# qalc engine
# ---------------------------------------------------------------------------

TIME_LIMIT_MS = "4000"   # qalc's own -m abort timeout for a single calculation
PROC_TIMEOUT_S = 6.0     # hard backstop in case the process itself hangs

MAX_HISTORY = 10
DOWNLOAD_URL = "https://qalculate.github.io/downloads.html"

EXAMPLES = [
    ("2 + 2 * (3 - 1)", "Basic arithmetic"),
    ("sqrt(2)", "Functions"),
    ("5 dm3 to L", "Unit conversion"),
    ("20 miles / 2h to km/h", "Compound units"),
    ("100 USD to EUR", "Currency conversion"),
    ("52 to bin", "Number bases"),
    ("today + 30 days", "Dates"),
    ("x^2 - 4 = 0", "Equations"),
]


def _current_windows_path():
    """Read the latest persistent PATH instead of Tabame's inherited snapshot."""
    if sys.platform != "win32":
        return ""

    try:
        import winreg
    except ImportError:
        return ""

    path_parts = []
    locations = (
        (winreg.HKEY_LOCAL_MACHINE,
         r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment"),
        (winreg.HKEY_CURRENT_USER, r"Environment"),
    )
    for hive, key_name in locations:
        try:
            with winreg.OpenKey(hive, key_name) as key:
                value, _ = winreg.QueryValueEx(key, "Path")
        except OSError:
            continue
        if isinstance(value, str) and value:
            path_parts.append(os.path.expandvars(value))
    return os.pathsep.join(path_parts)


def find_qalc():
    """Resolve qalc, including PATH changes made after Tabame was started."""
    found = shutil.which("qalc")
    if found is not None or sys.platform != "win32":
        return found

    current_path = _current_windows_path()
    return shutil.which("qalc", path=current_path) if current_path else None


def refresh_qalc_path():
    global QALC_PATH
    QALC_PATH = find_qalc()
    return QALC_PATH is not None


QALC_PATH = find_qalc()


def run_qalc(args, timeout=PROC_TIMEOUT_S):
    """Run qalc with the given extra args, always as a one-shot (non-interactive)
    call. Returns a CompletedProcess, or None if it couldn't run at all."""
    try:
        return subprocess.run(
            [QALC_PATH, *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            stdin=subprocess.DEVNULL,
        )
    except subprocess.TimeoutExpired:
        return None
    except OSError as e:
        log("qalc exec failed:", e)
        return None


def compute(expr):
    """Evaluate `expr` with qalc. Returns a dict:
    ok, result, full (input = result, as qalc renders it), warnings, errors, aborted
    """
    plain = run_qalc(["-m", TIME_LIMIT_MS, expr])
    if plain is None:
        return {"ok": False, "timeout": True, "result": "", "full": "",
                "warnings": [], "errors": [], "aborted": False}

    warnings, errors, rest = [], [], []
    for line in plain.stdout.splitlines():
        low = line.strip().lower()
        if low.startswith("warning:"):
            warnings.append(line.split(":", 1)[1].strip())
        elif low.startswith("error:"):
            errors.append(line.split(":", 1)[1].strip())
        elif line.strip():
            rest.append(line)
    full = "\n".join(rest).strip()
    aborted = full == "aborted"

    terse = run_qalc(["-t", "-m", TIME_LIMIT_MS, expr])
    result = terse.stdout.strip() if terse else ""

    ok = (not errors) and (not aborted) and result != ""
    return {
        "ok": ok, "timeout": False, "result": result, "full": full,
        "warnings": warnings, "errors": errors, "aborted": aborted,
    }


# ---------------------------------------------------------------------------
# Live hints (function/unit/variable name completion while typing)
# ---------------------------------------------------------------------------

TOKEN_RE = re.compile(r"([A-Za-z_][A-Za-z_0-9]*)$")
HINT_CATEGORIES = (
    ("--list-functions", "function", "code"),
    ("--list-variables", "variable", "tag"),
    ("--list-units", "unit", "label"),
)
HINT_LIMIT = 5


def trailing_token(text):
    """The identifier the user is still in the middle of typing, if any —
    e.g. '5 + sq' -> 'sq', 'sqrt(4)' -> '' (word is already closed off)."""
    m = TOKEN_RE.search(text)
    return m.group(1) if m else ""


def _list_qalc_entries(flag, term):
    r = run_qalc([flag, term], timeout=3.0)
    if r is None:
        return []
    entries = []
    for line in r.stdout.splitlines():
        for piece in re.split(r"\t+", line):
            piece = piece.strip()
            if not piece:
                continue
            low = piece.lower()
            if "please use the info command" in low or low.startswith("for more information") \
                    or "no matching item" in low:
                continue
            entries.append(piece)
    parsed = []
    for e in entries:
        if "(" in e and e.endswith(")"):
            name, _, rest = e.partition("(")
            parsed.append((name.strip(), rest[:-1].strip()))
        else:
            parsed.append((e, ""))
    return parsed


def _alias_rank(aliases, term_low):
    best = None
    for a in aliases:
        al = a.lower()
        if al == term_low:
            r = 0
        elif al.startswith(term_low):
            r = 1
        elif term_low in al:
            r = 2
        else:
            continue
        best = r if best is None else min(best, r)
    return best


def get_hints(token, limit=HINT_LIMIT):
    """Rank matching functions/variables/units for a partially-typed token."""
    if len(token) < 2:
        return []
    term_low = token.lower()
    pool = []
    for flag, kind, icon in HINT_CATEGORIES:
        for name, desc in _list_qalc_entries(flag, term_low):
            aliases = [a.strip() for a in name.split(" / ")]
            rank = _alias_rank(aliases, term_low)
            if rank is not None:
                pool.append((rank, len(aliases[0]), kind, icon, name, desc))
    if not pool:
        return []
    pool.sort(key=lambda x: (x[0], x[1]))
    seen, out = set(), []
    for rank, ln, kind, icon, name, desc in pool:
        if name in seen:
            continue
        seen.add(name)
        out.append({"kind": kind, "icon": icon, "name": name, "desc": desc,
                    "primary": name.split(" / ")[0].strip()})
        if len(out) >= limit:
            break
    return out


def hint_items(token):
    items = []
    for h in get_hints(token):
        items.append({
            "id": f"hint:{h['kind']}:{h['primary']}",
            "title": h["name"],
            "subtitle": h["desc"] or h["kind"].capitalize(),
            "icon": h["icon"],
            "section": "Suggestions",
            "accessories": [{"text": h["kind"]}],
        })
    return items


# ---------------------------------------------------------------------------
# History (persisted via the host storage command)
# ---------------------------------------------------------------------------

history = []            # list of {"expr":..., "result":...}
history_loaded = False
last_query_rev = 0
last_query_text = ""


def push_history(expr, result):
    global history
    history = [h for h in history if h["expr"] != expr]
    history.insert(0, {"expr": expr, "result": result})
    history = history[:MAX_HISTORY]
    send({"type": "command", "command": "storage", "op": "set",
          "key": "history", "value": history})


def history_items():
    return [
        {
            "id": f"hist:{i}",
            "title": h["expr"],
            "subtitle": h["result"],
            "icon": "clock",
            "section": "History",
            "actions": [
                {"id": "copy_result", "title": "Copy result", "icon": "copy"},
                {"id": "copy_expr", "title": "Copy expression", "icon": "content_copy"},
            ],
        }
        for i, h in enumerate(history)
    ]


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

def render_not_installed(rev):
    md = (
        "# qalc not found\n\n"
        "This plugin needs the **Qalculate!** command-line tool (`qalc`) "
        "on your `PATH`, and it isn't there.\n\n"
        "**Install it (pick one):**\n\n"
        "- `winget install -e --id Qalculate.Qalculate`\n"
        "- Chocolatey: `choco install qalculate`\n"
        f"- Or grab the portable zip / installer from [qalculate.github.io/downloads]({DOWNLOAD_URL}) "
        "(the CLI is bundled with the desktop app)\n\n"
        "After installing, make sure the folder containing `qalc.exe` is on your "
        "`PATH`, then reopen the launcher."
    )
    send({
        "type": "render", "rev": rev, "view": "detail",
        "page": {"id": "qalc:missing", "title": "Qalculate", "history": "none"},
        "detail": {"markdown": md},
        "actions": [
            {"id": "open_downloads", "title": "Open download page", "icon": "open"},
            {"id": "recheck", "title": "Check again", "icon": "refresh"},
        ],
    })


def render_home(rev):
    items = history_items()
    for expr, label in EXAMPLES:
        items.append({
            "id": f"ex:{expr}",
            "title": expr,
            "subtitle": label,
            "icon": "calculator",
            "section": "Try it",
        })

    frame_actions = [
        {"id": "refresh_rates", "title": "Update exchange rates", "icon": "sync"},
    ]
    if history:
        frame_actions.append({
            "id": "clear_history", "title": "Clear history", "icon": "trash",
            "destructive": True,
            "confirm": {"title": "Clear calculation history?",
                        "message": "This can't be undone.", "confirmLabel": "Clear"},
        })

    send({
        "type": "render", "rev": rev, "view": "list",
        "page": {"id": "qalc:home", "title": "Qalculate", "history": "none"},
        "placeholder": "Type an expression… e.g. 20 miles / 2h to km/h",
        "empty": {"icon": "calculator", "title": "Type a calculation",
                  "hint": "Math, units, currency, dates, bases…"},
        "items": items,
        "actions": frame_actions,
    })


def render_result(rev, expr, calc, hints):
    if calc.get("timeout"):
        send({
            "type": "render", "rev": rev, "view": "list",
            "placeholder": "Type an expression…",
            "items": [{
                "id": "err", "title": "qalc didn't respond",
                "subtitle": "The calculator process timed out. Try again.",
                "icon": "warning",
            }] + hints,
        })
        return

    if calc["aborted"]:
        send({
            "type": "render", "rev": rev, "view": "list",
            "placeholder": "Type an expression…",
            "items": [{
                "id": "aborted", "title": "Took too long — aborted",
                "subtitle": expr, "icon": "clock",
            }] + hints,
        })
        return

    if not calc["ok"]:
        msg = "; ".join(calc["errors"]) if calc["errors"] else "Couldn't evaluate that"
        item = {
            "id": "error", "title": msg, "subtitle": expr, "icon": "error",
            "actions": [
                {"id": "copy_error", "title": "Copy error message", "icon": "copy"},
            ],
        }
        if calc["warnings"]:
            item["preview"] = {"markdown": "**Warnings:**\n\n" + "\n".join(
                f"- {w}" for w in calc["warnings"])}
        send({
            "type": "render", "rev": rev, "view": "list",
            "placeholder": "Type an expression…",
            "preview": {"enabled": bool(calc["warnings"]) and not hints, "wide": False},
            "items": [item] + hints,
        })
        return

    subtitle = calc["full"] if calc["full"] and calc["full"] != calc["result"] else expr
    accessories = []
    if calc["warnings"]:
        accessories.append({"text": "warning", "icon": "warning", "color": "#F5A623"})

    item = {
        "id": "result",
        "title": calc["result"],
        "subtitle": subtitle,
        "icon": "calculator",
        "accessories": accessories,
        "actions": [
            {"id": "copy_only", "title": "Copy (keep open)", "icon": "copy"},
            {"id": "paste", "title": "Paste into active app", "icon": "paste"},
            {"id": "copy_full", "title": "Copy full expression", "icon": "content_copy"},
        ],
    }
    if calc["warnings"]:
        item["preview"] = {"markdown": "**Warnings:**\n\n" + "\n".join(
            f"- {w}" for w in calc["warnings"])}

    send({
        "type": "render", "rev": rev, "view": "list",
        "placeholder": "Type an expression…",
        "preview": {"enabled": bool(calc["warnings"]) and not hints, "wide": False},
        "selectId": "result",
        "items": [item] + history_items() + hints,
    })


def render(rev, text):
    global last_query_rev, last_query_text
    last_query_rev, last_query_text = rev, text

    if QALC_PATH is None and not refresh_qalc_path():
        render_not_installed(rev)
        return

    expr = text.strip()
    if not expr:
        render_home(rev)
        return

    token = trailing_token(text)
    hints = hint_items(token) if token else []
    calc = compute(expr)
    render_result(rev, expr, calc, hints)


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

def handle_action(item_id, action, ids, parameters):
    if item_id == "" and action == "recheck":
        if refresh_qalc_path():
            if not history_loaded:
                send({"type": "command", "command": "storage", "op": "get",
                      "key": "history", "requestId": "hist-load"})
            render(0, last_query_text)
        else:
            render_not_installed(0)
        return

    if item_id == "" and action == "open_downloads":
        send({"type": "command", "command": "open", "url": DOWNLOAD_URL})
        return

    if item_id == "" and action == "refresh_rates":
        send({"type": "command", "command": "toast", "text": "Updating exchange rates…",
              "style": "progress"})
        r = run_qalc(["-e"], timeout=15.0)
        ok = r is not None and r.returncode == 0
        send({"type": "command", "command": "toast",
              "text": "Exchange rates updated" if ok else "Couldn't update exchange rates",
              "style": "success" if ok else "error"})
        return

    if item_id == "" and action == "clear_history":
        global history
        history = []
        send({"type": "command", "command": "storage", "op": "delete", "key": "history"})
        render_home(0)
        return

    if item_id.startswith("hist:"):
        idx = int(item_id.split(":", 1)[1])
        h = history[idx] if 0 <= idx < len(history) else None
        if not h:
            return
        if action in ("default",):
            send({"type": "command", "command": "setQuery", "text": h["expr"]})
        elif action == "copy_result":
            send({"type": "command", "command": "copy", "text": h["result"]})
        elif action == "copy_expr":
            send({"type": "command", "command": "copy", "text": h["expr"]})
        return

    if item_id.startswith("ex:"):
        expr = item_id.split(":", 1)[1]
        send({"type": "command", "command": "setQuery", "text": expr})
        return

    if item_id.startswith("hint:"):
        _, kind, primary = item_id.split(":", 2)
        token = trailing_token(last_query_text)
        insert = primary + "(" if kind == "function" else primary
        base = last_query_text[: len(last_query_text) - len(token)] if token else last_query_text
        send({"type": "command", "command": "setQuery", "text": base + insert})
        return

    if item_id == "result":
        expr = last_query_text.strip()
        calc = compute(expr) if expr else None
        result = calc["result"] if calc and calc["ok"] else ""
        full = (calc["full"] if calc and calc["full"] else expr + " = " + result)
        if action == "default":
            if not result:
                return
            push_history(expr, result)
            send({"type": "command", "command": "copy", "text": result})
            send({"type": "command", "command": "setQuery", "text": " "})
        elif action == "copy_only":
            send({"type": "command", "command": "copy", "text": result})
        elif action == "paste":
            send({"type": "command", "command": "paste", "text": result})
        elif action == "copy_full":
            send({"type": "command", "command": "copy", "text": full})
        return

    if item_id in ("error", "aborted") and action == "copy_error":
        expr = last_query_text.strip()
        calc = compute(expr) if expr else None
        msg = "; ".join(calc["errors"]) if calc and calc["errors"] else ""
        send({"type": "command", "command": "copy", "text": msg})
        return


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

def main():
    global history, history_loaded

    if QALC_PATH is not None:
        send({"type": "command", "command": "storage", "op": "get",
              "key": "history", "requestId": "hist-load"})

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
            render(msg.get("rev", 0), msg.get("text", msg.get("query", "")))
        elif t == "action":
            handle_action(msg.get("id", ""), msg.get("action", "default"),
                          msg.get("ids"), msg.get("parameters"))
        elif t == "storage":
            if msg.get("requestId") == "hist-load":
                val = msg.get("value")
                if isinstance(val, list):
                    history = val[:MAX_HISTORY]
                history_loaded = True
                render(0, last_query_text)
        # select/tab/back/etc.: no special handling needed for a single-page calculator

if __name__ == "__main__":
    main()
