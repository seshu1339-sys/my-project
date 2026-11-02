'use strict';
// Wholesale offers: wholesaleOffers/<id>, made by the administrator and read by active Premium vendors (firestore.rules).
const {Timestamp} = require('firebase-admin/firestore');
const {validateWholesale} = require('./rules');

const offers = db => db.collection('wholesaleOffers');
const ID = /^[a-zA-Z0-9_-]{1,128}$/;

/// Adds an offer, or edits one with offerId.
async function saveOffer(db, data, now = Date.now()) {
  const {validUntil, ...fields} = validateWholesale(data, now);
  const at = Timestamp.fromMillis(now);
  const saved = {...fields, validUntil: Timestamp.fromMillis(validUntil), updatedAt: at};
  if (!data.offerId) {
    const ref = offers(db).doc();
    await ref.set({...saved, createdAt: at});
    return {offerId: ref.id};
  }
  if (typeof data.offerId !== 'string' || !ID.test(data.offerId)) throw new Error('Offer not found.');
  const ref = offers(db).doc(data.offerId);
  if (!(await ref.get()).exists) throw new Error('Offer not found.');
  await ref.update(saved);
  return {offerId: ref.id};
}

async function deleteOffer(db, offerId) {
  if (typeof offerId !== 'string' || !ID.test(offerId)) throw new Error('Offer not found.');
  await offers(db).doc(offerId).delete();
  return {deleted: true};
}

module.exports = {saveOffer, deleteOffer};
