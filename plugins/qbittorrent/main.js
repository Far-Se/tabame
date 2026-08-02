#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const REQUEST_TIMEOUT_MS = 30_000;
const READY_TIMEOUT_MS = 20_000;
const REFRESH_INTERVAL_MS = 15_000;
const PAGE_SIZE = 60;
const CONFIG_PATH = path.join(process.cwd(), "config.json");

const PAGE_API_SCRIPT = `
const target = new URL(input.path, input.base).href;
const request = {
  method: input.method || "GET",
  credentials: "include",
  cache: "no-store",
  headers: input.headers || {},
};
if (input.body != null) request.body = input.body;

const response = await fetch(target, request);
const text = await response.text();
let data = null;
try {
  data = text ? JSON.parse(text) : null;
} catch {
  // Some qBittorrent endpoints intentionally return plain text such as "Ok.".
}

return {
  ok: response.ok,
  status: response.status,
  statusText: response.statusText,
  url: response.url,
  data,
  text: text.slice(0, 12_000),
};
`;

function send(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

function command(name, fields = {}) {
  send({ type: "command", command: name, ...fields });
}

function render(rev, view, fields = {}) {
  send({ type: "render", rev, view, ...fields });
}

function log(...parts) {
  console.error(...parts);
}

function escapeMarkdown(value) {
  return String(value ?? "").replace(/([\\`*_{}[\]()#+\-.!|>])/g, "\\$1");
}

function text(value, fallback = "—") {
  const result = String(value ?? "").trim();
  return result || fallback;
}

function loadSettings() {
  try {
    const parsed = JSON.parse(fs.readFileSync(CONFIG_PATH, "utf8"));
    return {
      url: typeof parsed.url === "string" ? parsed.url.trim() : "",
      proxy: typeof parsed.proxy === "string" ? parsed.proxy.trim() : "",
    };
  } catch {
    return { url: "", proxy: "" };
  }
}

let settings = loadSettings();
let directProxyAgent = null;

function normalizeWebUiUrl(value) {
  const parsed = new URL(String(value || "").trim());
  if (!["http:", "https:"].includes(parsed.protocol)) {
    throw new Error("qBittorrent URL must use http:// or https://");
  }
  parsed.search = "";
  parsed.hash = "";
  parsed.pathname = `${parsed.pathname.replace(/\/+$/, "")}/`;
  return parsed.toString();
}

function validateProxy(value) {
  const proxy = String(value || "").trim();
  if (!proxy) return "";
  const parsed = new URL(proxy);
  if (!["http:", "https:"].includes(parsed.protocol)) {
    throw new Error("Proxy must use http:// or https://");
  }
  return parsed.toString();
}

function saveSettings(next) {
  fs.writeFileSync(
    CONFIG_PATH,
    `${JSON.stringify({ url: next.url, proxy: next.proxy }, null, 2)}\n`,
    "utf8",
  );
  settings = next;
  directProxyAgent = null;
}

function configured() {
  try {
    normalizeWebUiUrl(settings.url);
    return true;
  } catch {
    return false;
  }
}

const state = {
  initialized: false,
  shuttingDown: false,
  screen: configured() ? "root" : "config",
  query: "",
  filter: "all",
  qbitTabId: null,
  torrents: [],
  torrentById: new Map(),
  offset: 0,
  hasMore: false,
  selectedHash: "",
  detailTorrent: null,
  loadGeneration: 0,
  refreshTimer: null,
  refreshBusy: false,
};

class BrowserBridge {
  constructor(onStateChange, onEvent) {
    this.onStateChange = onStateChange;
    this.onEvent = onEvent;
    this.connected = false;
    this.enabled = false;
    this.running = false;
    this.startError = null;
    this.pending = new Map();
    this.requestCounter = 0;
  }

  start() {
    void this.refreshStatus().catch((error) => {
      this.startError = error instanceof Error ? error.message : String(error);
      this.onStateChange();
    });
  }

  refreshStatus() {
    return this.callHost("status").then((status) => {
      this.applyStatus(status);
      this.onStateChange();
      return status;
    });
  }

  handleHostMessage(message) {
    if (typeof message.requestId === "string") {
      const pending = this.pending.get(message.requestId);
      if (!pending) return;
      clearTimeout(pending.timer);
      this.pending.delete(message.requestId);
      if (message.ok) {
        pending.resolve(message.result);
      } else {
        pending.reject(
          new Error(message.error || "Browser bridge request failed"),
        );
      }
      return;
    }

    if (message.event === "connection.changed") {
      this.applyStatus(message.data || {});
      this.onStateChange();
      return;
    }
    if (typeof message.event === "string") {
      this.onEvent(message.event, message.data || {});
    }
  }

  applyStatus(status) {
    this.enabled = Boolean(status.enabled);
    this.running = Boolean(status.running);
    this.connected = Boolean(status.connected);
    this.startError = status.error ? String(status.error) : null;
    if (!this.enabled) {
      this.startError = "The persistent browser connector is disabled.";
    } else if (!this.running && !this.startError) {
      this.startError = "The persistent browser connector is starting.";
    }
  }

  callHost(op, fields = {}, timeoutMs = REQUEST_TIMEOUT_MS) {
    const requestId = `qbit-${process.pid}-${Date.now()}-${this.requestCounter++}`;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(requestId);
        reject(new Error(`Tabame browser bridge timed out: ${op}`));
      }, timeoutMs);
      this.pending.set(requestId, { resolve, reject, timer });
      command("browserBridge", { op, requestId, ...fields, timeoutMs });
    });
  }

  request(method, params = {}, timeoutMs = REQUEST_TIMEOUT_MS) {
    return this.callHost("request", { method, params }, timeoutMs);
  }

  close() {
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(new Error("qBittorrent plugin closed"));
    }
    this.pending.clear();
  }
}

const bridge = new BrowserBridge(
  () => {
    if (!state.initialized || state.shuttingDown) return;
    if (state.screen === "root") {
      renderRoot(0, state.query);
    }
  },
  (event) => {
    if (event !== "tabs.changed" || !state.initialized) return;
    if (state.screen === "torrents") {
      scheduleRefresh();
    }
  },
);
bridge.start();

function connectionAccessory() {
  if (bridge.connected) {
    return { text: "WebUI tab ready", color: "#3D9B72", icon: "check" };
  }
  if (!bridge.enabled) {
    return { text: "Connector off", color: "#A28C93", icon: "warning" };
  }
  return { text: "Browser session optional", color: "#D18B47", icon: "link" };
}

function filterLabel(filter) {
  const labels = {
    all: "All",
    active: "Active",
    downloading: "Downloading",
    seeding: "Seeding",
    completed: "Completed",
  };
  return labels[filter] || "All";
}

function filterItems(items, query) {
  const needle = String(query || "")
    .trim()
    .toLowerCase();
  if (!needle) return items;
  return items.filter((item) => {
    const haystack = `${item.title} ${item.subtitle}`.toLowerCase();
    return haystack.includes(needle);
  });
}

function renderConfig(rev, values = null, error = "", errorField = "url") {
  const current = values || settings;
  render(rev, "form", {
    canGoBack: configured(),
    placeholder: "Configure qBittorrent…",
    form: {
      title: "qBittorrent connection",
      submitLabel: "Save and connect",
      fields: [
        {
          id: "url",
          type: "text",
          label: "WebUI URL",
          placeholder: "http://localhost:8080/",
          value: current.url || "",
          required: true,
          description:
            "The qBittorrent WebUI address, including any reverse-proxy path.",
          ...(error && errorField === "url" ? { error } : {}),
        },
        {
          id: "proxy",
          type: "text",
          label: "Proxy (optional)",
          placeholder: "http://127.0.0.1:8080",
          value: current.proxy || "",
          description:
            "HTTP(S) forward proxy for direct API fallback requests. The browser tab uses the browser's proxy settings.",
          ...(error && errorField === "proxy" ? { error } : {}),
        },
      ],
    },
    actions: configured()
      ? [{ id: "cancel", title: "Cancel", icon: "close" }]
      : [],
  });
}

function rootItems() {
  const status = connectionAccessory();
  return [
    {
      id: "filter:all",
      title: "All torrents",
      subtitle: "Browse every torrent and its live transfer stats",
      icon: "list",
      accessories: [status],
      actions: [{ id: "default", title: "Browse torrents", icon: "open" }],
      preview: {
        markdown:
          "## All torrents\n\nSearch by name, category, tag, or hash. Enter a row to inspect its files and detailed qBittorrent properties.",
      },
    },
    {
      id: "filter:active",
      title: "Active torrents",
      subtitle: "Downloading, seeding, checking, or moving",
      icon: "bolt",
      accessories: [status],
      actions: [{ id: "default", title: "Browse active", icon: "open" }],
      preview: {
        markdown:
          "## Active torrents\n\nA focused view for transfers that are currently doing work.",
      },
    },
    {
      id: "filter:downloading",
      title: "Downloading",
      subtitle: "Torrents receiving data right now",
      icon: "download",
      accessories: [status],
      actions: [{ id: "default", title: "Browse downloads", icon: "open" }],
      preview: {
        markdown:
          "## Downloading\n\nSee progress, ETA, peers, and current download speed.",
      },
    },
    {
      id: "filter:seeding",
      title: "Seeding",
      subtitle: "Torrents uploading to peers",
      icon: "upload",
      accessories: [status],
      actions: [{ id: "default", title: "Browse seeding", icon: "open" }],
      preview: {
        markdown:
          "## Seeding\n\nSee upload speed, ratio, connected peers, and seeding time.",
      },
    },
    {
      id: "filter:completed",
      title: "Completed",
      subtitle: "Finished torrents and their download folders",
      icon: "check",
      accessories: [status],
      actions: [{ id: "default", title: "Browse completed", icon: "open" }],
      preview: {
        markdown:
          "## Completed\n\nUse **Open download folder** from Ctrl+K to reveal a completed torrent's local `save_path`.",
      },
    },
    {
      id: "webui:open",
      title: "Open qBittorrent WebUI tab",
      subtitle: bridge.connected
        ? "Focus the existing tab or open a new one"
        : "Open the configured URL in the default browser",
      icon: "open",
      accessories: [status],
      actions: [{ id: "default", title: "Open WebUI", icon: "open" }],
      preview: {
        markdown:
          "## WebUI tab\n\nThe plugin uses a normal browser tab for same-origin API access, so the browser's qBittorrent login session is reused.",
      },
    },
    {
      id: "settings",
      title: "Connection settings",
      subtitle: settings.proxy
        ? "URL and proxy are configured"
        : "Configure URL and optional proxy",
      icon: "settings",
      actions: [{ id: "default", title: "Edit settings", icon: "edit" }],
      preview: {
        markdown:
          "## Connection settings\n\nChange the qBittorrent WebUI URL or the optional direct-API proxy.",
      },
    },
  ];
}

function renderRoot(rev, query) {
  render(rev, "list", {
    preview: { enabled: true },
    placeholder: "Choose a torrent view or search…",
    emptyText: "No qBittorrent command matches that search",
    items: filterItems(rootItems(), query),
    actions: [
      {
        id: "refresh",
        title: "Refresh connection",
        icon: "refresh",
        shortcut: "ctrl+r",
      },
      { id: "settings", title: "Connection settings", icon: "settings" },
      { id: "open_webui", title: "Open qBittorrent WebUI", icon: "open" },
    ],
  });
}

function torrentStatus(torrent) {
  const stateValue = String(torrent.state || "").toLowerCase();
  const labels = {
    downloading: "Downloading",
    forceddl: "Forced download",
    stalleddl: "Stalled download",
    uploading: "Uploading",
    forcedup: "Forced upload",
    stalledup: "Stalled upload",
    queueddl: "Queued download",
    queuedup: "Queued upload",
    pauseddl: "Paused download",
    pausedup: "Paused upload",
    stoppeddl: "Stopped download",
    stoppedup: "Stopped upload",
    checkingdl: "Checking download",
    checkingup: "Checking upload",
    checkingresumedata: "Checking resume data",
    moving: "Moving",
    errored: "Error",
    missingfiles: "Missing files",
  };
  return labels[stateValue] || text(torrent.state, "Unknown");
}

function isPaused(torrent) {
  return /^(paused|stopped)/i.test(String(torrent.state || ""));
}

function torrentIcon(torrent) {
  const stateValue = String(torrent.state || "").toLowerCase();
  if (stateValue.includes("error") || stateValue.includes("missing"))
    return "error";
  if (stateValue.includes("checking") || stateValue === "moving") return "sync";
  if (stateValue.includes("up") || stateValue.includes("seeding"))
    return "upload";
  if (stateValue.includes("down") || stateValue.includes("download"))
    return "download";
  return "file";
}

function formatBytes(value) {
  const amount = Number(value);
  if (!Number.isFinite(amount) || amount < 0) return "—";
  if (amount < 1024) return `${Math.round(amount)} B`;
  const units = ["KiB", "MiB", "GiB", "TiB"];
  let scaled = amount;
  let unit = "B";
  for (const candidate of units) {
    scaled /= 1024;
    unit = candidate;
    if (scaled < 1024 || candidate === units[units.length - 1]) break;
  }
  return `${scaled.toFixed(scaled >= 100 ? 0 : scaled >= 10 ? 1 : 2)} ${unit}`;
}

function formatRate(value) {
  const amount = Number(value);
  return Number.isFinite(amount) && amount > 0
    ? `${formatBytes(amount)}/s`
    : "0 B/s";
}

function formatNumber(value, digits = 2) {
  const amount = Number(value);
  return Number.isFinite(amount) ? amount.toFixed(digits) : "—";
}

function formatEta(value) {
  const seconds = Number(value);
  if (!Number.isFinite(seconds) || seconds < 0 || seconds >= 8_640_000)
    return "∞";
  if (seconds < 60) return `${Math.round(seconds)}s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  if (hours < 48) return `${hours}h ${minutes % 60}m`;
  return `${Math.floor(hours / 24)}d ${hours % 24}h`;
}

function formatDate(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric <= 0) return "—";
  const date = new Date(numeric < 10_000_000_000 ? numeric * 1000 : numeric);
  if (Number.isNaN(date.getTime())) return "—";
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function torrentPreview(torrent) {
  const progress = Math.max(0, Math.min(1, Number(torrent.progress) || 0));
  const savePath = torrent.save_path || torrent.content_path || "";
  return {
    markdown: [
      `## ${escapeMarkdown(torrent.name || torrent.hash || "Torrent")}`,
      "",
      `**${escapeMarkdown(torrentStatus(torrent))}** · ${Math.round(progress * 100)}% complete`,
      "",
      `↓ ${formatRate(torrent.dlspeed)}  ·  ↑ ${formatRate(torrent.upspeed)}  ·  ETA ${formatEta(torrent.eta)}`,
    ].join("\n"),
    metadata: [
      { label: "Size", text: formatBytes(torrent.size), icon: "database" },
      {
        label: "Downloaded",
        text: formatBytes(torrent.downloaded),
        icon: "download",
      },
      {
        label: "Uploaded",
        text: formatBytes(torrent.uploaded),
        icon: "upload",
      },
      { label: "Ratio", text: formatNumber(torrent.ratio), icon: "chart" },
      { label: "Seeds", text: text(torrent.num_seeds, "0"), icon: "people" },
      { label: "Peers", text: text(torrent.num_leechs, "0"), icon: "person" },
      { separator: true },
      {
        label: "Save path",
        text: savePath || "Unavailable",
        icon: "folder",
        ...(savePath
          ? {
              actions: [
                { id: "open_folder", title: "Open folder", icon: "folder" },
              ],
            }
          : {}),
      },
      {
        label: "Category",
        text: torrent.category || "Uncategorized",
        icon: "tag",
      },
      { label: "Added", text: formatDate(torrent.added_on), icon: "calendar" },
    ],
  };
}

function torrentActions(torrent) {
  const paused = isPaused(torrent);
  return [
    { id: "default", title: "View torrent details", icon: "info" },
    {
      id: paused ? "resume" : "pause",
      title: paused ? "Resume torrent" : "Pause torrent",
      icon: paused ? "play" : "clock",
    },
    { id: "recheck", title: "Force recheck", icon: "sync" },
    { id: "open_folder", title: "Open download folder", icon: "folder" },
    { id: "open_webui", title: "Open WebUI tab", icon: "open" },
    { id: "copy_hash", title: "Copy torrent hash", icon: "copy" },
  ];
}

function torrentItem(torrent) {
  const hash = text(torrent.hash, "unknown");
  const id = `torrent:${hash}`;
  const progress = Math.max(0, Math.min(1, Number(torrent.progress) || 0));
  const item = {
    id,
    title: torrent.name || hash,
    // title: escapeMarkdown(torrent.name || hash),
    subtitle: `${torrentStatus(torrent)} · ${formatBytes(torrent.size)} · ↓ ${formatRate(torrent.dlspeed)} · ↑ ${formatRate(torrent.upspeed)}`,
    icon: torrentIcon(torrent),
    progress,
    lines: 2,
    accessories: [
      {
        text: `${Math.round(progress * 100)}%`,
        color: progress >= 1 ? "#3D9B72" : "#63A0EA",
      },
      ...(torrent.eta != null && progress < 1
        ? [{ text: `ETA ${formatEta(torrent.eta)}`, icon: "clock" }]
        : []),
      ...(torrent.category
        ? [{ text: String(torrent.category), icon: "tag" }]
        : []),
    ],
    actions: torrentActions(torrent),
    preview: torrentPreview(torrent),
  };
  state.torrentById.set(id, torrent);
  return item;
}

function torrentFrameActions() {
  return [
    {
      id: "refresh",
      title: "Refresh torrents",
      icon: "refresh",
      shortcut: "ctrl+r",
    },
    { id: "filter:all", title: "Show all torrents", icon: "list" },
    { id: "filter:active", title: "Show active torrents", icon: "bolt" },
    { id: "filter:downloading", title: "Show downloading", icon: "download" },
    { id: "filter:seeding", title: "Show seeding", icon: "upload" },
    { id: "filter:completed", title: "Show completed", icon: "check" },
    { id: "open_webui", title: "Open qBittorrent WebUI", icon: "open" },
    { id: "settings", title: "Connection settings", icon: "settings" },
  ];
}

function renderTorrentsFrame(rev, query) {
  const items = state.torrents
    .filter((torrent) => {
      const needle = String(query || "")
        .trim()
        .toLowerCase();
      if (!needle) return true;
      return `${torrent.name || ""} ${torrent.hash || ""} ${torrent.category || ""} ${torrent.tags || ""}`
        .toLowerCase()
        .includes(needle);
    })
    .map(torrentItem);
  render(rev, "list", {
    canGoBack: true,
    preview: { enabled: true },
    placeholder: `Search ${filterLabel(state.filter).toLowerCase()} torrents…`,
    empty: {
      icon: "search",
      title: query
        ? "No matching torrents"
        : `No ${filterLabel(state.filter).toLowerCase()} torrents`,
      hint: query
        ? "Try a name, category, tag, or hash"
        : "qBittorrent returned an empty list",
    },
    hasMore: state.hasMore,
    items,
    actions: torrentFrameActions(),
  });
}

function renderWaiting(rev, canGoBack = false) {
  const markdown = !bridge.enabled
    ? [
        "# Browser connector is off",
        "",
        "Enable **Persistent browser connector** in Tabame's Launcher Plugins settings to reuse a logged-in qBittorrent WebUI tab.",
        "",
        "The plugin can still try direct API requests when the server allows them.",
      ].join("\n")
    : bridge.connected
      ? "# qBittorrent is ready\n\nOpening the configured WebUI tab…"
      : [
          "# Waiting for the browser connector",
          "",
          escapeMarkdown(
            bridge.startError ||
              "Pair the tabame-extension browser extension, then try again.",
          ),
          "",
          "Use **Connection settings** to verify the WebUI URL.",
        ].join("\n");
  render(rev, "detail", {
    canGoBack,
    detail: { markdown },
    actions: [
      { id: "refresh", title: "Try again", icon: "refresh" },
      { id: "open_webui", title: "Open qBittorrent WebUI", icon: "open" },
      { id: "settings", title: "Connection settings", icon: "settings" },
    ],
  });
}

function renderError(rev, error, canGoBack = true) {
  const message = error instanceof Error ? error.message : String(error);
  render(rev, "detail", {
    canGoBack,
    detail: {
      wide: true,
      markdown: [
        "# qBittorrent request failed",
        "",
        escapeMarkdown(message),
        "",
        "If qBittorrent shows a login page, open the WebUI tab, sign in, and refresh this view.",
      ].join("\n"),
    },
    actions: [
      { id: "refresh", title: "Try again", icon: "refresh" },
      { id: "open_webui", title: "Open WebUI tab", icon: "open" },
      { id: "settings", title: "Connection settings", icon: "settings" },
    ],
  });
}

function apiPath(endpoint, params = {}) {
  const query = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== "")
      query.set(key, String(value));
  }
  const suffix = query.toString();
  return `api/v2/${endpoint}${suffix ? `?${suffix}` : ""}`;
}

async function pageApiRequest(tabId, requestPath, options = {}) {
  const execution = await bridge.request(
    "javascript.execute",
    {
      tabId,
      code: PAGE_API_SCRIPT,
      input: {
        base: normalizeWebUiUrl(settings.url),
        path: requestPath,
        method: options.method || "GET",
        headers: options.headers || {},
        body: options.body,
      },
    },
    REQUEST_TIMEOUT_MS,
  );
  const result = execution && execution.result;
  if (!result || typeof result !== "object") {
    throw new Error("The qBittorrent WebUI returned no API response");
  }
  return result;
}

function getDirectProxyAgent() {
  if (!settings.proxy) return undefined;
  if (directProxyAgent) return directProxyAgent;
  try {
    const { ProxyAgent } = require("undici");
    directProxyAgent = new ProxyAgent(settings.proxy);
    return directProxyAgent;
  } catch (error) {
    throw new Error(`Could not load the HTTP proxy support: ${error.message}`);
  }
}

async function directApiRequest(requestPath, options = {}) {
  const target = new URL(requestPath, normalizeWebUiUrl(settings.url));
  const init = {
    method: options.method || "GET",
    headers: options.headers || {},
  };
  if (options.body != null) init.body = options.body;
  const dispatcher = getDirectProxyAgent();
  if (dispatcher) init.dispatcher = dispatcher;
  const response = await fetch(target, init);
  const bodyText = await response.text();
  let data = null;
  try {
    data = bodyText ? JSON.parse(bodyText) : null;
  } catch {
    // Plain-text qBittorrent responses are valid for mutation endpoints.
  }
  return {
    ok: response.ok,
    status: response.status,
    statusText: response.statusText,
    url: response.url,
    data,
    text: bodyText.slice(0, 12_000),
  };
}

async function apiRequest(requestPath, options = {}, tabId = null) {
  if (Number.isInteger(tabId))
    return pageApiRequest(tabId, requestPath, options);
  if (bridge.connected) {
    const tab = await ensureQbitTab(false);
    return pageApiRequest(tab.id, requestPath, options);
  }
  return directApiRequest(requestPath, options);
}

function assertApiSuccess(response) {
  if (!response || response.ok !== true) {
    const status = response && response.status ? ` (${response.status})` : "";
    const detail = text(response && response.text, "No response body");
    if (response && (response.status === 401 || response.status === 403)) {
      throw new Error(
        `qBittorrent rejected the request${status}. Sign in to the WebUI tab first.`,
      );
    }
    throw new Error(`qBittorrent API error${status}: ${detail}`);
  }
  return response.data;
}

function tabMatchesConfiguredUrl(tab) {
  try {
    const base = new URL(normalizeWebUiUrl(settings.url));
    const candidate = new URL(String(tab.url || ""));
    if (candidate.origin !== base.origin) return false;
    const basePath = base.pathname.replace(/\/+$/, "") || "/";
    const prefix = basePath === "/" ? "/" : `${basePath}/`;
    return (
      candidate.pathname === basePath || candidate.pathname.startsWith(prefix)
    );
  } catch {
    return false;
  }
}

async function waitForTabReady(tabId) {
  const deadline = Date.now() + READY_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const snapshot = await bridge.request("tabs.list", {}, 10_000);
    const tab = (snapshot.tabs || []).find(
      (candidate) => candidate.id === tabId,
    );
    if (!tab) throw new Error("The qBittorrent WebUI tab was closed");
    if (tab.status === "complete") return tab;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error("The qBittorrent WebUI did not finish loading");
}

async function ensureQbitTab(active) {
  if (!bridge.connected) {
    throw new Error("The Tabame browser connector is not connected");
  }

  let snapshot = await bridge.request("tabs.list");
  let tab = (snapshot.tabs || []).find(
    (candidate) =>
      candidate.id === state.qbitTabId && tabMatchesConfiguredUrl(candidate),
  );
  if (!tab) {
    tab = (snapshot.tabs || []).find((candidate) =>
      tabMatchesConfiguredUrl(candidate),
    );
  }
  if (!tab) {
    tab = await bridge.request("tabs.open", {
      url: normalizeWebUiUrl(settings.url),
      active: Boolean(active),
    });
  } else if (active) {
    await bridge.request("tabs.activate", { tabId: tab.id });
  }

  if (!Number.isInteger(Number(tab.id))) {
    throw new Error("Tabame did not return a qBittorrent tab id");
  }
  state.qbitTabId = Number(tab.id);
  if (tab.status !== "complete") await waitForTabReady(state.qbitTabId);
  return { ...tab, id: state.qbitTabId };
}

async function openWebUi() {
  if (!configured()) {
    enterConfig();
    return;
  }
  try {
    if (bridge.connected) {
      await ensureQbitTab(true);
    } else {
      command("open", { url: normalizeWebUiUrl(settings.url) });
    }
    command("hide");
  } catch (error) {
    log("Could not focus qBittorrent tab:", error.message);
    command("open", { url: normalizeWebUiUrl(settings.url) });
    command("hide");
  }
}

function scheduleRefresh() {
  clearTimeout(state.refreshTimer);
  if (state.screen !== "torrents" || !state.initialized || state.shuttingDown)
    return;
  state.refreshTimer = setTimeout(async () => {
    if (state.screen !== "torrents" || state.refreshBusy) {
      scheduleRefresh();
      return;
    }
    state.refreshBusy = true;
    try {
      await loadTorrents(0, state.query, { quiet: true });
    } catch (error) {
      log("Background qBittorrent refresh failed:", error.message);
    } finally {
      state.refreshBusy = false;
      scheduleRefresh();
    }
  }, REFRESH_INTERVAL_MS);
}

async function loadTorrents(rev, query, options = {}) {
  const append = Boolean(options.append);
  const quiet = Boolean(options.quiet);
  const generation = ++state.loadGeneration;
  state.query = String(query || "");
  if (!append) {
    state.offset = 0;
    state.hasMore = false;
    state.torrents = [];
    state.torrentById.clear();
  }

  if (!quiet) {
    render(rev, "list", {
      canGoBack: true,
      loading: true,
      loadingText: `Reading ${filterLabel(state.filter).toLowerCase()} torrents…`,
      items: append ? state.torrents.map(torrentItem) : [],
      placeholder: `Search ${filterLabel(state.filter).toLowerCase()} torrents…`,
      actions: torrentFrameActions(),
    });
  }

  try {
    const response = await apiRequest(
      apiPath("torrents/info", {
        filter: state.filter,
        limit: PAGE_SIZE,
        offset: state.offset,
        sort: "added_on",
        reverse: true,
      }),
    );
    const page = assertApiSuccess(response);
    if (!Array.isArray(page))
      throw new Error("qBittorrent returned an invalid torrent list");
    if (generation !== state.loadGeneration || state.screen !== "torrents")
      return;

    state.torrents = append ? state.torrents.concat(page) : page;
    state.offset += page.length;
    state.hasMore = page.length >= PAGE_SIZE;
    renderTorrentsFrame(rev, state.query);
    scheduleRefresh();
  } catch (error) {
    if (generation !== state.loadGeneration || state.screen !== "torrents")
      return;
    if (quiet) {
      log("qBittorrent refresh failed:", error.message);
      return;
    }
    renderError(rev, error, true);
  }
}

function detailActions(torrent) {
  const paused = isPaused(torrent);
  return [
    { id: "open_folder", title: "Open download folder", icon: "folder" },
    {
      id: paused ? "resume" : "pause",
      title: paused ? "Resume torrent" : "Pause torrent",
      icon: paused ? "play" : "clock",
    },
    { id: "recheck", title: "Force recheck", icon: "sync" },
    { id: "open_webui", title: "Open WebUI tab", icon: "open" },
    { id: "copy_hash", title: "Copy torrent hash", icon: "copy" },
    { id: "refresh", title: "Refresh details", icon: "refresh" },
  ];
}

function detailMetadata(torrent, properties) {
  const property = (key, fallback = null) =>
    properties && properties[key] != null ? properties[key] : fallback;
  const savePath = property(
    "save_path",
    torrent.save_path || torrent.content_path,
  );
  return [
    {
      label: "State",
      text: torrentStatus(torrent),
      color:
        torrent.state && String(torrent.state).includes("error")
          ? "#C86464"
          : "#3D9B72",
    },
    {
      label: "Progress",
      text: `${Math.round((Number(torrent.progress) || 0) * 100)}%`,
      icon: "chart",
    },
    {
      label: "Size",
      text: formatBytes(torrent.size || property("total_size")),
      icon: "database",
    },
    {
      label: "Download speed",
      text: formatRate(torrent.dlspeed),
      icon: "download",
    },
    {
      label: "Upload speed",
      text: formatRate(torrent.upspeed),
      icon: "upload",
    },
    { label: "ETA", text: formatEta(torrent.eta), icon: "clock" },
    {
      label: "Seeds / peers",
      text: `${text(torrent.num_seeds, "0")} / ${text(torrent.num_leechs, "0")}`,
      icon: "people",
    },
    { label: "Share ratio", text: formatNumber(torrent.ratio), icon: "chart" },
    {
      label: "Added",
      text: formatDate(torrent.added_on || property("addition_date")),
      icon: "calendar",
    },
    {
      label: "Completed",
      text: formatDate(torrent.completion_on),
      icon: "check",
    },
    { separator: true },
    { label: "Save path", text: savePath || "Unavailable", icon: "folder" },
    {
      label: "Category",
      text: torrent.category || "Uncategorized",
      icon: "tag",
    },
    { label: "Hash", text: torrent.hash || "Unavailable", icon: "key" },
  ];
}

function filesMarkdown(files) {
  if (!Array.isArray(files) || files.length === 0)
    return "No file list was returned by qBittorrent.";
  const visible = files.slice(0, 80);
  const lines = visible.map((file) => {
    const progress = Math.round((Number(file.progress) || 0) * 100);
    return `- ${escapeMarkdown(file.name || "Unnamed file")} — ${formatBytes(file.size)} · ${progress}%`;
  });
  if (files.length > visible.length)
    lines.push(`\n_Only the first ${visible.length} files are shown._`);
  return lines.join("\n");
}

async function showTorrentDetail(rev, torrent) {
  state.selectedHash = String(torrent.hash || "");
  state.detailTorrent = torrent;
  render(rev, "detail", {
    canGoBack: true,
    loading: true,
    loadingText: "Reading torrent properties and files…",
    detail: {
      markdown: `# ${escapeMarkdown(torrent.name || torrent.hash || "Torrent")}\n\nLoading qBittorrent stats…`,
    },
  });

  try {
    let tabId = null;
    if (bridge.connected) tabId = (await ensureQbitTab(false)).id;
    const [propertiesResponse, filesResponse] = await Promise.all([
      apiRequest(
        apiPath("torrents/properties", { hash: torrent.hash }),
        {},
        tabId,
      ),
      apiRequest(apiPath("torrents/files", { hash: torrent.hash }), {}, tabId),
    ]);
    const properties = assertApiSuccess(propertiesResponse) || {};
    const files = assertApiSuccess(filesResponse) || [];
    const merged = { ...torrent, ...properties };
    state.detailTorrent = merged;
    render(rev, "detail", {
      canGoBack: true,
      detail: {
        wide: true,
        markdown: [
          `# ${escapeMarkdown(merged.name || merged.hash || "Torrent")}`,
          "",
          `## Files (${Array.isArray(files) ? files.length : 0})`,
          "",
          filesMarkdown(files),
        ].join("\n"),
        metadata: detailMetadata(merged, properties),
      },
      actions: detailActions(merged),
    });
  } catch (error) {
    renderError(rev, error, true);
  }
}

function folderPath(torrent) {
  const savePath = String(torrent.save_path || "").trim();
  if (savePath) return savePath;
  const contentPath = String(torrent.content_path || "").trim();
  return contentPath ? path.dirname(contentPath) : "";
}

function openTorrentFolder(torrent) {
  const target = folderPath(torrent);
  if (!target) {
    command("toast", {
      text: "qBittorrent did not report a download folder",
      style: "error",
    });
    return;
  }
  command("open", { path: target });
}

function postBody(values) {
  return new URLSearchParams(values).toString();
}

async function mutateTorrent(torrent, action) {
  const hash = String(torrent.hash || "");
  const endpoint =
    action === "pause"
      ? "torrents/pause"
      : action === "resume"
        ? "torrents/resume"
        : "torrents/recheck";
  const response = await apiRequest(apiPath(endpoint), {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: postBody({ hashes: hash }),
  });
  assertApiSuccess(response);
  const label =
    action === "pause"
      ? "Torrent paused"
      : action === "resume"
        ? "Torrent resumed"
        : "Torrent recheck started";
  command("toast", { text: label, style: "success" });
}

function enterConfig() {
  const hadQuery = state.query.length > 0;
  state.screen = "config";
  state.query = "";
  if (hadQuery) command("setQuery", { text: "" });
  else renderConfig(0);
}

function enterRoot() {
  clearTimeout(state.refreshTimer);
  const hadQuery = state.query.length > 0;
  state.screen = "root";
  state.query = "";
  state.loadGeneration++;
  if (hadQuery) command("setQuery", { text: "" });
  else renderRoot(0, "");
}

function enterTorrents(filter) {
  state.screen = "torrents";
  state.filter = filter || "all";
  const hadQuery = state.query.length > 0;
  state.query = "";
  if (hadQuery) command("setQuery", { text: "" });
  else void loadTorrents(0, "");
}

function currentTorrentForId(id) {
  if (id && state.torrentById.has(id)) return state.torrentById.get(id);
  if (state.detailTorrent && state.selectedHash) return state.detailTorrent;
  return null;
}

async function handleTorrentAction(id, action) {
  const torrent = currentTorrentForId(id);
  if (!torrent) return;
  if (action === "default") {
    await showTorrentDetail(0, torrent);
    return;
  }
  if (action === "open_folder") {
    openTorrentFolder(torrent);
    return;
  }
  if (action === "copy_hash") {
    command("copy", { text: String(torrent.hash || "") });
    return;
  }
  if (action === "open_webui") {
    await openWebUi();
    return;
  }
  if (["pause", "resume", "recheck"].includes(action)) {
    await mutateTorrent(torrent, action);
    if (state.screen === "detail") await showTorrentDetail(0, torrent);
    else await loadTorrents(0, state.query, { quiet: true });
  }
}

async function handleConfigSubmit(values) {
  const raw = {
    url: String(values.url || "").trim(),
    proxy: String(values.proxy || "").trim(),
  };
  try {
    const next = {
      url: normalizeWebUiUrl(raw.url),
      proxy: validateProxy(raw.proxy),
    };
    saveSettings(next);
    state.screen = "root";
    state.query = "";
    command("toast", { text: "qBittorrent settings saved", style: "success" });
    renderRoot(0, "");
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const errorField = /proxy/i.test(message) ? "proxy" : "url";
    renderConfig(0, raw, message, errorField);
  }
}

async function handleAction(message) {
  const id = String(message.id || "");
  const action = String(message.action || "default");

  try {
    if (action === "refresh") {
      if (state.screen === "root") {
        await bridge.refreshStatus();
        renderRoot(0, state.query);
      } else if (state.screen === "torrents") {
        await loadTorrents(0, state.query);
      } else if (state.screen === "detail" && state.detailTorrent) {
        await showTorrentDetail(0, state.detailTorrent);
      } else if (state.screen === "config") {
        renderConfig(0);
      }
      return;
    }
    if (action === "settings" || id === "settings") {
      enterConfig();
      return;
    }
    if (action === "cancel" && state.screen === "config") {
      enterRoot();
      return;
    }
    if (action === "open_webui" || id === "webui:open") {
      await openWebUi();
      return;
    }

    const requestedFilter = action.startsWith("filter:")
      ? action.slice("filter:".length)
      : id.startsWith("filter:")
        ? id.slice("filter:".length)
        : "";
    if (requestedFilter) {
      enterTorrents(requestedFilter);
      return;
    }

    if (state.screen === "root") {
      if (id.startsWith("filter:")) enterTorrents(id.slice("filter:".length));
      return;
    }
    if (state.screen === "torrents" || state.screen === "detail") {
      await handleTorrentAction(id, action);
    }
  } catch (error) {
    renderError(0, error, state.screen !== "root");
  }
}

function handleBack() {
  if (state.screen === "detail") {
    state.screen = "torrents";
    void loadTorrents(0, state.query, { quiet: true });
    return;
  }
  if (
    state.screen === "torrents" ||
    (state.screen === "config" && configured())
  ) {
    enterRoot();
  }
}

async function renderCurrent(rev, query) {
  state.query = String(query || "");
  if (!configured()) {
    state.screen = "config";
    renderConfig(rev);
    return;
  }
  if (state.screen === "config") {
    renderConfig(rev);
  } else if (state.screen === "torrents") {
    await loadTorrents(rev, state.query);
  } else if (state.screen === "detail" && state.detailTorrent) {
    await showTorrentDetail(rev, state.detailTorrent);
  } else {
    state.screen = "root";
    renderRoot(rev, state.query);
  }
}

let inputBuffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  inputBuffer += chunk;
  let newline;
  while ((newline = inputBuffer.indexOf("\n")) >= 0) {
    const line = inputBuffer.slice(0, newline).trim();
    inputBuffer = inputBuffer.slice(newline + 1);
    if (line) void handleLine(line);
  }
});
process.stdin.on("end", shutdown);

async function handleLine(line) {
  let message;
  try {
    message = JSON.parse(line);
  } catch (error) {
    log("Ignoring malformed launcher message:", error.message);
    return;
  }

  switch (message.type) {
    case "close":
      shutdown();
      break;
    case "browserBridge":
      bridge.handleHostMessage(message);
      break;
    case "init":
    case "query":
      state.initialized = true;
      await renderCurrent(
        Number(message.rev) || 0,
        message.text != null ? message.text : message.query || "",
      );
      break;
    case "action":
      await handleAction(message);
      break;
    case "submit":
      if (state.screen === "config")
        await handleConfigSubmit(message.values || {});
      break;
    case "back":
      handleBack();
      break;
    case "loadMore":
      if (state.screen === "torrents" && state.hasMore) {
        await loadTorrents(Number(message.rev) || 0, state.query, {
          append: true,
        });
      }
      break;
    case "tab": {
      const torrent = currentTorrentForId(String(message.id || ""));
      if (torrent && torrent.name)
        command("setQuery", { text: String(torrent.name) });
      break;
    }
    case "select":
      if (String(message.id || "").startsWith("torrent:")) {
        const torrent = state.torrentById.get(String(message.id));
        if (torrent) state.selectedHash = String(torrent.hash || "");
      }
      break;
  }
}

let shutdownTimer = null;
function shutdown() {
  if (state.shuttingDown) return;
  state.shuttingDown = true;
  clearTimeout(state.refreshTimer);
  bridge.close();
  if (directProxyAgent && typeof directProxyAgent.close === "function") {
    void directProxyAgent.close().catch(() => {});
  }
  shutdownTimer = setTimeout(() => process.exit(0), 20);
}
