'use strict';
// Vendor Offers: the module's own collections.
//   vendorOffers/<id>        one offer: live | pending | removed. The end date decides when a live offer stops showing.
//   vendorOffersConfig/main  {approvalRequired}: off means offers go live at once.
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const {MAX_RUNNING, photoPath, validateOffer, statusOnSave, endsAtFrom, isRunning} = require('./rules');
const {readPostDurationMs, cappedEnd} = require('../../post-duration');

const offers = db => db.collection('vendorOffers');
const configRef = db => db.collection('vendorOffersConfig').doc('main');

async function approvalRequired(db) {
  return (await configRef(db).get()).data()?.approvalRequired === true;
}

async function approvedVendor(db, uid) {
  const vendor = (await db.collection('vendors').doc(uid).get()).data();
  if (vendor?.status !== 'approved') throw new Error('Your vendor application must be approved first.');
  if (!vendor.shopId) throw new Error('Your shop is not ready yet.');
  return vendor;
}

/// Photos of the old version that the new one no longer uses.
async function dropPhotos(bucket, urls, uid) {
  await Promise.all(urls.map(url => photoPath(url, uid)).filter(Boolean).map(path => bucket.file(path).delete({ignoreNotFound: true})));
}

/// Adds an offer, or edits the vendor's own one. An edit goes back for approval when the admin's switch is on.
async function saveOffer(db, bucket, uid, data, now = Date.now()) {
  const vendor = await approvedVendor(db, uid);
  const ref = data.offerId ? offers(db).doc(String(data.offerId)) : offers(db).doc();
  const current = data.offerId ? (await ref.get()).data() : null;
  if (data.offerId && current?.vendorId !== uid) throw new Error('Offer not found.');
  if (current?.status === 'removed') throw new Error('The administrator removed this offer, so it cannot be changed.');
  const endsAt = current?.endsAt?.toMillis?.() ?? 0;
  const safe = validateOffer(data, uid, endsAt > now);
  if (!current || !isRunning(current, now)) {
    const mine = await offers(db).where('vendorId', '==', uid).get();
    if (mine.docs.filter(doc => isRunning(doc.data(), now)).length >= MAX_RUNNING) throw new Error(`You can run ${MAX_RUNNING} offers at a time. Delete one first.`);
  }
  const shop = (await db.collection('shops').doc(vendor.shopId).get()).data();
  const status = statusOnSave(await approvalRequired(db));
  // The nearby alert is chosen for a new offer, or when an ended one runs again (then it may alert again). Editing a running offer
  // keeps what it had, so an edit never sends a second alert.
  const fresh = !current || !isRunning(current, now);
  const alert = fresh ? {alert: safe.alert, alertRadiusKm: FieldValue.delete(), alertClaimedAt: FieldValue.delete(), alertStatus: FieldValue.delete(), alertSentAt: FieldValue.delete()} : {};
  // Posted now when it is new or runs again; an edit of a running offer keeps its posted time. The days chosen are the offer's own
  // end; the admin's post duration (post-duration.js) caps it for everyone.
  const postedAt = fresh ? now : (current.postedAt?.toMillis?.() ?? current.createdAt?.toMillis?.() ?? now);
  const ownEndsAt = safe.days ? endsAtFrom(now, safe.days) : (current?.ownEndsAt?.toMillis?.() ?? endsAt);
  const cappedEndsAt = cappedEnd(postedAt, await readPostDurationMs(db), ownEndsAt);
  await ref.set({
    ...alert,
    vendorId: uid, shopId: vendor.shopId, shopName: shop?.name || vendor.name || '',
    title: safe.title, details: safe.details, offerPrice: safe.offerPrice, regularPrice: safe.regularPrice, photos: safe.photos,
    status, endsAt: Timestamp.fromMillis(cappedEndsAt), ownEndsAt: Timestamp.fromMillis(ownEndsAt), postedAt: Timestamp.fromMillis(postedAt),
    updatedAt: FieldValue.serverTimestamp(), ...(current ? {} : {createdAt: FieldValue.serverTimestamp()}),
  }, {merge: true});
  if (current) await dropPhotos(bucket, (current.photos || []).filter(url => !safe.photos.includes(url)), uid);
  return {offerId: ref.id, status};
}

/// The vendor deletes their own offer and its photos, at any time and whatever its status.
async function deleteOffer(db, bucket, uid, offerId) {
  const ref = offers(db).doc(String(offerId || '-'));
  const offer = (await ref.get()).data();
  if (offer?.vendorId !== uid) throw new Error('Offer not found.');
  await ref.delete();
  await dropPhotos(bucket, offer.photos || [], uid);
  return {deleted: true};
}

/// The admin approves a waiting offer or removes any offer. A removed offer stays in the vendor's list with the reason.
async function reviewOffer(db, data) {
  const ref = offers(db).doc(String(data.offerId || '-'));
  const offer = (await ref.get()).data();
  if (!offer) throw new Error('Offer not found.');
  if (data.action === 'approve') {
    if (offer.status !== 'pending') throw new Error('Only a waiting offer can be approved.');
    await ref.update({status: 'live', removedReason: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp()});
    return {status: 'live'};
  }
  if (data.action !== 'remove') throw new Error('Choose approve or remove.');
  const reason = String(data.reason ?? '').trim().replace(/\s+/g, ' ');
  if (reason.length < 2 || reason.length > 200) throw new Error('Give a short reason (2-200 characters).');
  await ref.update({status: 'removed', removedReason: reason, updatedAt: FieldValue.serverTimestamp()});
  return {status: 'removed'};
}

async function saveConfig(db, data) {
  if (typeof data.approvalRequired !== 'boolean') throw new Error('Choose on or off.');
  await configRef(db).set({approvalRequired: data.approvalRequired, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  return {approvalRequired: data.approvalRequired};
}

module.exports = {saveOffer, deleteOffer, reviewOffer, saveConfig};
