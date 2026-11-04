// placeOrder: the order request needs the customer's place and a phone number, and works out each shop's delivery charge on the server.
// Runs against the Firestore emulator only (skipped without FIRESTORE_EMULATOR_HOST).
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {placeOrder} = require('./index');
const {getFirestore} = require('firebase-admin/firestore');

const skip = !process.env.FIRESTORE_EMULATOR_HOST;
const db = getFirestore();
const auth = {uid: 'po-user', token: {email_verified: true}};
const near = {latitude: 17.027, longitude: 82.0}; // about 3 km from the customer
const here = {latitude: 17.0, longitude: 82.0};

async function seed() {
  await db.collection('settings').doc('business').set({deliveryFeeTiers: '5:10, 10:20', defaultPaymentMethod: 'direct_vendor'});
  await db.collection('shops').doc('po-shop-a').set({name: 'Shop A', phone: '9000000001', ...near});
  await db.collection('shops').doc('po-shop-b').set({name: 'Shop B', phone: '9000000002', ...near, freeDelivery: true});
  await db.collection('products').doc('po-p1').set({name: 'Rice', active: true, stock: 10, price: 100, kind: 'product', shopId: 'po-shop-a'});
  await db.collection('products').doc('po-p2').set({name: 'Dal', active: true, stock: 10, price: 50, kind: 'product', shopId: 'po-shop-b'});
}
const call = data => placeOrder.run({auth, data: {pincode: '531116', address: '1-1 Main Road, Narsipatnam', paymentMethod: 'direct_vendor', ...data}});

test('an order request without a place is refused', {skip}, async () => {
  await seed();
  await assert.rejects(call({items: [{productId: 'po-p1', quantity: 1}], phone: '9876543210', requestId: 'po-r1'}), /location/i);
});

test('an order request without a valid phone number is refused', {skip}, async () => {
  await seed();
  await assert.rejects(call({items: [{productId: 'po-p1', quantity: 1}], ...here, phone: '12345', requestId: 'po-r2'}), /10-digit/);
});

test('each shop gets its own delivery charge and the phone number is stored on the order only', {skip}, async () => {
  await seed();
  const {orderId} = await call({items: [{productId: 'po-p1', quantity: 1}, {productId: 'po-p2', quantity: 1}], ...here, phone: '+91 98765 43210', requestId: 'po-r3'});
  const order = (await db.collection('orders').doc(orderId).get()).data();
  assert.equal(order.customerPhone, '9876543210');
  assert.equal(order.deliveryFee, 10, 'shop A pays the 5 km tier, shop B is free');
  assert.equal(order.total, 160);
  assert.deepEqual(order.deliveryByShop.map(part => [part.shopId, part.fee]), [['po-shop-a', 10], ['po-shop-b', 0]]);
  assert.equal(order.customerLatitude, undefined, 'the customer coordinates are not kept');
  assert.equal(order.latitude, undefined);
  const user = (await db.collection('users').doc('po-user').get()).data();
  assert.equal(user?.phone, undefined, 'the phone number is not saved in the account');
});
