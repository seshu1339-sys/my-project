// Staff work (functions/modules/staff-work): what counts as an update, once a day per item, only for linked people, targets, slabs,
// pay, "Paid", the ranking and the ID report. In the emulator where it needs the database.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {R, S} = require('.')._staffWork;

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
const NOW = Date.parse('2026-11-13T10:00:00+05:30');

test('what is an update: a new item, a new price, a new offer; not other changes', () => {
  assert.deepEqual(R.updateOfItem('p1', null, {ownerId: 'v1', price: 40}), {owner: 'v1', key: 'item:p1', type: 'items'});
  assert.deepEqual(R.updateOfItem('p1', {ownerId: 'v1', price: 40}, {ownerId: 'v1', price: 45}), {owner: 'v1', key: 'item:p1', type: 'prices'});
  assert.equal(R.updateOfItem('p1', {ownerId: 'v1', price: 40}, {ownerId: 'v1', price: 40, ratingAvg: 4}), null, 'a rating is not an update');
  assert.equal(R.updateOfItem('p1', {ownerId: 'v1', price: 40}, {ownerId: 'v1'}), null, 'an expired price is not an update');
  assert.equal(R.updateOfItem('p1', null, {name: 'admin item'}), null, 'only vendors\' and providers\' items');
  assert.deepEqual(R.updateOfOffer('o1', null, {vendorId: 'v1', status: 'live', postedAt: 1}), {owner: 'v1', key: 'offer:o1', type: 'offers'});
  assert.equal(R.updateOfOffer('o1', {vendorId: 'v1', status: 'live', postedAt: 1}, {vendorId: 'v1', status: 'live', postedAt: 1, title: 'edit'}), null, 'an edit is not a new offer');
  assert.ok(R.updateOfOffer('o1', {vendorId: 'v1', status: 'live', postedAt: 1}, {vendorId: 'v1', status: 'live', postedAt: 2}), 'run again counts');
  assert.equal(R.updateOfOffer('o1', null, {vendorId: 'v1', status: 'removed'}), null);
});

test('targets: 50 a day unless set, the month is days x daily unless set, own numbers win; pay is the highest slab reached', () => {
  assert.equal(R.daysInMonth('2026-02'), 28);
  const all = R.targetsFor({}, {}, '2026-11');
  assert.deepEqual([all.daily, all.monthly], [50, 1500]);
  const slabs = R.cleanSlabs([{percent: 40, amount: 4000}, {percent: 20, amount: 2000}, {percent: 100, amount: 10000}]);
  assert.deepEqual(slabs.map(s => s.percent), [20, 40, 100]);
  const t = R.targetsFor({dailyTarget: 50, slabs}, {monthlyTarget: 1000}, '2026-11');
  assert.equal(t.monthly, 1000);
  assert.deepEqual(R.payFor(450, t), {updates: 450, percent: 45, slab: {percent: 40, amount: 4000}, amount: 4000, next: {percent: 100, amount: 10000}});
  assert.equal(R.payFor(100, t).amount, 0, 'below the first slab: nothing');
  assert.equal(R.payFor(1200, t).amount, 10000);
  assert.throws(() => R.cleanSlabs([{percent: 20, amount: 1}, {percent: 20, amount: 2}]), /same percent/);
  assert.throws(() => R.cleanSlabs([{percent: 0, amount: 1}]), /percent/);
});

test('a linked vendor\'s updates count for their staff member once per item a day; an unlinked one counts for nobody', emulated, async () => {
  const db = getFirestore();
  const t = `sw${Date.now()}`;
  const [staff, linked, alone] = [`${t}s`, `${t}v`, `${t}w`];
  await db.doc(`fieldStaff/${staff}`).set({status: 'active', staffCode: `STF-TEST-${t.slice(-6)}`, name: 'Ravi', phone: '9000000002'});
  await db.doc(`staffLinks/vendor_${linked}`).set({kind: 'vendor', accountUid: linked, staffUid: staff, code: 'VEN-X', linkedAt: Timestamp.fromMillis(NOW)});
  await db.doc(`vendorApplications/${linked}`).set({name: 'Ramu Kirana', phone: '9000000003', vendorCode: `VEN-T-${t.slice(-6)}`});
  for (const u of [
    {owner: linked, key: 'item:p1', type: 'items'}, {owner: linked, key: 'item:p1', type: 'prices'}, {owner: linked, key: 'item:p1', type: 'prices'},
    {owner: linked, key: 'item:p2', type: 'prices'}, {owner: linked, key: 'offer:o1', type: 'offers'}, {owner: alone, key: 'item:q1', type: 'items'},
  ]) await S.recordUpdate(db, u, NOW);
  const day = (await db.doc(`staffWork/${staff}/days/2026-11-13`).get()).data();
  assert.equal(day.updates, 3, 'p1 once (new item, then two price changes the same day), p2, the offer');
  assert.deepEqual([day.items, day.prices, day.offers], [1, 1, 1]);
  assert.equal((await db.doc(`staffWork/${staff}/months/2026-11`).get()).data().updates, 3);
  assert.equal((await db.doc(`vendorActivity/${alone}/days/2026-11-13`).get()).data().updates, 1, 'the unlinked vendor has their own count');
  // The next day the same item counts again.
  await S.recordUpdate(db, {owner: linked, key: 'item:p1', type: 'prices'}, NOW + 86400000);
  assert.equal((await db.doc(`staffWork/${staff}/months/2026-11`).get()).data().updates, 4);

  // Pay: own monthly target 8, slabs 25% -> 500, 50% -> 1000: 4 of 8 = 50% -> 1000.
  await S.saveConfig(db, {dailyTarget: 50, slabs: [{percent: 25, amount: 500}, {percent: 50, amount: 1000}]});
  await S.saveStaffTargets(db, {staffUid: staff, monthlyTarget: 8});
  const month = await S.staffMonth(db, staff, '2026-11', (await db.doc('staffPayConfig/main').get()).data());
  assert.deepEqual([month.pay.percent, month.pay.amount, month.activeVendors], [50, 1000, 1]);
  const paid = await S.markPaid(db, 'admin1', {staffUid: staff, month: '2026-11', note: 'UPI ref 123'}, NOW);
  assert.deepEqual([paid.status, paid.amount, paid.method, paid.reference], ['paid', 1000, 'manual', 'UPI ref 123']);

  const ranking = await S.ranking(db, {month: '2026-11', now: NOW});
  const me = ranking.rows.find(r => r.staffUid === staff);
  assert.equal(me.linked, 1);
  assert.equal(me.people[0].phone, '9000000003');
  assert.ok(me.rank >= 1);

  const report = await S.idReport(db, (await db.doc(`fieldStaff/${staff}`).get()).data().staffCode, NOW + 86400000);
  assert.equal(report.kind, 'staff');
  assert.equal(report.linked.length, 1);
  assert.equal(report.payouts[0].amount, 1000);
  assert.equal(report.days.reduce((s, d) => s + d.updates, 0), 4);
  await assert.rejects(S.idReport(db, 'XYZ-1'), /Vendor ID/);
  await db.doc('staffPayConfig/main').delete();
});
