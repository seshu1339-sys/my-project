'use strict';
// A vendor's item price lasts the admin's post duration, 24 hours by default (post-duration.js; set when the item is saved or the price is changed, see submitVendorChange in index.js:
// priceSetAt / priceExpiresAt, and endsAt so the site hides the item and an order is refused the moment it passes). Every half hour
// this removes the expired prices, so the vendor's app shows "price expired, enter today's price" until the vendor sets a new one.
// The schedule is in functions/scheduled-jobs.js (one 15-minute and one hourly job for all).
const {task} = require('./task');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const db = getFirestore();

const VENDOR_PRICE_VALID_MS = 24 * 60 * 60 * 1000;

/// The fields a fresh vendor price carries: when it was set, when it expires (also endsAt, which the site and placeOrder already obey).
/// durationMs is the admin's post duration (post-duration.js, 24 hours when not set).
function freshPriceFields(now = Date.now(), durationMs = VENDOR_PRICE_VALID_MS) {
  const expires = new Date(now + durationMs).toISOString();
  return {priceSetAt: new Date(now).toISOString(), priceExpiresAt: expires, endsAt: expires, priceExpired: false};
}

/// Removes the price of every vendor item whose 24 hours are over. Returns how many prices were removed.
async function expireVendorPrices(now = Date.now()) {
  const due = await db.collection('products').where('priceExpiresAt', '<=', new Date(now).toISOString()).get();
  let batch = db.batch(), pending = 0, removed = 0;
  for (const doc of due.docs) {
    const item = doc.data();
    if (item.priceExpired === true && item.price === undefined) continue;
    batch.update(doc.ref, {price: FieldValue.delete(), priceExpired: true, priceExpiredAt: FieldValue.serverTimestamp()});
    removed++;
    if (++pending === 400) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (pending) await batch.commit();
  return removed;
}

exports.expireVendorPrices = task(() => expireVendorPrices());

exports.freshPriceFields = freshPriceFields;
exports.expireVendorPricesNow = expireVendorPrices;
exports.VENDOR_PRICE_VALID_MS = VENDOR_PRICE_VALID_MS;
