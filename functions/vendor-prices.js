'use strict';
// A vendor's item price stays until the vendor changes or deletes it (owner, 16 Nov 2026): it never runs out and never hides by
// itself. The admin's post duration (post-duration.js) no longer applies to item prices. What a price carries:
//   priceSetAt        when the vendor (or staff, for a staff-added item) set the price: the "Today's rate" tick shows for 24 hours
//                     from it, or from the vendor's "Yes, same rates" (shops/<id>.ratesConfirmedAt, functions/vendor-rates.js)
// Items saved before carry priceExpiresAt / endsAt (and priceExpired when the old 15-minute job removed the price): they are cleared
// once by clearOldPriceEnds, run by the 15-minute job's post-duration piece (post-duration.js), with no extra reads afterwards.
const {FieldValue} = require('firebase-admin/firestore');

/// The fields a fresh vendor price carries.
function freshPriceFields(now = Date.now()) {
  return {priceSetAt: new Date(now).toISOString(), priceExpired: false};
}

/// For an update of an item's price (never a new document): the old end of the price goes.
const priceEndRemoved = () => ({priceExpiresAt: FieldValue.delete(), endsAt: FieldValue.delete()});

/// Once: the items that still carry the old price end lose it (their end, and the "expired" mark of a price the old job removed), so
/// they show again; a removed price shows "Local vendor not updated item price" until the vendor sets one. Returns how many changed.
async function clearOldPriceEnds(db) {
  const due = await db.collection('products').where('priceExpiresAt', '>', '').get();
  let batch = db.batch(), pending = 0, changed = 0;
  for (const doc of due.docs) {
    const item = doc.data();
    // An exclusive item keeps its own end (expiresAt / endsAt); only the price's end goes.
    const sameEnd = item.endsAt === item.priceExpiresAt;
    batch.update(doc.ref, {priceExpiresAt: FieldValue.delete(), priceExpired: FieldValue.delete(), ...(sameEnd ? {endsAt: FieldValue.delete()} : {})});
    changed++;
    if (++pending === 400) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (pending) await batch.commit();
  return changed;
}

module.exports = {freshPriceFields, priceEndRemoved, clearOldPriceEnds};
