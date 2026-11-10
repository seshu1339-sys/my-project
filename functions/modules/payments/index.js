'use strict';
const {requireRole, isAdminToken} = require('../../role-auth');
// Razorpay payment module. Its own files, callables and collections (see store.js). Any module can ask for a payment by making a
// paymentRequests document; plans is the only one today, and this module never imports it. Vendors pay on a Razorpay Payment Link,
// which opens in the browser on the website and in the Android app alike.
//
//   savePaymentSettings    admin    -> switches payments on or off; says whether the Razorpay keys are set
//   startRazorpayPayment   vendor   -> the Payment Link for a request
//   checkRazorpayPayment   vendor   -> asks Razorpay whether the link is paid (for a late webhook)
//   razorpayWebhook        endpoint -> Razorpay events: payment_link.paid, payment_link.expired, payment_link.cancelled, payment.failed,
//                             refund.processed; checked with RAZORPAY_WEBHOOK_SECRET
//   cancelRazorpayLink     trigger  -> the asking module cancelled a request; its link is cancelled too
//
// Secrets to set before deploying: RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET, RAZORPAY_WEBHOOK_SECRET (placeholder values such as XX keep
// payments closed). The webhook URL to give Razorpay is the razorpayWebhook function's URL, with those five events switched on.
const {onCall, onRequest, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentUpdated} = require('firebase-functions/v2/firestore');
const {defineSecret} = require('firebase-functions/params');
const {getFirestore} = require('firebase-admin/firestore');
const {requireAdminSession} = require('../../admin-session');
const {keysReady, signatureValid} = require('./rules');
const {saveSettings, startPayment, checkPayment, handleEvent, cancelLinkOf} = require('./store');

const keyId = defineSecret('RAZORPAY_KEY_ID');
const keySecret = defineSecret('RAZORPAY_KEY_SECRET');
const webhookSecret = defineSecret('RAZORPAY_WEBHOOK_SECRET');
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};
const withKeys = {...options, secrets: [keyId, keySecret]};
const fail = error => { throw new HttpsError('failed-precondition', error.message); };
function requireVerified(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  requireRole(request);
  return request.auth.uid;
}
async function requireAdmin(request) {
  const uid = requireVerified(request);
  if (!isAdminToken(request.auth.token)) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(uid);
}

/// The Razorpay REST API, with the key id and secret as basic auth.
function razorpay() {
  if (!keysReady(keyId.value(), keySecret.value())) throw Error('Payments are not open yet.');
  const auth = `Basic ${Buffer.from(`${keyId.value().trim()}:${keySecret.value().trim()}`).toString('base64')}`;
  const send = async (method, path, body) => {
    const response = await fetch(`https://api.razorpay.com/v1${path}`, {
      method, headers: {authorization: auth, 'content-type': 'application/json'}, ...(body ? {body: JSON.stringify(body)} : {}),
    });
    const json = await response.json().catch(() => ({}));
    if (!response.ok) throw Object.assign(Error('Razorpay could not be reached. Try again.'), {status: response.status});
    return json;
  };
  return {
    createLink: payload => send('POST', '/payment_links', payload),
    fetchLink: id => send('GET', `/payment_links/${encodeURIComponent(id)}`),
    cancelLink: id => send('POST', `/payment_links/${encodeURIComponent(id)}/cancel`),
  };
}

exports.savePaymentSettings = onCall(withKeys, async request => {
  await requireAdmin(request);
  try { return await saveSettings(getFirestore(), request.data || {}, keysReady(keyId.value(), keySecret.value())); } catch (error) { return fail(error); }
});
exports.startRazorpayPayment = onCall(withKeys, async request => {
  const uid = requireVerified(request);
  try { return await startPayment(getFirestore(), razorpay(), uid, request.data || {}); } catch (error) { return fail(error); }
});
exports.checkRazorpayPayment = onCall(withKeys, async request => {
  const uid = requireVerified(request);
  try { return await checkPayment(getFirestore(), razorpay(), uid, request.data || {}); } catch (error) { return fail(error); }
});
exports.razorpayWebhook = onRequest({region: 'asia-south1', maxInstances: 3, invoker: 'public', secrets: [webhookSecret]}, async (req, res) => {
  if (req.method !== 'POST') return void res.status(405).send('POST only');
  if (!signatureValid(req.rawBody, req.get('x-razorpay-signature'), webhookSecret.value())) return void res.status(401).send('Bad signature');
  try {
    res.json(await handleEvent(getFirestore(), req.body ?? {}));
  } catch (error) {
    // Razorpay sends the event again when it does not get a 2xx.
    console.error('Razorpay event not stored', error.message);
    res.status(500).send('Try again');
  }
});
exports.cancelRazorpayLink = onDocumentUpdated({document: 'paymentRequests/{requestId}', region: 'asia-south1', maxInstances: 3, secrets: [keyId, keySecret]}, async event => {
  const before = event.data.before.data(), after = event.data.after.data();
  if (after.status !== 'cancelled' || !after.razorpayLinkId) return;
  await cancelLinkOf(razorpay(), before, after);
});
