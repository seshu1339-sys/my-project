// One-time fix. Deletes the stray pre-existing "rice" product doc
// (xNGqNwWQbeVtYRHu3sLJ) — an old leftover with no image, no order, and a
// lowercase un-formatted name, predating all of this session's seeded
// catalog data. User-confirmed safe to delete (not real inventory).
// Run from the repo root: node scripts/delete-stray-rice-product.cjs
'use strict';
const path = require('node:path');
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib');
const {getProjectDefaultAccount} = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
const {Client} = require(path.join(cli, 'apiv2'));
const project = 'e-commerce-app-a3897';
const id = 'xNGqNwWQbeVtYRHu3sLJ';

(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const firestore = new Client({urlPrefix: 'https://firestore.googleapis.com', auth: true});
  await firestore.delete(`/v1/projects/${project}/databases/(default)/documents/products/${id}`);
  console.log(id + ': deleted.');
  console.log('Done. Reload the site to see it.');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
