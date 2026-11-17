'use strict';
// "Today's rate" (owner, 16 Nov 2026). The customer sees a small green tick "Today's rate" next to a vendor's prices for 24 hours from
// the moment the vendor set a price (products.priceSetAt) or tapped "Yes, same rates" (ratesConfirmedAt). The check runs on the phone
// by comparing times; nothing is read for it.
//   confirmTodaysRates  vendor  -> ONE field on the vendor (vendors/<uid>.ratesConfirmedAt) and its copy on the shop
//                                  (shops/<shopId>.ratesConfirmedAt, which the customer app already loads), never a write per item
//   rateReminder        task    -> once a day at the admin's hour (Business Profile: rateReminder on/off, rateReminderHour, 8 by
//                                  default), ONE FCM topic message to every vendor app ("vendors" topic): "Are today's rates the same?".
//                                  Run by the hourly job (scheduled-jobs.js): one document read an hour, no per-vendor reads.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {requireRole} = require('./role-auth');
const {flagOff} = require('./domain');
const {task} = require('./task');

const VENDOR_TOPIC = 'vendors';
const DEFAULT_REMINDER_HOUR = 8;
const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};

/// The admin's reminder: on unless switched off, at a whole hour of the day in India (0-23, 8 by default).
function reminderSettings(business = {}) {
  const raw = business.rateReminderHour;
  const hour = raw === '' || raw === null || raw === undefined ? NaN : Number(raw);
  return {on: !flagOff(business.rateReminder), hour: Number.isInteger(hour) && hour >= 0 && hour <= 23 ? hour : DEFAULT_REMINDER_HOUR};
}

/// The vendor confirms that today's rates are the same: one write on the vendor and one on the shop.
async function confirmRates(db, uid, now = Date.now()) {
  const vendor = (await db.collection('vendors').doc(uid).get()).data();
  if (!vendor || vendor.status !== 'approved') throw Error('Your vendor application must be approved first.');
  const at = new Date(now).toISOString();
  const batch = db.batch();
  batch.set(db.collection('vendors').doc(uid), {ratesConfirmedAt: at}, {merge: true});
  if (vendor.shopId) batch.set(db.collection('shops').doc(vendor.shopId), {ratesConfirmedAt: at}, {merge: true});
  await batch.commit();
  return {ratesConfirmedAt: at};
}

/// Sends the reminder when this is the admin's hour in India. [send] is replaced in the tests.
async function sendRateReminder(db, now = Date.now(), send = message => getMessaging().send(message)) {
  const {on, hour} = reminderSettings((await db.collection('settings').doc('business').get()).data() || {});
  if (!on || new Date(now + IST_OFFSET_MS).getUTCHours() !== hour) return false;
  await send({
    topic: VENDOR_TOPIC,
    notification: {title: 'Are today\'s rates the same?', body: 'Tap "Yes, same rates" so customers see the Today\'s rate tick, or change a price.'},
    data: {open: 'confirmRates'},
    android: {priority: 'high'},
  });
  return true;
}

exports.confirmTodaysRates = onCall(options, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const uid = requireRole(request, ['vendor']);
  try { return await confirmRates(getFirestore(), uid); } catch (error) { throw new HttpsError('failed-precondition', error.message); }
});
exports.rateReminder = task(() => sendRateReminder(getFirestore()));
exports._vendorRates = {confirmRates, sendRateReminder, reminderSettings, VENDOR_TOPIC, DEFAULT_REMINDER_HOUR};
