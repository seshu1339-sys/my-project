// Read-only: copies every Firestore document (incl. subcollections) to JSON files in a folder outside the repo.
// Run from the repo root: node scripts/backup-firestore.cjs <output folder>
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib');
const {getProjectDefaultAccount} = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
const {Client} = require(path.join(cli, 'apiv2'));
const project = 'e-commerce-app-a3897';
const out = process.argv[2];
if (!out) throw Error('Give an output folder.');

(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const api = new Client({urlPrefix: 'https://firestore.googleapis.com', auth: true});
  const base = `/v1/projects/${project}/databases/(default)/documents`;
  fs.mkdirSync(out, {recursive: true});
  const counts = {};
  async function walk(parent, collection, file) {
    const docs = [];
    let token;
    do {
      const res = await api.get(`${parent}/${collection}`, {queryParams: {pageSize: 300, ...(token ? {pageToken: token} : {})}});
      docs.push(...(res.body.documents || []));
      token = res.body.nextPageToken;
    } while (token);
    counts[file] = docs.length;
    fs.writeFileSync(path.join(out, file + '.json'), JSON.stringify(docs, null, 1));
    for (const d of docs) {
      const rel = d.name.split('/documents/')[1];
      const subs = (await api.post(`${base}/${rel}:listCollectionIds`, {})).body.collectionIds || [];
      for (const s of subs) await walk(`${base}/${rel}`, s, `${rel.replace(/\//g, '__')}__${s}`);
    }
  }
  const top = (await api.post(`${base}:listCollectionIds`, {})).body.collectionIds || [];
  for (const c of top) await walk(base, c, c);
  fs.writeFileSync(path.join(out, '_summary.json'), JSON.stringify(counts, null, 1));
  console.log(counts);
})().catch(e => { console.error(e.message); process.exitCode = 1; });
