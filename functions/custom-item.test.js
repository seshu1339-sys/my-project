const {test} = require('node:test');
const assert = require('node:assert/strict');

test('an item that is not in the catalog: the vendor names it and picks the category; it waits, hidden, for the own photo', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST}, async () => {
  const {getFirestore} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const vendor = {auth: {uid: 'custV', token: {role: 'vendor', email_verified: true}}};
  await db.collection('vendors').doc('custV').set({vendorId: 'custV', name: 'Custom Vendor', shopId: 'custShop', status: 'approved'});
  await db.collection('vendorShopPhotos').doc('custV_1').set({vendorId: 'custV', slot: 1, status: 'approved'});
  await db.collection('categories').doc('custCat').set({name: 'Handmade', active: true});
  const submit = changes => fns.submitVendorChange.run({...vendor, data: {type: 'newProduct', collection: 'products', docId: '', changes: {unitType: 'pcs', quantity: 1, price: 40, ...changes}}});
  await assert.rejects(() => submit({customName: 'x', categoryId: 'custCat'}), /item name/);
  await assert.rejects(() => submit({customName: 'Clay lamp'}), /category/);
  await assert.rejects(() => submit({customName: 'Clay lamp', categoryId: 'noSuchCat'}), /category/);
  const made = await submit({customName: '  Clay   lamp ', categoryId: 'custCat'});
  const item = (await db.collection('products').doc(made.docId).get()).data();
  assert.deepEqual([item.name, item.categoryId, item.customItem, item.active, item.awaitingOwnPhoto, item.imageUrl], ['Clay lamp', 'custCat', true, false, true, '']);
  assert.equal(item.libraryItemId, undefined);
  assert.ok(item.createdAt, 'createdAt: the plan end keeps the first items');
});
