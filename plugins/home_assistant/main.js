#!/usr/bin/env node
'use strict';

const readline = require('readline');
const { HomeAssistantClient, HomeAssistantError, normalizeUrl } = require('./home_assistant_client');
const {
  makeEntity, number, isAvailable, iconFor, stateLabel, stateColor,
  entitySubtitle, escapeMarkdown,
} = require('./entity_model');
const { searchEntities } = require('./entity_search');
const { defaultAction, entityActions, resolveAction } = require('./entity_actions');

const CACHE_MS = 60_000;
const STORAGE_KEYS = ['url', 'token', 'preferences', 'favorites', 'recent'];
const CATEGORIES = [
  { id: 'favorites', title: 'Favorites', icon: 'star' },
  { id: 'lights', title: 'Lights', icon: 'sun', domains: ['light'] },
  { id: 'switches', title: 'Switches', icon: 'power', domains: ['switch'] },
  { id: 'scenes', title: 'Scenes', icon: 'palette', domains: ['scene'] },
  { id: 'climate', title: 'Climate', icon: 'weather', domains: ['climate'] },
  { id: 'covers', title: 'Covers', icon: 'window', domains: ['cover'] },
  { id: 'media', title: 'Media Players', icon: 'music', domains: ['media_player'] },
  { id: 'sensors', title: 'Sensors', icon: 'chart', domains: ['sensor', 'binary_sensor'] },
  { id: 'all', title: 'All Entities', icon: 'grid' },
];

const state = {
  started: false, loaded: false, closed: false, pending: new Set(STORAGE_KEYS),
  url: '', token: '',
  preferences: {
    showEntityIds: true, showUnavailable: true, resultLimit: 40, recentEnabled: true,
  },
  favorites: new Set(), recent: [],
  entities: new Map(), metadata: new Map(),
  temperatureUnit: '',
  client: null, configVersion: 0,
  refreshPromise: null, refreshSeq: 0, loadedAt: 0, lastAttemptAt: 0,
  error: '', busy: new Set(),
  screen: 'browse', entityId: '', query: '', rev: 0, visibleLimit: 40,
};

function send(message) {
  if (!state.closed) process.stdout.write(`${JSON.stringify(message)}\n`);
}

function render(rev, view, payload) {
  send({ type: 'render', rev, view, ...payload });
}

function command(name, fields = {}) {
  send({ type: 'command', command: name, ...fields });
}

function toast(text, style = 'info') {
  command('toast', { text, style });
}

function safeMessage(error) {
  if (error instanceof HomeAssistantError) return error.message;
  return error && error.message && [
    'Action is unavailable', 'Unsupported action', 'Enter a value in the allowed range',
    'Target temperature is unknown', 'Target temperature is at its limit',
    'Choose a valid color',
  ].includes(error.message) ? error.message : 'Home Assistant could not complete the request';
}

function storageSet(key, value, secret = false) {
  command('storage', { op: 'set', key, value, ...(secret ? { secret: true } : {}) });
}

function startStorage() {
  if (state.started) return;
  state.started = true;
  for (const key of STORAGE_KEYS) {
    command('storage', { op: 'get', key, requestId: key, ...(key === 'token' ? { secret: true } : {}) });
  }
}

function handleStorage(message) {
  const key = message.requestId;
  if (!state.pending.has(key)) return;
  state.pending.delete(key);
  const value = message.value;
  if (key === 'url' && typeof value === 'string') state.url = value;
  if (key === 'token' && typeof value === 'string') state.token = value;
  if (key === 'preferences' && value && typeof value === 'object' && !Array.isArray(value)) {
    state.preferences = {
      ...state.preferences,
      showEntityIds: value.showEntityIds !== false,
      showUnavailable: value.showUnavailable !== false,
      resultLimit: Math.min(100, Math.max(10, Number(value.resultLimit) || 40)),
      recentEnabled: value.recentEnabled !== false,
    };
  }
  if (key === 'favorites' && Array.isArray(value)) {
    state.favorites = new Set(value.filter((id) => typeof id === 'string'));
  }
  if (key === 'recent' && Array.isArray(value)) {
    state.recent = value.filter((id) => typeof id === 'string').slice(0, 20);
  }
  if (state.pending.size > 0) return;
  state.loaded = true;
  state.visibleLimit = state.preferences.resultLimit;
  if (!state.url || !state.token) {
    state.screen = 'settings';
    renderSettings(0, true);
    return;
  }
  void refreshEntities();
}

function entityItem(entity, section) {
  const favorite = state.favorites.has(entity.id);
  const actions = [
    ...entityActions(entity),
    { id: 'details', title: 'Details', icon: 'info' },
    { id: 'favorite', title: favorite ? 'Remove Favorite' : 'Add Favorite', icon: 'star' },
  ];
  return {
    id: `entity:${entity.id}`,
    title: entity.name,
    subtitle: entitySubtitle(entity, state.preferences.showEntityIds),
    icon: iconFor(entity),
    ...(section ? { section } : {}),
    accessories: [
      ...(favorite ? [{ text: '★', color: '#E8B653' }] : []),
      { text: stateLabel(entity, state.temperatureUnit), color: stateColor(entity) },
    ],
    actions,
  };
}

function visibleEntity(id) {
  const entity = state.entities.get(id);
  return entity && (state.preferences.showUnavailable || isAvailable(entity)) ? entity : null;
}

function categoryCount(category) {
  if (category.id === 'favorites') {
    return [...state.favorites].filter((id) => visibleEntity(id)).length;
  }
  if (!category.domains) return [...state.entities.values()].filter((entity) => visibleEntity(entity.id)).length;
  return [...state.entities.values()].filter((entity) =>
    category.domains.includes(entity.domain) && visibleEntity(entity.id)).length;
}

function browseActions() {
  return [
    { id: 'refresh', title: 'Refresh Entities', icon: 'refresh' },
    { id: 'test', title: 'Test Connection', icon: 'wifi' },
    { id: 'settings', title: 'Settings', icon: 'settings' },
  ];
}

function browseFrame(rev, payload = {}) {
  const { history = 'none', ...framePayload } = payload;
  render(rev, 'list', {
    page: { id: 'ha:home', title: 'Home Assistant', history, preserveState: true },
    elementId: 'entities',
    placeholder: 'Search Home Assistant entities…',
    actions: browseActions(),
    ...framePayload,
  });
}

function renderBrowse(rev = 0, history = 'none', selectId = '') {
  if (!state.loaded) {
    browseFrame(rev, { loading: true, loadingText: 'Loading Home Assistant settings…', items: [], history });
    return;
  }
  if (!state.url || !state.token) {
    state.screen = 'settings';
    renderSettings(rev, true);
    return;
  }
  if (state.entities.size === 0 && state.refreshPromise) {
    browseFrame(rev, { loading: true, loadingText: 'Fetching Home Assistant entities…', items: [], history });
    return;
  }
  const rawQuery = state.query.trim();
  let items = [];
  let total = 0;
  if (!rawQuery) {
    for (const id of state.favorites) {
      const entity = visibleEntity(id);
      if (entity) items.push(entityItem(entity, 'Favorites'));
    }
    if (state.preferences.recentEnabled) {
      for (const id of state.recent) {
        if (state.favorites.has(id)) continue;
        const entity = visibleEntity(id);
        if (entity) items.push(entityItem(entity, 'Recent'));
      }
    }
    items.push(...CATEGORIES.map((category) => ({
      id: `category:${category.id}`, title: category.title,
      subtitle: category.id === 'favorites' ? 'Saved locally in Tabame' : 'Browse entities',
      icon: category.icon, section: 'Browse',
      accessories: [{ text: String(categoryCount(category)) }],
    })));
    items.push({ id: 'navigation:settings', title: 'Settings', subtitle: 'Connection and display options',
      icon: 'settings', section: 'Setup' });
    total = items.length;
  } else {
    const results = searchEntities(state.entities, rawQuery, state.favorites, state.recent,
      state.preferences.showUnavailable);
    total = results.length;
    items = results.slice(0, state.visibleLimit).map((entity) => entityItem(entity));
  }

  const banners = state.error ? [{
    id: 'connection', style: 'warning', title: 'Home Assistant is unreachable',
    message: state.entities.size > 0
      ? `${state.error}. Showing the last fetched states.` : `${state.error}. Check settings or retry.`,
    actions: [{ id: 'refresh', title: 'Retry', icon: 'refresh' }],
  }] : [];
  browseFrame(rev, {
    history, items, banners, ...(selectId ? { selectId } : {}),
    hasMore: !!rawQuery && total > items.length,
    ...(items.length === 0 ? { empty: state.error ? {
      icon: 'warning', title: state.error, hint: 'Check the connection or settings.',
      action: { id: 'refresh', title: 'Retry', icon: 'refresh' },
    } : {
      icon: 'search', title: 'No matching entities', hint: 'Try a name, room, device, or entity ID.',
    } } : {}),
  });
}

function detailMetadata(entity) {
  const attr = entity.attributes;
  const metadata = [
    { label: 'State', text: stateLabel(entity, state.temperatureUnit), color: stateColor(entity) },
  ];
  if (entity.domain === 'light' && number(attr.brightness) !== null) {
    metadata.push({ label: 'Brightness', text: `${Math.round(number(attr.brightness) / 255 * 100)}%` });
  }
  if (entity.domain === 'climate') {
    if (number(attr.current_temperature) !== null) {
      metadata.push({ label: 'Current Temperature',
        text: `${attr.current_temperature}${attr.temperature_unit || state.temperatureUnit}` });
    }
    if (number(attr.temperature) !== null) {
      metadata.push({ label: 'Target Temperature',
        text: `${attr.temperature}${attr.temperature_unit || state.temperatureUnit}` });
    }
  }
  if (entity.domain === 'media_player' && number(attr.volume_level) !== null) {
    metadata.push({ label: 'Volume', text: `${Math.round(number(attr.volume_level) * 100)}%` });
  }
  if (entity.area) metadata.push({ label: 'Area', text: entity.area });
  if (entity.device) metadata.push({ label: 'Device', text: entity.device });
  metadata.push({ label: 'Entity ID', text: entity.id });
  if (entity.lastChanged) {
    const date = new Date(entity.lastChanged);
    if (!Number.isNaN(date.getTime())) metadata.push({ label: 'Last Changed', text: date.toLocaleString() });
  }
  const controls = entityActions(entity);
  if (controls.length) metadata.push({ label: 'Actions', text: 'Available controls', actions: controls });
  return metadata;
}

function renderDetail(rev = 0, history = 'none') {
  const entity = state.entities.get(state.entityId);
  const page = {
    id: `ha:entity:${state.entityId}`, title: entity ? entity.name : 'Entity',
    history, preserveState: true, breadcrumbs: [{ id: 'ha:home', label: 'Home Assistant' }],
  };
  if (!entity) {
    render(rev, 'detail', {
      page, detail: { markdown: '# Entity no longer exists\n\nRefresh the entity list to find what is available now.' },
      actions: [{ id: 'back', title: 'Back to Entities', icon: 'reply' }],
    });
    return;
  }
  const favorite = state.favorites.has(entity.id);
  render(rev, 'detail', {
    page,
    detail: {
      markdown: `# ${escapeMarkdown(entity.name)}\n\n${escapeMarkdown(entity.area || entity.domain)}`,
      metadata: detailMetadata(entity),
    },
    actions: [
      ...entityActions(entity),
      { id: 'favorite', title: favorite ? 'Remove Favorite' : 'Add Favorite', icon: 'star' },
      { id: 'refresh_entity', title: 'Refresh Entity', icon: 'refresh' },
      { id: 'back', title: 'Back to Entities', icon: 'reply' },
    ],
  });
}

function renderSettings(rev = 0, setup = false, error = '', history = 'none') {
  render(rev, 'form', {
    page: {
      id: 'ha:settings', title: 'Home Assistant Settings', history,
      // The host must discard typed password values when this page is revisited.
      preserveState: false,
      ...(setup ? {} : { breadcrumbs: [{ id: 'ha:home', label: 'Home Assistant' }] }),
    },
    form: {
      title: setup ? 'Connect Home Assistant' : 'Home Assistant Settings',
      ...(error ? { error } : {}),
      sections: [
        { id: 'connection', title: 'Connection', description: 'Use the URL and a Long-Lived Access Token from Home Assistant.' },
        { id: 'display', title: 'Results' },
      ],
      fields: [
        { id: 'url', type: 'text', label: 'Home Assistant URL', value: state.url,
          placeholder: 'http://homeassistant.local:8123', required: true, section: 'connection' },
        { id: 'token', type: 'password', label: 'Long-Lived Access Token',
          placeholder: state.token ? 'Saved token ••••••••••••••••' : 'Paste your token',
          description: state.token ? 'Leave blank to keep the saved token.' : 'Stored in Tabame secret storage.',
          required: !state.token, section: 'connection' },
        { id: 'showEntityIds', type: 'checkbox', label: 'Show entity IDs',
          value: state.preferences.showEntityIds, section: 'display' },
        { id: 'showUnavailable', type: 'checkbox', label: 'Show unavailable entities',
          value: state.preferences.showUnavailable, section: 'display' },
        { id: 'resultLimit', type: 'number', label: 'Default result limit', min: 10, max: 100,
          value: state.preferences.resultLimit, section: 'display' },
        { id: 'recentEnabled', type: 'checkbox', label: 'Enable recent entities',
          value: state.preferences.recentEnabled, section: 'display' },
      ],
      buttons: [
        { id: 'save', label: 'Save' },
        { id: 'test', label: 'Test Connection' },
        { id: 'refresh', label: 'Refresh Entities' },
      ],
    },
  });
}

function renderCurrent(rev = 0, selectId = '') {
  if (state.screen === 'detail') renderDetail(rev);
  else if (state.screen === 'settings') renderSettings(rev, !state.url || !state.token);
  else renderBrowse(rev, 'none', selectId);
}

async function refreshEntities(force = false) {
  if (!state.url || !state.token || state.closed) return;
  if (state.refreshPromise && !force) return state.refreshPromise;
  if (!force && state.entities.size > 0 && Date.now() - state.lastAttemptAt < CACHE_MS) return;

  let client;
  try {
    client = state.client || new HomeAssistantClient(state.url, state.token);
    state.client = client;
  } catch (error) {
    state.error = safeMessage(error);
    renderCurrent(0);
    return;
  }
  const version = state.configVersion;
  const sequence = ++state.refreshSeq;
  state.lastAttemptAt = Date.now();
  const job = (async () => {
    try {
      const rows = await client.getStates();
      if (state.closed || version !== state.configVersion || sequence !== state.refreshSeq) return;
      const next = new Map();
      for (const raw of rows) {
        const entity = makeEntity(raw, state.metadata.get(raw && raw.entity_id));
        if (entity) next.set(entity.id,
          state.busy.has(entity.id) ? state.entities.get(entity.id) || entity : entity);
      }
      state.entities = next;
      state.loadedAt = Date.now();
      state.error = '';
      renderCurrent(0);
      const [metadataResult, unitResult] = await Promise.allSettled([
        client.getEntityMetadata(),
        state.temperatureUnit ? Promise.resolve(state.temperatureUnit) : client.getTemperatureUnit(),
      ]);
      if (state.closed || version !== state.configVersion || sequence !== state.refreshSeq) return;
      if (unitResult.status === 'fulfilled') state.temperatureUnit = unitResult.value;
      if (metadataResult.status === 'fulfilled') {
        const nextMetadata = new Map(metadataResult.value.map((row) => [row.id, row]));
        state.metadata = nextMetadata;
        for (const [id, entity] of state.entities) {
          const updated = makeEntity({ entity_id: id, state: entity.state,
            attributes: entity.attributes, last_changed: entity.lastChanged }, nextMetadata.get(id));
          if (updated) state.entities.set(id, updated);
        }
      }
      renderCurrent(0);
    } catch (error) {
      if (state.closed || version !== state.configVersion || sequence !== state.refreshSeq) return;
      state.error = safeMessage(error);
      renderCurrent(0);
    }
  })();
  state.refreshPromise = job;
  if (state.entities.size === 0) renderCurrent(0);
  try {
    await job;
  } finally {
    if (state.refreshPromise === job) state.refreshPromise = null;
  }
}

function openDetail(id) {
  state.entityId = id;
  state.screen = 'detail';
  renderDetail(0, 'push');
}

function openSettings() {
  state.screen = 'settings';
  renderSettings(0, false, '', 'push');
}

function backToBrowse() {
  state.screen = 'browse';
  state.entityId = '';
  renderBrowse(0);
}

function toggleFavorite(id) {
  if (state.favorites.has(id)) state.favorites.delete(id);
  else state.favorites.add(id);
  storageSet('favorites', [...state.favorites]);
  renderCurrent(0, `entity:${id}`);
}

function markRecent(id) {
  if (!state.preferences.recentEnabled) return;
  state.recent = [id, ...state.recent.filter((item) => item !== id)].slice(0, 20);
  storageSet('recent', state.recent);
}

function updateEntity(raw) {
  const entity = makeEntity(raw, state.metadata.get(raw && raw.entity_id));
  if (entity) state.entities.set(entity.id, entity);
}

function optimisticState(entity, actionId) {
  if (!['light', 'switch'].includes(entity.domain)) return null;
  if (!['toggle', 'turn_on', 'turn_off'].includes(actionId)) return null;
  if (!['on', 'off'].includes(entity.state)) return null;
  const nextState = actionId === 'toggle' ? (entity.state === 'on' ? 'off' : 'on')
    : (actionId === 'turn_on' ? 'on' : 'off');
  return makeEntity({ entity_id: entity.id, state: nextState,
    attributes: entity.attributes, last_changed: entity.lastChanged }, state.metadata.get(entity.id));
}

async function executeEntityAction(id, actionId, parameters) {
  const entity = state.entities.get(id);
  if (!entity) { toast('Entity no longer exists', 'error'); return; }
  if (!isAvailable(entity)) { toast('Entity is unavailable', 'error'); return; }
  if (state.busy.has(id)) return;
  let operation;
  try {
    operation = resolveAction(entity, actionId, parameters);
  } catch (error) {
    toast(safeMessage(error), 'error');
    return;
  }
  state.busy.add(id);
  const client = state.client;
  const configVersion = state.configVersion;
  const optimistic = optimisticState(entity, actionId);
  if (optimistic) {
    state.entities.set(id, optimistic);
    renderCurrent(0, `entity:${id}`);
  }
  try {
    const changed = await client.callService(operation.domain, operation.service,
      id, operation.data || {});
    if (state.closed || configVersion !== state.configVersion) return;
    if (Array.isArray(changed)) {
      const row = changed.find((item) => item && item.entity_id === id);
      if (row) updateEntity(row);
    }
    markRecent(id);
    try {
      const current = await client.getEntity(id);
      if (state.closed || configVersion !== state.configVersion) return;
      updateEntity(current);
    } catch (error) {
      if (error instanceof HomeAssistantError && error.code === 'not_found') {
        state.entities.delete(id);
        toast('Entity no longer exists', 'error');
      } else {
        toast('Action sent; state could not be confirmed', 'info');
      }
    }
    if (actionId === 'activate') toast('Scene activated', 'success');
    renderCurrent(0, `entity:${id}`);
  } catch (error) {
    if (state.closed || configVersion !== state.configVersion) return;
    if (optimistic) state.entities.set(id, entity);
    toast(safeMessage(error), 'error');
    renderCurrent(0, `entity:${id}`);
  } finally {
    state.busy.delete(id);
  }
}

async function refreshEntity(id) {
  const entity = state.entities.get(id);
  if (!entity) return;
  try {
    updateEntity(await state.client.getEntity(id));
    renderCurrent(0, `entity:${id}`);
  } catch (error) {
    if (error instanceof HomeAssistantError && error.code === 'not_found') {
      state.entities.delete(id);
      renderCurrent(0);
    }
    toast(safeMessage(error), 'error');
  }
}

async function testConnection(values) {
  try {
    const url = values ? values.url : state.url;
    const token = values && String(values.token || '').trim() ? values.token : state.token;
    const client = new HomeAssistantClient(url, token);
    await client.testConnection();
    toast('Connected to Home Assistant', 'success');
  } catch (error) {
    toast(safeMessage(error), 'error');
  }
}

function saveSettings(values) {
  const url = normalizeUrl(values.url);
  const token = String(values.token || '').trim() || state.token;
  if (!token) throw new HomeAssistantError('Long-Lived Access Token is required', 'missing_token');
  const changed = url !== state.url || token !== state.token;
  state.url = url;
  state.token = token;
  state.preferences = {
    showEntityIds: values.showEntityIds !== false,
    showUnavailable: values.showUnavailable !== false,
    resultLimit: Math.min(100, Math.max(10, Number(values.resultLimit) || 40)),
    recentEnabled: values.recentEnabled !== false,
  };
  state.visibleLimit = state.preferences.resultLimit;
  storageSet('url', url);
  if (String(values.token || '').trim()) storageSet('token', token, true);
  storageSet('preferences', state.preferences);
  if (changed) {
    state.configVersion++;
    state.refreshSeq++;
    state.client = new HomeAssistantClient(url, token);
    state.entities.clear();
    state.metadata.clear();
    state.temperatureUnit = '';
    state.error = '';
    state.loadedAt = 0;
    state.lastAttemptAt = 0;
    state.refreshPromise = null;
  }
}

function handleSubmit(message) {
  if (state.screen !== 'settings') return;
  const values = message.values && typeof message.values === 'object' ? message.values : {};
  const button = message.button || 'save';
  if (button === 'test') { void testConnection(values); return; }
  try {
    saveSettings(values);
    backToBrowse();
    toast('Home Assistant settings saved', 'success');
    void refreshEntities(true);
  } catch (error) {
    renderSettings(0, !state.url || !state.token, safeMessage(error));
  }
}

function handleAction(message) {
  const id = String(message.id || '');
  const actionId = String(message.action || 'default');
  if (id.startsWith('category:') && actionId === 'default') {
    const filter = id.slice('category:'.length);
    state.screen = 'browse';
    state.query = filter === 'all' ? 'all ' : `${filter} `;
    state.visibleLimit = state.preferences.resultLimit;
    command('setQuery', { text: state.query });
    renderBrowse(0);
    return;
  }
  if (id === 'navigation:settings') { openSettings(); return; }
  if (id.startsWith('entity:')) {
    const entityId = id.slice('entity:'.length);
    const entity = state.entities.get(entityId);
    if (!entity) { toast('Entity no longer exists', 'error'); return; }
    if (actionId === 'details') { openDetail(entityId); return; }
    if (actionId === 'favorite') { toggleFavorite(entityId); return; }
    const chosen = actionId === 'default' ? defaultAction(entity) : actionId;
    if (!chosen) { openDetail(entityId); return; }
    void executeEntityAction(entityId, chosen, message.parameters || {});
    return;
  }
  if (actionId === 'back') { backToBrowse(); return; }
  if (actionId === 'settings') { openSettings(); return; }
  if (actionId === 'test') { void testConnection(); return; }
  if (actionId === 'refresh') { void refreshEntities(true); return; }
  if (state.screen !== 'detail') return;
  if (actionId === 'favorite') { toggleFavorite(state.entityId); return; }
  if (actionId === 'refresh_entity') { void refreshEntity(state.entityId); return; }
  void executeEntityAction(state.entityId, actionId, message.parameters || {});
}

function handleQuery(message) {
  const next = String(message.text ?? message.query ?? '');
  const changed = next !== state.query;
  state.query = next;
  state.rev = Number(message.rev) || 0;
  if (changed && state.screen === 'detail') state.screen = 'browse';
  if (changed) state.visibleLimit = state.preferences.resultLimit;
  renderCurrent(state.rev);
  if (state.loaded && state.screen === 'browse' && state.url && state.token &&
      Date.now() - state.lastAttemptAt >= CACHE_MS) {
    void refreshEntities();
  }
}

function handleBack(message) {
  if (message.toPageId && message.toPageId.startsWith('ha:entity:')) {
    state.entityId = message.toPageId.slice('ha:entity:'.length);
    state.screen = 'detail';
    renderDetail(0);
  } else {
    backToBrowse();
  }
}

function handleMessage(message) {
  switch (message.type) {
    case 'init':
      startStorage();
      handleQuery(message);
      break;
    case 'storage':
      handleStorage(message);
      break;
    case 'query':
      handleQuery(message);
      break;
    case 'action':
      handleAction(message);
      break;
    case 'submit':
      handleSubmit(message);
      break;
    case 'loadMore':
      state.visibleLimit += state.preferences.resultLimit;
      renderBrowse(Number(message.rev) || 0);
      break;
    case 'back':
      handleBack(message);
      break;
    case 'navigate':
      handleBack({ toPageId: message.targetPageId });
      break;
    case 'close':
      state.closed = true;
      process.exit(0);
      break;
    default:
      break;
  }
}

const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
input.on('line', (line) => {
  try {
    const message = JSON.parse(line);
    if (message && typeof message === 'object') handleMessage(message);
  } catch (error) {
    if (line.trim().startsWith('{')) toast(safeMessage(error), 'error');
  }
});
input.on('close', () => { state.closed = true; process.exit(0); });
