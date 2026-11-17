'use strict';
// Automatic staff areas (owner, 7 Nov 2026), with no database in them.
//
// All of India is divided into fixed blocks by a calculation from latitude and longitude: a block is BLOCK_DEG x BLOCK_DEG degrees
// (about 1.1 km north-south). Nothing is stored for India in advance; a block gets a document only when a staff member registers it.
//
// The staff member taps a centre on the map. The centre snaps to its block's middle. The server counts the buildings within
// SAMPLE_RADIUS_M of it in free OpenStreetMap data (Overpass), turns that into buildings per square kilometre, and the admin's density
// bands give the radius: dense city small, villages big. The staff member never sets the radius.
const BLOCK_DEG = 0.01;
const SAMPLE_RADIUS_M = 1000;
// India with a margin (the mainland and the islands).
const INDIA = {minLat: 6, maxLat: 37.6, minLng: 68, maxLng: 97.5};
// The owner's starting values: more than 1000 buildings per km2 = 1 km; 300 to 1000 = 2 km; 50 to 300 = 4 km (3 to 5); fewer = 15 km.
const DEFAULT_BANDS = [
  {minPerKm2: 1000, radiusKm: 1},
  {minPerKm2: 300, radiusKm: 2},
  {minPerKm2: 50, radiusKm: 4},
  {minPerKm2: 0, radiusKm: 15},
];
const MIN_RADIUS_KM = 0.5;
const MAX_RADIUS_KM = 30;

const num = v => (typeof v === 'number' && Number.isFinite(v) ? v : null);

function inIndia(lat, lng) {
  return num(lat) !== null && num(lng) !== null && lat >= INDIA.minLat && lat <= INDIA.maxLat && lng >= INDIA.minLng && lng <= INDIA.maxLng;
}

/// The block of a place: its id ("B1766_8261") and its middle, which becomes the area's centre.
function blockOf(lat, lng) {
  if (!inIndia(lat, lng)) throw Error('Choose a place in India on the map.');
  const row = Math.floor(lat / BLOCK_DEG);
  const col = Math.floor(lng / BLOCK_DEG);
  const round = v => Math.round(v * 1e6) / 1e6;
  return {blockId: `B${row}_${col}`, latitude: round((row + 0.5) * BLOCK_DEG), longitude: round((col + 0.5) * BLOCK_DEG)};
}

/// Buildings per square kilometre from a count within [radiusM] metres.
const densityPerKm2 = (buildings, radiusM = SAMPLE_RADIUS_M) => Math.round(buildings / (Math.PI * (radiusM / 1000) ** 2));

/// The radius for a density: the first band (highest first) whose minimum the density reaches.
function radiusFor(density, bands = DEFAULT_BANDS) {
  for (const band of bands) if (density >= band.minPerKm2) return band.radiusKm;
  return bands.at(-1).radiusKm;
}

/// The admin's bands: exactly 4, from the densest down, each minimum lower than the one above, the last 0, the radius 0.5 to 30 km.
function validateBands(value) {
  if (!Array.isArray(value) || value.length !== 4) throw Error('Give the 4 density bands.');
  const bands = value.map(b => ({minPerKm2: num(b?.minPerKm2), radiusKm: num(b?.radiusKm)}));
  bands[3].minPerKm2 = 0;
  for (const [i, b] of bands.entries()) {
    if (b.minPerKm2 === null || b.minPerKm2 < 0 || !Number.isInteger(b.minPerKm2)) throw Error('Enter the buildings per km² as whole numbers.');
    if (b.radiusKm === null || b.radiusKm < MIN_RADIUS_KM || b.radiusKm > MAX_RADIUS_KM) throw Error(`Enter each radius from ${MIN_RADIUS_KM} to ${MAX_RADIUS_KM} km.`);
    if (i > 0 && b.minPerKm2 >= bands[i - 1].minPerKm2) throw Error('Each band needs fewer buildings than the band above it.');
    b.radiusKm = Math.round(b.radiusKm * 10) / 10;
  }
  return bands;
}

const bandsOf = value => {
  try { return validateBands(value); } catch { return DEFAULT_BANDS.map(b => ({...b})); }
};

/// The OpenStreetMap (Overpass) question: how many buildings within [radiusM] of a place.
const overpassQuery = (lat, lng, radiusM = SAMPLE_RADIUS_M) =>
  `[out:json][timeout:25];(way["building"](around:${radiusM},${lat},${lng});relation["building"](around:${radiusM},${lat},${lng}););out count;`;

/// The count from Overpass's answer.
function parseCount(json) {
  const total = Number(json?.elements?.find(e => e.type === 'count')?.tags?.total);
  if (!Number.isFinite(total) || total < 0) throw Error('The building count could not be read. Try again in a minute.');
  return total;
}

/// A clean name and town from the place the staff member searched (the map search), or plain fallbacks.
const label = (v, fallback, max = 60) => {
  const s = typeof v === 'string' ? v.trim().replace(/\s+/g, ' ').slice(0, max) : '';
  return s.length >= 2 ? s : fallback;
};

module.exports = {BLOCK_DEG, SAMPLE_RADIUS_M, DEFAULT_BANDS, INDIA, inIndia, blockOf, densityPerKm2, radiusFor, validateBands, bandsOf, overpassQuery, parseCount, label};
