#!/usr/bin/env python3
"""Generate styled Unicode text from the bundled fancy-text data."""

from __future__ import annotations

import json
import re
import sys
import unicodedata
from pathlib import Path
from typing import Any


CATEGORIES_FILE = Path(__file__).resolve().with_name("categories.json")
FONTS_FILE = Path(__file__).resolve().with_name("fonts.json")
MAX_RENDER_DEPTH = 16

STATE: dict[str, Any] = {
    "screen": "categories",
    "category": None,
    "query": "",
}
LAST_CATEGORIES: dict[str, dict[str, Any]] = {}
LAST_RESULTS: dict[str, str] = {}
CATEGORIES: list[dict[str, Any]] = []
FONT_BY_SLUG: dict[str, dict[str, Any]] = {}
LOAD_ERROR: str | None = None


def log(*values: Any) -> None:
    """Write diagnostics to stderr; stdout is reserved for protocol frames."""

    print(*values, file=sys.stderr, flush=True)


def send(frame: dict[str, Any]) -> None:
    """Write one newline-delimited protocol object and flush it immediately."""

    sys.stdout.write(
        json.dumps(frame, ensure_ascii=False, separators=(",", ":")) + "\n"
    )
    sys.stdout.flush()


def safe_text(value: Any) -> str:
    return value if isinstance(value, str) else ""


def short_text(value: str, limit: int = 72) -> str:
    value = " ".join(value.split())
    if len(value) <= limit:
        return value
    return value[: limit - 1] + "…"


def first_value(values: Any) -> str:
    if isinstance(values, str):
        return values
    if isinstance(values, list):
        for value in values:
            if isinstance(value, str) and value:
                return value
    return ""


def grapheme_clusters(value: str) -> list[str]:
    """Keep combining marks and simple ZWJ sequences together."""

    clusters: list[str] = []
    for char in value:
        category = unicodedata.category(char)
        is_mark = category in {"Mn", "Mc", "Me"}
        is_variation_selector = "\ufe00" <= char <= "\ufe0f"
        joins_previous = clusters and clusters[-1].endswith("\u200d")
        if clusters and (
            is_mark
            or is_variation_selector
            or char == "\u200d"
            or joins_previous
        ):
            clusters[-1] += char
        else:
            clusters.append(char)
    return clusters


def category_id(title: str, index: int, used_ids: set[str]) -> str:
    base = re.sub(r"[^a-z0-9]+", "-", title.casefold()).strip("-")
    base = base or f"category-{index + 1}"
    candidate = f"category:{base}"
    suffix = 2
    while candidate in used_ids:
        candidate = f"category:{base}-{suffix}"
        suffix += 1
    used_ids.add(candidate)
    return candidate


def font_decoration(font: dict[str, Any]) -> dict[str, Any]:
    data = font.get("data")
    if not isinstance(data, dict):
        return {}
    decoration = data.get("decoration")
    return decoration if isinstance(decoration, dict) else {}


def map_static_font(font: dict[str, Any], value: str) -> str:
    data = font.get("data")
    characters = data.get("characters", {}) if isinstance(data, dict) else {}
    if not isinstance(characters, dict):
        return value

    letters = characters.get("letters", {})
    letters = letters if isinstance(letters, dict) else {}
    uppercase = letters.get("uppercase", {})
    lowercase = letters.get("lowercase", {})
    uppercase = uppercase if isinstance(uppercase, dict) else {}
    lowercase = lowercase if isinstance(lowercase, dict) else {}

    digits = characters.get("digits")
    if not isinstance(digits, dict):
        digits = characters.get("numbers", {})
    digits = digits if isinstance(digits, dict) else {}

    mapped: list[str] = []
    for cluster in grapheme_clusters(value):
        if not cluster:
            continue
        char = cluster[0]
        replacement: Any = None

        if char.isdigit():
            replacement = digits.get(char)
        if replacement is None:
            replacement = lowercase.get(char)
        if replacement is None:
            replacement = uppercase.get(char)
        if replacement is None and char.islower():
            replacement = uppercase.get(char.upper())
        if replacement is None and char.isupper():
            replacement = lowercase.get(char.lower())

        if isinstance(replacement, str):
            mapped.append(replacement + cluster[1:])
        else:
            mapped.append(cluster)
    return "".join(mapped)


def apply_decoration(font: dict[str, Any], value: str) -> str:
    decoration = font_decoration(font)
    clusters = grapheme_clusters(value)

    raw_diacritics = decoration.get("diacritics", [])
    diacritics = [
        item.strip()
        for item in raw_diacritics
        if isinstance(item, str) and item.strip()
    ]
    if diacritics:
        slug_seed = sum(
            (index + 1) * ord(char)
            for index, char in enumerate(safe_text(font.get("slug")))
        )
        try:
            level = max(1, min(int(font.get("zalgoLevel") or 1), 24))
        except (TypeError, ValueError):
            level = 1

        decorated: list[str] = []
        for index, cluster in enumerate(clusters):
            if cluster.isspace():
                decorated.append(cluster)
                continue
            output = cluster
            for offset in range(level):
                mark = diacritics[(slug_seed + index * level + offset) % len(diacritics)]
                output += mark
            decorated.append(output)
        clusters = grapheme_clusters("".join(decorated))

    delimiter = first_value(decoration.get("delimiters", []))
    if delimiter and len(clusters) > 1:
        value = delimiter.join(clusters)
    else:
        value = "".join(clusters)

    enclosures = decoration.get("enclosures", {})
    if not isinstance(enclosures, dict):
        enclosures = {}
    return (
        first_value(enclosures.get("left"))
        + value
        + first_value(enclosures.get("right"))
    )


def resolve_font(value: Any) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    slug = safe_text(value.get("slug"))
    if slug and not isinstance(value.get("data"), dict):
        return FONT_BY_SLUG.get(slug)
    return value


def render_font(font: dict[str, Any], value: str, depth: int = 0) -> str:
    """Render static, derivative, alternating, flipped, and Zalgo fonts."""

    if depth > MAX_RENDER_DEPTH:
        return value

    font_type = safe_text(font.get("type"))
    if font_type == "Static":
        output = map_static_font(font, value)
    elif font_type == "Derivative":
        base_font = resolve_font(font.get("baseFont"))
        output = (
            render_font(base_font, value, depth + 1)
            if base_font is not None
            else value
        )
    elif font_type == "Alternating":
        base_font = resolve_font(font.get("baseFont"))
        alternating_font = resolve_font(font.get("alternatingFont"))
        output_parts: list[str] = []
        for index, cluster in enumerate(grapheme_clusters(value)):
            selected = base_font if index % 2 == 0 else alternating_font
            if selected is not None:
                output_parts.append(render_font(selected, cluster, depth + 1))
            else:
                output_parts.append(cluster)
        output = "".join(output_parts)
    else:
        output = value

    output = apply_decoration(font, output)
    if font.get("verticalFlipped"):
        output = "".join(reversed(grapheme_clusters(output)))
    return output


def load_data() -> None:
    global CATEGORIES, FONT_BY_SLUG, LOAD_ERROR

    try:
        with CATEGORIES_FILE.open("r", encoding="utf-8") as source:
            raw_categories = json.load(source)
        with FONTS_FILE.open("r", encoding="utf-8") as source:
            raw_fonts = json.load(source)

        if not isinstance(raw_categories, list):
            raise ValueError("categories.json must contain an array")
        if not isinstance(raw_fonts, list):
            raise ValueError("fonts.json must contain an array")

        fonts: dict[str, dict[str, Any]] = {}
        for raw_font in raw_fonts:
            if not isinstance(raw_font, dict):
                continue
            slug = safe_text(raw_font.get("slug"))
            if slug:
                fonts[slug] = raw_font
        if not fonts:
            raise ValueError("fonts.json contains no font definitions")

        categories: list[dict[str, Any]] = []
        used_ids: set[str] = set()
        for index, raw_category in enumerate(raw_categories):
            if not isinstance(raw_category, dict):
                continue
            title = safe_text(raw_category.get("title")).strip()
            if not title:
                log(f"Skipping unnamed category at index {index}")
                continue

            curated_fonts = raw_category.get("curatedFonts", {})
            curated_items = (
                curated_fonts.get("items", [])
                if isinstance(curated_fonts, dict)
                else []
            )
            styles: list[dict[str, Any]] = []
            seen_slugs: set[str] = set()
            for raw_style in curated_items:
                if not isinstance(raw_style, dict):
                    continue
                slug = safe_text(raw_style.get("slug"))
                if not slug or slug in seen_slugs:
                    continue
                seen_slugs.add(slug)
                font = fonts.get(slug)
                if font is None:
                    log(f"Category {title!r} references missing font {slug!r}")
                    continue
                styles.append(
                    {
                        "slug": slug,
                        "title": (
                            safe_text(raw_style.get("title"))
                            or safe_text(font.get("title"))
                            or slug
                        ),
                        "type": (
                            safe_text(raw_style.get("type"))
                            or safe_text(font.get("type"))
                        ),
                        "font": font,
                    }
                )

            categories.append(
                {
                    "id": category_id(title, index, used_ids),
                    "title": title,
                    "pageSubtitle": safe_text(raw_category.get("pageSubtitle")),
                    "styles": styles,
                }
            )

        if not categories:
            raise ValueError("categories.json contains no named categories")

        FONT_BY_SLUG = fonts
        CATEGORIES = categories
        log(f"Loaded {len(FONT_BY_SLUG)} fonts in {len(CATEGORIES)} categories")
    except Exception as error:
        LOAD_ERROR = str(error)
        log(f"Could not load fancy-text data: {error}")


def revision(message: dict[str, Any]) -> int:
    value = message.get("rev", 0)
    return value if isinstance(value, int) and not isinstance(value, bool) else 0


def query_text(message: dict[str, Any]) -> str:
    value = message.get("text")
    if value is None:
        value = message.get("query", "")
    return safe_text(value)


def render_error(rev: int, message: str) -> None:
    safe_message = message.replace(chr(96) * 3, "'''")
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "detail": {
                "markdown": f"# Fancy text error\n\n{safe_message}",
            },
        }
    )


def render_categories(rev: int, query: str) -> None:
    if LOAD_ERROR:
        render_error(rev, LOAD_ERROR)
        return

    needle = query.strip().casefold()
    LAST_CATEGORIES.clear()
    items: list[dict[str, Any]] = []
    for category in CATEGORIES:
        searchable = " ".join(
            [
                safe_text(category.get("title")),
                safe_text(category.get("pageSubtitle")),
            ]
        ).casefold()
        if needle and needle not in searchable:
            continue

        item_id = safe_text(category.get("id"))
        LAST_CATEGORIES[item_id] = category
        styles = category.get("styles", [])
        count = len(styles) if isinstance(styles, list) else 0
        subtitle = f"{count} style" + ("s" if count != 1 else "")
        sample = safe_text(category.get("pageSubtitle"))
        if sample:
            subtitle += f" · {short_text(sample)}"
        items.append(
            {
                "id": item_id,
                "title": safe_text(category.get("title")),
                "subtitle": subtitle,
                "icon": "palette",
            }
        )

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "placeholder": "Choose a text category…",
            "emptyText": "No matching text categories",
            "items": items,
        }
    )


def category_options() -> list[dict[str, str]]:
    return [
        {
            "value": safe_text(category.get("id")),
            "label": f"{safe_text(category.get('title'))} - {safe_text(category.get('pageSubtitle'))}",
        }
        for category in CATEGORIES
        if safe_text(category.get("id")) and safe_text(category.get("title"))
    ]


def change_category_action() -> dict[str, Any]:
    return {
        "id": "change-category",
        "title": "Change Category",
        "icon": "palette",
        "parameters": [
            {
                "id": "category",
                "type": "dropdown",
                "label": "Category",
                "required": True,
                "options": category_options(),
            }
        ],
    }


def find_category(value: Any) -> dict[str, Any] | None:
    selected = safe_text(value)
    for category in CATEGORIES:
        if selected in {
            safe_text(category.get("id")),
            safe_text(category.get("title")),
        }:
            return category
    return None


def render_results(rev: int, query: str) -> None:
    category = STATE.get("category")
    if not isinstance(category, dict):
        STATE["screen"] = "categories"
        render_categories(rev, query)
        return

    LAST_RESULTS.clear()
    items: list[dict[str, Any]] = []
    if query:
        styles = category.get("styles", [])
        if not isinstance(styles, list):
            styles = []
        for style in styles:
            if not isinstance(style, dict):
                continue
            font = style.get("font")
            if not isinstance(font, dict):
                continue
            try:
                output = render_font(font, query)
            except Exception as error:
                log(f"Could not render {style.get('slug', '?')}: {error}")
                output = query

            style_slug = safe_text(style.get("slug"))
            item_id = f"{safe_text(category.get('id'))}:style:{style_slug}"
            LAST_RESULTS[item_id] = output
            style_title = safe_text(style.get("title")) or style_slug
            style_type = safe_text(style.get("type"))
            subtitle = style_title
            if style_type:
                subtitle += f" · {style_type}"
            items.append(
                {
                    "id": item_id,
                    "title": output,
                    "subtitle": subtitle,
                    "icon": "tag",
                    "actions": [
                        {
                            "id": "copy",
                            "title": "Copy and close",
                            "icon": "copy",
                            "shortcut": "ctrl+shift+c",
                        }
                    ],
                }
            )

    category_title = safe_text(category.get("title"))
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "placeholder": f"Type text for {category_title}…",
            "emptyText": "Type any text to generate every style",
            "actions": [change_category_action()],
            "items": items,
        }
    )


def copy_result(item_id: str) -> None:
    value = LAST_RESULTS.get(item_id)
    if value is None:
        return
    send({"type": "command", "command": "copy", "text": value})
    send({"type": "command", "command": "hide"})


def handle_action(message: dict[str, Any]) -> None:
    item_id = safe_text(message.get("id"))
    action = safe_text(message.get("action")) or "default"

    if STATE.get("screen") == "categories":
        category = LAST_CATEGORIES.get(item_id)
        if category is not None and action == "default":
            STATE["screen"] = "results"
            STATE["category"] = category
            STATE["query"] = ""
            send({"type": "command", "command": "setQuery", "text": ""})
            render_results(0, "")
        return

    if STATE.get("screen") != "results":
        return

    if action == "change-category":
        parameters = message.get("parameters")
        selected_value = (
            parameters.get("category") if isinstance(parameters, dict) else None
        )
        category = find_category(selected_value)
        if category is not None:
            STATE["category"] = category
            render_results(0, safe_text(STATE.get("query")))
        return

    if action in {"default", "copy"}:
        copy_result(item_id)


def handle_back() -> None:
    if STATE.get("screen") != "results":
        return
    STATE["screen"] = "categories"
    STATE["category"] = None
    STATE["query"] = ""
    LAST_RESULTS.clear()
    send({"type": "command", "command": "setQuery", "text": ""})
    render_categories(0, "")


def handle_tab(message: dict[str, Any]) -> None:
    if STATE.get("screen") != "categories":
        return
    category = LAST_CATEGORIES.get(safe_text(message.get("id")))
    if category is not None:
        send(
            {
                "type": "command",
                "command": "setQuery",
                "text": safe_text(category.get("title")),
            }
        )


def handle_message(message: dict[str, Any]) -> None:
    kind = safe_text(message.get("type"))
    if kind in {"init", "query"}:
        if kind == "init":
            STATE["screen"] = "categories"
            STATE["category"] = None
        text = query_text(message)
        STATE["query"] = text
        if STATE.get("screen") == "results":
            render_results(revision(message), text)
        else:
            render_categories(revision(message), text)
    elif kind == "action":
        handle_action(message)
    elif kind == "back":
        handle_back()
    elif kind == "tab":
        handle_tab(message)


def main() -> None:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass

    load_data()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError as error:
            log(f"Ignoring malformed message: {error}")
            render_error(0, str(error))
            continue
        if not isinstance(message, dict):
            log("Ignoring non-object message")
            render_error(0, "Expected a JSON object")
            continue
        if message.get("type") == "close":
            break
        try:
            handle_message(message)
        except Exception as error:
            log(f"Message handling failed: {error}")
            render_error(revision(message), str(error))


if __name__ == "__main__":
    main()
