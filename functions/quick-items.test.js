const {test} = require('node:test');
const assert = require('node:assert/strict');
const {quickItemDetails, approvedWindow, itemPhase, dailyLimit, dayKey, durationMs, QUICK_UNITS} = require('./quick-domain');

const base = {name: 'Tomatoes', categoryId: 'cat-vegetables', price: 30, unit: 'per kg', startMode: 'now', durationUnit: 'hours', durationValue: 2};
const NOW = Date.UTC(2026, 9, 21, 6, 0, 0);

test('quick item details: rate, unit, category, start and duration are all checked', () => {
  const ok = quickItemDetails(base, NOW);
  assert.equal(ok.requestedStartMs, NOW);
  assert.equal(ok.durationMs, 2 * 3600 * 1000);
  assert.throws(() => quickItemDetails({...base, price: 0}, NOW), /Rate/);
  assert.throws(() => quickItemDetails({...base, price: '30'}, NOW), /Rate/);
  assert.throws(() => quickItemDetails({...base, unit: 'per ton'}, NOW), /unit/);
  assert.throws(() => quickItemDetails({...base, name: 'a'}, NOW), /item name/);
  assert.throws(() => quickItemDetails({...base, categoryId: ''}, NOW), /category/);
  assert.throws(() => quickItemDetails({...base, startMode: 'later'}, NOW), /Now or Schedule/);
  assert.throws(() => quickItemDetails({...base, startMode: 'schedule'}, NOW), /date and time/);
  assert.throws(() => quickItemDetails({...base, startMode: 'schedule', scheduleAt: NOW - 3600000}, NOW), /future/);
  assert.throws(() => quickItemDetails({...base, startMode: 'schedule', scheduleAt: NOW + 40 * 86400000}, NOW), /30 days/);
  const tomorrow = NOW + 24 * 3600000;
  assert.equal(quickItemDetails({...base, startMode: 'schedule', scheduleAt: tomorrow}, NOW).requestedStartMs, tomorrow);
  assert.ok(QUICK_UNITS.includes('per kg') && QUICK_UNITS.includes('per piece'));
});

test('display duration: Hours 1-4 or Days 1-3 only', () => {
  for (const h of [1, 2, 3, 4]) assert.equal(durationMs('hours', h), h * 3600000);
  for (const d of [1, 2, 3]) assert.equal(durationMs('days', d), d * 86400000);
  assert.throws(() => durationMs('hours', 5));
  assert.throws(() => durationMs('days', 4));
  assert.throws(() => durationMs('weeks', 1));
  assert.throws(() => durationMs('hours', 1.5));
});

test('the timer starts at the later of approval and the requested start, not at save time', () => {
  const hour = 3600000;
  // "Now": approved 30 minutes after saving -> the 2 hours count from approval
  let w = approvedWindow(NOW + 30 * 60000, NOW, 2 * hour);
  assert.equal(w.startsAtMs, NOW + 30 * 60000);
  assert.equal(w.expiresAtMs, NOW + 30 * 60000 + 2 * hour);
  // scheduled for tomorrow 6 AM, approved today -> counts from tomorrow
  const tomorrow = NOW + 24 * hour;
  w = approvedWindow(NOW + hour, tomorrow, 3 * hour);
  assert.equal(w.startsAtMs, tomorrow);
  assert.equal(w.expiresAtMs, tomorrow + 3 * hour);
  // scheduled time already passed by the time the admin approves -> counts from approval
  w = approvedWindow(NOW + 5 * hour, NOW + hour, hour);
  assert.equal(w.startsAtMs, NOW + 5 * hour);
});

test('item phases: pending until approved, then scheduled / live / expired by the clock', () => {
  const item = {status: 'approved', startsAtMs: NOW + 1000, expiresAtMs: NOW + 5000};
  assert.equal(itemPhase({status: 'pending'}, NOW), 'pending');
  assert.equal(itemPhase(item, NOW), 'scheduled');
  assert.equal(itemPhase(item, NOW + 1000), 'live');
  assert.equal(itemPhase(item, NOW + 4999), 'live');
  assert.equal(itemPhase(item, NOW + 5000), 'expired');
  assert.equal(itemPhase({status: 'rejected'}, NOW), 'rejected');
  assert.equal(itemPhase({status: 'cancelled'}, NOW), 'cancelled');
});

test('daily limits: defaults 15 staff / 6 vendors, admin can change them', () => {
  assert.equal(dailyLimit('staff', {}), 15);
  assert.equal(dailyLimit('vendor', {}), 6);
  assert.equal(dailyLimit('staff', {quickItemsPerDayStaff: 20}), 20);
  assert.equal(dailyLimit('vendor', {quickItemsPerDayVendor: '9'}), 9);
  assert.equal(dailyLimit('vendor', {quickItemsPerDayVendor: 0}), 6);
  assert.equal(dailyLimit('staff', {quickItemsPerDayStaff: 'lots'}), 15);
});

test('the day for the limit is the Indian calendar day', () => {
  assert.equal(dayKey(Date.UTC(2026, 9, 21, 18, 29)), '2026-10-21');
  assert.equal(dayKey(Date.UTC(2026, 9, 21, 18, 31)), '2026-10-22'); // 00:01 IST next day
});

const emulators = !!(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST && process.env.FIREBASE_STORAGE_EMULATOR_HOST);
test('Quick Add is closed on the server (owner, 6 Nov 2026): no new accounts, shop locations or items', {skip: !emulators}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const admin = {auth: {uid: 'admin1', token: {role: 'admin', admin: true, email_verified: true}}};
  const someone = {auth: {uid: 'quickUser', token: {role: 'user', email_verified: true}}};
  await db.collection('_adminSessions').doc('admin1').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  await assert.rejects(() => fns.createQuickAccount.run({...admin, data: {email: 'a@example.test', role: 'staff'}}), /Quick Add is closed/);
  await assert.rejects(() => fns.setQuickShopLocation.run({...someone, data: {latitude: 17.0, longitude: 81.8}}), /Quick Add is closed/);
  await assert.rejects(() => fns.saveQuickItem.run({...someone, data: {}}), /Quick Add is closed/);
  await assert.rejects(() => fns.saveQuickItems.run({...someone, data: {}}), /Quick Add is closed/);
  await assert.rejects(() => fns.reactivateQuickItem.run({...someone, data: {}}), /Quick Add is closed/);
  assert.equal((await db.collection('quickAccounts').where('email', '==', 'a@example.test').get()).size, 0);
});

test('the pincode directory gives every place a coordinate and finds the nearest town', () => {
  const {filledCoordinates, nearestPlace, findPlace} = require('./places');
  const data = require('./places').placesData(['Andhra Pradesh']);
  const filled = filledCoordinates(data.places);
  assert.equal(filled.length, data.places.length);
  assert.equal(filled.filter(([lat, lng]) => lat === 0 && lng === 0).length, 0, 'no place is left without coordinates');
  // estimates for places the file has no coordinates for (the Dart app must give the same numbers)
  assert.deepEqual(filled[1], [14.352, 77.348]);   // Achampalle, 515621 -> from neighbours
  assert.deepEqual(filled[2], [14.085, 77.437]);   // Adadakulapalli, 515124
  assert.deepEqual(filled[3], [13.805, 77.044]);   // Agali S.O, 515311
  assert.equal(nearestPlace(17.0005, 81.804).town, 'Rajahmundry');
  assert.equal(nearestPlace(12.97, 77.59).state, 'Karnataka', 'Bengaluru is in the directory now');
  assert.equal(nearestPlace(25.0, 60.0), null, 'the Arabian Sea is nowhere near a post office');
  assert.equal(findPlace({town: 'Rajahmundry', district: 'East Godavari', pincode: '533101'}).state, 'Andhra Pradesh');
  assert.equal(findPlace({town: 'Rajahmundry', district: 'East Godavari', pincode: '500001'}), null);
});

test('Quick Add rules: only approved items are public; accounts are private; no direct writes', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {readFileSync} = require('node:fs');
  const {resolve} = require('node:path');
  const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
  const {doc, setDoc, getDoc, getDocs, query, where, collection, Timestamp} = require('firebase/firestore');
  const env = await initializeTestEnvironment({projectId: 'demo-neighbourly', firestore: {rules: readFileSync(resolve(__dirname, '../firestore.rules'), 'utf8')}});
  try {
    await env.withSecurityRulesDisabled(async ctx => {
      const f = ctx.firestore();
      await setDoc(doc(f, '_adminSessions/boss'), {expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
      await setDoc(doc(f, 'quickItems/live'), {status: 'approved', ownerUid: 'ravi', name: 'A'});
      await setDoc(doc(f, 'quickItems/wait'), {status: 'pending', ownerUid: 'ravi', name: 'B'});
      await setDoc(doc(f, 'quickItems/other'), {status: 'pending', ownerUid: 'sita', name: 'C'});
      await setDoc(doc(f, 'quickAccounts/ravi'), {code: 'ST001', role: 'staff', active: true});
      await setDoc(doc(f, 'locations/l1'), {name: 'Rajahmundry', active: true});
    });
    const anonymous = env.unauthenticatedContext().firestore();
    const ravi = env.authenticatedContext('ravi', {role: 'user', email_verified: true}).firestore();
    const sita = env.authenticatedContext('sita', {role: 'user', email_verified: true}).firestore();
    const admin = env.authenticatedContext('boss', {role: 'admin', admin: true, email_verified: true}).firestore();
    await assertSucceeds(getDoc(doc(anonymous, 'quickItems/live')));
    await assertFails(getDoc(doc(anonymous, 'quickItems/wait')));
    await assertSucceeds(getDocs(query(collection(anonymous, 'quickItems'), where('status', '==', 'approved'))));
    await assertFails(getDocs(collection(anonymous, 'quickItems')));
    await assertSucceeds(getDoc(doc(ravi, 'quickItems/wait')));
    await assertFails(getDoc(doc(sita, 'quickItems/wait')));
    await assertSucceeds(getDoc(doc(admin, 'quickItems/wait')));
    await assertFails(setDoc(doc(ravi, 'quickItems/wait'), {status: 'approved', ownerUid: 'ravi'}));
    await assertFails(setDoc(doc(ravi, 'quickItems/new'), {status: 'approved', ownerUid: 'ravi'}));
    await assertSucceeds(getDoc(doc(ravi, 'quickAccounts/ravi')));
    await assertFails(getDoc(doc(sita, 'quickAccounts/ravi')));
    await assertSucceeds(getDoc(doc(admin, 'quickAccounts/ravi')));
    await assertFails(setDoc(doc(ravi, 'quickAccounts/ravi'), {active: true, code: 'ST999'}));
    await assertSucceeds(getDoc(doc(anonymous, 'locations/l1')));
    await assertFails(setDoc(doc(ravi, 'locations/l2'), {name: 'Mine'}));
    await assertSucceeds(setDoc(doc(admin, 'locations/l2'), {name: 'Kakinada', active: true}));
  } finally { await env.cleanup(); }
});
