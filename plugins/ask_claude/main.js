#!/usr/bin/env node
"use strict";

// Ask Claude — a Tabame launcher plugin.
//
// Keyword: "ask". On first use it opens (or reuses) a claude.ai tab through
// Tabame's app-owned browser bridge. Every message you submit from the
// launcher is typed into that tab, sent, and the plugin waits for Claude's
// reply in-page before relaying the text back into the launcher's chat view.
//
// Typing the prompt and clicking send happen inside one javascript.execute
// call that runs in the connected page. The plugin then polls that same tab
// in short steps until the assistant response has finished streaming.
//
// claude.ai's DOM can change. Selectors are kept in config.json (with
// built-in fallbacks below) so they can be tweaked without touching this
// file if a UI update breaks detection.

const fs = require("fs");
const path = require("path");

const DEFAULT_CONFIG = {
  claudeUrl: "https://claude.ai/new",
  claudeOrigin: "https://claude.ai",
  responseTimeoutMs: 180_000,
  promptSelectors: [
    'div[contenteditable="true"].ProseMirror',
    'div[contenteditable="true"][data-placeholder]',
    'div[contenteditable="true"]',
    "textarea[placeholder]",
  ],
  sendButtonSelectors: [
    'button[aria-label="Send message" i]',
    'button[aria-label*="Send" i]',
    'button[data-testid="send-button"]',
  ],
  userMessageSelectors: [
    '[data-testid="user-message"]',
    '[data-cds="UserMessage"]',
    '[data-message-author-role="user"]',
  ],
  assistantMessageSelectors: [
    '[role="article"] .font-claude-response .standard-markdown',
    "[data-is-streaming] .font-claude-response .standard-markdown",
    '[role="article"] .font-claude-response',
    "[data-is-streaming] .font-claude-response",
    '[data-message-author-role="assistant"]',
    '[data-testid="assistant-message"]',
    '[role="article"] [data-is-streaming]',
    "[data-is-streaming]",
  ],
  // Generic fallback used only if the assistant-specific selectors above
  // find nothing — filtered to exclude anything matching userMessageSelectors.
  messageSelectors: [
    '[data-testid$="-message"]',
    "main [data-message-author-role]",
  ],
  streamingSelector: '[data-is-streaming="true"]',
};

function loadConfig() {
  const configPath = path.join(__dirname, "config.json");
  if (!fs.existsSync(configPath)) return { ...DEFAULT_CONFIG };
  try {
    const raw = JSON.parse(fs.readFileSync(configPath, "utf8"));
    return { ...DEFAULT_CONFIG, ...raw };
  } catch (error) {
    log("Ignoring invalid config.json:", error.message);
    return { ...DEFAULT_CONFIG };
  }
}

const CONFIG = loadConfig();
const REQUEST_TIMEOUT_MS = 30_000;
const READY_TIMEOUT_MS = 20_000;
const POLL_INTERVAL_MS = 500;
const POLL_REQUEST_TIMEOUT_MS = 15_000;
const STABLE_FOR_MS = 1_200;
const NO_PROGRESS_TIMEOUT_MS = 25_000;
const MAX_CONSECUTIVE_POLL_FAILURES = 5;

// Shared helpers injected into both in-page scripts. Assistant messages
// only — never the bubble you just typed. Prefers the dedicated assistant
// selectors; if none match, falls back to the generic message list with
// anything that also looks like a user message excluded.
const MESSAGE_HELPERS_SNIPPET = `
const USER_MESSAGE_SELECTORS = ${JSON.stringify(CONFIG.userMessageSelectors)};
const ASSISTANT_MESSAGE_SELECTORS = ${JSON.stringify(CONFIG.assistantMessageSelectors)};
const GENERIC_MESSAGE_SELECTORS = ${JSON.stringify(CONFIG.messageSelectors)};

function firstMatch(selectors) {
  for (const sel of selectors) {
    const node = document.querySelector(sel);
    if (node) return node;
  }
  return null;
}
function firstMatchAll(selectors) {
  for (const sel of selectors) {
    try {
      const nodes = document.querySelectorAll(sel);
      if (nodes.length) return Array.from(nodes);
    } catch {
      // Ignore a stale selector so the remaining fallbacks can be tried.
    }
  }
  return [];
}
function matchesAny(node, selectors) {
  return selectors.some((sel) => {
    try {
      return node.matches(sel);
    } catch {
      return false;
    }
  });
}
function getAssistantMessages() {
  const direct = firstMatchAll(ASSISTANT_MESSAGE_SELECTORS);
  if (direct.length) return direct;

  // Claude currently exposes each turn as an article. Assistant articles have
  // a response body or streaming marker; user articles contain user-message.
  const semantic = firstMatchAll(['[role="article"]'])
    .map(
      (article) =>
        article.querySelector(".font-claude-response .standard-markdown") ||
        article.querySelector("[data-is-streaming] .font-claude-response") ||
        article.querySelector(".font-claude-response") ||
        article.querySelector("[data-is-streaming]"),
    )
    .filter(Boolean);
  if (semantic.length) return semantic;

  const generic = firstMatchAll(GENERIC_MESSAGE_SELECTORS);
  return generic.filter((node) => !matchesAny(node, USER_MESSAGE_SELECTORS));
}
function messageText(node) {
  if (!node) return "";
  const content =
    typeof node.matches === "function" &&
    (node.matches(".standard-markdown") || node.matches(".font-claude-response"))
      ? node
      : (typeof node.querySelector === "function" &&
          node.querySelector(".standard-markdown, .font-claude-response")) || node;
  const controlsSelector =
    'button, [role="button"], [role="status"], [aria-live], .sr-only, [aria-hidden="true"], svg';
  let readable = content;
  if (
    typeof content.querySelectorAll === "function" &&
    content.querySelectorAll(controlsSelector).length > 0 &&
    typeof content.cloneNode === "function"
  ) {
    readable = content.cloneNode(true);
    readable
      .querySelectorAll(controlsSelector)
      .forEach((element) => element.remove());
  }
  return String(readable.innerText || readable.textContent || "").trim();
}
`;

// Runs inside the connected Claude.ai tab. Types the message, clicks send
// (or presses Enter), and returns immediately — it does NOT wait for a
// reply. Waiting happens on the Node side via POLL_SCRIPT below, in short,
// individually-timed steps, so a single call can never hang the whole
// round trip.
const SEND_SCRIPT = `
const text = String(input?.text ?? "");

const PROMPT_SELECTORS = ${JSON.stringify(CONFIG.promptSelectors)};
const SEND_BUTTON_SELECTORS = ${JSON.stringify(CONFIG.sendButtonSelectors)};
${MESSAGE_HELPERS_SNIPPET}

const promptEl = firstMatch(PROMPT_SELECTORS);
if (!promptEl) {
  throw new Error(
    "Could not find Claude's message box on this page. Make sure a claude.ai conversation is open and finished loading.",
  );
}

promptEl.focus();
document.execCommand("selectAll", false, null);
document.execCommand("delete", false, null);
document.execCommand("insertText", false, text);
promptEl.dispatchEvent(new InputEvent("input", { bubbles: true }));

await new Promise((r) => setTimeout(r, 300));

const beforeCount = getAssistantMessages().length;

const sendBtn = firstMatch(SEND_BUTTON_SELECTORS);
if (sendBtn && !sendBtn.disabled) {
  sendBtn.click();
} else {
  promptEl.dispatchEvent(
    new KeyboardEvent("keydown", {
      bubbles: true,
      key: "Enter",
      code: "Enter",
      keyCode: 13,
      which: 13,
    }),
  );
}

return { beforeCount, url: location.href };
`;

// Runs inside the connected Claude.ai tab, once per poll. Cheap and quick —
// just reports current state, never waits. Node decides when to stop
// polling. Includes diagnostics (url, whether the prompt box is still
// found) so a stalled wait can report something actionable instead of
// just "still thinking".
const POLL_SCRIPT = `
${MESSAGE_HELPERS_SNIPPET}
const PROMPT_SELECTORS = ${JSON.stringify(CONFIG.promptSelectors)};
const STREAMING_SELECTOR = ${JSON.stringify(CONFIG.streamingSelector)};

const nodes = getAssistantMessages();
const last = nodes[nodes.length - 1];
const streaming = last
  ? (typeof last.matches === "function" && last.matches(STREAMING_SELECTOR)) ||
    (typeof last.closest === "function" && Boolean(last.closest(STREAMING_SELECTOR)))
  : false;
return {
  count: nodes.length,
  text: last ? messageText(last) : "",
  streaming,
  url: location.href,
  promptFound: Boolean(firstMatch(PROMPT_SELECTORS)),
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

// javascript.execute returns an execution envelope; browser-scripts and the
// bridge contract expose the page function's value as `execution.result`.
// Keep a direct-value fallback for older connector versions.
function unwrapBrowserResult(execution) {
  if (
    execution &&
    typeof execution === "object" &&
    Object.prototype.hasOwnProperty.call(execution, "result")
  ) {
    return execution.result;
  }
  return execution;
}

/** Thin adapter over Tabame's app-owned browser bridge. */
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
    }
  }

  applyStatus(status) {
    this.enabled = Boolean(status.enabled);
    this.running = Boolean(status.running);
    this.connected = Boolean(status.connected);
    if (Number.isInteger(Number(status.port))) this.port = Number(status.port);
    if (typeof status.token === "string") this.token = status.token;
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
    const requestId = `ask-claude-${process.pid}-${Date.now()}-${this.requestCounter++}`;
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
      pending.reject(new Error("Ask Claude plugin closed"));
    }
    this.pending.clear();
  }
}

const state = {
  initialized: false,
  screen: "connection", // "connection" | "chat"
  tabId: null,
  messages: [], // {id, role: "user"|"assistant"|"error"|"system", text, time}
  busy: false,
  thinkingStartedAt: null,
  streamingMessageId: null,
  nextId: 1,
};

// Startup status and init can arrive at the same time. Share the in-flight
// operations so only one Claude tab can be opened for this plugin instance.
let tabOpenPromise = null;
let openClaudePromise = null;

const bridge = new BrowserBridge(() => {
  if (shuttingDown || !state.initialized) return;
  if (state.screen === "connection" && bridge.connected) {
    void openClaudeTab(0);
  } else if (state.screen === "connection") {
    renderConnection(0);
  }
});
bridge.start();

function newId(prefix) {
  return `${prefix}-${state.nextId++}`;
}

function formatTime(date = new Date()) {
  return new Intl.DateTimeFormat(undefined, {
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

function pushMessage(role, text) {
  const message = { id: newId(role), role, text, time: formatTime() };
  state.messages.push(message);
  return message;
}

function updateStreamingMessage(text) {
  const nextText = String(text ?? "").trim();
  if (!nextText) return false;

  const message = state.streamingMessageId
    ? state.messages.find(
        (candidate) => candidate.id === state.streamingMessageId,
      )
    : null;
  if (message) {
    if (message.text === nextText) return false;
    message.text = nextText;
    return true;
  }

  const created = pushMessage("assistant", nextText);
  state.streamingMessageId = created.id;
  return true;
}

function finishAssistantMessage(text) {
  const nextText = String(text ?? "").trim();
  const message = state.streamingMessageId
    ? state.messages.find(
        (candidate) => candidate.id === state.streamingMessageId,
      )
    : null;
  if (message) {
    message.text = nextText;
  } else {
    pushMessage("assistant", nextText);
  }
}

function escapeMarkdown(value) {
  return String(value ?? "").replace(/([\\`*_{}[\]()#+\-.!|>])/g, "\\$1");
}

async function waitForTabReady(tabId, timeoutMs = READY_TIMEOUT_MS) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const snapshot = await bridge.request("tabs.list");
    const tab = (snapshot.tabs || []).find(
      (candidate) => candidate.id === tabId,
    );
    if (!tab) throw new Error("The Claude tab was closed.");
    if (tab.status === "complete") return tab;
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error("The Claude tab did not finish loading.");
}

function ensureTabOpen() {
  if (tabOpenPromise) return tabOpenPromise;

  const opening = (async () => {
    if (state.tabId != null) {
      const snapshot = await bridge.request("tabs.list");
      if ((snapshot.tabs || []).some((t) => t.id === state.tabId)) {
        return state.tabId;
      }
      state.tabId = null;
    }

    const list = await bridge.request("tabs.list");
    const existing = (list.tabs || []).find(
      (t) => typeof t.url === "string" && t.url.startsWith(CONFIG.claudeOrigin),
    );
    if (existing) {
      state.tabId = existing.id;
    } else {
      const tab = await bridge.request("tabs.open", {
        url: CONFIG.claudeUrl,
        active: true,
      });
      state.tabId = tab.id;
      await waitForTabReady(state.tabId);
    }
    return state.tabId;
  })();

  tabOpenPromise = opening;
  const clearOpening = () => {
    if (tabOpenPromise === opening) tabOpenPromise = null;
  };
  void opening.then(clearOpening, clearOpening);
  return opening;
}

function openClaudeTab(rev) {
  if (openClaudePromise) return openClaudePromise;

  const opening = (async () => {
    render(rev, "chat", {
      loading: true,
      loadingText: "Opening Claude in your browser…",
      items: [],
    });
    try {
      await ensureTabOpen();
      state.screen = "chat";
      if (state.messages.length === 0) {
        pushMessage(
          "system",
          "Connected. Type a message and press Enter to send it to Claude.",
        );
      }
      renderChat(rev);
    } catch (error) {
      renderError(rev, error, "Could not open Claude");
    }
  })();

  openClaudePromise = opening;
  const clearOpening = () => {
    if (openClaudePromise === opening) openClaudePromise = null;
  };
  void opening.then(clearOpening, clearOpening);
  return opening;
}

function chatTitleFor() {
  return bridge.connected ? "Ask Claude" : "Ask Claude (bridge offline)";
}

function iconFor(role) {
  if (role === "user") return "person";
  if (role === "error") return "warning";
  if (role === "system") return "info";
  return "star";
}
function titleFor(role) {
  if (role === "user") return "You";
  if (role === "error") return "Error";
  if (role === "system") return "Ask Claude";
  return "Claude";
}

function renderChat(rev) {
  const items = state.messages.map((m) => ({
    id: m.id,
    title: titleFor(m.role),
    subtitle: m.text,
    icon: iconFor(m.role),
    lines: 3,
    accessories: [
      { text: m.id === state.streamingMessageId ? "Writing…" : m.time },
    ],
  }));

  if (state.busy && !state.streamingMessageId) {
    const elapsed = state.thinkingStartedAt
      ? Math.max(0, Math.round((Date.now() - state.thinkingStartedAt) / 1000))
      : 0;
    items.push({
      id: "typing",
      title: "Claude",
      subtitle: "Thinking…",
      icon: "star",
      accessories: [{ text: `${elapsed}s` }],
    });
  }

  render(rev, "chat", {
    page: { id: "ask:chat", title: chatTitleFor() },
    inputMode: "submit",
    placeholder: state.busy ? "Waiting for Claude…" : "Message Claude…",
    emptyText: "Say something to start the conversation",
    items,
    actions: [
      { id: "new_chat", title: "New conversation", icon: "add" },
      { id: "reconnect", title: "Reconnect bridge", icon: "refresh" },
    ],
  });
}

function renderError(rev, error, title) {
  const message = error instanceof Error ? error.message : String(error);
  render(rev, "detail", {
    page: { id: "ask:error", title: "Ask Claude" },
    detail: {
      markdown: [
        `# ${escapeMarkdown(title)}`,
        "",
        escapeMarkdown(message),
        "",
        "Open **Reconnect bridge** or try again.",
      ].join("\n"),
    },
    actions: [
      { id: "retry", title: "Try again", icon: "refresh" },
      { id: "reconnect", title: "Reconnect bridge", icon: "refresh" },
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
        "Open **Launcher Plugins** and enable **Persistent browser connector**, then come back here.",
      ].join("\n")
    : bridge.connected
      ? [
          "# Browser connector is online",
          "",
          "Ask Claude can now open and control a claude.ai tab.",
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
    page: { id: "ask:connection", title: "Ask Claude" },
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
      { id: "reconnect", title: "Refresh status", icon: "refresh" },
    ],
  });
}

function renderCurrent(rev) {
  if (state.screen === "chat") renderChat(rev);
  else renderConnection(rev);
}

async function handleInit(rev, text) {
  if (state.initialized) {
    renderCurrent(rev);
    return;
  }
  state.initialized = true;

  render(rev, "chat", {
    loading: true,
    loadingText: "Checking the browser bridge…",
    items: [],
  });
  try {
    if (!bridge.connected) await bridge.refreshStatus().catch(() => {});
  } catch {
    /* handled by applyStatus/startError */
  }

  if (bridge.connected) {
    await openClaudeTab(rev);
  } else {
    state.screen = "connection";
    renderConnection(rev);
  }
}

/**
 * Polls the Claude tab in short, individually-timed steps until a new
 * assistant message appears and its text stops changing (and no streaming
 * marker is present), or the overall budget runs out. Each poll is capped
 * at POLL_REQUEST_TIMEOUT_MS, so a single flaky round trip can't hang the
 * whole wait — it's just retried on the next tick. Calls onProgress() after
 * every poll with the latest response text so the chat can update live.
 */
async function waitForReply(
  beforeCount,
  overallTimeoutMs,
  onProgress = () => {},
) {
  const deadline = Date.now() + overallTimeoutMs;
  const noProgressDeadline = Date.now() + NO_PROGRESS_TIMEOUT_MS;
  let sawNewMessage = false;
  let lastText = "";
  let stableSince = 0;
  let lastDiagnostic = null;
  let consecutiveFailures = 0;

  while (Date.now() < deadline) {
    let result = null;
    try {
      const execution = await bridge.request(
        "javascript.execute",
        { tabId: state.tabId, code: POLL_SCRIPT },
        POLL_REQUEST_TIMEOUT_MS,
      );
      result = unwrapBrowserResult(execution);
      consecutiveFailures = 0;
    } catch (error) {
      // A single poll failing (e.g. the tab briefly navigating) isn't
      // fatal — log and try again next tick rather than aborting the wait.
      consecutiveFailures += 1;
      log(
        "Poll attempt failed, will retry:",
        error instanceof Error ? error.message : error,
      );
      if (consecutiveFailures >= MAX_CONSECUTIVE_POLL_FAILURES) {
        throw new Error(
          `Lost contact with the Claude tab after ${consecutiveFailures} failed polls: ` +
            (error instanceof Error ? error.message : String(error)),
        );
      }
    }

    if (result) {
      lastDiagnostic = {
        url: result.url,
        promptFound: result.promptFound,
        count: result.count,
      };
      if (result.count > beforeCount) sawNewMessage = true;
      if (sawNewMessage) {
        const currentText = String(result.text || "");
        if (!result.streaming && currentText && currentText === lastText) {
          if (!stableSince) stableSince = Date.now();
          if (Date.now() - stableSince > STABLE_FOR_MS) {
            onProgress(currentText);
            return currentText.trim();
          }
        } else {
          stableSince = 0;
        }
        lastText = currentText;
      }
    }

    // Fail fast instead of silently spinning for the full budget: if
    // nothing has happened (no new assistant message at all) for a while,
    // stop and report exactly what the tab currently looks like so it's
    // fixable instead of a mystery "stuck on Thinking".
    if (!sawNewMessage && Date.now() > noProgressDeadline) {
      const details = lastDiagnostic
        ? `Tab: ${lastDiagnostic.url || "unknown"}. Prompt box found: ${lastDiagnostic.promptFound ? "yes" : "no"}. Messages detected: ${lastDiagnostic.count}.`
        : "Never got a successful status check from the tab.";
      throw new Error(
        `Claude hasn't started responding after ${Math.round(NO_PROGRESS_TIMEOUT_MS / 1000)}s. ` +
          `${details} This usually means the message selectors in config.json no longer match claude.ai's layout, or a different claude.ai tab is being watched.`,
      );
    }

    onProgress(sawNewMessage ? lastText : "");
    await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
  }

  if (!sawNewMessage) {
    throw new Error("Claude never started responding before the timeout.");
  }
  // We did see a reply start — return whatever text we last captured
  // rather than erroring out, in case it only needed a bit more settle time.
  if (lastText.trim()) return lastText.trim();
  throw new Error("Claude's response did not finish before the timeout.");
}

async function handleSubmit(rev, text) {
  const trimmed = String(text || "").trim();
  if (!trimmed) return;

  if (state.screen !== "chat") {
    command("toast", { text: "Not connected to Claude yet.", style: "error" });
    renderCurrent(rev);
    return;
  }
  if (state.busy) {
    command("toast", {
      text: "Claude is still responding — please wait.",
      style: "info",
    });
    renderChat(rev);
    return;
  }

  pushMessage("user", trimmed);
  state.busy = true;
  state.thinkingStartedAt = Date.now();
  renderChat(rev);
  command("setQuery", { text: "" });

  try {
    await ensureTabOpen();
    const sendExecution = await bridge.request(
      "javascript.execute",
      { tabId: state.tabId, code: SEND_SCRIPT, input: { text: trimmed } },
      REQUEST_TIMEOUT_MS,
    );
    const sendResult = unwrapBrowserResult(sendExecution);
    const beforeCount = Number(sendResult?.beforeCount) || 0;

    const replyText = await waitForReply(
      beforeCount,
      CONFIG.responseTimeoutMs,
      (text) => {
        updateStreamingMessage(text);
        renderChat(0);
      },
    );
    if (!replyText) throw new Error("Claude did not return a response.");
    finishAssistantMessage(replyText);
  } catch (error) {
    pushMessage(
      "error",
      error instanceof Error ? error.message : String(error),
    );
  } finally {
    state.busy = false;
    state.thinkingStartedAt = null;
    state.streamingMessageId = null;
    renderChat(0);
  }
}

async function startNewConversation() {
  render(0, "chat", {
    loading: true,
    loadingText: "Starting a new conversation…",
    items: [],
  });
  try {
    await ensureTabOpen();
    await bridge.request("javascript.execute", {
      tabId: state.tabId,
      code: "location.assign(input.url); return { ok: true };",
      input: { url: CONFIG.claudeUrl },
    });
    await waitForTabReady(state.tabId);
    state.messages = [];
    pushMessage("system", "Started a new conversation.");
    renderChat(0);
  } catch (error) {
    renderError(0, error, "Could not start a new conversation");
  }
}

async function handleAction(id, action) {
  try {
    if (action === "reconnect") {
      await bridge.refreshStatus().catch(() => {});
      if (bridge.connected) {
        if (state.screen === "connection") await openClaudeTab(0);
        else renderChat(0);
      } else {
        state.screen = "connection";
        renderConnection(0);
      }
      return;
    }
    if (action === "retry") {
      state.screen = bridge.connected ? "chat" : "connection";
      if (state.screen === "chat") await openClaudeTab(0);
      else renderConnection(0);
      return;
    }
    if (action === "new_chat") {
      await startNewConversation();
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
    renderError(0, error, "Action failed");
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
process.stdin.on("end", () => shutdown());

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
      await handleInit(
        Number(message.rev) || 0,
        message.text ?? message.query ?? "",
      );
      break;
    case "submitQuery":
      await handleSubmit(Number(message.rev) || 0, message.text ?? "");
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
  bridge.close();
  setTimeout(() => process.exit(0), 20);
}
