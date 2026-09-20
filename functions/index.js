'use strict';
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentUpdated} = require('firebase-functions/v2/firestore');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {createHash, randomInt} = require('node:crypto');
const {quote, distanceKm, validCoordinate, paymentOptions, vendorFee} = require('./domain');
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
function requireUser(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true) throw new HttpsError('permission-denied', 'Verify your email first.');
  return request.auth.uid;
}
function requireAdmin(request) {
  requireUser(request);
  if (request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Administrator access required.');
}
function requireCoordinate(value, name) {
  if (!validCoordinate(value)) throw new HttpsError('invalid-argument', `Provide a valid ${name}.`);
  return value;
}
function publicChangeFields(type, changes) {
  const allowed = {
    price: ['price', 'compareAtPrice', 'prices'],
    product: ['name', 'description', 'categoryId', 'unit', 'imageUrl', 'images', 'tags'],
    shop: ['name', 'description', 'address', 'phone', 'whatsapp', 'imageUrl'],
  }[type];
  if (!allowed || !changes || typeof changes !== 'object') throw new HttpsError('invalid-argument', 'Unsupported public change.');
  const keys = Object.keys(changes);
  if (!keys.length || keys.some(key => !allowed.includes(key))) throw new HttpsError('invalid-argument', 'Unsupported public change field.');
  return Object.fromEntries(keys.map(key => [key, changes[key]]));
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
  const requestedPaymentMethod = request.data?.paymentMethod;
  if (typeof pincode !== 'string' || !/^\d{6}$/.test(pincode) || typeof address !== 'string' || address.trim().length < 10 || address.length > 1000 || typeof requestId !== 'string' || !/^[a-zA-Z0-9_-]{1,100}$/.test(requestId)) throw new HttpsError('invalid-argument', 'Provide a valid address, pincode and request ID.');
  if (!Array.isArray(items) || !items.length || items.length > 50 || items.some(i => typeof i?.productId !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(i.productId))) throw new HttpsError('invalid-argument', 'Invalid items.');
  await rateLimit(`order:${request.auth.uid}`, 20, 60 * 1000);
  const orderId = digest(`${request.auth.uid}:${requestId}`);
  const orderRef = db.collection('orders').doc(orderId);
  const businessRef = db.collection('settings').doc('business');
  return db.runTransaction(async tx => {
    if ((await tx.get(orderRef)).exists) return {orderId};
    const refs = items.map(i => db.collection('products').doc(i.productId));
    const [businessSnapshot, ...snapshots] = await tx.getAll(businessRef, ...refs);
    let result;
    try { result = quote(items, snapshots.map(s => s.data()), pincode, businessSnapshot.data()); } catch (e) { throw new HttpsError('failed-precondition', e.message); }
    const business = businessSnapshot.data() || {};
    const methods = paymentOptions(business);
    const paymentMethod = requestedPaymentMethod || business.defaultPaymentMethod || 'direct_vendor';
    if (typeof paymentMethod !== 'string' || methods[paymentMethod] !== true) throw new HttpsError('failed-precondition', 'This payment method is not currently available.');
    const paymentStatus = paymentMethod === 'platform_collected' ? 'pending_platform_collection' : paymentMethod === 'cash_on_delivery' ? 'pending_cash_on_delivery' : 'pending_vendor_direct';
    tx.create(orderRef, {userId: request.auth.uid, ...result, shopIds: [...new Set(result.lines.map(line => line.shopId).filter(Boolean))], pincode, address: address.trim(), status: 'submitted', paymentMethod, paymentStatus, createdAt: FieldValue.serverTimestamp()});
    refs.forEach((ref, i) => tx.update(ref, {stock: snapshots[i].data().stock - items[i].quantity}));
    return {orderId};
  });
});
exports.createComplaint = onCall(options, async request => {
  const uid = requireUser(request);
  const {orderId, productId, vendorId, subject, description} = request.data || {};
  if (typeof subject !== 'string' || subject.trim().length < 3 || subject.length > 160 || typeof description !== 'string' || description.trim().length < 5 || description.length > 3000) throw new HttpsError('invalid-argument', 'Provide a subject and description.');
  if (![orderId, productId, vendorId].some(value => typeof value === 'string' && value.length > 0)) throw new HttpsError('invalid-argument', 'Choose an order, product, or vendor.');
  let resolvedVendorId = typeof vendorId === 'string' ? vendorId : null;
  if (orderId) {
    const order = await db.collection('orders').doc(orderId).get();
    if (!order.exists) throw new HttpsError('not-found', 'Order not found.');
    const data = order.data();
    const vendor = (await db.collection('vendors').where('shopId', 'in', data.shopIds || ['__none__']).limit(1).get()).docs[0];
    resolvedVendorId = vendor?.id || resolvedVendorId;
    if (data.userId !== uid && !data.shopIds?.includes((await db.collection('vendors').doc(uid).get()).data()?.shopId)) throw new HttpsError('permission-denied', 'You cannot complain about this order.');
  }
  const complaintRef = db.collection('complaints').doc();
  const complaint = {customerId: uid, vendorId: resolvedVendorId, orderId: orderId || null, productId: productId || null, subject: subject.trim(), status: 'open', createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()};
  await complaintRef.set(complaint);
  await complaintRef.collection('messages').add({authorId: uid, authorRole: 'customer', body: description.trim(), createdAt: FieldValue.serverTimestamp()});
  return {complaintId: complaintRef.id};
});
exports.addComplaintMessage = onCall(options, async request => {
  const uid = requireUser(request);
  const {complaintId, body} = request.data || {};
  if (typeof complaintId !== 'string' || typeof body !== 'string' || body.trim().length < 1 || body.length > 3000) throw new HttpsError('invalid-argument', 'Provide a complaint message.');
  const complaintRef = db.collection('complaints').doc(complaintId);
  const complaint = (await complaintRef.get()).data();
  if (!complaint || complaint.status === 'closed') throw new HttpsError('failed-precondition', 'This complaint is closed.');
  const vendor = (await db.collection('vendors').doc(uid).get()).data();
  const allowed = complaint.customerId === uid || complaint.vendorId === uid || vendor?.shopId === complaint.vendorId;
  if (!allowed && request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'You cannot reply to this complaint.');
  await complaintRef.collection('messages').add({authorId: uid, authorRole: request.auth.token.admin === true ? 'admin' : complaint.customerId === uid ? 'customer' : 'vendor', body: body.trim(), createdAt: FieldValue.serverTimestamp()});
  await complaintRef.update({updatedAt: FieldValue.serverTimestamp()});
  return {sent: true};
});
exports.reviewComplaint = onCall(options, async request => {
  requireAdmin(request);
  const {complaintId, status, resolution} = request.data || {};
  if (typeof complaintId !== 'string' || !['open', 'in_review', 'resolved', 'closed'].includes(status) || typeof resolution !== 'string' || resolution.length > 1000) throw new HttpsError('invalid-argument', 'Provide a valid complaint decision.');
  await db.collection('complaints').doc(complaintId).update({status, resolution: resolution.trim(), reviewedBy: request.auth.uid, updatedAt: FieldValue.serverTimestamp()});
  await db.collection('complaints').doc(complaintId).collection('messages').add({authorId: request.auth.uid, authorRole: 'admin', body: resolution.trim() || `Status changed to ${status}.`, createdAt: FieldValue.serverTimestamp()});
  return {status};
});
exports.registerVendor = onCall(options, async request => {
  const uid = requireUser(request);
  const data = request.data || {};
  if (typeof data.name !== 'string' || data.name.trim().length < 2 || data.name.length > 120) throw new HttpsError('invalid-argument', 'Provide a shop name.');
  const applicationRef = db.collection('vendorApplications').doc(uid);
  const existing = await applicationRef.get();
  if (existing.exists && existing.data().status && existing.data().status !== 'rejected') throw new HttpsError('already-exists', 'This vendor application is already under review.');
  await applicationRef.set({
    vendorId: uid, name: data.name.trim(), description: String(data.description || '').trim().slice(0, 1000),
    address: String(data.address || '').trim().slice(0, 500), status: 'pending', updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {status: 'pending'};
});
exports.approveVendor = onCall(options, async request => {
  requireAdmin(request);
  const {vendorId, approved, reason = '', feeRequired = false, feeAmount = 0} = request.data || {};
  if (typeof vendorId !== 'string' || typeof approved !== 'boolean') throw new HttpsError('invalid-argument', 'Provide vendor and decision.');
  let fee;
  try { fee = vendorFee(feeRequired, feeAmount); } catch (error) { throw new HttpsError('invalid-argument', error.message); }
  const applicationRef = db.collection('vendorApplications').doc(vendorId);
  const application = await applicationRef.get();
  if (!application.exists) throw new HttpsError('not-found', 'Vendor application not found.');
  const data = application.data();
  const batch = db.batch();
  const nextStatus = !approved ? 'rejected' : fee.required ? 'payment_required' : 'approved';
  batch.set(applicationRef, {status: nextStatus, feeRequired: fee.required, feeAmount: fee.amount, feePaymentStatus: fee.required ? 'not_started' : 'not_required', decisionReason: String(reason).slice(0, 500), decidedAt: FieldValue.serverTimestamp()}, {merge: true});
  if (approved && !fee.required) {
    const vendorRef = db.collection('vendors').doc(vendorId);
    batch.set(vendorRef, {vendorId, name: data.name, shopId: vendorId, verified: false, status: 'approved', updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  }
  await batch.commit();
  return {status: nextStatus, feeAmount: fee.amount};
});
exports.submitVendorFeePayment = onCall(options, async request => {
  const uid = requireUser(request);
  const {paymentReference = ''} = request.data || {};
  const applicationRef = db.collection('vendorApplications').doc(uid);
  const application = (await applicationRef.get()).data();
  if (!application || application.status !== 'payment_required' || application.feeRequired !== true) throw new HttpsError('failed-precondition', 'Vendor fee payment is not currently required.');
  if (typeof paymentReference !== 'string' || paymentReference.trim().length < 2 || paymentReference.length > 200) throw new HttpsError('invalid-argument', 'Provide a payment reference.');
  await applicationRef.update({status: 'payment_submitted', feePaymentStatus: 'submitted', paymentReference: paymentReference.trim(), paymentSubmittedAt: FieldValue.serverTimestamp()});
  return {status: 'payment_submitted'};
});
exports.confirmVendorFeePayment = onCall(options, async request => {
  requireAdmin(request);
  const {vendorId, paid} = request.data || {};
  if (typeof vendorId !== 'string' || typeof paid !== 'boolean') throw new HttpsError('invalid-argument', 'Provide vendor and payment decision.');
  const applicationRef = db.collection('vendorApplications').doc(vendorId);
  const application = await applicationRef.get();
  if (!application.exists || application.data().status !== 'payment_submitted') throw new HttpsError('failed-precondition', 'No submitted vendor fee payment exists.');
  const batch = db.batch();
  batch.set(applicationRef, {status: paid ? 'approved' : 'payment_required', feePaymentStatus: paid ? 'paid' : 'rejected', paymentDecisionAt: FieldValue.serverTimestamp()}, {merge: true});
  if (paid) {
    const data = application.data();
    batch.set(db.collection('vendors').doc(vendorId), {vendorId, name: data.name, shopId: vendorId, verified: false, status: 'approved', updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  }
  await batch.commit();
  return {status: paid ? 'approved' : 'payment_required'};
});
exports.verifyVendorShop = onCall(options, async request => {
  requireAdmin(request);
  const {vendorId, shopId, latitude, longitude, radiusKm} = request.data || {};
  requireCoordinate(latitude, 'latitude'); requireCoordinate(longitude, 'longitude');
  if (typeof vendorId !== 'string' || typeof shopId !== 'string' || !Number.isFinite(radiusKm) || radiusKm <= 0 || radiusKm > 100) throw new HttpsError('invalid-argument', 'Provide valid shop verification details.');
  await db.collection('vendors').doc(vendorId).set({shopId, verified: true, latitude, longitude, radiusKm, verifiedAt: FieldValue.serverTimestamp()}, {merge: true});
  await db.collection('shops').doc(shopId).set({ownerId: vendorId, verified: true, latitude, longitude, radiusKm}, {merge: true});
  return {verified: true};
});
exports.submitVendorChange = onCall(options, async request => {
  const uid = requireUser(request);
  const {type, collection, docId, changes} = request.data || {};
  const allowedCollection = type === 'shop' ? 'shops' : 'products';
  if (collection !== allowedCollection || typeof docId !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(docId)) throw new HttpsError('invalid-argument', 'Invalid change target.');
  const safeChanges = publicChangeFields(type, changes);
  const vendor = (await db.collection('vendors').doc(uid).get()).data();
  if (!vendor || vendor.status !== 'approved' || vendor.verified !== true) throw new HttpsError('permission-denied', 'Your shop must be approved and verified first.');
  const target = db.collection(collection).doc(docId);
  const current = await target.get();
  if (!current.exists || (current.data().ownerId && current.data().ownerId !== uid)) throw new HttpsError('not-found', 'Public item not found.');
  const autoPublish = (await db.collection('settings').doc('business').get()).data()?.autoPublishVendorChanges === true;
  const change = {vendorId: uid, vendorName: vendor.name, type, collection, docId, oldValue: Object.fromEntries(Object.keys(safeChanges).map(key => [key, current.data()[key] ?? null])), newValue: safeChanges, status: autoPublish ? 'approved' : 'pending', updatedAt: FieldValue.serverTimestamp()};
  if (autoPublish) await target.set({...safeChanges, ownerId: uid, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  else await db.collection('vendorChanges').add(change);
  return {status: change.status};
});
exports.reviewVendorChange = onCall(options, async request => {
  requireAdmin(request);
  const {changeId, approved, reason = ''} = request.data || {};
  if (typeof changeId !== 'string' || typeof approved !== 'boolean') throw new HttpsError('invalid-argument', 'Provide change and decision.');
  const changeRef = db.collection('vendorChanges').doc(changeId);
  return db.runTransaction(async tx => {
    const snapshot = await tx.get(changeRef);
    const change = snapshot.data();
    if (!snapshot.exists || change.status !== 'pending') throw new HttpsError('failed-precondition', 'This change was already reviewed.');
    tx.update(changeRef, {status: approved ? 'approved' : 'rejected', decisionReason: String(reason).slice(0, 500), decidedAt: FieldValue.serverTimestamp()});
    if (approved) tx.set(db.collection(change.collection).doc(change.docId), {...change.newValue, ownerId: change.vendorId, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return {status: approved ? 'approved' : 'rejected'};
  });
});
exports.issuePurchaseCode = onCall(options, async request => {
  const uid = requireUser(request);
  const {orderId, latitude, longitude} = request.data || {};
  requireCoordinate(latitude, 'latitude'); requireCoordinate(longitude, 'longitude');
  if (typeof orderId !== 'string') throw new HttpsError('invalid-argument', 'Provide an order.');
  const order = await db.collection('orders').doc(orderId).get();
  if (!order.exists || order.data().userId !== uid || order.data().status !== 'fulfilled') throw new HttpsError('failed-precondition', 'Only fulfilled orders can be verified.');
  const code = String(randomInt(100000, 1000000));
  const codeRef = db.collection('purchaseCodes').doc(digest(`${uid}:${orderId}:${code}`));
  await codeRef.set({orderId, customerId: uid, latitude, longitude, expiresAt: Date.now() + 5 * 60 * 1000, used: false, createdAt: FieldValue.serverTimestamp()});
  return {code, expiresInSeconds: 300};
});
exports.redeemPurchaseCode = onCall(options, async request => {
  const vendorId = requireUser(request);
  const {code, orderId, latitude, longitude} = request.data || {};
  requireCoordinate(latitude, 'latitude'); requireCoordinate(longitude, 'longitude');
  if (typeof code !== 'string' || !/^\d{6}$/.test(code) || typeof orderId !== 'string') throw new HttpsError('invalid-argument', 'Provide a valid code and order.');
  const vendor = (await db.collection('vendors').doc(vendorId).get()).data();
  if (!vendor || vendor.status !== 'approved' || vendor.verified !== true) throw new HttpsError('permission-denied', 'Verified vendor access required.');
  // Codes are customer-bound; find the matching short-lived code without exposing it in reads.
  const matches = await db.collection('purchaseCodes').where('orderId', '==', orderId).where('used', '==', false).limit(10).get();
  let matchedRef, matched;
  for (const candidate of matches.docs) if (candidate.id.endsWith(digest(`${candidate.data().customerId}:${orderId}:${code}`).slice(-64))) { matchedRef = candidate.ref; matched = candidate.data(); break; }
  if (!matchedRef || !matched || matched.expiresAt < Date.now()) throw new HttpsError('failed-precondition', 'Code is invalid or expired.');
  const shop = (await db.collection('shops').doc(vendor.shopId).get()).data();
  const radius = Number(shop?.radiusKm || vendor.radiusKm);
  if (!validCoordinate(shop?.latitude) || !validCoordinate(shop?.longitude) || !Number.isFinite(radius) || distanceKm(latitude, longitude, shop.latitude, shop.longitude) > radius) throw new HttpsError('permission-denied', 'You must be inside the verified shop radius.');
  await db.runTransaction(async tx => {
    const fresh = await tx.get(matchedRef);
    if (!fresh.exists || fresh.data().used || fresh.data().expiresAt < Date.now()) throw new HttpsError('failed-precondition', 'Code is invalid or already used.');
    tx.update(matchedRef, {used: true, usedBy: vendorId, usedAt: FieldValue.serverTimestamp()});
    tx.set(db.collection('verifiedPurchases').doc(`${matched.customerId}_${orderId}`), {customerId: matched.customerId, vendorId, shopId: vendor.shopId, orderId, status: 'verified', verifiedAt: FieldValue.serverTimestamp()}, {merge: true});
  });
  return {verified: true};
});
exports.submitVerifiedReview = onCall(options, async request => {
  const uid = requireUser(request);
  const {productId, rating, text, name} = request.data || {};
  if (typeof productId !== 'string' || !Number.isInteger(rating) || rating < 1 || rating > 5 || typeof text !== 'string' || !text.trim() || text.length > 1000) throw new HttpsError('invalid-argument', 'Provide a valid review.');
  const purchases = await db.collection('verifiedPurchases').where('customerId', '==', uid).where('status', '==', 'verified').limit(20).get();
  let purchasedProduct = false;
  for (const purchase of purchases.docs) {
    const order = await db.collection('orders').doc(purchase.data().orderId).get();
    if (order.exists && order.data().lines?.some(line => line.productId === productId)) { purchasedProduct = true; break; }
  }
  if (!purchasedProduct) throw new HttpsError('permission-denied', 'Only verified purchases of this product can be reviewed.');
  const reviewRef = db.collection('products').doc(productId).collection('reviews').doc(uid);
  if ((await reviewRef.get()).exists) throw new HttpsError('already-exists', 'You already rated this product.');
  await reviewRef.create({userId: uid, name: String(name || '').slice(0, 100), rating, text: text.trim(), verifiedPurchase: true, updatedAt: FieldValue.serverTimestamp()});
  const previousReviews = await db.collectionGroup('reviews').where('userId', '==', uid).limit(4).get();
  if (previousReviews.size >= 3) await db.collection('suspiciousReviews').add({userId: uid, productId, reason: 'Multiple verified reviews in a short period', createdAt: FieldValue.serverTimestamp(), reviewed: false});
  return {created: true};
});
exports.updateVendorOrder = onCall(options, async request => {
  const uid = requireUser(request);
  const {orderId, status} = request.data || {};
  if (typeof orderId !== 'string' || !['confirmed', 'fulfilled', 'cancelled'].includes(status)) throw new HttpsError('invalid-argument', 'Provide a valid order status.');
  const vendor = (await db.collection('vendors').doc(uid).get()).data();
  const orderRef = db.collection('orders').doc(orderId);
  const order = await orderRef.get();
  if (!vendor || vendor.status !== 'approved' || !order.exists || !order.data().shopIds?.includes(vendor.shopId)) throw new HttpsError('permission-denied', 'You cannot update this order.');
  await orderRef.update({status});
  return {status};
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
