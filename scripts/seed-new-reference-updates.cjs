// One-time fix, safe to re-run. Matches the newest reference design:
//   - Every ad-placement promotion gets scrollEnabled:true, direction:'up'
//     (bottom-to-top, continuous), an explicit matching height (220 — avoids
//     the old gap bug: PromoCard's inner minHeight and the outer window only
//     agree when an explicit non-zero height is present on the entry), and a
//     countdownSeconds badge (60/90/120s, admin-editable afterward under
//     Promotions -> "Countdown timer badge, seconds").
//   - 2 new ad entries (Farm Fresh Fruits, Daily Essentials) so the rail has
//     real variety like the reference's 5-box column.
//   - 5 new categories (Pet Care, Home Appliances, Electronics, Fashion,
//     Beauty & Wellness) and 2 new non-veg products (Farm Eggs, Chicken)
//     under existing categories.
// Run from the repo root: node scripts/seed-new-reference-updates.cjs
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

const existingAdScroll = [
  {id: 'promo-big-savings', countdownSeconds: 118},
  {id: 'promo-home-services', countdownSeconds: 90},
  {id: 'promo-shop-ad-venkateswara', countdownSeconds: 60},
  {id: 'promo-shop-ad-suma', countdownSeconds: 75},
];

const newAds = [
  {id: 'promo-farm-fresh-fruits', name: 'Farm Fresh Fruits', description: 'Up to 40% OFF', placement: 'ad', order: 5, target: 'category:cat-fruits', backgroundColor: '#15803d', textColor: '#ffffff', countdownSeconds: 118},
  {id: 'promo-daily-essentials-ad', name: 'Daily Essentials\nFor Your Home', description: 'Up to 50% OFF', placement: 'ad', order: 6, target: 'category:cat-grocery-staples', backgroundColor: '#d97706', textColor: '#ffffff', countdownSeconds: 118},
];

const newCategories = [
  {id: 'cat-pet-care', name: 'Pet Care', order: 13},
  {id: 'cat-home-appliances', name: 'Home Appliances', order: 14},
  {id: 'cat-electronics', name: 'Electronics', order: 15},
  {id: 'cat-fashion', name: 'Fashion', order: 16},
  {id: 'cat-beauty-wellness', name: 'Beauty & Wellness', order: 17},
];

const newProducts = [
  {id: 'prod-farm-eggs', name: 'Farm Eggs', categoryId: 'cat-dairy-bakery', price: 60, compareAtPrice: 85, unit: '6 pcs', stock: 80, order: 5, description: 'Fresh farm eggs.'},
  {id: 'prod-chicken', name: 'Chicken', categoryId: 'cat-grocery-staples', price: 180, compareAtPrice: 279, unit: '1 kg', stock: 40, order: 4, description: 'Fresh chicken.'},
];

(async () => {
  const account = getProjectDefaultAccount(process.cwd());
  if (!account) throw Error('Sign in with firebase login first.');
  await requireAuth({project, ...account, nonInteractive: true});
  const firestore = new Client({urlPrefix: 'https://firestore.googleapis.com', auth: true});

  for (const {id, countdownSeconds} of existingAdScroll) {
    await setDoc(firestore, 'promotions', id, {scrollEnabled: true, direction: 'up', height: 220, countdownSeconds});
    console.log(id + ': scrollEnabled=true, height=220, countdownSeconds=' + countdownSeconds);
  }
  for (const p of newAds) {
    const {id, ...data} = p;
    await setDoc(firestore, 'promotions', id, {...data, scrollEnabled: true, direction: 'up', height: 220});
    console.log(id + ': seeded (scrolling ad).');
  }
  for (const c of newCategories) {
    const {id, ...data} = c;
    await setDoc(firestore, 'categories', id, data);
    console.log(id + ': seeded.');
  }
  for (const p of newProducts) {
    const {id, ...data} = p;
    await setDoc(firestore, 'products', id, data);
    console.log(id + ': seeded.');
  }
  console.log('Done. Reload the site to see it.');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
