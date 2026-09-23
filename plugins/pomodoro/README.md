# Pomodoro

A compact focus and break timer for the Tabame launcher. Type `pomodoro` to see the current session, remaining time, cycle dots, and today's completed focus sessions. Press **Enter** on the timer to start, pause, or resume. The visible **Skip** and **Reset** buttons provide the other common controls. Open **Settings** from the second row.

Direct launcher commands include `pomodoro start`, `pomodoro pause`, `pomodoro resume`, `pomodoro skip`, `pomodoro reset`, `pomodoro open`, `pomodoro focus`, `pomodoro short`, and `pomodoro long`. Press **Enter** on a matching command. All nine named actions are also available through **Ctrl+K**.

The default cycle is 25 minutes of focus, a 5-minute short break, and a 15-minute long break after four completed focus sessions. Settings include all durations, the long-break interval, auto-start options, notifications, and sound. Skipping a focus session does not count it as completed. Reset returns to a fresh focus session and resets the cycle, while preserving today's completed count.

The plugin stores settings and timer state through Tabame's per-plugin `storage` command. A running timer requests the host's reattachable background process capability. It waits until the stored end timestamp, even when the launcher is hidden, and sends Tabame's native notification and optional beep on completion. Opening Pomodoro again reconnects to that same process. If Tabame itself exits, the next launch reconstructs elapsed sessions from persisted timestamps; delivery of a notification while Tabame is not running is unavailable.

The plugin requires Python on `PATH` and a Tabame build with `background retain` and `sound` protocol support. It has no Python package dependencies. For a manual installation, copy this folder to `%localappdata%\Tabame\plugins\pomodoro\` on Windows and reopen the launcher.
