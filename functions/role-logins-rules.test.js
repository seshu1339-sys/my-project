const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, Timestamp} = require('firebase/firestore');
const {ref, uploadBytes} = require('firebase/storage');

// The database rules for ONE email with a login in every role (functions/role-logins.js): the customer, vendor, service-provider and
// staff logins have different uids, and none of them reads another's records. The email's own login (Google / email code / password,
// no role) reads and writes nothing, and an admin claim counts only on the admin login.
const projectId = process.env.GCLOUD_PROJECT || 'demo-neighbourly';
const email = 'same.person@example.test';
const login = role => ({role, loginEmail: email});

test('same email, different roles: no role login sees another role\'s records', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const env = await initializeTestEnvironment({projectId, firestore: {rules: readFileSync(resolve(__dirname, '../firestore.rules'), 'utf8')}});
  try {
    await env.withSecurityRulesDisabled(async ctx => {
      const f = ctx.firestore();
      await setDoc(doc(f, 'users/U'), {customer: true, email, name: 'As a customer'});
      await setDoc(doc(f, 'users/V'), {language: 'te'});
      await setDoc(doc(f, 'orders/mine'), {userId: 'U', shopIds: ['shopElsewhere'], status: 'submitted', lines: [], total: 1});
      await setDoc(doc(f, 'orders/atMyShop'), {userId: 'someoneElse', shopIds: ['shopV'], status: 'submitted', lines: [], total: 1});
      await setDoc(doc(f, 'vendors/V'), {vendorId: 'V', status: 'approved', shopId: 'shopV', email});
      await setDoc(doc(f, 'vendorApplications/V'), {status: 'approved', email});
      await setDoc(doc(f, 'providers/P'), {status: 'approved', email});
      await setDoc(doc(f, 'providerApplications/P'), {status: 'approved', email});
      await setDoc(doc(f, 'fieldStaff/S'), {status: 'pending', email});
      await setDoc(doc(f, 'accountStates/V'), {disabled: false});
      // An admin session for the customer login too, so only the role decides below.
      await setDoc(doc(f, '_adminSessions/U'), {expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
      await setDoc(doc(f, '_adminSessions/A'), {expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
    });
    const as = (uid, claims) => env.authenticatedContext(uid, claims).firestore();
    const customer = as('U', login('user')), vendor = as('V', login('vendor')), provider = as('P', login('provider')), staff = as('S', login('staff'));
    const admin = as('A', {...login('admin'), admin: true});
    const read = (db, path) => getDoc(doc(db, path));

    // Each login reads its own records.
    await assertSucceeds(read(customer, 'users/U'));
    await assertSucceeds(read(customer, 'orders/mine'));
    await assertSucceeds(read(vendor, 'vendors/V'));
    await assertSucceeds(read(vendor, 'vendorApplications/V'));
    await assertSucceeds(read(vendor, 'orders/atMyShop'));
    await assertSucceeds(read(provider, 'providers/P'));
    await assertSucceeds(read(provider, 'providerApplications/P'));
    await assertSucceeds(read(staff, 'fieldStaff/S'));

    // ...and never the same email's other roles: not the customer profile or orders from the vendor app, not the vendor records
    // from the customer app, and nothing across provider and staff.
    for (const db of [vendor, provider, staff]) {
      await assertFails(read(db, 'users/U'));
      await assertFails(read(db, 'orders/mine'));
    }
    for (const db of [customer, provider, staff]) {
      await assertFails(read(db, 'vendors/V'));
      await assertFails(read(db, 'vendorApplications/V'));
      await assertFails(read(db, 'orders/atMyShop'));
    }
    for (const db of [customer, vendor, staff]) await assertFails(read(db, 'providers/P'));
    for (const db of [customer, vendor, provider]) await assertFails(read(db, 'fieldStaff/S'));
    await assertFails(read(customer, 'users/V'));
    // The vendor app's Help chat checks all four vendor-app records under the login's own uid (13 Nov 2026 fix): a provider login
    // may look for a vendor record under its own uid and a vendor login for a provider record (none exists there, so nothing shows)...
    await assertSucceeds(read(provider, 'vendors/P'));
    await assertSucceeds(read(provider, 'vendorApplications/P'));
    await assertSucceeds(read(vendor, 'providers/V'));
    await assertSucceeds(read(vendor, 'providerApplications/V'));
    // ...but never another person's record, and never from the customer or staff app.
    await assertFails(read(provider, 'vendors/V'));
    await assertFails(read(vendor, 'providers/P'));
    for (const db of [customer, staff]) {
      await assertFails(read(db, 'providerApplications/P'));
      await assertFails(read(db, 'vendorApplications/V'));
    }
    await assertFails(read(as('U', login('user')), 'providerApplications/U'));
    await assertFails(read(as('S', login('staff')), 'vendors/S'));
    // A record under a login's own uid but of another role's kind is still refused (a vendor record is read only as a vendor).
    await assertFails(read(as('V', login('user')), 'vendors/V'));

    // The email's own login proves the email only: no role, so not even "its own" profile.
    const proofOnly = as('U', {email, email_verified: true});
    await assertFails(read(proofOnly, 'users/U'));
    await assertFails(setDoc(doc(proofOnly, 'users/U'), {name: 'x'}, {merge: true}));
    await assertFails(read(proofOnly, 'orders/mine'));

    // Admin power only on the admin login: an admin claim on the customer login (even with a session) is refused.
    await assertSucceeds(read(admin, 'accountStates/V'));
    await assertSucceeds(read(admin, 'users/U'));
    await assertFails(read(as('U', {...login('user'), admin: true}), 'accountStates/V'));
    await assertFails(read(as('U', {email, email_verified: true, admin: true}), 'accountStates/V'));
  } finally {
    await env.cleanup();
  }
});

test('same email, different roles: storage uploads only into the role\'s own folder', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  const [host, port] = process.env.FIREBASE_STORAGE_EMULATOR_HOST.split(':');
  const env = await initializeTestEnvironment({
    projectId,
    firestore: {rules: readFileSync(resolve(__dirname, '../firestore.rules'), 'utf8')},
    storage: {rules: readFileSync(resolve(__dirname, '../storage.rules'), 'utf8'), host, port: Number(port)},
  });
  try {
    const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
    const put = (uid, claims, path) => uploadBytes(ref(env.authenticatedContext(uid, claims).storage(), path), jpeg, {contentType: 'image/jpeg'});
    // The vendor login uploads its application photo; the customer login and the email's own login of the same person cannot.
    await assertSucceeds(put('V2', login('vendor'), 'vendorApplications/V2/vendorPhoto'));
    await assertFails(put('U2', login('user'), 'vendorApplications/U2/vendorPhoto'));
    await assertFails(put('I2', {email, email_verified: true}, 'vendorApplications/I2/vendorPhoto'));
    // Likewise for the provider and staff application photos.
    await assertSucceeds(put('P2', login('provider'), 'providerApplications/P2/photo'));
    await assertFails(put('V2', login('vendor'), 'providerApplications/V2/photo'));
    await assertSucceeds(put('S2', login('staff'), 'fieldStaffApplications/S2/staffPhoto'));
    await assertFails(put('U2', login('user'), 'fieldStaffApplications/U2/staffPhoto'));
  } finally {
    await env.cleanup();
  }
});
