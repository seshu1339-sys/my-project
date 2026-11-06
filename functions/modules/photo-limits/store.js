'use strict';
// Photo limits module: a vendor's own item photos and what happens to extra photos when a paid plan ends.
//   vendorItemPhotos/<productId>  {vendorId, productId, name, path, status: pending | approved | rejected, submittedAt, decisionReason}
//   products/<id>                 the item: ownPhoto, ownPhotoStatus, imageUrl (the own photo once approved, else libraryImageUrl),
//                                 awaitingOwnPhoto (its category needs an own photo: hidden until one is approved),
//                                 searchUntilMs (owner, 7 Nov 2026: how long the item shows in the website's category and search
//                                 results, chosen by the vendor: 1 week to 3 months; items without it show as before)
//   vendorShopPhotos/<uid>_<slot> read here only to trim extra shop photos at the end of a plan
//   Storage: vendorItemPhotos/<uid>/<productId> (private until approved), catalog/item_<productId>.jpg (public copy)
// The allowance (1 shop photo not counted + free 2 or the plan's number) is shared with extra shop photos (functions/plan-gate.js).
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const {vendorPhotoAllowance, vendorPhotosUsed} = require('../../plan-gate');
const {publicStorageUrl} = require('../../storage-url');

const ID = /^[A-Za-z0-9_-]{1,128}$/;
const privatePath = (uid, productId) => `vendorItemPhotos/${uid}/${productId}`;
const publicPath = productId => `catalog/item_${productId}.jpg`;
const live = status => ['pending', 'approved'].includes(status);
const DAY_MS = 86400000;
/// How long an item may show in search, in days: 1 week, 1 month, 2 months or 3 months.
const SEARCH_DAYS = [7, 30, 60, 90];
function searchDaysOf(value, required) {
  if (value === undefined || value === null) {
    if (required) throw Error('Choose how long the item shows in search: 1 week, 1 month, 2 months or 3 months.');
    return null;
  }
  if (!SEARCH_DAYS.includes(value)) throw Error('Choose how long the item shows in search: 1 week, 1 month, 2 months or 3 months.');
  return value;
}

async function ownProduct(db, uid, productId) {
  if (typeof productId !== 'string' || !ID.test(productId)) throw Error('Choose your item.');
  const product = (await db.collection('products').doc(productId).get()).data();
  if (!product || product.ownerId !== uid) throw Error('Choose your item.');
  return product;
}

/// The vendor sends their own photo for an item (uploaded first to vendorItemPhotos/<uid>/<productId>). It waits for the admin's photo
/// check; meanwhile the item keeps our standard photo (or stays hidden when its category needs an own photo).
async function submitItemPhoto(db, bucket, uid, data = {}, now = Date.now()) {
  const vendor = (await db.collection('vendors').doc(uid).get()).data();
  if (vendor?.status !== 'approved') throw Error('Your vendor application must be approved first.');
  const product = await ownProduct(db, uid, data.productId);
  const searchDays = searchDaysOf(data.searchDays, false);
  const [exists] = await bucket.file(privatePath(uid, data.productId)).exists();
  if (!exists) throw Error('Upload the photo first.');
  const ref = db.collection('vendorItemPhotos').doc(data.productId);
  const current = (await ref.get()).data();
  if (!(current && live(current.status))) {
    const {extras} = await vendorPhotoAllowance(db, uid, now);
    if ((await vendorPhotosUsed(db, uid, {productId: data.productId})) >= extras) throw Error(`You have used all ${extras} extra photos of your plan. Change or remove one first.`);
  }
  const at = Timestamp.fromMillis(now);
  await ref.set({vendorId: uid, productId: data.productId, name: product.name || '', path: privatePath(uid, data.productId), status: 'pending', submittedAt: at, decisionReason: FieldValue.delete()}, {merge: true});
  await db.collection('products').doc(data.productId).update({ownPhotoStatus: 'pending', updatedAt: at, ...(searchDays ? {searchUntilMs: now + searchDays * DAY_MS} : {})});
  return {status: 'pending'};
}

/// The vendor chooses how long an item shows in the website's category and search results, from now: 1 week to 3 months. After that
/// the item is out of search until the vendor chooses again (nothing is deleted).
async function setItemSearchTime(db, uid, data = {}, now = Date.now()) {
  await ownProduct(db, uid, data.productId);
  const days = searchDaysOf(data.days, true);
  const searchUntilMs = now + days * DAY_MS;
  await db.collection('products').doc(data.productId).update({searchUntilMs, updatedAt: Timestamp.fromMillis(now)});
  return {searchUntilMs};
}

/// Back to our standard photo: the own photo goes from Storage. An item whose category needs an own photo is hidden again.
async function dropOwnPhoto(db, bucket, product, productId, at) {
  await Promise.all([
    bucket.file(privatePath(product.ownerId, productId)).delete({ignoreNotFound: true}),
    bucket.file(publicPath(productId)).delete({ignoreNotFound: true}),
  ]);
  const category = product.categoryId ? (await db.collection('categories').doc(product.categoryId).get()).data() : null;
  const required = category?.ownPhotoRequired === true;
  await db.collection('products').doc(productId).update({
    imageUrl: product.libraryImageUrl || '', ownPhoto: false, ownPhotoStatus: FieldValue.delete(), updatedAt: at,
    ...(required ? {active: false, awaitingOwnPhoto: true} : {}),
  });
}

/// Admin: the photo check of an own item photo. Approved, the public copy becomes the item's photo; rejected, it is deleted.
async function reviewItemPhoto(db, bucket, data = {}, now = Date.now()) {
  if (typeof data.productId !== 'string' || !ID.test(data.productId) || typeof data.approved !== 'boolean') throw Error('Provide the item and the decision.');
  const ref = db.collection('vendorItemPhotos').doc(data.productId);
  const photo = (await ref.get()).data();
  if (!photo || photo.status !== 'pending') throw Error('This photo was already reviewed.');
  const product = (await db.collection('products').doc(data.productId).get()).data();
  const at = Timestamp.fromMillis(now);
  if (!data.approved) {
    await ref.update({status: 'rejected', decisionReason: String(data.reason || '').slice(0, 300), decidedAt: at});
    await bucket.file(photo.path).delete({ignoreNotFound: true});
    if (product) await db.collection('products').doc(data.productId).update({ownPhotoStatus: 'rejected', updatedAt: at});
    return {status: 'rejected'};
  }
  if (!product) throw Error('That item no longer exists.');
  await bucket.file(photo.path).copy(bucket.file(publicPath(data.productId)));
  const url = publicStorageUrl(bucket.name, publicPath(data.productId), `&v=${now}`);
  await ref.update({status: 'approved', decidedAt: at});
  await db.collection('products').doc(data.productId).update({
    imageUrl: url, ownPhoto: true, ownPhotoStatus: 'approved', updatedAt: at,
    ...(product.awaitingOwnPhoto ? {active: true, awaitingOwnPhoto: FieldValue.delete()} : {}),
  });
  return {status: 'approved'};
}

/// The vendor goes back to our standard photo for an item.
async function removeItemPhoto(db, bucket, uid, data = {}, now = Date.now()) {
  const product = await ownProduct(db, uid, data.productId);
  await db.collection('vendorItemPhotos').doc(data.productId).delete();
  await dropOwnPhoto(db, bucket, product, data.productId, Timestamp.fromMillis(now));
  return {removed: true};
}

/// A paid plan ended: only the first [keep] extra photos stay (extra shop photos first, by slot, then own item photos, oldest first);
/// the others are deleted from Storage and their records. Returns how many went.
async function trimAfterPlan(db, bucket, uid, keep, now = Date.now()) {
  const at = Timestamp.fromMillis(now);
  const shop = (await db.collection('vendorShopPhotos').where('vendorId', '==', uid).get()).docs
    .filter(d => d.data().slot >= 2 && live(d.data().status)).sort((a, b) => a.data().slot - b.data().slot);
  const items = (await db.collection('vendorItemPhotos').where('vendorId', '==', uid).get()).docs
    .filter(d => live(d.data().status)).sort((a, b) => (a.data().submittedAt?.toMillis?.() ?? 0) - (b.data().submittedAt?.toMillis?.() ?? 0));
  const extra = [...shop.map(d => ({kind: 'shop', doc: d})), ...items.map(d => ({kind: 'item', doc: d}))].slice(keep);
  for (const {kind, doc} of extra) {
    if (kind === 'shop') {
      const slot = doc.data().slot;
      await Promise.all([bucket.file(doc.data().path).delete({ignoreNotFound: true}), bucket.file(`catalog/shop_${uid}_${slot}.jpg`).delete({ignoreNotFound: true})]);
      await doc.ref.delete();
      const shopId = (await db.collection('vendors').doc(uid).get()).data()?.shopId || uid;
      await db.collection('shops').doc(shopId).set({[`photo${slot}Url`]: FieldValue.delete()}, {merge: true});
    } else {
      const product = (await db.collection('products').doc(doc.id).get()).data();
      await doc.ref.delete();
      if (product) await dropOwnPhoto(db, bucket, product, doc.id, at);
    }
  }
  return extra.length;
}

module.exports = {submitItemPhoto, setItemSearchTime, reviewItemPhoto, removeItemPhoto, trimAfterPlan, privatePath, publicPath, SEARCH_DAYS};
