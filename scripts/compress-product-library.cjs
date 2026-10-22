// Converts website-images/product-library/<category>/*.jpg to web/images/<category>/*.webp (max width 800, never enlarged, quality 80).
// The originals are only read. Run from the repo root: node scripts/compress-product-library.cjs
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const sharp = require(path.resolve('functions/node_modules/sharp'));
const src = path.resolve('website-images/product-library');
const out = path.resolve('web/images');
(async () => {
  const report = {converted: 0, before: 0, after: 0, missing: [], categories: {}};
  for (const cat of fs.readdirSync(src, {withFileTypes: true}).filter(d => d.isDirectory()).map(d => d.name)) {
    fs.mkdirSync(path.join(out, cat), {recursive: true});
    const jpgs = fs.readdirSync(path.join(src, cat)).filter(f => /\.jpe?g$/i.test(f));
    report.categories[cat] = 0;
    for (const f of jpgs) {
      const from = path.join(src, cat, f);
      const to = path.join(out, cat, f.replace(/\.jpe?g$/i, '.webp').toLowerCase());
      try {
        await sharp(from).rotate().resize({width: 800, withoutEnlargement: true}).webp({quality: 80}).toFile(to);
        report.converted++; report.categories[cat]++;
        report.before += fs.statSync(from).size; report.after += fs.statSync(to).size;
      } catch (e) { report.missing.push(`${cat}/${f}: ${e.message}`); }
    }
  }
  console.log(JSON.stringify(report, null, 1));
})();
