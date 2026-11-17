// AI Support module (AI Agent + Health System part 3, 17 Nov 2026): a person's problem report with its screenshot, their own list
// (account or device), the admin's Seen / Solved with a reply pushed in their language, every ticket of a solved problem solved at once,
// and the AI answer only when the admin turned it on and within the daily numbers. Emulator only for the writes; the AI is a fake.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore} = require('firebase-admin/firestore');
const {openTicket, myTickets, answer, ask, solveTicketsOf, deviceKeyOf, problemIdOf, WORDS, TICKETS_PER_DAY} = require('.')._test;
const {createHash} = require('node:crypto');
// The id functions/modules/app-problems gives a problem (index.js problemId), written out here: modules never require each other.
const problemIdOfProblems = (app, platform, kind, message) => `${app}~${platform}~${kind}~${createHash('sha256').update(`${app}|${kind}|${message}`).digest('hex').slice(0, 16)}`;

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 16, 74, 70, 73, 70]).toString('base64');

test('a ticket finds its problem with the same id as the problem records', () => {
  assert.equal(problemIdOf('vendor', 'android', 'tap', 'No answer to "Save" after 3 taps'), problemIdOfProblems('vendor', 'android', 'tap', 'No answer to "Save" after 3 taps'));
  assert.equal(problemIdOf('vendor', 'android', '', 'x'), '');
});

test('the words the person reads exist in English, Telugu and Hindi; a device has one key', () => {
  for (const w of Object.values(WORDS)) for (const l of ['en', 'te', 'hi']) assert.ok(w[l]);
  assert.equal(deviceKeyOf('abc'), deviceKeyOf('abc'));
  assert.notEqual(deviceKeyOf('abc'), deviceKeyOf('abd'));
});

test('a report is kept with the screenshot; the person sees their own; the admin answers; solved tells them in their language', emulated, async () => {
  const db = getFirestore();
  const now = Date.parse('2026-11-17T12:00:00Z');
  const deviceId = `sup-${now}`;
  await db.collection('users').doc('cu1').set({phone: '9000000002'});
  await db.collection('users').doc('cu1').collection('pushTokens').doc('tokA').set({at: 1});
  const req = {auth: {uid: 'cu1', token: {role: 'user'}}, rawRequest: {headers: {}}, data: {
    app: 'customer', platform: 'android', deviceId, version: '1.0.13+23', problemId: 'customer~android~api~p1', problemKind: 'api', cause: 'server_error',
    side: 'our', message: 'placeOrder: internal', screen: 'cart', option: 'Place order', text: 'Order button not working, call 9876543210', screenshot: JPEG, lang: 'te', auto: false,
  }};
  const {id} = await openTicket(db, req, now);
  const t = (await db.collection('supportTickets').doc(id).get()).data();
  assert.equal(t.status, 'sent');
  assert.equal(t.text, 'Order button not working, call <number>');
  assert.equal(t.phone, '9000000002');
  assert.equal(t.lang, 'te');
  assert.equal((await db.collection('supportShots').doc(id).get()).data().data, JPEG);
  const mine = await myTickets(db, {auth: null, rawRequest: {}, data: {deviceId}});
  assert.equal(mine.tickets[0].id, id, 'the same device sees it without signing in');
  assert.equal((await myTickets(db, {auth: null, rawRequest: {}, data: {deviceId: 'someone-else'}})).tickets.length, 0);
  const pushes = [];
  const send = async m => { pushes.push(m); return {successCount: 1}; };
  await answer(db, 'admin1', {id, status: 'seen', reply: 'We are fixing the order button.'}, now + 1000, {send});
  let after = (await db.collection('supportTickets').doc(id).get()).data();
  assert.equal(after.status, 'seen');
  assert.equal(after.reply, 'We are fixing the order button.');
  assert.match(pushes[0].notification.body, /LocaMarket టీమ్/);
  await assert.rejects(answer(db, 'admin1', {id, status: 'sent'}, now), /seen or solved/);
  // the fix went live: every open ticket of the problem is solved and each person is told
  const n = await solveTicketsOf(db, 'customer~android~api~p1', now + 2000, {send});
  assert.equal(n, 1);
  after = (await db.collection('supportTickets').doc(id).get()).data();
  assert.equal(after.status, 'solved');
  assert.equal(pushes.at(-1).notification.body, WORDS.solved.te);
  assert.equal((await db.collection('supportShots').doc(id).get()).exists, false, 'the screenshot goes when solved');
  // the daily cap per device
  const capReq = {...req, data: {...req.data, deviceId: `cap-${now}`, screenshot: ''}};
  for (let i = 0; i < TICKETS_PER_DAY; i++) await openTicket(db, capReq, now);
  await assert.rejects(openTicket(db, capReq, now), /5 problems today/);
});

test('AI answers only when the admin turned it on, within the daily limit; the call is logged', emulated, async () => {
  const db = getFirestore();
  const now = Date.parse('2026-11-17T13:00:00Z');
  const fake = () => ({messages: {create: async p => ({content: [{type: 'text', text: `1. ${p.system.includes('Telugu') ? 'తెలుగు' : 'en'}`}], usage: {input_tokens: 10, output_tokens: 5}, stop_reason: 'end_turn'})}});
  const req = q => ({auth: null, rawRequest: {}, data: {question: q, lang: 'te', deviceId: `ai-${now}`, context: {app: 'vendor', screen: 'add_item', message: 'x', cause: 'no_response'}}});
  await db.collection('settings').doc('support').set({aiOn: false});
  assert.deepEqual(await ask(db, req('why?'), now, fake), {text: '', off: true});
  await db.collection('settings').doc('support').set({aiOn: true, aiDailyLimit: 1});
  await db.collection('_private').doc('aiKey').set({provider: 'anthropic', key: 'sk-ant-' + 'abc'.repeat(14), last4: 'xxxx'});
  require('../../ai-key').resetAiKeyCache?.();
  const first = await ask(db, req('why?'), now, fake);
  assert.equal(first.text, '1. తెలుగు');
  assert.deepEqual(await ask(db, {...req('again?'), data: {...req('again?').data, deviceId: `ai2-${now}`}}, now, fake), {text: '', limit: true}, 'the daily limit for everyone');
  const logged = await db.collection('aiCallLog').where('feature', '==', 'support_ai').get();
  assert.ok(logged.size >= 1);
});
