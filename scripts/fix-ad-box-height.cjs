// One-time fix, safe to re-run: the two ad/box promotions were seeded with an
// explicit height (220) taller than their actual text content, so PromoCard
// (which vertically centers its content inside that height) left visible
// empty space above/below the text — exactly what showed as a "white line"
// mid-scroll. Clearing width/height back to 0 (this codebase's existing
// "automatic" convention) lets them use the already-tuned layout default
// instead. Run from the repo root: node scripts/fix-ad-box-height.cjs
'use strict';
const path = require('node:path');
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib');
const {getProjectDefaultAccount} = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
const {Client} = require(path.join(cli, 'apiv2'));
const project = 'e-commerce-app-a3897';

async function setDoc(firestore, collection, id, data) {
  const fields = {};
  for (const [k, v] of Object.entries(data)) fields[k] = {integerValue: String(v)};
  const fieldPaths = Object.keys(data).map(k => 'updateMask.fieldPaths=' + encodeURIComponent(k)).join('&');
  await firestore.patch(
    `/v1/projects/${project}/databases/(default)/documents/${collection}/${id}?${fieldPaths}`,
    {fields},
  );
}

(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const firestore = new Client({urlPrefix: 'https://firestore.googleapis.com', auth: true});

  for (const id of ['promo-big-savings', 'promo-home-services']) {
    await setDoc(firestore, 'promotions', id, {width: 0, height: 0});
    console.log(id + ': width/height reset to automatic.');
  }
  console.log('Done. Reload the site to see it.');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
