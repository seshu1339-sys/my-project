const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {HOUR_MS, photoPath, validateOffer, offerEnd} = require('./rules');
const {submitOffer, clearEnded, removeOffer} = require('./store');

const NOW = Date.parse('2026-11-02T10:00:00+05:30');
const DAY = 24 * HOUR_MS;
const photo = (uid, name = '1.webp') => `https://firebasestorage.googleapis.com/v0/b/demo.appspot.com/o/vendorTodaysOffers%2F${uid}%2F${name}?alt=media&token=abc`;

test('only a download link from the vendor\'s own folder is a photo', () => {
  assert.equal(photoPath(photo('v1'), 'v1'), 'vendorTodaysOffers/v1/1.webp');
  assert.equal(photoPath(photo('v2'), 'v1'), null);
  assert.equal(photoPath('https://example.com/o/vendorTodaysOffers%2Fv1%2F1.webp', 'v1'), null);
  assert.equal(photoPath(photo('v1', '..%2F..%2Fcatalog%2Fa'), 'v1'), null);
  assert.equal(photoPath(42, 'v1'), null);
});

test('price and time are checked; nothing else is taken', () => {
  assert.deepEqual(validateOffer({price: 99.5, hours: 24, name: 'ignored'}), {price: 99.5, hours: 24});
  assert.throws(() => validateOffer({price: 0, hours: 24}), /price/);
  assert.throws(() => validateOffer({price: '99', hours: 24}), /price/);
  assert.throws(() => validateOffer({price: 9.999, hours: 24}), /decimals/);
  assert.throws(() => validateOffer({price: 99, hours: 12}), /24 or 48/);
  assert.throws(() => validateOffer({price: 99}), /24 or 48/);
});

test('an offer ends after its hours, or with the plan if that is sooner', () => {
  assert.equal(offerEnd(NOW, 24, NOW + 10 * DAY), NOW + DAY);
  assert.equal(offerEnd(NOW, 48, NOW + 10 * DAY), NOW + 2 * DAY);
  assert.equal(offerEnd(NOW, 48, NOW + 3 * HOUR_MS), NOW + 3 * HOUR_MS);
});

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
const fakeBucket = (files = {}) => {
  const deleted = [];
  return {
    deleted,
    file: path => ({
      exists: async () => [path in files],
      getMetadata: async () => [{contentType: files[path]}],
      delete: async () => { deleted.push(path); },
    }),
  };
};

let seq = 0;
async function setup({status = 'approved', active = true, planEndsAt = NOW + 30 * DAY, shopId} = {}) {
  const db = getFirestore();
  const uid = `today-vendor-${Date.now()}-${++seq}`;
  await db.doc(`vendors/${uid}`).set({status, ...(shopId === null ? {} : {shopId: shopId ?? `shop-${uid}`})});
  await db.doc(`vendorPremium/${uid}`).set({uid, active, endsAt: Timestamp.fromMillis(planEndsAt)});
  const files = {[`vendorTodaysOffers/${uid}/1.webp`]: 'image/webp', [`vendorTodaysOffers/${uid}/2.webp`]: 'image/webp', [`vendorTodaysOffers/${uid}/x.pdf`]: 'application/pdf'};
  return {db, uid, bucket: fakeBucket(files), offer: (extra = {}) => ({photoUrl: photo(uid), price: 99, hours: 24, ...extra})};
}
const stored = (db, uid) => db.doc(`vendorTodaysOffers/${uid}`).get().then(doc => doc.data());

test('a Premium vendor\'s offer is live at once with the shop on it', emulated, async () => {
  const {db, uid, bucket, offer} = await setup();
  assert.deepEqual(await submitOffer(db, bucket, uid, offer(), NOW), {endsAt: NOW + DAY});
  const saved = await stored(db, uid);
  assert.equal(saved.vendorId, uid);
  assert.equal(saved.shopId, `shop-${uid}`);
  assert.equal(saved.price, 99);
  assert.equal(saved.endsAt.toMillis(), NOW + DAY);
  assert.deepEqual(Object.keys(saved).sort(), ['endsAt', 'hours', 'photoUrl', 'price', 'shopId', 'submittedAt', 'vendorId'], 'nothing else is stored');
});

test('the check refuses: not approved, no shop, no plan, plan ended, bad photo', emulated, async () => {
  const notApproved = await setup({status: 'pending'});
  await assert.rejects(submitOffer(notApproved.db, notApproved.bucket, notApproved.uid, notApproved.offer(), NOW), /approved/);
  const noShop = await setup({shopId: null});
  await assert.rejects(submitOffer(noShop.db, noShop.bucket, noShop.uid, noShop.offer(), NOW), /shop/);
  const free = await setup({active: false});
  await assert.rejects(submitOffer(free.db, free.bucket, free.uid, free.offer(), NOW), /active plan/);
  const ended = await setup({planEndsAt: NOW});
  await assert.rejects(submitOffer(ended.db, ended.bucket, ended.uid, ended.offer(), NOW), /active plan/, 'refused at the moment the plan ends, before the status is switched off');
  const {db, uid, bucket, offer} = await setup();
  await assert.rejects(submitOffer(db, bucket, uid, offer({photoUrl: photo('someoneElse')}), NOW), /own vendor app/);
  await assert.rejects(submitOffer(db, bucket, uid, offer({photoUrl: photo(uid, 'missing.webp')}), NOW), /not found/);
  await assert.rejects(submitOffer(db, bucket, uid, offer({photoUrl: photo(uid, 'x.pdf')}), NOW), /not a photo/);
  assert.equal(await stored(db, uid), undefined);
});

test('a new offer replaces the old one and its photo', emulated, async () => {
  const {db, uid, bucket, offer} = await setup();
  await submitOffer(db, bucket, uid, offer(), NOW);
  await submitOffer(db, bucket, uid, offer({photoUrl: photo(uid, '2.webp'), price: 150, hours: 48}), NOW);
  const saved = await stored(db, uid);
  assert.equal(saved.price, 150);
  assert.equal(saved.endsAt.toMillis(), NOW + 2 * DAY);
  assert.deepEqual(bucket.deleted, [`vendorTodaysOffers/${uid}/1.webp`]);
});

test('an offer stops with the plan when that comes first', emulated, async () => {
  const {db, uid, bucket, offer} = await setup({planEndsAt: NOW + 3 * HOUR_MS});
  await submitOffer(db, bucket, uid, offer({hours: 48}), NOW);
  assert.equal((await stored(db, uid)).endsAt.toMillis(), NOW + 3 * HOUR_MS);
});

test('ended offers are cleared with their photos, running ones stay', emulated, async () => {
  const running = await setup();
  await submitOffer(running.db, running.bucket, running.uid, running.offer({hours: 48}), NOW);
  const {db, uid, bucket, offer} = await setup();
  await submitOffer(db, bucket, uid, offer(), NOW);
  await clearEnded(db, bucket, NOW + DAY);
  assert.equal(await stored(db, uid), undefined);
  assert.ok(bucket.deleted.includes(`vendorTodaysOffers/${uid}/1.webp`));
  assert.ok(await stored(db, running.uid));
});

test('the admin removes an offer and the vendor is told', emulated, async () => {
  const {db, uid, bucket, offer} = await setup();
  await submitOffer(db, bucket, uid, offer(), NOW);
  assert.deepEqual(await removeOffer(db, bucket, uid, NOW), {removed: true});
  assert.equal(await stored(db, uid), undefined);
  assert.deepEqual(bucket.deleted, [`vendorTodaysOffers/${uid}/1.webp`]);
  const notices = await db.collection('vendorNotices').where('vendorId', '==', uid).get();
  assert.equal(notices.size, 1);
  await assert.rejects(removeOffer(db, bucket, uid, NOW), /not found/);
});
