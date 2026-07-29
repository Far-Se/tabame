#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { WebSocketServer } = require("ws");

const DEFAULT_PORT = 17373;
const CONFIG_PATH =
  process.env.TABAME_BROWSER_BRIDGE_CONFIG ||
  (process.env.LOCALAPPDATA
    ? path.join(process.env.LOCALAPPDATA, "Tabame", "browser-bridge.json")
    : path.join(process.cwd(), "browser-bridge.json"));
const LEGACY_CONFIG_PATH = process.env.LOCALAPPDATA
  ? path.join(
      process.env.LOCALAPPDATA,
      "Tabame",
      "plugins",
      "browser",
      "bridge-config.json",
    )
  : null;
const REQUEST_TIMEOUT_MS = 15_000;
const EXTENSION_ORIGIN = /^chrome-extension:\/\/[a-p]{32}\/?$/;
const PORT_RETRY_LIMIT = 30;
const PORT_RETRY_DELAY_MS = 100;

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

function readOrCreateSharedConfig() {
  function readConfig(filePath) {
    if (!filePath) return null;
    try {
      const parsed = JSON.parse(fs.readFileSync(filePath, "utf8"));
      const port = Number(parsed.port);
      if (
        typeof parsed.token === "string" &&
        parsed.token.length >= 32 &&
        Number.isInteger(port) &&
        port >= 1024 &&
        port <= 65535
      ) {
        return { token: parsed.token, port };
      }
    } catch {
      // Missing and invalid candidates are handled below.
    }
    return null;
  }

  const shared = readConfig(CONFIG_PATH);
  if (shared) return shared;

  const config =
    readConfig(LEGACY_CONFIG_PATH) || {
      port: DEFAULT_PORT,
      token: crypto.randomBytes(32).toString("base64url"),
    };
  fs.mkdirSync(path.dirname(CONFIG_PATH), { recursive: true });
  fs.writeFileSync(CONFIG_PATH, `${JSON.stringify(config, null, 2)}\n`, {
    encoding: "utf8",
    mode: 0o600,
  });
  return config;
}

function safeEqual(left, right) {
  const a = Buffer.from(String(left || "").replace(/\s+/g, ""));
  const b = Buffer.from(String(right || "").replace(/\s+/g, ""));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

class BrowserBridge {
  constructor(config, onStateChange, onEvent) {
    this.config = config;
    this.onStateChange = onStateChange;
    this.onEvent = onEvent;
    this.client = null;
    this.clientInfo = null;
    this.server = null;
    this.pending = new Map();
    this.startError = null;
    this.retryTimer = null;
    this.closed = false;
  }

  start(attempt = 0) {
    if (this.closed) return;
    const server = new WebSocketServer({
      host: "127.0.0.1",
      port: this.config.port,
      path: "/tabame",
      maxPayload: 256 * 1024,
    });

    server.on("connection", (socket, request) =>
      this.handleConnection(socket, request),
    );
    server.once("listening", () => {
      if (this.closed) {
        server.close();
        return;
      }
      this.server = server;
      this.startError = null;
      log(`Browser bridge listening on 127.0.0.1:${this.config.port}`);
      this.onStateChange();
    });
    server.once("error", (error) => {
      if (
        error.code === "EADDRINUSE" &&
        attempt < PORT_RETRY_LIMIT &&
        !this.closed
      ) {
        this.retryTimer = setTimeout(
          () => this.start(attempt + 1),
          PORT_RETRY_DELAY_MS,
        );
        return;
      }
      this.startError = error.message;
      log("Browser bridge error:", error.message);
      this.onStateChange();
    });
  }

  handleConnection(socket, request) {
    const origin = request.headers.origin || "";
    if (!EXTENSION_ORIGIN.test(origin)) {
      socket.close(1008, "Extension origin required");
      return;
    }

    let authenticated = false;
    const authTimer = setTimeout(() => {
      if (!authenticated) socket.close(1008, "Authentication timeout");
    }, 5_000);

    socket.on("message", (data) => {
      let message;
      try {
        message = JSON.parse(data.toString());
      } catch {
        socket.close(1003, "JSON required");
        return;
      }

      if (!authenticated) {
        if (
          message.type !== "hello" ||
          message.protocol !== 1 ||
          !safeEqual(message.token, this.config.token)
        ) {
          socket.close(1008, "Authentication failed");
          return;
        }
        authenticated = true;
        clearTimeout(authTimer);
        if (this.client && this.client !== socket) {
          this.client.close(1012, "Replaced by a new connector session");
        }
        this.client = socket;
        this.clientInfo = {
          extensionVersion: String(message.extensionVersion || "unknown"),
          connectedAt: new Date().toISOString(),
        };
        socket.send(
          JSON.stringify({
            type: "welcome",
            protocol: 1,
            serverVersion: "0.1.0",
          }),
        );
        this.onStateChange();
        return;
      }

      this.handleMessage(socket, message);
    });

    socket.on("close", () => {
      clearTimeout(authTimer);
      if (this.client !== socket) return;
      this.client = null;
      this.clientInfo = null;
      for (const pending of this.pending.values()) {
        clearTimeout(pending.timer);
        pending.reject(new Error("Browser connector disconnected"));
      }
      this.pending.clear();
      this.onStateChange();
    });

    socket.on("error", (error) => log("Connector socket error:", error.message));
  }

  handleMessage(socket, message) {
    if (message.type === "ping") {
      socket.send(JSON.stringify({ type: "pong", at: Date.now() }));
      return;
    }
    if (message.type === "response" && typeof message.id === "string") {
      const pending = this.pending.get(message.id);
      if (!pending) return;
      clearTimeout(pending.timer);
      this.pending.delete(message.id);
      if (message.ok) pending.resolve(message.result);
      else pending.reject(new Error(message.error || "Browser request failed"));
      return;
    }
    if (message.type === "event" && typeof message.event === "string") {
      this.onEvent(message.event, message.data || {});
    }
  }

  get connected() {
    return Boolean(this.client && this.client.readyState === this.client.OPEN);
  }

  request(method, params = {}, timeoutMs = REQUEST_TIMEOUT_MS) {
    if (!this.connected) {
      return Promise.reject(
        new Error("Waiting for the globally paired Tabame Connector."),
      );
    }
    const id = crypto.randomUUID();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Browser request timed out: ${method}`));
      }, timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
      this.client.send(JSON.stringify({ type: "request", id, method, params }));
    });
  }

  close() {
    this.closed = true;
    clearTimeout(this.retryTimer);
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(new Error("Browser tabs plugin closed"));
    }
    this.pending.clear();
    if (this.client) this.client.close(1001, "Launcher plugin closed");
    if (this.server) this.server.close();
  }
}

const config = readOrCreateSharedConfig();
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
  return /^https?:\/\//i.test(value) ? value : "globe";
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
  const needle = String(text || "").trim().toLowerCase();
  if (!needle) return tabs;
  return tabs.filter(
    (tab) =>
      String(tab.title || "").toLowerCase().includes(needle) ||
      String(tab.url || "").toLowerCase().includes(needle) ||
      String(tab.group?.title || "").toLowerCase().includes(needle),
  );
}

function renderWaiting(rev) {
  if (bridge.startError) {
    render(rev, "detail", {
      detail: {
        markdown: `# Browser bridge unavailable\n\n${escapeMarkdown(bridge.startError)}\n\nClose any other browser launcher plugin and reopen \`bwt\`.`,
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
      preview: { enabled: true },
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
