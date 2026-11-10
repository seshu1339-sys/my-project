const {test} = require('node:test');
const assert = require('node:assert/strict');

// One email, a separate login per role (functions/role-logins.js). The person uses the same email in every app; each role gets its own
// login ID, its own records and its own block / delete, and nothing is shared between them. Needs the Auth, Firestore and Storage
// emulators (the logins are real Firebase Auth users).
const ready = !!(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_STORAGE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);

function setup() {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const {getAuth} = require('firebase-admin/auth');
  const fns = require('./index');
  const {_roleLogins} = require('./role-logins');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  /// The email's own login, as Google / the email code / a password leaves it: the email proven, no role.
  const proof = email => ({auth: {uid: `proof-${email}`, token: {email_verified: true, email}}});
  const enter = async (email, role) => fns.enterRole.run({...proof(email), data: {role}});
  /// A call made by a role login, with the claims Firebase Auth really holds for it.
  const as = async uid => ({auth: {uid, token: {...(await getAuth().getUser(uid)).customClaims}}});
  const photo = path => bucket.file(path).save(Buffer.from([0xff, 0xd8, 0xff]), {metadata: {contentType: 'image/jpeg'}});
  const adminFor = async email => {
    const uid = await _roleLogins.roleLoginFor('admin', email);
    await db.collection('_adminSessions').doc(uid).set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
    return as(uid);
  };
  return {db, fns, getAuth, proof, enter, as, photo, adminFor};
}

const vendorData = {ownerName: 'S K', phone: '9876543210', name: 'Shop', shopCategory: 'Kirana', address: 'Main Road, Narsipatnam', pincode: '531116', description: 'A shop for testing here', latitude: 17.668, longitude: 82.612};
const staffData = {name: 'Kiran Kumar', phone: '9876543210', latitude: 17.668, longitude: 82.612, pincode: '531116'};

test('one email gets a separate login, with its own ID, as a customer, vendor, service provider and staff member', {skip: !ready}, async () => {
  const {db, fns, getAuth, proof, enter, as} = setup();
  const typed = 'Same.Person@Example.test', email = 'same.person@example.test';
  const roles = ['user', 'vendor', 'provider', 'staff'];
  const logins = {};
  for (const role of roles) {
    const result = await enter(typed, role);
    assert.equal(result.role, role);
    assert.ok(typeof result.token === 'string' && result.token.length > 20, 'a sign-in token for the role login');
    logins[role] = result.uid;
  }
  assert.equal(new Set(Object.values(logins)).size, 4, 'four different login IDs');
  for (const role of roles) {
    const user = await getAuth().getUser(logins[role]);
    assert.deepEqual(user.customClaims, {role, loginEmail: email});
    assert.equal(user.email, undefined, 'a role login has no email of its own, so the email may repeat across roles');
    assert.equal((await enter(email, role)).uid, logins[role], 'the same login every time');
  }
  // The customer record is made for the customer login only.
  assert.equal((await db.collection('users').doc(logins.user).get()).data().customer, true);
  assert.equal((await db.collection('users').doc(logins.vendor).get()).exists, false);

  // The email's own login proves the email and nothing else: every function refuses it.
  await assert.rejects(() => fns.registerVendor.run({...proof(email), data: vendorData}), /Sign in again/);
  await assert.rejects(() => fns.consentStatus.run({...proof(email), data: {}}), /Sign in again/);
  // enterRole needs a proven email, a known role, and is not for a role login.
  await assert.rejects(() => fns.enterRole.run({auth: {uid: 'x', token: {email_verified: false, email}}, data: {role: 'user'}}), /Verify your email/);
  await assert.rejects(() => fns.enterRole.run({data: {role: 'user'}}), /Sign in first/);
  await assert.rejects(() => enter(email, 'owner'), /Unknown app/);
  await assert.rejects(async () => fns.enterRole.run({...(await as(logins.vendor)), data: {role: 'user'}}), /already signed in/);
  // The admin login exists only when set up with functions/set-admin.js.
  await assert.rejects(() => enter(email, 'admin'), /Administrator access required/);
});

test('same email as a customer and a vendor: separate records; only the vendor login registers a shop; approval touches only it', {skip: !ready}, async () => {
  const {db, fns, enter, as, photo, adminFor} = setup();
  const email = 'shop.owner@example.test';
  const u = (await enter(email, 'user')).uid, v = (await enter(email, 'vendor')).uid;
  for (const uid of [u, v]) for (const name of ['vendorPhoto', 'shopPhoto']) await photo(`vendorApplications/${uid}/${name}`);
  await assert.rejects(async () => fns.registerVendor.run({...(await as(u)), data: vendorData}), /only in the vendor app/);
  assert.equal((await db.collection('vendorApplications').doc(u).get()).exists, false);
  const registered = await fns.registerVendor.run({...(await as(v)), data: vendorData});
  assert.equal(registered.status, 'pending');
  const application = (await db.collection('vendorApplications').doc(v).get()).data();
  assert.equal(application.email, email);
  assert.equal(application.vendorId, v, 'linked to the vendor login ID, never to the email');
  // A vendor login places no orders; that is the customer login's.
  await assert.rejects(async () => fns.placeOrder.run({...(await as(v)), data: {}}), /only in the LOCAMARKET app/);

  const admin = await adminFor('owner.one@example.test');
  await fns.approveVendor.run({...admin, data: {vendorId: v, approved: true}});
  assert.equal((await db.collection('vendors').doc(v).get()).data().status, 'approved');
  assert.equal((await db.collection('vendors').doc(u).get()).exists, false, 'the customer login is not a vendor');
  assert.equal((await db.collection('users').doc(u).get()).data().customer, true);
  assert.equal((await enter(email, 'user')).uid, u, 'the customer login is unchanged');
});

test('same email as a customer and staff: the staff record stays pending, and pending staff cannot submit anything', {skip: !ready}, async () => {
  const {db, fns, enter, as, photo, adminFor} = setup();
  const email = 'staff.person@example.test';
  const u = (await enter(email, 'user')).uid, s = (await enter(email, 'staff')).uid;
  await photo(`fieldStaffApplications/${u}/staffPhoto`);
  await photo(`fieldStaffApplications/${s}/staffPhoto`);
  await assert.rejects(async () => fns.requestFieldStaffAccess.run({...(await as(u)), data: staffData}), /only in the staff app/);
  const asked = await fns.requestFieldStaffAccess.run({...(await as(s)), data: staffData});
  assert.equal(asked.status, 'pending');
  const staff = (await db.collection('fieldStaff').doc(s).get()).data();
  assert.equal(staff.status, 'pending');
  assert.equal(staff.email, email);
  assert.equal((await db.collection('fieldStaff').doc(u).get()).exists, false);
  // Pending: nothing can be submitted until an administrator approves.
  const offer = {shopId: 'shop1', libraryItemId: 'item1', regularPrice: 100, offerPrice: 80};
  await assert.rejects(async () => fns.addStaffTodayOffer.run({...(await as(s)), data: offer}), /Only approved staff/);
  // The customer login of the same email cannot use the staff actions at all.
  await assert.rejects(async () => fns.addStaffTodayOffer.run({...(await as(u)), data: offer}), /only in the staff app/);
  const admin = await adminFor('owner.two@example.test');
  await fns.reviewFieldStaff.run({...admin, data: {staffUid: s, approved: true}});
  assert.equal((await db.collection('fieldStaff').doc(s).get()).data().status, 'active');
  assert.equal((await enter(email, 'user')).uid, u, 'approving the staff login leaves the customer login as it was');
  assert.equal((await db.collection('fieldStaff').doc(u).get()).exists, false);
});

test('blocking or deleting one role never changes the email\'s other roles', {skip: !ready}, async () => {
  const {db, fns, getAuth, enter, as, adminFor} = setup();
  const email = 'every.role@example.test';
  const ids = {};
  for (const role of ['user', 'vendor', 'provider', 'staff']) ids[role] = (await enter(email, role)).uid;
  const admin = await adminFor('owner.three@example.test');

  await fns.setAccountDisabled.run({...admin, data: {uid: ids.vendor, disabled: true}});
  await assert.rejects(() => enter(email, 'vendor'), error => {
    assert.match(error.message, /vendor account is blocked/);
    assert.deepEqual(error.details, {blocked: 'vendor'});
    return true;
  });
  for (const role of ['user', 'provider', 'staff']) assert.equal((await enter(email, role)).uid, ids[role], `${role} still signs in`);
  await assert.rejects(async () => fns.switchRole.run({...(await as(ids.provider)), data: {to: 'vendor'}}), /vendor account is blocked/);
  await fns.setAccountDisabled.run({...admin, data: {uid: ids.vendor, disabled: false}});
  assert.equal((await enter(email, 'vendor')).uid, ids.vendor);

  // The email's own login is never disabled here: that would lock the person out of every role.
  const own = await getAuth().createUser({email, emailVerified: true});
  await assert.rejects(() => fns.setAccountDisabled.run({...admin, data: {uid: own.uid, disabled: true}}), /not an app account/);

  // Deleting the customer login removes only it (and its customer data); the other logins stay, and the next customer sign-in
  // starts a new, empty customer login.
  await fns.deleteInactiveAccount.run({...admin, data: {uid: ids.user, confirm: 'DELETE'}});
  await assert.rejects(() => getAuth().getUser(ids.user), /no user record/i);
  for (const role of ['vendor', 'provider', 'staff']) assert.equal((await getAuth().getUser(ids[role])).disabled, false);
  assert.equal((await getAuth().getUser(own.uid)).disabled, false);
  const fresh = (await enter(email, 'user')).uid;
  assert.notEqual(fresh, ids.user);
  assert.equal((await db.collection('users').doc(fresh).get()).data().customer, true);
  // Vendor, provider and staff logins cannot be deleted here.
  await assert.rejects(() => fns.deleteInactiveAccount.run({...admin, data: {uid: ids.vendor, confirm: 'DELETE'}}), /Only customer accounts/);
});

test('admin power is only on the admin login, never on the same email\'s other logins', {skip: !ready}, async () => {
  const {getAuth, enter, as, adminFor, fns} = setup();
  const email = 'the.owner@example.test';
  const admin = await adminFor(email);
  const a = (await enter(email, 'admin')).uid;
  assert.equal(a, admin.auth.uid);
  assert.deepEqual((await getAuth().getUser(a)).customClaims, {role: 'admin', loginEmail: email, admin: true});
  const u = (await enter(email, 'user')).uid;
  assert.notEqual(u, a);
  assert.deepEqual((await getAuth().getUser(u)).customClaims, {role: 'user', loginEmail: email});
  // Even a forged admin claim on a customer login is refused: admin needs the admin login itself.
  const {db} = setup();
  const {Timestamp} = require('firebase-admin/firestore');
  await db.collection('_adminSessions').doc(u).set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  await assert.rejects(() => fns.reviewFieldStaff.run({auth: {uid: u, token: {role: 'user', loginEmail: email, admin: true}}, data: {staffUid: 'x', approved: true}}), /Administrator access required/);
  await assert.rejects(async () => fns.inactiveAccounts.run({...(await as(u)), data: {days: 7}}), /Administrator access required/);
  assert.ok((await fns.inactiveAccounts.run({...admin, data: {days: 7}})).accounts);
  await assert.rejects(() => fns.setAccountDisabled.run({...admin, data: {uid: a, disabled: true}}), /own account/);
});

test('the vendor app switches only between the email\'s Vendor and Service-provider logins', {skip: !ready}, async () => {
  const {fns, enter, as} = setup();
  const email = 'two.kinds@example.test';
  const v = (await enter(email, 'vendor')).uid, p = (await enter(email, 'provider')).uid;
  const toProvider = await fns.switchRole.run({...(await as(v)), data: {to: 'provider'}});
  assert.equal(toProvider.uid, p);
  assert.equal(toProvider.role, 'provider');
  assert.equal((await fns.switchRole.run({...(await as(p)), data: {to: 'vendor'}})).uid, v);
  await assert.rejects(async () => fns.switchRole.run({...(await as(v)), data: {to: 'vendor'}}), /already signed in as that/);
  await assert.rejects(async () => fns.switchRole.run({...(await as(v)), data: {to: 'staff'}}), /Vendor or Service provider/);
  const u = (await enter(email, 'user')).uid, s = (await enter(email, 'staff')).uid;
  await assert.rejects(async () => fns.switchRole.run({...(await as(u)), data: {to: 'vendor'}}), /only between Vendor and Service provider/);
  await assert.rejects(async () => fns.switchRole.run({...(await as(s)), data: {to: 'provider'}}), /only between Vendor and Service provider/);
});
