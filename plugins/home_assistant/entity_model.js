'use strict';

function normal(value) {
  return String(value || '').normalize('NFKD').replace(/[\u0300-\u036f]/g, '')
    .toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

function number(value) {
  if (value === null || value === undefined || String(value).trim() === '') return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function titleCase(value) {
  return String(value || '').replace(/_/g, ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function firstText(...values) {
  return values.find((value) => typeof value === 'string' && value.trim()) || '';
}

function makeEntity(raw, metadata = {}) {
  if (!raw || typeof raw.entity_id !== 'string' || !raw.entity_id.includes('.')) return null;
  const id = raw.entity_id;
  const attributes = raw.attributes && typeof raw.attributes === 'object' && !Array.isArray(raw.attributes)
    ? raw.attributes : {};
  const domain = id.split('.')[0];
  const name = firstText(attributes.friendly_name, titleCase(id.split('.').slice(1).join('.')));
  const area = firstText(metadata.area, attributes.area_name, attributes.area);
  const device = firstText(metadata.device, attributes.device_name);
  const entity = {
    id, domain, name, area, device, attributes,
    state: typeof raw.state === 'string' ? raw.state : 'unknown',
    lastChanged: raw.last_changed || '',
  };
  entity.search = {
    name: normal(name), id: normal(id), domain: normal(domain),
    area: normal(area), device: normal(device),
  };
  entity.search.words = [entity.search.name, entity.search.id, entity.search.domain,
    entity.search.area, entity.search.device].join(' ').split(' ').filter(Boolean);
  return entity;
}

function isAvailable(entity) {
  return entity.state !== 'unavailable' && entity.state !== 'unknown';
}

function iconFor(entity) {
  const domain = entity.domain;
  if (domain === 'sensor') {
    const deviceClass = entity.attributes.device_class;
    if (deviceClass === 'temperature') return 'weather';
    if (deviceClass === 'humidity') return 'cloud';
    if (deviceClass === 'power' || deviceClass === 'energy') return 'bolt';
    return 'chart';
  }
  return {
    light: 'sun', switch: 'power', input_boolean: 'power', scene: 'palette',
    climate: 'weather', cover: 'window', media_player: 'music', lock: 'lock',
    sun: 'sun', person: 'person', binary_sensor: 'info', fan: 'sync',
    script: 'run', automation: 'run', button: 'bolt',
  }[domain] || 'home';
}

function stateLabel(entity, defaultTemperatureUnit = '') {
  if (entity.state === 'unavailable') return 'Unavailable';
  if (entity.state === 'unknown') return 'Unknown';
  const { domain, state, attributes: attr } = entity;
  if (domain === 'scene') return 'Scene';
  if (domain === 'light') {
    const brightness = number(attr.brightness);
    return state === 'on' && brightness !== null
      ? `ON · ${Math.round(brightness / 255 * 100)}%` : state.toUpperCase();
  }
  if (['switch', 'input_boolean', 'fan', 'lock'].includes(domain)) return state.toUpperCase();
  if (domain === 'sensor') {
    const unit = firstText(attr.unit_of_measurement);
    return `${state}${unit ? ` ${unit}` : ''}`;
  }
  if (domain === 'binary_sensor') {
    if (attr.device_class === 'door' || attr.device_class === 'window' || attr.device_class === 'opening') {
      return state === 'on' ? 'Open' : 'Closed';
    }
    if (attr.device_class === 'motion') return state === 'on' ? 'Detected' : 'Clear';
    return state.toUpperCase();
  }
  if (domain === 'climate') {
    const current = number(attr.current_temperature);
    const target = number(attr.temperature);
    const unit = firstText(attr.temperature_unit, attr.unit_of_measurement, defaultTemperatureUnit);
    const mode = firstText(attr.hvac_action, state).replace(/_/g, ' ');
    const temps = current !== null && target !== null
      ? ` · ${current}${unit} → ${target}${unit}`
      : current !== null ? ` · ${current}${unit}` : target !== null ? ` · ${target}${unit}` : '';
    return `${titleCase(mode)}${temps}`;
  }
  if (domain === 'cover') {
    const position = number(attr.current_position);
    return position === null ? titleCase(state) : `${position}% open`;
  }
  if (domain === 'media_player') {
    const source = firstText(attr.app_name, attr.source, attr.media_title);
    return `${titleCase(state)}${source ? ` · ${source}` : ''}`;
  }
  return titleCase(state);
}

function stateColor(entity) {
  if (!isAvailable(entity)) return '#8A8F98';
  if (entity.state === 'on' || entity.state === 'playing' || entity.state === 'open') return '#48B88A';
  if (entity.state === 'off' || entity.state === 'closed' || entity.state === 'idle') return '#8A8F98';
  return '#6A9EEB';
}

function entitySubtitle(entity, showIds) {
  const parts = [];
  if (entity.area) parts.push(entity.area);
  if (entity.device && entity.device !== entity.name && entity.device !== entity.area) parts.push(entity.device);
  if (showIds || parts.length === 0) parts.push(entity.id);
  return parts.join(' · ');
}

function escapeMarkdown(value) {
  return String(value || '').replace(/[\\`*_\[\]<>]/g, '\\$&');
}

module.exports = {
  makeEntity, normal, number, isAvailable, iconFor, stateLabel,
  stateColor, entitySubtitle, escapeMarkdown,
};
