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
test('Quick Add end to end: accounts, shop lock by GPS, 100 m check, batches, towns, limits, approval, expiry', {skip: !emulators}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const {nearestPlace} = require('./places');
  const fns = require('./index');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  const admin = {auth: {uid: 'admin1', token: {admin: true, email_verified: true}}};
  await db.collection('_adminSessions').doc('admin1').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  for (const name of ['quickAccounts', 'quickItems', 'locations', '_idCounters']) for (const d of (await db.collection(name).get()).docs) await d.ref.delete();
  await db.collection('settings').doc('business').set({name: 'Test'});
  await db.collection('categories').doc('cat-vegetables').set({name: 'Fresh & Vegetables'});
  await db.collection('locations').doc('loc-mkt').set({name: 'Old Market', town: 'Rajahmundry', active: true});
  await db.collection('locations').doc('loc-off').set({name: 'Closed place', active: false});
  const upload = (uid, id) => bucket.file(`quickItems/${uid}/${id}`).save(Buffer.from([0xff, 0xd8, 0xff]), {metadata: {contentType: 'image/jpeg'}});
  const create = data => fns.createQuickAccount.run({...admin, data});
  const photo = 'https://example.test/p.jpg';

  // ---- admin creates accounts; codes ST001 / VN001; NO location is typed in for a vendor
  const staff = await create({role: 'staff', name: 'Ravi Staff', phone: '9876543210', email: 'qa-staff1@example.test', photoUrl: photo});
  const staff2 = await create({role: 'staff', name: 'Sita Staff', phone: '9876543211', email: 'qa-staff2@example.test', photoUrl: photo});
  const vendor = await create({role: 'vendor', name: 'Ramu Vendor', phone: '9876543212', email: 'qa-vendor1@example.test', photoUrl: photo, shopName: 'Ramu Fresh'});
  const vendor2 = await create({role: 'vendor', name: 'Far Vendor', phone: '9876543213', email: 'qa-vendor2@example.test', photoUrl: photo});
  assert.equal(staff.code, 'ST001');
  assert.equal(staff2.code, 'ST002');
  assert.equal(vendor.code, 'VN001');
  assert.match(staff.resetLink, /^http/);
  assert.equal((await db.collection('quickAccounts').doc(vendor.uid).get()).data().shopLocked, false);
  await assert.rejects(() => create({role: 'staff', name: 'Ravi Again', phone: '9876543210', email: 'qa-staff1@example.test', photoUrl: photo}), /already/);
  await assert.rejects(() => fns.createQuickAccount.run({auth: {uid: 'x', token: {email_verified: true}}, data: {role: 'staff'}}), /Administrator/);
  const ctx = account => ({auth: {uid: account.uid, token: {email_verified: true}}});
  const staffCtx = ctx(staff), vendorCtx = ctx(vendor);
  const item = {name: 'Tomatoes', categoryId: 'cat-vegetables', price: 30, unit: 'per kg', startMode: 'now', durationUnit: 'hours', durationValue: 2};
  const save = (c, data) => fns.saveQuickItem.run({...c, data});
  const saveMany = (c, data) => fns.saveQuickItems.run({...c, data});

  // ---- the vendor's shop: GPS at the shop sets the nearest town + pincode, once, for good
  const SHOP = {latitude: 17.0005, longitude: 81.804}; // Rajahmundry
  await upload(vendor.uid, 'v0');
  await assert.rejects(() => save(vendorCtx, {...item, submissionId: 'v0', ...SHOP}), /Set your shop location first/);
  await assert.rejects(() => fns.setQuickShopLocation.run({...staffCtx, data: SHOP}), /Only vendors/);
  await assert.rejects(() => fns.setQuickShopLocation.run({...vendorCtx, data: {latitude: 'x', longitude: 1}}), /Could not read/);
  await assert.rejects(() => fns.setQuickShopLocation.run({...ctx(vendor2), data: {latitude: 13.0, longitude: 77.5}}), /outside Andhra/);
  const lock = await fns.setQuickShopLocation.run({...vendorCtx, data: SHOP});
  assert.equal(lock.town, 'Rajahmundry');
  assert.equal(lock.state, 'Andhra Pradesh');
  assert.match(lock.pincode, /^5331/);
  const locked = (await db.collection('quickAccounts').doc(vendor.uid).get()).data();
  assert.equal(locked.shopLocked, true);
  assert.equal(locked.locationTown, 'Rajahmundry');
  assert.equal(locked.shopLatitude, SHOP.latitude);
  await assert.rejects(() => fns.setQuickShopLocation.run({...vendorCtx, data: {latitude: 16.95, longitude: 82.24}}), /already set/);

  // ---- every add is GPS-checked: within 100 m of the shop, else "you are not near your shop"
  const nearShop = {latitude: 17.0006, longitude: 81.804};   // about 11 m away
  const farShop = {latitude: 17.003, longitude: 81.804};     // about 280 m away
  await assert.rejects(() => save(vendorCtx, {...item, submissionId: 'v0'}), /Could not read your location/);
  await assert.rejects(() => save(vendorCtx, {...item, submissionId: 'v0', ...farShop}), /మీరు మీ షాప్ దగ్గర లేరు/);
  await assert.rejects(() => save(vendorCtx, {...item, submissionId: 'v0', ...farShop}), /not near your shop/);
  assert.equal((await db.collection('quickItems').get()).size, 0, 'nothing is saved when the vendor is away');
  await assert.rejects(() => save(vendorCtx, {...item, submissionId: 'v0', ...nearShop, locationTown: 'Kakinada'}), /fixed/);
  const one = await save(vendorCtx, {...item, submissionId: 'v0', ...nearShop});
  const oneDoc = (await db.collection('quickItems').doc(one.itemId).get()).data();
  assert.equal(oneDoc.status, 'pending');
  assert.equal(oneDoc.locationTown, 'Rajahmundry');
  assert.equal(oneDoc.locationPincode, locked.locationPincode);
  assert.equal(oneDoc.shopName, 'Ramu Fresh');
  assert.equal(oneDoc.ownerCode, 'VN001');

  // ---- up to 5 items with photos at once (all or nothing), GPS checked once
  const rows = n => Array.from({length: n}, (_, i) => ({name: `Batch ${i + 1}`, price: 10 + i, unit: 'per kg', submissionId: `b${i + 1}`}));
  for (let i = 1; i <= 6; i++) await upload(vendor.uid, `b${i}`);
  const batch = {categoryId: 'cat-vegetables', startMode: 'now', durationUnit: 'days', durationValue: 1};
  await assert.rejects(() => saveMany(vendorCtx, {...batch, items: rows(6), ...nearShop}), /1 to 5/);
  await assert.rejects(() => saveMany(vendorCtx, {...batch, items: [], ...nearShop}), /1 to 5/);
  await assert.rejects(() => saveMany(vendorCtx, {...batch, items: rows(2), ...farShop}), /not near your shop/);
  await assert.rejects(() => saveMany(vendorCtx, {...batch, items: [rows(2)[0], {...rows(2)[1], submissionId: 'missing'}], ...nearShop}), /Item 2/);
  await assert.rejects(() => saveMany(vendorCtx, {...batch, items: [rows(2)[0], {...rows(2)[0]}], ...nearShop}), /own photo/);
  assert.equal((await db.collection('quickItems').get()).size, 1, 'a failed batch saves nothing');
  const made = await saveMany(vendorCtx, {...batch, items: rows(5), ...nearShop});
  assert.equal(made.itemIds.length, 5);
  assert.equal(made.remainingToday, 0, 'one single item + five in the batch = the vendor limit of 6');
  const batchDocs = await Promise.all(made.itemIds.map(async id => (await db.collection('quickItems').doc(id).get()).data()));
  assert.ok(batchDocs.every(d => d.status === 'pending' && d.locationTown === 'Rajahmundry' && d.durationMs === 86400000));
  await upload(vendor.uid, 'b6');
  await assert.rejects(() => saveMany(vendorCtx, {...batch, items: rows(6).slice(5), ...nearShop}), /Daily limit reached: you can add 6/);

  // ---- staff: the town comes from the pincode directory (found from GPS, or searched), not an admin list
  const kak = nearestPlace(16.95, 82.24);
  const staffTown = {locationTown: kak.town, locationDistrict: kak.district, locationPincode: kak.pincode};
  await upload(staff.uid, 's1');
  await assert.rejects(() => save(staffCtx, {...item, submissionId: 's1'}), /location/);
  await assert.rejects(() => save(staffCtx, {...item, submissionId: 's1', locationTown: 'Nowhereville', locationDistrict: 'East Godavari', locationPincode: '533101'}), /town from the list/);
  await assert.rejects(() => save(staffCtx, {...item, submissionId: 's1', locationTown: kak.town, locationDistrict: kak.district, locationPincode: '500001'}), /town from the list/);
  await assert.rejects(() => save(staffCtx, {...item, submissionId: 's1', locationId: 'loc-off'}), /location/);
  await assert.rejects(() => save(staffCtx, {...item, submissionId: 's1', ...staffTown, categoryId: 'nope'}), /category/);
  const first = await save(staffCtx, {...item, submissionId: 's1', ...staffTown, latitude: 16.95, longitude: 82.24});
  await upload(staff.uid, 's2');
  const second = await save(staffCtx, {...item, name: 'Onions', submissionId: 's2', locationId: 'loc-mkt'});
  const byName = Object.fromEntries((await db.collection('quickItems').where('ownerUid', '==', staff.uid).get()).docs.map(d => [d.data().name, d.data()]));
  assert.equal(byName.Tomatoes.locationTown, kak.town);
  assert.equal(byName.Tomatoes.locationPincode, kak.pincode);
  assert.equal(byName.Tomatoes.capturedLatitude, 16.95);
  assert.equal(byName.Onions.locationName, 'Old Market', 'an extra place added by the admin still works');
  assert.equal(byName.Tomatoes.ownerCode, 'ST001');

  // ---- nothing is public until approved; approval starts the clock
  const review = (ids, approved, reason) => fns.reviewQuickItems.run({...admin, data: {itemIds: ids, approved, reason}});
  await assert.rejects(() => fns.reviewQuickItems.run({...staffCtx, data: {itemIds: [first.itemId], approved: true}}), /Administrator/);
  const before = Date.now();
  assert.deepEqual(await review([first.itemId, second.itemId, one.itemId], true), {approved: 3, rejected: 0, skipped: 0});
  const approved = (await db.collection('quickItems').doc(first.itemId).get()).data();
  assert.equal(approved.status, 'approved');
  assert.ok(approved.startsAt.toMillis() >= before, 'starts at approval, not at save time');
  assert.equal(approved.expiresAt.toMillis() - approved.startsAt.toMillis(), 2 * 3600000);
  assert.match(approved.imageUrl, /catalog%2Fquick_/);
  assert.deepEqual(await review([first.itemId], true), {approved: 0, rejected: 0, skipped: 1}, 'cannot approve twice');
  await upload(staff.uid, 's3');
  const tomorrow = Date.now() + 24 * 3600000;
  const scheduled = await save(staffCtx, {...item, name: 'Fresh Beans', submissionId: 's3', ...staffTown, startMode: 'schedule', scheduleAt: tomorrow, durationUnit: 'days', durationValue: 1});
  await review([scheduled.itemId], true);
  const sch = (await db.collection('quickItems').doc(scheduled.itemId).get()).data();
  assert.equal(sch.startsAt.toMillis(), tomorrow);
  assert.equal(sch.expiresAt.toMillis(), tomorrow + 86400000);

  // ---- ownership; cancel; re-activate and edit go back to the admin (a vendor must be at the shop again)
  await assert.rejects(() => fns.cancelQuickItem.run({...ctx(staff2), data: {itemId: first.itemId}}), /not found/i);
  await assert.rejects(() => save(ctx(staff2), {...item, itemId: first.itemId, ...staffTown}), /not found/i);
  assert.equal((await fns.cancelQuickItem.run({...staffCtx, data: {itemId: first.itemId}})).status, 'cancelled');
  await fns.reactivateQuickItem.run({...staffCtx, data: {itemId: first.itemId, startMode: 'now', durationUnit: 'days', durationValue: 2}});
  let again = (await db.collection('quickItems').doc(first.itemId).get()).data();
  assert.equal(again.status, 'pending');
  assert.equal(again.startsAt, undefined);
  assert.equal(again.durationMs, 2 * 86400000);
  await save(staffCtx, {...item, itemId: first.itemId, price: 35, ...staffTown});
  assert.equal((await db.collection('quickItems').doc(first.itemId).get()).data().price, 35);
  await fns.cancelQuickItem.run({...vendorCtx, data: {itemId: one.itemId}});
  await assert.rejects(() => fns.reactivateQuickItem.run({...vendorCtx, data: {itemId: one.itemId, startMode: 'now', durationUnit: 'hours', durationValue: 1, ...farShop}}), /not near your shop/);
  await fns.reactivateQuickItem.run({...vendorCtx, data: {itemId: one.itemId, startMode: 'now', durationUnit: 'hours', durationValue: 1, ...nearShop}});
  assert.equal((await db.collection('quickItems').doc(one.itemId).get()).data().status, 'pending');
  await assert.rejects(() => save(vendorCtx, {...item, itemId: one.itemId, ...farShop}), /not near your shop/);

  // ---- reject and take-down by the admin; expiry hides, never deletes
  assert.deepEqual(await review([first.itemId], false, 'blurry photo'), {approved: 0, rejected: 1, skipped: 0});
  assert.deepEqual(await review([second.itemId], false, 'wrong price'), {approved: 0, rejected: 1, skipped: 0});
  await db.collection('quickItems').doc(made.itemIds[0]).update({status: 'approved', expiresAt: Timestamp.fromMillis(Date.now() - 1000), startsAt: Timestamp.fromMillis(Date.now() - 7200000)});
  assert.equal(await fns._quick.expireQuickItems(), 1);
  const gone = await db.collection('quickItems').doc(made.itemIds[0]).get();
  assert.equal(gone.exists, true);
  assert.equal(gone.data().status, 'expired');

  // ---- an inactive account cannot add anything
  await fns.setQuickAccountActive.run({...admin, data: {uid: staff.uid, active: false}});
  await upload(staff.uid, 's4');
  await assert.rejects(() => save(staffCtx, {...item, submissionId: 's4', ...staffTown}), /inactive, contact admin/);
  await fns.setQuickAccountActive.run({...admin, data: {uid: staff.uid, active: true}});
  await save(staffCtx, {...item, submissionId: 's4', ...staffTown});
  await assert.rejects(() => save({auth: {uid: 'stranger', token: {email_verified: true}}}, {...item, submissionId: 's4', ...staffTown}), /not set up/);

  // ---- only the admin can unlock a shop location, so it can be set again
  await assert.rejects(() => fns.updateQuickAccount.run({...vendorCtx, data: {uid: vendor.uid, resetShopLocation: true}}), /Administrator/);
  await fns.updateQuickAccount.run({...admin, data: {uid: vendor.uid, resetShopLocation: true}});
  assert.equal((await db.collection('quickAccounts').doc(vendor.uid).get()).data().shopLocked, false);
  const relock = await fns.setQuickShopLocation.run({...vendorCtx, data: {latitude: 16.95, longitude: 82.24}});
  assert.equal(relock.town, kak.town);

  // ---- daily limit for staff: 15 by default, admin can change it
  for (const d of (await db.collection('quickItems').where('ownerUid', '==', staff.uid).get()).docs) await d.ref.delete();
  for (let i = 1; i <= 15; i++) { await upload(staff.uid, `st${i}`); await save(staffCtx, {...item, name: `Staff ${i}`, submissionId: `st${i}`, ...staffTown}); }
  await upload(staff.uid, 'st16');
  await assert.rejects(() => save(staffCtx, {...item, name: 'Staff 16', submissionId: 'st16', ...staffTown}), /Daily limit reached: you can add 15/);
  await db.collection('settings').doc('business').set({name: 'Test', quickItemsPerDayStaff: 16});
  await save(staffCtx, {...item, name: 'Staff 16', submissionId: 'st16', ...staffTown});
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
