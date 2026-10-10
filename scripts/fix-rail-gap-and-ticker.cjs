// One-time fix, safe to re-run:
// 1. promo-home-services was placed in a separate 'box' section from
//    promo-big-savings' 'ad' section — each section has its own padding, so
//    the two stacked with an oversized gap between them instead of the small
//    per-card spacing. Moving it to the same 'ad' placement stacks both in
//    one column with consistent spacing, matching the reference design.
// 2. settings/scrollingText never had any text, so the top ticker had
//    nothing to scroll. This sets a sample line — edit it anytime in
//    Admin -> Scrolling Text Settings.
// Run from the repo root: node scripts/fix-rail-gap-and-ticker.cjs
'use strict';
const path = require('node:path');
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib');
const {getProjectDefaultAccount} = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
const {Client} = require(path.join(cli, 'apiv2'));
const project = 'e-commerce-app-a3897';

function encodeValue(v) {
  if (v === null || v === undefined) return {nullValue: null};
  if (typeof v === 'string') return {stringValue: v};
  if (typeof v === 'boolean') return {booleanValue: v};
  if (typeof v === 'number') return Number.isInteger(v) ? {integerValue: String(v)} : {doubleValue: v};
  return {stringValue: String(v)};
}
function encodeFields(obj) {
  const out = {};
  for (const [k, val] of Object.entries(obj)) { if (val !== undefined) out[k] = encodeValue(val); }
  return out;
}
async function setDoc(firestore, collection, id, data) {
  const fieldPaths = Object.keys(data).map(k => 'updateMask.fieldPaths=' + encodeURIComponent(k)).join('&');
  await firestore.patch(
    `/v1/projects/${project}/databases/(default)/documents/${collection}/${id}?${fieldPaths}`,
    {fields: encodeFields(data)},
  );
}

(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const firestore = new Client({urlPrefix: 'https://firestore.googleapis.com', auth: true});

  await setDoc(firestore, 'promotions', 'promo-home-services', {placement: 'ad'});
  console.log('promo-home-services moved to the "ad" placement (same rail section as promo-big-savings).');

  await setDoc(firestore, 'settings', 'scrollingText', {
    name: 'Scrolling Text Settings',
    text: 'Welcome to Locamarket — fresh groceries and trusted local services, delivered fast!',
    speed: 70,
    direction: 'rtl',
  });
  console.log('settings/scrollingText seeded with sample text.');
  console.log('Done. Reload the site to see it.');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
