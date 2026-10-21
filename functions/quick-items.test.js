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
test('Quick Add end to end: accounts, locations, limits, approval, expiry', {skip: !emulators}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const fns = require('./index');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  const admin = {auth: {uid: 'admin1', token: {admin: true, email_verified: true}}};
  await db.collection('_adminSessions').doc('admin1').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  for (const name of ['quickAccounts', 'quickItems', 'locations', '_idCounters']) for (const d of (await db.collection(name).get()).docs) await d.ref.delete();
  await db.collection('settings').doc('business').set({name: 'Test'});
  await db.collection('categories').doc('cat-vegetables').set({name: 'Fresh & Vegetables'});
  await db.collection('locations').doc('loc-raj').set({name: 'Rajahmundry', active: true});
  await db.collection('locations').doc('loc-kak').set({name: 'Kakinada', active: true});
  await db.collection('locations').doc('loc-off').set({name: 'Closed town', active: false});
  const upload = (uid, id) => bucket.file(`quickItems/${uid}/${id}`).save(Buffer.from([0xff, 0xd8, 0xff]), {metadata: {contentType: 'image/jpeg'}});
  const create = data => fns.createQuickAccount.run({...admin, data});

  // ---- admin creates accounts; codes ST001 / VN001, in separate sequences
  const staff = await create({role: 'staff', name: 'Ravi Staff', phone: '9876543210', email: 'qa-staff1@example.test', photoUrl: 'https://example.test/p.jpg'});
  const staff2 = await create({role: 'staff', name: 'Sita Staff', phone: '9876543211', email: 'qa-staff2@example.test', photoUrl: 'https://example.test/p.jpg'});
  const vendor = await create({role: 'vendor', name: 'Ramu Vendor', phone: '9876543212', email: 'qa-vendor1@example.test', photoUrl: 'https://example.test/p.jpg', locationId: 'loc-raj', shopName: 'Ramu Fresh'});
  assert.equal(staff.code, 'ST001');
  assert.equal(staff2.code, 'ST002');
  assert.equal(vendor.code, 'VN001');
  assert.match(staff.resetLink, /^http/);
  await assert.rejects(() => create({role: 'staff', name: 'Ravi Again', phone: '9876543210', email: 'qa-staff1@example.test', photoUrl: 'https://example.test/p.jpg'}), /already/);
  await assert.rejects(() => create({role: 'vendor', name: 'No Loc', phone: '9876543210', email: 'qa-v2@example.test', photoUrl: 'https://example.test/p.jpg'}), /location/);
  await assert.rejects(() => create({role: 'vendor', name: 'Bad Loc', phone: '9876543210', email: 'qa-v3@example.test', photoUrl: 'https://example.test/p.jpg', locationId: 'loc-off'}), /not available/);
  await assert.rejects(() => fns.createQuickAccount.run({auth: {uid: 'x', token: {email_verified: true}}, data: {role: 'staff'}}), /Administrator/);
  const ctx = account => ({auth: {uid: account.uid, token: {email_verified: true}}});
  const staffCtx = ctx(staff), vendorCtx = ctx(vendor);
  const item = {name: 'Tomatoes', categoryId: 'cat-vegetables', price: 30, unit: 'per kg', startMode: 'now', durationUnit: 'hours', durationValue: 2};
  const save = (c, data) => fns.saveQuickItem.run({...c, data});

  // ---- an item needs a real photo in Storage first
  await assert.rejects(() => save(staffCtx, {...item, submissionId: 's1', locationId: 'loc-raj'}), /photo/);
  await upload(staff.uid, 's1');

  // ---- staff must pick a location from the list (any of them); inactive / unknown are refused
  await assert.rejects(() => save(staffCtx, {...item, submissionId: 's1'}), /location/);
  await assert.rejects(() => save(staffCtx, {...item, submissionId: 's1', locationId: 'loc-off'}), /location/);
  await assert.rejects(() => save(staffCtx, {...item, submissionId: 's1', locationId: 'nowhere'}), /location/);
  await assert.rejects(() => save(staffCtx, {...item, submissionId: 's1', locationId: 'loc-raj', categoryId: 'nope'}), /category/);
  const first = await save(staffCtx, {...item, submissionId: 's1', locationId: 'loc-raj'});
  await upload(staff.uid, 's2');
  const second = await save(staffCtx, {...item, name: 'Onions', submissionId: 's2', locationId: 'loc-kak'});
  const items = await db.collection('quickItems').get();
  const byName = Object.fromEntries(items.docs.map(d => [d.data().name, d.data()]));
  assert.equal(byName.Tomatoes.locationName, 'Rajahmundry');
  assert.equal(byName.Onions.locationName, 'Kakinada', 'each item can be at a different town');
  assert.equal(byName.Tomatoes.status, 'pending');
  assert.equal(byName.Tomatoes.ownerCode, 'ST001');
  assert.equal(byName.Tomatoes.ownerName, 'Ravi Staff');
  assert.equal(byName.Tomatoes.imageUrl, '');

  // ---- a vendor is locked to their own location
  await upload(vendor.uid, 'v1');
  await assert.rejects(() => save(vendorCtx, {...item, submissionId: 'v1', locationId: 'loc-kak'}), /fixed/);
  const vendorItem = await save(vendorCtx, {...item, name: 'Ramu Mango', categoryId: 'cat-vegetables', submissionId: 'v1'});
  const vendorDoc = (await db.collection('quickItems').doc(vendorItem.itemId).get()).data();
  assert.equal(vendorDoc.locationId, 'loc-raj');
  assert.equal(vendorDoc.shopName, 'Ramu Fresh');
  assert.equal(vendorDoc.ownerCode, 'VN001');

  // ---- nothing is public/visible until approved, and approval starts the clock
  const review = (ids, approved, reason) => fns.reviewQuickItems.run({...admin, data: {itemIds: ids, approved, reason}});
  await assert.rejects(() => fns.reviewQuickItems.run({...staffCtx, data: {itemIds: [first.itemId], approved: true}}), /Administrator/);
  const before = Date.now();
  const out = await review([first.itemId, second.itemId, vendorItem.itemId], true);
  assert.deepEqual(out, {approved: 3, rejected: 0, skipped: 0});
  const approved = (await db.collection('quickItems').doc(first.itemId).get()).data();
  assert.equal(approved.status, 'approved');
  assert.ok(approved.startsAt.toMillis() >= before, 'starts at approval, not at save time');
  assert.equal(approved.expiresAt.toMillis() - approved.startsAt.toMillis(), 2 * 3600000);
  assert.match(approved.imageUrl, /catalog%2Fquick_/);
  assert.equal((await bucket.file(`catalog/quick_${first.itemId}.jpg`).exists())[0], true);
  assert.deepEqual(await review([first.itemId], true), {approved: 0, rejected: 0, skipped: 1}, 'cannot approve twice');

  // ---- scheduled start: the clock waits for the schedule
  await upload(staff.uid, 's3');
  const tomorrow = Date.now() + 24 * 3600000;
  const scheduled = await save(staffCtx, {...item, name: 'Fresh Beans', submissionId: 's3', locationId: 'loc-raj', startMode: 'schedule', scheduleAt: tomorrow, durationUnit: 'days', durationValue: 1});
  await review([scheduled.itemId], true);
  const sch = (await db.collection('quickItems').doc(scheduled.itemId).get()).data();
  assert.equal(sch.startsAt.toMillis(), tomorrow);
  assert.equal(sch.expiresAt.toMillis(), tomorrow + 86400000);

  // ---- ownership: only your own items
  await assert.rejects(() => fns.cancelQuickItem.run({...ctx(staff2), data: {itemId: first.itemId}}), /not found/i);
  await assert.rejects(() => save(ctx(staff2), {...item, itemId: first.itemId, locationId: 'loc-raj'}), /not found/i);
  await assert.rejects(() => fns.reactivateQuickItem.run({...ctx(staff2), data: {itemId: first.itemId, startMode: 'now', durationUnit: 'hours', durationValue: 1}}), /not found/i);

  // ---- cancel, re-activate (back to the admin), edit (back to the admin)
  assert.equal((await fns.cancelQuickItem.run({...staffCtx, data: {itemId: first.itemId}})).status, 'cancelled');
  assert.equal((await db.collection('quickItems').doc(first.itemId).get()).data().status, 'cancelled');
  await fns.reactivateQuickItem.run({...staffCtx, data: {itemId: first.itemId, startMode: 'now', durationUnit: 'days', durationValue: 2}});
  let again = (await db.collection('quickItems').doc(first.itemId).get()).data();
  assert.equal(again.status, 'pending');
  assert.equal(again.startsAt, undefined);
  assert.equal(again.durationMs, 2 * 86400000);
  await save(staffCtx, {...item, itemId: first.itemId, price: 35, locationId: 'loc-kak'});
  again = (await db.collection('quickItems').doc(first.itemId).get()).data();
  assert.equal(again.price, 35);
  assert.equal(again.locationName, 'Kakinada');
  assert.equal(again.status, 'pending');

  // ---- reject (pending) and take-down (approved) by the admin
  assert.deepEqual(await review([first.itemId], false, 'blurry photo'), {approved: 0, rejected: 1, skipped: 0});
  assert.equal((await db.collection('quickItems').doc(first.itemId).get()).data().decisionReason, 'blurry photo');
  assert.deepEqual(await review([second.itemId], false, 'wrong price'), {approved: 0, rejected: 1, skipped: 0});

  // ---- expiry hides, never deletes
  await db.collection('quickItems').doc(vendorItem.itemId).update({expiresAt: Timestamp.fromMillis(Date.now() - 1000)});
  const expired = await fns._quick.expireQuickItems();
  assert.equal(expired, 1);
  const gone = await db.collection('quickItems').doc(vendorItem.itemId).get();
  assert.equal(gone.exists, true);
  assert.equal(gone.data().status, 'expired');

  // ---- inactive accounts cannot add anything
  await fns.setQuickAccountActive.run({...admin, data: {uid: staff.uid, active: false}});
  await upload(staff.uid, 's4');
  await assert.rejects(() => save(staffCtx, {...item, submissionId: 's4', locationId: 'loc-raj'}), /inactive, contact admin/);
  await fns.setQuickAccountActive.run({...admin, data: {uid: staff.uid, active: true}});
  await save(staffCtx, {...item, submissionId: 's4', locationId: 'loc-raj'});
  await assert.rejects(() => save({auth: {uid: 'stranger', token: {email_verified: true}}}, {...item, submissionId: 's4', locationId: 'loc-raj'}), /not set up/);

  // ---- daily limits (admin-configurable): vendor 6 by default
  for (const d of (await db.collection('quickItems').where('ownerUid', '==', vendor.uid).get()).docs) await d.ref.delete();
  for (let i = 1; i <= 6; i++) { await upload(vendor.uid, `lim${i}`); await save(vendorCtx, {...item, name: `Item ${i}`, submissionId: `lim${i}`}); }
  await upload(vendor.uid, 'lim7');
  await assert.rejects(() => save(vendorCtx, {...item, name: 'Item 7', submissionId: 'lim7'}), /Daily limit reached: you can add 6/);
  await db.collection('settings').doc('business').set({name: 'Test', quickItemsPerDayVendor: 7});
  await save(vendorCtx, {...item, name: 'Item 7', submissionId: 'lim7'});
  // staff default 15
  for (const d of (await db.collection('quickItems').where('ownerUid', '==', staff.uid).get()).docs) await d.ref.delete();
  for (let i = 1; i <= 15; i++) { await upload(staff.uid, `st${i}`); await save(staffCtx, {...item, name: `Staff ${i}`, submissionId: `st${i}`, locationId: 'loc-raj'}); }
  await upload(staff.uid, 'st16');
  await assert.rejects(() => save(staffCtx, {...item, name: 'Staff 16', submissionId: 'st16', locationId: 'loc-raj'}), /Daily limit reached: you can add 15/);
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
    const ravi = env.authenticatedContext('ravi', {email_verified: true}).firestore();
    const sita = env.authenticatedContext('sita', {email_verified: true}).firestore();
    const admin = env.authenticatedContext('boss', {admin: true, email_verified: true}).firestore();
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
