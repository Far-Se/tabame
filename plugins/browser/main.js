#!/usr/bin/env node
"use strict";

const ANALYTICS_URL =
  "https://chatgpt.com/codex/cloud/settings/analytics#usage";
const REQUEST_TIMEOUT_MS = 30_000;
const config = { token: "", port: 17373 };
const CODEX_USAGE_SCRIPT = `
const deadline = Date.now() + Math.max(1000, Number(input?.timeoutMs) || 20000);
let snapshot = null;

function parseResetDate(bodyText) {
  const match = bodyText.match(
    /Resets?\\s+([A-Z][a-z]{2}\\s+\\d{1,2},\\s+\\d{4}\\s+\\d{1,2}:\\d{2}\\s+[AP]M)/i,
  );

  if (!match) return null;

  // Parsed in the browser's local timezone.
  const date = new Date(match[1]);
  if (Number.isNaN(date.getTime())) return null;

  const remainingMs = Math.max(0, date.getTime() - Date.now());
  const totalMinutes = Math.ceil(remainingMs / 60000);
  const days = Math.floor(totalMinutes / (24 * 60));
  const hours = Math.floor((totalMinutes % (24 * 60)) / 60);
  const minutes = totalMinutes % 60;

  const parts = [];
  if (days > 0) parts.push(\`\${days} day\${days === 1 ? "" : "s"}\`);
  if (hours > 0) parts.push(\`\${hours} hour\${hours === 1 ? "" : "s"}\`);
  if (minutes > 0 || parts.length === 0) {
    parts.push(\`\${minutes} minute\${minutes === 1 ? "" : "s"}\`);
  }

  return {
    resetDateText: match[1],
    resetDate: date.toISOString(),
    remainingMs,
    remainingDays: days,
    remainingHours: hours,
    remainingMinutes: minutes,
    remainingText: remainingMs > 0 ? parts.join(", ") : "Now",
    hasReset: remainingMs <= 0,
  };
}

while (Date.now() < deadline) {
  const bodyText = document.body ? document.body.innerText : "";

  const usageMatch =
    bodyText.match(/(\\d+)%\\Wremaining/i) ||
    bodyText.match(/(\\d+)%\\W+remaining/i);

  const reset = parseResetDate(bodyText);

  snapshot = {
    remainingPercent: usageMatch ? Number(usageMatch[1]) : null,
    pageTitle: document.title,
    pageUrl: location.href,
    ...reset,
  };

  if (Number.isFinite(snapshot.remainingPercent)) {
    return {
      ...snapshot,
      usedPercent: 100 - snapshot.remainingPercent,
      fetchedAt: new Date().toISOString(),
    };
  }

  await new Promise((resolve) => setTimeout(resolve, 500));
}

if (snapshot && !snapshot.pageUrl.startsWith("https://chatgpt.com/")) {
  throw new Error("ChatGPT redirected away from the analytics page");
}

throw new Error(
  "Codex usage was not found. Make sure this browser profile is signed in to ChatGPT and has Codex access.",
);
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

class BrowserBridge {
  constructor(config, onStateChange, onEvent) {
    this.config = config;
    this.onStateChange = onStateChange;
    this.onEvent = onEvent;
    this.connected = false;
    this.enabled = false;
    this.running = false;
    this.clientInfo = {};
    this.pending = new Map();
    this.startError = null;
    this.requestCounter = 0;
  }

  start() {
    void this.refreshStatus();
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
      const requestId = message.requestId;
      const request = this.pending.get(requestId);
      if (!request) return;
      clearTimeout(request.timer);
      this.pending.delete(requestId);
      if (message.ok) request.resolve(message.result);
      else
        request.reject(
          new Error(message.error || "Browser bridge request failed"),
        );
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
    if (Number.isInteger(Number(status.port)))
      this.config.port = Number(status.port);
    if (typeof status.token === "string") this.config.token = status.token;
    this.clientInfo = {
      extensionVersion: String(status.extensionVersion || "unknown"),
      browser: String(status.browser || "unknown"),
      connectedAt: status.connectedAt || null,
    };
    this.startError = status.error
      ? String(status.error)
      : !this.enabled
        ? "The persistent browser connector is disabled. Enable it in Launcher Plugins."
        : !this.running
          ? "The persistent browser connector is starting."
          : null;
  }

  callHost(op, fields = {}, timeoutMs = REQUEST_TIMEOUT_MS) {
    const requestId = `browser-${process.pid}-${Date.now()}-${this.requestCounter++}`;
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
      pending.reject(new Error("Browser plugin closed"));
    }
    this.pending.clear();
  }
}

/*
 * Browser requests are routed by Tabame's app-owned bridge. Keeping this
 * adapter inside the plugin preserves its UI/state model while removing the
 * per-plugin WebSocket server and third-party `ws` dependency.
 */
const state = {
  screen: "root",
  query: "",
  rev: 0,
  itemData: new Map(),
  usageRemaining: null,
  initialized: false,
  extensionEventTimer: null,
};

const bridge = new BrowserBridge(
  config,
  () => {
    if (state.initialized) {
      renderCurrent(0, state.query, { refresh: true });
    }
  },
  (event) => {
    if (event !== "tabs.changed") return;
    if (!["tabs", "audio"].includes(state.screen)) return;
    clearTimeout(state.extensionEventTimer);
    state.extensionEventTimer = setTimeout(
      () => renderCurrent(0, state.query, { refresh: true, quiet: true }),
      220,
    );
  },
);
bridge.start();

function connectionAccessory() {
  return {
    text: bridge.connected ? "Connected" : "Offline",
    color: bridge.connected ? "#3D9B72" : "#8A7F88",
    icon: bridge.connected ? "check" : "warning",
  };
}

function rootItems(text) {
  const items = [
    {
      id: "command:usage",
      title: "Codex usage",
      subtitle: "Read the remaining allowance from ChatGPT analytics",
      icon: "chart",
      accessories: [connectionAccessory()],
      preview: {
        markdown:
          "## Codex usage\n\nOpens the ChatGPT analytics page in an **inactive temporary tab**, waits for the dynamic page to render, reads the remaining percentage, then closes the temporary tab.",
      },
    },
    {
      id: "command:tabs",
      title: "All browser tabs",
      subtitle: "Search, focus, close, reload, pin, duplicate, or mute",
      icon: "window",
      accessories: [connectionAccessory()],
      preview: {
        markdown:
          "## Tab control\n\nShows every open tab in this Chromium profile, including its favicon, window, active state, pinned state, and audio state.",
      },
    },
    {
      id: "command:audio",
      title: "Playing audio",
      subtitle: "Find and control tabs currently producing sound",
      icon: "music",
      accessories: [connectionAccessory()],
      preview: {
        markdown:
          "## Audio tabs\n\nChromium marks a tab audible while its speaker indicator is active. The current candidate is ranked first, followed by other audible tabs.",
      },
    },
    {
      id: "command:connection",
      title: "Connection & pairing",
      subtitle: bridge.connected
        ? `Connector ${bridge.clientInfo.extensionVersion} is ready`
        : `Pair the Chromium extension on port ${config.port}`,
      icon: bridge.connected ? "link" : "key",
      accessories: [connectionAccessory()],
      preview: {
        markdown:
          "## Secure local bridge\n\nThe bridge binds only to `127.0.0.1`, checks the Chromium extension origin, and requires the generated 256-bit token before accepting requests.",
      },
    },
  ];
  const needle = String(text || "")
    .trim()
    .toLowerCase();
  return needle
    ? items.filter(
        (item) =>
          item.title.toLowerCase().includes(needle) ||
          item.subtitle.toLowerCase().includes(needle),
      )
    : items;
}

function renderRoot(rev, text) {
  render(rev, "list", {
    items: rootItems(text),
    preview: { enabled: true },
    placeholder: "Choose a browser command…",
    emptyText: "No browser command matches this search",
  });
}

function favicon(tab) {
  const value = String(tab.favIconUrl || "");
  return /^https?:\/\//i.test(value) ? value : "globe";
}

function shortHost(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "Browser page";
  }
}

const GROUP_COLORS = {
  grey: "#777B82",
  blue: "#4F86D9",
  red: "#D05C5C",
  yellow: "#D6A746",
  green: "#4A9B68",
  pink: "#C767A2",
  purple: "#8C6BC7",
  cyan: "#3A9CAE",
  orange: "#D27A45",
};

function groupAccessory(tab) {
  if (!tab.group) return null;
  return {
    text: tab.group.title || "Group",
    color: GROUP_COLORS[tab.group.color] || GROUP_COLORS.grey,
    icon: "folder",
  };
}

function tabActions(tab) {
  return [
    { id: "default", title: "Focus tab", icon: "open" },
    {
      id: "mute",
      title: tab.muted ? "Unmute tab" : "Mute tab",
      icon: tab.muted ? "music" : "close",
    },
    {
      id: "pin",
      title: tab.pinned ? "Unpin tab" : "Pin tab",
      icon: "bookmark",
    },
    { id: "reload", title: "Reload tab", icon: "refresh" },
    { id: "duplicate", title: "Duplicate tab", icon: "copy" },
    { id: "copy_url", title: "Copy URL", icon: "link" },
    {
      id: "close",
      title: "Close tab",
      icon: "trash",
      shortcut: "ctrl+shift+delete",
      destructive: true,
      confirm: {
        title: "Close this browser tab?",
        message: tab.title || tab.url,
        confirmLabel: "Close tab",
      },
    },
  ];
}

function tabItem(tab, section) {
  const groupTag = groupAccessory(tab);
  const item = {
    id: `tab:${tab.id}`,
    title: tab.title || "Untitled tab",
    subtitle: tab.url || "No URL",
    icon: favicon(tab),
    section,
    lines: 1,
    accessories: [
      ...(groupTag ? [groupTag] : []),
      ...(tab.audible
        ? [{ text: "Playing", color: "#3D9B72", icon: "music" }]
        : []),
      ...(tab.muted ? [{ text: "Muted", icon: "close" }] : []),
      ...(tab.pinned ? [{ text: "Pinned", icon: "bookmark" }] : []),
      ...(tab.active ? [{ text: "Active", color: "#A46293" }] : []),
      { text: `W${tab.windowId}` },
    ],
    actions: tabActions(tab),
    preview: {
      markdown: `## ${escapeMarkdown(tab.title || "Untitled tab")}\n\n${escapeMarkdown(tab.url || "No URL")}`,
      metadata: [
        { label: "Site", text: shortHost(tab.url), icon: "globe" },
        { label: "Window", text: String(tab.windowId), icon: "window" },
        ...(tab.group
          ? [
              {
                label: "Group",
                text: tab.group.title || "Unnamed group",
                color: GROUP_COLORS[tab.group.color] || GROUP_COLORS.grey,
                icon: "folder",
              },
            ]
          : []),
        {
          label: "State",
          text: [
            tab.active ? "active" : "background",
            tab.pinned ? "pinned" : null,
            tab.audible ? "audible" : null,
            tab.muted ? "muted" : null,
            tab.discarded ? "discarded" : null,
          ]
            .filter(Boolean)
            .join(" · "),
        },
      ],
    },
  };
  state.itemData.set(item.id, tab);
  return item;
}

function filterTabs(tabs, text) {
  const needle = String(text || "")
    .trim()
    .toLowerCase();
  if (!needle) return tabs;
  return tabs.filter(
    (tab) =>
      String(tab.title || "")
        .toLowerCase()
        .includes(needle) ||
      String(tab.url || "")
        .toLowerCase()
        .includes(needle) ||
      String(tab.group?.title || "")
        .toLowerCase()
        .includes(needle),
  );
}

async function renderTabs(rev, text, quiet = false) {
  if (!quiet) {
    render(rev, "list", {
      loading: true,
      loadingText: "Reading browser tabs…",
      items: [],
      canGoBack: true,
    });
  }
  try {
    const result = await bridge.request("tabs.list");
    state.itemData.clear();
    const tabs = filterTabs(result.tabs || [], text).sort((a, b) => {
      if (a.windowId !== b.windowId) return a.windowId - b.windowId;
      return a.index - b.index;
    });
    render(rev, "list", {
      items: tabs.map((tab) =>
        tabItem(
          tab,
          tab.active
            ? `Window ${tab.windowId} · active`
            : `Window ${tab.windowId}`,
        ),
      ),
      preview: { enabled: true },
      canGoBack: true,
      placeholder: "Filter tabs by title or URL…",
      empty: {
        icon: "search",
        title: "No matching tabs",
        hint: text
          ? "Try a broader title or domain"
          : "Chromium returned no tabs",
      },
      actions: [
        {
          id: "refresh",
          title: "Refresh tabs",
          icon: "refresh",
          shortcut: "ctrl+r",
        },
      ],
    });
  } catch (error) {
    renderBridgeError(rev, error, "tabs");
  }
}

async function renderAudio(rev, text, quiet = false) {
  if (!quiet) {
    render(rev, "list", {
      loading: true,
      loadingText: "Finding audible tabs…",
      items: [],
      canGoBack: true,
    });
  }
  try {
    const result = await bridge.request("tabs.audible");
    state.itemData.clear();
    const tabs = filterTabs(result.tabs || [], text);
    render(rev, "list", {
      items: tabs.map((tab, index) =>
        tabItem(tab, index === 0 ? "Current audio candidate" : "Also playing"),
      ),
      preview: { enabled: true },
      canGoBack: true,
      placeholder: "Filter audible tabs…",
      empty: {
        icon: "music",
        title: "No tab is producing sound",
        hint: "Start playback in Chromium and this view will update",
      },
      actions: [
        {
          id: "refresh",
          title: "Refresh audio tabs",
          icon: "refresh",
          shortcut: "ctrl+r",
        },
      ],
    });
  } catch (error) {
    renderBridgeError(rev, error, "audio");
  }
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitForTabReady(tabId, timeoutMs = 20_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const snapshot = await bridge.request("tabs.list");
    const tab = (snapshot.tabs || []).find(
      (candidate) => candidate.id === tabId,
    );
    if (!tab) throw new Error("The temporary analytics tab was closed");
    if (tab.status === "complete") return tab;
    await delay(250);
  }
  throw new Error("The analytics page did not finish loading");
}

async function fetchCodexUsage() {
  let analyticsTab = null;
  try {
    analyticsTab = await bridge.request("tabs.open", {
      url: ANALYTICS_URL,
      active: false,
    });
    if (!Number.isInteger(analyticsTab?.id)) {
      throw new Error("Chromium did not return a temporary tab id");
    }
    await waitForTabReady(analyticsTab.id);
    const execution = await bridge.request(
      "javascript.execute",
      {
        tabId: analyticsTab.id,
        code: CODEX_USAGE_SCRIPT,
        input: { timeoutMs: 20_000 },
      },
      45_000,
    );
    const result = execution?.result;
    if (!result || !Number.isFinite(Number(result.remainingPercent))) {
      throw new Error("The Codex usage script returned an invalid result");
    }
    return result;
  } finally {
    if (Number.isInteger(analyticsTab?.id)) {
      await bridge
        .request("tabs.close", { tabId: analyticsTab.id })
        .catch(() => {});
    }
  }
}

async function renderUsage(rev) {
  render(rev, "list", {
    loading: true,
    loadingText: "Opening ChatGPT analytics in the background…",
    items: [],
    canGoBack: true,
  });
  try {
    const result = await fetchCodexUsage();
    const remaining = Number(result.remainingPercent);
    state.usageRemaining = remaining;
    render(rev, "list", {
      canGoBack: true,
      preview: { enabled: true },
      items: [
        {
          id: "usage:codex",
          title: `${remaining}% Codex usage remaining`,
          subtitle: `${result.usedPercent}% used · checked ${formatTime(result.fetchedAt)}`,
          icon: remaining >= 25 ? "chart" : "warning",
          progress: remaining / 100,
          accessories: [
            {
              text: remaining >= 25 ? "Available" : "Running low",
              color: remaining >= 25 ? "#3D9B72" : "#D18B47",
            },
          ],
          actions: [
            { id: "refresh", title: "Refresh usage", icon: "refresh" },
            { id: "open_analytics", title: "Open analytics", icon: "open" },
            { id: "copy", title: "Copy remaining percentage", icon: "copy" },
          ],
          preview: {
            markdown: `## Codex allowance\n\n**${remaining}% remains** for the current ChatGPT usage window.`,
            metadata: [
              {
                label: "Remaining",
                text: `${remaining}%`,
                color: remaining >= 25 ? "#3D9B72" : "#D18B47",
              },
              { label: "Used", text: `${result.usedPercent}%` },
              {
                label: "Checked",
                text: formatTime(result.fetchedAt),
                icon: "clock",
              },
              {
                label: "Resets At",
                text: result.resetDateText,
                icon: "clock",
              },
              {
                label: "Resets In",
                text: result.remainingText,
                icon: "clock",
              },
              {
                label: "Source",
                text: "ChatGPT Codex analytics",
                url: ANALYTICS_URL,
              },
            ],
          },
        },
      ],
      actions: [
        {
          id: "refresh",
          title: "Refresh usage",
          icon: "refresh",
          shortcut: "ctrl+r",
        },
      ],
    });
  } catch (error) {
    renderBridgeError(rev, error, "usage");
  }
}

function renderConnection(rev) {
  const token = config.token;
  const tokenDisplay = token.replace(/(.{6})/g, "$1 ").trim();
  const connected = bridge.connected;
  const markdown = !bridge.enabled
    ? [
        "# Persistent browser connector is off",
        "",
        "Open **Launcher Plugins** and enable **Persistent browser connector**.",
        "",
        "The bridge is optional and remains completely stopped while this setting is off.",
      ].join("\n")
    : connected
      ? [
          "# Browser connector is online",
          "",
          "Tabame can now exchange allowlisted requests with this Chromium profile.",
          "",
          "Use **Escape** to return to browser commands.",
        ].join("\n")
      : [
          "# Pair the Chromium extension",
          "",
          "1. Load `tabame-extension` from `chrome://extensions`.",
          "2. Enable **Allow User Scripts** on the extension details page if shown.",
          "3. Click the **Tabame Connector** toolbar icon.",
          "4. Paste the token below and keep the default port.",
          "5. Click **Save & connect**.",
          "",
          "### Pairing token",
          "",
          `\`${tokenDisplay}\``,
          "",
          "> The token is shared by Tabame browser plugins on this Windows account. Do not publish `browser-bridge.json`.",
        ].join("\n");

  render(rev, "detail", {
    canGoBack: true,
    detail: {
      markdown,
      metadata: [
        {
          label: "Status",
          text: !bridge.enabled
            ? "Disabled"
            : connected
              ? "Connected"
              : "Waiting for extension",
          color: !bridge.enabled
            ? "#8A7F88"
            : connected
              ? "#3D9B72"
              : "#D18B47",
        },
        { label: "Address", text: `127.0.0.1:${config.port}`, icon: "server" },
        ...(connected
          ? [
              {
                label: "Extension",
                text: bridge.clientInfo.extensionVersion,
                icon: "extension",
              },
              {
                label: "Connected",
                text: formatTime(bridge.clientInfo.connectedAt),
                icon: "clock",
              },
            ]
          : []),
        ...(bridge.startError
          ? [
              {
                label: "Bridge error",
                text: bridge.startError,
                color: "#C86464",
              },
            ]
          : []),
      ],
    },
    actions: [
      ...(bridge.enabled && token
        ? [{ id: "copy_token", title: "Copy pairing token", icon: "key" }]
        : []),
      {
        id: "copy_address",
        title: "Copy bridge address",
        icon: "copy",
      },
      { id: "refresh", title: "Refresh status", icon: "refresh" },
    ],
  });
}

function renderBridgeError(rev, error, destination) {
  const message = error instanceof Error ? error.message : String(error);
  render(rev, "detail", {
    canGoBack: true,
    detail: {
      markdown: `# Browser request failed\n\n${escapeMarkdown(message)}\n\nOpen **Connection & pairing** if the extension is not configured. If it is already paired, click the extension icon and choose **Retry** to reconnect immediately.`,
      metadata: [
        {
          label: "Connector",
          text: bridge.connected ? "Connected" : "Offline",
          color: bridge.connected ? "#3D9B72" : "#C86464",
        },
      ],
    },
    actions: [
      { id: `retry:${destination}`, title: "Try again", icon: "refresh" },
      { id: "connection", title: "Connection & pairing", icon: "key" },
    ],
  });
}

function escapeMarkdown(value) {
  return String(value || "").replace(/([\\`*_{}[\]()#+\-.!])/g, "\\$1");
}

function formatTime(value) {
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? "just now"
    : new Intl.DateTimeFormat(undefined, {
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
      }).format(date);
}

function renderCurrent(rev, text, options = {}) {
  state.query = String(text || "");
  state.rev = rev;
  switch (state.screen) {
    case "tabs":
      return renderTabs(rev, state.query, Boolean(options.quiet));
    case "audio":
      return renderAudio(rev, state.query, Boolean(options.quiet));
    case "usage":
      if (options.refresh) return;
      return renderUsage(rev);
    case "connection":
      return renderConnection(rev);
    default:
      return renderRoot(rev, state.query);
  }
}

function enterScreen(screen) {
  const needsQueryReset = state.query.length > 0;
  state.screen = screen;
  state.query = "";
  if (needsQueryReset) {
    command("setQuery", { text: "" });
  } else {
    renderCurrent(0, "");
  }
}

async function handleTabAction(id, action) {
  const tab = state.itemData.get(id);
  if (!tab) return;
  switch (action) {
    case "copy_url":
      command("copy", { text: tab.url || "" });
      return;
    case "close":
      await bridge.request("tabs.close", { tabId: tab.id });
      command("toast", { text: "Tab closed", style: "success" });
      return renderCurrent(0, state.query, { refresh: true, quiet: true });
    case "mute":
      await bridge.request("tabs.mute", { tabId: tab.id, muted: !tab.muted });
      return renderCurrent(0, state.query, { refresh: true, quiet: true });
    case "pin":
      await bridge.request("tabs.pin", { tabId: tab.id, pinned: !tab.pinned });
      return renderCurrent(0, state.query, { refresh: true, quiet: true });
    case "reload":
      await bridge.request("tabs.reload", { tabId: tab.id });
      command("toast", { text: "Tab reloading", style: "info" });
      return;
    case "duplicate":
      await bridge.request("tabs.duplicate", { tabId: tab.id });
      command("toast", { text: "Tab duplicated", style: "success" });
      return;
    default:
      await bridge.request("tabs.activate", { tabId: tab.id });
      command("hide");
  }
}

async function handleAction(id, action) {
  try {
    if (id.startsWith("command:")) {
      enterScreen(id.slice("command:".length));
      return;
    }
    if (id.startsWith("tab:")) {
      await handleTabAction(id, action);
      return;
    }
    if (id === "usage:codex") {
      if (action === "copy") {
        command("copy", {
          text: `${state.usageRemaining}%`,
        });
      } else if (action === "open_analytics") {
        await bridge.request("tabs.open", { url: ANALYTICS_URL, active: true });
        command("hide");
      } else {
        await renderUsage(0);
      }
      return;
    }

    if (action === "refresh") {
      if (state.screen === "connection") await bridge.refreshStatus();
      if (state.screen === "usage") await renderUsage(0);
      else renderCurrent(0, state.query, { refresh: true });
      return;
    }
    if (action.startsWith("retry:")) {
      state.screen = action.slice("retry:".length);
      renderCurrent(0, state.query);
      return;
    }
    if (action === "connection") {
      enterScreen("connection");
      return;
    }
    if (action === "copy_token") {
      command("copy", { text: config.token });
      command("toast", { text: "Pairing token copied", style: "success" });
      return;
    }
    if (action === "copy_address") {
      command("copy", { text: `127.0.0.1:${config.port}` });
    }
  } catch (error) {
    renderBridgeError(0, error, state.screen);
  }
}

function handleBack() {
  const needsQueryReset = state.query.length > 0;
  state.screen = "root";
  state.query = "";
  if (needsQueryReset) command("setQuery", { text: "" });
  renderRoot(0, "");
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

process.stdin.on("end", () => {
  shutdown();
});

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
      renderCurrent(
        Number(message.rev) || 0,
        message.text != null ? message.text : message.query || "",
      );
      break;
    case "action":
      await handleAction(String(message.id || ""), message.action || "default");
      break;
    case "back":
      handleBack();
      break;
  }
}

let shuttingDown = false;
function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  clearTimeout(state.extensionEventTimer);
  bridge.close();
  setTimeout(() => process.exit(0), 20);
}
