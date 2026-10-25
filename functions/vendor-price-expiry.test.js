const {test} = require('node:test');
const assert = require('node:assert/strict');

test('a vendor price lasts 24 hours: then it is removed, the item hides and cannot be ordered, and a new price brings it back for 24 hours', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore} = require('firebase-admin/firestore');
  const fns = require('./index');
  const {expireVendorPricesNow, VENDOR_PRICE_VALID_MS} = require('./vendor-prices');
  const db = getFirestore();
  assert.equal(typeof fns.expireVendorPrices, 'function', 'the scheduled job is deployed with the functions');
  const vendor = {auth: {uid: 'priceV', token: {email_verified: true}}};
  await db.collection('vendors').doc('priceV').set({vendorId: 'priceV', name: 'Price Shop', shopId: 'priceShop', status: 'approved'});
  await db.collection('vendorShopPhotos').doc('priceV_1').set({vendorId: 'priceV', slot: 1, status: 'approved'});
  await db.collection('productImageLibrary').doc('lib-price-tomato').set({name: 'Tomato', imageUrl: 'https://example.test/t.jpg', active: true});
  await db.collection('settings').doc('business').set({name: 'Test', defaultPaymentMethod: 'direct_vendor'});

  // ---- saved: the price is valid for 24 hours (also endsAt, which the site and placeOrder obey)
  const before = Date.now();
  const made = await fns.submitVendorChange.run({...vendor, data: {type: 'newProduct', collection: 'products', docId: '', changes: {libraryItemId: 'lib-price-tomato', unitType: 'kg', quantity: 2, price: 50}}});
  const ref = db.collection('products').doc(made.docId);
  let item = (await ref.get()).data();
  const expires = Date.parse(item.priceExpiresAt);
  assert.ok(expires >= before + VENDOR_PRICE_VALID_MS - 1000 && expires <= Date.now() + VENDOR_PRICE_VALID_MS + 1000, 'expires 24 hours after it was set');
  assert.equal(item.endsAt, item.priceExpiresAt);
  assert.equal(item.priceExpired, false);

  // ---- not yet due: nothing is removed; an admin product without a vendor price is never touched
  await db.collection('products').doc('admin-rice').set({name: 'Admin rice', price: 60, stock: 5, active: true});
  assert.equal(await expireVendorPricesNow(Date.now()), 0);

  // ---- 24 hours later: the price is removed, once
  const later = Date.now() + VENDOR_PRICE_VALID_MS + 60000;
  assert.ok(await expireVendorPricesNow(later) >= 1, 'this item (and any other vendor item saved in this test run)');
  item = (await ref.get()).data();
  assert.equal(item.price, undefined, 'the price is gone');
  assert.equal(item.priceExpired, true);
  assert.equal(await expireVendorPricesNow(later), 0, 'already removed');
  assert.equal((await db.collection('products').doc('admin-rice').get()).data().price, 60);

  // ---- an item past its 24 hours cannot be ordered
  await ref.update({price: 50, endsAt: new Date(Date.now() - 1000).toISOString()});
  const customer = {auth: {uid: 'priceCustomer', token: {email_verified: true}}};
  await assert.rejects(() => fns.placeOrder.run({...customer, data: {items: [{productId: made.docId, quantity: 1}], pincode: '531116', address: '12 Main Road, Narsipatnam', requestId: 'req-price-1'}}), /no longer available/);

  // ---- the vendor enters a new price: valid for another 24 hours, shown again, can be ordered
  const renewed = await fns.submitVendorChange.run({...vendor, data: {type: 'price', collection: 'products', docId: made.docId, changes: {price: 46}}});
  assert.equal(renewed.status, 'approved');
  item = (await ref.get()).data();
  assert.equal(item.price, 46);
  assert.equal(item.priceExpired, false);
  assert.ok(Date.parse(item.priceExpiresAt) > Date.now() + VENDOR_PRICE_VALID_MS - 60000);
  assert.equal(item.endsAt, item.priceExpiresAt);
  const order = await fns.placeOrder.run({...customer, data: {items: [{productId: made.docId, quantity: 1}], pincode: '531116', address: '12 Main Road, Narsipatnam', requestId: 'req-price-2'}});
  assert.ok(order.orderId);
});
