#!/usr/bin/env node
/*
 * GitHub plugin for the Tabame launcher.
 *
 * A long-lived child process speaking the launcher's newline-delimited JSON
 * protocol (see plugins/TABAME_PLUGIN_SKILL.md). The launcher exposes a single
 * query line, so this plugin is an internal state machine: a root command list
 * that drills into each command's own screen. Sub-screens set canGoBack, so
 * Escape walks back up the stack instead of exiting the plugin.
 *
 * Runtime: Node 18+ (global fetch). No dependencies.
 *
 * Setup: on first run the plugin shows a form asking for a Personal Access
 * Token and writes it to `config.json` next to this file. You can also create
 * the file yourself (see config.example.json) or set GITHUB_TOKEN / GH_TOKEN.
 *
 * Recommended classic-token scopes: repo, workflow, notifications,
 * read:project, read:org. Fine-grained tokens work too with equivalent
 * repository/account permissions.
 */

"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");

const API = "https://api.github.com";

// GitHub state colors.
const C = {
  open: "#3FB950",
  merged: "#A371F7",
  closed: "#F85149",
  draft: "#8B949E",
  warn: "#D29922",
  gray: "#8B949E",
};

const LANG_COLORS = {
  JavaScript: "#9B754B",
  TypeScript: "#9D800D",
  Python: "#3572A5",
  Dart: "#5865F2",
  "C++": "#F34B7D",
  "C#": "#178600",
  C: "#555555",
  Go: "#00ADD8",
  Rust: "#A42F71",
  Java: "#B07219",
  Ruby: "#701516",
  PHP: "#4F5D95",
  Swift: "#F05138",
  Kotlin: "#A97BFF",
  HTML: "#E34C26",
  CSS: "#663399",
  Shell: "#5983BF",
  Vue: "#41B883",
  Lua: "#000080",
  Zig: "#EC915C",
  Elixir: "#6E4A7E",
  Haskell: "#5E5086",
  "Objective-C": "#438EFF",
};

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

function loadingFrame(rev, text) {
  render(rev, "list", {
    loading: true,
    items: [],
    emptyText: text || "Loading…",
  });
}

function renderError(rev, err) {
  const msg = err && err.message ? err.message : String(err);
  if (err && err.status === 401)
    return renderSetup(rev, "token rejected — paste a new one");
  let hint = "";
  if (/scope|permission|forbidden|resource not accessible/i.test(msg)) {
    hint =
      "\n\nYour token may be missing a scope. Classic tokens want: `repo`, `workflow`, `notifications`, `read:project`, `read:org`.";
  }
  render(rev, "detail", {
    detail: { markdown: `## GitHub error\n\n\`\`\`\n${msg}\n\`\`\`${hint}` },
  });
}

// ── config / auth ────────────────────────────────────────────────────────────
function loadConfig() {
  const cfg = {
    token: process.env.GITHUB_TOKEN || process.env.GH_TOKEN || "",
    downloadDir: "",
  };
  try {
    const file = path.join(process.cwd(), "config.json");
    if (fs.existsSync(file)) {
      const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
      if (parsed.token) cfg.token = parsed.token;
      if (parsed.downloadDir) cfg.downloadDir = parsed.downloadDir;
    }
  } catch (err) {
    log("config:", err.message);
  }
  return cfg;
}
const config = loadConfig();

function saveConfig() {
  fs.writeFileSync(
    path.join(process.cwd(), "config.json"),
    JSON.stringify(
      { token: config.token, downloadDir: config.downloadDir },
      null,
      2,
    ),
  );
}

// ── HTTP ─────────────────────────────────────────────────────────────────────
class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function authHeaders(extra) {
  return Object.assign(
    {
      Authorization: `Bearer ${config.token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "tabame-github-plugin",
    },
    extra || {},
  );
}

async function rest(method, apiPath, body) {
  const res = await fetch(
    apiPath.startsWith("http") ? apiPath : API + apiPath,
    {
      method,
      headers: authHeaders(
        body ? { "Content-Type": "application/json" } : null,
      ),
      body: body ? JSON.stringify(body) : undefined,
    },
  );
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch (_) {
    /* non-JSON body */
  }
  if (!res.ok) {
    let msg = (json && json.message) || `HTTP ${res.status}`;
    if (json && Array.isArray(json.errors) && json.errors.length) {
      msg +=
        ": " +
        json.errors
          .map((e) => e.message || e.code || JSON.stringify(e))
          .join("; ");
    }
    if (res.status === 403 && /rate limit/i.test(msg)) {
      msg = "GitHub API rate limit hit — try again in a minute.";
    }
    throw new HttpError(res.status, msg);
  }
  return json;
}

async function gql(query, variables) {
  const json = await rest("POST", "/graphql", {
    query,
    variables: variables || {},
  });
  if (json && json.errors && json.errors.length) {
    const scoped = json.errors.some((e) => e.type === "INSUFFICIENT_SCOPES");
    throw new HttpError(
      scoped ? 403 : 400,
      json.errors.map((e) => e.message).join("; "),
    );
  }
  return json.data;
}

// ── small utils ──────────────────────────────────────────────────────────────
function ago(iso) {
  if (!iso) return "—";
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 60) return "just now";
  const m = s / 60;
  if (m < 60) return `${Math.floor(m)}m ago`;
  const h = m / 60;
  if (h < 24) return `${Math.floor(h)}h ago`;
  const d = h / 24;
  if (d < 7) return `${Math.floor(d)}d ago`;
  if (d < 30) return `${Math.floor(d / 7)}w ago`;
  if (d < 365) return `${Math.floor(d / 30)}mo ago`;
  return `${Math.floor(d / 365)}y ago`;
}

function human(bytes) {
  if (bytes == null) return "—";
  if (bytes < 1024) return `${bytes} B`;
  const kb = bytes / 1024;
  if (kb < 1024) return `${kb.toFixed(0)} KB`;
  const mb = kb / 1024;
  if (mb < 1024) return `${mb.toFixed(1)} MB`;
  return `${(mb / 1024).toFixed(2)} GB`;
}

function compact(n) {
  if (n == null) return "0";
  return n >= 1000 ? `${(n / 1000).toFixed(n >= 10000 ? 0 : 1)}k` : String(n);
}

function match(text, ...vals) {
  const t = (text || "").trim().toLowerCase();
  if (!t) return true;
  const hay = vals.filter(Boolean).join(" ").toLowerCase();
  return t.split(/\s+/).every((w) => hay.includes(w));
}

function truncate(s, n) {
  if (!s) return s;
  const clean = s.replace(/\r/g, "");
  return clean.length > n ? clean.slice(0, n) + "…" : clean;
}

// Per-segment URL encoding: keeps `/` in paths and branch names intact.
function encodePath(p) {
  return String(p || "")
    .split("/")
    .map(encodeURIComponent)
    .join("/");
}

function avatar(owner) {
  if (owner && owner.avatar_url) {
    return (
      owner.avatar_url + (owner.avatar_url.includes("?") ? "&" : "?") + "s=64"
    );
  }
  return "folder";
}

async function pool(items, size, worker) {
  let i = 0;
  const runners = Array.from(
    { length: Math.min(size, items.length) },
    async () => {
      while (i < items.length) {
        const idx = i++;
        await worker(items[idx], idx);
      }
    },
  );
  await Promise.all(runners);
}

// ── caches ───────────────────────────────────────────────────────────────────
const caches = new Map();
function hasFresh(key, ttlMs) {
  const hit = caches.get(key);
  return !!hit && Date.now() - hit.at < ttlMs;
}
async function cached(key, ttlMs, fn) {
  const hit = caches.get(key);
  if (hit && Date.now() - hit.at < ttlMs) return hit.value;
  const value = await fn();
  caches.set(key, { at: Date.now(), value });
  return value;
}
function invalidate(prefix) {
  for (const key of Array.from(caches.keys())) {
    if (key.startsWith(prefix)) caches.delete(key);
  }
}

const ME_TTL = 24 * 3600 * 1000;
const REPOS_TTL = 5 * 60 * 1000;

function me() {
  return cached("me", ME_TTL, () => rest("GET", "/user"));
}

// All repos the user can push to: own, collaborator and org repos (≤300).
function myRepos() {
  return cached("repos", REPOS_TTL, async () => {
    const all = [];
    for (let page = 1; page <= 3; page++) {
      const batch = await rest(
        "GET",
        `/user/repos?per_page=100&sort=pushed&affiliation=owner,collaborator,organization_member&page=${page}`,
      );
      all.push(...batch);
      if (batch.length < 100) break;
    }
    return all;
  });
}

function starredRepos() {
  return cached("starred", REPOS_TTL, () =>
    rest("GET", "/user/starred?per_page=100"),
  );
}

function repoBranches(fullName) {
  return cached(`branches:${fullName}`, 60 * 1000, async () => {
    const list = await rest("GET", `/repos/${fullName}/branches?per_page=100`);
    return list.map((b) => b.name);
  });
}

// ── state machine ────────────────────────────────────────────────────────────
const state = {
  stack: [{ screen: "root", ctx: {}, savedQuery: "" }],
  itemsById: {},
  lastRev: 0,
  lastText: "",
  downloading: null, // {label, progress, detail} while a download runs
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
  if (state.stack.length > 1) state.stack.pop();
  const q = top().savedQuery || "";
  cmdSetQuery(q);
  return renderScreen(0, q);
}

function resetToRoot() {
  cancelSearch();
  state.stack = [{ screen: "root", ctx: {}, savedQuery: "" }];
  cmdSetQuery("");
  return renderScreen(0, "");
}

// Debounce for screens that hit the search API on every keystroke. The host
// already drops stale frames by rev; this avoids hammering the API — and the
// screen check stops a pending search from painting over another screen the
// user has already navigated to (its rev would still count as fresh).
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
    if (top() !== frame) return;
    fn().catch((err) => renderError(rev, err));
  }, 350);
}

// ── root ─────────────────────────────────────────────────────────────────────
const COMMANDS = [
  {
    id: "my_prs",
    section: "Pull Requests",
    title: "My Pull Requests",
    subtitle: "Created, review-requested or mentioning you",
    icon: "code",
  },
  {
    id: "search_prs",
    section: "Pull Requests",
    title: "Search Pull Requests",
    subtitle: "Search recent pull requests in all repositories",
    icon: "search",
  },
  {
    id: "create_pr",
    section: "Pull Requests",
    title: "Create Pull Request",
    subtitle: "Open a pull request in one of your repositories",
    icon: "add",
  },
  {
    id: "my_issues",
    section: "Issues",
    title: "My Issues",
    subtitle: "Created, assigned or mentioning you",
    icon: "info",
  },
  {
    id: "search_issues",
    section: "Issues",
    title: "Search Issues",
    subtitle: "Search recent issues in all repositories",
    icon: "search",
  },
  {
    id: "create_issue",
    section: "Issues",
    title: "Create Issue",
    subtitle: "File an issue in one of your repositories",
    icon: "add",
  },
  {
    id: "my_repos",
    section: "Repositories",
    title: "My Latest Repositories (reps)",
    subtitle: "Your repositories by latest push",
    icon: "folder",
  },
  {
    id: "starred",
    section: "Repositories",
    title: "My Starred Repositories",
    subtitle: "Repositories you have starred",
    icon: "star",
  },
  {
    id: "search_repos",
    section: "Repositories",
    title: "Search Repositories",
    subtitle: "Find your public & private repos by name",
    icon: "search",
  },
  {
    id: "create_branch",
    section: "Repositories",
    title: "Create Branch",
    subtitle: "Create a branch in one of your repositories",
    icon: "add",
  },
  {
    id: "download_repo",
    section: "Repositories",
    title: "Download Repository",
    subtitle: "Download a repo ZIP or a single directory",
    icon: "download",
  },
  {
    id: "runs",
    section: "Repositories",
    title: "Workflow Runs",
    subtitle: "Inspect, re-run or cancel GitHub Actions runs",
    icon: "run",
  },
  {
    id: "notifications",
    section: "Activity",
    title: "Notifications",
    subtitle: "Your GitHub inbox, read and unread",
    icon: "bell",
  },
  {
    id: "unread",
    section: "Activity",
    title: "Unread Notifications",
    subtitle: "Only what you have not read yet",
    icon: "bell",
  },
  {
    id: "my_discussions",
    section: "Activity",
    title: "My Discussions",
    subtitle: "Discussions you started",
    icon: "chat",
  },
  {
    id: "search_discussions",
    section: "Activity",
    title: "Search Discussions",
    subtitle: "Search recent discussions in all repositories",
    icon: "chat",
  },
  {
    id: "my_projects",
    section: "Activity",
    title: "My Projects",
    subtitle: "Your GitHub Projects",
    icon: "grid",
  },
  {
    id: "my_stats",
    section: "Account",
    title: "My GitHub Stats",
    subtitle: "Followers, stars and contributions at a glance",
    icon: "chart",
  },
  {
    id: "set_token",
    section: "Account",
    title: "Set Personal Access Token",
    subtitle: "Change the token or the download folder",
    icon: "key",
  },
];

// The "menu bar unread count" adapted to the launcher: a live badge on the
// notification commands in the root list.
let unreadBadge = null;
async function refreshUnreadBadge() {
  if (!config.token) return;
  try {
    const list = await rest("GET", "/notifications?per_page=50");
    unreadBadge = list.length
      ? list.length >= 50
        ? "50+"
        : String(list.length)
      : null;
    caches.set("notif:false", { at: Date.now(), value: list });
    if (top().screen === "root" && !state.downloading)
      renderRoot(0, state.lastText);
  } catch (err) {
    log("unread badge:", err.message);
  }
}

function renderRoot(rev, text) {
  const filtered = COMMANDS.filter((c) =>
    match(text, c.title, c.subtitle, c.section),
  );
  const items = filtered.map((c) => {
    const badge =
      unreadBadge && (c.id === "notifications" || c.id === "unread")
        ? [{ text: `${unreadBadge} unread`, color: C.open }]
        : [];
    return {
      id: `cmd:${c.id}`,
      title: c.title,
      subtitle: c.subtitle,
      icon: c.icon,
      section: c.section,
      accessories: badge,
      actions: [{ id: "default", title: "Open", icon: "open" }],
      _data: { kind: "cmd", tab: c.title },
    };
  });
  setItems(items);
  render(rev, "list", {
    items,
    placeholder: "GitHub — pick a command…",
    empty: {
      icon: "search",
      title: "No matching command",
      hint: "Try “pr”, “issue”, “repo”, “runs”…",
    },
  });
}

// ── PR / issue items (REST search results) ──────────────────────────────────
function searchIssues(q, perPage) {
  return cached(`search:${perPage}:${q}`, 30 * 1000, async () => {
    const data = await rest(
      "GET",
      `/search/issues?q=${encodeURIComponent(q)}&per_page=${perPage || 30}`,
    );
    return data.items || [];
  });
}

function issueRepo(node) {
  const i = (node.repository_url || "").indexOf("/repos/");
  return i === -1 ? "" : node.repository_url.slice(i + 7);
}

function issueState(node) {
  const isPR = !!node.pull_request;
  if (isPR && node.pull_request.merged_at)
    return { text: "merged", color: C.merged };
  if (isPR && node.draft) return { text: "draft", color: C.draft };
  if (node.state === "closed") {
    if (!isPR && node.state_reason === "not_planned")
      return { text: "not planned", color: C.gray };
    return { text: "closed", color: isPR ? C.closed : C.merged };
  }
  return { text: "open", color: C.open };
}

function issueItem(node, section) {
  const repo = issueRepo(node);
  const st = issueState(node);
  const isPR = !!node.pull_request;
  const labels = (node.labels || []).map((l) => l.name).filter(Boolean);
  const author = node.user ? node.user.login : "?";
  return {
    id: `${isPR ? "pr" : "issue"}:${node.id}`,
    title: node.title || "(untitled)",
    subtitle: `${repo}#${node.number} · @${author}`,
    icon: isPR ? "code" : "info",
    ...(section ? { section } : {}),
    accessories: [
      { text: st.text, color: st.color },
      ...(node.comments
        ? [{ icon: "message", text: String(node.comments) }]
        : []),
    ],
    actions: [
      { id: "default", title: "Open in Browser", icon: "open" },
      { id: "copy_url", title: "Copy URL", icon: "link" },
      { id: "copy_number", title: "Copy Number", icon: "copy" },
      { id: "copy_md", title: "Copy Markdown Link", icon: "copy" },
    ],
    preview: {
      markdown: `## ${node.title}\n\n${truncate(node.body || "_No description._", 1200)}`,
      metadata: [
        { label: "Repository", text: repo, url: `https://github.com/${repo}` },
        { label: "State", text: st.text, color: st.color },
        { label: "Author", text: `@${author}`, icon: "person" },
        ...(labels.length
          ? [
              {
                label: "Labels",
                text: labels.slice(0, 5).join(", "),
                icon: "tag",
              },
            ]
          : []),
        {
          label: "Comments",
          text: String(node.comments || 0),
          icon: "message",
        },
        { label: "Updated", text: ago(node.updated_at), icon: "clock" },
        { separator: true },
        { label: "Link", text: `${repo}#${node.number}`, url: node.html_url },
      ],
    },
    _data: {
      kind: "link",
      url: node.html_url,
      number: node.number,
      md: `[${repo}#${node.number} ${node.title}](${node.html_url})`,
    },
  };
}

async function renderMyPRs(rev, text) {
  if (!hasFresh("my_prs", 45 * 1000))
    loadingFrame(rev, "Loading your pull requests…");
  const login = (await me()).login;
  const groups = await cached("my_prs", 45 * 1000, async () => {
    const [review, created, mentioned] = await Promise.all([
      searchIssues(
        `is:pr is:open review-requested:${login} sort:updated-desc`,
        20,
      ),
      searchIssues(`is:pr author:${login} sort:updated-desc`, 30),
      searchIssues(
        `is:pr mentions:${login} -author:${login} sort:updated-desc`,
        20,
      ),
    ]);
    return { review, created, mentioned };
  });
  const seen = new Set();
  const items = [];
  const add = (list, section) => {
    for (const n of list) {
      if (seen.has(n.id) || !match(text, n.title, issueRepo(n), `#${n.number}`))
        continue;
      seen.add(n.id);
      items.push(issueItem(n, section));
    }
  };
  add(groups.review, "Review requested");
  add(groups.created, "Created by you");
  add(groups.mentioned, "Mentioned");
  setItems(items);
  render(rev, "list", {
    items,
    preview: { enabled: true },
    placeholder: "Filter your pull requests…",
    empty: {
      icon: "code",
      title: "No pull requests",
      hint: "Nothing involves you right now",
    },
  });
}

async function renderMyIssues(rev, text) {
  if (!hasFresh("my_issues", 45 * 1000))
    loadingFrame(rev, "Loading your issues…");
  const login = (await me()).login;
  const groups = await cached("my_issues", 45 * 1000, async () => {
    const [assigned, created, mentioned] = await Promise.all([
      searchIssues(`is:issue is:open assignee:${login} sort:updated-desc`, 25),
      searchIssues(`is:issue author:${login} sort:updated-desc`, 30),
      searchIssues(
        `is:issue mentions:${login} -author:${login} sort:updated-desc`,
        20,
      ),
    ]);
    return { assigned, created, mentioned };
  });
  const seen = new Set();
  const items = [];
  const add = (list, section) => {
    for (const n of list) {
      if (seen.has(n.id) || !match(text, n.title, issueRepo(n), `#${n.number}`))
        continue;
      seen.add(n.id);
      items.push(issueItem(n, section));
    }
  };
  add(groups.assigned, "Assigned to you");
  add(groups.created, "Created by you");
  add(groups.mentioned, "Mentioned");
  setItems(items);
  render(rev, "list", {
    items,
    preview: { enabled: true },
    placeholder: "Filter your issues…",
    empty: {
      icon: "info",
      title: "No issues",
      hint: "Nothing involves you right now",
    },
  });
}

function renderGlobalSearch(rev, text, qualifier, noun, icon) {
  const q = text.trim();
  if (!q) {
    setItems([]);
    return render(rev, "list", {
      items: [],
      placeholder: `Search ${noun} on GitHub…`,
      empty: {
        icon,
        title: `Search ${noun}`,
        hint: `Type to search recent ${noun} in all repositories`,
      },
    });
  }
  loadingFrame(rev, `Searching ${noun}…`);
  debounceSearch(rev, async () => {
    const nodes = await searchIssues(`${qualifier} ${q} sort:updated-desc`, 30);
    const items = nodes.map((n) => issueItem(n));
    setItems(items);
    render(rev, "list", {
      items,
      preview: { enabled: true },
      placeholder: `Search ${noun} on GitHub…`,
      empty: {
        icon,
        title: "No matches",
        hint: "Try different keywords or qualifiers (repo:, org:, label:)",
      },
    });
  });
}

// ── repositories ─────────────────────────────────────────────────────────────
// Only what later screens/actions need — full API repo objects are ~6 KB each
// and would bloat every render frame via `_data`.
function slimRepo(r) {
  return {
    full_name: r.full_name,
    name: r.name,
    html_url: r.html_url,
    clone_url: r.clone_url,
    default_branch: r.default_branch,
  };
}

function repoItem(r, pick) {
  const lang = r.language;
  const acc = [];
  if (r.private) acc.push({ text: "private", icon: "lock" });
  if (r.archived) acc.push({ text: "archived", color: C.gray });
  if (lang)
    acc.push(
      LANG_COLORS[lang]
        ? { text: lang, color: LANG_COLORS[lang] }
        : { text: lang },
    );
  if (r.stargazers_count)
    acc.push({ icon: "star", text: compact(r.stargazers_count) });
  return {
    id: `repo:${r.full_name}`,
    title: r.full_name,
    subtitle: r.description || "",
    icon: avatar(r.owner),
    accessories: acc,
    actions: pick
      ? [
          { id: "default", title: pick.title, icon: pick.icon },
          { id: "open", title: "Open in Browser", icon: "open" },
        ]
      : [
          { id: "default", title: "Open in Browser", icon: "open" },
          { id: "copy_url", title: "Copy URL", icon: "link" },
          { id: "copy_clone", title: "Copy Clone URL", icon: "terminal" },
          { id: "open_issues", title: "Open Issues", icon: "info" },
          { id: "open_pulls", title: "Open Pull Requests", icon: "code" },
          { id: "goto_runs", title: "Workflow Runs", icon: "run" },
          { id: "goto_download", title: "Download…", icon: "download" },
        ],
    preview: {
      markdown: `## ${r.full_name}\n\n${r.description || "_No description._"}`,
      metadata: [
        { label: "Owner", text: r.owner ? r.owner.login : "—", icon: "person" },
        {
          label: "Visibility",
          text: r.private ? "private" : "public",
          icon: r.private ? "lock" : "globe",
        },
        ...(lang
          ? [
              {
                label: "Language",
                text: lang,
                ...(LANG_COLORS[lang] ? { color: LANG_COLORS[lang] } : {}),
              },
            ]
          : []),
        { label: "Stars", text: String(r.stargazers_count || 0), icon: "star" },
        { label: "Forks", text: String(r.forks_count || 0), icon: "sync" },
        {
          label: "Open issues",
          text: String(r.open_issues_count || 0),
          icon: "info",
        },
        {
          label: "Default branch",
          text: r.default_branch || "—",
          icon: "flag",
        },
        { label: "Pushed", text: ago(r.pushed_at), icon: "clock" },
        { separator: true },
        { label: "Link", text: r.full_name, url: r.html_url },
      ],
    },
    _data: {
      kind: pick ? "repo_pick" : "repo",
      url: r.html_url,
      repo: slimRepo(r),
      tab: r.full_name,
    },
  };
}

async function renderRepoList(rev, text, fetcher, opts) {
  if (!hasFresh(opts.cacheKey, REPOS_TTL))
    loadingFrame(rev, "Loading repositories…");
  const repos = await fetcher();
  const filtered = repos.filter((r) =>
    match(text, r.full_name, opts.matchDescription ? r.description : null),
  );
  const items = filtered.slice(0, 60).map((r) => repoItem(r, opts.pick));
  if (
    opts.pick &&
    /^[\w.-]+\/[\w.-]+$/.test(text.trim()) &&
    !filtered.some((r) => r.full_name === text.trim())
  ) {
    // Let the user target any repo they can access, not just the listed ones.
    const full = text.trim();
    items.push({
      id: `pickraw:${full}`,
      title: `Use “${full}”`,
      subtitle: "Fetch this repository by name",
      icon: "search",
      accessories: [],
      actions: [
        { id: "default", title: opts.pick.title, icon: opts.pick.icon },
      ],
      _data: { kind: "repo_pick_raw", full },
    });
  }
  setItems(items);
  render(rev, "list", {
    items,
    preview: { enabled: true },
    placeholder: opts.placeholder,
    empty: {
      icon: "folder",
      title: "No repositories",
      hint: opts.emptyHint || "Nothing matched",
    },
  });
}

const PICK_LABEL = {
  create_pr: { title: "Create pull request here", icon: "code" },
  create_issue: { title: "Create issue here", icon: "add" },
  create_branch: { title: "Create branch here", icon: "add" },
  runs: { title: "Show workflow runs", icon: "run" },
  download: { title: "Browse & download", icon: "download" },
};

function renderRepoPick(rev, text) {
  const purpose = top().ctx.purpose;
  return renderRepoList(rev, text, myRepos, {
    cacheKey: "repos",
    pick: PICK_LABEL[purpose] || { title: "Select", icon: "check" },
    placeholder: "Pick a repository (or type owner/repo)…",
    emptyHint: "Type an owner/repo to use any repository",
  });
}

async function pickRepo(purpose, repoRef) {
  loadingFrame(0, "Opening repository…");
  const repo =
    typeof repoRef === "string"
      ? slimRepo(await rest("GET", `/repos/${repoRef}`))
      : repoRef;
  switch (purpose) {
    case "create_issue":
      return push("create_issue_form", { repo });
    case "create_pr": {
      const branches = await repoBranches(repo.full_name);
      return push("create_pr_form", { repo, branches });
    }
    case "create_branch": {
      const branches = await repoBranches(repo.full_name);
      return push("create_branch_form", { repo, branches });
    }
    case "runs":
      return push("runs", { repo });
    case "download":
      return push("browse", {
        repo,
        branch: repo.default_branch || "main",
        path: "",
      });
    default:
      return push("runs", { repo });
  }
}

// ── workflow runs ────────────────────────────────────────────────────────────
function runStatus(r) {
  if (r.status === "completed") {
    switch (r.conclusion) {
      case "success":
        return { text: "success", color: C.open, icon: "check" };
      case "failure":
        return { text: "failed", color: C.closed, icon: "close" };
      case "cancelled":
        return { text: "cancelled", color: C.gray, icon: "remove" };
      case "skipped":
        return { text: "skipped", color: C.gray, icon: "minus" };
      case "timed_out":
        return { text: "timed out", color: C.warn, icon: "clock" };
      case "action_required":
        return { text: "action required", color: C.warn, icon: "warning" };
      default:
        return { text: r.conclusion || "done", color: C.gray, icon: "check" };
    }
  }
  if (r.status === "in_progress")
    return { text: "running", color: C.warn, icon: "refresh" };
  return { text: r.status || "queued", color: C.warn, icon: "clock" };
}

function runItem(r) {
  const st = runStatus(r);
  const active =
    r.status === "queued" ||
    r.status === "in_progress" ||
    r.status === "waiting";
  const duration =
    r.run_started_at && r.updated_at
      ? Math.max(
          0,
          Math.round(
            (new Date(r.updated_at) - new Date(r.run_started_at)) / 1000,
          ),
        )
      : null;
  return {
    id: `wfrun:${r.id}`,
    title: r.display_title || r.name || `Run #${r.run_number}`,
    subtitle: `${r.name || "workflow"} · ${r.head_branch || "—"} · ${r.event}`,
    icon: st.icon,
    accessories: [
      { text: st.text, color: st.color },
      { text: ago(r.run_started_at || r.created_at) },
    ],
    actions: [
      { id: "default", title: "Open in Browser", icon: "open" },
      ...(r.status === "completed"
        ? [{ id: "rerun", title: "Re-run", icon: "refresh" }]
        : []),
      ...(r.conclusion === "failure"
        ? [{ id: "rerun_failed", title: "Re-run Failed Jobs", icon: "refresh" }]
        : []),
      ...(active ? [{ id: "cancel", title: "Cancel Run", icon: "close" }] : []),
      { id: "copy_url", title: "Copy URL", icon: "link" },
    ],
    preview: {
      markdown: `## ${r.display_title || r.name}`,
      metadata: [
        { label: "Workflow", text: r.name || "—", icon: "run" },
        { label: "Status", text: st.text, color: st.color },
        { label: "Branch", text: r.head_branch || "—", icon: "flag" },
        { label: "Event", text: r.event, icon: "bolt" },
        {
          label: "Actor",
          text: r.actor ? `@${r.actor.login}` : "—",
          icon: "person",
        },
        { label: "Attempt", text: String(r.run_attempt || 1), icon: "refresh" },
        ...(duration != null
          ? [{ label: "Duration", text: `${duration}s`, icon: "timer" }]
          : []),
        {
          label: "Started",
          text: ago(r.run_started_at || r.created_at),
          icon: "clock",
        },
        { separator: true },
        { label: "Link", text: `run #${r.run_number}`, url: r.html_url },
      ],
    },
    _data: {
      kind: "run",
      url: r.html_url,
      runId: r.id,
      repo: top().ctx.repo ? top().ctx.repo.full_name : "",
    },
  };
}

async function renderRuns(rev, text) {
  const repo = top().ctx.repo;
  const key = `runs:${repo.full_name}`;
  if (!hasFresh(key, 20 * 1000)) loadingFrame(rev, "Loading workflow runs…");
  const data = await cached(key, 20 * 1000, () =>
    rest("GET", `/repos/${repo.full_name}/actions/runs?per_page=40`),
  );
  let runs = data.workflow_runs || [];
  if (text.trim()) {
    runs = runs.filter((r) =>
      match(
        text,
        r.name,
        r.display_title,
        r.head_branch,
        r.event,
        r.actor && r.actor.login,
        r.conclusion,
      ),
    );
  }
  const items = runs.map(runItem);
  setItems(items);
  render(rev, "list", {
    items,
    preview: { enabled: true },
    placeholder: `Filter runs in ${repo.full_name}…`,
    empty: {
      icon: "run",
      title: "No workflow runs",
      hint: "This repository has no Actions runs yet",
    },
  });
}

// ── notifications ────────────────────────────────────────────────────────────
const NOTIF_ICONS = {
  PullRequest: "code",
  Issue: "info",
  Release: "tag",
  Discussion: "chat",
  CheckSuite: "run",
  WorkflowRun: "run",
  Commit: "code",
  RepositoryVulnerabilityAlert: "shield",
  SecurityAlert: "shield",
};

function notifItem(n, sectioned) {
  const repo = n.repository ? n.repository.full_name : "";
  const type = n.subject ? n.subject.type : "";
  const title = (n.subject && n.subject.title) || type || "Notification";
  return {
    id: `notif:${n.id}`,
    title: n.unread ? `**${title}**` : title,
    subtitle: `${repo} · ${(n.reason || "").replace(/_/g, " ")}`,
    icon: NOTIF_ICONS[type] || "bell",
    ...(sectioned ? { section: n.unread ? "Unread" : "Read" } : {}),
    accessories: [
      { text: type },
      ...(n.unread ? [{ text: "new", color: C.open }] : []),
    ],
    actions: [
      { id: "default", title: "Open in Browser", icon: "open" },
      ...(n.unread
        ? [{ id: "mark_read", title: "Mark as Read", icon: "check" }]
        : []),
      { id: "mark_all_read", title: "Mark All as Read", icon: "check" },
    ],
    preview: {
      markdown: `## ${title}`,
      metadata: [
        { label: "Repository", text: repo, url: `https://github.com/${repo}` },
        { label: "Type", text: type, icon: NOTIF_ICONS[type] || "bell" },
        {
          label: "Reason",
          text: (n.reason || "").replace(/_/g, " "),
          icon: "info",
        },
        {
          label: "Status",
          text: n.unread ? "unread" : "read",
          color: n.unread ? C.open : C.gray,
        },
        { label: "Updated", text: ago(n.updated_at), icon: "clock" },
      ],
    },
    _data: {
      kind: "notif",
      threadId: n.id,
      subject: n.subject,
      repo,
      unread: !!n.unread,
    },
  };
}

async function renderNotifications(rev, text) {
  const all = !!top().ctx.all;
  const key = `notif:${all}`;
  if (!hasFresh(key, 30 * 1000)) loadingFrame(rev, "Loading notifications…");
  const list = await cached(key, 30 * 1000, () =>
    rest("GET", `/notifications?all=${all}&per_page=50`),
  );
  let nodes = list.filter((n) =>
    match(
      text,
      n.subject && n.subject.title,
      n.repository && n.repository.full_name,
      n.reason,
    ),
  );
  if (all) {
    // Keep sections contiguous: unread first, then read.
    nodes = [
      ...nodes.filter((n) => n.unread),
      ...nodes.filter((n) => !n.unread),
    ];
  }
  const items = nodes.map((n) => notifItem(n, all));
  setItems(items);
  render(rev, "list", {
    items,
    preview: { enabled: true },
    placeholder: all ? "Filter notifications…" : "Filter unread notifications…",
    empty: {
      icon: "bell",
      title: all ? "No notifications" : "Inbox zero",
      hint: all ? "" : "Nothing unread — nice.",
    },
  });
}

async function notifHtmlUrl(subject, repo) {
  const u = subject && subject.url;
  if (!u) {
    if (
      subject &&
      (subject.type === "CheckSuite" || subject.type === "WorkflowRun")
    ) {
      return `https://github.com/${repo}/actions`;
    }
    return `https://github.com/${repo}`;
  }
  if (subject.type === "Release") {
    try {
      const rel = await rest("GET", u);
      return rel.html_url;
    } catch (_) {
      return `https://github.com/${repo}/releases`;
    }
  }
  return u
    .replace("https://api.github.com/repos/", "https://github.com/")
    .replace("/pulls/", "/pull/")
    .replace("/commits/", "/commit/");
}

// ── discussions ──────────────────────────────────────────────────────────────
const DISCUSSION_FIELDS = `... on Discussion {
  title url updatedAt isAnswered
  repository { nameWithOwner }
  author { login }
  comments { totalCount }
  category { name emoji }
}`;

function searchDiscussions(q) {
  return cached(`disc:${q}`, 45 * 1000, async () => {
    const data = await gql(
      `query($q: String!) { search(query: $q, type: DISCUSSION, first: 30) { nodes { ${DISCUSSION_FIELDS} } } }`,
      { q },
    );
    return (data.search.nodes || []).filter((n) => n && n.title);
  });
}

function discussionItem(d) {
  const repo = d.repository ? d.repository.nameWithOwner : "";
  const category = d.category ? d.category.name : "";
  return {
    id: `disc:${d.url}`,
    title: d.title,
    subtitle: `${repo}${category ? ` · ${category}` : ""} · @${d.author ? d.author.login : "?"}`,
    icon: "chat",
    accessories: [
      ...(d.isAnswered ? [{ text: "answered", color: C.open }] : []),
      ...(d.comments && d.comments.totalCount
        ? [{ icon: "message", text: String(d.comments.totalCount) }]
        : []),
    ],
    actions: [
      { id: "default", title: "Open in Browser", icon: "open" },
      { id: "copy_url", title: "Copy URL", icon: "link" },
    ],
    preview: {
      markdown: `## ${d.title}`,
      metadata: [
        { label: "Repository", text: repo, url: `https://github.com/${repo}` },
        ...(category
          ? [{ label: "Category", text: category, icon: "tag" }]
          : []),
        {
          label: "Author",
          text: d.author ? `@${d.author.login}` : "—",
          icon: "person",
        },
        {
          label: "Answered",
          text: d.isAnswered ? "yes" : "no",
          color: d.isAnswered ? C.open : C.gray,
        },
        {
          label: "Comments",
          text: String(d.comments ? d.comments.totalCount : 0),
          icon: "message",
        },
        { label: "Updated", text: ago(d.updatedAt), icon: "clock" },
        { separator: true },
        { label: "Link", text: "open discussion", url: d.url },
      ],
    },
    _data: { kind: "link", url: d.url },
  };
}

function renderSearchDiscussions(rev, text) {
  const q = text.trim();
  if (!q) {
    setItems([]);
    return render(rev, "list", {
      items: [],
      placeholder: "Search discussions on GitHub…",
      empty: {
        icon: "chat",
        title: "Search discussions",
        hint: "Type to search recent discussions in all repositories",
      },
    });
  }
  loadingFrame(rev, "Searching discussions…");
  debounceSearch(rev, async () => {
    const nodes = await searchDiscussions(`${q} sort:updated-desc`);
    const items = nodes.map(discussionItem);
    setItems(items);
    render(rev, "list", {
      items,
      preview: { enabled: true },
      placeholder: "Search discussions on GitHub…",
      empty: {
        icon: "chat",
        title: "No matches",
        hint: "Try different keywords",
      },
    });
  });
}

async function renderMyDiscussions(rev, text) {
  if (!hasFresh("my_disc", 60 * 1000))
    loadingFrame(rev, "Loading your discussions…");
  const login = (await me()).login;
  const nodes = await cached("my_disc", 60 * 1000, () =>
    searchDiscussions(`author:${login} sort:updated-desc`),
  );
  const filtered = nodes.filter((d) =>
    match(text, d.title, d.repository && d.repository.nameWithOwner),
  );
  const items = filtered.map(discussionItem);
  setItems(items);
  render(rev, "list", {
    items,
    preview: { enabled: true },
    placeholder: "Filter your discussions…",
    empty: {
      icon: "chat",
      title: "No discussions",
      hint: "You have not started any discussions",
    },
  });
}

// ── projects ─────────────────────────────────────────────────────────────────
async function renderMyProjects(rev, text) {
  if (!hasFresh("projects", 60 * 1000))
    loadingFrame(rev, "Loading your projects…");
  const nodes = await cached("projects", 60 * 1000, async () => {
    const data = await gql(`{
      viewer {
        projectsV2(first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
          nodes { title shortDescription url number closed public updatedAt items { totalCount } }
        }
      }
    }`);
    return data.viewer.projectsV2.nodes || [];
  });
  const filtered = nodes.filter((p) =>
    match(text, p.title, p.shortDescription),
  );
  const items = filtered.map((p) => ({
    id: `proj:${p.url}`,
    title: p.title,
    subtitle: p.shortDescription || `#${p.number}`,
    icon: "grid",
    accessories: [
      { text: p.closed ? "closed" : "open", color: p.closed ? C.gray : C.open },
      { text: `${p.items ? p.items.totalCount : 0} items` },
    ],
    actions: [
      { id: "default", title: "Open in Browser", icon: "open" },
      { id: "copy_url", title: "Copy URL", icon: "link" },
    ],
    preview: {
      markdown: `## ${p.title}\n\n${p.shortDescription || "_No description._"}`,
      metadata: [
        { label: "Number", text: `#${p.number}` },
        {
          label: "State",
          text: p.closed ? "closed" : "open",
          color: p.closed ? C.gray : C.open,
        },
        {
          label: "Visibility",
          text: p.public ? "public" : "private",
          icon: p.public ? "globe" : "lock",
        },
        {
          label: "Items",
          text: String(p.items ? p.items.totalCount : 0),
          icon: "list",
        },
        { label: "Updated", text: ago(p.updatedAt), icon: "clock" },
        { separator: true },
        { label: "Link", text: "open project", url: p.url },
      ],
    },
    _data: { kind: "link", url: p.url },
  }));
  setItems(items);
  render(rev, "list", {
    items,
    preview: { enabled: true },
    placeholder: "Filter your projects…",
    empty: {
      icon: "grid",
      title: "No projects",
      hint: "Classic tokens need the read:project scope",
    },
  });
}

// ── stats (the "menu bar stats" adapted to a detail screen) ──────────────────
async function renderMyStats(rev) {
  if (!hasFresh("stats", 120 * 1000))
    loadingFrame(rev, "Crunching your numbers…");
  const v = await cached("stats", 120 * 1000, async () => {
    const data = await gql(`{
      viewer {
        login name url avatarUrl createdAt
        followers { totalCount }
        following { totalCount }
        gists { totalCount }
        starredRepositories { totalCount }
        pullRequests { totalCount }
        issues { totalCount }
        repositories(first: 100, ownerAffiliations: OWNER, orderBy: {field: STARGAZERS, direction: DESC}) {
          totalCount
          nodes { stargazerCount }
        }
        contributionsCollection {
          totalCommitContributions
          totalPullRequestReviewContributions
          contributionCalendar {
            totalContributions
            weeks { contributionDays { contributionCount } }
          }
        }
      }
    }`);
    return data.viewer;
  });
  const starsReceived = (v.repositories.nodes || []).reduce(
    (s, r) => s + (r.stargazerCount || 0),
    0,
  );
  const cc = v.contributionsCollection;
  const weekly = (cc.contributionCalendar.weeks || [])
    .map((w) => w.contributionDays.reduce((s, d) => s + d.contributionCount, 0))
    .slice(-26);
  const since = new Date(v.createdAt).toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
  });
  render(rev, "detail", {
    detail: {
      markdown: `# ${v.name || v.login} (@${v.login})\n\n![avatar](${v.avatarUrl}${v.avatarUrl.includes("?") ? "&" : "?"}s=96)`,
      metadata: [
        {
          label: "Followers",
          text: compact(v.followers.totalCount),
          icon: "people",
        },
        {
          label: "Following",
          text: compact(v.following.totalCount),
          icon: "person",
        },
        {
          label: "Repositories",
          text: String(v.repositories.totalCount),
          icon: "folder",
        },
        {
          label: "Stars received",
          text: compact(starsReceived),
          icon: "star",
          color: C.warn,
        },
        {
          label: "Repos starred",
          text: compact(v.starredRepositories.totalCount),
          icon: "favorite",
        },
        { separator: true },
        {
          label: "Pull requests",
          text: compact(v.pullRequests.totalCount),
          icon: "code",
        },
        { label: "Issues", text: compact(v.issues.totalCount), icon: "info" },
        { label: "Gists", text: String(v.gists.totalCount), icon: "document" },
        { separator: true },
        {
          label: "Commits (year)",
          text: compact(cc.totalCommitContributions),
          icon: "check",
        },
        {
          label: "Reviews (year)",
          text: compact(cc.totalPullRequestReviewContributions),
          icon: "search",
        },
        ...(weekly.length >= 2
          ? [
              {
                label: "Activity",
                sparkline: weekly,
                text: `${compact(cc.contributionCalendar.totalContributions)} in the last year`,
                color: C.open,
              },
            ]
          : []),
        { separator: true },
        { label: "Member since", text: since, icon: "calendar" },
        { label: "Profile", text: `github.com/${v.login}`, url: v.url },
      ],
    },
  });
}

// ── download / browse ────────────────────────────────────────────────────────
function ensureDownloadDir() {
  const dir =
    config.downloadDir && config.downloadDir.trim()
      ? config.downloadDir.trim()
      : path.join(os.homedir(), "Downloads");
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function uniquePath(p) {
  if (!fs.existsSync(p)) return p;
  const ext = path.extname(p);
  const base = p.slice(0, p.length - ext.length);
  for (let i = 1; i < 100; i++) {
    const candidate = `${base} (${i})${ext}`;
    if (!fs.existsSync(candidate)) return candidate;
  }
  return `${base}-${Date.now()}${ext}`;
}

async function renderBrowse(rev, text) {
  const { repo, branch } = top().ctx;
  const dirPath = top().ctx.path || "";
  const key = `contents:${repo.full_name}:${branch}:${dirPath}`;
  if (!hasFresh(key, 60 * 1000)) loadingFrame(rev, "Loading contents…");
  const list = await cached(key, 60 * 1000, () =>
    rest(
      "GET",
      `/repos/${repo.full_name}/contents/${encodePath(dirPath)}?ref=${encodeURIComponent(branch)}`,
    ),
  );
  const entries = Array.isArray(list) ? list : [list];
  const items = [];
  if (!dirPath) {
    items.push({
      id: "dl:zip",
      title: "Download repository as ZIP",
      subtitle: `${repo.full_name} @ ${branch}`,
      icon: "download",
      accessories: [],
      actions: [{ id: "default", title: "Download ZIP", icon: "download" }],
      _data: { kind: "dl_zip" },
    });
  } else {
    items.push({
      id: "dl:dir",
      title: "Download this directory",
      subtitle: `/${dirPath}`,
      icon: "download",
      accessories: [],
      actions: [
        { id: "default", title: "Download directory", icon: "download" },
      ],
      _data: { kind: "dl_dir" },
    });
  }
  const byName = (a, b) => a.name.localeCompare(b.name);
  const dirs = entries.filter((e) => e.type === "dir").sort(byName);
  const files = entries.filter((e) => e.type !== "dir").sort(byName);
  for (const e of dirs) {
    if (!match(text, e.name)) continue;
    items.push({
      id: `dir:${e.path}`,
      title: e.name,
      subtitle: "",
      icon: "folder",
      section: "Folders",
      accessories: [],
      actions: [
        { id: "default", title: "Open Folder", icon: "folder" },
        {
          id: "download_dir",
          title: "Download This Directory",
          icon: "download",
        },
        { id: "open_web", title: "Open in Browser", icon: "open" },
      ],
      _data: { kind: "dir", path: e.path, url: e.html_url },
    });
  }
  for (const e of files) {
    if (!match(text, e.name)) continue;
    items.push({
      id: `file:${e.path}`,
      title: e.name,
      subtitle: human(e.size),
      icon: "file",
      section: "Files",
      accessories: [],
      actions: [
        { id: "default", title: "Download File", icon: "download" },
        { id: "open_web", title: "Open in Browser", icon: "open" },
        { id: "copy_raw", title: "Copy Raw URL", icon: "link" },
      ],
      _data: {
        kind: "file",
        path: e.path,
        url: e.html_url,
        raw: e.download_url,
      },
    });
  }
  setItems(items);
  render(rev, "list", {
    items,
    placeholder: `Browse ${repo.full_name}${dirPath ? "/" + dirPath : ""}…`,
    empty: { icon: "folder", title: "Empty directory", hint: "" },
  });
}

function renderDownloading(rev) {
  const d = state.downloading;
  const item = {
    id: "dl:progress",
    title: d.label,
    subtitle: d.detail || "Starting…",
    icon: "download",
    accessories: [],
    actions: [],
  };
  if (d.progress != null) item.progress = d.progress;
  send({
    type: "render",
    rev,
    view: "list",
    canGoBack: false,
    placeholder: "Downloading… (Esc closes the launcher and aborts)",
    items: [item],
  });
}

async function startDownload(label, job) {
  if (state.downloading) return cmdToast("A download is already running");
  state.downloading = { label, progress: null, detail: "" };
  renderDownloading(0);
  try {
    const dest = await job();
    state.downloading = null;
    cmdToast(`Saved to ${dest}`);
    cmdOpen(path.dirname(dest));
    renderScreen(0, state.lastText);
  } catch (err) {
    state.downloading = null;
    renderError(0, err);
  }
}

function throttledProgress(progress, detail) {
  const d = state.downloading;
  if (!d) return;
  d.progress = progress;
  d.detail = detail;
  const now = Date.now();
  if (!d._last || now - d._last > 200) {
    d._last = now;
    renderDownloading(0);
  }
}

async function jobZip(repo, branch) {
  const dir = ensureDownloadDir();
  const res = await fetch(
    `${API}/repos/${repo.full_name}/zipball/${encodePath(branch)}`,
    {
      headers: authHeaders(),
    },
  );
  if (!res.ok)
    throw new HttpError(res.status, `ZIP download failed (HTTP ${res.status})`);
  const total = Number(res.headers.get("content-length")) || 0;
  const dest = uniquePath(
    path.join(dir, `${repo.name}-${String(branch).replace(/[\\/]/g, "-")}.zip`),
  );
  const ws = fs.createWriteStream(dest);
  const reader = res.body.getReader();
  let got = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    await new Promise((resolve, reject) =>
      ws.write(Buffer.from(value), (e) => (e ? reject(e) : resolve())),
    );
    got += value.length;
    throttledProgress(
      total ? got / total : null,
      total ? `${human(got)} of ${human(total)}` : `${human(got)} so far`,
    );
  }
  await new Promise((r) => ws.end(r));
  return dest;
}

async function fetchRawFile(repo, branch, filePath) {
  const res = await fetch(
    `${API}/repos/${repo.full_name}/contents/${encodePath(filePath)}?ref=${encodeURIComponent(branch)}`,
    { headers: authHeaders({ Accept: "application/vnd.github.raw" }) },
  );
  if (!res.ok)
    throw new HttpError(
      res.status,
      `Failed to download ${filePath} (HTTP ${res.status})`,
    );
  return Buffer.from(await res.arrayBuffer());
}

async function jobDir(repo, branch, dirPath) {
  const tree = await rest(
    "GET",
    `/repos/${repo.full_name}/git/trees/${encodePath(branch)}?recursive=1`,
  );
  const prefix = dirPath + "/";
  const blobs = (tree.tree || []).filter(
    (e) => e.type === "blob" && e.path.startsWith(prefix),
  );
  if (!blobs.length) throw new Error("This directory has no files.");
  const root = uniquePath(
    path.join(ensureDownloadDir(), `${repo.name}-${dirPath.split("/").pop()}`),
  );
  let done = 0;
  await pool(blobs, 5, async (b) => {
    const dest = path.join(root, b.path.slice(prefix.length));
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, await fetchRawFile(repo, branch, b.path));
    done++;
    throttledProgress(done / blobs.length, `${done} / ${blobs.length} files`);
  });
  if (tree.truncated)
    cmdToast("Note: the repo tree was truncated — some files may be missing.");
  return root;
}

async function jobFile(repo, branch, filePath) {
  const data = await fetchRawFile(repo, branch, filePath);
  const dest = uniquePath(
    path.join(ensureDownloadDir(), path.basename(filePath)),
  );
  fs.writeFileSync(dest, data);
  return dest;
}

// ── forms ────────────────────────────────────────────────────────────────────
function renderSetup(rev, note) {
  render(rev, "form", {
    form: {
      title: note ? `GitHub — ${note}` : "GitHub — connect your account",
      submitLabel: "Save & Sign in",
      fields: [
        {
          id: "token",
          type: "password",
          label:
            "Personal Access Token — create one at github.com/settings/tokens",
          placeholder: "ghp_… or github_pat_…",
        },
        {
          id: "downloadDir",
          type: "text",
          label: "Download folder (optional)",
          placeholder: path.join(os.homedir(), "Downloads"),
          value: config.downloadDir || "",
        },
      ],
    },
  });
}

function renderCreateIssueForm(rev) {
  const { repo } = top().ctx;
  render(rev, "form", {
    form: {
      title: `New issue — ${repo.full_name}`,
      submitLabel: "Create Issue",
      fields: [
        {
          id: "title",
          type: "text",
          label: "Title",
          placeholder: "Short summary",
        },
        {
          id: "body",
          type: "textarea",
          label: "Description",
          placeholder: "Markdown supported (optional)",
        },
        {
          id: "labels",
          type: "text",
          label: "Labels",
          placeholder: "bug, help wanted — comma separated (optional)",
        },
        {
          id: "assign_me",
          type: "checkbox",
          label: "Assign to me",
          value: false,
        },
      ],
    },
  });
}

function renderCreatePRForm(rev) {
  const { repo, branches } = top().ctx;
  const def = repo.default_branch || branches[0];
  const firstHead = branches.find((b) => b !== def) || def;
  render(rev, "form", {
    form: {
      title: `New pull request — ${repo.full_name}`,
      submitLabel: "Create Pull Request",
      fields: [
        {
          id: "title",
          type: "text",
          label: "Title",
          placeholder: "What does it change?",
        },
        {
          id: "head",
          type: "dropdown",
          label: "From branch (head)",
          value: firstHead,
          options: branches,
        },
        {
          id: "base",
          type: "dropdown",
          label: "Into branch (base)",
          value: def,
          options: branches,
        },
        {
          id: "body",
          type: "textarea",
          label: "Description",
          placeholder: "Markdown supported (optional)",
        },
        {
          id: "draft",
          type: "checkbox",
          label: "Create as draft",
          value: false,
        },
      ],
    },
  });
}

function renderCreateBranchForm(rev) {
  const { repo, branches } = top().ctx;
  const def = repo.default_branch || branches[0];
  render(rev, "form", {
    form: {
      title: `New branch — ${repo.full_name}`,
      submitLabel: "Create Branch",
      fields: [
        {
          id: "name",
          type: "text",
          label: "Branch name",
          placeholder: "feature/my-branch",
        },
        {
          id: "from",
          type: "dropdown",
          label: "From",
          value: def,
          options: branches,
        },
      ],
    },
  });
}

async function submitSetup(values) {
  const token = (values.token || "").trim();
  const dl = (values.downloadDir || "").trim();
  if (!token && !config.token) {
    cmdToast("Paste a Personal Access Token first");
    return renderScreen(0, state.lastText);
  }
  if (token) {
    const res = await fetch(`${API}/user`, {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/vnd.github+json",
        "User-Agent": "tabame-github-plugin",
      },
    });
    if (!res.ok) {
      cmdToast(`Token rejected (HTTP ${res.status})`);
      return renderScreen(0, state.lastText);
    }
    const user = await res.json();
    config.token = token;
    caches.clear();
    unreadBadge = null;
    cmdToast(`Signed in as @${user.login}`);
  } else {
    cmdToast("Settings saved");
  }
  config.downloadDir = dl;
  saveConfig();
  refreshUnreadBadge();
  return resetToRoot();
}

async function submitCreateIssue(values) {
  const { repo } = top().ctx;
  const title = (values.title || "").trim();
  if (!title) {
    cmdToast("A title is required");
    return renderScreen(0, state.lastText);
  }
  const body = { title, body: values.body || "" };
  const labels = (values.labels || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  if (labels.length) body.labels = labels;
  if (values.assign_me) body.assignees = [(await me()).login];
  const issue = await rest("POST", `/repos/${repo.full_name}/issues`, body);
  cmdToast(`Created issue #${issue.number}`);
  cmdOpen(issue.html_url);
  cmdHide();
}

async function submitCreatePR(values) {
  const { repo } = top().ctx;
  const title = (values.title || "").trim();
  if (!title) {
    cmdToast("A title is required");
    return renderScreen(0, state.lastText);
  }
  if (values.head === values.base) {
    cmdToast("Head and base must be different branches");
    return renderScreen(0, state.lastText);
  }
  const pr = await rest("POST", `/repos/${repo.full_name}/pulls`, {
    title,
    head: values.head,
    base: values.base,
    body: values.body || "",
    draft: !!values.draft,
  });
  cmdToast(`Created pull request #${pr.number}`);
  cmdOpen(pr.html_url);
  cmdHide();
}

async function submitCreateBranch(values) {
  const { repo } = top().ctx;
  const name = (values.name || "").trim();
  if (!name) {
    cmdToast("A branch name is required");
    return renderScreen(0, state.lastText);
  }
  const ref = await rest(
    "GET",
    `/repos/${repo.full_name}/git/ref/heads/${encodePath(values.from)}`,
  );
  await rest("POST", `/repos/${repo.full_name}/git/refs`, {
    ref: `refs/heads/${name}`,
    sha: ref.object.sha,
  });
  invalidate(`branches:${repo.full_name}`);
  cmdToast(`Created branch ${name} from ${values.from}`);
  return resetToRoot();
}

// ── screen dispatch ──────────────────────────────────────────────────────────
async function renderScreen(rev, text) {
  state.lastText = text;
  if (state.downloading) return renderDownloading(rev);
  const frame = top();
  if (!config.token && frame.screen !== "setup") return renderSetup(rev, null);
  try {
    switch (frame.screen) {
      case "root":
        return renderRoot(rev, text);
      case "setup":
        return renderSetup(rev, null);
      case "my_prs":
        return await renderMyPRs(rev, text);
      case "search_prs":
        return renderGlobalSearch(rev, text, "is:pr", "pull requests", "code");
      case "my_issues":
        return await renderMyIssues(rev, text);
      case "search_issues":
        return renderGlobalSearch(rev, text, "is:issue", "issues", "info");
      case "repo_pick":
        return await renderRepoPick(rev, text);
      case "my_repos":
        return await renderRepoList(rev, text, myRepos, {
          cacheKey: "repos",
          matchDescription: true,
          placeholder: "Filter your repositories…",
          emptyHint: "No repositories you can access matched",
        });
      case "starred":
        return await renderRepoList(rev, text, starredRepos, {
          cacheKey: "starred",
          matchDescription: true,
          placeholder: "Filter starred repositories…",
          emptyHint: "You have not starred anything (that matches)",
        });
      case "search_repos":
        return await renderRepoList(rev, text, myRepos, {
          cacheKey: "repos",
          placeholder: "Search your repositories by name…",
          emptyHint: "No repository name matched",
        });
      case "runs":
        return await renderRuns(rev, text);
      case "notifications":
        return await renderNotifications(rev, text);
      case "search_discussions":
        return renderSearchDiscussions(rev, text);
      case "my_discussions":
        return await renderMyDiscussions(rev, text);
      case "my_projects":
        return await renderMyProjects(rev, text);
      case "my_stats":
        return await renderMyStats(rev);
      case "browse":
        return await renderBrowse(rev, text);
      case "create_issue_form":
        return renderCreateIssueForm(rev);
      case "create_pr_form":
        return renderCreatePRForm(rev);
      case "create_branch_form":
        return renderCreateBranchForm(rev);
      default:
        return renderRoot(rev, text);
    }
  } catch (err) {
    renderError(rev, err);
  }
}

// ── actions ──────────────────────────────────────────────────────────────────
async function runCommand(cmdId) {
  switch (cmdId) {
    case "my_prs":
    case "search_prs":
    case "my_issues":
    case "search_issues":
    case "my_repos":
    case "starred":
    case "search_repos":
    case "my_discussions":
    case "search_discussions":
    case "my_projects":
    case "my_stats":
    case "setup":
      return push(cmdId);
    case "set_token":
      return push("setup");
    case "notifications":
      return push("notifications", { all: true });
    case "unread":
      return push("notifications", { all: false });
    case "create_pr":
    case "create_issue":
    case "create_branch":
      return push("repo_pick", { purpose: cmdId });
    case "runs":
      return push("repo_pick", { purpose: "runs" });
    case "download_repo":
      return push("repo_pick", { purpose: "download" });
    default:
      return renderRoot(0, "");
  }
}

async function handleRepoAction(d, action) {
  const r = d.repo;
  switch (action) {
    case "open_issues":
      cmdOpen(`${r.html_url}/issues`);
      return cmdHide();
    case "open_pulls":
      cmdOpen(`${r.html_url}/pulls`);
      return cmdHide();
    case "goto_runs":
      return push("runs", { repo: r });
    case "goto_download":
      return push("browse", {
        repo: r,
        branch: r.default_branch || "main",
        path: "",
      });
    default:
      cmdOpen(r.html_url);
      return cmdHide();
  }
}

async function handleNotifAction(d, action) {
  if (action === "mark_read") {
    await rest("PATCH", `/notifications/threads/${d.threadId}`);
    invalidate("notif:");
    cmdToast("Marked as read");
    refreshUnreadBadge();
    return renderScreen(0, state.lastText);
  }
  if (action === "mark_all_read") {
    await rest("PUT", "/notifications", { read: true });
    invalidate("notif:");
    unreadBadge = null;
    cmdToast("All notifications marked as read");
    return renderScreen(0, state.lastText);
  }
  // Default: open in the browser (and quietly mark the thread read).
  const url = await notifHtmlUrl(d.subject, d.repo);
  if (d.unread) {
    rest("PATCH", `/notifications/threads/${d.threadId}`)
      .then(() => invalidate("notif:"))
      .catch(() => {});
  }
  cmdOpen(url);
  return cmdHide();
}

async function handleRunAction(d, action) {
  if (action === "rerun" || action === "rerun_failed") {
    const suffix = action === "rerun_failed" ? "rerun-failed-jobs" : "rerun";
    await rest("POST", `/repos/${d.repo}/actions/runs/${d.runId}/${suffix}`);
    invalidate(`runs:${d.repo}`);
    cmdToast(
      action === "rerun_failed" ? "Re-running failed jobs" : "Run restarted",
    );
    return renderScreen(0, state.lastText);
  }
  if (action === "cancel") {
    await rest("POST", `/repos/${d.repo}/actions/runs/${d.runId}/cancel`);
    invalidate(`runs:${d.repo}`);
    cmdToast("Cancel requested");
    return renderScreen(0, state.lastText);
  }
  cmdOpen(d.url);
  return cmdHide();
}

async function handleAction(id, action) {
  try {
    if (state.downloading) return; // one thing at a time
    if (id.startsWith("cmd:")) return await runCommand(id.slice(4));

    const item = state.itemsById[id];
    const d = item && item._data ? item._data : {};

    // Generic copy actions shared by several item kinds.
    if (action === "copy_url") return cmdCopy(d.url || "");
    if (action === "copy_number" && d.number != null)
      return cmdCopy(`#${d.number}`);
    if (action === "copy_md" && d.md) return cmdCopy(d.md);
    if (action === "copy_clone" && d.repo) return cmdCopy(d.repo.clone_url);
    if (action === "copy_raw" && d.raw) return cmdCopy(d.raw);
    if (action === "open" || action === "open_web") {
      if (d.url) {
        cmdOpen(d.url);
        cmdHide();
      }
      return;
    }

    switch (d.kind) {
      case "repo_pick":
        return await pickRepo(top().ctx.purpose, d.repo);
      case "repo_pick_raw":
        return await pickRepo(top().ctx.purpose, d.full);
      case "repo":
        return await handleRepoAction(d, action);
      case "notif":
        return await handleNotifAction(d, action);
      case "run":
        return await handleRunAction(d, action);
      case "dir": {
        const ctx = top().ctx;
        if (action === "download_dir") {
          return startDownload(`Downloading /${d.path}`, () =>
            jobDir(ctx.repo, ctx.branch, d.path),
          );
        }
        return push("browse", {
          repo: ctx.repo,
          branch: ctx.branch,
          path: d.path,
        });
      }
      case "file": {
        const ctx = top().ctx;
        return startDownload(`Downloading ${path.basename(d.path)}`, () =>
          jobFile(ctx.repo, ctx.branch, d.path),
        );
      }
      case "dl_zip": {
        const ctx = top().ctx;
        return startDownload(`Downloading ${ctx.repo.full_name}.zip`, () =>
          jobZip(ctx.repo, ctx.branch),
        );
      }
      case "dl_dir": {
        const ctx = top().ctx;
        return startDownload(`Downloading /${ctx.path}`, () =>
          jobDir(ctx.repo, ctx.branch, ctx.path),
        );
      }
      case "link":
      default:
        if (d.url) {
          cmdOpen(d.url);
          cmdHide();
        }
        return;
    }
  } catch (err) {
    cmdToast(`Error: ${err.message}`);
  }
}

async function handleSubmit(values) {
  // With no token yet, the setup form is shown regardless of the stack screen.
  const screen =
    !config.token && top().screen !== "setup" ? "setup" : top().screen;
  try {
    switch (screen) {
      case "setup":
        return await submitSetup(values);
      case "create_issue_form":
        return await submitCreateIssue(values);
      case "create_pr_form":
        return await submitCreatePR(values);
      case "create_branch_form":
        return await submitCreateBranch(values);
      default:
        return;
    }
  } catch (err) {
    // Re-render the same form: the host keeps what the user typed.
    cmdToast(`Error: ${err.message}`);
    renderScreen(0, state.lastText);
  }
}

function handleTab(id) {
  const item = state.itemsById[id];
  const tab = item && item._data && item._data.tab;
  if (tab) cmdSetQuery(tab);
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
      process.exit(0);
      break;
    case "init":
      if (config.token) {
        // Warm the caches that make the first screens feel instant.
        refreshUnreadBadge();
        me().catch(() => {});
        myRepos().catch(() => {});
      }
      state.lastRev = msg.rev || 0;
      await renderScreen(msg.rev || 0, msg.query != null ? msg.query : "");
      break;
    case "query":
      state.lastRev = msg.rev || 0;
      await renderScreen(msg.rev || 0, msg.text != null ? msg.text : "");
      break;
    case "action":
      await handleAction(msg.id || "", msg.action || "default");
      break;
    case "submit":
      await handleSubmit(msg.values || {});
      break;
    case "back":
      await popScreen();
      break;
    case "tab":
      handleTab(msg.id || "");
      break;
    // 'select' needs no work — previews are provided per item.
  }
}
