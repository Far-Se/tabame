#!/usr/bin/env node
/*
 * MDBList plugin for the Tabame launcher.
 *
 * Runs as a long-lived child process speaking the launcher's newline-delimited
 * JSON protocol (see TABAME_PLUGIN_SKILL.md). The launcher exposes a single
 * query line, so this plugin is an internal state machine: a root command
 * list that drills into each command's own screen. Sub-screens set
 * canGoBack, so Escape pops back to the root instead of tearing down the
 * whole plugin.
 *
 * Runtime: Node 18+ (global fetch) or Bun. Plain JS, no dependencies.
 *
 * Setup: get a free API key from https://mdblist.com/preferences/#api and
 * paste it into the in-app form the first time you launch the plugin. The
 * key is stored via the launcher's secure `storage` command (Windows
 * Credential Manager), never written to disk in this folder.
 *
 * API reference: https://docs.mdblist.com/docs/api
 */

"use strict";

const fs = require("fs");
const path = require("path");

const API_BASE = "https://api.mdblist.com";
const SITE = "https://mdblist.com";
const PREFS_URL = "https://mdblist.com/preferences/#api";
const TMDB_IMG = "https://image.tmdb.org/t/p";

// ── protocol plumbing ────────────────────────────────────────────────────────
function send(frame) {
  process.stdout.write(JSON.stringify(frame) + "\n");
}
function log(...a) {
  process.stderr.write(
    a.map((x) => (typeof x === "string" ? x : JSON.stringify(x))).join(" ") +
      "\n",
  );
}
// Sub-screens (stack depth > 1) get canGoBack so Escape pops instead of exiting.
function render(rev, view, opts = {}) {
  send({
    type: "render",
    rev,
    view,
    canGoBack: state.stack.length > 1,
    ...opts,
  });
}
function command(name, extra = {}) {
  send({ type: "command", command: name, ...extra });
}
const cmdCopy = (t) => command("copy", { text: t == null ? "" : String(t) });
const cmdOpen = (u) => command("open", { url: u });
const cmdToast = (t, style) => command("toast", { text: t, style });
const cmdHide = () => command("hide");
const cmdSetQuery = (t) => command("setQuery", { text: t });

const storageRequests = new Map();
let storageRequestId = 0;
function storageGet(key, secret = false) {
  return new Promise((resolve) => {
    const requestId = `mdb-storage-${++storageRequestId}`;
    const timer = setTimeout(() => {
      storageRequests.delete(requestId);
      resolve(undefined);
    }, 1500);
    storageRequests.set(requestId, (value) => {
      clearTimeout(timer);
      resolve(value);
    });
    command("storage", { op: "get", key, secret, requestId });
  });
}
function storageSet(key, value, secret = false) {
  command("storage", { op: "set", key, value, secret });
}

function loadingFrame(rev, text) {
  render(rev, "list", {
    loading: true,
    items: [],
    loadingText: text || "Loading…",
  });
}
function renderError(rev, err) {
  const msg = err && err.message ? err.message : String(err);
  render(rev, "detail", {
    detail: { markdown: `## MDBList error\n\n\`\`\`\n${msg}\n\`\`\`` },
  });
}

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// ── config ───────────────────────────────────────────────────────────────────
function loadConfig() {
  const cfg = { apikey: process.env.MDBLIST_API_KEY || "", username: "" };
  try {
    const file = path.join(process.cwd(), "config.json");
    if (fs.existsSync(file)) {
      const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
      if (parsed.apikey) cfg.apikey = parsed.apikey;
    }
  } catch (err) {
    log("config:", err.message);
  }
  return cfg;
}
const config = loadConfig();
let configReady = null;
function ensureConfigLoaded() {
  if (configReady) return configReady;
  configReady = storageGet("apikey", true).then((stored) => {
    if (typeof stored === "string" && stored) config.apikey = stored;
  });
  return configReady;
}

// ── HTTP ─────────────────────────────────────────────────────────────────────
async function mdb(
  apiPath,
  { method = "GET", body = null, rawQuery = {}, overrideApikey } = {},
) {
  const url = new URL(API_BASE + apiPath);
  const key = overrideApikey || config.apikey;
  if (key) url.searchParams.set("apikey", key);
  for (const [k, v] of Object.entries(rawQuery)) {
    if (v !== undefined && v !== null && v !== "")
      url.searchParams.set(k, String(v));
  }
  const res = await fetch(url.toString(), {
    method,
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch (_) {
    data = text;
  }
  if (!res.ok) {
    const detail =
      (data && data.error) ||
      (typeof data === "string" && data) ||
      `HTTP ${res.status}`;
    throw new HttpError(res.status, detail);
  }
  return { data, headers: res.headers };
}

// ── formatting helpers ───────────────────────────────────────────────────────
function pad2(n) {
  return String(n).padStart(2, "0");
}
function fmtDate(iso) {
  try {
    return new Date(iso).toLocaleDateString();
  } catch (_) {
    return iso || "";
  }
}
function fmtDateTime(iso) {
  try {
    return new Date(iso).toLocaleString([], {
      dateStyle: "medium",
      timeStyle: "short",
    });
  } catch (_) {
    return iso || "";
  }
}
function posterUrl(p, size = "w342") {
  if (!p) return null;
  if (/^https?:\/\//.test(p)) return p;
  return `${TMDB_IMG}/${size}${p}`;
}
function imdbUrl(ids) {
  return ids && ids.imdb ? `https://www.imdb.com/title/${ids.imdb}/` : null;
}
function tmdbUrl(ids, mediatype) {
  if (!ids || !ids.tmdb) return null;
  const seg = mediatype === "show" ? "tv" : "movie";
  return `https://www.themoviedb.org/${seg}/${ids.tmdb}`;
}
function idsBody(ids) {
  const o = {};
  if (ids.tmdb) o.tmdb = ids.tmdb;
  if (ids.imdb) o.imdb = ids.imdb;
  return o;
}

const RATING_LABELS = {
  imdb: "IMDb",
  tmdb: "TMDb",
  metacritic: "Metacritic",
  metacriticuser: "Metacritic (User)",
  trakt: "Trakt",
  tomatoes: "Rotten Tomatoes",
  rtaudience: "RT Audience",
  letterboxd: "Letterboxd",
  rogerebert: "Roger Ebert",
  myanimelist: "MyAnimeList",
  mdblist: "MDBList",
};
function fmtRatingValue(r) {
  if ((r.source === "imdb" || r.source === "tmdb") && r.value != null)
    return Number(r.value).toFixed(1);
  if (r.score != null) return String(r.score);
  if (r.value != null) return String(r.value);
  return "—";
}

// ── media normalization ──────────────────────────────────────────────────────
// Search, list-item, and watchlist-item responses all have different shapes.
// Fold them into one common item shape so a single builder handles all of them.
function fromSearch(o) {
  const ids = o.ids || {};
  return {
    mediatype: o.type,
    title: o.title,
    year: o.year,
    ids: {
      imdb: ids.imdbid,
      tmdb: ids.tmdbid,
      trakt: ids.traktid,
      tvdb: ids.tvdbid,
      mal: ids.malid,
    },
    score: o.score,
    ratings: null,
    poster: null,
    description: null,
    genres: null,
    rank: null,
    watchlistAt: null,
  };
}
function fromListItem(o) {
  const ids = o.ids || {};
  return {
    mediatype: o.mediatype,
    title: o.title,
    year: o.release_year,
    ids: {
      imdb: o.imdb_id || ids.imdb,
      tmdb: ids.tmdb,
      tvdb: o.tvdb_id || ids.tvdb,
      mdblist: ids.mdblist,
    },
    score: null,
    ratings: o.ratings || null,
    poster: o.poster || null,
    description: o.description || null,
    genres: o.genres || null,
    rank: o.rank,
    watchlistAt: o.watchlist_at || null,
  };
}

function ratingBits(it) {
  const bits = [];
  if (it.mediatype)
    bits.push({
      text: it.mediatype === "show" ? "TV" : "FILM",
      color: it.mediatype === "show" ? "#8B5CF6" : "#0EA5E9",
    });
  if (it.score != null) bits.push({ text: `★ ${it.score}`, color: "#F5C518" });
  if (it.ratings) {
    const imdb = it.ratings.find((r) => r.source === "imdb");
    if (imdb && imdb.value != null)
      bits.push({
        text: `IMDb ${Number(imdb.value).toFixed(1)}`,
        color: "#F5C518",
      });
    const mdblist = it.ratings.find((r) => r.source === "mdblist");
    if (mdblist && mdblist.score != null)
      bits.push({ text: `MDB ${mdblist.score}`, color: "#0EA5E9" });
  }
  return bits;
}

function mediaPreview(it, actions) {
  const md = [];
  md.push(`## ${it.title || "Untitled"}${it.year ? ` (${it.year})` : ""}`);
  if (it.description) md.push("", it.description);

  const meta = [];
  meta.push({
    label: "Type",
    text: it.mediatype === "show" ? "TV Show" : "Movie",
    icon: "video",
  });
  if (it.year) meta.push({ label: "Year", text: String(it.year) });
  if (it.genres && it.genres.length) {
    meta.push({
      label: "Genres",
      text: Array.isArray(it.genres) ? it.genres.join(", ") : String(it.genres),
    });
  }
  if (it.ratings && it.ratings.length) {
    for (const r of it.ratings) {
      if (r.value == null && r.score == null) continue;
      meta.push({
        label: RATING_LABELS[r.source] || r.source,
        text: fmtRatingValue(r),
        color: "#F5C518",
      });
    }
  } else if (it.score != null) {
    meta.push({
      label: "MDBList Score",
      text: String(it.score),
      color: "#0EA5E9",
    });
  }
  if (it.rank != null) meta.push({ label: "Rank", text: `#${it.rank}` });
  if (it.watchlistAt)
    meta.push({ label: "Added", text: fmtDate(it.watchlistAt), icon: "clock" });

  meta.push({ separator: true });
  const iu = imdbUrl(it.ids);
  if (iu) meta.push({ label: "IMDb", text: it.ids.imdb, url: iu });
  const tu = tmdbUrl(it.ids, it.mediatype);
  if (tu) meta.push({ label: "TMDB", text: String(it.ids.tmdb), url: tu });
  if (actions.length) {
    meta.push({ separator: true });
    meta.push({ label: "Actions", text: "", actions });
  }

  const poster = posterUrl(it.poster);
  return {
    markdown: md.join("\n"),
    ...(poster ? { image: { url: poster, width: 160 } } : {}),
    metadata: meta,
  };
}

function mediaActions(it, screenKind) {
  const a = [];
  const iu = imdbUrl(it.ids);
  const tu = tmdbUrl(it.ids, it.mediatype);
  a.push({
    id: "default",
    title: iu ? "Open on IMDb" : tu ? "Open on TMDB" : "Open",
    icon: "open",
  });
  if (iu && tu)
    a.push({ id: "open_tmdb", title: "Open on TMDB", icon: "link" });
  a.push({ id: "copy_title", title: "Copy Title", icon: "copy" });
  if (it.ids.imdb)
    a.push({ id: "copy_imdb", title: "Copy IMDb ID", icon: "copy" });
  if (config.apikey) {
    if (screenKind === "watchlist") {
      a.push({
        id: "remove_watchlist",
        title: "Remove from Watchlist",
        icon: "remove",
        destructive: true,
      });
    } else {
      a.push({ id: "add_watchlist", title: "Add to Watchlist", icon: "add" });
    }
  }
  return a;
}

function mediaIcon(it) {
  return posterUrl(it.poster) || (it.mediatype === "show" ? "video" : "play");
}

function mediaItem(it, screenKind) {
  const sub = [];
  if (it.year) sub.push(String(it.year));
  if (it.genres && it.genres.length)
    sub.push(
      Array.isArray(it.genres)
        ? it.genres.slice(0, 3).join(", ")
        : String(it.genres),
    );
  if (it.watchlistAt) sub.push(`added ${fmtDate(it.watchlistAt)}`);
  const idKey = it.ids.mdblist || it.ids.imdb || it.ids.tmdb || it.title;
  const actions = mediaActions(it, screenKind);
  return {
    id: `media:${it.mediatype || "x"}:${idKey}`,
    title: it.title || "Untitled",
    subtitle: sub.join("  ·  "),
    icon: mediaIcon(it),
    accessories: ratingBits(it),
    actions,
    preview: mediaPreview(it, actions),
    _data: it,
  };
}

function listItem(l) {
  const subBits = [
    l.mediatype === "show"
      ? "Shows"
      : l.mediatype === "movie"
        ? "Movies"
        : "Mixed",
    `${l.items} items`,
  ];
  if (l.likes) subBits.push(`♥ ${l.likes}`);
  if (l.user_name) subBits.push(`by ${l.user_name}`);
  return {
    id: `list:${l.id}`,
    title: l.name,
    subtitle: subBits.join("  ·  "),
    icon: l.dynamic ? "sync" : "list",
    accessories: [
      l.private ? { text: "Private", icon: "lock" } : null,
      { text: l.dynamic ? "Dynamic" : "Static" },
    ].filter(Boolean),
    actions: [
      { id: "default", title: "Open List", icon: "open" },
      { id: "open_web", title: "Open on mdblist.com", icon: "link" },
    ],
    preview: {
      markdown: `## ${l.name}\n\n${l.description || "*No description*"}`,
      metadata: [
        { label: "Owner", text: l.user_name || "—" },
        { label: "Items", text: String(l.items) },
        { label: "Likes", text: String(l.likes || 0), icon: "heart" },
        { label: "Type", text: l.dynamic ? "Dynamic" : "Static" },
      ],
    },
    _list: l,
  };
}

function upNextItem(u) {
  const show = u.show || {};
  const ep = u.next_episode || {};
  const prog = u.progress || {};
  const sub = [];
  if (ep.season != null && ep.episode != null)
    sub.push(
      `S${pad2(ep.season)}E${pad2(ep.episode)}${ep.title ? ` · ${ep.title}` : ""}`,
    );
  if (ep.air_date) sub.push(fmtDateTime(ep.air_date));
  const acc = [];
  if (prog.total_episode_count)
    acc.push({
      text: `${prog.watched_episode_count}/${prog.total_episode_count}`,
      icon: "check",
    });
  const tmdbId = show.ids && show.ids.tmdb;
  return {
    id: `upnext:${tmdbId || show.title}`,
    title: show.title || "Untitled",
    subtitle: sub.join("  ·  "),
    icon: posterUrl(show.poster) || "video",
    accessories: acc,
    actions: [
      { id: "default", title: "Open on TMDB", icon: "open" },
      { id: "copy_title", title: "Copy Title", icon: "copy" },
    ],
    preview: {
      markdown: `## ${show.title || "Untitled"}${show.year ? ` (${show.year})` : ""}\n\n**Next up:** ${sub.join(" · ") || "—"}`,
      metadata: [
        prog.total_episode_count
          ? {
              label: "Progress",
              text: `${prog.watched_episode_count}/${prog.total_episode_count}`,
            }
          : null,
        u.last_watched_at
          ? { label: "Last watched", text: fmtDateTime(u.last_watched_at) }
          : null,
      ].filter(Boolean),
    },
    _show: show,
  };
}

// ── state machine ────────────────────────────────────────────────────────────
const state = {
  stack: [{ screen: "root", ctx: {}, savedQuery: "" }],
  itemsById: {},
  lastRev: 0,
  lastText: "",
};
function top() {
  return state.stack[state.stack.length - 1];
}
function setItems(items) {
  state.itemsById = {};
  for (const it of items) state.itemsById[it.id] = it;
}
function ctxFor(screen) {
  switch (screen) {
    case "search_all":
      return { screen: "search", mediaType: "any" };
    case "search_movies":
      return { screen: "search", mediaType: "movie" };
    case "search_shows":
      return { screen: "search", mediaType: "show" };
    case "watchlist":
      return {
        screen: "watchlist",
        loaded: [],
        offset: 0,
        hasMore: true,
        fetched: false,
      };
    default:
      return { screen, ctx: {} };
  }
}
function push(cmdId, extraCtx) {
  cancelDebounce();
  top().savedQuery = state.lastText;
  const mapped = ctxFor(cmdId);
  const screen = mapped.screen || cmdId;
  const ctx = Object.assign({}, mapped.ctx || mapped, extraCtx || {});
  delete ctx.screen;
  state.stack.push({ screen, ctx, savedQuery: "" });
  cmdSetQuery("");
  return renderScreen(0, "");
}
function popScreen() {
  cancelDebounce();
  if (state.stack.length > 1) state.stack.pop();
  const q = top().savedQuery || "";
  cmdSetQuery(q);
  return renderScreen(0, q);
}
function resetToRoot() {
  cancelDebounce();
  state.stack = [{ screen: "root", ctx: {}, savedQuery: "" }];
  cmdSetQuery("");
  return renderScreen(0, "");
}

// Debounce for screens that hit the API on every keystroke.
let debounceTimer = null;
function cancelDebounce() {
  if (debounceTimer) clearTimeout(debounceTimer);
  debounceTimer = null;
}
function debounce(rev, fn) {
  cancelDebounce();
  const frame = top();
  debounceTimer = setTimeout(() => {
    debounceTimer = null;
    if (top() !== frame) return; // user navigated away meanwhile
    fn().catch((err) => renderError(rev, err));
  }, 350);
}

// ── root ─────────────────────────────────────────────────────────────────────
function buildCommands() {
  return [
    {
      id: "search_all",
      section: "Search",
      title: "Search Movies & Shows",
      subtitle: "Search mdblist.com",
      icon: "search",
    },
    {
      id: "search_movies",
      section: "Search",
      title: "Search Movies",
      subtitle: "Movies only",
      icon: "search",
    },
    {
      id: "search_shows",
      section: "Search",
      title: "Search Shows",
      subtitle: "TV shows only",
      icon: "search",
    },
    {
      id: "mylists",
      section: "Lists",
      title: "My Lists",
      subtitle: "Lists you created or saved",
      icon: "list",
    },
    {
      id: "toplists",
      section: "Lists",
      title: "Popular Lists",
      subtitle: "Top public lists by likes",
      icon: "star",
    },
    {
      id: "listsearch",
      section: "Lists",
      title: "Search Lists",
      subtitle: "Find public lists by name",
      icon: "search",
    },
    {
      id: "watchlist",
      section: "You",
      title: "My Watchlist",
      subtitle: "Movies & shows you saved",
      icon: "bookmark",
    },
    {
      id: "upnext",
      section: "You",
      title: "Up Next",
      subtitle: "In-progress shows — next episode to watch",
      icon: "calendar",
    },
    {
      id: "settings",
      section: "Account",
      title: config.apikey ? "MDBList Account" : "Set API Key",
      subtitle: config.apikey
        ? "Manage or replace your API key"
        : "Add your free mdblist.com API key to get started",
      icon: "key",
    },
  ];
}

function renderRoot(rev, text) {
  const q = (text || "").trim().toLowerCase();
  const cmds = buildCommands().filter(
    (c) =>
      !q ||
      c.title.toLowerCase().includes(q) ||
      (c.subtitle || "").toLowerCase().includes(q),
  );
  const items = cmds.map((c) => ({
    id: `cmd:${c.id}`,
    section: c.section,
    title: c.title,
    subtitle: c.subtitle,
    icon: c.icon,
    actions: [{ id: "default", title: "Open", icon: "open" }],
  }));
  setItems(items);
  render(rev, "list", {
    items,
    emptyText: "No matches",
    placeholder: "Search movies, lists, your watchlist…",
    actions: [{ id: "open_site", title: "Open mdblist.com", icon: "open" }],
  });
}

// ── search ───────────────────────────────────────────────────────────────────
function renderSearchScreen(rev, text) {
  const mediaType = top().ctx.mediaType;
  const q = (text || "").trim();
  const hint = mediaType === "any" ? "movies & shows" : `${mediaType}s`;
  if (!q) {
    setItems([]);
    return render(rev, "list", {
      items: [],
      emptyText: "Type to search…",
      placeholder: `Search ${hint}…`,
    });
  }
  loadingFrame(rev, `Searching “${q}”…`);
  debounce(rev, async () => {
    const { data } = await mdb(`/search/${mediaType}`, {
      rawQuery: { query: q, limit: 30 },
    });
    const arr = (data && data.search) || [];
    const items = arr.map((o) => mediaItem(fromSearch(o), "search"));
    setItems(items);
    render(rev, "list", {
      preview: { enabled: true },
      emptyText: "No results",
      placeholder: `Search ${hint}…`,
      items,
    });
  });
}

// ── lists (my lists / popular lists) ────────────────────────────────────────
function renderLists(rev, text, kind) {
  const ctx = top().ctx;
  loadingFrame(
    rev,
    kind === "my" ? "Loading your lists…" : "Loading popular lists…",
  );
  debounce(rev, async () => {
    if (!ctx.loaded) {
      const { data } =
        kind === "my"
          ? await mdb("/lists/user", { rawQuery: { sort: "name" } })
          : await mdb("/lists/top", {});
      ctx.loaded = Array.isArray(data) ? data : [];
    }
    const q = (text || "").trim().toLowerCase();
    const filtered = q
      ? ctx.loaded.filter((l) => (l.name || "").toLowerCase().includes(q))
      : ctx.loaded;
    const items = filtered.map(listItem);
    setItems(items);
    render(rev, "list", {
      emptyText:
        kind === "my" ? "You don't have any lists yet" : "No lists found",
      placeholder: "Filter lists…",
      items,
      actions: [
        {
          id: "refresh",
          title: "Refresh",
          icon: "refresh",
          shortcut: "ctrl+r",
        },
      ],
    });
  });
}

function renderListSearch(rev, text) {
  const q = (text || "").trim();
  if (!q) {
    setItems([]);
    return render(rev, "list", {
      items: [],
      emptyText: "Type to search public lists…",
      placeholder: "Search lists by name…",
    });
  }
  loadingFrame(rev, `Searching lists “${q}”…`);
  debounce(rev, async () => {
    const { data } = await mdb("/lists/search", { rawQuery: { query: q } });
    const items = (Array.isArray(data) ? data : []).map(listItem);
    setItems(items);
    render(rev, "list", {
      emptyText: "No lists found",
      placeholder: "Search lists by name…",
      items,
    });
  });
}

// ── list items (drilled into from My Lists / Popular Lists / Search Lists) ──
async function fetchListPage(
  listid,
  { offset = 0, limit = 100, filterTitle = "" } = {},
) {
  const rawQuery = {
    limit,
    offset,
    append_to_response: "genres,poster,description,ratings",
    sort: "rank",
    order: "asc",
  };
  if (filterTitle) rawQuery.filter_title = filterTitle;
  const { data, headers } = await mdb(`/lists/${listid}/items`, { rawQuery });
  const hasMore = headers.get("x-has-more") === "true";
  const items = [...(data.movies || []), ...(data.shows || [])];
  return { items, hasMore };
}

function renderListItemsScreen(rev, text) {
  const ctx = top().ctx;
  const q = (text || "").trim();
  if (q !== ctx.lastQuery) {
    ctx.offset = 0;
    ctx.loaded = [];
    ctx.lastQuery = q;
  }
  loadingFrame(
    rev,
    ctx.loaded && ctx.loaded.length
      ? "Loading more…"
      : `Loading “${ctx.name}”…`,
  );
  debounce(rev, async () => {
    const { items: page, hasMore } = await fetchListPage(ctx.listid, {
      offset: ctx.offset,
      limit: 100,
      filterTitle: q,
    });
    ctx.loaded = ctx.offset === 0 ? page : ctx.loaded.concat(page);
    ctx.hasMore = hasMore;
    ctx.offset = ctx.loaded.length;
    const items = ctx.loaded.map((o) =>
      mediaItem(fromListItem(o), "listitems"),
    );
    setItems(items);
    render(rev, "list", {
      preview: { enabled: true },
      emptyText: "No items in this list",
      placeholder: `Filter “${ctx.name}”…`,
      hasMore: ctx.hasMore,
      items,
      actions: [
        {
          id: "refresh",
          title: "Refresh",
          icon: "refresh",
          shortcut: "ctrl+r",
        },
      ],
    });
  });
}

// ── watchlist ────────────────────────────────────────────────────────────────
async function fetchWatchlistPage(offset) {
  const { data } = await mdb("/watchlist/items", {
    rawQuery: {
      limit: 200,
      offset,
      append_to_response: "genres,poster,description,ratings",
    },
  });
  const items = [...(data.movies || []), ...(data.shows || [])];
  const hasMore = !!(data.pagination && data.pagination.has_more);
  return { items, hasMore };
}

function renderWatchlistScreen(rev, text) {
  const ctx = top().ctx;
  loadingFrame(rev, ctx.fetched ? "Loading more…" : "Loading watchlist…");
  debounce(rev, async () => {
    if (!ctx.fetched) {
      const { items, hasMore } = await fetchWatchlistPage(0);
      ctx.loaded = items;
      ctx.hasMore = hasMore;
      ctx.offset = items.length;
      ctx.fetched = true;
    }
    const q = (text || "").trim().toLowerCase();
    const filtered = q
      ? ctx.loaded.filter((o) => (o.title || "").toLowerCase().includes(q))
      : ctx.loaded;
    const items = filtered.map((o) => mediaItem(fromListItem(o), "watchlist"));
    setItems(items);
    render(rev, "list", {
      preview: { enabled: true },
      emptyText: "Your watchlist is empty",
      placeholder: "Filter watchlist…",
      hasMore: !q && ctx.hasMore,
      items,
      actions: [
        {
          id: "refresh",
          title: "Refresh",
          icon: "refresh",
          shortcut: "ctrl+r",
        },
      ],
    });
  });
}
async function loadMoreWatchlist(rev) {
  const ctx = top().ctx;
  if (!ctx.hasMore) return renderWatchlistScreen(rev, state.lastText);
  try {
    const { items, hasMore } = await fetchWatchlistPage(ctx.offset);
    ctx.loaded = ctx.loaded.concat(items);
    ctx.offset = ctx.loaded.length;
    ctx.hasMore = hasMore;
    renderWatchlistScreen(rev, state.lastText);
  } catch (err) {
    renderError(rev, err);
  }
}

// ── up next ──────────────────────────────────────────────────────────────────
function renderUpNextScreen(rev, text) {
  const ctx = top().ctx;
  loadingFrame(rev, "Loading calendar…");
  debounce(rev, async () => {
    if (!ctx.loaded) {
      const { data } = await mdb("/upnext", { rawQuery: { limit: 50 } });
      ctx.loaded = (data && data.items) || [];
    }
    const q = (text || "").trim().toLowerCase();
    const filtered = q
      ? ctx.loaded.filter((u) =>
          ((u.show && u.show.title) || "").toLowerCase().includes(q),
        )
      : ctx.loaded;
    const items = filtered.map(upNextItem);
    setItems(items);
    render(rev, "list", {
      preview: { enabled: true },
      emptyText: "Nothing in progress",
      placeholder: "Filter shows…",
      items,
      actions: [
        {
          id: "refresh",
          title: "Refresh",
          icon: "refresh",
          shortcut: "ctrl+r",
        },
      ],
    });
  });
}

// ── settings / API key ───────────────────────────────────────────────────────
function renderSetup(rev, error) {
  render(rev, "form", {
    form: {
      title: "MDBList API Key",
      submitLabel: "Save",
      fields: [
        {
          id: "apikey",
          type: "password",
          label: "API Key",
          value: config.apikey || "",
          placeholder: "Paste your key…",
          required: true,
          description:
            "Free — grab one from mdblist.com/preferences (Ctrl+K below opens the page).",
          error: error || undefined,
        },
      ],
    },
    actions: [
      { id: "open_prefs", title: "Open mdblist.com Preferences", icon: "open" },
    ],
  });
}
async function handleSetupSubmit(values) {
  const key = ((values && values.apikey) || "").trim();
  if (!key) return renderSetup(0, "API key is required");
  try {
    const { data } = await mdb("/user", { overrideApikey: key });
    config.apikey = key;
    config.username = data.username || data.name || "";
    storageSet("apikey", key, true);
    cmdToast(
      `Connected to mdblist.com${config.username ? ` as ${config.username}` : ""}`,
    );
    return resetToRoot();
  } catch (err) {
    return renderSetup(0, `Could not verify key: ${err.message}`);
  }
}

// ── screen dispatcher ────────────────────────────────────────────────────────
async function renderScreen(rev, text) {
  await ensureConfigLoaded();
  if (!config.apikey && top().screen !== "settings") return renderSetup(rev);
  try {
    switch (top().screen) {
      case "root":
        return renderRoot(rev, text);
      case "search":
        return renderSearchScreen(rev, text);
      case "mylists":
        return renderLists(rev, text, "my");
      case "toplists":
        return renderLists(rev, text, "top");
      case "listsearch":
        return renderListSearch(rev, text);
      case "listitems":
        return renderListItemsScreen(rev, text);
      case "watchlist":
        return renderWatchlistScreen(rev, text);
      case "upnext":
        return renderUpNextScreen(rev, text);
      case "settings":
        return renderSetup(rev);
      default:
        return renderRoot(rev, text);
    }
  } catch (err) {
    renderError(rev, err);
  }
}

// ── actions ──────────────────────────────────────────────────────────────────
async function handleMediaAction(it, action, screenKind) {
  const iu = imdbUrl(it.ids);
  const tu = tmdbUrl(it.ids, it.mediatype);
  switch (action) {
    case "default":
      if (iu) cmdOpen(iu);
      else if (tu) cmdOpen(tu);
      return cmdHide();
    case "open_tmdb":
      if (tu) cmdOpen(tu);
      return cmdHide();
    case "copy_title":
      return cmdCopy(it.title || "");
    case "copy_imdb":
      return cmdCopy(it.ids.imdb || "");
    case "add_watchlist": {
      const body =
        it.mediatype === "show"
          ? { shows: [idsBody(it.ids)] }
          : { movies: [idsBody(it.ids)] };
      await mdb("/watchlist/items/add", { method: "POST", body });
      return cmdToast(`Added “${it.title}” to watchlist`);
    }
    case "remove_watchlist": {
      const body =
        it.mediatype === "show"
          ? { shows: [idsBody(it.ids)] }
          : { movies: [idsBody(it.ids)] };
      await mdb("/watchlist/items/remove", { method: "POST", body });
      cmdToast(`Removed “${it.title}” from watchlist`);
      if (top().screen === "watchlist" && top().ctx.loaded) {
        top().ctx.loaded = top().ctx.loaded.filter((o) => {
          const oids = {
            imdb: o.imdb_id || (o.ids && o.ids.imdb),
            tmdb: o.ids && o.ids.tmdb,
          };
          return !(
            (oids.imdb && oids.imdb === it.ids.imdb) ||
            (oids.tmdb && oids.tmdb === it.ids.tmdb)
          );
        });
        return renderScreen(0, state.lastText);
      }
      return;
    }
    default:
      if (iu) cmdOpen(iu);
      return cmdHide();
  }
}

async function handleAction(id, action) {
  if (!id) {
    if (action === "open_prefs") return cmdOpen(PREFS_URL);
    if (action === "open_site") return cmdOpen(SITE);
    if (action === "refresh") {
      const ctx = top().ctx;
      if (top().screen === "listitems") {
        ctx.offset = 0;
        ctx.loaded = [];
        ctx.lastQuery = undefined;
      } else if (top().screen === "watchlist") {
        ctx.fetched = false;
        ctx.loaded = [];
        ctx.offset = 0;
      } else {
        ctx.loaded = null;
      }
      return renderScreen(0, state.lastText);
    }
    return;
  }
  if (id.startsWith("cmd:")) {
    return push(id.slice(4));
  }
  if (id.startsWith("list:")) {
    const item = state.itemsById[id];
    const l = item && item._list;
    if (!l) return;
    if (action === "open_web")
      return cmdOpen(`${SITE}/lists/${l.user_name}/${l.slug}/`);
    return push("listitems", {
      listid: l.id,
      username: l.user_name,
      listname: l.slug,
      name: l.name,
      mediatype: l.mediatype,
    });
  }
  if (id.startsWith("upnext:")) {
    const item = state.itemsById[id];
    const show = item && item._show;
    if (!show) return;
    if (action === "copy_title") return cmdCopy(show.title || "");
    const tu =
      show.ids && show.ids.tmdb
        ? `https://www.themoviedb.org/tv/${show.ids.tmdb}`
        : null;
    if (tu) cmdOpen(tu);
    return cmdHide();
  }
  if (id.startsWith("media:")) {
    const item = state.itemsById[id];
    const it = item && item._data;
    if (!it) return;
    return handleMediaAction(it, action, top().screen);
  }
}

// ── stdin loop ───────────────────────────────────────────────────────────────
let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  let idx;
  while ((idx = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, idx).trim();
    buffer = buffer.slice(idx + 1);
    if (line) handleLine(line);
  }
});
process.stdin.on("end", () => process.exit(0));

async function handleLine(line) {
  let msg;
  try {
    msg = JSON.parse(line);
  } catch (_) {
    return;
  }
  switch (msg.type) {
    case "close":
      process.exit(0);
      break;
    case "init":
      state.lastRev = msg.rev || 0;
      state.lastText = msg.query != null ? msg.query : "";
      await renderScreen(state.lastRev, state.lastText);
      break;
    case "query":
      state.lastRev = msg.rev || 0;
      state.lastText = msg.text != null ? msg.text : "";
      await renderScreen(state.lastRev, state.lastText);
      break;
    case "action":
      try {
        await handleAction(msg.id || "", msg.action || "default");
      } catch (err) {
        cmdToast(`Error: ${err.message}`, "error");
      }
      break;
    case "submit":
      try {
        await handleSetupSubmit(msg.values || {});
      } catch (err) {
        cmdToast(`Error: ${err.message}`, "error");
      }
      break;
    case "loadMore":
      try {
        if (top().screen === "listitems")
          await renderListItemsScreen(msg.rev, state.lastText);
        else if (top().screen === "watchlist") await loadMoreWatchlist(msg.rev);
      } catch (err) {
        renderError(msg.rev, err);
      }
      break;
    case "storage": {
      const resolve = storageRequests.get(msg.requestId);
      if (resolve) {
        storageRequests.delete(msg.requestId);
        resolve(msg.value);
      }
      break;
    }
    case "back":
      await popScreen();
      break;
    // 'select' / 'tab' unused — previews are provided per item.
  }
}
