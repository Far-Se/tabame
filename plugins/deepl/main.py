#!/usr/bin/env python3
"""
DeepL Translate - a Tabame launcher plugin.

- Ctrl+K -> "Set API Key"        : store your DeepL API key (Credential Manager)
- Ctrl+K -> "Language Settings"  : pick default source + a predefined list of
                                    target languages (e.g. RO -> EN, ES, DE, IT)
- Ctrl+K -> "Check Usage"        : shows how many characters you've used this month

Typing:
    deepl bună ziua                -> translates into every predefined target language
    deepl bună ziua to es          -> one-off override: translate (auto-detect) to Spanish
    deepl hello there from en to es-> one-off override: translate from English to Spanish
"""
import sys
import json
import threading

try:
    import requests
except ImportError:  # pragma: no cover - Tabame installs this via "pip" in plugin.json
    requests = None

# --------------------------------------------------------------------------
# stdout / stderr helpers
# --------------------------------------------------------------------------

_LOCK = threading.Lock()


def send(frame):
    with _LOCK:
        sys.stdout.write(json.dumps(frame) + "\n")
        sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def command(**fields):
    send({"type": "command", **fields})


# --------------------------------------------------------------------------
# Language tables
# --------------------------------------------------------------------------

# (target code, display name) - what DeepL's target_lang accepts.
TARGET_LANGS = [
    ("EN-US", "English (American)"),
    ("EN-GB", "English (British)"),
    ("PT-PT", "Portuguese"),
    ("PT-BR", "Portuguese (Brazilian)"),
    ("AR", "Arabic"),
    ("BG", "Bulgarian"),
    ("CS", "Czech"),
    ("DA", "Danish"),
    ("DE", "German"),
    ("EL", "Greek"),
    ("ES", "Spanish"),
    ("ET", "Estonian"),
    ("FI", "Finnish"),
    ("FR", "French"),
    ("HE", "Hebrew"),
    ("HU", "Hungarian"),
    ("ID", "Indonesian"),
    ("IT", "Italian"),
    ("JA", "Japanese"),
    ("KO", "Korean"),
    ("LT", "Lithuanian"),
    ("LV", "Latvian"),
    ("NB", "Norwegian"),
    ("NL", "Dutch"),
    ("PL", "Polish"),
    ("RO", "Romanian"),
    ("RU", "Russian"),
    ("SK", "Slovak"),
    ("SL", "Slovenian"),
    ("SV", "Swedish"),
    ("TH", "Thai"),
    ("TR", "Turkish"),
    ("UK", "Ukrainian"),
    ("VI", "Vietnamese"),
    ("ZH", "Chinese"),
]
NAME_BY_TARGET = {c: n for c, n in TARGET_LANGS}
TARGET_CODE_SET = set(NAME_BY_TARGET)

# Base (source) codes - DeepL's source_lang has no regional variants.
BASE_NAMES = {
    "EN": "English",
    "PT": "Portuguese",
}
for _c, _n in TARGET_LANGS:
    base = _c.split("-")[0]
    BASE_NAMES.setdefault(base, _n)
BASE_CODE_SET = set(BASE_NAMES)

DEFAULT_VARIANT = {"EN": "EN-US", "PT": "PT-PT"}


def lang_name(code):
    code = (code or "").upper()
    return NAME_BY_TARGET.get(code) or BASE_NAMES.get(code) or code


def normalize_target(token):
    t = token.upper()
    if t in TARGET_CODE_SET:
        return t
    if t in DEFAULT_VARIANT:
        return DEFAULT_VARIANT[t]
    if t in BASE_CODE_SET:
        return t
    return None


def normalize_source(token):
    t = token.upper()
    return t if t in BASE_CODE_SET else None


# --------------------------------------------------------------------------
# "... to es" / "... from en to es" parsing
# --------------------------------------------------------------------------


def parse_override(raw):
    """Split trailing 'to <lang>' / 'from <lang> to <lang>' off raw text.

    Token-based (not regex) so an empty body ("to es" with nothing before
    it) still works. Returns (body, source_code_or_None, target_code_or_None).
    If the trailing tokens don't form a recognized language code, target_code
    is None and body is the original text untouched.
    """
    raw = (raw or "").strip()
    if not raw:
        return "", None, None
    tokens = raw.split()
    if len(tokens) >= 2 and tokens[-2].lower() == "to":
        to_norm = normalize_target(tokens[-1])
        if to_norm:
            rest = tokens[:-2]
            from_norm = None
            if len(rest) >= 2 and rest[-2].lower() == "from":
                cand = normalize_source(rest[-1])
                if cand:
                    from_norm = cand
                    rest = rest[:-2]
            body = " ".join(rest).strip()
            return body, from_norm, to_norm
    return raw, None, None


# --------------------------------------------------------------------------
# DeepL API
# --------------------------------------------------------------------------


class DeepLError(Exception):
    pass


def _api_base(key):
    return "https://api-free.deepl.com" if key.endswith(":fx") else "https://api.deepl.com"


def _auth_headers(key):
    return {"Authorization": "DeepL-Auth-Key %s" % key}


def deepl_translate(key, text, target_lang, source_lang=None):
    if requests is None:
        raise DeepLError("The 'requests' package is not installed.")
    data = {"text": text, "target_lang": target_lang}
    if source_lang:
        data["source_lang"] = source_lang
    try:
        resp = requests.post(
            _api_base(key) + "/v2/translate",
            headers=_auth_headers(key),
            data=data,
            timeout=15,
        )
    except requests.RequestException as e:
        raise DeepLError("Network error: %s" % e)
    if resp.status_code == 403:
        raise DeepLError("Invalid API key.")
    if resp.status_code == 456:
        raise DeepLError("DeepL quota exceeded for this billing period.")
    if resp.status_code != 200:
        msg = resp.text
        try:
            msg = resp.json().get("message", msg)
        except Exception:
            pass
        raise DeepLError("DeepL error %s: %s" % (resp.status_code, msg))
    try:
        return resp.json()["translations"][0]["text"]
    except (KeyError, IndexError, ValueError):
        raise DeepLError("Unexpected response from DeepL.")


def deepl_usage(key):
    if requests is None:
        raise DeepLError("The 'requests' package is not installed.")
    try:
        resp = requests.get(_api_base(key) + "/v2/usage", headers=_auth_headers(key), timeout=10)
    except requests.RequestException as e:
        raise DeepLError("Network error: %s" % e)
    if resp.status_code == 403:
        raise DeepLError("Invalid API key.")
    if resp.status_code != 200:
        raise DeepLError("DeepL error %s" % resp.status_code)
    return resp.json()


# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------

state = {
    "screen": "translate",  # "translate" | "key_form" | "settings_form"
    "api_key": None,        # None = not loaded yet, "" = loaded but unset
    "settings": None,       # None = not loaded yet, else {"source": "auto"|CODE, "targets":[...]}
    "loaded_key": False,
    "loaded_settings": False,
    "last_text": "",
    "last_results": [],
    "last_error": None,
}

FRAME_ACTIONS = [
    {"id": "settings", "title": "Language Settings", "icon": "settings"},
    {"id": "set_key", "title": "Set API Key", "icon": "key"},
    {"id": "usage", "title": "Check Usage", "icon": "chart"},
]
COPY_ALL_ACTION = {"id": "copy_all", "title": "Copy All Translations", "icon": "copy"}

PLACEHOLDER = "Type text to translate... (end with \"to es\" to override)"


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------


def render_translate(rev):
    if not (state["loaded_key"] and state["loaded_settings"]):
        send({
            "type": "render", "rev": rev, "view": "list",
            "loading": True, "loadingText": "Loading DeepL settings...",
            "items": [], "inputMode": "submit",
        })
        return

    if not state["api_key"]:
        state["screen"] = "key_form"
        render_key_form(setup=True)
        return

    settings = state["settings"] or {"source": "auto", "targets": []}
    targets = settings.get("targets") or []

    if not targets:
        state["screen"] = "settings_form"
        render_settings_form(setup=True)
        return

    if not state["last_text"]:
        items = [
            {"id": "lang:%s" % c, "title": lang_name(c), "subtitle": c, "icon": "language"}
            for c in targets
        ]
        send({
            "type": "render", "rev": rev, "view": "list",
            "items": items,
            "emptyText": "Type text and press Enter",
            "placeholder": PLACEHOLDER,
            "inputMode": "submit",
            "actions": FRAME_ACTIONS,
        })
        return

    if state["last_error"]:
        send({
            "type": "render", "rev": rev, "view": "list",
            "items": [], "inputMode": "submit",
            "placeholder": PLACEHOLDER,
            "actions": FRAME_ACTIONS,
            "empty": {"icon": "error", "title": "Translation failed", "hint": state["last_error"]},
        })
        return

    items = []
    for r in state["last_results"]:
        items.append({
            "id": "res:%s" % r["code"],
            "title": r["text"],
            "subtitle": r["name"],
            "icon": "translate",
            "lines": 3,
            "accessories": [{"text": r["code"]}],
            "actions": [{"id": "copy", "title": "Copy", "icon": "copy"}],
            "preview": {"markdown": "**%s** (`%s`)\n\n%s" % (r["name"], r["code"], r["text"])},
        })
    actions = FRAME_ACTIONS + ([COPY_ALL_ACTION] if len(items) > 1 else [])
    send({
        "type": "render", "rev": rev, "view": "list",
        "items": items,
        "placeholder": PLACEHOLDER,
        "inputMode": "submit",
        "preview": {"enabled": True},
        "actions": actions,
    })


def render_key_form(error=None, setup=False):
    if setup:
        title = "Connect your DeepL account"
        description = (
            "1) Sign up free at deepl.com/pro-api (500,000 characters/month, no card needed for "
            "the Free plan). 2) Open your DeepL account page and copy your Authentication Key. "
            "Free-tier keys end with \":fx\" - paste it below."
        )
    else:
        title = "DeepL API Key"
        description = "Free-tier keys end with \":fx\". Get one at deepl.com/pro-api."
    field = {
        "id": "api_key",
        "type": "password",
        "label": "DeepL API Key",
        "required": True,
        "placeholder": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx:fx",
        "description": description,
    }
    if error:
        field["error"] = error
    send({
        "type": "render", "rev": 0, "view": "form", "canGoBack": not setup,
        "form": {"title": title, "submitLabel": "Save", "fields": [field]},
    })


def render_settings_form(target_error=None, setup=False):
    settings = state["settings"] or {"source": "auto", "targets": []}
    source_options = [{"value": "auto", "label": "Auto-detect"}] + [
        {"value": c, "label": n} for c, n in sorted(BASE_NAMES.items(), key=lambda x: x[1])
    ]
    target_options = [{"value": c, "label": n} for c, n in sorted(TARGET_LANGS, key=lambda x: x[1])]
    targets_field = {
        "id": "targets",
        "type": "tags",
        "label": "Translate to (predefined languages)",
        "value": settings.get("targets", []),
        "options": target_options,
        "required": True,
        "description": (
            "Default languages to translate into. Override per search by ending your text "
            "with e.g. \"to es\" or \"from en to es\"."
        ),
    }
    if target_error:
        targets_field["error"] = target_error
    fields = [
        {
            "id": "source",
            "type": "dropdown",
            "label": "Translate from (default)",
            "value": settings.get("source", "auto"),
            "options": source_options,
            "description": "Used when no override is typed in the search.",
        },
        targets_field,
    ]
    title = "Choose your languages" if setup else "DeepL Language Settings"
    send({
        "type": "render", "rev": 0, "view": "form", "canGoBack": not setup,
        "form": {"title": title, "submitLabel": "Save", "fields": fields},
    })


# --------------------------------------------------------------------------
# Business logic (run on worker threads so stdin stays responsive)
# --------------------------------------------------------------------------


def do_translate(rev, raw_text):
    body, from_c, to_c = parse_override(raw_text)
    state["last_text"] = raw_text

    if not body.strip():
        state["last_results"] = []
        state["last_error"] = (
            'Add some text before the language code, e.g. "hello to es".' if to_c else None
        )
        render_translate(rev)
        return

    send({
        "type": "render", "rev": rev, "view": "list",
        "loading": True, "loadingText": "Translating...", "items": [], "inputMode": "submit",
    })

    settings = state["settings"] or {"source": "auto", "targets": []}
    if to_c:
        targets = [to_c]
        source = from_c
    else:
        targets = settings.get("targets") or []
        source = None if settings.get("source", "auto") == "auto" else settings.get("source")

    if not targets:
        state["last_results"] = []
        state["last_error"] = (
            'No default target languages set. Press Ctrl+K -> Language Settings, '
            'or end your text with e.g. "to es".'
        )
        render_translate(rev)
        return

    results = []
    try:
        for code in targets:
            text = deepl_translate(state["api_key"], body, code, source)
            results.append({"code": code, "name": lang_name(code), "text": text})
        state["last_results"] = results
        state["last_error"] = None
    except DeepLError as e:
        state["last_results"] = []
        state["last_error"] = str(e)
    except Exception as e:  # pragma: no cover - defensive
        state["last_results"] = []
        state["last_error"] = "Unexpected error: %s" % e

    render_translate(rev)


def do_save_key(raw_key, is_setup):
    key = (raw_key or "").strip()
    if not key:
        render_key_form(error="API key is required.", setup=is_setup)
        return
    try:
        usage = deepl_usage(key)
    except DeepLError as e:
        render_key_form(error=str(e), setup=is_setup)
        return
    except Exception as e:  # pragma: no cover - defensive
        render_key_form(error="Unexpected error: %s" % e, setup=is_setup)
        return

    command(command="storage", op="set", key="api_key", value=key, secret=True)
    state["api_key"] = key
    used = usage.get("character_count")
    limit = usage.get("character_limit")
    if isinstance(used, int) and isinstance(limit, int):
        command(command="toast", text="API key saved - %s / %s characters used this month" % (
            format(used, ","), format(limit, ",")))
    else:
        command(command="toast", text="API key saved")

    settings = state["settings"] or {}
    if not (settings.get("targets") or []):
        state["screen"] = "settings_form"
        render_settings_form(setup=True)
    else:
        state["screen"] = "translate"
        render_translate(0)


def do_check_usage():
    if not state["api_key"]:
        command(command="toast", text="Set an API key first", style="error")
        return
    try:
        usage = deepl_usage(state["api_key"])
    except DeepLError as e:
        command(command="toast", text=str(e), style="error")
        return
    used = usage.get("character_count", 0)
    limit = usage.get("character_limit", 0)
    command(command="toast", text="%s / %s characters used this month" % (
        format(used, ","), format(limit, ",")), style="info")


# --------------------------------------------------------------------------
# Action / submit handlers
# --------------------------------------------------------------------------


def handle_action(item_id, action):
    if item_id == "":
        if action == "set_key":
            state["screen"] = "key_form"
            render_key_form(setup=False)
        elif action == "settings":
            state["screen"] = "settings_form"
            render_settings_form(setup=False)
        elif action == "usage":
            threading.Thread(target=do_check_usage, daemon=True).start()
        elif action == "copy_all":
            combined = "\n".join("%s: %s" % (r["name"], r["text"]) for r in state["last_results"])
            if combined:
                command(command="copy", text=combined)
        return

    if item_id.startswith("res:"):
        code = item_id[4:]
        match = next((r for r in state["last_results"] if r["code"] == code), None)
        if match:
            command(command="copy", text=match["text"])
    # "lang:*" idle hint rows: no-op


def handle_submit(values, button):
    if state["screen"] == "key_form":
        is_setup = not state["api_key"]
        threading.Thread(
            target=do_save_key, args=(values.get("api_key", ""), is_setup), daemon=True
        ).start()
    elif state["screen"] == "settings_form":
        was_setup = not ((state["settings"] or {}).get("targets"))
        targets = values.get("targets") or []
        source = values.get("source") or "auto"
        if not targets:
            render_settings_form(target_error="Pick at least one language.", setup=was_setup)
            return
        state["settings"] = {"source": source, "targets": targets}
        command(command="storage", op="set", key="settings", value=json.dumps(state["settings"]), secret=False)
        command(command="toast", text="Settings saved")
        state["screen"] = "translate"
        render_translate(0)


def handle_back():
    state["screen"] = "translate"
    render_translate(0)


def handle_storage(msg):
    rid = msg.get("requestId")
    if rid == "key":
        state["api_key"] = msg.get("value") or ""
        state["loaded_key"] = True
    elif rid == "settings":
        raw = msg.get("value")
        settings = {}
        if raw:
            try:
                settings = json.loads(raw)
            except Exception:
                settings = {}
        settings.setdefault("source", "auto")
        settings.setdefault("targets", [])
        state["settings"] = settings
        state["loaded_settings"] = True
    if state["screen"] == "translate" and state["loaded_key"] and state["loaded_settings"]:
        render_translate(0)


def fallback_defaults():
    changed = False
    if not state["loaded_key"]:
        state["api_key"] = state["api_key"] or ""
        state["loaded_key"] = True
        changed = True
    if not state["loaded_settings"]:
        state["settings"] = state["settings"] or {"source": "auto", "targets": []}
        state["loaded_settings"] = True
        changed = True
    if changed and state["screen"] == "translate":
        render_translate(0)


# --------------------------------------------------------------------------
# Main loop
# --------------------------------------------------------------------------


def main():
    command(command="storage", op="get", key="api_key", secret=True, requestId="key")
    command(command="storage", op="get", key="settings", secret=False, requestId="settings")
    timer = threading.Timer(3.0, fallback_defaults)
    timer.daemon = True
    timer.start()

    render_translate(0)

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
            if state["screen"] == "translate":
                render_translate(msg.get("rev", 0))
        elif t == "submitQuery":
            if state["screen"] == "translate":
                threading.Thread(
                    target=do_translate,
                    args=(msg.get("rev", 0), msg.get("text", "")),
                    daemon=True,
                ).start()
        elif t == "action":
            handle_action(msg.get("id", ""), msg.get("action", "default"))
        elif t == "submit":
            handle_submit(msg.get("values", {}) or {}, msg.get("button"))
        elif t == "back":
            handle_back()
        elif t == "storage":
            handle_storage(msg)
        # "select", "tab", "clipboard": not needed by this plugin


if __name__ == "__main__":
    main()
