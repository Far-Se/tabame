"""Timestamp-based Pomodoro state machine; independent of the launcher UI."""

from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from math import ceil


FOCUS = "focus"
SHORT_BREAK = "shortBreak"
LONG_BREAK = "longBreak"
SESSION_TYPES = (FOCUS, SHORT_BREAK, LONG_BREAK)


def utc_now():
    return datetime.now(timezone.utc)


def bounded_int(value, default, low, high):
    try:
        number = int(value)
    except (TypeError, ValueError):
        return default
    return min(high, max(low, number))


@dataclass
class PomodoroSettings:
    focus_minutes: int = 25
    short_break_minutes: int = 5
    long_break_minutes: int = 15
    sessions_before_long_break: int = 4
    auto_start_breaks: bool = False
    auto_start_focus: bool = False
    notify_on_completion: bool = True
    sound_on_completion: bool = True

    @classmethod
    def from_dict(cls, value):
        value = value if isinstance(value, dict) else {}
        return cls(
            focus_minutes=bounded_int(value.get("focus_minutes"), 25, 1, 240),
            short_break_minutes=bounded_int(value.get("short_break_minutes"), 5, 1, 120),
            long_break_minutes=bounded_int(value.get("long_break_minutes"), 15, 1, 240),
            sessions_before_long_break=bounded_int(value.get("sessions_before_long_break"), 4, 1, 12),
            auto_start_breaks=value.get("auto_start_breaks") is True,
            auto_start_focus=value.get("auto_start_focus") is True,
            notify_on_completion=value.get("notify_on_completion") is not False,
            sound_on_completion=value.get("sound_on_completion") is not False,
        )

    def to_dict(self):
        return vars(self).copy()

    def duration(self, session_type):
        minutes = {
            FOCUS: self.focus_minutes,
            SHORT_BREAK: self.short_break_minutes,
            LONG_BREAK: self.long_break_minutes,
        }[session_type]
        return minutes * 60


@dataclass
class PomodoroState:
    session_type: str = FOCUS
    status: str = "idle"
    end_time: datetime = None
    paused_remaining: float = None
    session_seconds: int = 1500
    completed_in_cycle: int = 0
    completed_today: int = 0
    stats_date: str = None

    @classmethod
    def from_dict(cls, value, settings):
        value = value if isinstance(value, dict) else {}
        session_type = value.get("session_type")
        if session_type not in SESSION_TYPES:
            session_type = FOCUS
        status = value.get("status")
        if status not in ("idle", "running", "paused"):
            status = "idle"
        end_time = None
        try:
            end_time = datetime.fromisoformat(value.get("end_time"))
            if end_time.tzinfo is None:
                end_time = end_time.replace(tzinfo=timezone.utc)
        except (TypeError, ValueError):
            pass
        if status == "running" and end_time is None:
            status = "idle"
        if status != "running":
            end_time = None
        session_seconds = bounded_int(
            value.get("session_seconds"), settings.duration(session_type), 60, 14400
        )
        try:
            paused_remaining = float(value.get("paused_remaining"))
        except (TypeError, ValueError):
            paused_remaining = float(session_seconds)
        paused_remaining = min(session_seconds, max(0.0, paused_remaining))
        stats_date = value.get("stats_date")
        try:
            date.fromisoformat(stats_date)
        except (TypeError, ValueError):
            stats_date = date.today().isoformat()
        return cls(
            session_type=session_type,
            status=status,
            end_time=end_time,
            paused_remaining=paused_remaining,
            session_seconds=session_seconds,
            completed_in_cycle=bounded_int(value.get("completed_in_cycle"), 0, 0, 12),
            completed_today=bounded_int(value.get("completed_today"), 0, 0, 100000),
            stats_date=stats_date,
        )

    def to_dict(self):
        return {
            "session_type": self.session_type,
            "status": self.status,
            "end_time": self.end_time.isoformat() if self.end_time else None,
            "paused_remaining": self.paused_remaining,
            "session_seconds": self.session_seconds,
            "completed_in_cycle": self.completed_in_cycle,
            "completed_today": self.completed_today,
            "stats_date": self.stats_date,
        }


class PomodoroController:
    def __init__(self, settings=None, state=None):
        self.settings = settings or PomodoroSettings()
        self.state = state or PomodoroState(
            session_seconds=self.settings.duration(FOCUS),
            paused_remaining=float(self.settings.duration(FOCUS)),
            stats_date=date.today().isoformat(),
        )

    @classmethod
    def from_dict(cls, value):
        value = value if isinstance(value, dict) else {}
        settings = PomodoroSettings.from_dict(value.get("settings"))
        state = PomodoroState.from_dict(value.get("state"), settings)
        return cls(settings, state)

    def to_dict(self):
        return {"settings": self.settings.to_dict(), "state": self.state.to_dict()}

    def _roll_date(self, day):
        day_text = day.isoformat()
        if self.state.stats_date != day_text:
            self.state.stats_date = day_text
            self.state.completed_today = 0
            return True
        return False

    def remaining(self, now=None):
        if self.state.status == "running" and self.state.end_time:
            return max(0.0, (self.state.end_time - (now or utc_now())).total_seconds())
        return self.state.paused_remaining or 0.0

    def display_seconds(self, now=None):
        return ceil(self.remaining(now))

    def progress(self, now=None):
        return 1.0 - self.remaining(now) / max(1, self.state.session_seconds)

    def _prepare(self, session_type):
        self.state.session_type = session_type
        self.state.session_seconds = self.settings.duration(session_type)
        self.state.paused_remaining = float(self.state.session_seconds)
        self.state.end_time = None
        self.state.status = "idle"

    def _start_at(self, at):
        remaining = self.state.paused_remaining or self.state.session_seconds
        self.state.end_time = at + timedelta(seconds=remaining)
        self.state.paused_remaining = None
        self.state.status = "running"

    def start(self, now=None):
        if self.state.status == "running":
            return False
        self._start_at(now or utc_now())
        return True

    def pause(self, now=None):
        if self.state.status != "running":
            return False
        self.state.paused_remaining = self.remaining(now)
        self.state.end_time = None
        self.state.status = "paused"
        return True

    def resume(self, now=None):
        if self.state.status != "paused":
            return False
        return self.start(now)

    def reset(self):
        self.state.completed_in_cycle = 0
        self._prepare(FOCUS)

    def skip(self, now=None):
        current = self.state.session_type
        if current == FOCUS:
            next_type = SHORT_BREAK
        else:
            next_type = FOCUS
            if current == LONG_BREAK:
                self.state.completed_in_cycle = 0
        self._prepare(next_type)
        should_start = (
            self.settings.auto_start_breaks if current == FOCUS else self.settings.auto_start_focus
        )
        if should_start:
            self._start_at(now or utc_now())

    def start_session(self, session_type, now=None):
        if session_type not in SESSION_TYPES:
            raise ValueError("Unknown session type")
        if self.state.session_type == LONG_BREAK and session_type == FOCUS:
            self.state.completed_in_cycle = 0
        self._prepare(session_type)
        self._start_at(now or utc_now())

    def _complete_at(self, finished_at):
        current = self.state.session_type
        self._roll_date(finished_at.astimezone().date())
        if current == FOCUS:
            self.state.completed_in_cycle += 1
            self.state.completed_today += 1
            next_type = (
                LONG_BREAK
                if self.state.completed_in_cycle >= self.settings.sessions_before_long_break
                else SHORT_BREAK
            )
            should_start = self.settings.auto_start_breaks
        else:
            if current == LONG_BREAK:
                self.state.completed_in_cycle = 0
            next_type = FOCUS
            should_start = self.settings.auto_start_focus
        self._prepare(next_type)
        if should_start:
            self._start_at(finished_at)
        return current

    def sync(self, now=None):
        now = now or utc_now()
        completions = []
        # Each step advances by at least a minute; the guard bounds corrupt or
        # years-old auto-start data without allowing a startup loop to hang.
        for _ in range(100000):
            if self.state.status != "running" or self.state.end_time > now:
                break
            deadline = self.state.end_time
            completions.append(self._complete_at(deadline))
        else:
            # An unattended auto-start cycle can span years. Keep recovery
            # bounded and leave a fresh session ready instead of looping again.
            self._prepare(self.state.session_type)
        changed = bool(completions)
        changed = self._roll_date(now.astimezone().date()) or changed
        return completions, changed

    def update_settings(self, value):
        self.settings = PomodoroSettings.from_dict(value)
        if self.state.status == "idle":
            self._prepare(self.state.session_type)
