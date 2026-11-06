'use strict';
// Today's Offer storage: a paid vendor's boxes, in their own collection.
//
//   vendorPremium/<uid>               read only; the premium status module keeps it (running plan, kind, offerBoxes)
//   products/<id>                     read only; the vendor's own items (the box shows the item's photo)
//   vendorTodaysOffers/<uid>_<slot>   {vendorId, shopId, slot, productId, name, photoUrl, price, days, submittedAt, endsAt}
//
// Owner, 7 Nov 2026: the vendor picks which of their items go into Today's Offers. A plan gives a number of boxes (Silver 1, Gold 3,
// Premium as the admin sets; Admin > Plans). Each box shows one item at a time for 1 week to 3 months, and never after the plan ends.
// Offers made before (one per vendor, document id = the vendor, an uploaded photo) still show until they end.
// How offers are shown (circle, boxes, rotation) is not here.
const {Timestamp} = require('firebase-admin/firestore');
const {photoPath, validateOffer, offerEnd, boxesOf, boxId} = require('./rules');

const offers = db => db.collection('vendorTodaysOffers');

async function dropPhoto(bucket, url, uid) {
  const path = photoPath(url, uid);
  if (path) await bucket.file(path).delete({ignoreNotFound: true});
}

/// The vendor's running boxes (and an older single offer), by document.
async function runningBoxes(db, uid, now) {
  const docs = (await offers(db).where('vendorId', '==', uid).get()).docs;
  return docs.filter(d => (d.data().endsAt?.toMillis?.() ?? 0) > now);
}

/// Puts one of the vendor's items in a Today's Offers box at once. The same item already in a box is updated there; otherwise the box
/// chosen, or the first free one. Returns the box and when it ends.
async function submitOffer(db, bucket, uid, data, now = Date.now()) {
  const vendor = (await db.collection('vendors').doc(uid).get()).data();
  if (vendor?.status !== 'approved') throw new Error('Your vendor application must be approved first.');
  if (!vendor.shopId) throw new Error('Your shop is not ready yet.');
  const premium = (await db.collection('vendorPremium').doc(uid).get()).data();
  const planEndsAt = premium?.endsAt?.toMillis?.() ?? 0;
  if (premium?.active !== true || planEndsAt <= now) throw new Error("Today's Offers need a Silver, Gold or Premium plan.");
  const boxes = boxesOf(premium);
  if (boxes < 1) throw new Error("Your plan has no Today's Offers boxes.");
  const safe = validateOffer(data, boxes);
  const product = (await db.collection('products').doc(safe.productId).get()).data();
  if (!product || product.ownerId !== uid) throw new Error('Choose one of your items.');
  if (product.active === false) throw new Error('This item is hidden just now. Choose an item that customers can see.');
  const photoUrl = typeof product.imageUrl === 'string' && product.imageUrl.startsWith('http') ? product.imageUrl : '';
  if (!photoUrl) throw new Error('This item has no photo yet.');
  const running = await runningBoxes(db, uid, now);
  const used = new Set(running.map(d => d.data().slot).filter(Number.isInteger));
  const sameItem = running.find(d => d.data().productId === safe.productId);
  let slot = safe.slot ?? sameItem?.data().slot ?? null;
  if (slot === null) {
    for (let i = 1; i <= boxes && slot === null; i++) if (!used.has(i)) slot = i;
    if (slot === null) throw new Error(`All your ${boxes} Today's Offers ${boxes === 1 ? 'box is' : 'boxes are'} in use. Choose a box to replace, or remove an offer first.`);
  }
  const endsAt = offerEnd(now, safe.days, planEndsAt);
  const batch = db.batch();
  // One item, one box: moving an item to another box frees its old one.
  if (sameItem && sameItem.data().slot !== slot) batch.delete(sameItem.ref);
  batch.set(offers(db).doc(boxId(uid, slot)), {
    vendorId: uid, shopId: vendor.shopId, slot, productId: safe.productId, name: product.name || '', photoUrl, price: safe.price, days: safe.days,
    submittedAt: Timestamp.fromMillis(now), endsAt: Timestamp.fromMillis(endsAt),
  });
  // An offer of the older kind (one per vendor, its own uploaded photo) gives way to the new boxes.
  const legacy = running.find(d => d.id === uid);
  if (legacy) batch.delete(legacy.ref);
  await batch.commit();
  if (legacy) await dropPhoto(bucket, legacy.data().photoUrl, uid);
  return {slot, endsAt};
}

/// The vendor takes one of their own boxes down (it is free again at once).
async function removeOwnOffer(db, bucket, uid, data = {}) {
  const id = Number.isInteger(data.slot) ? boxId(uid, data.slot) : String(data.offerId || '-');
  const ref = offers(db).doc(id);
  const offer = (await ref.get()).data();
  if (!offer || (offer.vendorId || ref.id) !== uid) throw new Error('Offer not found.');
  await ref.delete();
  await dropPhoto(bucket, offer.photoUrl, uid);
  return {removed: true};
}

/// Clears offers whose end has passed. Customers stop seeing them at the end time by themselves; this removes the document and the photo.
async function clearEnded(db, bucket, now = Date.now()) {
  const ended = await offers(db).where('endsAt', '<=', Timestamp.fromMillis(now)).get();
  for (const doc of ended.docs) {
    await doc.ref.delete();
    await dropPhoto(bucket, doc.data().photoUrl, doc.data().vendorId || doc.id);
  }
  return ended.size;
}

/// The administrator takes an offer down, for example a wrong photo. The vendor gets a notice and can submit a new one.
async function removeOffer(db, bucket, offerId, now = Date.now()) {
  const ref = offers(db).doc(String(offerId || '-'));
  const offer = (await ref.get()).data();
  if (!offer) throw new Error('Offer not found.');
  await ref.delete();
  await dropPhoto(bucket, offer.photoUrl, offer.vendorId || ref.id);
  await db.collection('vendorNotices').add({
    vendorId: offer.vendorId || ref.id, type: 'todaysOffer', title: 'Your Today\'s Offer was removed',
    body: 'The administrator removed your offer. You can submit a new one.', createdAt: Timestamp.fromMillis(now),
  });
  return {removed: true};
}

module.exports = {submitOffer, removeOwnOffer, clearEnded, removeOffer};
