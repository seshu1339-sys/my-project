'use strict';
// Today's Offer storage: a paid vendor's boxes, in their own collection.
//
//   vendorPremium/<uid>               read only; the premium status module keeps it (running plan, kind, offerBoxes, planName)
//   products/<id>                     read only; the vendor's own items (the box shows the item's photo)
//   productImageLibrary/<id>          read only; the catalog (the box shows the item's stock photo)
//   vendorTodaysOffers/<uid>_<slot>   {vendorId, vendorCode, shopId, slot, productId, libraryItemId, name, note, photoUrl, ownPhoto, price,
//                                      days, untilPlanEnds, planName, tier, hidden, waitingCheck, submittedAt, endsAt, ownEndsAt}
//   Storage vendorTodaysOffers/<uid>/<file>  the vendor's own photos (public; storage.rules)
//
// Owner, 7 Nov 2026: a plan gives a number of boxes (Admin > Plans). Owner, 13 Nov 2026:
//   - the vendor fills a box with one of their items, an item from the catalog, or their own photo (checked by Claude Haiku: only drugs,
//     weapons, alcohol, tobacco and adult content are refused; when the check cannot run the box waits, hidden, for the admin's Show);
//   - an optional short offer text;
//   - a box stays live while the plan runs (no post duration); when the plan ends it is hidden, never deleted, and shows again on renewal
//     (onPlanChange); the vendor can replace or remove it any time;
//   - the admin sees every box with the Vendor ID and plan, and can Hide, Show or Remove it.
// Offers made before (one per vendor, document id = the vendor, an uploaded photo) still show until they end.
// How offers are shown (circle, boxes, rotation, km) is not here.
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const {publicStorageUrl} = require('../../storage-url');
const {checkStoredPhotos, unsafeReason} = require('../../photo-safety');
const {FOLDER, photoPath, validateOffer, offerEnd, boxesOf, boxId} = require('./rules');

const offers = db => db.collection('vendorTodaysOffers');
const millis = t => t?.toMillis?.() ?? 0;

async function dropPhoto(bucket, url, uid) {
  const path = photoPath(url, uid);
  if (path) await bucket.file(path).delete({ignoreNotFound: true});
}

/// The vendor's running boxes (and an older single offer), by document.
async function runningBoxes(db, uid, now) {
  const docs = (await offers(db).where('vendorId', '==', uid).get()).docs;
  return docs.filter(d => millis(d.data().endsAt) > now);
}

/// The name and photo of what goes in the box: one of the vendor's items, a catalog item, or the vendor's own photo (checked first).
async function boxContent(db, bucket, uid, safe, now, checkOptions) {
  if (safe.productId) {
    const product = (await db.collection('products').doc(safe.productId).get()).data();
    if (!product || product.ownerId !== uid) throw new Error('Choose one of your items.');
    if (product.active === false) throw new Error('This item is hidden just now. Choose an item that customers can see.');
    const photoUrl = typeof product.imageUrl === 'string' && product.imageUrl.startsWith('http') ? product.imageUrl : '';
    if (!photoUrl) throw new Error('This item has no photo yet.');
    return {productId: safe.productId, libraryItemId: '', name: product.name || '', photoUrl, ownPhoto: false, waitingCheck: false};
  }
  if (safe.libraryItemId) {
    const item = (await db.collection('productImageLibrary').doc(safe.libraryItemId).get()).data();
    if (!item || item.active === false) throw new Error('Choose an item from the catalog.');
    const photoUrl = [item.imageUrl, item.url].find(u => typeof u === 'string' && u.startsWith('http')) || '';
    if (!photoUrl) throw new Error('This catalog item has no photo yet.');
    return {productId: '', libraryItemId: safe.libraryItemId, name: item.name || '', photoUrl, ownPhoto: false, waitingCheck: false};
  }
  const path = `${FOLDER}/${uid}/${safe.photoName}`;
  const [exists] = await bucket.file(path).exists();
  if (!exists) throw new Error('Upload the photo first.');
  const check = await checkStoredPhotos(db, [path], {feature: 'todays_offer', uid, ...checkOptions});
  if (check.verdict === 'unsafe') {
    await bucket.file(path).delete({ignoreNotFound: true});
    throw new Error(unsafeReason(check.categories));
  }
  return {productId: '', libraryItemId: '', name: safe.name, photoUrl: publicStorageUrl(bucket.name, path, `&v=${now}`), ownPhoto: true, waitingCheck: check.verdict !== 'safe'};
}

/// Puts an offer in a Today's Offers box at once. The same item already in a box is updated there; otherwise the box chosen, or the first
/// free one. Returns the box, when it ends and whether it waits for the admin (the photo check could not run).
async function submitOffer(db, bucket, uid, data, now = Date.now(), checkOptions = {}) {
  const vendor = (await db.collection('vendors').doc(uid).get()).data();
  if (vendor?.status !== 'approved') throw new Error('Your vendor application must be approved first.');
  if (!vendor.shopId) throw new Error('Your shop is not ready yet.');
  const premium = (await db.collection('vendorPremium').doc(uid).get()).data();
  const planEndsAt = millis(premium?.endsAt);
  if (premium?.active !== true || planEndsAt <= now) throw new Error("Today's Offers need a paid plan (Silver, Gold, Platinum, Diamond or Premium).");
  const boxes = boxesOf(premium);
  if (boxes < 1) throw new Error("Your plan has no Today's Offers boxes.");
  const safe = validateOffer(data, boxes);
  const content = await boxContent(db, bucket, uid, safe, now, checkOptions);
  const running = await runningBoxes(db, uid, now);
  const used = new Set(running.map(d => d.data().slot).filter(Number.isInteger));
  const sameItem = running.find(d => (content.productId && d.data().productId === content.productId) || (content.libraryItemId && d.data().libraryItemId === content.libraryItemId));
  let slot = safe.slot ?? sameItem?.data().slot ?? null;
  if (slot === null) {
    for (let i = 1; i <= boxes && slot === null; i++) if (!used.has(i)) slot = i;
    if (slot === null) throw new Error(`All your ${boxes} Today's Offers ${boxes === 1 ? 'box is' : 'boxes are'} in use. Choose a box to replace, or remove an offer first.`);
  }
  // Live while the plan runs, or for the days chosen if that is sooner. The admin's post duration does not apply (owner, 13 Nov 2026).
  const endsAt = offerEnd(now, safe.days, planEndsAt);
  const ref = offers(db).doc(boxId(uid, slot));
  const before = (await ref.get()).data();
  const batch = db.batch();
  // One item, one box: moving an item to another box frees its old one.
  if (sameItem && sameItem.data().slot !== slot) batch.delete(sameItem.ref);
  batch.set(ref, {
    vendorId: uid, vendorCode: vendor.vendorCode || '', shopId: vendor.shopId, slot, productId: content.productId, libraryItemId: content.libraryItemId,
    name: content.name, note: safe.note, photoUrl: content.photoUrl, ownPhoto: content.ownPhoto, price: safe.price, days: safe.days ?? 0,
    untilPlanEnds: safe.days === null, planName: premium.planName || '', tier: premium.tier || '',
    hidden: content.waitingCheck, waitingCheck: content.waitingCheck,
    submittedAt: Timestamp.fromMillis(now), endsAt: Timestamp.fromMillis(endsAt), ownEndsAt: Timestamp.fromMillis(endsAt),
  });
  // An offer of the older kind (one per vendor, its own uploaded photo) gives way to the new boxes.
  const legacy = running.find(d => d.id === uid);
  if (legacy) batch.delete(legacy.ref);
  await batch.commit();
  if (legacy) await dropPhoto(bucket, legacy.data().photoUrl, uid);
  // The vendor's own photo that was in this box (or in the box the item left) is deleted when it is replaced.
  for (const old of [before, sameItem && sameItem.data().slot !== slot ? sameItem.data() : null]) {
    if (old?.photoUrl && photoPath(old.photoUrl, uid) !== photoPath(content.photoUrl, uid)) await dropPhoto(bucket, old.photoUrl, uid);
  }
  return {slot, endsAt, ...(content.waitingCheck ? {waitingCheck: true} : {})};
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
/// A box that runs with the plan is kept (hidden) when the plan ends, so it shows again when the vendor renews.
async function clearEnded(db, bucket, now = Date.now()) {
  const ended = await offers(db).where('endsAt', '<=', Timestamp.fromMillis(now)).get();
  let cleared = 0;
  for (const doc of ended.docs) {
    if (doc.data().untilPlanEnds === true) continue;
    await doc.ref.delete();
    await dropPhoto(bucket, doc.data().photoUrl, doc.data().vendorId || doc.id);
    cleared++;
  }
  return cleared;
}

/// The vendor's plan changed (vendorPremium written): every box follows it. While a plan runs, the boxes that run with the plan show until
/// its end (also after a renewal); a box beyond the plan's number is hidden. When the plan ends or is stopped, every box stops with it.
async function onPlanChange(db, uid, premium, now = Date.now()) {
  const planEnd = millis(premium?.endsAt);
  const active = premium?.active === true && planEnd > now;
  const boxes = boxesOf(premium);
  const docs = (await offers(db).where('vendorId', '==', uid).get()).docs;
  const at = Timestamp.fromMillis(now);
  let changed = 0;
  const batch = db.batch();
  for (const doc of docs) {
    const offer = doc.data();
    const end = millis(offer.endsAt);
    const inPlan = (Number.isInteger(offer.slot) ? offer.slot : 1) <= boxes;
    let next;
    if (!active) next = Math.min(end, planEnd);
    else if (!inPlan) next = Math.min(end, now);
    else if (offer.untilPlanEnds === true) next = planEnd;
    else next = Math.min(millis(offer.ownEndsAt) || end, planEnd);
    const plan = {planName: premium?.planName || offer.planName || '', tier: premium?.tier || offer.tier || ''};
    if (next === end && plan.planName === (offer.planName || '') && plan.tier === (offer.tier || '')) continue;
    batch.update(doc.ref, {endsAt: Timestamp.fromMillis(next), ...plan, planChangedAt: at});
    changed++;
  }
  if (changed) await batch.commit();
  return changed;
}

/// The administrator hides an offer (customers stop seeing it; the vendor is told) or shows it again. Show also lets an offer whose photo
/// check could not run go live.
async function setOfferHidden(db, offerId, hidden, now = Date.now()) {
  if (typeof hidden !== 'boolean') throw new Error('Say whether to hide or show the offer.');
  const ref = offers(db).doc(String(offerId || '-'));
  const offer = (await ref.get()).data();
  if (!offer) throw new Error('Offer not found.');
  const at = Timestamp.fromMillis(now);
  await ref.update({hidden, waitingCheck: FieldValue.delete(), hiddenChangedAt: at});
  if (hidden) {
    await db.collection('vendorNotices').add({
      vendorId: offer.vendorId || ref.id, type: 'todaysOffer', title: "Your Today's Offer was hidden",
      body: 'The LOCAMARKET team hid one of your Today\'s Offers. You can replace it with a new one.', createdAt: at,
    });
  }
  return {hidden};
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

module.exports = {submitOffer, removeOwnOffer, clearEnded, onPlanChange, setOfferHidden, removeOffer};
