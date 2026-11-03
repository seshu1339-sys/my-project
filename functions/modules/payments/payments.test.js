const {test} = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore} = require('firebase-admin/firestore');
const R = require('./rules');
const {saveSettings, startPayment, checkPayment, handleEvent, cancelLinkOf} = require('./store');

const NOW = Date.parse('2026-11-03T10:00:00+05:30');
const SECRET = 'whsec_made_up_for_tests';
const request = (extra = {}) => ({uid: 'v1', source: 'plans', amount: 4999, label: '3 Year plan', status: 'awaiting_payment', razorpayLinkId: 'plink_1', ...extra});
const paidLink = (extra = {}) => ({id: 'plink_1', status: 'paid', reference_id: 'r1', amount: 499900, amount_paid: 499900, payments: [{payment_id: 'pay_1', status: 'captured', created_at: NOW / 1000 - 60}], ...extra});
const paidEvent = (link = {}, payment = {}) => ({
  event: 'payment_link.paid',
  payload: {payment_link: {entity: {id: 'plink_1', status: 'paid', reference_id: 'r1', amount: 499900, amount_paid: 499900, ...link}}, payment: {entity: {id: 'pay_1', amount: 499900, status: 'captured', created_at: NOW / 1000 - 60, ...payment}}},
});

test('payments stay closed until the keys are real Razorpay keys', () => {
  assert.equal(R.keysReady('XX-KEY-ID', 'XX-SECRET'), false);
  assert.equal(R.keysReady('rzp_test_AbC123', 'XX'), false);
  assert.equal(R.keysReady('', 'secret'), false);
  assert.equal(R.keysReady('rzp_test_AbC123', 'realsecret'), true);
  assert.equal(R.keysReady('rzp_live_AbC123', 'realsecret'), true);
});

test('the link asks for exactly the amount in paise, no part payment, with the request id as its reference', () => {
  const link = R.linkPayload(request({amount: 99.5}), 'r1', NOW);
  assert.equal(link.amount, 9950);
  assert.equal(link.currency, 'INR');
  assert.equal(link.accept_partial, false);
  assert.equal(link.reference_id, 'r1');
  assert.equal(link.expire_by, NOW / 1000 + 2 * 86400);
  assert.throws(() => R.linkPayload(request({amount: 0}), 'r1', NOW), /no amount/);
});

test('a webhook counts only with the right signature of the raw body', () => {
  const body = Buffer.from(JSON.stringify(paidEvent()));
  const good = crypto.createHmac('sha256', SECRET).update(body).digest('hex');
  assert.equal(R.signatureValid(body, good, SECRET), true);
  assert.equal(R.signatureValid(Buffer.from(`${body} `), good, SECRET), false);
  assert.equal(R.signatureValid(body, good, 'another'), false);
  assert.equal(R.signatureValid(body, 'nothex', SECRET), false);
  assert.equal(R.signatureValid(body, good, 'XX-WEBHOOK-SECRET'), false, 'a placeholder secret accepts nothing');
});

test('only a full, captured payment of this request\'s own link counts', () => {
  assert.deepEqual(R.paidFromLink(paidLink(), request(), 'r1'), {paymentId: 'pay_1', paidAtMs: NOW - 60000});
  assert.equal(R.paidFromLink(paidLink({status: 'partially_paid'}), request(), 'r1'), null);
  assert.equal(R.paidFromLink(paidLink({amount_paid: 100}), request(), 'r1'), null);
  assert.equal(R.paidFromLink(paidLink({reference_id: 'r2'}), request(), 'r1'), null);
  assert.equal(R.paidFromLink(paidLink({id: 'plink_other'}), request(), 'r1'), null);
  assert.equal(R.paidFromLink(paidLink({payments: [{payment_id: 'pay_1', status: 'failed'}]}), request(), 'r1'), null);
  assert.deepEqual(R.paidFromEvent(paidEvent(), request(), 'r1'), {paymentId: 'pay_1', paidAtMs: NOW - 60000});
  assert.equal(R.paidFromEvent({...paidEvent(), event: 'payment_link.cancelled'}, request(), 'r1'), null);
  assert.equal(R.paidFromEvent(paidEvent({}, {amount: 100}), request(), 'r1'), null);
  assert.equal(R.requestIdOf(paidEvent()), 'r1');
  assert.equal(R.requestIdOf(paidEvent({reference_id: '../x'})), '');
});

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
const fakeApi = (link = paidLink()) => {
  const calls = [];
  return {
    calls,
    createLink: async payload => { calls.push(['create', payload]); return {id: 'plink_1', short_url: 'https://rzp.io/i/abc', expire_by: payload.expire_by}; },
    fetchLink: async id => { calls.push(['fetch', id]); return link; },
    cancelLink: async id => { calls.push(['cancel', id]); return {}; },
  };
};
async function setup(extra = {}, ready = true) {
  const db = getFirestore();
  const id = `r${crypto.randomUUID().slice(0, 8)}`;
  await db.collection('paymentPublic').doc('main').set({ready});
  await db.collection('paymentRequests').doc(id).set(request({razorpayLinkId: null, ...extra}));
  return {db, id};
}
const read = async (db, id) => (await db.collection('paymentRequests').doc(id).get()).data();

test('the admin switch opens payments only with real keys', emulated, async () => {
  const db = getFirestore();
  assert.deepEqual(await saveSettings(db, {enabled: true}, false, NOW), {ready: false, keysSet: false});
  assert.equal((await db.collection('paymentPublic').doc('main').get()).data().ready, false);
  assert.deepEqual(await saveSettings(db, {enabled: true}, true, NOW), {ready: true, keysSet: true});
  assert.equal((await db.collection('paymentPublic').doc('main').get()).data().ready, true);
  assert.deepEqual(await saveSettings(db, {enabled: false}, true, NOW), {ready: false, keysSet: true});
  await assert.rejects(saveSettings(db, {enabled: 'yes'}, true, NOW), /on or off/);
});

test('a vendor gets one link per request, reused while it is valid; never for someone else\'s request or while closed', emulated, async () => {
  const {db, id} = await setup();
  const api = fakeApi();
  assert.deepEqual(await startPayment(db, api, 'v1', {requestId: id}, NOW), {url: 'https://rzp.io/i/abc'});
  assert.deepEqual(await startPayment(db, api, 'v1', {requestId: id}, NOW + 60000), {url: 'https://rzp.io/i/abc'});
  assert.equal(api.calls.filter(c => c[0] === 'create').length, 1);
  assert.equal(api.calls[0][1].reference_id, id);
  assert.equal((await read(db, id)).razorpayLinkId, 'plink_1');
  await assert.rejects(startPayment(db, api, 'v2', {requestId: id}, NOW), /not found/);
  const closed = await setup({}, false);
  await assert.rejects(startPayment(db, api, 'v1', {requestId: closed.id}, NOW), /not open/);
  const done = await setup({status: 'verified'});
  await assert.rejects(startPayment(db, api, 'v1', {requestId: done.id}, NOW), /already done/);
});

test('the webhook verifies the request once, with the payment time; the same payment never pays another request', emulated, async () => {
  const {db, id} = await setup({razorpayLinkId: 'plink_1'});
  const payId = `pay_${crypto.randomUUID().slice(0, 8)}`;
  const event = paidEvent({reference_id: id}, {id: payId});
  assert.deepEqual(await handleEvent(db, event, NOW), {handled: true, status: 'verified'});
  const paid = await read(db, id);
  assert.equal(paid.status, 'verified');
  assert.equal(paid.razorpayPaymentId, payId);
  assert.equal(paid.paidAt.toMillis(), NOW - 60000);
  assert.deepEqual(await handleEvent(db, event, NOW + 1000), {handled: true, status: 'verified'}, 'Razorpay sending it again changes nothing');
  const other = await setup({razorpayLinkId: 'plink_1'});
  assert.deepEqual(await handleEvent(db, paidEvent({reference_id: other.id}, {id: payId}), NOW), {handled: true, status: 'used'});
  assert.equal((await read(db, other.id)).status, 'awaiting_payment');
});

test('"I have paid" asks Razorpay and verifies; an unpaid link stays waiting', emulated, async () => {
  const {db, id} = await setup({razorpayLinkId: 'plink_1'});
  assert.deepEqual(await checkPayment(db, fakeApi(paidLink({reference_id: id, status: 'created', amount_paid: 0})), 'v1', {requestId: id}, NOW), {status: 'awaiting_payment'});
  const payId = `pay_${crypto.randomUUID().slice(0, 8)}`;
  const link = paidLink({reference_id: id, payments: [{payment_id: payId, status: 'captured', created_at: NOW / 1000 - 60}]});
  assert.deepEqual(await checkPayment(db, fakeApi(link), 'v1', {requestId: id}, NOW), {status: 'verified'});
  await assert.rejects(checkPayment(db, fakeApi(link), 'v2', {requestId: id}, NOW), /not found/);
});

test('a cancelled request has its link cancelled; a payment that still comes in is kept for a refund, not verified', emulated, async () => {
  const api = fakeApi();
  assert.equal(await cancelLinkOf(api, {status: 'awaiting_payment'}, {status: 'cancelled', razorpayLinkId: 'plink_9'}), true);
  assert.deepEqual(api.calls, [['cancel', 'plink_9']]);
  assert.equal(await cancelLinkOf(api, {status: 'awaiting_payment'}, {status: 'cancelled'}), false);
  const {db, id} = await setup({status: 'cancelled', razorpayLinkId: 'plink_1'});
  const payId = `pay_${crypto.randomUUID().slice(0, 8)}`;
  assert.deepEqual(await handleEvent(db, paidEvent({reference_id: id}, {id: payId}), NOW), {handled: true, status: 'paid_after_cancel'});
  assert.equal((await read(db, id)).status, 'paid_after_cancel');
  const notice = await db.collection('vendorNotices').where('vendorId', '==', 'v1').where('type', '==', 'payment').get();
  assert.ok(notice.docs.some(d => /refund/.test(d.data().body)));
});

test('an event for an unknown request, or for a link that is not the request\'s, is ignored', emulated, async () => {
  const {db, id} = await setup({razorpayLinkId: 'plink_other'});
  assert.deepEqual(await handleEvent(db, paidEvent({reference_id: id}), NOW), {handled: false});
  assert.deepEqual(await handleEvent(db, paidEvent({reference_id: 'nobody'}), NOW), {handled: false});
  assert.deepEqual(await handleEvent(db, {event: 'payment.failed'}, NOW), {handled: false});
  assert.equal((await read(db, id)).status, 'awaiting_payment');
});
