'use strict';
const {onDocumentUpdated, onDocumentWritten} = require('firebase-functions/v2/firestore');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {getAuth} = require('firebase-admin/auth');
const {createHash} = require('node:crypto');
const {active, priceDrop, price, priceAlertKey, offerNotifiable, offerKey, offerCopy, INTEREST_WINDOW_MS, PRICE_ALERT_WINDOW_MS} = require('./notifications-domain');
const {flagOff} = require('./domain');
const {requireAdminSession} = require('./admin-session');
const db = getFirestore();
const hash = value => createHash('sha256').update(value).digest('hex');
async function* pages(query) {
  let cursor;
  do {
    const page = await (cursor ? query.startAfter(cursor) : query).limit(200).get();
    for (const doc of page.docs) yield doc;
    cursor = page.size === 200 ? page.docs.at(-1) : null;
  } while (cursor);
}
// The Firebase emulators cannot deliver real pushes. With PUSH_DRY_RUN=true
// (only ever set through functions/.env.local for local testing) every message
// that would be sent is recorded in _pushDryRun instead, so targeting and
// duplicate suppression can still be verified end to end.
async function deliver(uid, eventKey, tokens, notification, data) {
  if (process.env.PUSH_DRY_RUN === 'true') {
    await db.collection('_pushDryRun').add({uid, eventKey, notification, data, tokenCount: tokens.size, createdAt: FieldValue.serverTimestamp()});
    return;
  }
  for (let i = 0; i < tokens.size; i += 500) {
    const batch = tokens.docs.slice(i, i + 500);
    const result = await getMessaging().sendEachForMulticast({
      tokens: batch.map(d => d.data().token), notification, data,
      webpush: {fcmOptions: {link: 'https://e-commerce-app-a3897.web.app/'}},
      android: {priority: 'high'},
      apns: {payload: {aps: {sound: 'default'}}},
    });
    for (let j = 0; j < result.responses.length; j++) {
      const code = result.responses[j].error?.code;
      if (['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(code)) await batch[j].ref.delete();
    }
    if (result.failureCount) console.warn('Some push deliveries failed', {failureCount: result.failureCount});
  }
}
/// Returns 'sent', 'duplicate', 'not-subscribed' or 'no-token'. [reclaimAfterMs]
/// lets the very same alert be sent again once that much time has passed.
async function send(uid, eventKey, notification, data, {reclaimAfterMs = 0} = {}) {
  if (!(await db.collection('notificationSubscribers').doc(uid).get()).data()?.enabled) return 'not-subscribed';
  const tokens = await db.collection('users').doc(uid).collection('pushTokens').get();
  if (tokens.empty) return 'no-token';
  // Claim before dispatch: duplicate event deliveries never send the same alert twice.
  // A crash after claiming may drop an alert; commerce writes are never retried by this job.
  const claim = db.collection('_notificationDeliveries').doc(hash(`${uid}:${eventKey}`));
  try { await claim.create({createdAt: FieldValue.serverTimestamp()}); }
  catch (error) {
    if (error.code !== 6) throw error;
    if (!reclaimAfterMs) return 'duplicate';
    const reclaimed = await db.runTransaction(async tx => {
      const at = (await tx.get(claim)).data()?.createdAt?.toMillis?.() ?? 0;
      if (Date.now() - at < reclaimAfterMs) return false;
      tx.update(claim, {createdAt: FieldValue.serverTimestamp()});
      return true;
    });
    if (!reclaimed) return 'duplicate';
  }
  await deliver(uid, eventKey, tokens, notification, data);
  return 'sent';
}
const priceCopy = (product, value, pincode) => ({
  title: 'Price dropped', body: `${product.name || 'An item you viewed'} is now ₹${value}${pincode ? ` in ${pincode}` : ''}.`,
});
async function noteAlert(viewerRef, value) {
  await viewerRef.set({lastAlertPrice: value, lastAlertAt: FieldValue.serverTimestamp(), alertCount: FieldValue.increment(1)}, {merge: true});
}
/// One interested customer's alert. The dedupe key is per customer, product,
/// pincode and price, so the automatic and the manual path can never both send
/// the same alert, and re-saving a product never repeats it.
async function alertViewer(productId, product, viewer, value) {
  const view = viewer.data();
  const status = await send(viewer.id, priceAlertKey(productId, view.pincode, value), priceCopy(product, value, view.pincode), {type: 'priceDrop', productId}, {reclaimAfterMs: PRICE_ALERT_WINDOW_MS});
  if (status === 'sent') await noteAlert(viewer.ref, value);
  return status;
}
exports.notifyPriceDrop = onDocumentUpdated({document: 'products/{productId}', region: 'asia-south1', maxInstances: 2}, async event => {
  const before = event.data.before.data(), after = event.data.after.data();
  // Ignore unrelated product writes such as stock decrements at checkout.
  if (JSON.stringify([before.price, before.prices]) === JSON.stringify([after.price, after.prices])) return;
  // The admin can switch automatic alerts off; manual sending stays available.
  if (flagOff(((await db.collection('settings').doc('business').get()).data() || {}).priceDropAutoEnabled)) return;
  for await (const viewer of pages(event.data.after.ref.collection('viewers').orderBy('__name__'))) {
    const view = viewer.data();
    if (!view.lastViewedAt || view.lastViewedAt.toMillis() < Date.now() - INTEREST_WINDOW_MS) continue;
    const value = priceDrop(before, after, view.pincode);
    if (value !== null) await alertViewer(event.params.productId, after, viewer, value);
  }
});
// One account (the admin changing status) notifying exactly one other
// account (the customer who placed that order) — not a broadcast.
const orderStatusCopy = {
  confirmed: 'Your order has been confirmed.',
  fulfilled: 'Your order has been fulfilled.',
  cancelled: 'Your order was cancelled and any charged stock has been restored.',
};
exports.notifyOrderStatus = onDocumentUpdated({document: 'orders/{orderId}', region: 'asia-south1', maxInstances: 5}, async event => {
  const before = event.data.before.data(), after = event.data.after.data();
  const body = orderStatusCopy[after.status];
  if (!body || before.status === after.status || !after.userId) return;
  await send(after.userId, event.id, {title: 'Order update', body}, {
    type: 'orderStatus', orderId: event.params.orderId, status: after.status,
  });
});
// ---- Offer notifications to every subscriber.
// Each promotion is claimed once per go-live time (notifiedKey on the promotion itself), so the
// scheduled check reads only the promotions, never every subscriber, and a retried run or a later
// edit never notifies twice. The per-customer delivery claim in send() is a second safeguard.
const FAN_OUT = 25; // subscribers processed in parallel
async function fanOutOffer(promotionId, data, eventKey) {
  const notification = offerCopy(data), extra = {type: 'offer', promotionId};
  const counts = {sent: 0, duplicate: 0, noDevice: 0};
  let batch = [];
  const flush = async () => {
    const results = await Promise.all(batch.map(uid => send(uid, eventKey, notification, extra).catch(error => { console.warn('Offer delivery failed', {promotionId, error: String(error).slice(0, 120)}); return 'failed'; })));
    for (const status of results) { if (status === 'sent') counts.sent++; else if (status === 'duplicate') counts.duplicate++; else counts.noDevice++; }
    batch = [];
  };
  for await (const subscriber of pages(db.collection('notificationSubscribers').where('enabled', '==', true).orderBy('__name__'))) {
    batch.push(subscriber.id);
    if (batch.length >= FAN_OUT) await flush();
  }
  if (batch.length) await flush();
  return counts;
}
/// Notifies subscribers about one promotion if it is due. [force] is the admin's manual "send now":
/// it ignores the automatic on/off switch and the per-offer flag, and may repeat at most hourly.
async function releaseOffer(promotionId, {force = false, now = Date.now()} = {}) {
  const ref = db.collection('promotions').doc(promotionId);
  if (!force && flagOff(((await db.collection('settings').doc('business').get()).data() || {}).offerNotificationsEnabled)) return {status: 'disabled'};
  const claimed = await db.runTransaction(async tx => {
    const data = (await tx.get(ref)).data();
    if (!data) return null;
    if (force ? !active(data, now) : !offerNotifiable(data, now)) return {status: 'not-due'};
    const key = offerKey(promotionId, data);
    if (!force && data.notifiedKey === key) return {status: 'already-sent'};
    tx.update(ref, {notifiedKey: key, notifiedAt: FieldValue.serverTimestamp(), notifiedCount: 0});
    return {status: 'claimed', data, key};
  });
  if (!claimed) return {status: 'not-found'};
  if (claimed.status !== 'claimed') return claimed;
  const eventKey = force ? `${claimed.key}:manual:${Math.floor(now / 3600000)}` : claimed.key;
  const counts = await fanOutOffer(promotionId, claimed.data, eventKey);
  await ref.update({notifiedCount: counts.sent});
  return {status: 'sent', ...counts};
}
// An offer goes out as soon as the admin publishes it...
exports.notifyOfferPublished = onDocumentWritten({document: 'promotions/{promotionId}', region: 'asia-south1', maxInstances: 3, timeoutSeconds: 540}, async event => {
  if (!event.data?.after?.exists) return;
  const before = event.data.before?.data(), after = event.data.after.data();
  // Our own bookkeeping writes must not re-trigger.
  if (before && after.notifiedKey !== before.notifiedKey) return;
  await releaseOffer(event.params.promotionId);
});
// ...and this check catches offers whose scheduled start arrives without any edit.
exports.notifyNewOffers = onSchedule({schedule: 'every 15 minutes', region: 'asia-south1', maxInstances: 1, timeoutSeconds: 540}, async () => {
  for await (const offer of pages(db.collection('promotions').orderBy('__name__'))) {
    const data = offer.data();
    if (!offerNotifiable(data) || data.notifiedKey === offerKey(offer.id, data)) continue;
    await releaseOffer(offer.id);
  }
});

// ---- Admin: who is eligible for a product's price alert, and manual sending.
const adminOptions = {region: 'us-central1', maxInstances: 5, invoker: 'public'};
async function requireAdmin(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true || request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
}
async function loadAudience(productId) {
  if (typeof productId !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(productId)) throw new HttpsError('invalid-argument', 'Choose a product.');
  const productRef = db.collection('products').doc(productId);
  const product = (await productRef.get()).data();
  if (!product) throw new HttpsError('not-found', 'Product not found.');
  const viewers = [];
  for await (const viewer of pages(productRef.collection('viewers').orderBy('__name__'))) { viewers.push(viewer); if (viewers.length >= 500) break; }
  const emails = new Map();
  for (let i = 0; i < viewers.length; i += 100) {
    const found = await getAuth().getUsers(viewers.slice(i, i + 100).map(v => ({uid: v.id})));
    for (const user of found.users) emails.set(user.uid, user.email || '');
  }
  const now = Date.now();
  const rows = [];
  for (const viewer of viewers) {
    const view = viewer.data(), uid = viewer.id;
    const subscribed = (await db.collection('notificationSubscribers').doc(uid).get()).data()?.enabled === true;
    const tokens = (await db.collection('users').doc(uid).collection('pushTokens').count().get()).data().count;
    const recent = !!view.lastViewedAt && view.lastViewedAt.toMillis() >= now - INTEREST_WINDOW_MS;
    const value = price(product, view.pincode);
    let notified = false;
    if (value !== null) {
      const claim = (await db.collection('_notificationDeliveries').doc(hash(`${uid}:${priceAlertKey(productId, view.pincode, value)}`)).get()).data();
      notified = !!claim?.createdAt && now - claim.createdAt.toMillis() < PRICE_ALERT_WINDOW_MS;
    }
    rows.push({
      uid, email: emails.get(uid) || '', pincode: view.pincode || '', viewCount: Number(view.viewCount) || 1,
      lastViewedAt: view.lastViewedAt?.toMillis() ?? null, subscribed, tokens, recent, currentPrice: value,
      alertedPrice: view.lastAlertPrice ?? null, alertedAt: view.lastAlertAt?.toMillis() ?? null, alertCount: Number(view.alertCount) || 0,
      alreadyNotified: notified, eligible: subscribed && tokens > 0 && recent && value !== null,
    });
  }
  rows.sort((a, b) => b.viewCount - a.viewCount);
  return {productRef, product, viewers, rows};
}
exports.priceAlertAudience = onCall(adminOptions, async request => {
  await requireAdmin(request);
  const {product, rows} = await loadAudience(request.data?.productId);
  return {product: {id: request.data.productId, name: product.name || '', price: product.price ?? null}, rows, truncated: rows.length >= 500};
});
exports.sendPriceDropAlerts = onCall(adminOptions, async request => {
  await requireAdmin(request);
  const {productId, uids} = request.data || {};
  if (uids !== undefined && (!Array.isArray(uids) || uids.length > 500 || uids.some(u => typeof u !== 'string'))) throw new HttpsError('invalid-argument', 'Invalid customer list.');
  const {product, viewers, rows} = await loadAudience(productId);
  const summary = {sent: 0, duplicate: 0, ineligible: 0, results: []};
  for (const row of rows) {
    if (uids && !uids.includes(row.uid)) continue;
    let status = 'ineligible';
    if (row.eligible) status = await alertViewer(productId, product, viewers.find(v => v.id === row.uid), row.currentPrice);
    if (status === 'sent' || status === 'duplicate') summary[status]++; else summary.ineligible++;
    summary.results.push({uid: row.uid, status});
  }
  return summary;
});

// ---- Admin: send an offer to every subscriber now, and see how many that is.
exports.sendOfferNotification = onCall({...adminOptions, timeoutSeconds: 540}, async request => {
  await requireAdmin(request);
  const {promotionId} = request.data || {};
  if (typeof promotionId !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(promotionId)) throw new HttpsError('invalid-argument', 'Choose an offer.');
  const result = await releaseOffer(promotionId, {force: true});
  if (result.status === 'not-found') throw new HttpsError('not-found', 'Offer not found.');
  if (result.status === 'not-due') throw new HttpsError('failed-precondition', 'Only an offer that is live right now can be sent.');
  return result;
});
exports.offerAudienceSize = onCall(adminOptions, async request => {
  await requireAdmin(request);
  return {subscribers: (await db.collection('notificationSubscribers').where('enabled', '==', true).count().get()).data().count};
});
// Exposed for reuse by other function modules (e.g. functions/storage-maintenance.js), which
// otherwise only see the onCall/onSchedule handlers above via index.js's Object.assign(exports, ...).
exports._internal = {send, pages, hash};
