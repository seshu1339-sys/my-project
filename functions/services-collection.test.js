const {test} = require('node:test');
const assert = require('node:assert/strict');

// Services have their own collection: a vendor's new service is saved there, a service can be ordered, and cancelling its order
// gives its stock back.
test('a vendor service is saved in services (not products); a product still goes to products; wrong collection is refused', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const admin = {auth: {uid: 'admin1', token: {admin: true, email_verified: true}}};
  await db.collection('_adminSessions').doc('admin1').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  const vendor = {auth: {uid: 'svcV', token: {email_verified: true}}};
  await db.collection('vendors').doc('svcV').set({vendorId: 'svcV', name: 'Fix It', shopId: 'svcShop', status: 'approved', verified: true});
  await db.collection('vendorShopPhotos').doc('svcV_1').set({vendorId: 'svcV', slot: 1, status: 'approved'}); // photo 1 (the shop) is required before items
  await db.collection('shops').doc('svcShop').set({name: 'Fix It', address: 'Main Road', pincode: '533101', ownerId: 'svcV', active: true});

  const service = await fns.submitVendorChange.run({...vendor, data: {type: 'newProduct', collection: 'services', docId: '', changes: {name: 'AC servicing', price: 500, stock: 20, kind: 'service'}}});
  assert.equal(service.status, 'pending');
  const change = (await db.collection('vendorChanges').where('docId', '==', service.docId).get()).docs[0];
  assert.equal(change.data().collection, 'services');
  await fns.reviewVendorChange.run({...admin, data: {changeId: change.id, approved: true}});
  const saved = (await db.collection('services').doc(service.docId).get()).data();
  assert.equal(saved.kind, 'service');
  assert.equal(saved.shopId, 'svcShop');
  assert.equal(saved.active, true);
  assert.equal((await db.collection('products').doc(service.docId).get()).exists, false, 'not in products');

  const product = await fns.submitVendorChange.run({...vendor, data: {type: 'newProduct', collection: 'products', docId: '', changes: {name: 'Rice bag', price: 900, stock: 5}}});
  assert.equal((await db.collection('vendorChanges').where('docId', '==', product.docId).get()).docs[0].data().collection, 'products');

  // a service must go to services, a product to products
  await assert.rejects(() => fns.submitVendorChange.run({...vendor, data: {type: 'newProduct', collection: 'products', docId: '', changes: {name: 'Wrong place', price: 10, stock: 1, kind: 'service'}}}), /Invalid change target/);
  await assert.rejects(() => fns.submitVendorChange.run({...vendor, data: {type: 'newProduct', collection: 'services', docId: '', changes: {name: 'Wrong place', price: 10, stock: 1}}}), /Invalid change target/);

  // an existing service can be changed (price) through its own collection
  const price = await fns.submitVendorChange.run({...vendor, data: {type: 'price', collection: 'services', docId: service.docId, changes: {price: 450}}});
  assert.equal(price.docId, service.docId);
  await assert.rejects(() => fns.submitVendorChange.run({...vendor, data: {type: 'price', collection: 'orders', docId: service.docId, changes: {price: 1}}}), /Invalid change target/);
});

test('a service can be ordered (stock goes down) and cancelling the order gives the stock back', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  await db.collection('settings').doc('business').set({name: 'Local Market', defaultPaymentMethod: 'direct_vendor'});
  await db.collection('services').doc('order-svc-1').set({name: 'Plumbing visit', kind: 'service', price: 300, stock: 10, active: true, shopId: 'orderShop'});
  await db.collection('products').doc('order-prod-1').set({name: 'Soap', kind: 'product', price: 20, stock: 10, active: true, shopId: 'orderShop'});
  const customer = {auth: {uid: 'orderCustomer', token: {email_verified: true}}};
  const placed = await fns.placeOrder.run({...customer, data: {
    items: [{productId: 'order-svc-1', quantity: 2}, {productId: 'order-prod-1', quantity: 3}],
    pincode: '533101', address: '12 Main Road, Rajahmundry', requestId: 'req-services-1',
  }});
  const order = (await db.collection('orders').doc(placed.orderId).get()).data();
  assert.equal(order.lines.length, 2);
  assert.equal(order.lines.find(line => line.productId === 'order-svc-1').kind, 'service');
  assert.equal(order.subtotal, 660);
  assert.equal((await db.collection('services').doc('order-svc-1').get()).data().stock, 8);
  assert.equal((await db.collection('products').doc('order-prod-1').get()).data().stock, 7);

  const orderRef = db.collection('orders').doc(placed.orderId);
  await orderRef.update({status: 'cancelled'});
  await fns.reconcileCancelledOrderStock.run({
    data: {before: {data: () => ({status: 'submitted', lines: order.lines})}, after: {data: () => ({status: 'cancelled', lines: order.lines}), ref: orderRef}},
    params: {orderId: placed.orderId},
  });
  assert.equal((await db.collection('services').doc('order-svc-1').get()).data().stock, 10);
  assert.equal((await db.collection('products').doc('order-prod-1').get()).data().stock, 10);

  // an unknown id is still refused
  await assert.rejects(() => fns.placeOrder.run({...customer, data: {items: [{productId: 'no-such-item', quantity: 1}], pincode: '533101', address: '12 Main Road, Rajahmundry', requestId: 'req-services-2'}}), /no longer available/);
});
