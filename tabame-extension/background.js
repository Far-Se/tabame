"use strict";

const BRIDGE_HOST = "127.0.0.1";
const DEFAULT_PORT = 17373;
const BRIDGE_PATH = "/tabame";
const ANALYTICS_URL =
  "https://chatgpt.com/codex/cloud/settings/analytics#usage";
const KEEPALIVE_MS = 20_000;
const RECONNECT_MIN_MS = 800;
const RECONNECT_MAX_MS = 12_000;
const REQUEST_TIMEOUT_MS = 25_000;
const RECONNECT_ALARM = "tabame-connector-reconnect";

let socket = null;
let authenticated = false;
let reconnectTimer = null;
let keepaliveTimer = null;
let reconnectDelay = RECONNECT_MIN_MS;
let tabEventTimer = null;
let lastError = "";
let connectGeneration = 0;

function extensionVersion() {
  return chrome.runtime.getManifest().version;
}

async function readBridgeConfig() {
  const stored = await chrome.storage.local.get(["bridgeToken", "bridgePort"]);
  return {
    token:
      typeof stored.bridgeToken === "string"
        ? stored.bridgeToken.replace(/\s+/g, "")
        : "",
    port: validPort(stored.bridgePort) ? Number(stored.bridgePort) : DEFAULT_PORT,
  };
}

function validPort(value) {
  const port = Number(value);
  return Number.isInteger(port) && port >= 1024 && port <= 65535;
}

function socketUrl(port) {
  return `ws://${BRIDGE_HOST}:${port}${BRIDGE_PATH}`;
}

function setBadge(connected) {
  chrome.action.setBadgeBackgroundColor({
    color: connected ? "#3D9B72" : "#6C6972",
  });
  chrome.action.setBadgeText({ text: connected ? "ON" : "" });
  chrome.action.setTitle({
    title: connected ? "Tabame Connector · Connected" : "Tabame Connector",
  });
}

function closeSocket() {
  clearInterval(keepaliveTimer);
  keepaliveTimer = null;
  authenticated = false;
  if (socket) {
    const oldSocket = socket;
    socket = null;
    try {
      oldSocket.close();
    } catch {
      // The socket may already be closing.
    }
  }
  setBadge(false);
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
  }, reconnectDelay);
  reconnectDelay = Math.min(
    Math.round(reconnectDelay * 1.6),
    RECONNECT_MAX_MS,
  );
}

async function connect() {
  const generation = ++connectGeneration;
  clearTimeout(reconnectTimer);
  reconnectTimer = null;
  closeSocket();

  const config = await readBridgeConfig();
  if (generation !== connectGeneration) return;
  if (!config.token) {
    lastError = "Pairing token not configured";
    return;
  }

  let nextSocket;
  try {
    nextSocket = new WebSocket(socketUrl(config.port));
  } catch (error) {
    lastError = error instanceof Error ? error.message : String(error);
    scheduleReconnect();
    return;
  }
  socket = nextSocket;

  nextSocket.onopen = () => {
    if (socket !== nextSocket) return;
    nextSocket.send(
      JSON.stringify({
        type: "hello",
        token: config.token,
        protocol: 1,
        extensionVersion: extensionVersion(),
        userAgent: navigator.userAgent,
      }),
    );
  };

  nextSocket.onmessage = (event) => {
    if (socket !== nextSocket) return;
    void handleBridgeMessage(event.data);
  };

  nextSocket.onerror = () => {
    if (socket === nextSocket) lastError = "Cannot reach the Tabame launcher plugin";
  };

  nextSocket.onclose = (event) => {
    if (socket !== nextSocket) return;
    socket = null;
    authenticated = false;
    clearInterval(keepaliveTimer);
    keepaliveTimer = null;
    setBadge(false);
    if (event.code === 1008) {
      lastError = event.reason || "The bridge rejected the pairing token";
    } else if (!lastError) {
      lastError = "The Tabame launcher plugin is not currently available";
    }
    scheduleReconnect();
  };
}

function sendBridge(message) {
  if (!socket || socket.readyState !== WebSocket.OPEN) return false;
  socket.send(JSON.stringify(message));
  return true;
}

async function handleBridgeMessage(raw) {
  let message;
  try {
    message = JSON.parse(raw);
  } catch {
    return;
  }

  if (message.type === "welcome") {
    authenticated = true;
    reconnectDelay = RECONNECT_MIN_MS;
    lastError = "";
    setBadge(true);
    clearInterval(keepaliveTimer);
    keepaliveTimer = setInterval(() => {
      sendBridge({ type: "ping", at: Date.now() });
    }, KEEPALIVE_MS);
    return;
  }

  if (message.type === "pong") return;
  if (message.type !== "request" || !authenticated) return;

  const id = typeof message.id === "string" ? message.id : "";
  if (!id) return;

  try {
    const result = await withTimeout(
      dispatchRequest(message.method, message.params || {}),
      REQUEST_TIMEOUT_MS,
      `Request timed out: ${message.method}`,
    );
    sendBridge({ type: "response", id, ok: true, result });
  } catch (error) {
    sendBridge({
      type: "response",
      id,
      ok: false,
      error: normalizeError(error),
    });
  }
}

function normalizeError(error) {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  return "Unexpected extension error";
}

function withTimeout(promise, timeoutMs, message) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(message)), timeoutMs);
    Promise.resolve(promise).then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (error) => {
        clearTimeout(timer);
        reject(error);
      },
    );
  });
}

async function dispatchRequest(method, params) {
  switch (method) {
    case "bridge.ping":
      return {
        connected: true,
        extensionVersion: extensionVersion(),
        browser: navigator.userAgent,
      };
    case "tabs.list":
      return listTabs();
    case "tabs.audible":
      return listAudibleTabs();
    case "tabs.activate":
      return activateTab(requireTabId(params));
    case "tabs.close":
      await chrome.tabs.remove(requireTabId(params));
      return { closed: true };
    case "tabs.mute":
      return setTabMuted(requireTabId(params), params.muted);
    case "tabs.pin":
      return setTabPinned(requireTabId(params), params.pinned);
    case "tabs.reload":
      await chrome.tabs.reload(requireTabId(params));
      return { reloaded: true };
    case "tabs.duplicate":
      return serializeTab(await chrome.tabs.duplicate(requireTabId(params)));
    case "tabs.open":
      return openTab(params.url, params.active !== false);
    case "codex.usage":
      return getCodexUsage();
    default:
      throw new Error(`Unsupported bridge method: ${method}`);
  }
}

function requireTabId(params) {
  const tabId = Number(params.tabId);
  if (!Number.isInteger(tabId) || tabId < 0) {
    throw new Error("A valid tabId is required");
  }
  return tabId;
}

function safeWebUrl(value) {
  let parsed;
  try {
    parsed = new URL(String(value || ""));
  } catch {
    throw new Error("A valid URL is required");
  }
  if (!["http:", "https:"].includes(parsed.protocol)) {
    throw new Error("Only HTTP and HTTPS URLs can be opened");
  }
  return parsed.href;
}

function serializeTab(tab, groupsById = null) {
  const group =
    groupsById && Number.isInteger(tab.groupId)
      ? groupsById.get(tab.groupId)
      : null;
  return {
    id: tab.id,
    windowId: tab.windowId,
    index: tab.index,
    title: tab.title || "Untitled tab",
    url: tab.url || tab.pendingUrl || "",
    favIconUrl: tab.favIconUrl || "",
    active: Boolean(tab.active),
    audible: Boolean(tab.audible),
    muted: Boolean(tab.mutedInfo && tab.mutedInfo.muted),
    pinned: Boolean(tab.pinned),
    discarded: Boolean(tab.discarded),
    incognito: Boolean(tab.incognito),
    status: tab.status || "unknown",
    lastAccessed: tab.lastAccessed || 0,
    groupId: Number.isInteger(tab.groupId) ? tab.groupId : -1,
    group: group
      ? {
          id: group.id,
          title: String(group.title || "").trim(),
          color: group.color,
          collapsed: Boolean(group.collapsed),
          shared: Boolean(group.shared),
        }
      : null,
  };
}

async function listTabs() {
  const [tabs, groups] = await Promise.all([
    chrome.tabs.query({}),
    chrome.tabGroups.query({}),
  ]);
  const groupsById = new Map(groups.map((group) => [group.id, group]));
  return {
    tabs: tabs.map((tab) => serializeTab(tab, groupsById)),
    count: tabs.length,
    capturedAt: new Date().toISOString(),
  };
}

async function listAudibleTabs() {
  const [audible, groups] = await Promise.all([
    chrome.tabs.query({ audible: true }),
    chrome.tabGroups.query({}),
  ]);
  const groupsById = new Map(groups.map((group) => [group.id, group]));
  const tabs = audible
    .map((tab) => serializeTab(tab, groupsById))
    .sort((a, b) => {
      if (a.active !== b.active) return a.active ? -1 : 1;
      return b.lastAccessed - a.lastAccessed;
    });
  return {
    tabs,
    current: tabs[0] || null,
    count: tabs.length,
    capturedAt: new Date().toISOString(),
  };
}

async function activateTab(tabId) {
  const tab = await chrome.tabs.get(tabId);
  await chrome.windows.update(tab.windowId, { focused: true });
  return serializeTab(await chrome.tabs.update(tabId, { active: true }));
}

async function setTabMuted(tabId, requestedState) {
  const tab = await chrome.tabs.get(tabId);
  const current = Boolean(tab.mutedInfo && tab.mutedInfo.muted);
  const muted =
    typeof requestedState === "boolean" ? requestedState : !current;
  return serializeTab(await chrome.tabs.update(tabId, { muted }));
}

async function setTabPinned(tabId, requestedState) {
  const tab = await chrome.tabs.get(tabId);
  const pinned =
    typeof requestedState === "boolean" ? requestedState : !tab.pinned;
  return serializeTab(await chrome.tabs.update(tabId, { pinned }));
}

async function openTab(url, active) {
  return serializeTab(
    await chrome.tabs.create({ url: safeWebUrl(url), active: Boolean(active) }),
  );
}

async function waitForTabComplete(tabId, timeoutMs = 20_000) {
  const existing = await chrome.tabs.get(tabId);
  if (existing.status === "complete") return existing;

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      chrome.tabs.onUpdated.removeListener(onUpdated);
      reject(new Error("The analytics page did not finish loading"));
    }, timeoutMs);

    function onUpdated(updatedTabId, changeInfo, tab) {
      if (updatedTabId !== tabId || changeInfo.status !== "complete") return;
      clearTimeout(timer);
      chrome.tabs.onUpdated.removeListener(onUpdated);
      resolve(tab);
    }

    chrome.tabs.onUpdated.addListener(onUpdated);
  });
}

async function readUsageFromTab(tabId) {
  const results = await chrome.scripting.executeScript({
    target: { tabId },
    func: () => {
      const bodyText = document.body ? document.body.innerText : "";
      const match =
        bodyText.match(/(\d+)%\Wremaining/i) ||
        bodyText.match(/(\d+)%\W+remaining/i);
      return {
        remainingPercent: match ? Number(match[1]) : null,
        pageTitle: document.title,
        pageUrl: location.href,
      };
    },
  });
  return results[0] ? results[0].result : null;
}

async function getCodexUsage() {
  let analyticsTab;
  try {
    analyticsTab = await chrome.tabs.create({
      url: ANALYTICS_URL,
      active: false,
    });
    await waitForTabComplete(analyticsTab.id);

    const deadline = Date.now() + 20_000;
    let snapshot = null;
    while (Date.now() < deadline) {
      snapshot = await readUsageFromTab(analyticsTab.id);
      if (snapshot && Number.isFinite(snapshot.remainingPercent)) {
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
  } finally {
    if (analyticsTab && Number.isInteger(analyticsTab.id)) {
      try {
        await chrome.tabs.remove(analyticsTab.id);
      } catch {
        // The user may have closed the temporary tab first.
      }
    }
  }
}

function queueTabEvent(reason) {
  clearTimeout(tabEventTimer);
  tabEventTimer = setTimeout(() => {
    if (!authenticated) return;
    sendBridge({
      type: "event",
      event: "tabs.changed",
      data: { reason, at: new Date().toISOString() },
    });
  }, 180);
}

chrome.tabs.onActivated.addListener(() => queueTabEvent("activated"));
chrome.tabs.onCreated.addListener(() => queueTabEvent("created"));
chrome.tabs.onRemoved.addListener(() => queueTabEvent("removed"));
chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
  const relevant = [
    "audible",
    "favIconUrl",
    "groupId",
    "mutedInfo",
    "pinned",
    "status",
    "title",
    "url",
  ].some((key) => Object.hasOwn(changeInfo, key));
  if (relevant) queueTabEvent("updated");
});
chrome.tabGroups.onCreated.addListener(() => queueTabEvent("group-created"));
chrome.tabGroups.onMoved.addListener(() => queueTabEvent("group-moved"));
chrome.tabGroups.onRemoved.addListener(() => queueTabEvent("group-removed"));
chrome.tabGroups.onUpdated.addListener(() => queueTabEvent("group-updated"));

chrome.runtime.onInstalled.addListener(() => {
  setBadge(false);
  chrome.alarms.create(RECONNECT_ALARM, { periodInMinutes: 1 });
  void connect();
});
chrome.runtime.onStartup.addListener(() => {
  chrome.alarms.create(RECONNECT_ALARM, { periodInMinutes: 1 });
  void connect();
});
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === RECONNECT_ALARM && !authenticated) void connect();
});
chrome.storage.onChanged.addListener((changes, area) => {
  if (
    area === "local" &&
    (Object.hasOwn(changes, "bridgeToken") ||
      Object.hasOwn(changes, "bridgePort"))
  ) {
    reconnectDelay = RECONNECT_MIN_MS;
    void connect();
  }
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || message.type !== "popup") return false;

  if (message.action === "status") {
    void readBridgeConfig().then((config) =>
      sendResponse({
        connected: authenticated,
        connecting: Boolean(socket),
        configured: Boolean(config.token),
        port: config.port,
        token: config.token,
        lastError,
        version: extensionVersion(),
      }),
    );
    return true;
  }

  if (message.action === "reconnect") {
    reconnectDelay = RECONNECT_MIN_MS;
    void connect().then(() => sendResponse({ ok: true }));
    return true;
  }

  return false;
});

void connect();
