const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {Timestamp} = require('firebase-admin/firestore');
const {wantsAlert, planKm, reach, alertCopy, vendorMayAlert, distanceKm, VENDOR_ALERT_GAP_MS} = require('./rules');
const {releaseAlert} = require('./store');

// Narsipatnam bazaar; Anakapalli is about 45 km away, Visakhapatnam about 75 km.
const SHOP = {lat: 17.668, lng: 82.612};
const NEAR = {latitude: 17.70, longitude: 82.65}; // ~5 km
const ANAKAPALLI = {latitude: 17.69, longitude: 83.0}; // ~41 km
const VIZAG = {latitude: 17.72, longitude: 83.30}; // ~73 km

test('alert on asks for an alert; offers saved before (25 or 50 km) still do', () => {
  assert.equal(wantsAlert({alert: true}), true);
  assert.equal(wantsAlert({alert: false, alertRadiusKm: 25}), false);
  assert.equal(wantsAlert({alertRadiusKm: 25}), true);
  assert.equal(wantsAlert({alertRadiusKm: 50}), true);
  for (const v of [0, 10, 100, '25', undefined]) assert.equal(wantsAlert({alertRadiusKm: v}), false, String(v));
});

test('the alert reaches the plan km (owner, 7 Nov 2026)', () => {
  assert.equal(planKm({radiusKm: 40}), 40);
  assert.equal(planKm({}), 25);
  assert.equal(planKm(null), 25);
});

test('a customer inside the circle is reached; outside, or with no known location, is not', () => {
  assert.ok(distanceKm(SHOP.lat, SHOP.lng, ANAKAPALLI.latitude, ANAKAPALLI.longitude) > 25);
  assert.ok(reach(SHOP, NEAR, 25) < 25);
  assert.equal(reach(SHOP, ANAKAPALLI, 25), null);
  assert.ok(reach(SHOP, ANAKAPALLI, 50) < 50);
  assert.equal(reach(SHOP, VIZAG, 50), null);
  assert.equal(reach(SHOP, {}, 50), null);
  assert.equal(reach(SHOP, {latitude: 0, longitude: 0}, 50), null);
  assert.equal(reach(null, NEAR, 50), null);
});

test('the alert reads: the shop, the offer, its price, the old price and how far', () => {
  const copy = alertCopy({shopName: 'Lakshmi Kirana', title: 'Tomato 1 kg', offerPrice: 20, regularPrice: 32}, 4.6);
  assert.equal(copy.title, 'Offer near you: Lakshmi Kirana');
  assert.equal(copy.body, 'Tomato 1 kg: ₹20 (was ₹32) • 5 km away. Tap to see the shop and the way.');
  assert.match(alertCopy({shopName: 'S', title: 'T', offerPrice: 19.5}, 0.4).body, /^T: ₹19\.50 • less than 1 km away/);
});

test('one alert per vendor a day', () => {
  const now = Date.parse('2026-11-06T10:00:00Z');
  assert.equal(vendorMayAlert(0, now), true);
  assert.equal(vendorMayAlert(now - VENDOR_ALERT_GAP_MS + 1000, now), false);
  assert.equal(vendorMayAlert(now - VENDOR_ALERT_GAP_MS, now), true);
});

const emulator = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
const t0 = Date.parse('2031-03-05T10:00:00+05:30');
async function setup() {
  const {getFirestore} = require('firebase-admin/firestore');
  const db = getFirestore();
  for (const c of ['vendorOffers', 'vendorOfferAlerts', 'notificationSubscribers', 'shops', 'settings', 'vendorPremium']) {
    for (const d of (await db.collection(c).get()).docs) await d.ref.delete();
  }
  await db.collection('shops').doc('s1').set({name: 'Lakshmi Kirana', latitude: SHOP.lat, longitude: SHOP.lng});
  await db.collection('notificationSubscribers').doc('near').set({enabled: true, ...NEAR});
  await db.collection('notificationSubscribers').doc('anakapalli').set({enabled: true, ...ANAKAPALLI});
  await db.collection('notificationSubscribers').doc('vizag').set({enabled: true, ...VIZAG});
  await db.collection('notificationSubscribers').doc('nowhere').set({enabled: true});
  await db.collection('notificationSubscribers').doc('off').set({enabled: false, ...NEAR});
  // Paid vendors only: v1 and v2 have a running plan.
  for (const v of ['v1', 'v2']) await db.collection('vendorPremium').doc(v).set({active: true, radiusKm: 25, endsAt: Timestamp.fromMillis(t0 + 365 * 86400000)});
  return db;
}
const offer = (extra = {}) => ({
  vendorId: 'v1', shopId: 's1', shopName: 'Lakshmi Kirana', title: 'Tomato 1 kg', offerPrice: 20, regularPrice: 32, status: 'live',
  alert: true, endsAt: Timestamp.fromMillis(t0 + 86400000), ...extra,
});
const recorder = () => {
  const sent = [];
  const send = async (uid, key, copy, data) => { sent.push({uid, key, copy, data}); return 'sent'; };
  return {sent, send};
};

test('a 25 km plan: only the customer inside gets it, with the shop to open; never twice', emulator, async () => {
  const db = await setup();
  await db.collection('vendorOffers').doc('o1').set(offer());
  const {sent, send} = recorder();
  assert.deepEqual(await releaseAlert(db, 'o1', send, t0), {status: 'sent', reached: 1});
  assert.deepEqual(sent.map(s => s.uid), ['near']);
  assert.deepEqual(sent[0].data, {type: 'shopOffer', shopId: 's1', offerId: 'o1'});
  assert.equal(sent[0].key, 'vendorOfferAlert:o1');
  const saved = (await db.collection('vendorOffers').doc('o1').get()).data();
  assert.equal(saved.alertStatus, 'sent');
  assert.equal(saved.alertRadiusKm, 25, 'the plan km is written on the offer');
  assert.equal(saved.alertReached, undefined, 'the number is not on the public offer');
  assert.equal((await db.collection('vendorOfferAlerts').doc('v1').collection('sent').doc('o1').get()).data().reached, 1);
  assert.deepEqual(await releaseAlert(db, 'o1', send, t0 + 1000), {status: 'not-due', reached: 0}, 'a second event sends nothing');
  assert.equal(sent.length, 1);
});

test('a 50 km plan reaches further, but not beyond; the km the offer asked for no longer matters', emulator, async () => {
  const db = await setup();
  await db.collection('vendorPremium').doc('v1').set({active: true, radiusKm: 50, endsAt: Timestamp.fromMillis(t0 + 365 * 86400000)});
  await db.collection('vendorOffers').doc('o1').set(offer({alertRadiusKm: 25}));
  const {sent, send} = recorder();
  await releaseAlert(db, 'o1', send, t0);
  assert.deepEqual(sent.map(s => s.uid).sort(), ['anakapalli', 'near']);
});

test('no alert: not asked, waiting for approval, ended, switched off by the admin, or a second one the same day', emulator, async () => {
  const db = await setup();
  const {sent, send} = recorder();
  await db.collection('vendorOffers').doc('none').set(offer({alert: false}));
  await db.collection('vendorOffers').doc('pending').set(offer({status: 'pending'}));
  await db.collection('vendorOffers').doc('ended').set(offer({endsAt: Timestamp.fromMillis(t0 - 1)}));
  for (const id of ['none', 'pending', 'ended']) assert.equal((await releaseAlert(db, id, send, t0)).status, 'not-due', id);

  await db.collection('vendorOffers').doc('first').set(offer());
  await db.collection('vendorOffers').doc('second').set(offer());
  assert.equal((await releaseAlert(db, 'first', send, t0)).status, 'sent');
  assert.equal((await releaseAlert(db, 'second', send, t0 + 3600000)).status, 'daily-limit');
  assert.equal((await db.collection('vendorOffers').doc('second').get()).data().alertStatus, 'daily-limit');

  await db.collection('settings').doc('business').set({vendorOfferAlertsEnabled: false});
  await db.collection('vendorOffers').doc('off').set(offer({vendorId: 'v2'}));
  assert.equal((await releaseAlert(db, 'off', send, t0)).status, 'disabled');
  assert.equal(sent.length, 1);
});

test('a shop with no map location sends nothing and says why', emulator, async () => {
  const db = await setup();
  await db.collection('shops').doc('s1').set({name: 'Lakshmi Kirana'});
  await db.collection('vendorOffers').doc('o1').set(offer());
  const {sent, send} = recorder();
  assert.equal((await releaseAlert(db, 'o1', send, t0)).status, 'no-shop-location');
  assert.equal((await db.collection('vendorOffers').doc('o1').get()).data().alertStatus, 'no-shop-location');
  assert.equal(sent.length, 0);
});

test('a free vendor cannot alert (paid plans only)', emulator, async () => {
  const db = await setup();
  await db.collection('vendorOffers').doc('free').set(offer({vendorId: 'freeVendor'}));
  const {sent, send} = recorder();
  assert.equal((await releaseAlert(db, 'free', send, t0)).status, 'paid-only');
  assert.equal((await db.collection('vendorOffers').doc('free').get()).data().alertStatus, 'paid-only');
  assert.equal(sent.length, 0);
});
