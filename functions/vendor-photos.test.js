const {test} = require('node:test');
const assert = require('node:assert/strict');

test('vendor shop photos: pending, approve/reject, and 15-day expiry', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const fns = require('./index');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  const admin = {auth: {uid: 'admin1', token: {admin: true, email_verified: true}}};
  const vendor = {auth: {uid: 'spV', token: {email_verified: true}}};
  const submit = (data, ctx = vendor) => fns.submitShopPhoto.run({...ctx, data});
  const review = (data, ctx = admin) => fns.reviewShopPhoto.run({...ctx, data});
  const upload = (uid, slot) => bucket.file(`vendorShopPhotos/${uid}/shopPhoto${slot}`).save(Buffer.from([0xff, 0xd8, 0xff]), {metadata: {contentType: 'image/jpeg'}});
  const exists = async path => (await bucket.file(path).exists())[0];

  await db.collection('vendors').doc('spV').set({vendorId: 'spV', name: 'Sp Shop', shopId: 'spShop', status: 'approved'});
  await db.collection('vendors').doc('notApproved').set({vendorId: 'notApproved', name: 'Pending Shop', status: 'payment_required'});

  // ---- validation and access
  await assert.rejects(() => submit({slot: 3}), /slot 1 or 2/);
  await assert.rejects(() => submit({slot: 1}, {auth: {uid: 'notApproved', token: {email_verified: true}}}), /approved/);
  await assert.rejects(() => submit({slot: 1}), /Upload the photo/); // nothing uploaded to Storage yet

  // ---- submit slot 1: upload first, then submit
  await upload('spV', 1);
  const out = await submit({slot: 1});
  assert.equal(out.status, 'pending');
  let doc = (await db.collection('vendorShopPhotos').doc('spV_1').get()).data();
  assert.equal(doc.status, 'pending'); assert.equal(doc.vendorId, 'spV'); assert.equal(doc.shopId, 'spShop'); assert.ok(doc.submittedAt);

  // ---- admin review: access control and one-shot guard
  await assert.rejects(() => review({vendorId: 'spV', slot: 1, approved: true}, vendor), /Administrator/);
  await review({vendorId: 'spV', slot: 1, approved: true});
  doc = (await db.collection('vendorShopPhotos').doc('spV_1').get()).data();
  assert.equal(doc.status, 'approved'); assert.ok(doc.decidedAt);
  await assert.rejects(() => review({vendorId: 'spV', slot: 1, approved: true}), /already reviewed/);
  assert.ok(await exists('vendorShopPhotos/spV/shopPhoto1'), 'an approved photo keeps its Storage object');

  // ---- submit + reject slot 2: the Storage object is deleted right away, reason is recorded
  await upload('spV', 2);
  await submit({slot: 2});
  await review({vendorId: 'spV', slot: 2, approved: false, reason: 'Too blurry'});
  doc = (await db.collection('vendorShopPhotos').doc('spV_2').get()).data();
  assert.equal(doc.status, 'rejected'); assert.equal(doc.decisionReason, 'Too blurry');
  assert.ok(!(await exists('vendorShopPhotos/spV/shopPhoto2')), 'a rejected photo is deleted from Storage immediately');

  // ---- re-upload after rejection resets the same slot to pending
  await upload('spV', 2);
  await submit({slot: 2});
  doc = (await db.collection('vendorShopPhotos').doc('spV_2').get()).data();
  assert.equal(doc.status, 'pending'); assert.equal(doc.decisionReason, undefined);

  // ---- 15-day expiry via the daily maintenance schedule: an old pending photo is deleted...
  await db.collection('vendorShopPhotos').doc('spV_2').update({submittedAt: Timestamp.fromMillis(Date.now() - 16 * 86400000)});
  await upload('spV', 2); // recreate the object the doc still points at, so we can prove it gets removed
  await fns.dailyStorageMaintenance.run({});
  assert.equal((await db.collection('vendorShopPhotos').doc('spV_2').get()).exists, false, 'a 16-day-old pending photo record is deleted');
  assert.ok(!(await exists('vendorShopPhotos/spV/shopPhoto2')), 'and its Storage object goes with it');
  // ...but a recently-approved photo and a fresh pending one are untouched
  assert.equal((await db.collection('vendorShopPhotos').doc('spV_1').get()).exists, true);
});
