// Coverage check of the staff hexagon cells (functions/hex-grid.js + functions/data/india-hex-levels.txt). Run on a computer:
//
//   node tools/hex/check-coverage.mjs [points] [shapePoints] [ind_pd_2020_1km_UNadj.tif]
//
// 1. [points] random places in India's box: each gets exactly one cell, a real cell of the grid, whose 1 km hexagons contain the place.
// 2. [shapePoints] random places (half anywhere, half in towns and cities where sizes meet): the place is inside its own cell's outline
//    and inside none of the neighbouring cells' outlines (no overlaps, no gaps, drawn as the staff app draws them).
// 3. Every area code gives its cell back, and two cells never share a code.
// 4. With the WorldPop file: the people counted (pixel area taken into account) and the cells by size.
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {dirname, join} from 'node:path';

const require = createRequire(import.meta.url);
const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const grid = require(join(root, 'functions', 'hex-grid.js'));
const h3 = require(join(root, 'functions', 'node_modules', 'h3-js'));

const POINTS = Number(process.argv[2] || 1000000);
const SHAPES = Number(process.argv[3] || 20000);
const TIF = process.argv[4];
const BOX = {minLat: 6.5, maxLat: 35.5, minLng: 68.2, maxLng: 97.4};
let seed = 20261113;
const random = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
const randomPlace = () => [BOX.minLat + random() * (BOX.maxLat - BOX.minLat), BOX.minLng + random() * (BOX.maxLng - BOX.minLng)];

// 1. One cell for every place.
const bySize = {1: 0, 2: 0, 5: 0};
const codes = new Map();
let wrong = 0;
let started = Date.now();
for (let i = 0; i < POINTS; i++) {
  const [lat, lng] = randomPlace();
  const cell = grid.cellAt(lat, lng);
  const hex = h3.latLngToCell(lat, lng, 8);
  const res = h3.getResolution(cell);
  if (!grid.isCell(cell) || h3.cellToParent(hex, res) !== cell) wrong++;
  bySize[grid.sizeKm(cell)]++;
  if (i % 50 === 0) {
    const code = grid.codeOf(cell);
    if (codes.has(code) && codes.get(code) !== cell) wrong++;
    codes.set(code, cell);
    if (grid.cellOfCode(code) !== cell) wrong++;
  }
}
console.log(`1+3. ${POINTS} random places: ${wrong} problems; places in 1 km cells ${bySize[1]}, 2 km ${bySize[2]}, 5 km ${bySize[5]} (${Date.now() - started} ms); ${codes.size} area codes checked both ways`);

// 2. The outlines: inside its own, inside no neighbour's.
const outline = cell => h3.cellsToMultiPolygon(h3.getResolution(cell) === 8 ? [cell] : h3.cellToChildren(cell, 8), false);
function inside(polygons, lat, lng) {
  let hits = 0;
  for (const rings of polygons) {
    let inPolygon = false;
    for (const ring of rings) {
      let crossing = false;
      for (let a = 0, b = ring.length - 1; a < ring.length; b = a++) {
        const [la, lo] = ring[a];
        const [lb, lob] = ring[b];
        if ((lo > lng) !== (lob > lng) && lat < ((lb - la) * (lng - lo)) / (lob - lo) + la) crossing = !crossing;
      }
      if (crossing) inPolygon = !inPolygon;
    }
    if (inPolygon) hits++;
  }
  return hits > 0;
}
const towns = [...grid.levels().keys()];
const outlines = new Map();
const shapeOf = cell => {
  if (outlines.size > 20000) outlines.clear();
  if (!outlines.has(cell)) outlines.set(cell, outline(cell));
  return outlines.get(cell);
};
let notInOwn = 0, inOther = 0, mixedEdges = 0;
started = Date.now();
for (let i = 0; i < SHAPES; i++) {
  let lat, lng;
  if (i % 2 === 0) [lat, lng] = randomPlace();
  else {
    // A place inside a town or city area (sizes meet there).
    const area = towns[Math.floor(random() * towns.length)];
    const [cLat, cLng] = h3.cellToLatLng(area);
    lat = cLat + (random() - 0.5) * 0.12;
    lng = cLng + (random() - 0.5) * 0.12;
  }
  const own = grid.cellAt(lat, lng);
  if (!inside(shapeOf(own), lat, lng)) notInOwn++;
  const neighbours = new Set(h3.gridDisk(h3.latLngToCell(lat, lng, 8), 2).map(grid.cellOfHex));
  neighbours.delete(own);
  for (const other of neighbours) {
    if (h3.getResolution(other) !== h3.getResolution(own)) mixedEdges++;
    if (inside(shapeOf(other), lat, lng)) inOther++;
  }
}
console.log(`2. ${SHAPES} places against the drawn outlines: ${notInOwn} outside their own cell, ${inOther} inside another cell; ${mixedEdges} neighbour checks across different sizes (${Date.now() - started} ms)`);

// 4. People and cells by size, from the WorldPop file.
if (TIF) {
  const {fromFile} = await import(join(root, 'tools', 'hex', 'node_modules', 'geotiff', 'dist-module', 'geotiff.js')).catch(() => import('geotiff'));
  const image = await (await fromFile(TIF)).getImage();
  const [originX, originY] = image.getOrigin();
  const [resX, resY] = image.getResolution();
  const [data] = await image.readRasters();
  const width = image.getWidth();
  let people = 0;
  for (let row = 0; row < image.getHeight(); row++) {
    const lat = originY + (row + 0.5) * resY;
    const pixelKm2 = Math.abs(resX) * 111.32 * Math.cos((lat * Math.PI) / 180) * Math.abs(resY) * 110.57;
    for (let col = 0; col < width; col++) {
      const v = data[row * width + col];
      if (v >= 0) people += v * pixelKm2;
    }
  }
  console.log(`4. People in the WorldPop file (density x pixel area): about ${(people / 1e7).toFixed(1)} crore`);
}
let five = 0, two = 0, one = 0;
console.log(`   Areas written in the file: ${towns.length} (every other area is one 5 km cell)`);
for (const [, mask] of grid.levels()) {
  for (let i = 0; i < 7; i++) if (mask & (1 << i)) one += 7; else two++;
}
console.log(`   Cells from the file: ${two} of 2 km, ${one} of 1 km`);
const failed = wrong + notInOwn + inOther;
console.log(failed ? `FAILED: ${failed} problems` : 'PASSED: every place is in exactly one cell');
process.exit(failed ? 1 : 0);
