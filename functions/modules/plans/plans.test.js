const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {Timestamp} = require('firebase-admin/firestore');
const {validatePlan, validateGates, addMonths, planPeriod} = require('./rules');
const {savePlan, saveGates, startPurchase, activatePlan, adminActivatePlan, adminStopPlan} = require('./store');
const {planAllows, requirePlan, vendorItemLimitNow} = require('../../plan-gate');

const good = (extra = {}) => ({name: '1 Year', price: 4999, durationMonths: 12, ...extra});

test('what the admin may save as a plan is checked', () => {
  assert.deepEqual(validatePlan(good({name: '  Gold   plan '})), {name: 'Gold plan', tier: 'premium', price: 4999, durationMonths: 12, itemLimit: 10, extraPhotos: 10, radiusKm: 25, offerBoxes: 5, active: true});
  assert.equal(validatePlan(good({active: false})).active, false);
  assert.equal(validatePlan(good({price: 99.5})).price, 99.5);
  assert.throws(() => validatePlan(good({name: 'x'})), /name/);
  assert.throws(() => validatePlan(good({price: 0})), /price/);
  assert.throws(() => validatePlan(good({price: '4999'})), /price/);
  assert.throws(() => validatePlan(good({price: 10.123})), /decimals/);
  assert.throws(() => validatePlan(good({durationMonths: 0})), /duration/);
  assert.throws(() => validatePlan(good({durationMonths: 1.5})), /duration/);
  assert.throws(() => validatePlan(good({durationMonths: 121})), /duration/);
});

test("a plan allows 10 items unless the admin sets its own number; the free number is the admin's too", () => {
  assert.equal(validatePlan(good()).itemLimit, 10);
  assert.equal(validatePlan(good({itemLimit: 25})).itemLimit, 25);
  assert.throws(() => validatePlan(good({itemLimit: 0})), /items/);
  assert.throws(() => validatePlan(good({itemLimit: 2.5})), /items/);
  assert.throws(() => validatePlan(good({itemLimit: 101})), /items/);
  assert.deepEqual(validateGates({freeItemLimit: 3}), {freeItemLimit: 3});
  assert.deepEqual(validateGates({freeItemLimit: 0, vendorAds: true}), {vendorAds: true, freeItemLimit: 0});
  assert.throws(() => validateGates({freeItemLimit: -1}), /free vendor/);
});

test('Silver, Gold and Premium differ only in extra photos and km, which the admin sets', () => {
  const silver = validatePlan(good({name: 'Silver', tier: 'silver', extraPhotos: 4, radiusKm: 10}));
  assert.deepEqual([silver.tier, silver.extraPhotos, silver.radiusKm, silver.offerBoxes], ['silver', 4, 10, 1]);
  // Today's Offers boxes: Silver 1, Gold 3, Premium 5 unless the admin sets the plan's own number (owner, 7 Nov 2026).
  assert.equal(validatePlan(good({tier: 'gold'})).offerBoxes, 3);
  assert.equal(validatePlan(good({tier: 'premium', offerBoxes: 8})).offerBoxes, 8);
  assert.throws(() => validatePlan(good({offerBoxes: 21})), /Today's Offers boxes/);
  assert.throws(() => validatePlan(good({offerBoxes: 1.5})), /Today's Offers boxes/);
  assert.throws(() => validatePlan(good({tier: 'diamond'})), /Silver, Gold or Premium/);
  assert.throws(() => validatePlan(good({extraPhotos: 31})), /extra photos/);
  assert.throws(() => validatePlan(good({radiusKm: 0})), /km/);
});

test('only known services can be gated', () => {
  assert.deepEqual(validateGates({vendorAds: true, shopVisibility: true, exclusives: 'yes'}), {vendorAds: true});
  assert.throws(() => validateGates({shopVisibility: true}), /service/);
});

test('months are calendar months in India', () => {
  const at = text => Date.parse(text);
  assert.equal(addMonths(at('2026-11-02T10:00:00+05:30'), 12), at('2027-11-02T10:00:00+05:30'));
  assert.equal(addMonths(at('2028-02-29T10:00:00+05:30'), 12), at('2029-02-28T10:00:00+05:30'), 'no 29 Feb next year');
  assert.equal(addMonths(at('2027-01-31T10:00:00+05:30'), 1), at('2027-02-28T10:00:00+05:30'));
  assert.equal(addMonths(at('2026-12-31T23:30:00+05:30'), 12), at('2027-12-31T23:30:00+05:30'), 'late evening stays on its Indian day');
});

test('a plan starts on the payment date, a renewal when the running plan ends', () => {
  const paid = Date.parse('2027-01-10T09:00:00+05:30');
  assert.deepEqual(planPeriod(paid, 12), {startsAt: paid, endsAt: Date.parse('2028-01-10T09:00:00+05:30')});
  const expired = paid - 86400000;
  assert.equal(planPeriod(paid, 12, expired).startsAt, paid, 'an ended plan changes nothing');
  const running = Date.parse('2027-03-01T00:00:00+05:30');
  assert.deepEqual(planPeriod(paid, 12, running), {startsAt: running, endsAt: Date.parse('2028-03-01T00:00:00+05:30')});
});

// A tiny stand-in for the two documents the gate reads.
const fakeDb = (gates, status) => ({
  collection: name => ({doc: () => ({get: async () => ({data: () => (name === 'planServiceGates' ? gates : status)})})}),
});

test('the gate lets every service through until the admin switches it on', async () => {
  assert.equal(await planAllows(fakeDb(undefined, undefined), 'v1', 'vendorAds'), true);
  assert.equal(await planAllows(fakeDb({vendorAds: false}, undefined), 'v1', 'vendorAds'), true);
  assert.equal(await planAllows(fakeDb({exclusives: true}, undefined), 'v1', 'vendorAds'), true);
});

test('a switched-on gate needs a running plan, and stops when the plan ends', async () => {
  const now = Date.parse('2027-06-01T00:00:00Z');
  const endsAt = ms => ({endsAt: Timestamp.fromMillis(ms)});
  assert.equal(await planAllows(fakeDb({vendorAds: true}, undefined), 'v1', 'vendorAds', now), false);
  assert.equal(await planAllows(fakeDb({vendorAds: true}, endsAt(now + 1000)), 'v1', 'vendorAds', now), true);
  assert.equal(await planAllows(fakeDb({vendorAds: true}, endsAt(now - 1000)), 'v1', 'vendorAds', now), false);
  await assert.rejects(requirePlan(fakeDb({vendorAds: true}, undefined), 'v1', 'vendorAds', now), /active plan/);
});

test("the item limit: free 2 (or the admin's free number, or this vendor's own), a running plan's number when bigger", async () => {
  const now = Date.parse('2027-06-01T00:00:00Z');
  const plan = (ms, itemLimit) => ({endsAt: Timestamp.fromMillis(ms), itemLimit});
  assert.equal(await vendorItemLimitNow(fakeDb(undefined, undefined), 'v1', {}, now), 2);
  assert.equal(await vendorItemLimitNow(fakeDb({freeItemLimit: 3}, undefined), 'v1', {}, now), 3);
  assert.equal(await vendorItemLimitNow(fakeDb({freeItemLimit: 3}, undefined), 'v1', {itemLimit: 5}, now), 5, 'the admin gave this vendor 5');
  assert.equal(await vendorItemLimitNow(fakeDb(undefined, plan(now + 1000, 10)), 'v1', {}, now), 10);
  assert.equal(await vendorItemLimitNow(fakeDb(undefined, plan(now + 1000, undefined)), 'v1', {}, now), 10, 'a plan made before limits');
  assert.equal(await vendorItemLimitNow(fakeDb(undefined, plan(now - 1000, 10)), 'v1', {}, now), 2, 'the plan ended');
  assert.equal(await vendorItemLimitNow(fakeDb(undefined, plan(now + 1000, 10)), 'v1', {itemLimit: 20}, now), 20);
  const broken = {collection: () => ({doc: () => ({get: async () => { throw Error('offline'); }})})};
  assert.equal(await vendorItemLimitNow(broken, 'v1', {}, now), 2);
});

test('a failed gate read never stops a service', async () => {
  const broken = {collection: () => ({doc: () => ({get: async () => { throw Error('offline'); }})})};
  assert.equal(await planAllows(broken, 'v1', 'vendorAds'), true);
});

const emulator = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
const t0 = Date.parse('2031-03-05T10:00:00+05:30');
async function setup() {
  const {getFirestore} = require('firebase-admin/firestore');
  const db = getFirestore();
  for (const c of ['vendorPlans', 'planServiceGates', 'vendorPlanPeriods', 'vendorPlanStatus', 'paymentRequests', 'vendors', 'vendorNotices', 'shops']) {
    for (const d of (await db.collection(c).get()).docs) await d.ref.delete();
  }
  await db.collection('vendors').doc('v1').set({status: 'approved', name: 'Ramu', shopId: 'v1'});
  await db.collection('vendors').doc('v2').set({status: 'pending', name: 'New'});
  await db.collection('shops').doc('v1').set({active: true, name: 'Ramu Kirana'});
  return db;
}
// What the payment module does: marks the request verified. The trigger then calls activatePlan with that document.
const verified = async (db, id, paidAt) => {
  const ref = db.collection('paymentRequests').doc(id);
  await ref.update({status: 'verified', paidAt: Timestamp.fromMillis(paidAt)});
  return activatePlan(db, id, (await ref.get()).data(), paidAt + 60000);
};

test('the vendor gets exactly the admin price, even if the price changes after choosing', emulator, async () => {
  const db = await setup();
  const {planId} = await savePlan(db, good(), t0);
  const {requestId, amount} = await startPurchase(db, 'v1', {planId}, t0);
  assert.equal(amount, 4999);
  const request = (await db.collection('paymentRequests').doc(requestId).get()).data();
  assert.equal(request.amount, 4999);
  assert.equal(request.source, 'plans');
  assert.equal(request.status, 'awaiting_payment');
  await savePlan(db, good({planId, price: 5999}), t0 + 1000);
  const period = (await db.collection('vendorPlanPeriods').doc(requestId).get()).data();
  assert.equal(period.price, 4999);
  assert.equal(period.status, 'pending');
});

test('only an approved vendor, and only an active plan', emulator, async () => {
  const db = await setup();
  const {planId} = await savePlan(db, good(), t0);
  await assert.rejects(startPurchase(db, 'v2', {planId}, t0), /approved vendor/);
  await assert.rejects(startPurchase(db, 'nobody', {planId}, t0), /approved vendor/);
  await savePlan(db, good({planId, active: false}), t0);
  await assert.rejects(startPurchase(db, 'v1', {planId}, t0), /not available/);
  await assert.rejects(startPurchase(db, 'v1', {planId: 'missing'}, t0), /not available/);
});

test('choosing again reuses the open request; another plan replaces it', emulator, async () => {
  const db = await setup();
  const a = await savePlan(db, good(), t0);
  const b = await savePlan(db, good({name: '2 Years', price: 8999, durationMonths: 24}), t0);
  const first = await startPurchase(db, 'v1', {planId: a.planId}, t0);
  assert.equal((await startPurchase(db, 'v1', {planId: a.planId}, t0)).requestId, first.requestId);
  const second = await startPurchase(db, 'v1', {planId: b.planId}, t0);
  assert.notEqual(second.requestId, first.requestId);
  assert.equal((await db.collection('paymentRequests').doc(first.requestId).get()).data().status, 'cancelled');
  assert.equal((await db.collection('vendorPlanPeriods').doc(first.requestId).get()).data().status, 'cancelled');
  await db.collection('paymentRequests').doc(second.requestId).update({status: 'checking'});
  await assert.rejects(startPurchase(db, 'v1', {planId: a.planId}, t0), /still being checked/);
});

test('a verified payment activates the plan once, from the payment date, and the shop is not touched', emulator, async () => {
  const db = await setup();
  const {planId} = await savePlan(db, good(), t0);
  const {requestId} = await startPurchase(db, 'v1', {planId}, t0);
  const paidAt = t0 + 3600000;
  const result = await verified(db, requestId, paidAt);
  assert.equal(result.startsAt, paidAt);
  assert.equal(result.endsAt, Date.parse('2032-03-05T11:00:00+05:30'));
  const status = (await db.collection('vendorPlanStatus').doc('v1').get()).data();
  assert.equal(status.endsAt.toMillis(), result.endsAt);
  assert.equal(status.planName, '1 Year');
  assert.equal(await verified(db, requestId, paidAt + 5000), null, 'a repeated event changes nothing');
  assert.equal((await db.collection('vendorNotices').where('vendorId', '==', 'v1').get()).size, 1);
  assert.equal((await db.collection('shops').doc('v1').get()).data().active, true);
});

test('another vendor\'s request cannot activate anything', emulator, async () => {
  const db = await setup();
  const {planId} = await savePlan(db, good(), t0);
  const {requestId} = await startPurchase(db, 'v1', {planId}, t0);
  assert.equal(await activatePlan(db, requestId, {uid: 'v2', paidAt: Timestamp.fromMillis(t0)}, t0), null);
  assert.equal((await db.collection('vendorPlanStatus').doc('v2').get()).exists, false);
});

test('a renewal adds to the running plan; the gate follows the end date', emulator, async () => {
  const db = await setup();
  await saveGates(db, {vendorAds: true}, t0);
  const {planId} = await savePlan(db, good(), t0);
  assert.equal(await planAllows(db, 'v1', 'vendorAds', t0), false);
  const first = await startPurchase(db, 'v1', {planId}, t0);
  await verified(db, first.requestId, t0);
  const second = await startPurchase(db, 'v1', {planId}, t0 + 1000);
  const paidAgain = t0 + 30 * 86400000;
  const renewed = await verified(db, second.requestId, paidAgain);
  assert.equal(renewed.startsAt, Date.parse('2032-03-05T10:00:00+05:30'));
  assert.equal(renewed.endsAt, Date.parse('2033-03-05T10:00:00+05:30'));
  assert.equal(await planAllows(db, 'v1', 'vendorAds', renewed.endsAt - 1000), true);
  assert.equal(await planAllows(db, 'v1', 'vendorAds', renewed.endsAt + 1000), false);
});

test('the admin starts a plan by Vendor ID: full duration from now, the item limit and the vendor told', emulator, async () => {
  const db = await setup();
  await db.collection('vendors').doc('v1').set({vendorCode: 'VEN-NRPM-116-325'}, {merge: true});
  const {planId} = await savePlan(db, good({name: 'Premium', price: 2000, durationMonths: 36}), t0);
  const result = await adminActivatePlan(db, {vendorCode: ' ven-nrpm-116-325 ', planId}, 'admin1', t0);
  assert.equal(result.uid, 'v1');
  assert.equal(result.startsAt, t0);
  assert.equal(result.endsAt, Date.parse('2034-03-05T10:00:00+05:30'));
  const status = (await db.collection('vendorPlanStatus').doc('v1').get()).data();
  assert.equal(status.planName, 'Premium');
  assert.equal(status.itemLimit, 10);
  assert.equal(status.vendorCode, 'VEN-NRPM-116-325');
  assert.equal(status.source, 'admin');
  assert.equal(await vendorItemLimitNow(db, 'v1', {}, t0 + 1000), 10);
  assert.equal(await planAllows(db, 'v1', 'vendorAds', t0 + 1000), true);
  const periods = (await db.collection('vendorPlanPeriods').where('uid', '==', 'v1').get()).docs.map(d => d.data());
  assert.deepEqual(periods.map(p => [p.status, p.source, p.activatedBy]), [['active', 'admin', 'admin1']]);
  assert.equal((await db.collection('vendorNotices').where('vendorId', '==', 'v1').get()).size, 1);
  await assert.rejects(adminActivatePlan(db, {uid: 'v2', planId}, 'admin1', t0), /approved/);
  await assert.rejects(adminActivatePlan(db, {vendorCode: 'VEN-XXXX-000-000', planId}, 'admin1', t0), /No vendor/);
  await assert.rejects(adminActivatePlan(db, {uid: 'v1', planId: 'nope'}, 'admin1', t0), /not found/);
});

test('the admin stops a running plan: it ends now, the items limit and the gate follow, the shop stays', emulator, async () => {
  const db = await setup();
  await saveGates(db, {vendorAds: true}, t0);
  const {planId} = await savePlan(db, good(), t0);
  await adminActivatePlan(db, {uid: 'v1', planId}, 'admin1', t0);
  await adminActivatePlan(db, {uid: 'v1', planId}, 'admin1', t0 + 1000);
  const stopAt = t0 + 86400000;
  await adminStopPlan(db, {uid: 'v1'}, 'admin1', stopAt);
  assert.equal((await db.collection('vendorPlanStatus').doc('v1').get()).data().endsAt.toMillis(), stopAt);
  const periods = (await db.collection('vendorPlanPeriods').where('uid', '==', 'v1').get()).docs.map(d => d.data().status);
  assert.deepEqual(periods, ['stopped', 'stopped'], 'the renewal waiting after it stops too');
  assert.equal(await planAllows(db, 'v1', 'vendorAds', stopAt + 1), false);
  assert.equal(await vendorItemLimitNow(db, 'v1', {}, stopAt + 1), 2);
  assert.equal((await db.collection('shops').doc('v1').get()).data().active, true);
  await assert.rejects(adminStopPlan(db, {uid: 'v1'}, 'admin1', stopAt + 1), /no running plan/);
});

test('a plan bought by payment carries its item limit too', emulator, async () => {
  const db = await setup();
  const {planId} = await savePlan(db, good({itemLimit: 15}), t0);
  const {requestId} = await startPurchase(db, 'v1', {planId}, t0);
  await verified(db, requestId, t0);
  assert.equal((await db.collection('vendorPlanStatus').doc('v1').get()).data().itemLimit, 15);
});

test("the plan kind, extra photos and km go onto the vendor's plan status", emulator, async () => {
  const db = await setup();
  const {planId} = await savePlan(db, good({name: 'Gold', tier: 'gold', extraPhotos: 6, radiusKm: 15}), t0);
  await adminActivatePlan(db, {uid: 'v1', planId}, 'admin1', t0);
  const status = (await db.collection('vendorPlanStatus').doc('v1').get()).data();
  assert.deepEqual([status.tier, status.extraPhotos, status.radiusKm, status.offerBoxes], ['gold', 6, 15, 3]);
});
