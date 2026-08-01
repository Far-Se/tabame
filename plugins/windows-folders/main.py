#!/usr/bin/env python3
"""
Tabame plugin: "wf" (Windows Folder)

Lists Windows "special" / known folders (AppData, Downloads, Startup,
ProgramData, ...) and lets you filter them by typing, e.g.:

    wf appdata      -> AppData (Roaming), Local AppData, LocalLow AppData
    wf startup      -> Startup
    wf              -> everything

Enter opens the folder in Explorer. Ctrl+K offers "Copy Path".

Paths are resolved via the Windows Known Folder API (SHGetKnownFolderPath)
rather than plain env vars, so folders redirected elsewhere (e.g. Desktop /
Documents moved to another drive or synced by OneDrive) still resolve
correctly.
"""

import ctypes
import json
import os
import sys


def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# Known Folder resolution (ctypes -> shell32.SHGetKnownFolderPath)
# ---------------------------------------------------------------------------


class GUID(ctypes.Structure):
    _fields_ = [
        ("Data1", ctypes.c_ulong),
        ("Data2", ctypes.c_ushort),
        ("Data3", ctypes.c_ushort),
        ("Data4", ctypes.c_ubyte * 8),
    ]


def _guid(guid_str):
    g = GUID()
    ctypes.windll.ole32.CLSIDFromString(ctypes.c_wchar_p(guid_str), ctypes.byref(g))
    return g


def known_folder(guid_str):
    """Resolve a KNOWNFOLDERID GUID string to a filesystem path, or None."""
    try:
        rfid = _guid(guid_str)
        path_ptr = ctypes.c_wchar_p()
        hr = ctypes.windll.shell32.SHGetKnownFolderPath(
            ctypes.byref(rfid), 0, 0, ctypes.byref(path_ptr)
        )
        if hr != 0 or not path_ptr.value:
            return None
        path = path_ptr.value
        try:
            ctypes.windll.ole32.CoTaskMemFree(path_ptr)
        except Exception:
            pass
        return path
    except Exception as e:
        log("known_folder failed for", guid_str, "->", e)
        return None


# ---------------------------------------------------------------------------
# Folder catalogue
# ---------------------------------------------------------------------------

FOLDERS = [
    {
        "id": "appdata-roaming",
        "name": "AppData (Roaming)",
        "keywords": ["appdata", "roaming"],
        "guid": "{3EB685DB-65F9-4CF6-A03A-E3EF65729F3D}",
    },
    {
        "id": "appdata-local",
        "name": "Local AppData",
        "keywords": ["appdata", "local"],
        "guid": "{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}",
    },
    {
        "id": "appdata-locallow",
        "name": "LocalLow AppData",
        "keywords": ["appdata", "locallow", "low"],
        "guid": "{A520A1A4-1780-4FF6-BD18-167343C5AF16}",
    },
    {
        "id": "desktop",
        "name": "Desktop",
        "keywords": ["desktop"],
        "guid": "{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}",
    },
    {
        "id": "documents",
        "name": "Documents",
        "keywords": ["documents", "my documents"],
        "guid": "{FDD39AD0-238F-46AF-ADB4-6C85480369C7}",
    },
    {
        "id": "downloads",
        "name": "Downloads",
        "keywords": ["downloads"],
        "guid": "{374DE290-123F-4565-9164-39C4925E467B}",
    },
    {
        "id": "pictures",
        "name": "Pictures",
        "keywords": ["pictures", "photos"],
        "guid": "{33E28130-4E1E-4676-835A-98395C3BC3BB}",
    },
    {
        "id": "music",
        "name": "Music",
        "keywords": ["music"],
        "guid": "{4BD8D571-6D19-48D3-BE97-422220080E43}",
    },
    {
        "id": "videos",
        "name": "Videos",
        "keywords": ["videos", "movies"],
        "guid": "{18989B1D-99B5-455B-841C-AB7C74E4DDFC}",
    },
    {
        "id": "favorites",
        "name": "Favorites",
        "keywords": ["favorites", "bookmarks"],
        "guid": "{1777F761-68AD-4D8A-87BD-30B759FA33DD}",
    },
    {
        "id": "startup",
        "name": "Startup",
        "keywords": ["startup", "autostart", "run"],
        "guid": "{B97D20BB-F46A-4C97-BA10-5E3608430854}",
    },
    {
        "id": "start-menu",
        "name": "Start Menu",
        "keywords": ["start menu", "startmenu"],
        "guid": "{625B53C3-AB48-4EC2-8FD8-C6C2E39A5FF9}",
    },
    {
        "id": "programs",
        "name": "Start Menu Programs",
        "keywords": ["programs", "start menu programs"],
        "guid": "{A77F5D77-2E2B-44C3-A6A2-ABA601054A51}",
    },
    {
        "id": "recent",
        "name": "Recent Items",
        "keywords": ["recent"],
        "guid": "{AE50C081-EBD2-438A-8655-8A092E34987A}",
    },
    {
        "id": "sendto",
        "name": "SendTo",
        "keywords": ["sendto", "send to"],
        "guid": "{8983036C-27C0-404B-8F08-102D10DCFD74}",
    },
    {
        "id": "templates",
        "name": "Templates",
        "keywords": ["templates"],
        "guid": "{A63293E8-664E-48DB-A079-83A65DE1EAAA}",
    },
    {
        "id": "quicklaunch",
        "name": "Quick Launch",
        "keywords": ["quicklaunch", "quick launch"],
        "guid": None,
        "manual": "quicklaunch",
    },
    {
        "id": "public",
        "name": "Public",
        "keywords": ["public"],
        "guid": "{DFDF76A2-C82A-4D63-906A-5644AC457385}",
    },
    {
        "id": "public-desktop",
        "name": "Public Desktop",
        "keywords": ["public desktop", "public"],
        "guid": "{C4AA340D-F20F-4863-AFEF-F87EF2E6BA25}",
    },
    {
        "id": "public-documents",
        "name": "Public Documents",
        "keywords": ["public documents", "public"],
        "guid": "{ED4824AF-DCE4-45A8-81E2-FC7965083634}",
    },
    {
        "id": "public-downloads",
        "name": "Public Downloads",
        "keywords": ["public downloads", "public"],
        "guid": "{3D644C9B-1FB8-4F30-9B45-F670235F79C0}",
    },
    {
        "id": "programdata",
        "name": "ProgramData",
        "keywords": ["programdata", "program data"],
        "guid": "{62AB5D82-FDC1-4DC3-A9DD-070D1D495D97}",
    },
    {
        "id": "program-files",
        "name": "Program Files",
        "keywords": ["program files", "programfiles"],
        "guid": "{6D809377-6AF0-444B-8957-A3773F02200E}",
    },
    {
        "id": "program-files-x86",
        "name": "Program Files (x86)",
        "keywords": ["program files x86", "programfiles(x86)"],
        "guid": "{7C5A40EF-A0FB-4BFC-874A-C0F2E0B9FA8E}",
    },
    {
        "id": "windows",
        "name": "Windows",
        "keywords": ["windows", "winsxs"],
        "guid": "{F38BF404-1D43-42F2-9305-67DE0B28FC23}",
    },
    {
        "id": "system32",
        "name": "System32",
        "keywords": ["system32", "system"],
        "guid": "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}",
    },
    {
        "id": "fonts",
        "name": "Fonts",
        "keywords": ["fonts"],
        "guid": "{FD228CB7-AE11-4AE3-864C-16F3910AB8FE}",
    },
    {
        "id": "savedgames",
        "name": "Saved Games",
        "keywords": ["saved games", "savedgames", "games"],
        "guid": "{4C5C32FF-BB9D-43B0-B5B4-2D72E54EAAA4}",
    },
    {
        "id": "cookies",
        "name": "Cookies",
        "keywords": ["cookies"],
        "guid": "{2B0F765D-C0E9-4171-908E-08A611B84FF6}",
    },
    {
        "id": "history",
        "name": "History",
        "keywords": ["history"],
        "guid": "{D9DC8A3B-B784-432E-A781-5A1130A75963}",
    },
    {
        "id": "inetcache",
        "name": "Temporary Internet Files",
        "keywords": ["inetcache", "internet cache", "temp internet"],
        "guid": "{352481E8-33BE-4251-BA85-6007CAEDCF9D}",
    },
    {
        "id": "nethood",
        "name": "Network Shortcuts",
        "keywords": ["nethood", "network shortcuts"],
        "guid": "{C5ABBF53-E17F-4121-8900-86626FC2C973}",
    },
    {
        "id": "printhood",
        "name": "Printer Shortcuts",
        "keywords": ["printhood", "printer shortcuts"],
        "guid": "{9274BD8D-CFD1-41C3-B35E-B13F55A758F4}",
    },
    {
        "id": "temp",
        "name": "Temp",
        "keywords": ["temp", "temporary"],
        "guid": None,
        "manual": "temp",
    },
    {
        "id": "profile",
        "name": "User Profile",
        "keywords": ["profile", "home", "userprofile"],
        "guid": "{5E6C858F-0E22-4760-9AFE-EA3317B67173}",
    },
]

_RESOLVED = {}


def resolve_all():
    if _RESOLVED:
        return _RESOLVED
    for f in FOLDERS:
        if f.get("guid"):
            _RESOLVED[f["id"]] = known_folder(f["guid"])
    roaming = _RESOLVED.get("appdata-roaming")
    for f in FOLDERS:
        manual = f.get("manual")
        if manual == "quicklaunch" and roaming:
            _RESOLVED["quicklaunch"] = os.path.join(
                roaming, "Microsoft", "Internet Explorer", "Quick Launch"
            )
        elif manual == "temp":
            _RESOLVED["temp"] = os.environ.get("TEMP") or os.environ.get("TMP")
    return _RESOLVED


def path_for(folder_id):
    return resolve_all().get(folder_id)


# ---------------------------------------------------------------------------
# Search / rendering
# ---------------------------------------------------------------------------


def matches(folder, tokens):
    if not tokens:
        return True
    haystack = (
        folder["name"] + " " + " ".join(folder.get("keywords", [])) + " " + folder["id"]
    ).lower()
    return all(tok in haystack for tok in tokens)


def build_items(query_text):
    tokens = [t for t in query_text.lower().split() if t]
    items = []
    for f in FOLDERS:
        if not matches(f, tokens):
            continue
        p = path_for(f["id"])
        exists = bool(p) and os.path.isdir(p)
        if p:
            subtitle = p if exists else f"{p}  ·  not found"
        else:
            subtitle = "Unavailable on this system"
        items.append(
            {
                "id": f["id"],
                "title": f["name"],
                "subtitle": subtitle,
                "icon": "folder",
                "lines": 1,
                "actions": [
                    {"id": "copy", "title": "Copy Path", "icon": "copy"},
                ],
                # "preview": {
                #     "markdown": f"## {f['name']}",
                #     "metadata": [
                #         {"label": "Path", "text": p or "—"},
                #         {
                #             "label": "Status",
                #             "text": "Exists" if exists else "Not found",
                #             "color": "#22C55E" if exists else "#EF4444",
                #         },
                #     ],
                # },
            }
        )
    return items


def render(rev, text):
    items = build_items(text)
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            # "preview": {"enabled": True},
            "placeholder": "Search Windows folders… e.g. appdata, downloads, startup",
            "emptyText": "No matching special folder",
            "items": items,
        }
    )


def handle_action(item_id, action):
    p = path_for(item_id)
    if not p:
        send(
            {
                "type": "command",
                "command": "toast",
                "text": "That folder isn't available on this system.",
                "style": "error",
            }
        )
        return

    if action == "copy":
        send({"type": "command", "command": "copy", "text": p})
        return

    # default action: open in Explorer
    if not os.path.isdir(p):
        send(
            {
                "type": "command",
                "command": "toast",
                "text": f"Folder not found: {p}",
                "style": "error",
            }
        )
        return
    send({"type": "command", "command": "open", "path": p})
    send({"type": "command", "command": "hide"})


def main():
    resolve_all()
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
            handle_action(msg.get("id", ""), msg.get("action", "default"))
        # "select" is not needed: previews are attached per-item already.


if __name__ == "__main__":
    main()
