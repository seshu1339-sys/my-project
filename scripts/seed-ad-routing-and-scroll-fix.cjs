// One-time fix, safe to re-run.
// Pairs with the storefront.dart routing change that added 'services' and
// 'shop:<id>' as click targets (previously only 'shops'/'category:ID'/
// 'product:ID'/https:// worked, so a shop- or services-targeted ad silently
// fell through to a generic "ask our office" message).
//   - promo-home-services -> target: 'services' (opens the full Services page).
//   - promo-big-savings -> target: 'shops' (opens the shop directory).
//   - 2 new shop-specific ads, each targeting one real shop by id, so
//     tapping shows that shop's actual map pin, address and a directions
//     link (ShopPage, already built) — this is what rotates through the
//     right-rail ad slot alongside the two above.
//   - The 3 "Top Offers Near You" boxes get scrollEnabled:true (continuous
//     bottom-to-top scroll, as requested) with an EXPLICIT height (160) set
//     on every one of them. This matters: PromoCard's inner minHeight and
//     ScheduledPromo's outer window only resolve to the same number when an
//     explicit, non-zero height is present on the entry itself (both then
//     use that same number) — a missing/zero height lets them each fall back
//     to a different default and reproduces the old visible-gap bug.
// Run from the repo root: node scripts/seed-ad-routing-and-scroll-fix.cjs
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

const adTargets = [
  {id: 'promo-home-services', target: 'services'},
  {id: 'promo-big-savings', target: 'shops'},
];

const newShopAds = [
  {id: 'promo-shop-ad-venkateswara', name: 'Sri Venkateswara Vegetables', description: 'Fresh veggies daily — visit us today', placement: 'ad', order: 3, target: 'shop:shop-venkateswara', backgroundColor: '#15803d', textColor: '#ffffff', scrollEnabled: false},
  {id: 'promo-shop-ad-suma', name: 'Suma Fresh Mart', description: 'Your one-stop supermarket nearby', placement: 'ad', order: 4, target: 'shop:shop-suma-fresh', backgroundColor: '#b45309', textColor: '#ffffff', scrollEnabled: false},
];

const topOfferScroll = ['promo-top-vegetables', 'promo-top-essentials', 'promo-top-personal-care'];

(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const firestore = new Client({urlPrefix: 'https://firestore.googleapis.com', auth: true});

  for (const {id, target} of adTargets) {
    await setDoc(firestore, 'promotions', id, {target});
    console.log(id + ': target -> ' + target);
  }
  for (const p of newShopAds) {
    const {id, ...data} = p;
    await setDoc(firestore, 'promotions', id, data);
    console.log(id + ': seeded (shop ad).');
  }
  for (const id of topOfferScroll) {
    await setDoc(firestore, 'promotions', id, {scrollEnabled: true, height: 160, direction: 'up'});
    console.log(id + ': scrollEnabled=true, height=160, direction=up.');
  }
  console.log('Done. Reload the site to see it.');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
