// Builds web/data/places.v1.json: every post office of Andhra Pradesh and
// Telangana (name, district, pincode, coordinates) from India Post's "All India
// Pincode Directory" (data.gov.in, open data under GODL-India).
//
//   node scripts/build-places.cjs <pincode.csv> [out.json]
//
// The CSV columns are CircleName, RegionName, DivisionName, OfficeName,
// Pincode, OfficeType, Delivery, District, StateName, Latitude, Longitude.
// The output is deliberately compact (arrays, a district table, 3-decimal
// coordinates) because it is fetched by customers' phones, but only when they
// open the location dialog -- never with the home page. The file name carries
// the format version: bump it (and the app's constant) when the shape changes,
// since Hosting serves it with a one-year cache.
const fs = require('node:fs');
const path = require('node:path');

const input = process.argv[2];
const output = process.argv[3] || path.join(__dirname, '../web/data/places.v1.json');
if (!input) {
  console.error('usage: node scripts/build-places.cjs <pincode.csv> [out.json]');
  process.exit(1);
}

const STATES = { 'ANDHRA PRADESH': 'Andhra Pradesh', TELANGANA: 'Telangana' };
// The source file spells a few districts in ways nobody searches for.
const DISTRICT_FIXES = {
  VISAKHAPATANAM: 'Visakhapatnam',
  'Y.S.R.': 'YSR Kadapa',
  'SPSR NELLORE': 'Nellore',
  'MEDCHAL MALKAJGIRI': 'Medchal-Malkajgiri',
  'JAYASHANKAR BHUPALAPALLY': 'Jayashankar Bhupalpally',
  'KUMURAM BHEEM ASIFABAD': 'Komaram Bheem Asifabad',
  'RAJANNA SIRCILLA': 'Rajanna Sircilla',
  'WARANGAL RURAL': 'Warangal Rural',
  'WARANGAL URBAN': 'Warangal Urban',
};
// Rough bounding box of the two states; coordinates outside it are typos.
const BOX = { latMin: 12.4, latMax: 19.95, lngMin: 76.7, lngMax: 84.9 };

function parseCsvLine(line) {
  const out = [];
  let cell = '', quoted = false;
  for (const ch of line) {
    if (ch === '"') quoted = !quoted;
    else if (ch === ',' && !quoted) { out.push(cell); cell = ''; }
    else cell += ch;
  }
  out.push(cell);
  return out;
}

const WORD_KEEP_UPPER = new Set(['IIT', 'IIIT', 'NIT', 'APSP', 'RTC', 'HAL', 'NTPC', 'ONGC', 'BHEL', 'RS', 'GPO', 'II', 'III']);
function titleCase(text) {
  return text
    .toLowerCase()
    .replace(/(^|[\s(/\-])([a-z])/g, (m, a, b) => a + b.toUpperCase())
    .replace(/\b[A-Za-z]+\b/g, (w) => (WORD_KEEP_UPPER.has(w.toUpperCase()) ? w.toUpperCase() : w));
}

// "Rajahmundry H.O", "Sriramnagar S.O", "Peddakotla B.O", "IIT HYDERABAD SO",
// "Narayana(Nellore) B.O" -> the place's own name.
function cleanName(raw) {
  let name = raw.trim().replace(/\s+/g, ' ');
  name = name.replace(/\s*\b(B\.?O\.?|S\.?O\.?|H\.?O\.?|G\.?P\.?O\.?|NDBO)\s*$/i, '').trim();
  name = name.replace(/\s*\(\s*/g, ' (').replace(/\s*\)\s*/g, ')').trim();
  if (name === name.toUpperCase() || name === name.toLowerCase()) name = titleCase(name);
  return name;
}

function districtName(raw) {
  const key = raw.trim();
  if (DISTRICT_FIXES[key]) return DISTRICT_FIXES[key];
  if (key === key.toUpperCase() || key === key.toLowerCase()) return titleCase(key);
  return key;
}

function km(aLat, aLng, bLat, bLng) {
  const r = Math.PI / 180;
  const dLat = (bLat - aLat) * r, dLng = (bLng - aLng) * r;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(aLat * r) * Math.cos(bLat * r) * Math.sin(dLng / 2) ** 2;
  return 12742 * Math.asin(Math.sqrt(h));
}

const lines = fs.readFileSync(input, 'utf8').split(/\r?\n/).filter(Boolean);
const header = parseCsvLine(lines[0]);
const col = (name) => header.indexOf(name);
const C = { office: col('OfficeName'), pin: col('Pincode'), type: col('OfficeType'), district: col('District'), state: col('StateName'), lat: col('Latitude'), lng: col('Longitude') };
if (Object.values(C).some((i) => i < 0)) throw new Error(`Unexpected CSV header: ${header}`);

const states = [];
const districts = []; // [name, stateIndex]
const districtIndex = new Map();
let dropped = { notState: 0, junk: 0, badCoords: 0, duplicates: 0 };
const rows = [];
for (const line of lines.slice(1)) {
  const cells = parseCsvLine(line);
  const stateRaw = STATES[cells[C.state].trim().toUpperCase()];
  if (!stateRaw) { dropped.notState++; continue; }
  const pin = cells[C.pin].trim();
  const rawName = cells[C.office];
  if (!/^[1-9]\d{5}$/.test(pin) || pin === '999999' || /\bTEST\b/i.test(rawName)) { dropped.junk++; continue; }
  let stateIdx = states.indexOf(stateRaw);
  if (stateIdx < 0) { states.push(stateRaw); stateIdx = states.length - 1; }
  const dName = districtName(cells[C.district]);
  const dKey = `${stateIdx}|${dName}`;
  if (!districtIndex.has(dKey)) { districtIndex.set(dKey, districts.length); districts.push([dName, stateIdx]); }
  let lat = parseFloat(cells[C.lat]), lng = parseFloat(cells[C.lng]);
  if (!(lat >= BOX.latMin && lat <= BOX.latMax && lng >= BOX.lngMin && lng <= BOX.lngMax)) {
    if (!Number.isNaN(lat) && lat !== 0) dropped.badCoords++;
    lat = 0; lng = 0;
  }
  rows.push({ name: cleanName(rawName), district: districtIndex.get(dKey), pin: Number(pin), town: cells[C.type].trim() !== 'BO', head: cells[C.type].trim() === 'HO', lat, lng });
}

// A coordinate far from the rest of its district is a data-entry slip.
const byDistrict = new Map();
for (const r of rows) if (r.lat) (byDistrict.get(r.district) || byDistrict.set(r.district, []).get(r.district)).push(r);
for (const list of byDistrict.values()) {
  const median = (key) => list.map((r) => r[key]).sort((a, b) => a - b)[Math.floor(list.length / 2)];
  const mLat = median('lat'), mLng = median('lng');
  // Keep what lies within a few "typical distances" of the district's middle: a small
  // district (Hyderabad) gets a tight limit, a large one (Kurnool) a wide one.
  const distances = list.map((r) => km(mLat, mLng, r.lat, r.lng)).sort((a, b) => a - b);
  const limit = Math.max(15, 3 * distances[Math.floor(distances.length / 2)]);
  for (const r of list) if (km(mLat, mLng, r.lat, r.lng) > limit) { r.lat = 0; r.lng = 0; dropped.badCoords++; }
}

// Likewise inside one pincode (a few km across): an office tens of km from the
// median of its pincode-mates is mis-geocoded.
const byPin = new Map();
for (const r of rows) if (r.lat) (byPin.get(r.pin) || byPin.set(r.pin, []).get(r.pin)).push(r);
for (const list of byPin.values()) {
  if (list.length < 3) continue;
  const median = (key) => list.map((r) => r[key]).sort((a, b) => a - b)[Math.floor(list.length / 2)];
  const mLat = median('lat'), mLng = median('lng');
  for (const r of list) if (km(mLat, mLng, r.lat, r.lng) > 30) { r.lat = 0; r.lng = 0; dropped.badCoords++; }
}

// A head office whose own coordinates were wrong (and so dropped) takes the median
// of its pincode-mates', so the offices around it can still find it.
for (const list of byPin.values()) void list;
const matesByPin = new Map();
for (const r of rows) if (r.lat) (matesByPin.get(r.pin) || matesByPin.set(r.pin, []).get(r.pin)).push(r);
for (const r of rows) {
  if (!r.head || r.lat) continue;
  const mates = matesByPin.get(r.pin);
  if (!mates || !mates.length) continue;
  const mid = (key) => mates.map((m) => m[key]).sort((a, b) => a - b)[Math.floor(mates.length / 2)];
  r.lat = mid('lat'); r.lng = mid('lng');
}

// One entry per (name, pincode); keep the one with coordinates / the town kind.
const unique = new Map();
for (const r of rows) {
  const key = `${r.name.toLowerCase()}|${r.pin}`;
  const have = unique.get(key);
  if (!have) { unique.set(key, r); continue; }
  dropped.duplicates++;
  if ((!have.lat && r.lat) || (!have.town && r.town)) unique.set(key, { ...r, town: have.town || r.town, head: have.head || r.head });
}
const places = [...unique.values()];

// The town an office belongs to -- offers are matched on it:
//  1. the head office of its pincode (Alcot Gardens -> Rajahmundry);
//  2. else, when the pincode's first sub office with coordinates lies within 12 km of a
//     head office, that head office (a city's outlying sub offices: Buckinghampet ->
//     Vijayawada, a university campus -> Rajahmundry);
//  3. else the pincode's first sub office alphabetically (Narsipatnam).
// Cities with several head offices: the post office names of one city.
const HEAD_ALIASES = {
  Buckinghampet: 'Vijayawada',
  'Waltair R S': 'Visakhapatnam',
  Charminar: 'Hyderabad',
  Khairatabad: 'Hyderabad',
  'Stn. Kachiguda': 'Hyderabad',
  Trimulgherry: 'Secunderabad',
};
const heads = places.filter((p) => p.head && p.lat && !HEAD_ALIASES[p.name]);
const townOfPin = new Map();
for (const r of places.filter((p) => p.town && p.head)) townOfPin.set(r.pin, HEAD_ALIASES[r.name] || r.name);
const subsByPin = new Map();
for (const r of [...places].filter((p) => p.town && !p.head).sort((a, b) => a.name.localeCompare(b.name))) {
  (subsByPin.get(r.pin) || subsByPin.set(r.pin, []).get(r.pin)).push(r);
}
for (const [pin, subs] of subsByPin) {
  if (townOfPin.has(pin)) continue;
  const located = subs.find((s) => s.lat);
  let best = null, bestKm = 12;
  if (located) for (const h of heads) {
    const d = km(located.lat, located.lng, h.lat, h.lng);
    if (d <= bestKm) { best = h; bestKm = d; }
  }
  townOfPin.set(pin, best ? best.name : subs[0].name);
}

places.sort((a, b) => a.district - b.district || a.name.localeCompare(b.name) || a.pin - b.pin);
const r3 = (n) => Math.round(n * 1000) / 1000;
const out = {
  v: 1,
  source: 'India Post, All India Pincode Directory (data.gov.in), Government Open Data License - India',
  built: new Date().toISOString().slice(0, 10),
  states,
  districts,
  // [name, district, pincode, kind (0 sub office / 1 village branch / 2 head office), lat, lng (0 = unknown), town it belongs to (only when different from name)]
  places: places.map((r) => {
    const row = [r.name, r.district, r.pin, r.head ? 2 : r.town ? 0 : 1, r.lat ? r3(r.lat) : 0, r.lng ? r3(r.lng) : 0];
    const parent = townOfPin.get(r.pin);
    if (parent && parent !== r.name) row.push(parent);
    return row;
  }),
};
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, JSON.stringify(out));
const zlib = require('node:zlib');
const buf = fs.readFileSync(output);
console.log(JSON.stringify({
  output, places: out.places.length, towns: places.filter((p) => p.town).length, villages: places.filter((p) => !p.town).length,
  districts: districts.length, states, pincodes: new Set(places.map((p) => p.pin)).size,
  withCoordinates: places.filter((p) => p.lat).length, dropped,
  bytes: buf.length, gzipBytes: zlib.gzipSync(buf, { level: 9 }).length, brotliBytes: zlib.brotliCompressSync(buf).length,
}, null, 1));
