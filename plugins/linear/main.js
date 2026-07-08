#!/usr/bin/env node
/*
 * Linear plugin for the Tabame launcher.
 *
 * Runs as a long-lived child process speaking the launcher's newline-delimited
 * JSON protocol (see plugin_protocol.dart). Because the launcher exposes a
 * single query line, this plugin behaves as an internal state machine: a root
 * "command list" that drills into each command's own screen. Escape (in the
 * launcher) tears the whole plugin down; a "Back to commands" row / action
 * returns to the root.
 *
 * Runtime: Node 18+ (global fetch) or Bun. Set "runtime": "bun" in plugin.json
 * to use Bun instead — main.js is plain JS and needs no dependencies.
 *
 * Setup: create `config.json` next to this file:
 *   { "apiKey": "lin_api_xxx", "defaultTeamKey": "ENG" }
 * A personal API key can be created at Linear → Settings → API → Personal keys.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const ENDPOINT = 'https://api.linear.app/graphql';

// ── stdout protocol ─────────────────────────────────────────────────────────
function send(frame) {
  process.stdout.write(JSON.stringify(frame) + '\n');
}

// A render frame. `rev` echoes the query generation so Tabame drops stale
// frames; use 0 for unsolicited renders (action results, drill-ins).
function render(rev, view, opts = {}) {
  send({ type: 'render', rev, view, ...opts });
}

function loadingFrame(rev, text) {
  render(rev, 'list', { loading: true, items: [], emptyText: text || 'Loading…' });
}

function errorDetail(rev, message) {
  render(rev, 'detail', { detail: { markdown: message } });
}

// ── config / auth ───────────────────────────────────────────────────────────
function loadConfig() {
  const cfg = { apiKey: process.env.LINEAR_API_KEY || '', defaultTeamKey: '' };
  try {
    const file = path.join(process.cwd(), 'config.json');
    if (fs.existsSync(file)) {
      const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
      if (parsed.apiKey) cfg.apiKey = parsed.apiKey;
      if (parsed.defaultTeamKey) cfg.defaultTeamKey = parsed.defaultTeamKey;
    }
  } catch (_) {
    /* fall through to the setup screen */
  }
  return cfg;
}

const config = loadConfig();

async function gql(query, variables = {}) {
  const res = await fetch(ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: config.apiKey },
    body: JSON.stringify({ query, variables }),
  });
  const json = await res.json();
  if (json.errors) throw new Error(json.errors.map((e) => e.message).join('; '));
  return json.data;
}

// ── OS helpers (self-sufficient: the plugin owns clipboard / browser) ─────────
function openUrl(url) {
  if (!url) return;
  spawn('cmd', ['/c', 'start', '', url], { detached: true, stdio: 'ignore' }).unref();
}

function copyToClipboard(text) {
  const clip = spawn('cmd', ['/c', 'clip'], { stdio: ['pipe', 'ignore', 'ignore'] });
  clip.stdin.write(text == null ? '' : String(text));
  clip.stdin.end();
}

// ── cached viewer / teams ─────────────────────────────────────────────────────
let _viewer = null;
let _teams = null;

async function viewer() {
  if (!_viewer) {
    const data = await gql('{ viewer { id name email } }');
    _viewer = data.viewer;
  }
  return _viewer;
}

async function teams() {
  if (!_teams) {
    const data = await gql('{ teams(first: 100) { nodes { id key name } } }');
    _teams = data.teams.nodes;
  }
  return _teams;
}

async function defaultTeam() {
  const list = await teams();
  if (config.defaultTeamKey) {
    const match = list.find((t) => t.key.toLowerCase() === config.defaultTeamKey.toLowerCase());
    if (match) return match;
  }
  return list[0];
}

// ── issue rendering helpers ───────────────────────────────────────────────────
const ISSUE_FIELDS = `
  id identifier title url branchName priorityLabel updatedAt
  state { name type color }
  assignee { name }
  team { id key }
`;

function issuePreview(issue) {
  const lines = [
    `## ${issue.identifier} — ${issue.title || 'Untitled'}`,
    '',
    `- **State:** ${issue.state ? issue.state.name : '—'}`,
    `- **Assignee:** ${issue.assignee ? issue.assignee.name : 'Unassigned'}`,
    `- **Priority:** ${issue.priorityLabel || '—'}`,
    `- **Team:** ${issue.team ? issue.team.key : '—'}`,
    `- **Branch:** \`${issue.branchName || '—'}\``,
    '',
    `[Open in Linear](${issue.url})`,
  ];
  return lines.join('\n');
}

const ISSUE_ACTIONS = [
  { id: 'default', title: 'Open in Linear', icon: 'open' },
  { id: 'copy_url', title: 'Copy URL', icon: 'link' },
  { id: 'copy_branch', title: 'Copy Branch Name', icon: 'code' },
  { id: 'assign_me', title: 'Assign to Me', icon: 'person' },
  { id: 'mark_done', title: 'Mark as Done', icon: 'check' },
  { id: 'back', title: '◀ Back to commands', icon: 'menu' },
];

function issueItem(issue) {
  issueObjects[issue.id] = issue;
  return {
    id: `issue:${issue.id}`,
    title: `${issue.identifier}  ${issue.title || ''}`.trim(),
    subtitle: `${issue.state ? issue.state.name : ''} · ${issue.assignee ? issue.assignee.name : 'Unassigned'}`,
    icon: issueStateIcon(issue.state),
    accessories: issue.priorityLabel ? [{ text: issue.priorityLabel }] : [],
    actions: ISSUE_ACTIONS,
    preview: { markdown: issuePreview(issue) },
  };
}

function issueStateIcon(state) {
  if (!state) return 'tag';
  switch (state.type) {
    case 'completed':
      return 'check';
    case 'canceled':
      return 'close';
    case 'started':
      return 'bolt';
    case 'unstarted':
      return 'label';
    default:
      return 'tag';
  }
}

// A synthetic "back to commands" row shown at the top of sub-screens.
const BACK_ITEM = {
  id: 'nav:back',
  title: '◀ Back to commands',
  subtitle: 'Return to the Linear command list',
  icon: 'menu',
  accessories: [],
  actions: [],
  preview: null,
};

// ── command catalogue ─────────────────────────────────────────────────────────
const COMMANDS = [
  { id: 'create_issue', title: 'Create Issue', subtitle: 'Create and assign a new issue', icon: 'add' },
  { id: 'create_issue_self', title: 'Create Issue for Myself', subtitle: 'Create a new issue assigned to you', icon: 'person' },
  { id: 'search_issues', title: 'Search Issues', subtitle: 'Search issues across all projects', icon: 'search' },
  { id: 'my_issues', title: 'My Issues', subtitle: 'Issues assigned to you', icon: 'person' },
  { id: 'created_issues', title: 'Created Issues', subtitle: 'Issues you created', icon: 'document' },
  { id: 'active_cycle', title: 'Active Cycle', subtitle: 'Issues in the active cycle', icon: 'refresh' },
  { id: 'search_projects', title: 'Search Projects', subtitle: 'Explore your team projects', icon: 'grid' },
  { id: 'custom_views', title: 'Search Custom Views', subtitle: 'Browse custom views', icon: 'list' },
  { id: 'documents', title: 'Search Documents', subtitle: 'Explore team documents', icon: 'book' },
  { id: 'create_project', title: 'Create Project', subtitle: 'Create a project for your team', icon: 'add' },
  { id: 'notifications', title: 'Notifications', subtitle: 'Your latest notifications', icon: 'bell' },
  { id: 'unread_notifications', title: 'Unread Notifications', subtitle: 'Only unread notifications', icon: 'bell' },
  { id: 'add_comment', title: 'Quick Add Comment to Issue', subtitle: 'ID first, then the comment body', icon: 'message' },
  { id: 'favorites', title: 'Favorites', subtitle: 'Browse your Linear favorites', icon: 'star' },
];

// ── state machine ─────────────────────────────────────────────────────────────
const state = {
  screen: 'root', // 'root' | one of COMMANDS[].id
  itemsById: {}, // id -> rendered item, for action handling
  lastRev: 0,
};

// Raw Linear issue objects keyed by UUID, so issue actions (assign, done, copy
// branch) can read fields without re-querying.
const issueObjects = {};

function setItems(items) {
  state.itemsById = {};
  for (const it of items) state.itemsById[it.id] = it;
}

function contains(haystack, needle) {
  return (haystack || '').toLowerCase().includes((needle || '').toLowerCase());
}

// ── screens ────────────────────────────────────────────────────────────────────
function renderSetup(rev) {
  errorDetail(
    rev,
    [
      '# Linear — setup needed',
      '',
      'No API key found. Create a file named `config.json` next to the plugin\'s',
      '`main.js` with:',
      '',
      '```json',
      '{ "apiKey": "lin_api_xxx", "defaultTeamKey": "ENG" }',
      '```',
      '',
      'Generate a personal API key at **Linear → Settings → API → Personal API keys**,',
      'then re-open this plugin.',
    ].join('\n'),
  );
}

function renderRoot(rev, text) {
  const filtered = COMMANDS.filter(
    (c) => !text || contains(c.title, text) || contains(c.subtitle, text),
  );
  const items = filtered.map((c) => ({
    id: `cmd:${c.id}`,
    title: c.title,
    subtitle: c.subtitle,
    icon: c.icon,
    accessories: [],
    actions: [{ id: 'default', title: 'Open command', icon: 'open' }],
    preview: null,
  }));
  setItems(items);
  render(rev, 'list', { items, emptyText: 'No matching commands' });
}

async function renderIssueList(rev, text, fetcher, emptyText) {
  loadingFrame(rev, 'Loading issues…');
  const issues = await fetcher(text);
  const items = [BACK_ITEM, ...issues.map(issueItem)];
  setItems(items);
  render(rev, 'list', { items, preview: { enabled: true }, emptyText: emptyText || 'No issues' });
}

// Fetchers -------------------------------------------------------------------
async function fetchSearchIssues(text) {
  const term = (text || '').trim();
  const filter = term
    ? { or: [{ title: { containsIgnoreCase: term } }, { description: { containsIgnoreCase: term } }] }
    : {};
  const data = await gql(
    `query($filter: IssueFilter) { issues(first: 30, filter: $filter, orderBy: updatedAt) { nodes { ${ISSUE_FIELDS} } } }`,
    { filter },
  );
  return data.issues.nodes;
}

async function fetchMyIssues(text) {
  const data = await gql(
    `{ viewer { assignedIssues(first: 50, orderBy: updatedAt) { nodes { ${ISSUE_FIELDS} } } } }`,
  );
  return clientFilterIssues(data.viewer.assignedIssues.nodes, text);
}

async function fetchCreatedIssues(text) {
  const data = await gql(
    `{ viewer { createdIssues(first: 50, orderBy: updatedAt) { nodes { ${ISSUE_FIELDS} } } } }`,
  );
  return clientFilterIssues(data.viewer.createdIssues.nodes, text);
}

async function fetchActiveCycleIssues(text) {
  const data = await gql(
    `{ teams(first: 100) { nodes { key activeCycle { id name issues(first: 50) { nodes { ${ISSUE_FIELDS} } } } } } }`,
  );
  const issues = [];
  for (const team of data.teams.nodes) {
    if (team.activeCycle && team.activeCycle.issues) issues.push(...team.activeCycle.issues.nodes);
  }
  return clientFilterIssues(issues, text);
}

function clientFilterIssues(issues, text) {
  if (!text || !text.trim()) return issues;
  return issues.filter(
    (i) => contains(i.title, text) || contains(i.identifier, text) || (i.assignee && contains(i.assignee.name, text)),
  );
}

async function renderProjects(rev, text) {
  loadingFrame(rev, 'Loading projects…');
  const data = await gql(
    '{ projects(first: 100, orderBy: updatedAt) { nodes { id name description url state } } }',
  );
  const projects = data.projects.nodes.filter(
    (p) => !text || contains(p.name, text) || contains(p.description, text),
  );
  const items = [
    BACK_ITEM,
    ...projects.map((p) => ({
      id: `project:${p.id}`,
      title: p.name,
      subtitle: p.state || '',
      icon: 'grid',
      accessories: [],
      actions: [
        { id: 'default', title: 'Open in Linear', icon: 'open' },
        { id: 'copy_url', title: 'Copy URL', icon: 'link' },
        { id: 'back', title: '◀ Back to commands', icon: 'menu' },
      ],
      preview: { markdown: `## ${p.name}\n\n${p.description || '_No description_'}\n\n[Open](${p.url})` },
      _url: p.url,
    })),
  ];
  setItems(items);
  render(rev, 'list', { items, preview: { enabled: true }, emptyText: 'No projects' });
}

async function renderCustomViews(rev, text) {
  loadingFrame(rev, 'Loading custom views…');
  const data = await gql('{ customViews(first: 100) { nodes { id name description } } }');
  const views = data.customViews.nodes.filter(
    (v) => !text || contains(v.name, text) || contains(v.description, text),
  );
  const items = [
    BACK_ITEM,
    ...views.map((v) => ({
      id: `view:${v.id}`,
      title: v.name,
      subtitle: v.description || '',
      icon: 'list',
      accessories: [],
      actions: [{ id: 'back', title: '◀ Back to commands', icon: 'menu' }],
      preview: { markdown: `## ${v.name}\n\n${v.description || '_No description_'}` },
    })),
  ];
  setItems(items);
  render(rev, 'list', { items, preview: { enabled: true }, emptyText: 'No custom views' });
}

async function renderDocuments(rev, text) {
  loadingFrame(rev, 'Loading documents…');
  const data = await gql('{ documents(first: 100) { nodes { id title url } } }');
  const docs = data.documents.nodes.filter((d) => !text || contains(d.title, text));
  const items = [
    BACK_ITEM,
    ...docs.map((d) => ({
      id: `doc:${d.id}`,
      title: d.title,
      subtitle: 'Document',
      icon: 'book',
      accessories: [],
      actions: [
        { id: 'default', title: 'Open in Linear', icon: 'open' },
        { id: 'copy_url', title: 'Copy URL', icon: 'link' },
        { id: 'back', title: '◀ Back to commands', icon: 'menu' },
      ],
      preview: { markdown: `## ${d.title}\n\n[Open](${d.url})` },
      _url: d.url,
    })),
  ];
  setItems(items);
  render(rev, 'list', { items, preview: { enabled: true }, emptyText: 'No documents' });
}

async function renderNotifications(rev, text, unreadOnly) {
  loadingFrame(rev, 'Loading notifications…');
  const data = await gql(`{
    notifications(first: 50) {
      nodes {
        id type readAt createdAt
        ... on IssueNotification { issue { identifier title url } }
      }
    }
  }`);
  let nodes = data.notifications.nodes;
  if (unreadOnly) nodes = nodes.filter((n) => !n.readAt);
  if (text && text.trim()) {
    nodes = nodes.filter((n) => contains(n.type, text) || (n.issue && contains(n.issue.title, text)));
  }
  const items = [
    BACK_ITEM,
    ...nodes.map((n) => {
      const title = n.issue ? `${n.issue.identifier}  ${n.issue.title}` : n.type;
      return {
        id: `notif:${n.id}`,
        title,
        subtitle: `${n.type}${n.readAt ? '' : ' · unread'}`,
        icon: n.readAt ? 'bell' : 'bolt',
        accessories: n.readAt ? [] : [{ text: 'new' }],
        actions: n.issue
          ? [
              { id: 'default', title: 'Open Issue', icon: 'open' },
              { id: 'copy_url', title: 'Copy URL', icon: 'link' },
              { id: 'back', title: '◀ Back to commands', icon: 'menu' },
            ]
          : [{ id: 'back', title: '◀ Back to commands', icon: 'menu' }],
        preview: { markdown: `## ${title}\n\n- Type: ${n.type}\n- ${n.readAt ? 'Read' : 'Unread'}` },
        _url: n.issue ? n.issue.url : null,
      };
    }),
  ];
  setItems(items);
  render(rev, 'list', { items, preview: { enabled: true }, emptyText: 'No notifications' });
}

async function renderFavorites(rev, text) {
  loadingFrame(rev, 'Loading favorites…');
  const data = await gql(`{
    favorites(first: 100) {
      nodes {
        id type
        issue { identifier title url }
        project { name url }
        document { title url }
      }
    }
  }`);
  let nodes = data.favorites.nodes;
  const mapped = nodes.map((f) => {
    let title = f.type;
    let url = null;
    if (f.issue) {
      title = `${f.issue.identifier}  ${f.issue.title}`;
      url = f.issue.url;
    } else if (f.project) {
      title = f.project.name;
      url = f.project.url;
    } else if (f.document) {
      title = f.document.title;
      url = f.document.url;
    }
    return { id: `fav:${f.id}`, title, subtitle: f.type, url };
  });
  const filtered = mapped.filter((f) => !text || contains(f.title, text));
  const items = [
    BACK_ITEM,
    ...filtered.map((f) => ({
      id: f.id,
      title: f.title,
      subtitle: f.subtitle,
      icon: 'star',
      accessories: [],
      actions: [
        { id: 'default', title: 'Open in Linear', icon: 'open' },
        { id: 'copy_url', title: 'Copy URL', icon: 'link' },
        { id: 'back', title: '◀ Back to commands', icon: 'menu' },
      ],
      preview: { markdown: `## ${f.title}\n\n[Open](${f.url || ''})` },
      _url: f.url,
    })),
  ];
  setItems(items);
  render(rev, 'list', { items, preview: { enabled: true }, emptyText: 'No favorites' });
}

// Create screens -------------------------------------------------------------
async function renderCreateIssue(rev, text, assignSelf) {
  const title = (text || '').trim();
  const team = await defaultTeam();
  const who = assignSelf ? (await viewer()).name : 'Unassigned';
  const item = {
    id: 'create:issue',
    title: title ? `Create: ${title}` : 'Type a title, then press Enter',
    subtitle: `Team ${team ? team.key : '—'} · ${who}`,
    icon: 'add',
    accessories: [],
    actions: [
      { id: 'default', title: 'Create Issue', icon: 'check' },
      { id: 'back', title: '◀ Back to commands', icon: 'menu' },
    ],
    preview: {
      markdown: [
        '## New issue',
        '',
        `- **Title:** ${title || '_(empty)_'}`,
        `- **Team:** ${team ? `${team.name} (${team.key})` : '—'}`,
        `- **Assignee:** ${who}`,
        '',
        'Press **Enter** to create.',
      ].join('\n'),
    },
    _assignSelf: assignSelf,
  };
  setItems([BACK_ITEM, item]);
  render(rev, 'list', { items: [BACK_ITEM, item], preview: { enabled: true } });
}

async function renderCreateProject(rev, text) {
  const name = (text || '').trim();
  const team = await defaultTeam();
  const item = {
    id: 'create:project',
    title: name ? `Create project: ${name}` : 'Type a project name, then press Enter',
    subtitle: `Team ${team ? team.key : '—'}`,
    icon: 'add',
    accessories: [],
    actions: [
      { id: 'default', title: 'Create Project', icon: 'check' },
      { id: 'back', title: '◀ Back to commands', icon: 'menu' },
    ],
    preview: {
      markdown: `## New project\n\n- **Name:** ${name || '_(empty)_'}\n- **Team:** ${team ? team.key : '—'}\n\nPress **Enter** to create.`,
    },
  };
  setItems([BACK_ITEM, item]);
  render(rev, 'list', { items: [BACK_ITEM, item], preview: { enabled: true } });
}

function renderAddComment(rev, text) {
  const raw = (text || '').trim();
  const space = raw.indexOf(' ');
  const identifier = space === -1 ? raw : raw.slice(0, space);
  const body = space === -1 ? '' : raw.slice(space + 1).trim();
  const ready = identifier && body;
  const item = {
    id: 'comment:add',
    title: ready ? `Comment on ${identifier}` : 'Type: <ISSUE-ID> your comment body',
    subtitle: ready ? body : 'e.g.  ENG-123 looks good to me',
    icon: 'message',
    accessories: [],
    actions: [
      { id: 'default', title: 'Add Comment', icon: 'check' },
      { id: 'back', title: '◀ Back to commands', icon: 'menu' },
    ],
    preview: {
      markdown: `## Add comment\n\n- **Issue:** ${identifier || '_(none)_'}\n- **Body:** ${body || '_(empty)_'}\n\nPress **Enter** to post.`,
    },
    _identifier: identifier,
    _body: body,
  };
  setItems([BACK_ITEM, item]);
  render(rev, 'list', { items: [BACK_ITEM, item], preview: { enabled: true } });
}

// ── screen dispatch ────────────────────────────────────────────────────────────
async function renderScreen(rev, text) {
  if (!config.apiKey) return renderSetup(rev);
  try {
    switch (state.screen) {
      case 'root':
        return renderRoot(rev, text);
      case 'search_issues':
        return renderIssueList(rev, text, fetchSearchIssues, 'No matching issues');
      case 'my_issues':
        return renderIssueList(rev, text, fetchMyIssues, 'No issues assigned to you');
      case 'created_issues':
        return renderIssueList(rev, text, fetchCreatedIssues, 'You have not created issues');
      case 'active_cycle':
        return renderIssueList(rev, text, fetchActiveCycleIssues, 'No active-cycle issues');
      case 'search_projects':
        return renderProjects(rev, text);
      case 'custom_views':
        return renderCustomViews(rev, text);
      case 'documents':
        return renderDocuments(rev, text);
      case 'notifications':
        return renderNotifications(rev, text, false);
      case 'unread_notifications':
        return renderNotifications(rev, text, true);
      case 'favorites':
        return renderFavorites(rev, text);
      case 'create_issue':
        return renderCreateIssue(rev, text, false);
      case 'create_issue_self':
        return renderCreateIssue(rev, text, true);
      case 'create_project':
        return renderCreateProject(rev, text);
      case 'add_comment':
        return renderAddComment(rev, text);
      default:
        return renderRoot(rev, text);
    }
  } catch (err) {
    errorDetail(rev, `# Linear error\n\n\`\`\`\n${err.message}\n\`\`\``);
  }
}

// ── action handling ─────────────────────────────────────────────────────────────
async function completedStateId(teamId) {
  const data = await gql(
    'query($id: String!) { team(id: $id) { states(first: 50) { nodes { id type } } } }',
    { id: teamId },
  );
  const done = data.team.states.nodes.find((s) => s.type === 'completed');
  return done ? done.id : null;
}

async function handleAction(id, action) {
  // Root command drill-in.
  if (id.startsWith('cmd:')) {
    state.screen = id.slice(4);
    return renderScreen(0, '');
  }
  if (id === 'nav:back' || action === 'back') {
    state.screen = 'root';
    return renderScreen(0, '');
  }

  const item = state.itemsById[id];

  // Create / comment screens.
  if (id === 'create:issue') return doCreateIssue(item);
  if (id === 'create:project') return doCreateProject(item);
  if (id === 'comment:add') return doAddComment(item);

  if (!item) return;

  // Issue-specific actions.
  if (id.startsWith('issue:')) {
    return handleIssueAction(id.slice(6), action);
  }

  // Generic open / copy for projects, docs, notifications, favorites.
  if (action === 'copy_url') return copyToClipboard(item._url || '');
  return openUrl(item._url || '');
}

async function handleIssueAction(issueId, action) {
  const issue = issueObjects[issueId];
  const url = issue ? issue.url : null;
  switch (action) {
    case 'copy_url':
      return copyToClipboard(url || '');
    case 'copy_branch':
      return copyToClipboard(issue ? issue.branchName || '' : '');
    case 'assign_me': {
      const me = await viewer();
      await gql('mutation($id: String!, $a: String!) { issueUpdate(id: $id, input: { assigneeId: $a }) { success } }', {
        id: issueId,
        a: me.id,
      });
      return toast(`Assigned ${issue ? issue.identifier : ''} to you`);
    }
    case 'mark_done': {
      if (!issue || !issue.team) return;
      const stateId = await completedStateId(issue.team.id);
      if (!stateId) return toast('No completed state found for this team');
      await gql('mutation($id: String!, $s: String!) { issueUpdate(id: $id, input: { stateId: $s }) { success } }', {
        id: issueId,
        s: stateId,
      });
      return toast(`Marked ${issue.identifier} as done`);
    }
    default:
      return openUrl(url);
  }
}

function toast(message) {
  render(0, 'detail', {
    detail: { markdown: `# ✓ Done\n\n${message}\n\nKeep typing to return to the list.` },
  });
}

async function doCreateIssue(item) {
  const title = item && item.title ? item.title.replace(/^Create:\s*/, '') : '';
  if (!title || title.startsWith('Type a title')) return toast('Type a title first');
  const team = await defaultTeam();
  const input = { title, teamId: team.id };
  if (item._assignSelf) input.assigneeId = (await viewer()).id;
  const data = await gql(
    'mutation($input: IssueCreateInput!) { issueCreate(input: $input) { success issue { identifier url } } }',
    { input },
  );
  const created = data.issueCreate.issue;
  openUrl(created.url);
  toast(`Created ${created.identifier}`);
}

async function doCreateProject(item) {
  const name = item && item.title ? item.title.replace(/^Create project:\s*/, '') : '';
  if (!name || name.startsWith('Type a project')) return toast('Type a project name first');
  const team = await defaultTeam();
  const data = await gql(
    'mutation($input: ProjectCreateInput!) { projectCreate(input: $input) { success project { name url } } }',
    { input: { name, teamIds: [team.id] } },
  );
  const created = data.projectCreate.project;
  openUrl(created.url);
  toast(`Created project “${created.name}”`);
}

async function doAddComment(item) {
  const identifier = item._identifier;
  const body = item._body;
  if (!identifier || !body) return toast('Provide <ISSUE-ID> then a comment body');

  // Resolve the issue UUID from its human identifier (e.g. "ENG-123").
  const dash = identifier.lastIndexOf('-');
  if (dash === -1) return toast(`"${identifier}" is not a valid issue id`);
  const teamKey = identifier.slice(0, dash);
  const number = parseInt(identifier.slice(dash + 1), 10);
  if (!teamKey || Number.isNaN(number)) return toast(`"${identifier}" is not a valid issue id`);

  const data = await gql(
    'query($f: IssueFilter) { issues(first: 1, filter: $f) { nodes { id identifier } } }',
    { f: { team: { key: { eqIgnoreCase: teamKey } }, number: { eq: number } } },
  );
  const match = data.issues.nodes[0];
  if (!match) return toast(`Issue ${identifier} not found`);
  await gql('mutation($input: CommentCreateInput!) { commentCreate(input: $input) { success } }', {
    input: { issueId: match.id, body },
  });
  toast(`Commented on ${match.identifier}`);
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
      state.lastRev = msg.rev || 0;
      await renderScreen(msg.rev || 0, msg.text != null ? msg.text : msg.query || '');
      break;
    case 'action':
      try {
        await handleAction(msg.id, msg.action || 'default');
      } catch (err) {
        toast(`Error: ${err.message}`);
      }
      break;
    // 'select' needs no work — previews are provided per item.
  }
}
