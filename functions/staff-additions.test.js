const {test} = require('node:test');
const assert = require('node:assert/strict');
require('./index'); // starts the Firebase app that staff-additions.js uses
const {_staffAdditions} = require('./staff-additions');
const {_photoCheck} = require('./photo-check');
// The emulator has no Google credentials: the Google check answers "not found online".
_photoCheck.setWebDetection(async () => ({}));
/// The admin checks every photo of an addition with Google (required before approving).
async function checkAll(db, additionId) {
  const addition = (await db.collection('staffAdditions').doc(additionId).get()).data();
  for (const path of [...addition.photoPaths, ...(addition.items || []).flatMap(item => item.photoPaths)]) await _photoCheck.checkPhotoAt(path, 'admin1');
}

const vendor = {name: 'Lakshmi Kirana', phone: '9876543210', ownerName: 'Lakshmi Devi', shopCategory: 'Kirana', address: 'Main Road, Narsipatnam', pincode: '531116'};
const items = [{libraryItemId: 'lib-tomato', unitType: 'kg', quantity: 1, price: 30, photoCount: 2}];
const ok = {vendor, latitude: 17.668, longitude: 82.612, items};

test('what keeps an auto-approved addition for the admin', () => {
  assert.equal(_staffAdditions.autoApproveProblem({label: 'vendor photo 1', online: 'none', duplicates: []}), '');
  assert.equal(_staffAdditions.autoApproveProblem({label: 'item 1 photo 1', online: 'partial', duplicates: []}), '', 'similar pictures online are fine');
  assert.equal(_staffAdditions.autoApproveProblem({label: 'vendor photo 2', online: 'full'}), 'vendor photo 2: this picture is online');
  assert.equal(_staffAdditions.autoApproveProblem({label: 'vendor photo 3', online: 'none', duplicates: [{path: 'x'}]}), 'vendor photo 3: the same photo was used before');
  assert.equal(_staffAdditions.autoApproveProblem({label: 'work photo 1', online: 'limit', note: 'used up'}), 'work photo 1: the Google check could not run (used up)');
});

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

test('a service provider a staff member adds needs a name, a phone, the staff GPS, the service, the charge per hour and 2-3 work photos', () => {
  const okProvider = {provider: {name: 'Suresh Kumar', phone: '9876543210', pincode: '531116'}, latitude: 17.668, longitude: 82.612, serviceTypeId: 'type-plumber', hourlyRate: 250, photoCount: 2};
  const details = _staffAdditions.staffProviderDetails(okProvider);
  assert.equal(details.provider.address, '', 'optional');
  assert.equal(_staffAdditions.staffProviderDetails({...okProvider, hourlyRate: 199.999}).hourlyRate, 200);
  assert.throws(() => _staffAdditions.staffProviderDetails({...okProvider, provider: {...okProvider.provider, name: 'S'}}), /provider's name/);
  assert.throws(() => _staffAdditions.staffProviderDetails({...okProvider, provider: {...okProvider.provider, phone: ''}}), /phone/);
  assert.throws(() => _staffAdditions.staffProviderDetails({...okProvider, longitude: undefined}), /location/);
  assert.throws(() => _staffAdditions.staffProviderDetails({...okProvider, serviceTypeId: ''}), /service/);
  assert.throws(() => _staffAdditions.staffProviderDetails({...okProvider, hourlyRate: 0}), /per hour/);
  assert.throws(() => _staffAdditions.staffProviderDetails({...okProvider, photoCount: 1}), /2 or 3 photos of their work/);
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

  // ---- every photo is checked with Google before the admin can approve
  await assert.rejects(() => fns.reviewStaffAddition.run({...admin, data: {additionId: 'addition0001', approved: true}}), /Check every photo with Google first: 8 of 8/);
  await _photoCheck.checkPhotoAt(`${folder('addition0001')}/vendor_1`, 'admin1');
  await assert.rejects(() => fns.reviewStaffAddition.run({...admin, data: {additionId: 'addition0001', approved: true}}), /7 of 8 not checked/);
  await checkAll(db, 'addition0001');

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

test('trusted staff: with auto-approve on (only the admin switches it), what they add goes live at once; off again, it waits', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const fns = require('./index');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  const as = uid => ({auth: {uid, token: {email_verified: true}}});
  const admin = {auth: {uid: 'admin1', token: {admin: true, email_verified: true}}};
  await db.collection('_adminSessions').doc('admin1').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  await db.collection('productImageLibrary').doc('lib-tomato').set({name: 'Tomato', categoryId: 'cat-vegetables', active: true});
  await db.collection('services').doc('type-plumber').set({kind: 'serviceType', typeId: 'plumber', name: 'Plumber', active: true});
  await db.collection('fieldStaff').doc('trusted').set({status: 'active', name: 'Ravi', staffCode: 'STF-NRPM-116-111'});
  await db.collection('fieldStaff').doc('waiting').set({status: 'pending'});
  // every photo different (the same photo twice would be held as "used before")
  const photo = path => bucket.file(path).save(Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.from(`${path}${Date.now()}`)]), {metadata: {contentType: 'image/jpeg'}});
  const stage = async (id, names) => { for (const name of names) await photo(`staffAdditions/trusted/${id}/${name}`); };

  // ---- only the admin switches it, and only for active staff; it is off until then
  await assert.rejects(() => fns.setStaffAutoApprove.run({...as('trusted'), data: {staffUid: 'trusted', enabled: true}}), /Administrator/);
  await assert.rejects(() => fns.setStaffAutoApprove.run({...admin, data: {staffUid: 'waiting', enabled: true}}), /active/);
  await assert.rejects(() => fns.setStaffAutoApprove.run({...admin, data: {staffUid: 'nobody', enabled: true}}), /not found/);
  await stage('autoAdd0001', ['vendor_1', 'vendor_2', 'vendor_3', 'item1_1', 'item1_2']);
  assert.equal((await fns.submitStaffVendor.run({...as('trusted'), data: {additionId: 'autoAdd0001', ...ok}})).status, 'pending', 'off by default');

  // ---- on: every photo is Google-checked, all pass, so a vendor and a provider go live at once, marked as auto-approved
  assert.deepEqual(await fns.setStaffAutoApprove.run({...admin, data: {staffUid: 'trusted', enabled: true}}), {autoApprove: true});
  assert.equal((await db.collection('fieldStaff').doc('trusted').get()).data().autoApproveBy, 'admin1');
  await stage('autoAdd0002', ['vendor_1', 'vendor_2', 'vendor_3', 'item1_1', 'item1_2']);
  const vendorOut = await fns.submitStaffVendor.run({...as('trusted'), data: {additionId: 'autoAdd0002', ...ok}});
  assert.deepEqual([vendorOut.status, vendorOut.autoApproved, vendorOut.vendorId], ['approved', true, 'autoAdd0002']);
  assert.equal((await db.collection('vendors').doc('autoAdd0002').get()).data().status, 'approved');
  assert.equal((await db.collection('products').where('additionId', '==', 'autoAdd0002').get()).size, 1);
  const addition = (await db.collection('staffAdditions').doc('autoAdd0002').get()).data();
  assert.deepEqual([addition.status, addition.autoApproved, addition.decidedBy], ['approved', true, 'auto:trusted']);
  assert.deepEqual(await _photoCheck.uncheckedPhotos([...addition.photoPaths, ...addition.items[0].photoPaths]), [], 'every photo was checked with Google');
  assert.equal((await db.collection('photoChecks').doc('staffAdditions~trusted~autoAdd0002~vendor_1').get()).data().checkedBy, 'auto:trusted');
  assert.equal((await bucket.file('staffAdditions/trusted/autoAdd0002/vendor_1').exists())[0], false);
  await stage('autoAdd0003', ['work_1', 'work_2']);
  const providerOut = await fns.submitStaffProvider.run({...as('trusted'), data: {additionId: 'autoAdd0003', provider: {name: 'Suresh Kumar', phone: '9876543210', pincode: '531116'}, latitude: 17.668, longitude: 82.612, serviceTypeId: 'type-plumber', hourlyRate: 250, photoCount: 2}});
  assert.deepEqual([providerOut.status, providerOut.listingId], ['approved', 'prov-autoAdd0003']);
  assert.equal((await db.collection('services').doc('prov-autoAdd0003').get()).data().active, true);

  // ---- a photo that is online as it is: it waits for the admin, with the reason
  _photoCheck.setWebDetection(async () => ({fullMatchingImages: [{url: 'https://stock.example/x.jpg'}]}));
  await stage('autoAdd0005', ['work_1', 'work_2']);
  const held = await fns.submitStaffProvider.run({...as('trusted'), data: {additionId: 'autoAdd0005', provider: {name: 'Mahesh', phone: '9876543210', pincode: '531116'}, latitude: 17.668, longitude: 82.612, serviceTypeId: 'type-plumber', hourlyRate: 300, photoCount: 2}});
  assert.equal(held.status, 'pending');
  assert.deepEqual(held.held, ['work photo 1: this picture is online', 'work photo 2: this picture is online']);
  assert.deepEqual((await db.collection('staffAdditions').doc('autoAdd0005').get()).data().autoApproveHeld, held.held);
  assert.equal((await db.collection('services').doc('prov-autoAdd0005').get()).exists, false);
  // ---- Google not reachable: the photos are not checked, so it waits too
  _photoCheck.setWebDetection(async () => { throw Error('Cloud Vision API is disabled'); });
  await stage('autoAdd0006', ['work_1', 'work_2']);
  const down = await fns.submitStaffProvider.run({...as('trusted'), data: {additionId: 'autoAdd0006', provider: {name: 'Naresh', phone: '9876543210', pincode: '531116'}, latitude: 17.668, longitude: 82.612, serviceTypeId: 'type-plumber', hourlyRate: 300, photoCount: 2}});
  assert.equal(down.status, 'pending');
  assert.match(down.held[0], /work photo 1: the Google check could not run \(Cloud Vision API is disabled\)/);
  _photoCheck.setWebDetection(async () => ({}));

  // ---- off again: it waits for the admin
  await fns.setStaffAutoApprove.run({...admin, data: {staffUid: 'trusted', enabled: false}});
  await stage('autoAdd0004', ['vendor_1', 'vendor_2', 'vendor_3', 'item1_1', 'item1_2']);
  assert.equal((await fns.submitStaffVendor.run({...as('trusted'), data: {additionId: 'autoAdd0004', ...ok}})).status, 'pending');
  assert.equal((await db.collection('vendors').doc('autoAdd0004').get()).exists, false);
});

test('staff add a service provider (pending, with the SRV ID); approved, the provider is listed under the service with the work photos', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const fns = require('./index');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  const as = uid => ({auth: {uid, token: {email_verified: true}}});
  const admin = {auth: {uid: 'admin1', token: {admin: true, email_verified: true}}};
  await db.collection('_adminSessions').doc('admin1').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  await db.collection('services').doc('type-plumber').set({kind: 'serviceType', typeId: 'plumber', name: 'Plumber', active: true});
  await db.collection('fieldStaff').doc('provStaff').set({status: 'active', name: 'Kiran Kumar', staffCode: 'STF-NRPM-116-482'});
  const photo = path => bucket.file(path).save(Buffer.from([0xff, 0xd8, 0xff]), {metadata: {contentType: 'image/jpeg'}});
  const data = {additionId: 'provAdd0001', provider: {name: 'Suresh Kumar', phone: '9876543210', address: 'Gandhi Nagar, Narsipatnam', pincode: '531116'}, latitude: 17.6685, longitude: 82.6126, serviceTypeId: 'type-plumber', hourlyRate: 250, photoCount: 2};
  const submit = (extra = {}) => fns.submitStaffProvider.run({...as('provStaff'), data: {...data, ...extra}});

  await assert.rejects(() => submit(), /photo 1 of their work/);
  await photo('staffAdditions/provStaff/provAdd0001/work_1');
  await photo('staffAdditions/provStaff/provAdd0001/work_2');
  await assert.rejects(() => submit({serviceTypeId: 'type-astronaut'}), /service from the list/);
  const out = await submit();
  assert.equal(out.status, 'pending');
  assert.match(out.providerCode, /^SRV-NRPM-116-\d{3}$/);
  const pending = (await db.collection('staffAdditions').doc('provAdd0001').get()).data();
  assert.deepEqual([pending.kind, pending.serviceName, pending.serviceTypeKey, pending.hourlyRate, pending.staffCode, pending.town], ['provider', 'Plumber', 'plumber', 250, 'STF-NRPM-116-482', 'Narsipatnam']);
  assert.equal((await db.collection('services').doc('prov-provAdd0001').get()).exists, false, 'nothing is live before the admin approves');

  await checkAll(db, 'provAdd0001');
  const approved = await fns.reviewStaffAddition.run({...admin, data: {additionId: 'provAdd0001', approved: true}});
  assert.deepEqual(approved, {status: 'approved', providerId: 'provAdd0001', listingId: 'prov-provAdd0001'});
  const listing = (await db.collection('services').doc('prov-provAdd0001').get()).data();
  assert.deepEqual([listing.kind, listing.typeId, listing.name, listing.price, listing.unit, listing.phone, listing.whatsapp, listing.providerCode, listing.active],
    ['service', 'plumber', 'Suresh Kumar', 250, 'per hour', '9876543210', '919876543210', out.providerCode, true]);
  assert.deepEqual([listing.latitude, listing.longitude, listing.town], [17.67, 82.61, 'Narsipatnam'], 'only an approximate location');
  assert.equal(listing.address, undefined, 'the address is never public');
  assert.match(listing.imageUrl, /catalog%2Fstaffprovider_provAdd0001_1\.jpg/);
  assert.equal(listing.images.length, 1);
  assert.equal((await db.collection('products').doc('prov-provAdd0001').get()).exists, false, 'services, never products');
  const record = (await db.collection('providers').doc('provAdd0001').get()).data();
  assert.deepEqual([record.status, record.providerCode, record.noLogin, record.addedByStaffUid], ['approved', out.providerCode, true, 'provStaff']);
  assert.equal((await bucket.file('staffAdditions/provStaff/provAdd0001/work_1').exists())[0], false);
});
