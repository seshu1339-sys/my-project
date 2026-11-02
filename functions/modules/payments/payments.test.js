const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const R = require('./rules');
const {readAnswer, FORMAT} = require('./extract');
const {saveConfig, testSms, ingestSms, submitScreenshot, closeChecks, reviewPayment, readConfig} = require('./store');

const NOW = Date.parse('2026-11-02T10:00:00+05:30');
const HOUR = 3600000;

// Made up for these tests only: the real sender and SMS wording are still XX until the bank account opens.
const FILLED = {
  accountName: 'Local Market', accountNumber: '50100000000000', ifsc: 'HDFC0000001', upiId: 'localmarket@hdfcbank',
  smsSenders: ['HDFCBK'],
  smsPatterns: [{credit: 'credited', amount: 'Rs\\.?\\s*([0-9,]+(?:\\.[0-9]{1,2})?)', paymentId: 'UPI Ref\\s+([A-Za-z0-9]+)'}],
  windowHours: 3, dailyScreenshots: 5,
};
const SMS = (id = '123456789012', amount = '4,999.00') => `Rs ${amount} credited to a/c XX1234 on 02-11-26. UPI Ref ${id}`;

test('the defaults are placeholders, and they keep payments closed', () => {
  assert.equal(R.configReady(R.DEFAULT_CONFIG), false);
  assert.equal(R.parseSms(SMS(), R.DEFAULT_CONFIG), null);
  assert.equal(R.senderAllowed('AD-HDFCBK', R.DEFAULT_CONFIG), false);
  assert.equal(R.publicDetails(R.DEFAULT_CONFIG).ready, false);
  assert.ok(Object.values({...R.DEFAULT_CONFIG.smsPatterns[0], s: R.DEFAULT_CONFIG.smsSenders[0], a: R.DEFAULT_CONFIG.accountNumber}).every(v => v.startsWith('XX')));
});

test('one placeholder left anywhere keeps payments closed', () => {
  assert.equal(R.configReady(FILLED), true);
  assert.equal(R.configReady({...FILLED, ifsc: 'XX-IFSC'}), false);
  assert.equal(R.configReady({...FILLED, smsSenders: ['HDFCBK', 'XX-SENDER-ID']}), false);
  assert.equal(R.configReady({...FILLED, smsPatterns: [{...FILLED.smsPatterns[0], credit: 'XX-CREDIT-WORDS'}]}), false);
  assert.equal(R.configReady({...FILLED, smsPatterns: []}), false);
});

test('saving: placeholders pass, broken patterns do not', () => {
  assert.equal(R.validateConfig({...R.DEFAULT_CONFIG}).ifsc, 'XX-IFSC');
  assert.throws(() => R.validateConfig({...FILLED, smsPatterns: [{...FILLED.smsPatterns[0], amount: '('}]}), /amount pattern/);
  assert.throws(() => R.validateConfig({...FILLED, smsSenders: []}), /sender/);
  assert.throws(() => R.validateConfig({...FILLED, windowHours: 0}), /window/);
  assert.throws(() => R.validateConfig({...FILLED, dailyScreenshots: 0}), /limit/);
});

test('vendors get bank details only, never patterns or senders', () => {
  assert.deepEqual(Object.keys(R.publicDetails(FILLED)).sort(), ['accountName', 'accountNumber', 'ifsc', 'ready', 'upiId']);
});

test('a credit SMS gives its id and amount; anything else gives nothing', () => {
  assert.deepEqual(R.parseSms(SMS(), FILLED), {paymentId: '123456789012', amount: 4999});
  assert.equal(R.parseSms('Rs 4999 debited from a/c. UPI Ref 123456789012', FILLED), null, 'a debit is not a payment to us');
  assert.equal(R.parseSms('Your OTP is 123456', FILLED), null);
  assert.equal(R.parseSms('Rs 10 credited. Ref missing', FILLED), null);
});

test('the bank sender is recognised with any operator prefix', () => {
  assert.equal(R.senderAllowed('AD-HDFCBK-S', FILLED), true);
  assert.equal(R.senderAllowed('vm-hdfcbk', FILLED), true);
  assert.equal(R.senderAllowed('AD-AMAZON', FILLED), false);
  assert.equal(R.senderAllowed('', FILLED), false);
});

test('the endpoint token is compared whole', () => {
  assert.equal(R.tokenMatches('Bearer secret', 'secret'), true);
  assert.equal(R.tokenMatches('Bearer wrong', 'secret'), false);
  assert.equal(R.tokenMatches('secret', 'secret'), false);
  assert.equal(R.tokenMatches('Bearer ', ''), false, 'an empty secret never opens it');
});

const request = (extra = {}) => ({amount: 4999, createdAt: Timestamp.fromMillis(NOW - HOUR), ...extra});
const claim = (extra = {}) => ({readable: true, paymentId: '123456789012', amount: 4999, date: '2026-11-02', time: '09:30', ...extra});

test('a screenshot goes on only when it is clean and the amount is the price', () => {
  assert.equal(R.claimProblem(claim(), request(), 3, NOW), '');
  assert.match(R.claimProblem(null, request(), 3, NOW), /could not be read/);
  assert.match(R.claimProblem(claim({readable: false}), request(), 3, NOW), /could not be read/);
  assert.match(R.claimProblem(claim({paymentId: 'x'}), request(), 3, NOW), /could not be read/);
  assert.match(R.claimProblem(claim({amount: 4000}), request(), 3, NOW), /differs/);
  assert.match(R.claimProblem(claim({date: '2/11/26'}), request(), 3, NOW), /date or time/);
  assert.match(R.claimProblem(claim({date: '2026-11-03'}), request(), 3, NOW), /future/);
  assert.match(R.claimProblem(claim({date: '2026-11-01'}), request(), 3, NOW), /before this plan/);
});

test('an SMS confirms only the same amount, close in time', () => {
  const paid = NOW - HOUR;
  assert.equal(R.smsConfirms({amount: 4999, smsAt: paid + HOUR}, paid, 4999, 3), true);
  assert.equal(R.smsConfirms({amount: 4999, smsAt: paid - 2 * HOUR}, paid, 4999, 3), true, 'an SMS before the upload counts');
  assert.equal(R.smsConfirms({amount: 4998, smsAt: paid}, paid, 4999, 3), false);
  assert.equal(R.smsConfirms({amount: 4999, smsAt: paid + 4 * HOUR}, paid, 4999, 3), false);
});

const reply = (answer, stop = 'end_turn') => ({stop_reason: stop, content: [{type: 'text', text: JSON.stringify(answer)}], usage: {input_tokens: 100, output_tokens: 20}});
const GOOD = {payment_id: '123456789012', amount: 4999, paid_date: '2026-11-02', paid_time: '09:30', readable: true};

test('only a clean answer from the model counts', () => {
  assert.deepEqual(readAnswer(reply(GOOD)), {paymentId: '123456789012', amount: 4999, date: '2026-11-02', time: '09:30', readable: true});
  assert.equal(readAnswer(reply(GOOD, 'refusal')), null);
  assert.equal(readAnswer(reply(GOOD, 'max_tokens')), null);
  assert.equal(readAnswer({stop_reason: 'end_turn', content: [{type: 'text', text: 'not json'}]}), null);
  assert.equal(readAnswer({stop_reason: 'end_turn', content: []}), null);
  assert.equal(FORMAT.schema.additionalProperties, false);
});

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
let seq = 0;

function fakes(contentType = 'image/png', bytes = Buffer.from(`shot-${Date.now()}-${++seq}`)) {
  const deleted = [];
  const bucket = {
    deleted,
    file: path => ({
      exists: async () => [true],
      getMetadata: async () => [{contentType, size: bytes.length}],
      download: async () => [bytes],
      delete: async () => { deleted.push(path); },
    }),
  };
  return {bucket, bytes};
}
const model = (answer, stop) => {
  const calls = [];
  return {calls, client: () => ({messages: {create: async body => { calls.push(body); return reply(answer, stop); }}})};
};
const broken = () => { throw new Error('no key'); };

async function setup(amount = 4999) {
  const db = getFirestore();
  await saveConfig(db, FILLED);
  const uid = `pay-vendor-${Date.now()}-${++seq}`;
  const ref = db.collection('paymentRequests').doc();
  await ref.set({uid, source: 'plans', amount, label: 'Plan', status: 'awaiting_payment', createdAt: Timestamp.fromMillis(NOW - HOUR)});
  return {db, uid, requestId: ref.id, read: async () => (await ref.get()).data(), path: `paymentScreenshots/${uid}/shot-${seq}`};
}
const freshId = () => String(Date.now()).slice(-9) + String(++seq).padStart(3, '0');

test('the screenshot first, then the SMS: verified with the bank time, and the screenshot removed', emulated, async () => {
  const {db, uid, requestId, read, path} = await setup();
  const {bucket} = fakes();
  const paymentId = freshId();
  const {client, calls} = model({...GOOD, payment_id: paymentId});
  assert.deepEqual(await submitScreenshot(db, bucket, client, uid, {requestId, path}, NOW), {status: 'checking'});
  assert.equal(calls[0].model, 'claude-sonnet-5-5');
  assert.equal(calls[0].messages[0].content[0].source.media_type, 'image/png');
  const smsAt = NOW - 25 * 60000;
  assert.deepEqual(await ingestSms(db, bucket, {sender: 'AD-HDFCBK', text: SMS(paymentId), receivedAt: smsAt}, NOW), {stored: true});
  const done = await read();
  assert.equal(done.status, 'verified');
  assert.equal(done.paidAt.toMillis(), smsAt);
  assert.deepEqual(bucket.deleted, [path]);
  const log = await db.collection('aiCallLog').where('uid', '==', uid).get();
  assert.equal(log.docs[0].data().model, 'claude-sonnet-5-5');
  assert.equal(log.docs[0].data().inputTokens, 100);
});

test('the SMS first, then the screenshot: also verified', emulated, async () => {
  const {db, uid, requestId, read, path} = await setup();
  const {bucket} = fakes();
  const paymentId = freshId();
  await ingestSms(db, bucket, {sender: 'HDFCBK', text: SMS(paymentId), receivedAt: NOW - 30 * 60000}, NOW);
  assert.deepEqual(await submitScreenshot(db, bucket, model({...GOOD, payment_id: paymentId}).client, uid, {requestId, path}, NOW), {status: 'verified'});
  assert.equal((await read()).status, 'verified');
});

test('an SMS keeps the id and amount only, never the text; the wrong sender is dropped', emulated, async () => {
  const {db} = await setup();
  const {bucket} = fakes();
  const paymentId = freshId();
  assert.deepEqual(await ingestSms(db, bucket, {sender: 'AD-AMAZON', text: SMS(paymentId)}, NOW), {stored: false});
  assert.equal((await db.doc(`paymentSms/${paymentId}`).get()).exists, false);
  await ingestSms(db, bucket, {sender: 'HDFCBK', text: SMS(paymentId), receivedAt: NOW}, NOW);
  assert.deepEqual(Object.keys((await db.doc(`paymentSms/${paymentId}`).get()).data()).sort(), ['amount', 'paymentId', 'smsAt', 'used']);
  assert.deepEqual(await ingestSms(db, bucket, {sender: 'HDFCBK', text: SMS(paymentId), receivedAt: NOW}, NOW), {stored: true}, 'the forwarder sending twice is harmless');
});

test('the same photo is refused before any AI call; a reused payment id is refused', emulated, async () => {
  const first = await setup();
  const second = await setup();
  const third = await setup();
  const paymentId = freshId();
  const {bucket, bytes} = fakes();
  await submitScreenshot(first.db, bucket, model({...GOOD, payment_id: paymentId}).client, first.uid, {requestId: first.requestId, path: first.path}, NOW);
  const noCall = model(GOOD);
  await assert.rejects(submitScreenshot(second.db, bucket, noCall.client, second.uid, {requestId: second.requestId, path: second.path}, NOW), /already used/);
  assert.equal(noCall.calls.length, 0);
  assert.ok(bucket.deleted.includes(second.path));
  assert.equal(bytes.length > 0, true);
  const other = fakes();
  await assert.rejects(submitScreenshot(third.db, other.bucket, model({...GOOD, payment_id: paymentId}).client, third.uid, {requestId: third.requestId, path: third.path}, NOW), /payment ID was already used/);
  assert.equal((await third.read()).status, 'awaiting_payment');
});

test('the wrong amount, an unreadable image, a refusal or a failed AI call all go to the manual check, never to verified', emulated, async () => {
  const wrong = await setup();
  assert.deepEqual(await submitScreenshot(wrong.db, fakes().bucket, model({...GOOD, payment_id: freshId(), amount: 100}).client, wrong.uid, {requestId: wrong.requestId, path: wrong.path}, NOW), {status: 'manual_review'});
  assert.match((await wrong.read()).reviewReason, /differs/);
  const unread = await setup();
  await submitScreenshot(unread.db, fakes().bucket, model({...GOOD, payment_id: freshId(), readable: false}).client, unread.uid, {requestId: unread.requestId, path: unread.path}, NOW);
  assert.equal((await unread.read()).status, 'manual_review');
  const refused = await setup();
  await submitScreenshot(refused.db, fakes().bucket, model(GOOD, 'refusal').client, refused.uid, {requestId: refused.requestId, path: refused.path}, NOW);
  assert.equal((await refused.read()).status, 'manual_review');
  const down = await setup();
  assert.deepEqual(await submitScreenshot(down.db, fakes().bucket, broken, down.uid, {requestId: down.requestId, path: down.path}, NOW), {status: 'manual_review'});
});

test('a bank SMS with another amount does not verify; the admin decides', emulated, async () => {
  const {db, uid, requestId, read, path} = await setup();
  const {bucket} = fakes();
  const paymentId = freshId();
  await submitScreenshot(db, bucket, model({...GOOD, payment_id: paymentId}).client, uid, {requestId, path}, NOW);
  await ingestSms(db, bucket, {sender: 'HDFCBK', text: SMS(paymentId, '100.00'), receivedAt: NOW}, NOW);
  const after = await read();
  assert.equal(after.status, 'manual_review');
  assert.equal(after.paidAt, undefined);
});

test('no SMS within the window: the manual check', emulated, async () => {
  const {db, uid, requestId, read, path} = await setup();
  await submitScreenshot(db, fakes().bucket, model({...GOOD, payment_id: freshId()}).client, uid, {requestId, path}, NOW);
  await closeChecks(db, NOW + 2 * HOUR);
  assert.equal((await read()).status, 'checking', 'still inside the window');
  await closeChecks(db, NOW + 3 * HOUR);
  const after = await read();
  assert.equal(after.status, 'manual_review');
  assert.match(after.reviewReason, /No bank SMS/);
});

test('the admin approves with the screenshot\'s time, or rejects and the vendor is told; each only once', emulated, async () => {
  const yes = await setup();
  const {bucket} = fakes();
  await submitScreenshot(yes.db, bucket, model({...GOOD, payment_id: freshId(), amount: 100}).client, yes.uid, {requestId: yes.requestId, path: yes.path}, NOW);
  assert.deepEqual(await reviewPayment(yes.db, bucket, {requestId: yes.requestId, action: 'approve'}, NOW), {status: 'verified'});
  const done = await yes.read();
  assert.equal(done.paidAt.toMillis(), Date.parse('2026-11-02T09:30:00+05:30'));
  assert.equal(done.verifiedBy, 'admin');
  assert.ok(done.paymentId, 'the id is taken now, so it stays unique');
  assert.ok(bucket.deleted.includes(yes.path));
  await assert.rejects(reviewPayment(yes.db, bucket, {requestId: yes.requestId, action: 'approve'}, NOW), /not waiting/);

  const no = await setup();
  await submitScreenshot(no.db, fakes().bucket, broken, no.uid, {requestId: no.requestId, path: no.path}, NOW);
  assert.deepEqual(await reviewPayment(no.db, bucket, {requestId: no.requestId, action: 'reject'}, NOW), {status: 'rejected'});
  assert.equal((await no.read()).paidAt, undefined);
  assert.equal((await no.db.collection('vendorNotices').where('vendorId', '==', no.uid).get()).size, 1);
});

test('the admin cannot approve an id that another payment already used', emulated, async () => {
  const paymentId = freshId();
  const first = await setup();
  await submitScreenshot(first.db, fakes().bucket, model({...GOOD, payment_id: paymentId}).client, first.uid, {requestId: first.requestId, path: first.path}, NOW);
  const second = await setup();
  await submitScreenshot(second.db, fakes().bucket, model({...GOOD, payment_id: paymentId, amount: 100}).client, second.uid, {requestId: second.requestId, path: second.path}, NOW);
  await assert.rejects(reviewPayment(second.db, fakes().bucket, {requestId: second.requestId, action: 'approve'}, NOW), /another payment/);
});

test('a vendor cannot send for another\'s request, twice, a wrong folder, a wrong file or past the daily limit', emulated, async () => {
  const {db, uid, requestId, path} = await setup();
  const {client} = model({...GOOD, payment_id: freshId()});
  await assert.rejects(submitScreenshot(db, fakes().bucket, client, 'someone-else', {requestId, path}, NOW), /not found/);
  await assert.rejects(submitScreenshot(db, fakes().bucket, client, uid, {requestId, path: 'catalog/x'}, NOW), /own vendor app/);
  await assert.rejects(submitScreenshot(db, fakes('application/pdf').bucket, client, uid, {requestId, path}, NOW), /JPG, PNG/);
  await submitScreenshot(db, fakes().bucket, client, uid, {requestId, path}, NOW);
  await assert.rejects(submitScreenshot(db, fakes().bucket, client, uid, {requestId, path}, NOW), /already being checked/);
  const limited = await setup();
  await saveConfig(limited.db, {...FILLED, dailyScreenshots: 1});
  await assert.rejects(submitScreenshot(limited.db, {file: fakes('application/pdf').bucket.file}, client, limited.uid, {requestId: limited.requestId, path: limited.path}, NOW), /JPG, PNG/);
  const bucket = fakes().bucket;
  // the failed type above used no allowance; the first real one does
  await submitScreenshot(limited.db, bucket, model({...GOOD, payment_id: freshId(), amount: 1}).client, limited.uid, {requestId: limited.requestId, path: limited.path}, NOW);
  const again = await limited.db.collection('paymentRequests').doc(); // the vendor's next try the same day
  await again.set({uid: limited.uid, amount: 4999, status: 'awaiting_payment', createdAt: Timestamp.fromMillis(NOW - HOUR)});
  await assert.rejects(submitScreenshot(limited.db, fakes().bucket, client, limited.uid, {requestId: again.id, path: limited.path}, NOW), /Too many/);
  await saveConfig(limited.db, FILLED);
});

test('with placeholders in the config, nothing is accepted', emulated, async () => {
  const {db, uid, requestId, path} = await setup();
  await saveConfig(db, {...FILLED, accountNumber: 'XX-ACCOUNT-NUMBER'});
  await assert.rejects(submitScreenshot(db, fakes().bucket, model(GOOD).client, uid, {requestId, path}, NOW), /not open yet/);
  assert.deepEqual(await ingestSms(db, fakes().bucket, {sender: 'HDFCBK', text: SMS(freshId())}, NOW), {stored: false});
  assert.equal((await db.doc('paymentBankPublic/main').get()).data().ready, false);
  await saveConfig(db, FILLED);
});

test('the admin\'s test box shows what the saved patterns find', emulated, async () => {
  const {db} = await setup();
  assert.deepEqual(await testSms(db, {sender: 'AD-HDFCBK', text: SMS('123456789012')}), {senderAllowed: true, found: {paymentId: '123456789012', amount: 4999}});
  assert.deepEqual(await testSms(db, {sender: 'X', text: 'hello'}), {senderAllowed: false, found: null});
  assert.equal((await readConfig(db)).ifsc, 'HDFC0000001');
});

test('a verified request carries all that the asking module needs, and nothing of how it was verified is required', emulated, async () => {
  const {db, uid, requestId, read, path} = await setup();
  const {bucket} = fakes();
  const paymentId = freshId();
  await submitScreenshot(db, bucket, model({...GOOD, payment_id: paymentId}).client, uid, {requestId, path}, NOW);
  await ingestSms(db, bucket, {sender: 'HDFCBK', text: SMS(paymentId), receivedAt: NOW - 25 * 60000}, NOW);
  const request = await read();
  assert.equal(request.source, 'plans', 'the mark of the asking module is left alone');
  assert.equal(request.uid, uid);
  assert.equal(request.status, 'verified');
  assert.equal(request.paidAt.toMillis(), NOW - 25 * 60000);
});
