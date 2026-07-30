#!/usr/bin/env node
"use strict";

const REQUEST_TIMEOUT_MS = 15_000;
const config = { token: "", port: 17373 };

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
    const requestId = `bwt-${process.pid}-${Date.now()}-${this.requestCounter++}`;
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

const state = {
  initialized: false,
  query: "",
  rev: 0,
  itemData: new Map(),
  refreshTimer: null,
};

const bridge = new BrowserBridge(
  config,
  () => {
    if (state.initialized) void renderTabs(0, state.query, true);
  },
  (event) => {
    if (event !== "tabs.changed" || !state.initialized) return;
    clearTimeout(state.refreshTimer);
    state.refreshTimer = setTimeout(
      () => void renderTabs(0, state.query, true),
      180,
    );
  },
);
bridge.start();

function favicon(tab) {
  const value = String(tab.favIconUrl || "");
  return /^(?:https?:\/\/|data:image\/)/i.test(value) ? value : "globe";
}

function siteName(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "Browser page";
  }
}

function escapeMarkdown(value) {
  return String(value || "").replace(/([\\`*_{}[\]()#+\-.!])/g, "\\$1");
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

function tabItem(tab) {
  const groupTag = groupAccessory(tab);
  const item = {
    id: `tab:${tab.id}`,
    title: tab.title || "Untitled tab",
    subtitle: tab.url || "No URL",
    icon: favicon(tab),
    section: tab.active ? "Active tab" : `Window ${tab.windowId}`,
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
        { label: "Site", text: siteName(tab.url), icon: "globe" },
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

function renderWaiting(rev) {
  if (!bridge.enabled) {
    render(rev, "detail", {
      detail: {
        markdown:
          "# Persistent browser connector is off\n\nOpen **Launcher Plugins** and enable **Persistent browser connector**, then return to `bwt`.",
      },
      actions: [{ id: "refresh", title: "Check again", icon: "refresh" }],
    });
    return;
  }
  if (bridge.startError) {
    render(rev, "detail", {
      detail: {
        markdown: `# Browser bridge unavailable\n\n${escapeMarkdown(bridge.startError)}\n\nCheck the connector status in **Launcher Plugins**.`,
      },
      actions: [{ id: "refresh", title: "Try again", icon: "refresh" }],
    });
    return;
  }
  render(rev, "list", {
    loading: true,
    loadingText: "Waiting for the globally paired Tabame Connector…",
    items: [],
    placeholder: "Filter tabs by title or URL…",
  });
}

async function renderTabs(rev, text, quiet = false) {
  state.query = String(text || "");
  state.rev = rev;
  if (!bridge.connected) {
    renderWaiting(rev);
    return;
  }
  if (!quiet) {
    render(rev, "list", {
      loading: true,
      loadingText: "Reading browser tabs…",
      items: [],
      placeholder: "Filter tabs by title or URL…",
    });
  }

  try {
    const result = await bridge.request("tabs.list");
    state.itemData.clear();
    const tabs = filterTabs(result.tabs || [], state.query).sort((a, b) => {
      if (a.active !== b.active) return a.active ? -1 : 1;
      if (a.windowId !== b.windowId) return a.windowId - b.windowId;
      return a.index - b.index;
    });
    render(rev, "list", {
      items: tabs.map(tabItem),
      preview: { enabled: false, wide: false },
      placeholder: "Filter tabs by title or URL…",
      empty: {
        icon: "search",
        title: "No matching tabs",
        hint: state.query
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
    if (!bridge.connected) {
      renderWaiting(rev);
      return;
    }
    render(rev, "detail", {
      detail: {
        markdown: `# Could not read browser tabs\n\n${escapeMarkdown(error.message)}`,
      },
      actions: [{ id: "refresh", title: "Try again", icon: "refresh" }],
    });
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
      return renderTabs(0, state.query, true);
    case "mute":
      await bridge.request("tabs.mute", {
        tabId: tab.id,
        muted: !tab.muted,
      });
      return renderTabs(0, state.query, true);
    case "pin":
      await bridge.request("tabs.pin", {
        tabId: tab.id,
        pinned: !tab.pinned,
      });
      return renderTabs(0, state.query, true);
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
    if (id.startsWith("tab:")) {
      await handleTabAction(id, action);
    } else if (action === "refresh") {
      await bridge.refreshStatus();
      await renderTabs(0, state.query);
    }
  } catch (error) {
    render(0, "detail", {
      detail: {
        markdown: `# Browser action failed\n\n${escapeMarkdown(error.message)}`,
      },
      actions: [{ id: "refresh", title: "Return to tabs", icon: "refresh" }],
    });
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
      await renderTabs(
        Number(message.rev) || 0,
        message.text != null ? message.text : message.query || "",
      );
      break;
    case "action":
      await handleAction(String(message.id || ""), message.action || "default");
      break;
  }
}

let shuttingDown = false;
function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  clearTimeout(state.refreshTimer);
  bridge.close();
  setTimeout(() => process.exit(0), 20);
}
