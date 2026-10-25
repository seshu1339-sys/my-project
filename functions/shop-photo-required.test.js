const {test} = require('node:test');
const assert = require('node:assert/strict');

test('a vendor cannot add an item before photo 1 (the shop) is uploaded; pending counts, rejected does not', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const vendor = {auth: {uid: 'photoV', token: {email_verified: true}}};
  await db.collection('vendors').doc('photoV').set({vendorId: 'photoV', name: 'Photo Shop', shopId: 'photoShop', status: 'approved'});
  const add = () => fns.submitVendorChange.run({...vendor, data: {type: 'newProduct', collection: 'products', docId: '', changes: {name: 'Tomato', price: 30, stock: 5}}});
  await assert.rejects(add, /photo 1/);
  await db.collection('vendorShopPhotos').doc('photoV_1').set({vendorId: 'photoV', slot: 1, status: 'rejected'});
  await assert.rejects(add, /photo 1/);
  await db.collection('vendorShopPhotos').doc('photoV_2').set({vendorId: 'photoV', slot: 2, status: 'approved'});
  await assert.rejects(add, /photo 1/, 'photo 2 is not the shop photo');
  await db.collection('vendorShopPhotos').doc('photoV_1').set({vendorId: 'photoV', slot: 1, status: 'pending'});
  assert.equal((await add()).status, 'pending');
});
