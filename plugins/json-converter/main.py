#!/usr/bin/env python3
import json
import os
import sys
import threading
import time
from pathlib import Path

# ---------- Protocol helpers ----------


def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def log(*a):
    # All debug goes to stderr, safe.
    print(*a, file=sys.stderr, flush=True)


def send_command(cmd, **kwargs):
    payload = {"type": "command", "command": cmd}
    payload.update(kwargs)
    send(payload)


# ---------- State ----------

state = {
    "screen": "root",  # "root" or "form"
    "operation": None,  # "compress" or "decompress"
    "form_values": {
        "sourceType": "file",
        "file": "",
        "dest": "",
    },
    "pending_clipboard": {},  # request_id -> {"dest": str, "operation": str}
}

# ---------- Rendering ----------


def render_root(rev=0):
    items = [
        {
            "id": "compress",
            "title": "Compress JSON",
            "subtitle": "Minify a JSON file or clipboard content",
            "icon": "compress",
            "actions": [{"id": "default", "title": "Compress"}],
        },
        {
            "id": "decompress",
            "title": "Decompress JSON",
            "subtitle": "Pretty‑print a JSON file or clipboard content",
            "icon": "expand",
            "actions": [{"id": "default", "title": "Decompress"}],
        },
    ]
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "items": items,
            "emptyText": "No actions",
            "canGoBack": False,
        }
    )


def render_form(operation, values, rev=0, loading=False):
    op_label = "Compress" if operation == "compress" else "Decompress"
    submit_label = op_label
    dest_placeholder = "Destination path (auto‑filled when file is picked)"

    # Build fields
    fields = [
        {
            "id": "sourceType",
            "type": "dropdown",
            "label": "Source",
            "value": values.get("sourceType", "file"),
            "options": [
                {"value": "file", "label": "File"},
                {"value": "clipboard", "label": "Clipboard"},
            ],
            "watch": True,  # we may want to react to source changes (optional)
        },
        {
            "id": "file",
            "type": "filepicker",
            "label": "Source file",
            "value": values.get("file", ""),
            "description": "Required when Source is 'File'",
            "watch": True,  # pick triggers change -> update dest
        },
        {
            "id": "dest",
            "type": "text",
            "label": "Destination path",
            "value": values.get("dest", ""),
            "placeholder": dest_placeholder,
            "required": True,
            "description": "Full path where the result will be saved",
        },
    ]

    # If source is clipboard, we still show the file field but it's ignored.
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "canGoBack": True,
            "loading": loading,
            "loadingText": "Processing..." if loading else None,
            "form": {
                "title": f"{op_label} JSON",
                "submitLabel": submit_label,
                "fields": fields,
            },
        }
    )


def update_dest_from_file(file_path, operation):
    if not file_path:
        return ""
    p = Path(file_path)
    if operation == "compress":
        # default: same dir + basename without extension + ".min.json"
        new_name = p.stem + ".min.json"
        return str(p.parent / new_name)
    else:
        # Decompress: add ".pretty.json"
        new_name = p.stem + ".pretty.json"
        return str(p.parent / new_name)


# ---------- Processing ----------


def compress_json(data):
    """Return minified JSON string."""
    return json.dumps(data, separators=(",", ":"), ensure_ascii=False)


def decompress_json(data):
    """Return pretty‑printed JSON string (indent=2)."""
    return json.dumps(data, indent=2, ensure_ascii=False)


def process_file(source_path, dest_path, operation):
    try:
        with open(source_path, "r", encoding="utf-8") as f:
            raw = f.read()
        data = json.loads(raw)
        result = (
            compress_json(data) if operation == "compress" else decompress_json(data)
        )
        with open(dest_path, "w", encoding="utf-8") as f:
            f.write(result)
        return True, f"Saved to {dest_path}"
    except FileNotFoundError:
        return False, f"File not found: {source_path}"
    except json.JSONDecodeError as e:
        return False, f"Invalid JSON: {e}"
    except Exception as e:
        return False, f"Error: {e}"


def process_clipboard_text(text, dest_path, operation):
    try:
        data = json.loads(text)
        result = (
            compress_json(data) if operation == "compress" else decompress_json(data)
        )
        with open(dest_path, "w", encoding="utf-8") as f:
            f.write(result)
        return True, f"Saved to {dest_path}"
    except json.JSONDecodeError as e:
        return False, f"Clipboard content is not valid JSON: {e}"
    except Exception as e:
        return False, f"Error: {e}"


# ---------- Event handlers ----------


def handle_action(item_id, action, rev):
    global state
    if state["screen"] == "root":
        if item_id in ("compress", "decompress"):
            state["operation"] = item_id
            state["screen"] = "form"
            # Initialize form values with defaults
            state["form_values"] = {
                "sourceType": "file",
                "file": "",
                "dest": "",
            }
            render_form(state["operation"], state["form_values"], rev=rev)
        else:
            # Unknown item, ignore
            pass
    elif state["screen"] == "form":
        # If we have any item actions (none currently), handle them
        pass


def handle_submit(values, button, rev):
    global state
    if state["screen"] != "form":
        return

    source_type = values.get("sourceType", "file")
    file_path = values.get("file", "").strip()
    dest_path = values.get("dest", "").strip()
    operation = state["operation"]

    # Validate
    if not dest_path:
        # Show error: re‑render form with an error on the dest field
        # We can't set field‑level error directly, so we can append a description?
        # Simpler: send a toast error and stay on form.
        send_command("toast", text="Destination path is required", style="error")
        # Re‑render form with same values (keeps user input)
        render_form(operation, values, rev=rev)
        return

    if source_type == "file" and not file_path:
        send_command("toast", text="Please select a file", style="error")
        render_form(operation, values, rev=rev)
        return

    # Process
    if source_type == "file":
        # Direct processing
        ok, msg = process_file(file_path, dest_path, operation)
        if ok:
            send_command("toast", text=msg, style="success")
            send_command("hide")
        else:
            send_command("toast", text=msg, style="error")
            # Stay on form
            render_form(operation, values, rev=rev)
    else:  # clipboard
        # Show loading spinner while we wait for clipboard
        render_form(operation, values, rev=rev, loading=True)

        # Send clipboardRead and store pending operation
        import uuid

        request_id = str(uuid.uuid4())
        state["pending_clipboard"][request_id] = {
            "dest": dest_path,
            "operation": operation,
            "values": values,  # to preserve form values if we need to re‑render on error
            "rev": rev,
        }
        send_command("clipboardRead", requestId=request_id)
        # The reply will come as a `clipboard` message; we'll handle it in main loop.


def handle_change(field_id, values, rev):
    global state
    if state["screen"] != "form":
        return

    # If file field changed, update destination automatically
    if field_id == "file":
        file_path = values.get("file", "")
        if file_path:
            new_dest = update_dest_from_file(file_path, state["operation"])
            if new_dest:
                # Update form_values and re‑render
                state["form_values"] = values.copy()
                state["form_values"]["dest"] = new_dest
                render_form(state["operation"], state["form_values"], rev=rev)
                return
    # For other changes (sourceType), we could adjust UI, but we just re‑render to keep values
    state["form_values"] = values.copy()
    render_form(state["operation"], state["form_values"], rev=rev)


def handle_clipboard_reply(request_id, text):
    pending = state["pending_clipboard"].get(request_id)
    if not pending:
        return
    dest = pending["dest"]
    operation = pending["operation"]
    values = pending["values"]
    rev = pending["rev"]

    # Remove from pending
    del state["pending_clipboard"][request_id]

    if text is None:
        # Clipboard read failed
        send_command("toast", text="Failed to read clipboard", style="error")
        render_form(operation, values, rev=rev)
        return

    ok, msg = process_clipboard_text(text, dest, operation)
    if ok:
        send_command("toast", text=msg, style="success")
        send_command("hide")
    else:
        send_command("toast", text=msg, style="error")
        # Re‑render form without loading
        render_form(operation, values, rev=rev)


def handle_back(rev):
    global state
    state["screen"] = "root"
    state["operation"] = None
    state["form_values"] = {
        "sourceType": "file",
        "file": "",
        "dest": "",
    }
    state["pending_clipboard"] = {}
    render_root(rev=rev)


def handle_query(text, rev):
    # If we are on root, we could filter items, but we have only two; just render root.
    # On form, we might want to ignore query or use it? Not used.
    if state["screen"] == "root":
        render_root(rev=rev)
    else:
        # Re‑render the form with current values (preserve user input)
        render_form(state["operation"], state["form_values"], rev=rev)


# ---------- Main loop ----------


def main():
    # Seed initial state
    state["screen"] = "root"
    state["operation"] = None
    state["form_values"] = {"sourceType": "file", "file": "", "dest": ""}
    state["pending_clipboard"] = {}

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue

        msg_type = msg.get("type")
        if msg_type == "close":
            break

        elif msg_type in ("init", "query"):
            rev = msg.get("rev", 0)
            text = msg.get("text", msg.get("query", ""))
            handle_query(text, rev)

        elif msg_type == "action":
            item_id = msg.get("id", "")
            action = msg.get("action", "default")
            rev = msg.get("rev", 0)
            handle_action(item_id, action, rev)

        elif msg_type == "submit":
            values = msg.get("values", {})
            button = msg.get("button")
            rev = msg.get("rev", 0)
            handle_submit(values, button, rev)

        elif msg_type == "change":
            field_id = msg.get("id", "")
            values = msg.get("values", {})
            rev = msg.get("rev", 0)
            handle_change(field_id, values, rev)

        elif msg_type == "back":
            rev = msg.get("rev", 0)
            handle_back(rev)

        elif msg_type == "clipboard":
            request_id = msg.get("requestId")
            text = msg.get("text")
            if request_id and request_id in state["pending_clipboard"]:
                handle_clipboard_reply(request_id, text)

        # Other message types ignored

    # Cleanup on EOF
    sys.exit(0)


if __name__ == "__main__":
    main()
