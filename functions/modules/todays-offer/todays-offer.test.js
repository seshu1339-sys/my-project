const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly', storageBucket: 'demo-neighbourly.appspot.com'});
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {HOUR_MS, DAY_MS, photoPath, validateOffer, offerEnd, boxesOf, boxId} = require('./rules');
const {submitOffer, removeOwnOffer, clearEnded, onPlanChange, setOfferHidden, removeOffer} = require('./store');

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
  assert.deepEqual(validateOffer({productId: 'p1', price: 99.5, days: 7, name: 'ignored'}, 3), {productId: 'p1', price: 99.5, days: 7, note: '', slot: null});
  assert.deepEqual(validateOffer({productId: 'p1', price: 99, days: 90, slot: 3}, 3).slot, 3);
  assert.throws(() => validateOffer({productId: 'p1', price: 99, days: 30, slot: 4}, 3), /box 1 to 3/);
  assert.throws(() => validateOffer({price: 99, days: 7}, 1), /items/);
  assert.throws(() => validateOffer({productId: 'p1', price: 0, days: 7}, 1), /price/);
  assert.throws(() => validateOffer({productId: 'p1', price: 9.999, days: 7}, 1), /decimals/);
  assert.equal(validateOffer({productId: 'p1', price: 99}, 1).days, null, 'no days: the offer runs with the plan (owner, 13 Nov 2026)');
  for (const days of [1, 2, 14, 120]) assert.throws(() => validateOffer({productId: 'p1', price: 99, days}, 1), /1 week, 1 month/, String(days));
});

test('a plan gives its own box number; without one Silver 1, Gold 3, Premium 5', () => {
  assert.equal(boxesOf({tier: 'silver'}), 1);
  assert.equal(boxesOf({tier: 'gold'}), 2);
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
  // The vendor chose 7 days; the admin's post duration does not apply to Today's Offers boxes any more (owner, 13 Nov 2026).
  assert.deepEqual(await submitOffer(db, bucket, uid, offer(1), NOW), {slot: 1, endsAt: NOW + 7 * DAY});
  const saved = await stored(db, uid, 1);
  assert.equal(saved.ownEndsAt.toMillis(), NOW + 7 * DAY, 'the days the vendor chose are kept');
  assert.deepEqual([saved.vendorId, saved.shopId, saved.productId, saved.name, saved.photoUrl, saved.price, saved.days, saved.slot],
    [uid, `shop-${uid}`, `${uid}-p1`, 'Item 1', 'https://example.com/1.jpg', 99, 7, 1]);
});

test('Gold plan with 3 boxes (set by the admin): a fourth item is refused unless a box is chosen to replace; the same item stays in its box', emulated, async () => {
  const {db, uid, bucket, offer} = await setup({tier: 'gold', offerBoxes: 3});
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
  await assert.rejects(submitOffer(free.db, free.bucket, free.uid, free.offer(), NOW), /paid plan/);
  const ended = await setup({planEndsAt: NOW});
  await assert.rejects(submitOffer(ended.db, ended.bucket, ended.uid, ended.offer(), NOW), /paid plan/, 'refused at the moment the plan ends');
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
  // An offer for 7 days posted 8 days ago has ended; one posted now for 30 days runs.
  const running = await setup();
  await submitOffer(running.db, running.bucket, running.uid, running.offer(1, {days: 30}), NOW);
  const {db, uid, bucket, offer} = await setup();
  await submitOffer(db, bucket, uid, offer(1), NOW - 8 * DAY);
  await clearEnded(db, bucket, NOW + DAY / 2);
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

// Owner, 13 Nov 2026: a catalog item or the vendor's own photo (checked by Claude Haiku; a fake AI answers), a short text, live while the
// plan runs, hidden when it ends and back on renewal, and the admin's Hide / Show.
const storage = {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST};
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0xff, 0xd9]);
const fakeAi = found => () => ({messages: {create: async () => ({stop_reason: 'end_turn', usage: {input_tokens: 10, output_tokens: 5}, content: [{type: 'text', text: JSON.stringify({found, note: 'x'})}]})}});

test('a catalog item with a short text runs until the plan ends', emulated, async () => {
  const {db, uid, bucket} = await setup({planEndsAt: NOW + 40 * DAY});
  await db.doc(`productImageLibrary/${uid}-lib`).set({name: 'Tomato', imageUrl: 'https://example.com/tomato.jpg', active: true});
  const result = await submitOffer(db, bucket, uid, {libraryItemId: `${uid}-lib`, price: 25, note: '  2 kg   only today '}, NOW);
  assert.deepEqual(result, {slot: 1, endsAt: NOW + 40 * DAY});
  const saved = await stored(db, uid, 1);
  assert.deepEqual([saved.name, saved.photoUrl, saved.note, saved.untilPlanEnds, saved.hidden, saved.libraryItemId], ['Tomato', 'https://example.com/tomato.jpg', '2 kg only today', true, false, `${uid}-lib`]);
  await assert.rejects(submitOffer(db, bucket, uid, {libraryItemId: 'missing-item', price: 25}, NOW), /catalog/);
  await assert.rejects(submitOffer(db, bucket, uid, {libraryItemId: `${uid}-lib`, price: 25, note: 'x'.repeat(61)}, NOW), /under 60/);
});

test('own photo: safe goes live, forbidden is refused and deleted, no check waits hidden for the admin', storage, async () => {
  const {getStorage} = require('firebase-admin/storage');
  const realBucket = getStorage().bucket();
  const {db, uid} = await setup({offerBoxes: 3});
  const put = name => realBucket.file(`vendorTodaysOffers/${uid}/${name}`).save(JPEG, {contentType: 'image/jpeg'});
  await put('a.jpg');
  const ok = await submitOffer(db, realBucket, uid, {photoName: 'a.jpg', name: 'Fresh fish', price: 180}, NOW, {makeClient: fakeAi([])});
  assert.equal(ok.waitingCheck, undefined);
  const live = await stored(db, uid, 1);
  assert.deepEqual([live.name, live.ownPhoto, live.hidden], ['Fresh fish', true, false]);
  assert.match(live.photoUrl, /vendorTodaysOffers%2F/);
  await put('b.jpg');
  await assert.rejects(submitOffer(db, realBucket, uid, {photoName: 'b.jpg', name: 'Beer', price: 100}, NOW, {makeClient: fakeAi(['alcohol'])}), /alcohol/);
  assert.equal((await realBucket.file(`vendorTodaysOffers/${uid}/b.jpg`).exists())[0], false);
  await put('c.jpg');
  const waiting = await submitOffer(db, realBucket, uid, {photoName: 'c.jpg', name: 'Mangoes', price: 90}, NOW);
  assert.equal(waiting.waitingCheck, true, 'no AI key in the tests: the admin decides');
  assert.deepEqual([(await stored(db, uid, waiting.slot)).hidden, (await stored(db, uid, waiting.slot)).waitingCheck], [true, true]);
  await setOfferHidden(db, `${uid}_${waiting.slot}`, false, NOW);
  assert.deepEqual([(await stored(db, uid, waiting.slot)).hidden, (await stored(db, uid, waiting.slot)).waitingCheck], [false, undefined]);
  // Replacing box 1 with an item deletes the own photo that was there.
  await submitOffer(db, realBucket, uid, {productId: `${uid}-p1`, price: 99, slot: 1}, NOW);
  assert.equal((await realBucket.file(`vendorTodaysOffers/${uid}/a.jpg`).exists())[0], false);
});

test('plan ends: the boxes are hidden, kept by the clean-up, and back on renewal; fewer boxes hide the extra ones', emulated, async () => {
  const {db, uid, bucket, offer} = await setup({planEndsAt: NOW + 10 * DAY, offerBoxes: 3});
  for (const n of [1, 2, 3]) await submitOffer(db, bucket, uid, offer(n, {days: null}), NOW);
  assert.equal((await stored(db, uid, 2)).endsAt.toMillis(), NOW + 10 * DAY);
  const ended = {active: false, tier: 'gold', offerBoxes: 3, endsAt: Timestamp.fromMillis(NOW + 10 * DAY)};
  await onPlanChange(db, uid, ended, NOW + 11 * DAY);
  await clearEnded(db, bucket, NOW + 12 * DAY);
  for (const n of [1, 2, 3]) assert.ok(await stored(db, uid, n), `box ${n} kept while the plan is off`);
  const renewed = {active: true, tier: 'gold', offerBoxes: 2, planName: 'Gold', endsAt: Timestamp.fromMillis(NOW + 400 * DAY)};
  await onPlanChange(db, uid, renewed, NOW + 13 * DAY);
  assert.equal((await stored(db, uid, 1)).endsAt.toMillis(), NOW + 400 * DAY, 'back on renewal');
  assert.equal((await stored(db, uid, 2)).planName, 'Gold');
  assert.ok((await stored(db, uid, 3)).endsAt.toMillis() <= NOW + 13 * DAY, 'the plan now gives 2 boxes: box 3 is hidden');
  // The admin stops the plan early: every box stops with it.
  await onPlanChange(db, uid, {active: false, tier: 'gold', offerBoxes: 2, endsAt: Timestamp.fromMillis(NOW + 20 * DAY)}, NOW + 20 * DAY);
  assert.equal((await stored(db, uid, 1)).endsAt.toMillis(), NOW + 20 * DAY);
});

test('the admin hides an offer (the vendor is told) and shows it again', emulated, async () => {
  const {db, uid, bucket, offer} = await setup();
  await submitOffer(db, bucket, uid, offer(1), NOW);
  assert.deepEqual(await setOfferHidden(db, `${uid}_1`, true, NOW), {hidden: true});
  assert.equal((await stored(db, uid, 1)).hidden, true);
  assert.equal((await db.collection('vendorNotices').where('vendorId', '==', uid).get()).size, 1);
  await setOfferHidden(db, `${uid}_1`, false, NOW);
  assert.equal((await stored(db, uid, 1)).hidden, false);
  await assert.rejects(setOfferHidden(db, 'nope', true, NOW), /not found/);
  await assert.rejects(setOfferHidden(db, `${uid}_1`, 'yes', NOW), /hide or show/);
});
