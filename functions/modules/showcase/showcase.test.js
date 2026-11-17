const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {Timestamp} = require('firebase-admin/firestore');
const {shopPhotos, choosePhoto, syncPlan} = require('./store');

test('the ad box photo is one of the shop photos, photo 1 first', () => {
  assert.deepEqual(shopPhotos({imageUrl: 'https://a/1', photo3Url: 'https://a/3', photo2Url: 'https://a/2', name: 'x'}), ['https://a/1', 'https://a/2', 'https://a/3']);
  assert.deepEqual(shopPhotos({}), []);
});

const emulator = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
const T = Date.parse('2031-03-05T10:00:00+05:30');
async function setup() {
  const {getFirestore} = require('firebase-admin/firestore');
  const db = getFirestore();
  for (const c of ['vendors', 'shops', 'vendorPremium', 'vendorShowcase']) for (const d of (await db.collection(c).get()).docs) await d.ref.delete();
  await db.collection('vendors').doc('v1').set({status: 'approved', shopId: 's1', name: 'Lakshmi'});
  await db.collection('shops').doc('s1').set({name: 'Lakshmi Kirana', imageUrl: 'https://a/1', photo2Url: 'https://a/2'});
  return db;
}
const paid = (km = 15) => ({active: true, endsAt: Timestamp.fromMillis(T + 86400000), radiusKm: km, tier: 'gold'});

test('a paid vendor picks the ad photo; the plan km and end go with it; a free vendor cannot', emulator, async () => {
  const db = await setup();
  await assert.rejects(choosePhoto(db, 'v1', {photoUrl: 'https://a/2'}, T), /Silver, Gold and Premium/);
  await db.collection('vendorPremium').doc('v1').set(paid());
  await assert.rejects(choosePhoto(db, 'v1', {photoUrl: 'https://elsewhere/x'}, T), /approved shop photos/);
  await choosePhoto(db, 'v1', {photoUrl: 'https://a/2'}, T);
  const s = (await db.collection('vendorShowcase').doc('v1').get()).data();
  assert.deepEqual([s.photoUrl, s.radiusKm, s.active, s.shopName], ['https://a/2', 15, true, 'Lakshmi Kirana']);
});

test('the plan changes: the km follow; the plan ends: the boxes go; a new plan with no choice uses photo 1', emulator, async () => {
  const db = await setup();
  await syncPlan(db, 'v1', paid(50), T);
  let s = (await db.collection('vendorShowcase').doc('v1').get()).data();
  assert.deepEqual([s.photoUrl, s.radiusKm, s.active], ['https://a/1', 50, true]);
  await syncPlan(db, 'v1', {...paid(50), active: false}, T);
  s = (await db.collection('vendorShowcase').doc('v1').get()).data();
  assert.equal(s.active, false);
  assert.equal(await syncPlan(db, 'nobody', {active: false}, T), null, 'a vendor who never paid gets no record');
});
