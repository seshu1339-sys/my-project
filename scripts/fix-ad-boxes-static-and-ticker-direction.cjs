// One-time fix, safe to re-run:
// 1. The two ad/box promotions have different text lengths ("Big Savings
//    Everyday" fits one line; "Home Services At Your Doorstep" wraps to two),
//    so their actual rendered content heights differ even though they share
//    one layout height — breaking the scroll-loop's "two stacked copies tile
//    exactly" assumption and showing as a visible gap/partial second copy.
//    The reference design shows these as static cards anyway, so the
//    reliable fix is to stop them scrolling at all (scrollEnabled: false)
//    rather than chase an exact height match.
// 2. Ticker direction set to 'ltr' so it visibly moves left-to-right, per
//    the explicit request (home_ticker_section.dart: direction defaults to
//    'rtl'; 'ltr' reverses that).
// Run from the repo root: node scripts/fix-ad-boxes-static-and-ticker-direction.cjs
'use strict';
const path = require('node:path');
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib');
const {getProjectDefaultAccount} = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
const {Client} = require(path.join(cli, 'apiv2'));
const project = 'e-commerce-app-a3897';

function encodeValue(v) {
  if (typeof v === 'string') return {stringValue: v};
  if (typeof v === 'boolean') return {booleanValue: v};
  if (typeof v === 'number') return Number.isInteger(v) ? {integerValue: String(v)} : {doubleValue: v};
  return {stringValue: String(v)};
}
async function setDoc(firestore, collection, id, data) {
  const fields = {};
  for (const [k, v] of Object.entries(data)) fields[k] = encodeValue(v);
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
    await setDoc(firestore, 'promotions', id, {scrollEnabled: false});
    console.log(id + ': set to static (scrollEnabled: false).');
  }
  await setDoc(firestore, 'settings', 'scrollingText', {direction: 'ltr'});
  console.log('ticker direction set to ltr (left-to-right).');
  console.log('Done. Reload the site to see it.');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
