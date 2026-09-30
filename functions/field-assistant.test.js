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

  const staffAuth = (uid, extra = {}) => ({auth: {uid, token: {email_verified: true, email: `${uid}@example.test`, name: `Staff ${uid}`, ...extra}}});
  const stagePhoto = async path => bucket.file(path).save(Buffer.from([0xff, 0xd8, 0xff]), {metadata: {contentType: 'image/jpeg'}});
  const newShop = {name: 'Ramu Stores', address: '12 Market Road', pincode: '560001', latitude: 12.9716, longitude: 77.5946};
  const item = {name: 'Rice 5kg', price: 250, stock: 40};

  // ---- self-registration is idempotent and starts pending
  const uid = 'staff1';
  let result = await fns.requestFieldStaffAccess.run(staffAuth(uid));
  assert.equal(result.status, 'pending');
  result = await fns.requestFieldStaffAccess.run(staffAuth(uid));
  assert.equal(result.status, 'pending', 're-requesting is a no-op');

  // ---- a pending (not yet approved) staff member cannot submit
  await stagePhoto(`fieldSubmissions/${uid}/blocked`);
  await assert.rejects(() => fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: '', shop: newShop, item, submissionId: 'blocked', visitLatitude: 12.9, visitLongitude: 77.6}}), /approved/);

  // ---- only an admin can review, and only once
  await assert.rejects(() => fns.reviewFieldStaff.run({...staffAuth(uid), data: {staffUid: uid, approved: true}}), /Administrator/);
  await fns.reviewFieldStaff.run({...adminAuth, data: {staffUid: uid, approved: true}});
  assert.equal((await db.collection('fieldStaff').doc(uid).get()).data().status, 'active');
  await assert.rejects(() => fns.reviewFieldStaff.run({...adminAuth, data: {staffUid: uid, approved: true}}), /already reviewed/);

  // ---- submitFieldEntry validates GPS, shop and item before touching Storage
  await assert.rejects(() => fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: '', shop: newShop, item, submissionId: 'novalidphoto'}}), /GPS location/);
  await assert.rejects(() => fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: '', shop: {...newShop, pincode: '12'}, item, submissionId: 'x', visitLatitude: 1, visitLongitude: 1}}), /pincode/);
  await assert.rejects(() => fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: '', shop: newShop, item: {...item, price: -1}, submissionId: 'x', visitLatitude: 1, visitLongitude: 1}}), /price/);
  // valid details, but the photo was never uploaded to this submissionId
  await assert.rejects(() => fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: '', shop: newShop, item, submissionId: 'neverUploaded', visitLatitude: 1, visitLongitude: 1}}), /Upload the item photo/);

  // ---- a valid new-shop submission is queued as pending, nothing live yet
  await stagePhoto(`fieldSubmissions/${uid}/newShopEntry`);
  const submitted = await fns.submitFieldEntry.run({...staffAuth(uid), data: {
    shopId: '', shop: newShop, item, submissionId: 'newShopEntry', visitLatitude: 12.9716, visitLongitude: 77.5946,
  }});
  assert.equal(submitted.status, 'pending');
  const pendingDoc = (await db.collection('fieldSubmissions').doc(submitted.submissionId).get()).data();
  assert.equal(pendingDoc.staffUid, uid);
  assert.equal(pendingDoc.shop.name, 'Ramu Stores');
  assert.equal(pendingDoc.item.name, 'Rice 5kg');
  assert.equal(pendingDoc.item.photoPath, `fieldSubmissions/${uid}/newShopEntry`);
  assert.equal(pendingDoc.visitLatitude, 12.9716);

  // ---- suspension blocks submission immediately, reinstatement restores it
  await fns.setFieldStaffSuspension.run({...adminAuth, data: {staffUid: uid, suspended: true, reason: 'On leave'}});
  await stagePhoto(`fieldSubmissions/${uid}/duringSuspension`);
  await assert.rejects(() => fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: '', shop: newShop, item, submissionId: 'duringSuspension', visitLatitude: 1, visitLongitude: 1}}), /approved/);
  await fns.setFieldStaffSuspension.run({...adminAuth, data: {staffUid: uid, suspended: false}});
  const afterReinstate = await fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: '', shop: newShop, item, submissionId: 'duringSuspension', visitLatitude: 1, visitLongitude: 1}});
  assert.equal(afterReinstate.status, 'pending');

  // ---- rejecting an entry deletes the private photo and leaves no live doc
  const [existsBeforeReject] = await bucket.file(`fieldSubmissions/${uid}/duringSuspension`).exists();
  assert.equal(existsBeforeReject, true);
  await fns.reviewFieldEntry.run({...adminAuth, data: {entryId: afterReinstate.submissionId, approved: false, reason: 'Duplicate'}});
  assert.equal((await db.collection('fieldSubmissions').doc(afterReinstate.submissionId).get()).data().status, 'rejected');
  const [existsAfterReject] = await bucket.file(`fieldSubmissions/${uid}/duringSuspension`).exists();
  assert.equal(existsAfterReject, false, 'a rejected entry\'s private photo is deleted');
  await assert.rejects(() => fns.reviewFieldEntry.run({...adminAuth, data: {entryId: afterReinstate.submissionId, approved: true}}), /already reviewed/);

  // ---- approving a new-shop entry creates a live, active shop AND product,
  // stamped with who captured them, and copies the photo into catalog/
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
  assert.ok(product.imageUrl.includes('catalog%2F'), 'the photo was copied into the public catalog/ convention');
  const [publicPhotoExists] = await bucket.file(`catalog/${approved.productId}.jpg`).exists();
  assert.equal(publicPhotoExists, true);
  const [privatePhotoGone] = await bucket.file(`fieldSubmissions/${uid}/newShopEntry`).exists();
  assert.equal(privatePhotoGone, false, 'the private original is removed once copied');

  // ---- an existing-shop submission reuses that shop, never creates a new one
  const existingShopId = 'existingShopX';
  await db.collection('shops').doc(existingShopId).set({name: 'Existing Shop', active: true});
  await stagePhoto(`fieldSubmissions/${uid}/existingShopEntry`);
  const existingSubmitted = await fns.submitFieldEntry.run({...staffAuth(uid), data: {
    shopId: existingShopId, item: {name: 'Another item', price: 50, stock: 5}, submissionId: 'existingShopEntry', visitLatitude: 12.9, visitLongitude: 77.5,
  }});
  const existingApproved = await fns.reviewFieldEntry.run({...adminAuth, data: {entryId: existingSubmitted.submissionId, approved: true}});
  assert.equal(existingApproved.shopId, existingShopId);
  const reusedShop = (await db.collection('shops').doc(existingShopId).get()).data();
  assert.equal(reusedShop.name, 'Existing Shop', 'the existing shop document is untouched, not overwritten');

  // ---- submitting against a shop id that does not exist is rejected
  await stagePhoto(`fieldSubmissions/${uid}/badShopId`);
  await assert.rejects(() => fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: 'doesNotExist', item, submissionId: 'badShopId', visitLatitude: 1, visitLongitude: 1}}), /not found/i);
});
