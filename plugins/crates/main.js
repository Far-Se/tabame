#!/usr/bin/env node
'use strict';

/**
 * Crates.io — a Tabame launcher plugin.
 *
 * Type `crate <query>` to search crates.io. Enter (or the "View details"
 * action) opens the full crate detail screen (license, downloads, links).
 * Ctrl+K on any result offers: open on crates.io, open docs.rs, open the
 * repository, copy a `cargo add` line, or copy the bare crate name.
 *
 * Requires Node 18+ (uses the global `fetch`/`AbortController`). No
 * dependencies, so no package.json / npm install step is needed — Tabame
 * launches `node main.js` directly.
 *
 * Protocol: newline-delimited JSON on stdin/stdout. See
 * TABAME_PLUGIN_SKILL.md for the full spec this follows.
 */

const API_BASE = 'https://crates.io/api/v1/crates';
// crates.io asks bots/scripts to identify themselves with a contact-able UA.
const USER_AGENT = 'TabameCratesPlugin/1.0 (github.com/Far-Se/tabame)';
const PER_PAGE = 20;
const DEBOUNCE_MS = 250;

function send(frame) {
  process.stdout.write(JSON.stringify(frame) + '\n');
}

function log(...args) {
  console.error(...args); // stderr only — stdout is protocol-only
}

function formatNumber(n) {
  if (typeof n !== 'number') return '0';
  try {
    return new Intl.NumberFormat('en-US', { notation: 'compact', maximumFractionDigits: 1 }).format(n);
  } catch {
    return String(n);
  }
}

function formatDate(iso) {
  if (!iso) return '—';
  try {
    return new Date(iso).toISOString().slice(0, 10);
  } catch {
    return iso;
  }
}

// ---- state -----------------------------------------------------------
// id -> title, for `tab` autocomplete.
const LAST_ITEMS = {};
// id -> last-seen crate summary from a search response, so Ctrl+K actions
// (open/docs/repo/copy) don't need an extra network round trip.
const CRATE_MAP = {};

const STATE = {
  screen: 'list', // 'list' | 'detail'
  query: '',
  page: 1,
  total: 0,
  crates: [], // accumulated results for the current query (for loadMore)
  currentCrateId: null,
  lastListFrame: null, // cached root frame, replayed on `back`
};

let debounceTimer = null;
let abortController = null;
let searchGeneration = 0;

const FRAME_ACTIONS = [
  { id: 'frame:refresh', title: 'Refresh', icon: 'refresh', shortcut: 'ctrl+r' },
];

// ---- crates.io API -----------------------------------------------------

async function apiFetch(url, signal) {
  const res = await fetch(url, {
    headers: { 'User-Agent': USER_AGENT, Accept: 'application/json' },
    signal,
  });
  if (!res.ok) {
    const err = new Error(`crates.io returned ${res.status} ${res.statusText}`);
    err.status = res.status;
    throw err;
  }
  return res.json();
}

async function searchCrates(query, page, signal) {
  const url = `${API_BASE}?q=${encodeURIComponent(query)}&page=${page}&per_page=${PER_PAGE}`;
  const data = await apiFetch(url, signal);
  return { crates: data.crates || [], total: (data.meta && data.meta.total) || 0 };
}

async function fetchCrateDetail(id, signal) {
  const data = await apiFetch(`${API_BASE}/${encodeURIComponent(id)}`, signal);
  const crate = data.crate || {};
  const versions = data.versions || [];
  const latest = versions.find((v) => v.num === crate.max_version) || versions[0] || {};
  return { crate, latest, keywords: data.keywords || [], categories: data.categories || [] };
}

// ---- rendering ---------------------------------------------------------

function crateToItem(c) {
  CRATE_MAP[c.id] = c;
  const version = c.newest_version || c.max_stable_version || c.max_version || '?';
  LAST_ITEMS[c.id] = c.id;
  return {
    id: c.id,
    title: `**${c.name}** \`${version}\``,
    subtitle: c.description || 'No description',
    icon: 'code',
    lines: 2,
    accessories: [{ text: `${formatNumber(c.downloads)} downloads`, icon: 'download' }],
    actions: itemActions(),
    preview: {
      markdown:
        `## ${c.name}\n\n${c.description || '_No description._'}\n\n` +
        '```\n' + `cargo add ${c.name}` + '\n```',
      metadata: previewMetadata(c),
    },
  };
}

function itemActions() {
  return [
    { id: 'default', title: 'View details', icon: 'document' },
    { id: 'open', title: 'Open on crates.io', icon: 'open' },
    { id: 'docs', title: 'Open docs.rs', icon: 'book' },
    { id: 'repo', title: 'Open repository', icon: 'link' },
    { id: 'copyadd', title: 'Copy `cargo add` command', icon: 'copy', shortcut: 'ctrl+shift+c' },
    { id: 'copyname', title: 'Copy crate name', icon: 'copy' },
  ];
}

function previewMetadata(c) {
  const rows = [
    { label: 'Version', text: c.newest_version || c.max_version || '—', icon: 'tag' },
    { label: 'Downloads', text: formatNumber(c.downloads), icon: 'download' },
  ];
  if (c.recent_downloads) {
    rows.push({ label: 'Recent (90d)', text: formatNumber(c.recent_downloads) });
  }
  rows.push({ separator: true });
  if (c.repository) rows.push({ label: 'Repository', text: c.repository.replace(/^https?:\/\//, ''), url: c.repository, icon: 'link' });
  if (c.documentation) rows.push({ label: 'Docs', text: 'docs.rs', url: c.documentation, icon: 'book' });
  if (c.homepage) rows.push({ label: 'Homepage', text: c.homepage.replace(/^https?:\/\//, ''), url: c.homepage, icon: 'globe' });
  return rows;
}

function renderRoot(rev) {
  send({
    type: 'render',
    rev,
    view: 'list',
    placeholder: 'crate <name> — search crates.io',
    empty: {
      icon: 'search',
      title: 'Search crates.io',
      hint: 'Try "tokio", "serde", "actix-web"…',
    },
    preview: { enabled: true },
    actions: FRAME_ACTIONS,
    items: [],
  });
  STATE.lastListFrame = null;
}

function renderList(rev, { loading = false } = {}) {
  const frame = {
    type: 'render',
    rev,
    view: 'list',
    placeholder: 'crate <name> — search crates.io',
    loading,
    loadingText: 'Searching crates.io…',
    emptyText: `No crates found for "${STATE.query}"`,
    preview: { enabled: true },
    actions: FRAME_ACTIONS,
    hasMore: STATE.crates.length < STATE.total,
    items: STATE.crates.map(crateToItem),
  };
  send(frame);
  if (!loading) STATE.lastListFrame = frame;
}

function renderDetail(rev, id, detail, error) {
  STATE.screen = 'detail';
  STATE.currentCrateId = id;

  if (error) {
    send({
      type: 'render',
      rev,
      view: 'detail',
      canGoBack: true,
      detail: { markdown: `# Error\n\nCouldn't load **${id}**:\n\n\`\`\`\n${error.message}\n\`\`\`` },
      actions: [{ id: 'open', title: 'Open on crates.io', icon: 'open' }],
    });
    return;
  }

  const { crate: c, latest } = detail;
  const md =
    `# ${c.name} \`${c.newest_version || c.max_version || ''}\`\n\n` +
    `${c.description || '_No description._'}\n\n` +
    '```\n' + `cargo add ${c.name}` + '\n```' +
    (latest.yanked ? '\n\n> ⚠️ Latest version is **yanked**.' : '');

  const metadata = [
    { label: 'Version', text: latest.num || c.max_version || '—', icon: 'tag' },
    { label: 'License', text: latest.license || 'unknown', icon: 'shield' },
    { label: 'Downloads', text: formatNumber(c.downloads), icon: 'download' },
    { label: 'Published', text: formatDate(latest.created_at || c.created_at), icon: 'calendar' },
    { separator: true },
  ];
  if (c.repository) metadata.push({ label: 'Repository', text: c.repository.replace(/^https?:\/\//, ''), url: c.repository, icon: 'link' });
  if (c.documentation || true) metadata.push({ label: 'Docs', text: 'docs.rs', url: c.documentation || `https://docs.rs/${c.name}`, icon: 'book' });
  if (c.homepage) metadata.push({ label: 'Homepage', text: c.homepage.replace(/^https?:\/\//, ''), url: c.homepage, icon: 'globe' });
  if (detail.keywords && detail.keywords.length) {
    metadata.push({ separator: true });
    metadata.push({ label: 'Keywords', text: detail.keywords.map((k) => k.id).join(', '), icon: 'label' });
  }

  send({
    type: 'render',
    rev,
    view: 'detail',
    canGoBack: true,
    detail: { markdown: md, metadata },
    actions: itemActions().filter((a) => a.id !== 'default'),
  });
}

// ---- search orchestration ----------------------------------------------

function runSearch(text, rev, { append = false } = {}) {
  const query = text.trim();
  STATE.screen = 'list';

  if (!query) {
    if (debounceTimer) clearTimeout(debounceTimer);
    if (abortController) abortController.abort();
    STATE.query = '';
    STATE.crates = [];
    STATE.page = 1;
    STATE.total = 0;
    renderRoot(rev);
    return;
  }

  if (!append && query !== STATE.query) {
    STATE.query = query;
    STATE.page = 1;
    STATE.crates = [];
    STATE.total = 0;
  }

  if (debounceTimer) clearTimeout(debounceTimer);
  const myGeneration = ++searchGeneration;

  const fire = () => {
    if (myGeneration !== searchGeneration) return; // superseded by newer input
    renderList(rev, { loading: true });
    if (abortController) abortController.abort();
    abortController = new AbortController();
    const page = append ? STATE.page + 1 : STATE.page;

    searchCrates(STATE.query, page, abortController.signal)
      .then(({ crates, total }) => {
        if (myGeneration !== searchGeneration) return;
        STATE.page = page;
        STATE.total = total;
        STATE.crates = append ? STATE.crates.concat(crates) : crates;
        renderList(rev, { loading: false });
      })
      .catch((err) => {
        if (err.name === 'AbortError' || myGeneration !== searchGeneration) return;
        log('search failed:', err);
        send({
          type: 'render',
          rev,
          view: 'list',
          emptyText: `Search failed: ${err.message}`,
          actions: FRAME_ACTIONS,
          items: [],
        });
      });
  };

  // Pagination (`loadMore`) should feel instant — no debounce there.
  if (append) fire();
  else debounceTimer = setTimeout(fire, DEBOUNCE_MS);
}

function openCrateDetail(id, rev) {
  const cached = CRATE_MAP[id];
  fetchCrateDetail(id)
    .then((detail) => renderDetail(rev, id, detail))
    .catch((err) => {
      log('detail fetch failed:', err);
      if (cached) {
        // Degrade gracefully using the search summary we already have.
        renderDetail(rev, id, {
          crate: cached,
          latest: { num: cached.newest_version || cached.max_version },
          keywords: [],
        });
      } else {
        renderDetail(rev, id, null, err);
      }
    });
}

// ---- action handling -----------------------------------------------------

function resolveCrateForAction(id) {
  if (STATE.screen === 'detail' && (id === STATE.currentCrateId || id === '')) {
    return CRATE_MAP[STATE.currentCrateId] || { id: STATE.currentCrateId, name: STATE.currentCrateId };
  }
  return CRATE_MAP[id] || { id, name: id };
}

function handleAction(msg) {
  const action = msg.action || 'default';
  const id = msg.id || '';

  if (action === 'frame:refresh') {
    if (STATE.screen === 'detail' && STATE.currentCrateId) {
      openCrateDetail(STATE.currentCrateId, 0);
    } else if (STATE.query) {
      STATE.crates = [];
      STATE.page = 1;
      runSearch(STATE.query, 0);
    } else {
      send({ type: 'command', command: 'toast', text: 'Nothing to refresh', style: 'info' });
    }
    return;
  }

  const crate = resolveCrateForAction(id);
  const name = crate.name || crate.id;

  switch (action) {
    case 'default':
      if (STATE.screen === 'list') openCrateDetail(id, 0);
      return;
    case 'open':
      send({ type: 'command', command: 'open', url: `https://crates.io/crates/${name}` });
      return;
    case 'docs':
      send({ type: 'command', command: 'open', url: crate.documentation || `https://docs.rs/${name}` });
      return;
    case 'repo':
      if (crate.repository) {
        send({ type: 'command', command: 'open', url: crate.repository });
      } else {
        send({ type: 'command', command: 'toast', text: `${name} has no repository listed`, style: 'info' });
      }
      return;
    case 'copyadd':
      send({ type: 'command', command: 'copy', text: `cargo add ${name}` });
      return;
    case 'copyname':
      send({ type: 'command', command: 'copy', text: name });
      return;
    default:
      // Unknown action — ignore rather than crash.
      return;
  }
}

// ---- stdin loop ----------------------------------------------------------

let buf = '';
process.stdin.setEncoding('utf8');

process.stdin.on('data', (chunk) => {
  buf += chunk;
  let idx;
  while ((idx = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, idx).trim();
    buf = buf.slice(idx + 1);
    if (!line) continue;

    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      continue; // malformed line — ignore
    }

    switch (msg.type) {
      case 'init': {
        const theme = msg.theme || {};
        log(`init: protocol=${msg.protocol} accent=${theme.accent} dark=${theme.dark}`);
        runSearch(msg.text != null ? msg.text : msg.query || '', msg.rev || 0);
        break;
      }
      case 'query':
        runSearch(msg.text != null ? msg.text : msg.query || '', msg.rev || 0);
        break;
      case 'action':
        handleAction(msg);
        break;
      case 'loadMore':
        if (STATE.query) runSearch(STATE.query, msg.rev || 0, { append: true });
        break;
      case 'back':
        STATE.screen = 'list';
        STATE.currentCrateId = null;
        if (STATE.lastListFrame) {
          send({ ...STATE.lastListFrame, rev: 0 });
        } else {
          renderRoot(0);
        }
        break;
      case 'tab': {
        const name = LAST_ITEMS[msg.id || ''];
        if (name) send({ type: 'command', command: 'setQuery', text: name });
        break;
      }
      case 'close':
        if (abortController) abortController.abort();
        process.exit(0);
        break;
      // 'select', 'submit', 'change', 'submitQuery', 'storage', 'clipboard'
      // are not used by this plugin.
      default:
        break;
    }
  }
});

process.stdin.on('end', () => process.exit(0));
