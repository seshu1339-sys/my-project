const {test} = require('node:test');
const assert = require('node:assert/strict');

test('new vendor items come only from the admin library; the library switch still guards a vendor photo change', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST}, async () => {
  const {getFirestore} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const vendor = {auth: {uid: 'libV', token: {email_verified: true}}};
  await db.collection('vendors').doc('libV').set({vendorId: 'libV', name: 'Lib Vendor', shopId: 'libShop', status: 'approved'});
  await db.collection('vendorShopPhotos').doc('libV_1').set({vendorId: 'libV', slot: 1, status: 'approved'}); // photo 1 (the shop) is required before items
  await db.collection('productImageLibrary').doc('approvedImg').set({name: 'Approved lamp', imageUrl: 'https://example.test/approved.jpg', active: true, order: 0});
  await db.collection('productImageLibrary').doc('disabledImg').set({name: 'Disabled lamp', imageUrl: 'https://example.test/disabled.jpg', active: false, order: 1});
  const submitNew = libraryItemId => fns.submitVendorChange.run({...vendor, data: {type: 'newProduct', collection: 'products', docId: '', changes: {libraryItemId, unitType: 'pcs', quantity: 1, price: 10}}});

  // ---- a new item must be a library item that is switched on; free text is refused
  await assert.rejects(() => fns.submitVendorChange.run({...vendor, data: {type: 'newProduct', collection: 'products', docId: '', changes: {name: 'My own lamp', price: 10}}}), /Unsupported public change field/);
  await assert.rejects(() => submitNew('disabledImg'), /item from the list/);
  await assert.rejects(() => submitNew('noSuchItem'), /item from the list/);
  const made = await submitNew('approvedImg');
  const item = (await db.collection('products').doc(made.docId).get()).data();
  assert.equal(item.name, 'Approved lamp', 'the name is the library item\'s');
  assert.equal(item.imageUrl, 'https://example.test/approved.jpg', 'and so is the photo');

  // ---- changing the photo of an item: free while the switch is off, library photos only once it is on
  const changePhoto = imageUrl => fns.submitVendorChange.run({...vendor, data: {type: 'product', collection: 'products', docId: made.docId, changes: {imageUrl}}});
  assert.ok(['pending', 'approved'].includes((await changePhoto('https://example.test/vendors-own-photo.jpg')).status));
  await db.collection('settings').doc('business').set({productImageLibraryEnforced: 'true'}, {merge: true});
  await assert.rejects(() => changePhoto('https://example.test/vendors-own-photo.jpg'), /Product Image Library/);
  await assert.rejects(() => changePhoto('https://example.test/disabled.jpg'), /Product Image Library/, 'a disabled library entry is not accepted either');
  assert.ok(['pending', 'approved'].includes((await changePhoto('https://example.test/approved.jpg')).status));
  await db.collection('settings').doc('business').set({productImageLibraryEnforced: 'false'}, {merge: true});
});
