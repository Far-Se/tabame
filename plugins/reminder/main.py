"""Launcher pages: history/help, live time preview, and reminder detail."""

from datetime import datetime
import json
import os
import queue
import sys
import threading
import time

import scheduler
from time_parser import parse


EXAMPLES = [
    "8pm go to gym", "8:30pm water the flowers", "20:30 strech",
    "8h5m pick kids", "tomorrow 10AM schedule the meeting", "2 Nov 12:40 anniversary",
]


def send(frame):
    print(json.dumps(frame, ensure_ascii=True), flush=True)


def command(name, **fields):
    send({"type": "command", "command": name, **fields})


def when(timestamp):
    return datetime.fromtimestamp(timestamp).astimezone().strftime("%a, %d %b %Y · %H:%M:%S %Z")


def countdown(timestamp):
    seconds = int(timestamp - time.time())
    if seconds <= 0:
        return "Due now"
    days, seconds = divmod(seconds, 86400)
    hours, seconds = divmod(seconds, 3600)
    minutes, seconds = divmod(seconds, 60)
    return "In " + " ".join(f"{value}{unit}" for value, unit in
                            ((days, "d"), (hours, "h"), (minutes, "m"), (seconds, "s")) if value)


class Plugin:
    def __init__(self):
        self.query = ""
        self.preview = None
        self.problem = ""
        self.selected = None
        self.rev = 0
        self.visible_ids = set()

    def render(self, rev=0):
        frame = {
            "type": "render", "rev": rev, "view": "list",
            "page": {"id": "reminders", "title": "Reminders", "history": "none"},
            "placeholder": "8pm go wash clothes · Enter to set reminder",
            "actions": [{"id": "refresh", "title": "Refresh", "icon": "refresh"}],
        }
        if self.selected:
            row = next((r for r in scheduler.reminders() if r["id"] == self.selected), None)
            if row:
                frame.update(view="detail", canGoBack=True, detail={
                    "markdown": row["message"],
                    "metadata": [
                        {"label": "Scheduled for", "value": when(row["due"])},
                        {"label": "Status", "value": row["status"].capitalize()},
                        *([{"label": "Error", "value": row["error"]}] if row["error"] else []),
                    ],
                }, actions=[{"id": "back", "title": "Back to reminders", "icon": "reply"}, *self.actions(row)])
                send(frame)
                return
            self.selected = None
        if self.query:
            if self.preview:
                ready = bool(self.preview.message) and self.preview.due > time.time() and os.name == "nt"
                frame["items"] = [{
                    "id": "create", "title": self.preview.message or "Add a message after the time",
                    "subtitle": when(self.preview.due), "icon": "bell", "lines": 2,
                    "accessories": [countdown(self.preview.due)],
                    "actions": [{"id": "create", "title": "Set reminder", "icon": "add"}] if ready else [],
                }, {"id": "hint", "title": "Press Enter to set this reminder" if ready else
                    ("Scheduling requires Windows" if os.name != "nt" else "Type a message and a future time"),
                    "subtitle": "Clock times use your local timezone. Nothing is saved until you press Enter.", "icon": "info"}]
            else:
                frame["items"] = [{"id": "hint", "title": self.problem, "subtitle": "Keep typing to preview the trigger time.", "icon": "clock"}, *self.examples()]
        else:
            rows = scheduler.reminders()
            frame["items"] = [{
                "id": row["id"], "title": row["message"], "icon": "bell" if row["status"] == "active" else "clock",
                "subtitle": when(row["due"]) + (" · " + row["error"] if row["error"] else ""),
                "lines": 2, "section": "Active reminders" if row["status"] in ("active", "scheduling") else "Past reminders",
                "accessories": [countdown(row["due"]) if row["status"] == "active" else row["status"].capitalize()],
                "actions": self.actions(row),
            } for row in rows]
            if not rows:
                frame["items"] = [{"id": "hint", "title": "Set your first reminder", "icon": "bell",
                    "subtitle": "Type reminder <time> <message>, then press Enter. Choose an example below to start.", "lines": 2}, *self.examples()]
        self.visible_ids = {item["id"] for item in frame.get("items", [])}
        send(frame)

    @staticmethod
    def examples():
        return [{"id": f"example:{i}", "title": "reminder " + example, "icon": "clock", "section": "Examples"}
                for i, example in enumerate(EXAMPLES)]

    @staticmethod
    def actions(row):
        actions = [{"id": "copy", "title": "Copy message", "icon": "copy"}]
        if row["status"] in ("active", "scheduling"):
            actions.append({"id": "cancel", "title": "Cancel reminder", "icon": "close", "destructive": True})
        return actions

    def handle(self, event):
        kind = event.get("type")
        if kind in ("init", "query"):
            self.rev = event.get("rev", 0)
            self.query = event.get("text", event.get("query", "")).strip()
            self.selected = None
            self.preview = None
            if self.query:
                try:
                    self.preview = parse(self.query)
                    self.problem = ""
                except (ValueError, OverflowError, OSError) as error:
                    self.problem = str(error)
            self.render(self.rev)
        elif kind in ("back", "navigate"):
            self.selected = None
            self.render(event.get("rev", 0))
        elif kind == "action":
            action, item_id = event.get("action", "default"), event.get("id", "")
            if action in ("refresh", "back"):
                self.selected = None
                self.render()
            elif item_id.startswith("example:") and item_id in self.visible_ids:
                command("setQuery", text=EXAMPLES[int(item_id.split(":")[1])])
            elif (item_id == "create" and action in ("default", "create")) and self.preview:
                command("background", timeout=60)
                command("toast", text="Setting reminder…", style="progress")
                scheduler.create(self.preview)
                self.preview = None  # Repeated Enter cannot create a duplicate.
                self.query = ""
                command("setQuery", text="")
                command("toast", text="Reminder set", style="success")
                self.render()
            else:
                row_id = self.selected or item_id
                row = next((r for r in scheduler.reminders() if r["id"] == row_id), None)
                if row:
                    if action == "cancel":
                        command("background", timeout=60)
                        scheduler.cancel(row_id)
                        command("toast", text="Reminder cancelled")
                    elif action == "copy":
                        command("copy", text=row["message"])
                    elif action == "default":
                        self.selected = row_id
                    self.render()


def main():
    plugin = Plugin()
    events = queue.Queue()

    def read_input():
        for line in sys.stdin:
            try:
                event = json.loads(line)
                if isinstance(event, dict):
                    events.put(event)
            except ValueError as error:
                print(str(error), file=sys.stderr)
        events.put({"type": "close"})

    threading.Thread(target=read_input, daemon=True).start()
    while True:
        try:
            event = events.get(timeout=1)
        except queue.Empty:
            event = None
        if event and event.get("type") == "close":
            break
        try:
            if event:
                plugin.handle(event)
            elif not plugin.query or plugin.preview:
                # Refresh delivery status/countdown without changing the preview
                # deadline. Echo the last revision so stale ticks get dropped.
                plugin.render(plugin.rev)
        except Exception as error:
            print(str(error), file=sys.stderr)
            command("toast", text=str(error), style="error")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--fire":
        scheduler.fire(sys.argv[2])
    else:
        main()
