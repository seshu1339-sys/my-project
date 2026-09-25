const {test} = require('node:test');
const assert = require('node:assert/strict');

test('vendor registration requires GPS coordinates, and they carry onto the approved vendor record', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const fns = require('./index');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  const admin = {auth: {uid: 'admin1', token: {admin: true, email_verified: true}}};
  // Admin callables now also require a fresh OTP-verified session (see admin-otp.js).
  await db.collection('_adminSessions').doc('admin1').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  const application = uid => ({
    ownerName: 'GPS Owner', phone: '9876500009', name: 'GPS Shop', shopCategory: 'General',
    address: '1 Coordinate Lane', pincode: '560001', description: 'A shop with a captured location',
    latitude: 12.9716, longitude: 77.5946,
  });
  const stagePhotos = async uid => {
    await bucket.file(`vendorApplications/${uid}/vendorPhoto`).save(Buffer.from([0xff, 0xd8, 0xff]), {metadata: {contentType: 'image/jpeg'}});
    await bucket.file(`vendorApplications/${uid}/shopPhoto`).save(Buffer.from([0xff, 0xd8, 0xff]), {metadata: {contentType: 'image/jpeg'}});
  };
  const register = (uid, data) => fns.registerVendor.run({auth: {uid, token: {email_verified: true}}, data});

  // ---- registerVendor refuses missing or invalid coordinates; the application is never created
  const gpsV = 'gpsV';
  await stagePhotos(gpsV);
  await assert.rejects(() => register(gpsV, {...application(gpsV), latitude: undefined}), /GPS location/);
  assert.equal((await db.collection('vendorApplications').doc(gpsV).get()).exists, false, 'no application is left behind by a rejected attempt');
  await assert.rejects(() => register(gpsV, {...application(gpsV), latitude: 'not a number'}), /GPS location/);
  await assert.rejects(() => register(gpsV, {...application(gpsV), latitude: 200}), /GPS location/);

  // ---- a valid submission stores the coordinates on the application
  const out = await register(gpsV, application(gpsV));
  assert.equal(out.status, 'pending');
  let app = (await db.collection('vendorApplications').doc(gpsV).get()).data();
  assert.equal(app.latitude, 12.9716); assert.equal(app.longitude, 77.5946);

  // ---- approveVendor (no fee) carries the coordinates onto vendors/{uid}
  await fns.approveVendor.run({...admin, data: {vendorId: gpsV, approved: true}});
  let vendor = (await db.collection('vendors').doc(gpsV).get()).data();
  assert.equal(vendor.latitude, 12.9716); assert.equal(vendor.longitude, 77.5946);
  assert.equal(vendor.verified, false, 'self-reported registration GPS is not the same as admin-verified location');

  // ---- the fee-payment path (confirmVendorFeePayment) also carries the coordinates
  const feeV = 'feeGpsV';
  await stagePhotos(feeV);
  await register(feeV, application(feeV));
  await fns.approveVendor.run({...admin, data: {vendorId: feeV, approved: true, feeRequired: true, feeAmount: 500}});
  await db.collection('vendorApplications').doc(feeV).update({status: 'payment_submitted', feePaymentStatus: 'submitted'});
  await fns.confirmVendorFeePayment.run({...admin, data: {vendorId: feeV, paid: true}});
  vendor = (await db.collection('vendors').doc(feeV).get()).data();
  assert.equal(vendor.latitude, 12.9716); assert.equal(vendor.longitude, 77.5946);
});
