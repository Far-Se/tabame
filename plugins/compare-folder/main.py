#!/usr/bin/env python3
import difflib
import hashlib
import json
import os
import subprocess
import sys
import threading


def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def get_md5(filepath):
    """Generate MD5 hash for a file."""
    try:
        h = hashlib.md5()
        with open(filepath, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                h.update(chunk)
        return h.hexdigest()
    except Exception:
        return None


def is_git_identical(file1, file2):
    """Quickly check if git considers files identical (ignoring whitespace/etc)."""
    try:
        result = subprocess.run(
            ["git", "diff", "--no-index", "--quiet", file1, file2],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        # Exit code 0 means identical, 1 means different, >1 means error
        return result.returncode == 0
    except FileNotFoundError:
        pass  # Git not installed

    # Fallback to exact string match if git is missing
    try:
        with (
            open(file1, "r", encoding="utf-8", errors="replace") as f1,
            open(file2, "r", encoding="utf-8", errors="replace") as f2,
        ):
            return f1.read() == f2.read()
    except Exception:
        return False


def get_file_diff(file1, file2):
    """Generate a full unified diff using git, fallback to difflib."""
    try:
        result = subprocess.run(
            ["git", "diff", "--no-index", "--color=never", file1, file2],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        if result.returncode <= 1:
            return result.stdout.strip() or "Files are identical."
    except FileNotFoundError:
        pass

    try:
        with (
            open(file1, "r", encoding="utf-8", errors="replace") as f1,
            open(file2, "r", encoding="utf-8", errors="replace") as f2,
        ):
            diff = difflib.unified_diff(
                f1.readlines(), f2.readlines(), fromfile=file1, tofile=file2
            )
            diff_text = "".join(diff).strip()
            return diff_text if diff_text else "Files are identical."
    except Exception as e:
        return f"Error reading files for diff: {e}"


# Plugin state
state = {
    "screen": "loading",
    "folder1": "",
    "folder2": "",
    "results": [],
    "current_query": "",
}


def render_form():
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "form",
            "canGoBack": state["screen"] == "results",
            "placeholder": "Fill the form below...",
            "form": {
                "title": "Check Folder Sync",
                "submitLabel": "Check Sync",
                "fields": [
                    {
                        "id": "folder1",
                        "type": "folderpicker",
                        "label": "Source Folder (1st)",
                        "required": True,
                        "value": state.get("folder1", ""),
                        "description": "The folder to scan for files (1 level deep).",
                    },
                    {
                        "id": "folder2",
                        "type": "folderpicker",
                        "label": "Target Folder (2nd)",
                        "required": True,
                        "value": state.get("folder2", ""),
                        "description": "The folder to compare files against.",
                    },
                ],
            },
        }
    )


def render_results(rev, text=""):
    """Render the comparison results list with the preview pane enabled."""
    state["current_query"] = text
    filtered = []
    for r in state["results"]:
        if text.lower() in r["title"].lower():
            filtered.append(r)

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": False,
            "preview": {"enabled": True, "wide": True},
            "placeholder": "Filter files...",
            "emptyText": "No files found or no match.",
            "actions": [
                {"id": "change_folders", "title": "Change Folders", "icon": "folder"},
                {"id": "rescan", "title": "Rescan Folders", "icon": "refresh"},
            ],
            "items": filtered,
        }
    )


def compute_diff_async(item_id):
    """Run full diff in a thread so the UI doesn't freeze, then update the preview."""

    def run():
        f1 = os.path.join(state["folder1"], item_id)
        f2 = os.path.join(state["folder2"], item_id)

        diff_text = get_file_diff(f1, f2)
        is_identical = diff_text.strip() == "Files are identical."

        for item in state["results"]:
            if item["id"] == item_id:
                item["verified"] = True
                if is_identical:
                    item["status"] = "Synced"
                    item["icon"] = "check"
                    item["accessories"] = [{"text": "Synced", "color": "#10B981"}]
                    item["preview"] = {
                        "markdown": "**Synced**\n\nFiles are identical (ignoring whitespace/metadata)."
                    }
                else:
                    item["preview"] = {"markdown": f"```diff\n{diff_text}\n```"}
                break

        render_results(0, state.get("current_query", ""))

    threading.Thread(target=run, daemon=True).start()


def verify_differences():
    """Background thread to check MD5-mismatched files with git."""
    count = 0
    for item in state["results"]:
        if item.get("status") == "Different" and not item.get("verified"):
            item["verified"] = True  # Mark immediately to prevent re-entry
            f1 = os.path.join(state["folder1"], item["id"])
            f2 = os.path.join(state["folder2"], item["id"])

            if is_git_identical(f1, f2):
                item["status"] = "Synced"
                item["icon"] = "check"
                item["accessories"] = [{"text": "Synced", "color": "#10B981"}]
                item["preview"] = {
                    "markdown": "**Synced**\n\nFiles are identical (ignoring whitespace/metadata)."
                }
                count += 1
            else:
                item["preview"] = {"markdown": "**Different**\n\nHover to view diff..."}
                count += 1

            # Batch UI updates every 10 files to avoid spamming the launcher
            if count % 10 == 0:
                render_results(0, state.get("current_query", ""))

    if count % 10 != 0:
        render_results(0, state.get("current_query", ""))


def process_sync(f1, f2):
    """Scan f1 (1 level deep), compute MD5s, and compare with f2."""
    state["screen"] = "loading"
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "list",
            "loading": True,
            "items": [],
            "loadingText": "Scanning files and hashing...",
        }
    )

    if not os.path.isdir(f1) or not os.path.isdir(f2):
        state["screen"] = "error"
        send(
            {
                "type": "render",
                "rev": 0,
                "view": "detail",
                "canGoBack": True,
                "detail": {
                    "markdown": "# Error\n\nOne or both folders do not exist or are inaccessible.\n\nPress Escape to go back."
                },
            }
        )
        return

    files_to_check = []
    for root, dirs, files in os.walk(f1):
        rel_root = os.path.relpath(root, f1)
        depth = 0 if rel_root == "." else rel_root.count(os.sep) + 1

        if depth > 1:
            dirs[:] = []
            continue

        for f in files:
            files_to_check.append(os.path.join(root, f))

    items = []
    for f in files_to_check:
        rel_path = os.path.relpath(f, f1)
        path2 = os.path.join(f2, rel_path)

        md5_1 = get_md5(f)
        actions = [{"id": "open1", "title": "Open in Source", "icon": "open"}]

        if not os.path.exists(path2):
            status = "Missing"
            icon = "warning"
            color = "#F59E0B"
            preview_md = (
                "**Missing in Target**\n\nFile does not exist in the second folder."
            )
            verified = True
        else:
            actions.append({"id": "open2", "title": "Open in Target", "icon": "open"})
            md5_2 = get_md5(path2)

            if md5_1 == md5_2:
                status = "Synced"
                icon = "check"
                color = "#10B981"
                preview_md = "**Synced**\n\nMD5 hashes match exactly."
                verified = True
            else:
                status = "Different"
                icon = "error"
                color = "#EF4444"
                preview_md = "**Different**\n\nVerifying with Git..."
                verified = False  # Will be checked by the background thread

        items.append(
            {
                "id": rel_path,
                "title": rel_path,
                "subtitle": f"MD5: {md5_1}" if md5_1 else "Could not read source file",
                "icon": icon,
                "accessories": [{"text": status, "color": color}],
                "actions": actions,
                "preview": {"markdown": preview_md},
                "status": status,
                "verified": verified,
                "diff_loaded": False,
            }
        )

    state["results"] = items
    state["screen"] = "results"
    render_results(0)

    # Kick off the background verification for files that have different MD5s
    threading.Thread(target=verify_differences, daemon=True).start()


def handle_action(item_id, action):
    """Handle Enter or Ctrl+K actions."""
    if item_id == "":
        if action == "change_folders":
            state["screen"] = "form"
            render_form()
        elif action == "rescan":
            process_sync(state["folder1"], state["folder2"])
        return

    path = None
    if action in ("default", "open1"):
        path = os.path.join(state["folder1"], item_id)
    elif action == "open2":
        path = os.path.join(state["folder2"], item_id)

    if path and os.path.exists(path):
        send({"type": "command", "command": "open", "path": path})


def load_settings():
    send(
        {
            "type": "command",
            "command": "storage",
            "op": "get",
            "key": "sync_folders",
            "requestId": "load_folders",
        }
    )


def main():
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

        elif t == "init":
            state["screen"] = "loading"
            send(
                {
                    "type": "render",
                    "rev": 0,
                    "view": "list",
                    "loading": True,
                    "items": [],
                    "loadingText": "Loading settings...",
                }
            )
            load_settings()

        elif t == "storage":
            if msg.get("requestId") == "load_folders":
                val = msg.get("value")
                if val:
                    try:
                        data = json.loads(val)
                        state["folder1"] = data.get("folder1", "")
                        state["folder2"] = data.get("folder2", "")
                    except:
                        pass

                if state["folder1"] and state["folder2"]:
                    process_sync(state["folder1"], state["folder2"])
                else:
                    state["screen"] = "form"
                    render_form()

        elif t == "query":
            state["current_query"] = msg.get("text", "")
            if state["screen"] == "results":
                render_results(msg.get("rev", 0), state["current_query"])

        elif t == "select":
            # Lazy load the full diff when a file is highlighted
            item_id = msg.get("id", "")
            if not item_id:
                continue

            for item in state["results"]:
                if item["id"] == item_id:
                    if item.get("status") == "Different" and not item.get(
                        "diff_loaded"
                    ):
                        item["diff_loaded"] = True
                        item["preview"] = {
                            "markdown": "**Different**\n\nGenerating diff..."
                        }
                        render_results(0, state.get("current_query", ""))
                        compute_diff_async(item_id)
                    break

        elif t == "submit":
            vals = msg.get("values", {})
            f1 = vals.get("folder1", "").strip()
            f2 = vals.get("folder2", "").strip()

            if not f1 or not f2:
                render_form()
                continue

            state["folder1"] = f1
            state["folder2"] = f2

            send(
                {
                    "type": "command",
                    "command": "storage",
                    "op": "set",
                    "key": "sync_folders",
                    "value": json.dumps({"folder1": f1, "folder2": f2}),
                }
            )

            process_sync(f1, f2)

        elif t == "action":
            handle_action(msg.get("id", ""), msg.get("action", "default"))

        elif t == "back":
            if (
                state["screen"] in ("form", "error")
                and state["folder1"]
                and state["folder2"]
            ):
                process_sync(state["folder1"], state["folder2"])
            else:
                state["screen"] = "form"
                render_form()


if __name__ == "__main__":
    main()
