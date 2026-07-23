# To-Do & Reminders — Tabame Launcher Plugin

A comprehensive to-do list you drive entirely from the Tabame launcher: quick
natural-language add, due dates, priorities, tags, sections, a full edit
form, and a split preview pane.

## Install

Copy this whole folder into:

```
%localappdata%\Tabame\plugins\todo-reminders\
```

Reopen the launcher, then type `todo`.

## Using it

**Quick add** — type after `todo` and press Enter:

```
todo Buy milk tomorrow 5pm !h #errands #home
```

| Token | Meaning |
|---|---|
| `!h` / `!high` | priority: high |
| `!m` / `!med` / `!medium` | priority: medium |
| `!l` / `!low` | priority: low |
| `#tag` | one or more tags |
| `today` | due today |
| `tomorrow` / `tmrw` | due tomorrow |
| `mon` … `sun` (or full names) | due next occurrence of that weekday |
| `+3d` / `+2h` / `+1w` | due N days / hours / weeks from now |
| `2026-07-22` | explicit date |
| `7/22` or `7-22` | explicit date, month/day (this year, or next if already past) |
| `5pm`, `5:30pm`, `17:00` | time of day |

Any words left over become the task title. As you type, a pinned "Add: …"
row previews exactly what will be created before you commit with Enter.

**Everything else** is done from the list, via **Enter** or **Ctrl+K**:

- **Enter** on a task — toggle complete / reopen it
- **Ctrl+K** on a task — Edit, Snooze 1 Day, Set Due Today/Tomorrow, Clear
  Due Date, set/clear Priority, Delete (confirmed)
- **Ctrl+K** on the list itself (or **Ctrl+N**) — New Task (full form),
  Show/Hide Completed, Clear Completed Tasks
- **New Task (full form)** — title, notes, due date, due time, priority
  dropdown, and a tags field with autocomplete from your existing tags

Tasks are grouped into **Overdue / Today / Tomorrow / This Week / Later /
No Due Date / Done**, sorted by due date then priority within each group.
The colored dot on each row is its priority; a due chip turns red once a
task is overdue.

## Data

Tasks live in `tasks.json` right next to `main.py`, in plain readable JSON
(intentionally not the launcher's internal `.tabame-store.json`, so you can
inspect it, back it up, or point another tool at it).

## Background reminders (optional)

The plugin process only runs while you're actively in the `todo` keyword —
like any Tabame plugin, it can't ring an alarm while the launcher is closed.
`reminder_watcher.py` is a small standalone script (not a Tabame plugin,
just a normal Python script) that watches the same `tasks.json` and fires a
native Windows notification the moment a task's due time passes, whether or
not the launcher is open.

Setup:

```
pip install plyer
```

Then register it to run at logon, e.g. via Task Scheduler:

- Trigger: **At log on**
- Action: `pythonw.exe` (or `python.exe`) with argument
  `"%localappdata%\Tabame\plugins\todo-reminders\reminder_watcher.py"`

It checks every 30 seconds and marks a task `"notified": true` after
alerting so it won't repeat — snoozing, editing, or changing a task's due
date automatically re-arms it.

## Files

| File | Purpose |
|---|---|
| `plugin.json` | Tabame manifest |
| `main.py` | the plugin itself |
| `tasks.json` | your data (created on first use) |
| `reminder_watcher.py` | optional standalone notifier |
