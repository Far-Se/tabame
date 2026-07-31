#!/usr/bin/env python3
"""
Google Translate - a Tabame launcher plugin.

Uses Google Translate's public web endpoint (translate.google.com), the same
one the browser page itself uses - no API key, no account, no quota. The
token-generation and request logic is a straight Python port of
https://github.com/iamtraction/google-translate (MIT).

- Ctrl+K -> "Language Settings"  : pick default source + a predefined list of
                                    target languages (e.g. RO -> EN, ES, DE, IT)

Typing:
    gt buna ziua                  -> translates into every predefined target language
    gt buna ziua to es            -> one-off override: translate (auto-detect) to Spanish
    gt hello there from en to es  -> one-off override: translate from English to Spanish
"""

import json
import queue
import re
import sys
import threading
import time

try:
    import requests
except ImportError:  # pragma: no cover - Tabame installs this via "pip" in plugin.json
    requests = None

# --------------------------------------------------------------------------
# stdout / stderr helpers
# --------------------------------------------------------------------------

_LOCK = threading.Lock()
_RENDER_LOCK = threading.Lock()


def send(frame):
    with _LOCK:
        sys.stdout.write(json.dumps(frame) + "\n")
        sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def command(**fields):
    send({"type": "command", **fields})


# --------------------------------------------------------------------------
# Languages (ported from languages.ts - Google Translate's supported set)
# --------------------------------------------------------------------------

LANGUAGES = {
    "auto": "Auto-Detect",
    "ab": "Abkhaz",
    "ace": "Acehnese",
    "ach": "Acholi",
    "aa": "Afar",
    "af": "Afrikaans",
    "sq": "Albanian",
    "alz": "Alur",
    "am": "Amharic",
    "ar": "Arabic",
    "hy": "Armenian",
    "as": "Assamese",
    "av": "Avar",
    "awa": "Awadhi",
    "ay": "Aymara",
    "az": "Azerbaijani",
    "ban": "Balinese",
    "bal": "Baluchi",
    "bm": "Bambara",
    "bci": "Baoul\u00e9",
    "ba": "Bashkir",
    "eu": "Basque",
    "btx": "Batak Karo",
    "bts": "Batak Simalungun",
    "bbc": "Batak Toba",
    "be": "Belarusian",
    "bem": "Bemba",
    "bn": "Bengali",
    "bew": "Betawi",
    "bho": "Bhojpuri",
    "bik": "Bikol",
    "bs": "Bosnian",
    "br": "Breton",
    "bg": "Bulgarian",
    "bua": "Buryat",
    "yue": "Cantonese",
    "ca": "Catalan",
    "ceb": "Cebuano",
    "ch": "Chamorro",
    "ce": "Chechen",
    "ny": "Chichewa",
    "zh-CN": "Chinese (Simplified)",
    "zh-TW": "Chinese (Traditional)",
    "chk": "Chuukese",
    "cv": "Chuvash",
    "co": "Corsican",
    "crh": "Crimean Tatar (Cyrillic)",
    "crh-Latn": "Crimean Tatar (Latin)",
    "hr": "Croatian",
    "cs": "Czech",
    "da": "Danish",
    "fa-AF": "Dari",
    "dv": "Dhivehi",
    "din": "Dinka",
    "doi": "Dogri",
    "dov": "Dombe",
    "nl": "Dutch",
    "dyu": "Dyula",
    "dz": "Dzongkha",
    "en": "English",
    "eo": "Esperanto",
    "et": "Estonian",
    "ee": "Ewe",
    "fo": "Faroese",
    "fj": "Fijian",
    "tl": "Filipino",
    "fi": "Finnish",
    "fon": "Fon",
    "fr": "French",
    "fr-CA": "French (Canada)",
    "fy": "Frisian",
    "fur": "Friulian",
    "ff": "Fulani",
    "gaa": "Ga",
    "gl": "Galician",
    "ka": "Georgian",
    "de": "German",
    "el": "Greek",
    "gn": "Guarani",
    "gu": "Gujarati",
    "ht": "Haitian Creole",
    "cnh": "Hakha Chin",
    "ha": "Hausa",
    "haw": "Hawaiian",
    "iw": "Hebrew",
    "hil": "Hiligaynon",
    "hi": "Hindi",
    "hmn": "Hmong",
    "hu": "Hungarian",
    "hrx": "Hunsrik",
    "iba": "Iban",
    "is": "Icelandic",
    "ig": "Igbo",
    "ilo": "Ilocano",
    "id": "Indonesian",
    "iu-Latn": "Inuktut (Latin)",
    "iu": "Inuktut (Syllabics)",
    "ga": "Irish",
    "it": "Italian",
    "jam": "Jamaican Patois",
    "ja": "Japanese",
    "jv": "Javanese",
    "kac": "Jingpo",
    "kl": "Kalaallisut",
    "kn": "Kannada",
    "kr": "Kanuri",
    "pam": "Kapampangan",
    "kk": "Kazakh",
    "kha": "Khasi",
    "km": "Khmer",
    "cgg": "Kiga",
    "kg": "Kikongo",
    "rw": "Kinyarwanda",
    "ktu": "Kituba",
    "trp": "Kokborok",
    "kv": "Komi",
    "gom": "Konkani",
    "ko": "Korean",
    "kri": "Krio",
    "ku": "Kurdish (Kurmanji)",
    "ckb": "Kurdish (Sorani)",
    "ky": "Kyrgyz",
    "lo": "Lao",
    "ltg": "Latgalian",
    "la": "Latin",
    "lv": "Latvian",
    "lij": "Ligurian",
    "li": "Limburgish",
    "ln": "Lingala",
    "lt": "Lithuanian",
    "lmo": "Lombard",
    "lg": "Luganda",
    "luo": "Luo",
    "lb": "Luxembourgish",
    "mk": "Macedonian",
    "mad": "Madurese",
    "mai": "Maithili",
    "mak": "Makassar",
    "mg": "Malagasy",
    "ms": "Malay",
    "ms-Arab": "Malay (Jawi)",
    "ml": "Malayalam",
    "mt": "Maltese",
    "mam": "Mam",
    "gv": "Manx",
    "mi": "Maori",
    "mr": "Marathi",
    "mh": "Marshallese",
    "mwr": "Marwadi",
    "mfe": "Mauritian Creole",
    "chm": "Meadow Mari",
    "mni-Mtei": "Meiteilon (Manipuri)",
    "min": "Minang",
    "lus": "Mizo",
    "mn": "Mongolian",
    "my": "Myanmar (Burmese)",
    "bm-Nkoo": "NKo",
    "nhe": "Nahuatl (Eastern Huasteca)",
    "ndc-ZW": "Ndau",
    "nr": "Ndebele (South)",
    "new": "Nepalbhasa (Newari)",
    "ne": "Nepali",
    "no": "Norwegian",
    "nus": "Nuer",
    "oc": "Occitan",
    "or": "Odia (Oriya)",
    "om": "Oromo",
    "os": "Ossetian",
    "pag": "Pangasinan",
    "pap": "Papiamento",
    "ps": "Pashto",
    "fa": "Persian",
    "pl": "Polish",
    "pt": "Portuguese (Brazil)",
    "pt-PT": "Portuguese (Portugal)",
    "pa": "Punjabi (Gurmukhi)",
    "pa-Arab": "Punjabi (Shahmukhi)",
    "qu": "Quechua",
    "kek": "Q\u02bceqchi\u02bc",
    "rom": "Romani",
    "ro": "Romanian",
    "rn": "Rundi",
    "ru": "Russian",
    "se": "Sami (North)",
    "sm": "Samoan",
    "sg": "Sango",
    "sa": "Sanskrit",
    "sat-Latn": "Santali (Latin)",
    "sat": "Santali (Ol Chiki)",
    "gd": "Scots Gaelic",
    "nso": "Sepedi",
    "sr": "Serbian",
    "st": "Sesotho",
    "crs": "Seychellois Creole",
    "shn": "Shan",
    "sn": "Shona",
    "scn": "Sicilian",
    "szl": "Silesian",
    "sd": "Sindhi",
    "si": "Sinhala",
    "sk": "Slovak",
    "sl": "Slovenian",
    "so": "Somali",
    "es": "Spanish",
    "su": "Sundanese",
    "sus": "Susu",
    "sw": "Swahili",
    "ss": "Swati",
    "sv": "Swedish",
    "ty": "Tahitian",
    "tg": "Tajik",
    "ber-Latn": "Tamazight",
    "ber": "Tamazight (Tifinagh)",
    "ta": "Tamil",
    "tt": "Tatar",
    "te": "Telugu",
    "tet": "Tetum",
    "th": "Thai",
    "bo": "Tibetan",
    "ti": "Tigrinya",
    "tiv": "Tiv",
    "tpi": "Tok Pisin",
    "to": "Tongan",
    "lua": "Tshiluba",
    "ts": "Tsonga",
    "tn": "Tswana",
    "tcy": "Tulu",
    "tum": "Tumbuka",
    "tr": "Turkish",
    "tk": "Turkmen",
    "tyv": "Tuvan",
    "ak": "Twi",
    "udm": "Udmurt",
    "uk": "Ukrainian",
    "ur": "Urdu",
    "ug": "Uyghur",
    "uz": "Uzbek",
    "ve": "Venda",
    "vec": "Venetian",
    "vi": "Vietnamese",
    "war": "Waray",
    "cy": "Welsh",
    "wo": "Wolof",
    "xh": "Xhosa",
    "sah": "Yakut",
    "yi": "Yiddish",
    "yo": "Yoruba",
    "yua": "Yucatec Maya",
    "zap": "Zapotec",
    "zu": "Zulu",
}

LANGUAGES_LOWER = {k.lower(): k for k in LANGUAGES}
NAME_TO_CODE = {v.lower(): k for k, v in LANGUAGES.items()}

# A short, commonly-used subset offered as quick-pick target options in the
# settings form (the full list above is still searchable by typing).
COMMON_TARGETS = [
    "en",
    "es",
    "fr",
    "de",
    "it",
    "pt",
    "pt-PT",
    "ro",
    "ru",
    "nl",
    "pl",
    "tr",
    "ar",
    "zh-CN",
    "zh-TW",
    "ja",
    "ko",
    "vi",
    "th",
    "hi",
    "uk",
    "sv",
    "da",
    "no",
    "fi",
    "cs",
    "el",
    "iw",
]
COMMON_TARGETS = [c for c in dict.fromkeys(COMMON_TARGETS) if c in LANGUAGES]


def lang_name(code):
    return LANGUAGES.get(code, code)


def get_iso_code(token):
    """Port of languages.ts getISOCode(): match by code (any case) or by
    display name (any case)."""
    if not token:
        return None
    if token in LANGUAGES:
        return token
    low = token.lower()
    if low in LANGUAGES_LOWER:
        return LANGUAGES_LOWER[low]
    if low in NAME_TO_CODE:
        return NAME_TO_CODE[low]
    return None


# --------------------------------------------------------------------------
# "... to es" / "... from en to es" parsing
# --------------------------------------------------------------------------


def parse_override(raw):
    """Split trailing 'to <lang>' / 'from <lang> to <lang>' off raw text.

    Returns (body, source_code_or_None, target_code_or_None). If the trailing
    tokens don't form a recognized language code, target_code is None and
    body is the original text untouched.
    """
    raw = (raw or "").strip()
    if not raw:
        return "", None, None
    tokens = raw.split()
    if len(tokens) >= 2 and tokens[-2].lower() == "to":
        to_code = get_iso_code(tokens[-1])
        if to_code and to_code != "auto":
            rest = tokens[:-2]
            from_code = None
            if len(rest) >= 2 and rest[-2].lower() == "from":
                cand = get_iso_code(rest[-1])
                if cand:
                    from_code = cand
                    rest = rest[:-2]
            body = " ".join(rest).strip()
            return body, from_code, to_code
    return raw, None, None


# --------------------------------------------------------------------------
# Google Translate token generator (ported from tokenGenerator.ts)
# --------------------------------------------------------------------------

_tkk_lock = threading.Lock()
_tkk_refresh_lock = threading.Lock()
_tkk = {"value": "0"}


class GoogleTranslateError(Exception):
    pass


def _update_tkk():
    # The translation queue can start three requests together. Refresh the
    # shared token only once, then let the other workers reuse it.
    with _tkk_refresh_lock:
        now_hour = int(time.time() // 3600)
        with _tkk_lock:
            current = _tkk["value"]
        try:
            current_hour = int(current.split(".")[0])
        except (ValueError, IndexError):
            current_hour = 0
        if current_hour == now_hour:
            return
        try:
            resp = requests.get(
                "https://translate.google.com",
                timeout=10,
                headers={"User-Agent": "Mozilla/5.0"},
            )
            resp.raise_for_status()
            match = re.search(r"tkk:'(\d+\.\d+)'", resp.text)
            if match:
                with _tkk_lock:
                    _tkk["value"] = match.group(1)
        except requests.RequestException as e:
            raise GoogleTranslateError("Could not reach Google Translate: %s" % e)


def _xr(a, b):
    c = 0
    n = len(b)
    while c < n - 2:
        d = b[c + 2]
        e = ord(d) - 87 if d >= "a" else int(d)
        if b[c + 1] == "+":
            e = (a % 0x100000000) >> e
        else:
            e = (a << e) & 0xFFFFFFFF
        if b[c] == "+":
            a = (a + e) & 4294967295
        else:
            a = a ^ e
        c += 3
    return a


def _acquire_token(text):
    _update_tkk()
    with _tkk_lock:
        tkk = _tkk["value"]
    lst = tkk.split(".")
    first_seed = int(lst[0]) if lst and lst[0] else 0
    second_seed = int(lst[1]) if len(lst) > 1 and lst[1] else 0

    d = []
    for ch in text:
        code = ord(ch)
        if code < 128:
            d.append(code)
        elif code < 2048:
            d.append((code >> 6) | 192)
            d.append((code & 63) | 128)
        else:
            if code > 0xFFFF:
                d.append((code >> 18) | 240)
                d.append(((code >> 12) & 63) | 128)
            else:
                d.append((code >> 12) | 224)
            d.append(((code >> 6) & 63) | 128)
            d.append((code & 63) | 128)

    a = first_seed
    for value in d:
        a += value
        a = _xr(a, "+-a^+6")
    a = _xr(a, "+-3^+b+-f")
    a ^= second_seed
    if a < 0:
        a = (a & 2147483647) + 2147483648
    a %= 1000000
    return "%d.%d" % (a, a ^ first_seed)


# --------------------------------------------------------------------------
# Google Translate request (ported from index.ts)
# --------------------------------------------------------------------------


def google_translate(text, target, source="auto"):
    if requests is None:
        raise GoogleTranslateError("The 'requests' package is not installed.")

    token = _acquire_token(text)
    params = [
        ("client", "gtx"),
        ("sl", source or "auto"),
        ("tl", target),
        ("hl", target),
        ("dt", "at"),
        ("dt", "bd"),
        ("dt", "ex"),
        ("dt", "ld"),
        ("dt", "md"),
        ("dt", "qca"),
        ("dt", "rw"),
        ("dt", "rm"),
        ("dt", "ss"),
        ("dt", "t"),
        ("ie", "UTF-8"),
        ("oe", "UTF-8"),
        ("otf", "1"),
        ("ssel", "0"),
        ("tsel", "0"),
        ("kc", "7"),
        ("q", text),
        ("tk", token),
    ]
    try:
        resp = requests.get(
            "https://translate.google.com/translate_a/single",
            params=params,
            timeout=15,
            headers={"User-Agent": "Mozilla/5.0"},
        )
    except requests.RequestException as e:
        raise GoogleTranslateError("Network error: %s" % e)

    if resp.status_code != 200:
        raise GoogleTranslateError("Google Translate error %s" % resp.status_code)

    try:
        body = resp.json()
    except ValueError:
        raise GoogleTranslateError("Unexpected response from Google Translate.")

    try:
        translated = "".join(seg[0] for seg in body[0] if seg and seg[0])
    except (IndexError, TypeError):
        raise GoogleTranslateError("Unexpected response from Google Translate.")

    detected = None
    try:
        if body[2] == body[8][0][0]:
            detected = body[2]
        else:
            detected = body[8][0][0]
    except (IndexError, TypeError):
        detected = body[2] if len(body) > 2 else None

    return translated, detected


# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------

state = {
    "screen": "translate",  # "translate" | "settings_form"
    "settings": None,  # None = not loaded yet, else {"source": "auto"|CODE, "targets":[...]}
    "loaded_settings": False,
    "last_text": "",
    "last_results": [],
    "last_detected": None,
    "last_error": None,
    "translation_id": 0,
    "translation_targets": [],
    "translation_errors": {},
    "active_targets": set(),
    "translating": False,
}
_STATE_LOCK = threading.RLock()
_TRANSLATION_QUEUE = queue.PriorityQueue()
_TRANSLATION_WORKERS_STARTED = False
_TRANSLATION_WORKERS_LOCK = threading.Lock()

FRAME_ACTIONS = [
    {"id": "settings", "title": "Language Settings", "icon": "settings"},
]
COPY_ALL_ACTION = {"id": "copy_all", "title": "Copy All Translations", "icon": "copy"}

PLACEHOLDER = 'Type text to translate... (end with "to es" to override)'


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------


def render_translate(rev):
    with _RENDER_LOCK:
        with _STATE_LOCK:
            _render_translate(rev)


def _render_translate(rev):
    if state["screen"] != "translate":
        return

    if not state["loaded_settings"]:
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "list",
                "loading": True,
                "loadingText": "Loading settings...",
                "items": [],
                "inputMode": "submit",
            }
        )
        return

    settings = state["settings"] or {"source": "auto", "targets": []}
    targets = settings.get("targets") or []

    if not targets:
        state["screen"] = "settings_form"
        render_settings_form(setup=True)
        return

    if not state["last_text"]:
        items = [
            {
                "id": "lang:%s" % c,
                "title": lang_name(c),
                "subtitle": c,
                "icon": "language",
            }
            for c in targets
        ]
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "list",
                "items": items,
                "emptyText": "Type text and press Enter",
                "placeholder": PLACEHOLDER,
                "inputMode": "submit",
                "actions": FRAME_ACTIONS,
            }
        )
        return

    if state["last_error"] and not state["last_results"]:
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "list",
                "items": [],
                "inputMode": "submit",
                "placeholder": PLACEHOLDER,
                "actions": FRAME_ACTIONS,
                "empty": {
                    "icon": "error",
                    "title": "Translation failed",
                    "hint": state["last_error"],
                },
            }
        )
        return

    results_by_code = {r["code"]: r for r in state["last_results"]}
    errors_by_code = state["translation_errors"]
    active_targets = state["active_targets"]
    display_targets = state["translation_targets"] or list(results_by_code)
    items = []
    for code in display_targets:
        r = results_by_code.get(code)
        if r:
            items.append(
                {
                    "id": "res:%s" % r["code"],
                    "title": r["text"],
                    "subtitle": r["name"],
                    "icon": "translate",
                    "lines": 3,
                    "accessories": [{"text": r["code"]}],
                    "actions": [{"id": "copy", "title": "Copy", "icon": "copy"}],
                    "preview": {
                        "markdown": "**%s** (`%s`)\n\n%s"
                        % (r["name"], r["code"], r["text"])
                    },
                }
            )
        elif code in errors_by_code:
            items.append(
                {
                    "id": "err:%s" % code,
                    "title": lang_name(code),
                    "subtitle": errors_by_code[code],
                    "icon": "error",
                    "lines": 2,
                    "accessories": [{"text": code}, {"text": "Failed"}],
                }
            )
        elif state["translating"]:
            is_active = code in active_targets
            items.append(
                {
                    "id": "pending:%s" % code,
                    "title": lang_name(code),
                    "subtitle": "Translating..." if is_active else "Queued",
                    "icon": "sync" if is_active else "clock",
                    "accessories": [
                        {"text": code},
                        {"text": "Working" if is_active else "Queued"},
                    ],
                }
            )

    actions = FRAME_ACTIONS + (
        [COPY_ALL_ACTION] if len(state["last_results"]) > 1 else []
    )
    placeholder = PLACEHOLDER
    if state["last_detected"]:
        placeholder = "Detected: %s - %s" % (
            lang_name(state["last_detected"]),
            PLACEHOLDER,
        )
    if state["translating"]:
        finished = len(results_by_code) + len(errors_by_code)
        placeholder = "Translating %d/%d (3 at a time) - %s" % (
            finished,
            len(display_targets),
            PLACEHOLDER,
        )
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "items": items,
            "placeholder": placeholder,
            "inputMode": "submit",
            "preview": {"enabled": True},
            "actions": actions,
        }
    )


def render_settings_form(target_error=None, setup=False):
    settings = state["settings"] or {"source": "auto", "targets": []}
    source_options = [{"value": "auto", "label": "Auto-detect"}] + [
        {"value": c, "label": n}
        for c, n in sorted(LANGUAGES.items(), key=lambda x: x[1])
        if c != "auto"
    ]
    target_options = [
        {"value": c, "label": n}
        for c, n in sorted(LANGUAGES.items(), key=lambda x: x[1])
        if c != "auto"
    ]
    targets_field = {
        "id": "targets",
        "type": "tags",
        "label": "Translate to",
        "value": settings.get("targets") or (COMMON_TARGETS if setup else []),
        "options": target_options,
        "required": True,
        "description": (
            "Default languages to translate into. Override per search by ending your text "
            'with e.g. "to es" or "from en to es".'
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
    title = "Choose your languages" if setup else "Google Translate Language Settings"
    send(
        {
            "type": "render",
            "rev": 0,
            "view": "form",
            "canGoBack": not setup,
            "form": {"title": title, "submitLabel": "Save", "fields": fields},
        }
    )


# --------------------------------------------------------------------------
# Business logic (three persistent workers keep stdin responsive)
# --------------------------------------------------------------------------


def _translation_worker():
    while True:
        _, _, job_id, body, code, source = _TRANSLATION_QUEUE.get()
        try:
            with _STATE_LOCK:
                if job_id != state["translation_id"]:
                    continue
                state["active_targets"].add(code)
            render_translate(0)

            try:
                text, detected = google_translate(body, code, source)
                error = None
            except GoogleTranslateError as e:
                text, detected, error = None, None, str(e)
            except Exception as e:  # pragma: no cover - defensive
                text, detected, error = None, None, "Unexpected error: %s" % e

            with _STATE_LOCK:
                if job_id != state["translation_id"]:
                    continue

                state["active_targets"].discard(code)
                if error:
                    state["translation_errors"][code] = error
                else:
                    by_code = {r["code"]: r for r in state["last_results"]}
                    by_code[code] = {
                        "code": code,
                        "name": lang_name(code),
                        "text": text,
                    }
                    state["last_results"] = [
                        by_code[target]
                        for target in state["translation_targets"]
                        if target in by_code
                    ]
                    if source == "auto" and detected and not state["last_detected"]:
                        state["last_detected"] = detected

                finished = len(state["last_results"]) + len(
                    state["translation_errors"]
                )
                if finished == len(state["translation_targets"]):
                    state["translating"] = False
                    state["active_targets"].clear()
                    if not state["last_results"] and state["translation_errors"]:
                        state["last_error"] = next(
                            iter(state["translation_errors"].values())
                        )
            render_translate(0)
        finally:
            _TRANSLATION_QUEUE.task_done()


def ensure_translation_workers():
    global _TRANSLATION_WORKERS_STARTED
    with _TRANSLATION_WORKERS_LOCK:
        if _TRANSLATION_WORKERS_STARTED:
            return
        for index in range(3):
            threading.Thread(
                target=_translation_worker,
                name="google-translate-%d" % (index + 1),
                daemon=True,
            ).start()
        _TRANSLATION_WORKERS_STARTED = True


def start_translate(rev, raw_text):
    body, from_c, to_c = parse_override(raw_text)
    with _STATE_LOCK:
        state["translation_id"] += 1
        job_id = state["translation_id"]
        state["last_text"] = raw_text
        state["last_results"] = []
        state["last_detected"] = None
        state["last_error"] = None
        state["translation_targets"] = []
        state["translation_errors"] = {}
        state["active_targets"] = set()
        state["translating"] = False

    if not body.strip():
        state["last_error"] = (
            'Add some text before the language code, e.g. "hello to es".'
            if to_c
            else None
        )
        render_translate(rev)
        return

    settings = state["settings"] or {"source": "auto", "targets": []}
    if to_c:
        targets = [to_c]
        source = from_c or "auto"
    else:
        targets = settings.get("targets") or []
        source = settings.get("source", "auto") or "auto"
    targets = list(dict.fromkeys(targets))

    if not targets:
        state["last_error"] = (
            "No default target languages set. Press Ctrl+K -> Language Settings, "
            'or end your text with e.g. "to es".'
        )
        render_translate(rev)
        return

    with _STATE_LOCK:
        state["translation_targets"] = targets
        state["translating"] = True
    render_translate(rev)
    ensure_translation_workers()
    for index, code in enumerate(targets):
        # Newer submissions sort ahead of stale queued work. Exactly three
        # persistent workers consume this queue for the plugin's lifetime.
        _TRANSLATION_QUEUE.put((-job_id, index, job_id, body, code, source))


# --------------------------------------------------------------------------
# Action / submit handlers
# --------------------------------------------------------------------------


def handle_action(item_id, action):
    if item_id == "":
        if action == "settings":
            with _STATE_LOCK:
                state["translation_id"] += 1
                state["translating"] = False
                state["active_targets"].clear()
                state["screen"] = "settings_form"
            render_settings_form(setup=False)
        elif action == "copy_all":
            combined = "\n".join(
                "%s: %s" % (r["name"], r["text"]) for r in state["last_results"]
            )
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
    if state["screen"] == "settings_form":
        was_setup = not ((state["settings"] or {}).get("targets"))
        targets = values.get("targets") or []
        source = values.get("source") or "auto"
        if not targets:
            render_settings_form(
                target_error="Pick at least one language.", setup=was_setup
            )
            return
        state["settings"] = {"source": source, "targets": targets}
        command(
            command="storage",
            op="set",
            key="settings",
            value=json.dumps(state["settings"]),
            secret=False,
        )
        command(command="toast", text="Settings saved")
        state["screen"] = "translate"
        render_translate(0)


def handle_back():
    state["screen"] = "translate"
    render_translate(0)


def handle_storage(msg):
    rid = msg.get("requestId")
    if rid == "settings":
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
        if state["screen"] == "translate":
            render_translate(0)


def fallback_defaults():
    if not state["loaded_settings"]:
        state["settings"] = state["settings"] or {"source": "auto", "targets": []}
        state["loaded_settings"] = True
        if state["screen"] == "translate":
            render_translate(0)


# --------------------------------------------------------------------------
# Main loop
# --------------------------------------------------------------------------


def main():
    command(
        command="storage", op="get", key="settings", secret=False, requestId="settings"
    )
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
                text = msg.get("text", "")
                start_translate(msg.get("rev", 0), text)
                # inputMode "submit" is chat-style: the launcher clears the
                # query box right after firing submitQuery. Put the text
                # back so what you typed stays visible/editable.
                command(command="setQuery", text=text)
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
