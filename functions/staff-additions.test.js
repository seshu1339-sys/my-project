const {test} = require('node:test');
const assert = require('node:assert/strict');
require('./index'); // starts the Firebase app that staff-additions.js uses
const {_staffAdditions} = require('./staff-additions');

const vendor = {name: 'Lakshmi Kirana', phone: '9876543210', ownerName: 'Lakshmi Devi', shopCategory: 'Kirana', address: 'Main Road, Narsipatnam', pincode: '531116'};
const items = [{libraryItemId: 'lib-tomato', unitType: 'kg', quantity: 1, price: 30, photoCount: 2}];
const ok = {vendor, latitude: 17.668, longitude: 82.612, items};

test('a vendor a staff member adds needs a name, a phone, the staff GPS, and 1-2 library items with 2-3 photos each', () => {
  const details = _staffAdditions.staffVendorDetails(ok);
  assert.equal(details.vendor.name, 'Lakshmi Kirana');
  assert.equal(details.vendor.description, '', 'optional');
  assert.throws(() => _staffAdditions.staffVendorDetails({...ok, vendor: {...vendor, name: ''}}), /vendor's name/);
  assert.throws(() => _staffAdditions.staffVendorDetails({...ok, vendor: {...vendor, phone: '12'}}), /phone/);
  assert.throws(() => _staffAdditions.staffVendorDetails({...ok, latitude: undefined}), /location/);
  assert.throws(() => _staffAdditions.staffVendorDetails({...ok, items: []}), /at least one item/);
  assert.throws(() => _staffAdditions.staffVendorDetails({...ok, items: [...items, ...items, ...items]}), /2 items/);
  assert.throws(() => _staffAdditions.staffVendorDetails({...ok, items: [{...items[0], photoCount: 1}]}), /Item 1: add 2 or 3 photos/);
  assert.throws(() => _staffAdditions.staffVendorDetails({...ok, items: [{...items[0], quantity: 11}]}), /quantity/);
  assert.throws(() => _staffAdditions.staffVendorDetails({...ok, items: [{...items[0], price: 0}]}), /price/);
});

test('staff add a vendor (pending), the admin approves: the vendor, its shop and its items go live with the photos; the staff member renews prices', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const fns = require('./index');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  const as = uid => ({auth: {uid, token: {email_verified: true}}});
  const admin = {auth: {uid: 'admin1', token: {admin: true, email_verified: true}}};
  await db.collection('_adminSessions').doc('admin1').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  await db.collection('productImageLibrary').doc('lib-tomato').set({name: 'Tomato', categoryId: 'cat-vegetables', imageUrl: 'https://example.test/tomato.jpg', active: true});
  await db.collection('productImageLibrary').doc('lib-onion').set({name: 'Onion', categoryId: 'cat-vegetables', imageUrl: 'https://example.test/onion.jpg', active: true});
  await db.collection('fieldStaff').doc('addStaff').set({status: 'active', name: 'Kiran Kumar', staffCode: 'STF-NRPM-116-482'});
  await db.collection('fieldStaff').doc('waitStaff').set({status: 'pending'});
  const photo = path => bucket.file(path).save(Buffer.from([0xff, 0xd8, 0xff]), {metadata: {contentType: 'image/jpeg'}});
  const folder = id => `staffAdditions/addStaff/${id}`;
  const twoItems = [items[0], {libraryItemId: 'lib-onion', unitType: 'kg', quantity: 2, price: 50, photoCount: 3}];
  const submit = (id, data = {...ok, items: twoItems}, who = 'addStaff') => fns.submitStaffVendor.run({...as(who), data: {additionId: id, ...data}});

  // ---- only approved staff; every photo is required (3 of the vendor, 2-3 of each item)
  await assert.rejects(() => submit('addition0001', ok, 'waitStaff'), /approved/);
  await assert.rejects(() => submit('addition0001'), /the vendor's photo/);
  for (const n of [1, 2, 3]) await photo(`${folder('addition0001')}/vendor_${n}`);
  await assert.rejects(() => submit('addition0001'), /photo 1 of item 1/);
  for (const name of ['item1_1', 'item1_2', 'item2_1', 'item2_2']) await photo(`${folder('addition0001')}/${name}`);
  await assert.rejects(() => submit('addition0001'), /photo 3 of item 2/);
  await photo(`${folder('addition0001')}/item2_3`);
  await assert.rejects(() => submit('addition0001', {...ok, items: [{...items[0], libraryItemId: 'lib-nothing'}]}), /choose an item from the list/);

  // ---- added: pending, with the Vendor ID and the staff member who added it
  const out = await submit('addition0001');
  assert.equal(out.status, 'pending');
  assert.match(out.vendorCode, /^VEN-NRPM-116-\d{3}$/);
  const pending = (await db.collection('staffAdditions').doc('addition0001').get()).data();
  assert.deepEqual([pending.kind, pending.staffUid, pending.staffCode, pending.vendor.phone, pending.town, pending.latitude], ['vendor', 'addStaff', 'STF-NRPM-116-482', '9876543210', 'Narsipatnam', 17.668]);
  assert.deepEqual(pending.items.map(i => [i.name, i.unit, i.price, i.photoPaths.length]), [['Tomato', '1 kg', 30, 2], ['Onion', '2 kg', 50, 3]]);
  assert.equal((await db.collection('vendors').doc('addition0001').get()).exists, false, 'nothing is live before the admin approves');
  assert.equal((await db.collection('products').where('additionId', '==', 'addition0001').get()).size, 0);
  assert.equal((await submit('addition0001')).status, 'pending', 'sending again changes nothing');
  await assert.rejects(() => submit('addition0001', ok, 'waitStaff'), /approved/);

  // ---- only the admin decides; a rejection needs a reason
  await assert.rejects(() => fns.reviewStaffAddition.run({...as('addStaff'), data: {additionId: 'addition0001', approved: true}}), /Administrator/);
  await assert.rejects(() => fns.reviewStaffAddition.run({...admin, data: {additionId: 'addition0001', approved: false}}), /reason/);

  // ---- approved: the vendor (no login of its own), its shop with the photos, address and phone, and its items, live at the place
  const approved = await fns.reviewStaffAddition.run({...admin, data: {additionId: 'addition0001', approved: true}});
  assert.equal(approved.status, 'approved');
  const v = (await db.collection('vendors').doc('addition0001').get()).data();
  assert.deepEqual([v.status, v.name, v.vendorCode, v.noLogin, v.addedByStaffUid, v.shopId], ['approved', 'Lakshmi Kirana', out.vendorCode, true, 'addStaff', 'addition0001']);
  const shop = (await db.collection('shops').doc('addition0001').get()).data();
  assert.deepEqual([shop.name, shop.phone, shop.whatsapp, shop.address, shop.town, shop.latitude, shop.active], ['Lakshmi Kirana', '9876543210', '919876543210', 'Main Road, Narsipatnam', 'Narsipatnam', 17.668, true]);
  assert.match(shop.imageUrl, /catalog%2Fstaffvendor_addition0001_1\.jpg\?alt=media$/);
  assert.equal(shop.images.length, 2);
  const products = (await db.collection('products').where('additionId', '==', 'addition0001').get()).docs.map(d => ({id: d.id, ...d.data()}));
  assert.equal(products.length, 2);
  const tomato = products.find(p => p.name === 'Tomato');
  assert.deepEqual([tomato.ownerId, tomato.shopId, tomato.price, tomato.unit, tomato.categoryId, tomato.active, tomato.town, tomato.priceExpired], ['addition0001', 'addition0001', 30, '1 kg', 'cat-vegetables', true, 'Narsipatnam', false]);
  assert.match(tomato.imageUrl, new RegExp(`catalog%2F${tomato.id}_1\\.jpg`), "the staff member's photo of the item");
  assert.equal(tomato.images.length, 1);
  assert.ok(tomato.priceExpiresAt, 'the price lasts 24 hours, like a vendor\'s own');
  assert.equal((await bucket.file(`${folder('addition0001')}/vendor_1`).exists())[0], false, 'the private originals are removed');
  await assert.rejects(() => fns.reviewStaffAddition.run({...admin, data: {additionId: 'addition0001', approved: true}}), /already reviewed/);

  // ---- the staff member who added the vendor enters a new price (24 hours again); nobody else can
  await db.collection('products').doc(tomato.id).update({price: require('firebase-admin/firestore').FieldValue.delete(), priceExpired: true});
  assert.deepEqual(await fns.renewStaffVendorPrice.run({...as('addStaff'), data: {productId: tomato.id, price: 32}}), {price: 32});
  const renewed = (await db.collection('products').doc(tomato.id).get()).data();
  assert.deepEqual([renewed.price, renewed.priceExpired], [32, false]);
  await db.collection('fieldStaff').doc('otherStaff').set({status: 'active'});
  await assert.rejects(() => fns.renewStaffVendorPrice.run({...as('otherStaff'), data: {productId: tomato.id, price: 32}}), /only of the vendors you added/);
  await assert.rejects(() => fns.renewStaffVendorPrice.run({...as('addStaff'), data: {productId: tomato.id, price: -1}}), /price/);

  // ---- rejected: nothing goes live, the staff member sees the reason, the private photos are removed
  for (const name of ['vendor_1', 'vendor_2', 'vendor_3', 'item1_1', 'item1_2']) await photo(`${folder('addition0002')}/${name}`);
  await submit('addition0002', ok);
  assert.deepEqual(await fns.reviewStaffAddition.run({...admin, data: {additionId: 'addition0002', approved: false, reason: 'Photos are blurred'}}), {status: 'rejected'});
  const rejected = (await db.collection('staffAdditions').doc('addition0002').get()).data();
  assert.deepEqual([rejected.status, rejected.decisionReason], ['rejected', 'Photos are blurred']);
  assert.equal((await db.collection('vendors').doc('addition0002').get()).exists, false);
  assert.equal((await bucket.file(`${folder('addition0002')}/vendor_1`).exists())[0], false);
});
