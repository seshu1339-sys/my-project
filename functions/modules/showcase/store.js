'use strict';
// Showcase module (owner, 6 Nov 2026): every paid vendor (Silver, Gold, Premium) has one box in Today's Offers (their day's offer,
// vendorTodaysOffers) and one box in the website's right-side ad boxes (the photo they choose). Both are seen only by users within the
// plan's km. This module keeps the public record the apps read for that:
//   vendorShowcase/<uid>  {vendorId, shopId, shopName, photoUrl, radiusKm, endsAt, active, updatedAt}
// It reads vendorPremium (premium-status: active, endsAt, radiusKm), vendors and shops, and imports no other module.
const {Timestamp} = require('firebase-admin/firestore');

const DEFAULT_RADIUS_KM = 25;
const running = (premium, now) => premium?.active === true && (premium.endsAt?.toMillis?.() ?? 0) > now;

/// The photos a vendor may choose for the ad box: their approved shop photos (photo 1 and the extra ones).
function shopPhotos(shop = {}) {
  const urls = [shop.imageUrl, ...Object.keys(shop).filter(k => /^photo\d+Url$/.test(k)).sort((a, b) => Number(a.slice(5, -3)) - Number(b.slice(5, -3))).map(k => shop[k])];
  return urls.filter(u => typeof u === 'string' && u.startsWith('http'));
}

/// The vendor picks the photo of their right-side ad box. Paid vendors only.
async function choosePhoto(db, uid, data = {}, now = Date.now()) {
  const [vendorDoc, premiumDoc] = await Promise.all([db.collection('vendors').doc(uid).get(), db.collection('vendorPremium').doc(uid).get()]);
  const vendor = vendorDoc.data();
  if (vendor?.status !== 'approved') throw Error('Your vendor application must be approved first.');
  const premium = premiumDoc.data();
  if (!running(premium, now)) throw Error('The ad box is for Silver, Gold and Premium plans.');
  const shopId = vendor.shopId || uid;
  const shop = (await db.collection('shops').doc(shopId).get()).data() || {};
  if (typeof data.photoUrl !== 'string' || !shopPhotos(shop).includes(data.photoUrl)) throw Error('Choose one of your approved shop photos.');
  await db.collection('vendorShowcase').doc(uid).set({
    vendorId: uid, shopId, shopName: shop.name || vendor.name || '', photoUrl: data.photoUrl,
    radiusKm: typeof premium.radiusKm === 'number' ? premium.radiusKm : DEFAULT_RADIUS_KM, endsAt: premium.endsAt, active: true, updatedAt: Timestamp.fromMillis(now),
  }, {merge: true});
  return {photoUrl: data.photoUrl};
}

/// The plan changed (vendorPremium trigger): the reach (km) and the end follow; an ended plan takes the boxes away. A vendor who never
/// chose a photo still gets a record (shop photo 1 by default), so their Today's Offers box knows its km.
async function syncPlan(db, uid, premium, now = Date.now()) {
  const ref = db.collection('vendorShowcase').doc(uid);
  const current = (await ref.get()).data();
  const active = running(premium, now);
  if (!current && !active) return null;
  const vendor = (await db.collection('vendors').doc(uid).get()).data() || {};
  const shopId = current?.shopId || vendor.shopId || uid;
  const shop = (await db.collection('shops').doc(shopId).get()).data() || {};
  const fields = {
    vendorId: uid, shopId, shopName: shop.name || vendor.name || current?.shopName || '',
    photoUrl: current?.photoUrl && shopPhotos(shop).includes(current.photoUrl) ? current.photoUrl : shopPhotos(shop)[0] || '',
    radiusKm: typeof premium?.radiusKm === 'number' ? premium.radiusKm : current?.radiusKm ?? DEFAULT_RADIUS_KM,
    endsAt: premium?.endsAt ?? Timestamp.fromMillis(0), active, updatedAt: Timestamp.fromMillis(now),
  };
  await ref.set(fields, {merge: true});
  return fields;
}

module.exports = {shopPhotos, choosePhoto, syncPlan, DEFAULT_RADIUS_KM};
