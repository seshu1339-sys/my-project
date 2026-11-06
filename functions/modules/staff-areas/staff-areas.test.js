const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly', storageBucket: 'demo-neighbourly.appspot.com'});
const {Timestamp} = require('firebase-admin/firestore');
const R = require('./rules');
const S = require('./store');

test('town radius: 1, 2, 3, 5 km or another between 0.2 and 50', () => {
  assert.equal(R.validateRadius(2), 2);
  assert.equal(R.validateRadius(1.25), 1.3);
  assert.throws(() => R.validateRadius(0.1), /radius/);
  assert.throws(() => R.validateRadius(60), /radius/);
  assert.equal(R.townKey('Krishna Bazar (Narsipatnam)'), 'narsipatnam');
  assert.equal(R.townKey(' Narsipatnam '), 'narsipatnam');
});

test('areas overlap when their circles touch; a place is inside or not', () => {
  const a = {latitude: 17.668, longitude: 82.612, radiusKm: 1};
  const near = {latitude: 17.678, longitude: 82.612, radiusKm: 1}; // ~1.1 km away
  const far = {latitude: 17.700, longitude: 82.612, radiusKm: 1}; // ~3.6 km away
  assert.equal(R.overlaps(a, near), true);
  assert.equal(R.overlaps(a, far), false);
  assert.equal(R.inside(a, 17.669, 82.613), true);
  assert.equal(R.inside(a, 17.700, 82.612), false);
  assert.equal(R.inside(a, undefined, 82.6), false);
});

test('India days: start, end, the next day', () => {
  const ms = Date.parse('2026-11-06T20:00:00Z'); // 01:30 on 7 Nov in India
  assert.equal(R.istDay(ms), '2026-11-07');
  assert.equal(R.dayStart('2026-11-07'), Date.parse('2026-11-06T18:30:00Z'));
  assert.equal(R.addDays('2026-11-30', 1), '2026-12-01');
});

test('a staff offer: the normal price and a lower offer price; always today (staff choose no dates)', () => {
  const ok = {shopId: 's1', libraryItemId: 'lib-tomato', regularPrice: 32, offerPrice: 25};
  assert.equal(R.validateStaffOffer(ok, '2026-11-06').validDate, '2026-11-06');
  assert.equal(R.validateStaffOffer({...ok, validDate: '2026-11-12'}, '2026-11-06').validDate, '2026-11-06', 'a date sent by an old app is ignored');
  assert.throws(() => R.validateStaffOffer({...ok, offerPrice: 32}, '2026-11-06'), /lower/);
  assert.throws(() => R.validateStaffOffer({...ok, regularPrice: undefined}, '2026-11-06'), /normal price/);
});

test('settings: monthly targets, rate days a week, missed days; the warning comes on the last-chance day, before it is missed', () => {
  const d = R.settingsOf({});
  assert.deepEqual([d.monthlyPhotoTarget, d.monthlyVendorTarget, d.monthlyPaidVendorTarget, d.rateDaysPerWeek, d.maxMissedDays], [100, 10, 2, 4, 7]);
  assert.throws(() => R.validateSettings({rateDaysPerWeek: 8}), /1 to 7/);
  assert.throws(() => R.validateSettings({maxMissedDays: 0}), /1 to 31/);
  assert.throws(() => R.validateSettings({}), /Nothing/);
  assert.equal(R.missedOutcome(6, 7), 'missed');
  assert.equal(R.missedOutcome(7, 7), 'deactivate', 'the 7th missed day stops the account');
  // 4 rate days a week = 3 free days off. With 6 missed of 7, today is the last chance only once the free days are used up.
  assert.equal(R.lastChance(6, 7, 3, 4), true, 'one more missed day would stop it: warn today');
  assert.equal(R.lastChance(6, 7, 2, 4), false, 'today would only be a free day off');
  assert.equal(R.lastChance(5, 7, 3, 4), false, 'two more are needed');
  assert.equal(R.lastChance(0, 1, 3, 4), true, 'with 1 allowed, every non-free day is the last chance');
  // Daily, weekly and monthly targets for live photos, shops visited, new vendors and new paid vendors (owner, 7 Nov 2026).
  assert.deepEqual([d.dailyPhotoTarget, d.weeklyShopTarget, d.monthlyShopTarget, d.dailyPaidVendorTarget], [0, 0, 0, 0], 'no target until the admin sets one');
  assert.deepEqual(R.validateSettings({dailyShopTarget: 5, weeklyVendorTarget: 3}), {dailyShopTarget: 5, weeklyVendorTarget: 3});
  assert.throws(() => R.validateSettings({dailyPhotoTarget: -1}), /live photos a day/);
  assert.throws(() => R.validateSettings({weeklyShopTarget: 1.5}), /shops visited a week/);
  const daily = R.periodTargets({...d, dailyShopTarget: 3}, 'daily', {photos: 4, shops: 2, vendors: 0, paidVendors: 0});
  assert.deepEqual(daily.shops, {done: 2, target: 3, complete: false});
  assert.deepEqual(daily.photos, {done: 4, target: 0, complete: true}, 'a target of 0 is always complete');
  assert.equal(R.dayOff(0, 4), 'off');
  assert.equal(R.dayOff(2, 4), 'off');
  assert.equal(R.dayOff(3, 4), 'missed', 'with 4 rate days a week, 3 days off are free');
  assert.equal(R.weekOf('2026-11-06'), '2026-11-02', 'weeks start on Monday');
  assert.deepEqual(R.targetProgress(99, 100), {done: 99, target: 100, complete: false});
  for (const rule of ['no fixed salary', 'One area per staff', "Today's Offers", 'live camera photo', 'monthly targets', 'deactivated automatically', 'change these rules']) {
    assert.match(R.DEFAULT_TERMS, new RegExp(rule, 'i'), rule);
  }
});

test('a live photo counts only with real GPS, accurate, within 100 m of the shop, sent soon after it was taken', () => {
  const shop = {latitude: 17.668, longitude: 82.612};
  const now = Date.parse('2026-11-06T10:00:00Z');
  const good = {latitude: 17.6684, longitude: 82.6121, accuracy: 15, mocked: false, takenAt: now - 60000};
  assert.equal(R.livePhotoProblem(good, shop, now), null);
  assert.match(R.livePhotoProblem({...good, mocked: true}, shop, now), /Fake GPS/);
  assert.match(R.livePhotoProblem({...good, mocked: undefined}, shop, now), /Fake GPS/, 'unknown counts as fake');
  assert.match(R.livePhotoProblem({...good, latitude: 17.70}, shop, now), /Go to the shop/, 'from home, km away');
  assert.match(R.livePhotoProblem({...good, latitude: 17.6695}, shop, now), /within 100 m/, 'about 170 m away');
  assert.match(R.livePhotoProblem({...good, accuracy: 500}, shop, now), /not exact enough/);
  assert.match(R.livePhotoProblem({...good, takenAt: now - 60 * 60000}, shop, now), /too old/);
  assert.match(R.livePhotoProblem(good, {}, now), /no map location/);
});

const emulator = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
const withStorage = {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST};
const T = Date.parse('2031-03-05T10:00:00+05:30');
const CENTRE = {latitude: 17.668, longitude: 82.612};
async function setup() {
  const {getFirestore} = require('firebase-admin/firestore');
  const db = getFirestore();
  for (const c of ['staffAreaTowns', 'staffAreas', 'staffAreaHolders', 'staffAreaStaff', 'staffAreaSettings', 'staffAreaDays', 'fieldStaff', 'shops', 'vendorOffers', 'productImageLibrary', 'staffLinks', 'staffOfferPhotoUses', 'vendorPremium']) {
    for (const d of (await db.collection(c).get()).docs) await d.ref.delete();
  }
  await db.collection('fieldStaff').doc('s1').set({status: 'pending', name: 'Kiran', phone: '9876500001', staffCode: 'STF-NRPM-116-482'});
  await db.collection('fieldStaff').doc('s2').set({status: 'active', name: 'Ravi', phone: '9876500002', staffCode: 'STF-NRPM-116-483'});
  await db.collection('shops').doc('inA').set({name: 'Lakshmi Kirana', latitude: 17.6685, longitude: 82.6125, active: true});
  await db.collection('shops').doc('inB').set({name: 'Ravi Fruits', latitude: 17.6675, longitude: 82.6115, active: true});
  await db.collection('shops').doc('out').set({name: 'Far Shop', latitude: 17.75, longitude: 82.7, active: true});
  await db.collection('productImageLibrary').doc('lib-tomato').set({name: 'Tomato', imageUrl: 'https://example.test/tomato.jpg', active: true});
  await S.saveTown(db, {town: 'Narsipatnam', radiusKm: 1}, T);
  const {areaId} = await S.saveArea(db, {name: 'Narsipatnam Main Bazaar', town: 'Narsipatnam', ...CENTRE}, T);
  return {db, areaId};
}

test('admin: areas need the town radius, never overlap; a new radius moves to every area unless they would overlap', emulator, async () => {
  const {db, areaId} = await setup();
  assert.equal((await db.collection('staffAreas').doc(areaId).get()).data().status, 'free');
  await assert.rejects(S.saveArea(db, {name: 'Too close', town: 'Narsipatnam', latitude: 17.675, longitude: 82.612}, T), /overlap "Narsipatnam Main Bazaar"/);
  await assert.rejects(S.saveArea(db, {name: 'Elsewhere', town: 'Anakapalli', latitude: 17.69, longitude: 83.0}, T), /radius of Anakapalli first/);
  const second = await S.saveArea(db, {name: 'Bus Stand', town: 'Narsipatnam', latitude: 17.690, longitude: 82.612}, T); // ~2.4 km away
  await assert.rejects(S.saveTown(db, {town: 'Narsipatnam', radiusKm: 2}, T), /would overlap/);
  await S.saveTown(db, {town: 'Narsipatnam', radiusKm: 1.1}, T);
  assert.equal((await db.collection('staffAreas').doc(second.areaId).get()).data().radiusKm, 1.1);
});

test('claim: only standing inside, Terms accepted, one area each; pending until approved, then booked; refused staff frees it', emulator, async () => {
  const {db, areaId} = await setup();
  const at = {areaId, latitude: 17.6682, longitude: 82.6122, termsAccepted: true};
  await assert.rejects(S.claimArea(db, 's1', {...at, termsAccepted: false}, T), /Terms/);
  await assert.rejects(S.claimArea(db, 's1', {...at, latitude: 17.70}, T), /Please go to this area to register it/);
  assert.deepEqual(await S.claimArea(db, 's1', at, T), {areaId, status: 'pending'});
  await assert.rejects(S.claimArea(db, 's2', at, T), /already taken/);
  const holder = (await db.collection('staffAreaHolders').doc(areaId).get()).data();
  assert.deepEqual([holder.staffCode, holder.staffName, holder.staffPhone], ['STF-NRPM-116-482', 'Kiran', '9876500001']);
  assert.equal((await db.collection('staffAreas').doc(areaId).get()).data().staffUid, undefined, 'who holds it is not on the public area');

  assert.equal(await S.onStaffStatus(db, 's1', {status: 'pending'}, {status: 'active'}, T + 1000), 'booked');
  assert.equal((await db.collection('staffAreas').doc(areaId).get()).data().status, 'booked');
  const other = await S.saveArea(db, {name: 'Bus Stand', town: 'Narsipatnam', latitude: 17.690, longitude: 82.612}, T);
  await assert.rejects(S.claimArea(db, 's1', {areaId: other.areaId, latitude: 17.690, longitude: 82.612, termsAccepted: true}, T), /already have an area/);

  // An approved staff member claims and is booked at once.
  assert.equal((await S.claimArea(db, 's2', {areaId: other.areaId, latitude: 17.690, longitude: 82.612, termsAccepted: true}, T)).status, 'booked');

  // Not approved: the area is free again.
  await db.collection('fieldStaff').doc('s3').set({status: 'pending', staffCode: 'STF-NRPM-116-484'});
  const third = await S.saveArea(db, {name: 'Market', town: 'Narsipatnam', latitude: 17.712, longitude: 82.612}, T);
  await S.claimArea(db, 's3', {areaId: third.areaId, latitude: 17.712, longitude: 82.612, termsAccepted: true}, T);
  assert.equal(await S.onStaffStatus(db, 's3', {status: 'pending'}, {status: 'rejected'}, T), 'free');
  assert.equal((await db.collection('staffAreas').doc(third.areaId).get()).data().status, 'free');
});

async function bookedArea() {
  const {db, areaId} = await setup();
  await S.claimArea(db, 's2', {areaId, ...CENTRE, termsAccepted: true}, T - 3 * R.DAY_MS);
  return {db, areaId};
}

let photoSeq = 0;
/// A live photo taken now at the shop (inA), uploaded like the staff app does.
async function livePhoto(at, extra = {}) {
  const {getStorage} = require('firebase-admin/storage');
  const id = `photo${Date.now()}${++photoSeq}`;
  await getStorage().bucket().file(`staffOfferPhotos/s2/${id}`).save(Buffer.from([0xff, 0xd8, 0xff]), {metadata: {contentType: 'image/jpeg'}});
  return {id, latitude: 17.6686, longitude: 82.6126, accuracy: 12, mocked: false, takenAt: at - 30000, ...extra};
}
const bucket = () => require('firebase-admin/storage').getStorage().bucket();

test("rate updates: a live photo at a shop of my area (never from home or with fake GPS), the admin's item, a lower price", withStorage, async () => {
  const {db, areaId} = await bookedArea();
  const now = Date.now();
  const offer = {shopId: 'inA', libraryItemId: 'lib-tomato', regularPrice: 32, offerPrice: 25};
  await assert.rejects(S.addStaffOffer(db, bucket(), 's2', offer, now), /live photo/);
  await assert.rejects(S.addStaffOffer(db, bucket(), 's2', {...offer, photo: await livePhoto(now, {latitude: 17.70})}, now), /Go to the shop/, 'from home');
  await assert.rejects(S.addStaffOffer(db, bucket(), 's2', {...offer, photo: await livePhoto(now, {mocked: true})}, now), /Fake GPS/);
  await assert.rejects(S.addStaffOffer(db, bucket(), 's2', {...offer, photo: {...(await livePhoto(now)), id: 'neverUploaded1'}}, now), /live photo/);
  const photo = await livePhoto(now);
  const {offerId, metres} = await S.addStaffOffer(db, bucket(), 's2', {...offer, photo}, now);
  assert.ok(metres < 100);
  const saved = (await db.collection('vendorOffers').doc(offerId).get()).data();
  assert.deepEqual([saved.source, saved.livePhotoVerified, saved.title, saved.vendorId], ['staff', true, 'Tomato', '']);
  assert.match(saved.photos[0], /staffOfferPhotos/, 'the live photo first');
  await assert.rejects(S.addStaffOffer(db, bucket(), 's2', {...offer, libraryItemId: 'lib-tomato', photo}, now), /already has this item|already/, 'one photo never counts twice');
  await assert.rejects(S.addStaffOffer(db, bucket(), 's2', {...offer, shopId: 'out', photo: await livePhoto(now)}, now), /inside your own area/);
  const today = await S.myToday(db, 's2', now + 1000);
  assert.equal(today.area.id, areaId);
  assert.equal(today.todayUpdates, 1);
  assert.deepEqual(today.photos, {done: 1, target: 100, complete: false});
  assert.deepEqual(today.rateDays, {done: 1, target: 4, complete: false});
  await S.removeStaffOffer(db, 's2', {offerId});
});

test('monthly targets: linked vendors this month and the paid ones among them', emulator, async () => {
  const {db} = await bookedArea();
  const now = Date.now();
  await S.saveSettings(db, {monthlyVendorTarget: 2, monthlyPaidVendorTarget: 1}, now);
  await db.collection('staffLinks').doc('vendor_a').set({kind: 'vendor', accountUid: 'a', staffUid: 's2', linkedAt: Timestamp.fromMillis(now)});
  await db.collection('staffLinks').doc('vendor_b').set({kind: 'vendor', accountUid: 'b', staffUid: 's2', linkedAt: Timestamp.fromMillis(now)});
  await db.collection('vendorPremium').doc('b').set({active: true, endsAt: Timestamp.fromMillis(now + 86400000)});
  const today = await S.myToday(db, 's2', now);
  assert.deepEqual(today.vendors, {done: 2, target: 2, complete: true});
  assert.deepEqual(today.paidVendors, {done: 1, target: 1, complete: true});
});

test('nightly: a day without rate updates is a free day off while the week allows, then a missed day; warned on the morning of the last-chance day; reactivation gives the area back', emulator, async () => {
  const {db, areaId} = await bookedArea();
  // 6 rate days a week = 1 free day off a week; the account stops at the 2nd missed day.
  await S.saveSettings(db, {rateDaysPerWeek: 6, maxMissedDays: 2}, T);
  const pushed = [];
  const push = async (uid, title) => { pushed.push(title); };
  const night = n => T + n * R.DAY_MS; // the check of day T + n - 1 (T is a Wednesday)
  let r = await S.nightlyCheck(db, push, night(1));
  assert.equal(r.results[0].outcome, 'off', 'the week\'s free day off');
  assert.equal(r.results[0].warned, false, '0 missed of 2: today is not the last chance');
  r = await S.nightlyCheck(db, push, night(1) + 1000);
  assert.equal(r.results.length, 0, 'the same day is never counted twice');
  r = await S.nightlyCheck(db, push, night(2));
  assert.equal(r.results[0].outcome, 'missed');
  assert.equal(r.results[0].warned, true, '1 missed of 2 and no free day left: warned at the start of the last-chance day');
  const record = (await db.collection('staffAreaStaff').doc('s2').get()).data();
  assert.match(record.warning, /Last chance today/);
  assert.equal(record.lastChanceDay, R.istDay(night(2)));
  // 5 PM on that day: nothing sent yet, so a second reminder; once a rate update is sent, none.
  assert.deepEqual((await S.lastChanceReminder(db, push, night(2) + 12 * 3600000)).reminded, ['s2']);
  await db.collection('vendorOffers').add({source: 'staff', staffUid: 's2', livePhotoVerified: true, shopId: 'inA', status: 'live', createdAt: Timestamp.fromMillis(night(2))});
  assert.deepEqual((await S.lastChanceReminder(db, push, night(2) + 12 * 3600000)).reminded, []);
  r = await S.nightlyCheck(db, push, night(3));
  assert.equal(r.results[0].outcome, 'worked');
  assert.equal(r.results[0].warned, true, 'still 1 missed and no free day this week: the next day is a last chance too');
  // An update WITHOUT a verified live photo does not count.
  await db.collection('vendorOffers').add({source: 'staff', staffUid: 's2', shopId: 'inA', status: 'live', createdAt: Timestamp.fromMillis(night(3))});
  r = await S.nightlyCheck(db, push, night(4));
  assert.equal(r.results[0].outcome, 'deactivate');
  assert.equal((await db.collection('fieldStaff').doc('s2').get()).data().status, 'suspended');
  assert.equal((await db.collection('staffAreas').doc(areaId).get()).data().status, 'free');
  assert.deepEqual(pushed, ['Last chance today: update rates', 'Reminder: last chance today', 'Last chance today: update rates', 'Your staff ID is stopped']);

  const report = await S.report(db, {month: R.istDay(night(1)).slice(0, 7)}, night(4));
  const row = report.staff.find(s => s.staffUid === 's2');
  assert.equal(row.missedDays, 2);
  assert.equal(row.daysWorked, 1);
  assert.equal(report.towns[0].deactivatedThisMonth, 1);

  assert.deepEqual(await S.reactivate(db, {staffUid: 's2'}, 'admin1', night(4) + 1000), {areaId});
  assert.equal((await db.collection('fieldStaff').doc('s2').get()).data().status, 'active');
  assert.equal((await db.collection('staffAreaStaff').doc('s2').get()).data().missedThisMonth, 0);
});

test('reactivation is refused when the area was taken meanwhile', emulator, async () => {
  const {db, areaId} = await bookedArea();
  await S.saveSettings(db, {rateDaysPerWeek: 7, maxMissedDays: 1}, T);
  await S.nightlyCheck(db, async () => {}, T + R.DAY_MS);
  assert.equal((await db.collection('staffAreas').doc(areaId).get()).data().status, 'free');
  await db.collection('fieldStaff').doc('s9').set({status: 'active', staffCode: 'STF-NRPM-116-499'});
  await S.claimArea(db, 's9', {areaId, ...CENTRE, termsAccepted: true}, T + R.DAY_MS);
  await assert.rejects(S.reactivate(db, {staffUid: 's2'}, 'admin1'), /taken now/);
});
