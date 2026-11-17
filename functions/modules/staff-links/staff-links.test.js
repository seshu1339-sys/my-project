const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {Timestamp} = require('firebase-admin/firestore');
const {parseCode, linkProblem, LINK_WINDOW_MS} = require('./rules');
const {linkAccount, removeLink, disableOldStaffAdded} = require('./store');

test('an ID tells a vendor (VEN) from a service provider (SRV); anything else is refused', () => {
  assert.deepEqual(parseCode(' ven-nrpm-116-325 '), {kind: 'vendor', code: 'VEN-NRPM-116-325'});
  assert.deepEqual(parseCode('SRV-NRPM-116-001'), {kind: 'provider', code: 'SRV-NRPM-116-001'});
  for (const bad of ['STF-NRPM-116-001', 'VEN-NRPM-116', 'hello', '', null]) assert.equal(parseCode(bad), null, String(bad));
});

test('linking is possible for 30 minutes from the registration, not after', () => {
  const at = Date.parse('2026-11-06T10:00:00Z');
  assert.equal(linkProblem(at, at + 1000), null);
  assert.equal(linkProblem(at, at + LINK_WINDOW_MS), null);
  assert.match(linkProblem(at, at + LINK_WINDOW_MS + 1), /30 minutes/);
  assert.match(linkProblem(0, at), /no time yet/);
});

const emulator = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
const t0 = Date.parse('2031-03-05T10:00:00+05:30');
async function setup() {
  const {getFirestore} = require('firebase-admin/firestore');
  const db = getFirestore();
  for (const c of ['staffLinks', 'vendorApplications', 'providerApplications', 'fieldStaff', 'vendors', 'providers', 'products', 'shops', 'services', 'staffAdditions', 'staffAreas', 'staffAreaHolders', 'staffAreaStaff']) {
    for (const d of (await db.collection(c).get()).docs) await d.ref.delete();
  }
  await db.collection('fieldStaff').doc('s1').set({status: 'active', name: 'Kiran', staffCode: 'STF-NRPM-116-482'});
  await db.collection('fieldStaff').doc('s2').set({status: 'active', name: 'Ravi', staffCode: 'STF-NRPM-116-483'});
  await db.collection('fieldStaff').doc('waiting').set({status: 'pending'});
  const here = {latitude: 17.6685, longitude: 82.6125};
  await db.collection('vendorApplications').doc('v1').set({name: 'Lakshmi Kirana', vendorCode: 'VEN-NRPM-116-325', status: 'pending', town: 'Narsipatnam', submittedAt: Timestamp.fromMillis(t0), ...here});
  await db.collection('providerApplications').doc('p1').set({name: 'Raju Plumber', providerCode: 'SRV-NRPM-116-001', status: 'pending', submittedAt: Timestamp.fromMillis(t0), ...here});
  // s1 and s2 each hold an area around the same bazaar (in real life areas never overlap; here both may link the test shop).
  for (const [staff, area] of [['s1', 'a1'], ['s2', 'a2']]) {
    await db.collection('staffAreas').doc(area).set({name: `Area ${area}`, latitude: 17.668, longitude: 82.612, radiusKm: 1, status: 'booked'});
    await db.collection('staffAreaHolders').doc(area).set({staffUid: staff});
    await db.collection('staffAreaStaff').doc(staff).set({areaId: area});
  }
  return db;
}

test('staff link a vendor within 30 minutes: saved once, shown on the registration; another staff member cannot take it', emulator, async () => {
  const db = await setup();
  const result = await linkAccount(db, 's1', {code: 'ven-nrpm-116-325'}, t0 + 10 * 60000);
  assert.equal(result.kind, 'vendor');
  assert.equal(result.name, 'Lakshmi Kirana');
  const link = (await db.collection('staffLinks').doc('vendor_v1').get()).data();
  assert.equal(link.staffCode, 'STF-NRPM-116-482');
  assert.equal(link.accountUid, 'v1');
  assert.equal(link.registeredAt.toMillis(), t0);
  assert.equal((await db.collection('vendorApplications').doc('v1').get()).data().registeredByStaffCode, 'STF-NRPM-116-482');
  await assert.rejects(linkAccount(db, 's1', {code: 'VEN-NRPM-116-325'}, t0 + 11 * 60000), /already linked this/);
  await assert.rejects(linkAccount(db, 's2', {code: 'VEN-NRPM-116-325'}, t0 + 11 * 60000), /already linked to STF-NRPM-116-482/);
});

test('a provider links the same way; too late, unknown, rejected or by staff not yet approved is refused', emulator, async () => {
  const db = await setup();
  assert.equal((await linkAccount(db, 's2', {code: 'SRV-NRPM-116-001'}, t0 + 60000)).kind, 'provider');
  assert.equal((await db.collection('staffLinks').doc('provider_p1').get()).data().staffUid, 's2');
  await db.collection('vendorApplications').doc('late').set({name: 'Late', vendorCode: 'VEN-NRPM-116-400', status: 'pending', submittedAt: Timestamp.fromMillis(t0), latitude: 17.6685, longitude: 82.6125});
  await assert.rejects(linkAccount(db, 's1', {code: 'VEN-NRPM-116-400'}, t0 + 31 * 60000), /30 minutes/);
  assert.equal((await db.collection('staffLinks').doc('vendor_late').get()).exists, false);
  await assert.rejects(linkAccount(db, 's1', {code: 'VEN-NRPM-116-999'}, t0), /No registration/);
  await assert.rejects(linkAccount(db, 's1', {code: 'nonsense'}, t0), /Enter the ID/);
  await db.collection('vendorApplications').doc('no').set({vendorCode: 'VEN-NRPM-116-401', status: 'rejected', submittedAt: Timestamp.fromMillis(t0), latitude: 17.6685, longitude: 82.6125});
  await assert.rejects(linkAccount(db, 's1', {code: 'VEN-NRPM-116-401'}, t0), /not approved/);
  await assert.rejects(linkAccount(db, 'waiting', {code: 'VEN-NRPM-116-325'}, t0), /approved staff/);
});

test('the admin removes a wrong link; the person stays and can be linked again in time', emulator, async () => {
  const db = await setup();
  await linkAccount(db, 's1', {code: 'VEN-NRPM-116-325'}, t0 + 60000);
  await removeLink(db, {linkId: 'vendor_v1'});
  assert.equal((await db.collection('staffLinks').doc('vendor_v1').get()).exists, false);
  assert.equal((await db.collection('vendorApplications').doc('v1').get()).data().registeredByStaffCode, undefined);
  await linkAccount(db, 's2', {code: 'VEN-NRPM-116-325'}, t0 + 2 * 60000);
  await assert.rejects(removeLink(db, {linkId: 'nope'}), /not found/);
});

test('the old way: staff-created vendors and providers are suspended and hidden, waiting additions closed; own vendors untouched', emulator, async () => {
  const db = await setup();
  await db.collection('vendors').doc('old').set({status: 'approved', noLogin: true, addedByStaffUid: 's1', name: 'Old Kirana'});
  await db.collection('shops').doc('old').set({ownerId: 'old', active: true});
  await db.collection('products').doc('oldItem').set({ownerId: 'old', active: true});
  await db.collection('vendors').doc('own').set({status: 'approved', name: 'Own shop'});
  await db.collection('products').doc('ownItem').set({ownerId: 'own', active: true});
  await db.collection('providers').doc('oldP').set({status: 'approved', noLogin: true, addedByStaffUid: 's1'});
  await db.collection('services').doc('prov-oldP').set({ownerId: 'oldP', active: true});
  await db.collection('staffAdditions').doc('w1').set({status: 'pending', kind: 'vendor'});
  const counts = await disableOldStaffAdded(db, 'admin1', t0);
  assert.deepEqual(counts, {vendors: 1, providers: 1, items: 3, waitingClosed: 1});
  assert.equal((await db.collection('vendors').doc('old').get()).data().status, 'suspended');
  assert.equal((await db.collection('products').doc('oldItem').get()).data().active, false);
  assert.equal((await db.collection('services').doc('prov-oldP').get()).data().active, false);
  assert.equal((await db.collection('vendors').doc('own').get()).data().status, 'approved');
  assert.equal((await db.collection('products').doc('ownItem').get()).data().active, true);
  assert.equal((await db.collection('staffAdditions').doc('w1').get()).data().status, 'closed');
  assert.deepEqual(await disableOldStaffAdded(db, 'admin1', t0 + 1000), {vendors: 0, providers: 0, items: 0, waitingClosed: 0}, 'pressing again changes nothing');
});

test("only registrations inside the staff member's own area can be linked (owner, 6 Nov 2026)", emulator, async () => {
  const db = await setup();
  await db.collection('vendorApplications').doc('far').set({name: 'Far Shop', vendorCode: 'VEN-NRPM-116-500', status: 'pending', submittedAt: Timestamp.fromMillis(t0), latitude: 17.75, longitude: 82.70});
  await assert.rejects(linkAccount(db, 's1', {code: 'VEN-NRPM-116-500'}, t0 + 60000), /outside your area/);
  await db.collection('staffAreaStaff').doc('s1').set({areaId: null});
  await assert.rejects(linkAccount(db, 's1', {code: 'VEN-NRPM-116-325'}, t0 + 60000), /own area first/);
});
