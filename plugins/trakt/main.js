#!/usr/bin/env node
/*
 * Trakt.tv plugin for the Tabame launcher.
 *
 * Runs as a long-lived child process speaking the launcher's newline-delimited
 * JSON protocol (see ../TABAME_PLUGIN_SKILL.md). The launcher exposes a single
 * query line, so this plugin is an internal state machine: a root command list
 * that drills into each command's own screen. Sub-screens set canGoBack, so
 * Escape pops back to the root instead of tearing down the whole plugin.
 *
 * Runtime: Node 18+ (global fetch) or Bun. Plain JS, no dependencies.
 *
 * Setup is handled by an in-app form. Register a free API app at
 * https://trakt.tv/oauth/applications with redirect URI
 * `urn:ietf:wg:oauth:2.0:oob`, then paste its Client ID + Secret into Tabame.
 * `tmdbApiKey` is optional (free TMDB v3 key) — with it, browse/search show
 * poster thumbnails; without it they fall back to icons.
 */

"use strict";

const fs = require("fs");
const path = require("path");

const TRAKT_API = "https://api.trakt.tv";
const TRAKT_APPS_URL = "https://trakt.tv/oauth/applications";
const TMDB_API = "https://api.themoviedb.org/3";
const TMDB_IMG = "https://image.tmdb.org/t/p";
const OOB = "urn:ietf:wg:oauth:2.0:oob";
// api.trakt.tv is behind Cloudflare, which blocks requests with no/default
// User-Agent (what Node's fetch sends) with a bot challenge. Send a real one.
const USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";

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
const cmdToast = (t) => command("toast", { text: t });
const cmdHide = () => command("hide");
const cmdSetQuery = (t) => command("setQuery", { text: t });
const storageRequests = new Map();
let storageRequestId = 0;

function storageGet(key, secret = false) {
  return new Promise((resolve) => {
    const requestId = `trakt-storage-${++storageRequestId}`;
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
  if (err && err.status === 401 && !session.access_token) {
    return renderNeedLogin(rev);
  }
  render(rev, "detail", {
    detail: { markdown: `## Trakt error\n\n\`\`\`\n${msg}\n\`\`\`` },
  });
}

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// ── config / auth ────────────────────────────────────────────────────────────
function loadConfig() {
  const cfg = {
    clientId: process.env.TRAKT_CLIENT_ID || "",
    clientSecret: process.env.TRAKT_CLIENT_SECRET || "",
    tmdbApiKey: process.env.TMDB_API_KEY || "",
  };
  try {
    const file = path.join(process.cwd(), "config.json");
    if (fs.existsSync(file)) {
      const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
      if (parsed.clientId) cfg.clientId = parsed.clientId;
      if (parsed.clientSecret) cfg.clientSecret = parsed.clientSecret;
      if (parsed.tmdbApiKey) cfg.tmdbApiKey = parsed.tmdbApiKey;
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
  configReady = Promise.all([
    storageGet("clientId"),
    storageGet("clientSecret", true),
    storageGet("tmdbApiKey", true),
  ]).then(([clientId, clientSecret, tmdbApiKey]) => {
    // Stored form values take precedence, while env/config.json remain a
    // backwards-compatible migration path for existing installs.
    if (typeof clientId === "string" && clientId) config.clientId = clientId;
    if (typeof clientSecret === "string" && clientSecret)
      config.clientSecret = clientSecret;
    if (typeof tmdbApiKey === "string") config.tmdbApiKey = tmdbApiKey;
  });
  return configReady;
}
const hasPosters = () => !!config.tmdbApiKey;

// OAuth tokens live in their own file so we never rewrite the user's config.
const TOKENS_FILE = path.join(process.cwd(), "tokens.json");
function loadTokens() {
  try {
    if (fs.existsSync(TOKENS_FILE))
      return JSON.parse(fs.readFileSync(TOKENS_FILE, "utf8"));
  } catch (err) {
    log("tokens:", err.message);
  }
  return {};
}
let session = loadTokens(); // { access_token, refresh_token, expires_at }
const isAuthed = () => !!session.access_token;

function saveTokens(tok) {
  session = {
    access_token: tok.access_token,
    refresh_token: tok.refresh_token,
    expires_at: Date.now() + (Number(tok.expires_in) || 7776000) * 1000,
  };
  try {
    fs.writeFileSync(TOKENS_FILE, JSON.stringify(session, null, 2));
  } catch (err) {
    log("saveTokens:", err.message);
  }
}
function clearTokens() {
  session = {};
  try {
    if (fs.existsSync(TOKENS_FILE)) fs.unlinkSync(TOKENS_FILE);
  } catch (err) {
    log("clearTokens:", err.message);
  }
}

// ── HTTP ─────────────────────────────────────────────────────────────────────
async function ensureToken() {
  if (!session.access_token) throw new HttpError(401, "Not logged in");
  // Refresh a minute before expiry.
  if (
    session.expires_at &&
    Date.now() > session.expires_at - 60000 &&
    session.refresh_token
  ) {
    const res = await fetch(`${TRAKT_API}/oauth/token`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "User-Agent": USER_AGENT },
      body: JSON.stringify({
        refresh_token: session.refresh_token,
        client_id: config.clientId,
        client_secret: config.clientSecret,
        redirect_uri: OOB,
        grant_type: "refresh_token",
      }),
    });
    if (res.ok) {
      saveTokens(await res.json());
    } else {
      clearTokens();
      throw new HttpError(401, "Trakt session expired — please log in again");
    }
  }
}

async function trakt(
  apiPath,
  { method = "GET", body = null, authed = false } = {},
) {
  if (authed) await ensureToken();
  const headers = {
    "Content-Type": "application/json",
    "User-Agent": USER_AGENT,
    "trakt-api-version": "2",
    "trakt-api-key": config.clientId,
  };
  if (authed) headers.Authorization = `Bearer ${session.access_token}`;
  const res = await fetch(TRAKT_API + apiPath, {
    method,
    headers,
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
      (data && (data.error_description || data.error)) ||
      (typeof data === "string" && data) ||
      `HTTP ${res.status}`;
    throw new HttpError(res.status, detail);
  }
  return data;
}

// ── TMDB posters (optional) ──────────────────────────────────────────────────
const posterCache = new Map(); // `${type}:${tmdbId}` -> poster_path | null
async function posterPath(mediaType, tmdbId) {
  if (!config.tmdbApiKey || !tmdbId) return null;
  const key = `${mediaType}:${tmdbId}`;
  if (posterCache.has(key)) return posterCache.get(key);
  try {
    const kind = mediaType === "show" ? "tv" : "movie";
    const res = await fetch(
      `${TMDB_API}/${kind}/${tmdbId}?api_key=${encodeURIComponent(config.tmdbApiKey)}`,
      { headers: { "User-Agent": USER_AGENT } },
    );
    if (!res.ok) {
      posterCache.set(key, null);
      return null;
    }
    const j = await res.json();
    const p = j.poster_path || null;
    posterCache.set(key, p);
    return p;
  } catch (err) {
    posterCache.set(key, null);
    return null;
  }
}
function imgUrl(p, size) {
  return p ? `${TMDB_IMG}/${size}${p}` : null;
}
async function attachPosters(medias) {
  if (!config.tmdbApiKey) return;
  await Promise.all(
    medias.map(async (m) => {
      m._posterPath = await posterPath(
        m.mediaType,
        m.obj.ids && m.obj.ids.tmdb,
      );
    }),
  );
}

// ── media normalization ──────────────────────────────────────────────────────
// Every source (search / trending / watchlist / history / calendar) is folded
// into a common { mediaType, obj, extra } shape so one item builder handles all.
function toMedia(mediaType, obj, extra) {
  return { mediaType, obj: obj || {}, extra: extra || {} };
}

function fmtNum(n) {
  n = Number(n) || 0;
  if (n >= 1e6) return (n / 1e6).toFixed(1).replace(/\.0$/, "") + "M";
  if (n >= 1e3) return (n / 1e3).toFixed(1).replace(/\.0$/, "") + "k";
  return String(n);
}
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

function traktWebUrl(m) {
  const seg = m.mediaType === "show" ? "shows" : "movies";
  const ids = m.obj.ids || {};
  return `https://trakt.tv/${seg}/${ids.slug || ids.trakt || ""}`;
}
function tmdbWebUrl(m) {
  const seg = m.mediaType === "show" ? "tv" : "movie";
  const ids = m.obj.ids || {};
  return ids.tmdb ? `https://www.themoviedb.org/${seg}/${ids.tmdb}` : null;
}
function imdbWebUrl(m) {
  const ids = m.obj.ids || {};
  return ids.imdb ? `https://www.imdb.com/title/${ids.imdb}/` : null;
}

function mediaPreview(m) {
  const o = m.obj;
  const isShow = m.mediaType === "show";
  const md = [];
  // const big = imgUrl(m._posterPath, 'w500');
  // if (big) md.push(`![poster](${big})`, '');
  md.push(`## ${o.title || "Untitled"}${o.year ? ` (${o.year})` : ""}`);
  if (o.tagline) md.push("", `*${o.tagline}*`);
  if (o.overview) md.push("", o.overview);

  const meta = [];
  meta.push({
    label: "Type",
    text: isShow ? "TV Show" : "Movie",
    icon: "video",
  });
  if (o.year) meta.push({ label: "Year", text: String(o.year) });
  if (o.rating)
    meta.push({
      label: "Rating",
      text: `★ ${Number(o.rating).toFixed(1)}${o.votes ? `  ·  ${fmtNum(o.votes)} votes` : ""}`,
      color: "#F5C518",
    });
  if (o.runtime) meta.push({ label: "Runtime", text: `${o.runtime} min` });
  if (o.genres && o.genres.length)
    meta.push({ label: "Genres", text: o.genres.slice(0, 4).join(", ") });
  if (o.certification) meta.push({ label: "Rated", text: o.certification });
  if (isShow && o.status) meta.push({ label: "Status", text: o.status });
  if (isShow && o.network) meta.push({ label: "Network", text: o.network });
  if (o.language)
    meta.push({ label: "Language", text: String(o.language).toUpperCase() });

  const ex = m.extra || {};
  if (ex.episode)
    meta.push({
      label: "Episode",
      text: `S${pad2(ex.episode.season)}E${pad2(ex.episode.number)}${ex.episode.title ? ` · ${ex.episode.title}` : ""}`,
    });
  if (ex.watchers)
    meta.push({ label: "Watchers", text: fmtNum(ex.watchers), icon: "person" });
  if (ex.rank) meta.push({ label: "List rank", text: `#${ex.rank}` });
  if (ex.watched_at)
    meta.push({
      label: "Watched",
      text: fmtDate(ex.watched_at),
      icon: "clock",
    });
  if (ex.first_aired)
    meta.push({
      label: "Airs",
      text: fmtDateTime(ex.first_aired),
      icon: "calendar",
    });

  meta.push({ separator: true });
  meta.push({
    label: "Trakt",
    text: "trakt.tv",
    url: traktWebUrl(m),
    icon: "link",
  });
  const imdb = imdbWebUrl(m);
  if (imdb)
    meta.push({ label: "IMDb", text: (o.ids && o.ids.imdb) || "", url: imdb });
  const tmdb = tmdbWebUrl(m);
  if (tmdb) meta.push({ label: "TMDB", text: String(o.ids.tmdb), url: tmdb });

  return { markdown: md.join("\n"), metadata: meta };
}

function mediaActions(m) {
  const a = [{ id: "default", title: "Open on Trakt", icon: "open" }];
  if (imdbWebUrl(m))
    a.push({ id: "open_imdb", title: "Open on IMDb", icon: "link" });
  a.push({ id: "copy_title", title: "Copy Title", icon: "copy" });
  if (isAuthed()) {
    if (top().screen === "watchlist")
      a.push({
        id: "remove_watchlist",
        title: "Remove from Watchlist",
        icon: "remove",
      });
    else
      a.push({ id: "add_watchlist", title: "Add to Watchlist", icon: "add" });
    a.push({ id: "mark_watched", title: "Mark as Watched", icon: "check" });
  }
  return a;
}

function mediaItem(m) {
  const o = m.obj;
  const isShow = m.mediaType === "show";
  const id = `media:${m.mediaType}:${(o.ids && o.ids.trakt) || o.title}`;
  const small = imgUrl(m._posterPath, "w342");

  const acc = [
    { text: isShow ? "TV" : "FILM", color: isShow ? "#8B5CF6" : "#0EA5E9" },
  ];
  if (o.rating)
    acc.push({ text: `★ ${Number(o.rating).toFixed(1)}`, color: "#F5C518" });
  const ex = m.extra || {};
  if (ex.watchers)
    acc.push({ text: `${fmtNum(ex.watchers)} watching`, icon: "person" });
  if (ex.rank) acc.push({ text: `#${ex.rank}` });

  const sub = [];
  if (ex.episode)
    sub.push(`S${pad2(ex.episode.season)}E${pad2(ex.episode.number)}`);
  if (o.year) sub.push(String(o.year));
  if (o.genres && o.genres.length) sub.push(o.genres.slice(0, 3).join(", "));
  else if (o.runtime) sub.push(`${o.runtime} min`);
  if (ex.first_aired) sub.push(fmtDateTime(ex.first_aired));
  if (ex.watched_at) sub.push(`watched ${fmtDate(ex.watched_at)}`);

  const it = {
    id,
    title: o.title || "Untitled",
    subtitle: sub.join("  ·  "),
    icon: small || (isShow ? "video" : "play"),
    accessories: acc,
    actions: mediaActions(m),
    preview: mediaPreview(m),
    _data: m,
  };
  return it;
}

function filterMedia(list, text) {
  const q = (text || "").trim().toLowerCase();
  if (!q) return list;
  return list.filter(
    (m) =>
      (m.obj.title || "").toLowerCase().includes(q) ||
      String(m.obj.year || "").includes(q) ||
      (m.obj.genres || []).some((g) => String(g).toLowerCase().includes(q)),
  );
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
function push(screen, ctx) {
  cancelSearch();
  top().savedQuery = state.lastText;
  state.stack.push({ screen, ctx: ctx || {}, savedQuery: "" });
  cmdSetQuery("");
  return renderScreen(0, "");
}
function popScreen() {
  cancelSearch();
  if (top().screen === "login") stopLogin();
  if (state.stack.length > 1) state.stack.pop();
  const q = top().savedQuery || "";
  cmdSetQuery(q);
  return renderScreen(0, q);
}
function resetToRoot() {
  cancelSearch();
  stopLogin();
  state.stack = [{ screen: "root", ctx: {}, savedQuery: "" }];
  cmdSetQuery("");
  return renderScreen(0, "");
}

// Debounce for screens that hit the search API on every keystroke.
let searchTimer = null;
function cancelSearch() {
  if (searchTimer) clearTimeout(searchTimer);
  searchTimer = null;
}
function debounceSearch(rev, fn) {
  cancelSearch();
  const frame = top();
  searchTimer = setTimeout(() => {
    searchTimer = null;
    if (top() !== frame) return; // user navigated away
    fn().catch((err) => renderError(rev, err));
  }, 350);
}

// ── root / commands ──────────────────────────────────────────────────────────
function buildCommands() {
  const cmds = [
    {
      id: "search_all",
      section: "Search",
      title: "Search Movies & Shows",
      subtitle: "Search everything on Trakt",
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
      id: "trending_movies",
      section: "Discover",
      title: "Trending Movies",
      subtitle: "What people are watching now",
      icon: "bolt",
    },
    {
      id: "trending_shows",
      section: "Discover",
      title: "Trending Shows",
      subtitle: "What people are watching now",
      icon: "bolt",
    },
    {
      id: "popular_movies",
      section: "Discover",
      title: "Popular Movies",
      subtitle: "Most popular of all time",
      icon: "star",
    },
    {
      id: "popular_shows",
      section: "Discover",
      title: "Popular Shows",
      subtitle: "Most popular of all time",
      icon: "star",
    },
  ];
  if (isAuthed()) {
    cmds.push(
      {
        id: "watchlist",
        section: "You",
        title: "My Watchlist",
        subtitle: "Movies & shows you saved",
        icon: "bookmark",
      },
      {
        id: "history",
        section: "You",
        title: "Watched History",
        subtitle: "Recently watched",
        icon: "clock",
      },
      {
        id: "up_next",
        section: "You",
        title: "Up Next",
        subtitle: "Upcoming episodes (next 14 days)",
        icon: "calendar",
      },
      {
        id: "account",
        section: "Account",
        title: "Account",
        subtitle: "Your Trakt profile",
        icon: "person",
      },
      {
        id: "logout",
        section: "Account",
        title: "Log out",
        subtitle: "Sign out of Trakt",
        icon: "lock",
      },
    );
  } else {
    cmds.push({
      id: "login",
      section: "Account",
      title: "Log in to Trakt",
      subtitle: "Enable your watchlist, history & calendar",
      icon: "key",
    });
  }
  cmds.push({
    id: "setup",
    section: "Account",
    title: "Trakt API Settings",
    subtitle: "Edit Client ID, Client Secret & optional TMDB key",
    icon: "settings",
  });
  return cmds;
}

function renderRoot(rev, text) {
  const q = (text || "").toLowerCase();
  const items = buildCommands()
    .filter(
      (c) =>
        !q ||
        c.title.toLowerCase().includes(q) ||
        c.subtitle.toLowerCase().includes(q),
    )
    .map((c) => ({
      id: `cmd:${c.id}`,
      title: c.title,
      subtitle: c.subtitle,
      icon: c.icon,
      section: c.section,
      actions: [{ id: "default", title: "Open", icon: "open" }],
    }));
  setItems(items);
  render(rev, "list", {
    items,
    emptyText: "No matching commands",
    placeholder: "Trakt — search or pick a command…",
  });
}

// ── media screens (browse + search) ──────────────────────────────────────────
function renderMediaFrame(rev, medias, opts) {
  const items = medias.map(mediaItem);
  setItems(items);
  const view = hasPosters() ? "grid" : "list";
  const frame = {
    items,
    preview: { enabled: true },
    emptyText: (opts && opts.emptyText) || "No results",
  };
  if (opts && opts.placeholder) frame.placeholder = opts.placeholder;
  // Poster wall: 4 columns, tile a touch taller than 2:3 to fit the caption.
  if (view === "grid") frame.grid = { columns: 4, aspectRatio: 0.6 };
  render(rev, view, frame);
}

// Browse screens fetch once, cache in the stack frame, then filter client-side.
async function renderBrowse(rev, text, fetcher, opts) {
  const frame = top();
  if (frame.ctx.data) {
    return renderMediaFrame(rev, filterMedia(frame.ctx.data, text), opts);
  }
  if (frame.ctx.loading)
    return loadingFrame(rev, (opts && opts.loadingText) || "Loading…");
  frame.ctx.loading = true;
  loadingFrame(rev, (opts && opts.loadingText) || "Loading…");
  try {
    const data = await fetcher();
    await attachPosters(data);
    frame.ctx.data = data;
  } catch (err) {
    frame.ctx.loading = false;
    if (top() === frame) renderError(rev, err);
    return;
  }
  frame.ctx.loading = false;
  // Render against the latest query — the awaited fetch may be stale by `rev`.
  if (top() === frame)
    renderMediaFrame(
      state.lastRev,
      filterMedia(frame.ctx.data, state.lastText),
      opts,
    );
}

function renderSearch(rev, text, endpoint, opts) {
  const term = (text || "").trim();
  if (!term) {
    setItems([]);
    return render(rev, "list", {
      items: [],
      empty: {
        icon: "search",
        title: "Search Trakt",
        hint: (opts && opts.hint) || "Type a title…",
      },
      placeholder: (opts && opts.placeholder) || "Search…",
    });
  }
  loadingFrame(rev, "Searching…");
  debounceSearch(rev, async () => {
    const raw = await trakt(
      `/search/${endpoint}?query=${encodeURIComponent(term)}&extended=full&limit=25`,
    );
    const medias = (raw || [])
      .map((r) =>
        r.movie
          ? toMedia("movie", r.movie)
          : r.show
            ? toMedia("show", r.show)
            : null,
      )
      .filter(Boolean);
    await attachPosters(medias);
    renderMediaFrame(rev, medias, opts);
  });
}

// Fetchers -------------------------------------------------------------------
async function fetchTrending(kind) {
  const raw = await trakt(`/${kind}/trending?extended=full&limit=25`);
  const type = kind === "shows" ? "show" : "movie";
  return (raw || []).map((r) =>
    toMedia(type, r[type], { watchers: r.watchers }),
  );
}
async function fetchPopular(kind) {
  const raw = await trakt(`/${kind}/popular?extended=full&limit=25`);
  const type = kind === "shows" ? "show" : "movie";
  return (raw || []).map((o) => toMedia(type, o));
}
async function fetchWatchlist() {
  const raw = await trakt("/sync/watchlist?extended=full", { authed: true });
  return (raw || [])
    .filter((r) => r.type === "movie" || r.type === "show")
    .map((r) => toMedia(r.type, r[r.type], { rank: r.rank }));
}
async function fetchHistory() {
  const raw = await trakt("/sync/history?limit=40&extended=full", {
    authed: true,
  });
  return (raw || [])
    .filter(
      (r) => r.type === "movie" || r.type === "show" || r.type === "episode",
    )
    .map((r) => {
      if (r.type === "episode")
        return toMedia("show", r.show, {
          watched_at: r.watched_at,
          episode: r.episode,
        });
      return toMedia(r.type, r[r.type], { watched_at: r.watched_at });
    });
}
async function fetchUpNext() {
  const today = new Date().toISOString().slice(0, 10);
  const raw = await trakt(`/calendars/my/shows/${today}/14?extended=full`, {
    authed: true,
  });
  return (raw || []).map((r) =>
    toMedia("show", r.show, { first_aired: r.first_aired, episode: r.episode }),
  );
}

// ── login (OAuth device flow) ────────────────────────────────────────────────
const login = {
  active: false,
  userCode: "",
  url: "",
  deviceCode: "",
  interval: 5,
  expiresAt: 0,
  timer: null,
  status: "idle",
  error: "",
};
function stopLogin() {
  if (login.timer) clearTimeout(login.timer);
  login.timer = null;
  login.active = false;
}

async function startLogin() {
  if (!config.clientSecret) {
    login.status = "no-secret";
    return renderLogin(0);
  }
  try {
    const d = await trakt("/oauth/device/code", {
      method: "POST",
      body: { client_id: config.clientId },
    });
    login.active = true;
    login.userCode = d.user_code;
    login.url = d.verification_url || "https://trakt.tv/activate";
    login.deviceCode = d.device_code;
    login.interval = d.interval || 5;
    login.expiresAt = Date.now() + (d.expires_in || 600) * 1000;
    login.status = "waiting";
    login.error = "";
    scheduleLoginPoll();
    renderLogin(0);
  } catch (err) {
    login.status = "error";
    login.error = err.message;
    renderLogin(0);
  }
}
function scheduleLoginPoll() {
  if (login.timer) clearTimeout(login.timer);
  login.timer = setTimeout(pollLogin, Math.max(1, login.interval) * 1000);
}
async function pollLogin() {
  if (!login.active) return;
  if (Date.now() > login.expiresAt) {
    stopLogin();
    login.status = "expired";
    return renderLogin(0);
  }
  try {
    const res = await fetch(`${TRAKT_API}/oauth/device/token`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "User-Agent": USER_AGENT },
      body: JSON.stringify({
        code: login.deviceCode,
        client_id: config.clientId,
        client_secret: config.clientSecret,
      }),
    });
    if (res.status === 200) {
      saveTokens(await res.json());
      stopLogin();
      login.status = "done";
      cmdToast("Logged into Trakt");
      return resetToRoot();
    }
    if (res.status === 400) return scheduleLoginPoll(); // authorization pending
    if (res.status === 429) {
      login.interval += 1; // slow down
      return scheduleLoginPoll();
    }
    // 404 not found · 409 already used · 410 expired · 418 denied
    stopLogin();
    login.status =
      res.status === 410 ? "expired" : res.status === 418 ? "denied" : "error";
    login.error = `HTTP ${res.status}`;
    renderLogin(0);
  } catch (err) {
    scheduleLoginPoll(); // transient network error — keep polling
  }
}

function renderLogin(rev) {
  if (!config.clientSecret) {
    return renderSetup(rev, "A Client Secret is required to log in");
  }

  let statusLine = "Waiting for you to authorize…";
  if (login.status === "expired")
    statusLine = "Code expired — press Enter on “Restart” to try again.";
  else if (login.status === "denied") statusLine = "Authorization was denied.";
  else if (login.status === "error") statusLine = `Error: ${login.error}`;

  const items = [];
  if (login.status === "waiting") {
    items.push({
      id: "login:open",
      title: `Your code:  ${login.userCode || "…"}`,
      subtitle: `Enter to open ${login.url}  ·  ${statusLine}`,
      icon: "globe",
      accessories: [{ text: "waiting", color: "#F5C518" }],
      actions: [
        { id: "default", title: "Open activation page", icon: "open" },
        { id: "copy_code", title: "Copy code", icon: "copy" },
      ],
      preview: {
        markdown: [
          "## Log in to Trakt",
          "",
          `1. Open **[${login.url}](${login.url})**`,
          `2. Enter the code:  **\`${login.userCode}\`**`,
          "3. Approve the app — this screen updates automatically.",
        ].join("\n"),
      },
    });
  } else {
    items.push({
      id: "login:restart",
      title: "Restart login",
      subtitle: statusLine,
      icon: "refresh",
      actions: [{ id: "default", title: "Restart", icon: "refresh" }],
    });
  }
  setItems(items);
  render(rev, "list", { items, placeholder: "Authorizing with Trakt…" });
}

function renderNeedLogin(rev) {
  render(rev, "detail", {
    detail: {
      markdown: [
        "## Not logged in",
        "",
        "This needs a Trakt login. Go back and run **Log in to Trakt** first.",
      ].join("\n"),
    },
  });
}

async function renderAccount(rev) {
  loadingFrame(rev, "Loading profile…");
  const data = await trakt("/users/settings", { authed: true });
  const u = (data && data.user) || {};
  render(rev, "detail", {
    detail: {
      markdown: [
        `## ${u.name || u.username || "Trakt user"}`,
        "",
        "You are logged in.",
      ].join("\n"),
      metadata: [
        { label: "Username", text: u.username || "—", icon: "person" },
        { label: "VIP", text: u.vip ? "Yes" : "No" },
        { label: "Private", text: u.private ? "Yes" : "No" },
        { separator: true },
        {
          label: "Profile",
          text: "trakt.tv",
          url: u.username
            ? `https://trakt.tv/users/${u.username}`
            : "https://trakt.tv",
        },
      ],
    },
  });
}

// ── screen dispatch ──────────────────────────────────────────────────────────
function renderSetup(rev, note = "") {
  render(rev, "form", {
    actions: [
      {
        id: "open_trakt_apps",
        title: "Open Trakt API Applications",
        icon: "open",
      },
    ],
    form: {
      title: note ? `Trakt setup — ${note}` : "Connect Trakt",
      buttons: [
        { id: "save", label: "Save & Log in" },
        { id: "copy_url", label: "Copy URL" },
        { id: "copy_uri", label: "Copy URI" },
      ],
      fields: [
        {
          id: "clientId",
          type: "text",
          label: "Trakt Client ID",
          placeholder: "Paste the Client ID from your Trakt API app",
          value: config.clientId || "",
          description:
            "Create an app at trakt.tv/oauth/applications with redirect URI urn:ietf:wg:oauth:2.0:oob.",
        },
        {
          id: "clientSecret",
          type: "password",
          label: "Trakt Client Secret",
          placeholder: "Paste the Client Secret",
          value: config.clientSecret || "",
          description: "Stored securely in Windows Credential Manager.",
        },
        {
          id: "tmdbApiKey",
          type: "password",
          label: "TMDB v3 API Key (optional)",
          placeholder: "Adds poster artwork to results",
          value: config.tmdbApiKey || "",
          description: "Leave empty to use icon-based results.",
        },
      ],
    },
  });
}

async function submitSetup(values) {
  const clientId = String(values.clientId || "").trim();
  const clientSecret = String(values.clientSecret || "").trim();
  const tmdbApiKey = String(values.tmdbApiKey || "").trim();
  if (!clientId || !clientSecret) {
    return renderSetup(0, "Client ID and Client Secret are required");
  }

  config.clientId = clientId;
  config.clientSecret = clientSecret;
  config.tmdbApiKey = tmdbApiKey;
  posterCache.clear();
  storageSet("clientId", clientId);
  storageSet("clientSecret", clientSecret, true);
  storageSet("tmdbApiKey", tmdbApiKey, true);
  cmdToast("Trakt credentials saved securely");

  stopLogin();
  login.status = "idle";
  state.stack = [
    { screen: "root", ctx: {}, savedQuery: "" },
    { screen: "login", ctx: {}, savedQuery: "" },
  ];
  cmdSetQuery("");
  return startLogin();
}

function handleSetupSubmit(values, button) {
  if (button === "copy_url") return cmdCopy(TRAKT_APPS_URL);
  if (button === "copy_uri") return cmdCopy(OOB);
  return submitSetup(values);
}

async function renderScreen(rev, text) {
  await ensureConfigLoaded();
  if (!config.clientId) return renderSetup(rev);
  try {
    switch (top().screen) {
      case "root":
        return renderRoot(rev, text);
      case "search_all":
        return renderSearch(rev, text, "movie,show", {
          emptyText: "No results",
          hint: "Type a movie or show…",
          placeholder: "Search movies & shows…",
        });
      case "search_movies":
        return renderSearch(rev, text, "movie", {
          emptyText: "No movies",
          hint: "Type a movie title…",
          placeholder: "Search movies…",
        });
      case "search_shows":
        return renderSearch(rev, text, "show", {
          emptyText: "No shows",
          hint: "Type a show title…",
          placeholder: "Search shows…",
        });
      case "trending_movies":
        return renderBrowse(rev, text, () => fetchTrending("movies"), {
          loadingText: "Loading trending movies…",
          placeholder: "Filter trending movies…",
        });
      case "trending_shows":
        return renderBrowse(rev, text, () => fetchTrending("shows"), {
          loadingText: "Loading trending shows…",
          placeholder: "Filter trending shows…",
        });
      case "popular_movies":
        return renderBrowse(rev, text, () => fetchPopular("movies"), {
          loadingText: "Loading popular movies…",
          placeholder: "Filter popular movies…",
        });
      case "popular_shows":
        return renderBrowse(rev, text, () => fetchPopular("shows"), {
          loadingText: "Loading popular shows…",
          placeholder: "Filter popular shows…",
        });
      case "watchlist":
        return renderBrowse(rev, text, fetchWatchlist, {
          loadingText: "Loading watchlist…",
          emptyText: "Your watchlist is empty",
          placeholder: "Filter watchlist…",
        });
      case "history":
        return renderBrowse(rev, text, fetchHistory, {
          loadingText: "Loading history…",
          emptyText: "No watched history",
          placeholder: "Filter history…",
        });
      case "up_next":
        return renderBrowse(rev, text, fetchUpNext, {
          loadingText: "Loading calendar…",
          emptyText: "Nothing airing in the next 14 days",
          placeholder: "Filter upcoming…",
        });
      case "login":
        // Kick off the device flow once on entry; afterwards just reflect its
        // state. A failed/expired flow shows a "Restart login" item instead of
        // re-triggering on every keystroke.
        if (login.status === "idle") return startLogin();
        return renderLogin(rev);
      case "setup":
        return renderSetup(rev);
      case "account":
        return renderAccount(rev);
      default:
        return renderRoot(rev, text);
    }
  } catch (err) {
    renderError(rev, err);
  }
}

// ── actions ──────────────────────────────────────────────────────────────────
async function mediaBody(m) {
  const key = m.mediaType === "show" ? "shows" : "movies";
  return { [key]: [{ ids: { trakt: m.obj.ids.trakt } }] };
}

async function handleMediaAction(m, action) {
  switch (action) {
    case "default":
      cmdOpen(traktWebUrl(m));
      return cmdHide();
    case "open_imdb": {
      const u = imdbWebUrl(m);
      if (u) cmdOpen(u);
      return cmdHide();
    }
    case "copy_title":
      return cmdCopy(m.obj.title || "");
    case "add_watchlist":
      await trakt("/sync/watchlist", {
        method: "POST",
        body: await mediaBody(m),
        authed: true,
      });
      return cmdToast(`Added “${m.obj.title}” to watchlist`);
    case "remove_watchlist":
      await trakt("/sync/watchlist/remove", {
        method: "POST",
        body: await mediaBody(m),
        authed: true,
      });
      cmdToast(`Removed “${m.obj.title}” from watchlist`);
      // Refresh the watchlist so the row disappears.
      if (top().screen === "watchlist") top().ctx.data = null;
      return renderScreen(0, state.lastText);
    case "mark_watched":
      await trakt("/sync/history", {
        method: "POST",
        body: await mediaBody(m),
        authed: true,
      });
      return cmdToast(`Marked “${m.obj.title}” as watched`);
    default:
      cmdOpen(traktWebUrl(m));
      return cmdHide();
  }
}

async function handleAction(id, action) {
  if (!id && action === "open_trakt_apps") {
    return cmdOpen(TRAKT_APPS_URL);
  }
  if (id.startsWith("cmd:")) {
    const c = id.slice(4);
    if (c === "logout") {
      clearTokens();
      cmdToast("Logged out of Trakt");
      return resetToRoot();
    }
    if (c === "login") {
      stopLogin();
      login.status = "idle"; // start a fresh device flow on entry
    }
    return push(c);
  }
  if (id === "login:open") {
    if (action === "copy_code") return cmdCopy(login.userCode);
    return cmdOpen(login.url);
  }
  if (id === "login:restart") {
    stopLogin();
    login.status = "idle";
    return startLogin();
  }

  const item = state.itemsById[id];
  if (!item || !item._data) return;
  return handleMediaAction(item._data, action);
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
      stopLogin();
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
        cmdToast(`Error: ${err.message}`);
      }
      break;
    case "submit":
      try {
        if (
          top().screen === "setup" ||
          !config.clientId ||
          (top().screen === "login" && !config.clientSecret)
        )
          await handleSetupSubmit(msg.values || {}, msg.button || "save");
      } catch (err) {
        cmdToast(`Error: ${err.message}`);
        renderSetup(0, err.message);
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
    // 'select' needs no work — previews are provided per item.
    // 'tab' / 'submit' unused by this plugin.
  }
}
