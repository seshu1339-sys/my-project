const {test} = require('node:test');
const assert = require('node:assert/strict');
const {cityCodeRows, cityCodeFor, vendorCodePrefix, autoCityCode, DEFAULT_CITY_CODES, VENDOR_CODE, ACCOUNT_CODE} = require('./vendor-id');

test('city codes: the built-in table, a pincode listed by the admin, a post-office name, and four letters for an unknown town', () => {
  assert.deepEqual(cityCodeRows({}).map(r => r.code), ['NRPM', 'TUNI', 'RAJH']);
  assert.equal(vendorCodePrefix('531116'), 'VEN-NRPM-116', 'Narsipatnam');
  assert.equal(vendorCodePrefix('533101'), 'VEN-RAJH-101', 'Rajahmundry');
  // Tuni's offices are filed under another town in the directory; the office name still finds it
  assert.equal(vendorCodePrefix('533401'), 'VEN-TUNI-401', 'Tuni');
  // Narsipatnam's other pincode: its office is "Krishna Bazar (Narsipatnam)"
  assert.equal(vendorCodePrefix('531118'), 'VEN-NRPM-118', 'Krishna Bazar (Narsipatnam)');
  assert.equal(autoCityCode('Krishna Bazar (Narsipatnam)'), 'NARS', 'the town in brackets');
  assert.deepEqual(cityCodeFor('531001'), {code: 'ANAK', town: 'Anakapalle', auto: true}, 'not in the table: four letters, marked auto');
  assert.equal(autoCityCode('Rly'), 'RLYX');
  assert.equal(vendorCodePrefix('999999'), 'VEN-XXXX-999', 'a pincode outside the directory');

  // the admin's table replaces the built-in one; invalid rows are ignored
  const rows = cityCodeRows({rows: [
    {town: 'Anakapalle', code: 'akp1'}, // not four letters: ignored
    {town: 'Anakapalle', code: 'akpl'},
    {town: 'Somewhere', code: 'SMWR', pincodes: '531001, 531002'},
  ]});
  assert.deepEqual(rows.map(r => r.code), ['AKPL', 'SMWR']);
  assert.equal(cityCodeFor('531001', rows).code, 'SMWR', 'a pincode listed on a row wins over the town name');
  assert.equal(cityCodeFor('531116', rows).code, 'NARS', 'Narsipatnam is not in this table: auto');
  assert.deepEqual(cityCodeRows({rows: [{town: '', code: 'ABCD'}]}), DEFAULT_CITY_CODES, 'no valid row: the built-in table');

  assert.ok(VENDOR_CODE.test('VEN-NRPM-116-325'));
  // field staff and service providers: the same shape with their own first part
  assert.equal(vendorCodePrefix('531116', undefined, 'STF'), 'STF-NRPM-116');
  assert.equal(vendorCodePrefix('533401', undefined, 'SRV'), 'SRV-TUNI-401');
  assert.ok(ACCOUNT_CODE.STF.test('STF-NRPM-116-001'));
  assert.ok(!ACCOUNT_CODE.STF.test('STF00001'), 'the earlier staff IDs are a different shape');
  assert.ok(ACCOUNT_CODE.SRV.test('SRV-NRPM-116-042'));
  assert.ok(!VENDOR_CODE.test('VN00001'));
});

test('a vendor gets VEN-<CITY>-<PIN>-<NNN> when applying, keeps it on resubmission, and the vendor record gets the same ID', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const fns = require('./index');
  const {reserveVendorCode} = require('./vendor-id');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  const admin = {auth: {uid: 'admin1', token: {admin: true, email_verified: true}}};
  await db.collection('_adminSessions').doc('admin1').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  const application = pincode => ({
    ownerName: 'Ramu', phone: '9876500009', name: 'Ramu Kirana', shopCategory: 'Kirana',
    address: 'Main Road, Narsipatnam', pincode, description: 'Rice, dal and oil at fair prices', latitude: 17.668, longitude: 82.612,
  });
  const stagePhotos = async uid => {
    for (const name of ['vendorPhoto', 'shopPhoto']) await bucket.file(`vendorApplications/${uid}/${name}`).save(Buffer.from([0xff, 0xd8, 0xff]), {metadata: {contentType: 'image/jpeg'}});
  };
  const register = (uid, data) => fns.registerVendor.run({auth: {uid, token: {email_verified: true}}, data});

  await stagePhotos('idV1');
  const out = await register('idV1', application('531116'));
  assert.match(out.vendorCode, /^VEN-NRPM-116-\d{3}$/);
  const app = (await db.collection('vendorApplications').doc('idV1').get()).data();
  assert.equal(app.vendorCode, out.vendorCode);

  // rejected, then resubmitted with the same pincode: the same ID
  await fns.approveVendor.run({...admin, data: {vendorId: 'idV1', approved: false, reason: 'Photo unclear'}});
  const again = await register('idV1', application('531116'));
  assert.equal(again.vendorCode, out.vendorCode);

  // approved: the vendor record has the same ID
  await fns.approveVendor.run({...admin, data: {vendorId: 'idV1', approved: true}});
  assert.equal((await db.collection('vendors').doc('idV1').get()).data().vendorCode, out.vendorCode);

  // the admin's own table is used for new IDs
  await db.collection('settings').doc('cityCodes').set({rows: [{town: 'Narsipatnam', code: 'NPTM'}]});
  await stagePhotos('idV2');
  assert.match((await register('idV2', application('531116'))).vendorCode, /^VEN-NPTM-116-\d{3}$/);
  await db.collection('settings').doc('cityCodes').delete();

  // two reservations of the same prefix never give the same ID, even when the random number repeats
  const a = await reserveVendorCode(db, 'VEN-TEST-001', 'x', () => 0.5);
  const b = await reserveVendorCode(db, 'VEN-TEST-001', 'y', () => 0.5);
  assert.notEqual(a, b);
  assert.match(b, /^VEN-TEST-001-\d{3}$/);

  // a vendor record created without an ID (e.g. by another path) gets one from its application through the trigger
  await stagePhotos('idV3');
  await register('idV3', application('533401'));
  const appCode = (await db.collection('vendorApplications').doc('idV3').get()).data().vendorCode;
  assert.match(appCode, /^VEN-TUNI-401-\d{3}$/);
  const vendorRef = db.collection('vendors').doc('idV3');
  await vendorRef.set({vendorId: 'idV3', status: 'approved'});
  await fns.assignVendorCode.run({data: {ref: vendorRef}, params: {uid: 'idV3'}});
  assert.equal((await vendorRef.get()).data().vendorCode, appCode);
  // and a record that already has one keeps it
  await fns.assignVendorCode.run({data: {ref: vendorRef}, params: {uid: 'idV3'}});
  assert.equal((await vendorRef.get()).data().vendorCode, appCode);
});
