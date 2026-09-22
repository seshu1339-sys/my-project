const {test} = require('node:test');
const assert = require('node:assert/strict');

test('storage maintenance: usage monitoring and orphan sweeps leave fresh/referenced files alone', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  const {getFirestore} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const fns = require('./index');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  const exists = async path => (await bucket.file(path).exists())[0];

  // ---- usage monitoring: reuses the existing analyticsTotals collection/rule, no new one
  await bucket.file('vendorProducts/smV/a.jpg').save(Buffer.from([1, 2, 3, 4, 5]));
  await bucket.file('vendorProducts/smV/b.jpg').save(Buffer.from([1, 2, 3]));
  await fns.weeklyStorageUsage.run({});
  const usage = (await db.collection('analyticsTotals').doc('storageUsage').get()).data();
  assert.ok(usage.bytesUsed >= 8, `expected at least 8 bytes, got ${usage.bytesUsed}`);
  assert.ok(usage.objectCount >= 2, `expected at least 2 objects, got ${usage.objectCount}`);
  assert.ok(usage.updatedAt);

  // ---- orphan sweep: a shop photo object with NO Firestore record, uploaded moments ago, must
  // survive the 24-hour grace period (protects an in-flight upload from being raced).
  await db.collection('vendors').doc('smV').set({vendorId: 'smV', name: 'SM Shop', shopId: 'smShop', status: 'approved'});
  await bucket.file('vendorShopPhotos/smV/shopPhoto1').save(Buffer.from([0xff, 0xd8]), {metadata: {contentType: 'image/jpeg'}});
  await fns.dailyStorageMaintenance.run({});
  assert.ok(await exists('vendorShopPhotos/smV/shopPhoto1'), 'a just-uploaded orphan is not deleted before its grace period passes');

  // ---- a vendorProducts object referenced by a live product's imageUrl is never treated as an orphan
  await db.collection('products').doc('smP').set({name: 'Referenced', price: 1, ownerId: 'smV', shopId: 'smShop', active: true, imageUrl: 'http://127.0.0.1:9199/v0/b/x/o/vendorProducts%2FsmV%2Fa.jpg?alt=media'});
  await fns.dailyStorageMaintenance.run({});
  assert.ok(await exists('vendorProducts/smV/a.jpg'), 'a referenced photo is never swept as an orphan');
});
