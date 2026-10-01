const {test} = require('node:test');
const assert = require('node:assert/strict');

// Field Assistant: staff self-registers (pending), an admin approves/rejects/
// suspends them, and every submission stays pending until an admin approves
// it — only then does a shop/product go live. Mirrors vendor-location.test.js's
// direct fns.xxx.run({auth, data}) pattern (no real Auth/HTTP needed).
test('field staff access, suspension and entry submission/review lifecycle', {
  skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST,
}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const fns = require('./index');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  const adminAuth = {auth: {uid: 'fieldAdmin', token: {admin: true, email_verified: true}}};
  await db.collection('_adminSessions').doc('fieldAdmin').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  await db.collection('settings').doc('business').set({});

  const staffAuth = (uid, extra = {}) => ({auth: {uid, token: {email_verified: true, email: `${uid}@example.test`, name: `Staff ${uid}`, ...extra}}});
  const stagePhoto = async path => bucket.file(path).save(Buffer.from([0xff, 0xd8, 0xff]), {metadata: {contentType: 'image/jpeg'}});
  // Stages `count` photos at fieldSubmissions/{uid}/{submissionId}_1..count.
  const stagePhotos = (uid, submissionId, count) => Promise.all(
    Array.from({length: count}, (_, i) => stagePhoto(`fieldSubmissions/${uid}/${submissionId}_${i + 1}`)),
  );
  const newShop = {name: 'Ramu Stores', address: '12 Market Road', pincode: '560001', latitude: 12.9716, longitude: 77.5946};
  const item = {name: 'Rice 5kg', price: 250, stock: 40};

  // ---- self-registration is idempotent and starts pending
  const uid = 'staff1';
  let result = await fns.requestFieldStaffAccess.run(staffAuth(uid));
  assert.equal(result.status, 'pending');
  result = await fns.requestFieldStaffAccess.run(staffAuth(uid));
  assert.equal(result.status, 'pending', 're-requesting is a no-op');

  // ---- a pending (not yet approved) staff member cannot submit
  await stagePhotos(uid, 'blocked', 1);
  await assert.rejects(() => fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: '', shop: newShop, item, submissionId: 'blocked', photoCount: 1, visitLatitude: 12.9, visitLongitude: 77.6}}), /approved/);

  // ---- only an admin can review, and only once
  await assert.rejects(() => fns.reviewFieldStaff.run({...staffAuth(uid), data: {staffUid: uid, approved: true}}), /Administrator/);
  await fns.reviewFieldStaff.run({...adminAuth, data: {staffUid: uid, approved: true}});
  assert.equal((await db.collection('fieldStaff').doc(uid).get()).data().status, 'active');
  await assert.rejects(() => fns.reviewFieldStaff.run({...adminAuth, data: {staffUid: uid, approved: true}}), /already reviewed/);

  // ---- submitFieldEntry validates photoCount, GPS, shop and item
  await assert.rejects(() => fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: '', shop: newShop, item, submissionId: 'x', visitLatitude: 1, visitLongitude: 1}}), /1 to 2 item photo/, 'photoCount is required (default limit is 2)');
  await assert.rejects(() => fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: '', shop: newShop, item, submissionId: 'x', photoCount: 3, visitLatitude: 1, visitLongitude: 1}}), /1 to 2 item photo/, 'default limit is 2, a 3rd photo is rejected');
  await assert.rejects(() => fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: '', shop: newShop, item, submissionId: 'novalidphoto', photoCount: 1}}), /GPS location/);
  await assert.rejects(() => fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: '', shop: {...newShop, pincode: '12'}, item, submissionId: 'x', photoCount: 1, visitLatitude: 1, visitLongitude: 1}}), /pincode/);
  await assert.rejects(() => fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: '', shop: newShop, item: {...item, price: -1}, submissionId: 'x', photoCount: 1, visitLatitude: 1, visitLongitude: 1}}), /price/);
  // valid details, but no photo was ever uploaded to this submissionId
  await assert.rejects(() => fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: '', shop: newShop, item, submissionId: 'neverUploaded', photoCount: 1, visitLatitude: 1, visitLongitude: 1}}), /Upload the item photo/);
  // only the first of 2 claimed photos was actually uploaded
  await stagePhotos(uid, 'partialUpload', 1);
  await assert.rejects(() => fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: '', shop: newShop, item, submissionId: 'partialUpload', photoCount: 2, visitLatitude: 1, visitLongitude: 1}}), /Upload the item photo/);

  // ---- a valid new-shop, 2-photo submission is queued as pending, nothing live yet
  await stagePhotos(uid, 'newShopEntry', 2);
  const submitted = await fns.submitFieldEntry.run({...staffAuth(uid), data: {
    shopId: '', shop: newShop, item, submissionId: 'newShopEntry', photoCount: 2, visitLatitude: 12.9716, visitLongitude: 77.5946,
  }});
  assert.equal(submitted.status, 'pending');
  const pendingDoc = (await db.collection('fieldSubmissions').doc(submitted.submissionId).get()).data();
  assert.equal(pendingDoc.staffUid, uid);
  assert.equal(pendingDoc.shop.name, 'Ramu Stores');
  assert.equal(pendingDoc.item.name, 'Rice 5kg');
  assert.deepEqual(pendingDoc.item.photoPaths, [`fieldSubmissions/${uid}/newShopEntry_1`, `fieldSubmissions/${uid}/newShopEntry_2`]);
  assert.equal(pendingDoc.visitLatitude, 12.9716);

  // ---- suspension blocks submission immediately, reinstatement restores it
  await fns.setFieldStaffSuspension.run({...adminAuth, data: {staffUid: uid, suspended: true, reason: 'On leave'}});
  await stagePhotos(uid, 'duringSuspension', 1);
  await assert.rejects(() => fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: '', shop: newShop, item, submissionId: 'duringSuspension', photoCount: 1, visitLatitude: 1, visitLongitude: 1}}), /approved/);
  await fns.setFieldStaffSuspension.run({...adminAuth, data: {staffUid: uid, suspended: false}});
  const afterReinstate = await fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: '', shop: newShop, item, submissionId: 'duringSuspension', photoCount: 1, visitLatitude: 1, visitLongitude: 1}});
  assert.equal(afterReinstate.status, 'pending');

  // ---- rejecting an entry deletes every private photo and leaves no live doc
  const [existsBeforeReject] = await bucket.file(`fieldSubmissions/${uid}/duringSuspension_1`).exists();
  assert.equal(existsBeforeReject, true);
  await fns.reviewFieldEntry.run({...adminAuth, data: {entryId: afterReinstate.submissionId, approved: false, reason: 'Duplicate'}});
  assert.equal((await db.collection('fieldSubmissions').doc(afterReinstate.submissionId).get()).data().status, 'rejected');
  const [existsAfterReject] = await bucket.file(`fieldSubmissions/${uid}/duringSuspension_1`).exists();
  assert.equal(existsAfterReject, false, 'a rejected entry\'s private photos are deleted');
  await assert.rejects(() => fns.reviewFieldEntry.run({...adminAuth, data: {entryId: afterReinstate.submissionId, approved: true}}), /already reviewed/);

  // ---- approving a new-shop, 2-photo entry creates a live, active shop AND
  // product, stamped with who captured them, with photo 1 as imageUrl and
  // photo 2 in the existing `images` gallery field (lib/ui/details.dart
  // already renders [imageUrl, ...images] — no customer-UI change needed)
  const approved = await fns.reviewFieldEntry.run({...adminAuth, data: {entryId: submitted.submissionId, approved: true}});
  assert.equal(approved.status, 'approved');
  const shop = (await db.collection('shops').doc(approved.shopId).get()).data();
  assert.equal(shop.active, true);
  assert.equal(shop.name, 'Ramu Stores');
  assert.equal(shop.createdByStaffUid, uid);
  const product = (await db.collection('products').doc(approved.productId).get()).data();
  assert.equal(product.active, true);
  assert.equal(product.name, 'Rice 5kg');
  assert.equal(product.price, 250);
  assert.equal(product.stock, 40);
  assert.equal(product.shopId, approved.shopId);
  assert.equal(product.createdByStaffUid, uid);
  assert.ok(product.imageUrl.includes(`catalog%2F${approved.productId}_1.jpg`), 'photo 1 becomes the primary imageUrl');
  assert.equal(product.images.length, 1);
  assert.ok(product.images[0].includes(`catalog%2F${approved.productId}_2.jpg`), 'photo 2 is in the images gallery array');
  const [photo1Exists] = await bucket.file(`catalog/${approved.productId}_1.jpg`).exists();
  const [photo2Exists] = await bucket.file(`catalog/${approved.productId}_2.jpg`).exists();
  assert.equal(photo1Exists, true);
  assert.equal(photo2Exists, true);
  const [private1Gone] = await bucket.file(`fieldSubmissions/${uid}/newShopEntry_1`).exists();
  const [private2Gone] = await bucket.file(`fieldSubmissions/${uid}/newShopEntry_2`).exists();
  assert.equal(private1Gone, false, 'private original 1 is removed once copied');
  assert.equal(private2Gone, false, 'private original 2 is removed once copied');

  // ---- raising fieldPhotoLimit allows more photos, independently of vendorPhotoLimit
  await db.collection('settings').doc('business').set({fieldPhotoLimit: 3, vendorPhotoLimit: 5}, {merge: true});
  await stagePhotos(uid, 'threePhotos', 3);
  const threePhoto = await fns.submitFieldEntry.run({...staffAuth(uid), data: {
    shopId: '', shop: newShop, item, submissionId: 'threePhotos', photoCount: 3, visitLatitude: 1, visitLongitude: 1,
  }});
  assert.equal(threePhoto.status, 'pending', 'raising fieldPhotoLimit to 3 allows a 3rd photo (vendorPhotoLimit=5 set alongside it has no effect on this field-only check)');
  await fns.reviewFieldEntry.run({...adminAuth, data: {entryId: threePhoto.submissionId, approved: false, reason: 'cleanup'}});
  await db.collection('settings').doc('business').set({}, {merge: false});

  // ---- an existing-shop submission reuses that shop, never creates a new one
  const existingShopId = 'existingShopX';
  await db.collection('shops').doc(existingShopId).set({name: 'Existing Shop', active: true});
  await stagePhotos(uid, 'existingShopEntry', 1);
  const existingSubmitted = await fns.submitFieldEntry.run({...staffAuth(uid), data: {
    shopId: existingShopId, item: {name: 'Another item', price: 50, stock: 5}, submissionId: 'existingShopEntry', photoCount: 1, visitLatitude: 12.9, visitLongitude: 77.5,
  }});
  const existingApproved = await fns.reviewFieldEntry.run({...adminAuth, data: {entryId: existingSubmitted.submissionId, approved: true}});
  assert.equal(existingApproved.shopId, existingShopId);
  const reusedShop = (await db.collection('shops').doc(existingShopId).get()).data();
  assert.equal(reusedShop.name, 'Existing Shop', 'the existing shop document is untouched, not overwritten');

  // ---- submitting against a shop id that does not exist is rejected
  await stagePhotos(uid, 'badShopId', 1);
  await assert.rejects(() => fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: 'doesNotExist', item, submissionId: 'badShopId', photoCount: 1, visitLatitude: 1, visitLongitude: 1}}), /not found/i);
});
