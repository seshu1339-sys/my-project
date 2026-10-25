const {test} = require('node:test');
const assert = require('node:assert/strict');

// Vendor, service-provider and field-staff accounts are completely separate: each registration refuses a login that is already
// another kind of account, and says which.
test('one login is only ever a vendor, a service provider or field staff', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  const {getFirestore} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const fns = require('./index');
  const {accountKinds} = require('./accounts');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  const as = uid => ({auth: {uid, token: {email_verified: true, email: `${uid}@example.test`}}});
  const photo = path => bucket.file(path).save(Buffer.from([0xff, 0xd8, 0xff]), {metadata: {contentType: 'image/jpeg'}});
  const here = {latitude: 17.668, longitude: 82.612, pincode: '531116'};
  const staffData = {name: 'Kiran Kumar', phone: '9876543210', ...here};
  const vendorData = {ownerName: 'S K', phone: '9876543210', name: 'Shop', shopCategory: 'Kirana', address: 'Main Road, Narsipatnam', pincode: '531116', description: 'A shop for testing here', latitude: 17.668, longitude: 82.612};
  const providerData = {name: 'Suresh Kumar', phone: '9876543210', serviceTypeId: 'type-plumber', hourlyRate: 250, address: 'Door 4-12, Gandhi Nagar, Narsipatnam', pincode: '531116', latitude: 17.668, longitude: 82.612};
  await db.collection('services').doc('type-plumber').set({kind: 'serviceType', typeId: 'plumber', name: 'Plumber', active: true});

  // ---- a field-staff account cannot become a vendor or a service provider
  await photo('fieldStaffApplications/accStaff/staffPhoto');
  assert.equal((await fns.requestFieldStaffAccess.run({...as('accStaff'), data: staffData})).status, 'pending');
  assert.deepEqual(await accountKinds(db, 'accStaff'), {vendor: false, provider: false, staff: true});
  await assert.rejects(() => fns.registerVendor.run({...as('accStaff'), data: vendorData}), /field-staff account\. Register as a vendor/);
  await photo('providerApplications/accStaff/photo');
  await assert.rejects(() => fns.registerProvider.run({...as('accStaff'), data: providerData}), /field-staff account\. Register as a service provider/);
  assert.equal((await db.collection('vendorApplications').doc('accStaff').get()).exists, false);
  assert.equal((await db.collection('providerApplications').doc('accStaff').get()).exists, false);

  // ---- a vendor account and a service-provider account cannot become field staff
  await db.collection('vendorApplications').doc('accVendor').set({status: 'pending'});
  await photo('fieldStaffApplications/accVendor/staffPhoto');
  await assert.rejects(() => fns.requestFieldStaffAccess.run({...as('accVendor'), data: staffData}), /vendor account\. Register as field staff/);
  await db.collection('providerApplications').doc('accProvider').set({status: 'pending'});
  await photo('fieldStaffApplications/accProvider/staffPhoto');
  await assert.rejects(() => fns.requestFieldStaffAccess.run({...as('accProvider'), data: staffData}), /service-provider account\. Register as field staff/);
  assert.equal((await db.collection('fieldStaff').doc('accVendor').get()).exists, false);
  assert.equal((await db.collection('fieldStaff').doc('accProvider').get()).exists, false);

  // ---- an admin-made Quick Add staff account counts as staff
  await db.collection('quickAccounts').doc('accQuick').set({role: 'staff', code: 'ST001'});
  assert.equal((await accountKinds(db, 'accQuick')).staff, true);
  await assert.rejects(() => fns.registerVendor.run({...as('accQuick'), data: vendorData}), /field-staff account/);
});
