#!/usr/bin/env python3
"""
TV Shows Tracker — a Tabame launcher plugin.

Keyword: shows

  shows              -> list of tracked shows (type to filter locally),
                        plus a "Calendar" entry that renders a poster
                        calendar image of upcoming/recent episodes.
  Ctrl+K / Ctrl+N     -> "Add show from TMDB" -> search -> preview -> add
  Enter on a show     -> season overview + episode calendar + ratings sparkline

No config file needed up front — if no TMDB API key is set yet, the plugin
shows a form to paste one in and saves it to config.json for you.
"""

import calendar as cal_mod
import json
import os
import pathlib
import sys
from datetime import date, timedelta

import requests
from PIL import Image, ImageDraw, ImageFont

TMDB_BASE = "https://api.themoviedb.org/3"
IMG_ROW = "https://image.tmdb.org/t/p/w185"
IMG_PREVIEW = "https://image.tmdb.org/t/p/w342"
IMG_STILL = "https://image.tmdb.org/t/p/w300"
IMG_POSTER_SMALL = "https://image.tmdb.org/t/p/w154"

CONFIG_PATH = "config.json"
DATA_PATH = "data.json"
POSTER_CACHE_DIR = "posters_cache"
CALENDAR_OUT = "calendar.png"


# ---------------------------------------------------------------- protocol --


def send(frame):
    sys.stdout.write(json.dumps(frame) + "\n")
    sys.stdout.flush()


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# -------------------------------------------------------------- persistence --


def load_json(path, default):
    if not os.path.exists(path):
        return default
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        log("failed to read", path, e)
        return default


def load_config():
    return load_json(CONFIG_PATH, {})


def save_config(cfg):
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)


def load_data():
    return load_json(DATA_PATH, {"shows": {}})


def save_data(data):
    try:
        with open(DATA_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        log("failed to write data.json", e)


def get_api_key():
    return (load_config() or {}).get("tmdb_api_key")


def get_omdb_key():
    return (load_config() or {}).get("omdb_api_key")


# --------------------------------------------------------------------- OMDb --


def omdb_get(params):
    key = get_omdb_key()
    if not key:
        return None, "missing_key"
    p = dict(params)
    p["apikey"] = key
    try:
        r = requests.get("https://www.omdbapi.com/", params=p, timeout=10)
        if not r.ok:
            return None, f"http_{r.status_code}"
        data = r.json()
        if str(data.get("Response", "")).lower() == "false":
            return None, data.get("Error", "not_found")
        return data, None
    except requests.RequestException as e:
        log("omdb request failed", e)
        return None, "network"


def fetch_external_ratings(imdb_id):
    """Show-level ratings from OMDb: IMDb, Rotten Tomatoes, Metacritic."""
    if not imdb_id or not get_omdb_key():
        return {}
    data, err = omdb_get({"i": imdb_id})
    if err or not data:
        return {}
    out = {}
    if data.get("imdbRating") and data["imdbRating"] != "N/A":
        out["imdb"] = data["imdbRating"]
    for src in data.get("Ratings", []) or []:
        name = (src.get("Source") or "").lower()
        if "rotten" in name:
            out["rotten_tomatoes"] = src.get("Value")
        elif "metacritic" in name:
            out["metacritic"] = src.get("Value")
    return out


def fetch_episode_imdb_ratings(imdb_id, season_num):
    """{episode_number: imdb_rating_str} for one season, via a single OMDb call."""
    if not imdb_id or not get_omdb_key():
        return {}
    data, err = omdb_get({"i": imdb_id, "Season": season_num})
    if err or not data:
        return {}
    out = {}
    for ep in data.get("Episodes", []) or []:
        try:
            num = int(ep.get("Episode"))
        except (TypeError, ValueError):
            continue
        r = ep.get("imdbRating")
        if r and r != "N/A":
            out[num] = r
    return out


# --------------------------------------------------------------------- TMDB --


def tmdb_get(path, params=None):
    key = get_api_key()
    if not key:
        return None, "missing_key"
    p = dict(params or {})
    p["api_key"] = key
    try:
        r = requests.get(f"{TMDB_BASE}{path}", params=p, timeout=10)
        if r.status_code == 401:
            return None, "bad_key"
        if not r.ok:
            return None, f"http_{r.status_code}"
        return r.json(), None
    except requests.RequestException as e:
        log("tmdb request failed", path, e)
        return None, "network"


def search_shows(query):
    data, err = tmdb_get("/search/tv", {"query": query, "include_adult": "false"})
    if err:
        return [], err
    return data.get("results", []), None


def current_season_number(details):
    nxt = details.get("next_episode_to_air")
    if nxt:
        return nxt.get("season_number", 1)
    last = details.get("last_episode_to_air")
    if last:
        return last.get("season_number", 1)
    seasons = [s for s in details.get("seasons", []) if s.get("season_number", 0) > 0]
    if seasons:
        return max(seasons, key=lambda s: s.get("season_number", 0))["season_number"]
    return 1


def fetch_show_full(tv_id):
    """Fetch show details + current season's episodes from TMDB. Returns (show_dict, err)."""
    details, err = tmdb_get(f"/tv/{tv_id}", {"append_to_response": "external_ids"})
    if err:
        return None, err
    season_num = current_season_number(details)
    season, serr = tmdb_get(f"/tv/{tv_id}/season/{season_num}")
    episodes_raw = season.get("episodes", []) if season and not serr else []

    air_dates = [e["air_date"] for e in episodes_raw if e.get("air_date")]
    season_start = min(air_dates) if air_dates else None
    season_end = max(air_dates) if air_dates else None

    status_raw = details.get("status") or "Unknown"
    next_ep = details.get("next_episode_to_air")

    imdb_id = (details.get("external_ids") or {}).get("imdb_id")
    external_ratings = fetch_external_ratings(imdb_id)
    episode_imdb = fetch_episode_imdb_ratings(imdb_id, season_num)

    episodes = [
        {
            "number": e.get("episode_number"),
            "name": e.get("name") or "TBA",
            "air_date": e.get("air_date"),
            "rating": e.get("vote_average"),
            "vote_count": e.get("vote_count", 0),
            "overview": e.get("overview", ""),
            "still_path": e.get("still_path"),
            "imdb_rating": episode_imdb.get(e.get("episode_number")),
        }
        for e in episodes_raw
    ]
    episodes.sort(key=lambda e: (e["number"] is None, e["number"]))

    show = {
        "id": tv_id,
        "name": details.get("name") or "Unknown",
        "poster_path": details.get("poster_path"),
        "overview": details.get("overview", ""),
        "status_raw": status_raw,
        "season_number": season_num,
        "season_start": season_start,
        "season_end": season_end,
        "next_air_date": next_ep.get("air_date") if next_ep else None,
        "episodes": episodes,
        "imdb_id": imdb_id,
        "external_ratings": external_ratings,
        "all_seasons": None,
        "updated_at": date.today().isoformat(),
    }
    return show, None


def format_status(show):
    """Status text computed fresh at render time, so 'in X days' stays accurate
    between refreshes."""
    status_raw = show.get("status_raw") or "Unknown"
    if status_raw in ("Ended", "Canceled"):
        return status_raw
    next_ad = show.get("next_air_date")
    if not next_ad:
        return "Between seasons"
    days = None
    try:
        days = (date.fromisoformat(next_ad) - date.today()).days
    except ValueError:
        pass
    if days is None or days < 0:
        return f"Airing \u2014 next {next_ad}"
    if days == 0:
        return f"Airing today \u2014 next {next_ad}"
    if days == 1:
        return f"Airing tomorrow \u2014 next {next_ad}"
    return f"Airing in {days} days \u2014 next {next_ad}"


def fetch_all_seasons(tv_id, imdb_id=None):
    """All seasons + per-episode ratings (TMDB + IMDb where available)."""
    details, err = tmdb_get(f"/tv/{tv_id}")
    if err or not details:
        return []
    seasons_meta = [
        s for s in details.get("seasons", []) if s.get("season_number", 0) > 0
    ]
    result = []
    for sm in seasons_meta:
        num = sm.get("season_number")
        season, serr = tmdb_get(f"/tv/{tv_id}/season/{num}")
        if serr or not season:
            continue
        imdb_map = fetch_episode_imdb_ratings(imdb_id, num) if imdb_id else {}
        eps = []
        for e in season.get("episodes", []):
            eps.append(
                {
                    "number": e.get("episode_number"),
                    "name": e.get("name") or "TBA",
                    "air_date": e.get("air_date"),
                    "rating": e.get("vote_average"),
                    "vote_count": e.get("vote_count", 0),
                    "imdb_rating": imdb_map.get(e.get("episode_number")),
                }
            )
        eps.sort(key=lambda e: (e["number"] is None, e["number"]))
        result.append(
            {"number": num, "name": sm.get("name") or f"Season {num}", "episodes": eps}
        )
    result.sort(key=lambda s: s["number"])
    return result


def rated_values(episodes):
    return [
        e["rating"] for e in episodes if e.get("rating") and e.get("vote_count", 0) > 0
    ]


def status_color(show):
    raw = (show.get("status_raw") or "").lower()
    if raw in ("ended", "canceled"):
        return "#8B8B8B"
    if show.get("next_air_date"):
        return "#3FB950"
    return "#D29922"


def err_message(err):
    return {
        "missing_key": "No TMDB API key configured yet.",
        "bad_key": "TMDB rejected the API key in `config.json`. Double-check it's your v3 API key.",
        "network": "Couldn't reach TMDB. Check your internet connection and try again.",
    }.get(err, f"TMDB request failed ({err}).")


# ------------------------------------------------------------ calendar image --


def get_font(size, bold=False):
    candidates = [
        "C:\\Windows\\Fonts\\segoeuib.ttf"
        if bold
        else "C:\\Windows\\Fonts\\segoeui.ttf",
        "C:\\Windows\\Fonts\\arialbd.ttf" if bold else "C:\\Windows\\Fonts\\arial.ttf",
    ]
    for c in candidates:
        if os.path.exists(c):
            try:
                return ImageFont.truetype(c, size)
            except Exception:
                pass
    return ImageFont.load_default()


def cached_poster(poster_path, width):
    if not poster_path:
        return None
    os.makedirs(POSTER_CACHE_DIR, exist_ok=True)
    fname = os.path.join(POSTER_CACHE_DIR, poster_path.strip("/").replace("/", "_"))
    if not os.path.exists(fname):
        try:
            r = requests.get(f"{IMG_POSTER_SMALL}{poster_path}", timeout=10)
            r.raise_for_status()
            with open(fname, "wb") as f:
                f.write(r.content)
        except Exception as e:
            log("poster download failed", e)
            return None
    try:
        img = Image.open(fname).convert("RGBA")
        ratio = width / img.width
        return img.resize((width, int(img.height * ratio)))
    except Exception as e:
        log("poster open failed", e)
        return None


def collect_calendar_entries():
    data = load_data()
    entries = []
    for s in data.get("shows", {}).values():
        for e in s.get("episodes", []):
            ad = e.get("air_date")
            if not ad:
                continue
            try:
                d = date.fromisoformat(ad)
            except ValueError:
                continue
            entries.append(
                {
                    "date": d,
                    "show": s.get("name") or "?",
                    "poster": s.get("poster_path"),
                    "ep": e.get("number"),
                }
            )
    return entries


def draw_month(year, month, entries_by_day, cell=112):
    cols, rows = 7, 6
    pad_top = 56
    header_h = 28
    w = cols * cell
    h = pad_top + header_h + rows * cell
    img = Image.new("RGB", (w, h), "#1B1D23")
    draw = ImageDraw.Draw(img)
    title_font = get_font(26, bold=True)
    wd_font = get_font(15, bold=True)
    day_font = get_font(13)
    show_font = get_font(11)

    draw.text(
        (14, 12), f"{cal_mod.month_name[month]} {year}", font=title_font, fill="#E8E8E8"
    )
    weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    for i, wd in enumerate(weekdays):
        draw.text((i * cell + 8, pad_top + 4), wd, font=wd_font, fill="#8B8B8B")

    first_weekday, days_in_month = cal_mod.monthrange(year, month)
    grid_top = pad_top + header_h
    today = date.today()

    for d in range(1, days_in_month + 1):
        idx = first_weekday + (d - 1)
        col, row = idx % 7, idx // 7
        x0, y0 = col * cell, grid_top + row * cell
        draw.rectangle([x0, y0, x0 + cell, y0 + cell], outline="#333844")
        is_today = date(year, month, d) == today
        draw.text(
            (x0 + 6, y0 + 4),
            str(d),
            font=day_font,
            fill="#63A0EA" if is_today else "#AAAAAA",
        )

        day_entries = sorted(entries_by_day.get(d, []), key=lambda e: e["show"])
        if day_entries:
            poster = cached_poster(day_entries[0]["poster"], 44)
            px, py = x0 + cell - 50, y0 + cell - 68
            if poster:
                img.paste(poster, (px, py), poster)
            label = day_entries[0]["show"][:13]
            draw.text((x0 + 4, y0 + cell - 16), label, font=show_font, fill="#E8E8E8")
            if len(day_entries) > 1:
                draw.text(
                    (x0 + cell - 22, y0 + 4),
                    f"+{len(day_entries) - 1}",
                    font=show_font,
                    fill="#F5A623",
                )

    return img


def generate_calendar_image():
    entries = collect_calendar_entries()
    if not entries:
        return None, "No episodes with known air dates in your tracked shows yet."

    today = date.today()
    window_start = today - timedelta(days=14)
    window_end = today + timedelta(days=75)
    windowed = [e for e in entries if window_start <= e["date"] <= window_end]
    if not windowed:
        windowed = entries

    months = sorted(set((e["date"].year, e["date"].month) for e in windowed))[:3]
    imgs = []
    for y, m in months:
        by_day = {}
        for e in windowed:
            if e["date"].year == y and e["date"].month == m:
                by_day.setdefault(e["date"].day, []).append(e)
        imgs.append(draw_month(y, m, by_day))

    if not imgs:
        return None, "Nothing to show yet."

    w = max(i.width for i in imgs)
    h = sum(i.height for i in imgs) + 16 * (len(imgs) - 1)
    combined = Image.new("RGB", (w, h), "#1B1D23")
    y = 0
    for i in imgs:
        combined.paste(i, (0, y))
        y += i.height + 16

    out_path = os.path.abspath(CALENDAR_OUT)
    combined.save(out_path)
    return out_path, None


# ---------------------------------------------------------------- rendering --


def error_frame(rev, title, message, can_go_back):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "canGoBack": can_go_back,
            "detail": {"markdown": f"# {title}\n\n{message}"},
        }
    )


def render_setup_form(rev, can_go_back):
    cfg = load_config()
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "form",
            "canGoBack": can_go_back,
            "form": {
                "title": "Connect TMDB",
                "submitLabel": "Save & continue",
                "fields": [
                    {
                        "id": "api_key",
                        "type": "password",
                        "label": "TMDB API key (v3 auth)",
                        "placeholder": "Paste your key\u2026",
                        "required": True,
                        "description": "Free key: themoviedb.org/settings/api \u2192 API \u2192 v3 auth",
                        "value": cfg.get("tmdb_api_key") or "",
                    },
                    {
                        "id": "omdb_api_key",
                        "type": "password",
                        "label": "OMDb API key (optional)",
                        "placeholder": "Unlocks IMDb / Rotten Tomatoes / Metacritic ratings\u2026",
                        "required": False,
                        "description": "Free key: omdbapi.com/apikey.aspx \u2014 adds ratings beyond TMDB",
                        "value": cfg.get("omdb_api_key") or "",
                    },
                ],
            },
        }
    )


def build_show_items(show, watchlist_action=None):
    episodes = show.get("episodes", [])
    ratings = rated_values(episodes)
    today = date.today().isoformat()
    status_text = format_status(show)
    ext = show.get("external_ratings") or {}

    summary_meta = [
        {"label": "Status", "text": status_text, "color": status_color(show)},
        {"label": "Season", "text": f"Season {show.get('season_number')}"},
        {"label": "Season start", "text": show.get("season_start") or "Unknown"},
        {"label": "Season end", "text": show.get("season_end") or "TBD"},
    ]
    if show.get("next_air_date"):
        summary_meta.append({"label": "Next episode", "text": show["next_air_date"]})
    summary_meta.append({"separator": True})
    if ratings:
        avg = sum(ratings) / len(ratings)
        summary_meta.append(
            {
                "label": "TMDB episode ratings",
                "sparkline": ratings,
                "text": f"avg {avg:.1f}",
                "color": "#F5A623",
            }
        )
    else:
        summary_meta.append({"label": "TMDB episode ratings", "text": "No ratings yet"})
    if ext.get("imdb"):
        summary_meta.append(
            {"label": "IMDb", "text": f"\u2605 {ext['imdb']}/10", "color": "#F5C518"}
        )
    if ext.get("rotten_tomatoes"):
        summary_meta.append(
            {
                "label": "Rotten Tomatoes",
                "text": ext["rotten_tomatoes"],
                "color": "#FA320A",
            }
        )
    if ext.get("metacritic"):
        summary_meta.append(
            {"label": "Metacritic", "text": ext["metacritic"], "color": "#66CC33"}
        )
    if not get_omdb_key():
        summary_meta.append(
            {
                "label": "More ratings",
                "text": "Add an OMDb key in settings for IMDb/RT/Metacritic",
            }
        )

    summary_preview = {
        "markdown": f"## {show.get('name')}\n\n{show.get('overview') or ''}",
        "metadata": summary_meta,
    }
    if show.get("poster_path"):
        summary_preview["image"] = {
            "url": f"{IMG_PREVIEW}{show['poster_path']}",
            "width": 180,
        }

    summary_item = {
        "id": "summary",
        "title": f"\U0001f4ca Season {show.get('season_number')} overview",
        "subtitle": status_text,
        "icon": "chart",
        "section": "Overview",
        "preview": summary_preview,
    }
    if watchlist_action:
        summary_item["actions"] = [watchlist_action]

    all_seasons_item = {
        "id": "all_seasons",
        "title": "\U0001f4da All seasons",
        "subtitle": "Browse every season \u2022 episode-by-episode ratings",
        "icon": "list",
        "section": "Overview",
    }

    items = [summary_item, all_seasons_item]

    for e in episodes:
        aired = bool(e.get("air_date")) and e["air_date"] <= today
        rated = bool(e.get("rating")) and e.get("vote_count", 0) > 0
        rating_text = f"\u2605 {e['rating']:.1f}" if rated else "\u2014"
        imdb_rating = e.get("imdb_rating")
        num = e.get("number")
        num_txt = f"{num:02d}" if isinstance(num, int) else "??"

        ep_meta = [
            {"label": "Air date", "text": e.get("air_date") or "TBA"},
            {
                "label": "TMDB rating",
                "text": rating_text,
                "color": "#F5A623" if rated else None,
            },
        ]
        if imdb_rating:
            ep_meta.append(
                {
                    "label": "IMDb rating",
                    "text": f"\u2605 {imdb_rating}/10",
                    "color": "#F5C518",
                }
            )

        ep_preview = {
            "markdown": f"### E{num_txt} \u00b7 {e.get('name')}\n\n{e.get('overview') or 'No overview available.'}",
            "metadata": ep_meta,
        }
        if e.get("still_path"):
            ep_preview["image"] = {"url": f"{IMG_STILL}{e['still_path']}", "width": 220}

        accessories = [
            {"text": rating_text, "color": "#F5A623" if rated else "#8B8B8B"}
        ]
        if imdb_rating:
            accessories.append({"text": f"IMDb {imdb_rating}", "color": "#F5C518"})

        items.append(
            {
                "id": f"ep:{num}",
                "title": f"E{num_txt} \u00b7 {e.get('name')}",
                "subtitle": (e.get("air_date") or "Air date TBA")
                + ("" if aired else "  \u2022  Upcoming"),
                "icon": "check" if aired else "clock",
                "section": "Episodes",
                "accessories": accessories,
                "actions": [
                    {"id": "open_tmdb", "title": "Open episode on TMDB", "icon": "open"}
                ],
                "preview": ep_preview,
            }
        )

    return items


def render_show_screen(
    rev, show, frame_actions, placeholder_prefix, watchlist_action=None
):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "preview": {"enabled": True},
            "placeholder": f"{placeholder_prefix} {show.get('name')}\u2026",
            "selectId": "summary",
            "actions": frame_actions,
            "items": build_show_items(show, watchlist_action=watchlist_action),
        }
    )


def render_all_seasons(rev, show, persist):
    """List of all seasons; each item's side-preview shows every episode's rating."""
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "loading": True,
            "loadingText": f"Loading all seasons of {show.get('name')}\u2026",
            "items": [],
        }
    )

    seasons = show.get("all_seasons")
    if seasons is None:
        seasons = fetch_all_seasons(show["id"], show.get("imdb_id"))
        show["all_seasons"] = seasons
        if persist:
            data = load_data()
            data.setdefault("shows", {})[str(show["id"])] = show
            save_data(data)

    items = []
    for s in seasons:
        ratings = [
            e["rating"]
            for e in s["episodes"]
            if e.get("rating") and e.get("vote_count", 0) > 0
        ]
        avg = sum(ratings) / len(ratings) if ratings else None
        lines = []
        for e in s["episodes"]:
            num = e.get("number")
            num_txt = f"{num:02d}" if isinstance(num, int) else "??"
            if e.get("rating") and e.get("vote_count", 0) > 0:
                r = f"\u2605 {e['rating']:.1f}"
            else:
                r = "\u2014"
            if e.get("imdb_rating"):
                r += f" \u00b7 IMDb {e['imdb_rating']}"
            lines.append(f"**E{num_txt}** {e.get('name') or 'TBA'} \u2014 {r}")
        md = f"## {s['name']}\n\n" + (
            "\n\n".join(lines) if lines else "No episodes found."
        )
        meta = []
        if ratings:
            meta.append(
                {
                    "label": "TMDB ratings",
                    "sparkline": ratings,
                    "text": f"avg {avg:.1f}",
                    "color": "#F5A623",
                }
            )

        items.append(
            {
                "id": f"season:{s['number']}",
                "title": s["name"],
                "subtitle": f"{len(s['episodes'])} episodes"
                + (f" \u2022 avg \u2605{avg:.1f}" if avg else ""),
                "icon": "video",
                "actions": [
                    {"id": "open_tmdb", "title": "Open season on TMDB", "icon": "open"}
                ],
                "preview": {"markdown": md, "metadata": meta},
            }
        )

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "preview": {"enabled": True},
            "placeholder": f"All seasons of {show.get('name')}\u2026",
            "emptyText": "No seasons found",
            "actions": [
                {
                    "id": "refresh_all_seasons",
                    "title": "Refresh all seasons",
                    "icon": "refresh",
                }
            ],
            "items": items,
        }
    )


def render_root(rev, query_text):
    if not get_api_key():
        state["screen"] = "setup"
        render_setup_form(rev, can_go_back=False)
        return

    data = load_data()
    shows = list(data.get("shows", {}).values())
    shows.sort(key=lambda s: (s.get("name") or "").lower())

    q = (query_text or "").strip().lower()
    if q:
        shows = [s for s in shows if q in (s.get("name") or "").lower()]

    items = []
    if not q:
        items.append(
            {
                "id": "search_show",
                "title": "\U0001f50d Search Show",
                "subtitle": "Search TMDB and add a new show",
                "icon": "search",
                "section": "Tools",
            }
        )
        if shows:
            items.append(
                {
                    "id": "calendar",
                    "title": "\U0001f4c5 Calendar",
                    "subtitle": "Poster calendar of when your shows air",
                    "icon": "calendar",
                    "section": "Tools",
                }
            )

    for s in shows:
        icon = f"{IMG_ROW}{s['poster_path']}" if s.get("poster_path") else "video"
        ratings = rated_values(s.get("episodes", []))
        accessories = []
        if ratings:
            avg = sum(ratings) / len(ratings)
            accessories.append({"text": f"\u2605{avg:.1f}", "color": "#F5A623"})
        ext = s.get("external_ratings") or {}
        if ext.get("imdb"):
            accessories.append({"text": f"IMDb {ext['imdb']}", "color": "#F5C518"})
        items.append(
            {
                "id": f"show:{s['id']}",
                "title": s.get("name") or "Unknown",
                "subtitle": f"Season {s.get('season_number')} \u2022 {format_status(s)}",
                "icon": icon,
                "section": "Your shows",
                "accessories": accessories,
                "actions": [
                    {"id": "refresh", "title": "Refresh from TMDB", "icon": "refresh"},
                    {
                        "id": "remove",
                        "title": "Remove show",
                        "icon": "trash",
                        "destructive": True,
                        "confirm": {
                            "title": f"Remove {s.get('name')}?",
                            "message": "This stops tracking this show.",
                            "confirmLabel": "Remove",
                        },
                    },
                    {"id": "open_tmdb", "title": "Open on TMDB", "icon": "open"},
                ],
            }
        )

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "placeholder": "Filter your shows, or Ctrl+K to add one\u2026",
            "emptyText": "No shows tracked yet",
            "empty": {
                "icon": "video",
                "title": "No shows tracked",
                "hint": "Add a show from TMDB to get started",
                "action": {"id": "add", "title": "Add a show", "icon": "add"},
            },
            "actions": [
                {
                    "id": "add",
                    "title": "Add show from TMDB",
                    "icon": "add",
                    "shortcut": "ctrl+n",
                },
                {"id": "settings", "title": "Change TMDB API key", "icon": "key"},
                {"id": "omdb_settings", "title": "Add OMDb API key", "icon": "key"},
            ],
            "items": items,
        }
    )


def render_search(rev, query_text):
    q = (query_text or "").strip()
    if not q:
        send(
            {
                "type": "render",
                "rev": rev,
                "view": "list",
                "canGoBack": True,
                "placeholder": "Type a show name to search TMDB\u2026",
                "emptyText": "Type to search TMDB",
                "items": [],
            }
        )
        return

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "loading": True,
            "loadingText": "Searching TMDB\u2026",
            "placeholder": "Type a show name to search TMDB\u2026",
            "items": [],
        }
    )

    results, err = search_shows(q)
    if err:
        error_frame(rev, "Search failed", err_message(err), True)
        return

    data = load_data()
    tracked_ids = set(data.get("shows", {}).keys())

    items = []
    for r in results[:25]:
        rid = str(r["id"])
        already = rid in tracked_ids
        icon = f"{IMG_ROW}{r['poster_path']}" if r.get("poster_path") else "video"
        year = (r.get("first_air_date") or "")[:4]
        title = r.get("name", "Unknown") + (f" ({year})" if year else "")
        subtitle = (
            "\u2713 Already in your watchlist \u2014 select to view"
            if already
            else (r.get("overview") or "No overview")[:110]
        )
        items.append(
            {
                "id": f"peek:{rid}",
                "title": title,
                "subtitle": subtitle,
                "icon": icon,
                "actions": [
                    {"id": "open_tmdb", "title": "Open on TMDB", "icon": "open"}
                ],
            }
        )

    send(
        {
            "type": "render",
            "rev": rev,
            "view": "list",
            "canGoBack": True,
            "placeholder": "Type a show name to search TMDB\u2026",
            "emptyText": "No shows found",
            "items": items,
        }
    )


def render_peek(rev):
    show = state.get("peek_show")
    if not show:
        state["screen"] = "search"
        render_search(rev, state["query_search"])
        return
    already = str(show["id"]) in load_data().get("shows", {})
    frame_actions = [{"id": "open_tmdb", "title": "Open on TMDB", "icon": "open"}]
    watchlist_action = None
    if already:
        frame_actions.insert(
            0, {"id": "noop", "title": "Already in watchlist", "icon": "check"}
        )
    else:
        watchlist_action = {"id": "add", "title": "Add to watchlist", "icon": "add"}
        frame_actions.insert(0, watchlist_action)
    render_show_screen(
        rev, show, frame_actions, "Previewing", watchlist_action=watchlist_action
    )


def render_show(rev, show_id):
    data = load_data()
    s = data.get("shows", {}).get(str(show_id))
    if not s:
        error_frame(rev, "Show not found", "It may have been removed.", True)
        return
    frame_actions = [
        {"id": "refresh", "title": "Refresh from TMDB", "icon": "refresh"},
        {
            "id": "remove",
            "title": "Remove show",
            "icon": "trash",
            "destructive": True,
            "confirm": {
                "title": f"Remove {s.get('name')}?",
                "message": "This stops tracking this show.",
                "confirmLabel": "Remove",
            },
        },
        {"id": "open_tmdb", "title": "Open show on TMDB", "icon": "open"},
    ]
    render_show_screen(rev, s, frame_actions, "Browsing")


def render_calendar(rev):
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "canGoBack": True,
            "loading": True,
            "loadingText": "Building your poster calendar\u2026",
            "detail": {"markdown": ""},
        }
    )
    path, err = generate_calendar_image()
    if err:
        error_frame(rev, "No calendar yet", err, True)
        return
    uri = pathlib.Path(path).as_uri()
    send(
        {
            "type": "render",
            "rev": rev,
            "view": "detail",
            "canGoBack": True,
            "detail": {
                "wide": True,
                "markdown": f"# \U0001f4c5 Episode Calendar\n\n![Calendar]({uri})\n\n"
                f"Covers roughly the last 2 weeks through the next ~2.5 months across your tracked shows.",
            },
        }
    )


# --------------------------------------------------------------------- state --

state = {
    "screen": "root",
    "show_id": None,
    "query_root": "",
    "query_search": "",
    "peek_show": None,
    "all_seasons_from": None,
}


def go_root(rev=0):
    state["screen"] = "root"
    state["show_id"] = None
    state["peek_show"] = None
    send({"type": "command", "command": "setQuery", "text": ""})
    render_root(rev, "")


def refresh_show(tv_id_str, rerender):
    full, err = fetch_show_full(int(tv_id_str))
    if err:
        send(
            {
                "type": "command",
                "command": "toast",
                "text": f"Refresh failed: {err_message(err)[:60]}",
                "style": "error",
            }
        )
    else:
        data = load_data()
        data.setdefault("shows", {})[tv_id_str] = full
        save_data(data)
        send(
            {"type": "command", "command": "toast", "text": f"Refreshed {full['name']}"}
        )
    if rerender:
        rerender()


# -------------------------------------------------------------------- events --


def handle_query(rev, text):
    screen = state["screen"]
    if screen == "root":
        state["query_root"] = text
        render_root(rev, text)
    elif screen == "search":
        state["query_search"] = text
        render_search(rev, text)
    # peek / show / calendar / setup: query bar isn't the primary input there; ignore keystrokes.


def handle_back():
    screen = state["screen"]
    if screen == "peek":
        state["screen"] = "search"
        render_search(0, state["query_search"])
    elif screen == "all_seasons":
        if state["all_seasons_from"] == "show":
            state["screen"] = "show"
            render_show(0, state["show_id"])
        else:
            state["screen"] = "peek"
            render_peek(0)
    elif screen in ("search", "show", "calendar"):
        go_root()


def handle_submit(values):
    if state["screen"] != "setup":
        return
    key = (values.get("api_key") or "").strip()
    omdb_key = (values.get("omdb_api_key") or "").strip()
    cfg = {"tmdb_api_key": key}
    if omdb_key:
        cfg["omdb_api_key"] = omdb_key
    save_config(cfg)
    send(
        {
            "type": "command",
            "command": "toast",
            "text": "OMDb key saved" if omdb_key else "TMDB connected",
        }
    )
    go_root()


def handle_action(item_id, action):
    screen = state["screen"]

    if screen == "root":
        if item_id == "" and action == "add":
            state["screen"] = "search"
            send({"type": "command", "command": "setQuery", "text": ""})
            render_search(0, "")
        elif item_id == "" and action in ("settings", "omdb_settings"):
            state["screen"] = "setup"
            send({"type": "command", "command": "setQuery", "text": ""})
            render_setup_form(0, can_go_back=True)
        elif item_id == "search_show" and action == "default":
            state["screen"] = "search"
            send({"type": "command", "command": "setQuery", "text": ""})
            render_search(0, "")
        elif item_id == "calendar" and action == "default":
            state["screen"] = "calendar"
            send({"type": "command", "command": "setQuery", "text": ""})
            render_calendar(0)
        elif item_id.startswith("show:"):
            sid = item_id.split(":", 1)[1]
            if action == "default":
                state["screen"] = "show"
                state["show_id"] = sid
                send({"type": "command", "command": "setQuery", "text": ""})
                render_show(0, sid)
            elif action == "refresh":
                refresh_show(sid, lambda: render_root(0, state["query_root"]))
            elif action == "remove":
                data = load_data()
                name = data.get("shows", {}).get(sid, {}).get("name", "Show")
                data.get("shows", {}).pop(sid, None)
                save_data(data)
                send({"type": "command", "command": "toast", "text": f"Removed {name}"})
                render_root(0, state["query_root"])
            elif action == "open_tmdb":
                send(
                    {
                        "type": "command",
                        "command": "open",
                        "url": f"https://www.themoviedb.org/tv/{sid}",
                    }
                )
        return

    if screen == "search":
        if item_id.startswith("peek:"):
            tid = item_id.split(":", 1)[1]
            if action == "default":
                send(
                    {
                        "type": "render",
                        "rev": 0,
                        "view": "list",
                        "canGoBack": True,
                        "loading": True,
                        "loadingText": "Loading show\u2026",
                        "items": [],
                    }
                )
                full, err = fetch_show_full(int(tid))
                if err:
                    send(
                        {
                            "type": "command",
                            "command": "toast",
                            "text": f"Couldn't load show: {err_message(err)[:60]}",
                            "style": "error",
                        }
                    )
                    render_search(0, state["query_search"])
                    return
                state["screen"] = "peek"
                state["peek_show"] = full
                render_peek(0)
            elif action == "open_tmdb":
                send(
                    {
                        "type": "command",
                        "command": "open",
                        "url": f"https://www.themoviedb.org/tv/{tid}",
                    }
                )
        return

    if screen == "peek":
        show = state.get("peek_show") or {}
        sid = str(show.get("id", ""))
        if item_id in ("", "summary"):
            if action == "add":
                data = load_data()
                data.setdefault("shows", {})[sid] = show
                save_data(data)
                send(
                    {
                        "type": "command",
                        "command": "toast",
                        "text": f"Added {show.get('name')} to your watchlist",
                    }
                )
                go_root()
            elif action == "open_tmdb":
                send(
                    {
                        "type": "command",
                        "command": "open",
                        "url": f"https://www.themoviedb.org/tv/{sid}",
                    }
                )
        elif item_id == "all_seasons" and action == "default":
            state["screen"] = "all_seasons"
            state["all_seasons_from"] = "peek"
            send({"type": "command", "command": "setQuery", "text": ""})
            render_all_seasons(0, show, persist=False)
        elif item_id.startswith("ep:") and action == "open_tmdb":
            num = item_id.split(":", 1)[1]
            url = f"https://www.themoviedb.org/tv/{sid}/season/{show.get('season_number', 1)}/episode/{num}"
            send({"type": "command", "command": "open", "url": url})
        return

    if screen == "show":
        sid = state.get("show_id")
        if item_id == "":
            if action == "refresh":
                refresh_show(sid, lambda: render_show(0, sid))
            elif action == "remove":
                data = load_data()
                name = data.get("shows", {}).get(sid, {}).get("name", "Show")
                data.get("shows", {}).pop(sid, None)
                save_data(data)
                send({"type": "command", "command": "toast", "text": f"Removed {name}"})
                go_root()
            elif action == "open_tmdb":
                send(
                    {
                        "type": "command",
                        "command": "open",
                        "url": f"https://www.themoviedb.org/tv/{sid}",
                    }
                )
        elif item_id == "all_seasons" and action == "default":
            data = load_data()
            show = data.get("shows", {}).get(sid)
            if show:
                state["screen"] = "all_seasons"
                state["all_seasons_from"] = "show"
                send({"type": "command", "command": "setQuery", "text": ""})
                render_all_seasons(0, show, persist=True)
        elif item_id.startswith("ep:") and action == "open_tmdb":
            data = load_data()
            s = data.get("shows", {}).get(sid, {})
            num = item_id.split(":", 1)[1]
            url = f"https://www.themoviedb.org/tv/{sid}/season/{s.get('season_number', 1)}/episode/{num}"
            send({"type": "command", "command": "open", "url": url})
        return

    if screen == "all_seasons":
        if item_id == "" and action == "refresh_all_seasons":
            if state["all_seasons_from"] == "show":
                data = load_data()
                show = data.get("shows", {}).get(state["show_id"])
                if show:
                    show["all_seasons"] = None
                    render_all_seasons(0, show, persist=True)
            else:
                show = state.get("peek_show") or {}
                show["all_seasons"] = None
                render_all_seasons(0, show, persist=False)
        elif item_id.startswith("season:") and action == "open_tmdb":
            num = item_id.split(":", 1)[1]
            sid = (
                state["show_id"]
                if state["all_seasons_from"] == "show"
                else str((state.get("peek_show") or {}).get("id", ""))
            )
            send(
                {
                    "type": "command",
                    "command": "open",
                    "url": f"https://www.themoviedb.org/tv/{sid}/season/{num}",
                }
            )
        return


# ----------------------------------------------------------------------- main --


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
        try:
            if t == "close":
                break
            elif t in ("init", "query"):
                handle_query(msg.get("rev", 0), msg.get("text", msg.get("query", "")))
            elif t == "action":
                handle_action(msg.get("id", ""), msg.get("action", "default"))
            elif t == "back":
                handle_back()
            elif t == "submit":
                handle_submit(msg.get("values", {}))
            # "select", "submitQuery", "change", "loadMore", "tab" not used.
        except Exception as e:
            log("unhandled error", e)
            error_frame(
                0, "Something went wrong", f"```\n{e}\n```", state["screen"] != "root"
            )


if __name__ == "__main__":
    main()
