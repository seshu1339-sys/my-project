const {test} = require('node:test');
const assert = require('node:assert/strict');

// Field Assistant: staff self-registers (pending), an admin approves/rejects/
// suspends them, and every submission stays pending until an admin approves
// it — only then does a shop/product go live. Mirrors vendor-location.test.js's
// direct fns.xxx.run({auth, data}) pattern (no real Auth/HTTP needed).
test('field staff access and suspension; New entry is closed, an old entry can still be rejected', {
  skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST,
}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const fns = require('./index');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  const adminAuth = {auth: {uid: 'fieldAdmin', token: {role: 'admin', admin: true, email_verified: true}}};
  await db.collection('_adminSessions').doc('fieldAdmin').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  await db.collection('settings').doc('business').set({});

  const staffAuth = (uid, extra = {}) => ({auth: {uid, token: {role: 'staff', loginEmail: `${uid}@example.test`, name: `Staff ${uid}`, ...extra}}});
  const stagePhoto = async path => bucket.file(path).save(Buffer.from([0xff, 0xd8, 0xff]), {metadata: {contentType: 'image/jpeg'}});
  // Stages `count` photos at fieldSubmissions/{uid}/{submissionId}_1..count.
  const stagePhotos = (uid, submissionId, count) => Promise.all(
    Array.from({length: count}, (_, i) => stagePhoto(`fieldSubmissions/${uid}/${submissionId}_${i + 1}`)),
  );
  const newShop = {name: 'Ramu Stores', address: '12 Market Road', pincode: '560001', latitude: 12.9716, longitude: 77.5946};
  await db.collection('categories').doc('cat-grocery').set({name: 'Grocery', active: true});
  const item = {name: 'Rice 5kg', price: 250, stock: 40, categoryId: 'cat-grocery'};

  // ---- self-registration requires a name, phone, the location (GPS and its pincode) and mandatory staff photo
  const uid = 'staff1';
  const here = {latitude: 17.668, longitude: 82.612, pincode: '531116', gpsAddress: 'Gandhi Nagar, Narsipatnam, 531116'};
  await assert.rejects(() => fns.requestFieldStaffAccess.run({...staffAuth(uid), data: {name: 'Staff One', phone: '+911234567890', ...here}}), /photo/i, 'the staff photo is mandatory');
  await assert.rejects(() => fns.requestFieldStaffAccess.run({...staffAuth(uid), data: {phone: '+911234567890', ...here}}), /name/i, 'name is required');
  await stagePhoto(`fieldStaffApplications/${uid}/staffPhoto`);
  await assert.rejects(() => fns.requestFieldStaffAccess.run({...staffAuth(uid), data: {name: 'Staff One', ...here}}), /phone/i, 'phone is required');
  await assert.rejects(() => fns.requestFieldStaffAccess.run({...staffAuth(uid), data: {name: 'Staff One', phone: '+911234567890'}}), /location/i, 'the location is required');
  await assert.rejects(() => fns.requestFieldStaffAccess.run({...staffAuth(uid), data: {name: 'Staff One', phone: '+911234567890', ...here, pincode: '5311'}}), /pincode/i);

  // ---- self-registration is idempotent and starts pending, with the Staff ID made from the pincode (STF-NRPM-116-NNN)
  let result = await fns.requestFieldStaffAccess.run({...staffAuth(uid), data: {name: 'Staff One', phone: '+911234567890', ...here}});
  assert.equal(result.status, 'pending');
  assert.match(result.staffCode, /^STF-NRPM-116-\d{3}$/);
  result = await fns.requestFieldStaffAccess.run({...staffAuth(uid), data: {name: 'Staff One', phone: '+911234567890', ...here}});
  assert.equal(result.status, 'pending', 're-requesting is a no-op');
  const registered = (await db.collection('fieldStaff').doc(uid).get()).data();
  assert.equal(registered.phone, '+911234567890');
  assert.equal(registered.staffCode, result.staffCode, 'the same ID, kept');
  assert.deepEqual([registered.latitude, registered.longitude, registered.pincode, registered.town], [17.668, 82.612, '531116', 'Narsipatnam']);
  assert.equal(registered.gpsAddress, 'Gandhi Nagar, Narsipatnam, 531116');

  // ---- only an admin can review, and only once
  await assert.rejects(() => fns.reviewFieldStaff.run({...staffAuth(uid), data: {staffUid: uid, approved: true}}), /Administrator/);
  await fns.reviewFieldStaff.run({...adminAuth, data: {staffUid: uid, approved: true}});
  assert.equal((await db.collection('fieldStaff').doc(uid).get()).data().status, 'active');
  await assert.rejects(() => fns.reviewFieldStaff.run({...adminAuth, data: {staffUid: uid, approved: true}}), /already reviewed/);

  // ---- "New entry" is closed (owner, 6 Nov 2026): even an approved staff member's entry is refused
  await stagePhotos(uid, 'closedEntry', 1);
  await assert.rejects(() => fns.submitFieldEntry.run({...staffAuth(uid), data: {shopId: '', shop: newShop, item, submissionId: 'closedEntry', photoCount: 1, visitLatitude: 12.9716, visitLongitude: 77.5946}}), /New entry is closed/);

  // ---- suspension and reinstatement
  await fns.setFieldStaffSuspension.run({...adminAuth, data: {staffUid: uid, suspended: true, reason: 'On leave'}});
  assert.equal((await db.collection('fieldStaff').doc(uid).get()).data().status, 'suspended');
  await fns.setFieldStaffSuspension.run({...adminAuth, data: {staffUid: uid, suspended: false}});
  assert.equal((await db.collection('fieldStaff').doc(uid).get()).data().status, 'active');

  // ---- an old entry still waiting can be rejected; its private photos are deleted
  await stagePhotos(uid, 'oldEntry', 1);
  const old = await db.collection('fieldSubmissions').add({staffUid: uid, status: 'pending', shopId: '', shop: newShop, item: {...item, photoPaths: [`fieldSubmissions/${uid}/oldEntry_1`]}, submittedAt: Timestamp.now()});
  await fns.reviewFieldEntry.run({...adminAuth, data: {entryId: old.id, approved: false, reason: 'Closed'}});
  assert.equal((await db.collection('fieldSubmissions').doc(old.id).get()).data().status, 'rejected');
  assert.equal((await bucket.file(`fieldSubmissions/${uid}/oldEntry_1`).exists())[0], false);
});
