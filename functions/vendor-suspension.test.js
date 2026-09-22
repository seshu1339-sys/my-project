const {test} = require('node:test');
const assert = require('node:assert/strict');

test('admin can suspend and reinstate a vendor; access and catalog follow', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const admin = {auth: {uid: 'admin1', token: {admin: true, email_verified: true}}};
  const vendor = {auth: {uid: 'susV', token: {email_verified: true}}};
  const suspend = (data, ctx = admin) => fns.setVendorSuspension.run({...ctx, data});
  await db.collection('vendors').doc('susV').set({vendorId: 'susV', name: 'Sus Shop', shopId: 'susShop', status: 'approved', verified: true});
  await db.collection('vendors').doc('pendingV').set({vendorId: 'pendingV', name: 'Not approved', shopId: 'pendingV', status: 'payment_required'});
  await db.collection('shops').doc('susShop').set({name: 'Sus Shop', ownerId: 'susV', active: true});
  await db.collection('products').doc('susOwned').set({name: 'Owned', ownerId: 'susV', shopId: 'susShop', price: 10, stock: 5, active: true});
  await db.collection('products').doc('susShopItem').set({name: 'At the shop', shopId: 'susShop', price: 10, stock: 5, active: true});
  await db.collection('products').doc('susOther').set({name: 'Someone else', shopId: 'otherShop', price: 10, stock: 5, active: true});
  await db.collection('products').doc('susAdminHidden').set({name: 'Hidden by admin', ownerId: 'susV', shopId: 'susShop', price: 10, stock: 5, active: false});
  const flag = async id => (await db.collection('products').doc(id).get()).data();

  // ---- who may do it, and to whom
  await assert.rejects(() => suspend({vendorId: 'susV', suspended: true, reason: 'x'}, {auth: {uid: 'susV', token: {email_verified: true}}}), /Administrator/);
  await assert.rejects(() => suspend({vendorId: 'susV', suspended: true, reason: 'x'}, {}), /Sign in/);
  await assert.rejects(() => suspend({vendorId: 'susV', suspended: true, reason: ''}), /reason/i);           // a reason is required
  await assert.rejects(() => suspend({vendorId: 'nobody', suspended: true, reason: 'because'}), /not found/i);
  await assert.rejects(() => suspend({vendorId: 'pendingV', suspended: true, reason: 'because'}), /approved vendor/);
  await assert.rejects(() => suspend({vendorId: 'susV', suspended: false}), /not suspended/);                 // cannot "reinstate" an active vendor
  await assert.rejects(() => suspend({vendorId: '../x', suspended: true, reason: 'because'}), /Provide/);

  // ---- a queued change exists before the suspension
  const pendingChange = await db.collection('vendorChanges').add({vendorId: 'susV', vendorName: 'Sus Shop', type: 'price', collection: 'products', docId: 'susOwned', oldValue: {price: 10}, newValue: {price: 1}, status: 'pending'});
  const pendingChange2 = await db.collection('vendorChanges').add({vendorId: 'susV', vendorName: 'Sus Shop', type: 'price', collection: 'products', docId: 'susOwned', oldValue: {price: 10}, newValue: {price: 2}, status: 'pending'});

  // ---- suspend
  const out = await suspend({vendorId: 'susV', suspended: true, reason: 'Repeated customer complaints'});
  assert.equal(out.status, 'suspended'); assert.equal(out.itemsChanged, 3);          // 2 products + the shop
  const v = (await db.collection('vendors').doc('susV').get()).data();
  assert.equal(v.status, 'suspended'); assert.equal(v.suspensionReason, 'Repeated customer complaints'); assert.equal(v.suspendedBy, 'admin1');
  assert.equal((await flag('susOwned')).active, false); assert.equal((await flag('susShopItem')).active, false);
  assert.equal((await db.collection('shops').doc('susShop').get()).data().active, false);
  assert.equal((await flag('susOther')).active, true);                                // other shops untouched
  assert.equal((await flag('susAdminHidden')).hiddenBySuspension, undefined);         // already hidden: left alone
  await assert.rejects(() => suspend({vendorId: 'susV', suspended: true, reason: 'again'}), /approved vendor/);   // not twice

  // ---- the vendor is locked out of every business function
  await assert.rejects(() => fns.submitVendorChange.run({...vendor, data: {type: 'newProduct', collection: 'products', docId: '', changes: {name: 'New thing', price: 5}}}), /approved/);
  await assert.rejects(() => fns.submitVendorChange.run({...vendor, data: {type: 'price', collection: 'products', docId: 'susOwned', changes: {price: 3}}}), /approved/);
  await db.collection('orders').doc('susOrder').set({userId: 'c', shopIds: ['susShop'], status: 'submitted', lines: [], total: 1});
  await assert.rejects(() => fns.updateVendorOrder.run({...vendor, data: {orderId: 'susOrder', status: 'confirmed'}}), /cannot update/);
  await assert.rejects(() => fns.redeemPurchaseCode.run({...vendor, data: {orderId: 'susOrder', code: '123456', latitude: 12.9, longitude: 77.5}}), /Verified vendor/);
  // ...and its queued changes cannot be published while suspended (rejecting them is still fine)
  await assert.rejects(() => fns.reviewVendorChange.run({...admin, data: {changeId: pendingChange.id, approved: true}}), /not active/);
  assert.equal((await flag('susOwned')).price, 10);
  await fns.reviewVendorChange.run({...admin, data: {changeId: pendingChange2.id, approved: false, reason: 'suspended'}});
  // a suspended vendor cannot re-apply either
  await db.collection('vendorApplications').doc('susV').set({status: 'approved'});
  await assert.rejects(() => fns.registerVendor.run({...vendor, data: {ownerName: 'Sus Owner', phone: '9876543210', name: 'Sus Shop', shopCategory: 'General', address: '1 Road Street', pincode: '560001', description: 'A shop description', latitude: 12.97, longitude: 77.59}}), /already under review|photo/i);

  // ---- reinstate
  const back = await suspend({vendorId: 'susV', suspended: false});
  assert.equal(back.status, 'approved'); assert.equal(back.itemsChanged, 3);
  const r = (await db.collection('vendors').doc('susV').get()).data();
  assert.equal(r.status, 'approved'); assert.equal(r.suspensionReason, undefined); assert.equal(r.reinstatedBy, 'admin1');
  assert.equal((await flag('susOwned')).active, true); assert.equal((await flag('susOwned')).hiddenBySuspension, undefined);
  assert.equal((await flag('susShopItem')).active, true);
  assert.equal((await db.collection('shops').doc('susShop').get()).data().active, true);
  assert.equal((await flag('susAdminHidden')).active, false);                          // the admin's own choice survives
  await assert.rejects(() => suspend({vendorId: 'susV', suspended: false}), /not suspended/);
  const ok = await fns.submitVendorChange.run({...vendor, data: {type: 'price', collection: 'products', docId: 'susOwned', changes: {price: 3}}});
  assert.ok(['pending', 'approved'].includes(ok.status));                              // trading again
  await fns.updateVendorOrder.run({...vendor, data: {orderId: 'susOrder', status: 'confirmed'}});
  assert.equal((await db.collection('orders').doc('susOrder').get()).data().status, 'confirmed');
});
