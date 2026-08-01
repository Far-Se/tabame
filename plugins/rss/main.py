#!/usr/bin/env python3
"""RSS & Read Later - a detailed, dependency-free Tabame launcher plugin.

The plugin keeps a small local RSS/Atom library in Tabame's per-plugin storage.
It deliberately uses only Python's standard library so a fresh install does not
need a package download:

  rss                         dashboard: new articles, saved stories, feeds
  rss <words>                 search articles, feeds, and categories

Highlights:
  - RSS 2.x, RDF-style RSS, and Atom feed parsing
  - unread/new articles, Read Later, notes, tags, and manual articles
  - nested user categories (category -> subcategory -> ...)
  - add/edit forms for feeds, categories, articles, and settings
  - refresh one feed or all feeds in a background worker
  - OPML import and JSON/OPML export
  - rich previews and article detail pages

All stdout is protocol traffic. Diagnostics go to stderr.
"""

from __future__ import annotations

import copy
import datetime as dt
import hashlib
import html
import json
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime
from html.parser import HTMLParser
from xml.sax.saxutils import escape as xml_escape


PLUGIN_DIR = os.path.dirname(os.path.abspath(__file__))
STATE_KEY = "rss-read-later-state"
STORAGE_REQUEST_ID = "rss-read-later-load"
PAGE_SIZE = 45
MAX_FEED_BYTES = 8 * 1024 * 1024
REQUEST_TIMEOUT = 20
USER_AGENT = "Tabame RSS Reader/1.0 (+https://github.com/Far-Se/tabame)"

UNCATEGORIZED_ID = "uncategorized"
FORM_SCREENS = {
    "feed_form",
    "category_form",
    "article_form",
    "settings_form",
    "import_form",
    "export_form",
}

DEFAULT_CATEGORIES = [
    {
        "id": UNCATEGORIZED_ID,
        "name": "Uncategorized",
        "parent_id": None,
        "color": "#94A3B8",
        "description": "Feeds and articles that have not been assigned a category yet.",
    },
    {
        "id": "news",
        "name": "News",
        "parent_id": None,
        "color": "#3B82F6",
        "description": "Headlines, current events, and reporting.",
    },
    {
        "id": "technology",
        "name": "Technology",
        "parent_id": None,
        "color": "#8B5CF6",
        "description": "Software, hardware, science, and the web.",
    },
    {
        "id": "design",
        "name": "Design",
        "parent_id": None,
        "color": "#EC4899",
        "description": "Design, typography, product, and visual culture.",
    },
    {
        "id": "work",
        "name": "Work",
        "parent_id": None,
        "color": "#F59E0B",
        "description": "Work, business, productivity, and career reading.",
    },
    {
        "id": "culture",
        "name": "Culture",
        "parent_id": None,
        "color": "#10B981",
        "description": "Arts, entertainment, ideas, and long reads.",
    },
]

DEFAULT_SETTINGS = {
    "max_articles_per_feed": 100,
    "refresh_on_open": True,
    "mark_open_read": True,
}


def default_state() -> dict:
    return {
        "version": 1,
        "feeds": [],
        "articles": [],
        "categories": copy.deepcopy(DEFAULT_CATEGORIES),
        "settings": copy.deepcopy(DEFAULT_SETTINGS),
        # UI-only state is intentionally not persisted.
        "screen": "root",
        "query": "",
        "history": [],
        "list_kind": "all",
        "category_id": None,
        "feed_id": None,
        "detail_article_id": None,
        "form_kind": None,
        "form_entity_id": None,
        "form_values": {},
        "form_errors": {},
        "storage_requested": False,
        "storage_loaded": False,
        "refreshing": False,
        "closing": False,
        "list_limit": PAGE_SIZE,
    }


state = default_state()
SEND_LOCK = threading.Lock()
REFRESH_LOCK = threading.Lock()
REFRESH_THREAD: threading.Thread | None = None


# ---------------------------------------------------------------------------
# Protocol helpers


def send(frame: dict) -> None:
    """Write one JSON object and flush it immediately."""

    with SEND_LOCK:
        sys.stdout.write(json.dumps(frame, ensure_ascii=False, separators=(",", ":")) + "\n")
        sys.stdout.flush()


def command(name: str, **fields) -> None:
    send({"type": "command", "command": name, **fields})


def log(*values) -> None:
    print(*values, file=sys.stderr, flush=True)


def toast(text: str, style: str = "success") -> None:
    command("toast", text=text, style=style)


# ---------------------------------------------------------------------------
# Persistent state


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def parse_datetime(value) -> dt.datetime | None:
    if not value:
        return None
    if isinstance(value, dt.datetime):
        result = value
    else:
        text = str(value).strip()
        if not text:
            return None
        result = None
        try:
            result = parsedate_to_datetime(text)
        except (TypeError, ValueError, IndexError):
            try:
                result = dt.datetime.fromisoformat(text.replace("Z", "+00:00"))
            except ValueError:
                return None
    if result.tzinfo is None:
        result = result.replace(tzinfo=dt.timezone.utc)
    return result.astimezone(dt.timezone.utc)


def normalize_tags(value) -> list[str]:
    if isinstance(value, str):
        values = re.split(r"[,\n]", value)
    elif isinstance(value, (list, tuple)):
        values = value
    else:
        values = []
    result = []
    seen = set()
    for raw in values:
        tag = re.sub(r"\s+", " ", str(raw).strip())
        if tag and tag.casefold() not in seen:
            result.append(tag)
            seen.add(tag.casefold())
    return result[:30]


def valid_http_url(value: str) -> bool:
    try:
        parsed = urllib.parse.urlparse(value.strip())
    except ValueError:
        return False
    return parsed.scheme.lower() in {"http", "https"} and bool(parsed.netloc)


def slug_id(prefix: str, value: str) -> str:
    digest = hashlib.sha1(value.encode("utf-8", "ignore")).hexdigest()[:12]
    return f"{prefix}-{digest}"


def normalize_category(raw: dict) -> dict:
    category = dict(raw) if isinstance(raw, dict) else {}
    category.setdefault("id", slug_id("category", str(time.time_ns())))
    category.setdefault("name", "Untitled category")
    category.setdefault("parent_id", None)
    category.setdefault("color", "#64748B")
    category.setdefault("description", "")
    category["id"] = str(category["id"])
    category["name"] = str(category["name"]).strip() or "Untitled category"
    category["parent_id"] = str(category["parent_id"]) if category.get("parent_id") else None
    category["color"] = normalize_color(category.get("color"), "#64748B")
    category["description"] = str(category.get("description") or "").strip()
    return category


def normalize_color(value, fallback: str = "#64748B") -> str:
    text = str(value or "").strip()
    if re.fullmatch(r"#[0-9a-fA-F]{6}", text):
        return text.upper()
    if re.fullmatch(r"#[0-9a-fA-F]{3}", text):
        return "#" + "".join(ch * 2 for ch in text[1:]).upper()
    return fallback


def normalize_feed(raw: dict) -> dict:
    feed = dict(raw) if isinstance(raw, dict) else {}
    feed.setdefault("id", slug_id("feed", str(time.time_ns())))
    feed.setdefault("url", "")
    feed.setdefault("title", feed.get("url") or "Untitled feed")
    feed.setdefault("description", "")
    feed.setdefault("site_url", "")
    feed.setdefault("category_id", UNCATEGORIZED_ID)
    feed.setdefault("tags", [])
    feed.setdefault("enabled", True)
    feed.setdefault("custom_title", False)
    feed.setdefault("added_at", now_iso())
    feed.setdefault("last_checked", None)
    feed.setdefault("last_error", "")
    feed.setdefault("image_url", "")
    feed["id"] = str(feed["id"])
    feed["url"] = str(feed.get("url") or "").strip()
    feed["title"] = str(feed.get("title") or feed["url"] or "Untitled feed").strip()
    feed["description"] = str(feed.get("description") or "").strip()
    feed["site_url"] = str(feed.get("site_url") or "").strip()
    feed["category_id"] = str(feed.get("category_id") or UNCATEGORIZED_ID)
    feed["tags"] = normalize_tags(feed.get("tags"))
    feed["enabled"] = bool(feed.get("enabled", True))
    feed["custom_title"] = bool(feed.get("custom_title", False))
    feed["last_error"] = str(feed.get("last_error") or "")
    feed["image_url"] = str(feed.get("image_url") or "")
    return feed


def normalize_article(raw: dict) -> dict:
    article = dict(raw) if isinstance(raw, dict) else {}
    article.setdefault("id", slug_id("article", str(time.time_ns())))
    article.setdefault("feed_id", None)
    article.setdefault("source_name", "Manual")
    article.setdefault("title", "Untitled article")
    article.setdefault("url", "")
    article.setdefault("summary", "")
    article.setdefault("content", "")
    article.setdefault("image_url", "")
    article.setdefault("author", "")
    article.setdefault("published", None)
    article.setdefault("added_at", now_iso())
    article.setdefault("updated_at", now_iso())
    article.setdefault("unread", True)
    article.setdefault("saved", False)
    article.setdefault("saved_at", None)
    article.setdefault("note", "")
    article.setdefault("tags", [])
    article.setdefault("category_id", None)
    article.setdefault("guid", "")
    article["id"] = str(article["id"])
    article["feed_id"] = str(article["feed_id"]) if article.get("feed_id") else None
    article["source_name"] = str(article.get("source_name") or "Manual").strip()
    article["title"] = str(article.get("title") or "Untitled article").strip()
    article["url"] = str(article.get("url") or "").strip()
    article["summary"] = str(article.get("summary") or "").strip()[:6000]
    article["content"] = str(article.get("content") or "").strip()[:10000]
    article["image_url"] = str(article.get("image_url") or "").strip()
    article["author"] = str(article.get("author") or "").strip()
    article["unread"] = bool(article.get("unread", True))
    article["saved"] = bool(article.get("saved", False))
    article["note"] = str(article.get("note") or "").strip()[:6000]
    article["tags"] = normalize_tags(article.get("tags"))
    article["category_id"] = str(article["category_id"]) if article.get("category_id") else None
    article["guid"] = str(article.get("guid") or "")
    return article


def normalize_persisted(value) -> dict:
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except json.JSONDecodeError:
            value = {}
    if not isinstance(value, dict):
        value = {}

    categories = [normalize_category(item) for item in value.get("categories", []) if isinstance(item, dict)]
    category_ids = {item["id"] for item in categories}
    for default in DEFAULT_CATEGORIES:
        if default["id"] not in category_ids:
            categories.append(copy.deepcopy(default))
            category_ids.add(default["id"])
    for category in categories:
        if category.get("parent_id") not in category_ids or category["parent_id"] == category["id"]:
            category["parent_id"] = None

    feeds = [normalize_feed(item) for item in value.get("feeds", []) if isinstance(item, dict)]
    articles = [normalize_article(item) for item in value.get("articles", []) if isinstance(item, dict)]
    settings = copy.deepcopy(DEFAULT_SETTINGS)
    if isinstance(value.get("settings"), dict):
        settings.update(value["settings"])
    try:
        settings["max_articles_per_feed"] = max(10, min(500, int(settings["max_articles_per_feed"])))
    except (TypeError, ValueError):
        settings["max_articles_per_feed"] = DEFAULT_SETTINGS["max_articles_per_feed"]
    settings["refresh_on_open"] = bool(settings.get("refresh_on_open", True))
    settings["mark_open_read"] = bool(settings.get("mark_open_read", True))

    valid_feed_ids = {feed["id"] for feed in feeds}
    for feed in feeds:
        if feed["category_id"] not in category_ids:
            feed["category_id"] = UNCATEGORIZED_ID
    for article in articles:
        if article["feed_id"] not in valid_feed_ids:
            article["feed_id"] = None
        if article["category_id"] not in category_ids:
            article["category_id"] = None

    return {
        "version": 1,
        "feeds": feeds,
        "articles": articles,
        "categories": categories,
        "settings": settings,
    }


def serializable_state() -> dict:
    return {
        "version": 1,
        "feeds": [normalize_feed(feed) for feed in state["feeds"]],
        "articles": [normalize_article(article) for article in state["articles"]],
        "categories": [normalize_category(category) for category in state["categories"]],
        "settings": dict(state["settings"]),
    }


def request_state() -> None:
    if state["storage_requested"]:
        return
    state["storage_requested"] = True
    command(
        "storage",
        op="get",
        key=STATE_KEY,
        requestId=STORAGE_REQUEST_ID,
    )


def save_state() -> None:
    command(
        "storage",
        op="set",
        key=STATE_KEY,
        value=serializable_state(),
    )


# ---------------------------------------------------------------------------
# HTML, XML, and feed parsing


class _TextExtractor(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.skip_depth = 0

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        if tag in {"script", "style", "noscript"}:
            self.skip_depth += 1
        elif tag in {"br", "p", "div", "li", "article", "section", "h1", "h2", "h3"}:
            self.parts.append("\n")

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag in {"script", "style", "noscript"} and self.skip_depth:
            self.skip_depth -= 1
        elif tag in {"p", "div", "li", "article", "section", "h1", "h2", "h3"}:
            self.parts.append("\n")

    def handle_data(self, data):
        if not self.skip_depth:
            self.parts.append(data)


def strip_html(value, limit: int = 6000) -> str:
    raw = html.unescape(str(value or ""))
    parser = _TextExtractor()
    try:
        parser.feed(raw)
        parser.close()
        text = "".join(parser.parts)
    except Exception:
        text = re.sub(r"<[^>]+>", " ", raw)
    text = re.sub(r"[ \t\f\v]+", " ", text)
    text = re.sub(r"\n[ \t]+", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    return text[:limit]


def markdown_escape(value: str) -> str:
    text = str(value or "")
    return (
        text.replace("\\", "\\\\")
        .replace("`", "\\`")
        .replace("*", "\\*")
        .replace("_", "\\_")
        .replace("[", "\\[")
        .replace("]", "\\]")
        .replace("<", "\\<")
        .replace(">", "\\>")
    )


def local_name(tag) -> str:
    if not isinstance(tag, str):
        return ""
    return tag.rsplit("}", 1)[-1].rsplit(":", 1)[-1].lower()


def direct_children(element, names: set[str]):
    return [child for child in list(element) if local_name(child.tag) in names]


def child_element(element, names: set[str]):
    for child in list(element):
        if local_name(child.tag) in names:
            return child
    return None


def child_text(element, names: set[str]) -> str:
    child = child_element(element, names)
    if child is None:
        return ""
    return "".join(child.itertext()).strip()


def atom_or_rss_link(element) -> str:
    candidates = []
    for child in list(element):
        if local_name(child.tag) != "link":
            continue
        href = str(child.attrib.get("href") or "").strip()
        text = "".join(child.itertext()).strip()
        rel = str(child.attrib.get("rel") or "alternate").lower()
        if href:
            candidates.append((0 if rel in {"alternate", ""} else 1, href))
        elif text:
            candidates.append((0, text))
    if candidates:
        candidates.sort(key=lambda item: item[0])
        return candidates[0][1]
    return child_text(element, {"guid", "id"})


def image_from_element(element) -> str:
    for child in element.iter():
        name = local_name(child.tag)
        if name not in {"content", "thumbnail", "enclosure", "image"}:
            continue
        url = str(child.attrib.get("url") or child.attrib.get("href") or "").strip()
        media_type = str(child.attrib.get("type") or "").lower()
        if url and (name in {"content", "thumbnail", "image"} or media_type.startswith("image/")):
            return url
    return ""


def feed_image(container) -> str:
    image = child_element(container, {"image", "logo", "icon"})
    if image is not None:
        url = str(image.attrib.get("href") or image.attrib.get("url") or "").strip()
        if url:
            return url
        nested = child_text(image, {"url", "href"})
        if nested:
            return nested
    return image_from_element(container)


def parse_date_value(value: str) -> str | None:
    parsed = parse_datetime(value)
    return parsed.isoformat() if parsed else None


def parse_feed_document(document: bytes, source_url: str) -> tuple[dict, list[dict]]:
    root = ET.fromstring(document)
    root_name = local_name(root.tag)
    if root_name == "channel":
        container = root
    else:
        container = child_element(root, {"channel", "feed"}) or root

    feed_title = strip_html(child_text(container, {"title"}), 300)
    feed_description = strip_html(child_text(container, {"subtitle", "description", "summary"}), 1200)
    feed_site = atom_or_rss_link(container)
    if not valid_http_url(feed_site):
        feed_site = source_url
    feed_picture = feed_image(container)

    entries = [child for child in list(container) if local_name(child.tag) in {"item", "entry"}]
    if not entries and container is not root:
        entries = [child for child in list(root) if local_name(child.tag) in {"item", "entry"}]

    parsed_articles = []
    for entry in entries:
        title = strip_html(child_text(entry, {"title"}), 500) or "Untitled article"
        link = atom_or_rss_link(entry)
        if link:
            link = urllib.parse.urljoin(source_url, link)
        guid = child_text(entry, {"guid", "id"})
        published_raw = child_text(entry, {"published", "updated", "pubdate", "date", "issued"})
        published = parse_date_value(published_raw)
        content_raw = child_text(entry, {"encoded", "content", "summary", "description"})
        summary_raw = child_text(entry, {"summary", "description", "content", "encoded"})
        content = strip_html(content_raw, 10000)
        summary = strip_html(summary_raw, 1600)
        if not summary and content:
            summary = content[:1600]
        author = child_text(entry, {"creator", "author", "contributor"})
        if author:
            author = strip_html(author, 200)
        tags = []
        for category in direct_children(entry, {"category", "subject"}):
            value = category.attrib.get("term") or category.attrib.get("label") or "".join(category.itertext())
            value = strip_html(value, 120)
            if value:
                tags.append(value)
        image_url = image_from_element(entry)
        identity = guid or link or f"{title}|{published or ''}"
        article_id = slug_id("article", source_url + "|" + identity)
        parsed_articles.append(
            {
                "id": article_id,
                "guid": guid or link or identity,
                "title": title,
                "url": link or source_url,
                "summary": summary,
                "content": content,
                "image_url": urllib.parse.urljoin(source_url, image_url) if image_url else feed_picture,
                "author": author,
                "published": published,
                "tags": normalize_tags(tags),
            }
        )

    return (
        {
            "title": feed_title or urllib.parse.urlparse(source_url).netloc or source_url,
            "description": feed_description,
            "site_url": feed_site,
            "image_url": urllib.parse.urljoin(source_url, feed_picture) if feed_picture else "",
        },
        parsed_articles,
    )


def fetch_feed_document(url: str) -> bytes:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/rss+xml, application/atom+xml, application/xml, text/xml, */*;q=0.8",
        },
    )
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
        data = response.read(MAX_FEED_BYTES + 1)
    if len(data) > MAX_FEED_BYTES:
        raise ValueError("The feed is larger than 8 MB and was not loaded.")
    return data


# ---------------------------------------------------------------------------
# Lookup and formatting helpers


def get_feed(feed_id: str | None) -> dict | None:
    if not feed_id:
        return None
    return next((feed for feed in state["feeds"] if feed["id"] == feed_id), None)


def get_article(article_id: str | None) -> dict | None:
    if not article_id:
        return None
    return next((article for article in state["articles"] if article["id"] == article_id), None)


def get_category(category_id: str | None) -> dict | None:
    if not category_id:
        return None
    return next((category for category in state["categories"] if category["id"] == category_id), None)


def category_path(category_id: str | None, seen: set[str] | None = None) -> str:
    category = get_category(category_id) or get_category(UNCATEGORIZED_ID)
    if category is None:
        return "Uncategorized"
    seen = set() if seen is None else seen
    if category["id"] in seen or not category.get("parent_id"):
        return category["name"]
    seen.add(category["id"])
    return f"{category_path(category['parent_id'], seen)} / {category['name']}"


def article_category_id(article: dict) -> str:
    if article.get("category_id") and get_category(article["category_id"]):
        return article["category_id"]
    feed = get_feed(article.get("feed_id"))
    if feed and get_category(feed.get("category_id")):
        return feed["category_id"]
    return UNCATEGORIZED_ID


def article_category(article: dict) -> str:
    return category_path(article_category_id(article))


def is_descendant(category_id: str, ancestor_id: str) -> bool:
    current = get_category(category_id)
    seen = set()
    while current and current.get("parent_id") and current["id"] not in seen:
        if current["parent_id"] == ancestor_id:
            return True
        seen.add(current["id"])
        current = get_category(current.get("parent_id"))
    return False


def category_options(exclude_id: str | None = None) -> list[dict]:
    options = []
    categories = sorted(state["categories"], key=lambda item: category_path(item["id"]).casefold())
    for category in categories:
        if category["id"] != exclude_id and not (exclude_id and is_descendant(category["id"], exclude_id)):
            options.append({"value": category["id"], "label": category_path(category["id"])})
    return options or [{"value": UNCATEGORIZED_ID, "label": "Uncategorized"}]


def category_counts(category_id: str) -> tuple[int, int]:
    article_count = sum(1 for article in state["articles"] if article_category_id(article) == category_id)
    feed_count = sum(1 for feed in state["feeds"] if feed.get("category_id") == category_id)
    return article_count, feed_count


def feed_article_count(feed_id: str) -> int:
    return sum(1 for article in state["articles"] if article.get("feed_id") == feed_id)


def normalize_query(text: str) -> str:
    return re.sub(r"\s+", " ", str(text or "").strip()).casefold()


def text_matches(term: str, *values) -> bool:
    if not term:
        return True
    haystack = " ".join(str(value or "") for value in values).casefold()
    return term in haystack


def truncate(text: str, limit: int) -> str:
    text = str(text or "").strip()
    if len(text) <= limit:
        return text
    return text[: max(0, limit - 1)].rstrip() + "…"


def format_age(value) -> str:
    parsed = parse_datetime(value)
    if parsed is None:
        return "Unknown date"
    delta = dt.datetime.now(dt.timezone.utc) - parsed
    seconds = int(delta.total_seconds())
    if seconds < 0:
        seconds = abs(seconds)
        if seconds < 3600:
            return f"in {max(1, seconds // 60)}m"
        if seconds < 86400:
            return f"in {seconds // 3600}h"
        return f"in {seconds // 86400}d"
    if seconds < 60:
        return "just now"
    if seconds < 3600:
        return f"{seconds // 60}m ago"
    if seconds < 86400:
        return f"{seconds // 3600}h ago"
    if seconds < 7 * 86400:
        return f"{seconds // 86400}d ago"
    local = parsed.astimezone()
    return local.strftime("%b %-d, %Y") if os.name != "nt" else local.strftime("%b %#d, %Y")


def format_timestamp(value) -> str:
    parsed = parse_datetime(value)
    if parsed is None:
        return "—"
    local = parsed.astimezone()
    return local.strftime("%Y-%m-%d %H:%M")


def status_label(article: dict) -> str:
    labels = []
    if article.get("unread"):
        labels.append("New")
    else:
        labels.append("Read")
    if article.get("saved"):
        labels.append("Read Later")
    return " · ".join(labels)


# ---------------------------------------------------------------------------
# Item previews and UI frames


def action_entry(action_id: str, title: str, icon: str, **extra) -> dict:
    return {"id": action_id, "title": title, "icon": icon, **extra}


def article_preview(article: dict) -> dict:
    body = article.get("content") or article.get("summary") or "This feed did not include an article summary."
    markdown = (
        f"## {markdown_escape(article.get('title', 'Untitled article'))}\n\n"
        f"{markdown_escape(truncate(body, 2200))}\n\n"
        f"[Open article in your browser]({article.get('url', '')})"
    )
    if article.get("note"):
        markdown += f"\n\n> **Your note:** {markdown_escape(truncate(article['note'], 700))}"
    metadata = [
        {"label": "Status", "text": status_label(article), "color": "#3B82F6" if article.get("unread") else "#64748B"},
        {"label": "Source", "text": article.get("source_name") or "Manual", "icon": "globe"},
        {"label": "Published", "text": format_timestamp(article.get("published")), "icon": "clock"},
        {"label": "Category", "text": article_category(article), "icon": "folder"},
    ]
    if article.get("author"):
        metadata.append({"label": "Author", "text": article["author"], "icon": "person"})
    if article.get("tags"):
        metadata.append({"label": "Tags", "text": ", ".join(article["tags"]), "icon": "tag"})
    return {
        "markdown": markdown,
        "metadata": metadata,
        **({"image": {"url": article["image_url"], "width": 160}} if valid_http_url(article.get("image_url", "")) else {}),
    }


def article_item(article: dict, section: str | None = None) -> dict:
    badges = []
    if article.get("unread"):
        badges.append({"text": "NEW", "color": "#3B82F6", "icon": "star"})
    if article.get("saved"):
        badges.append({"text": "LATER", "color": "#F59E0B", "icon": "bookmark"})
    source = article.get("source_name") or "Manual"
    subtitle_parts = [source, format_age(article.get("published") or article.get("added_at"))]
    if article_category(article) != "Uncategorized":
        subtitle_parts.append(article_category(article))
    return {
        "id": article["id"],
        "title": ("**" + markdown_escape(article["title"]) + "**") if article.get("unread") else markdown_escape(article["title"]),
        "subtitle": " · ".join(subtitle_parts),
        "icon": "bookmark" if article.get("saved") else "book",
        "section": section or ("New" if article.get("unread") else "Read"),
        "lines": 2,
        "accessories": badges,
        "actions": [
            action_entry("article:open", "Open in browser", "open"),
            action_entry("article:detail", "Read summary here", "document"),
            action_entry("article:toggle-read", "Mark as read" if article.get("unread") else "Mark as unread", "check"),
            action_entry("article:toggle-save", "Remove from Read Later" if article.get("saved") else "Save for Read Later", "bookmark"),
            action_entry("article:edit", "Edit article", "edit"),
            action_entry("article:copy", "Copy link", "copy"),
            action_entry(
                "article:remove",
                "Remove from library",
                "trash",
                destructive=True,
                confirm={
                    "title": "Remove this article?",
                    "message": "The cached article and your local note will be removed.",
                    "confirmLabel": "Remove",
                },
            ),
        ],
        "preview": article_preview(article),
    }


def feed_preview(feed: dict) -> dict:
    count = feed_article_count(feed["id"])
    markdown = f"## {markdown_escape(feed.get('title', 'Feed'))}\n\n"
    markdown += markdown_escape(truncate(feed.get("description") or "No feed description provided.", 1200))
    if feed.get("site_url"):
        markdown += f"\n\n[Open website]({feed['site_url']})"
    if feed.get("last_error"):
        markdown += f"\n\n> **Last refresh error:** {markdown_escape(feed['last_error'])}"
    return {
        "markdown": markdown,
        "metadata": [
            {"label": "Articles", "text": str(count), "icon": "book"},
            {"label": "Category", "text": category_path(feed.get("category_id")), "icon": "folder"},
            {"label": "Last checked", "text": format_timestamp(feed.get("last_checked")), "icon": "refresh"},
            {"label": "URL", "text": truncate(feed.get("url", ""), 48), "url": feed.get("url")},
        ],
        **({"image": {"url": feed["image_url"], "width": 120}} if valid_http_url(feed.get("image_url", "")) else {}),
    }


def feed_item(feed: dict) -> dict:
    count = feed_article_count(feed["id"])
    unread = sum(1 for article in state["articles"] if article.get("feed_id") == feed["id"] and article.get("unread"))
    status = "disabled" if not feed.get("enabled", True) else f"{unread} new · {count} cached"
    if feed.get("last_error"):
        status += " · needs attention"
    return {
        "id": feed["id"],
        "title": feed.get("title") or feed.get("url") or "Untitled feed",
        "subtitle": f"{status} · {category_path(feed.get('category_id'))}",
        "icon": "cloud" if feed.get("enabled", True) else "close",
        "section": category_path(feed.get("category_id")),
        "accessories": ([{"text": str(unread), "color": "#3B82F6", "icon": "star"}] if unread else []),
        "actions": [
            action_entry("feed:refresh", "Refresh feed", "refresh"),
            action_entry("feed:edit", "Edit feed", "edit"),
            action_entry("feed:copy", "Copy feed URL", "copy"),
            action_entry(
                "feed:remove",
                "Remove feed and cached articles",
                "trash",
                destructive=True,
                confirm={
                    "title": "Remove this feed?",
                    "message": "The feed and all of its cached articles, notes, and Read Later entries will be removed.",
                    "confirmLabel": "Remove feed",
                },
            ),
        ],
        "preview": feed_preview(feed),
    }


def category_item(category: dict) -> dict:
    article_count, feed_count = category_counts(category["id"])
    subtitle = f"{article_count} articles · {feed_count} feeds"
    if category.get("description"):
        subtitle += f" · {truncate(category['description'], 70)}"
    actions = [action_entry("category:edit", "Edit category", "edit")]
    if category["id"] != UNCATEGORIZED_ID:
        actions.append(
            action_entry(
                "category:remove",
                "Delete category",
                "trash",
                destructive=True,
                confirm={
                    "title": f"Delete {category['name']}?",
                    "message": "Its feeds and articles will move to the parent category. The Uncategorized category cannot be deleted.",
                    "confirmLabel": "Delete category",
                },
            )
        )
    return {
        "id": category["id"],
        "title": category_path(category["id"]),
        "subtitle": subtitle,
        "icon": category.get("color") or "folder",
        "section": "Categories",
        "accessories": [
            {"text": str(article_count), "color": category.get("color", "#64748B"), "icon": "book"},
            {"text": str(feed_count), "color": "#64748B", "icon": "cloud"},
        ],
        "actions": actions,
        "preview": {
            "markdown": f"## {markdown_escape(category_path(category['id']))}\n\n{markdown_escape(category.get('description') or 'No description yet.')}",
            "metadata": [
                {"label": "Articles", "text": str(article_count), "icon": "book"},
                {"label": "Feeds", "text": str(feed_count), "icon": "cloud"},
                {"label": "Color", "text": category.get("color", "#64748B"), "color": category.get("color", "#64748B")},
            ],
        },
    }


def command_item(item_id: str, title: str, subtitle: str, icon: str, section: str = "Actions") -> dict:
    return {
        "id": item_id,
        "title": title,
        "subtitle": subtitle,
        "icon": icon,
        "section": section,
    }


def common_frame_actions() -> list[dict]:
    return [
        action_entry("frame:refresh-all", "Refresh all feeds", "refresh", shortcut="ctrl+r"),
        action_entry("frame:add-feed", "Add RSS/Atom feed", "plus", shortcut="ctrl+shift+a"),
        action_entry("frame:new-article", "Add article manually", "add"),
        action_entry("frame:add-category", "Add category or subcategory", "folder"),
        action_entry(
            "frame:mark-all-read",
            "Mark all articles as read",
            "check",
            confirm={
                "title": "Mark all articles as read?",
                "message": "This clears the New Articles list, but does not remove anything from Read Later.",
                "confirmLabel": "Mark all read",
            },
        ),
        action_entry("frame:import-opml", "Import subscriptions from OPML", "download"),
        action_entry("frame:export", "Export library and subscriptions", "upload"),
        action_entry("frame:settings", "RSS settings", "settings"),
    ]


def detail_actions(article: dict) -> list[dict]:
    return [
        action_entry("detail:open", "Open in browser", "open"),
        action_entry("detail:toggle-read", "Mark as read" if article.get("unread") else "Mark as unread", "check"),
        action_entry("detail:toggle-save", "Remove from Read Later" if article.get("saved") else "Save for Read Later", "bookmark"),
        action_entry("detail:edit", "Edit article", "edit"),
        action_entry("detail:copy", "Copy link", "copy"),
    ]


def render_root(rev: int, text: str) -> None:
    term = normalize_query(text)
    items = []
    if term:
        matching_articles = [
            article
            for article in state["articles"]
            if text_matches(
                term,
                article.get("title"),
                article.get("summary"),
                article.get("content"),
                article.get("source_name"),
                article.get("note"),
                " ".join(article.get("tags", [])),
                article_category(article),
            )
        ]
        matching_articles.sort(
            key=lambda article: parse_datetime(article.get("published") or article.get("added_at"))
            or dt.datetime.min.replace(tzinfo=dt.timezone.utc),
            reverse=True,
        )
        # Python's sort is stable, so this keeps the date ordering inside the
        # unread/read groups while making unread articles lead.
        matching_articles.sort(key=lambda article: 0 if article.get("unread") else 1)
        for article in matching_articles[:80]:
            items.append(article_item(article, "Articles"))
        for category in state["categories"]:
            if text_matches(term, category.get("name"), category_path(category["id"]), category.get("description")):
                items.append(category_item(category))
        for feed in state["feeds"]:
            if text_matches(term, feed.get("title"), feed.get("url"), feed.get("description"), category_path(feed.get("category_id"))):
                items.append(feed_item(feed))
        empty = {"icon": "search", "title": "No matching subscriptions", "hint": "Search titles, sources, tags, feeds, or category names."} if not items else None
    else:
        newest = sorted(
            [article for article in state["articles"] if article.get("unread")],
            key=lambda article: parse_datetime(article.get("published") or article.get("added_at")) or dt.datetime.min.replace(tzinfo=dt.timezone.utc),
            reverse=True,
        )
        for article in newest[:12]:
            items.append(article_item(article, "New Articles"))
        newest_ids = {article["id"] for article in newest[:12]}
        saved = sorted(
            [article for article in state["articles"] if article.get("saved") and article["id"] not in newest_ids],
            key=lambda article: parse_datetime(article.get("saved_at") or article.get("published") or article.get("added_at")) or dt.datetime.min.replace(tzinfo=dt.timezone.utc),
            reverse=True,
        )
        for article in saved[:12]:
            items.append(article_item(article, "Read Later"))
        for category in sorted(state["categories"], key=lambda item: category_path(item["id"]).casefold()):
            items.append(category_item(category))
        for feed in sorted(state["feeds"], key=lambda item: item.get("title", "").casefold()):
            items.append(feed_item(feed))
        items.extend(
            [
                command_item("cmd:new-articles", "All New Articles", "Unread stories from every feed", "star"),
                command_item("cmd:read-later", "Read Later Library", "Saved stories, notes, and tags", "bookmark"),
                command_item("cmd:all-articles", "All Articles", "Search the complete cached library", "book"),
                command_item("cmd:feeds", "Manage Feeds", "Add, edit, refresh, or remove subscriptions", "cloud"),
                command_item("cmd:categories", "Manage Categories", "Organize feeds and stories into nested groups", "folder"),
                command_item("cmd:import", "Import OPML", "Bring subscriptions from another reader", "download"),
                command_item("cmd:export", "Export Library", "Back up subscriptions and saved stories", "upload"),
            ]
        )
        empty = None

    frame = {
        "type": "render",
        "rev": rev,
        "view": "list",
        "preview": {"enabled": True},
        "placeholder": "Search articles, feeds, categories, or tags…",
        "actions": common_frame_actions(),
        "items": items,
    }
    if empty:
        frame["empty"] = empty
    send(frame)


def article_filter(kind: str, term: str) -> list[dict]:
    articles = []
    for article in state["articles"]:
        if kind == "unread" and not article.get("unread"):
            continue
        if kind == "saved" and not article.get("saved"):
            continue
        if kind == "category" and article_category_id(article) != state.get("category_id"):
            continue
        if kind == "feed" and article.get("feed_id") != state.get("feed_id"):
            continue
        if term and not text_matches(
            term,
            article.get("title"),
            article.get("summary"),
            article.get("content"),
            article.get("source_name"),
            article.get("note"),
            " ".join(article.get("tags", [])),
            article_category(article),
        ):
            continue
        articles.append(article)
    articles.sort(
        key=lambda article: parse_datetime(article.get("published") or article.get("added_at"))
        or dt.datetime.min.replace(tzinfo=dt.timezone.utc),
        reverse=True,
    )
    articles.sort(key=lambda article: 0 if article.get("unread") else 1)
    return articles


def render_article_screen(rev: int, text: str, kind: str) -> None:
    term = normalize_query(text)
    articles = article_filter(kind, term)
    visible = articles[: state.get("list_limit", PAGE_SIZE)]
    if kind == "unread":
        title = "New Articles"
        placeholder = "Search new articles…"
    elif kind == "saved":
        title = "Read Later"
        placeholder = "Search saved articles…"
    elif kind == "category":
        title = category_path(state.get("category_id"))
        placeholder = f"Search {title}…"
    elif kind == "feed":
        feed = get_feed(state.get("feed_id"))
        title = feed.get("title", "Feed") if feed else "Feed"
        placeholder = f"Search {title}…"
    else:
        title = "All Articles"
        placeholder = "Search all cached articles…"
    frame = {
        "type": "render",
        "rev": rev,
        "view": "list",
        "canGoBack": True,
        "preview": {"enabled": True},
        "placeholder": placeholder,
        "actions": common_frame_actions(),
        "items": [article_item(article) for article in visible],
        "emptyText": f"No articles in {title}. Refresh a feed or add one manually.",
        "hasMore": len(visible) < len(articles),
    }
    if kind == "feed" and state.get("feed_id"):
        frame["actions"] = [
            action_entry("frame:refresh-current", "Refresh this feed", "refresh", shortcut="ctrl+r"),
            action_entry("frame:edit-current-feed", "Edit this feed", "edit"),
            action_entry("frame:add-feed", "Add another feed", "plus"),
            action_entry("frame:new-article", "Add article manually", "add"),
        ]
    if kind == "category" and state.get("category_id"):
        frame["actions"] = [
            action_entry("frame:edit-current-category", "Edit this category", "edit"),
            action_entry("frame:add-category", "Add subcategory", "folder"),
            action_entry("frame:refresh-all", "Refresh all feeds", "refresh"),
            action_entry("frame:new-article", "Add article manually", "add"),
        ]
    if not visible:
        frame["empty"] = {
            "icon": "book",
            "title": f"No articles in {title}",
            "hint": "Try refreshing your feeds or add a manual article to your library.",
            "action": {"id": "frame:new-article", "title": "Add article", "icon": "add"},
        }
    send(frame)


def render_feed_list(rev: int, text: str) -> None:
    term = normalize_query(text)
    feeds = [
        feed
        for feed in state["feeds"]
        if text_matches(term, feed.get("title"), feed.get("url"), feed.get("description"), category_path(feed.get("category_id")))
    ]
    feeds.sort(key=lambda feed: (category_path(feed.get("category_id")).casefold(), feed.get("title", "").casefold()))
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "preview": {"enabled": True},
            "placeholder": "Search subscriptions…",
            "actions": [
                action_entry("frame:add-feed", "Add RSS/Atom feed", "plus", shortcut="ctrl+shift+a"),
                action_entry("frame:refresh-all", "Refresh all feeds", "refresh", shortcut="ctrl+r"),
                action_entry("frame:import-opml", "Import OPML", "download"),
                action_entry("frame:export", "Export library", "upload"),
            ],
            "items": [feed_item(feed) for feed in feeds],
            "emptyText": "No subscriptions yet. Add a feed or import an OPML file.",
        }
    )


def render_category_list(rev: int, text: str) -> None:
    term = normalize_query(text)
    categories = [
        category
        for category in state["categories"]
        if text_matches(term, category.get("name"), category_path(category["id"]), category.get("description"))
    ]
    categories.sort(key=lambda category: category_path(category["id"]).casefold())
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "preview": {"enabled": True},
            "placeholder": "Search categories…",
            "actions": [
                action_entry("frame:add-category", "Add category or subcategory", "folder", shortcut="ctrl+shift+c"),
                action_entry("frame:export", "Export library", "upload"),
            ],
            "items": [category_item(category) for category in categories],
            "emptyText": "No categories match this search.",
        }
    )


def render_article_detail(rev: int) -> None:
    article = get_article(state.get("detail_article_id"))
    if article is None:
        pop_screen()
        return
    body = article.get("content") or article.get("summary") or "This article did not include a readable summary."
    markdown = (
        f"# {markdown_escape(article.get('title', 'Untitled article'))}\n\n"
        f"{markdown_escape(body)}\n\n"
        f"[Open the original article]({article.get('url', '')})"
    )
    if article.get("note"):
        markdown += f"\n\n## Your note\n\n{markdown_escape(article['note'])}"
    if article.get("tags"):
        markdown += f"\n\n**Tags:** {markdown_escape(', '.join(article['tags']))}"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "canGoBack": True,
            "detail": {
                "wide": True,
                "markdown": markdown,
                "metadata": article_preview(article)["metadata"],
            },
            "actions": detail_actions(article),
        }
    )


# ---------------------------------------------------------------------------
# Forms


def form_value(name: str, default=None):
    if name in state.get("form_values", {}):
        return state["form_values"].get(name)
    return default


def field_error(name: str) -> dict:
    error = state.get("form_errors", {}).get(name)
    return {"error": error} if error else {}


def render_feed_form(rev: int) -> None:
    feed = get_feed(state.get("form_entity_id"))
    editing = feed is not None
    values = state.get("form_values", {})
    url = form_value("feed_url", feed.get("url", "") if feed else "")
    title = form_value("feed_title", feed.get("title", "") if feed else "")
    category_id = form_value("feed_category", feed.get("category_id", UNCATEGORIZED_ID) if feed else UNCATEGORIZED_ID)
    tags = form_value("feed_tags", feed.get("tags", []) if feed else [])
    enabled = form_value("feed_enabled", feed.get("enabled", True) if feed else True)
    label = "Edit Feed" if editing else "Add RSS / Atom Feed"
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "canGoBack": True,
            "form": {
                "title": label,
                "buttons": [
                    {"id": "save", "label": "Save Feed"},
                    {"id": "save_refresh", "label": "Save & Refresh"},
                ],
                "fields": [
                    {
                        "id": "feed_url",
                        "type": "text",
                        "label": "Feed URL",
                        "placeholder": "https://example.com/feed.xml",
                        "value": url,
                        "required": True,
                        "description": "Paste an RSS, RSS 2, RDF, or Atom feed URL.",
                        **field_error("feed_url"),
                    },
                    {
                        "id": "feed_title",
                        "type": "text",
                        "label": "Display name",
                        "placeholder": "Optional custom name",
                        "value": title,
                        "description": "Leave blank to use the title published by the feed.",
                        **field_error("feed_title"),
                    },
                    {
                        "id": "feed_category",
                        "type": "dropdown",
                        "label": "Category",
                        "value": category_id if get_category(category_id) else UNCATEGORIZED_ID,
                        "options": category_options(),
                        **field_error("feed_category"),
                    },
                    {
                        "id": "feed_tags",
                        "type": "tags",
                        "label": "Feed tags",
                        "value": tags if isinstance(tags, list) else normalize_tags(tags),
                        "options": sorted({tag for feed_item_data in state["feeds"] for tag in feed_item_data.get("tags", [])}),
                        "description": "Optional tags make search and filtering faster.",
                    },
                    {
                        "id": "feed_enabled",
                        "type": "checkbox",
                        "label": "Refresh this feed automatically",
                        "value": bool(enabled),
                    },
                ],
            },
        }
    )


def render_category_form(rev: int) -> None:
    category = get_category(state.get("form_entity_id"))
    editing = category is not None
    name = form_value("category_name", category.get("name", "") if category else "")
    parent_id = form_value("category_parent", category.get("parent_id") or "" if category else "")
    color = form_value("category_color", category.get("color", "#64748B") if category else "#64748B")
    description = form_value("category_description", category.get("description", "") if category else "")
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "canGoBack": True,
            "form": {
                "title": "Edit Category" if editing else "Add Category / Subcategory",
                "submitLabel": "Save Category",
                "fields": [
                    {
                        "id": "category_name",
                        "type": "text",
                        "label": "Name",
                        "placeholder": "e.g. Frontend, Local News, Essays",
                        "value": name,
                        "required": True,
                        **field_error("category_name"),
                    },
                    {
                        "id": "category_parent",
                        "type": "dropdown",
                        "label": "Parent category",
                        "value": parent_id if parent_id and get_category(parent_id) else "",
                        "options": [{"value": "", "label": "Top level"}] + category_options(exclude_id=category["id"] if category else None),
                        "description": "Choose a parent to create a nested subcategory.",
                        **field_error("category_parent"),
                    },
                    {
                        "id": "category_color",
                        "type": "text",
                        "label": "Color",
                        "value": color,
                        "placeholder": "#64748B",
                        "description": "Six-digit hex color used for the category icon and badge.",
                        **field_error("category_color"),
                    },
                    {
                        "id": "category_description",
                        "type": "textarea",
                        "label": "Description",
                        "value": description,
                        "placeholder": "What belongs in this category?",
                    },
                ],
            },
        }
    )


def render_article_form(rev: int) -> None:
    article = get_article(state.get("form_entity_id"))
    editing = article is not None
    values = state.get("form_values", {})
    title = form_value("article_title", article.get("title", "") if article else "")
    url = form_value("article_url", article.get("url", "") if article else "")
    summary = form_value("article_summary", article.get("summary", "") if article else "")
    default_category = (article.get("category_id") or article_category_id(article)) if article else UNCATEGORIZED_ID
    category_id = form_value("article_category", default_category)
    tags = form_value("article_tags", article.get("tags", []) if article else [])
    note = form_value("article_note", article.get("note", "") if article else "")
    saved = form_value("article_saved", article.get("saved", True) if article else True)
    unread = form_value("article_unread", article.get("unread", True) if article else True)
    source = form_value("article_source", article.get("source_name", "Manual") if article else "Manual")
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "canGoBack": True,
            "form": {
                "title": "Edit Article" if editing else "Add Article Manually",
                "submitLabel": "Save Article",
                "fields": [
                    {
                        "id": "article_title",
                        "type": "text",
                        "label": "Title",
                        "placeholder": "Article title",
                        "value": title,
                        "required": True,
                        **field_error("article_title"),
                    },
                    {
                        "id": "article_url",
                        "type": "text",
                        "label": "Article URL",
                        "placeholder": "https://example.com/story",
                        "value": url,
                        "required": True,
                        **field_error("article_url"),
                    },
                    {
                        "id": "article_source",
                        "type": "text",
                        "label": "Source name",
                        "value": source,
                        "placeholder": "Manual, newsletter, website…",
                    },
                    {
                        "id": "article_summary",
                        "type": "textarea",
                        "label": "Summary",
                        "value": summary,
                        "placeholder": "A short excerpt or your own summary",
                    },
                    {
                        "id": "article_category",
                        "type": "dropdown",
                        "label": "Category",
                        "value": category_id if get_category(category_id) else UNCATEGORIZED_ID,
                        "options": category_options(),
                    },
                    {
                        "id": "article_tags",
                        "type": "tags",
                        "label": "Tags",
                        "value": tags if isinstance(tags, list) else normalize_tags(tags),
                        "options": sorted({tag for item in state["articles"] for tag in item.get("tags", [])}),
                    },
                    {
                        "id": "article_note",
                        "type": "textarea",
                        "label": "Private note",
                        "value": note,
                        "placeholder": "Why do you want to remember this?",
                    },
                    {"id": "article_saved", "type": "checkbox", "label": "Keep in Read Later", "value": bool(saved)},
                    {"id": "article_unread", "type": "checkbox", "label": "Show as new / unread", "value": bool(unread)},
                ],
            },
        }
    )


def render_settings_form(rev: int) -> None:
    settings = state["settings"]
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "canGoBack": True,
            "form": {
                "title": "RSS Settings",
                "submitLabel": "Save Settings",
                "fields": [
                    {
                        "id": "settings_max_articles",
                        "type": "number",
                        "label": "Cached articles per feed",
                        "value": form_value("settings_max_articles", settings.get("max_articles_per_feed", 100)),
                        "min": 10,
                        "max": 500,
                        "description": "Older read, unsaved articles are pruned after a refresh.",
                        **field_error("settings_max_articles"),
                    },
                    {
                        "id": "settings_refresh_open",
                        "type": "checkbox",
                        "label": "Refresh feeds when RSS opens",
                        "value": bool(form_value("settings_refresh_open", settings.get("refresh_on_open", True))),
                        "description": "The dashboard appears immediately; refresh runs in the background.",
                    },
                    {
                        "id": "settings_mark_open_read",
                        "type": "checkbox",
                        "label": "Mark an article read when opened",
                        "value": bool(form_value("settings_mark_open_read", settings.get("mark_open_read", True))),
                    },
                ],
            },
        }
    )


def render_import_form(rev: int) -> None:
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "canGoBack": True,
            "form": {
                "title": "Import OPML Subscriptions",
                "submitLabel": "Import and Refresh",
                "fields": [
                    {
                        "id": "opml_file",
                        "type": "filepicker",
                        "label": "OPML file",
                        "required": True,
                        "description": "Folders in the OPML file become RSS categories and subcategories.",
                        **field_error("opml_file"),
                    }
                ],
            },
        }
    )


def render_export_form(rev: int) -> None:
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "canGoBack": True,
            "form": {
                "title": "Export RSS Library",
                "submitLabel": "Export",
                "fields": [
                    {
                        "id": "export_folder",
                        "type": "folderpicker",
                        "label": "Destination folder",
                        "required": True,
                        **field_error("export_folder"),
                    },
                    {
                        "id": "export_articles",
                        "type": "checkbox",
                        "label": "Include cached articles, notes, and Read Later items",
                        "value": True,
                    },
                ],
            },
        }
    )


def render_form_screen(rev: int) -> None:
    form_kind = state.get("form_kind")
    if form_kind == "feed_form":
        render_feed_form(rev)
    elif form_kind == "category_form":
        render_category_form(rev)
    elif form_kind == "article_form":
        render_article_form(rev)
    elif form_kind == "settings_form":
        render_settings_form(rev)
    elif form_kind == "import_form":
        render_import_form(rev)
    elif form_kind == "export_form":
        render_export_form(rev)


# ---------------------------------------------------------------------------
# Navigation


def snapshot_screen() -> dict:
    return {
        "screen": state["screen"],
        "list_kind": state.get("list_kind", "all"),
        "category_id": state.get("category_id"),
        "feed_id": state.get("feed_id"),
        "detail_article_id": state.get("detail_article_id"),
        "query": state.get("query", ""),
    }


def restore_screen(snapshot: dict) -> None:
    for key, value in snapshot.items():
        state[key] = value
    state["form_kind"] = None
    state["form_entity_id"] = None
    state["form_values"] = {}
    state["form_errors"] = {}
    state["list_limit"] = PAGE_SIZE


def navigate(screen: str, **fields) -> None:
    state["history"].append(snapshot_screen())
    state["screen"] = screen
    state["query"] = ""
    state["list_limit"] = PAGE_SIZE
    state["form_kind"] = None
    state["form_entity_id"] = None
    state["form_values"] = {}
    state["form_errors"] = {}
    state.update(fields)
    command("setQuery", text="")
    render_current(0, "")


def begin_form(form_kind: str, entity_id: str | None = None) -> None:
    state["history"].append(snapshot_screen())
    state["screen"] = form_kind
    state["form_kind"] = form_kind
    state["form_entity_id"] = entity_id
    state["form_values"] = {}
    state["form_errors"] = {}
    state["query"] = ""
    command("setQuery", text="")
    render_current(0, "")


def pop_screen() -> None:
    if state["history"]:
        restore_screen(state["history"].pop())
    else:
        state["screen"] = "root"
        state["query"] = ""
    command("setQuery", text="")
    render_current(0, state.get("query", ""))


def render_current(rev: int, text: str | None = None) -> None:
    if text is not None and state["screen"] not in FORM_SCREENS and state["screen"] != "detail":
        state["query"] = text
    query = state.get("query", "")
    screen = state["screen"]
    if screen == "root":
        render_root(rev, query)
    elif screen == "articles":
        render_article_screen(rev, query, state.get("list_kind", "all"))
    elif screen == "feeds":
        render_feed_list(rev, query)
    elif screen == "categories":
        render_category_list(rev, query)
    elif screen == "category":
        render_article_screen(rev, query, "category")
    elif screen == "feed":
        render_article_screen(rev, query, "feed")
    elif screen == "detail":
        render_article_detail(rev)
    elif screen in FORM_SCREENS:
        render_form_screen(rev)
    else:
        state["screen"] = "root"
        render_root(rev, query)


# ---------------------------------------------------------------------------
# Refreshing and merging feeds


def merge_feed(feed: dict, parsed_info: dict, parsed_articles: list[dict]) -> int:
    if parsed_info.get("title") and not feed.get("custom_title"):
        feed["title"] = parsed_info["title"]
    if parsed_info.get("description"):
        feed["description"] = parsed_info["description"]
    if valid_http_url(parsed_info.get("site_url", "")):
        feed["site_url"] = parsed_info["site_url"]
    if parsed_info.get("image_url"):
        feed["image_url"] = parsed_info["image_url"]

    existing = {article["id"]: article for article in state["articles"]}
    new_count = 0
    for incoming in parsed_articles:
        article = existing.get(incoming["id"])
        if article is None:
            article = normalize_article(
                {
                    **incoming,
                    "feed_id": feed["id"],
                    "source_name": feed["title"],
                    "category_id": None,
                    "unread": True,
                    "saved": False,
                    "added_at": now_iso(),
                    "updated_at": now_iso(),
                }
            )
            state["articles"].append(article)
            existing[article["id"]] = article
            new_count += 1
        else:
            article.update(
                {
                    "feed_id": feed["id"],
                    "source_name": feed["title"],
                    "title": incoming.get("title") or article.get("title"),
                    "url": incoming.get("url") or article.get("url"),
                    "summary": incoming.get("summary") or article.get("summary"),
                    "content": incoming.get("content") or article.get("content"),
                    "image_url": incoming.get("image_url") or article.get("image_url"),
                    "author": incoming.get("author") or article.get("author"),
                    "published": incoming.get("published") or article.get("published"),
                    "tags": normalize_tags(incoming.get("tags") or article.get("tags")),
                    "updated_at": now_iso(),
                }
            )

    max_items = int(state["settings"].get("max_articles_per_feed", 100))
    related = [article for article in state["articles"] if article.get("feed_id") == feed["id"]]
    related.sort(
        key=lambda article: parse_datetime(article.get("published") or article.get("added_at")) or dt.datetime.min.replace(tzinfo=dt.timezone.utc),
        reverse=True,
    )
    if len(related) > max_items:
        keep = related[:max_items]
        keep_ids = {article["id"] for article in keep}
        # Saved, unread, or annotated items are never pruned just because they
        # fell outside the normal cache window.
        protected = {
            article["id"]
            for article in related[max_items:]
            if article.get("saved") or article.get("unread") or article.get("note")
        }
        remove_ids = {article["id"] for article in related if article["id"] not in keep_ids and article["id"] not in protected}
        state["articles"] = [article for article in state["articles"] if article["id"] not in remove_ids]
    feed["last_checked"] = now_iso()
    feed["last_error"] = ""
    return new_count


def start_refresh(feed_ids: list[str] | None = None) -> None:
    global REFRESH_THREAD
    with REFRESH_LOCK:
        if REFRESH_THREAD is not None and REFRESH_THREAD.is_alive():
            toast("A feed refresh is already running.", "info")
            return
        selected = feed_ids or [feed["id"] for feed in state["feeds"] if feed.get("enabled", True)]
        selected = [feed_id for feed_id in selected if get_feed(feed_id) is not None]
        if not selected:
            toast("Add a feed before refreshing.", "info")
            return
        state["refreshing"] = True
        toast(f"Refreshing {len(selected)} feed{'s' if len(selected) != 1 else ''}…", "progress")

        def run() -> None:
            new_count = 0
            successes = 0
            errors = []
            for feed_id in selected:
                if state.get("closing"):
                    break
                feed = get_feed(feed_id)
                if feed is None:
                    continue
                try:
                    document = fetch_feed_document(feed["url"])
                    info, articles = parse_feed_document(document, feed["url"])
                    new_count += merge_feed(feed, info, articles)
                    successes += 1
                except (urllib.error.URLError, TimeoutError, ET.ParseError, ValueError, OSError) as exc:
                    message = truncate(str(exc), 180) or exc.__class__.__name__
                    feed["last_checked"] = now_iso()
                    feed["last_error"] = message
                    errors.append(f"{feed.get('title', feed['url'])}: {message}")
                except Exception as exc:  # keep one broken feed from killing all refreshes
                    log("refresh error", feed.get("url"), repr(exc))
                    message = truncate(str(exc), 180) or exc.__class__.__name__
                    feed["last_checked"] = now_iso()
                    feed["last_error"] = message
                    errors.append(f"{feed.get('title', feed['url'])}: {message}")
            state["refreshing"] = False
            save_state()
            if errors:
                toast(f"Refreshed {successes}; {len(errors)} feed{'s' if len(errors) != 1 else ''} failed.", "error")
                log("refresh failures:", " | ".join(errors))
            else:
                toast(f"Refresh complete · {new_count} new article{'s' if new_count != 1 else ''}.", "success")
            if not state.get("closing") and state["screen"] not in FORM_SCREENS and state["screen"] != "detail":
                render_current(0, state.get("query", ""))

        REFRESH_THREAD = threading.Thread(target=run, name="rss-refresh", daemon=True)
        REFRESH_THREAD.start()


# ---------------------------------------------------------------------------
# OPML import/export


def parse_opml_file(path: str) -> list[dict]:
    root = ET.parse(path).getroot()
    imported = []

    def walk(parent, folders: list[str]) -> None:
        for outline in list(parent):
            if local_name(outline.tag) != "outline":
                continue
            xml_url = str(outline.attrib.get("xmlUrl") or outline.attrib.get("xmlurl") or "").strip()
            title = str(outline.attrib.get("title") or outline.attrib.get("text") or "").strip()
            if xml_url and valid_http_url(xml_url):
                imported.append(
                    {
                        "url": xml_url,
                        "title": title,
                        "site_url": str(outline.attrib.get("htmlUrl") or outline.attrib.get("htmlurl") or "").strip(),
                        "folders": list(folders),
                    }
                )
            else:
                walk(outline, folders + ([title] if title else []))

    body = child_element(root, {"body"}) or root
    walk(body, [])
    return imported


def ensure_category_path(parts: list[str]) -> str:
    parent_id = None
    for raw_name in parts:
        name = re.sub(r"\s+", " ", raw_name.strip())
        if not name:
            continue
        existing = next(
            (
                category
                for category in state["categories"]
                if category.get("parent_id") == parent_id and category.get("name", "").casefold() == name.casefold()
            ),
            None,
        )
        if existing is None:
            existing = {
                "id": slug_id("category", f"{parent_id or 'root'}|{name.casefold()}"),
                "name": name,
                "parent_id": parent_id,
                "color": "#64748B",
                "description": "Imported from OPML.",
            }
            state["categories"].append(normalize_category(existing))
        parent_id = existing["id"]
    return parent_id or UNCATEGORIZED_ID


def import_opml(path: str) -> tuple[int, int]:
    entries = parse_opml_file(path)
    added = 0
    categories_added = 0
    before_categories = len(state["categories"])
    known_urls = {feed.get("url", "").casefold() for feed in state["feeds"]}
    for entry in entries:
        url = entry["url"]
        if url.casefold() in known_urls:
            continue
        category_id = ensure_category_path(entry.get("folders", []))
        feed = normalize_feed(
            {
                "id": slug_id("feed", url),
                "url": url,
                "title": entry.get("title") or urllib.parse.urlparse(url).netloc or url,
                "custom_title": bool(entry.get("title")),
                "site_url": entry.get("site_url", ""),
                "category_id": category_id,
                "enabled": True,
                "added_at": now_iso(),
            }
        )
        state["feeds"].append(feed)
        known_urls.add(url.casefold())
        added += 1
    categories_added = len(state["categories"]) - before_categories
    return added, categories_added


def export_opml(path: str) -> None:
    root = ET.Element("opml", version="2.0")
    head = ET.SubElement(root, "head")
    ET.SubElement(head, "title").text = "Tabame RSS subscriptions"
    body = ET.SubElement(root, "body")
    category_nodes: dict[tuple[str | None, str], ET.Element] = {}

    def node_for(category_id: str) -> ET.Element:
        category = get_category(category_id) or get_category(UNCATEGORIZED_ID)
        if category is None or category["id"] == UNCATEGORIZED_ID:
            return body
        parent = category.get("parent_id")
        key = (parent, category["name"])
        if key in category_nodes:
            return category_nodes[key]
        parent_node = node_for(parent) if parent else body
        node = ET.SubElement(parent_node, "outline", text=category["name"], title=category["name"])
        category_nodes[key] = node
        return node

    for feed in sorted(state["feeds"], key=lambda item: item.get("title", "").casefold()):
        parent = node_for(feed.get("category_id") or UNCATEGORIZED_ID)
        attrs = {
            "type": "rss",
            "text": feed.get("title", "Feed"),
            "title": feed.get("title", "Feed"),
            "xmlUrl": feed.get("url", ""),
        }
        if feed.get("site_url"):
            attrs["htmlUrl"] = feed["site_url"]
        ET.SubElement(parent, "outline", **attrs)
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)


def export_library(folder: str, include_articles: bool) -> tuple[str, str]:
    if not os.path.isdir(folder):
        raise ValueError("Choose an existing destination folder.")
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    json_path = os.path.join(folder, f"tabame-rss-{stamp}.json")
    opml_path = os.path.join(folder, f"tabame-rss-{stamp}.opml")
    data = serializable_state()
    if not include_articles:
        data["articles"] = []
    with open(json_path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
    export_opml(opml_path)
    return json_path, opml_path


# ---------------------------------------------------------------------------
# Form submissions


def set_form_error(values: dict, errors: dict) -> None:
    state["form_values"] = values
    state["form_errors"] = errors
    render_current(0)


def submit_feed(values: dict, button: str | None) -> None:
    url = str(values.get("feed_url") or "").strip()
    errors = {}
    if not valid_http_url(url):
        errors["feed_url"] = "Enter a complete http:// or https:// feed URL."
    editing = get_feed(state.get("form_entity_id"))
    duplicate = next((feed for feed in state["feeds"] if feed.get("url", "").casefold() == url.casefold() and (editing is None or feed["id"] != editing["id"])), None)
    if duplicate:
        errors["feed_url"] = f"This URL is already subscribed as {duplicate.get('title', 'another feed')}."
    category_id = str(values.get("feed_category") or UNCATEGORIZED_ID)
    if not get_category(category_id):
        errors["feed_category"] = "Choose an existing category."
    if errors:
        set_form_error(values, errors)
        return

    title = str(values.get("feed_title") or "").strip()
    tags = normalize_tags(values.get("feed_tags"))
    enabled = bool(values.get("feed_enabled", True))
    if editing:
        editing.update(
            {
                "url": url,
                "title": title or editing.get("title") or urllib.parse.urlparse(url).netloc or url,
                "custom_title": bool(title),
                "category_id": category_id,
                "tags": tags,
                "enabled": enabled,
                "last_error": "",
            }
        )
        feed_id = editing["id"]
        message = "Feed updated."
    else:
        feed_id = slug_id("feed", url)
        while get_feed(feed_id):
            feed_id += "x"
        feed = normalize_feed(
            {
                "id": feed_id,
                "url": url,
                "title": title or urllib.parse.urlparse(url).netloc or url,
                "custom_title": bool(title),
                "category_id": category_id,
                "tags": tags,
                "enabled": enabled,
                "added_at": now_iso(),
            }
        )
        state["feeds"].append(feed)
        message = "Feed added."
    save_state()
    pop_screen()
    toast(message)
    if button in {None, "save_refresh"}:
        start_refresh([feed_id])


def submit_category(values: dict) -> None:
    name = re.sub(r"\s+", " ", str(values.get("category_name") or "").strip())
    parent_id = str(values.get("category_parent") or "").strip() or None
    color = normalize_color(values.get("category_color"), "")
    errors = {}
    if not name:
        errors["category_name"] = "Give the category a name."
    if parent_id and not get_category(parent_id):
        errors["category_parent"] = "Choose an existing parent category."
    if state.get("form_entity_id") and parent_id == state.get("form_entity_id"):
        errors["category_parent"] = "A category cannot be its own parent."
    if state.get("form_entity_id") and parent_id and is_descendant(parent_id, state["form_entity_id"]):
        errors["category_parent"] = "A category cannot be placed below one of its own subcategories."
    if not color:
        errors["category_color"] = "Use a color such as #64748B."
    duplicate = next(
        (
            category
            for category in state["categories"]
            if category.get("id") != state.get("form_entity_id")
            and category.get("parent_id") == parent_id
            and category.get("name", "").casefold() == name.casefold()
        ),
        None,
    )
    if duplicate:
        errors["category_name"] = "A category with this name already exists at this level."
    if errors:
        set_form_error(values, errors)
        return

    description = str(values.get("category_description") or "").strip()[:1000]
    if state.get("form_entity_id"):
        category = get_category(state["form_entity_id"])
        if category:
            category.update({"name": name, "parent_id": parent_id, "color": color, "description": description})
    else:
        category = normalize_category(
            {
                "id": slug_id("category", f"{parent_id or 'root'}|{name.casefold()}|{time.time_ns()}"),
                "name": name,
                "parent_id": parent_id,
                "color": color,
                "description": description,
            }
        )
        state["categories"].append(category)
    save_state()
    pop_screen()
    toast("Category saved.")


def submit_article(values: dict) -> None:
    title = str(values.get("article_title") or "").strip()
    url = str(values.get("article_url") or "").strip()
    errors = {}
    if not title:
        errors["article_title"] = "Give the article a title."
    if not valid_http_url(url):
        errors["article_url"] = "Enter a complete http:// or https:// article URL."
    category_id = str(values.get("article_category") or UNCATEGORIZED_ID)
    if not get_category(category_id):
        errors["article_category"] = "Choose an existing category."
    if errors:
        set_form_error(values, errors)
        return

    article = get_article(state.get("form_entity_id"))
    if article is None:
        article = normalize_article(
            {
                "id": slug_id("article-manual", url + title + str(time.time_ns())),
                "feed_id": None,
                "published": now_iso(),
                "added_at": now_iso(),
            }
        )
        state["articles"].append(article)
    article.update(
        {
            "title": title,
            "url": url,
            "source_name": str(values.get("article_source") or "Manual").strip() or "Manual",
            "summary": str(values.get("article_summary") or "").strip()[:6000],
            "category_id": category_id,
            "tags": normalize_tags(values.get("article_tags")),
            "note": str(values.get("article_note") or "").strip()[:6000],
            "saved": bool(values.get("article_saved", True)),
            "unread": bool(values.get("article_unread", True)),
            "updated_at": now_iso(),
        }
    )
    if article["saved"] and not article.get("saved_at"):
        article["saved_at"] = now_iso()
    if not article["saved"]:
        article["saved_at"] = None
    save_state()
    pop_screen()
    toast("Article saved.")


def submit_settings(values: dict) -> None:
    try:
        max_articles = int(values.get("settings_max_articles"))
    except (TypeError, ValueError):
        max_articles = 0
    if not 10 <= max_articles <= 500:
        set_form_error(values, {"settings_max_articles": "Choose a number between 10 and 500."})
        return
    state["settings"].update(
        {
            "max_articles_per_feed": max_articles,
            "refresh_on_open": bool(values.get("settings_refresh_open", True)),
            "mark_open_read": bool(values.get("settings_mark_open_read", True)),
        }
    )
    save_state()
    refresh_requested = state["settings"]["refresh_on_open"]
    pop_screen()
    toast("RSS settings saved.")
    if refresh_requested and state["feeds"]:
        start_refresh()


def submit_import(values: dict) -> None:
    path = str(values.get("opml_file") or "").strip()
    if not path or not os.path.isfile(path):
        set_form_error(values, {"opml_file": "Choose an existing OPML file."})
        return
    try:
        added, categories_added = import_opml(path)
    except (ET.ParseError, OSError, ValueError) as exc:
        set_form_error(values, {"opml_file": f"Could not read OPML: {truncate(str(exc), 180)}"})
        return
    save_state()
    pop_screen()
    toast(f"Imported {added} feed{'s' if added != 1 else ''} and {categories_added} categor{'ies' if categories_added != 1 else 'y'}.")
    if added:
        start_refresh()


def submit_export(values: dict) -> None:
    folder = str(values.get("export_folder") or "").strip()
    if not os.path.isdir(folder):
        set_form_error(values, {"export_folder": "Choose an existing destination folder."})
        return
    try:
        json_path, opml_path = export_library(folder, bool(values.get("export_articles", True)))
    except (OSError, ValueError) as exc:
        set_form_error(values, {"export_folder": f"Export failed: {truncate(str(exc), 180)}"})
        return
    pop_screen()
    toast(f"Exported library and subscriptions to {os.path.basename(folder)}.")
    log("exported", json_path, opml_path)


def handle_submit(msg: dict) -> None:
    values = msg.get("values") if isinstance(msg.get("values"), dict) else {}
    button = msg.get("button")
    kind = state.get("form_kind")
    if kind == "feed_form":
        submit_feed(values, button)
    elif kind == "category_form":
        submit_category(values)
    elif kind == "article_form":
        submit_article(values)
    elif kind == "settings_form":
        submit_settings(values)
    elif kind == "import_form":
        submit_import(values)
    elif kind == "export_form":
        submit_export(values)


# ---------------------------------------------------------------------------
# Actions


def mark_all_read() -> None:
    changed = 0
    for article in state["articles"]:
        if article.get("unread"):
            article["unread"] = False
            changed += 1
    save_state()
    render_current(0, state.get("query", ""))
    toast(f"Marked {changed} article{'s' if changed != 1 else ''} as read.")


def open_article(article: dict) -> None:
    if state["settings"].get("mark_open_read", True) and article.get("unread"):
        article["unread"] = False
        save_state()
    if valid_http_url(article.get("url", "")):
        command("open", url=article["url"])
        command("hide")
    else:
        toast("This article does not have a valid URL.", "error")


def toggle_article_read(article: dict) -> None:
    article["unread"] = not article.get("unread")
    article["updated_at"] = now_iso()
    save_state()
    if state["screen"] == "detail":
        render_article_detail(0)
    else:
        render_current(0, state.get("query", ""))
    toast("Marked as new." if article["unread"] else "Marked as read.")


def toggle_article_saved(article: dict) -> None:
    article["saved"] = not article.get("saved")
    article["saved_at"] = now_iso() if article["saved"] else None
    article["updated_at"] = now_iso()
    save_state()
    if state["screen"] == "detail":
        render_article_detail(0)
    else:
        render_current(0, state.get("query", ""))
    toast("Saved to Read Later." if article["saved"] else "Removed from Read Later.")


def remove_article(article: dict) -> None:
    state["articles"] = [item for item in state["articles"] if item["id"] != article["id"]]
    save_state()
    if state["screen"] == "detail":
        pop_screen()
    else:
        render_current(0, state.get("query", ""))
    toast("Article removed.")


def remove_feed(feed: dict) -> None:
    state["feeds"] = [item for item in state["feeds"] if item["id"] != feed["id"]]
    state["articles"] = [article for article in state["articles"] if article.get("feed_id") != feed["id"]]
    save_state()
    if state["screen"] == "feed" and state.get("feed_id") == feed["id"]:
        pop_screen()
    else:
        render_current(0, state.get("query", ""))
    toast("Feed and cached articles removed.")


def remove_category(category: dict) -> None:
    if category["id"] == UNCATEGORIZED_ID:
        toast("The Uncategorized category cannot be deleted.", "info")
        return
    replacement = category.get("parent_id") or UNCATEGORIZED_ID
    for feed in state["feeds"]:
        if feed.get("category_id") == category["id"]:
            feed["category_id"] = replacement
    for article in state["articles"]:
        if article.get("category_id") == category["id"]:
            article["category_id"] = replacement
    state["categories"] = [item for item in state["categories"] if item["id"] != category["id"]]
    for child in state["categories"]:
        if child.get("parent_id") == category["id"]:
            child["parent_id"] = replacement
    save_state()
    if state["screen"] == "category" and state.get("category_id") == category["id"]:
        pop_screen()
    else:
        render_current(0, state.get("query", ""))
    toast(f"Category deleted; items moved to {category_path(replacement)}.")


def handle_frame_action(action: str) -> bool:
    if action == "frame:refresh-all":
        start_refresh()
    elif action == "frame:refresh-current":
        if state.get("feed_id"):
            start_refresh([state["feed_id"]])
        else:
            start_refresh()
    elif action == "frame:add-feed":
        begin_form("feed_form")
    elif action == "frame:new-article":
        begin_form("article_form")
    elif action == "frame:add-category":
        begin_form("category_form")
    elif action == "frame:mark-all-read":
        mark_all_read()
    elif action == "frame:import-opml":
        begin_form("import_form")
    elif action == "frame:export":
        begin_form("export_form")
    elif action == "frame:settings":
        begin_form("settings_form")
    elif action == "frame:edit-current-feed" and state.get("feed_id"):
        begin_form("feed_form", state["feed_id"])
    elif action == "frame:edit-current-category" and state.get("category_id"):
        begin_form("category_form", state["category_id"])
    else:
        return False
    return True


def handle_command_item(item_id: str) -> bool:
    if item_id in {"cmd:new-articles"}:
        navigate("articles", list_kind="unread")
    elif item_id == "cmd:read-later":
        navigate("articles", list_kind="saved")
    elif item_id == "cmd:all-articles":
        navigate("articles", list_kind="all")
    elif item_id == "cmd:feeds":
        navigate("feeds")
    elif item_id == "cmd:categories":
        navigate("categories")
    elif item_id == "cmd:import":
        begin_form("import_form")
    elif item_id == "cmd:export":
        begin_form("export_form")
    else:
        return False
    return True


def handle_detail_action(action: str) -> None:
    article = get_article(state.get("detail_article_id"))
    if article is None:
        pop_screen()
        return
    if action in {"default", "detail:open"}:
        open_article(article)
    elif action == "detail:toggle-read":
        toggle_article_read(article)
    elif action == "detail:toggle-save":
        toggle_article_saved(article)
    elif action == "detail:edit":
        begin_form("article_form", article["id"])
    elif action == "detail:copy":
        command("copy", text=article.get("url", ""))


def handle_article_action(article: dict, action: str) -> None:
    if action in {"default", "article:open"}:
        open_article(article)
    elif action == "article:detail":
        navigate("detail", detail_article_id=article["id"])
    elif action == "article:toggle-read":
        toggle_article_read(article)
    elif action == "article:toggle-save":
        toggle_article_saved(article)
    elif action == "article:edit":
        begin_form("article_form", article["id"])
    elif action == "article:copy":
        command("copy", text=article.get("url", ""))
    elif action == "article:remove":
        remove_article(article)


def handle_feed_action(feed: dict, action: str) -> None:
    if action == "default":
        navigate("feed", feed_id=feed["id"])
    elif action == "feed:refresh":
        start_refresh([feed["id"]])
    elif action == "feed:edit":
        begin_form("feed_form", feed["id"])
    elif action == "feed:copy":
        command("copy", text=feed.get("url", ""))
    elif action == "feed:remove":
        remove_feed(feed)


def handle_category_action(category: dict, action: str) -> None:
    if action == "default":
        navigate("category", category_id=category["id"])
    elif action == "category:edit":
        begin_form("category_form", category["id"])
    elif action == "category:remove":
        remove_category(category)


def handle_action(msg: dict) -> None:
    action = str(msg.get("action") or "default")
    item_id = str(msg.get("id") or "")
    if action.startswith("frame:"):
        handle_frame_action(action)
        return
    if state["screen"] == "detail":
        handle_detail_action(action)
        return
    if item_id.startswith("cmd:") and action == "default":
        handle_command_item(item_id)
        return
    article = get_article(item_id)
    if article is not None:
        handle_article_action(article, action)
        return
    feed = get_feed(item_id)
    if feed is not None:
        handle_feed_action(feed, action)
        return
    category = get_category(item_id)
    if category is not None:
        handle_category_action(category, action)
        return


# ---------------------------------------------------------------------------
# Event loop


def handle_query(text: str, rev: int) -> None:
    if state["screen"] in FORM_SCREENS or state["screen"] == "detail":
        return
    state["query"] = text or ""
    render_current(rev, state["query"])


def main() -> None:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            log("Ignoring malformed input line")
            continue
        kind = msg.get("type")
        try:
            if kind == "close":
                state["closing"] = True
                if REFRESH_THREAD is not None and REFRESH_THREAD.is_alive():
                    REFRESH_THREAD.join(timeout=1.5)
                break
            if kind == "init":
                request_state()
                handle_query(msg.get("text", msg.get("query", "")), msg.get("rev", 0))
                if state["storage_loaded"] and state["settings"].get("refresh_on_open") and state["feeds"]:
                    start_refresh()
            elif kind == "query":
                handle_query(msg.get("text", msg.get("query", "")), msg.get("rev", 0))
            elif kind == "action":
                handle_action(msg)
            elif kind == "submit":
                handle_submit(msg)
            elif kind == "loadMore":
                state["list_limit"] = state.get("list_limit", PAGE_SIZE) + PAGE_SIZE
                render_current(msg.get("rev", 0), state.get("query", ""))
            elif kind == "storage" and msg.get("requestId") == STORAGE_REQUEST_ID:
                persisted = normalize_persisted(msg.get("value"))
                state.update(persisted)
                state["storage_loaded"] = True
                render_current(0, state.get("query", ""))
                if state["settings"].get("refresh_on_open") and state["feeds"]:
                    start_refresh()
            elif kind == "back":
                pop_screen()
            elif kind == "tab":
                # Completing a feed/category title is a helpful Tab shortcut.
                item_id = str(msg.get("id") or "")
                title = None
                item = get_feed(item_id) or get_category(item_id)
                if item:
                    title = item.get("title") or item.get("name")
                article = get_article(item_id)
                if article:
                    title = article.get("title")
                if title:
                    command("setQuery", text=title)
            # select, change, toggle, and chartSelect are not needed by this UI.
        except Exception as exc:  # render a useful error instead of killing the plugin
            log("handler error", kind, repr(exc))
            send(
                {
                    "type": "render",
                    "rev": msg.get("rev", 0),
                    "view": "detail",
                    "canGoBack": True,
                    "detail": {
                        "markdown": f"# RSS plugin error\n\n`{markdown_escape(str(exc))}`\n\nThe plugin is still running; press Escape to return.",
                    },
                }
            )


if __name__ == "__main__":
    main()
