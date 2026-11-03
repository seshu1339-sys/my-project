'use strict';
// What the payment module reads and writes. It knows nothing about plans: paymentRequests is the only meeting point.
//
//   paymentSettings/main     admin only: {enabled, keysSet}, the admin's on/off switch and whether the Razorpay keys are real
//   paymentPublic/main       what vendors see: {ready}, true only when the switch is on and the keys are real
//   paymentRequests/<id>     made by the asking module with status awaiting_payment. This module adds the Razorpay link
//                            (razorpayLinkId, razorpayLinkUrl, razorpayLinkExpiresAt) and, once Razorpay says it is paid, status
//                            verified, paidAt and razorpayPaymentId: all the asking module needs. A request cancelled by its module
//                            has its link cancelled; one paid anyway becomes paid_after_cancel, for the admin to refund.
//   paymentIds/<paymentId>   one per Razorpay payment ever used, created in a transaction: one payment never pays two requests
//
// [api] is the Razorpay client made in index.js ({createLink, fetchLink, cancelLink}); tests pass their own.
const {Timestamp} = require('firebase-admin/firestore');
const {ID, linkPayload, paidFromLink, paidFromEvent, requestIdOf} = require('./rules');

const requests = db => db.collection('paymentRequests');
const stamp = ms => Timestamp.fromMillis(ms);
// A link that expires sooner than this is replaced rather than handed out.
const LINK_MARGIN_MS = 15 * 60 * 1000;

async function paymentsReady(db) {
  return (await db.collection('paymentPublic').doc('main').get()).data()?.ready === true;
}

/// The admin's switch. Vendors can pay only when it is on and the keys are real.
async function saveSettings(db, data, keysSet, now = Date.now()) {
  if (typeof data.enabled !== 'boolean') throw Error('Choose on or off.');
  const batch = db.batch();
  batch.set(db.collection('paymentSettings').doc('main'), {enabled: data.enabled, keysSet, updatedAt: stamp(now)});
  batch.set(db.collection('paymentPublic').doc('main'), {ready: data.enabled && keysSet, updatedAt: stamp(now)});
  await batch.commit();
  return {ready: data.enabled && keysSet, keysSet};
}

async function ownRequest(db, uid, requestId) {
  if (typeof requestId !== 'string' || !ID.test(requestId)) throw Error('Payment not found.');
  const request = (await requests(db).doc(requestId).get()).data();
  if (request?.uid !== uid) throw Error('Payment not found.');
  return request;
}

async function notify(db, uid, title, body, now) {
  await db.collection('vendorNotices').add({vendorId: uid, type: 'payment', title, body, createdAt: stamp(now)});
}

/// The vendor taps Pay: the Razorpay link for this request, made once and reused while it is valid.
async function startPayment(db, api, uid, data, now = Date.now()) {
  const request = await ownRequest(db, uid, data.requestId);
  if (request.status === 'verified') throw Error('This payment is already done.');
  if (request.status !== 'awaiting_payment') throw Error('This payment can no longer be paid.');
  if (!(await paymentsReady(db))) throw Error('Payments are not open yet.');
  const expires = request.razorpayLinkExpiresAt?.toMillis?.() ?? 0;
  if (request.razorpayLinkUrl && expires > now + LINK_MARGIN_MS) return {url: request.razorpayLinkUrl};
  const link = await api.createLink(linkPayload(request, data.requestId, now));
  if (typeof link?.id !== 'string' || typeof link.short_url !== 'string') throw Error('Razorpay did not give a payment link. Try again.');
  await requests(db).doc(data.requestId).update({
    razorpayLinkId: link.id, razorpayLinkUrl: link.short_url, razorpayLinkExpiresAt: stamp(Number(link.expire_by) * 1000 || now), updatedAt: stamp(now),
  });
  return {url: link.short_url};
}

/// Marks a request paid, once. The payment id is claimed in the same transaction, so one payment never pays two requests.
async function markPaid(db, requestId, {paymentId, paidAtMs}, now) {
  const ref = requests(db).doc(requestId);
  const idRef = db.collection('paymentIds').doc(paymentId);
  return db.runTransaction(async tx => {
    const [requestDoc, idDoc] = [await tx.get(ref), await tx.get(idRef)];
    const request = requestDoc.data();
    if (!request) return 'missing';
    if (request.status === 'verified' || request.status === 'paid_after_cancel') return request.status;
    if (idDoc.exists) return 'used';
    const status = request.status === 'awaiting_payment' ? 'verified' : 'paid_after_cancel';
    tx.create(idRef, {requestId, uid: request.uid, createdAt: stamp(now)});
    tx.update(ref, {status, paidAt: stamp(Math.min(paidAtMs ?? now, now)), verifiedBy: 'razorpay', razorpayPaymentId: paymentId, updatedAt: stamp(now)});
    return status;
  });
}

async function afterPaid(db, request, status, now) {
  if (status === 'paid_after_cancel') await notify(db, request.uid, 'Payment received for a cancelled choice', 'You paid for a plan you had already changed. The office will refund it.', now);
}

/// The vendor taps "I have paid": asks Razorpay directly, for when the webhook is late.
async function checkPayment(db, api, uid, data, now = Date.now()) {
  const request = await ownRequest(db, uid, data.requestId);
  if (request.status !== 'awaiting_payment' || !request.razorpayLinkId) return {status: request.status};
  const paid = paidFromLink(await api.fetchLink(request.razorpayLinkId), request, data.requestId);
  if (!paid) return {status: 'awaiting_payment'};
  const status = await markPaid(db, data.requestId, paid, now);
  await afterPaid(db, request, status, now);
  return {status};
}

/// A webhook event whose signature is already checked. Anything that is not a full payment of a known request is ignored.
async function handleEvent(db, event, now = Date.now()) {
  const requestId = requestIdOf(event);
  if (!requestId) return {handled: false};
  const request = (await requests(db).doc(requestId).get()).data();
  const paid = request ? paidFromEvent(event, request, requestId) : null;
  if (!paid) return {handled: false};
  const status = await markPaid(db, requestId, paid, now);
  await afterPaid(db, request, status, now);
  return {handled: true, status};
}

/// The asking module cancelled a request: its link must not take money any more.
async function cancelLinkOf(api, before, after) {
  if (before.status !== 'awaiting_payment' || after.status !== 'cancelled' || !after.razorpayLinkId) return false;
  try {
    await api.cancelLink(after.razorpayLinkId);
  } catch (error) {
    // Already paid, expired or cancelled: a payment that still comes in becomes paid_after_cancel.
    console.warn('Payment link not cancelled', error.status ?? error.message);
  }
  return true;
}

module.exports = {saveSettings, startPayment, checkPayment, handleEvent, markPaid, cancelLinkOf, paymentsReady};
