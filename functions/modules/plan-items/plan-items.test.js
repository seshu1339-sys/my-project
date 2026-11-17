const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {hideAfterPlan, showAfterRenewal} = require('./store');

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};

test('plan ends: the first 2 items stay live, the rest are hidden; renewal shows them again; nothing is deleted', emulated, async () => {
  const db = getFirestore();
  const uid = `pi${Date.now()}`;
  for (let n = 1; n <= 5; n++) await db.doc(`products/${uid}-${n}`).set({ownerId: uid, name: `Item ${n}`, active: true, createdAt: Timestamp.fromMillis(1000 * n)});
  await db.doc(`products/${uid}-6`).set({ownerId: uid, name: 'Hidden by admin', active: false, createdAt: Timestamp.fromMillis(6000)});
  assert.equal(await hideAfterPlan(db, uid, 2), 3, 'items 3, 4, 5');
  const state = async n => (await db.doc(`products/${uid}-${n}`).get()).data();
  assert.equal((await state(1)).active, true);
  assert.equal((await state(2)).active, true);
  for (const n of [3, 4, 5]) assert.deepEqual([(await state(n)).active, (await state(n)).hiddenByPlan], [false, true]);
  assert.equal((await state(6)).hiddenByPlan, undefined, 'the admin\'s own hide is left alone');
  assert.equal(await showAfterRenewal(db, uid), 3);
  for (const n of [3, 4, 5]) assert.deepEqual([(await state(n)).active, (await state(n)).hiddenByPlan], [true, undefined]);
  assert.equal((await state(6)).active, false, 'still hidden by the admin');
});
