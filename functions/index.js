'use strict';
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentUpdated} = require('firebase-functions/v2/firestore');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {createHash} = require('node:crypto');
const {quote} = require('./domain');
initializeApp();
Object.assign(exports, require('./notifications'));
const db = getFirestore();
// Firebase callable handlers validate user auth inside the function. The HTTP
// transport must accept requests before login and Firebase ID-token requests.
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};
const digest = value => createHash('sha256').update(value).digest('hex');
async function rateLimit(key, limit, windowMs) {
  const ref = db.collection('_rateLimits').doc(digest(key));
  await db.runTransaction(async tx => {
    const snapshot = await tx.get(ref);
    const data = snapshot.data();
    const now = Date.now();
    const fresh = !data || data.until <= now;
    if (!fresh && data.count >= limit) throw new HttpsError('resource-exhausted', 'Too many attempts. Please try again later.');
    tx.set(ref, {count: fresh ? 1 : data.count + 1, until: fresh ? now + windowMs : data.until});
  });
}
// Keep legacy callable URLs explicit during migration; never issue PIN tokens.
const retiredPhoneAuth = onCall(options, async () => {
  throw new HttpsError('failed-precondition', 'SMS/PIN sign-in has been replaced by verified email and password. Update the app and use email sign-in.');
});
exports.pinLogin = retiredPhoneAuth;
exports.setPin = retiredPhoneAuth;
exports.placeOrder = onCall(options, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true) throw new HttpsError('permission-denied', 'Verify your email before ordering.');
  const {items, pincode, address, requestId} = request.data || {};
  if (typeof pincode !== 'string' || !/^\d{6}$/.test(pincode) || typeof address !== 'string' || address.trim().length < 10 || address.length > 1000 || typeof requestId !== 'string' || !/^[a-zA-Z0-9_-]{1,100}$/.test(requestId)) throw new HttpsError('invalid-argument', 'Provide a valid address, pincode and request ID.');
  if (!Array.isArray(items) || !items.length || items.length > 50 || items.some(i => typeof i?.productId !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(i.productId))) throw new HttpsError('invalid-argument', 'Invalid items.');
  await rateLimit(`order:${request.auth.uid}`, 20, 60 * 1000);
  const orderId = digest(`${request.auth.uid}:${requestId}`);
  const orderRef = db.collection('orders').doc(orderId);
  return db.runTransaction(async tx => {
    if ((await tx.get(orderRef)).exists) return {orderId};
    const refs = items.map(i => db.collection('products').doc(i.productId));
    const snapshots = await tx.getAll(...refs);
    let result;
    try { result = quote(items, snapshots.map(s => s.data()), pincode); } catch (e) { throw new HttpsError('failed-precondition', e.message); }
    tx.create(orderRef, {userId: request.auth.uid, ...result, pincode, address: address.trim(), status: 'submitted', paymentStatus: 'pending_arrangement', createdAt: FieldValue.serverTimestamp()});
    refs.forEach((ref, i) => tx.update(ref, {stock: snapshots[i].data().stock - items[i].quantity}));
    return {orderId};
  });
});
// Cancelling an order must return its reserved stock exactly once, however many
// times an admin toggles status; a stockRestored flag makes the transaction idempotent.
exports.reconcileCancelledOrderStock = onDocumentUpdated({document: 'orders/{orderId}', region: 'asia-south1', maxInstances: 5}, async event => {
  const before = event.data.before.data(), after = event.data.after.data();
  if (after.status !== 'cancelled' || before.status === 'cancelled' || !Array.isArray(after.lines)) return;
  const orderRef = event.data.after.ref;
  await db.runTransaction(async tx => {
    const fresh = (await tx.get(orderRef)).data();
    if (!fresh || fresh.status !== 'cancelled' || fresh.stockRestored) return;
    const refs = after.lines.map(line => db.collection('products').doc(line.productId));
    const snapshots = refs.length ? await tx.getAll(...refs) : [];
    snapshots.forEach((snapshot, i) => {
      if (snapshot.exists) tx.update(snapshot.ref, {stock: FieldValue.increment(after.lines[i].quantity)});
    });
    tx.update(orderRef, {stockRestored: true});
  });
});
