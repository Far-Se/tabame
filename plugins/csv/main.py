import csv
import io
import json
import sys
from collections import Counter


def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def get_stats(headers, rows):
    if not rows:
        return "### No Data\n\nNo rows matched the filter."
    md = "### Column Statistics\n\n"
    for h in headers:
        vals = [str(r.get(h, "")).strip() for r in rows if str(r.get(h, "")).strip()]
        md += f"**{h}** ({len(vals)} non-empty)\n"
        if not vals:
            md += "- _Empty_\n\n"
            continue
        is_numeric = True
        nums = []
        for v in vals:
            try:
                nums.append(float(v.replace(",", "")))
            except ValueError:
                is_numeric = False
                break
        if is_numeric and nums:
            md += f"- Min: `{min(nums)}`\n"
            md += f"- Max: `{max(nums)}`\n"
            md += f"- Avg: `{sum(nums) / len(nums):.2f}`\n\n"
        else:
            counts = Counter(vals)
            top = counts.most_common(3)
            md += "- Top: " + ", ".join(f"`{v}` ({c})" for v, c in top) + "\n\n"
    return md


def get_row_md(headers, row):
    md = "### Selected Row\n\n"
    for h in headers:
        md += f"- **{h}**: `{row.get(h, '')}`\n"
    return md


# ── state ──────────────────────────────────────────────────────────
headers = []
rows = []
cur_filter = ""
loaded = False


def form_screen(error=None):
    field = {
        "id": "csv_data",
        "type": "textarea",
        "label": "CSV Data",
        "placeholder": "Paste your CSV here…\n\nComma, tab, semicolon, or pipe delimiters.\nFirst row must be headers.",
        "required": True,
        "description": "Include a header row so columns are named.",
    }
    if error:
        field["error"] = error
    return {
        "type": "render",
        "rev": 0,
        "view": "form",
        "form": {
            "title": "Paste CSV",
            "submitLabel": "Analyze",
            "fields": [field],
        },
    }


def filtered():
    if not cur_filter:
        return rows
    q = cur_filter.lower()
    return [r for r in rows if any(q in str(v).lower() for v in r.values())]


def list_screen(query, rev):
    global cur_filter
    cur_filter = query
    fres = filtered()
    stats = get_stats(headers, fres)
    items = []
    for i, row in enumerate(fres[:100]):
        t = str(row.get(headers[0], "")).strip() or "(empty)"
        s_parts = [str(row.get(h, "")).strip() for h in headers[1:4]]
        s = " · ".join(p for p in s_parts if p)
        if len(t) > 60:
            t = t[:57] + "…"
        if len(s) > 90:
            s = s[:87] + "…"
        items.append(
            {
                "id": str(i),
                "title": t,
                "subtitle": s,
                "icon": "table",
                "preview": {"markdown": f"{get_row_md(headers, row)}\n---\n{stats}"},
                "actions": [
                    {"id": "copy_row", "title": "Copy Row", "icon": "copy"},
                ],
            }
        )
    frame = {
        "type": "render",
        "rev": rev,
        "view": "list",
        "placeholder": "Filter rows…",
        "preview": {"enabled": True},
        "items": items,
        "canGoBack": True,
        "actions": [
            {"id": "copy_all", "title": "Copy Filtered CSV", "icon": "copy"},
            {"id": "new", "title": "Paste New CSV", "icon": "refresh"},
        ],
    }
    if not fres:
        frame["empty"] = {
            "icon": "filter",
            "title": "No matches",
            "hint": "Try a different search term",
        }
    return frame


# ── main loop ──────────────────────────────────────────────────────
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    msg = json.loads(line)

    if msg["type"] == "close":
        break

    if msg["type"] == "init":
        loaded = False
        headers, rows, cur_filter = [], [], ""
        send(form_screen())

    elif msg["type"] == "submit":
        text = msg.get("values", {}).get("csv_data", "").strip()
        if not text:
            send(form_screen())
            continue
        # parse
        parsed_rows = None
        err = None
        try:
            dialect = csv.Sniffer().sniff(text[:2048], delimiters=",\t;|")
            reader = csv.DictReader(io.StringIO(text), dialect=dialect)
            parsed_rows = list(reader)
            if not reader.fieldnames:
                err = "No header row found."
        except Exception as e:
            err = str(e)
        if err:
            send(form_screen(error=f"Parse error: {err}"))
            continue
        headers = reader.fieldnames or []
        rows = parsed_rows
        cur_filter = ""
        loaded = True
        send(list_screen("", 0))

    elif msg["type"] == "query":
        if loaded:
            send(list_screen(msg.get("text", ""), msg.get("rev", 0)))
        else:
            send(form_screen())

    elif msg["type"] == "back":
        loaded = False
        headers, rows, cur_filter = [], [], ""
        send(form_screen())

    elif msg["type"] == "action":
        aid = msg.get("action")
        iid = msg.get("id")

        if aid == "new":
            loaded = False
            headers, rows, cur_filter = [], [], ""
            send(form_screen())

        elif aid == "copy_all" and loaded:
            fres = filtered()
            buf = io.StringIO()
            w = csv.DictWriter(buf, fieldnames=headers, extrasaction="ignore")
            w.writeheader()
            w.writerows(fres)
            send({"type": "command", "command": "copy", "text": buf.getvalue().strip()})
            send(
                {
                    "type": "command",
                    "command": "toast",
                    "text": f"Copied {len(fres)} rows",
                }
            )

        elif aid in ("copy_row", "default") and iid:
            try:
                row = filtered()[int(iid)]
                csv_line = ",".join(str(row.get(h, "")) for h in headers)
                send({"type": "command", "command": "copy", "text": csv_line})
                send({"type": "command", "command": "hide"})
            except (ValueError, IndexError):
                pass
