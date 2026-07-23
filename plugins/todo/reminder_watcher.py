#!/usr/bin/env python3
"""
Standalone due-task notifier for the To-Do & Reminders Tabame plugin.

The plugin itself only runs while its `todo` keyword is active in the
launcher, so it can't fire alarms in the background on its own. Run this
script separately (e.g. via Windows Task Scheduler, trigger "At log on",
action "python reminder_watcher.py") to get a native notification the
moment a task's due time arrives, even when the launcher isn't open.

It reads/writes the exact same tasks.json the plugin uses, so nothing
needs to be duplicated or kept in sync manually.

Requires:  pip install plyer
"""
import json
import os
import sys
import time
import datetime

TASKS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tasks.json")
CHECK_INTERVAL_SECONDS = 30


def notify(title, message):
    try:
        from plyer import notification
        notification.notify(title=title, message=message, app_name="Tabame To-Do", timeout=10)
    except Exception as e:
        print(f"[warn] notification failed: {e}", file=sys.stderr)


def load():
    if not os.path.exists(TASKS_FILE):
        return []
    try:
        with open(TASKS_FILE, encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"[warn] load failed: {e}", file=sys.stderr)
        return []


def save(tasks):
    try:
        with open(TASKS_FILE, "w", encoding="utf-8") as f:
            json.dump(tasks, f, indent=2)
    except Exception as e:
        print(f"[warn] save failed: {e}", file=sys.stderr)


def main():
    print(f"Watching {TASKS_FILE}", file=sys.stderr)
    while True:
        tasks = load()
        changed = False
        now = datetime.datetime.now()
        for t in tasks:
            if t.get("done") or not t.get("due") or t.get("notified"):
                continue
            try:
                due = datetime.datetime.fromisoformat(t["due"])
            except ValueError:
                continue
            if due <= now:
                notify("Task due", t["title"])
                t["notified"] = True
                changed = True
        if changed:
            save(tasks)
        time.sleep(CHECK_INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
