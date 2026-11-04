'use strict';
// Today's Offer storage: one offer per vendor, in its own collection and Storage folder.
//
//   vendorPremium/<uid>         read only; the premium status module keeps it
//   vendorTodaysOffers/<uid>    {vendorId, shopId, photoUrl, price, hours, submittedAt, endsAt}
//
// The document id is the vendor, so a new offer replaces the old one by itself. How offers are shown (circle, boxes, rotation) is not here.
const {Timestamp} = require('firebase-admin/firestore');
const {photoPath, validateOffer, offerEnd} = require('./rules');

const offers = db => db.collection('vendorTodaysOffers');

async function dropPhoto(bucket, url, uid) {
  const path = photoPath(url, uid);
  if (path) await bucket.file(path).delete({ignoreNotFound: true});
}

/// The automatic check: an approved vendor with a shop, a running plan, a stored image of their own, a valid price and time.
async function checkSubmission(db, bucket, uid, data, now) {
  const vendor = (await db.collection('vendors').doc(uid).get()).data();
  if (vendor?.status !== 'approved') throw new Error('Your vendor application must be approved first.');
  if (!vendor.shopId) throw new Error('Your shop is not ready yet.');
  const premium = (await db.collection('vendorPremium').doc(uid).get()).data();
  const planEndsAt = premium?.endsAt?.toMillis?.() ?? 0;
  if (premium?.active !== true || planEndsAt <= now) throw new Error('Today\'s Offer needs an active plan.');
  const safe = validateOffer(data);
  const path = photoPath(data.photoUrl, uid);
  if (!path) throw new Error('Upload the photo from your own vendor app.');
  const [exists] = await bucket.file(path).exists();
  if (!exists) throw new Error('The photo was not found. Upload it again.');
  const [metadata] = await bucket.file(path).getMetadata();
  if (!String(metadata.contentType).startsWith('image/')) throw new Error('The file is not a photo.');
  return {...safe, shopId: vendor.shopId, planEndsAt};
}

/// Puts the vendor's offer live at once, replacing their old one. Returns when it ends.
async function submitOffer(db, bucket, uid, data, now = Date.now()) {
  const safe = await checkSubmission(db, bucket, uid, data, now);
  const ref = offers(db).doc(uid);
  const old = (await ref.get()).data();
  const endsAt = offerEnd(now, safe.hours, safe.planEndsAt);
  await ref.set({
    vendorId: uid, shopId: safe.shopId, photoUrl: data.photoUrl, price: safe.price, hours: safe.hours,
    submittedAt: Timestamp.fromMillis(now), endsAt: Timestamp.fromMillis(endsAt),
  });
  if (old?.photoUrl && old.photoUrl !== data.photoUrl) await dropPhoto(bucket, old.photoUrl, uid);
  return {endsAt};
}

/// Clears offers whose end has passed. Customers stop seeing them at the end time by themselves; this removes the document and the photo.
async function clearEnded(db, bucket, now = Date.now()) {
  const ended = await offers(db).where('endsAt', '<=', Timestamp.fromMillis(now)).get();
  for (const doc of ended.docs) {
    await doc.ref.delete();
    await dropPhoto(bucket, doc.data().photoUrl, doc.id);
  }
  return ended.size;
}

/// The administrator takes an offer down, for example a wrong photo. The vendor gets a notice and can submit a new one.
async function removeOffer(db, bucket, vendorId, now = Date.now()) {
  const ref = offers(db).doc(String(vendorId || '-'));
  const offer = (await ref.get()).data();
  if (!offer) throw new Error('Offer not found.');
  await ref.delete();
  await dropPhoto(bucket, offer.photoUrl, offer.vendorId);
  await db.collection('vendorNotices').add({
    vendorId: offer.vendorId, type: 'todaysOffer', title: 'Your Today\'s Offer was removed',
    body: 'The administrator removed your offer. You can submit a new one.', createdAt: Timestamp.fromMillis(now),
  });
  return {removed: true};
}

module.exports = {submitOffer, clearEnded, removeOffer};
