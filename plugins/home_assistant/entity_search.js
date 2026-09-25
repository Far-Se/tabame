'use strict';

const { normal } = require('./entity_model');

const FILTERS = {
  light: ['light'], lights: ['light'],
  switch: ['switch'], switches: ['switch'],
  scene: ['scene'], scenes: ['scene'],
  climate: ['climate'],
  cover: ['cover'], covers: ['cover'],
  media: ['media_player'], media_players: ['media_player'],
  sensor: ['sensor', 'binary_sensor'], sensors: ['sensor', 'binary_sensor'],
  lock: ['lock'], locks: ['lock'],
  all: null,
};

function parseQuery(raw) {
  const value = String(raw || '').trim();
  const [first, ...rest] = value.split(/\s+/);
  const key = first && first.toLowerCase();
  if (key === 'favorites' || key === 'recent') {
    return { domains: null, text: rest.join(' '), collection: key, filter: key };
  }
  if (Object.prototype.hasOwnProperty.call(FILTERS, key)) {
    return { domains: FILTERS[key], text: rest.join(' '), collection: null, filter: key };
  }
  return { domains: null, text: value, collection: null, filter: null };
}

function editDistance(a, b, max = 2) {
  if (Math.abs(a.length - b.length) > max) return max + 1;
  let previous = Array.from({ length: b.length + 1 }, (_, index) => index);
  for (let i = 1; i <= a.length; i++) {
    const current = [i];
    for (let j = 1; j <= b.length; j++) {
      current[j] = Math.min(
        current[j - 1] + 1,
        previous[j] + 1,
        previous[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1),
      );
    }
    if (Math.min(...current) > max) return max + 1;
    previous = current;
  }
  return previous[b.length];
}

function fuzzyScore(query, entity) {
  const s = entity.search;
  if (s.name === query) return 1000;
  if (s.name.startsWith(query)) return 850;
  if (s.name.includes(query)) return 700;

  const words = query.split(' ').filter(Boolean);
  const haystack = [s.name, s.id, s.domain, s.area, s.device].join(' ');
  if (words.every((word) => haystack.includes(word))) {
    if (words.every((word) => s.name.includes(word))) return 620;
    if (s.id.includes(query)) return 510;
    if (s.area.includes(query) || s.device.includes(query)) return 440;
    return 380;
  }

  if (query.length < 3) return -1;
  const candidates = s.words;
  let total = 0;
  for (const word of words) {
    const best = Math.min(...candidates.map((candidate) => editDistance(word, candidate, 2)));
    if (best > 2) return -1;
    total += best;
  }
  return 180 - total * 20;
}

function searchEntities(entities, rawQuery, favorites, recent, showUnavailable) {
  const { domains, text, collection } = parseQuery(rawQuery);
  const query = normal(text);
  const recentRanks = new Map(recent.map((id, index) => [id, index]));
  const results = [];
  for (const entity of entities.values()) {
    if (domains && !domains.includes(entity.domain)) continue;
    if (collection === 'favorites' && !favorites.has(entity.id)) continue;
    if (collection === 'recent' && !recentRanks.has(entity.id)) continue;
    if (!showUnavailable && ['unavailable', 'unknown'].includes(entity.state)) continue;
    const base = query ? fuzzyScore(query, entity) : 0;
    if (base < 0) continue;
    const favoriteBoost = favorites.has(entity.id) ? 70 : 0;
    const recentRank = recentRanks.get(entity.id);
    const recentBoost = recentRank === undefined ? 0 : Math.max(1, 35 - recentRank);
    results.push({ entity, score: base + favoriteBoost + recentBoost });
  }
  results.sort((left, right) => right.score - left.score ||
    left.entity.name.localeCompare(right.entity.name));
  return results.map((entry) => entry.entity);
}

module.exports = { parseQuery, searchEntities };
