#!/usr/bin/env node
'use strict';

// Microsoft 365 agenda for Tabame's newline-delimited JSON plugin protocol.
// Requires Node 18+ and a user-owned Microsoft Entra public-client registration.

const crypto = require('node:crypto');
const readline = require('node:readline');

const GRAPH = 'https://graph.microsoft.com/v1.0';
const LOGIN = 'https://login.microsoftonline.com';
const SCOPES = 'offline_access Calendars.Read Mail.Read';
const SETTINGS_KEY = 'settings';
const TOKEN_KEY = 'tokens';
const EVENTS_TTL_MS = 60_000;
const MAIL_TTL_MS = 45_000;
const MAX_EVENT_PAGES = 3;

const state = {
  settings: null,
  tokens: null,
  screen: 'loading',
  query: '',
  rev: 0,
  generation: 0,
  loading: false,
  loadErrors: [],
  events: [],
  eventsAt: 0,
  eventsPromise: null,
  mailCache: new Map(),
  items: new Map(),
  detailId: null,
  refreshPromise: null,
  deviceFlow: null,
  detached: false,
  closed: false,
  bootstrapped: false,
  storageRequests: new Map(),
};

function send(payload) {
  if (!state.closed) process.stdout.write(`${JSON.stringify(payload)}\n`);
}

function render(rev, view, options = {}) {
  send({ type: 'render', rev, view, ...options });
}

function command(name, options = {}) {
  send({ type: 'command', command: name, ...options });
}

function toast(text, style = 'info') {
  command('toast', { text, style });
}

function storageGet(key, secret = false) {
  const requestId = crypto.randomUUID();
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      state.storageRequests.delete(requestId);
      reject(new Error('Tabame storage did not respond'));
    }, 8000);
    state.storageRequests.set(requestId, { resolve, timer });
    command('storage', { op: 'get', key, secret, requestId });
  });
}

function storageSet(key, value, secret = false) {
  command('storage', { op: 'set', key, value, secret });
}

function storageDelete(key, secret = false) {
  command('storage', { op: 'delete', key, secret });
}

function handleStorage(message) {
  const pending = state.storageRequests.get(message.requestId);
  if (!pending) return;
  clearTimeout(pending.timer);
  state.storageRequests.delete(message.requestId);
  pending.resolve(message.value ?? null);
}

function parseStoredJson(raw) {
  if (typeof raw !== 'string' || !raw) return null;
  try {
    return JSON.parse(raw);
  } catch (_) {
    return null;
  }
}

function validateSettings(clientId, tenant) {
  const id = String(clientId || '').trim();
  const directory = String(tenant || 'common').trim();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) {
    throw new Error('Enter the Application (client) ID as a UUID.');
  }
  if (!/^(common|organizations|consumers|[0-9a-z][0-9a-z.-]{0,127})$/i.test(directory) || directory.includes('..')) {
    throw new Error('Use common, organizations, consumers, or your tenant ID.');
  }
  return { clientId: id, tenant: directory };
}

function authUrl(path) {
  return `${LOGIN}/${encodeURIComponent(state.settings.tenant)}/oauth2/v2.0/${path}`;
}

async function requestJson(url, options = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15_000);
  try {
    const response = await fetch(url, { ...options, signal: controller.signal });
    let body;
    try {
      body = await response.json();
    } catch (_) {
      body = {};
    }
    return { response, body };
  } finally {
    clearTimeout(timer);
  }
}

function serviceError(body, response) {
  const detail = body?.error?.message || body?.error_description || body?.error || response.statusText;
  return new Error(`${response.status}: ${String(detail).slice(0, 260)}`);
}

async function tokenRequest(parameters) {
  const { response, body } = await requestJson(authUrl('token'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: state.settings.clientId, ...parameters }),
  });
  if (!response.ok) throw serviceError(body, response);
  return body;
}

function saveTokens(body, previousRefreshToken = '') {
  if (!body.access_token) throw new Error('Microsoft did not return an access token.');
  state.tokens = {
    accessToken: body.access_token,
    refreshToken: body.refresh_token || previousRefreshToken,
    expiresAt: Date.now() + Math.max(60, Number(body.expires_in) || 3600) * 1000,
    clientId: state.settings.clientId,
    tenant: state.settings.tenant,
  };
  storageSet(TOKEN_KEY, JSON.stringify(state.tokens), true);
}

async function accessToken(forceRefresh = false) {
  if (!state.tokens) throw new Error('Connect your Microsoft account first.');
  if (!forceRefresh && state.tokens.accessToken && state.tokens.expiresAt > Date.now() + 90_000) {
    return state.tokens.accessToken;
  }
  if (!state.tokens.refreshToken) throw new Error('Your Microsoft session has expired. Connect again.');
  if (!state.refreshPromise) {
    state.refreshPromise = (async () => {
      const oldRefresh = state.tokens.refreshToken;
      try {
        const body = await tokenRequest({ grant_type: 'refresh_token', refresh_token: oldRefresh, scope: SCOPES });
        saveTokens(body, oldRefresh);
        return state.tokens.accessToken;
      } catch (error) {
        if (/invalid_grant|interaction_required/i.test(error.message)) {
          state.tokens = null;
          storageDelete(TOKEN_KEY, true);
          state.screen = 'connect';
        }
        throw error;
      }
    })().finally(() => { state.refreshPromise = null; });
  }
  return state.refreshPromise;
}

async function graphGet(path, retry = true) {
  const token = await accessToken();
  const url = path.startsWith('https://') ? path : `${GRAPH}${path}`;
  if (!url.startsWith(`${GRAPH}/`)) throw new Error('Unexpected Microsoft Graph URL.');
  const { response, body } = await requestJson(url, {
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
  });
  if (response.status === 401 && retry) {
    await accessToken(true);
    return graphGet(path, false);
  }
  if (!response.ok) throw serviceError(body, response);
  return body;
}

function graphDateTime(value) {
  if (!value?.dateTime) return null;
  let input = String(value.dateTime).replace(/(\.\d{3})\d+/, '$1');
  if (!/(Z|[+-]\d\d:\d\d)$/i.test(input)) input += 'Z';
  const parsed = new Date(input);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function safeUrl(value) {
  try {
    const url = new URL(String(value || ''));
    return url.protocol === 'https:' ? url.href : '';
  } catch (_) {
    return '';
  }
}

function eventJoinUrl(event) {
  return safeUrl(event.onlineMeeting?.joinUrl || event.onlineMeetingUrl);
}

async function fetchEvents(force = false) {
  if (!force && Date.now() - state.eventsAt < EVENTS_TTL_MS) return state.events;
  if (state.eventsPromise) return state.eventsPromise;
  state.eventsPromise = (async () => {
    const start = new Date(Date.now() - 2 * 60 * 60 * 1000);
    const end = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    const params = new URLSearchParams({
      startDateTime: start.toISOString(),
      endDateTime: end.toISOString(),
      '$top': '100',
      '$select': 'id,subject,start,end,isAllDay,location,organizer,onlineMeeting,onlineMeetingUrl,webLink,isCancelled',
    });
    let next = `/me/calendarView?${params}`;
    const events = [];
    for (let page = 0; next && page < MAX_EVENT_PAGES; page += 1) {
      const data = await graphGet(next);
      events.push(...(Array.isArray(data.value) ? data.value : []));
      next = data['@odata.nextLink'] || null;
    }
    state.events = events
      .filter((event) => !event.isCancelled && graphDateTime(event.end)?.getTime() > Date.now())
      .sort((a, b) => (graphDateTime(a.start)?.getTime() || 0) - (graphDateTime(b.start)?.getTime() || 0));
    state.eventsAt = Date.now();
    return state.events;
  })().finally(() => { state.eventsPromise = null; });
  return state.eventsPromise;
}

async function fetchMail(query, force = false) {
  const key = query.toLowerCase();
  const cached = state.mailCache.get(key);
  if (!force && cached && Date.now() - cached.at < MAIL_TTL_MS) return cached.items;
  if (cached?.promise) return cached.promise;
  const params = new URLSearchParams({
    '$top': query ? '20' : '8',
    '$select': 'id,subject,from,receivedDateTime,bodyPreview,webLink,isRead,importance',
  });
  let path;
  if (query) {
    params.set('$search', `"${query.replace(/"/g, ' ').slice(0, 120)}"`);
    path = `/me/messages?${params}`;
  } else {
    params.set('$orderby', 'receivedDateTime desc');
    path = `/me/mailFolders/inbox/messages?${params}`;
  }
  const promise = graphGet(path).then((data) => {
    const items = Array.isArray(data.value) ? data.value : [];
    state.mailCache.set(key, { items, at: Date.now() });
    return items;
  }).catch((error) => {
    state.mailCache.delete(key);
    throw error;
  });
  state.mailCache.set(key, { items: cached?.items || [], at: 0, promise });
  return promise;
}

function escapeMarkdown(value) {
  return String(value || '').replace(/[\\`*_{}\[\]()#+.!>|~-]/g, '\\$&').replace(/[\r\n]+/g, ' ');
}

function formatDate(value, options) {
  return value ? new Intl.DateTimeFormat(undefined, options).format(value) : 'Unknown time';
}

function eventSubtitle(event) {
  const start = graphDateTime(event.start);
  const date = formatDate(start, { weekday: 'short', month: 'short', day: 'numeric' });
  const time = event.isAllDay ? 'All day' : formatDate(start, { hour: 'numeric', minute: '2-digit' });
  const location = event.location?.displayName;
  return [date, time, location].filter(Boolean).join(' · ');
}

function eventPreview(event) {
  const host = event.organizer?.emailAddress?.name || event.organizer?.emailAddress?.address;
  const lines = [
    `## ${escapeMarkdown(event.subject || '(No title)')}`,
    '',
    `**When:** ${escapeMarkdown(eventSubtitle(event))}`,
  ];
  if (host) lines.push(`**Organizer:** ${escapeMarkdown(host)}`);
  if (event.location?.displayName) lines.push(`**Location:** ${escapeMarkdown(event.location.displayName)}`);
  if (eventJoinUrl(event)) lines.push('', 'Press Enter to join this meeting.');
  return lines.join('\n');
}

function mailSender(mail) {
  return mail.from?.emailAddress?.name || mail.from?.emailAddress?.address || 'Unknown sender';
}

function mailSubtitle(mail) {
  const received = mail.receivedDateTime ? new Date(mail.receivedDateTime) : null;
  const date = received && !Number.isNaN(received.getTime())
    ? formatDate(received, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : '';
  return [mailSender(mail), date, mail.isRead ? '' : 'Unread'].filter(Boolean).join(' · ');
}

function mailPreview(mail) {
  return [
    `## ${escapeMarkdown(mail.subject || '(No subject)')}`,
    '',
    `**From:** ${escapeMarkdown(mailSender(mail))}`,
    `**Received:** ${escapeMarkdown(mailSubtitle(mail))}`,
    '',
    escapeMarkdown(mail.bodyPreview || ''),
  ].join('\n');
}

function eventItem(event, section) {
  const join = eventJoinUrl(event);
  const outlook = safeUrl(event.webLink);
  const actions = [{ id: 'details', title: 'View details', icon: 'info' }];
  if (join) actions.unshift({ id: 'join', title: 'Join meeting', icon: 'video' });
  if (outlook) actions.push({ id: 'open', title: 'Open in Outlook', icon: 'open' });
  if (join || outlook) actions.push({ id: 'copy_link', title: 'Copy link', icon: 'link' });
  actions.push({ id: 'copy_details', title: 'Copy event details', icon: 'copy' });
  const item = {
    id: `event:${event.id}`,
    title: event.subject || '(No title)',
    subtitle: eventSubtitle(event),
    icon: join ? 'video' : 'calendar',
    section,
    actions,
    preview: { markdown: eventPreview(event) },
  };
  state.items.set(item.id, { kind: 'event', data: event });
  return item;
}

function mailItem(mail, section) {
  const item = {
    id: `mail:${mail.id}`,
    title: mail.subject || '(No subject)',
    subtitle: mailSubtitle(mail),
    icon: mail.isRead ? 'mail' : 'email',
    section,
    actions: [
      { id: 'open', title: 'Open in Outlook', icon: 'open' },
      { id: 'details', title: 'View preview', icon: 'info' },
      { id: 'copy_sender', title: 'Copy sender address', icon: 'copy' },
      { id: 'copy_link', title: 'Copy link', icon: 'link' },
    ],
    preview: { markdown: mailPreview(mail) },
  };
  state.items.set(item.id, { kind: 'mail', data: mail });
  return item;
}

function frameActions() {
  return [
    { id: 'refresh', title: 'Refresh agenda and mail', icon: 'refresh' },
    { id: 'settings', title: 'Account settings', icon: 'settings' },
    { id: 'signout', title: 'Sign out', icon: 'lock', destructive: true,
      confirm: { title: 'Sign out of Microsoft 365?', message: 'You will need to connect again to see your agenda and mail.', confirmLabel: 'Sign out' } },
  ];
}

function renderResults(rev = 0) {
  if (state.screen !== 'results' || state.detached) return;
  const query = state.query.trim().toLowerCase();
  const filteredEvents = query
    ? state.events.filter((event) => [event.subject, event.location?.displayName,
      event.organizer?.emailAddress?.name, event.organizer?.emailAddress?.address]
      .some((value) => String(value || '').toLowerCase().includes(query)))
    : state.events;
  const mail = state.mailCache.get(query)?.items || [];
  state.items.clear();
  const items = [
    ...filteredEvents.slice(0, query ? 30 : 20).map((event) => eventItem(event, query ? 'Events' : 'Upcoming events')),
    ...mail.map((message) => mailItem(message, query ? 'Mail results' : 'Recent inbox')),
  ];
  const banners = state.loadErrors.map((message, index) => ({
    id: `error-${index}`, style: 'warning', title: 'Could not load some results', message,
  }));
  if (state.loading && items.length > 0) banners.push({ id: 'loading', style: 'info', message: 'Updating results…' });
  render(rev, 'list', {
    page: { id: 'm365-agenda', title: 'Microsoft 365 Agenda', preserveState: true },
    placeholder: 'Search upcoming events and mail…',
    items,
    preview: { enabled: true, resizable: true, initialWidth: 370 },
    loading: state.loading && items.length === 0,
    loadingText: 'Loading Outlook agenda and mail…',
    empty: { icon: 'calendar', title: query ? 'No matches' : 'Nothing upcoming',
      hint: query ? 'Try a different search.' : 'Your next 30 days and recent inbox are clear.' },
    banners,
    actions: frameActions(),
  });
}

function renderSettings(rev = 0, error = '') {
  state.screen = 'settings';
  render(rev, 'form', {
    page: { id: 'm365-settings', title: 'Microsoft 365 setup' },
    canGoBack: Boolean(state.settings),
    form: {
      title: 'Connect Microsoft 365',
      error,
      submitLabel: 'Save settings',
      sections: [{ id: 'account', title: 'Your app registration',
        description: 'Create a Microsoft Entra public-client app with Calendars.Read and Mail.Read delegated permissions. See the plugin README for the steps.' }],
      fields: [
        { id: 'clientId', type: 'text', label: 'Application (client) ID', required: true,
          value: state.settings?.clientId || '', section: 'account' },
        { id: 'tenant', type: 'text', label: 'Tenant', required: true,
          value: state.settings?.tenant || 'common', section: 'account',
          description: 'Use common for both work and personal accounts, or your organization tenant ID.' },
      ],
    },
    actions: [{ id: 'registration', title: 'Open Microsoft app registrations', icon: 'open' }],
  });
}

function renderConnect(rev = 0, error = '') {
  state.screen = 'connect';
  render(rev, 'list', {
    page: { id: 'm365-connect', title: 'Connect Microsoft 365' },
    items: [{ id: 'connect', title: 'Sign in with Microsoft',
      subtitle: 'Read your upcoming Outlook events and mail', icon: 'person',
      actions: [{ id: 'default', title: 'Connect account', icon: 'open' }] }],
    banners: error ? [{ id: 'connect-error', style: 'error', title: 'Connection needed', message: error }] : [],
    actions: [{ id: 'settings', title: 'Account settings', icon: 'settings' }],
  });
}

function renderDeviceCode(rev = 0) {
  if (!state.deviceFlow || state.detached) return;
  state.screen = 'connecting';
  const flow = state.deviceFlow;
  render(rev, 'detail', {
    page: { id: 'm365-signin', title: 'Microsoft sign-in' },
    detail: { markdown: [
      '# Finish Microsoft sign-in', '',
      'A browser page should be open. Enter this code there:', '',
      `## ${escapeMarkdown(flow.userCode)}`, '',
      'Tabame will load your agenda after you approve the requested calendar and mail access.',
    ].join('\n') },
    actions: [
      { id: 'open_signin', title: 'Open sign-in page', icon: 'open' },
      { id: 'copy_code', title: 'Copy sign-in code', icon: 'copy' },
      { id: 'cancel_signin', title: 'Cancel sign-in', icon: 'close' },
    ],
  });
}

function renderDetail(id) {
  const entry = state.items.get(id);
  if (!entry) return;
  state.screen = 'detail';
  state.detailId = id;
  const isEvent = entry.kind === 'event';
  const data = entry.data;
  render(0, 'detail', {
    page: { id: 'm365-detail', title: isEvent ? 'Event details' : 'Mail preview' },
    canGoBack: true,
    detail: { markdown: isEvent ? eventPreview(data) : mailPreview(data) },
    actions: [
      ...(isEvent && eventJoinUrl(data) ? [{ id: 'join', title: 'Join meeting', icon: 'video' }] : []),
      { id: 'open', title: 'Open in Outlook', icon: 'open' },
      { id: 'back', title: 'Back to results', icon: 'reply' },
    ],
  });
}

async function loadResults(force = false) {
  const generation = ++state.generation;
  state.loading = true;
  state.loadErrors = [];
  renderResults(state.rev);
  const query = state.query.trim();
  const results = await Promise.allSettled([fetchEvents(force), fetchMail(query, force)]);
  if (state.closed || state.detached || generation !== state.generation) return;
  state.loading = false;
  state.loadErrors = results.filter((result) => result.status === 'rejected')
    .map((result) => result.reason?.message || 'Microsoft Graph request failed.');
  if (state.screen === 'connect') {
    renderConnect(0, state.loadErrors[0] || 'Connect your account again.');
  } else {
    renderResults(0);
  }
}

let queryTimer = null;
function scheduleLoad(force = false) {
  clearTimeout(queryTimer);
  state.generation += 1;
  state.loading = true;
  renderResults(state.rev);
  queryTimer = setTimeout(() => { void loadResults(force); }, state.query.trim() ? 320 : 0);
}

async function beginSignIn() {
  if (state.deviceFlow) return;
  render(0, 'list', { loading: true, loadingText: 'Starting Microsoft sign-in…', items: [] });
  try {
    const { response, body } = await requestJson(authUrl('devicecode'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ client_id: state.settings.clientId, scope: SCOPES }),
    });
    if (!response.ok) throw serviceError(body, response);
    if (!body.device_code || !body.user_code || !safeUrl(body.verification_uri)) {
      throw new Error('Microsoft returned an incomplete sign-in response.');
    }
    state.deviceFlow = {
      id: crypto.randomUUID(), deviceCode: body.device_code, userCode: body.user_code,
      verificationUri: safeUrl(body.verification_uri),
      expiresAt: Date.now() + Number(body.expires_in || 900) * 1000,
      interval: Math.max(5, Number(body.interval) || 5),
    };
    renderDeviceCode(0);
    // The launcher may close when the browser opens. Finish the token exchange
    // and secret-store write during the host's detached grace period.
    command('background', { timeout: 300 });
    command('open', { url: state.deviceFlow.verificationUri });
    void pollSignIn(state.deviceFlow);
  } catch (error) {
    renderConnect(0, `Could not start sign-in: ${error.message}`);
  }
}

function pause(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function pollSignIn(flow) {
  while (!state.closed && state.deviceFlow?.id === flow.id && Date.now() < flow.expiresAt) {
    await pause(flow.interval * 1000);
    if (state.closed || state.deviceFlow?.id !== flow.id) return;
    try {
      const { response, body } = await requestJson(authUrl('token'), {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ client_id: state.settings.clientId,
          grant_type: 'urn:ietf:params:oauth:grant-type:device_code', device_code: flow.deviceCode }),
      });
      if (response.ok) {
        saveTokens(body);
        state.deviceFlow = null;
        if (state.detached) {
          command('notify', { title: 'Microsoft 365 connected', text: 'Your Outlook agenda is ready in Tabame.' });
          setTimeout(() => process.exit(0), 1000);
        } else {
          state.screen = 'results';
          state.eventsAt = 0;
          state.mailCache.clear();
          scheduleLoad(true);
        }
        return;
      }
      if (body.error === 'authorization_pending') continue;
      if (body.error === 'slow_down') {
        flow.interval += 5;
        continue;
      }
      throw serviceError(body, response);
    } catch (error) {
      if (/abort|fetch failed/i.test(error.message) && Date.now() < flow.expiresAt) continue;
      state.deviceFlow = null;
      if (!state.detached) renderConnect(0, `Sign-in failed: ${error.message}`);
      return;
    }
  }
  if (state.deviceFlow?.id === flow.id) {
    state.deviceFlow = null;
    if (!state.detached) renderConnect(0, 'The sign-in code expired. Start sign-in again.');
  }
}

function openAndHide(url) {
  if (!safeUrl(url)) {
    toast('No link is available for this item.', 'error');
    return;
  }
  command('open', { url });
  command('hide');
}

function copy(value) {
  if (!value) {
    toast('Nothing to copy for this item.', 'error');
    return;
  }
  command('copy', { text: value });
}

function backToResults() {
  state.screen = 'results';
  state.detailId = null;
  renderResults(0);
}

async function handleAction(message) {
  const action = message.action || 'default';
  const id = message.id || '';
  if (action === 'registration') {
    command('open', { url: 'https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade' });
    return;
  }
  if (action === 'settings') { renderSettings(); return; }
  if (action === 'refresh') { scheduleLoad(true); return; }
  if (action === 'signout') {
    state.tokens = null;
    state.events = [];
    state.eventsAt = 0;
    state.mailCache.clear();
    storageDelete(TOKEN_KEY, true);
    renderConnect();
    return;
  }
  if (id === 'connect' || action === 'connect') { await beginSignIn(); return; }
  if (action === 'open_signin' && state.deviceFlow) {
    command('open', { url: state.deviceFlow.verificationUri });
    return;
  }
  if (action === 'copy_code' && state.deviceFlow) { copy(state.deviceFlow.userCode); return; }
  if (action === 'cancel_signin') { state.deviceFlow = null; renderConnect(); return; }
  if (action === 'back') { backToResults(); return; }

  const entry = state.items.get(id || state.detailId);
  if (!entry) return;
  const data = entry.data;
  if (action === 'details') { renderDetail(id); return; }
  if (entry.kind === 'event') {
    const join = eventJoinUrl(data);
    const outlook = safeUrl(data.webLink);
    if (action === 'default' || action === 'join') {
      if (join) openAndHide(join);
      else if (outlook) openAndHide(outlook);
      else renderDetail(id || state.detailId);
    } else if (action === 'open') openAndHide(outlook);
    else if (action === 'copy_link') copy(join || outlook);
    else if (action === 'copy_details') copy(`${data.subject || '(No title)'}\n${eventSubtitle(data)}${join ? `\n${join}` : ''}`);
  } else {
    if (action === 'default' || action === 'open') openAndHide(safeUrl(data.webLink));
    else if (action === 'copy_sender') copy(data.from?.emailAddress?.address);
    else if (action === 'copy_link') copy(safeUrl(data.webLink));
  }
}

async function bootstrap() {
  try {
    const [savedSettings, savedTokens] = await Promise.all([
      storageGet(SETTINGS_KEY), storageGet(TOKEN_KEY, true),
    ]);
    const settings = parseStoredJson(savedSettings);
    try {
      state.settings = settings ? validateSettings(settings.clientId, settings.tenant) : null;
    } catch (_) {
      state.settings = null;
    }
    const tokens = parseStoredJson(savedTokens);
    state.tokens = tokens && state.settings && tokens.clientId === state.settings.clientId
      && tokens.tenant === state.settings.tenant ? tokens : null;
    state.bootstrapped = true;
    if (!state.settings) renderSettings(state.rev);
    else if (!state.tokens) renderConnect(state.rev);
    else { state.screen = 'results'; scheduleLoad(); }
  } catch (error) {
    render(0, 'detail', { detail: { markdown: `# Storage unavailable\n\n${escapeMarkdown(error.message)}` } });
  }
}

async function handleMessage(message) {
  if (message.type === 'storage') { handleStorage(message); return; }
  if (message.type === 'init') {
    state.query = String(message.query || '');
    render(0, 'list', { loading: true, loadingText: 'Loading Microsoft 365…', items: [] });
    if (!state.bootstrapped) void bootstrap();
    return;
  }
  if (message.type === 'query') {
    state.rev = Number(message.rev) || 0;
    state.query = String(message.text || '');
    if (!state.bootstrapped) return;
    if (state.screen === 'detail') state.screen = 'results';
    if (state.screen === 'results') scheduleLoad();
    return;
  }
  if (message.type === 'submit' && state.screen === 'settings') {
    try {
      const settings = validateSettings(message.values?.clientId, message.values?.tenant);
      const changed = settings.clientId !== state.settings?.clientId || settings.tenant !== state.settings?.tenant;
      state.settings = settings;
      storageSet(SETTINGS_KEY, JSON.stringify(settings));
      if (changed) {
        state.tokens = null;
        storageDelete(TOKEN_KEY, true);
      }
      if (state.tokens) { state.screen = 'results'; scheduleLoad(true); }
      else renderConnect();
    } catch (error) {
      renderSettings(0, error.message);
    }
    return;
  }
  if (message.type === 'action') { await handleAction(message); return; }
  if (message.type === 'back') {
    if (state.screen === 'settings') {
      if (state.tokens) { state.screen = 'results'; renderResults(); }
      else renderConnect();
    } else if (state.screen === 'detail') backToResults();
    return;
  }
  if (message.type === 'close') {
    state.detached = true;
    clearTimeout(queryTimer);
    if (!state.deviceFlow) process.exit(0);
  }
}

const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
input.on('line', (line) => {
  try {
    const message = JSON.parse(line);
    void handleMessage(message).catch((error) => {
      if (!state.detached) render(0, 'detail', { detail: { markdown: `# Microsoft 365 error\n\n${escapeMarkdown(error.message)}` } });
    });
  } catch (error) {
    process.stderr.write(`Invalid plugin message: ${error.message}\n`);
  }
});
input.on('close', () => { state.closed = true; process.exit(0); });
