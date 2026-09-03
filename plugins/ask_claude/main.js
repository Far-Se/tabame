#!/usr/bin/env node
"use strict";

// Ask Claude — a Tabame launcher plugin.
//
// Keyword: "ask". On first use it opens (or reuses) a claude.ai tab through
// Tabame's app-owned browser bridge. Every message you submit from the
// launcher is typed into that tab, sent, and the plugin waits for Claude's
// reply in-page before relaying the text back into the launcher's chat view.
// The browser exposes snapshots while that response is streaming, so the
// plugin interpolates those snapshots into character-level chat frames instead
// of showing each polling chunk as a jump.
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
const crypto = require("crypto");

const SNIPPETS_STORAGE_KEY = "snippets";
const HOME_ASK_ITEM_ID = "ask-claude";
const CREATE_SNIPPET_ITEM_ID = "create-snippet";
const DRAFT_MESSAGE_ITEM_ID = "draft-message";
const DRAFT_PREVIEW_ITEM_ID = "draft-preview";
const DEFAULT_SNIPPET_TRIGGER = "$process";
const DEFAULT_SNIPPET_TEMPLATE =
  "Please tell me how many i have in my basked: $1, $2, $3";

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
// The native chat view replaces item subtitles per frame, so animate the
// growing assistant message here rather than switching away from the
// Discord-style message layout to detail.append.
const STREAM_TICK_MS = 24;
const STREAM_MAX_CHARS_PER_TICK = 4;
const STREAM_SETTLE_TIMEOUT_MS = 1_500;
const SHUTDOWN_TAB_WAIT_MS = 500;
const SHUTDOWN_TAB_CLOSE_TIMEOUT_MS = 1_000;

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
function toast(text, style = "success") {
  command("toast", { text, style });
}
function render(rev, view, fields = {}) {
  send({ type: "render", rev, view, ...fields });
}
function log(...parts) {
  console.error(...parts);
}

const storageRequests = new Map();
let storageRequestCounter = 0;

function storageGet(key) {
  return new Promise((resolve) => {
    const requestId = `ask-claude-storage-${++storageRequestCounter}`;
    const timer = setTimeout(() => {
      storageRequests.delete(requestId);
      resolve(undefined);
    }, 1_500);
    storageRequests.set(requestId, { resolve, timer });
    command("storage", { op: "get", key, requestId });
  });
}

function storageSet(key, value) {
  command("storage", { op: "set", key, value });
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
    this.statusKnown = false;
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
      this.statusKnown = true;
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
    this.statusKnown = true;
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
  screen: "home", // home | connection | chat | snippets | snippet_form
  chatMode: "conversation", // autocomplete | conversation
  tabId: null,
  tabOwned: false,
  snippetFormMode: "create", // create | edit
  editingSnippetId: null,
  snippetQuery: "",
  snippets: [],
  snippetsLoaded: false,
  snippetsReturnScreen: "home",
  draftText: "",
  messages: [], // {id, role: "user"|"assistant"|"error"|"system", text, time}
  busy: false,
  thinkingStartedAt: null,
  streamingMessageId: null,
  streamingTarget: "",
  streamingTargetCharacters: [],
  streamingDisplayedLength: 0,
  streamingTimer: null,
  nextId: 1,
};

let snippetsLoadPromise = null;

function newSnippetId() {
  return `snippet-${crypto.randomUUID()}`;
}

function normalizeSnippet(value, fallbackId) {
  if (!value || typeof value !== "object") return null;
  const trigger = String(value.trigger || "").trim();
  if (!trigger) return null;
  return {
    id: String(value.id || fallbackId || newSnippetId()),
    trigger,
    template: String(value.template || DEFAULT_SNIPPET_TEMPLATE),
  };
}

function saveSnippets() {
  storageSet(SNIPPETS_STORAGE_KEY, JSON.stringify(state.snippets));
}

function ensureSnippetsLoaded() {
  if (state.snippetsLoaded) return Promise.resolve(state.snippets);
  if (snippetsLoadPromise) return snippetsLoadPromise;

  snippetsLoadPromise = storageGet(SNIPPETS_STORAGE_KEY)
    .then((stored) => {
      let parsed = [];
      try {
        if (Array.isArray(stored)) parsed = stored;
        else if (typeof stored === "string" && stored.trim())
          parsed = JSON.parse(stored);
      } catch (error) {
        log("Ignoring invalid saved snippets:", error.message);
      }
      state.snippets = Array.isArray(parsed)
        ? parsed
            .map((item, index) =>
              normalizeSnippet(item, `snippet-${index + 1}`),
            )
            .filter(Boolean)
        : [];
      state.snippetsLoaded = true;
      return state.snippets;
    })
    .catch((error) => {
      state.snippets = [];
      state.snippetsLoaded = true;
      log("Could not load saved snippets:", error.message || error);
      return state.snippets;
    })
    .finally(() => {
      snippetsLoadPromise = null;
    });

  return snippetsLoadPromise;
}

function quotedArguments(text) {
  const args = [];
  const pattern = /(?:\"((?:\\.|[^\"\\])*)\"|'((?:\\.|[^'\\])*)')/g;
  let match;
  while ((match = pattern.exec(text)) !== null) {
    const value = match[1] !== undefined ? match[1] : match[2];
    args.push(value.replace(/\\([\\\"'])/g, "$1"));
  }
  return args;
}

function substituteArguments(value, args) {
  return String(value || "").replace(/\$(\d+)/g, (_, number) => {
    const index = Number(number) - 1;
    return index >= 0 && index < args.length ? args[index] : "";
  });
}

function snippetCandidates() {
  return [...state.snippets].sort(
    (left, right) => right.trigger.length - left.trigger.length,
  );
}

function snippetForInput(text) {
  const source = String(text || "").trim();
  if (!source) return null;

  return (
    snippetCandidates().find(
      (candidate) =>
        source === candidate.trigger ||
        source.startsWith(`${candidate.trigger} `) ||
        source.startsWith(`${candidate.trigger}\t`),
    ) || null
  );
}

function snippetPrefixForInput(text) {
  const source = String(text || "")
    .trim()
    .toLowerCase();
  if (!source || /\s/.test(source)) return null;

  return (
    snippetCandidates().find((candidate) =>
      candidate.trigger.toLowerCase().startsWith(source),
    ) || null
  );
}

function expandSnippet(text) {
  const source = String(text || "").trim();
  const snippet = snippetForInput(source);
  if (!snippet) return source;

  const remainder = source.slice(snippet.trigger.length).trim();
  let args = quotedArguments(remainder);
  if (!args.length && remainder) args = [remainder];

  return substituteArguments(snippet.template, args).trim();
}

function snippetById(id) {
  return state.snippets.find((snippet) => snippet.id === id) || null;
}

function snippetFormValues(snippet = null) {
  return {
    trigger: snippet?.trigger || DEFAULT_SNIPPET_TRIGGER,
    template: snippet?.template || DEFAULT_SNIPPET_TEMPLATE,
  };
}

function snippetItem(snippet) {
  return {
    id: snippet.id,
    title: snippet.trigger,
    subtitle: snippet.template,
    icon: "code",
    lines: 2,
    actions: [
      { id: "default", title: "Use shortcut", icon: "chat" },
      { id: "edit_snippet", title: "Edit snippet", icon: "edit" },
      {
        id: "delete_snippet",
        title: "Delete snippet",
        icon: "trash",
        destructive: true,
        confirm: {
          title: "Delete this snippet?",
          message: `Remove ${snippet.trigger} from your saved snippets.`,
          confirmLabel: "Delete",
        },
      },
    ],
  };
}

function connectionStatusLabel() {
  if (!bridge.statusKnown) return "Checking";
  if (bridge.connected) return "Connected";
  return "Not connected";
}

function connectionStatusColor() {
  if (!bridge.statusKnown) return "#8A7F88";
  if (bridge.connected) return "#3D9B72";
  return "#D18B47";
}

function connectionSummary() {
  if (!bridge.statusKnown) return "Checking the browser connector…";
  if (!bridge.enabled) return "Not connected · connector disabled";
  if (bridge.connected) {
    const browser = String(bridge.clientInfo.browser || "").trim();
    const version = String(bridge.clientInfo.extensionVersion || "").trim();
    const details = [];
    if (browser && browser.toLowerCase() !== "unknown") details.push(browser);
    if (version && version.toLowerCase() !== "unknown")
      details.push(`extension ${version}`);
    return `Connected${details.length ? ` · ${details.join(" · ")}` : ""} · ready to chat`;
  }
  if (!bridge.running) return "Not connected · connector is starting";
  return `Not connected · waiting for browser extension on port ${bridge.port}`;
}

function askClaudeHomeItem() {
  return {
    id: HOME_ASK_ITEM_ID,
    title: "Ask Claude",
    subtitle: connectionSummary(),
    icon: "chat",
    lines: 2,
    accessories: [
      { text: connectionStatusLabel(), color: connectionStatusColor() },
    ],
    actions: [
      {
        id: "open_chat",
        title: bridge.connected ? "Open chat" : "Show connection details",
        icon: bridge.connected ? "chat" : "info",
      },
    ],
  };
}

function renderHome(rev, query = state.snippetQuery) {
  const normalizedQuery = String(query || "")
    .trim()
    .toLowerCase();
  const savedItems = state.snippets
    .filter((snippet) => {
      if (!normalizedQuery) return true;
      return `${snippet.trigger} ${snippet.template}`
        .toLowerCase()
        .includes(normalizedQuery);
    })
    .map(snippetItem);

  render(rev, "list", {
    page: { id: "ask:home", title: "Ask Claude", history: "none" },
    placeholder: "Type a shortcut or prompt…",
    emptyText: "No saved shortcuts yet",
    items: [askClaudeHomeItem(), ...savedItems],
    actions: [
      { id: "reconnect", title: "Refresh connection", icon: "refresh" },
      { id: "create_snippet", title: "Create snippet", icon: "add" },
    ],
    floatingAction: {
      id: "create_snippet",
      title: "Create snippet",
      icon: "add",
    },
  });
}

function renderSnippets(rev, query = state.snippetQuery) {
  const normalizedQuery = String(query || "")
    .trim()
    .toLowerCase();
  const savedItems = state.snippets
    .filter((snippet) => {
      if (!normalizedQuery) return true;
      return `${snippet.trigger} ${snippet.template}`
        .toLowerCase()
        .includes(normalizedQuery);
    })
    .map(snippetItem);

  render(rev, "list", {
    page: { id: "ask:snippets", title: "Snippets", history: "push" },
    canGoBack: true,
    placeholder: "Filter snippets…",
    emptyText: normalizedQuery
      ? "No matching snippets"
      : "No saved snippets yet",
    items: [
      {
        id: CREATE_SNIPPET_ITEM_ID,
        title: "Create new snippet",
        subtitle: "Save a reusable prompt transformation",
        icon: "add",
      },
      ...savedItems,
    ],
    floatingAction: {
      id: "create_snippet",
      title: "Create snippet",
      icon: "add",
    },
  });
}

function renderSnippetForm(rev, error = null) {
  const snippet =
    state.snippetFormMode === "edit"
      ? snippetById(state.editingSnippetId)
      : null;
  const values = snippetFormValues(snippet);
  render(rev, "form", {
    page: {
      id:
        state.snippetFormMode === "edit"
          ? "ask:snippet:edit"
          : "ask:snippet:new",
      title: state.snippetFormMode === "edit" ? "Edit snippet" : "New snippet",
      history: "push",
    },
    canGoBack: true,
    placeholder: "Configure your prompt transformation…",
    form: {
      title:
        state.snippetFormMode === "edit"
          ? "Edit snippet"
          : "Create new snippet",
      submitLabel: state.snippetFormMode === "edit" ? "Save" : "Create",
      error: error?.message || undefined,
      fields: [
        {
          id: "trigger",
          type: "text",
          label: "Shortcut",
          placeholder: DEFAULT_SNIPPET_TRIGGER,
          value: values.trigger,
          required: true,
          description: "The exact prefix used in chat, for example $process.",
          error: error?.field === "trigger" ? error.message : undefined,
        },
        {
          id: "template",
          type: "textarea",
          label: "Snippet text",
          value: values.template,
          required: true,
          description:
            "Use $1, $2, etc. for the quoted values supplied after the shortcut.",
          error: error?.field === "template" ? error.message : undefined,
        },
      ],
    },
  });
}

function enterSnippetForm(mode = "create", id = null) {
  state.screen = "snippet_form";
  state.snippetFormMode = mode;
  state.editingSnippetId = id;
  command("setQuery", { text: " " });
  renderSnippetForm(0);
}

async function enterSnippets() {
  state.snippetsReturnScreen =
    state.screen === "snippets" || state.screen === "snippet_form"
      ? "chat"
      : state.screen;
  state.screen = "snippets";
  state.snippetQuery = "";
  render(0, "list", {
    loading: true,
    loadingText: "Loading snippets…",
    items: [],
  });
  command("setQuery", { text: " " });
  await ensureSnippetsLoaded();
  if (!shuttingDown && state.screen === "snippets") renderSnippets(0);
}

function leaveSnippets() {
  const returnScreen = state.snippetsReturnScreen || "chat";
  const returningToAutocomplete = Boolean(
    returnScreen === "chat" &&
    state.chatMode === "autocomplete" &&
    state.draftText.trim(),
  );
  state.screen = returnScreen;
  state.snippetQuery = returningToAutocomplete ? state.draftText : "";
  if (!returningToAutocomplete) state.draftText = "";
  state.editingSnippetId = null;
  command("setQuery", {
    text: returningToAutocomplete ? state.draftText : " ",
  });
  renderCurrent(0);
}

function handleSnippetSubmit(values) {
  const trigger = String(values.trigger || "").trim();
  const template = String(values.template || "").trim();
  if (!trigger)
    return renderSnippetForm(0, {
      field: "trigger",
      message: "Trigger is required.",
    });
  if (!template)
    return renderSnippetForm(0, {
      field: "template",
      message: "Prompt template is required.",
    });

  const duplicate = state.snippets.find(
    (snippet) =>
      snippet.trigger.toLowerCase() === trigger.toLowerCase() &&
      snippet.id !== state.editingSnippetId,
  );
  if (duplicate)
    return renderSnippetForm(0, {
      field: "trigger",
      message: "That trigger is already saved.",
    });

  if (state.snippetFormMode === "edit") {
    const snippet = snippetById(state.editingSnippetId);
    if (!snippet) return enterSnippets();
    snippet.trigger = trigger;
    snippet.template = template;
    saveSnippets();
    toast(`Updated ${trigger}`);
  } else {
    state.snippets.push({
      id: newSnippetId(),
      trigger,
      template,
    });
    saveSnippets();
    toast(`Saved ${trigger}`);
  }

  state.screen = "snippets";
  state.editingSnippetId = null;
  state.snippetFormMode = "create";
  renderSnippets(0);
}

function openSnippetAutocomplete(snippet) {
  state.screen = "chat";
  state.chatMode = "autocomplete";
  state.draftText = snippet.trigger;
  state.snippetQuery = snippet.trigger;
  command("setQuery", { text: `${snippet.trigger} ` });
  renderAutocompleteChat(0, snippet.trigger);
}

function handleSnippetAction(id, action) {
  if (state.screen === "snippets") {
    if (id === "" && (action === "create_snippet" || action === "default")) {
      return enterSnippetForm();
    }
    if (id === CREATE_SNIPPET_ITEM_ID && action === "default")
      return enterSnippetForm();
    const snippet = snippetById(id);
    if (!snippet) return;
    if (action === "default") return openSnippetAutocomplete(snippet);
    if (action === "edit_snippet") {
      return enterSnippetForm("edit", snippet.id);
    }
    if (action === "delete_snippet") {
      state.snippets = state.snippets.filter(
        (candidate) => candidate.id !== snippet.id,
      );
      saveSnippets();
      renderSnippets(0);
      toast(`Deleted ${snippet.trigger}`);
    }
    return;
  }

  if (state.screen === "snippet_form" && id === "" && action === "cancel") {
    state.screen = "snippets";
    state.editingSnippetId = null;
    renderSnippets(0);
  }
}

// Startup status and init can arrive at the same time. Share the in-flight
// operations so only one Claude tab can be opened for this plugin instance.
let tabOpenPromise = null;
let openClaudePromise = null;

const bridge = new BrowserBridge(() => {
  if (shuttingDown || !state.initialized) return;
  if (state.screen === "home") renderHome(0);
  else if (state.screen === "connection") renderConnection(0);

  if (
    bridge.connected &&
    (state.screen === "home" || state.screen === "connection")
  ) {
    prewarmClaudeTab();
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

function streamingMessage() {
  return state.streamingMessageId
    ? state.messages.find(
        (candidate) => candidate.id === state.streamingMessageId,
      )
    : null;
}

function ensureStreamingMessage() {
  const existing = streamingMessage();
  if (existing) return existing;

  const created = pushMessage("assistant", "");
  state.streamingMessageId = created.id;
  state.streamingTarget = "";
  state.streamingTargetCharacters = [];
  state.streamingDisplayedLength = 0;
  return created;
}

function stopStreamingAnimation() {
  if (state.streamingTimer !== null) {
    clearInterval(state.streamingTimer);
    state.streamingTimer = null;
  }
}

function resetStreamingAnimation() {
  stopStreamingAnimation();
  state.streamingTarget = "";
  state.streamingTargetCharacters = [];
  state.streamingDisplayedLength = 0;
}

function advanceStreamingMessage() {
  const message = streamingMessage();
  if (!message || state.screen !== "chat") {
    stopStreamingAnimation();
    return;
  }

  const target = state.streamingTargetCharacters;
  const remaining = target.length - state.streamingDisplayedLength;
  if (remaining <= 0) {
    stopStreamingAnimation();
    return;
  }

  // Stay gentle when the browser is keeping up, but catch up quickly after a
  // slower poll so the animation never falls far behind the real response.
  const step =
    remaining > 120 ? STREAM_MAX_CHARS_PER_TICK : remaining > 30 ? 2 : 1;
  state.streamingDisplayedLength += Math.min(step, remaining);
  message.text = target.slice(0, state.streamingDisplayedLength).join("");
  renderChat(0);

  if (state.streamingDisplayedLength >= target.length) {
    stopStreamingAnimation();
  }
}

function startStreamingAnimation() {
  if (state.streamingTimer !== null) return;
  state.streamingTimer = setInterval(advanceStreamingMessage, STREAM_TICK_MS);
}

function updateStreamingMessage(text) {
  const nextText = String(text ?? "").trim();
  if (!nextText) return false;

  const message = ensureStreamingMessage();
  const visibleCharacters = Array.from(message.text);
  const targetCharacters = Array.from(nextText);
  let sharedLength = 0;
  while (
    sharedLength < visibleCharacters.length &&
    sharedLength < targetCharacters.length &&
    visibleCharacters[sharedLength] === targetCharacters[sharedLength]
  ) {
    sharedLength += 1;
  }

  // The DOM can briefly correct an earlier character while Claude streams.
  // Keep the already-visible common prefix, then continue pouring from there.
  if (sharedLength !== visibleCharacters.length) {
    message.text = targetCharacters.slice(0, sharedLength).join("");
  }
  state.streamingDisplayedLength = sharedLength;

  const changed = state.streamingTarget !== nextText;
  state.streamingTarget = nextText;
  state.streamingTargetCharacters = targetCharacters;
  startStreamingAnimation();
  return changed || sharedLength !== visibleCharacters.length;
}

async function revealStreamingMessage(text) {
  const nextText = String(text ?? "").trim();
  if (!nextText) return;

  updateStreamingMessage(nextText);
  const deadline = Date.now() + STREAM_SETTLE_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const message = streamingMessage();
    if (!message || state.streamingTarget !== nextText) return;
    if (
      state.streamingDisplayedLength >= state.streamingTargetCharacters.length
    ) {
      stopStreamingAnimation();
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, STREAM_TICK_MS));
  }

  const message = streamingMessage();
  if (!message || state.streamingTarget !== nextText) return;
  message.text = nextText;
  state.streamingDisplayedLength = state.streamingTargetCharacters.length;
  stopStreamingAnimation();
  if (state.screen === "chat") renderChat(0);
}

function finishAssistantMessage(text) {
  const nextText = String(text ?? "").trim();
  const message = streamingMessage();
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
      state.tabOwned = false;
    }

    const list = await bridge.request("tabs.list");
    const existing = (list.tabs || []).find(
      (t) => typeof t.url === "string" && t.url.startsWith(CONFIG.claudeOrigin),
    );
    if (existing) {
      state.tabId = existing.id;
      state.tabOwned = false;
    } else {
      const tab = await bridge.request("tabs.open", {
        url: CONFIG.claudeUrl,
        active: true,
      });
      state.tabId = tab.id;
      state.tabOwned = true;
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

function prewarmClaudeTab() {
  if (!bridge.connected) return;
  void ensureTabOpen().catch((error) => {
    log(
      "Could not pre-open Claude:",
      error instanceof Error ? error.message : error,
    );
  });
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

function chatMessageItem(message) {
  return {
    id: message.id,
    title: titleFor(message.role),
    subtitle: message.text,
    icon: iconFor(message.role),
    lines: 3,
    accessories: [
      {
        text:
          message.id === state.streamingMessageId ? "Writing…" : message.time,
      },
    ],
    actions: [{ id: "copy", title: "Copy message", icon: "copy" }],
  };
}

function renderAutocompleteChat(rev, text = state.draftText) {
  const draft = String(text || "").trim();
  state.draftText = draft;

  const matchedSnippet = snippetForInput(draft);
  const suggestedSnippet = matchedSnippet || snippetPrefixForInput(draft);
  const previewText = matchedSnippet
    ? expandSnippet(draft)
    : suggestedSnippet
      ? suggestedSnippet.template
      : draft;
  const previewLabel = matchedSnippet
    ? `Will send · ${matchedSnippet.trigger}`
    : suggestedSnippet
      ? `Shortcut suggestion · ${suggestedSnippet.trigger}`
      : "Ready to send";

  const items = state.messages.map(chatMessageItem);
  items.push({
    id: DRAFT_MESSAGE_ITEM_ID,
    title: "You",
    subtitle: draft,
    icon: "person",
    lines: 3,
    accessories: [{ text: matchedSnippet ? "Shortcut" : "Draft" }],
    actions: [{ id: "default", title: "Send to Claude", icon: "chat" }],
  });

  if (matchedSnippet || suggestedSnippet) {
    items.push({
      id: DRAFT_PREVIEW_ITEM_ID,
      title: "Ask Claude",
      subtitle: previewText,
      icon: "chat",
      lines: 3,
      accessories: [{ text: previewLabel }],
      actions: [{ id: "send_draft", title: "Send to Claude", icon: "chat" }],
    });
  }

  // Keep the normal query mode here so every keystroke can refresh the
  // shortcut expansion. A submitted conversation switches to submit mode.
  render(rev, "chat", {
    page: { id: "ask:composer", title: chatTitleFor(), history: "none" },
    placeholder: "Type a shortcut or prompt…",
    emptyText: "Type a message to preview it here",
    items,
    actions: [
      { id: "new_chat", title: "New conversation", icon: "add" },
      { id: "reconnect", title: "Refresh connection", icon: "refresh" },
    ],
    floatingAction: { id: "snippets", title: "Snippets", icon: "code" },
  });
}

function renderChat(rev) {
  const items = state.messages.map(chatMessageItem);

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
    floatingAction: { id: "snippets", title: "Snippets", icon: "code" },
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
    floatingAction: { id: "snippets", title: "Snippets", icon: "code" },
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
    floatingAction: { id: "snippets", title: "Snippets", icon: "code" },
  });
}

function renderCurrent(rev) {
  if (state.screen === "home") renderHome(rev);
  else if (state.screen === "chat") {
    if (state.chatMode === "autocomplete") renderAutocompleteChat(rev);
    else renderChat(rev);
  } else if (state.screen === "snippets") renderSnippets(rev);
  else if (state.screen === "snippet_form") renderSnippetForm(rev);
  else renderConnection(rev);
}

async function handleInit(rev, text) {
  if (state.initialized) {
    renderCurrent(rev);
    return;
  }
  state.initialized = true;
  state.screen = "home";
  state.chatMode = "autocomplete";
  state.snippetsReturnScreen = "home";
  state.snippetQuery = String(text ?? "");
  state.draftText = state.snippetQuery.trim();

  render(rev, "list", {
    page: { id: "ask:home", title: "Ask Claude", history: "none" },
    loading: true,
    loadingText: "Loading Claude shortcuts…",
    items: [],
  });
  try {
    if (!bridge.connected) await bridge.refreshStatus().catch(() => {});
  } catch {
    /* handled by applyStatus/startError */
  }

  // Start loading Claude while the launcher finishes preparing its home
  // screen. Sending a message later reuses this same in-flight operation.
  prewarmClaudeTab();

  await ensureSnippetsLoaded();
  if (shuttingDown) return;

  if (state.snippetQuery.trim()) {
    state.screen = "chat";
    state.chatMode = "autocomplete";
    renderAutocompleteChat(0, state.snippetQuery);
  } else if (state.screen === "home") {
    renderHome(0);
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

  if (!bridge.connected) {
    await bridge.refreshStatus().catch(() => {});
    if (!bridge.connected) {
      state.screen = "connection";
      renderConnection(0);
      return;
    }
  }

  await ensureSnippetsLoaded();
  const expanded = expandSnippet(trimmed);
  if (expanded !== trimmed) {
    log(
      `Expanded snippet input ${JSON.stringify(trimmed)} to ${JSON.stringify(expanded)}`,
    );
  }

  state.chatMode = "conversation";
  state.draftText = "";
  pushMessage("user", expanded);
  state.busy = true;
  state.thinkingStartedAt = Date.now();
  renderChat(rev);
  command("setQuery", { text: " " });

  try {
    await ensureTabOpen();
    const sendExecution = await bridge.request(
      "javascript.execute",
      { tabId: state.tabId, code: SEND_SCRIPT, input: { text: expanded } },
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
    await revealStreamingMessage(replyText);
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
    resetStreamingAnimation();
    renderChat(0);
  }
}

async function startNewConversation() {
  state.chatMode = "conversation";
  state.draftText = "";
  state.streamingMessageId = null;
  resetStreamingAnimation();
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

async function openClaudeFromHome() {
  await bridge.refreshStatus().catch(() => {});
  if (!bridge.connected) {
    state.screen = "connection";
    renderConnection(0);
    return;
  }

  state.screen = "chat";
  state.chatMode = "conversation";
  state.draftText = "";
  await openClaudeTab(0);
}

async function handleHomeAction(id, action) {
  if (id === HOME_ASK_ITEM_ID && ["default", "open_chat"].includes(action)) {
    await openClaudeFromHome();
    return;
  }

  if (id === "" && action === "reconnect") {
    await bridge.refreshStatus().catch(() => {});
    renderHome(0);
    return;
  }

  if (id === "" && (action === "create_snippet" || action === "default")) {
    enterSnippetForm();
    return;
  }

  if (id === CREATE_SNIPPET_ITEM_ID && action === "default") {
    enterSnippetForm();
    return;
  }

  const snippet = snippetById(id);
  if (!snippet) return;
  if (action === "default") return openSnippetAutocomplete(snippet);
  if (action === "edit_snippet") return enterSnippetForm("edit", snippet.id);
  if (action === "delete_snippet") {
    state.snippets = state.snippets.filter(
      (candidate) => candidate.id !== snippet.id,
    );
    saveSnippets();
    renderHome(0);
    toast(`Deleted ${snippet.trigger}`);
  }
}

async function handleAction(id, action) {
  try {
    if (state.screen === "home") {
      await handleHomeAction(id, action);
      return;
    }
    if (state.screen === "snippets" || state.screen === "snippet_form") {
      handleSnippetAction(id, action);
      return;
    }
    if (
      state.screen === "chat" &&
      state.chatMode === "autocomplete" &&
      ["default", "send_draft"].includes(action)
    ) {
      await handleSubmit(0, state.draftText);
      return;
    }
    if (action === "snippets") {
      await enterSnippets();
      return;
    }
    if (action === "copy") {
      const message = state.messages.find((candidate) => candidate.id === id);
      if (message?.text) {
        command("copy", { text: message.text });
        command("toast", { text: "Message copied", style: "success" });
      }
      return;
    }
    if (action === "reconnect") {
      await bridge.refreshStatus().catch(() => {});
      if (bridge.connected) {
        if (state.screen === "connection") await openClaudeTab(0);
        else if (state.screen === "chat") {
          if (state.chatMode === "autocomplete") renderAutocompleteChat(0);
          else renderChat(0);
        } else renderCurrent(0);
      } else {
        if (state.screen === "chat" && state.chatMode === "autocomplete")
          renderAutocompleteChat(0);
        else {
          state.screen = "connection";
          renderConnection(0);
        }
      }
      return;
    }
    if (action === "retry") {
      state.screen = bridge.connected ? "chat" : "connection";
      if (state.screen === "chat") {
        state.chatMode = "conversation";
        await openClaudeTab(0);
      } else renderConnection(0);
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
      await handleInit(
        Number(message.rev) || 0,
        message.text ?? message.query ?? "",
      );
      break;
    case "query": {
      const rev = Number(message.rev) || 0;
      const text = String(message.text ?? "");
      if (!state.initialized) {
        await handleInit(rev, text || message.query || "");
      } else if (state.screen === "home") {
        state.snippetQuery = text;
        if (text.trim()) {
          state.screen = "chat";
          state.chatMode = "autocomplete";
          renderAutocompleteChat(rev, text);
        } else {
          renderHome(rev);
        }
      } else if (state.screen === "chat" && state.chatMode === "autocomplete") {
        if (text.trim()) {
          state.snippetQuery = text;
          renderAutocompleteChat(rev, text);
        } else {
          state.screen = "home";
          state.draftText = "";
          state.snippetQuery = "";
          renderHome(rev);
        }
      } else if (state.screen === "connection" && text.trim()) {
        state.screen = "chat";
        state.chatMode = "autocomplete";
        state.snippetQuery = text;
        renderAutocompleteChat(rev, text);
      } else if (state.screen === "snippets") {
        state.snippetQuery = text;
        if (!state.snippetsLoaded) {
          render(rev, "list", {
            loading: true,
            loadingText: "Loading snippets…",
            items: [],
          });
        } else {
          renderSnippets(rev, state.snippetQuery);
        }
      }
      break;
    }
    case "submitQuery":
      await handleSubmit(Number(message.rev) || 0, message.text ?? "");
      break;
    case "submit":
      if (state.screen === "snippet_form")
        handleSnippetSubmit(message.values || {});
      break;
    case "action":
      await handleAction(String(message.id || ""), message.action || "default");
      break;
    case "tab": {
      const id = String(message.id || "");
      if (state.screen === "home") {
        const snippet = snippetById(id);
        if (snippet) openSnippetAutocomplete(snippet);
      } else if (state.screen === "chat" && state.chatMode === "autocomplete") {
        const snippet =
          snippetForInput(state.draftText) ||
          snippetPrefixForInput(state.draftText);
        if (snippet) command("setQuery", { text: `${snippet.trigger} ` });
      }
      break;
    }
    case "back":
      if (state.screen === "snippet_form") {
        state.screen = "snippets";
        state.editingSnippetId = null;
        renderSnippets(Number(message.rev) || 0);
      } else if (state.screen === "snippets") {
        leaveSnippets();
      } else if (state.screen === "chat" && state.chatMode === "autocomplete") {
        state.screen = "home";
        state.draftText = "";
        state.snippetQuery = "";
        renderHome(Number(message.rev) || 0);
      }
      break;
    case "storage": {
      const request = storageRequests.get(message.requestId);
      if (request) {
        clearTimeout(request.timer);
        storageRequests.delete(message.requestId);
        request.resolve(message.value);
      }
      break;
    }
  }
}

async function closeOwnedClaudeTab() {
  // If shutdown races the initial tabs.open request, give it a brief chance
  // to return an id before releasing the bridge.
  if (state.tabId == null && tabOpenPromise) {
    await Promise.race([
      tabOpenPromise.catch(() => null),
      new Promise((resolve) => setTimeout(resolve, SHUTDOWN_TAB_WAIT_MS)),
    ]);
  }

  if (!state.tabOwned || state.tabId == null) return;

  const tabId = state.tabId;
  state.tabId = null;
  state.tabOwned = false;
  if (!bridge.connected) {
    log(
      "Could not close the Claude tab because the browser bridge is offline.",
    );
    return;
  }

  await bridge
    .request("tabs.close", { tabId }, SHUTDOWN_TAB_CLOSE_TIMEOUT_MS)
    .catch((error) =>
      log(
        "Could not close the Claude tab on shutdown:",
        error instanceof Error ? error.message : error,
      ),
    );
}

let shuttingDown = false;
function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  state.streamingMessageId = null;
  resetStreamingAnimation();
  void closeOwnedClaudeTab()
    .catch((error) => log("Claude tab cleanup failed:", error))
    .finally(() => {
      bridge.close();
      setTimeout(() => process.exit(0), 20);
    });
}
