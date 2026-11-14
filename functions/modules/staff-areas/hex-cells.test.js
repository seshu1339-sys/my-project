// Staff hexagon cells (owner, 13 Nov 2026): the cells near a staff member, registering the cell where they stand (free, inside it,
// home within 5 km of its centre, Terms), one cell each, and a cancelled staff ID freeing it. The grid itself is tested in
// functions/hex-grid.test.js.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore} = require('firebase-admin/firestore');
const G = require('../../hex-grid');
const R = require('./rules');
const S = require('./store');

const emulator = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
// Visakhapatnam, Jagadamba Junction: a 1 km cell.
const HERE = {latitude: 17.7110, longitude: 83.3010};
const HOME_NEAR = {homeLatitude: 17.7290, homeLongitude: 83.3010, homeAddress: 'Door 12-3-4, Asilmetta, Visakhapatnam'};
const HOME_FAR = {homeLatitude: 17.8200, homeLongitude: 83.3010, homeAddress: 'Door 5-6, Madhurawada, Visakhapatnam'};

let seq = 0;
async function staff(status = 'pending') {
  const db = getFirestore();
  const uid = `hexStaff${Date.now()}${++seq}`;
  await db.collection('fieldStaff').doc(uid).set({status, name: `Staff ${seq}`, phone: '9876500000', staffCode: `STF-NRPM-116-${100 + seq}`, town: 'Visakhapatnam'});
  return uid;
}
async function clean() {
  const db = getFirestore();
  const cell = G.cellAt(HERE.latitude, HERE.longitude);
  for (const near of G.cellsNear(HERE.latitude, HERE.longitude)) {
    await db.collection('staffAreas').doc(near).delete();
    await db.collection('staffAreaHolders').doc(near).delete();
  }
  return cell;
}

test('a hexagon area holds exactly the places of its cell (targets, shops in the area and linking use this)', () => {
  const cell = G.cellAt(HERE.latitude, HERE.longitude);
  const area = {hexCell: cell, latitude: 17.71, longitude: 83.3, radiusKm: 0.6};
  assert.equal(R.inside(area, HERE.latitude, HERE.longitude), true);
  assert.equal(R.inside(area, 17.7600, 83.3010), false, '5 km away');
  assert.equal(R.inside(area, 51.5, -0.1), false, 'outside India');
  assert.equal(R.inside({latitude: 17.71, longitude: 83.3, radiusKm: 1}, 17.711, 83.301), true, 'an older circle area still works');
});

test('nearby: the cell where the staff member stands first, the cells around it free or taken, their own marked', emulator, async () => {
  const db = getFirestore();
  const cell = await clean();
  await assert.rejects(S.hexNearby(db, 'nobody', HERE), /Register as staff/);
  const a = await staff();
  await assert.rejects(S.hexNearby(db, a, {latitude: 51.5, longitude: -0.1}), /India/);
  const first = await S.hexNearby(db, a, HERE);
  assert.equal(first.cellId, cell);
  assert.match(first.code, /^HX1-/);
  assert.equal(first.sizeKm, 1);
  assert.equal(first.status, 'free');
  assert.equal(first.homeMaxKm, 5);
  assert.ok(first.cells.length > 7);
  assert.ok(first.cells.every(c => c.status === 'free' && c.outline.length >= 6));
  await S.claimHexCell(db, a, {...HERE, ...HOME_NEAR, termsAccepted: true});
  assert.equal((await S.hexNearby(db, a, HERE)).status, 'mine');
  const b = await staff();
  const seen = await S.hexNearby(db, b, HERE);
  assert.equal(seen.status, 'taken', 'red for everyone else');
  assert.equal(seen.cells.filter(c => c.status === 'taken').length, 1);
});

test('register: Terms, GPS inside the cell, home within 5 km of the centre; one cell each, never shared', emulator, async () => {
  const db = getFirestore();
  const cell = await clean();
  const a = await staff();
  await assert.rejects(S.claimHexCell(db, a, {...HERE, ...HOME_NEAR}), /Terms/);
  await assert.rejects(S.claimHexCell(db, a, {...HOME_NEAR, termsAccepted: true}), /GPS/);
  await assert.rejects(S.claimHexCell(db, a, {...HERE, ...HOME_NEAR, accuracyM: 250, termsAccepted: true}), /not exact enough/);
  const other = G.cellAt(17.7600, 83.3010);
  await assert.rejects(S.claimHexCell(db, a, {...HERE, ...HOME_NEAR, cellId: other, termsAccepted: true}), /not standing inside/);
  await assert.rejects(S.claimHexCell(db, a, {...HERE, homeAddress: HOME_NEAR.homeAddress, termsAccepted: true}), /pin on your home/);
  await assert.rejects(S.claimHexCell(db, a, {...HERE, ...HOME_NEAR, homeAddress: 'short', termsAccepted: true}), /home address/);
  await assert.rejects(S.claimHexCell(db, a, {...HERE, ...HOME_FAR, termsAccepted: true}), /km from the centre of this cell/);

  const done = await S.claimHexCell(db, a, {...HERE, ...HOME_NEAR, cellId: cell, accuracyM: 12, termsAccepted: true});
  assert.deepEqual([done.areaId, done.status, done.sizeKm], [cell, 'pending', 1]);
  assert.ok(done.homeDistanceKm <= 5);
  const area = (await db.collection('staffAreas').doc(cell).get()).data();
  assert.deepEqual([area.hex, area.hexCell, area.hexCode, area.hexSizeKm, area.status], [true, cell, G.codeOf(cell), 1, 'pending']);
  assert.equal(area.hexParent5, G.parent5Of(cell));
  assert.ok(area.hexOutline.length >= 12 && area.radiusKm > 0.4 && area.radiusKm < 1);
  assert.equal(area.name, `${G.codeOf(cell)} · Visakhapatnam`);
  const mine = (await db.collection('staffAreaStaff').doc(a).get()).data();
  assert.deepEqual([mine.areaId, mine.areaCode, mine.homeAddress], [cell, G.codeOf(cell), HOME_NEAR.homeAddress]);
  assert.equal((await db.collection('staffAreaHolders').doc(cell).get()).data().staffUid, a);

  await assert.rejects(S.claimHexCell(db, a, {latitude: 17.7600, longitude: 83.3010, homeLatitude: 17.75, homeLongitude: 83.30, homeAddress: HOME_NEAR.homeAddress, termsAccepted: true}), /already have a cell/);
  const b = await staff('active');
  await assert.rejects(S.claimHexCell(db, b, {...HERE, ...HOME_NEAR, termsAccepted: true}), /already taken/);
});

test('approved: the cell is booked; a cancelled staff ID frees it for the next staff member', emulator, async () => {
  const db = getFirestore();
  const cell = await clean();
  const a = await staff();
  await S.claimHexCell(db, a, {...HERE, ...HOME_NEAR, termsAccepted: true});
  assert.equal(await S.onStaffStatus(db, a, {status: 'pending'}, {status: 'active'}), 'booked');
  assert.equal((await db.collection('staffAreas').doc(cell).get()).data().status, 'booked');
  assert.equal(await S.onStaffStatus(db, a, {status: 'active'}, {status: 'cancelled'}), 'free');
  assert.equal((await db.collection('staffAreas').doc(cell).get()).data().status, 'free');
  assert.equal((await db.collection('staffAreaHolders').doc(cell).get()).exists, false);
  const mine = (await db.collection('staffAreaStaff').doc(a).get()).data();
  assert.deepEqual([mine.areaId, mine.cancelledAreaId], [null, cell]);
  const next = await staff('active');
  assert.equal((await S.claimHexCell(db, next, {...HERE, ...HOME_NEAR, termsAccepted: true})).status, 'booked', 'a new staff member takes the free cell');
});

test('the area\'s shops are the shops inside the cell', emulator, async () => {
  const db = getFirestore();
  const cell = await clean();
  const a = await staff('active');
  await S.claimHexCell(db, a, {...HERE, ...HOME_NEAR, termsAccepted: true});
  await db.collection('shops').doc(`hexShopIn${seq}`).set({name: 'Inside', latitude: HERE.latitude, longitude: HERE.longitude});
  await db.collection('shops').doc(`hexShopOut${seq}`).set({name: 'Outside', latitude: 17.7600, longitude: 83.3010});
  const area = {id: cell, ...(await db.collection('staffAreas').doc(cell).get()).data()};
  const ids = (await S.shopsInArea(db, area)).map(s => s.id);
  assert.ok(ids.includes(`hexShopIn${seq}`));
  assert.ok(!ids.includes(`hexShopOut${seq}`));
});
