const {test} = require('node:test');
const assert = require('node:assert/strict');
const {vendorItemUnit, vendorItemLimit} = require('./domain');

test('item quantities read 2 kg / 1 pc / 5 pcs; the item limit is 2 unless the admin set another', () => {
  assert.equal(vendorItemUnit('kg', 2), '2 kg');
  assert.equal(vendorItemUnit('pcs', 1), '1 pc');
  assert.equal(vendorItemUnit('pcs', 5), '5 pcs');
  assert.equal(vendorItemLimit({}), 2);
  assert.equal(vendorItemLimit({itemLimit: 5}), 5);
  assert.equal(vendorItemLimit({itemLimit: 0}), 0);
  assert.equal(vendorItemLimit({itemLimit: -1}), 2);
  assert.equal(vendorItemLimit({itemLimit: '7'}), 2, 'only a whole number set by the admin counts');
});

test('a vendor item goes live on save at the shop\'s place; 2 items by default (hidden ones count); the admin can allow more; a price change shows at once', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const admin = {auth: {uid: 'admin1', token: {admin: true, email_verified: true}}};
  await db.collection('_adminSessions').doc('admin1').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  await db.collection('settings').doc('business').set({name: 'Test', autoPublishVendorChanges: false});
  const vendor = {auth: {uid: 'itemV', token: {email_verified: true}}};
  await db.collection('vendors').doc('itemV').set({vendorId: 'itemV', name: 'Ravi Stores', shopId: 'itemShop', status: 'approved'});
  await db.collection('shops').doc('itemShop').set({name: 'Ravi Stores', pincode: '531116', latitude: 17.668, longitude: 82.612, ownerId: 'itemV', active: true});
  await db.collection('vendorShopPhotos').doc('itemV_1').set({vendorId: 'itemV', slot: 1, status: 'approved'});
  for (const [id, name, categoryId] of [['lib-tomato', 'Tomato', 'cat-veg'], ['lib-onion', 'Onion', 'cat-veg'], ['lib-soap', 'Bath Soap', 'cat-care']]) {
    await db.collection('productImageLibrary').doc(id).set({name, imageUrl: `https://example.test/${id}.jpg`, categoryId, active: true});
  }
  const add = (libraryItemId, unitType, quantity, price) =>
    fns.submitVendorChange.run({...vendor, data: {type: 'newProduct', collection: 'products', docId: '', changes: {libraryItemId, unitType, quantity, price}}});

  // ---- saved: live at once, with the library's name, photo and category, the quantity and the price for it, at the shop's place
  const first = await add('lib-tomato', 'kg', 2, 50);
  assert.equal(first.status, 'approved');
  const tomato = (await db.collection('products').doc(first.docId).get()).data();
  assert.deepEqual(
    {name: tomato.name, imageUrl: tomato.imageUrl, categoryId: tomato.categoryId, unit: tomato.unit, unitType: tomato.unitType, quantity: tomato.quantity, price: tomato.price, active: tomato.active, ownerId: tomato.ownerId, kind: tomato.kind},
    {name: 'Tomato', imageUrl: 'https://example.test/lib-tomato.jpg', categoryId: 'cat-veg', unit: '2 kg', unitType: 'kg', quantity: 2, price: 50, active: true, ownerId: 'itemV', kind: 'product'},
  );
  assert.equal(tomato.pincode, '531116');
  assert.equal(tomato.town, 'Narsipatnam');
  assert.ok(tomato.stock > 0, 'it can be ordered');

  // ---- two items, then the limit; an item the admin hid still counts
  const second = await add('lib-soap', 'pcs', 3, 90);
  assert.equal((await db.collection('products').doc(second.docId).get()).data().unit, '3 pcs');
  await assert.rejects(() => add('lib-onion', 'kg', 1, 28), /You can have 2 items/);
  await db.collection('products').doc(second.docId).update({active: false}); // hidden by the admin
  await assert.rejects(() => add('lib-onion', 'kg', 1, 28), /You can have 2 items/, 'a hidden item still counts');

  // ---- only the admin can allow more, and only a sensible number
  await assert.rejects(() => fns.setVendorItemLimit.run({...vendor, data: {vendorId: 'itemV', itemLimit: 10}}), /Administrator/);
  await assert.rejects(() => fns.setVendorItemLimit.run({...admin, data: {vendorId: 'itemV', itemLimit: 101}}), /0 to 100/);
  await assert.rejects(() => fns.setVendorItemLimit.run({...admin, data: {vendorId: 'nobody', itemLimit: 3}}), /not found/);
  assert.deepEqual(await fns.setVendorItemLimit.run({...admin, data: {vendorId: 'itemV', itemLimit: 3}}), {itemLimit: 3});
  const third = await add('lib-onion', 'kg', 1, 28);
  assert.equal(third.status, 'approved');
  await assert.rejects(() => add('lib-onion', 'kg', 5, 130), /You can have 3 items/);

  // ---- a price change shows at once (customers' search, map and list read the product); a stock change still follows the policy
  const priced = await fns.submitVendorChange.run({...vendor, data: {type: 'price', collection: 'products', docId: first.docId, changes: {price: 46}}});
  assert.equal(priced.status, 'approved');
  assert.equal((await db.collection('products').doc(first.docId).get()).data().price, 46);
  const stocked = await fns.submitVendorChange.run({...vendor, data: {type: 'stock', collection: 'products', docId: first.docId, changes: {stock: 5}}});
  assert.equal(stocked.status, 'pending');
});
