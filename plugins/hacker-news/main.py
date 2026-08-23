#!/usr/bin/env python3
"""
Hacker News plugin for Tabame.

Data sources:
  - Firebase HN API (https://hacker-news.firebaseio.com/v0) for feeds,
    items (stories/comments), and users.
  - Algolia HN Search API (https://hn.algolia.com/api/v1) for full-text
    search and per-user submission history.

Pages:
  hn:home                  dashboard  Top/New/Ask/Show panels + Saved panel
  hn:feed:<key>             list      Paginated feed, filterable by typing
  hn:search                 list      Algolia search-as-you-type, paginated
  hn:story:<id>              dashboard  Story detail + top comments panel
  hn:comments:<id>           tree      Full nested comment thread
  hn:user:<name>              detail    Karma / bio / profile link
  hn:user:<name>:subs          list      User's submissions, paginated
  hn:saved                    list      Bookmarked stories (persisted)
"""

import sys
import json
import time
import html
import re
import urllib.parse
from concurrent.futures import ThreadPoolExecutor

try:
    import requests
except ImportError:
    requests = None

FIREBASE = "https://hacker-news.firebaseio.com/v0"
ALGOLIA = "https://hn.algolia.com/api/v1"
POOL = ThreadPoolExecutor(max_workers=12)

FEEDS = {
    "top": "topstories",
    "new": "newstories",
    "best": "beststories",
    "ask": "askstories",
    "show": "showstories",
    "job": "jobstories",
}
FEED_TITLES = {
    "top": "Top Stories", "new": "New", "best": "Best",
    "ask": "Ask HN", "show": "Show HN", "job": "Jobs",
}
FEED_ICONS = {
    "top": "chart", "new": "clock", "best": "star",
    "ask": "chat", "show": "star", "job": "money",
}


# --------------------------------------------------------------------------
# stdout / stderr helpers
# --------------------------------------------------------------------------

def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# --------------------------------------------------------------------------
# HTTP + caches
# --------------------------------------------------------------------------

_item_cache = {}
_ids_cache = {}
_user_cache = {}


def fetch_json(url, timeout=10):
    r = requests.get(url, timeout=timeout, headers={"User-Agent": "tabame-hn-plugin"})
    r.raise_for_status()
    return r.json()


def get_item(item_id):
    item_id = int(item_id)
    cached = _item_cache.get(item_id)
    if cached and time.time() - cached["_ts"] < 120:
        return cached
    try:
        data = fetch_json(f"{FIREBASE}/item/{item_id}.json")
    except Exception as e:
        log("get_item error", item_id, e)
        data = None
    if data is None:
        data = {"id": item_id, "deleted": True}
    data["_ts"] = time.time()
    _item_cache[item_id] = data
    return data


def get_items(ids):
    ids = [int(i) for i in ids]
    if not ids:
        return []
    return list(POOL.map(get_item, ids))


def get_feed_ids(feed):
    cached = _ids_cache.get(feed)
    if cached and time.time() - cached[0] < 60:
        return cached[1]
    try:
        ids = fetch_json(f"{FIREBASE}/{FEEDS[feed]}.json") or []
    except Exception as e:
        log("feed error", feed, e)
        ids = _ids_cache.get(feed, (0, []))[1]
    _ids_cache[feed] = (time.time(), ids)
    return ids


def get_user(username):
    cached = _user_cache.get(username)
    if cached and time.time() - cached["_ts"] < 300:
        return cached
    try:
        data = fetch_json(f"{FIREBASE}/user/{urllib.parse.quote(username)}.json") or {}
    except Exception as e:
        log("user error", username, e)
        data = {}
    data["_ts"] = time.time()
    _user_cache[username] = data
    return data


def algolia_search(query, page=0, by_date=False, tags=None):
    params = {"query": query, "page": page, "hitsPerPage": 20}
    if tags:
        params["tags"] = tags
    endpoint = "search_by_date" if by_date else "search"
    try:
        return fetch_json(f"{ALGOLIA}/{endpoint}?{urllib.parse.urlencode(params)}")
    except Exception as e:
        log("search error", e)
        return {"hits": [], "nbPages": 0}


def algolia_hit_to_item(h):
    return {
        "id": int(h.get("objectID")),
        "title": h.get("title") or h.get("story_title") or "(untitled)",
        "url": h.get("url") or h.get("story_url"),
        "by": h.get("author", "unknown"),
        "score": h.get("points") or 0,
        "descendants": h.get("num_comments") or 0,
        "time": h.get("created_at_i"),
        "type": "story",
    }


def invalidate_caches():
    _item_cache.clear()
    _ids_cache.clear()
    _user_cache.clear()


# --------------------------------------------------------------------------
# formatting helpers
# --------------------------------------------------------------------------

def time_ago(unix_ts):
    if not unix_ts:
        return ""
    delta = time.time() - unix_ts
    if delta < 0:
        delta = 0
    if delta < 60:
        return "just now"
    mins = int(delta // 60)
    if mins < 60:
        return f"{mins}m ago"
    hours = int(mins // 60)
    if hours < 24:
        return f"{hours}h ago"
    days = int(hours // 24)
    if days < 30:
        return f"{days}d ago"
    months = int(days // 30)
    if months < 12:
        return f"{months}mo ago"
    years = int(months // 12)
    return f"{years}y ago"


def domain_of(url):
    try:
        return urllib.parse.urlparse(url).netloc.replace("www.", "")
    except Exception:
        return ""


def favicon_icon(url):
    d = domain_of(url)
    if not d:
        return "message"
    return f"https://www.google.com/s2/favicons?domain={d}&sz=64"


def html_to_md(text):
    if not text:
        return ""
    t = text
    t = re.sub(r"<p>", "\n\n", t)
    t = re.sub(r'<a href="([^"]+)"[^>]*>(.*?)</a>', r"[\2](\1)", t, flags=re.S)
    t = re.sub(r"<i>(.*?)</i>", r"*\1*", t, flags=re.S)
    t = re.sub(r"<b>(.*?)</b>", r"**\1**", t, flags=re.S)
    t = re.sub(r"<pre><code>(.*?)</code></pre>", r"```\n\1\n```", t, flags=re.S)
    t = re.sub(r"<code>(.*?)</code>", r"`\1`", t, flags=re.S)
    t = re.sub(r"<[^>]+>", "", t)
    t = html.unescape(t)
    return t.strip()


def snippet_of(text, length=140):
    t = text.replace("\n", " ").strip()
    if len(t) > length:
        return t[:length].rstrip() + "…"
    return t


# --------------------------------------------------------------------------
# plugin state
# --------------------------------------------------------------------------

state = {
    "page_id": "hn:home",
    "feed": "top",
    "feed_page_size": 20,
    "saved": {},
    "saved_loaded": False,
    "saved_requested": False,
    "story_id": None,
    "comments_root": None,
    "comments_state": {},
    "comments_order": [],
    "search_query": "",
    "search_page": 0,
    "search_hits": [],
    "search_nb_pages": 0,
    "user_id": None,
    "user_subs_user": None,
    "user_subs_page": 0,
    "user_subs_items": [],
    "user_subs_nb_pages": 0,
}


def ensure_saved_loaded():
    if not state["saved_requested"]:
        state["saved_requested"] = True
        send({"type": "command", "command": "storage", "op": "get",
              "key": "saved", "requestId": "load_saved"})


def persist_saved():
    send({"type": "command", "command": "storage", "op": "set",
          "key": "saved", "value": json.dumps(state["saved"])})


def toggle_save(item_id, it_hint=None):
    sid = str(int(item_id))
    if sid in state["saved"]:
        del state["saved"][sid]
        is_saved_now = False
    else:
        it = it_hint or get_item(item_id)
        entry = {k: it.get(k) for k in ("id", "title", "url", "by", "score", "descendants", "time", "type")}
        entry["_saved_at"] = time.time()
        state["saved"][sid] = entry
        is_saved_now = True
    persist_saved()
    return is_saved_now


# --------------------------------------------------------------------------
# shared item -> row builders
# --------------------------------------------------------------------------

def story_item(it, saved_ids):
    if not it or it.get("deleted") or it.get("dead"):
        return None
    iid = str(it["id"])
    title = it.get("title") or "(untitled)"
    url = it.get("url")
    by = it.get("by", "unknown")
    score = it.get("score", 0) or 0
    n_comments = it.get("descendants", 0) or 0
    typ = it.get("type", "story")
    dom = domain_of(url) if url else None

    parts = []
    if dom:
        parts.append(dom)
    parts.append(f"by {by}")
    ago = time_ago(it.get("time"))
    if ago:
        parts.append(ago)
    subtitle = "  ·  ".join(parts)

    if url:
        icon = favicon_icon(url)
    elif typ == "job":
        icon = "money"
    elif "Ask HN" in title or typ == "ask":
        icon = "chat"
    elif "Show HN" in title:
        icon = "star"
    else:
        icon = "message"

    is_saved = iid in saved_ids
    actions = []
    if url:
        actions.append({"id": "open", "title": "Open link", "icon": "open"})
    actions.append({"id": "discuss", "title": f"View discussion ({n_comments})", "icon": "chat"})
    actions.append({"id": "copy_link", "title": "Copy link", "icon": "copy"})
    actions.append({"id": "copy_hn", "title": "Copy HN link", "icon": "link"})
    actions.append({"id": "user", "title": f"View {by}", "icon": "person"})
    if is_saved:
        actions.append({"id": "unsave", "title": "Remove from saved", "icon": "trash"})
    else:
        actions.append({"id": "save", "title": "Save story", "icon": "bookmark"})

    return {
        "id": iid,
        "title": f"{'★ ' if is_saved else ''}{title}",
        "subtitle": subtitle,
        "icon": icon,
        "accessories": [
            {"text": str(score), "icon": "bolt"},
            {"text": str(n_comments), "icon": "chat"},
        ],
        "actions": actions,
        "preview": {
            "markdown": build_story_markdown(it),
            "metadata": story_metadata(it),
        },
    }


def build_story_markdown(it):
    title = it.get("title", "(untitled)")
    url = it.get("url")
    lines = [f"# {title}"]
    if url:
        lines.append(f"\n{url}\n")
    text = it.get("text")
    if text:
        lines.append("\n" + html_to_md(text))
    if not url and not text:
        lines.append("\n_No link or text — see the discussion for context._")
    return "\n".join(lines)


def story_metadata(it):
    md = [
        {"label": "Score", "text": str(it.get("score", 0) or 0), "icon": "bolt"},
        {"label": "Comments", "text": str(it.get("descendants", 0) or 0), "icon": "chat"},
        {"label": "By", "text": it.get("by", "unknown"), "icon": "person"},
        {"label": "Posted", "text": time_ago(it.get("time")) or "unknown", "icon": "clock"},
    ]
    if it.get("url"):
        md.append({"label": "Link", "text": domain_of(it["url"]), "url": it["url"]})
    return md


def comment_preview_item(c):
    by = c.get("by", "unknown")
    text = html_to_md(c.get("text", ""))
    n_kids = len(c.get("kids", []) or [])
    return {
        "id": str(c["id"]),
        "title": f"**{by}**  ·  {time_ago(c.get('time'))}",
        "subtitle": snippet_of(text) if text else "_(no text)_",
        "icon": "person",
        "lines": 2,
        "accessories": [{"text": f"{n_kids} replies"}] if n_kids else [],
        "actions": [
            {"id": "view_user", "title": f"View {by}", "icon": "person"},
            {"id": "copy_text", "title": "Copy comment text", "icon": "copy"},
        ],
        "preview": {"markdown": f"**{by}**  ·  {time_ago(c.get('time'))}\n\n{text or '_(no text)_'}"},
    }


# --------------------------------------------------------------------------
# HOME
# --------------------------------------------------------------------------

def home_actions():
    actions = [{"id": f"feed_{k}", "title": f"Browse: {FEED_TITLES[k]}", "icon": FEED_ICONS[k]}
               for k in ("top", "new", "best", "ask", "show", "job")]
    actions.append({"id": "saved", "title": "Saved stories", "icon": "bookmark", "shortcut": "ctrl+s"})
    actions.append({
        "id": "lookup_user", "title": "Look up user…", "icon": "person",
        "parameters": [{"id": "username", "type": "text", "label": "Username", "required": True}],
    })
    actions.append({"id": "refresh", "title": "Refresh", "icon": "refresh", "shortcut": "ctrl+r"})
    return actions


def render_home(rev, history="replace"):
    state["page_id"] = "hn:home"
    saved_ids = set(state["saved"].keys())

    def panel(pid, feed_key, items, height, title=None):
        rows = [r for r in (story_item(it, saved_ids) for it in items) if r]
        return {
            "id": pid, "title": title or FEED_TITLES[feed_key], "height": height, "view": "list",
            "emptyText": "Nothing here right now", "items": rows,
        }

    top_items = [x for x in get_items(get_feed_ids("top")[:6])]
    new_items = [x for x in get_items(get_feed_ids("new")[:5])]
    ask_items = [x for x in get_items(get_feed_ids("ask")[:5])]
    show_items = [x for x in get_items(get_feed_ids("show")[:5])]

    panels = [
        panel("top", "top", top_items, 340),
        panel("new", "new", new_items, 260),
        panel("ask", "ask", ask_items, 220),
        panel("show", "show", show_items, 220),
    ]
    if state["saved_loaded"] and state["saved"]:
        saved_items = sorted(state["saved"].values(), key=lambda x: x.get("_saved_at", 0), reverse=True)[:5]
        panels.append(panel("saved", "top", saved_items, 220, title="Saved"))

    send({
        "type": "render", "rev": rev, "view": "dashboard",
        "page": {"id": "hn:home", "title": "Hacker News", "history": history},
        "placeholder": "Search Hacker News…",
        "dashboard": {"layout": "stack", "panels": panels},
        "actions": home_actions(),
        "floatingAction": {"id": "refresh", "title": "Refresh", "icon": "refresh"},
    })


# --------------------------------------------------------------------------
# FEED
# --------------------------------------------------------------------------

def render_feed(rev, feed, history="replace", filter_text=None):
    changed_feed = state["feed"] != feed
    state["feed"] = feed
    state["page_id"] = f"hn:feed:{feed}"
    if changed_feed:
        state["feed_page_size"] = 20

    all_ids = get_feed_ids(feed)
    page_size = state["feed_page_size"]
    fetch_n = 60 if filter_text else page_size
    ids_to_fetch = all_ids[:fetch_n]
    items = [x for x in get_items(ids_to_fetch)]
    saved_ids = set(state["saved"].keys())

    if filter_text:
        ft = filter_text.lower()
        items = [it for it in items if ft in (it.get("title") or "").lower()]
        has_more = False
    else:
        has_more = page_size < len(all_ids)

    rows = [r for r in (story_item(it, saved_ids) for it in items) if r]

    send({
        "type": "render", "rev": rev, "view": "list",
        "page": {
            "id": f"hn:feed:{feed}", "title": FEED_TITLES[feed], "history": history,
            "breadcrumbs": [{"id": "hn:home", "label": "Hacker News"}],
        },
        "placeholder": f"Filter {FEED_TITLES[feed]}…",
        "preview": {"enabled": True},
        "hasMore": has_more,
        "emptyText": "No stories match" if filter_text else "No stories",
        "items": rows,
        "actions": [{"id": "refresh", "title": "Refresh", "icon": "refresh", "shortcut": "ctrl+r"}],
        "floatingAction": {"id": "refresh", "title": "Refresh", "icon": "refresh"},
    })


# --------------------------------------------------------------------------
# SEARCH (Algolia)
# --------------------------------------------------------------------------

def do_search(rev, query, history="replace", more=False):
    state["page_id"] = "hn:search"
    if state["search_query"] != query:
        state["search_query"] = query
        state["search_page"] = 0
        state["search_hits"] = []
    elif more:
        state["search_page"] += 1
    else:
        # same query, no pagination requested — nothing new to fetch
        pass

    if not state["search_hits"] or more or state["search_query"] != state.get("_last_fetched_query"):
        data = algolia_search(query, page=state["search_page"], tags="story")
        hits = data.get("hits", [])
        state["search_nb_pages"] = data.get("nbPages", 0)
        if more:
            state["search_hits"].extend(algolia_hit_to_item(h) for h in hits)
        else:
            state["search_hits"] = [algolia_hit_to_item(h) for h in hits]
        state["_last_fetched_query"] = query

    saved_ids = set(state["saved"].keys())
    rows = [r for r in (story_item(it, saved_ids) for it in state["search_hits"]) if r]
    has_more = state["search_page"] + 1 < state["search_nb_pages"]

    send({
        "type": "render", "rev": rev, "view": "list",
        "page": {
            "id": "hn:search", "title": f'Search: "{query}"', "history": history,
            "breadcrumbs": [{"id": "hn:home", "label": "Hacker News"}],
        },
        "placeholder": "Search Hacker News…",
        "preview": {"enabled": True},
        "hasMore": has_more,
        "emptyText": f'No results for "{query}"' if query else "Type to search",
        "items": rows,
    })


# --------------------------------------------------------------------------
# STORY (dashboard: detail + top comments)
# --------------------------------------------------------------------------

def render_story(rev, story_id, history="push"):
    story_id = int(story_id)
    state["page_id"] = f"hn:story:{story_id}"
    state["story_id"] = story_id
    it = get_item(story_id)

    if not it or it.get("deleted") or it.get("dead"):
        send({
            "type": "render", "rev": rev, "view": "detail",
            "page": {
                "id": f"hn:story:{story_id}", "title": "Story", "history": history,
                "breadcrumbs": [{"id": "hn:home", "label": "Hacker News"}],
            },
            "canGoBack": True,
            "detail": {"markdown": "# Not found\n\nThis item was deleted, flagged, or is unavailable."},
        })
        return

    saved_ids = set(state["saved"].keys())
    is_saved = str(story_id) in saved_ids
    kids = (it.get("kids") or [])[:8]
    top_comments = [c for c in get_items(kids) if c and not c.get("deleted") and not c.get("dead")]
    comment_rows = [comment_preview_item(c) for c in top_comments]

    panels = [
        {
            "id": "info", "title": it.get("title", "Story")[:60], "height": 260, "view": "detail",
            "detail": {"markdown": build_story_markdown(it), "metadata": story_metadata(it)},
        },
        {
            "id": "comments", "title": f'Top comments ({it.get("descendants", 0) or 0})',
            "height": 320, "view": "list",
            "emptyText": "No comments yet", "items": comment_rows,
        },
    ]

    actions = []
    if it.get("url"):
        actions.append({"id": "open_url", "title": "Open link", "icon": "open"})
    actions.append({"id": "open_comments", "title": "View all comments", "icon": "chat"})
    actions.append({"id": "copy_link", "title": "Copy link", "icon": "copy"})
    actions.append({"id": "open_user", "title": f'View {it.get("by", "?")}', "icon": "person"})
    actions.append({"id": "unsave" if is_saved else "save",
                     "title": "Remove from saved" if is_saved else "Save story",
                     "icon": "trash" if is_saved else "bookmark"})
    actions.append({"id": "refresh", "title": "Refresh", "icon": "refresh", "shortcut": "ctrl+r"})

    send({
        "type": "render", "rev": rev, "view": "dashboard",
        "page": {
            "id": f"hn:story:{story_id}", "title": it.get("title", "Story")[:60], "history": history,
            "breadcrumbs": [{"id": "hn:home", "label": "Hacker News"}],
        },
        "placeholder": "Press Esc to go back",
        "dashboard": {"layout": "stack", "panels": panels},
        "actions": actions,
        "floatingAction": {"id": "open_comments",
                            "title": f'{it.get("descendants", 0) or 0} Comments', "icon": "chat"},
    })


# --------------------------------------------------------------------------
# COMMENTS (tree, lazy expand)
# --------------------------------------------------------------------------

def init_comment_tree(story_id, story):
    state["comments_state"] = {}
    top_ids = story.get("kids") or []
    top_items = get_items(top_ids)
    order = []
    for c in top_items:
        if not c:
            continue
        cid = str(c["id"])
        state["comments_state"][cid] = {
            "item": c, "expanded": False,
            "children_ids": c.get("kids") or [], "loaded_children": None, "depth": 0,
        }
        order.append(cid)
    state["comments_order"] = order


def toggle_node(cid, requested=None):
    node = state["comments_state"].get(cid)
    if not node:
        return
    want = requested if requested is not None else (not node["expanded"])
    node["expanded"] = want
    if want and node["loaded_children"] is None:
        kid_items = get_items(node["children_ids"])
        loaded = []
        for k in kid_items:
            if not k:
                continue
            kcid = str(k["id"])
            loaded.append(kcid)
            if kcid not in state["comments_state"]:
                state["comments_state"][kcid] = {
                    "item": k, "expanded": False,
                    "children_ids": k.get("kids") or [], "loaded_children": None,
                    "depth": node["depth"] + 1,
                }
        node["loaded_children"] = loaded


def build_comment_rows():
    rows = []

    def walk(cid, depth):
        node = state["comments_state"].get(cid)
        if not node:
            return
        c = node["item"]
        n_kids = len(node["children_ids"] or [])
        if c.get("deleted") or c.get("dead"):
            title = "_[deleted]_"
            subtitle = ""
        else:
            title = f'**{c.get("by", "unknown")}**  ·  {time_ago(c.get("time"))}'
            subtitle = snippet_of(html_to_md(c.get("text", "")), 180) or "_(no text)_"
        accessories = []
        if n_kids:
            accessories.append({"text": f"{n_kids}"})
        rows.append({
            "id": cid, "title": title, "subtitle": subtitle, "icon": "person",
            "lines": 3, "depth": depth, "expanded": node["expanded"],
            "accessories": accessories,
            "actions": [
                {"id": "view_user", "title": f'View {c.get("by", "?")}', "icon": "person"},
                {"id": "copy_text", "title": "Copy comment text", "icon": "copy"},
                {"id": "open_hn", "title": "Open on Hacker News", "icon": "open"},
            ],
        })
        if node["expanded"]:
            for kid_id in (node["loaded_children"] or []):
                walk(kid_id, depth + 1)

    for cid in state["comments_order"]:
        walk(cid, 0)
    return rows


def render_comments(rev, story_id, history="push"):
    story_id = int(story_id)
    state["page_id"] = f"hn:comments:{story_id}"
    state["comments_root"] = story_id
    story = get_item(story_id)

    if state.get("comments_loaded_for") != story_id:
        init_comment_tree(story_id, story)
        state["comments_loaded_for"] = story_id

    rows = build_comment_rows()
    send({
        "type": "render", "rev": rev, "view": "tree",
        "page": {
            "id": f"hn:comments:{story_id}", "title": f'Comments: {story.get("title", "")[:40]}',
            "history": history,
            "breadcrumbs": [
                {"id": "hn:home", "label": "Hacker News"},
                {"id": f"hn:story:{story_id}", "label": story.get("title", "Story")[:30]},
            ],
        },
        "placeholder": "Press Esc to go back",
        "emptyText": "No comments yet",
        "items": rows,
        "actions": [
            {"id": "expand_all", "title": "Expand all (top level)", "icon": "add"},
            {"id": "refresh", "title": "Refresh thread", "icon": "refresh", "shortcut": "ctrl+r"},
        ],
    })


def rerender_comments_partial():
    rows = build_comment_rows()
    send({"type": "render", "rev": 0, "view": "tree", "items": rows})


# --------------------------------------------------------------------------
# USER
# --------------------------------------------------------------------------

def render_user(rev, username, history="push"):
    state["page_id"] = f"hn:user:{username}"
    state["user_id"] = username
    u = get_user(username)

    if not u or not u.get("id"):
        send({
            "type": "render", "rev": rev, "view": "detail",
            "page": {
                "id": f"hn:user:{username}", "title": username, "history": history,
                "breadcrumbs": [{"id": "hn:home", "label": "Hacker News"}],
            },
            "canGoBack": True,
            "detail": {"markdown": f"# {username}\n\nUser not found."},
        })
        return

    about = html_to_md(u.get("about", "")) or "_No bio._"
    created = u.get("created")
    md = f"# {username}\n\n{about}"
    metadata = [
        {"label": "Karma", "text": str(u.get("karma", 0) or 0), "icon": "bolt"},
        {"label": "Member since", "text": time_ago(created) or "unknown", "icon": "calendar"},
        {"label": "Profile", "text": "news.ycombinator.com",
         "url": f"https://news.ycombinator.com/user?id={username}"},
    ]

    send({
        "type": "render", "rev": rev, "view": "detail",
        "page": {
            "id": f"hn:user:{username}", "title": username, "history": history,
            "breadcrumbs": [{"id": "hn:home", "label": "Hacker News"}],
        },
        "placeholder": "Press Esc to go back",
        "detail": {"markdown": md, "metadata": metadata},
        "actions": [
            {"id": "open_profile", "title": "Open on Hacker News", "icon": "open"},
            {"id": "view_submissions", "title": "View recent submissions", "icon": "list"},
        ],
        "canGoBack": True,
    })


def fetch_user_submissions_page(username, page):
    data = algolia_search("", page=page, by_date=True, tags=f"author_{username},story")
    hits = data.get("hits", [])
    return [algolia_hit_to_item(h) for h in hits], data.get("nbPages", 0)


def render_user_submissions(rev, username, history="push", more=False):
    pid = f"hn:user:{username}:subs"
    state["page_id"] = pid
    is_new = state["user_subs_user"] != username
    if is_new:
        state["user_subs_user"] = username
        items0, nb = fetch_user_submissions_page(username, 0)
        state["user_subs_page"] = 0
        state["user_subs_items"] = items0
        state["user_subs_nb_pages"] = nb
    elif more:
        state["user_subs_page"] += 1
        items_n, nb = fetch_user_submissions_page(username, state["user_subs_page"])
        state["user_subs_items"].extend(items_n)
        state["user_subs_nb_pages"] = nb

    saved_ids = set(state["saved"].keys())
    rows = [r for r in (story_item(it, saved_ids) for it in state["user_subs_items"]) if r]
    has_more = state["user_subs_page"] + 1 < state["user_subs_nb_pages"]

    send({
        "type": "render", "rev": rev, "view": "list",
        "page": {
            "id": pid, "title": f"{username}'s submissions", "history": history,
            "breadcrumbs": [
                {"id": "hn:home", "label": "Hacker News"},
                {"id": f"hn:user:{username}", "label": username},
            ],
        },
        "preview": {"enabled": True},
        "hasMore": has_more,
        "emptyText": "No submissions found",
        "items": rows,
    })


# --------------------------------------------------------------------------
# SAVED
# --------------------------------------------------------------------------

def render_saved(rev, history="push", filter_text=None):
    state["page_id"] = "hn:saved"
    items = list(state["saved"].values())
    items.sort(key=lambda it: it.get("_saved_at", 0), reverse=True)
    if filter_text:
        ft = filter_text.lower()
        items = [it for it in items if ft in (it.get("title") or "").lower()]
    saved_ids = set(state["saved"].keys())
    rows = [r for r in (story_item(it, saved_ids) for it in items) if r]

    send({
        "type": "render", "rev": rev, "view": "list",
        "page": {
            "id": "hn:saved", "title": "Saved Stories", "history": history,
            "breadcrumbs": [{"id": "hn:home", "label": "Hacker News"}],
        },
        "placeholder": "Filter saved stories…",
        "preview": {"enabled": True},
        "empty": {"icon": "bookmark", "title": "No saved stories",
                   "hint": "Save any story with the bookmark action (Ctrl+K → Save story)"},
        "items": rows,
        "actions": [{"id": "refresh", "title": "Refresh", "icon": "refresh"}],
    })


# --------------------------------------------------------------------------
# routing helpers
# --------------------------------------------------------------------------

def is_story_listing_page(pid):
    return (pid == "hn:home" or pid.startswith("hn:feed:") or pid in ("hn:search", "hn:saved")
            or pid.endswith(":subs"))


def refresh_current_page():
    pid = state["page_id"]
    if pid == "hn:home":
        render_home(0, history="none")
    elif pid.startswith("hn:feed:"):
        render_feed(0, state["feed"], history="none")
    elif pid == "hn:search":
        do_search(0, state["search_query"], history="none")
    elif pid == "hn:saved":
        render_saved(0, history="none")
    elif pid.startswith("hn:story:"):
        render_story(0, state["story_id"], history="none")
    elif pid.startswith("hn:comments:"):
        render_comments(0, state["comments_root"], history="none")
    elif pid.endswith(":subs"):
        render_user_submissions(0, state["user_subs_user"], history="none")
    elif pid.startswith("hn:user:"):
        render_user(0, state["user_id"], history="none")


def go(page_id):
    if not page_id or page_id == "hn:home":
        render_home(0, history="none")
        return
    parts = page_id.split(":")
    if page_id.startswith("hn:feed:"):
        render_feed(0, parts[2], history="none")
    elif page_id == "hn:search":
        do_search(0, state["search_query"], history="none")
    elif page_id == "hn:saved":
        render_saved(0, history="none")
    elif page_id.startswith("hn:story:"):
        render_story(0, int(parts[2]), history="none")
    elif page_id.startswith("hn:comments:"):
        render_comments(0, int(parts[2]), history="none")
    elif page_id.startswith("hn:user:") and page_id.endswith(":subs"):
        render_user_submissions(0, parts[2], history="none")
    elif page_id.startswith("hn:user:"):
        render_user(0, parts[2], history="none")
    else:
        render_home(0, history="none")


# --------------------------------------------------------------------------
# event handlers
# --------------------------------------------------------------------------

def handle_query(msg):
    rev = msg.get("rev", 0)
    text = msg.get("text")
    if text is None:
        text = msg.get("query", "")
    text = (text or "").strip()
    ensure_saved_loaded()
    pid = state["page_id"]

    if pid == "hn:home":
        if text:
            do_search(rev, text, history="push")
        else:
            render_home(rev, history="none")
    elif pid == "hn:search":
        if text:
            do_search(rev, text, history="none")
        else:
            render_home(rev, history="none")
    elif pid.startswith("hn:feed:"):
        feed = pid.split(":")[2]
        render_feed(rev, feed, history="none", filter_text=text or None)
    elif pid == "hn:saved":
        render_saved(rev, history="none", filter_text=text or None)
    elif pid.startswith("hn:story:"):
        send_current_frame_rev_only(rev, lambda: render_story(rev, state["story_id"], history="none"))
    elif pid.startswith("hn:comments:"):
        send_current_frame_rev_only(rev, lambda: render_comments(rev, state["comments_root"], history="none"))
    elif pid.endswith(":subs"):
        render_user_submissions(rev, state["user_subs_user"], history="none")
    elif pid.startswith("hn:user:"):
        render_user(rev, state["user_id"], history="none")
    else:
        render_home(rev, history="none")


def send_current_frame_rev_only(rev, render_fn):
    # Typing has no effect on these pages; just re-answer with the same
    # content so the query's rev is satisfied.
    render_fn()


def handle_action(msg):
    item_id = msg.get("id", "")
    action = msg.get("action", "default")
    params = msg.get("parameters") or {}
    pid = state["page_id"]

    if item_id == "":
        handle_frame_action(pid, action, params)
        return

    if is_story_listing_page(pid):
        handle_story_row_action(item_id, action)
    elif pid.startswith("hn:story:"):
        handle_comment_row_action(item_id, action)
    elif pid.startswith("hn:comments:"):
        handle_comment_row_action(item_id, action)


def handle_story_row_action(item_id, action):
    it = get_item(item_id)
    if action in ("default", "open"):
        if it.get("url"):
            send({"type": "command", "command": "open", "url": it["url"]})
        else:
            render_story(0, int(item_id), history="push")
        return
    if action == "discuss":
        render_story(0, int(item_id), history="push")
        return
    if action == "copy_link":
        url = it.get("url") or f"https://news.ycombinator.com/item?id={item_id}"
        send({"type": "command", "command": "copy", "text": url})
        send({"type": "command", "command": "toast", "text": "Link copied"})
        return
    if action == "copy_hn":
        send({"type": "command", "command": "copy",
              "text": f"https://news.ycombinator.com/item?id={item_id}"})
        send({"type": "command", "command": "toast", "text": "HN link copied"})
        return
    if action == "user":
        render_user(0, it.get("by", "unknown"), history="push")
        return
    if action in ("save", "unsave"):
        toggle_save(item_id, it)
        refresh_current_page()
        return


def handle_comment_row_action(item_id, action):
    # Used both for the story page's "Top comments" preview panel and
    # for full tree rows on the comments page.
    on_tree_page = state["page_id"].startswith("hn:comments:")
    node = state["comments_state"].get(item_id) if on_tree_page else None
    c = node["item"] if node else get_item(item_id)

    if action == "default":
        if on_tree_page:
            toggle_node(item_id)
            rerender_comments_partial()
        else:
            render_comments(0, state["story_id"], history="push")
        return
    if action == "open_thread":
        render_comments(0, state["story_id"], history="push")
        return
    if action == "view_user":
        render_user(0, c.get("by", "unknown"), history="push")
        return
    if action == "copy_text":
        send({"type": "command", "command": "copy", "text": html_to_md(c.get("text", ""))})
        send({"type": "command", "command": "toast", "text": "Comment copied"})
        return
    if action == "open_hn":
        send({"type": "command", "command": "open",
              "url": f"https://news.ycombinator.com/item?id={item_id}"})
        return


def handle_frame_action(pid, action, params):
    if action == "refresh":
        invalidate_caches()
        if pid.startswith("hn:comments:"):
            state["comments_loaded_for"] = None
        if pid.startswith("hn:user:") and pid.endswith(":subs"):
            state["user_subs_user"] = None
        refresh_current_page()
        return

    if pid == "hn:home":
        if action.startswith("feed_"):
            render_feed(0, action.split("_", 1)[1], history="push")
            return
        if action == "saved":
            render_saved(0, history="push")
            return
        if action == "lookup_user":
            uname = (params.get("username") or "").strip()
            if uname:
                render_user(0, uname, history="push")
            return

    if pid.startswith("hn:story:"):
        story_id = state["story_id"]
        it = get_item(story_id)
        if action == "open_url" and it.get("url"):
            send({"type": "command", "command": "open", "url": it["url"]})
            return
        if action == "open_comments":
            render_comments(0, story_id, history="push")
            return
        if action == "copy_link":
            url = it.get("url") or f"https://news.ycombinator.com/item?id={story_id}"
            send({"type": "command", "command": "copy", "text": url})
            send({"type": "command", "command": "toast", "text": "Link copied"})
            return
        if action == "open_user":
            render_user(0, it.get("by", "unknown"), history="push")
            return
        if action in ("save", "unsave"):
            toggle_save(story_id, it)
            render_story(0, story_id, history="none")
            return

    if pid.startswith("hn:comments:"):
        if action == "expand_all":
            for cid in list(state["comments_order"]):
                toggle_node(cid, requested=True)
            rerender_comments_partial()
            return

    if pid.startswith("hn:user:") and pid.endswith(":subs"):
        pass  # only refresh handled above

    elif pid.startswith("hn:user:"):
        username = state["user_id"]
        if action == "open_profile":
            send({"type": "command", "command": "open",
                  "url": f"https://news.ycombinator.com/user?id={username}"})
            return
        if action == "view_submissions":
            render_user_submissions(0, username, history="push")
            return


def handle_toggle(msg):
    cid = str(msg.get("id"))
    toggle_node(cid, requested=msg.get("expanded"))
    rerender_comments_partial()


def handle_load_more(msg):
    rev = msg.get("rev", 0)
    pid = state["page_id"]
    if pid.startswith("hn:feed:"):
        state["feed_page_size"] += 20
        render_feed(rev, state["feed"], history="none")
    elif pid == "hn:search":
        do_search(rev, state["search_query"], history="none", more=True)
    elif pid.endswith(":subs"):
        render_user_submissions(rev, state["user_subs_user"], history="none", more=True)


def handle_back(msg):
    go(msg.get("toPageId"))


def handle_navigate(msg):
    go(msg.get("targetPageId", "hn:home"))


def handle_storage(msg):
    if msg.get("requestId") == "load_saved":
        raw = msg.get("value")
        try:
            state["saved"] = json.loads(raw) if raw else {}
        except Exception:
            state["saved"] = {}
        state["saved_loaded"] = True
        refresh_current_page()


# --------------------------------------------------------------------------
# main loop
# --------------------------------------------------------------------------

def dispatch(msg):
    t = msg.get("type")
    if t == "close":
        sys.exit(0)
    elif t in ("init", "query"):
        handle_query(msg)
    elif t == "action":
        handle_action(msg)
    elif t == "back":
        handle_back(msg)
    elif t == "navigate":
        handle_navigate(msg)
    elif t == "loadMore":
        handle_load_more(msg)
    elif t == "toggle":
        handle_toggle(msg)
    elif t == "storage":
        handle_storage(msg)
    # "select" and "tab" are not used by this plugin.


def main():
    if requests is None:
        send({"type": "render", "rev": 0, "view": "detail",
              "detail": {"markdown": "# Missing dependency\n\nThe `requests` package failed to install."}})

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        try:
            dispatch(msg)
        except SystemExit:
            raise
        except Exception as e:
            log("dispatch error:", msg.get("type"), e)
            rev = msg.get("rev", 0)
            send({"type": "render", "rev": rev, "view": "detail",
                  "canGoBack": True,
                  "detail": {"markdown": f"# Something went wrong\n\n```\n{e}\n```"}})


if __name__ == "__main__":
    main()
