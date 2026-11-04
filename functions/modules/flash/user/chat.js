'use strict';
// The users' chat: its own categories, rules and data. A service provider is treated as a user here. Each fact is read with this person's
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

module.exports = {
  kind: 'user',
  collection: 'flashUserChats',
  categories: ['Orders', 'Offers', 'App', 'Other'],
  helpField: 'helpUser',
  rules: 'You are talking with a customer. Help with their own orders, the offers in the app and using the app. Order status comes only from FACTS. A refund, a cancellation or a problem with a delivered item needs the team.',

  /// Any signed-in person may use this chat.
  allowed: async () => true,
  label: async (db, uid) => (await db.collection('users').doc(uid).get()).data()?.name ?? '',
  facts: async (db, uid, category, now) => {
    if (category === 'Orders') return orderFacts(db, uid);
    if (category === 'Offers') return offerFacts(db, now);
    return {};
  },
};
