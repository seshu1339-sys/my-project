// Health module (owner spec F + H): the checks never touch real data, a failure gets a "since" and is explained only with AI explain on,
// server errors are grouped. No real network, AI or Storage: fakes.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore} = require('firebase-admin/firestore');
const {buildChecks, runChecks, adProblems, siteUrls, CALLABLES} = require('./checks');
const {runHealth, serverErrors} = require('.')._test;
const aiKey = require('../../ai-key');

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};

const response = (status, body = '', url = '') => ({status, url, text: async () => body});
/// A fake fetch: sites answer with the app page, main.dart.js exists, functions say "sign in first" unless [broken] names them.
const fakeFetch = (broken = new Set()) => async url => {
  for (const b of broken) if (url.includes(b)) return response(b.includes('.web.app') ? 503 : 500);
  if (url.includes('cloudfunctions.net')) return response(401, '{"error":{"status":"UNAUTHENTICATED"}}');
  if (url.endsWith('main.dart.js')) return response(200);
  return response(200, '<script src="flutter_bootstrap.js"></script>', url);
};
const fakeBucket = () => {
  const files = new Map();
  return {files, file: name => ({save: async b => files.set(name, b), exists: async () => [files.has(name)], delete: async () => files.delete(name)})};
};

test('the default sites are the four Firebase sites and locamarket.in; the admin may set others', () => {
  assert.deepEqual(siteUrls('p').map(s => s.url), ['https://p.web.app/', 'https://p-admin.web.app/', 'https://p-vendor.web.app/', 'https://p-field.web.app/', 'https://locamarket.in/']);
  assert.deepEqual(siteUrls('p', {urls: 'https://a.in/\nnot-a-url https://b.in/'}).map(s => s.url), ['https://a.in/', 'https://b.in/']);
  assert.ok(CALLABLES.length >= 15);
});

test('a live ad with no photo and no text, a bad place or a bad radius is reported; ended and pending ads are not checked', () => {
  const now = Date.parse('2026-11-17T10:00:00Z');
  assert.deepEqual(adProblems('ads', 'a', {title: 'Sale', latitude: 17.6, longitude: 82.6, radiusKm: 10}, now), []);
  assert.equal(adProblems('ads', 'b', {}, now).length, 1);
  assert.match(adProblems('ads', 'c', {title: 'x', latitude: 'abc', longitude: 82}, now)[0], /latitude/);
  assert.match(adProblems('ads', 'd', {title: 'x', radiusKm: -1}, now)[0], /radius/);
  assert.deepEqual(adProblems('ads', 'e', {endsAt: '2026-11-01T00:00:00Z'}, now), [], 'ended');
  assert.deepEqual(adProblems('ads', 'f', {status: 'pending'}, now), []);
});

test('server errors are grouped by function and message; unreadable logs are a note, not a failure', async () => {
  const entries = [
    {resource: {labels: {service_name: 'placeorder'}}, textPayload: 'TypeError: x is undefined\n at ...', timestamp: '2026-11-17T01:00:00Z'},
    {resource: {labels: {service_name: 'placeorder'}}, textPayload: 'TypeError: x is undefined', timestamp: '2026-11-17T02:00:00Z'},
    {resource: {labels: {service_name: 'trackusage'}}, jsonPayload: {message: 'Quota 1234567 exceeded'}, timestamp: '2026-11-17T03:00:00Z'},
  ];
  const r = await serverErrors(async () => entries);
  assert.equal(r.ok, true);
  assert.deepEqual(r.list[0], {service: 'placeorder', message: 'TypeError: x is undefined', count: 2, last: '2026-11-17T02:00:00Z'});
  assert.equal(r.list[1].message, 'Quota <n> exceeded');
  const denied = await serverErrors(async () => { throw Error('PERMISSION_DENIED'); });
  assert.equal(denied.ok, false);
  assert.match(denied.note, /could not be read/);
});

test('checks run with fakes: all pass; a broken site and a missing function fail with the reason', emulated, async () => {
  const db = getFirestore();
  const bucket = fakeBucket();
  await db.collection('settings').doc('business').set({name: 'Local Market'}, {merge: true});
  const ok = await runChecks(buildChecks({db, bucket, fetch: fakeFetch(), project: 'p', runId: 'r1'}));
  assert.deepEqual(ok.filter(r => !r.ok).map(r => `${r.id}: ${r.error}`), []);
  assert.equal(bucket.files.size, 0, 'the test photo was deleted');
  assert.equal((await db.collection('_healthTest').doc('r1').get()).exists, false, 'the test record was deleted');
  const bad = await runChecks(buildChecks({db, bucket, fetch: fakeFetch(new Set(['p-vendor.web.app', 'placeOrder'])), project: 'p', runId: 'r2'}));
  const failed = Object.fromEntries(bad.filter(r => !r.ok).map(r => [r.id, r.error]));
  assert.deepEqual(Object.keys(failed).sort(), ['api:placeOrder', 'site:https://p-vendor.web.app/']);
  assert.equal(failed['api:placeOrder'], 'HTTP 500');
});

test('a run keeps the status with "since", explains only new failures and only with AI explain on', emulated, async () => {
  const db = getFirestore();
  await db.collection('healthStatus').doc('current').delete();
  const calls = [];
  const client = () => ({messages: {create: async req => { calls.push(req); return {content: [{type: 'text', text: 'కారణం: ...'}], usage: {}, stop_reason: 'end_turn'}; }}});
  const failing = [{id: 'x', name: 'X works', group: 'G', registryIds: ['page.ads'], run: async () => { throw Error('boom'); }}, {id: 'y', name: 'Y', group: 'G', run: async () => {}}];
  const logs = async () => [];
  await db.collection('settings').doc('agent').set({aiExplain: 'false'});
  const first = await runHealth(db, {checks: failing, readLogs: logs, client, now: 1000});
  assert.deepEqual(first.newlyFailed, ['x']);
  let status = (await db.collection('healthStatus').doc('current').get()).data();
  assert.equal(status.failed, 1);
  assert.equal(status.checks.x.since.toMillis(), 1000);
  assert.deepEqual(status.checks.x.registryIds, ['page.ads']);
  assert.equal(calls.length, 0, 'AI explain is off: no AI call');

  await db.collection('settings').doc('agent').set({aiExplain: 'true'});
  const before = process.env.ANTHROPIC_API_KEY;
  process.env.ANTHROPIC_API_KEY = 'sk-ant-test-' + 'k'.repeat(30);
  aiKey.resetAiKeyCache();
  await runHealth(db, {checks: failing, readLogs: logs, client, now: 2000});
  status = (await db.collection('healthStatus').doc('current').get()).data();
  assert.equal(status.checks.x.since.toMillis(), 1000, 'still failing since the first run');
  assert.equal(calls.length, 0, 'an old failure is not explained again by the run');
  await db.collection('healthStatus').doc('current').delete();
  await runHealth(db, {checks: failing, readLogs: logs, client, now: 3000});
  assert.equal(calls.length, 1, 'a new failure with AI explain on is explained once');
  status = (await db.collection('healthStatus').doc('current').get()).data();
  assert.match(status.checks.x.explain, /కారణం/);
  process.env.ANTHROPIC_API_KEY = before;
  aiKey.resetAiKeyCache();
  await db.collection('settings').doc('agent').delete();
});
