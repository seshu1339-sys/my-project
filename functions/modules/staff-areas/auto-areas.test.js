const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {Timestamp} = require('firebase-admin/firestore');
const B = require('./blocks');
const R = require('./rules');
const S = require('./store');

// Owner, 7 Nov 2026: automatic staff areas. India in computed blocks, buildings counted in OpenStreetMap, the radius from the density.

test('India is divided into blocks by a calculation; a centre snaps to its block\'s middle; outside India is refused', () => {
  const a = B.blockOf(17.6683, 82.6121);
  assert.deepEqual(a, {blockId: 'B1766_8261', latitude: 17.665, longitude: 82.615});
  assert.equal(B.blockOf(17.6611, 82.6199).blockId, a.blockId, 'two taps in the same block give the same block');
  assert.notEqual(B.blockOf(17.6701, 82.6121).blockId, a.blockId);
  assert.throws(() => B.blockOf(51.5, -0.12), /India/);
  assert.throws(() => B.blockOf(undefined, 82), /India/);
});

test('buildings per km² give the radius: >1000 = 1 km, 300-1000 = 2 km, 50-300 = 4 km, fewer = 15 km', () => {
  assert.equal(B.densityPerKm2(3142), 1000, 'within 1 km = 3.14 km²');
  const r = n => B.radiusFor(B.densityPerKm2(n));
  assert.equal(r(4000), 1, 'dense city');
  assert.equal(r(2000), 2);
  assert.equal(r(500), 4);
  assert.equal(r(100), 15, 'very sparse');
  assert.equal(r(0), 15);
});

test('the admin changes the bands in plain numbers; nonsense is refused', () => {
  const bands = B.validateBands([{minPerKm2: 1500, radiusKm: 1}, {minPerKm2: 400, radiusKm: 2.5}, {minPerKm2: 60, radiusKm: 5}, {minPerKm2: 9, radiusKm: 20}]);
  assert.deepEqual(bands.map(b => [b.minPerKm2, b.radiusKm]), [[1500, 1], [400, 2.5], [60, 5], [0, 20]], 'the last band is everything below');
  assert.throws(() => B.validateBands([{minPerKm2: 100, radiusKm: 1}, {minPerKm2: 300, radiusKm: 2}, {minPerKm2: 50, radiusKm: 4}, {minPerKm2: 0, radiusKm: 15}]), /fewer buildings/);
  assert.throws(() => B.validateBands([{minPerKm2: 1000, radiusKm: 0.1}, {minPerKm2: 300, radiusKm: 2}, {minPerKm2: 50, radiusKm: 4}, {minPerKm2: 0, radiusKm: 15}]), /0.5 to 30/);
  assert.throws(() => B.validateBands([]), /4 density bands/);
  assert.deepEqual(R.validateSettings({densityBands: bands}).densityBands, bands);
  assert.deepEqual(R.settingsOf({}).densityBands, B.DEFAULT_BANDS);
});

test('the OpenStreetMap question and its answer', () => {
  assert.match(B.overpassQuery(17.665, 82.615), /way\["building"\]\(around:1000,17.665,82.615\)/);
  assert.equal(B.parseCount({elements: [{type: 'count', tags: {total: '1234', ways: '1200'}}]}), 1234);
  assert.throws(() => B.parseCount({}), /could not be read/);
});

const emulator = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
const T = Date.parse('2031-03-05T10:00:00+05:30');
const CENTRE = {latitude: 17.6683, longitude: 82.6121};
const GPS = {gpsLatitude: 17.6652, gpsLongitude: 82.6148};
async function setup() {
  const {getFirestore} = require('firebase-admin/firestore');
  const db = getFirestore();
  for (const c of ['fieldStaff', 'staffAreas', 'staffAreaHolders', 'staffAreaStaff', 'staffAreaBlocks', 'staffAreaSettings']) for (const d of (await db.collection(c).get()).docs) await d.ref.delete();
  await db.collection('fieldStaff').doc('s1').set({status: 'active', staffCode: 'STF-1', name: 'Ravi'});
  await db.collection('fieldStaff').doc('s2').set({status: 'active', staffCode: 'STF-2', name: 'Sita'});
  const calls = [];
  const count = n => async (lat, lng, radiusM) => { calls.push([lat, lng, radiusM]); return n; };
  return {db, calls, count};
}

test('a staff member checks a place: the block, the buildings, the radius; nothing is saved for the block yet', emulator, async () => {
  const {db, calls, count} = await setup();
  const p = await S.previewAutoArea(db, 's1', CENTRE, count(4000), T);
  assert.deepEqual([p.blockId, p.radiusKm, p.buildings, p.free], ['B1766_8261', 1, 4000, true]);
  assert.deepEqual(calls, [[17.665, 82.615, 1000]], 'counted at the block\'s middle');
  assert.equal((await db.collection('staffAreaBlocks').get()).size, 0, 'only blocks that are registered are saved');
});

test('registering: the server\'s radius only, the block saved once, one area per staff member, the block taken for others', emulator, async () => {
  const {db, calls, count} = await setup();
  const r = await S.claimAutoArea(db, 's1', {...CENTRE, ...GPS, radiusKm: 50, name: 'Main Bazaar', town: 'Narsipatnam', termsAccepted: true}, count(500), T);
  assert.deepEqual(r, {areaId: 'B1766_8261', status: 'booked', radiusKm: 4}, 'a radius sent by the phone is ignored');
  const area = (await db.collection('staffAreas').doc('B1766_8261').get()).data();
  assert.deepEqual([area.name, area.town, area.radiusKm, area.auto, area.status, area.latitude], ['Main Bazaar', 'Narsipatnam', 4, true, 'booked', 17.665]);
  assert.equal((await db.collection('staffAreaBlocks').doc('B1766_8261').get()).data().buildings, 500);
  // A second area for the same staff member: refused, at the check and at registering.
  const far = {latitude: 18.2, longitude: 83.4, gpsLatitude: 18.205, gpsLongitude: 83.405, termsAccepted: true};
  await assert.rejects(S.previewAutoArea(db, 's1', far, count(100), T), /One staff member has one area/);
  await assert.rejects(S.claimAutoArea(db, 's1', far, count(100), T), /One staff member has one area/);
  // Someone else: the same block is taken; a block nearby overlaps; the count is not asked again for a saved block.
  calls.length = 0;
  const same = await S.previewAutoArea(db, 's2', CENTRE, count(999999), T);
  assert.deepEqual([same.free, same.buildings], [false, 500]);
  assert.match(same.problem, /already taken/);
  assert.deepEqual(calls, []);
  const next = await S.previewAutoArea(db, 's2', {latitude: 17.69, longitude: 82.62}, count(4000), T);
  assert.match(next.problem, /Too close to "Main Bazaar"/);
  await assert.rejects(S.claimAutoArea(db, 's2', {latitude: 17.69, longitude: 82.62, gpsLatitude: 17.695, gpsLongitude: 82.625, termsAccepted: true}, count(4000), T), /Too close/);
});

test('registering needs the Terms and standing inside the area', emulator, async () => {
  const {db, count} = await setup();
  await assert.rejects(S.claimAutoArea(db, 's1', {...CENTRE, ...GPS}, count(4000), T), /Terms/);
  await assert.rejects(S.claimAutoArea(db, 's1', {...CENTRE, gpsLatitude: 17.75, gpsLongitude: 82.7, termsAccepted: true}, count(4000), T), /go to this area/);
  await db.collection('fieldStaff').doc('s9').set({status: 'suspended'});
  await assert.rejects(S.claimAutoArea(db, 's9', {...CENTRE, ...GPS, termsAccepted: true}, count(4000), T), /Register as staff/);
});

test('the admin\'s bands decide the radius; a freed automatic area never blocks a new one', emulator, async () => {
  const {db, count} = await setup();
  await S.saveSettings(db, {densityBands: [{minPerKm2: 5000, radiusKm: 0.5}, {minPerKm2: 1000, radiusKm: 1.5}, {minPerKm2: 100, radiusKm: 3}, {minPerKm2: 0, radiusKm: 10}]}, T);
  assert.equal((await S.previewAutoArea(db, 's1', CENTRE, count(4000), T)).radiusKm, 1.5);
  await S.claimAutoArea(db, 's1', {...CENTRE, ...GPS, termsAccepted: true}, count(4000), T);
  await db.collection('staffAreas').doc('B1766_8261').update({status: 'free'});
  await db.collection('staffAreaHolders').doc('B1766_8261').delete();
  await db.collection('staffAreaStaff').doc('s1').update({areaId: null});
  const again = await S.previewAutoArea(db, 's2', {latitude: 17.675, longitude: 82.62}, count(4000), T);
  assert.equal(again.free, true, 'the free automatic area next door does not block');
});

test('a staff member can check at most 30 places a day', emulator, async () => {
  const {db, count} = await setup();
  await db.collection('staffAreaStaff').doc('s1').set({previewDay: R.istDay(T), previews: 30});
  await assert.rejects(S.previewAutoArea(db, 's1', CENTRE, count(10), T), /30 places today/);
  assert.ok(await S.previewAutoArea(db, 's1', CENTRE, count(10), T + R.DAY_MS), 'a new day');
  void Timestamp;
});
