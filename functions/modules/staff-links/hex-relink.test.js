// A cancelled staff ID (owner, 13 Nov 2026): their linked vendors and providers move under the admin, and the admin links the cell's
// vendors to the cell's next staff member in one click. Linking also works by the hexagon cell.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const G = require('../../hex-grid');
const {areaProblem} = require('./rules');
const {moveLinksToAdmin, relinkAreaVendors, linkAccount} = require('./store');

const emulator = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
const IN = {latitude: 17.7110, longitude: 83.3010};
const OUT = {latitude: 17.7600, longitude: 83.3010};

test('linking by the hexagon cell: inside the cell yes, outside no', () => {
  const cell = G.cellAt(IN.latitude, IN.longitude);
  const area = {name: 'HX1 cell', hexCell: cell, latitude: 17.71, longitude: 83.3, radiusKm: 0.6};
  assert.equal(areaProblem(area, IN), null);
  assert.match(areaProblem(area, OUT), /outside your area/);
});

test('cancelled staff: links move under the admin; the next staff of the cell gets the cell\'s vendors in one click', emulator, async () => {
  const db = getFirestore();
  const t = `hx${Date.now()}`;
  const cell = G.cellAt(IN.latitude, IN.longitude);
  await db.collection('fieldStaff').doc(`${t}old`).set({status: 'cancelled', name: 'Old', staffCode: 'STF-NRPM-116-701'});
  await db.collection('fieldStaff').doc(`${t}new`).set({status: 'active', name: 'New', staffCode: 'STF-NRPM-116-702'});
  const app = (id, place, code) => db.collection('vendorApplications').doc(id).set({name: id, vendorCode: code, status: 'approved', ...place, submittedAt: Timestamp.now()});
  await app(`${t}v1`, IN, 'VEN-NRPM-116-801');
  await app(`${t}v2`, IN, 'VEN-NRPM-116-802');
  await app(`${t}v3`, OUT, 'VEN-NRPM-116-803');
  for (const n of [1, 2, 3]) {
    await db.collection('staffLinks').doc(`vendor_${t}v${n}`).set({kind: 'vendor', accountUid: `${t}v${n}`, code: `VEN-NRPM-116-80${n}`, name: `${t}v${n}`, staffUid: `${t}old`, staffCode: 'STF-NRPM-116-701', staffName: 'Old'});
  }
  assert.equal(await moveLinksToAdmin(db, `${t}old`), 3);
  const moved = (await db.collection('staffLinks').doc(`vendor_${t}v1`).get()).data();
  assert.deepEqual([moved.staffUid, moved.underAdmin, moved.previousStaffCode], ['', true, 'STF-NRPM-116-701']);
  assert.equal((await db.collection('staffLinks').where('staffUid', '==', `${t}old`).get()).size, 0, 'the old ID has nobody now');

  // Staff cannot take a vendor that is with the office.
  await assert.rejects(linkAccount(db, `${t}new`, {code: 'VEN-NRPM-116-801'}), /LOCAMARKET office|area/);

  // The new staff member holds the same cell.
  await db.collection('staffAreas').doc(cell).set({name: 'HX1 cell', hex: true, hexCell: cell, latitude: IN.latitude, longitude: IN.longitude, radiusKm: 0.6, status: 'booked'});
  await db.collection('staffAreaHolders').doc(cell).set({staffUid: `${t}new`});
  await db.collection('staffAreaStaff').doc(`${t}new`).set({staffUid: `${t}new`, areaId: cell});
  const preview = await relinkAreaVendors(db, 'admin1', {staffUid: `${t}new`, preview: true});
  assert.ok(preview.count >= 2, 'the two vendors inside the cell');
  const before = (await db.collection('staffLinks').doc(`vendor_${t}v3`).get()).data();
  const done = await relinkAreaVendors(db, 'admin1', {staffUid: `${t}new`});
  assert.equal(done.count, preview.count);
  for (const n of [1, 2]) {
    const link = (await db.collection('staffLinks').doc(`vendor_${t}v${n}`).get()).data();
    assert.deepEqual([link.staffUid, link.staffCode, link.underAdmin, link.linkedBy], [`${t}new`, 'STF-NRPM-116-702', undefined, 'admin']);
  }
  const outside = (await db.collection('staffLinks').doc(`vendor_${t}v3`).get()).data();
  assert.deepEqual([outside.staffUid, outside.underAdmin], [before.staffUid, true], 'a vendor outside the cell stays with the admin');
  await assert.rejects(relinkAreaVendors(db, 'admin1', {staffUid: `${t}old`}), /approved staff/);
  await db.collection('staffAreas').doc(cell).delete();
  await db.collection('staffAreaHolders').doc(cell).delete();
});
