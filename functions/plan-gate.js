'use strict';
// The one check the older vendor services make: does this service need a plan, and does the vendor have one running?
// It only reads two documents and imports nothing from functions/modules/plans, so that module can change or go away without touching
// the services. A service runs as it always did when its gate is off, or when the check itself cannot be read. A plan never hides a shop.
const PLAN_NEEDED = 'This service needs an active plan. You can choose one in your vendor app.';

async function planAllows(db, uid, service, now = Date.now()) {
  try {
    const gates = (await db.collection('planServiceGates').doc('main').get()).data();
    if (gates?.[service] !== true) return true;
    const status = (await db.collection('vendorPlanStatus').doc(uid).get()).data();
    return (status?.endsAt?.toMillis?.() ?? 0) > now;
  } catch (error) {
    console.warn('Plan check could not be read', error.message);
    return true;
  }
}

async function requirePlan(db, uid, service, now = Date.now()) {
  if (!(await planAllows(db, uid, service, now))) throw Error(PLAN_NEEDED);
}

// How many items a vendor may add: the free number (planServiceGates/main.freeItemLimit, else 2, or the admin's own number for this
// vendor, vendors/<uid>.itemLimit), or the running plan's number (vendorPlanStatus/<uid>.itemLimit, else 10) when that is bigger.
// Items already saved are never removed when a plan ends; only new ones wait until the vendor is under the limit again.
const FREE_ITEMS = 2;
const PLAN_ITEMS = 10;
const count = n => (Number.isInteger(n) && n >= 0 && n <= 100 ? n : null);

async function vendorItemLimitNow(db, uid, vendor = {}, now = Date.now()) {
  let gates, status;
  try {
    [gates, status] = await Promise.all([db.collection('planServiceGates').doc('main').get(), db.collection('vendorPlanStatus').doc(uid).get()]);
  } catch (error) {
    console.warn('Plan item limit could not be read', error.message);
  }
  const free = count(vendor.itemLimit) ?? count(gates?.data()?.freeItemLimit) ?? FREE_ITEMS;
  const plan = status?.data();
  const running = (plan?.endsAt?.toMillis?.() ?? 0) > now;
  return running ? Math.max(free, count(plan.itemLimit) || PLAN_ITEMS) : free;
}

// Photos (owner, 6 Nov 2026): every vendor has ONE shop photo (photo 1: the shop with its name board or the owner), which is never
// counted. On top of it, a free vendor has FREE_EXTRA_PHOTOS extra photos (planServiceGates/main.freeExtraPhotos), a paid vendor the
// number of their plan (vendorPremium/<uid>.extraPhotos, copied from the plan). Extra shop photos (slots 2, 3, ...) and the vendor's own
// item photos share the same allowance.
const FREE_EXTRA_PHOTOS = 2;
const PLAN_EXTRA_PHOTOS = 10;
const MAX_SHOP_SLOT = 31;

async function vendorPhotoAllowance(db, uid, now = Date.now()) {
  let gates, premium;
  try {
    [gates, premium] = await Promise.all([db.collection('planServiceGates').doc('main').get(), db.collection('vendorPremium').doc(uid).get()]);
  } catch (error) {
    console.warn('Photo allowance could not be read', error.message);
  }
  const free = count(gates?.data()?.freeExtraPhotos) ?? FREE_EXTRA_PHOTOS;
  const p = premium?.data();
  const paid = p?.active === true && (p.endsAt?.toMillis?.() ?? 0) > now;
  return {paid, free, extras: paid ? Math.max(free, count(p.extraPhotos) ?? PLAN_EXTRA_PHOTOS) : free};
}

/// The extra photos a vendor uses now: extra shop photos and own item photos that are waiting or approved. [except] leaves out the
/// one being replaced ({shopSlot} or {productId}), so replacing a photo never needs room for a second one.
async function vendorPhotosUsed(db, uid, except = {}) {
  const [shop, items] = await Promise.all([
    db.collection('vendorShopPhotos').where('vendorId', '==', uid).get(),
    db.collection('vendorItemPhotos').where('vendorId', '==', uid).get(),
  ]);
  const live = d => ['pending', 'approved'].includes(d.data().status);
  return shop.docs.filter(d => live(d) && d.data().slot >= 2 && d.data().slot !== except.shopSlot).length
    + items.docs.filter(d => live(d) && d.id !== except.productId).length;
}

module.exports = {planAllows, requirePlan, vendorItemLimitNow, vendorPhotoAllowance, vendorPhotosUsed, FREE_EXTRA_PHOTOS, MAX_SHOP_SLOT, PLAN_NEEDED};
