// AI Support module (AI Agent + Health System part 3, 17 Nov 2026): a person's problem report with its screenshot, their own list
// (account or device), the admin's Seen / Solved with a reply pushed in their language, every ticket of a solved problem solved at once,
// and the AI answer only when the admin turned it on and within the daily numbers. Emulator only for the writes; the AI is a fake.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore} = require('firebase-admin/firestore');
const {openTicket, myTickets, answer, ask, solveTicketsOf, deviceKeyOf, problemIdOf, ticketIdOf, WORDS, TICKETS_PER_DAY} = require('.')._test;

/// A stand-in for the US screenshot bucket.
function fakeBucket() {
  const files = new Map();
  return {
    files,
    file: name => ({save: async bytes => files.set(name, bytes)}),
    deleteFiles: async ({prefix}) => { for (const k of [...files.keys()]) if (k.startsWith(prefix)) files.delete(k); },
  };
}
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
  const bucket = fakeBucket();
  const {id} = await openTicket(db, req, now, {bucket});
  assert.equal(id, ticketIdOf('customer~android~api~p1'), 'one ticket per problem');
  const t = (await db.collection('supportTickets').doc(id).get()).data();
  assert.equal(t.status, 'sent');
  assert.equal(t.text, 'Order button not working, call <number>');
  assert.equal(t.phone, '9000000002');
  assert.equal(t.lang, 'te');
  assert.equal(t.shots, 1);
  assert.ok(bucket.files.has(t.shotPaths[0]), 'the screenshot is in the US bucket');
  assert.match(t.shotPaths[0], new RegExp(`^support/${id}/`));
  const mine = await myTickets(db, {auth: null, rawRequest: {}, data: {deviceId}});
  assert.equal(mine.tickets[0].id, id, 'the same device sees it without signing in');
  assert.equal((await myTickets(db, {auth: null, rawRequest: {}, data: {deviceId: 'someone-else'}})).tickets.length, 0);
  const pushes = [];
  const send = async m => { pushes.push(m); return {successCount: 1}; };
  await answer(db, 'admin1', {id, status: 'seen', reply: 'We are fixing the order button.'}, now + 1000, {send, bucket});
  let after = (await db.collection('supportTickets').doc(id).get()).data();
  assert.equal(after.status, 'seen');
  assert.equal(after.reply, 'We are fixing the order button.');
  assert.match(pushes[0].notification.body, /LocaMarket టీమ్/);
  await assert.rejects(answer(db, 'admin1', {id, status: 'sent'}, now), /seen or solved/);
  // the fix went live: every open ticket of the problem is solved and each person is told
  const n = await solveTicketsOf(db, 'customer~android~api~p1', now + 2000, {send, bucket});
  assert.equal(n, 1);
  after = (await db.collection('supportTickets').doc(id).get()).data();
  assert.equal(after.status, 'solved');
  assert.equal(pushes.at(-1).notification.body, WORDS.solved.te);
  assert.equal(bucket.files.size, 0, 'the screenshot goes when solved');
  assert.equal(after.shots, 0);
  // the daily cap per device
  const capReq = {...req, data: {...req.data, deviceId: `cap-${now}`, screenshot: ''}};
  for (let i = 0; i < TICKETS_PER_DAY; i++) await openTicket(db, capReq, now, {bucket});
  await assert.rejects(openTicket(db, capReq, now, {bucket}), /5 problems today/);
});

test('the same problem from many people is ONE ticket that counts up; one answer reaches everyone; 3 screenshots at most', emulated, async () => {
  const db = getFirestore();
  const bucket = fakeBucket();
  const now = Date.parse('2026-11-18T09:00:00Z');
  const problemId = `vendor~android~upload~many-${now}`;
  for (const u of ['vm1', 'vm2']) await db.collection('users').doc(u).collection('pushTokens').doc(`tok-${u}`).set({at: 1});
  const send = (uid, lang, text, i) => openTicket(db, {
    auth: uid ? {uid, token: {role: 'vendor'}} : null, rawRequest: {headers: {}},
    data: {app: 'vendor', platform: 'android', deviceId: `m-${i}-${now}`, problemId, problemKind: 'upload', side: 'our', message: 'Photo upload failed', text, screenshot: JPEG, lang, auto: !text},
  }, now + i, {bucket});
  const ids = new Set();
  ids.add((await send('vm1', 'te', '', 1)).id);
  ids.add((await send('vm2', 'en', 'My photo does not go', 2)).id);
  ids.add((await send(null, 'hi', '', 3)).id);
  ids.add((await send('vm1', 'te', 'Still failing', 4)).id);
  assert.equal(ids.size, 1, 'no ticket per person');
  const [id] = ids;
  const t = (await db.collection('supportTickets').doc(id).get()).data();
  assert.equal(t.count, 4);
  assert.equal(t.users, 3);
  assert.equal(t.members.filter(m => m.startsWith('u_')).length, 2, 'two accounts and the not-signed-in device');
  assert.deepEqual(t.notes.map(n => n.text), ['My photo does not go', 'Still failing']);
  assert.equal(t.shots, 3, 'at most 3 screenshots for one problem');
  assert.equal(bucket.files.size, 3);
  // Each sees it in their own list, with only their own words.
  const mine = await myTickets(db, {auth: {uid: 'vm2'}, rawRequest: {}, data: {deviceId: 'other'}});
  assert.equal(mine.tickets[0].id, id);
  assert.equal(mine.tickets[0].text, 'My photo does not go');
  // "Tell us more" only by someone it belongs to.
  await assert.rejects(openTicket(db, {auth: {uid: 'stranger'}, rawRequest: {}, data: {app: 'vendor', deviceId: 'x9', ticketId: id, text: 'hello'}}, now + 9, {bucket}), /not there any more/);
  // One answer: a push to every signed-in person in their language.
  const pushes = [];
  await answer(db, 'admin1', {id, status: 'solved', reply: ''}, now + 10, {send: async m => { pushes.push(m); return {successCount: 1}; }, bucket});
  assert.equal(pushes.length, 2);
  assert.deepEqual(pushes.map(m => m.notification.body).sort(), [WORDS.solved.en, WORDS.solved.te].sort());
  assert.equal(bucket.files.size, 0);
  // It comes back: the same ticket opens again.
  await send('vm2', 'en', '', 11);
  assert.equal((await db.collection('supportTickets').doc(id).get()).data().status, 'sent');
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
