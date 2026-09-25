'use strict';

class HomeAssistantError extends Error {
  constructor(message, code) {
    super(message);
    this.name = 'HomeAssistantError';
    this.code = code;
  }
}

function normalizeUrl(value) {
  let url;
  try {
    url = new URL(String(value || '').trim());
  } catch (_) {
    throw new HomeAssistantError('Invalid Home Assistant URL', 'invalid_url');
  }
  if (!['http:', 'https:'].includes(url.protocol) || !url.hostname ||
      url.username || url.password || url.search || url.hash) {
    throw new HomeAssistantError('Invalid Home Assistant URL', 'invalid_url');
  }
  return url.toString().replace(/\/+$/, '');
}

// One REST request obtains area/device search terms for the same state snapshot.
// This is optional: installations that disable templates still get entity search.
const ENTITY_METADATA_TEMPLATE =
  '[{% for s in states %}{"id":{{ s.entity_id | to_json }},' +
  '"area":{{ area_name(s.entity_id) | to_json }},' +
  '"device":{{ device_name(s.entity_id) | to_json }}}' +
  '{% if not loop.last %},{% endif %}{% endfor %}]';

class HomeAssistantClient {
  constructor(url, token) {
    this.url = normalizeUrl(url);
    this.token = String(token || '').trim();
    if (!this.token) throw new HomeAssistantError('Long-Lived Access Token is required', 'missing_token');
  }

  async request(path, { method = 'GET', body, text = false } = {}) {
    let response;
    try {
      response = await fetch(`${this.url}${path}`, {
        method,
        headers: {
          Authorization: `Bearer ${this.token}`,
          'Content-Type': 'application/json',
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(7000),
        redirect: 'error',
      });
    } catch (error) {
      if (error && (error.name === 'TimeoutError' || error.name === 'AbortError')) {
        throw new HomeAssistantError('Connection timed out', 'timeout');
      }
      throw new HomeAssistantError('Could not reach Home Assistant', 'network');
    }

    if (response.status === 401) throw new HomeAssistantError('Invalid access token', 'invalid_token');
    if (response.status === 403) throw new HomeAssistantError('Unauthorized', 'unauthorized');
    if (response.status === 404) {
      throw new HomeAssistantError(
        path.startsWith('/api/states/') ? 'Entity no longer exists' : 'Home Assistant API endpoint not found',
        'not_found',
      );
    }
    if (!response.ok) {
      throw new HomeAssistantError(
        method === 'POST' && path.startsWith('/api/services/')
          ? 'Home Assistant could not perform this action'
          : 'Home Assistant returned an error',
        'http_error',
      );
    }

    let payload;
    try {
      payload = await response.text();
    } catch (_) {
      throw new HomeAssistantError('Could not read Home Assistant response', 'network');
    }
    if (text) return payload;
    try {
      return JSON.parse(payload);
    } catch (_) {
      throw new HomeAssistantError('Invalid response from Home Assistant', 'invalid_json');
    }
  }

  async testConnection() {
    const data = await this.request('/api/');
    if (!data || typeof data !== 'object' || Array.isArray(data)) {
      throw new HomeAssistantError('Invalid response from Home Assistant', 'invalid_json');
    }
    return true;
  }

  async getStates() {
    const data = await this.request('/api/states');
    if (!Array.isArray(data)) throw new HomeAssistantError('Invalid response from Home Assistant', 'invalid_json');
    return data;
  }

  async getTemperatureUnit() {
    const config = await this.request('/api/config');
    const unit = config && config.unit_system && config.unit_system.temperature;
    return typeof unit === 'string' ? unit : '';
  }

  async getEntity(entityId) {
    const data = await this.request(`/api/states/${encodeURIComponent(entityId)}`);
    if (!data || typeof data !== 'object' || data.entity_id !== entityId) {
      throw new HomeAssistantError('Invalid response from Home Assistant', 'invalid_json');
    }
    return data;
  }

  async callService(domain, service, entityId, data = {}) {
    // The caller selects a known domain/service; never accept a URL from an entity.
    if (!/^[a-z_]+$/.test(domain) || !/^[a-z_]+$/.test(service)) {
      throw new HomeAssistantError('Unsupported action', 'unsupported');
    }
    return this.request(`/api/services/${domain}/${service}`, {
      method: 'POST',
      body: { ...data, entity_id: entityId },
    });
  }

  toggleEntity(entity) {
    return this.callService(entity.domain, 'toggle', entity.id);
  }

  activateScene(entity) {
    return this.callService('scene', 'turn_on', entity.id);
  }

  async getEntityMetadata() {
    const raw = await this.request('/api/template', {
      method: 'POST',
      body: { template: ENTITY_METADATA_TEMPLATE },
      text: true,
    });
    try {
      const rows = JSON.parse(raw);
      if (!Array.isArray(rows)) return [];
      return rows.filter((row) => row && typeof row.id === 'string');
    } catch (_) {
      return [];
    }
  }
}

module.exports = { HomeAssistantClient, HomeAssistantError, normalizeUrl };
