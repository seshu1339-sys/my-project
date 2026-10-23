// Reports how independent the app's modules and sections are: which files each app (customer, admin, vendor, staff) can reach, which
// files are used by several apps, and which "sections" (a file group such as home_*, admin_*, vendor_*, field_*, quick_*) import each other.
// Run from the repo root: node scripts/module-graph.cjs [--json]
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const lib = path.resolve('lib');
const files = [];
(function walk(d) { for (const e of fs.readdirSync(d, {withFileTypes: true})) { const p = path.join(d, e.name); if (e.isDirectory()) walk(p); else if (p.endsWith('.dart')) files.push(p); } })(lib);
const rel = f => path.relative(lib, f).split(path.sep).join('/');
const deps = new Map();
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  const out = new Set();
  for (const m of src.matchAll(/^\s*(?:import|export)\s+'([^']+)'(?:\s+(?:if\s*\([^)]*\)\s*'([^']+)'\s*)*)?/gm)) {
    for (const target of [m[1], m[2]]) {
      if (!target || target.startsWith('dart:') || target.startsWith('package:') && !target.startsWith('package:ecommerce_app/')) continue;
      const resolved = target.startsWith('package:ecommerce_app/') ? path.join(lib, target.slice(22)) : path.resolve(path.dirname(f), target);
      if (fs.existsSync(resolved)) out.add(resolved);
    }
  }
  deps.set(f, out);
}
const entries = {customer: 'main.dart', admin: 'main_admin.dart', vendor: 'main_vendor.dart', staff: 'main_field.dart'};
const reach = {};
for (const [app, entry] of Object.entries(entries)) {
  const seen = new Set(), stack = [path.join(lib, entry)];
  while (stack.length) { const f = stack.pop(); if (seen.has(f)) continue; seen.add(f); for (const d of deps.get(f) || []) stack.push(d); }
  reach[app] = seen;
}
// a file's section: its prefix before the first underscore (home_, admin_, vendor_, field_, quick_ ...), or its folder
const section = f => { const r = rel(f); if (r.includes('/')) { const [dir, name] = r.split('/'); return dir === 'ui' ? (name.includes('_') ? name.split('_')[0] : name.replace('.dart', '')) : dir; } return 'root'; };
const result = {apps: {}, shared: {}, crossSection: {}, fanIn: {}, big: []};
for (const [app, set] of Object.entries(reach)) {
  const bySection = {};
  for (const f of set) bySection[section(f)] = (bySection[section(f)] || 0) + 1;
  result.apps[app] = {files: set.size, sections: bySection};
}
for (const f of files) {
  const users = Object.keys(reach).filter(a => reach[a].has(f));
  result.shared[rel(f)] = users;
}
const fan = new Map();
for (const [f, out] of deps) for (const d of out) fan.set(d, (fan.get(d) || 0) + 1);
result.fanIn = Object.fromEntries([...fan].sort((a, b) => b[1] - a[1]).slice(0, 15).map(([f, n]) => [rel(f), n]));
const cross = {};
for (const [f, out] of deps) for (const d of out) { const a = section(f), b = section(d); if (a !== b) { const k = `${a} -> ${b}`; (cross[k] = cross[k] || []).push(`${rel(f)} -> ${rel(d)}`); } }
result.crossSection = cross;
result.big = files.map(f => [rel(f), fs.readFileSync(f, 'utf8').split('\n').length]).filter(x => x[1] > 600).sort((a, b) => b[1] - a[1]);
if (process.argv.includes('--json')) { console.log(JSON.stringify(result, null, 1)); process.exit(0); }
for (const [app, r] of Object.entries(result.apps)) console.log(`${app}: ${r.files} files reachable`, JSON.stringify(r.sections));
console.log('\nUsed by every app:', Object.entries(result.shared).filter(([, u]) => u.length === 4).map(([f]) => f).length, 'files');
console.log('Used by none (dead from every entry point):', Object.entries(result.shared).filter(([, u]) => u.length === 0).map(([f]) => f).join(', '));
console.log('\nMost depended-on files:', JSON.stringify(result.fanIn, null, 1));
console.log('\nFiles over 600 lines:', result.big.map(b => b.join(':')).join(', '));
