#!/usr/bin/env python3
"""Compact Pomodoro timer for Tabame's launcher plugin protocol."""

import json
import queue
import sys
import threading
from datetime import date, datetime, time, timedelta

from controller import FOCUS, LONG_BREAK, SHORT_BREAK, PomodoroController, utc_now


STORAGE_KEY = "pomodoro-v1"
LOAD_REQUEST = "pomodoro-load"

COMMANDS = (
    ("start", "Start Pomodoro", "play"),
    ("pause", "Pause Pomodoro", "clock"),
    ("resume", "Resume Pomodoro", "play"),
    ("skip", "Skip Session", "refresh"),
    ("reset", "Reset Pomodoro", "sync"),
    ("open", "Open Pomodoro", "timer"),
    ("focus", "Start Focus Session", "timer"),
    ("short", "Start Short Break", "clock"),
    ("long", "Start Long Break", "clock"),
)
ALIASES = {
    "start focus": "focus",
    "focus": "focus",
    "start short break": "short",
    "short break": "short",
    "short": "short",
    "break": "short",
    "start long break": "long",
    "long break": "long",
    "long": "long",
    "settings": "settings",
}


def send(message):
    sys.stdout.write(json.dumps(message, ensure_ascii=False, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def command(name, **fields):
    send({"type": "command", "command": name, **fields})


def duration_text(seconds):
    seconds = max(0, int(seconds))
    minutes, seconds = divmod(seconds, 60)
    return f"{minutes:02d}:{seconds:02d}"


def session_name(session_type):
    return {
        FOCUS: "Focus",
        SHORT_BREAK: "Short Break",
        LONG_BREAK: "Long Break",
    }[session_type]


class PomodoroPlugin:
    def __init__(self):
        self.controller = PomodoroController()
        self.loaded = False
        self.load_requested = False
        self.visible = False
        self.screen = "main"
        self.query = ""
        self.rev = 0
        self.last_display = None

    def persist(self):
        command("storage", op="set", key=STORAGE_KEY, value=self.controller.to_dict())

    def update_retention(self):
        command("background", retain=self.controller.state.status == "running")

    def notify_completion(self, completed):
        if not completed:
            return
        settings = self.controller.settings
        if settings.notify_on_completion:
            if completed[-1] == FOCUS:
                command("notify", title="Pomodoro complete", text="Time for a break.")
            else:
                command("notify", title="Break finished", text="Ready to focus?")
        if settings.sound_on_completion:
            command("sound", name="beep")

    def sync(self):
        completed, changed = self.controller.sync()
        if changed:
            self.persist()
            if self.visible:
                self.update_retention()
        self.notify_completion(completed)
        return changed

    def render_loading(self):
        if not self.visible:
            return
        send({
            "type": "render", "rev": self.rev, "view": "list",
            "loading": True, "loadingText": "Loading Pomodoro…", "items": [],
        })

    def request_load(self):
        if self.load_requested:
            return
        self.load_requested = True
        self.render_loading()
        command("storage", op="get", key=STORAGE_KEY, requestId=LOAD_REQUEST)

    def load(self, value):
        self.controller = PomodoroController.from_dict(value)
        self.loaded = True
        self.sync()
        self.update_retention()
        self.render()

    def actions(self):
        return [
            {"id": action_id, "title": title, "icon": icon}
            for action_id, title, icon in COMMANDS
        ] + [{"id": "settings", "title": "Pomodoro Settings", "icon": "settings"}]

    def page(self, name):
        if name == "settings":
            return {
                "id": "pomodoro:settings", "title": "Settings", "history": "push",
                "breadcrumbs": [{"id": "pomodoro:main", "label": "Pomodoro"}],
            }
        return {"id": "pomodoro:main", "title": "Pomodoro", "history": "none"}

    def render_main(self):
        state = self.controller.state
        settings = self.controller.settings
        seconds = self.controller.display_seconds()
        label = session_name(state.session_type)
        dots = " ".join(
            "●" if n < state.completed_in_cycle else "○"
            for n in range(settings.sessions_before_long_break)
        )
        if state.status == "running":
            title = f"{label.upper()}  {duration_text(seconds)}"
            subtitle = f"{label} · {duration_text(seconds)} remaining"
            badge = "Running"
            primary_id, primary_title, primary_icon = "pause", "Pause", "clock"
        elif state.status == "paused":
            title = f"PAUSED · {label.upper()}  {duration_text(seconds)}"
            subtitle = f"{label} · {duration_text(seconds)} left"
            badge = "Paused"
            primary_id, primary_title, primary_icon = "resume", "Resume", "play"
        else:
            title = f"{label.upper()}  {duration_text(seconds)}"
            subtitle = f"Start a {settings.duration(state.session_type) // 60}-minute {label.lower()} session"
            badge = "Ready"
            primary_id, primary_title, primary_icon = "start", "Start", "play"
        count = state.completed_today
        items = [
            {
                "id": "timer", "title": title,
                "subtitle": f"{subtitle}  ·  {dots}",
                "lines": 2,
                "icon": "timer" if state.session_type == FOCUS else "clock",
                "accessories": [{"text": badge}],
                "progress": self.controller.progress(),
                "actions": [{"id": primary_id, "title": primary_title, "icon": primary_icon}],
            },
            {
                "id": "settings", "title": "Settings",
                "subtitle": f"{count} Pomodoro{'s' if count != 1 else ''} today · {settings.focus_minutes}/{settings.short_break_minutes}/{settings.long_break_minutes} min",
                "icon": "settings",
            },
        ]
        send({
            "type": "render", "rev": self.rev, "view": "list",
            "page": self.page("main"), "placeholder": "pomodoro start · pause · skip · settings",
            "items": items, "actions": self.actions(),
            "floatingAction": [
                {"id": primary_id, "title": primary_title, "icon": primary_icon},
                {"id": "skip", "title": "Skip", "icon": "refresh"},
                {"id": "reset", "title": "Reset", "icon": "sync"},
            ],
        })
        self.last_display = (state.session_type, state.status, seconds, state.completed_today)

    def render_commands(self):
        query = " ".join(self.query.lower().split())
        exact = ALIASES.get(query, query)
        choices = [entry for entry in COMMANDS if entry[0] == exact]
        if not choices:
            choices = [entry for entry in COMMANDS if query in entry[1].lower()]
        if "settings".startswith(query) or query in "pomodoro settings":
            choices.append(("settings", "Pomodoro Settings", "settings"))
        items = [
            {
                "id": f"command:{action_id}", "title": title,
                "subtitle": "Press Enter", "icon": icon,
            }
            for action_id, title, icon in choices
        ]
        send({
            "type": "render", "rev": self.rev, "view": "list",
            "page": self.page("main"), "placeholder": "Pomodoro command",
            "items": items, "actions": self.actions(),
            "empty": {"icon": "timer", "title": "No Pomodoro command", "hint": "Try start, pause, skip, reset, or settings"},
        })

    def render_settings(self, error=None):
        values = self.controller.settings.to_dict()
        fields = [
            {"id": "focus_minutes", "type": "number", "label": "Focus (minutes)", "value": values["focus_minutes"], "min": 1, "max": 240, "section": "timer"},
            {"id": "short_break_minutes", "type": "number", "label": "Short break (minutes)", "value": values["short_break_minutes"], "min": 1, "max": 120, "section": "timer"},
            {"id": "long_break_minutes", "type": "number", "label": "Long break (minutes)", "value": values["long_break_minutes"], "min": 1, "max": 240, "section": "timer"},
            {"id": "sessions_before_long_break", "type": "number", "label": "Focus sessions before long break", "value": values["sessions_before_long_break"], "min": 1, "max": 12, "section": "timer"},
            {"id": "auto_start_breaks", "type": "checkbox", "label": "Auto-start breaks", "value": values["auto_start_breaks"], "section": "automation"},
            {"id": "auto_start_focus", "type": "checkbox", "label": "Auto-start focus sessions", "value": values["auto_start_focus"], "section": "automation"},
            {"id": "notify_on_completion", "type": "checkbox", "label": "Notify on completion", "value": values["notify_on_completion"], "section": "alerts"},
            {"id": "sound_on_completion", "type": "checkbox", "label": "Sound on completion", "value": values["sound_on_completion"], "section": "alerts"},
        ]
        send({
            "type": "render", "rev": self.rev, "view": "form",
            "page": self.page("settings"), "canGoBack": True,
            "form": {
                "title": "Pomodoro Settings", "error": error,
                "sections": [
                    {"id": "timer", "title": "Timer", "description": "New durations apply to the next session."},
                    {"id": "automation", "title": "Automation"},
                    {"id": "alerts", "title": "Notifications"},
                ],
                "fields": fields, "submitLabel": "Save Settings",
            },
            "actions": [{"id": "open", "title": "Back to Pomodoro", "icon": "reply"}],
        })

    def render(self):
        if not self.visible or not self.loaded:
            return
        if self.screen == "settings":
            self.render_settings()
        elif self.query.strip():
            self.render_commands()
        else:
            self.render_main()

    def run_action(self, action_id):
        if action_id == "settings":
            self.screen = "settings"
            if self.query:
                self.query = ""
                command("setQuery", text="")
            self.render()
            return
        if action_id == "open":
            self.screen = "main"
            if self.query:
                self.query = ""
                command("setQuery", text="")
            self.render()
            return

        self.sync()
        changed = True
        if action_id == "start":
            changed = self.controller.start()
        elif action_id == "pause":
            changed = self.controller.pause()
        elif action_id == "resume":
            changed = self.controller.resume()
        elif action_id == "skip":
            self.controller.skip()
        elif action_id == "reset":
            self.controller.reset()
        elif action_id == "focus":
            self.controller.start_session(FOCUS)
        elif action_id == "short":
            self.controller.start_session(SHORT_BREAK)
        elif action_id == "long":
            self.controller.start_session(LONG_BREAK)
        else:
            return
        if changed:
            self.persist()
            self.update_retention()
        self.screen = "main"
        if self.query:
            self.query = ""
            command("setQuery", text="")
        self.render()

    def handle(self, message):
        kind = message.get("type")
        if kind == "close":
            if message.get("reason") == "disabled" and self.loaded:
                self.sync()
                if self.controller.pause():
                    self.persist()
            return False
        if kind == "detach":
            self.visible = False
            return True
        if kind == "attach":
            self.visible = True
            self.screen = "main"
            return True
        if kind in ("init", "query"):
            self.visible = True
            self.query = message.get("text", message.get("query", "")) or ""
            self.rev = message.get("rev", 0)
            if not self.loaded:
                self.request_load()
            else:
                self.sync()
                self.render()
            return True
        if kind == "storage" and message.get("requestId") == LOAD_REQUEST:
            self.load(message.get("value"))
            return True
        if not self.loaded:
            return True
        if kind == "action":
            action_id = message.get("action")
            item_id = message.get("id", "")
            if action_id == "default":
                if item_id == "timer":
                    action_id = {"running": "pause", "paused": "resume", "idle": "start"}[self.controller.state.status]
                elif item_id == "settings":
                    action_id = "settings"
                elif item_id.startswith("command:"):
                    action_id = item_id.split(":", 1)[1]
            self.run_action(action_id)
        elif kind == "submit" and self.screen == "settings":
            values = message.get("values")
            if not isinstance(values, dict):
                self.render_settings("Please review the settings.")
                return True
            merged = self.controller.settings.to_dict()
            merged.update(values)
            self.controller.update_settings(merged)
            self.persist()
            self.screen = "main"
            command("toast", text="Pomodoro settings saved")
            self.render()
        elif kind in ("back", "navigate"):
            self.screen = "main"
            self.render()
        return True

    def wait_timeout(self):
        if not self.loaded:
            return None
        deadlines = []
        if self.controller.state.status == "running":
            deadlines.append(self.controller.remaining())
            if self.visible and self.screen == "main" and not self.query.strip():
                deadlines.append(1.0)
        elif self.visible:
            tomorrow = datetime.combine(date.today() + timedelta(days=1), time.min)
            deadlines.append((tomorrow - datetime.now()).total_seconds())
        if not deadlines:
            return None
        return max(0.05, min(deadlines))

    def on_timeout(self):
        changed = self.sync()
        if not self.visible and self.controller.state.status != "running":
            return False
        if self.visible and self.screen == "main" and not self.query.strip():
            current = (
                self.controller.state.session_type,
                self.controller.state.status,
                self.controller.display_seconds(),
                self.controller.state.completed_today,
            )
            if changed or current != self.last_display:
                self.render_main()
        return True


def read_stdin(events):
    for line in sys.stdin:
        try:
            message = json.loads(line)
            if isinstance(message, dict):
                events.put(message)
        except (TypeError, ValueError) as error:
            print(f"Invalid input: {error}", file=sys.stderr, flush=True)
    events.put({"type": "close"})


def main():
    events = queue.Queue()
    threading.Thread(target=read_stdin, args=(events,), daemon=True).start()
    plugin = PomodoroPlugin()
    while True:
        try:
            message = events.get(timeout=plugin.wait_timeout())
        except queue.Empty:
            if not plugin.on_timeout():
                break
            continue
        try:
            if not plugin.handle(message):
                break
        except Exception as error:
            print(f"Pomodoro error: {error}", file=sys.stderr, flush=True)
            if plugin.visible:
                send({
                    "type": "render", "rev": 0, "view": "detail",
                    "detail": {"markdown": "## Pomodoro error\n\nPlease reopen the plugin."},
                })


if __name__ == "__main__":
    main()
