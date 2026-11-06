const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly', storageBucket: 'demo-neighbourly.appspot.com'});
const {Timestamp} = require('firebase-admin/firestore');
const {vendorPhotoAllowance, vendorPhotosUsed} = require('../../plan-gate');
const S = require('./store');

const fakeDb = (gates, premium) => ({
  collection: name => ({doc: () => ({get: async () => ({data: () => (name === 'planServiceGates' ? gates : premium)})})}),
});

test('the allowance: free 2 extra photos (or the admin\'s number); a running paid plan its own number; the shop photo is never counted', async () => {
  const now = Date.parse('2027-06-01T00:00:00Z');
  const running = n => ({active: true, endsAt: Timestamp.fromMillis(now + 1000), extraPhotos: n});
  assert.deepEqual(await vendorPhotoAllowance(fakeDb(undefined, undefined), 'v', now), {paid: false, free: 2, extras: 2});
  assert.equal((await vendorPhotoAllowance(fakeDb({freeExtraPhotos: 3}, undefined), 'v', now)).extras, 3);
  assert.equal((await vendorPhotoAllowance(fakeDb(undefined, running(10)), 'v', now)).extras, 10);
  assert.equal((await vendorPhotoAllowance(fakeDb(undefined, running(4)), 'v', now)).extras, 4, 'Silver');
  assert.equal((await vendorPhotoAllowance(fakeDb(undefined, {...running(10), endsAt: Timestamp.fromMillis(now - 1)}), 'v', now)).extras, 2, 'ended');
});

const emulator = {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST};
const T = Date.parse('2031-03-05T10:00:00+05:30');
async function setup() {
  const {getFirestore} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  for (const c of ['vendors', 'products', 'vendorItemPhotos', 'vendorShopPhotos', 'vendorPremium', 'planServiceGates', 'categories', 'shops']) {
    for (const d of (await db.collection(c).get()).docs) await d.ref.delete();
  }
  await db.collection('vendors').doc('v1').set({status: 'approved', name: 'Lakshmi', shopId: 'v1'});
  await db.collection('categories').doc('sarees').set({name: 'Sarees', ownPhotoRequired: true});
  await db.collection('categories').doc('veg').set({name: 'Vegetables'});
  const product = (id, categoryId, extra = {}) => db.collection('products').doc(id).set({ownerId: 'v1', name: id, categoryId, imageUrl: 'https://lib/x.jpg', libraryImageUrl: 'https://lib/x.jpg', active: true, ...extra});
  const upload = path => bucket.file(path).save(Buffer.from([0xff, 0xd8, 0xff]), {metadata: {contentType: 'image/jpeg'}});
  const shopPhoto = (slot, status = 'approved') => db.collection('vendorShopPhotos').doc(`v1_${slot}`).set({vendorId: 'v1', slot, status, path: `vendorShopPhotos/v1/shopPhoto${slot}`});
  return {db, bucket, product, upload, shopPhoto};
}

test('own item photos share the allowance with extra shop photos; replacing needs no room; the shop photo is free', emulator, async () => {
  const {db, bucket, product, upload, shopPhoto} = await setup();
  await shopPhoto(1); // the shop photo: never counted
  await shopPhoto(2);
  await product('p1', 'veg');
  await product('p2', 'veg');
  await upload(S.privatePath('v1', 'p1'));
  await upload(S.privatePath('v1', 'p2'));
  assert.equal((await S.submitItemPhoto(db, bucket, 'v1', {productId: 'p1'}, T)).status, 'pending');
  assert.equal(await vendorPhotosUsed(db, 'v1'), 2);
  await assert.rejects(S.submitItemPhoto(db, bucket, 'v1', {productId: 'p2'}, T), /all 2 extra photos/);
  assert.equal((await S.submitItemPhoto(db, bucket, 'v1', {productId: 'p1'}, T + 1000)).status, 'pending', 'replacing p1 needs no room');
  await db.collection('vendorPremium').doc('v1').set({active: true, endsAt: Timestamp.fromMillis(T + 86400000), extraPhotos: 10});
  assert.equal((await S.submitItemPhoto(db, bucket, 'v1', {productId: 'p2'}, T)).status, 'pending', 'a paid plan has room');
  await assert.rejects(S.submitItemPhoto(db, bucket, 'v2', {productId: 'p1'}, T), /approved/);
});

test('the admin photo check: approved becomes the item photo (and shows a hidden saree); rejected is deleted', emulator, async () => {
  const {db, bucket, product, upload} = await setup();
  await product('saree', 'sarees', {active: false, awaitingOwnPhoto: true});
  await upload(S.privatePath('v1', 'saree'));
  await S.submitItemPhoto(db, bucket, 'v1', {productId: 'saree'}, T);
  await S.reviewItemPhoto(db, bucket, {productId: 'saree', approved: true}, T);
  const saree = (await db.collection('products').doc('saree').get()).data();
  assert.equal(saree.active, true);
  assert.equal(saree.ownPhoto, true);
  assert.match(saree.imageUrl, /item_saree/);
  assert.equal(saree.awaitingOwnPhoto, undefined);
  await product('p3', 'veg');
  await upload(S.privatePath('v1', 'p3'));
  await S.submitItemPhoto(db, bucket, 'v1', {productId: 'p3'}, T);
  await S.reviewItemPhoto(db, bucket, {productId: 'p3', approved: false, reason: 'blurred'}, T);
  assert.equal((await bucket.file(S.privatePath('v1', 'p3')).exists())[0], false, 'deleted from Storage');
  await assert.rejects(S.reviewItemPhoto(db, bucket, {productId: 'p3', approved: true}, T), /already reviewed/);
});

test('removing an own photo goes back to our photo; a saree is hidden again', emulator, async () => {
  const {db, bucket, product, upload} = await setup();
  await product('saree', 'sarees', {ownPhoto: true, imageUrl: 'https://own/s.jpg'});
  await db.collection('vendorItemPhotos').doc('saree').set({vendorId: 'v1', status: 'approved', path: S.privatePath('v1', 'saree')});
  await upload(S.privatePath('v1', 'saree'));
  await S.removeItemPhoto(db, bucket, 'v1', {productId: 'saree'}, T);
  const saree = (await db.collection('products').doc('saree').get()).data();
  assert.deepEqual([saree.imageUrl, saree.ownPhoto, saree.active, saree.awaitingOwnPhoto], ['https://lib/x.jpg', false, false, true]);
});

test('a paid plan ends: the first 2 extra photos stay (shop slots first), the rest are deleted', emulator, async () => {
  const {db, bucket, product, upload, shopPhoto} = await setup();
  await shopPhoto(1);
  for (const slot of [2, 3, 4]) {
    await shopPhoto(slot);
    await upload(`vendorShopPhotos/v1/shopPhoto${slot}`);
  }
  await product('p1', 'veg', {ownPhoto: true, imageUrl: 'https://own/p1.jpg'});
  await db.collection('vendorItemPhotos').doc('p1').set({vendorId: 'v1', status: 'approved', path: S.privatePath('v1', 'p1'), submittedAt: Timestamp.fromMillis(T)});
  assert.equal(await S.trimAfterPlan(db, bucket, 'v1', 2, T), 2);
  const left = (await db.collection('vendorShopPhotos').where('vendorId', '==', 'v1').get()).docs.map(d => d.data().slot).sort();
  assert.deepEqual(left, [1, 2, 3], 'the shop photo and the first 2 extras stay');
  assert.equal((await bucket.file('vendorShopPhotos/v1/shopPhoto4').exists())[0], false);
  assert.equal((await db.collection('products').doc('p1').get()).data().imageUrl, 'https://lib/x.jpg', 'the item is back on our photo');
});

test('the vendor chooses how long an item shows in search (1 week to 3 months), also when sending an own photo', emulator, async () => {
  const {db, bucket, product, upload} = await setup();
  await product('p1', 'veg');
  const DAY = 86400000;
  assert.deepEqual(await S.setItemSearchTime(db, 'v1', {productId: 'p1', days: 30}, T), {searchUntilMs: T + 30 * DAY});
  assert.equal((await db.collection('products').doc('p1').get()).data().searchUntilMs, T + 30 * DAY);
  await assert.rejects(S.setItemSearchTime(db, 'v1', {productId: 'p1', days: 10}, T), /1 week, 1 month/);
  await assert.rejects(S.setItemSearchTime(db, 'someoneElse', {productId: 'p1', days: 7}, T), /your item/);
  await upload(S.privatePath('v1', 'p1'));
  await S.submitItemPhoto(db, bucket, 'v1', {productId: 'p1', searchDays: 90}, T);
  assert.equal((await db.collection('products').doc('p1').get()).data().searchUntilMs, T + 90 * DAY);
  await assert.rejects(S.submitItemPhoto(db, bucket, 'v1', {productId: 'p1', searchDays: 3}, T), /1 week, 1 month/);
});
