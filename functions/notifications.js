'use strict';
const {onDocumentUpdated} = require('firebase-functions/v2/firestore');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {createHash} = require('node:crypto');
const {active, priceDrop} = require('./notifications-domain');
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
async function send(uid, eventKey, notification, data) {
  if (!(await db.collection('notificationSubscribers').doc(uid).get()).data()?.enabled) return;
  const tokens = await db.collection('users').doc(uid).collection('pushTokens').get();
  if (tokens.empty) return;
  // Claim before dispatch: duplicate event deliveries never send the same alert twice.
  // A crash after claiming may drop an alert; commerce writes are never retried by this job.
  const claim = db.collection('_notificationDeliveries').doc(hash(`${uid}:${eventKey}`));
  try { await claim.create({createdAt: FieldValue.serverTimestamp()}); }
  catch (error) { if (error.code === 6) return; throw error; }
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
exports.notifyPriceDrop = onDocumentUpdated({document: 'products/{productId}', region: 'asia-south1', maxInstances: 2}, async event => {
  const before = event.data.before.data(), after = event.data.after.data();
  // Ignore unrelated product writes such as stock decrements at checkout.
  if (JSON.stringify([before.price, before.prices]) === JSON.stringify([after.price, after.prices])) return;
  for await (const viewer of pages(event.data.after.ref.collection('viewers').orderBy('__name__'))) {
    const view = viewer.data();
    if (!view.lastViewedAt || view.lastViewedAt.toMillis() < Date.now() - 90 * 86400000) continue;
    const value = priceDrop(before, after, view.pincode);
    if (value !== null) await send(viewer.id, event.id, {
      title: 'Price dropped', body: `${after.name || 'An item you viewed'} is now ₹${value}${view.pincode ? ` in ${view.pincode}` : ''}.`,
    }, {type: 'priceDrop', productId: event.params.productId});
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
// Polling also catches offers whose scheduled start arrives without a document edit.
exports.notifyNewOffers = onSchedule({schedule: 'every 15 minutes', region: 'asia-south1', maxInstances: 1, timeoutSeconds: 540}, async () => {
  for await (const offer of pages(db.collection('promotions').orderBy('__name__'))) {
    const data = offer.data();
    if (!active(data)) continue;
    const key = `offer:${offer.id}:${data.startsAt || 'initial'}`;
    for await (const subscriber of pages(db.collection('notificationSubscribers').orderBy('__name__'))) {
      if (subscriber.data().enabled) await send(subscriber.id, key, {
        title: 'New offer', body: data.name || data.title || 'A new offer is available. Open the shop to explore.',
      }, {type: 'offer', promotionId: offer.id});
    }
  }
});
