// The AI money limit (owner, free-limit plan 17 Nov 2026): every AI call's real cost is added up; at ₹90 a month (or ₹3 a day) every AI
// feature gets "no key" and falls back. The admin may only lower the limits. Emulator only for the Firestore parts.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore} = require('firebase-admin/firestore');
const {costInr, limitsOf, recordSpend, budgetOk, monthKey, dayKey, MONTH_MAX_INR} = require('./ai-budget');
const {loadAiKey, resetAiKeyCache} = require('./ai-key');

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};

test('the cost of a call in rupees, from its tokens and the model price', () => {
  // Haiku 5.5: 3,000 input + 400 output tokens = $0.0005 = ₹0.044 at ₹88
  assert.equal(costInr('claude-haiku-5-5', {input_tokens: 3000, output_tokens: 400}), 0.044);
  // Sonnet 5.5: 1M input = $2 = ₹176
  assert.equal(costInr('claude-sonnet-5-5', {input_tokens: 1e6}), 176);
  // an unknown model is priced as the dearest, never under-counted
  assert.equal(costInr('some-new-model', {output_tokens: 1e6}), 880);
  assert.equal(costInr('claude-haiku-5-5', {}), 0);
});

test('the admin may lower the limits, never raise them past ₹90 a month / ₹10 a day', () => {
  assert.deepEqual(limitsOf({}), {monthInr: 90, dayInr: 3, usdToInr: 88});
  assert.equal(limitsOf({aiMonthlyInr: 50}).monthInr, 50);
  assert.equal(limitsOf({aiMonthlyInr: 500}).monthInr, MONTH_MAX_INR);
  assert.equal(limitsOf({aiDailyInr: 50}).dayInr, 3);
  assert.equal(limitsOf({aiMonthlyInr: 0}).monthInr, 0, 'zero turns AI off');
});

test('the spend is added up; at the day or month limit every AI feature gets "no key"', emulated, async () => {
  const db = getFirestore();
  const now = Date.parse('2026-12-05T06:00:00Z');
  await db.collection('settings').doc('agent').set({aiMonthlyInr: 90, aiDailyInr: 3}, {merge: true});
  await db.collection('_private').doc('aiKey').set({provider: 'anthropic', key: 'sk-ant-' + 'abc'.repeat(14), last4: 'cabc'});
  for (const id of [monthKey(now), dayKey(now)]) await db.collection('aiSpend').doc(id).delete();
  resetAiKeyCache();
  assert.ok(await budgetOk(db, now));
  assert.ok((await loadAiKey(db, now)).startsWith('sk-ant-'), 'under the limit: the key is given');
  // 100,000 input + 46,000 output tokens on Haiku = $0.033 = ₹2.90 today: still under ₹3
  assert.equal(await recordSpend(db, 'claude-haiku-5-5', {input_tokens: 100000, output_tokens: 46000}, now), 2.904);
  assert.ok(await budgetOk(db, now));
  await recordSpend(db, 'claude-haiku-5-5', {input_tokens: 1e6}, now); // +₹8.80
  assert.equal(await budgetOk(db, now), false, "today's ₹3 used");
  assert.equal(await loadAiKey(db, now), '', 'over the limit: no key, so every feature falls back');
  const month = (await db.collection('aiSpend').doc(monthKey(now)).get()).data();
  assert.equal(month.calls, 2);
  assert.ok(month.inr > 3);
  // the next day is open again, until the month reaches ₹90
  const tomorrow = now + 86400000;
  assert.ok(await budgetOk(db, tomorrow));
  await db.collection('aiSpend').doc(monthKey(now)).set({inr: 90}, {merge: true});
  assert.equal(await budgetOk(db, tomorrow), false, 'the month is at ₹90: AI stops until the 1st');
  resetAiKeyCache();
  await db.collection('_private').doc('aiKey').delete();
});
