#!/usr/bin/env node
/*
 * Can I Use plugin for the Tabame launcher.
 *
 * Runs as a long-lived child process speaking the launcher's newline-delimited
 * JSON protocol (see plugin_protocol.dart). Type the keyword `ciu` followed by a
 * feature name (e.g. `ciu grid`, `ciu :has`, `ciu webp`) to search the caniuse
 * feature database and see, per browser, whether the feature is supported.
 *
 * Runtime: Node 18+ (global fetch) or Bun. Set "runtime": "bun" in plugin.json
 * to use Bun instead — main.js is plain JS and needs no dependencies.
 *
 * Data: the full caniuse dataset (fulldata-json/data-2.0.json) is fetched once
 * from a CDN and cached to `caniuse-cache.json` next to this file, refreshed
 * weekly. No API key or config is required.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

// Mirrors of the caniuse dataset. jsdelivr first, raw GitHub as a fallback.
const DATA_URLS = [
  'https://cdn.jsdelivr.net/gh/Fyrd/caniuse@main/fulldata-json/data-2.0.json',
  'https://raw.githubusercontent.com/Fyrd/caniuse/main/fulldata-json/data-2.0.json',
];
const CACHE_FILE = path.join(process.cwd(), 'caniuse-cache.json');
const CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000; // refresh weekly
const FEATURE_URL = (id) => `https://caniuse.com/${id}`;

// Browsers shown in the compatibility preview, grouped and in display order.
const DESKTOP = ['chrome', 'edge', 'safari', 'firefox', 'opera'];
const MOBILE = ['ios_saf', 'and_chr', 'and_ff', 'samsung', 'op_mob'];

// ── stdout protocol ─────────────────────────────────────────────────────────
function send(frame) {
  process.stdout.write(JSON.stringify(frame) + '\n');
}

// A render frame. `rev` echoes the query generation so Tabame drops stale
// frames; use 0 for unsolicited renders (drill-ins, action results).
function render(rev, view, opts = {}) {
  send({ type: 'render', rev, view, ...opts });
}

function loadingFrame(rev, text) {
  render(rev, 'list', { loading: true, items: [], emptyText: text || 'Loading…' });
}

function detailFrame(rev, markdown) {
  render(rev, 'detail', { detail: { markdown } });
}

// ── OS helpers (the plugin owns clipboard / browser, like the Linear plugin) ──
function openUrl(url) {
  if (!url) return;
  spawn('cmd', ['/c', 'start', '', url], { detached: true, stdio: 'ignore' }).unref();
}

function copyToClipboard(text) {
  const clip = spawn('cmd', ['/c', 'clip'], { stdio: ['pipe', 'ignore', 'ignore'] });
  clip.stdin.write(text == null ? '' : String(text));
  clip.stdin.end();
}

// ── dataset loading (disk cache + CDN, fetched at most once per process) ──────
let _dataset = null; // parsed { agents, data }
let _loading = null; // in-flight promise, so concurrent queries share one fetch

async function fetchDataset() {
  let lastErr = null;
  for (const url of DATA_URLS) {
    try {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 25000);
      const res = await fetch(url, { signal: ctrl.signal });
      clearTimeout(timer);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const text = await res.text();
      const parsed = JSON.parse(text);
      if (!parsed || !parsed.data || !parsed.agents) throw new Error('unexpected shape');
      try {
        fs.writeFileSync(CACHE_FILE, text);
      } catch (_) {
        /* cache is best-effort */
      }
      return parsed;
    } catch (err) {
      lastErr = err;
    }
  }
  throw lastErr || new Error('could not download the caniuse dataset');
}

function readCache(allowStale) {
  try {
    const stat = fs.statSync(CACHE_FILE);
    const fresh = Date.now() - stat.mtimeMs < CACHE_TTL_MS;
    if (fresh || allowStale) {
      const parsed = JSON.parse(fs.readFileSync(CACHE_FILE, 'utf8'));
      if (parsed && parsed.data && parsed.agents) return parsed;
    }
  } catch (_) {
    /* no cache yet */
  }
  return null;
}

function ensureDataset() {
  if (_dataset) return Promise.resolve(_dataset);
  if (_loading) return _loading;
  _loading = (async () => {
    const fresh = readCache(false);
    if (fresh) {
      _dataset = fresh;
      return _dataset;
    }
    try {
      _dataset = await fetchDataset();
    } catch (err) {
      // Network failed — fall back to any cached copy, even an expired one.
      const stale = readCache(true);
      if (stale) {
        _dataset = stale;
      } else {
        _loading = null; // let a later query retry the download
        throw err;
      }
    }
    return _dataset;
  })();
  return _loading;
}

// ── support interpretation ────────────────────────────────────────────────────
// caniuse support codes: "y" full, "a" partial, "n" none, "p" polyfill only,
// "u" unknown; combined with "x" (needs prefix) and "d" (disabled by default)
// and note refs like "#1". We only care about the leading letter + the flags.
function interpret(code) {
  if (!code || typeof code !== 'string') return { level: 'u', prefix: false, flag: false };
  const tokens = code.trim().split(/\s+/);
  const main = tokens[0][0];
  const prefix = tokens.includes('x');
  const flag = tokens.includes('d');
  let level = 'u';
  if (main === 'y') level = 'y';
  else if (main === 'a') level = 'a';
  else if (main === 'n' || main === 'p') level = 'n';
  return { level, prefix, flag };
}

function symbol(info) {
  switch (info.level) {
    case 'y':
      return info.prefix || info.flag ? '🟡' : '✅';
    case 'a':
      return '🟠';
    case 'n':
      return '❌';
    default:
      return '❔';
  }
}

// The support of a browser's current stable release for a feature.
function currentSupport(feature, agents, agentId) {
  const agent = agents[agentId];
  if (!agent || !agent.version_list) return { info: interpret('u'), version: '' };
  const current = agent.version_list.find((v) => v.era === 0);
  if (!current) return { info: interpret('u'), version: '' };
  const stats = feature.stats && feature.stats[agentId];
  const code = stats ? stats[current.version] : undefined;
  return { info: interpret(code), version: current.version };
}

function itemIcon(percentY) {
  if (percentY >= 90) return 'check';
  if (percentY >= 50) return 'warning';
  return 'close';
}

// ── search ─────────────────────────────────────────────────────────────────────
function contains(haystack, needle) {
  return (haystack || '').toLowerCase().includes(needle);
}

function scoreFeature(id, feature, term) {
  const title = (feature.title || '').toLowerCase();
  const keywords = (feature.keywords || '').toLowerCase();
  if (id === term || title === term) return 100;
  if (title.startsWith(term)) return 80;
  if (keywords.split(',').some((k) => k.trim() === term)) return 70;
  if (id.includes(term)) return 55;
  if (contains(title, term)) return 45;
  if (contains(keywords, term)) return 30;
  if (contains(feature.description, term)) return 15;
  return 0;
}

function searchFeatures(dataset, rawTerm) {
  const term = rawTerm.trim().toLowerCase();
  const results = [];
  for (const id of Object.keys(dataset.data)) {
    const feature = dataset.data[id];
    const score = term ? scoreFeature(id, feature, term) : 0;
    if (term && score === 0) continue;
    results.push({ id, feature, score });
  }
  results.sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score;
    const ua = parseFloat(a.feature.usage_perc_y) || 0;
    const ub = parseFloat(b.feature.usage_perc_y) || 0;
    if (ub !== ua) return ub - ua;
    return (a.feature.title || '').localeCompare(b.feature.title || '');
  });
  return results.slice(0, 40);
}

// ── rendering ───────────────────────────────────────────────────────────────────
function supportRow(feature, agents, ids) {
  const cells = ids
    .filter((id) => agents[id])
    .map((id) => {
      const s = currentSupport(feature, agents, id);
      const name = agents[id].browser || id;
      return `${symbol(s.info)} ${name} ${s.version}`.trim();
    });
  return cells.join('  ·  ');
}

function featurePreview(id, feature, agents) {
  const y = Math.round(parseFloat(feature.usage_perc_y) || 0);
  const a = Math.round(parseFloat(feature.usage_perc_a) || 0);
  const lines = [
    `## ${feature.title || id}`,
    '',
    feature.description ? `${stripHtml(feature.description)}\n` : '',
    `**Global support:** ${y}% full${a ? ` · +${a}% partial` : ''}  ·  **Status:** ${statusLabel(feature.status)}`,
    '',
    '**Desktop**',
    '',
    supportRow(feature, agents, DESKTOP),
    '',
    '**Mobile**',
    '',
    supportRow(feature, agents, MOBILE),
    '',
    '`✅ full`  `🟡 prefixed / behind a flag`  `🟠 partial`  `❌ none`  `❔ unknown`',
    '',
    notesSection(feature),
    `[Open on caniuse.com](${FEATURE_URL(id)})`,
  ];
  return lines.filter((l) => l !== null).join('\n');
}

function notesSection(feature) {
  if (!feature.notes || !feature.notes.trim()) return '';
  return `> ${stripHtml(feature.notes).replace(/\n+/g, ' ').trim()}\n`;
}

function statusLabel(status) {
  const map = {
    ls: 'WHATWG Living Standard',
    rec: 'W3C Recommendation',
    pr: 'Proposed Recommendation',
    cr: 'Candidate Recommendation',
    wd: 'Working Draft',
    other: 'Non-W3C',
    unoff: 'Unofficial / Note',
  };
  return map[status] || status || '—';
}

function stripHtml(s) {
  return String(s || '')
    .replace(/<[^>]*>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

// Rendered items are stashed so actions (open / copy) can read the URL/title.
const itemsById = {};

function featureItem(id, feature, agents) {
  const y = Math.round(parseFloat(feature.usage_perc_y) || 0);
  const a = Math.round(parseFloat(feature.usage_perc_a) || 0);
  const item = {
    id: `feat:${id}`,
    title: feature.title || id,
    subtitle: supportRow(feature, agents, DESKTOP),
    icon: itemIcon(y),
    accessories: [{ text: a ? `${y}%+${a}` : `${y}%` }],
    actions: [
      { id: 'default', title: 'Open on caniuse.com', icon: 'open' },
      { id: 'copy_url', title: 'Copy URL', icon: 'link' },
      { id: 'copy_title', title: 'Copy Feature Name', icon: 'copy' },
    ],
    preview: { markdown: featurePreview(id, feature, agents) },
    _url: FEATURE_URL(id),
    _title: feature.title || id,
  };
  itemsById[item.id] = item;
  return item;
}

const HELP_MARKDOWN = [
  '# Can I Use',
  '',
  'Type a web-platform feature after the keyword to check browser support:',
  '',
  '- `ciu grid` — CSS Grid Layout',
  '- `ciu :has` — the `:has()` selector',
  '- `ciu webp` — the WebP image format',
  '- `ciu container queries`',
  '- `ciu dialog`',
  '',
  'Each result shows the global support percentage and per-browser status.',
  'Press **Enter** to open the feature on caniuse.com, or **Ctrl+K** to copy its',
  'URL or name.',
].join('\n');

async function renderQuery(rev, text) {
  const term = (text || '').trim();
  if (!term) {
    detailFrame(rev, HELP_MARKDOWN);
    return;
  }
  loadingFrame(rev, 'Loading caniuse data…');
  let dataset;
  try {
    dataset = await ensureDataset();
  } catch (err) {
    detailFrame(
      rev,
      `# Can I Use — data unavailable\n\nCould not download the caniuse dataset.\n\n\`\`\`\n${err.message}\n\`\`\`\n\nCheck your internet connection and try again.`,
    );
    return;
  }
  const results = searchFeatures(dataset, term);
  const items = results.map((r) => featureItem(r.id, r.feature, dataset.agents));
  render(rev, 'list', {
    items,
    preview: { enabled: true },
    emptyText: `No caniuse feature matches “${term}”`,
  });
}

// ── action handling ───────────────────────────────────────────────────────────
function handleAction(id, action) {
  const item = itemsById[id];
  if (!item) return;
  switch (action) {
    case 'copy_url':
      return copyToClipboard(item._url);
    case 'copy_title':
      return copyToClipboard(item._title);
    default:
      return openUrl(item._url);
  }
}

// ── stdin loop ────────────────────────────────────────────────────────────────
let buffer = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  buffer += chunk;
  let idx;
  while ((idx = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, idx).trim();
    buffer = buffer.slice(idx + 1);
    if (line) handleLine(line);
  }
});
process.stdin.on('end', () => process.exit(0));

async function handleLine(line) {
  let msg;
  try {
    msg = JSON.parse(line);
  } catch (_) {
    return;
  }
  switch (msg.type) {
    case 'close':
      process.exit(0);
      break;
    case 'init':
    case 'query':
      await renderQuery(msg.rev || 0, msg.text != null ? msg.text : msg.query || '');
      break;
    case 'action':
      handleAction(msg.id, msg.action || 'default');
      break;
    // 'select' needs no work — previews are provided per item.
  }
}
