'use strict';
// Razorpay payments: the pure rules, no database and no network.
//
// The keys are secrets (RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET, RAZORPAY_WEBHOOK_SECRET). Until they are real Razorpay keys (rzp_test_...
// or rzp_live_...) payments stay closed and vendors see "Payments will open soon", whatever the admin's switch says.
const crypto = require('node:crypto');

const LINK_DAYS = 2;
const ID = /^[a-zA-Z0-9_-]{1,128}$/;

const isPlaceholder = value => typeof value !== 'string' || value.trim() === '' || /^XX/.test(value.trim());

/// True when the key id and secret look like real Razorpay keys.
function keysReady(keyId, keySecret) {
  return /^rzp_(test|live)_[A-Za-z0-9]+$/.test(String(keyId ?? '').trim()) && !isPlaceholder(keySecret);
}

/// Rupees as Razorpay wants them: whole paise.
const paise = amount => Math.round(Number(amount) * 100);

/// The Payment Link for a request: exactly its amount, no part payments, and the request id as the reference Razorpay sends back.
function linkPayload(request, requestId, now = Date.now()) {
  if (!(Number(request.amount) > 0)) throw Error('This payment has no amount.');
  return {
    amount: paise(request.amount),
    currency: 'INR',
    accept_partial: false,
    reference_id: requestId,
    description: String(request.label || 'Loca Market payment').slice(0, 200),
    expire_by: Math.floor(now / 1000) + LINK_DAYS * 86400,
    reminder_enable: false,
    notify: {sms: false, email: false},
    notes: {requestId},
  };
}

/// Razorpay signs every webhook with the webhook secret: HMAC-SHA256 of the raw body, as hex.
function signatureValid(rawBody, signature, secret) {
  if (isPlaceholder(secret) || typeof signature !== 'string' || !/^[0-9a-f]{64}$/.test(signature)) return false;
  const expected = crypto.createHmac('sha256', secret).update(rawBody ?? '').digest('hex');
  return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(signature));
}

/// The captured payment of a paid link, or null. The link must be this request's, for its full amount.
function paidFromLink(link, request, requestId) {
  if (!link || link.status !== 'paid' || link.reference_id !== requestId || link.id !== request.razorpayLinkId) return null;
  if (Number(link.amount_paid) !== paise(request.amount)) return null;
  const payment = (link.payments ?? []).find(p => p.status === 'captured' && ID.test(String(p.payment_id ?? '')));
  if (!payment) return null;
  return {paymentId: payment.payment_id, paidAtMs: Number(payment.created_at) * 1000 || null};
}

/// The same from a payment_link.paid webhook event.
function paidFromEvent(event, request, requestId) {
  const link = event?.payload?.payment_link?.entity;
  const payment = event?.payload?.payment?.entity;
  if (event?.event !== 'payment_link.paid' || !link || !payment || payment.status !== 'captured') return null;
  if (Number(payment.amount) !== paise(request.amount)) return null;
  return paidFromLink({...link, payments: [{payment_id: payment.id, status: payment.status, created_at: payment.created_at}]}, request, requestId);
}

/// Which request a webhook event is about, or ''.
function requestIdOf(event) {
  const id = event?.payload?.payment_link?.entity?.reference_id;
  return typeof id === 'string' && ID.test(id) ? id : '';
}

module.exports = {LINK_DAYS, ID, isPlaceholder, keysReady, paise, linkPayload, signatureValid, paidFromLink, paidFromEvent, requestIdOf};
