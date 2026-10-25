const {test} = require('node:test');
const assert = require('node:assert/strict');
require('./index'); // starts the Firebase app that providers.js uses
const {providerApplication} = require('./providers');

const ok = {name: 'Suresh Kumar', phone: '9876543210', serviceTypeId: 'type-plumber', hourlyRate: 250, address: 'Door 4-12, Gandhi Nagar, Narsipatnam', pincode: '531116', latitude: 17.668, longitude: 82.612};

test('a provider application needs a name, mobile, a service from the list, a charge per hour, the house address and the location', () => {
  assert.deepEqual(providerApplication({...ok, hourlyRate: 199.999}).hourlyRate, 200);
  assert.throws(() => providerApplication({...ok, name: 'S'}), /full name/);
  assert.throws(() => providerApplication({...ok, phone: 'abc'}), /mobile/);
  assert.throws(() => providerApplication({...ok, serviceTypeId: ''}), /service/);
  assert.throws(() => providerApplication({...ok, hourlyRate: 0}), /per hour/);
  assert.throws(() => providerApplication({...ok, hourlyRate: '300'}), /per hour/);
  assert.throws(() => providerApplication({...ok, latitude: undefined}), /location/);
  assert.throws(() => providerApplication({...ok, pincode: '5311'}), /pincode/);
  assert.equal(providerApplication({...ok, gpsAddress: ' Gandhi Nagar,  Narsipatnam '}).gpsAddress, 'Gandhi Nagar, Narsipatnam');
});

test('a service provider registers (separately from vendors), the admin approves, and the listing goes into services with the photo and the hourly charge', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const fns = require('./index');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  const admin = {auth: {uid: 'admin1', token: {admin: true, email_verified: true}}};
  await db.collection('_adminSessions').doc('admin1').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  await db.collection('services').doc('type-plumber').set({kind: 'serviceType', typeId: 'plumber', name: 'Plumber', imageFileName: 'plumber.webp', order: 1, active: true});
  const as = uid => ({auth: {uid, token: {email_verified: true, email: `${uid}@example.test`}}});
  const register = (uid, data = ok) => fns.registerProvider.run({...as(uid), data});
  const photo = uid => bucket.file(`providerApplications/${uid}/photo`).save(Buffer.from([0xff, 0xd8, 0xff]), {metadata: {contentType: 'image/jpeg'}});

  // ---- the photo is required; the service must be one of the admin's service types
  await assert.rejects(() => register('provA'), /photo/);
  await photo('provA');
  await assert.rejects(() => register('provA', {...ok, serviceTypeId: 'type-astronaut'}), /service from the list/);
  const registered = await register('provA');
  assert.equal(registered.status, 'pending');
  assert.match(registered.providerCode, /^SRV-NRPM-116-\d{3}$/, 'the Provider ID, like the Vendor ID');
  const app = (await db.collection('providerApplications').doc('provA').get()).data();
  assert.equal(app.providerCode, registered.providerCode);
  assert.equal(app.serviceName, 'Plumber');
  assert.equal(app.hourlyRate, 250);
  await assert.rejects(() => register('provA'), /already under review/);

  // ---- one login is never both: a vendor account cannot become a provider, a provider account cannot become a vendor
  await db.collection('vendorApplications').doc('vendX').set({status: 'pending'});
  await photo('vendX');
  await assert.rejects(() => register('vendX'), /vendor account/);
  await assert.rejects(() => fns.registerVendor.run({...as('provA'), data: {ownerName: 'S K', phone: '9876543210', name: 'Shop', shopCategory: 'Kirana', address: 'Main Road, Narsipatnam', pincode: '531116', description: 'A shop for testing here', latitude: 17.668, longitude: 82.612}}), /service-provider account/);

  // ---- only the admin decides; a rejection needs a reason
  await assert.rejects(() => fns.approveProvider.run({...as('provA'), data: {providerId: 'provA', approved: true}}), /Administrator/);
  await assert.rejects(() => fns.approveProvider.run({...admin, data: {providerId: 'provA', approved: false}}), /reason/);

  // ---- approved: the listing is in services (never products), with the public photo, the charge per hour and the place
  const out = await fns.approveProvider.run({...admin, data: {providerId: 'provA', approved: true}});
  assert.equal(out.listingId, 'prov-provA');
  const listing = (await db.collection('services').doc('prov-provA').get()).data();
  assert.equal(listing.kind, 'service');
  assert.equal(listing.typeId, 'plumber', 'listed under the Plumber type');
  assert.equal(listing.name, 'Suresh Kumar');
  assert.equal(listing.price, 250);
  assert.equal(listing.providerCode, registered.providerCode);
  assert.equal((await db.collection('providers').doc('provA').get()).data().providerCode, registered.providerCode);
  assert.equal(listing.unit, 'per hour');
  assert.equal(listing.phone, '9876543210');
  assert.equal(listing.whatsapp, '919876543210');
  assert.equal(listing.town, 'Narsipatnam');
  assert.equal(listing.address, undefined, 'the house address is never public');
  assert.equal(listing.latitude, 17.67, 'only an approximate location (about 1 km)');
  assert.equal(listing.longitude, 82.61);
  assert.equal(listing.active, true);
  assert.match(listing.imageUrl, /catalog%2Fprovider_provA\.jpg\?alt=media$/);
  assert.equal((await bucket.file('catalog/provider_provA.jpg').exists())[0], true);
  assert.equal((await db.collection('products').doc('prov-provA').get()).exists, false);
  assert.equal((await db.collection('providers').doc('provA').get()).data().status, 'approved');
  await assert.rejects(() => fns.approveProvider.run({...admin, data: {providerId: 'provA', approved: false, reason: 'x'}}), /pending/);

  // ---- the provider changes the hourly charge: the listing shows it at once
  assert.deepEqual(await fns.updateProviderRate.run({...as('provA'), data: {hourlyRate: 300}}), {hourlyRate: 300});
  assert.equal((await db.collection('services').doc('prov-provA').get()).data().price, 300);
  await assert.rejects(() => fns.updateProviderRate.run({...as('nobody'), data: {hourlyRate: 300}}), /approved first/);
  await assert.rejects(() => fns.updateProviderRate.run({...as('provA'), data: {hourlyRate: -5}}), /per hour/);
});
