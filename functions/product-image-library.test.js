const {test} = require('node:test');
const assert = require('node:assert/strict');

test('Product Image Library enforcement is a feature toggle, off by default', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST}, async () => {
  const {getFirestore} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const vendor = {auth: {uid: 'libV', token: {email_verified: true}}};
  const submitNew = imageUrl => fns.submitVendorChange.run({...vendor, data: {type: 'newProduct', collection: 'products', docId: '', changes: {name: 'Some item', price: 10, imageUrl}}});
  await db.collection('vendors').doc('libV').set({vendorId: 'libV', name: 'Lib Vendor', shopId: 'libShop', status: 'approved'});
  await db.collection('productImageLibrary').doc('approvedImg').set({name: 'Approved lamp', imageUrl: 'https://example.test/approved.jpg', active: true, order: 0});
  await db.collection('productImageLibrary').doc('disabledImg').set({name: 'Disabled lamp', imageUrl: 'https://example.test/disabled.jpg', active: false, order: 1});

  // ---- off by default: today's free upload keeps working, existing behaviour unchanged
  const off = await submitNew('https://example.test/vendors-own-photo.jpg');
  assert.ok(['pending', 'approved'].includes(off.status));

  // ---- once the admin turns it on, only an approved library image is accepted
  await db.collection('settings').doc('business').set({productImageLibraryEnforced: 'true'}, {merge: true});
  await assert.rejects(() => submitNew('https://example.test/vendors-own-photo.jpg'), /Product Image Library/);
  await assert.rejects(() => submitNew('https://example.test/disabled.jpg'), /Product Image Library/, 'a disabled library entry is not accepted either');
  const on = await submitNew('https://example.test/approved.jpg');
  assert.ok(['pending', 'approved'].includes(on.status));

  await db.collection('settings').doc('business').set({productImageLibraryEnforced: 'false'}, {merge: true});
});
