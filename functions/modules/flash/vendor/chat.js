'use strict';
// The vendors' chat: its own categories, rules and data. Payment answers come only from the vendor's own paymentRequests documents, which
// the payment module writes: Flash reads them, never decides a payment. Each fact is read with the vendor's uid
// from the server, and only what the chosen category needs.
const {dateText, newestFirst} = require('../rules');

const PAYMENT_WORDS = {
  awaiting_payment: 'waiting for the vendor to pay with Razorpay (Pay button on the plan card)',
  verified: 'confirmed',
  paid_after_cancel: 'paid after the vendor changed plan; the office will refund it',
  cancelled: 'cancelled',
};

async function paymentFacts(db, uid) {
  const found = await db.collection('paymentRequests').where('uid', '==', uid).get();
  const rows = found.docs.map(doc => doc.data()).sort(newestFirst('createdAt')).slice(0, 5);
  return {payments: rows.map(row => ({for: row.label, amount: row.amount, status: PAYMENT_WORDS[row.status] ?? 'being checked', requestedOn: dateText(row.createdAt), paidOn: dateText(row.paidAt)}))};
}

async function planFacts(db, uid) {
  const [status, plans] = await Promise.all([db.collection('vendorPlanStatus').doc(uid).get(), db.collection('vendorPlans').where('active', '==', true).get()]);
  const mine = status.data();
  return {
    myPlan: mine ? {name: mine.planName, endsOn: dateText(mine.endsAt)} : 'no plan bought yet',
    plansOnSale: plans.docs.map(doc => ({name: doc.data().name, price: doc.data().price, months: doc.data().durationMonths})),
  };
}

async function offerFacts(db, uid) {
  const [offers, todays] = await Promise.all([db.collection('vendorOffers').where('vendorId', '==', uid).get(), db.collection('vendorTodaysOffers').doc(uid).get()]);
  const today = todays.data();
  return {
    shopOffers: offers.docs.map(doc => doc.data()).sort(newestFirst('endsAt')).slice(0, 10).map(offer => ({title: offer.title, status: offer.status, offerPrice: offer.offerPrice, regularPrice: offer.regularPrice, endsOn: dateText(offer.endsAt)})),
    todaysOffer: today ? {price: today.price, hours: today.hours, endsOn: dateText(today.endsAt)} : 'none',
  };
}

async function shopFacts(db, uid) {
  const vendor = (await db.collection('vendors').doc(uid).get()).data() ?? {};
  const shop = vendor.shopId ? (await db.collection('shops').doc(vendor.shopId).get()).data() : null;
  return {
    vendor: {status: vendor.status, verified: vendor.verified === true, vendorCode: vendor.vendorCode ?? ''},
    shop: shop ? {name: shop.name, category: shop.category, address: shop.address, showing: shop.active !== false} : 'no shop record yet',
  };
}

module.exports = {
  kind: 'vendor',
  collection: 'flashVendorChats',
  categories: ['Payment', 'Plan', 'Offers', 'Shop', 'Other'],
  helpField: 'helpVendor',
  rules: 'You are talking with a shop owner. Help with their own payments, plan, offers and shop. A payment is confirmed only if FACTS say confirmed; never tell them a payment went through otherwise. Screenshots are sent on the payment page, not in this chat. A shop is never hidden because of a plan. A wrong payment, a refund or a plan that did not start needs the team.',

  /// Only someone with a vendor record, whatever its status: a suspended vendor can still ask for help.
  allowed: async (db, uid) => (await db.collection('vendors').doc(uid).get()).exists,
  label: async (db, uid) => {
    const vendor = (await db.collection('vendors').doc(uid).get()).data();
    return [vendor?.name, vendor?.vendorCode].filter(Boolean).join(' · ');
  },
  facts: async (db, uid, category) => {
    if (category === 'Payment') return paymentFacts(db, uid);
    if (category === 'Plan') return planFacts(db, uid);
    if (category === 'Offers') return offerFacts(db, uid);
    if (category === 'Shop') return shopFacts(db, uid);
    return {};
  },
};
