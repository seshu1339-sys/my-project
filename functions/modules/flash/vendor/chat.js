'use strict';
// The free vendors' chat (basic): login, plans, prices and validity, adding items and photos, posting offers, payments and the shop.
// Premium vendors have their own advanced chat (premium/chat.js). Each fact is read with the vendor's uid from the server, and only what
// the chosen category needs.
const F = require('./facts');

module.exports = {
  kind: 'vendor',
  collection: 'flashVendorChats',
  categories: ['Login', 'Plans & prices', 'Items & photos', 'Offers', 'Payment', 'Shop', 'Other'],
  helpField: 'helpVendor',
  rules: 'You are talking with a shop owner. Help with signing in, their plan and its prices and validity, their items, photos and prices, posting offers, their payments and their shop. A payment is confirmed only if FACTS say confirmed; never tell them a payment went through otherwise. A shop is never hidden because of a plan. A wrong payment, a refund or a plan that did not start needs the team.',

  /// Someone registered as a vendor (approved or still waiting), whatever the status: a suspended vendor can still ask for help.
  allowed: async (db, uid) => {
    const [vendor, application] = await Promise.all([db.collection('vendors').doc(uid).get(), db.collection('vendorApplications').doc(uid).get()]);
    return vendor.exists || application.exists;
  },
  label: async (db, uid) => {
    const vendor = (await db.collection('vendors').doc(uid).get()).data() ?? (await db.collection('vendorApplications').doc(uid).get()).data();
    return [vendor?.name, vendor?.vendorCode].filter(Boolean).join(' · ');
  },
  facts: async (db, uid, category, now) => {
    if (category === 'Login' || category === 'Shop') return F.shopFacts(db, uid);
    if (category === 'Plans & prices') return F.planFacts(db, uid, now);
    if (category === 'Items & photos') return F.itemFacts(db, uid, now);
    if (category === 'Offers') return F.offerFacts(db, uid);
    if (category === 'Payment') return F.paymentFacts(db, uid);
    // Older chats were made with these names.
    if (category === 'Plan') return F.planFacts(db, uid, now);
    return {};
  },
};
