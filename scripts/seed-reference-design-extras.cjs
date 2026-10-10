// One-time fix, safe to re-run. Closes the remaining content gaps between
// the live site and the user's reference design screenshot:
//   - 5 more categories (Rice/Dal/Grains, Atta/Flours/Sooji, Cooking Oils &
//     Ghee, Masalas & Spices, Baby & Kids) alongside the 7 already seeded.
//   - 3 "Top Offers Near You" box-placement promotions (the small cards that
//     sit under the ADS rail on the right), matching the reference's exact
//     labels.
// Run from the repo root: node scripts/seed-reference-design-extras.cjs
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

const categories = [
  {id: 'cat-rice-dal-grains', name: 'Rice, Dal & Grains', order: 8},
  {id: 'cat-atta-flours', name: 'Atta, Flours & Sooji', order: 9},
  {id: 'cat-cooking-oils-ghee', name: 'Cooking Oils & Ghee', order: 10},
  {id: 'cat-masalas-spices', name: 'Masalas & Spices', order: 11},
  {id: 'cat-baby-kids', name: 'Baby & Kids', order: 12},
];

// scrollEnabled: false — same reasoning as the existing ad-rail promos: the
// two-stacked-copies scroll loop only tiles seamlessly when a card's natural
// content height exactly matches its viewport, which isn't guaranteed here,
// so these render as plain static cards instead of risking the same visual
// gap bug that hit promo-big-savings/promo-home-services earlier.
const topOffers = [
  {id: 'promo-top-vegetables', name: 'Farm Fresh Vegetables', description: 'Up to 30% OFF', placement: 'box', order: 1, target: 'cat-vegetables', backgroundColor: '#dcfce7', textColor: '#166534', scrollEnabled: false},
  {id: 'promo-top-essentials', name: 'Daily Essentials', description: 'Best Prices', placement: 'box', order: 2, target: 'cat-grocery-staples', backgroundColor: '#ffedd5', textColor: '#9a3412', scrollEnabled: false},
  {id: 'promo-top-personal-care', name: 'Personal Care', description: 'Up to 25% OFF', placement: 'box', order: 3, target: 'cat-personal-care', backgroundColor: '#fce7f3', textColor: '#9d174d', scrollEnabled: false},
];

(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const firestore = new Client({urlPrefix: 'https://firestore.googleapis.com', auth: true});

  for (const c of categories) { const {id, ...data} = c; await setDoc(firestore, 'categories', id, data); console.log(id + ': seeded.'); }
  for (const p of topOffers) { const {id, ...data} = p; await setDoc(firestore, 'promotions', id, data); console.log(id + ': seeded (placement: box).'); }
  console.log('Done. Reload the site to see it.');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
