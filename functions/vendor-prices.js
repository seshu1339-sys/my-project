'use strict';
// A vendor's item price lasts 24 hours (set when the item is saved or the price is changed, see submitVendorChange in index.js:
// priceSetAt / priceExpiresAt, and endsAt so the site hides the item and an order is refused the moment it passes). Every half hour
// this removes the expired prices, so the vendor's app shows "price expired, enter today's price" until the vendor sets a new one.
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const db = getFirestore();

const VENDOR_PRICE_VALID_MS = 24 * 60 * 60 * 1000;

/// The fields a fresh vendor price carries: when it was set, when it expires (also endsAt, which the site and placeOrder already obey).
function freshPriceFields(now = Date.now()) {
  const expires = new Date(now + VENDOR_PRICE_VALID_MS).toISOString();
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

exports.expireVendorPrices = onSchedule({schedule: 'every 30 minutes', region: 'asia-south1', maxInstances: 1, timeoutSeconds: 300}, () => expireVendorPrices());

exports.freshPriceFields = freshPriceFields;
exports.expireVendorPricesNow = expireVendorPrices;
exports.VENDOR_PRICE_VALID_MS = VENDOR_PRICE_VALID_MS;
