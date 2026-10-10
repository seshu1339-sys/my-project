// One-time fix, safe to re-run.
// The reference wireframe the user drew shows two SEPARATE promo areas:
//   - a horizontal "TODAY OFFER BOXES" row (item 7) directly under the
//     ticker, swipeable, arrows hinting scroll direction
//   - a vertical "ADS" rail (item 8) down the right side
// Only the second one (placement: 'ad') was ever seeded, so the "today
// Narsipatnam offer" boxes the user kept asking about never had any content
// to show — they map to HeroCarousel, which reads placement: 'carousel',
// a placement that simply didn't exist in the data yet. This adds 4 such
// entries, plus a compact visibleCount/height on section_promo so they
// render as a row of small swipeable cards (not one big banner).
// Run from the repo root: node scripts/seed-today-offer-carousel.cjs
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
async function setDoc(firestore, collection, id, data) {
  const fields = {};
  for (const [k, v] of Object.entries(data)) { if (v !== undefined) fields[k] = encodeValue(v); }
  const fieldPaths = Object.keys(data).map(k => 'updateMask.fieldPaths=' + encodeURIComponent(k)).join('&');
  await firestore.patch(
    `/v1/projects/${project}/databases/(default)/documents/${collection}/${id}?${fieldPaths}`,
    {fields},
  );
}

const todayOffers = [
  {id: 'promo-today-vegetables', name: "Today's Offer", description: 'Fresh vegetables & fruits — best prices today', placement: 'carousel', order: 1, target: 'cat-vegetables', backgroundColor: '#16a34a', textColor: '#ffffff'},
  {id: 'promo-today-dairy', name: "Today's Offer", description: 'Dairy & Bakery — fresh stock daily', placement: 'carousel', order: 2, target: 'cat-dairy-bakery', backgroundColor: '#2563eb', textColor: '#ffffff'},
  {id: 'promo-today-services', name: "Today's Offer", description: 'Home services at your doorstep, Narsipatnam', placement: 'carousel', order: 3, target: 'svc-plumbing', backgroundColor: '#d97706', textColor: '#ffffff'},
  {id: 'promo-today-grocery', name: "Today's Offer", description: 'Grocery & staples combo savings', placement: 'carousel', order: 4, target: 'cat-grocery-staples', backgroundColor: '#dc2626', textColor: '#ffffff'},
];

(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const firestore = new Client({urlPrefix: 'https://firestore.googleapis.com', auth: true});

  for (const p of todayOffers) {
    const {id, ...data} = p;
    await setDoc(firestore, 'promotions', id, data);
    console.log(id + ': seeded (placement: carousel).');
  }
  await setDoc(firestore, 'settings', 'section_promo', {visibleCount: 3, height: 180});
  console.log('section_promo: visibleCount=3, height=180 (compact swipeable row).');
  console.log('Done. Reload the site to see it.');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
