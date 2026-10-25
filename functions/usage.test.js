const {test} = require('node:test');
const assert = require('node:assert/strict');
require('./index'); // starts the Firebase app
const {normalizeUsageBatch, recordUsage, countUsage, dayKey, shortKey, DEVICE_DAILY_CAP} = require('./usage');

const D = 'device-0123456789abcdef';

test('usage batches: only the listed app events count; server-only and unknown events are dropped', () => {
  const batch = normalizeUsageBatch({deviceId: D, app: 'vendor', platform: 'android', events: [
    {event: 'shop_call', key: 'shopA', label: 'Lakshmi Kirana'},
    {event: 'item_added', key: 'x'}, // server only
    {event: 'hack', key: 'x'},
    {event: 'search_no_result', key: 'x'.repeat(300)},
    {event: 'app_start', key: 'vendor/android/1-2 s', label: '1-2 s'},
    {event: 'app_error', key: 'vendor/android/error/1a2b3c4d', label: 'StateError: Bad state'},
  ]});
  assert.deepEqual(batch.events.map(e => e.event), ['shop_call', 'search_no_result', 'app_start', 'app_error']);
  assert.equal(batch.events[1].key.length, 100, 'keys are cut short');
  assert.deepEqual([batch.app, batch.platform, batch.touch], ['vendor', 'android', false]);
  assert.throws(() => normalizeUsageBatch({deviceId: 'short', events: []}), /device id/);
  assert.throws(() => normalizeUsageBatch({deviceId: D, events: Array(51).fill({event: 'search'})}), /0 to 50/);
  assert.equal(dayKey(Date.parse('2026-10-25T20:00:00Z')), '2026-10-26', 'the Indian day');
});

test('counts by day and key, the shop owner\'s and the staff member\'s own numbers, a person\'s day, the device cap', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  for (const c of ['usageDaily', 'usageOwnerDaily', 'usagePersonDaily', 'userActivity', '_usageDevices']) for (const d of (await db.collection(c).get()).docs) await d.ref.delete();
  await db.collection('shops').doc('uShopA').set({name: 'Lakshmi Kirana', ownerId: 'uVendor1', addedByStaffUid: 'uStaff1'});
  await db.collection('services').doc('prov-uP1').set({name: 'Suresh', providerId: 'uP1'});
  const t0 = Date.parse('2031-05-05T06:00:00Z');
  const day = dayKey(t0);
  const ctx = (uid = null) => ({uid, userAgent: 'Mozilla/5.0 Chrome/120'});
  const send = (events, extra = {}) => normalizeUsageBatch({deviceId: D, events, ...extra});

  const out = await recordUsage(db, send([
    {event: 'shop_call', key: 'uShopA', label: 'Lakshmi Kirana', town: 'Narsipatnam'},
    {event: 'shop_call', key: 'uShopA', label: 'Lakshmi Kirana', town: 'Narsipatnam'},
    {event: 'shop_directions', key: 'uShopA', label: 'Lakshmi Kirana'},
    {event: 'worker_call', key: 'prov-uP1', label: 'Suresh'},
    {event: 'search_no_result', key: 'dragon fruit', label: 'dragon fruit'},
  ], {touch: true}), ctx('uCustomer1'), t0);
  assert.deepEqual(out, {counted: 5, dropped: 0});
  const calls = (await db.collection('usageDaily').doc(`${day}~shop_call`).get()).data();
  assert.equal(calls.total, 2);
  assert.deepEqual(calls.keys[shortKey('uShopA')], {key: 'uShopA', label: 'Lakshmi Kirana', town: 'Narsipatnam', count: 2});
  assert.equal((await db.collection('usageDaily').doc(`${day}~search_no_result`).get()).data().keys[shortKey('dragon fruit')].count, 1);
  // the vendor and the staff member who added the shop see it in their numbers; the provider sees the worker call
  assert.deepEqual((await db.collection('usageOwnerDaily').doc(`uVendor1~${day}`).get()).data().counts, {shop_call: 2, shop_directions: 1});
  assert.deepEqual((await db.collection('usageOwnerDaily').doc(`uStaff1~${day}`).get()).data().counts, {shop_call: 2, shop_directions: 1});
  assert.deepEqual((await db.collection('usageOwnerDaily').doc(`uP1~${day}`).get()).data().counts, {worker_call: 1});
  // the signed-in person's day, and when they were last active
  const person = (await db.collection('usagePersonDaily').doc(`uCustomer1~${day}`).get()).data();
  assert.deepEqual([person.counts.shop_call, person.counts.search_no_result], [2, 1]);
  assert.equal(person.keys[`shop_call~${shortKey('uShopA')}`].label, 'Lakshmi Kirana');
  assert.ok(person.expiresAt, 'kept for a limited time');
  assert.equal((await db.collection('userActivity').doc('uCustomer1').get()).data().app, 'customer');

  // bots are not counted
  assert.equal((await recordUsage(db, send([{event: 'search', key: 'x'}]), {userAgent: 'Googlebot/2.1'}, t0)).counted, 0);
  // a device counts at most DEVICE_DAILY_CAP events a day
  const {createHash} = require('node:crypto');
  await db.collection('_usageDevices').doc(createHash('sha256').update(`${D}|${day}`).digest('hex')).set({count: DEVICE_DAILY_CAP - 2});
  assert.deepEqual(await recordUsage(db, send([{event: 'search', key: 'a'}, {event: 'search', key: 'b'}, {event: 'search', key: 'c'}]), ctx(), t0), {counted: 2, dropped: 1});

  // what vendors and staff do through the server is counted there
  await countUsage(db, 'staff_added', {key: 'uStaff1', label: 'Kiran (STF-NRPM-116-482)', town: 'Narsipatnam', owners: ['uStaff1'], uid: 'uStaff1'}, t0);
  const staffAdded = (await db.collection('usageDaily').doc(`${day}~staff_added`).get()).data();
  assert.equal(staffAdded.keys[shortKey('uStaff1')].town, 'Narsipatnam');
  assert.equal((await db.collection('usageOwnerDaily').doc(`uStaff1~${day}`).get()).data().counts.staff_added, 1);
  await countUsage(db, 'not_an_event', {}, t0); // never throws

  // through a callable: the "Ad for your shop" tick
  await db.collection('vendors').doc('uVendorAd').set({status: 'approved', name: 'Ravi Stores', town: 'Tuni'});
  await fns.setAdInterest.run({auth: {uid: 'uVendorAd', token: {email_verified: true}}, data: {interested: true}});
  const interest = (await db.collection('usageDaily').doc(`${dayKey()}~ad_interest`).get()).data();
  assert.equal(interest.keys[shortKey('uVendorAd')].label, 'Ravi Stores');
});

test('the people report says who an account is: email, name and kind', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST}, async () => {
  const {getFirestore} = require('firebase-admin/firestore');
  const {getAuth} = require('firebase-admin/auth');
  const {_usageAdmin} = require('./usage-admin');
  const db = getFirestore();
  for (const [uid, email] of [['labCustomer', 'cust@example.test'], ['labStaff', 'staff@example.test']]) {
    try { await getAuth().deleteUser(uid); } catch (_) { /* not there */ }
    await getAuth().createUser({uid, email, displayName: uid === 'labStaff' ? 'Kiran' : undefined});
  }
  await db.collection('fieldStaff').doc('labStaff').set({status: 'active'});
  const labels = await _usageAdmin.labelsFor(['labCustomer', 'labStaff', 'labGone']);
  assert.deepEqual([labels.labCustomer.email, labels.labCustomer.kind], ['cust@example.test', 'customer']);
  assert.deepEqual([labels.labStaff.name, labels.labStaff.kind], ['Kiran', 'staff']);
  assert.equal(labels.labGone.missing, true);
  const fns = require('./index');
  await assert.rejects(() => fns.accountLabels.run({auth: {uid: 'x', token: {email_verified: true}}, data: {uids: ['labCustomer']}}), /Administrator/);
});
