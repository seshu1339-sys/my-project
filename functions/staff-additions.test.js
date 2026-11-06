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

test('closed (6 Nov 2026): staff can no longer add vendors or providers, approve old additions, or change vendor prices; an old one can still be rejected', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const as = uid => ({auth: {uid, token: {email_verified: true}}});
  const admin = {auth: {uid: 'admin1', token: {admin: true, email_verified: true}}};
  await db.collection('_adminSessions').doc('admin1').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  await db.collection('fieldStaff').doc('closedStaff').set({status: 'active', name: 'Kiran Kumar', staffCode: 'STF-NRPM-116-482'});
  await assert.rejects(() => fns.submitStaffVendor.run({...as('closedStaff'), data: {additionId: 'addition0001', ...ok}}), /no longer add vendors/);
  await assert.rejects(() => fns.submitStaffProvider.run({...as('closedStaff'), data: {additionId: 'addition0002'}}), /no longer add vendors/);
  await assert.rejects(() => fns.renewStaffVendorPrice.run({...as('closedStaff'), data: {productId: 'p1', price: 30}}), /no longer change vendor prices/);
  await db.collection('staffAdditions').doc('oldWaiting').set({kind: 'vendor', status: 'pending', staffUid: 'closedStaff', photoPaths: [], items: []});
  await assert.rejects(() => fns.reviewStaffAddition.run({...admin, data: {additionId: 'oldWaiting', approved: true}}), /closed/);
  assert.deepEqual(await fns.reviewStaffAddition.run({...admin, data: {additionId: 'oldWaiting', approved: false, reason: 'Closed: register in the vendor app'}}), {status: 'rejected'});
});
