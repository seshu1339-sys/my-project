const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {HOUR_MS, DAY_MS, photoPath, validateOffer, offerEnd, boxesOf, boxId} = require('./rules');
const {submitOffer, removeOwnOffer, clearEnded, removeOffer} = require('./store');

const NOW = Date.parse('2026-11-02T10:00:00+05:30');
const DAY = DAY_MS;
const photo = (uid, name = '1.webp') => `https://firebasestorage.googleapis.com/v0/b/demo.appspot.com/o/vendorTodaysOffers%2F${uid}%2F${name}?alt=media&token=abc`;

test('only a download link from the vendor\'s own folder is a photo (offers of the older kind)', () => {
  assert.equal(photoPath(photo('v1'), 'v1'), 'vendorTodaysOffers/v1/1.webp');
  assert.equal(photoPath(photo('v2'), 'v1'), null);
  assert.equal(photoPath('https://example.com/o/vendorTodaysOffers%2Fv1%2F1.webp', 'v1'), null);
  assert.equal(photoPath(photo('v1', '..%2F..%2Fcatalog%2Fa'), 'v1'), null);
  assert.equal(photoPath(42, 'v1'), null);
});

test('an item, a price, 1 week to 3 months and a box within the plan are checked; nothing else is taken', () => {
  assert.deepEqual(validateOffer({productId: 'p1', price: 99.5, days: 7, name: 'ignored'}, 3), {productId: 'p1', price: 99.5, days: 7, slot: null});
  assert.deepEqual(validateOffer({productId: 'p1', price: 99, days: 90, slot: 3}, 3).slot, 3);
  assert.throws(() => validateOffer({productId: 'p1', price: 99, days: 30, slot: 4}, 3), /box 1 to 3/);
  assert.throws(() => validateOffer({price: 99, days: 7}, 1), /items/);
  assert.throws(() => validateOffer({productId: 'p1', price: 0, days: 7}, 1), /price/);
  assert.throws(() => validateOffer({productId: 'p1', price: 9.999, days: 7}, 1), /decimals/);
  for (const days of [1, 2, 14, 120, undefined]) assert.throws(() => validateOffer({productId: 'p1', price: 99, days}, 1), /1 week, 1 month/, String(days));
});

test('a plan gives its own box number; without one Silver 1, Gold 3, Premium 5', () => {
  assert.equal(boxesOf({tier: 'silver'}), 1);
  assert.equal(boxesOf({tier: 'gold'}), 3);
  assert.equal(boxesOf({tier: 'premium'}), 5);
  assert.equal(boxesOf({tier: 'premium', offerBoxes: 8}), 8);
  assert.equal(boxesOf({tier: 'gold', offerBoxes: 0}), 0);
  assert.equal(boxesOf({}), 5);
  assert.equal(boxId('v1', 2), 'v1_2');
});

test('an offer ends after its days, or with the plan if that is sooner', () => {
  assert.equal(offerEnd(NOW, 7, NOW + 100 * DAY), NOW + 7 * DAY);
  assert.equal(offerEnd(NOW, 90, NOW + 100 * DAY), NOW + 90 * DAY);
  assert.equal(offerEnd(NOW, 30, NOW + 3 * HOUR_MS), NOW + 3 * HOUR_MS);
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
async function setup({status = 'approved', active = true, planEndsAt = NOW + 200 * DAY, shopId, tier = 'gold', offerBoxes} = {}) {
  const db = getFirestore();
  const uid = `today-vendor-${Date.now()}-${++seq}`;
  await db.doc(`vendors/${uid}`).set({status, ...(shopId === null ? {} : {shopId: shopId ?? `shop-${uid}`})});
  await db.doc(`vendorPremium/${uid}`).set({uid, active, tier, ...(offerBoxes === undefined ? {} : {offerBoxes}), endsAt: Timestamp.fromMillis(planEndsAt)});
  for (const n of [1, 2, 3, 4]) await db.doc(`products/${uid}-p${n}`).set({ownerId: uid, name: `Item ${n}`, imageUrl: `https://example.com/${n}.jpg`, active: true});
  await db.doc(`products/${uid}-hidden`).set({ownerId: uid, name: 'Hidden', imageUrl: 'https://example.com/h.jpg', active: false});
  await db.doc(`products/${uid}-nophoto`).set({ownerId: uid, name: 'No photo', imageUrl: '', active: true});
  return {db, uid, bucket: fakeBucket(), offer: (n = 1, extra = {}) => ({productId: `${uid}-p${n}`, price: 99, days: 7, ...extra})};
}
const stored = (db, uid, slot) => db.doc(`vendorTodaysOffers/${uid}_${slot}`).get().then(doc => doc.data());

test('a paid vendor\'s item is live at once in their first box, with the item\'s photo and the shop', emulated, async () => {
  const {db, uid, bucket, offer} = await setup();
  assert.deepEqual(await submitOffer(db, bucket, uid, offer(1), NOW), {slot: 1, endsAt: NOW + 7 * DAY});
  const saved = await stored(db, uid, 1);
  assert.deepEqual([saved.vendorId, saved.shopId, saved.productId, saved.name, saved.photoUrl, saved.price, saved.days, saved.slot],
    [uid, `shop-${uid}`, `${uid}-p1`, 'Item 1', 'https://example.com/1.jpg', 99, 7, 1]);
});

test('Gold has 3 boxes: a fourth item is refused unless a box is chosen to replace; the same item stays in its box', emulated, async () => {
  const {db, uid, bucket, offer} = await setup({tier: 'gold'});
  for (const n of [1, 2, 3]) assert.equal((await submitOffer(db, bucket, uid, offer(n), NOW)).slot, n);
  await assert.rejects(submitOffer(db, bucket, uid, offer(4), NOW), /All your 3 Today's Offers boxes are in use/);
  assert.equal((await submitOffer(db, bucket, uid, offer(2, {price: 50, days: 30}), NOW)).slot, 2, 'the same item is updated in its box');
  assert.equal((await stored(db, uid, 2)).price, 50);
  assert.equal((await submitOffer(db, bucket, uid, offer(4, {slot: 3}), NOW)).slot, 3);
  assert.equal((await stored(db, uid, 3)).productId, `${uid}-p4`);
  // Moving an item to another box frees its old box.
  await submitOffer(db, bucket, uid, offer(1, {slot: 2}), NOW);
  assert.equal(await stored(db, uid, 1), undefined);
  assert.equal((await stored(db, uid, 2)).productId, `${uid}-p1`);
});

test('Silver has 1 box; the admin\'s own number for a plan wins', emulated, async () => {
  const silver = await setup({tier: 'silver'});
  await submitOffer(silver.db, silver.bucket, silver.uid, silver.offer(1), NOW);
  await assert.rejects(submitOffer(silver.db, silver.bucket, silver.uid, silver.offer(2), NOW), /All your 1 Today's Offers box is in use/);
  await assert.rejects(submitOffer(silver.db, silver.bucket, silver.uid, silver.offer(2, {slot: 2}), NOW), /box 1 to 1/);
  const none = await setup({tier: 'premium', offerBoxes: 0});
  await assert.rejects(submitOffer(none.db, none.bucket, none.uid, none.offer(1), NOW), /no Today's Offers boxes/);
});

test('the check refuses: not approved, no shop, no plan, plan ended, not their item, hidden item, no photo', emulated, async () => {
  const notApproved = await setup({status: 'pending'});
  await assert.rejects(submitOffer(notApproved.db, notApproved.bucket, notApproved.uid, notApproved.offer(), NOW), /approved/);
  const noShop = await setup({shopId: null});
  await assert.rejects(submitOffer(noShop.db, noShop.bucket, noShop.uid, noShop.offer(), NOW), /shop/);
  const free = await setup({active: false});
  await assert.rejects(submitOffer(free.db, free.bucket, free.uid, free.offer(), NOW), /Silver, Gold or Premium/);
  const ended = await setup({planEndsAt: NOW});
  await assert.rejects(submitOffer(ended.db, ended.bucket, ended.uid, ended.offer(), NOW), /Silver, Gold or Premium/, 'refused at the moment the plan ends');
  const {db, uid, bucket, offer} = await setup();
  await assert.rejects(submitOffer(db, bucket, uid, offer(1, {productId: `${noShop.uid}-p1`}), NOW), /your items/);
  await assert.rejects(submitOffer(db, bucket, uid, offer(1, {productId: `${uid}-hidden`}), NOW), /hidden/);
  await assert.rejects(submitOffer(db, bucket, uid, offer(1, {productId: `${uid}-nophoto`}), NOW), /no photo/);
  assert.equal(await stored(db, uid, 1), undefined);
});

test('an offer of the older kind (one per vendor, own photo) gives way and its photo goes', emulated, async () => {
  const {db, uid, bucket, offer} = await setup();
  await db.doc(`vendorTodaysOffers/${uid}`).set({vendorId: uid, shopId: 's', photoUrl: photo(uid), price: 10, endsAt: Timestamp.fromMillis(NOW + DAY)});
  await submitOffer(db, bucket, uid, offer(1), NOW);
  assert.equal((await db.doc(`vendorTodaysOffers/${uid}`).get()).exists, false);
  assert.deepEqual(bucket.deleted, [`vendorTodaysOffers/${uid}/1.webp`]);
});

test('an offer stops with the plan when that comes first', emulated, async () => {
  const {db, uid, bucket, offer} = await setup({planEndsAt: NOW + 3 * HOUR_MS});
  await submitOffer(db, bucket, uid, offer(1, {days: 90}), NOW);
  assert.equal((await stored(db, uid, 1)).endsAt.toMillis(), NOW + 3 * HOUR_MS);
});

test('the vendor takes a box down; never someone else\'s', emulated, async () => {
  const {db, uid, bucket, offer} = await setup();
  const other = await setup();
  await submitOffer(db, bucket, uid, offer(1), NOW);
  await assert.rejects(removeOwnOffer(db, bucket, other.uid, {offerId: `${uid}_1`}), /not found/);
  assert.deepEqual(await removeOwnOffer(db, bucket, uid, {slot: 1}), {removed: true});
  assert.equal(await stored(db, uid, 1), undefined);
  assert.deepEqual(bucket.deleted, [], 'the item photo is the item\'s, never deleted with the box');
});

test('ended offers are cleared, running ones stay', emulated, async () => {
  const running = await setup();
  await submitOffer(running.db, running.bucket, running.uid, running.offer(1, {days: 30}), NOW);
  const {db, uid, bucket, offer} = await setup();
  await submitOffer(db, bucket, uid, offer(1), NOW);
  await clearEnded(db, bucket, NOW + 7 * DAY);
  assert.equal(await stored(db, uid, 1), undefined);
  assert.ok(await stored(db, running.uid, 1));
});

test('the admin removes an offer and the vendor is told', emulated, async () => {
  const {db, uid, bucket, offer} = await setup();
  await submitOffer(db, bucket, uid, offer(1), NOW);
  assert.deepEqual(await removeOffer(db, bucket, `${uid}_1`, NOW), {removed: true});
  assert.equal(await stored(db, uid, 1), undefined);
  const notices = await db.collection('vendorNotices').where('vendorId', '==', uid).get();
  assert.equal(notices.size, 1);
  await assert.rejects(removeOffer(db, bucket, `${uid}_1`, NOW), /not found/);
});
