'use strict';
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {createHash} = require('node:crypto');
const {hashPin, verifyPin, quote} = require('./domain');
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
exports.pinLogin = onCall(options, async request => {
  const {phone, pin} = request.data || {};
  if (typeof phone !== 'string' || !/^\+[1-9]\d{7,14}$/.test(phone) || typeof pin !== 'string' || !/^\d{6}$/.test(pin)) throw new HttpsError('invalid-argument', 'Use an international phone number and six-digit PIN.');
  await rateLimit(`ip:${request.rawRequest.ip}`, 30, 15 * 60 * 1000);
  await rateLimit(`phone:${phone}`, 5, 15 * 60 * 1000);
  let user;
  try { user = await getAuth().getUserByPhoneNumber(phone); } catch { /* Return the same error for unknown numbers. */ }
  const record = user ? (await db.collection('_pins').doc(user.uid).get()).data() : null;
  const valid = verifyPin(pin, record || {salt: 'unknown-account', hash: '00'.repeat(64)});
  if (!valid || !user || user.disabled) throw new HttpsError('unauthenticated', 'Phone number or PIN is incorrect.');
  return {token: await getAuth().createCustomToken(user.uid)};
});
exports.setPin = onCall(options, async request => {
  const auth = request.auth;
  if (!auth || auth.token.firebase?.sign_in_provider !== 'phone' || Date.now() / 1000 - auth.token.auth_time > 300 || !auth.token.phone_number) throw new HttpsError('unauthenticated', 'Verify your phone by SMS again before setting a PIN.');
  const pin = request.data?.pin;
  if (typeof pin !== 'string' || !/^\d{6}$/.test(pin)) throw new HttpsError('invalid-argument', 'Use exactly six digits.');
  await rateLimit(`pin-set:${auth.uid}`, 5, 15 * 60 * 1000);
  await db.collection('_pins').doc(auth.uid).set({...hashPin(pin), updatedAt: FieldValue.serverTimestamp()});
  await getAuth().revokeRefreshTokens(auth.uid);
  return {ok: true};
});
exports.placeOrder = onCall(options, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
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
