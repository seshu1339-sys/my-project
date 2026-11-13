'use strict';
// Staff hexagon cells for all of India (owner, 13 Nov 2026), with no database in them.
//
// The grid is H3 (hexagons, the free h3-js library; nothing is called over the internet). Every place is in exactly one resolution-8
// hexagon (about 0.9 km across). A staff cell is that hexagon (a "1 km" cell, dense cities), its resolution-7 parent ("2 km", about
// 2.4 km across, towns) or its resolution-6 grandparent ("5 km", about 6.4 km across, villages and fields). Which one is decided once,
// offline, from WorldPop's population density (tools/hex/build-india-hex-levels.mjs) and kept in data/india-hex-levels.txt (about 270 KB,
// inside the functions code): over 4,000 people per km2 = 1 km, 800 to 4,000 = 2 km, under 800 = 5 km. A cell is always every 1 km
// hexagon under it, so each place belongs to exactly one cell: no gaps, no overlaps. The admin never sets a size.
//
// Population data: WorldPop (www.worldpop.org), CC BY 4.0.
const {readFileSync} = require('node:fs');
const {join} = require('node:path');
const h3 = require('h3-js');

const SIZE_OF_RES = {8: 1, 7: 2, 6: 5};
const RES_OF_SIZE = {1: 8, 2: 7, 5: 6};
// India with a margin (the mainland and the islands), as functions/modules/staff-areas/blocks.js.
const INDIA = {minLat: 6, maxLat: 37.6, minLng: 68, maxLng: 97.5};
const LEVELS_FILE = join(__dirname, 'data', 'india-hex-levels.txt');

let table = null;
/// The resolution-6 areas that are not one 5 km cell, with the mask of their parts split into 1 km cells. Read once per server.
function levels() {
  if (table) return table;
  const read = new Map();
  for (const raw of readFileSync(LEVELS_FILE, 'utf8').split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const [key, mask] = line.split(/\s+/);
    read.set(`${key}ffffff`, parseInt(mask, 16));
  }
  table = read;
  return table;
}

const finite = v => typeof v === 'number' && Number.isFinite(v);
const inIndia = (lat, lng) => finite(lat) && finite(lng) && lat >= INDIA.minLat && lat <= INDIA.maxLat && lng >= INDIA.minLng && lng <= INDIA.maxLng;

/// The staff cell a 1 km hexagon belongs to.
function cellOfHex(hex8) {
  const area = h3.cellToParent(hex8, 6);
  const mask = levels().get(area);
  if (mask === undefined) return area;
  const part = h3.cellToParent(hex8, 7);
  const i = h3.cellToChildren(area, 7).sort().indexOf(part);
  return mask & (1 << i) ? hex8 : part;
}

/// The staff cell of a place in India.
function cellAt(lat, lng) {
  if (!inIndia(lat, lng)) throw Error('This place is outside India.');
  return cellOfHex(h3.latLngToCell(lat, lng, 8));
}

/// 1, 2 or 5 (km), the cell's size name.
const sizeKm = cell => SIZE_OF_RES[h3.getResolution(cell)];

/// True when [cell] is a real staff cell of this grid (not, for example, a 2 km cell inside a 5 km one).
function isCell(cell) {
  if (typeof cell !== 'string' || !/^[0-9a-f]{15}$/.test(cell) || !h3.isValidCell(cell)) return false;
  const res = h3.getResolution(cell);
  if (!SIZE_OF_RES[res]) return false;
  return cellOfHex(h3.cellToCenterChild(cell, 8)) === cell;
}

/// The centre of a cell as [lat, lng].
const centerOf = cell => h3.cellToLatLng(cell);

/// Distance in km between two [lat, lng] places.
const distanceKm = (a, b) => h3.greatCircleDistance(a, b, 'km');

const round5 = v => Math.round(v * 1e5) / 1e5;
/// The outline of a cell, [[lat, lng], ...]: the edge of all its 1 km hexagons (a 2 km or 5 km cell is slightly zig-zag where it meets
/// cells of other sizes; that is what makes them fit with no gaps).
function outlineOf(cell) {
  const hexes = h3.getResolution(cell) === 8 ? [cell] : h3.cellToChildren(cell, 8);
  const polygons = h3.cellsToMultiPolygon(hexes, false);
  return polygons[0][0].map(([lat, lng]) => [round5(lat), round5(lng)]);
}

// How many 1 km hexagons around the place to look at for the cells nearby: about two rings of cells of the place's own size.
const RINGS_OF_RES = {8: 4, 7: 8, 6: 16};
/// The place's cell first, then the cells around it.
function cellsNear(lat, lng) {
  if (!inIndia(lat, lng)) throw Error('This place is outside India.');
  const hex = h3.latLngToCell(lat, lng, 8);
  const own = cellOfHex(hex);
  const seen = new Set([own]);
  for (const near of h3.gridDisk(hex, RINGS_OF_RES[h3.getResolution(own)])) seen.add(cellOfHex(near));
  return [...seen];
}

// Area codes: "HX" + the size + "-" + the cell's number in Crockford base 32 (no I, L, O, U): HX1-1F3KQ9M (1 km), HX2-9K2QXA (2 km),
// HX5-B7R2Q (5 km). The same cell always has the same code, and the code gives the cell back.
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
function codeOf(cell) {
  const res = h3.getResolution(cell);
  const index = BigInt(`0x${cell}`);
  let value = (index >> 45n) & 0x7fn;
  for (let digit = 1; digit <= res; digit++) value = value * 8n + ((index >> BigInt((15 - digit) * 3)) & 7n);
  const length = Math.ceil((7 + 3 * res) / 5);
  let text = '';
  for (let i = 0; i < length; i++) {
    text = ALPHABET[Number(value & 31n)] + text;
    value >>= 5n;
  }
  return `HX${SIZE_OF_RES[res]}-${text}`;
}

/// The cell of an area code, or null.
function cellOfCode(code) {
  const match = /^HX([125])-([0-9A-HJKMNP-TV-Z]+)$/.exec(String(code || '').trim().toUpperCase());
  if (!match) return null;
  const res = RES_OF_SIZE[match[1]];
  if (match[2].length !== Math.ceil((7 + 3 * res) / 5)) return null;
  let value = 0n;
  for (const ch of match[2]) value = value * 32n + BigInt(ALPHABET.indexOf(ch));
  let index = (1n << 59n) | (BigInt(res) << 52n);
  for (let digit = 15; digit >= 1; digit--) {
    const bits = digit > res ? 7n : value & 7n;
    if (digit <= res) value >>= 3n;
    index |= bits << BigInt((15 - digit) * 3);
  }
  if (value > 0x7fn) return null;
  index |= value << 45n;
  const cell = index.toString(16);
  return isCell(cell) ? cell : null;
}

module.exports = {cellAt, cellOfHex, cellsNear, isCell, sizeKm, centerOf, outlineOf, distanceKm, codeOf, cellOfCode, inIndia, levels, SIZE_OF_RES};
