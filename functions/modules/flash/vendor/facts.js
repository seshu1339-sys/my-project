'use strict';
// What Flash may read about one vendor, by the vendor's uid from the server. Shared by the free vendors' chat (vendor/chat.js) and the
// Premium vendors' advanced chat (premium/chat.js). Payment answers come only from the vendor's own paymentRequests documents, which the
// payment module writes: Flash reads them, never decides a payment. Ad view numbers are never given (the vendor sees totals only in
// My Stats); the vendor's own customer actions (calls, WhatsApp, directions) are.
const {Timestamp} = require('firebase-admin/firestore');
const {dateText, newestFirst} = require('../rules');

const PAYMENT_WORDS = {
  awaiting_payment: 'waiting for the vendor to pay with Razorpay (Pay button on the plan card)',
  verified: 'confirmed',
  paid_after_cancel: 'paid after the vendor changed plan; the office will refund it',
  cancelled: 'cancelled',
};
const FREE_ITEMS = 2, PLAN_ITEMS = 10;
const count = n => (Number.isInteger(n) && n >= 0 && n <= 100 ? n : null);

async function paymentFacts(db, uid) {
  const found = await db.collection('paymentRequests').where('uid', '==', uid).get();
  const rows = found.docs.map(doc => doc.data()).sort(newestFirst('createdAt')).slice(0, 5);
  return {payments: rows.map(row => ({for: row.label, amount: row.amount, status: PAYMENT_WORDS[row.status] ?? 'being checked', requestedOn: dateText(row.createdAt), paidOn: dateText(row.paidAt)}))};
}

async function planFacts(db, uid, now = Date.now()) {
  const [status, plans, gates, vendor] = await Promise.all([
    db.collection('vendorPlanStatus').doc(uid).get(),
    db.collection('vendorPlans').where('active', '==', true).get(),
    db.collection('planServiceGates').doc('main').get(),
    db.collection('vendors').doc(uid).get(),
  ]);
  const mine = status.data();
  const running = (mine?.endsAt?.toMillis?.() ?? 0) > now;
  const free = count(vendor.data()?.itemLimit) ?? count(gates.data()?.freeItemLimit) ?? FREE_ITEMS;
  return {
    myPlan: mine ? {name: mine.planName, kind: mine.tier || 'premium', extraPhotos: mine.extraPhotos ?? 10, reachKm: mine.radiusKm ?? 25, running, endsOn: dateText(mine.endsAt), itemsAllowed: running ? Math.max(free, count(mine.itemLimit) || PLAN_ITEMS) : free} : 'free plan (no plan bought)',
    freePlan: {items: free, photos: '1 shop photo + 2 extra photos', price: 'free for life', pricesChangeableAnyDay: true},
    plansOnSale: plans.docs.map(doc => ({name: doc.data().name, kind: doc.data().tier || 'premium', price: doc.data().price, months: doc.data().durationMonths, extraPhotos: doc.data().extraPhotos ?? 10, reachKm: doc.data().radiusKm ?? 25, items: count(doc.data().itemLimit) || PLAN_ITEMS})),
    paidPlansAllGive: "sudden offer alerts, a Today's Offers box, a box in the website ad boxes and the advanced help chat; the kinds differ only in extra photos and km",
    howToStartAPlan: 'Contact the LOCAMARKET office (the admin starts it), or pay on the Plans card when payments are open.',
  };
}

async function itemFacts(db, uid, now = Date.now()) {
  const [items, plan] = await Promise.all([db.collection('products').where('ownerId', '==', uid).get(), planFacts(db, uid, now)]);
  const allowed = typeof plan.myPlan === 'object' ? plan.myPlan.itemsAllowed : plan.freePlan.items;
  return {
    itemsAllowed: allowed,
    items: items.docs.map(doc => doc.data()).map(item => ({
      name: item.name, price: item.priceExpired ? 'price expired: enter a new price' : item.price, unit: item.unit,
      priceValidUntil: item.priceExpiresAt ? dateText(Timestamp.fromDate(new Date(item.priceExpiresAt))) : '', shownToCustomers: item.active !== false,
    })),
  };
}

async function offerFacts(db, uid) {
  const [offers, todays] = await Promise.all([db.collection('vendorOffers').where('vendorId', '==', uid).get(), db.collection('vendorTodaysOffers').doc(uid).get()]);
  const today = todays.data();
  return {
    shopOffers: offers.docs.map(doc => doc.data()).sort(newestFirst('endsAt')).slice(0, 10).map(offer => ({
      title: offer.title, status: offer.status, offerPrice: offer.offerPrice, regularPrice: offer.regularPrice, endsOn: dateText(offer.endsAt),
      nearbyAlert: offer.alert === true || offer.alertRadiusKm ? `${offer.alertRadiusKm ? `${offer.alertRadiusKm} km (plan km)` : 'plan km'}, ${offer.alertStatus || 'waiting'}` : 'none',
    })),
    todaysOffer: today ? {price: today.price, hours: today.hours, endsOn: dateText(today.endsAt)} : 'none',
  };
}

async function shopFacts(db, uid) {
  const [vendorDoc, application] = await Promise.all([db.collection('vendors').doc(uid).get(), db.collection('vendorApplications').doc(uid).get()]);
  const vendor = vendorDoc.data() ?? {};
  const shop = vendor.shopId ? (await db.collection('shops').doc(vendor.shopId).get()).data() : null;
  return {
    registration: application.exists ? {status: application.data().status, vendorCode: application.data().vendorCode ?? ''} : 'not registered yet',
    vendor: {status: vendor.status ?? 'not approved yet', verified: vendor.verified === true, vendorCode: vendor.vendorCode ?? ''},
    shop: shop ? {name: shop.name, category: shop.category, address: shop.address, showing: shop.active !== false} : 'no shop record yet',
  };
}

/// The vendor's own customer actions over the last 30 days (from usageOwnerDaily): calls, WhatsApp, directions, searches. No views.
async function statsFacts(db, uid, now = Date.now()) {
  const since = new Date(now - 30 * 86400000 + 19800000).toISOString().slice(0, 10);
  const days = await db.collection('usageOwnerDaily').where('ownerId', '==', uid).where('day', '>=', since).get();
  const totals = {};
  for (const doc of days.docs) {
    for (const [event, n] of Object.entries(doc.data().counts || {})) {
      if (/view/i.test(event)) continue;
      totals[event] = (totals[event] || 0) + n;
    }
  }
  return {last30Days: totals, note: 'shop_call = calls, shop_whatsapp = WhatsApp messages, shop_directions = route taps, price_changed = your price changes, item_added = items added.'};
}

/// The admin's wholesale offers (only Premium vendors see the Wholesale box).
async function wholesaleFacts(db, now = Date.now()) {
  const found = await db.collection('wholesaleOffers').limit(30).get();
  return {
    wholesale: found.docs.map(doc => doc.data()).filter(o => (o.validUntil?.toMillis?.() ?? now + 1) > now && o.active !== false).map(o => ({
      item: o.name, price: o.price, minimum: o.minQuantity, wholesaler: o.wholesaler, phone: o.phone, validUntil: dateText(o.validUntil),
    })),
    howToOrder: 'Tap a wholesale card in the Wholesale box to call the wholesaler and order stock.',
  };
}

module.exports = {paymentFacts, planFacts, itemFacts, offerFacts, shopFacts, statsFacts, wholesaleFacts};
