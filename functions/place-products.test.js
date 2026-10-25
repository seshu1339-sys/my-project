const {test} = require('node:test');
const assert = require('node:assert/strict');

// A vendor's or field staff's new product waits for the admin and, once approved, carries where it is
// (the shop's pincode, town, district, state and GPS) so the site can show its location.
test('approved vendor and staff products carry their shop\'s place', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-neighbourly';
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const admin = {auth: {uid: 'admin1', token: {admin: true, email_verified: true}}};
  await db.collection('_adminSessions').doc('admin1').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  await db.collection('settings').doc('business').set({name: 'Test', autoPublishVendorChanges: false});

  // ---- vendor: pending first, then approved
  const vendor = {auth: {uid: 'plV', token: {email_verified: true}}};
  await db.collection('vendors').doc('plV').set({vendorId: 'plV', name: 'Raj Store', shopId: 'plShop', status: 'approved', verified: true});
  await db.collection('vendorShopPhotos').doc('plV_1').set({vendorId: 'plV', slot: 1, status: 'approved'}); // photo 1 (the shop) is required before items
  await db.collection('shops').doc('plShop').set({name: 'Raj Store', address: 'Main Road', pincode: '533101', latitude: 16.99, longitude: 81.78, ownerId: 'plV', active: true});
  const sub = await fns.submitVendorChange.run({...vendor, data: {type: 'newProduct', collection: 'products', docId: '', changes: {name: 'Rice 25kg', price: 1200, stock: 10}}});
  assert.equal(sub.status, 'pending');
  assert.equal((await db.collection('products').doc(sub.docId).get()).exists, false, 'not on the site before approval');
  const change = (await db.collection('vendorChanges').where('docId', '==', sub.docId).get()).docs[0];
  await fns.reviewVendorChange.run({...admin, data: {changeId: change.id, approved: true}});
  const product = (await db.collection('products').doc(sub.docId).get()).data();
  assert.equal(product.active, true);
  assert.equal(product.shopId, 'plShop');
  assert.equal(product.pincode, '533101');
  assert.equal(product.town, 'Rajahmundry');
  assert.equal(product.state, 'Andhra Pradesh');
  assert.equal(product.latitude, 16.99);

  // ---- staff at a brand-new shop: shop and product both get the place
  await db.collection('fieldSubmissions').doc('fs1').set({
    staffUid: 's1', staffName: 'Staff One', shopId: '',
    shop: {name: 'Warangal Mart', address: 'Station Road', pincode: '506002', latitude: 17.97, longitude: 79.59},
    item: {name: 'Soap', price: 30, stock: 5, photoPaths: []}, visitLatitude: 17.97, visitLongitude: 79.59, status: 'pending',
  });
  const out = await fns.reviewFieldEntry.run({...admin, data: {entryId: 'fs1', approved: true}});
  const staffProduct = (await db.collection('products').doc(out.productId).get()).data();
  const staffShop = (await db.collection('shops').doc(out.shopId).get()).data();
  for (const doc of [staffProduct, staffShop]) {
    assert.equal(doc.pincode, '506002');
    assert.equal(doc.state, 'Telangana');
    assert.ok(doc.town);
  }
  // ---- staff at an existing shop: the product takes that shop's place
  await db.collection('fieldSubmissions').doc('fs2').set({staffUid: 's1', staffName: 'Staff One', shopId: 'plShop', shop: null, item: {name: 'Dal', price: 90, stock: 5, photoPaths: []}, visitLatitude: 16.99, visitLongitude: 81.78, status: 'pending'});
  const out2 = await fns.reviewFieldEntry.run({...admin, data: {entryId: 'fs2', approved: true}});
  assert.equal((await db.collection('products').doc(out2.productId).get()).data().town, 'Rajahmundry');
});
