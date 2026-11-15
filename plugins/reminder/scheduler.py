"""Durable reminder storage and Windows Task Scheduler integration."""

import base64
from contextlib import contextmanager
import ctypes
from ctypes import wintypes
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import time
import uuid


ROOT = Path(__file__).resolve().parent
DATABASE = ROOT / "reminders.sqlite3"
TASK_PREFIX = "Tabame-Reminder-" + hashlib.sha256(str(ROOT).casefold().encode()).hexdigest()[:12] + "-"


@contextmanager
def connect():
    db = sqlite3.connect(DATABASE, timeout=40)
    db.row_factory = sqlite3.Row
    try:
        db.execute("""CREATE TABLE IF NOT EXISTS reminders (
            id TEXT PRIMARY KEY, message TEXT NOT NULL, due REAL NOT NULL,
            created REAL NOT NULL, status TEXT NOT NULL, exe TEXT NOT NULL,
            finished REAL, error TEXT NOT NULL DEFAULT ''
        )""")
        with db:
            yield db
    finally:
        db.close()


def require_windows():
    if os.name != "nt":
        # //TODO: Implement multiplatform
        raise RuntimeError("Scheduling is available on Windows. Linux and macOS are not implemented yet.")


def powershell(script, data):
    require_windows()
    # User text and paths travel as JSON on stdin, never as PowerShell source.
    source = "$ErrorActionPreference = 'Stop'; $d = [Console]::In.ReadToEnd() | ConvertFrom-Json;\n" + script
    encoded = base64.b64encode(source.encode("utf-16-le")).decode("ascii")
    result = subprocess.run(
        ["powershell.exe", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-EncodedCommand", encoded],
        input=json.dumps(data), text=True, encoding="utf-8", errors="replace",
        capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW, timeout=30,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "Windows Task Scheduler failed.")


def tabame_executable():
    require_windows()
    config_path = ROOT / "config.json"
    config = json.loads(config_path.read_text(encoding="utf-8-sig")) if config_path.exists() else {}
    configured = config.get("tabamePath") or os.environ.get("TABAME_EXE")
    if configured:
        path = Path(os.path.expandvars(configured)).expanduser()
        if path.is_file() and path.suffix.lower() == ".exe":
            return str(path.resolve())
        raise RuntimeError("tabamePath in config.json must point to an existing Tabame.exe.")

    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
    kernel.QueryFullProcessImageNameW.restype = wintypes.BOOL
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel.CloseHandle.restype = wintypes.BOOL
    handle = kernel.OpenProcess(0x1000, False, os.getppid())
    if handle:
        try:
            buffer = ctypes.create_unicode_buffer(32768)
            length = wintypes.DWORD(len(buffer))
            if kernel.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(length)):
                parent = Path(buffer.value)
                if parent.name.lower() == "tabame.exe":
                    return str(parent)
        finally:
            kernel.CloseHandle(handle)
    found = shutil.which("tabame.exe")
    if found:
        return found
    raise RuntimeError("Cannot locate Tabame.exe. Copy config.example.json to config.json and set tabamePath.")


def unregister(reminder_id):
    powershell("""
$task = Get-ScheduledTask -TaskName $d.name -ErrorAction SilentlyContinue
if ($task) { $task | Unregister-ScheduledTask -Confirm:$false }
""", {"name": TASK_PREFIX + reminder_id})


def create(preview):
    require_windows()
    if not preview.message:
        raise ValueError("Add a reminder message after the time.")
    if preview.due <= time.time():
        raise ValueError("The preview time has passed. Edit the time to choose a new one.")
    exe = tabame_executable()
    pythonw = Path(sys.executable).with_name("pythonw.exe")
    if not pythonw.is_file():
        raise RuntimeError("pythonw.exe is required beside python.exe to deliver reminders without a console.")
    reminder_id = uuid.uuid4().hex
    with connect() as db:
        # Persist before registration: even an interrupted UI process cannot
        # leave a registered task without its message. Failed setup is visible.
        db.execute("INSERT INTO reminders (id,message,due,created,status,exe) VALUES (?,?,?,?,?,?)",
                   (reminder_id, preview.message, preview.due, time.time(), "scheduling", exe))
    try:
        powershell("""
$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute $d.python -Argument $d.arguments -WorkingDirectory $d.root
$at = [DateTimeOffset]::Parse($d.at, [Globalization.CultureInfo]::InvariantCulture).LocalDateTime
$triggers = @((New-ScheduledTaskTrigger -Once -At $at), (New-ScheduledTaskTrigger -AtLogOn -User $user))
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName $d.name -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description 'Tabame reminder' | Out-Null
if ($at -le (Get-Date)) { Start-ScheduledTask -TaskName $d.name }
""", {
            "name": TASK_PREFIX + reminder_id, "python": str(pythonw), "root": str(ROOT),
            "arguments": subprocess.list2cmdline([str(ROOT / "main.py"), "--fire", reminder_id]),
            "at": datetime.fromtimestamp(preview.due).astimezone().isoformat(),
        })
    except Exception as error:
        with connect() as db:
            db.execute("UPDATE reminders SET status='failed',finished=?,error=? WHERE id=? AND status='scheduling'",
                       (time.time(), str(error), reminder_id))
        # Registration can succeed just before a timeout; failed rows never fire.
        try:
            unregister(reminder_id)
        except Exception:
            pass
        raise
    with connect() as db:
        db.execute("UPDATE reminders SET status='active' WHERE id=? AND status='scheduling'", (reminder_id,))


def cancel(reminder_id):
    # Serialize with delivery so cancelled reminders cannot launch afterwards.
    with connect() as db:
        db.execute("BEGIN IMMEDIATE")
        db.execute("UPDATE reminders SET status='cancelled',finished=? WHERE id=? AND status IN ('active','scheduling')",
                   (time.time(), reminder_id))
    unregister(reminder_id)


def fire(reminder_id):
    require_windows()
    with connect() as db:
        db.execute("BEGIN IMMEDIATE")
        row = db.execute("SELECT * FROM reminders WHERE id=?", (reminder_id,)).fetchone()
        if row and row["status"] in ("active", "scheduling"):
            if row["due"] > time.time():
                return  # A logon before the due time must not trigger early.
            try:
                # Tabame treats leading '-' as a flag; an invisible prefix keeps
                # arbitrary message text (including '-title') a literal value.
                message = row["message"]
                if message.startswith("-"):
                    message = "\u200b" + message
                subprocess.Popen(
                    [row["exe"], "-msgbox", "-title", "Reminder", "-message", message, "-speak", message],
                    cwd=str(Path(row["exe"]).parent), stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP,
                    close_fds=True,
                )
            except Exception as error:
                db.execute("UPDATE reminders SET status='failed',finished=?,error=? WHERE id=?",
                           (time.time(), str(error), reminder_id))
            else:
                db.execute("UPDATE reminders SET status='delivered',finished=?,error='' WHERE id=?", (time.time(), reminder_id))
    try:
        unregister(reminder_id)
    except Exception:
        # A leftover task is harmless: terminal rows are never delivered twice.
        pass


def reminders():
    with connect() as db:
        return [dict(row) for row in db.execute("""SELECT * FROM reminders
            ORDER BY CASE WHEN status IN ('active','scheduling') THEN 0 ELSE 1 END,
            CASE WHEN status IN ('active','scheduling') THEN due END ASC,
            COALESCE(finished,created) DESC""")]
