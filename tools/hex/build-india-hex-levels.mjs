// One-time script (owner, 13 Nov 2026): WorldPop's India population density (about 1 km pixels) to the size of every staff hexagon cell.
// Nothing here runs in the cloud. Run it on a computer, once:
//
//   node tools/hex/build-india-hex-levels.mjs <ind_pd_2020_1km_UNadj.tif> functions/data/india-hex-levels.txt
//
// Data: WorldPop (www.worldpop.org), Population Density 2020, 1 km, UN-adjusted, India (ind_pd_2020_1km_UNadj.tif, 18,080,605 bytes),
// licence CC BY 4.0. The 18 MB file is NOT kept in the repo or the cloud; only the small result is.
//
// The grid is H3 (hexagons). Every place belongs to exactly one H3 resolution-8 hexagon (about 0.9 km across). A cell is that hexagon
// (1 km cells, dense cities), its resolution-7 parent (about 2.4 km, towns) or its resolution-6 grandparent (about 6.4 km, villages and
// fields), decided by the people per km2:
//   over 4,000 = 1 km; 800 to 4,000 = 2 km; under 800 = 5 km (the real 6.4 km H3 cell)
// A resolution-6 area whose 7 resolution-7 parts are all under 800 is one 5 km cell (the default: nothing is written for it). Otherwise
// each of its 7 parts is one 2 km cell, or 7 cells of 1 km when that part is over 4,000. Because a cell is always "all the 1 km hexagons
// under it", every place is in exactly one cell: no gaps, no overlaps.
//
// Output, one line per resolution-6 area that is NOT a single 5 km cell:
//   <the area's H3 index without its last 6 'f' characters> <2 hex digits: bit i set = part i (cellToChildren order) is split into 1 km>
import {writeFileSync} from 'node:fs';
import {fromFile} from 'geotiff';
import * as h3 from 'h3-js';

const [, , tifPath, outPath] = process.argv;
if (!tifPath || !outPath) {
  console.error('Usage: node build-india-hex-levels.mjs <ind_pd_2020_1km_UNadj.tif> <output.txt>');
  process.exit(1);
}
const DENSE = 4000;
const SPARSE = 800;

const tiff = await fromFile(tifPath);
const image = await tiff.getImage();
const width = image.getWidth();
const height = image.getHeight();
const [originX, originY] = image.getOrigin();
const [resX, resY] = image.getResolution();
const noData = image.getGDALNoData();
console.log(`Raster ${width} x ${height}, pixel ${resX} x ${resY} degrees, origin ${originX}, ${originY}, no-data ${noData}`);
const [data] = await image.readRasters();

// People per km2, summed per resolution-7 part (through the pixel's resolution-8 hexagon, as the server does).
const sums = new Map();
const counts = new Map();
let pixels = 0;
let people = 0;
for (let row = 0; row < height; row++) {
  const lat = originY + (row + 0.5) * resY;
  for (let col = 0; col < width; col++) {
    const v = data[row * width + col];
    if (!(v >= 0) || v === noData) continue;
    const lng = originX + (col + 0.5) * resX;
    const part = h3.cellToParent(h3.latLngToCell(lat, lng, 8), 7);
    sums.set(part, (sums.get(part) ?? 0) + v);
    counts.set(part, (counts.get(part) ?? 0) + 1);
    pixels++;
    people += v;
  }
}
console.log(`${pixels} pixels with data (about ${Math.round(people / 1e6)} million people if each pixel is 1 km2)`);

const areas = new Set([...counts.keys()].map(part => h3.cellToParent(part, 6)));
const lines = [];
let five = 0, two = 0, one = 0;
for (const area of [...areas].sort()) {
  const parts = h3.cellToChildren(area, 7).sort();
  const density = parts.map(p => (counts.get(p) ? sums.get(p) / counts.get(p) : 0));
  if (density.every(d => d < SPARSE)) {
    five++;
    continue;
  }
  let mask = 0;
  parts.forEach((p, i) => {
    if (density[i] >= DENSE) {
      mask |= 1 << i;
      one += h3.cellToChildren(p, 8).length;
    } else two++;
  });
  if (!area.endsWith('ffffff')) throw new Error(`Unexpected H3 index ${area}`);
  lines.push(`${area.slice(0, -6)} ${mask.toString(16).padStart(2, '0')}`);
}

const header = [
  '# LOCAMARKET staff hexagon cell sizes for India (functions/hex-grid.js reads this file).',
  '# Source: WorldPop (www.worldpop.org) Population Density 2020, 1 km, UN-adjusted, India - CC BY 4.0.',
  `# Bands: over ${DENSE} people per km2 = 1 km cell (H3 res 8); ${SPARSE}-${DENSE} = 2 km (res 7); under ${SPARSE} = 5 km (res 6, the default).`,
  `# Built ${new Date().toISOString().slice(0, 10)}. Areas with data: ${areas.size}. Cells: ${five} of 5 km, ${two} of 2 km, ${one} of 1 km.`,
  '# Line: <res-6 H3 index without the last 6 f> <hex mask: bit i = res-7 part i (sorted cellToChildren) split into 1 km cells>',
];
writeFileSync(outPath, `${header.join('\n')}\n${lines.join('\n')}\n`);
console.log(`Areas with data: ${areas.size}. Cells: ${five} of 5 km, ${two} of 2 km, ${one} of 1 km. Lines written: ${lines.length}.`);
