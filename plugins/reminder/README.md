# Reminders

A Windows launcher plugin with the keyword `reminder`. Requires Python 3.8+
(including `pythonw.exe`) on PATH and Windows Task Scheduler. No pip packages.

Copy this folder to `%LOCALAPPDATA%\Tabame\plugins\reminder\`, then reopen the
launcher. When launched by Tabame, the plugin finds its parent Tabame.exe.
If discovery fails, copy `config.example.json` to `config.json` and set
`tabamePath` to the full executable path. `TABAME_EXE` is also supported.

## Usage

Type a time followed by the message. The trigger date, local time, timezone,
and countdown appear while typing. **Enter** saves the displayed reminder.
Typing a time without a message only previews it.

| Input | Meaning |
| --- | --- |
| `reminder 8pm go wash clothes` | Next 20:00 |
| `reminder 8:30pm go wash clothes` | Next 20:30 |
| `reminder 20:30 go wash clothes` | Next 20:30 |
| `reminder 8h5m go wash clothes` | 8 hours and 5 minutes from now |
| `reminder tomorrow 10AM go wash clothes` | Tomorrow at 10:00 |
| `reminder 2 Nov 12:40 go wash clothes` | Next November 2 at 12:40 |

AM/PM and English month names are case-insensitive. Full month names and an
explicit year (`2 November 2027 12:40`) work too. Durations accept `d`, `h`, `m`,
and `s`, joined or separated by spaces (`8h 5m`). Each unit may appear once.
Bare hours such as `8` need AM/PM or minutes before they become a valid preview.
Invalid/incomplete times never create a reminder.

Clock-only times that have passed roll to tomorrow; dates without a year roll
to their next occurrence. Explicit past dates are rejected. Durations count
elapsed seconds across daylight-saving changes. Clock times use the computer's
local timezone at creation; nonexistent spring-forward times are rejected and
ambiguous fall-back times use the operating system's default interpretation.
The preview includes the timezone. The displayed instant is saved on Enter;
editing the query recalculates relative times.

Type just `reminder` to see active reminders first (earliest first), then past
reminders (most recently finished first). If none exist, usage examples appear;
Enter on an example fills the query. Enter on a reminder opens its details.
Use Ctrl+K to cancel an active reminder or copy its message. Cancellation stays
in history. Delivery failures also appear in history with their error.

## Background delivery

Each saved reminder registers a per-user Windows scheduled task named
`Tabame-Reminder-<installation hash>-<reminder id>`. It invokes a hidden Python
helper, which launches:

```text
Tabame.exe -msgbox -title Reminder -message "go wash clothes"
```

Messages are passed as a single process argument, never evaluated by a shell.
Closing the launcher or exiting Tabame does not cancel scheduled reminders.
The task runs in your interactive Windows session without storing a password.
It also checks at sign-in so overdue reminders can be delivered after reboot.
Future reminders are not fired early at sign-in. Sleeping/offline computers
cannot show the dialog on time; missed reminders run when Windows allows them
after waking or signing in. The plugin does not wake the computer.

Settings use Windows Task Scheduler's
[StartWhenAvailable and battery options](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset)
and an [interactive principal](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtaskprincipal).
Task registration failures (including restricted Task Scheduler access) are
reported in the launcher. Completed/cancelled tasks are removed automatically.
History lives in `reminders.sqlite3` beside the scripts; SQLite serializes
delivery and cancellation. “Delivered” means Tabame was successfully launched,
not that the dialog was acknowledged. A crash between process launch and the
database commit can cause a duplicate on recovery.

Keep the plugin folder, Python, and Tabame executable at their original paths
while reminders are active. Cancel active reminders before moving/uninstalling
the plugin. To remove orphaned tasks, find the matching installation prefix in
Windows Task Scheduler and delete those tasks. Do not delete the database while
reminders are active. Linux/macOS provide parsing and preview only; native
scheduling remains a placeholder.
