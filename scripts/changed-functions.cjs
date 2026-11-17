#!/usr/bin/env node
// Which Cloud Functions changed since a commit (free-limit plan, owner OK 17 Nov 2026): deploy only those instead of all ~200, so a
// deploy builds and stores less (Artifact Registry stays under 0.5 GB) and does not hit Google's deploy limits (429).
//
//   node scripts/changed-functions.cjs <since-commit>      prints  functions:a,functions:b,...  (or ALL / NONE)
//   firebase deploy --only "$(node scripts/changed-functions.cjs bf78dc7)"
//
// A function is changed when the file that defines it, or any file it requires (followed through every local require), changed.
// package.json / package-lock.json / .env changes mean ALL. A function removed from the code is not listed (firebase asks about it).
const {execSync} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');

const root = path.resolve(__dirname, '..');
const fnDir = path.join(root, 'functions');
const since = process.argv[2];
if (!since) {
  console.error('Give the commit the live functions were deployed from, e.g. node scripts/changed-functions.cjs bf78dc7');
  process.exit(2);
}

const changed = execSync(`git diff --name-only ${since} -- functions`, {cwd: root, encoding: 'utf8'})
  .split('\n').map(s => s.trim()).filter(Boolean).map(f => path.join(root, f));
if (!changed.length) { console.log('NONE'); process.exit(0); }
if (changed.some(f => /package(-lock)?\.json$|[\\/]\.env/.test(f))) { console.log('ALL'); process.exit(0); }
const changedSet = new Set(changed.filter(f => f.endsWith('.js') && !f.endsWith('.test.js')).map(f => path.normalize(f)));

// Load the functions as firebase does, noting which file defines each export.
process.env.FIREBASE_CONFIG ||= JSON.stringify({projectId: 'e-commerce-app-a3897', storageBucket: 'e-commerce-app-a3897.firebasestorage.app'});
process.env.GCLOUD_PROJECT ||= 'e-commerce-app-a3897';
const req = Module.createRequire(path.join(fnDir, 'index.js'));
const index = req('./index.js');
const files = Object.keys(require.cache).filter(f => f.startsWith(fnDir) && !f.includes('node_modules'));
const definedIn = {};
for (const [name, fn] of Object.entries(index)) {
  if (!fn || typeof fn !== 'function' || !fn.__endpoint) continue;
  const owner = files.find(f => f !== path.join(fnDir, 'index.js') && Object.values(require.cache[f].exports || {}).includes(fn));
  definedIn[name] = path.normalize(owner || path.join(fnDir, 'index.js'));
}

// Every local file each file requires, followed all the way.
const depsCache = new Map();
function deps(file, seen = new Set()) {
  if (seen.has(file)) return seen;
  seen.add(file);
  let src = '';
  try { src = fs.readFileSync(file, 'utf8'); } catch { return seen; }
  for (const m of src.matchAll(/require\(\s*['"](\.{1,2}\/[^'"]+)['"]\s*\)/g)) {
    try {
      deps(path.normalize(Module.createRequire(file).resolve(m[1])), seen);
    } catch { /* not a file */ }
  }
  return seen;
}
const out = Object.entries(definedIn).filter(([, file]) => {
  if (!depsCache.has(file)) depsCache.set(file, deps(file));
  return [...depsCache.get(file)].some(d => changedSet.has(d));
}).map(([name]) => `functions:${name}`).sort();
console.log(out.length ? out.join(',') : 'NONE');
process.exit(0);
