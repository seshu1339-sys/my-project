'use strict';
// The users' chat: its own categories, rules and data. Service providers have their own chat (provider/chat.js). Each fact is read with this person's
// uid from the server, and only what the chosen category needs. Only offers are public; everything else is the person's own.
const {Timestamp} = require('firebase-admin/firestore');
const {dateText} = require('../rules');

const ORDER_WORDS = {submitted: 'placed, waiting for the shop', confirmed: 'confirmed by the shop', fulfilled: 'delivered or collected', cancelled: 'cancelled'};

async function orderFacts(db, uid) {
  const orders = await db.collection('orders').where('userId', '==', uid).orderBy('createdAt', 'desc').limit(10).get();
  return {
    orders: orders.docs.map(doc => {
      const order = doc.data();
      return {
        orderNumber: doc.id.slice(0, 8), placedOn: dateText(order.createdAt), status: ORDER_WORDS[order.status] ?? order.status,
        total: order.total, deliveryFee: order.deliveryFee ?? 0, paymentMethod: order.paymentMethod ?? '',
        items: (order.lines ?? []).map(line => ({name: line.name, quantity: line.quantity, unitPrice: line.unitPrice})),
      };
    }),
  };
}

async function offerFacts(db, now) {
  const offers = await db.collection('vendorOffers').where('status', '==', 'live').where('endsAt', '>', Timestamp.fromMillis(now)).orderBy('endsAt').limit(20).get();
  return {
    note: 'These are the live offers ending soonest. Some may be in other towns; the Shop Offers box in the app shows the ones near this person.',
    offers: offers.docs.map(doc => {
      const offer = doc.data();
      return {shop: offer.shopName, title: offer.title, offerPrice: offer.offerPrice, regularPrice: offer.regularPrice, endsOn: dateText(offer.endsAt)};
    }),
  };
}

/// The services customers can choose (the admin's list) and how many providers are live in each.
async function serviceFacts(db) {
  const found = await db.collection('services').where('active', '==', true).limit(500).get();
  const types = new Map(), providers = new Map();
  for (const doc of found.docs) {
    const s = doc.data();
    if (s.kind === 'serviceType') types.set(s.typeId || doc.id, s.name);
    else if (s.kind === 'service') providers.set(s.typeId, (providers.get(s.typeId) || 0) + 1);
  }
  return {services: [...types].map(([id, name]) => ({service: name, providersLive: providers.get(id) || 0})), howTo: 'Tap Services, choose the service, see the providers near you with photo, charge per hour and distance, and tap Call.'};
}

module.exports = {
  kind: 'user',
  collection: 'flashUserChats',
  categories: ['Search & shops', 'Offers', 'Services', 'App', 'Orders', 'Other'],
  helpField: 'helpUser',
  rules: 'You are talking with a customer. Help with searching for items and finding the cheapest shop near them, the offers in the app, finding services such as a plumber, and using the app. Customers buy at the shop in person; there is no online payment for them. Order status, when asked about an older order, comes only from FACTS. A complaint about a shop, a refund or a wrong price needs the team.',

  /// Any signed-in person may use this chat.
  allowed: async () => true,
  label: async (db, uid) => (await db.collection('users').doc(uid).get()).data()?.name ?? '',
  facts: async (db, uid, category, now) => {
    if (category === 'Orders') return orderFacts(db, uid);
    if (category === 'Offers') return offerFacts(db, now);
    if (category === 'Services') return serviceFacts(db);
    return {};
  },
};
