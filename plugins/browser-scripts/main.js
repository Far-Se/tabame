#!/usr/bin/env node
"use strict";

// This plugin is intentionally small and heavily commented. It is a runnable
// reference for AI tools generating browser-capable Tabame plugins.
//
// The important pattern is:
//   1. Ask Tabame for a browserBridge request.
//   2. Open/select a tab with an allowlisted tabs.* method.
//   3. Run site-specific JavaScript with javascript.execute.
//   4. Validate the returned JSON in the plugin process.
//   5. Close any temporary tab in a finally block.

const ANALYTICS_URL =
  "https://chatgpt.com/codex/cloud/settings/analytics#usage";
const REQUEST_TIMEOUT_MS = 30_000;
const READY_TIMEOUT_MS = 20_000;

// This is the site-specific part of the example. It runs in the connected
// browser page, while the surrounding workflow stays in the plugin process.
// The bridge exposes the request's JSON `input` value to this script.
const CODEX_USAGE_SCRIPT = `
const deadline = Date.now() + Math.max(1000, Number(input?.timeoutMs) || 20000);
let snapshot = null;

function parseResetDate(bodyText) {
  const match = bodyText.match(
    /Resets?\\s+([A-Z][a-z]{2}\\s+\\d{1,2},\\s+\\d{4}\\s+\\d{1,2}:\\d{2}\\s+[AP]M)/i,
  );

  if (!match) return null;

  // This intentionally uses the browser's local timezone, just like a page
  // user would read the date.
  const date = new Date(match[1]);
  if (Number.isNaN(date.getTime())) return null;

  const remainingMs = Math.max(0, date.getTime() - Date.now());
  const totalMinutes = Math.ceil(remainingMs / 60000);
  const days = Math.floor(totalMinutes / (24 * 60));
  const hours = Math.floor((totalMinutes % (24 * 60)) / 60);
  const minutes = totalMinutes % 60;
  const parts = [];

  if (days > 0) parts.push(days + " day" + (days === 1 ? "" : "s"));
  if (hours > 0) parts.push(hours + " hour" + (hours === 1 ? "" : "s"));
  if (minutes > 0 || parts.length === 0) {
    parts.push(minutes + " minute" + (minutes === 1 ? "" : "s"));
  }

  return {
    resetDateText: match[1],
    resetDate: date.toISOString(),
    remainingMs,
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

// A second, intentionally simpler example: execute a small script in the
// currently active page without opening a temporary tab.
const ACTIVE_PAGE_SCRIPT = `
const bodyText = document.body ? document.body.innerText : "";
return {
  title: document.title,
  url: location.href,
  selection: String(window.getSelection ? window.getSelection() : ""),
  bodyText: bodyText.slice(0, 4000),
};
`;

function send(message) {
  // stdout is reserved for newline-delimited protocol messages.
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

function command(name, fields = {}) {
  send({ type: "command", command: name, ...fields });
}

function render(rev, view, fields = {}) {
  send({ type: "render", rev, view, ...fields });
}

function log(...parts) {
  // Diagnostics belong on stderr, never in the render stream.
  console.error(...parts);
}

/**
 * Small adapter for Tabame's app-owned browser bridge.
 *
 * The plugin does not open its own WebSocket. It asks Tabame to forward an
 * allowlisted browser request and correlates the asynchronous reply by ID.
 */
class BrowserBridge {
  constructor(onStateChange) {
    this.onStateChange = onStateChange;
    this.enabled = false;
    this.running = false;
    this.connected = false;
    this.port = 17373;
    this.token = "";
    this.clientInfo = {};
    this.pending = new Map();
    this.requestCounter = 0;
    this.startError = null;
  }

  start() {
    void this.refreshStatus().catch(() => {});
  }

  async refreshStatus() {
    try {
      const status = await this.callHost("status");
      this.applyStatus(status);
      this.onStateChange();
      return status;
    } catch (error) {
      this.startError = error instanceof Error ? error.message : String(error);
      this.onStateChange();
      throw error;
    }
  }

  handleHostMessage(message) {
    if (typeof message.requestId === "string") {
      const request = this.pending.get(message.requestId);
      if (!request) return;

      clearTimeout(request.timer);
      this.pending.delete(message.requestId);
      if (message.ok) {
        request.resolve(message.result);
      } else {
        request.reject(
          new Error(message.error || "Browser bridge request failed"),
        );
      }
      return;
    }

    if (message.event === "connection.changed") {
      this.applyStatus(message.data || {});
      this.onStateChange();
    }
  }

  applyStatus(status) {
    this.enabled = Boolean(status.enabled);
    this.running = Boolean(status.running);
    this.connected = Boolean(status.connected);
    if (Number.isInteger(Number(status.port))) {
      this.port = Number(status.port);
    }
    if (typeof status.token === "string") {
      this.token = status.token;
    }

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
    const requestId = `browser-scripts-${process.pid}-${Date.now()}-${this.requestCounter++}`;
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
      pending.reject(new Error("Browser Scripts plugin closed"));
    }
    this.pending.clear();
  }
}

const state = {
  initialized: false,
  screen: "root",
  query: "",
  usage: null,
  activePage: null,
};

const bridge = new BrowserBridge(() => {
  // A connection event should refresh the root status without interrupting a
  // script that is already running on a sub-screen.
  if (shuttingDown || !state.initialized) return;
  if (state.screen === "root" || state.screen === "connection") {
    renderCurrent(0, state.query);
  }
});
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
      id: "command:active",
      title: "Inspect active tab",
      subtitle: "The smallest javascript.execute example",
      icon: "search",
      accessories: [connectionAccessory()],
      preview: {
        markdown:
          "## Active-tab script\n\nRuns a plugin-owned function against the currently active HTTP(S) tab and returns JSON containing the title, URL, selection, and a short text sample.",
      },
    },
    {
      id: "command:codex",
      title: "Codex usage",
      subtitle: "A complete temporary-tab browser script example",
      icon: "chart",
      accessories: [connectionAccessory()],
      preview: {
        markdown:
          "## Codex usage workflow\n\nOpens ChatGPT analytics in an **inactive temporary tab**, waits for the dynamic page to finish loading, runs site-specific extraction JavaScript, validates the JSON result, and closes the tab in a `finally` block.",
      },
    },
    {
      id: "command:connection",
      title: "Connection & pairing",
      subtitle: bridge.connected
        ? `Connector ${bridge.clientInfo.extensionVersion} is ready`
        : `Enable the connector and pair it on port ${bridge.port}`,
      icon: bridge.connected ? "link" : "key",
      accessories: [connectionAccessory()],
      preview: {
        markdown:
          "## App-owned browser bridge\n\nThe plugin sends browserBridge commands to Tabame. Tabame owns the local connector and forwards only allowlisted browser methods to the companion extension.",
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
    placeholder: "Choose a browser script…",
    emptyText: "No browser script matches this search",
  });
}

function escapeMarkdown(value) {
  return String(value ?? "").replace(/([\\`*_{}[\]()#+\-.!|>])/g, "\\$1");
}

function codeBlock(value) {
  return String(value ?? "").replace(/```/g, "``\\`");
}

function truncate(value, maxLength) {
  const text = String(value ?? "");
  return text.length > maxLength ? `${text.slice(0, maxLength)}…` : text;
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

function renderError(rev, error, title) {
  const message = error instanceof Error ? error.message : String(error);
  render(rev, "detail", {
    canGoBack: true,
    detail: {
      markdown: [
        `# ${escapeMarkdown(title)}`,
        "",
        escapeMarkdown(message),
        "",
        "Open **Connection & pairing** if the connector is disabled or offline.",
      ].join("\n"),
    },
    actions: [
      { id: "retry", title: "Try again", icon: "refresh" },
      { id: "connection", title: "Connection & pairing", icon: "key" },
    ],
  });
}

function renderConnection(rev) {
  const token = bridge.token;
  const tokenDisplay = token
    ? (token.match(/.{1,6}/g) || [token]).join(" ")
    : "Not available while the connector is disabled";
  const markdown = !bridge.enabled
    ? [
        "# Persistent browser connector is off",
        "",
        "Open **Launcher Plugins** and enable **Persistent browser connector**.",
        "",
        "The bridge is optional and remains stopped while that setting is off.",
      ].join("\n")
    : bridge.connected
      ? [
          "# Browser connector is online",
          "",
          "This plugin can now run trusted JavaScript in the connected HTTP(S) tabs.",
          "",
          "Use **Escape** to return to the script examples.",
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
          "> Treat this token like a credential. Never commit or publish it.",
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
            : bridge.connected
              ? "Connected"
              : "Waiting for extension",
          color: !bridge.enabled
            ? "#8A7F88"
            : bridge.connected
              ? "#3D9B72"
              : "#D18B47",
        },
        { label: "Address", text: `127.0.0.1:${bridge.port}`, icon: "server" },
        ...(bridge.connected
          ? [
              {
                label: "Extension",
                text: bridge.clientInfo.extensionVersion,
                icon: "extension",
              },
              {
                label: "Browser",
                text: bridge.clientInfo.browser,
                icon: "globe",
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
      { id: "copy_address", title: "Copy bridge address", icon: "copy" },
      { id: "refresh", title: "Refresh status", icon: "refresh" },
    ],
  });
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitForTabReady(tabId, timeoutMs = READY_TIMEOUT_MS) {
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

/**
 * Complete browser-task pattern, based on the Browser plugin's Codex Usage
 * command. Site-specific code stays in CODEX_USAGE_SCRIPT above; this helper
 * owns the temporary tab lifecycle and always attempts cleanup.
 */
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
        .catch((error) => log("Could not close temporary tab:", error.message));
    }
  }
}

async function inspectActivePage() {
  const execution = await bridge.request(
    "javascript.execute",
    { code: ACTIVE_PAGE_SCRIPT },
    REQUEST_TIMEOUT_MS,
  );
  const result = execution?.result;
  if (!result || typeof result !== "object") {
    throw new Error("The active-tab script returned an invalid result");
  }
  return result;
}

async function renderCodexUsage(rev) {
  render(rev, "list", {
    loading: true,
    loadingText: "Opening ChatGPT analytics in the background…",
    items: [],
    wide: true,
    canGoBack: true,
  });

  try {
    const result = await fetchCodexUsage();
    const remaining = Math.max(
      0,
      Math.min(100, Number(result.remainingPercent)),
    );
    const used = Number.isFinite(Number(result.usedPercent))
      ? Number(result.usedPercent)
      : 100 - remaining;
    state.usage = result;

    render(rev, "list", {
      canGoBack: true,
      preview: { enabled: true },
      items: [
        {
          id: "usage:codex",
          title: `${remaining}% Codex usage remaining`,
          subtitle: `${used}% used · checked ${formatTime(result.fetchedAt)}`,
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
              { label: "Used", text: `${used}%` },
              {
                label: "Checked",
                text: formatTime(result.fetchedAt),
                icon: "clock",
              },
              {
                label: "Resets At",
                text: result.resetDateText || "Unknown",
                icon: "clock",
              },
              {
                label: "Resets In",
                text: result.remainingText || "Unknown",
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
    renderError(rev, error, "Codex usage failed");
  }
}

async function renderActivePage(rev) {
  render(rev, "detail", {
    loading: true,
    loadingText: "Reading the active browser tab…",
    canGoBack: true,
    detail: { markdown: "# Active tab\n\nReading page data…" },
  });

  try {
    const result = await inspectActivePage();
    state.activePage = result;
    const title = result.title || "Untitled page";
    const url = result.url || "";
    const selection = result.selection || "(no text selected)";
    const bodyLength = String(result.bodyText || "").length;

    render(rev, "detail", {
      canGoBack: true,
      detail: {
        wide: true,
        markdown: [
          "# Active tab",
          "",
          `**${escapeMarkdown(title)}**`,
          "",
          "### Selected text",
          "",
          "```text",
          codeBlock(selection),
          "```",
        ].join("\n"),
        metadata: [
          { label: "URL", text: url || "Unavailable", url: url || undefined },
          {
            label: "Readable text",
            text: `${bodyLength} characters`,
            icon: "document",
          },
        ],
      },
      actions: [
        { id: "copy_url", title: "Copy URL", icon: "copy" },
        { id: "open", title: "Open in browser", icon: "open" },
        { id: "refresh", title: "Run script again", icon: "refresh" },
      ],
    });
  } catch (error) {
    renderError(rev, error, "Active-tab script failed");
  }
}

function renderCurrent(rev, text) {
  state.query = String(text || "");
  switch (state.screen) {
    case "active":
      return renderActivePage(rev);
    case "codex":
      return renderCodexUsage(rev);
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
    void renderCurrent(0, "");
  }
}

async function handleAction(id, action) {
  try {
    if (id === "command:active") {
      enterScreen("active");
      return;
    }
    if (id === "command:codex") {
      enterScreen("codex");
      return;
    }
    if (id === "command:connection") {
      enterScreen("connection");
      return;
    }

    if (action === "retry") {
      void renderCurrent(0, state.query);
      return;
    }
    if (action === "connection") {
      enterScreen("connection");
      return;
    }
    if (action === "refresh") {
      if (state.screen === "connection") {
        await bridge.refreshStatus();
      } else {
        void renderCurrent(0, state.query);
      }
      return;
    }

    if (state.screen === "codex" && id === "usage:codex") {
      if (action === "copy" && state.usage) {
        command("copy", { text: `${state.usage.remainingPercent}%` });
      } else if (action === "open_analytics") {
        await bridge.request("tabs.open", {
          url: ANALYTICS_URL,
          active: true,
        });
        command("hide");
      } else {
        void renderCodexUsage(0);
      }
      return;
    }

    // Detail-view actions are frame-level, so their incoming id is empty.
    if (state.screen === "active" && (id === "" || id === "page:active")) {
      if (action === "copy_url" && state.activePage?.url) {
        command("copy", { text: state.activePage.url });
      } else if (action === "open" && state.activePage?.url) {
        command("open", { url: state.activePage.url });
        command("hide");
      } else {
        void renderActivePage(0);
      }
      return;
    }

    if (state.screen === "connection") {
      if (action === "copy_token" && bridge.token) {
        command("copy", { text: bridge.token });
        command("toast", { text: "Pairing token copied", style: "success" });
      } else if (action === "copy_address") {
        command("copy", { text: `127.0.0.1:${bridge.port}` });
      }
    }
  } catch (error) {
    renderError(0, error, "Browser bridge request failed");
  }
}

function handleBack() {
  const needsQueryReset = state.query.length > 0;
  state.screen = "root";
  state.query = "";
  if (needsQueryReset) {
    command("setQuery", { text: "" });
  } else {
    renderRoot(0, "");
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
      void renderCurrent(
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
  bridge.close();
  setTimeout(() => process.exit(0), 20);
}
