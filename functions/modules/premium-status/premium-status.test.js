const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {syncStatus, expireStatuses} = require('./store');

const NOW = Date.parse('2026-11-02T10:00:00+05:30');
const plan = time => ({endsAt: Timestamp.fromMillis(time)});
const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
let seq = 0;
const newUid = () => `premium-${Date.now()}-${++seq}`;
const read = (db, uid) => db.doc(`vendorPremium/${uid}`).get().then(doc => doc.data());

test('a running plan makes a vendor Premium, an ended or missing one does not', emulated, async () => {
  const db = getFirestore();
  const uid = newUid();
  await syncStatus(db, uid, plan(NOW + 1000), NOW);
  assert.equal((await read(db, uid)).active, true);
  await syncStatus(db, uid, plan(NOW), NOW);
  assert.equal((await read(db, uid)).active, false);
  await syncStatus(db, uid, undefined, NOW);
  assert.equal((await read(db, uid)).active, false);
});

test('Premium ends when the plan ends, and comes back when the vendor pays again', emulated, async () => {
  const db = getFirestore();
  const uid = newUid();
  await syncStatus(db, uid, plan(NOW + 1000), NOW);
  assert.ok(await expireStatuses(db, NOW + 999) >= 0);
  assert.equal((await read(db, uid)).active, true, 'not ended yet');
  assert.ok(await expireStatuses(db, NOW + 1000) >= 1);
  assert.equal((await read(db, uid)).active, false);
  await syncStatus(db, uid, plan(NOW + 5000), NOW + 2000);
  assert.equal((await read(db, uid)).active, true);
});
