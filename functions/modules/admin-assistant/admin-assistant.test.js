// Admin AI assistant (functions/modules/admin-assistant), the photo search allowance (functions/image-search.js) and the one model config
// (functions/ai-models.js). No real Anthropic call: a fake client records the request.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {AI_MODELS, keyIsSet} = require('../../ai-models');
const {answerQuestion, adminFacts, adminAiLimit, DEFAULT_ADMIN_AI_PER_DAY} = require('.')._test;
const photo = require('../../image-search')._test;

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};

test('one place names the models: Haiku 5.5 for chat and photo search, Sonnet 5.5 for the admin', () => {
  assert.deepEqual({...AI_MODELS}, {chat: 'claude-haiku-5-5', photoSearch: 'claude-haiku-5-5', admin: 'claude-sonnet-5-5'});
});

test('a placeholder key never reaches Anthropic', () => {
  for (const placeholder of [undefined, '', 'XX', 'xx', 'XXXXXXXXXXXXXXXXXXXXXXXXX', 'short']) assert.equal(keyIsSet(placeholder), false, String(placeholder));
  assert.equal(keyIsSet('sk-ant-api03-' + 'a'.repeat(40)), true);
});

test('the daily limits are the admin numbers, with 10 photo searches and 50 questions when not set', () => {
  assert.equal(photo.photoSearchLimit(undefined), 10);
  assert.equal(photo.photoSearchLimit({photoSearchesPerDay: 25}), 25);
  assert.equal(photo.photoSearchLimit({photoSearchesPerDay: 'abc'}), 10);
  assert.equal(photo.photoSearchLimit({photoSearchesPerDay: 0}), 10);
  assert.equal(adminAiLimit({}), DEFAULT_ADMIN_AI_PER_DAY);
  assert.equal(adminAiLimit({adminAiPerDay: 5}), 5);
});

test('a person gets the day\'s photo searches, then "try again tomorrow"', emulated, async () => {
  const db = getFirestore();
  const uid = `photo${Date.now()}`;
  await db.doc('settings/business').set({photoSearchesPerDay: 2}, {merge: true});
  try {
    const now = Date.parse('2026-11-13T10:00:00+05:30');
    assert.equal(await photo.takePhotoSearch(db, uid, now), 2);
    await photo.takePhotoSearch(db, uid, now);
    await assert.rejects(photo.takePhotoSearch(db, uid, now), error => error.code === 'resource-exhausted' && /try again tomorrow/.test(error.message));
    assert.equal(await photo.takePhotoSearch(db, uid, now + 24 * 3600000), 2, 'a new day, a new allowance');
  } finally {
    await db.doc('settings/business').set({photoSearchesPerDay: FieldValue.delete()}, {merge: true});
  }
});

test('the assistant answers from the counts with Sonnet 5.5 and stops at the daily limit without calling Anthropic', emulated, async () => {
  const db = getFirestore();
  const uid = `admin${Date.now()}`;
  const calls = [];
  const fake = () => ({beta: {messages: {create: async request => {
    calls.push(request);
    return {model: request.model, stop_reason: 'end_turn', usage: {input_tokens: 10, output_tokens: 5}, content: [{type: 'text', text: 'There are 2 vendors waiting.'}]};
  }}}});
  await db.doc('settings/business').set({adminAiPerDay: 1}, {merge: true});
  try {
    const result = await answerQuestion(db, fake, uid, 'How many vendors are waiting?');
    assert.equal(result.answer, 'There are 2 vendors waiting.');
    assert.equal(calls.length, 1);
    assert.equal(calls[0].model, 'claude-sonnet-5-5');
    assert.deepEqual(calls[0].output_config, {effort: 'low'});
    assert.equal(calls[0].fallbacks, 'default');
    assert.match(calls[0].messages[0].content, /<facts>[\s\S]*vendors[\s\S]*<\/facts>[\s\S]*How many vendors are waiting\?/);
    await assert.rejects(answerQuestion(db, fake, uid, 'And now?'), error => error.code === 'resource-exhausted' && /try again tomorrow/i.test(error.message));
    assert.equal(calls.length, 1, 'past the limit Anthropic is not called');
    await assert.rejects(answerQuestion(db, fake, `${uid}b`, '   '), /question/);
  } finally {
    await db.doc('settings/business').set({adminAiPerDay: FieldValue.delete()}, {merge: true});
  }
});

test('the counts are read-only numbers and a missing collection is never a failure', emulated, async () => {
  const facts = await adminFacts(getFirestore());
  assert.equal(typeof facts.asOf, 'string');
  for (const value of [facts.shops, facts.products, facts.vendors.approved, facts.posts.vendorOffersLive]) assert.ok(value === null || Number.isInteger(value));
});
