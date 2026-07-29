#!/usr/bin/env python3
"""
Spell Check & Dictionary — Tabame launcher plugin.

Type `sp <word or sentence>` to get spelling suggestions. Misspelled words
get ranked corrections; a personal "custom dictionary" lets you teach it
words (names, slang, jargon) it should stop flagging.
"""
import sys
import json
import os
import re
import threading

from spellchecker import SpellChecker

PLUGIN_DIR = os.path.dirname(os.path.abspath(__file__))
DICT_FILE = os.path.join(PLUGIN_DIR, "custom_words.json")

spell = SpellChecker(distance=2)  # loaded once per process start

WORD_RE = re.compile(r"[A-Za-z']+")
MAX_SUGGESTIONS = 6

# ---------------------------------------------------------------- storage --

def load_custom_words():
    if os.path.exists(DICT_FILE):
        try:
            with open(DICT_FILE, encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, list):
                    return set(w.lower() for w in data if isinstance(w, str))
        except Exception as e:
            log("failed to load custom_words.json:", e)
    return set()


def save_custom_words():
    try:
        with open(DICT_FILE, "w", encoding="utf-8") as f:
            json.dump(sorted(custom_words), f, ensure_ascii=False, indent=2)
    except Exception as e:
        log("failed to save custom_words.json:", e)


custom_words = load_custom_words()

# --------------------------------------------------------------- protocol --

_stdout_lock = threading.Lock()


def send(frame):
    with _stdout_lock:
        sys.stdout.write(json.dumps(frame) + "\n")
        sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def command(cmd, **fields):
    send({"type": "command", "command": cmd, **fields})


# ------------------------------------------------------------ spellcheck --

def tokenize(text):
    """Split into (is_word, chunk) pairs, preserving separators so the
    original sentence can be rebuilt exactly."""
    tokens = []
    last = 0
    for m in WORD_RE.finditer(text):
        if m.start() > last:
            tokens.append((False, text[last:m.start()]))
        tokens.append((True, m.group()))
        last = m.end()
    if last < len(text):
        tokens.append((False, text[last:]))
    return tokens


def preserve_case(original, replacement):
    if original.isupper() and len(original) > 1:
        return replacement.upper()
    if original[:1].isupper():
        return replacement[:1].upper() + replacement[1:]
    return replacement


def should_skip(word):
    # Skip acronyms, numbers, and single letters — too noisy to flag.
    if len(word) <= 1:
        return True
    if any(ch.isdigit() for ch in word):
        return True
    if word.isupper() and len(word) > 1:
        return True
    return False


def suggestions_for(lower_word):
    """Returns None if considered correct, otherwise a ranked list of
    candidate corrections (best first), possibly empty."""
    if lower_word in custom_words:
        return None
    if should_skip(lower_word):
        return None
    if spell.known([lower_word]):
        return None
    cands = spell.candidates(lower_word)
    if not cands:
        return []
    ranked = sorted(cands, key=lambda w: -spell.word_frequency[w])
    return ranked[:MAX_SUGGESTIONS]


def analyze(text):
    """Returns (tokens, per_lower_suggestions dict, ordered unique misspelled
    lower-words with their first-seen original casing)."""
    tokens = tokenize(text)
    cache = {}
    ordered_misspelled = []  # list of (lower, original_display)
    seen = set()
    for is_word, chunk in tokens:
        if not is_word:
            continue
        lower = chunk.lower()
        if lower not in cache:
            cache[lower] = suggestions_for(lower)
        if cache[lower] is not None and lower not in seen:
            seen.add(lower)
            ordered_misspelled.append((lower, chunk))
    return tokens, cache, ordered_misspelled


def corrected_sentence(tokens, cache):
    out = []
    for is_word, chunk in tokens:
        if not is_word:
            out.append(chunk)
            continue
        lower = chunk.lower()
        sugg = cache.get(lower)
        if sugg:
            out.append(preserve_case(chunk, sugg[0]))
        else:
            out.append(chunk)
    return "".join(out)


# ------------------------------------------------------------------ state --

state = {"screen": "check"}          # "check" | "dict" | "dict_add"
last_check = {"text": "", "tokens": [], "cache": {}, "misspelled": []}


def switch_screen(screen):
    state["screen"] = screen
    command("setQuery", text="")


# --------------------------------------------------------------- renders --

def render_check(rev, text):
    tokens, cache, misspelled = analyze(text)
    last_check.update(text=text, tokens=tokens, cache=cache, misspelled=misspelled)

    frame_actions = [
        {"id": "manage_dict", "title": "Manage custom dictionary", "icon": "book",
         "shortcut": "ctrl+alt+d"},
    ]

    if not tokens:
        send({
            "type": "render", "rev": rev, "view": "list",
            "placeholder": "Type a word or sentence to check…",
            "empty": {
                "icon": "edit",
                "title": "Type something to spell-check",
                "hint": "e.g. \"teh recursevly mispeling\"",
            },
            "actions": frame_actions,
            "items": [],
        })
        return

    if not misspelled:
        send({
            "type": "render", "rev": rev, "view": "list",
            "placeholder": "Type a word or sentence to check…",
            "empty": {
                "icon": "check",
                "title": "No spelling issues found",
                "hint": text if len(text) < 60 else text[:57] + "…",
            },
            "actions": frame_actions,
            "items": [],
        })
        return

    items = []
    for lower, original in misspelled:
        sugg = cache[lower]
        if not sugg:
            items.append({
                "id": f"w:{lower}",
                "title": f"**{original}** — no suggestions found",
                "subtitle": "Not in the dictionary, and no close match either",
                "icon": "help",
                "accessories": [{"text": "unknown", "color": "#9CA3AF"}],
                "actions": [
                    {"id": "add_word", "title": f"Add \"{original}\" to dictionary",
                     "icon": "add", "shortcut": "ctrl+alt+a"},
                ],
            })
            continue

        top = sugg[0]
        alts = sugg[1:4]
        subtitle = f"Also: {', '.join(alts)}" if alts else "Best guess"
        actions = [
            {"id": "copy0", "title": f"Copy \"{preserve_case(original, top)}\"", "icon": "copy"},
        ]
        for i, alt in enumerate(alts, start=1):
            actions.append({
                "id": f"paste{i}",
                "title": f"Use \"{preserve_case(original, alt)}\" instead",
                "icon": "edit",
            })
        actions.append({
            "id": "add_word", "title": f"Add \"{original}\" to dictionary (keep as-is)",
            "icon": "add", "shortcut": "ctrl+alt+a",
        })

        items.append({
            "id": f"w:{lower}",
            "title": f"**{original}** → {preserve_case(original, top)}",
            "subtitle": subtitle,
            "icon": "warning",
            "accessories": [{"text": "misspelled", "color": "#DC2626"}],
            "actions": actions,
        })

    frame_actions = [
        {"id": "fix_copy", "title": "Copy corrected sentence", "icon": "copy",
         "shortcut": "ctrl+alt+c"},
        {"id": "fix_paste", "title": "Paste corrected sentence", "icon": "paste",
         "shortcut": "ctrl+alt+v"},
    ] + frame_actions

    send({
        "type": "render", "rev": rev, "view": "list",
        "placeholder": "Type a word or sentence to check…",
        "emptyText": "No results",
        "actions": frame_actions,
        "items": items,
    })


def render_dict(rev, filter_text):
    words = sorted(w for w in custom_words if filter_text.lower() in w)
    items = [
        {
            "id": f"cw:{w}",
            "title": w,
            "icon": "book",
            "actions": [
                {"id": "remove", "title": "Remove", "icon": "trash",
                 "destructive": True,
                 "confirm": {"title": f"Remove \"{w}\"?",
                             "message": "It will be flagged as a misspelling again.",
                             "confirmLabel": "Remove"}},
            ],
        }
        for w in words
    ]
    send({
        "type": "render", "rev": rev, "view": "list",
        "canGoBack": True,
        "placeholder": "Search your custom dictionary…",
        "empty": {
            "icon": "book",
            "title": "No custom words yet",
            "hint": "Add words from the spell-check screen, or add one here",
            "action": {"id": "add_word_form", "title": "Add a word", "icon": "add"},
        },
        "actions": [
            {"id": "add_word_form", "title": "Add a word", "icon": "add",
             "shortcut": "ctrl+alt+a"},
        ],
        "items": items,
    })


def render_dict_add():
    send({
        "type": "render", "rev": 0, "view": "form",
        "canGoBack": True,
        "form": {
            "title": "Add words to your dictionary",
            "submitLabel": "Add",
            "fields": [
                {
                    "id": "words", "type": "text", "label": "Word(s)",
                    "placeholder": "e.g. tabame, kubectl, iasi",
                    "required": True,
                    "description": "Separate multiple words with commas or spaces",
                },
            ],
        },
    })


# ---------------------------------------------------------------- actions --

def handle_check_action(item_id, action):
    if item_id == "" :
        if action == "fix_copy":
            text = corrected_sentence(last_check["tokens"], last_check["cache"])
            command("copy", text=text)
        elif action == "fix_paste":
            text = corrected_sentence(last_check["tokens"], last_check["cache"])
            command("paste", text=text)
        elif action == "manage_dict":
            switch_screen("dict")
            render_dict(0, "")
        return

    if not item_id.startswith("w:"):
        return
    lower = item_id[2:]
    original = next((o for l, o in last_check["misspelled"] if l == lower), lower)
    sugg = last_check["cache"].get(lower) or []

    if action == "add_word":
        custom_words.add(lower)
        save_custom_words()
        command("toast", text=f"Added \"{original}\" to your dictionary")
        render_check(0, last_check["text"])
        return

    if action == "default" or action == "paste0" or action == "copy0":
        if not sugg:
            return
        top = preserve_case(original, sugg[0])
        if action == "copy0":
            command("copy", text=top)
        else:
            command("paste", text=top)
        return

    if action.startswith("paste") and action[5:].isdigit():
        idx = int(action[5:])
        if 0 <= idx < len(sugg):
            command("paste", text=preserve_case(original, sugg[idx]))
        return


def handle_dict_action(item_id, action):
    if item_id == "" and action == "add_word_form":
        switch_screen("dict_add")
        render_dict_add()
        return
    if item_id.startswith("cw:") and action == "remove":
        word = item_id[3:]
        custom_words.discard(word)
        save_custom_words()
        command("toast", text=f"Removed \"{word}\"")
        render_dict(0, "")
        return
    if item_id == "" and action == "":
        return


def handle_dict_add_submit(values):
    raw = (values or {}).get("words", "") or ""
    words = [w.lower() for w in re.split(r"[,\s]+", raw) if w.strip()]
    words = [w for w in words if WORD_RE.fullmatch(w)]
    added = 0
    for w in words:
        if w not in custom_words:
            custom_words.add(w)
            added += 1
    if added:
        save_custom_words()
    switch_screen("dict")
    render_dict(0, "")
    command("toast", text=f"Added {added} word(s)" if added else "No new words added")


# ---------------------------------------------------------------- main() --

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

        elif t in ("init", "query"):
            rev = msg.get("rev", 0)
            text = msg.get("text", msg.get("query", ""))
            if state["screen"] == "check":
                render_check(rev, text)
            elif state["screen"] == "dict":
                render_dict(rev, text)
            # dict_add: query events are ignored — form owns input

        elif t == "action":
            item_id = msg.get("id", "")
            action = msg.get("action", "default")
            if state["screen"] == "check":
                handle_check_action(item_id, action)
            elif state["screen"] == "dict":
                handle_dict_action(item_id, action)

        elif t == "submit":
            if state["screen"] == "dict_add":
                handle_dict_add_submit(msg.get("values", {}))

        elif t == "back":
            if state["screen"] == "dict_add":
                switch_screen("dict")
                render_dict(0, "")
            elif state["screen"] == "dict":
                switch_screen("check")
                render_check(0, "")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        log("fatal:", e)
