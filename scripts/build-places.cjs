// Builds the places directory in web/data/: one file per state or union territory,
// places.<state>.v1.json (every post office: name, district, pincode, coordinates),
// and places.index.v1.json (the list of states with their districts, map box and
// pincode prefixes), from India Post's "All India Pincode Directory" (data.gov.in,
// open data under GODL-India). A phone only downloads the states it needs.
//
//   node scripts/build-places.cjs <pincode.csv> [out-dir]
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
const outDir = process.argv[3] || path.join(__dirname, '../web/data');
if (!input) {
  console.error('usage: node scripts/build-places.cjs <pincode.csv> [out-dir]');
  process.exit(1);
}

// The source spells states in capitals; these two are long enough to want a fixed name.
const STATE_FIXES = {
  'THE DADRA AND NAGAR HAVELI AND DAMAN AND DIU': 'Dadra and Nagar Haveli and Daman and Diu',
  'ANDAMAN AND NICOBAR ISLANDS': 'Andaman and Nicobar Islands',
  'JAMMU AND KASHMIR': 'Jammu and Kashmir',
};
const stateName = (raw) => {
  const key = raw.trim().toUpperCase();
  if (!key) return '';
  return STATE_FIXES[key] || titleCase(key);
};
const slug = (name) => name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
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
// Rough bounding box of India; coordinates outside it are typos. (A district's own
// outliers are removed further down.)
const BOX = { latMin: 6.5, latMax: 37.2, lngMin: 68, lngMax: 97.5 };

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
  const stateRaw = stateName(cells[C.state]);
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
const source = 'India Post, All India Pincode Directory (data.gov.in), Government Open Data License - India';
const built = new Date().toISOString().slice(0, 10);
const zlib = require('node:zlib');
fs.mkdirSync(outDir, { recursive: true });
// Files of an earlier build (a state that is gone, the old single file) must not linger.
for (const f of fs.readdirSync(outDir)) if (/^places.[a-z0-9-]+.v1.json$/.test(f)) fs.rmSync(path.join(outDir, f));

const index = { v: 1, source, built, states: [] };
let totalBytes = 0, totalGzip = 0;
const sizes = {};
const stateOrder = states.map((name, i) => ({ name, i })).sort((a, b) => a.name.localeCompare(b.name));
for (const { name, i: stateIdx } of stateOrder) {
  const localDistricts = []; // [name, 0]
  const localOf = new Map();
  districts.forEach(([dName, dState], di) => {
    if (dState === stateIdx) { localOf.set(di, localDistricts.length); localDistricts.push([dName, 0]); }
  });
  const mine = places.filter((p) => localOf.has(p.district));
  const file = {
    v: 1, source, built,
    states: [name],
    districts: localDistricts,
    // [name, district, pincode, kind (0 sub office / 1 village branch / 2 head office), lat, lng (0 = unknown), town it belongs to (only when different from name)]
    places: mine.map((r) => {
      const row = [r.name, localOf.get(r.district), r.pin, r.head ? 2 : r.town ? 0 : 1, r.lat ? r3(r.lat) : 0, r.lng ? r3(r.lng) : 0];
      const parent = townOfPin.get(r.pin);
      if (parent && parent !== r.name) row.push(parent);
      return row;
    }),
  };
  const fileName = `places.${slug(name)}.v1.json`;
  const text = JSON.stringify(file);
  fs.writeFileSync(path.join(outDir, fileName), text);
  const located = mine.filter((p) => p.lat);
  const pins = [...new Set(mine.map((p) => p.pin))];
  index.states.push({
    name,
    file: fileName,
    places: mine.length,
    districts: localDistricts.map((d) => d[0]),
    // [south, west, north, east] of the offices that have coordinates, for choosing the state of a GPS fix
    box: located.length ? [Math.min(...located.map((p) => p.lat)), Math.min(...located.map((p) => p.lng)), Math.max(...located.map((p) => p.lat)), Math.max(...located.map((p) => p.lng))].map(r3) : [0, 0, 0, 0],
    // the first two digits of the state's pincodes, for choosing the state of a typed pincode
    pinPrefixes: [...new Set(pins.map((p) => Math.floor(p / 10000)))].sort((a, b) => a - b),
  });
  const gz = zlib.gzipSync(text, { level: 9 }).length;
  sizes[name] = { places: mine.length, kb: Math.round(text.length / 1024), gzipKb: Math.round(gz / 1024) };
  totalBytes += text.length; totalGzip += gz;
}
fs.writeFileSync(path.join(outDir, 'places.index.v1.json'), JSON.stringify(index));
console.log(JSON.stringify({
  outDir, states: index.states.length, places: places.length, districts: districts.length,
  pincodes: new Set(places.map((p) => p.pin)).size, withCoordinates: places.filter((p) => p.lat).length, dropped,
  totalMB: +(totalBytes / 1048576).toFixed(2), totalGzipMB: +(totalGzip / 1048576).toFixed(2), sizes,
}, null, 1));
