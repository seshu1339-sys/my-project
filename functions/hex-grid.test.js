// The staff hexagon cells (functions/hex-grid.js): every place in India is in exactly one cell, sized from WorldPop's population density.
// The full check (a million places) is tools/hex/check-coverage.mjs; this one runs with every test run.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const h3 = require('h3-js');
const grid = require('./hex-grid');

let seed = 7;
const random = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
const place = () => [6.5 + random() * 29, 68.2 + random() * 29.2];

test('the size file is small and has the three sizes', () => {
  const {statSync} = require('node:fs');
  assert.ok(statSync(require('node:path').join(__dirname, 'data', 'india-hex-levels.txt')).size < 1024 * 1024, 'under 1 MB');
  assert.ok(grid.levels().size > 10000);
  // Mumbai (Dharavi) is a dense city: a 1 km cell; a village area in central India: a 5 km cell.
  assert.equal(grid.sizeKm(grid.cellAt(19.0430, 72.8540)), 1);
  assert.equal(grid.sizeKm(grid.cellAt(22.97, 79.39)), 5);
});

test('every one of 50,000 random places is in exactly one real cell', () => {
  for (let i = 0; i < 50000; i++) {
    const [lat, lng] = place();
    const cell = grid.cellAt(lat, lng);
    assert.ok(grid.isCell(cell), cell);
    assert.equal(h3.cellToParent(h3.latLngToCell(lat, lng, 8), h3.getResolution(cell)), cell);
  }
});

test('drawn outlines: a place is inside its own cell and inside no neighbour, also where sizes meet', () => {
  const inside = (ring, lat, lng) => {
    let crossing = false;
    for (let a = 0, b = ring.length - 1; a < ring.length; b = a++) {
      const [la, lo] = ring[a];
      const [lb, lob] = ring[b];
      if ((lo > lng) !== (lob > lng) && lat < ((lb - la) * (lng - lo)) / (lob - lo) + la) crossing = !crossing;
    }
    return crossing;
  };
  const exact = cell => h3.cellsToMultiPolygon(h3.getResolution(cell) === 8 ? [cell] : h3.cellToChildren(cell, 8), false)[0][0];
  const towns = [...grid.levels().keys()];
  for (let i = 0; i < 600; i++) {
    const [cLat, cLng] = h3.cellToLatLng(towns[Math.floor(random() * towns.length)]);
    const lat = cLat + (random() - 0.5) * 0.1;
    const lng = cLng + (random() - 0.5) * 0.1;
    const own = grid.cellAt(lat, lng);
    assert.ok(inside(exact(own), lat, lng), `inside its own cell ${own}`);
    for (const other of new Set(h3.gridDisk(h3.latLngToCell(lat, lng, 8), 1).map(grid.cellOfHex))) {
      if (other !== own) assert.equal(inside(exact(other), lat, lng), false, `not inside ${other}`);
    }
  }
});

test('area codes: the same cell always has the same code, and the code gives the cell back', () => {
  const seen = new Map();
  for (let i = 0; i < 3000; i++) {
    const cell = grid.cellAt(...place());
    const code = grid.codeOf(cell);
    assert.match(code, /^HX[125]-[0-9A-Z]{5,7}$/);
    assert.equal(grid.cellOfCode(code), cell);
    assert.ok(!seen.has(code) || seen.get(code) === cell, 'two cells never share a code');
    seen.set(code, cell);
  }
  assert.equal(grid.cellOfCode('HX1-XXXX'), null);
  assert.equal(grid.cellOfCode('nonsense'), null);
});

test('cells near a place: its own first, then about two rings around; outlines and centres are ready to draw', () => {
  const cells = grid.cellsNear(17.7231, 83.3013);
  assert.equal(cells[0], grid.cellAt(17.7231, 83.3013));
  assert.ok(cells.length >= 7 && cells.length < 200, `${cells.length} cells`);
  const outline = grid.outlineOf(cells[0]);
  assert.ok(outline.length >= 6);
  const [lat, lng] = grid.centerOf(cells[0]);
  assert.ok(grid.distanceKm([lat, lng], [17.7231, 83.3013]) < 6);
  assert.throws(() => grid.cellAt(51.5, -0.12), /outside India/);
});
