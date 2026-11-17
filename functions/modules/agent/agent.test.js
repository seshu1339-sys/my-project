// Agent module (functions/modules/agent) and the admin-set AI key (functions/ai-key.js). No real AI call.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore} = require('firebase-admin/firestore');
const aiKey = require('../../ai-key');
const {saveKey, keyStatus} = require('.')._test;

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
const KEY = 'sk-ant-api03-' + 'b'.repeat(40);

/// A tiny stand-in for Firestore: one document.
const fakeDb = (data, counter = {reads: 0}) => ({collection: () => ({doc: () => ({get: async () => { counter.reads++; return {data: () => data}; }})})});

test('the admin key wins over the secret; a placeholder never counts; the read is cached', async () => {
  aiKey.resetAiKeyCache();
  const before = process.env.ANTHROPIC_API_KEY;
  process.env.ANTHROPIC_API_KEY = 'XX';
  const counter = {reads: 0};
  // (the AI money limit is tested in functions/ai-budget.test.js; here it is open)
  const open = {budget: async () => true};
  assert.equal(await aiKey.loadAiKey(fakeDb({key: 'XX'}, counter), 1000, open), '', 'nothing set: AI is off');
  aiKey.resetAiKeyCache();
  assert.equal(await aiKey.loadAiKey(fakeDb({key: KEY}, counter), 1000, open), KEY);
  assert.equal(await aiKey.loadAiKey(fakeDb({key: 'other'}, counter), 2000, open), KEY, 'cached for 5 minutes');
  assert.equal(counter.reads, 2);
  aiKey.resetAiKeyCache();
  process.env.ANTHROPIC_API_KEY = 'sk-ant-secret-' + 'c'.repeat(30);
  assert.equal(await aiKey.loadAiKey(fakeDb({}), 1000, open), process.env.ANTHROPIC_API_KEY, 'no admin key: the secret');
  assert.equal(await aiKey.loadAiKey(fakeDb({}), 1000, {budget: async () => false}), '', 'over the AI money limit: no key');
  process.env.ANTHROPIC_API_KEY = before;
  aiKey.resetAiKeyCache();
});

test('a broken read never throws: AI just stays off', async () => {
  aiKey.resetAiKeyCache();
  const broken = {collection: () => ({doc: () => ({get: async () => { throw new Error('offline'); }})})};
  assert.equal(await aiKey.loadAiKey(broken), aiKey.currentAiKey());
  aiKey.resetAiKeyCache();
});

test('saving checks the provider and the key shape, and never hands the key back', emulated, async () => {
  const db = getFirestore();
  await assert.rejects(saveKey(db, 'admin1', {provider: 'other', key: KEY}), /Provider/);
  await assert.rejects(saveKey(db, 'admin1', {provider: 'anthropic', key: 'short'}), /API key/);
  await assert.rejects(saveKey(db, 'admin1', {provider: 'anthropic', key: 'abc'.repeat(14)}), /sk-ant-/);
  const status = await saveKey(db, 'admin1', {provider: 'anthropic', key: KEY}, 5000);
  assert.deepEqual({...status, setAt: null}, {provider: 'anthropic', set: true, last4: 'bbbb', setAt: null, source: 'admin'});
  assert.equal(JSON.stringify(status).includes(KEY), false);
  const log = await db.collection('agentLog').where('uid', '==', 'admin1').get();
  assert.ok(log.docs.some(d => d.data().action === 'ai_key_set'));
  const cleared = await saveKey(db, 'admin1', {provider: 'anthropic', key: ''});
  assert.equal(cleared.source === 'admin', false);
  assert.equal((await keyStatus(db)).last4, '');
});
