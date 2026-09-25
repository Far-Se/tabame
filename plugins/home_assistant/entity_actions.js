'use strict';

const { isAvailable, number } = require('./entity_model');

const COVER = { OPEN: 1, CLOSE: 2, SET_POSITION: 4, STOP: 8 };
const CLIMATE = { TARGET_TEMPERATURE: 1 };
const MEDIA = {
  PAUSE: 1, VOLUME_SET: 4, VOLUME_MUTE: 8, PREVIOUS: 16, NEXT: 32,
  TURN_ON: 128, TURN_OFF: 256, VOLUME_STEP: 1024, PLAY: 16384,
};

function feature(entity, flag) {
  const value = number(entity.attributes.supported_features);
  return value !== null && (value & flag) !== 0;
}

function action(id, title, icon, parameters, extra = {}) {
  return { id, title, icon, ...(parameters ? { parameters } : {}), ...extra };
}

function numberParameter(id, label, min, max, value, step = 1) {
  return [{ id, type: 'number', label, required: true, min, max, step, value }];
}

function defaultAction(entity) {
  if (!isAvailable(entity)) return null;
  if (['light', 'switch', 'input_boolean', 'fan'].includes(entity.domain)) return 'toggle';
  if (entity.domain === 'scene') return 'activate';
  if (entity.domain === 'button') return 'press';
  if (entity.domain === 'script') return 'run';
  return null;
}

function entityActions(entity) {
  if (!isAvailable(entity)) return [];
  const attr = entity.attributes;
  switch (entity.domain) {
    case 'light': {
      const items = [
        action('toggle', 'Toggle', 'power'),
        action('turn_on', 'Turn On', 'sun'),
        action('turn_off', 'Turn Off', 'power'),
      ];
      const modes = Array.isArray(attr.supported_color_modes) ? attr.supported_color_modes : [];
      if (modes.some((mode) => mode !== 'onoff' && mode !== 'unknown')) {
        items.push(action('brightness', 'Brightness', 'sun',
          numberParameter('brightness', 'Brightness (%)', 1, 100,
            Math.round((number(attr.brightness) || 255) / 255 * 100))));
      }
      if (modes.includes('color_temp')) {
        const min = number(attr.min_color_temp_kelvin) || 2000;
        const max = number(attr.max_color_temp_kelvin) || 6500;
        items.push(action('color_temperature', 'Color Temperature', 'weather',
          numberParameter('kelvin', 'Color temperature (K)', min, max,
            number(attr.color_temp_kelvin) || Math.round((min + max) / 2))));
      }
      if (modes.some((mode) => ['hs', 'rgb', 'rgbw', 'rgbww', 'xy'].includes(mode))) {
        items.push(action('color', 'Color', 'palette',
          [{ id: 'color', type: 'color', label: 'Color', value: '#FFFFFF', required: true }]));
      }
      return items;
    }
    case 'switch':
    case 'input_boolean':
    case 'fan':
      return [action('toggle', 'Toggle', 'power'), action('turn_on', 'Turn On', 'power'),
        action('turn_off', 'Turn Off', 'power')];
    case 'scene':
      return [action('activate', 'Activate Scene', 'play')];
    case 'climate': {
      const items = [];
      const modes = Array.isArray(attr.hvac_modes) ? attr.hvac_modes : [];
      if (feature(entity, CLIMATE.TARGET_TEMPERATURE)) {
        const min = number(attr.min_temp) ?? 0;
        const max = number(attr.max_temp) ?? 100;
        const step = number(attr.target_temp_step) || 0.5;
        const target = number(attr.temperature) ?? number(attr.current_temperature) ?? min;
        items.push(action('temp_up', 'Increase Temperature', 'add'));
        items.push(action('temp_down', 'Decrease Temperature', 'remove'));
        items.push(action('set_temperature', 'Set Temperature', 'weather',
          numberParameter('temperature', 'Target temperature', min, max, target, step)));
      }
      for (const mode of ['off', 'heat', 'cool', 'auto']) {
        if (modes.includes(mode)) items.push(action(`mode:${mode}`,
          mode === 'off' ? 'Turn Off' : mode[0].toUpperCase() + mode.slice(1),
          mode === 'off' ? 'power' : 'weather'));
      }
      return items;
    }
    case 'cover': {
      const items = [];
      if (feature(entity, COVER.OPEN)) items.push(action('open', 'Open', 'window'));
      if (feature(entity, COVER.CLOSE)) items.push(action('close', 'Close', 'window'));
      if (feature(entity, COVER.STOP)) items.push(action('stop', 'Stop', 'close'));
      if (feature(entity, COVER.SET_POSITION)) {
        items.push(action('set_position', 'Set Position', 'window',
          numberParameter('position', 'Open position (%)', 0, 100,
            number(attr.current_position) ?? 50)));
      }
      return items;
    }
    case 'media_player': {
      const items = [];
      if (entity.state === 'playing' && feature(entity, MEDIA.PAUSE)) {
        items.push(action('pause', 'Pause', 'play'));
      } else if (feature(entity, MEDIA.PLAY)) {
        items.push(action('play', 'Play', 'play'));
      }
      if (feature(entity, MEDIA.NEXT)) items.push(action('next', 'Next', 'play'));
      if (feature(entity, MEDIA.PREVIOUS)) items.push(action('previous', 'Previous', 'reply'));
      if (feature(entity, MEDIA.VOLUME_SET) || feature(entity, MEDIA.VOLUME_STEP)) {
        items.push(action('volume_up', 'Volume Up', 'add'));
        items.push(action('volume_down', 'Volume Down', 'remove'));
      }
      if (feature(entity, MEDIA.VOLUME_MUTE)) {
        items.push(action('mute', attr.is_volume_muted ? 'Unmute' : 'Mute', 'music'));
      }
      if (feature(entity, MEDIA.TURN_ON)) items.push(action('turn_on', 'Turn On', 'power'));
      if (feature(entity, MEDIA.TURN_OFF)) items.push(action('turn_off', 'Turn Off', 'power'));
      return items;
    }
    case 'lock':
      return entity.state === 'locked'
        ? [action('unlock', 'Unlock', 'unlock', null, {
          confirm: { title: `Unlock ${entity.name}?`, message: 'This will unlock the device.', confirmLabel: 'Unlock' },
        })]
        : [action('lock', 'Lock', 'lock')];
    case 'button':
      return [action('press', 'Press', 'bolt')];
    case 'script':
      return [action('run', 'Run Script', 'run')];
    case 'automation':
      return [action('trigger', 'Trigger Automation', 'run')];
    default:
      return [];
  }
}

function numericParameter(parameters, key, min, max) {
  const value = number(parameters && parameters[key]);
  if (value === null || value < min || value > max) throw new Error('Enter a value in the allowed range');
  return value;
}

function resolveAction(entity, id, parameters = {}) {
  if (!entityActions(entity).some((item) => item.id === id)) throw new Error('Action is unavailable');
  const { domain, attributes: attr } = entity;
  if (id === 'activate') return { domain: 'scene', service: 'turn_on' };
  if (id === 'press') return { domain: 'button', service: 'press' };
  if (id === 'run') return { domain: 'script', service: 'turn_on' };
  if (id === 'trigger') return { domain: 'automation', service: 'trigger' };
  if (id === 'toggle') return { domain, service: 'toggle' };
  if (id === 'turn_on' || id === 'turn_off') return { domain, service: id };
  if (id === 'brightness') {
    return { domain: 'light', service: 'turn_on', data: {
      brightness_pct: numericParameter(parameters, 'brightness', 1, 100),
    } };
  }
  if (id === 'color_temperature') {
    return { domain: 'light', service: 'turn_on', data: {
      color_temp_kelvin: numericParameter(parameters, 'kelvin',
        number(attr.min_color_temp_kelvin) || 2000, number(attr.max_color_temp_kelvin) || 6500),
    } };
  }
  if (id === 'color') {
    const hex = String(parameters.color || '');
    if (!/^#[0-9a-fA-F]{6}$/.test(hex)) throw new Error('Choose a valid color');
    return { domain: 'light', service: 'turn_on', data: {
      rgb_color: [1, 3, 5].map((start) => parseInt(hex.slice(start, start + 2), 16)),
    } };
  }
  if (id === 'temp_up' || id === 'temp_down' || id === 'set_temperature') {
    const min = number(attr.min_temp) ?? 0;
    const max = number(attr.max_temp) ?? 100;
    const step = number(attr.target_temp_step) || 0.5;
    const current = number(attr.temperature);
    if (id !== 'set_temperature' && current === null) throw new Error('Target temperature is unknown');
    const target = id === 'set_temperature'
      ? numericParameter(parameters, 'temperature', min, max)
      : Number((current + (id === 'temp_up' ? step : -step)).toFixed(3));
    if (target < min || target > max) throw new Error('Target temperature is at its limit');
    return { domain: 'climate', service: 'set_temperature', data: { temperature: target } };
  }
  if (id.startsWith('mode:')) {
    return { domain: 'climate', service: 'set_hvac_mode', data: { hvac_mode: id.slice(5) } };
  }
  if (id === 'open' || id === 'close' || id === 'stop') {
    return { domain: 'cover', service: `${id}_cover` };
  }
  if (id === 'set_position') {
    return { domain: 'cover', service: 'set_cover_position', data: {
      position: numericParameter(parameters, 'position', 0, 100),
    } };
  }
  const mediaServices = {
    play: 'media_play', pause: 'media_pause', next: 'media_next_track',
    previous: 'media_previous_track', volume_up: 'volume_up', volume_down: 'volume_down',
  };
  if (mediaServices[id]) return { domain: 'media_player', service: mediaServices[id] };
  if (id === 'mute') return { domain: 'media_player', service: 'volume_mute', data: {
    is_volume_muted: !Boolean(attr.is_volume_muted),
  } };
  if (id === 'unlock' || id === 'lock') return { domain: 'lock', service: id };
  throw new Error('Unsupported action');
}

module.exports = { defaultAction, entityActions, resolveAction };
