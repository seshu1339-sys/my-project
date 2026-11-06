'use strict';
// The Premium vendors' advanced chat: the stronger model, every fact about the vendor at once (plan and expiry, their customers' calls
// and directions, offers, items, wholesale box, payments), longer answers, and priority in the admin's Support Inbox. The app also shows
// the office's phone and WhatsApp (flashPublic/main). Only a vendor whose plan is running (vendorPremium active) may use it.
const {SONNET} = require('../../ai-core');
const F = require('../vendor/facts');

async function everything(db, uid, now) {
  const [shop, plan, items, offers, stats, wholesale, payments] = await Promise.all([
    F.shopFacts(db, uid), F.planFacts(db, uid, now), F.itemFacts(db, uid, now), F.offerFacts(db, uid), F.statsFacts(db, uid, now), F.wholesaleFacts(db, now), F.paymentFacts(db, uid),
  ]);
  return {shop, plan, items, offers, myStats: stats, wholesaleBox: wholesale, payments};
}

module.exports = {
  kind: 'premium',
  collection: 'flashPremiumChats',
  categories: ['My plan', 'My stats', 'Ads & offers', 'Wholesale', 'Items & prices', 'Payment', 'Other'],
  helpField: 'helpPremium',
  model: SONNET,
  effort: 'medium',
  priority: true,
  rules: 'You are talking with a Premium shop owner: give detailed, helpful answers from FACTS, up to eight sentences, with exact numbers and dates from FACTS. Help with their plan and its end date, their customers\' calls, WhatsApp and directions, their offers and ads, their items and prices, the wholesale box and their payments. Never give ad view numbers. A payment is confirmed only if FACTS say confirmed. A wrong payment, a refund, a plan that did not start or anything you cannot answer needs the team; the office phone is shown in the app.',

  allowed: async (db, uid, now = Date.now()) => {
    const premium = (await db.collection('vendorPremium').doc(uid).get()).data();
    return premium?.active === true && (premium.endsAt?.toMillis?.() ?? 0) > now;
  },
  label: async (db, uid) => {
    const vendor = (await db.collection('vendors').doc(uid).get()).data();
    return ['Premium', vendor?.name, vendor?.vendorCode].filter(Boolean).join(' · ');
  },
  facts: async (db, uid, category, now) => everything(db, uid, now),
};
