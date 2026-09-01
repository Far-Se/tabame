#!/usr/bin/env python3
"""Tabame 'Bookmarks' plugin — links, files, and parameterized commands under categories."""
import sys, json, os, re, uuid, threading, subprocess, hashlib
from datetime import datetime
from urllib.parse import urlparse

PLUGIN_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_FILE = os.path.join(PLUGIN_DIR, "bookmarks.json")

VAR_RE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")

TYPE_ICON = {"link": "link", "file": "file", "command": "terminal"}
TYPE_LABEL = {"link": "Link", "file": "File", "command": "Command"}

TABAME_CATEGORY_PREFIX = "tabame_category_"
TABAME_BOOKMARK_PREFIX = "tabame_bookmark_"
TABAME_SETTINGS_SIGNATURES = None
TABAME_SETTINGS_PATH = None
TABAME_SETTINGS_ERROR = None
TABAME_CATEGORIES = []
TABAME_BOOKMARKS = []

# ---------------------------------------------------------------- protocol --

OUTPUT_LOCK = threading.Lock()

def send(frame):
    with OUTPUT_LOCK:
        sys.stdout.write(json.dumps(frame) + "\n")
        sys.stdout.flush()

def log(*a):
    print(*a, file=sys.stderr, flush=True)

# -------------------------------------------------------------------- data --

def default_data():
    return {
        "categories": [{"id": "uncategorized", "name": "Uncategorized", "color": "#8A8F98"}],
        "bookmarks": [],
    }

def load_data():
    if os.path.exists(DATA_FILE):
        try:
            with open(DATA_FILE, "r", encoding="utf-8") as f:
                d = json.load(f)
            if not isinstance(d, dict):
                raise ValueError("bookmark data must be an object")
            d.setdefault("categories", [])
            d.setdefault("bookmarks", [])
            if not any(c.get("id") == "uncategorized" for c in d["categories"]):
                d["categories"].insert(0, {"id": "uncategorized", "name": "Uncategorized", "color": "#8A8F98"})
            return d
        except Exception as e:
            log("load error:", e)
    return default_data()

def save_data():
    payload = json.dumps(DATA, indent=2, ensure_ascii=False)
    tmp = DATA_FILE + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(payload)
            f.flush()
            os.fsync(f.fileno())
        try:
            os.replace(tmp, DATA_FILE)
            return
        except OSError as replace_error:
            # Some Windows readers keep the destination open without delete
            # sharing. Direct writes are still allowed, so fall back after
            # staging the complete payload above.
            log("atomic save unavailable, using direct write:", replace_error)
        with open(DATA_FILE, "w", encoding="utf-8") as f:
            f.write(payload)
            f.flush()
            os.fsync(f.fileno())
        try:
            os.remove(tmp)
        except OSError:
            pass
    except Exception as e:
        log("save error:", e)

DATA = load_data()

def _decode_json_setting(value, default):
    if value is None:
        return default
    if isinstance(value, str):
        try:
            return json.loads(value)
        except (TypeError, json.JSONDecodeError):
            return default
    return value

def _tabame_settings_candidates():
    candidates = []
    override = os.environ.get("TABAME_SETTINGS_PATH", "").strip()
    if override:
        candidates.append(override)

    local_app_data = os.environ.get("LOCALAPPDATA", "").strip()
    if not local_app_data:
        local_app_data = os.path.join(os.path.expanduser("~"), "AppData", "Local")
    tabame_root = os.path.join(local_app_data, "Tabame")
    candidates.extend([
        os.path.join(tabame_root, "settings", "settings.json"),
        os.path.join(tabame_root, "settings", "debug", "settings.json"),
        os.path.join(tabame_root, "settings.json"),
    ])

    unique = []
    seen = set()
    for candidate in candidates:
        normalized = os.path.normcase(os.path.abspath(candidate))
        if normalized not in seen:
            seen.add(normalized)
            unique.append(candidate)
    return unique

def _settings_file_signature(path):
    try:
        stat = os.stat(path)
        return (path, stat.st_mtime_ns, stat.st_size)
    except OSError:
        return None

def _stable_tabame_id(prefix, value):
    digest = hashlib.sha1(value.encode("utf-8")).hexdigest()[:12]
    return f"{prefix}{digest}"

def _tabame_type(value):
    # Use the same classification as quick-add, but keep this wrapper named
    # separately so settings parsing remains explicit at the call site.
    return detect_type(value)

def _build_tabame_data(groups):
    categories = []
    bookmarks = []
    category_ids = set()

    for group_index, raw_group in enumerate(groups):
        group = _decode_json_setting(raw_group, raw_group)
        if not isinstance(group, dict):
            continue
        group_name = str(group.get("title") or "Uncategorized").strip() or "Uncategorized"
        category_key = group_name
        category_id = _stable_tabame_id(TABAME_CATEGORY_PREFIX, category_key)
        if category_id in category_ids:
            category_id = _stable_tabame_id(
                TABAME_CATEGORY_PREFIX,
                f"{category_key}\0{group_index}",
            )
        category_ids.add(category_id)
        categories.append({
            "id": category_id,
            "name": f"Tabame / {group_name}",
            "color": "#63A0EA",
            "_source": "tabame",
        })

        raw_bookmarks = _decode_json_setting(group.get("projects"), [])
        if not isinstance(raw_bookmarks, list):
            continue
        for bookmark_index, raw_bookmark in enumerate(raw_bookmarks):
            bookmark = _decode_json_setting(raw_bookmark, raw_bookmark)
            if not isinstance(bookmark, dict):
                continue
            value = str(bookmark.get("stringToExecute") or "").strip()
            if not value:
                continue
            bookmark_type = _tabame_type(value)
            name = str(bookmark.get("title") or "").strip() or derive_name(value, bookmark_type)
            link_value = normalize_link(value) if bookmark_type == "link" else value
            bookmark_id = _stable_tabame_id(
                TABAME_BOOKMARK_PREFIX,
                f"{group_name}\0{name}\0{value}\0{bookmark_index}",
            )
            bookmarks.append({
                "id": bookmark_id,
                "type": bookmark_type,
                "name": name,
                "categoryId": category_id,
                "tags": [],
                "url": link_value if bookmark_type == "link" else "",
                "path": value if bookmark_type == "file" else "",
                "command": value if bookmark_type == "command" else "",
                "variables": [
                    {"name": variable, "type": "text"}
                    for variable in dict.fromkeys(VAR_RE.findall(value))
                ] if bookmark_type == "command" else [],
                "usedCount": 0,
                "_source": "tabame",
                "_source_group": group_name,
                "emoji": str(bookmark.get("emoji") or ""),
                "preferInputIcon": bool(bookmark.get("preferInputIcon", False)),
            })
    return categories, bookmarks

def refresh_tabame_bookmarks(force=False):
    global TABAME_SETTINGS_SIGNATURES, TABAME_SETTINGS_PATH, TABAME_SETTINGS_ERROR
    global TABAME_CATEGORIES, TABAME_BOOKMARKS

    candidates = _tabame_settings_candidates()
    signatures = tuple(
        signature for signature in (_settings_file_signature(path) for path in candidates)
        if signature is not None
    )
    if not force and signatures == TABAME_SETTINGS_SIGNATURES:
        return False

    valid_sources = []
    errors = []
    for path in candidates:
        signature = _settings_file_signature(path)
        if signature is None:
            continue
        try:
            with open(path, "r", encoding="utf-8") as f:
                settings = json.load(f)
            projects = _decode_json_setting(settings.get("flutter.projects"), None)
            if isinstance(projects, list):
                valid_sources.append((signature[1], path, projects))
            else:
                errors.append(f"{path}: flutter.projects is missing or invalid")
        except Exception as error:
            errors.append(f"{path}: {error}")

    previous_category_ids = {c.get("id") for c in TABAME_CATEGORIES}
    if valid_sources:
        override = os.path.normcase(os.path.abspath(os.environ.get("TABAME_SETTINGS_PATH", "").strip()))
        override_sources = [
            source for source in valid_sources
            if os.path.normcase(os.path.abspath(source[1])) == override
        ] if override else []
        _, source_path, groups = max(override_sources or valid_sources, key=lambda source: source[0])
        categories, bookmarks = _build_tabame_data(groups)
        TABAME_SETTINGS_PATH = source_path
        TABAME_SETTINGS_ERROR = None
        TABAME_CATEGORIES = categories
        TABAME_BOOKMARKS = bookmarks
    else:
        TABAME_SETTINGS_PATH = None
        TABAME_SETTINGS_ERROR = "; ".join(errors) if errors else "Tabame settings.json was not found"
        TABAME_CATEGORIES = []
        TABAME_BOOKMARKS = []
        if errors:
            log("Tabame bookmark load error:", TABAME_SETTINGS_ERROR)

    TABAME_SETTINGS_SIGNATURES = signatures
    if "STATE" in globals():
        current_category_ids = {c.get("id") for c in TABAME_CATEGORIES}
        for category_id in current_category_ids:
            STATE["expanded"].add(category_id)
        for category_id in previous_category_ids - current_category_ids:
            STATE["expanded"].discard(category_id)
    return True

def all_categories():
    return DATA["categories"] + TABAME_CATEGORIES

def all_bookmarks():
    return DATA["bookmarks"] + TABAME_BOOKMARKS

def is_tabame_bookmark(bookmark):
    return bookmark.get("_source") == "tabame"

def is_tabame_category(category):
    return category.get("_source") == "tabame"

def new_id(prefix):
    return f"{prefix}_{uuid.uuid4().hex[:10]}"

def cat_by_id(cid):
    for c in all_categories():
        if c["id"] == cid:
            return c
    return None

def local_cat_by_id(cid):
    for c in DATA["categories"]:
        if c["id"] == cid:
            return c
    return None

def cat_name(cid):
    c = cat_by_id(cid)
    return c["name"] if c else "Uncategorized"

def bm_by_id(bid):
    for b in all_bookmarks():
        if b["id"] == bid:
            return b
    return None

def bookmarks_in(cid):
    return [b for b in all_bookmarks() if b.get("categoryId") == cid]

def sorted_categories():
    return sorted(
        all_categories(),
        key=lambda c: (
            is_tabame_category(c),
            c["id"] != "uncategorized",
            c["name"].lower(),
        ),
    )

def sorted_local_categories():
    return sorted(DATA["categories"], key=lambda c: (c["id"] != "uncategorized", c["name"].lower()))

# ------------------------------------------------------------------- state --

STATE = {
    "page_id": "bookmarks:home",
    "route_stack": ["bookmarks:home"],
    "expanded": set(c["id"] for c in DATA["categories"]),
    "editing_id": None,
    "form_prefill": {},
    "run_target": None,
    "run_force_folder": False,
    "pending_quickadd": None,
    "pending_catadd": None,
    "quickadd_awaiting_new_category": False,
    "last_query": "",
    "job": None,
}

TABAME_WATCH_INTERVAL = 1.0
TABAME_WATCH_STOP = threading.Event()
TABAME_WATCH_THREAD = None

def render_after_tabame_refresh():
    page_id = STATE.get("page_id")
    if page_id == "bookmarks:categories":
        render_categories_manage(0)
        return
    if page_id != "bookmarks:home":
        return
    if STATE.get("pending_quickadd") or STATE.get("pending_catadd"):
        return
    if STATE.get("quickadd_awaiting_new_category") or STATE.get("editing_id"):
        return
    query = STATE.get("last_query", "")
    render_search(0, query) if query else render_home(0)

def tabame_settings_watcher():
    while not TABAME_WATCH_STOP.wait(TABAME_WATCH_INTERVAL):
        try:
            if refresh_tabame_bookmarks():
                render_after_tabame_refresh()
        except Exception as error:
            log("Tabame bookmark watcher error:", repr(error))

def start_tabame_settings_watcher():
    global TABAME_WATCH_THREAD
    if TABAME_WATCH_THREAD is None:
        TABAME_WATCH_THREAD = threading.Thread(
            target=tabame_settings_watcher,
            name="tabame-bookmark-watcher",
            daemon=True,
        )
        TABAME_WATCH_THREAD.start()

def go(page_id):
    STATE["route_stack"].append(page_id)
    STATE["page_id"] = page_id
    send({"type": "command", "command": "setQuery", "text": ""})

# ------------------------------------------------------------ quick parsing --

QUOTED_RE = re.compile(r'"((?:\\.|[^"\\])*)"')

def _unescape_quoted(s):
    return s.replace('\\"', '"').replace("\\\\", "\\")

def parse_quick_tokens(s):
    # Supports: add "name" "value" / add "value" — and, for values that
    # themselves contain double quotes (e.g. a command with "${var}"
    # segments), escape them as \" so the outer quoting stays unambiguous.
    s = s.strip()
    if not s:
        return []
    matches = QUOTED_RE.findall(s)
    if matches:
        return [_unescape_quoted(m) for m in matches[:2]]
    return [s]

def detect_type(value):
    v = value.strip()
    if re.match(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://', v) or v.lower().startswith("www."):
        return "link"
    if os.path.exists(v):
        return "file"
    return "command"

def normalize_link(v):
    v = v.strip()
    if not re.match(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://', v):
        return "https://" + v
    return v

def derive_name(value, vtype):
    v = value.strip()
    if vtype == "link":
        try:
            netloc = urlparse(v if "://" in v else "http://" + v).netloc
            return netloc or v[:40]
        except Exception:
            return v[:40]
    if vtype == "file":
        base = os.path.basename(v.rstrip("\\/"))
        return base or v[:40]
    first = v.split()[0] if v.split() else v
    return (first[:30] + "…") if len(first) > 30 else (first or "Command")

# ---------------------------------------------------------- item / actions --

def add_tabame_status(frame):
    if TABAME_SETTINGS_ERROR:
        frame["banners"] = [{
            "id": "tabame-settings-error",
            "style": "warning",
            "title": "Tabame bookmarks unavailable",
            "message": TABAME_SETTINGS_ERROR,
            "dismissible": False,
        }]

def bookmark_subtitle(bm):
    if bm["type"] == "link":
        return bm.get("url", "")
    if bm["type"] == "file":
        return bm.get("path", "")
    return bm.get("command", "")

def bookmark_preview_md(bm):
    lines = [f"## {bm['name']}", f"**Type:** {TYPE_LABEL[bm['type']]}", f"**Category:** {cat_name(bm.get('categoryId'))}"]
    if is_tabame_bookmark(bm):
        lines.append("**Source:** Live Tabame settings")
    if bm["type"] == "link":
        lines.append(f"**URL:** {bm.get('url', '')}")
    elif bm["type"] == "file":
        lines.append(f"**Path:** {bm.get('path', '')}")
    else:
        lines.append(f"**Command:**\n```\n{bm.get('command', '')}\n```")
        if bm.get("variables"):
            varlist = ", ".join(f"`{v['name']}` ({v['type']})" for v in bm["variables"])
            lines.append(f"**Variables:** {varlist}")
        if bm.get("defaultWorkdir"):
            lines.append(f"**Default folder:** {bm['defaultWorkdir']}")
    if bm.get("tags"):
        lines.append(f"**Tags:** {', '.join(bm['tags'])}")
    if bm.get("usedCount"):
        lines.append(f"**Used:** {bm['usedCount']} time(s)")
    return "\n\n".join(lines)

def bookmark_actions(bm):
    acts = []
    if bm["type"] == "link":
        acts.append({"id": "copy_link", "title": "Copy Link", "icon": "copy"})
    elif bm["type"] == "file":
        acts += [
            {"id": "open_folder", "title": "Open Containing Folder", "icon": "folder"},
            {"id": "copy_path", "title": "Copy Path", "icon": "copy"},
        ]
    else:
        acts += [
            {"id": "run_in_folder", "title": "Run in Folder…", "icon": "folder"},
            {"id": "copy_command", "title": "Copy Command", "icon": "code"},
        ]
    if is_tabame_bookmark(bm):
        return acts
    acts += [
        {"id": "edit", "title": "Edit", "icon": "edit"},
        {
            "id": "move", "title": "Move to Category", "icon": "folder",
            "parameters": [{
                "id": "category", "type": "dropdown", "label": "Category", "required": True,
                "value": bm.get("categoryId", "uncategorized"),
                "options": [{"value": c["id"], "label": c["name"]} for c in sorted_local_categories()],
            }],
        },
        {
            "id": "delete", "title": "Delete", "icon": "trash", "destructive": True,
            "confirm": {"title": f"Delete “{bm['name']}”?", "message": "This cannot be undone.", "confirmLabel": "Delete"},
        },
    ]
    return acts

def bookmark_item(bm, depth=None, subtitle_with_category=False):
    sub = bookmark_subtitle(bm)
    if subtitle_with_category:
        sub = f"{cat_name(bm.get('categoryId'))} · {sub}"
    if len(sub) > 80:
        sub = sub[:77] + "…"
    accessories = []
    if is_tabame_bookmark(bm):
        accessories.append({"text": "LIVE", "icon": "sync"})
    if bm["type"] == "command" and bm.get("variables"):
        n = len(bm["variables"])
        accessories.append({"text": f"{n} var" + ("s" if n != 1 else ""), "icon": "tag"})
    if bm.get("usedCount"):
        accessories.append({"text": str(bm["usedCount"]), "icon": "run"})
    item = {
        "id": f"bm:{bm['id']}",
        "title": bm["name"],
        "subtitle": sub,
        "icon": TYPE_ICON[bm["type"]],
        "accessories": accessories,
        "actions": bookmark_actions(bm),
        "preview": {"markdown": bookmark_preview_md(bm)},
    }
    if depth is not None:
        item["depth"] = depth
    return item

def category_actions(cat):
    if is_tabame_category(cat):
        return []
    acts = [
        {"id": "add_here", "title": "Add Bookmark Here", "icon": "add"},
        {
            "id": "rename", "title": "Rename Category", "icon": "edit",
            "parameters": [{"id": "name", "type": "text", "label": "Name", "required": True, "value": cat["name"]}],
        },
    ]
    if cat["id"] != "uncategorized":
        acts.append({
            "id": "delete_category", "title": "Delete Category", "icon": "trash", "destructive": True,
            "confirm": {
                "title": f"Delete “{cat['name']}”?",
                "message": "Bookmarks inside move to Uncategorized.",
                "confirmLabel": "Delete",
            },
        })
    return acts

def category_node(cat, expanded):
    n = len(bookmarks_in(cat["id"]))
    return {
        "id": f"cat:{cat['id']}",
        "title": cat["name"],
        "subtitle": f"{n} bookmark{'s' if n != 1 else ''}",
        "icon": "folder",
        "depth": 0,
        "expanded": expanded,
        "actions": category_actions(cat),
    }

# -------------------------------------------------------------------- home --

def render_home(rev, history="none"):
    refresh_tabame_bookmarks()
    items = []
    for c in sorted_categories():
        expanded = c["id"] in STATE["expanded"]
        items.append(category_node(c, expanded))
        if expanded:
            for b in sorted(bookmarks_in(c["id"]), key=lambda b: b["name"].lower()):
                items.append(bookmark_item(b, depth=1))
    frame = {
        "type": "render", "rev": rev, "view": "tree",
        "page": {"id": "bookmarks:home", "title": "Bookmarks", "history": history},
        "placeholder": 'Search, or type add "name" "url"…',
        "floatingAction": {"id": "add", "title": "Add Bookmark", "icon": "add"},
        "actions": [
            {
                "id": "new_category", "title": "New Category", "icon": "folder",
                "parameters": [{"id": "name", "type": "text", "label": "Category name", "required": True}],
            },
            {"id": "manage_categories", "title": "Manage Categories", "icon": "list"},
            {"id": "refresh_tabame", "title": "Refresh Tabame Bookmarks", "icon": "refresh"},
        ],
        "items": items,
    }
    if not all_bookmarks():
        frame["empty"] = {
            "icon": "bookmark", "title": "No bookmarks yet",
            "hint": 'Add your first link, file, or command',
            "action": {"id": "add", "title": "Add Bookmark", "icon": "add"},
        }
    add_tabame_status(frame)
    send(frame)
    STATE["page_id"] = "bookmarks:home"

# ------------------------------------------------------------------ search --

def render_search(rev, text):
    refresh_tabame_bookmarks()
    q = text.lower()

    def matches(b):
        hay = " ".join([
            b.get("name", ""), b.get("url", ""), b.get("path", ""), b.get("command", ""),
            cat_name(b.get("categoryId")), " ".join(b.get("tags", [])),
        ]).lower()
        return q in hay

    results = [b for b in all_bookmarks() if matches(b)]
    results.sort(key=lambda b: (not b["name"].lower().startswith(q), b["name"].lower()))
    items = [bookmark_item(b, depth=None, subtitle_with_category=True) for b in results]
    frame = {
        "type": "render", "rev": rev, "view": "list",
        "page": {"id": "bookmarks:search", "title": "Search", "history": "none"},
        "preview": {"enabled": True, "wide": False},
        "emptyText": f'No bookmarks match "{text}"',
        "actions": [{"id": "refresh_tabame", "title": "Refresh Tabame Bookmarks", "icon": "refresh"}],
        "items": items,
    }
    add_tabame_status(frame)
    send(frame)
    STATE["page_id"] = "bookmarks:home"  # search is a live filter, not a pushed page

# --------------------------------------------------------------- quick add --

def render_category_picker(rev):
    refresh_tabame_bookmarks()
    pending = STATE.get("pending_quickadd")
    if not pending:
        render_home(rev)
        return
    name = pending["name"]
    cats = sorted_local_categories()
    items = []
    for c in cats:
        count = sum(1 for b in DATA["bookmarks"] if b.get("categoryId") == c["id"])
        items.append({
            "id": f"quickaddcat:{c['id']}", "title": c["name"],
            "subtitle": f'{count} bookmark{"s" if count != 1 else ""}',
            "icon": "folder",
        })
    items.append({
        "id": "quickaddcat:new", "title": "+ New Category",
        "subtitle": "Create a new category for this bookmark", "icon": "add",
    })
    send({
        "type": "render", "rev": rev, "view": "list",
        "page": {"id": "bookmarks:quickadd", "title": f'Add “{name}” to…', "history": "none"},
        "placeholder": "Select a category",
        "items": items,
    })

def render_add_preview(rev, arg_text):
    tokens = parse_quick_tokens(arg_text)
    if not tokens or not tokens[-1].strip():
        send({
            "type": "render", "rev": rev, "view": "list",
            "page": {"id": "bookmarks:quickadd", "title": "Add Bookmark", "history": "none"},
            "placeholder": 'add "name" "url, path, or command"',
            "items": [{
                "id": "hint", "title": "Type a URL, file path, or command to add",
                "subtitle": 'e.g. add "GitHub" "https://github.com" — for commands with quotes, escape them as \\" or use the Add form',
                "icon": "bookmark",
            }],
        })
        STATE["pending_quickadd"] = None
        STATE["quickadd_awaiting_new_category"] = False
        return

    if len(tokens) >= 2:
        name, value = tokens[0].strip(), tokens[1].strip()
    else:
        value = tokens[0].strip()
        name = None

    vtype = detect_type(value)
    if vtype == "link":
        value = normalize_link(value)
    if not name:
        name = derive_name(value, vtype)

    variables = []
    if vtype == "command":
        variables = [{"name": v, "type": "text"} for v in dict.fromkeys(VAR_RE.findall(value))]

    STATE["pending_quickadd"] = {"name": name, "value": value, "type": vtype, "variables": variables}
    STATE["quickadd_awaiting_new_category"] = False
    render_category_picker(rev)

def render_quickadd_newcat_prompt(rev, name_text):
    pending = STATE.get("pending_quickadd")
    if not pending:
        STATE["quickadd_awaiting_new_category"] = False
        render_home(rev)
        return
    name_text = name_text.strip()
    items = []
    if name_text:
        items.append({
            "id": "quickaddcat_confirmnew",
            "title": f'Create “{name_text}” and add bookmark here',
            "icon": "folder",
        })
    else:
        items.append({
            "id": "hint", "title": "Type a name for the new category",
            "subtitle": f'Bookmark “{pending["name"]}” will be added to it',
            "icon": "folder",
        })
    items.append({"id": "quickaddcat_cancel", "title": "← Back to categories", "icon": "back"})
    send({
        "type": "render", "rev": rev, "view": "list",
        "page": {"id": "bookmarks:quickadd", "title": "New Category", "history": "none"},
        "placeholder": "Type a category name",
        "items": items,
    })

def commit_quick_add(category_id="uncategorized"):
    pending = STATE.get("pending_quickadd")
    if not pending:
        render_home(0)
        return
    if not local_cat_by_id(category_id):
        category_id = "uncategorized"
    bm = {
        "id": new_id("bm"), "type": pending["type"], "name": pending["name"],
        "categoryId": category_id, "tags": [],
        "url": pending["value"] if pending["type"] == "link" else "",
        "path": pending["value"] if pending["type"] == "file" else "",
        "command": pending["value"] if pending["type"] == "command" else "",
        "variables": pending.get("variables", []),
        "createdAt": datetime.now().isoformat(timespec="seconds"), "usedCount": 0,
    }
    DATA["bookmarks"].append(bm)
    save_data()
    STATE["pending_quickadd"] = None
    STATE["quickadd_awaiting_new_category"] = False
    send({"type": "command", "command": "toast", "text": f'Added “{bm["name"]}” to {cat_name(category_id)}'})
    render_home(0)

def render_catadd_preview(rev, arg_text):
    tokens = parse_quick_tokens(arg_text)
    name = tokens[0].strip() if tokens else ""
    if not name:
        send({
            "type": "render", "rev": rev, "view": "list",
            "page": {"id": "bookmarks:quickadd", "title": "New Category", "history": "none"},
            "items": [{"id": "hint", "title": "Type a category name to create", "subtitle": 'e.g. cat add "Dev Tools"', "icon": "folder"}],
        })
        STATE["pending_catadd"] = None
        return
    STATE["pending_catadd"] = name
    send({
        "type": "render", "rev": rev, "view": "list",
        "page": {"id": "bookmarks:quickadd", "title": "New Category", "history": "none"},
        "placeholder": "Press Enter to create",
        "items": [{"id": "catadd", "title": f"Create category **{name}**", "icon": "folder"}],
    })

def commit_cat_add():
    pending = STATE.get("pending_catadd")
    if not pending:
        render_home(0)
        return
    cid = new_id("cat")
    DATA["categories"].append({"id": cid, "name": pending, "color": "#63A0EA"})
    STATE["expanded"].add(cid)
    save_data()
    STATE["pending_catadd"] = None
    send({"type": "command", "command": "toast", "text": f'Created category “{pending}”'})
    render_home(0)

def route_query(rev, text):
    text = text.strip()
    STATE["last_query"] = text
    if STATE.get("quickadd_awaiting_new_category"):
        render_quickadd_newcat_prompt(rev, text)
        return
    if not text:
        render_home(rev)
        return
    m_cat = re.match(r'(?i)^cat(?:egory)?\s*add\s+(.*)$', text)
    if m_cat:
        render_catadd_preview(rev, m_cat.group(1))
        return
    m_add = re.match(r'(?i)^add\s+(.*)$', text)
    if m_add:
        render_add_preview(rev, m_add.group(1))
        return
    render_search(rev, text)

# ---------------------------------------------------------------- add form --

def variables_from_command(cmd):
    return list(dict.fromkeys(VAR_RE.findall(cmd or "")))

def render_form(rev, values=None, error=None, first=False):
    refresh_tabame_bookmarks()
    values = values or {}
    editing_id = STATE.get("editing_id")
    bm = bm_by_id(editing_id) if editing_id else None

    vtype = values["type"] if "type" in values else (bm["type"] if bm else "link")
    name_val = values["name"] if "name" in values else (bm["name"] if bm else "")
    cat_val = values["category"] if "category" in values else (
        bm.get("categoryId") if bm else STATE.get("form_prefill", {}).get("categoryId", "uncategorized"))
    if not local_cat_by_id(cat_val):
        cat_val = "uncategorized"
    url_val = values["url"] if "url" in values else (bm.get("url", "") if bm else "")
    path_val = values["path"] if "path" in values else (bm.get("path", "") if bm else "")
    cmd_val = values["command"] if "command" in values else (bm.get("command", "") if bm else "")
    tags_val = values["tags"] if "tags" in values else (bm.get("tags", []) if bm else [])

    fields = [
        {
            "id": "type", "type": "dropdown", "label": "Type", "value": vtype, "watch": True,
            "options": [
                {"value": "link", "label": "Link"},
                {"value": "file", "label": "File"},
                {"value": "command", "label": "Command"},
            ],
        },
        {"id": "name", "type": "text", "label": "Name", "value": name_val, "required": True, "placeholder": "My bookmark"},
        {
            "id": "category", "type": "dropdown", "label": "Category", "value": cat_val, "required": True,
            "options": [{"value": c["id"], "label": c["name"]} for c in sorted_local_categories()],
        },
        {
            "id": "url", "type": "text", "label": "URL", "value": url_val, "placeholder": "https://example.com",
            "visibleWhen": {"field": "type", "equals": "link"},
        },
        {"id": "path", "type": "filepicker", "label": "File", "value": path_val, "visibleWhen": {"field": "type", "equals": "file"}},
        {
            "id": "command", "type": "textarea", "label": "Command", "value": cmd_val, "watch": True,
            "description": "Use ${name} for values filled in at run time, e.g. ${fileName}. "
                            "Wrap ${var} in quotes yourself if the value may contain spaces.",
            "visibleWhen": {"field": "type", "equals": "command"},
        },
        {"id": "tags", "type": "tags", "label": "Tags", "value": tags_val},
    ]

    sections = []
    if vtype == "command":
        varnames = variables_from_command(cmd_val)
        if varnames:
            sections.append({
                "id": "variables", "title": "Command Variables", "collapsible": True,
                "description": "Detected from ${...} in the command above",
            })
            existing_types = {v["name"]: v.get("type", "text") for v in (bm.get("variables", []) if bm else [])}
            for vn in varnames:
                fid = f"vartype__{vn}"
                cur = values[fid] if fid in values else existing_types.get(vn, "text")
                fields.append({
                    "id": fid, "type": "dropdown", "label": f"${{{vn}}} input", "value": cur, "section": "variables",
                    "options": [{"value": "text", "label": "Text"}, {"value": "file", "label": "File picker"}],
                })

    send({
        "type": "render", "rev": rev, "view": "form",
        "page": {
            "id": "bookmarks:edit" if editing_id else "bookmarks:add",
            "title": "Edit Bookmark" if editing_id else "New Bookmark",
            "history": "push" if first else "none",
            "preserveState": True,
        },
        "form": {
            "title": "Edit Bookmark" if editing_id else "New Bookmark",
            "error": error,
            "sections": sections,
            "submitLabel": "Save" if editing_id else "Add",
            "fields": fields,
        },
    })

def handle_form_submit(values):
    refresh_tabame_bookmarks()
    vtype = values.get("type", "link")
    name = (values.get("name") or "").strip()
    category = values.get("category") or "uncategorized"

    error = None
    if not name:
        error = "Name is required."
    elif vtype == "link" and not (values.get("url") or "").strip():
        error = "URL is required for a link."
    elif vtype == "file" and not (values.get("path") or "").strip():
        error = "Choose a file."
    elif vtype == "command" and not (values.get("command") or "").strip():
        error = "Command is required."
    if error:
        render_form(0, values=values, error=error, first=False)
        return

    editing_id = STATE.get("editing_id")
    bm = bm_by_id(editing_id) if editing_id else None
    if bm and is_tabame_bookmark(bm):
        STATE["editing_id"] = None
        send({"type": "command", "command": "toast", "text": "Tabame bookmarks are read-only", "style": "info"})
        render_home(0, history="replace")
        return
    if bm is None:
        bm = {"id": new_id("bm"), "createdAt": datetime.now().isoformat(timespec="seconds"), "usedCount": 0}
        DATA["bookmarks"].append(bm)

    bm["type"] = vtype
    bm["name"] = name
    bm["categoryId"] = category if local_cat_by_id(category) else "uncategorized"
    bm["tags"] = values.get("tags") or []

    url_val = (values.get("url") or "").strip()
    if vtype == "link" and url_val:
        url_val = normalize_link(url_val)
    bm["url"] = url_val if vtype == "link" else ""
    bm["path"] = (values.get("path") or "").strip() if vtype == "file" else ""

    cmd_val = (values.get("command") or "").strip() if vtype == "command" else ""
    bm["command"] = cmd_val
    if vtype == "command":
        varnames = variables_from_command(cmd_val)
        bm["variables"] = [{"name": vn, "type": values.get(f"vartype__{vn}", "text")} for vn in varnames]
    else:
        bm["variables"] = []

    save_data()
    STATE["editing_id"] = None
    send({"type": "command", "command": "toast", "text": f'Saved “{name}”'})
    render_home(0, history="replace")

# ------------------------------------------------------------ run / execute --

def build_command(template, values):
    def repl(m):
        return values.get(m.group(1), "")
    return VAR_RE.sub(repl, template or "")

def render_run_form(rev, bm, first=False, force_folder=False, error=None):
    STATE["run_force_folder"] = force_folder
    fields = []
    for v in bm.get("variables", []):
        fid = f"var__{v['name']}"
        fields.append({
            "id": fid,
            "type": "filepicker" if v.get("type") == "file" else "text",
            "label": v["name"],
            "value": v.get("default", ""),
        })
    fields.append({
        "id": "workdir", "type": "folderpicker",
        "label": "Run in folder" + (" (required)" if force_folder else " (optional)"),
        "value": bm.get("defaultWorkdir", ""),
        "required": force_folder,
    })
    fields.append({"id": "remember_workdir", "type": "checkbox", "label": "Remember this folder for next time", "value": False})

    send({
        "type": "render", "rev": rev, "view": "form",
        "page": {
            "id": "bookmarks:run", "title": f"Run “{bm['name']}”",
            "history": "push" if first else "none", "preserveState": True,
        },
        "form": {
            "title": f"Run “{bm['name']}”",
            "error": error,
            "submitLabel": "Run",
            "fields": fields,
        },
    })

def handle_run_submit(values):
    refresh_tabame_bookmarks()
    bm = bm_by_id(STATE.get("run_target"))
    if not bm:
        render_home(0, history="replace")
        return
    force_folder = STATE.get("run_force_folder", False)
    workdir = (values.get("workdir") or "").strip() or None
    if force_folder and not workdir:
        render_run_form(0, bm, first=False, force_folder=True, error="Choose a folder to run in.")
        return
    if values.get("remember_workdir") and workdir and not is_tabame_bookmark(bm):
        bm["defaultWorkdir"] = workdir
        save_data()

    var_values = {v["name"]: values.get(f"var__{v['name']}", "") for v in bm.get("variables", [])}
    final_cmd = build_command(bm.get("command", ""), var_values)
    if not is_tabame_bookmark(bm):
        bm["usedCount"] = bm.get("usedCount", 0) + 1
        bm["lastUsedAt"] = datetime.now().isoformat(timespec="seconds")
        save_data()
    start_job(bm, final_cmd, workdir or bm.get("defaultWorkdir") or None)

def start_job(bm, command_str, workdir):
    old = STATE.get("job")
    if old and old.get("process") and old["process"].poll() is None:
        try:
            old["process"].terminate()
        except Exception:
            pass
    job = {
        "id": new_id("job"), "name": bm["name"], "command": command_str,
        "lines": [], "finished": False, "exit_code": None, "cwd": workdir, "process": None,
    }
    STATE["job"] = job
    go("bookmarks:running")
    render_running(0, job, first=True)
    threading.Thread(target=run_job_thread, args=(job, command_str, workdir), daemon=True).start()

def run_job_thread(job, command_str, workdir):
    try:
        proc = subprocess.Popen(
            command_str, shell=True, cwd=workdir or None,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1, encoding="utf-8", errors="replace",
        )
        job["process"] = proc
        for raw in iter(proc.stdout.readline, ""):
            line = raw.rstrip("\n")
            job["lines"].append({"id": str(len(job["lines"])), "text": line})
            if len(job["lines"]) > 2000:
                job["lines"] = job["lines"][-2000:]
            push_running_update(job)
        try:
            proc.stdout.close()
        except Exception:
            pass
        job["exit_code"] = proc.wait()
    except Exception as e:
        job["lines"].append({"id": str(len(job["lines"])), "level": "error", "text": f"Failed to start: {e}"})
        job["exit_code"] = -1

    job["finished"] = True
    level = "success" if job.get("exit_code") == 0 else "error"
    job["lines"].append({"id": str(len(job["lines"])), "level": level, "text": f"— exited with code {job.get('exit_code')} —"})
    push_running_update(job, final=True)
    if not (STATE.get("job") and STATE["job"]["id"] == job["id"] and STATE.get("page_id") == "bookmarks:running"):
        send({"type": "command", "command": "notify", "title": job["name"], "text": f"Finished (exit {job.get('exit_code')})."})

def push_running_update(job, final=False):
    if STATE.get("job") and STATE["job"]["id"] == job["id"] and STATE.get("page_id") == "bookmarks:running":
        render_running(0, job, first=False)

def render_running(rev, job, first=False):
    lines = job["lines"][-800:]
    fa = None if job.get("finished") else {"id": "stop", "title": "Stop", "icon": "close", "destructive": True}
    frame = {
        "type": "render", "rev": rev, "view": "log",
        "page": {
            "id": "bookmarks:running", "title": job.get("name", "Running"),
            "history": "push" if first else "none", "preserveState": True,
        },
        "log": {"follow": True, "wrap": False, "lines": lines},
        "loading": (not job.get("finished")) and not lines,
        "loadingText": "Starting…",
        "actions": [
            {"id": "copy_output", "title": "Copy Output", "icon": "copy"},
            {"id": "copy_command", "title": "Copy Command", "icon": "code"},
        ],
    }
    if fa:
        frame["floatingAction"] = fa
    send(frame)

def open_bookmark(bm):
    refresh_tabame_bookmarks()
    if not is_tabame_bookmark(bm):
        bm["usedCount"] = bm.get("usedCount", 0) + 1
        bm["lastUsedAt"] = datetime.now().isoformat(timespec="seconds")
        save_data()
    if bm["type"] == "link":
        send({"type": "command", "command": "open", "url": bm.get("url", "")})
        send({"type": "command", "command": "hide"})
    elif bm["type"] == "file":
        send({"type": "command", "command": "open", "path": bm.get("path", "")})
        send({"type": "command", "command": "hide"})
    else:
        if bm.get("variables"):
            STATE["run_target"] = bm["id"]
            go("bookmarks:run")
            render_run_form(0, bm, first=True, force_folder=False)
        else:
            start_job(bm, bm.get("command", ""), bm.get("defaultWorkdir") or None)

# ------------------------------------------------------------- categories --

def render_categories_manage(rev, first=False):
    refresh_tabame_bookmarks()
    items = []
    for c in sorted_categories():
        n = len(bookmarks_in(c["id"]))
        items.append({
            "id": f"catm:{c['id']}", "title": c["name"],
            "subtitle": f"{n} bookmark{'s' if n != 1 else ''}",
            "icon": "folder", "actions": category_actions(c),
        })
    frame = {
        "type": "render", "rev": rev, "view": "list",
        "page": {"id": "bookmarks:categories", "title": "Categories", "history": "push" if first else "none"},
        "actions": [{
            "id": "new_category", "title": "New Category", "icon": "folder",
            "parameters": [{"id": "name", "type": "text", "label": "Category name", "required": True}],
        }, {"id": "refresh_tabame", "title": "Refresh Tabame Bookmarks", "icon": "refresh"}],
        "emptyText": "No categories",
        "items": items,
    }
    add_tabame_status(frame)
    send(frame)

# ------------------------------------------------------------------- back --

def resolve(page_id, rev):
    if page_id == "bookmarks:home":
        render_home(rev, history="replace")
    elif page_id in ("bookmarks:add", "bookmarks:edit"):
        render_form(rev, first=True)
    elif page_id == "bookmarks:categories":
        render_categories_manage(rev, first=True)
    elif page_id == "bookmarks:run":
        bm = bm_by_id(STATE.get("run_target"))
        if bm:
            render_run_form(rev, bm, first=True, force_folder=STATE.get("run_force_folder", False))
        else:
            render_home(rev, history="replace")
    elif page_id == "bookmarks:running":
        job = STATE.get("job")
        if job:
            render_running(rev, job, first=True)
        else:
            render_home(rev, history="replace")
    else:
        render_home(rev, history="replace")

def handle_back(msg):
    target = msg.get("toPageId")
    stack = STATE["route_stack"]
    if target and target in stack:
        STATE["route_stack"] = stack[: stack.index(target) + 1]
    elif len(stack) > 1:
        stack.pop()
        target = stack[-1]
    else:
        target = "bookmarks:home"
        STATE["route_stack"] = ["bookmarks:home"]
    STATE["page_id"] = target
    if target != "bookmarks:edit":
        STATE["editing_id"] = None
    send({"type": "command", "command": "setQuery", "text": ""})
    resolve(target, 0)

def handle_navigate(msg):
    target = msg.get("targetPageId", "bookmarks:home")
    stack = STATE["route_stack"]
    if target in stack:
        STATE["route_stack"] = stack[: stack.index(target) + 1]
    else:
        stack.append(target)
    STATE["page_id"] = target
    send({"type": "command", "command": "setQuery", "text": ""})
    resolve(target, 0)

def handle_toggle(msg):
    tid = msg.get("id", "")
    if not tid.startswith("cat:"):
        return
    cid = tid[4:]
    want = msg.get("expanded")
    if want is None:
        want = cid not in STATE["expanded"]
    if want:
        STATE["expanded"].add(cid)
    else:
        STATE["expanded"].discard(cid)
    render_home(0)

# ------------------------------------------------------------------ action --

def refresh_after_category_change(source_page):
    if source_page == "bookmarks:categories":
        render_categories_manage(0)
    else:
        render_home(0)

def refresh_after_bookmark_change(page_id):
    if page_id == "bookmarks:home":
        render_search(0, STATE.get("last_query", "")) if STATE.get("last_query") else render_home(0)
    else:
        render_home(0)

def handle_action(msg):
    refresh_tabame_bookmarks()
    item_id = msg.get("id", "")
    action = msg.get("action", "default")
    params = msg.get("parameters") or {}
    page_id = STATE.get("page_id")

    if item_id.startswith("quickaddcat:") and action == "default":
        sel = item_id[len("quickaddcat:"):]
        if sel == "new":
            STATE["quickadd_awaiting_new_category"] = True
            send({"type": "command", "command": "setQuery", "text": ""})
            return
        commit_quick_add(sel)
        return
    if item_id == "quickaddcat_cancel" and action == "default":
        STATE["quickadd_awaiting_new_category"] = False
        render_category_picker(0)
        return
    if item_id == "quickaddcat_confirmnew" and action == "default":
        name_text = STATE.get("last_query", "").strip()
        if not name_text:
            return
        cid = new_id("cat")
        DATA["categories"].append({"id": cid, "name": name_text, "color": "#63A0EA"})
        STATE["expanded"].add(cid)
        save_data()
        STATE["quickadd_awaiting_new_category"] = False
        commit_quick_add(cid)
        return
    if item_id == "catadd" and action == "default":
        commit_cat_add()
        return

    if item_id == "":
        if action == "add":
            STATE["editing_id"] = None
            STATE["form_prefill"] = {}
            go("bookmarks:add")
            render_form(0, first=True)
        elif action == "new_category":
            name = (params.get("name") or "").strip()
            if name:
                cid = new_id("cat")
                DATA["categories"].append({"id": cid, "name": name, "color": "#63A0EA"})
                STATE["expanded"].add(cid)
                save_data()
                send({"type": "command", "command": "toast", "text": f'Created “{name}”'})
            refresh_after_category_change(page_id)
        elif action == "manage_categories":
            go("bookmarks:categories")
            render_categories_manage(0, first=True)
        elif action == "refresh_tabame":
            refresh_tabame_bookmarks(force=True)
            if TABAME_SETTINGS_ERROR:
                send({"type": "command", "command": "toast", "text": "Could not refresh Tabame bookmarks", "style": "error"})
            else:
                send({"type": "command", "command": "toast", "text": "Tabame bookmarks refreshed", "style": "info"})
            if page_id == "bookmarks:categories":
                render_categories_manage(0)
            elif STATE.get("last_query"):
                render_search(0, STATE["last_query"])
            else:
                render_home(0)
        elif action == "stop" and page_id == "bookmarks:running":
            job = STATE.get("job")
            if job and job.get("process") and job["process"].poll() is None:
                try:
                    job["process"].terminate()
                except Exception:
                    pass
            send({"type": "command", "command": "toast", "text": "Stopping…", "style": "info"})
        elif action == "copy_output" and page_id == "bookmarks:running":
            job = STATE.get("job")
            if job:
                text = "\n".join(l.get("text", "") for l in job["lines"])
                send({"type": "command", "command": "copy", "text": text})
        elif action == "copy_command" and page_id == "bookmarks:running":
            job = STATE.get("job")
            if job:
                send({"type": "command", "command": "copy", "text": job["command"]})
        return

    if item_id.startswith("cat:") or item_id.startswith("catm:"):
        cid = item_id.split(":", 1)[1]
        source_page = "bookmarks:categories" if item_id.startswith("catm:") else "bookmarks:home"
        cat = cat_by_id(cid)
        if not cat:
            refresh_after_category_change(source_page)
            return
        if is_tabame_category(cat) and (
            action in ("add_here", "rename", "delete_category")
            or (source_page == "bookmarks:categories" and action == "default")
        ):
            send({"type": "command", "command": "toast", "text": "Tabame categories are read-only", "style": "info"})
            return
        if action == "default":
            if source_page == "bookmarks:home":
                if cid in STATE["expanded"]:
                    STATE["expanded"].discard(cid)
                else:
                    STATE["expanded"].add(cid)
                render_home(0)
            else:
                STATE["editing_id"] = None
                STATE["form_prefill"] = {"categoryId": cid}
                go("bookmarks:add")
                render_form(0, first=True)
            return
        if action == "add_here":
            STATE["editing_id"] = None
            STATE["form_prefill"] = {"categoryId": cid}
            go("bookmarks:add")
            render_form(0, first=True)
            return
        if action == "rename":
            newname = (params.get("name") or "").strip()
            if newname:
                cat["name"] = newname
                save_data()
                send({"type": "command", "command": "toast", "text": "Renamed"})
            refresh_after_category_change(source_page)
            return
        if action == "delete_category":
            for b in DATA["bookmarks"]:
                if b.get("categoryId") == cid:
                    b["categoryId"] = "uncategorized"
            DATA["categories"] = [c for c in DATA["categories"] if c["id"] != cid]
            STATE["expanded"].discard(cid)
            save_data()
            send({"type": "command", "command": "toast", "text": "Category deleted"})
            refresh_after_category_change(source_page)
            return
        refresh_after_category_change(source_page)
        return

    if item_id.startswith("bm:"):
        bid = item_id[3:]
        bm = bm_by_id(bid)
        if not bm:
            refresh_after_bookmark_change(page_id)
            return
        if is_tabame_bookmark(bm) and action in ("edit", "delete", "move"):
            send({"type": "command", "command": "toast", "text": "Tabame bookmarks are read-only", "style": "info"})
            return
        if action == "default":
            open_bookmark(bm)
            return
        if action == "edit":
            STATE["editing_id"] = bid
            go("bookmarks:edit")
            render_form(0, first=True)
            return
        if action == "delete":
            DATA["bookmarks"] = [b for b in DATA["bookmarks"] if b["id"] != bid]
            save_data()
            send({"type": "command", "command": "toast", "text": "Deleted"})
            refresh_after_bookmark_change(page_id)
            return
        if action == "move":
            cid = params.get("category") or "uncategorized"
            bm["categoryId"] = cid if local_cat_by_id(cid) else "uncategorized"
            save_data()
            send({"type": "command", "command": "toast", "text": f"Moved to {cat_name(bm['categoryId'])}"})
            refresh_after_bookmark_change(page_id)
            return
        if action == "copy_link" and bm["type"] == "link":
            send({"type": "command", "command": "copy", "text": bm.get("url", "")})
            return
        if action == "copy_path" and bm["type"] == "file":
            send({"type": "command", "command": "copy", "text": bm.get("path", "")})
            return
        if action == "open_folder" and bm["type"] == "file":
            folder = os.path.dirname(bm.get("path", "")) or bm.get("path", "")
            send({"type": "command", "command": "open", "path": folder})
            return
        if action == "copy_command" and bm["type"] == "command":
            send({"type": "command", "command": "copy", "text": bm.get("command", "")})
            return
        if action == "run_in_folder" and bm["type"] == "command":
            STATE["run_target"] = bid
            go("bookmarks:run")
            render_run_form(0, bm, first=True, force_folder=True)
            return
        return

# --------------------------------------------------------------------- main --

def main():
    try:
        for raw in sys.stdin:
            raw = raw.strip()
            if not raw:
                continue
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                continue
            t = msg.get("type")
            try:
                if t == "close":
                    break
                elif t in ("init", "query"):
                    rev = msg.get("rev", 0)
                    text = msg.get("text", msg.get("query", ""))
                    route_query(rev, text)
                    start_tabame_settings_watcher()
                elif t == "action":
                    handle_action(msg)
                elif t == "submit":
                    values = msg.get("values", {})
                    page_id = STATE.get("page_id")
                    if page_id in ("bookmarks:add", "bookmarks:edit"):
                        handle_form_submit(values)
                    elif page_id == "bookmarks:run":
                        handle_run_submit(values)
                elif t == "change":
                    values = msg.get("values")
                    if values is None:
                        values = {k: v for k, v in msg.items() if k not in ("type", "id", "rev")}
                    if STATE.get("page_id") in ("bookmarks:add", "bookmarks:edit"):
                        render_form(0, values=values, first=False)
                elif t == "toggle":
                    handle_toggle(msg)
                elif t == "back":
                    handle_back(msg)
                elif t == "navigate":
                    handle_navigate(msg)
                elif t == "select":
                    pass
                elif t == "loadMore":
                    pass
            except Exception as e:
                log("error handling", t, repr(e))
                send({"type": "render", "rev": 0, "view": "detail", "detail": {"markdown": f"# Error\n\n```\n{e}\n```"}})
    finally:
        TABAME_WATCH_STOP.set()

if __name__ == "__main__":
    main()
