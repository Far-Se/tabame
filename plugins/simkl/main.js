#!/usr/bin/env node
/*
 * Simkl plugin for the Tabame launcher.
 *
 * Runs as a long-lived child process speaking the launcher's newline-delimited
 * JSON protocol (see the tbm-plugin skill). The launcher exposes a single
 * query line, so this plugin is an internal state machine: a root command list
 * that drills into each command's own screen. Sub-screens set canGoBack, so
 * Escape pops back to the root instead of tearing down the whole plugin.
 *
 * Runtime: Node 18+ (global fetch) or Bun. Plain JS, no dependencies.
 *
 * Setup is handled by an in-app form. Register a free app at
 * https://simkl.com/settings/developer/ (no redirect URI needed for the PIN
 * flow used here) and paste its Client ID into Tabame. Unlike Trakt, Simkl's
 * PIN flow needs no Client Secret, and Simkl serves its own poster art, so
 * no third-party image API key is needed either.
 *
 * ── A NOTE ON API ACCURACY ──────────────────────────────────────────────
 * This was converted from a Trakt version of the plugin using Simkl's public
 * docs (api.simkl.org). Auth (PIN flow), search, and the sync/watchlist
 * read+write endpoints are documented with high confidence. Three endpoints
 * below are educated best guesses because the docs describe the *feature*
 * without pinning an exact path in the pages I could reach:
 *   - fetchTrending() / fetchPopular()  → GET /{type}/trending, /{type}/best
 *   - fetchUpNext()                     → GET /calendar/shows/{date}/{days}
 * If any of the three "You"/"Discover" screens error out, open
 * https://api.simkl.org/api-reference and fix the path in the fetcher
 * function of the same name — everything else (auth, search, watchlist,
 * mark-as-watched) should work as written.
 */

"use strict";

const fs = require("fs");
const path = require("path");

const SIMKL_API = "https://api.simkl.com";
const SIMKL_APP_SETTINGS_URL = "https://simkl.com/settings/developer/";
const APP_NAME = "tabame-simkl-plugin";
const APP_VERSION = "1.0.0";
const USER_AGENT = `${APP_NAME}/${APP_VERSION}`;

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
    const requestId = `simkl-storage-${++storageRequestId}`;
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
    detail: { markdown: `## Simkl error\n\n\`\`\`\n${msg}\n\`\`\`` },
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
    clientId: process.env.SIMKL_CLIENT_ID || "",
  };
  try {
    const file = path.join(process.cwd(), "config.json");
    if (fs.existsSync(file)) {
      const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
      if (parsed.clientId) cfg.clientId = parsed.clientId;
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
  configReady = storageGet("clientId").then((clientId) => {
    // Stored form value takes precedence, while env/config.json remain a
    // backwards-compatible migration path for existing installs.
    if (typeof clientId === "string" && clientId) config.clientId = clientId;
  });
  return configReady;
}

// Simkl access tokens are long-lived (docs advertise ~5 years) and there is
// no refresh token in the PIN flow, so unlike Trakt there's nothing to
// refresh — they're valid until the user revokes the app on simkl.com.
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
let session = loadTokens(); // { access_token }
const isAuthed = () => !!session.access_token;

function saveTokens(tok) {
  session = { access_token: tok.access_token };
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
function withAppParams(apiPath) {
  const sep = apiPath.includes("?") ? "&" : "?";
  return (
    `${apiPath}${sep}client_id=${encodeURIComponent(config.clientId)}` +
    `&app-name=${encodeURIComponent(APP_NAME)}&app-version=${encodeURIComponent(APP_VERSION)}`
  );
}

async function simkl(
  apiPath,
  { method = "GET", body = null, authed = false } = {},
) {
  if (authed && !session.access_token) throw new HttpError(401, "Not logged in");
  const headers = {
    "Content-Type": "application/json",
    "User-Agent": USER_AGENT,
    "simkl-api-key": config.clientId,
  };
  if (authed) headers.Authorization = `Bearer ${session.access_token}`;
  const res = await fetch(SIMKL_API + withAppParams(apiPath), {
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
      (data && (data.error_description || data.error || data.message)) ||
      (typeof data === "string" && data) ||
      `HTTP ${res.status}`;
    if (res.status === 401) clearTokens();
    throw new HttpError(res.status, detail);
  }
  return data;
}

// ── Simkl posters (native — no third-party image API needed) ────────────────
// Widths: _s 40, _cm 84, _c 170, _ca 190, _m 340 (height varies, never cropped
// for _m). Simkl returns bare paths; wsrv.nl proxies/caches/converts them.
function posterUrl(posterPath, size) {
  if (!posterPath) return null;
  return `https://wsrv.nl/?url=https://simkl.in/posters/${posterPath}_${size}.webp&q=90`;
}
const hasPosters = () => true;

// ── media normalization ──────────────────────────────────────────────────────
// Every source (search / trending / watchlist / calendar) is folded into a
// common { mediaType, obj, extra } shape so one item builder handles all.
function toMedia(mediaType, obj, extra) {
  return { mediaType, obj: obj || {}, extra: extra || {} };
}

// Sync endpoints (/sync/*) key items as ids.simkl; catalog endpoints
// (/search, /trending, /best, /calendar) key them as ids.simkl_id — same
// integer, different field name depending on which family returned it.
function simklId(obj) {
  const ids = (obj && obj.ids) || {};
  return ids.simkl != null ? ids.simkl : ids.simkl_id;
}

function ratingInfo(o) {
  const r = o.ratings || {};
  const src = r.simkl || r.imdb || null;
  if (src && src.rating != null) return { rating: src.rating, votes: src.votes };
  if (o.rating != null) return { rating: o.rating, votes: o.votes };
  return null;
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
function episodeNum(ep) {
  if (!ep) return null;
  return ep.episode != null ? ep.episode : ep.number;
}

function simklWebUrl(m) {
  const seg = m.mediaType === "show" ? "tv" : "movies";
  const id = simklId(m.obj);
  return id ? `https://simkl.com/${seg}/${id}` : "https://simkl.com";
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
  const rating = ratingInfo(o);
  if (rating)
    meta.push({
      label: "Rating",
      text: `★ ${Number(rating.rating).toFixed(1)}${rating.votes ? `  ·  ${fmtNum(rating.votes)} votes` : ""}`,
      color: "#F5C518",
    });
  if (o.runtime) meta.push({ label: "Runtime", text: `${o.runtime} min` });
  if (o.genres && o.genres.length)
    meta.push({ label: "Genres", text: o.genres.slice(0, 4).join(", ") });
  if (o.certification) meta.push({ label: "Rated", text: o.certification });
  if (isShow && o.status) meta.push({ label: "Status", text: o.status });
  if (isShow && o.network) meta.push({ label: "Network", text: o.network });

  const ex = m.extra || {};
  if (ex.episode) {
    const n = episodeNum(ex.episode);
    meta.push({
      label: "Episode",
      text: `S${pad2(ex.episode.season)}${n != null ? `E${pad2(n)}` : ""}${ex.episode.title ? ` · ${ex.episode.title}` : ""}`,
    });
  }
  if (ex.watchers)
    meta.push({ label: "Watchers", text: fmtNum(ex.watchers), icon: "person" });
  if (ex.rank) meta.push({ label: "List rank", text: `#${ex.rank}` });
  if (ex.watched_at)
    meta.push({
      label: "Watched",
      text: fmtDate(ex.watched_at),
      icon: "clock",
    });
  if (ex.date || ex.first_aired)
    meta.push({
      label: "Airs",
      text: fmtDateTime(ex.date || ex.first_aired),
      icon: "calendar",
    });

  meta.push({ separator: true });
  meta.push({
    label: "Simkl",
    text: "simkl.com",
    url: simklWebUrl(m),
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
  const a = [{ id: "default", title: "Open on Simkl", icon: "open" }];
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
  const id = `media:${m.mediaType}:${simklId(o) || o.title}`;
  const small = posterUrl(o.poster, "c");

  const acc = [
    { text: isShow ? "TV" : "FILM", color: isShow ? "#8B5CF6" : "#0EA5E9" },
  ];
  const rating = ratingInfo(o);
  if (rating)
    acc.push({ text: `★ ${Number(rating.rating).toFixed(1)}`, color: "#F5C518" });
  const ex = m.extra || {};
  if (ex.watchers)
    acc.push({ text: `${fmtNum(ex.watchers)} watching`, icon: "person" });
  if (ex.rank) acc.push({ text: `#${ex.rank}` });

  const sub = [];
  if (ex.episode) {
    const n = episodeNum(ex.episode);
    sub.push(`S${pad2(ex.episode.season)}${n != null ? `E${pad2(n)}` : ""}`);
  }
  if (o.year) sub.push(String(o.year));
  if (o.genres && o.genres.length) sub.push(o.genres.slice(0, 3).join(", "));
  else if (o.runtime) sub.push(`${o.runtime} min`);
  if (ex.date || ex.first_aired) sub.push(fmtDateTime(ex.date || ex.first_aired));
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
      subtitle: "Search everything on Simkl",
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
      title: "Most Watched Movies",
      subtitle: "Simkl's most-watched movies",
      icon: "star",
    },
    {
      id: "popular_shows",
      section: "Discover",
      title: "Most Watched Shows",
      subtitle: "Simkl's most-watched shows",
      icon: "star",
    },
  ];
  if (isAuthed()) {
    cmds.push(
      {
        id: "watchlist",
        section: "You",
        title: "Plan to Watch",
        subtitle: "Movies & shows you saved",
        icon: "bookmark",
      },
      {
        id: "history",
        section: "You",
        title: "Completed",
        subtitle: "Movies & shows you finished",
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
        subtitle: "Your Simkl profile",
        icon: "person",
      },
      {
        id: "logout",
        section: "Account",
        title: "Log out",
        subtitle: "Sign out of Simkl",
        icon: "lock",
      },
    );
  } else {
    cmds.push({
      id: "login",
      section: "Account",
      title: "Log in to Simkl",
      subtitle: "Enable your watchlist, history & calendar",
      icon: "key",
    });
  }
  cmds.push({
    id: "setup",
    section: "Account",
    title: "Simkl API Settings",
    subtitle: "Edit your Client ID",
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
    placeholder: "Simkl — search or pick a command…",
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

function renderSearch(rev, text, endpoints, opts) {
  const term = (text || "").trim();
  if (!term) {
    setItems([]);
    return render(rev, "list", {
      items: [],
      empty: {
        icon: "search",
        title: "Search Simkl",
        hint: (opts && opts.hint) || "Type a title…",
      },
      placeholder: (opts && opts.placeholder) || "Search…",
    });
  }
  loadingFrame(rev, "Searching…");
  debounceSearch(rev, async () => {
    const medias = (
      await Promise.all(endpoints.map((type) => searchMedia(term, type)))
    ).flat();
    renderMediaFrame(rev, medias, opts);
  });
}

// Fetchers -------------------------------------------------------------------
// "movie" → toMedia("movie", ...); "tv" → toMedia("show", ...)
async function searchMedia(type, term) {
  const raw = await simkl(
    `/search/${type}?q=${encodeURIComponent(term)}&extended=full&page=1&limit=25`,
  );
  const mediaType = type === "tv" ? "show" : "movie";
  return (raw || []).map((o) => toMedia(mediaType, o));
}
// Best-guess path — see the accuracy note at the top of this file.
async function fetchTrending(kind) {
  const type = kind === "shows" ? "tv" : "movies";
  const raw = await simkl(`/${type}/trending`);
  const mediaType = kind === "shows" ? "show" : "movie";
  return (raw || []).map((r) =>
    toMedia(mediaType, r, { watchers: r.watchers || r.watcher_count }),
  );
}
// Best-guess path — see the accuracy note at the top of this file.
async function fetchPopular(kind) {
  const type = kind === "shows" ? "tv" : "movies";
  const raw = await simkl(`/${type}/best`);
  const mediaType = kind === "shows" ? "show" : "movie";
  return (raw || []).map((o) => toMedia(mediaType, o));
}
async function fetchWatchlist() {
  const [movies, shows] = await Promise.all([
    simkl("/sync/all-items/movies/plantowatch?extended=full", { authed: true }),
    simkl("/sync/all-items/shows/plantowatch?extended=full", { authed: true }),
  ]);
  const fromList = (list, mediaType, key) =>
    ((list && list[key]) || list || [])
      .map((r) => r[mediaType] || r.show || r.movie)
      .filter(Boolean)
      .map((o, i) => toMedia(mediaType, o, { rank: i + 1 }));
  return [
    ...fromList(movies, "movie", "movies"),
    ...fromList(shows, "show", "shows"),
  ];
}
async function fetchHistory() {
  const [movies, shows] = await Promise.all([
    simkl("/sync/all-items/movies/completed?extended=full", { authed: true }),
    simkl("/sync/all-items/shows/completed?extended=full", { authed: true }),
  ]);
  const fromList = (list, mediaType, key) =>
    ((list && list[key]) || list || [])
      .map((r) => ({ obj: r[mediaType] || r.show || r.movie, watched_at: r.last_watched_at }))
      .filter((r) => r.obj)
      .map((r) => toMedia(mediaType, r.obj, { watched_at: r.watched_at }));
  return [
    ...fromList(movies, "movie", "movies"),
    ...fromList(shows, "show", "shows"),
  ];
}
// Best-guess path — see the accuracy note at the top of this file.
async function fetchUpNext() {
  const today = new Date().toISOString().slice(0, 10);
  const raw = await simkl(`/calendar/shows/${today}/14?extended=full`, {
    authed: true,
  });
  return (raw || []).map((r) =>
    toMedia("show", r.show, { date: r.date || r.first_aired, episode: r.episode }),
  );
}

// ── login (OAuth PIN flow) ───────────────────────────────────────────────────
const login = {
  active: false,
  userCode: "",
  url: "",
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
  try {
    const d = await simkl("/oauth/pin");
    login.active = true;
    login.userCode = d.user_code;
    login.url = d.verification_url || "https://simkl.com/pin/";
    login.interval = d.interval || 5;
    login.expiresAt = Date.now() + (d.expires_in || 900) * 1000;
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
    const data = await simkl(`/oauth/pin/${encodeURIComponent(login.userCode)}`);
    if (data && data.access_token) {
      saveTokens(data);
      stopLogin();
      login.status = "done";
      cmdToast("Logged into Simkl");
      return resetToRoot();
    }
    // result:"KO" / no token yet → still waiting for the user to approve.
    return scheduleLoginPoll();
  } catch (err) {
    if (err.status === 404 || err.status === 410) {
      stopLogin();
      login.status = "expired";
      login.error = err.message;
      return renderLogin(0);
    }
    if (err.status === 429) {
      login.interval += 1; // slow down
      return scheduleLoginPoll();
    }
    // Transient network / server error — keep polling.
    return scheduleLoginPoll();
  }
}

function renderLogin(rev) {
  let statusLine = "Waiting for you to authorize…";
  if (login.status === "expired")
    statusLine = "Code expired — press Enter on “Restart” to try again.";
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
          "## Log in to Simkl",
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
  render(rev, "list", { items, placeholder: "Authorizing with Simkl…" });
}

function renderNeedLogin(rev) {
  render(rev, "detail", {
    detail: {
      markdown: [
        "## Not logged in",
        "",
        "This needs a Simkl login. Go back and run **Log in to Simkl** first.",
      ].join("\n"),
    },
  });
}

async function renderAccount(rev) {
  loadingFrame(rev, "Loading profile…");
  const data = await simkl("/users/settings", { authed: true });
  const u = (data && data.user) || {};
  const account = (data && data.account) || {};
  render(rev, "detail", {
    detail: {
      markdown: [
        `## ${u.name || account.name || "Simkl user"}`,
        "",
        "You are logged in.",
      ].join("\n"),
      metadata: [
        { label: "Username", text: account.id || u.name || "—", icon: "person" },
        { label: "Premium", text: account.premium_dt ? "Yes" : "No" },
        { separator: true },
        { label: "Profile", text: "simkl.com", url: "https://simkl.com" },
      ],
    },
  });
}

// ── screen dispatch ──────────────────────────────────────────────────────────
function renderSetup(rev, note = "") {
  render(rev, "form", {
    actions: [
      {
        id: "open_simkl_apps",
        title: "Open Simkl Developer Settings",
        icon: "open",
      },
    ],
    form: {
      title: note ? `Simkl setup — ${note}` : "Connect Simkl",
      buttons: [
        { id: "save", label: "Save & Log in" },
        { id: "copy_url", label: "Copy URL" },
      ],
      fields: [
        {
          id: "clientId",
          type: "text",
          label: "Simkl Client ID",
          placeholder: "Paste the Client ID from your Simkl app",
          value: config.clientId || "",
          description:
            "Create a free app at simkl.com/settings/developer/. No redirect URI or Client Secret needed for this PIN-based login.",
        },
      ],
    },
  });
}

async function submitSetup(values) {
  const clientId = String(values.clientId || "").trim();
  if (!clientId) {
    return renderSetup(0, "Client ID is required");
  }

  config.clientId = clientId;
  storageSet("clientId", clientId);
  cmdToast("Simkl Client ID saved");

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
  if (button === "copy_url") return cmdCopy(SIMKL_APP_SETTINGS_URL);
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
        return renderSearch(rev, text, ["movie", "tv"], {
          emptyText: "No results",
          hint: "Type a movie or show…",
          placeholder: "Search movies & shows…",
        });
      case "search_movies":
        return renderSearch(rev, text, ["movie"], {
          emptyText: "No movies",
          hint: "Type a movie title…",
          placeholder: "Search movies…",
        });
      case "search_shows":
        return renderSearch(rev, text, ["tv"], {
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
          loadingText: "Loading most-watched movies…",
          placeholder: "Filter most-watched movies…",
        });
      case "popular_shows":
        return renderBrowse(rev, text, () => fetchPopular("shows"), {
          loadingText: "Loading most-watched shows…",
          placeholder: "Filter most-watched shows…",
        });
      case "watchlist":
        return renderBrowse(rev, text, fetchWatchlist, {
          loadingText: "Loading Plan to Watch…",
          emptyText: "Your Plan to Watch list is empty",
          placeholder: "Filter watchlist…",
        });
      case "history":
        return renderBrowse(rev, text, fetchHistory, {
          loadingText: "Loading completed titles…",
          emptyText: "Nothing marked completed yet",
          placeholder: "Filter completed…",
        });
      case "up_next":
        return renderBrowse(rev, text, fetchUpNext, {
          loadingText: "Loading calendar…",
          emptyText: "Nothing airing in the next 14 days",
          placeholder: "Filter upcoming…",
        });
      case "login":
        // Kick off the PIN flow once on entry; afterwards just reflect its
        // state. A failed/expired flow shows a "Restart login" item instead
        // of re-triggering on every keystroke.
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
function mediaBody(m) {
  const key = m.mediaType === "show" ? "shows" : "movies";
  return { [key]: [{ ids: { simkl: simklId(m.obj) } }] };
}

async function handleMediaAction(m, action) {
  switch (action) {
    case "default":
      cmdOpen(simklWebUrl(m));
      return cmdHide();
    case "open_imdb": {
      const u = imdbWebUrl(m);
      if (u) cmdOpen(u);
      return cmdHide();
    }
    case "copy_title":
      return cmdCopy(m.obj.title || "");
    case "add_watchlist": {
      const key = m.mediaType === "show" ? "shows" : "movies";
      await simkl("/sync/add-to-list", {
        method: "POST",
        body: { [key]: [{ ids: { simkl: simklId(m.obj) }, to: "plantowatch" }] },
        authed: true,
      });
      return cmdToast(`Added “${m.obj.title}” to Plan to Watch`);
    }
    case "remove_watchlist":
      await simkl("/sync/history/remove", {
        method: "POST",
        body: mediaBody(m),
        authed: true,
      });
      cmdToast(`Removed “${m.obj.title}” from watchlist`);
      // Refresh the watchlist so the row disappears.
      if (top().screen === "watchlist") top().ctx.data = null;
      return renderScreen(0, state.lastText);
    case "mark_watched":
      await simkl("/sync/history", {
        method: "POST",
        body: mediaBody(m),
        authed: true,
      });
      return cmdToast(`Marked “${m.obj.title}” as watched`);
    default:
      cmdOpen(simklWebUrl(m));
      return cmdHide();
  }
}

async function handleAction(id, action) {
  if (!id && action === "open_simkl_apps") {
    return cmdOpen(SIMKL_APP_SETTINGS_URL);
  }
  if (id.startsWith("cmd:")) {
    const c = id.slice(4);
    if (c === "logout") {
      clearTokens();
      cmdToast("Logged out of Simkl");
      return resetToRoot();
    }
    if (c === "login") {
      stopLogin();
      login.status = "idle"; // start a fresh PIN flow on entry
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
        if (top().screen === "setup" || !config.clientId)
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
