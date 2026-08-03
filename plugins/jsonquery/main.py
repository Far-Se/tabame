#!/usr/bin/env python3
"""
JSON Query — Tabame launcher plugin.

Load a JSON file / clipboard / pasted text, then filter and project it with
a small query language, view single entries, and export results (whole
objects or a single key) to a file or the clipboard.

Query language (typed after the `json` keyword, once something is loaded):

    <filter> [ | <key> ]

  filter   := condition (('and'|'or') condition)*
  condition:= field [":"] [op] value
  op       := "=" | "!=" | ">" | "<" | ">=" | "<="

  Examples:
    name=George
    "name":"George" and "money":>300 and "Location":!="Madrid"
    money>300 or money<10
    id                      -> pure projection: just the "id" of every entry
    money>300 | id          -> filter, then project only "id"
    | name                  -> no filter, project "name" from every entry
"""

import json
import os
import re
import sys
from copy import deepcopy

MISSING = object()

# --------------------------------------------------------------------------- #
# stdout / stderr helpers
# --------------------------------------------------------------------------- #


def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# --------------------------------------------------------------------------- #
# query language
# --------------------------------------------------------------------------- #

COND_RE = re.compile(
    r'^\s*"?(?P<field>[^":=<>!]+)"?\s*:?\s*(?P<op>!=|>=|<=|=|>|<)?\s*(?P<value>.*)$'
)


def parse_value(raw):
    raw = raw.strip()
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in ("'", '"'):
        return raw[1:-1]
    low = raw.lower()
    if low == "true":
        return True
    if low == "false":
        return False
    if low in ("null", "none"):
        return None
    if re.fullmatch(r"-?\d+", raw):
        try:
            return int(raw)
        except ValueError:
            pass
    if re.fullmatch(r"-?\d+\.\d+", raw):
        try:
            return float(raw)
        except ValueError:
            pass
    return raw


def parse_condition(text):
    m = COND_RE.match(text.strip())
    if not m:
        return None
    field = m.group("field").strip().strip('"').strip("'")
    op = m.group("op") or "="
    value = parse_value(m.group("value"))
    if not field:
        return None
    return field, op, value


def parse_query(text):
    """Returns (filter_groups, projection_key). filter_groups is a list of
    AND-groups (each a list of (field, op, value)) combined with OR; None
    means 'no filter, everything matches'."""
    text = (text or "").strip()
    if text == "":
        return None, None

    if "|" in text:
        left, _, right = text.partition("|")
        filter_text = left.strip()
        proj = right.strip() or None
    else:
        filter_text = text
        proj = None
        # A single bare identifier with no operators/spaces is treated as a
        # pure projection: `id` means "just show me id from every entry".
        if re.fullmatch(r"[A-Za-z0-9_.\-]+", filter_text):
            return None, filter_text

    if filter_text == "":
        return None, proj

    groups = []
    for or_part in re.split(r"\s+or\s+", filter_text, flags=re.IGNORECASE):
        conds = []
        for and_part in re.split(r"\s+and\s+", or_part, flags=re.IGNORECASE):
            and_part = and_part.strip()
            if not and_part:
                continue
            c = parse_condition(and_part)
            if c:
                conds.append(c)
        if conds:
            groups.append(conds)
    if not groups:
        groups = None
    return groups, proj


def get_ci(d, key):
    if not isinstance(d, dict):
        return MISSING
    target = key.strip().lower()
    for k, v in d.items():
        if str(k).lower() == target:
            return v
    return MISSING


def eval_condition(entry, field, op, target):
    actual = get_ci(entry, field)
    if actual is MISSING:
        return op == "!="

    if isinstance(target, bool):
        try:
            eq = bool(actual) == target
        except Exception:
            return False
        return eq if op == "=" else (not eq if op == "!=" else False)

    if isinstance(target, (int, float)) and not isinstance(target, bool):
        try:
            av = float(actual)
        except (TypeError, ValueError):
            return op == "!="
        tv = float(target)
        if op == "=":
            return av == tv
        if op == "!=":
            return av != tv
        if op == ">":
            return av > tv
        if op == "<":
            return av < tv
        if op == ">=":
            return av >= tv
        if op == "<=":
            return av <= tv
        return False

    av = "" if actual is None else str(actual)
    tv = "" if target is None else str(target)
    avl, tvl = av.lower(), tv.lower()
    if op == "=":
        return avl == tvl
    if op == "!=":
        return avl != tvl
    if op == ">":
        return avl > tvl
    if op == "<":
        return avl < tvl
    if op == ">=":
        return avl >= tvl
    if op == "<=":
        return avl <= tvl
    return False


def matches(entry, filter_groups):
    if filter_groups is None:
        return True
    for group in filter_groups:
        ok = True
        for field, op, value in group:
            if not eval_condition(entry, field, op, value):
                ok = False
                break
        if ok:
            return True
    return False


def normalize_data(raw):
    """Coerce any parsed JSON value into a list[dict] we can filter/project."""
    if isinstance(raw, list):
        out = []
        for item in raw:
            out.append(item if isinstance(item, dict) else {"value": item})
        return out
    if isinstance(raw, dict):
        values = list(raw.values())
        if values and all(isinstance(v, dict) for v in values):
            out = []
            for k, v in raw.items():
                e = dict(v)
                e.setdefault("_key", k)
                out.append(e)
            return out
        return [raw]
    return [{"value": raw}]


def parse_json_text(text):
    try:
        raw = json.loads(text)
    except Exception as e:  # noqa: BLE001
        return None, str(e)
    return raw, None


def describe_node(val):
    """Return (icon, subtitle) describing a key's value for the picker screen."""
    if isinstance(val, list):
        return "list", f"array · {len(val)} item(s)"
    if isinstance(val, dict):
        return "folder", f"object · {len(val)} key(s)"
    if isinstance(val, bool):
        return "tag", f"boolean · {val}"
    if val is None:
        return "tag", "null"
    if isinstance(val, (int, float)):
        return "tag", f"number · {val}"
    s = str(val)
    if len(s) > 60:
        s = s[:60] + "…"
    return "tag", f"string · {s}"


def looks_like_dict_of_dicts(node):
    values = list(node.values())
    return bool(values) and all(isinstance(v, dict) for v in values)


EXPORT_OMIT = object()


def format_export_path(path):
    """Return a compact, readable label for a nested export path."""
    return ".".join(str(part) for part in path)


def collect_export_options(raw):
    """Return selectable (path, sample-value) pairs for a JSON value.

    Arrays of objects are treated as a repeated object, so a document such as
    ``{"version": "1.0", "values": [{"id": 1, "name": "A"}]}`` exposes
    ``version``, ``values``, ``values.id`` and ``values.name`` as independent
    choices.  The paths are tuples rather than dotted strings because JSON
    keys are allowed to contain dots.
    """
    options = []
    seen = set()

    def first_value(values):
        for value in values:
            if value is not MISSING:
                return value
        return None

    def nested_values(values):
        """Flatten list wrappers until object children can be inspected."""
        pending = [value for value in values if value is not MISSING]
        while pending and not any(isinstance(value, dict) for value in pending):
            flattened = [item for value in pending if isinstance(value, list) for item in value]
            if not flattened or flattened == pending:
                break
            pending = flattened
        return pending

    def add(path, values):
        if not path or path in seen:
            return
        seen.add(path)
        values = [value for value in values if value is not MISSING]
        options.append((path, first_value(values)))

        object_values = nested_values(values)
        object_values = [value for value in object_values if isinstance(value, dict)]
        keys = []
        for value in object_values:
            for key in value:
                if key not in keys:
                    keys.append(key)
        for key in keys:
            child_values = [value[key] for value in object_values if key in value]
            add(path + (str(key),), child_values)

    if isinstance(raw, dict):
        root_values = [raw]
    elif isinstance(raw, list):
        root_values = raw
    else:
        root_values = []

    root_objects = nested_values(root_values)
    root_objects = [value for value in root_objects if isinstance(value, dict)]
    root_keys = []
    for value in root_objects:
        for key in value:
            if key not in root_keys:
                root_keys.append(key)
    for key in root_keys:
        child_values = [value[key] for value in root_objects if key in value]
        add((str(key),), child_values)
    return options


def project_selected_json(node, selected_paths, path=()):
    """Project [node] while preserving its JSON shape.

    Selecting a path includes that complete subtree.  Otherwise, object keys
    and array items are recursively reduced to the selected descendants.  A
    list path is not advanced while walking its items, which applies a choice
    such as ``values.name`` to every object in ``values``.
    """
    selected_paths = set(selected_paths)
    if path in selected_paths and path:
        return deepcopy(node)

    has_descendant = any(
        len(selected) > len(path) and selected[: len(path)] == path
        for selected in selected_paths
    )

    if isinstance(node, dict):
        projected = {}
        for key, value in node.items():
            child = project_selected_json(value, selected_paths, path + (str(key),))
            if child is not EXPORT_OMIT:
                projected[key] = child
        return projected if projected or has_descendant else EXPORT_OMIT

    if isinstance(node, list):
        projected = []
        for value in node:
            child = project_selected_json(value, selected_paths, path)
            if child is not EXPORT_OMIT:
                projected.append(child)
        return projected if projected or has_descendant else EXPORT_OMIT

    return EXPORT_OMIT


# --------------------------------------------------------------------------- #
# plugin state
# --------------------------------------------------------------------------- #

state = {
    "screen": "root",  # root | form_file | form_paste | select_key | browse | detail | export_form | export_only_select | export_only_form
    "data": None,  # list[dict] — the array currently being browsed
    "raw": None,  # the original parsed JSON value, kept for shape-preserving exports
    "browse_path": (),  # path of the list/object currently being browsed in raw
    "source": None,  # human-readable source label (breadcrumb)
    "last_query": "",
    "current_filtered": [],  # list[(idx, entry)]
    "current_proj": None,
    "detail_idx": None,
    "nav_stack": [],  # [{"label":..., "node":...}] path through a loaded object
    "used_select_key": False,  # whether browse was reached via the key picker
    "export_only_paths": set(),  # selected tuple paths in the original JSON
    "export_only_raw": None,  # raw data snapshot, optionally narrowed to current results
    "export_only_item_paths": {},  # current selection-page item id -> tuple path
    "export_only_query": "",
    "export_only_return_query": "",
}


# --------------------------------------------------------------------------- #
# rendering
# --------------------------------------------------------------------------- #


def render_root(query_text=""):
    q = (query_text or "").strip().lower()
    if state["data"] is None:
        items = [
            {
                "id": "open_file",
                "title": "Open JSON File…",
                "subtitle": "Pick a .json file from disk",
                "icon": "folder",
                "actions": [{"id": "default", "title": "Open", "icon": "open"}],
            },
            {
                "id": "load_clipboard",
                "title": "Load JSON from Clipboard",
                "subtitle": "Parse JSON currently on your clipboard",
                "icon": "clipboard",
            },
            {
                "id": "paste_manual",
                "title": "Paste JSON Manually",
                "subtitle": "Type or paste raw JSON text",
                "icon": "edit",
            },
        ]
    else:
        n = len(state["data"])
        items = [
            {
                "id": "browse",
                "title": f"Browse / Query ({n} entries)",
                "subtitle": state.get("source") or "loaded data",
                "icon": "search",
            },
            {
                "id": "reload",
                "title": "Load Different JSON",
                "subtitle": "Replace the currently loaded data",
                "icon": "refresh",
            },
            {"id": "clear", "title": "Clear Loaded Data", "icon": "trash"},
        ]
    if q:
        items = [it for it in items if q in it["title"].lower()]
    state["screen"] = "root"
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "list",
            "canGoBack": False,
            "placeholder": "json — pick a source, or search the menu",
            "emptyText": "No matching option",
            "items": items,
        }
    )


def breadcrumb(extra=None):
    labels = [seg["label"] for seg in state["nav_stack"]]
    if extra:
        labels.append(extra)
    return " → ".join(labels)


def render_select_key(query_text=""):
    q = (query_text or "").strip().lower()
    node = state["nav_stack"][-1]["node"]
    items = []
    for key, val in node.items():
        icon, subtitle = describe_node(val)
        items.append(
            {
                "id": f"key:{key}",
                "title": str(key),
                "subtitle": subtitle,
                "icon": icon,
                "actions": [{"id": "default", "title": "Open", "icon": "open"}],
            }
        )
    if looks_like_dict_of_dicts(node):
        items.append(
            {
                "id": "__dict_as_list__",
                "title": "Use These Entries As a List",
                "subtitle": f'{len(node)} entries, each becomes an object (adds "_key")',
                "icon": "list",
            }
        )
    items.append(
        {
            "id": "__use_object__",
            "title": "Use This Object As One Entry",
            "subtitle": "Browse this object itself, as a single row",
            "icon": "document",
        }
    )
    if q:
        items = [it for it in items if q in it["title"].lower()]
    state["screen"] = "select_key"
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "list",
            "canGoBack": True,
            "placeholder": f"Pick a key to browse into — {breadcrumb() or 'root'}",
            "emptyText": "No matching key",
            "actions": [{"id": "export_only", "title": "Export Only", "icon": "download"}],
            "items": items,
        }
    )


def begin_navigation(raw, source_label):
    """Decide how to enter browsing for a freshly-loaded JSON value."""
    state["raw"] = raw
    state["browse_path"] = ()
    state["export_only_paths"] = set()
    state["export_only_raw"] = None
    state["export_only_item_paths"] = {}
    state["export_only_query"] = ""
    state["export_only_return_query"] = ""
    if isinstance(raw, list):
        state["data"] = normalize_data(raw)
        state["source"] = source_label
        state["used_select_key"] = False
        enter_browse("")
    elif isinstance(raw, dict):
        state["nav_stack"] = [{"label": source_label, "node": raw, "path": ()}]
        state["used_select_key"] = True
        render_select_key("")
    else:
        state["data"] = normalize_data(raw)
        state["source"] = source_label
        state["used_select_key"] = False
        enter_browse("")


def render_form_file(error=None):
    field = {
        "id": "path",
        "type": "filepicker",
        "label": "JSON file",
        "required": True,
        "description": "Choose a .json file on disk",
    }
    if error:
        field["error"] = error
    state["screen"] = "form_file"
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "form",
            "canGoBack": True,
            "form": {
                "title": "Open JSON File",
                "submitLabel": "Load",
                "fields": [field],
            },
        }
    )


def render_form_paste(error=None):
    field = {
        "id": "json",
        "type": "textarea",
        "label": "JSON text",
        "required": True,
        "placeholder": '[{"id": 1, "name": "George", "money": 400}, ...]',
    }
    if error:
        field["error"] = error
    state["screen"] = "form_paste"
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "form",
            "canGoBack": True,
            "form": {"title": "Paste JSON", "submitLabel": "Load", "fields": [field]},
        }
    )


def render_export_form(error_field=None, error=None):
    proj = state.get("current_proj")
    default_name = proj if proj else "results"
    folder_field = {
        "id": "folder",
        "type": "folderpicker",
        "label": "Save to folder",
        "required": True,
    }
    filename_field = {
        "id": "filename",
        "type": "text",
        "label": "File name",
        "value": default_name,
        "required": True,
        "description": "Extension is added automatically",
    }
    format_field = {
        "id": "format",
        "type": "dropdown",
        "label": "Format",
        "value": "json" if not proj else "json",
        "options": [
            {"value": "json", "label": "JSON"},
            {"value": "txt", "label": "Text (one value per line)"},
        ],
    }
    if error_field == "folder":
        folder_field["error"] = error
    elif error_field == "filename":
        filename_field["error"] = error
    n = len(state.get("current_filtered", []))
    subtitle = f"Exporting {n} result(s)" + (
        f", key: {proj}" if proj else ", whole objects"
    )
    state["screen"] = "export_form"
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "form",
            "canGoBack": True,
            "form": {
                "title": "Export Results",
                "submitLabel": "Export",
                "fields": [folder_field, filename_field, format_field],
            },
            "placeholder": subtitle,
        }
    )


def export_path_is_selected(path):
    """Whether [path] is selected directly or covered by a selected parent."""
    return any(
        selected == path or (len(selected) < len(path) and path[: len(selected)] == selected)
        for selected in state.get("export_only_paths", set())
    )


def export_path_has_selected_parent(path):
    return any(
        len(selected) < len(path) and path[: len(selected)] == selected
        for selected in state.get("export_only_paths", set())
    )


def toggle_export_path(path):
    """Toggle a path while keeping parent/child selections unambiguous."""
    selected = state.setdefault("export_only_paths", set())
    if path in selected:
        selected.remove(path)
        selected.difference_update([
            candidate
            for candidate in selected
            if len(candidate) > len(path) and candidate[: len(path)] == path
        ])
        return

    # Choosing a child refines a whole-parent choice; choosing a parent replaces
    # any narrower choices below it.
    selected.difference_update([
        candidate
        for candidate in selected
        if (len(candidate) < len(path) and path[: len(candidate)] == candidate)
        or (len(candidate) > len(path) and candidate[: len(path)] == path)
    ])
    selected.add(path)


def raw_node_at_path(node, path):
    if not path:
        return node
    if isinstance(node, dict):
        part = path[0]
        if part not in node:
            return MISSING
        return raw_node_at_path(node[part], path[1:])
    if isinstance(node, list):
        return [raw_node_at_path(item, path) for item in node]
    return MISSING


def filtered_browse_node(raw_node):
    indices = [index for index, _ in state.get("current_filtered", [])]
    if isinstance(raw_node, list):
        return [
            deepcopy(raw_node[index])
            for index in indices
            if 0 <= index < len(raw_node)
        ]
    if isinstance(raw_node, dict) and looks_like_dict_of_dicts(raw_node):
        keys = list(raw_node)
        return {
            key: deepcopy(raw_node[key])
            for index, key in enumerate(keys)
            if index in indices
        }
    return deepcopy(raw_node) if indices else {}


def build_export_source():
    """Snapshot the original JSON, narrowed to the current browse results."""
    raw = state.get("raw")
    if state.get("screen") != "browse":
        return deepcopy(raw)
    browse_path = state.get("browse_path", ())
    raw_node = raw_node_at_path(raw, browse_path)
    if raw_node is MISSING:
        return deepcopy(raw)
    return replace_raw_node(raw, browse_path, filtered_browse_node(raw_node))


def replace_raw_node(node, path, replacement):
    if not path:
        return deepcopy(replacement)
    if isinstance(node, dict):
        key = path[0]
        if key not in node:
            return deepcopy(node)
        result = deepcopy(node)
        result[key] = replace_raw_node(node[key], path[1:], replacement)
        return result
    if isinstance(node, list):
        return [replace_raw_node(item, path, replacement) for item in node]
    return deepcopy(node)


def export_raw():
    return state["export_only_raw"] if state.get("export_only_raw") is not None else state.get("raw")


def selected_export_labels():
    options = collect_export_options(export_raw())
    return [format_export_path(path) for path, _ in options if path in state.get("export_only_paths", set())]


def render_export_only_select(rev=0, query_text=None):
    if query_text is not None:
        state["export_only_query"] = (query_text or "").strip()
    query = state.get("export_only_query", "").lower()
    options = collect_export_options(export_raw())
    state["export_only_item_paths"] = {}

    items = []
    for index, (path, sample) in enumerate(options):
        label = format_export_path(path)
        icon, description = describe_node(sample)
        if len(path) > 1:
            description += " · nested key"
        if isinstance(sample, (dict, list)):
            description += " · selecting this includes the whole value"
        if query and query not in label.lower() and query not in description.lower():
            continue

        item_id = f"export-key-{index}"
        state["export_only_item_paths"][item_id] = path
        is_selected = export_path_is_selected(path)
        action_title = "Deselect Key" if path in state.get("export_only_paths", set()) else (
            "Select Only This Key" if export_path_has_selected_parent(path) else "Select Key"
        )
        item = {
            "id": item_id,
            "title": label,
            "subtitle": description,
            "icon": "check" if is_selected else icon,
            "actions": [
                {
                    "id": "toggle",
                    "title": action_title,
                    "icon": "check",
                    "shortcut": "ctrl+space",
                }
            ],
        }
        if is_selected:
            item["accessories"] = [{"text": "Selected", "icon": "check"}]
        items.append(item)

    frame_actions = [
        {"id": "export_selected", "title": "Export Selected", "icon": "download"}
    ]
    if state.get("export_only_paths"):
        frame_actions.append(
            {"id": "clear_export_selection", "title": "Clear Selection", "icon": "close"}
        )

    state["screen"] = "export_only_select"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "placeholder": "Select keys to include (Enter or Ctrl+Space)",
            "emptyText": "No selectable keys match this search",
            "actions": frame_actions,
            "items": items,
        }
    )


def render_export_only_form(error_field=None, error=None):
    folder_field = {
        "id": "folder",
        "type": "folderpicker",
        "label": "Save to folder",
        "required": True,
    }
    filename_field = {
        "id": "filename",
        "type": "text",
        "label": "File name",
        "value": "selected",
        "required": True,
        "description": "A .json extension is added automatically",
    }
    if error_field == "folder":
        folder_field["error"] = error
    elif error_field == "filename":
        filename_field["error"] = error

    labels = selected_export_labels()
    summary = ", ".join(labels[:8])
    if len(labels) > 8:
        summary += f", … (+{len(labels) - 8} more)"
    state["screen"] = "export_only_form"
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "form",
            "canGoBack": True,
            "form": {
                "title": "Export Selected Keys",
                "submitLabel": "Export JSON",
                "fields": [folder_field, filename_field],
            },
            "placeholder": f"Exporting {len(labels)} key(s): {summary}",
        }
    )


def project_value(entry, proj):
    return get_ci(entry, proj)


def build_entry_preview(entry):
    markdown = "```json\n" + json.dumps(entry, indent=2, ensure_ascii=False) + "\n```"
    return {
        "markdown": markdown,
        "metadata": [
            {
                "label": "Actions",
                "text": "Full entry",
                "actions": [{"id": "copy_json", "title": "Copy JSON", "icon": "copy"}],
            }
        ],
    }


def render_browse(rev, text):
    data = state["data"] or []
    filter_groups, proj = parse_query(text)
    filtered = [(i, e) for i, e in enumerate(data) if matches(e, filter_groups)]
    state["current_filtered"] = filtered
    state["current_proj"] = proj
    state["last_query"] = text
    state["screen"] = "browse"

    frame_actions = [
        {"id": "copy_all", "title": "Copy All Results (JSON)", "icon": "copy"},
        {"id": "export", "title": "Export Results…", "icon": "download"},
        {"id": "export_only", "title": "Export Only", "icon": "download"},
    ]
    if proj:
        frame_actions.insert(
            1,
            {
                "id": "copy_values",
                "title": "Copy Values (one per line)",
                "icon": "copy",
            },
        )
    if state.get("used_select_key"):
        frame_actions.append(
            {"id": "change_key", "title": "Browse Different Key", "icon": "folder"}
        )

    items = []
    if proj:
        for idx, e in filtered:
            val = project_value(e, proj)
            if val is MISSING:
                continue
            display = (
                val if isinstance(val, str) else json.dumps(val, ensure_ascii=False)
            )
            sub = None
            for hint in ("name", "title", "id"):
                if hint.lower() == proj.lower():
                    continue
                hv = get_ci(e, hint)
                if hv is not MISSING:
                    sub = f"{hint}: {hv}"
                    break
            items.append(
                {
                    "id": f"proj-{idx}",
                    "title": str(display)[:200],
                    "subtitle": sub or f"entry #{idx}",
                    "icon": "tag",
                    "actions": [{"id": "copy", "title": "Copy Value", "icon": "copy"}],
                    "preview": build_entry_preview(e),
                }
            )
        empty = f'No entries have "{proj}"' if not items else None
    else:
        for idx, e in filtered:
            title = None
            for hint in ("name", "title", "id"):
                hv = get_ci(e, hint)
                if hv is not MISSING:
                    title = f"{hint}: {hv}"
                    break
            if title is None:
                title = json.dumps(e, ensure_ascii=False)[:80]
            subtitle = json.dumps(e, ensure_ascii=False)
            if len(subtitle) > 220:
                subtitle = subtitle[:220] + "…"
            items.append(
                {
                    "id": f"entry-{idx}",
                    "title": title,
                    "subtitle": subtitle,
                    "lines": 2,
                    "icon": "document",
                    "actions": [
                        {"id": "default", "title": "View Full JSON", "icon": "open"},
                        {"id": "copy", "title": "Copy JSON", "icon": "copy"},
                    ],
                    "preview": build_entry_preview(e),
                }
            )
        empty = None

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "placeholder": 'Filter e.g. "name":"George" and "money":>300 | id',
            "emptyText": empty or "No entries match this query",
            "preview": {"enabled": True},
            "actions": frame_actions,
            "items": items,
        }
    )


def render_detail(idx):
    entry = state["data"][idx]
    md = "```json\n" + json.dumps(entry, indent=2, ensure_ascii=False) + "\n```"
    state["screen"] = "detail"
    state["detail_idx"] = idx
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "detail",
            "canGoBack": True,
            "detail": {"markdown": md},
            "actions": [{"id": "copy", "title": "Copy JSON", "icon": "copy"}],
        }
    )


# --------------------------------------------------------------------------- #
# actions
# --------------------------------------------------------------------------- #


def do_copy_item(item_id):
    kind, _, idx_s = item_id.partition("-")
    try:
        idx = int(idx_s)
    except ValueError:
        return
    entry = state["data"][idx]
    if kind == "proj":
        val = project_value(entry, state["current_proj"])
        text = val if isinstance(val, str) else json.dumps(val, ensure_ascii=False)
    else:
        text = json.dumps(entry, indent=2, ensure_ascii=False)
    send({"type": "command", "command": "copy", "text": str(text)})


def do_copy_full_item(item_id):
    _, _, idx_s = item_id.partition("-")
    try:
        idx = int(idx_s)
    except ValueError:
        return
    if idx < 0 or idx >= len(state.get("data") or []):
        return
    text = json.dumps(state["data"][idx], indent=2, ensure_ascii=False)
    send({"type": "command", "command": "copy", "text": text})


def do_copy_all():
    filtered = state.get("current_filtered", [])
    proj = state.get("current_proj")
    if proj:
        vals = [
            project_value(e, proj)
            for _, e in filtered
            if project_value(e, proj) is not MISSING
        ]
        text = json.dumps(vals, indent=2, ensure_ascii=False)
    else:
        text = json.dumps([e for _, e in filtered], indent=2, ensure_ascii=False)
    send({"type": "command", "command": "copy", "text": text})
    send(
        {
            "type": "command",
            "command": "toast",
            "text": f"Copied {len(filtered)} result(s)",
        }
    )


def do_copy_values():
    filtered = state.get("current_filtered", [])
    proj = state.get("current_proj")
    if not proj:
        return
    vals = []
    for _, e in filtered:
        v = project_value(e, proj)
        if v is not MISSING:
            vals.append(v if isinstance(v, str) else json.dumps(v, ensure_ascii=False))
    text = "\n".join(vals)
    send({"type": "command", "command": "copy", "text": text})
    send(
        {"type": "command", "command": "toast", "text": f"Copied {len(vals)} value(s)"}
    )


def build_export_content(fmt):
    filtered = state.get("current_filtered", [])
    proj = state.get("current_proj")
    if proj:
        vals = [
            project_value(e, proj)
            for _, e in filtered
            if project_value(e, proj) is not MISSING
        ]
        if fmt == "txt":
            return "\n".join(
                v if isinstance(v, str) else json.dumps(v, ensure_ascii=False)
                for v in vals
            )
        return json.dumps(vals, indent=2, ensure_ascii=False)
    entries = [e for _, e in filtered]
    if fmt == "txt":
        return "\n".join(json.dumps(e, ensure_ascii=False) for e in entries)
    return json.dumps(entries, indent=2, ensure_ascii=False)


def build_export_only_content():
    raw = export_raw()
    projected = project_selected_json(raw, state.get("export_only_paths", set()))
    if projected is EXPORT_OMIT:
        projected = {} if isinstance(raw, dict) else []
    return json.dumps(projected, indent=2, ensure_ascii=False)


def go_back():
    scr = state["screen"]

    if scr == "select_key":
        if len(state["nav_stack"]) > 1:
            state["nav_stack"].pop()
            render_select_key("")
        else:
            send({"type": "command", "command": "setQuery", "text": ""})
            render_root("")
        return

    if scr == "detail":
        q = state["last_query"]
        send({"type": "command", "command": "setQuery", "text": q})
        render_browse(0, q)
        return

    if scr == "export_form":
        q = state["last_query"]
        send({"type": "command", "command": "setQuery", "text": q})
        render_browse(0, q)
        return

    if scr == "export_only_form":
        send({"type": "command", "command": "setQuery", "text": ""})
        render_export_only_select(0, "")
        return

    if scr == "export_only_select":
        q = state.get("export_only_return_query", "")
        send({"type": "command", "command": "setQuery", "text": q})
        render_browse(0, q)
        return

    if scr == "browse":
        if state.get("used_select_key") and state["nav_stack"]:
            render_select_key("")
        else:
            send({"type": "command", "command": "setQuery", "text": ""})
            render_root("")
        return

    # form_file, form_paste -> root
    send({"type": "command", "command": "setQuery", "text": ""})
    render_root("")


def enter_browse(query_text=""):
    send({"type": "command", "command": "setQuery", "text": query_text})
    render_browse(0, query_text)


def open_export_only():
    state["export_only_paths"] = set()
    state["export_only_raw"] = build_export_source()
    state["export_only_item_paths"] = {}
    state["export_only_query"] = ""
    state["export_only_return_query"] = state.get("last_query", "")
    send({"type": "command", "command": "setQuery", "text": ""})
    render_export_only_select(0, "")


def handle_action(item_id, action):
    scr = state["screen"]

    if scr == "root":
        if item_id == "open_file":
            render_form_file()
        elif item_id == "load_clipboard":
            send(
                {
                    "type": "command",
                    "command": "clipboardRead",
                    "requestId": "load_clip",
                }
            )
        elif item_id == "paste_manual":
            render_form_paste()
        elif item_id == "browse":
            enter_browse("")
        elif item_id in ("reload", "clear"):
            state["data"] = None
            state["raw"] = None
            state["browse_path"] = ()
            state["source"] = None
            state["nav_stack"] = []
            state["used_select_key"] = False
            state["export_only_paths"] = set()
            state["export_only_raw"] = None
            render_root("")

    elif scr == "select_key":
        if item_id == "" and action == "export_only":
            open_export_only()
            return
        node = state["nav_stack"][-1]["node"]
        if item_id.startswith("key:"):
            key = item_id[4:]
            val = node.get(key, MISSING)
            if isinstance(val, list):
                state["data"] = normalize_data(val)
                state["source"] = breadcrumb(key)
                state["browse_path"] = state["nav_stack"][-1].get("path", ()) + (str(key),)
                state["used_select_key"] = True
                enter_browse("")
            elif isinstance(val, dict):
                current_path = state["nav_stack"][-1].get("path", ())
                state["nav_stack"].append(
                    {"label": key, "node": val, "path": current_path + (str(key),)}
                )
                render_select_key("")
            elif val is not MISSING:
                text = (
                    val if isinstance(val, str) else json.dumps(val, ensure_ascii=False)
                )
                send({"type": "command", "command": "copy", "text": str(text)})
                send(
                    {
                        "type": "command",
                        "command": "toast",
                        "text": f"Copied {key}: {text}",
                    }
                )
        elif item_id == "__dict_as_list__":
            state["data"] = normalize_data(node)
            state["source"] = breadcrumb()
            state["browse_path"] = state["nav_stack"][-1].get("path", ())
            state["used_select_key"] = True
            enter_browse("")
        elif item_id == "__use_object__":
            state["data"] = [node]
            state["source"] = breadcrumb()
            state["browse_path"] = state["nav_stack"][-1].get("path", ())
            state["used_select_key"] = True
            enter_browse("")

    elif scr == "browse":
        if item_id.startswith("entry-"):
            idx = int(item_id.split("-", 1)[1])
            if action in ("copy", "copy_json"):
                do_copy_item(item_id)
            else:  # "default" -> view
                render_detail(idx)
        elif item_id.startswith("proj-"):
            if action == "copy_json":
                do_copy_full_item(item_id)
            else:
                do_copy_item(item_id)
        elif item_id == "":
            if action == "copy_all":
                do_copy_all()
            elif action == "copy_values":
                do_copy_values()
            elif action == "export":
                render_export_form()
            elif action == "export_only":
                open_export_only()
            elif action == "change_key" and state.get("used_select_key"):
                render_select_key("")

    elif scr == "export_only_select":
        path = state.get("export_only_item_paths", {}).get(item_id)
        if path is not None and action in ("default", "toggle"):
            toggle_export_path(path)
            render_export_only_select(0)
        elif item_id == "" and action == "export_selected":
            if not state.get("export_only_paths"):
                send(
                    {
                        "type": "command",
                        "command": "toast",
                        "style": "error",
                        "text": "Select at least one key to export",
                    }
                )
            else:
                render_export_only_form()
        elif item_id == "" and action == "clear_export_selection":
            state["export_only_paths"] = set()
            render_export_only_select(0)

    elif scr == "detail":
        if item_id == "" and action == "copy":
            idx = state.get("detail_idx")
            if idx is not None:
                do_copy_item(f"entry-{idx}")


def handle_submit(values, button):
    scr = state["screen"]

    if scr == "form_file":
        path = (values.get("path") or "").strip()
        if not path:
            render_form_file("Please choose a file")
            return
        try:
            with open(path, "r", encoding="utf-8") as f:
                text = f.read()
        except Exception as e:  # noqa: BLE001
            render_form_file(f"Could not read file: {e}")
            return
        raw, err = parse_json_text(text)
        if err:
            render_form_file(f"Invalid JSON: {err}")
            return
        send({"type": "command", "command": "toast", "text": "JSON loaded"})
        begin_navigation(raw, os.path.basename(path))

    elif scr == "form_paste":
        text = values.get("json") or ""
        raw, err = parse_json_text(text)
        if err:
            render_form_paste(f"Invalid JSON: {err}")
            return
        send({"type": "command", "command": "toast", "text": "JSON loaded"})
        begin_navigation(raw, "pasted text")

    elif scr == "export_only_form":
        folder = (values.get("folder") or "").strip()
        filename = (values.get("filename") or "").strip() or "selected"
        if not folder:
            render_export_only_form("folder", "Please choose a folder")
            return
        if not filename.lower().endswith(".json"):
            filename += ".json"
        full_path = os.path.join(folder, filename)
        try:
            with open(full_path, "w", encoding="utf-8") as f:
                f.write(build_export_only_content())
        except Exception as e:  # noqa: BLE001
            render_export_only_form("filename", f"Write failed: {e}")
            return
        send({"type": "command", "command": "toast", "text": f"Exported to {filename}"})
        send({"type": "command", "command": "open", "url": full_path})
        state["export_only_paths"] = set()
        q = state.get("export_only_return_query", state.get("last_query", ""))
        send({"type": "command", "command": "setQuery", "text": q})
        render_browse(0, q)

    elif scr == "export_form":
        folder = (values.get("folder") or "").strip()
        filename = (values.get("filename") or "").strip()
        fmt = values.get("format") or "json"
        if not folder:
            render_export_form("folder", "Please choose a folder")
            return
        if not filename:
            filename = state.get("current_proj") or "results"
        ext = ".json" if fmt == "json" else ".txt"
        if not filename.lower().endswith(ext):
            filename += ext
        full_path = os.path.join(folder, filename)
        content = build_export_content(fmt)
        try:
            with open(full_path, "w", encoding="utf-8") as f:
                f.write(content)
        except Exception as e:  # noqa: BLE001
            render_export_form("filename", f"Write failed: {e}")
            return
        send({"type": "command", "command": "toast", "text": f"Exported to {filename}"})
        send({"type": "command", "command": "open", "url": full_path})
        q = state["last_query"]
        send({"type": "command", "command": "setQuery", "text": q})
        render_browse(0, q)


def handle_clipboard(msg):
    if msg.get("requestId") != "load_clip":
        return
    text = msg.get("text") or ""
    raw, err = parse_json_text(text)
    if err:
        send(
            {
                "type": "command",
                "command": "toast",
                "style": "error",
                "text": f"Clipboard isn't valid JSON: {err}",
            }
        )
        render_root("")
        return
    send({"type": "command", "command": "toast", "text": "JSON loaded from clipboard"})
    begin_navigation(raw, "clipboard")


# --------------------------------------------------------------------------- #
# main loop
# --------------------------------------------------------------------------- #


def main():
    render_root("")
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue

        t = msg.get("type")
        try:
            if t == "close":
                break
            elif t in ("init", "query"):
                text = msg.get("text", msg.get("query", ""))
                rev = msg.get("rev", 0)
                if state["screen"] == "browse":
                    render_browse(rev, text)
                elif state["screen"] == "root":
                    render_root(text)
                elif state["screen"] == "select_key":
                    render_select_key(text)
                elif state["screen"] == "export_only_select":
                    render_export_only_select(rev, text)
                # form screens: ignore query events, the form owns input
            elif t == "action":
                handle_action(msg.get("id", ""), msg.get("action", "default"))
            elif t == "submit":
                handle_submit(msg.get("values", {}), msg.get("button"))
            elif t == "back":
                go_back()
            elif t == "clipboard":
                handle_clipboard(msg)
        except Exception as e:  # noqa: BLE001
            log("ERROR:", repr(e))
            send(
                {
                    "type": "render",
                    "rev": 0,
                    "view": "detail",
                    "canGoBack": True,
                    "detail": {"markdown": f"# Error\n\n```\n{e}\n```"},
                }
            )


if __name__ == "__main__":
    main()
