const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore, Timestamp, FieldValue} = require('firebase-admin/firestore');
const {DAY_MS, MAX_RUNNING, photoPath, validateOffer, statusOnSave, isRunning} = require('./rules');
const {saveOffer, deleteOffer, reviewOffer, saveConfig} = require('./store');

const NOW = Date.parse('2026-11-02T10:00:00+05:30');
const photo = (uid, name = '1.webp') => `https://firebasestorage.googleapis.com/v0/b/demo.appspot.com/o/vendorOffers%2F${uid}%2F${name}?alt=media&token=abc`;
const good = (extra = {}) => ({title: 'Diwali sweets', details: 'Fresh box', offerPrice: 199, regularPrice: 299, photos: [photo('v1')], days: 7, ...extra});

test('only a download link of the vendor\'s own offer folder counts as a photo', () => {
  assert.equal(photoPath(photo('v1'), 'v1'), 'vendorOffers/v1/1.webp');
  assert.equal(photoPath(photo('v2'), 'v1'), null, 'another vendor\'s folder');
  assert.equal(photoPath('https://example.com/o/vendorOffers%2Fv1%2F1.webp', 'v1'), null);
  assert.equal(photoPath('https://firebasestorage.googleapis.com/v0/b/x/o/catalog%2F1.webp', 'v1'), null);
  assert.equal(photoPath('https://firebasestorage.googleapis.com/v0/b/x/o/vendorOffers%2Fv1%2F..%2F..%2Fcatalog%2Fa', 'v1'), null);
  assert.equal(photoPath('not a link', 'v1'), null);
});

test('what a vendor may save as an offer is checked', () => {
  const safe = validateOffer(good({title: '  Diwali   sweets '}), 'v1');
  assert.equal(safe.title, 'Diwali sweets');
  assert.equal(safe.days, 7);
  assert.equal(validateOffer(good({regularPrice: undefined}), 'v1').regularPrice, null);
  assert.throws(() => validateOffer(good({title: 'x'}), 'v1'), /name/);
  assert.throws(() => validateOffer(good({details: 'x'.repeat(301)}), 'v1'), /details/);
  assert.throws(() => validateOffer(good({offerPrice: 0}), 'v1'), /offer price/);
  assert.throws(() => validateOffer(good({offerPrice: '199'}), 'v1'), /offer price/);
  assert.throws(() => validateOffer(good({offerPrice: 10.123}), 'v1'), /offer price/);
  assert.throws(() => validateOffer(good({regularPrice: 199}), 'v1'), /regular price/);
  assert.throws(() => validateOffer(good({photos: []}), 'v1'), /photos/);
  assert.throws(() => validateOffer(good({photos: [photo('v1', 'a'), photo('v1', 'b'), photo('v1', 'c'), photo('v1', 'd')]}), 'v1'), /photos/);
  assert.throws(() => validateOffer(good({photos: [photo('v2')]}), 'v1'), /own vendor app/);
  assert.throws(() => validateOffer(good({photos: [photo('v1'), photo('v1')]}), 'v1'), /own vendor app/);
  assert.throws(() => validateOffer(good({days: 0}), 'v1'), /days/);
  assert.throws(() => validateOffer(good({days: 31}), 'v1'), /days/);
  assert.throws(() => validateOffer(good({days: undefined}), 'v1'), /days/);
  assert.equal(validateOffer(good({days: undefined}), 'v1', true).days, null, 'a running offer may keep its end date');
});

test('an offer is live at once unless the admin switched on approval', () => {
  assert.equal(statusOnSave(undefined), 'live');
  assert.equal(statusOnSave(false), 'live');
  assert.equal(statusOnSave(true), 'pending');
});

test('only a live or waiting offer before its end date counts as running', () => {
  const at = (status, time) => ({status, endsAt: Timestamp.fromMillis(time)});
  assert.equal(isRunning(at('live', NOW + 1), NOW), true);
  assert.equal(isRunning(at('pending', NOW + 1), NOW), true);
  assert.equal(isRunning(at('live', NOW), NOW), false);
  assert.equal(isRunning(at('removed', NOW + 1), NOW), false);
});

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
const fakeBucket = () => {
  const deleted = [];
  return {deleted, file: path => ({delete: async () => { deleted.push(path); }})};
};

let seq = 0;
async function setup(status = 'approved') {
  const db = getFirestore();
  const uid = `offer-vendor-${Date.now()}-${++seq}`;
  await db.doc(`vendors/${uid}`).set({status, shopId: `shop-${uid}`, name: 'Owner name'});
  await db.doc(`shops/shop-${uid}`).set({name: 'Lakshmi Sweets'});
  await saveConfig(db, {approvalRequired: false});
  return {db, uid, bucket: fakeBucket(), offer: (extra = {}) => good({photos: [photo(uid)], ...extra})};
}

test('an approved vendor\'s offer goes live at once with their shop on it', emulated, async () => {
  const {db, uid, bucket, offer} = await setup();
  const {offerId, status} = await saveOffer(db, bucket, uid, offer(), NOW);
  assert.equal(status, 'live');
  const saved = (await db.doc(`vendorOffers/${offerId}`).get()).data();
  assert.equal(saved.vendorId, uid);
  assert.equal(saved.shopId, `shop-${uid}`);
  assert.equal(saved.shopName, 'Lakshmi Sweets');
  // The vendor chose 7 days; the admin's post duration (24 hours unless set, functions/post-duration.js) ends it first.
  assert.equal(saved.endsAt.toMillis(), NOW + DAY_MS);
  assert.equal(saved.ownEndsAt.toMillis(), NOW + 7 * DAY_MS);
  assert.equal(saved.postedAt.toMillis(), NOW);
});

test('a vendor who is not approved cannot make an offer', emulated, async () => {
  const {db, uid, bucket, offer} = await setup('pending');
  await assert.rejects(saveOffer(db, bucket, uid, offer(), NOW), /approved/);
});

test('with the admin switch on, a new offer and an edit of a live one wait for approval', emulated, async () => {
  const {db, uid, bucket, offer} = await setup();
  const {offerId} = await saveOffer(db, bucket, uid, offer(), NOW);
  await saveConfig(db, {approvalRequired: true});
  assert.equal((await saveOffer(db, bucket, uid, offer(), NOW)).status, 'pending');
  assert.equal((await saveOffer(db, bucket, uid, offer({offerId, title: 'Changed name'}), NOW)).status, 'pending');
  assert.deepEqual(await reviewOffer(db, {offerId, action: 'approve'}), {status: 'live'});
  await assert.rejects(reviewOffer(db, {offerId, action: 'approve'}), /waiting/);
  await saveConfig(db, {approvalRequired: false});
});

test('an edit may keep the end date, change it, and a finished offer needs a new one', emulated, async () => {
  const {db, uid, bucket, offer} = await setup();
  // With the longest post duration (1 month) the vendor's own days count; an edit keeps the posted time, so 30 more days are still
  // capped at 30 days after it was posted.
  await db.doc('settings/business').set({postDuration: '1m'}, {merge: true});
  try {
    const {offerId} = await saveOffer(db, bucket, uid, offer(), NOW);
    await saveOffer(db, bucket, uid, offer({offerId, days: undefined}), NOW + DAY_MS);
    assert.equal((await db.doc(`vendorOffers/${offerId}`).get()).data().endsAt.toMillis(), NOW + 7 * DAY_MS);
    await saveOffer(db, bucket, uid, offer({offerId, days: 30}), NOW + DAY_MS);
    const later = NOW + 40 * DAY_MS;
    assert.equal((await db.doc(`vendorOffers/${offerId}`).get()).data().endsAt.toMillis(), NOW + 30 * DAY_MS);
    await assert.rejects(saveOffer(db, bucket, uid, offer({offerId, days: undefined}), later), /days/);
    await saveOffer(db, bucket, uid, offer({offerId, days: 3}), later);
    assert.equal((await db.doc(`vendorOffers/${offerId}`).get()).data().endsAt.toMillis(), later + 3 * DAY_MS, 'running again is a new post');
  } finally {
    await db.doc('settings/business').set({postDuration: FieldValue.delete()}, {merge: true});
  }
});

test('a vendor can never touch another vendor\'s offer', emulated, async () => {
  const a = await setup();
  const b = await setup();
  const {offerId} = await saveOffer(a.db, a.bucket, a.uid, a.offer(), NOW);
  await assert.rejects(saveOffer(b.db, b.bucket, b.uid, b.offer({offerId}), NOW), /not found/);
  await assert.rejects(deleteOffer(b.db, b.bucket, b.uid, offerId), /not found/);
  assert.equal((await a.db.doc(`vendorOffers/${offerId}`).get()).data().vendorId, a.uid);
  assert.deepEqual(b.bucket.deleted, []);
});

test('a photo taken out of an offer, and every photo of a deleted offer, leaves Storage', emulated, async () => {
  const {db, uid, bucket, offer} = await setup();
  const [one, two] = [photo(uid, '1.webp'), photo(uid, '2.webp')];
  const {offerId} = await saveOffer(db, bucket, uid, offer({photos: [one, two]}), NOW);
  await saveOffer(db, bucket, uid, offer({offerId, photos: [two]}), NOW);
  assert.deepEqual(bucket.deleted, [`vendorOffers/${uid}/1.webp`]);
  await deleteOffer(db, bucket, uid, offerId);
  assert.deepEqual(bucket.deleted, [`vendorOffers/${uid}/1.webp`, `vendorOffers/${uid}/2.webp`]);
  assert.equal((await db.doc(`vendorOffers/${offerId}`).get()).exists, false);
});

test('the admin removes an offer with a reason; the vendor can then only delete it', emulated, async () => {
  const {db, uid, bucket, offer} = await setup();
  const {offerId} = await saveOffer(db, bucket, uid, offer(), NOW);
  await assert.rejects(reviewOffer(db, {offerId, action: 'remove', reason: ''}), /reason/);
  await assert.rejects(reviewOffer(db, {offerId, action: 'hide', reason: 'Wrong'}), /approve or remove/);
  assert.deepEqual(await reviewOffer(db, {offerId, action: 'remove', reason: 'Wrong photo'}), {status: 'removed'});
  assert.equal((await db.doc(`vendorOffers/${offerId}`).get()).data().removedReason, 'Wrong photo');
  await assert.rejects(saveOffer(db, bucket, uid, offer({offerId}), NOW), /removed/);
  assert.deepEqual(await deleteOffer(db, bucket, uid, offerId), {deleted: true});
});

test('a vendor runs at most the limit of offers, and a finished one does not count', emulated, async () => {
  const {db, uid, bucket, offer} = await setup();
  const made = [];
  for (let i = 0; i < MAX_RUNNING; i++) made.push((await saveOffer(db, bucket, uid, offer(), NOW)).offerId);
  await assert.rejects(saveOffer(db, bucket, uid, offer(), NOW), /at a time/);
  await saveOffer(db, bucket, uid, offer({offerId: made[0], title: 'Still fine to edit'}), NOW);
  assert.equal((await saveOffer(db, bucket, uid, offer(), NOW + 8 * DAY_MS)).status, 'live');
});

test('the nearby alert: on or off (the plan km decides how far); kept on a new offer; an edit of a running offer never asks again', emulated, async () => {
  assert.equal(validateOffer(good(), 'v1').alert, false);
  assert.equal(validateOffer(good({alert: true}), 'v1').alert, true);
  assert.equal(validateOffer(good({alertRadiusKm: 50}), 'v1').alert, true, 'an older app sending 50 km means on');
  assert.throws(() => validateOffer(good({alert: 'yes'}), 'v1'), /on or off/);
  const {db, uid, bucket, offer} = await setup();
  const {offerId} = await saveOffer(db, bucket, uid, offer({alert: true}), NOW);
  const ref = db.doc(`vendorOffers/${offerId}`);
  assert.equal((await ref.get()).data().alert, true);
  await ref.update({alertClaimedAt: Timestamp.fromMillis(NOW), alertStatus: 'sent', alertRadiusKm: 25}); // what the Offer Alerts module writes
  await saveOffer(db, bucket, uid, offer({offerId, title: 'New name', alert: false, days: undefined}), NOW + 1000);
  const edited = (await ref.get()).data();
  assert.equal(edited.alert, true, 'unchanged');
  assert.equal(edited.alertStatus, 'sent', 'not asked again');
  // Run again after it ended: a fresh choice, and it may alert again.
  await saveOffer(db, bucket, uid, offer({offerId, days: 3, alert: true}), NOW + 8 * DAY_MS);
  const again = (await ref.get()).data();
  assert.equal(again.alert, true);
  assert.equal(again.alertRadiusKm, undefined);
  assert.equal(again.alertClaimedAt, undefined);
  assert.equal(again.alertStatus, undefined);
});
