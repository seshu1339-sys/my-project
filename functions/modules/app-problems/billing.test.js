// The admin billing alert (17 Nov 2026): a budget message under every threshold does nothing; a new threshold this month opens the red
// line and pushes once; the same threshold again (budgets resend their status many times a day) does not. Emulator only.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore} = require('firebase-admin/firestore');
const {onBudgetMessage} = require('./billing');

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};

test('a new threshold alerts once; the same one again does not; under every threshold nothing', emulated, async () => {
  const db = getFirestore();
  await db.collection('adminPushTokens').doc('bt').set({uid: 'a1'});
  const pushes = [];
  const send = async m => { pushes.push(m); return {successCount: 1, responses: [{success: true}]}; };
  const base = {budgetDisplayName: 'LOCAMARKET Rs 1 alert (email only)', costAmount: 1.4, budgetAmount: 1, currencyCode: 'INR', costIntervalStart: '2026-11-01T00:00:00Z'};
  const now = Date.parse('2026-11-17T15:00:00Z');
  assert.equal(await onBudgetMessage(db, {...base, costAmount: 0.2}, now, {send}), false, 'no threshold passed');
  assert.equal(await onBudgetMessage(db, {...base, alertThresholdExceeded: 1}, now, {send}), true);
  assert.equal(await onBudgetMessage(db, {...base, alertThresholdExceeded: 1}, now + 1800000, {send}), false, 'the same status again');
  assert.equal(pushes.length, 1);
  assert.match(pushes[0].notification.title, /₹1\.40: 100% of LOCAMARKET Rs 1 alert/);
  const alert = (await db.collection('healthAlerts').doc('billing~LOCAMARKET Rs 1 alert _email only_').get()).data();
  assert.equal(alert.open, true);
  assert.equal(alert.type, 'billing');
  assert.match(alert.message, /₹1\.40 spent/);
  // next month starts again
  assert.equal(await onBudgetMessage(db, {...base, alertThresholdExceeded: 1, costIntervalStart: '2026-12-01T00:00:00Z'}, now, {send}), true);
  await db.collection('adminPushTokens').doc('bt').delete();
});
