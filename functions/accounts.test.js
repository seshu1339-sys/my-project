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
  await assert.rejects(() => fns.registerVendor.run({...as('accStaff'), data: vendorData}), /already registered in another role. Please use a different email/);
  await photo('providerApplications/accStaff/photo');
  await assert.rejects(() => fns.registerProvider.run({...as('accStaff'), data: providerData}), /already registered in another role/);
  assert.equal((await db.collection('vendorApplications').doc('accStaff').get()).exists, false);
  assert.equal((await db.collection('providerApplications').doc('accStaff').get()).exists, false);

  // ---- a vendor account and a service-provider account cannot become field staff
  await db.collection('vendorApplications').doc('accVendor').set({status: 'pending'});
  await photo('fieldStaffApplications/accVendor/staffPhoto');
  await assert.rejects(() => fns.requestFieldStaffAccess.run({...as('accVendor'), data: staffData}), /already registered in another role/);
  await db.collection('providerApplications').doc('accProvider').set({status: 'pending'});
  await photo('fieldStaffApplications/accProvider/staffPhoto');
  await assert.rejects(() => fns.requestFieldStaffAccess.run({...as('accProvider'), data: staffData}), /already registered in another role/);
  assert.equal((await db.collection('fieldStaff').doc('accVendor').get()).exists, false);
  assert.equal((await db.collection('fieldStaff').doc('accProvider').get()).exists, false);

  // ---- an admin-made Quick Add staff account counts as staff
  await db.collection('quickAccounts').doc('accQuick').set({role: 'staff', code: 'ST001'});
  assert.equal((await accountKinds(db, 'accQuick')).staff, true);
  await assert.rejects(() => fns.registerVendor.run({...as('accQuick'), data: vendorData}), /already registered in another role/);
});

// The role follows the EMAIL: the first role an email registers in is saved (emailRoles), and the same email is refused in
// the other roles (at registration and at sign-in to the vendor / staff app), while the customer app is open to everyone.
test('one email holds one of vendor, provider or staff; the customer app is open to every email', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  const {getFirestore} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const fns = require('./index');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  const as = (uid, email) => ({auth: {uid, token: {email_verified: true, email}}});
  const taken = /This email is already registered in another role\. Please use a different email\./;
  const staffData = {name: 'Kiran Kumar', phone: '9876543210', latitude: 17.668, longitude: 82.612, pincode: '531116'};

  // a new email may sign in to either app, and a customer record is made on the first customer login
  assert.equal((await fns.claimAppRole.run({...as('roleU1', 'Role.One@Example.test'), data: {app: 'staff'}})).role, '');
  assert.equal((await fns.claimAppRole.run({...as('roleU1', 'Role.One@Example.test'), data: {app: 'user'}})).role, 'customer');
  assert.equal((await db.collection('users').doc('roleU1').get()).data().customer, true);
  await assert.rejects(() => fns.claimAppRole.run({data: {app: 'user'}}), /Sign in/);
  await assert.rejects(() => fns.claimAppRole.run({...as('roleU1', 'role.one@example.test'), data: {app: 'admin'}}), /Unknown app/);

  // registering as staff saves the role against the (lower-cased) email
  await bucket.file('fieldStaffApplications/roleU1/staffPhoto').save(Buffer.from([0xff, 0xd8, 0xff]), {metadata: {contentType: 'image/jpeg'}});
  await fns.requestFieldStaffAccess.run({...as('roleU1', 'Role.One@Example.test'), data: staffData});
  assert.equal((await db.collection('emailRoles').doc('role.one@example.test').get()).data().role, 'staff');

  // the same email is refused by the vendor app, even from a different account (uid), but not by the staff or customer app
  await assert.rejects(() => fns.claimAppRole.run({...as('roleU2', 'role.one@example.test'), data: {app: 'vendor'}}), taken);
  assert.equal((await fns.claimAppRole.run({...as('roleU1', 'role.one@example.test'), data: {app: 'staff'}})).role, 'staff');
  assert.equal((await fns.claimAppRole.run({...as('roleU2', 'role.one@example.test'), data: {app: 'user'}})).role, 'customer');

  // a vendor email is refused by the staff app, but a vendor-app login is fine
  await db.collection('emailRoles').doc('v@example.test').set({role: 'vendor'});
  await assert.rejects(() => fns.claimAppRole.run({...as('roleV', 'v@example.test'), data: {app: 'staff'}}), taken);
  assert.equal((await fns.claimAppRole.run({...as('roleV', 'v@example.test'), data: {app: 'vendor'}})).role, 'vendor');
  // service providers use the vendor app too
  await db.collection('emailRoles').doc('p@example.test').set({role: 'provider'});
  assert.equal((await fns.claimAppRole.run({...as('roleP', 'p@example.test'), data: {app: 'vendor'}})).role, 'provider');
  await assert.rejects(() => fns.claimAppRole.run({...as('roleP', 'p@example.test'), data: {app: 'staff'}}), taken);

  // registering the other role with a different uid but the same email is refused too
  await db.collection('emailRoles').doc('w@example.test').set({role: 'vendor'});
  await bucket.file('fieldStaffApplications/roleW/staffPhoto').save(Buffer.from([0xff, 0xd8, 0xff]), {metadata: {contentType: 'image/jpeg'}});
  await assert.rejects(() => fns.requestFieldStaffAccess.run({...as('roleW', 'w@example.test'), data: staffData}), taken);
});
