// Shows the import chain from an app's entry point to a file: node scripts/why-reach.cjs main_field.dart ui/layout_settings.dart
'use strict';
const fs = require('node:fs'), path = require('node:path');
const lib = path.resolve('lib');
const [entry, target] = process.argv.slice(2);
const resolveImports = f => {
  const src = fs.readFileSync(f, 'utf8'), out = [];
  for (const m of src.matchAll(/^\s*(?:import|export)\s+'([^']+)'/gm)) {
    const t = m[1];
    if (t.startsWith('dart:') || (t.startsWith('package:') && !t.startsWith('package:ecommerce_app/'))) continue;
    const r = t.startsWith('package:ecommerce_app/') ? path.join(lib, t.slice(22)) : path.resolve(path.dirname(f), t);
    if (fs.existsSync(r)) out.push(r);
  }
  return out;
};
const start = path.join(lib, entry), goal = path.join(lib, target);
const prev = new Map([[start, null]]);
const queue = [start];
while (queue.length) {
  const f = queue.shift();
  if (f === goal) break;
  for (const d of resolveImports(f)) if (!prev.has(d)) { prev.set(d, f); queue.push(d); }
}
if (!prev.has(goal)) { console.log('not reachable'); process.exit(0); }
const chain = [];
for (let f = goal; f; f = prev.get(f)) chain.unshift(path.relative(lib, f).split(path.sep).join('/'));
console.log(chain.join('\n  -> '));
