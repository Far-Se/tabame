"use strict";

// Port of otherSources/gif-search. No Raycast runtime or npm dependencies.
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const crypto = require("node:crypto");
const readline = require("node:readline");

const SOURCES = {
  giphy: "GIPHY GIFs",
  "giphy-clips": "GIPHY Clips",
  klipy: "Klipy",
  finergifs: "Finer Gifs Club",
  favorites: "Favorites",
  recents: "Recent GIFs",
};
const ACTIONS = {
  copyFile: "Copy GIF File",
  copyGifUrl: "Copy GIF Link",
  pasteGifUrl: "Paste GIF Link",
  copyGifMarkdown: "Copy GIF Markdown",
  pasteGifMarkdown: "Paste GIF Markdown",
  toggleFav: "Toggle Favorite",
  viewDetails: "View GIF Details",
  copyPageUrl: "Copy Page Link",
  openUrlInBrowser: "Open in Browser",
  downloadFile: "Download GIF",
};
const DEFAULTS = {
  source: "giphy", defaultAction: "copyFile", maxResults: 20,
  columns: 4, trendingColumns: 4, giphyLocale: "en", klipyLocale: "en",
  downloadPath: path.join(os.homedir(), "Downloads"), hideFilename: false,
};
const CACHE = path.join(__dirname, ".cache");
const MAX_BYTES = 50 * 1024 * 1024;
const state = {
  ready: false, closed: false, rev: 0, generation: 0, timer: null,
  controller: null, downloading: null, query: "", source: "giphy",
  screen: "browse", detail: null, results: [], offset: 0, cursor: "",
  hasMore: false, loading: false, error: "", settings: { ...DEFAULTS },
  favorites: [], recents: [], config: {},
};
const pendingStorage = new Set(["settings", "favorites", "recents"]);

function send(value) {
  if (!state.closed) process.stdout.write(JSON.stringify(value) + "\n");
}
function command(command, fields = {}) { send({ type: "command", command, ...fields }); }
function toast(text, style = "success") { command("toast", { text, style }); }
function save(key, value) { command("storage", { op: "set", key, value }); }
function action(id, title, icon) { return { id, title, ...(icon ? { icon } : {}) }; }
function httpUrl(value) {
  try { const u = new URL(value); return ["http:", "https:"].includes(u.protocol) ? u.href : ""; }
  catch { return ""; }
}
function escapeMarkdown(value) { return String(value).replace(/[\\`*_[\]<>]/g, "\\$&"); }
function imageMarkdown(gif) { return `![${escapeMarkdown(gif.title)}](<${gif.gifUrl}>)`; }
function validGif(gif) {
  return gif && typeof gif.id === "string" && SOURCES[gif.source] &&
    typeof gif.title === "string" && httpUrl(gif.gifUrl) && httpUrl(gif.downloadUrl);
}
function unique(gifs) { return [...new Map(gifs.map(g => [g.id, g])).values()]; }
function normalizeSettings(value = {}) {
  const s = { ...DEFAULTS, ...value };
  if (!SOURCES[s.source]) s.source = DEFAULTS.source;
  if (!ACTIONS[s.defaultAction]) s.defaultAction = DEFAULTS.defaultAction;
  for (const [key, min, max] of [["maxResults", 1, 50], ["columns", 2, 8], ["trendingColumns", 2, 8]]) {
    s[key] = Number.isFinite(Number(s[key])) ? Math.max(min, Math.min(max, Math.trunc(Number(s[key])))) : DEFAULTS[key];
  }
  for (const key of ["giphyLocale", "klipyLocale", "downloadPath"]) {
    s[key] = typeof s[key] === "string" && s[key].trim() ? s[key].trim() : DEFAULTS[key];
  }
  s.hideFilename = s.hideFilename === true;
  return s;
}
function gifActions(gif) {
  const list = Object.entries(ACTIONS).map(([id, title]) => action(id,
    id === "toggleFav" ? (state.favorites.some(g => g.id === gif.id) ? "Remove from Favorites" : "Add to Favorites") : title));
  const index = list.findIndex(a => a.id === state.settings.defaultAction);
  list.unshift(...list.splice(index, 1));
  if (state.recents.some(g => g.id === gif.id)) list.push(action("removeRecent", "Remove from Recents", "trash"));
  return list;
}
function localItems() {
  const list = state.source === "favorites" ? state.favorites : state.recents;
  const words = state.query.toLowerCase().split(/\s+/).filter(Boolean);
  return list.filter(g => words.every(w => `${g.title} ${(g.tags || []).join(" ")} ${SOURCES[g.source]}`.toLowerCase().includes(w)));
}
function visibleItems() {
  if (["favorites", "recents"].includes(state.source)) return localItems();
  if (state.query) return state.results;
  return unique([...state.favorites.filter(g => g.source === state.source).slice(0, 8),
    ...state.recents.filter(g => g.source === state.source).slice(0, 8), ...state.results]);
}
function page(id, title, history = "none") {
  return { id: `gif:${id}`, title, history, preserveState: true,
    ...(id !== "browse" ? { breadcrumbs: [{ id: "gif:browse", label: "GIF Search" }] } : {}) };
}
function render(rev = state.rev, history = "none") {
  if (state.screen === "settings") return renderSettings(rev, history);
  if (state.screen === "detail") return renderDetail(rev, history);
  const local = ["favorites", "recents"].includes(state.source);
  const gifs = visibleItems();
  const favorites = new Set(state.favorites.map(g => g.id));
  send({ type: "render", rev, view: "gallery", page: page("browse", "GIF Search", history),
    placeholder: `Search ${SOURCES[state.source]}…`,
    toolbar: { filters: [{ id: "source", label: "Source", value: state.source,
      options: Object.entries(SOURCES).map(([value, label]) => ({ value, label })) }] },
    gallery: { columns: state.query ? state.settings.columns : state.settings.trendingColumns,
      aspectRatio: 1.2, fit: "contain", showLabels: true },
    loading: !state.ready || state.loading, loadingText: state.ready ? `Searching ${SOURCES[state.source]}…` : "Loading GIF library…",
    hasMore: !local && state.hasMore && !state.loading,
    empty: { icon: "image", title: state.error ? "Could not load GIFs" : "No GIFs here yet",
      hint: state.error || (state.source === "favorites" ? "Save GIFs with Add to Favorites in Ctrl+K." :
        state.source === "recents" ? "GIFs you copy, open or download appear here." :
        state.source === "finergifs" && !state.query ? "Search for a quote from The Office. This source has no trending feed." : "Try a different search or source."),
      ...(state.error ? { action: action("refresh", "Retry", "refresh") } : {}) },
    ...(state.error && gifs.length ? { banner: { style: "error", message: state.error,
      actions: [action("refresh", "Retry", "refresh")] } } : {}),
    items: gifs.map(g => ({ id: g.id, title: g.title, subtitle: SOURCES[g.source],
      media: { type: g.videoUrl ? "video" : "image", url: g.videoUrl || g.previewUrl || g.gifUrl,
        thumbnail: g.previewUrl || g.gifUrl, width: g.width, height: g.height },
      accessories: favorites.has(g.id) ? [{ text: "Favorite", icon: "star" }] : [], actions: gifActions(g) })),
    actions: [action("refresh", "Refresh", "refresh"), action("settings", "Settings", "settings"),
      action("favorites", "Browse Favorites", "star"), action("recents", "Browse Recents", "clock")],
    floatingAction: action("settings", "Settings", "settings"),
  });
}
function renderDetail(rev, history) {
  const g = state.detail;
  if (!g) { state.screen = "browse"; return render(rev); }
  const metadata = [{ label: "Provider", text: SOURCES[g.source] },
    { label: "File", text: g.videoUrl ? "MP4 clip (GIF preview)" : "Animated GIF" }];
  if (g.width && g.height) metadata.push({ label: "Dimensions", text: `${g.width} × ${g.height}` });
  if (g.size) metadata.push({ label: "Size", text: `${(g.size / 1024 / 1024).toFixed(2)} MB` });
  if (g.author) metadata.push({ label: "Creator", text: g.author });
  if (g.created) metadata.push({ label: "Created", text: String(g.created) });
  if (g.season) metadata.push({ label: "Episode", text: `Season ${g.season}, episode ${g.episode}` });
  if (g.tags?.length) metadata.push({ label: "Tags", text: g.tags.join(", ") });
  metadata.push({ label: "Source", text: g.pageUrl || g.gifUrl, url: g.pageUrl || g.gifUrl });
  send({ type: "render", rev, view: "detail", page: page(`detail:${g.id}`, g.title, history), canGoBack: true,
    detail: { markdown: `# ${escapeMarkdown(g.title)}\n\n${imageMarkdown(g)}`, metadata },
    actions: [...gifActions(g).filter(a => a.id !== "viewDetails"), action("back", "Back", "arrow_back")],
    floatingAction: action("copyFile", g.videoUrl ? "Copy Clip File" : "Copy GIF File", "copy") });
}
function renderSettings(rev, history, error) {
  const s = state.settings;
  const fields = [
    { id: "source", type: "dropdown", label: "Default source", options: Object.entries(SOURCES).map(([value, label]) => ({ value, label })) },
    { id: "defaultAction", type: "dropdown", label: "Enter action", options: Object.entries(ACTIONS).map(([value, label]) => ({ value, label })) },
    { id: "maxResults", type: "number", label: "Results per page", min: 1, max: 50 },
    { id: "columns", type: "number", label: "Search columns", min: 2, max: 8 },
    { id: "trendingColumns", type: "number", label: "Trending columns", min: 2, max: 8 },
    { id: "giphyLocale", type: "text", label: "GIPHY language", description: "Language code, e.g. en, ro, de or zh-CN" },
    { id: "klipyLocale", type: "text", label: "Klipy language" },
    { id: "downloadPath", type: "folderpicker", label: "Download folder" },
    { id: "hideFilename", type: "checkbox", label: "Use anonymous filenames" },
  ].map(f => ({ ...f, value: s[f.id] }));
  send({ type: "render", rev, view: "form", page: page("settings", "GIF Settings", history), canGoBack: true,
    form: { title: "GIF Search Settings", submitLabel: "Save Settings", fields, ...(error ? { error } : {}) },
    actions: [action("back", "Cancel", "arrow_back")] });
}
function cancelSearch() {
  state.generation++;
  clearTimeout(state.timer);
  state.controller?.abort();
  state.controller = null;
  state.loading = false;
}
function scheduleSearch(rev, delay = 250) {
  cancelSearch();
  state.rev = rev;
  state.results = []; state.offset = 0; state.cursor = ""; state.hasMore = false; state.error = "";
  if (!state.ready) return render(rev);
  if (["favorites", "recents"].includes(state.source) || (state.source === "finergifs" && !state.query)) return render(rev);
  state.loading = true;
  render(rev);
  state.timer = setTimeout(() => fetchPage(false, rev), delay);
}
function providerUrl(source, query, offset, cursor) {
  let url;
  const s = state.settings;
  if (source === "finergifs") {
    url = new URL(state.config.finerEndpoint || "https://api.thefinergifs.club/search");
    for (const [key, value] of Object.entries({ q: query, "q.parser": "simple", sort: "_score desc", size: s.maxResults, start: offset })) url.searchParams.set(key, value);
  } else {
    url = new URL(source === "klipy" ? state.config.klipyEndpoint || "https://gif-search.raycast.com/api/klipy" :
      state.config.giphyEndpoint || "https://gif-search.raycast.com/api/giphy");
    url.searchParams.set("limit", s.maxResults);
    if (query) url.searchParams.set("q", query);
    if (source === "klipy") {
      url.searchParams.set("locale", s.klipyLocale);
      url.searchParams.set("media_filter", "gif,nanogif,tinygif");
      if (cursor) url.searchParams.set("pos", cursor);
    } else {
      url.searchParams.set("offset", offset);
      url.searchParams.set("lang", s.giphyLocale);
      url.searchParams.set("type", source === "giphy-clips" ? "videos" : "gifs");
    }
  }
  if (!httpUrl(url.href)) throw new Error("Provider endpoint must use HTTP or HTTPS.");
  return url;
}
function mapGif(raw, source) {
  let g;
  if (source === "finergifs") {
    const f = raw.fields || {};
    const url = `https://media.thefinergifs.club/${encodeURIComponent(f.fileid)}.gif`;
    const episode = /^(\d{2})x(\d{2})-/.exec(f.fileid || "");
    g = { providerId: f.fileid, title: f.text || f.name, gifUrl: url, downloadUrl: url, previewUrl: url,
      season: episode?.[1], episode: episode?.[2] };
  } else if (source === "klipy") {
    const m = raw.media_formats || {}, gif = m.gif || {};
    g = { providerId: raw.id, title: raw.title || raw.content_description, gifUrl: gif.url,
      downloadUrl: gif.url, previewUrl: m.tinygif?.url || m.nanogif?.url || gif.url,
      width: gif.dims?.[0], height: gif.dims?.[1], size: Number(gif.size) || 0,
      pageUrl: raw.itemurl, tags: raw.tags, created: raw.created ? new Date(raw.created * 1000).toISOString() : "" };
  } else {
    const imgs = raw.images || {}, orig = imgs.original || {}, assets = raw.video?.assets || {};
    const videoUrl = source === "giphy-clips" ? (assets["1080p"]?.url || assets["720p"]?.url || assets["360p"]?.url) : "";
    g = { providerId: raw.id, title: raw.title || raw.slug, gifUrl: orig.url,
      downloadUrl: videoUrl || orig.url, videoUrl, previewUrl: imgs.fixed_height_small?.url || imgs.preview_gif?.url || orig.url,
      width: orig.width, height: orig.height, size: videoUrl ? undefined : Number(orig.size) || 0,
      pageUrl: raw.url, tags: raw.tags, author: raw.username, created: raw.import_datetime };
  }
  if (g.providerId === undefined || g.providerId === null) return null;
  g.source = source; g.id = `${source}:${g.providerId}`; g.title = String(g.title || "Untitled GIF");
  for (const key of ["gifUrl", "downloadUrl", "previewUrl", "pageUrl", "videoUrl"]) g[key] = httpUrl(g[key]);
  g.width = Number(g.width) || undefined;
  g.height = Number(g.height) || undefined;
  g.tags = Array.isArray(g.tags) ? g.tags.map(String) : [];
  return validGif(g) ? g : null;
}
async function fetchPage(append, rev) {
  if (append && (state.loading || !state.hasMore)) return;
  const generation = state.generation, source = state.source, query = state.query;
  const controller = new AbortController(); state.controller = controller;
  const timeout = setTimeout(() => controller.abort(), 15000);
  state.loading = true;
  render(rev);
  try {
    const response = await fetch(providerUrl(source, query, state.offset, state.cursor), { signal: controller.signal });
    if (!response.ok) throw new Error(`${SOURCES[source]} returned HTTP ${response.status}. Try another source or retry later.`);
    const body = await response.json();
    const raw = source.startsWith("giphy") ? body.data : body.results;
    if (!Array.isArray(raw)) throw new Error(`${SOURCES[source]} returned an unexpected response.`);
    const gifs = raw.map(g => mapGif(g, source)).filter(Boolean);
    if (generation !== state.generation || state.closed) return;
    state.results = unique([...(append ? state.results : []), ...gifs]);
    state.offset += raw.length;
    const cursor = String(body.next ?? "");
    state.hasMore = source === "klipy" ? Boolean(cursor && cursor !== state.cursor) :
      raw.length === state.settings.maxResults && (body.pagination?.total_count == null || state.offset < body.pagination.total_count);
    state.cursor = cursor; state.error = "";
  } catch (error) {
    if (generation !== state.generation || state.closed) return;
    state.error = controller.signal.aborted ? "The provider took too long to respond. Try again." : error.message;
    state.hasMore = false;
  } finally {
    clearTimeout(timeout);
    if (generation === state.generation && !state.closed) { state.loading = false; state.controller = null; render(rev); }
  }
}
function cacheName(gif) { return crypto.createHash("sha256").update(`${gif.id}:${gif.downloadUrl}`).digest("hex"); }
function filename(gif) {
  const title = state.settings.hideFilename ? "gif" : gif.title.toLowerCase().replace(/[^a-z0-9_-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 70) || "gif";
  return `${title}-${cacheName(gif).slice(0, 10)}.${gif.videoUrl ? "mp4" : "gif"}`;
}
async function pruneCache(current) {
  // Keep clipboard files across launcher sessions; bound older cached downloads.
  const entries = await fs.readdir(CACHE, { withFileTypes: true });
  const files = await Promise.all(entries.filter(e => e.isFile() && /\.(gif|mp4)$/.test(e.name)).map(async e => {
    const file = path.join(CACHE, e.name); return { file, ...await fs.stat(file) };
  }));
  files.sort((a, b) => b.mtimeMs - a.mtimeMs);
  let total = 0;
  for (let i = 0; i < files.length; i++) {
    total += files[i].size;
    if ((i >= 100 || total > 256 * 1024 * 1024) && files[i].file !== current && Date.now() - files[i].mtimeMs > 86400000) await fs.unlink(files[i].file);
  }
}
async function resolveFile(gif) {
  await fs.mkdir(CACHE, { recursive: true });
  const destination = path.join(CACHE, filename(gif));
  try { const stat = await fs.stat(destination); if (stat.size > 0) { await fs.utimes(destination, new Date(), new Date()); return destination; } }
  catch (error) { if (error.code !== "ENOENT") throw error; }
  const controller = new AbortController(); state.downloading = controller;
  const timeout = setTimeout(() => controller.abort(), 60000);
  const temporary = `${destination}.${crypto.randomUUID()}.tmp`;
  try {
    const response = await fetch(gif.downloadUrl, { signal: controller.signal });
    if (!response.ok || !response.body) throw new Error(`Download failed (HTTP ${response.status}).`);
    if (Number(response.headers.get("content-length")) > MAX_BYTES) throw new Error("This file exceeds the 50 MB download limit.");
    const chunks = []; let size = 0;
    for await (const chunk of response.body) {
      size += chunk.length;
      if (size > MAX_BYTES) throw new Error("This file exceeds the 50 MB download limit.");
      chunks.push(chunk);
    }
    const bytes = Buffer.concat(chunks);
    if (gif.videoUrl ? bytes.toString("ascii", 4, 8) !== "ftyp" : !["GIF87a", "GIF89a"].includes(bytes.toString("ascii", 0, 6))) {
      throw new Error("The provider did not return a valid GIF or MP4 file.");
    }
    await fs.writeFile(temporary, bytes, { flag: "wx" });
    await fs.rename(temporary, destination);
    await pruneCache(destination).catch(e => process.stderr.write(`Cache cleanup: ${e.message}\n`));
    return destination;
  } finally {
    clearTimeout(timeout); state.downloading = null;
    await fs.unlink(temporary).catch(() => {});
  }
}
function track(gif) {
  state.recents = [gif, ...state.recents.filter(g => g.id !== gif.id)].slice(0, 100);
  save("recents", state.recents);
}
function goBack(rev = 0) {
  state.screen = "browse"; state.detail = null;
  command("setQuery", { text: state.query });
  render(rev);
}
async function handleAction(message) {
  let id = message.action;
  if (id === "back") return goBack();
  if (id === "settings") {
    cancelSearch(); state.screen = "settings";
    command("setQuery", { text: "" }); return render(0, "push");
  }
  if (id === "refresh") return scheduleSearch(0, 0);
  if (["favorites", "recents"].includes(id)) {
    state.screen = "browse"; state.source = id; state.query = "";
    command("setQuery", { text: "" }); return scheduleSearch(0, 0);
  }
  const gif = message.id ? visibleItems().find(g => g.id === message.id) : state.detail;
  if (!gif) return;
  if (id === "default") id = state.settings.defaultAction;
  if (id === "toggleFav") {
    const exists = state.favorites.some(g => g.id === gif.id);
    state.favorites = exists ? state.favorites.filter(g => g.id !== gif.id) : [gif, ...state.favorites];
    save("favorites", state.favorites); toast(exists ? "Removed from favorites" : "Added to favorites"); return render(0);
  }
  if (id === "removeRecent") {
    state.recents = state.recents.filter(g => g.id !== gif.id); save("recents", state.recents); return render(0);
  }
  if (id === "viewDetails") {
    cancelSearch(); state.detail = gif; state.screen = "detail";
    command("setQuery", { text: "" }); return render(0, "push");
  }
  if (["copyFile", "downloadFile"].includes(id)) {
    if (id === "copyFile" && process.platform !== "win32") {
      //TODO: Implement multiplatform
      throw new Error("File clipboard support is currently Windows-only. Use Download GIF or Copy GIF Link.");
    }
    toast("Downloading file…", "progress");
    const file = await resolveFile(gif);
    if (state.closed) return;
    if (id === "copyFile") command("copyFile", { path: file });
    else {
      const folder = path.resolve(state.settings.downloadPath);
      await fs.mkdir(folder, { recursive: true });
      // COPYFILE_EXCL prevents overwriting an existing download.
      let target = path.join(folder, filename(gif));
      for (let n = 1; ; n++) {
        try { await fs.copyFile(file, target, require("node:fs").constants.COPYFILE_EXCL); break; }
        catch (e) { if (e.code !== "EEXIST") throw e; const p = path.parse(filename(gif)); target = path.join(folder, `${p.name} (${n})${p.ext}`); }
      }
      toast(`Downloaded to ${target}`);
    }
    track(gif); render(0); return;
  }
  if (id === "openUrlInBrowser") { track(gif); command("open", { url: gif.pageUrl || gif.gifUrl }); return; }
  const text = id.includes("Markdown") ? imageMarkdown(gif) : id === "copyPageUrl" ? gif.pageUrl || gif.gifUrl : gif.gifUrl;
  if (["copyGifUrl", "copyGifMarkdown", "copyPageUrl", "pasteGifUrl", "pasteGifMarkdown"].includes(id)) {
    track(gif); command(id.startsWith("paste") ? "paste" : "copy", { text });
  }
}
async function initialize() {
  try {
    const config = JSON.parse((await fs.readFile(path.join(__dirname, "config.json"), "utf8")).replace(/^\uFEFF/, ""));
    if (!config || typeof config !== "object" || Array.isArray(config)) throw new Error("Expected a JSON object.");
    state.config = config;
  } catch (error) {
    if (error.code !== "ENOENT") toast(`Cannot read config.json; using default providers. ${error.message}`, "error");
  }
  for (const key of pendingStorage) command("storage", { op: "get", key, requestId: `gif:${key}` });
}
let actionQueue = Promise.resolve();
function fail(error) { toast(error.message || String(error), "error"); }
async function handle(message) {
  if (!message || typeof message !== "object") return;
  if (message.type === "close") { shutdown(); return; }
  if (message.type === "init") {
    state.query = String(message.query || "").trim(); render(0); await initialize(); return;
  }
  if (message.type === "storage" && typeof message.requestId === "string" && message.requestId.startsWith("gif:")) {
    const key = message.requestId.slice(4);
    if (!pendingStorage.has(key)) return;
    const value = message.value;
    if (key === "settings") {
      state.settings = normalizeSettings(value && typeof value === "object" ? value : {});
      state.source = state.settings.source;
    } else state[key] = Array.isArray(value) ? unique(value.filter(validGif)) : [];
    pendingStorage.delete(key);
    if (!pendingStorage.size) { state.ready = true; scheduleSearch(state.rev, 0); }
    return;
  }
  if (message.type === "query") {
    state.rev = Number(message.rev) || 0;
    if (state.screen !== "browse") return render(state.rev);
    state.query = String(message.text || "").trim(); return scheduleSearch(state.rev);
  }
  if (!state.ready) return;
  if (message.type === "toolbarChange" && message.id === "source" && SOURCES[message.value]) {
    state.source = message.value; state.settings.source = message.value; save("settings", state.settings);
    return scheduleSearch(Number(message.rev) || 0, 0);
  }
  if (message.type === "loadMore" && state.screen === "browse") return fetchPage(true, Number(message.rev) || state.rev);
  if (["back", "navigate"].includes(message.type)) return goBack(Number(message.rev) || 0);
  if (message.type === "submit" && state.screen === "settings") {
    const values = normalizeSettings({ ...state.settings, ...message.values });
    if (!path.isAbsolute(values.downloadPath)) return renderSettings(0, "none", "Choose an absolute download folder path.");
    state.settings = values; state.source = values.source; save("settings", values); toast("Settings saved"); return goBack();
  }
  if (message.type === "action") {
    actionQueue = actionQueue.then(() => state.closed ? undefined : handleAction(message)).catch(fail);
  }
}
function shutdown() {
  state.closed = true; cancelSearch(); state.downloading?.abort(); process.exit(0);
}
const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
input.on("line", line => {
  try { const message = JSON.parse(line); handle(message).catch(fail); }
  catch (error) { fail(new Error(`Invalid plugin message: ${error.message}`)); }
});
input.on("close", shutdown);
process.stdout.on("error", shutdown);
