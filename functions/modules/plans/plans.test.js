const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {Timestamp} = require('firebase-admin/firestore');
const {validatePlan, validateGates, addMonths, planPeriod} = require('./rules');
const {savePlan, saveGates, startPurchase, activatePlan} = require('./store');
const {planAllows, requirePlan} = require('../../plan-gate');

const good = (extra = {}) => ({name: '1 Year', price: 4999, durationMonths: 12, ...extra});

test('what the admin may save as a plan is checked', () => {
  assert.deepEqual(validatePlan(good({name: '  Gold   plan '})), {name: 'Gold plan', price: 4999, durationMonths: 12, active: true});
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
