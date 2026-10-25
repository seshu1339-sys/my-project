const {test} = require('node:test');
const assert = require('node:assert/strict');
require('./index'); // starts the Firebase app

test('inactive accounts: the list, disable and enable, deleting a customer (not a business account), and the sweep that is off until switched on', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const {getAuth} = require('firebase-admin/auth');
  const {_inactive} = require('./inactive-accounts');
  const fns = require('./index');
  const db = getFirestore();
  const auth = getAuth();
  for (const c of ['userActivity', 'accountStates', 'inactiveSweeps']) for (const d of (await db.collection(c).get()).docs) await d.ref.delete();
  await db.collection('settings').doc('inactiveAccounts').delete();
  // every account in the emulator is new; "now" is moved 40 days ahead instead
  const later = Date.now() + 40 * 86400000;
  for (const uid of ['inCust', 'inVendor', 'inBoss', 'inFresh']) {
    try { await auth.deleteUser(uid); } catch (_) { /* not there */ }
    await auth.createUser({uid, email: `${uid.toLowerCase()}@example.test`});
  }
  await auth.setCustomUserClaims('inBoss', {admin: true});
  await db.collection('vendors').doc('inVendor').set({status: 'approved'});
  await db.collection('userActivity').doc('inFresh').set({lastActiveAt: Timestamp.fromMillis(later - 86400000)});
  await db.collection('users').doc('inCust').set({name: 'Old customer'});
  await db.collection('users').doc('inCust').collection('pushTokens').doc('t').set({token: 'x'});
  await db.collection('notificationSubscribers').doc('inCust').set({enabled: true});

  // ---- the list: not the admin, not someone active yesterday
  const list = await _inactive.findInactive({days: 30, now: later});
  const ids = list.map(r => r.uid);
  assert.ok(ids.includes('inCust') && ids.includes('inVendor'));
  assert.ok(!ids.includes('inBoss'), 'never the admin');
  assert.ok(!ids.includes('inFresh'), 'used the app yesterday');
  assert.equal(list.find(r => r.uid === 'inVendor').kind, 'vendor');
  assert.ok(list.find(r => r.uid === 'inCust').inactiveDays >= 39);

  // ---- the admin's actions
  await db.collection('_adminSessions').doc('inBoss').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  const boss = {auth: {uid: 'inBoss', token: {admin: true, email_verified: true}}};
  await assert.rejects(() => fns.setAccountDisabled.run({auth: {uid: 'inCust', token: {email_verified: true}}, data: {uid: 'inVendor', disabled: true}}), /Administrator/);
  assert.deepEqual(await fns.setAccountDisabled.run({...boss, data: {uid: 'inVendor', disabled: true}}), {uid: 'inVendor', disabled: true});
  assert.equal((await auth.getUser('inVendor')).disabled, true);
  await fns.setAccountDisabled.run({...boss, data: {uid: 'inVendor', disabled: false}});
  assert.equal((await auth.getUser('inVendor')).disabled, false);
  await assert.rejects(() => fns.setAccountDisabled.run({...boss, data: {uid: 'inBoss', disabled: true}}), /your own account/);
  await assert.rejects(() => fns.deleteInactiveAccount.run({...boss, data: {uid: 'inVendor', confirm: 'DELETE'}}), /Only customer accounts/);
  await assert.rejects(() => fns.deleteInactiveAccount.run({...boss, data: {uid: 'inCust'}}), /Type DELETE/);

  // ---- the sweep: nothing while it is off
  assert.deepEqual((await _inactive.sweep(later)).disabled, []);
  assert.equal((await auth.getUser('inCust')).disabled, false);
  // on: customers inactive for 30 days are disabled (a vendor is not touched)
  await db.collection('settings').doc('inactiveAccounts').set({autoDisable: true, disableAfterDays: 30, autoDelete: true, deleteAfterDays: 90});
  const first = await _inactive.sweep(later);
  // (other test accounts in the emulator may be swept too)
  assert.ok(first.disabled.includes('inCust'));
  assert.ok(!first.disabled.includes('inVendor') && !first.disabled.includes('inBoss'));
  assert.deepEqual(first.deleted, []);
  assert.equal((await auth.getUser('inCust')).disabled, true);
  assert.equal((await auth.getUser('inVendor')).disabled, false);
  // 100 days on, the customer the sweep disabled is deleted with their personal data; orders would stay
  const second = await _inactive.sweep(Date.now() + 100 * 86400000);
  assert.ok(second.deleted.includes('inCust'));
  assert.ok(!second.deleted.includes('inVendor'));
  await assert.rejects(() => auth.getUser('inCust'), /no user record/i);
  assert.equal((await db.collection('users').doc('inCust').get()).exists, false);
  assert.equal((await db.collection('users').doc('inCust').collection('pushTokens').get()).size, 0);
  assert.equal((await db.collection('notificationSubscribers').doc('inCust').get()).exists, false);
  assert.equal((await db.collection('accountStates').doc('inCust').get()).data().deleted, true);
  assert.equal((await db.collection('inactiveSweeps').get()).size >= 1, true);
  await db.collection('settings').doc('inactiveAccounts').delete();
});
