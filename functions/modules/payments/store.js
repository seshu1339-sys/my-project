'use strict';
// What the payment module reads and writes. It knows nothing about plans: paymentRequests is the only meeting point.
//
//   paymentSettings/main     admin only: {enabled, keysSet}, the admin's on/off switch and whether the Razorpay keys are real
//   paymentPublic/main       what vendors see: {ready}, true only when the switch is on and the keys are real
//   paymentRequests/<id>     made by the asking module with status awaiting_payment. This module adds the Razorpay link
//                            (razorpayLinkId, razorpayLinkUrl, razorpayLinkExpiresAt) and, once Razorpay says it is paid, status
//                            verified, paidAt and razorpayPaymentId: all the asking module needs. A request cancelled by its module
//                            has its link cancelled; one paid anyway becomes paid_after_cancel, for the admin to refund.
//                            Refunds: a full one makes it refunded, a part one records refundedAmount; a failed try is kept as lastFailure;
//                            an expired or cancelled link is dropped so Pay makes a new one. The vendor's plan is never touched by a refund.
//   paymentRefunds/<id>      one per Razorpay refund, so a refund event sent twice counts once
//   paymentIds/<paymentId>   one per Razorpay payment ever used, created in a transaction: one payment never pays two requests
//
// [api] is the Razorpay client made in index.js ({createLink, fetchLink, cancelLink}); tests pass their own.
const {Timestamp, FieldValue} = require('firebase-admin/firestore');
const {ID, linkPayload, paidFromLink, paidFromEvent, requestIdOf, refundFromEvent, failureFromEvent, closedLinkFromEvent, paise} = require('./rules');

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

/// refund.processed: the money went back. The refund id is claimed once (Razorpay may send the event again). A full refund makes the
/// request 'refunded'; a part refund only records the amount. The vendor's plan is not touched: the admin stops it by hand if needed.
async function handleRefund(db, refund, now) {
  const found = await requests(db).where('razorpayPaymentId', '==', refund.paymentId).limit(1).get();
  if (found.empty) return {handled: false};
  const ref = found.docs[0].ref;
  const refundRef = db.collection('paymentRefunds').doc(refund.refundId);
  const result = await db.runTransaction(async tx => {
    const [requestDoc, refundDoc] = [await tx.get(ref), await tx.get(refundRef)];
    const request = requestDoc.data();
    if (refundDoc.exists) return {status: request.status, duplicate: true};
    const refundedPaise = Math.round(Number(request.refundedAmount ?? 0) * 100) + refund.amountPaise;
    const full = refundedPaise >= paise(request.amount);
    const status = full ? 'refunded' : request.status;
    tx.create(refundRef, {requestId: ref.id, uid: request.uid, amountPaise: refund.amountPaise, createdAt: stamp(now)});
    tx.update(ref, {status, refundedAmount: refundedPaise / 100, refundedAt: stamp(now), updatedAt: stamp(now)});
    return {status, request, refundedPaise, full};
  });
  if (result.duplicate) return {handled: true, status: result.status};
  const money = `₹${result.refundedPaise / 100}`;
  await notify(db, result.request.uid, 'Refund processed', result.full
    ? `Your payment of ₹${result.request.amount} was refunded (${money}). Your bank may take some time to show it.`
    : `A part refund of ${money} was processed for your payment of ₹${result.request.amount}. Your bank may take some time to show it.`, now);
  return {handled: true, status: result.status};
}

/// payment.failed: the request stays open so the vendor can try again; the reason is kept and shown.
async function handleFailure(db, requestId, failure, now) {
  const request = (await requests(db).doc(requestId).get()).data();
  if (request?.status !== 'awaiting_payment') return {handled: false};
  if (request.lastFailure?.paymentId === failure.paymentId) return {handled: true, status: request.status};
  await requests(db).doc(requestId).update({lastFailure: {paymentId: failure.paymentId, reason: failure.reason, at: stamp(now)}, updatedAt: stamp(now)});
  await notify(db, request.uid, 'Payment did not go through', `${failure.reason} You can try again from the payment page.`, now);
  return {handled: true, status: request.status};
}

/// payment_link.expired or .cancelled for a request still waiting: the old link is dropped, so tapping Pay makes a new one.
async function handleClosedLink(db, requestId, request, now) {
  if (request.status !== 'awaiting_payment') return {handled: false};
  await requests(db).doc(requestId).update({razorpayLinkUrl: FieldValue.delete(), razorpayLinkExpiresAt: FieldValue.delete(), linkClosedAt: stamp(now), updatedAt: stamp(now)});
  await notify(db, request.uid, 'Payment link closed', 'Your payment link is no longer open. Open the payment page and tap Pay to get a new one.', now);
  return {handled: true, status: request.status};
}

/// A webhook event whose signature is already checked. Anything that is not about a known request is ignored.
async function handleEvent(db, event, now = Date.now()) {
  const refund = refundFromEvent(event);
  if (refund) return handleRefund(db, refund, now);
  const requestId = requestIdOf(event);
  if (!requestId) return {handled: false};
  const request = (await requests(db).doc(requestId).get()).data();
  if (!request) return {handled: false};
  const failure = failureFromEvent(event);
  if (failure) return handleFailure(db, requestId, failure, now);
  if (closedLinkFromEvent(event, request, requestId)) return handleClosedLink(db, requestId, request, now);
  const paid = paidFromEvent(event, request, requestId);
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
