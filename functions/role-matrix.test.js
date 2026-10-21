const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, deleteDoc, Timestamp} = require('firebase/firestore');

// Who may touch what, for every kind of signed-in person the four apps have. The apps hide screens by role, but this is what
// actually keeps the roles apart: a customer, a vendor or a staff member cannot read or change another role's data even by
// calling Firestore directly.
test('role matrix: customer, vendor, staff, Quick Add accounts and admin each see only their own data', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-neighbourly', firestore: {rules: readFileSync(resolve(__dirname, '../firestore.rules'), 'utf8')}});
  try {
    await env.withSecurityRulesDisabled(async ctx => {
      const f = ctx.firestore();
      await setDoc(doc(f, '_adminSessions/boss'), {expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
      await setDoc(doc(f, 'vendors/vend'), {vendorId: 'vend', status: 'approved', shopId: 'shopV'});
      await setDoc(doc(f, 'vendors/other'), {vendorId: 'other', status: 'approved', shopId: 'shopO'});
      await setDoc(doc(f, 'vendorApplications/vend'), {status: 'approved'});
      await setDoc(doc(f, 'vendorChanges/c1'), {vendorId: 'vend', status: 'pending'});
      await setDoc(doc(f, 'fieldStaff/staff'), {status: 'active'});
      await setDoc(doc(f, 'fieldStaff/staff2'), {status: 'active'});
      await setDoc(doc(f, 'fieldSubmissions/s1'), {staffUid: 'staff', status: 'pending'});
      await setDoc(doc(f, 'quickAccounts/qs'), {role: 'staff', code: 'ST001', active: true});
      await setDoc(doc(f, 'quickAccounts/qv'), {role: 'vendor', code: 'VN001', active: true});
      await setDoc(doc(f, 'quickItems/qi1'), {status: 'pending', ownerUid: 'qs'});
      await setDoc(doc(f, 'quickItems/qi2'), {status: 'approved', ownerUid: 'qv'});
      await setDoc(doc(f, 'orders/o1'), {userId: 'cust', status: 'submitted', shopIds: ['shopV'], lines: [], total: 1});
      await setDoc(doc(f, 'users/cust'), {name: 'Customer'});
      await setDoc(doc(f, 'products/p1'), {name: 'P', active: true});
    });
    const as = (uid, claims = {}) => env.authenticatedContext(uid, {email_verified: true, ...claims}).firestore();
    const who = {
      anonymous: env.unauthenticatedContext().firestore(),
      customer: as('cust'),
      vendor: as('vend'),
      otherVendor: as('other'),
      staff: as('staff'),
      otherStaff: as('staff2'),
      quickStaff: as('qs'),
      quickVendor: as('qv'),
      admin: as('boss', {admin: true}),
    };
    const can = (name, path, op = 'read') => {
      const ref = doc(who[name], path);
      return op === 'read' ? assertSucceeds(getDoc(ref)) : assertSucceeds(setDoc(ref, {x: 1}, {merge: true}));
    };
    const cannot = (name, path, op = 'read') => {
      const ref = doc(who[name], path);
      return op === 'read' ? assertFails(getDoc(ref)) : assertFails(setDoc(ref, {x: 1}, {merge: true}));
    };

    // ---- everyone reads the public catalog; only the admin writes it
    for (const name of Object.keys(who)) await can(name, 'products/p1');
    for (const name of Object.keys(who)) {
      if (name === 'admin') await can(name, 'products/p1', 'write');
      else for (const path of ['products/p1', 'promotions/x', 'settings/business', 'categories/c', 'shops/s', 'locations/l']) await cannot(name, path, 'write');
    }
    // ---- vendor records: the vendor and the admin only
    await can('vendor', 'vendors/vend'); await can('admin', 'vendors/vend');
    for (const name of ['anonymous', 'customer', 'otherVendor', 'staff', 'quickStaff']) await cannot(name, 'vendors/vend');
    await can('vendor', 'vendorApplications/vend'); await can('admin', 'vendorApplications/vend');
    for (const name of ['customer', 'otherVendor', 'staff']) await cannot(name, 'vendorApplications/vend');
    await can('vendor', 'vendorChanges/c1'); await can('admin', 'vendorChanges/c1');
    for (const name of ['customer', 'otherVendor', 'staff']) await cannot(name, 'vendorChanges/c1');
    // ---- field staff records
    await can('staff', 'fieldStaff/staff'); await can('admin', 'fieldStaff/staff');
    for (const name of ['customer', 'vendor', 'otherStaff', 'anonymous']) await cannot(name, 'fieldStaff/staff');
    await can('staff', 'fieldSubmissions/s1'); await can('admin', 'fieldSubmissions/s1');
    for (const name of ['customer', 'vendor', 'otherStaff', 'anonymous']) await cannot(name, 'fieldSubmissions/s1');
    // ---- Quick Add: each account sees its own record and items; the public sees approved items only
    await can('quickStaff', 'quickAccounts/qs'); await can('admin', 'quickAccounts/qs');
    for (const name of ['anonymous', 'customer', 'vendor', 'staff', 'quickVendor']) await cannot(name, 'quickAccounts/qs');
    await can('quickStaff', 'quickItems/qi1'); await can('admin', 'quickItems/qi1');
    for (const name of ['anonymous', 'customer', 'vendor', 'staff', 'quickVendor']) await cannot(name, 'quickItems/qi1');
    for (const name of Object.keys(who)) await can(name, 'quickItems/qi2');
    for (const name of Object.keys(who)) await cannot(name, 'quickItems/qi1', 'write');
    for (const name of Object.keys(who)) await cannot(name, 'quickAccounts/qs', 'write');
    for (const name of Object.keys(who)) await cannot(name, 'fieldSubmissions/s1', 'write');
    for (const name of Object.keys(who)) await cannot(name, 'vendors/vend', 'write');
    // ---- orders: the customer, the vendor of the shop, the admin; nobody else
    await can('customer', 'orders/o1'); await can('vendor', 'orders/o1'); await can('admin', 'orders/o1');
    for (const name of ['anonymous', 'otherVendor', 'staff', 'quickStaff']) await cannot(name, 'orders/o1');
    // ---- customer profiles are private
    await can('customer', 'users/cust'); await can('admin', 'users/cust');
    for (const name of ['anonymous', 'vendor', 'staff', 'quickVendor']) await cannot(name, 'users/cust');
    // ---- admin sessions: nobody touches them from a client, not even the admin
    for (const name of Object.keys(who)) { await cannot(name, '_adminSessions/boss'); await cannot(name, '_adminSessions/boss', 'write'); }
    // ---- a deleted/forged admin claim without a session is not an admin
    const noSession = as('nobody', {admin: true});
    await assertFails(setDoc(doc(noSession, 'products/p1'), {x: 1}, {merge: true}));
    await assertFails(deleteDoc(doc(noSession, 'products/p1')));
  } finally { await env.cleanup(); }
});
