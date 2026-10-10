// One-time fix, safe to re-run. The uniform height:220 set earlier for all
// scrolling ad boxes was too short for entries with more text (e.g. "Home
// Services At Your Doorstep" + its 5-service list), so their two-stacked-
// copies scroll loop overlapped instead of tiling seamlessly (same root
// cause class as the earlier "white line" gap bug — just overflow instead
// of underflow this time). Sets a per-entry height sized to each one's
// actual content instead of one number for all of them.
// Run from the repo root: node scripts/fix-ad-box-heights.cjs
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

const heights = [
  ['promo-big-savings', 200],           // "Big Savings Everyday / Up to 50% OFF" — short
  ['promo-home-services', 320],         // "Home Services At Your Doorstep" + 5-service list — longest
  ['promo-shop-ad-venkateswara', 200],  // short shop tagline
  ['promo-shop-ad-suma', 200],          // short shop tagline
  ['promo-farm-fresh-fruits', 220],     // 2-line description
  ['promo-daily-essentials-ad', 240],   // 2-line name + description
];

(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const firestore = new Client({urlPrefix: 'https://firestore.googleapis.com', auth: true});

  for (const [id, height] of heights) {
    await setDoc(firestore, 'promotions', id, {height});
    console.log(id + ': height=' + height);
  }
  console.log('Done. Reload the site to see it.');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
