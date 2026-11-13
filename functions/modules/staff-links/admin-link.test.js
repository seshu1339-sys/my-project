// The admin links a vendor to a staff member of the same area at any time; a vendor asks for local staff (functions/modules/staff-links).
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
if (!getApps().length) initializeApp({projectId: 'demo-neighbourly'});
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {adminLink, requestLocalStaff, staffInAreaOf, linkAccount} = require('./store');

const emulated = {skip: !process.env.FIRESTORE_EMULATOR_HOST};

test('the admin links in the same area only, at any time; a vendor asks for local staff without a staff ID', emulated, async () => {
  const db = getFirestore();
  const t = `al${Date.now()}`;
  const now = Date.now();
  const staff = `${t}s`, area = `${t}a`;
  // IDs in the app's format (VEN-XXXX-123-456), different on every run.
  const n = String(now).slice(-6), NEAR = `VEN-KPLM-${n.slice(0, 3)}-${n.slice(3)}`, FAR = `VEN-NRPM-${n.slice(0, 3)}-${n.slice(3)}`;
  await db.doc(`staffAreas/${area}`).set({name: 'Kancharapalem', latitude: 17.734, longitude: 83.279, radiusKm: 3});
  await db.doc(`staffAreaHolders/${area}`).set({staffUid: staff});
  await db.doc(`staffAreaStaff/${staff}`).set({areaId: area});
  await db.doc(`fieldStaff/${staff}`).set({status: 'active', staffCode: `STF-KPL-${t.slice(-4)}`, name: 'Ravi', phone: '9000000004'});
  const old = Timestamp.fromMillis(now - 2 * 3600000);
  await db.doc(`vendorApplications/${t}near`).set({vendorCode: NEAR, name: 'Near Shop', latitude: 17.735, longitude: 83.280, submittedAt: old, phone: '9000000005', town: 'Visakhapatnam'});
  await db.doc(`vendorApplications/${t}far`).set({vendorCode: FAR, name: 'Far Shop', latitude: 17.667, longitude: 82.612, submittedAt: old});

  // Two hours after registration the staff member cannot link any more...
  await assert.rejects(linkAccount(db, staff, {code: NEAR}, now), /30 minutes/);
  // ...the vendor asks from the chat, and the admin chooses from the staff of that area.
  assert.deepEqual(await requestLocalStaff(db, `${t}near`, 'vendor', now), {status: 'open'});
  assert.deepEqual(await requestLocalStaff(db, `${t}near`, 'vendor', now), {status: 'open', already: true});
  const choices = await staffInAreaOf(db, (await db.doc(`vendorApplications/${t}near`).get()).data());
  assert.ok(choices.some(c => c.staffUid === staff && c.areaName === 'Kancharapalem'));
  assert.equal((await staffInAreaOf(db, (await db.doc(`vendorApplications/${t}far`).get()).data())).some(c => c.staffUid === staff), false);
  const linked = await adminLink(db, 'admin1', {code: NEAR, staffUid: staff}, now);
  assert.equal(linked.linkId, `vendor_${t}near`);
  const link = (await db.doc(`staffLinks/vendor_${t}near`).get()).data();
  assert.deepEqual([link.staffUid, link.linkedBy], [staff, 'admin']);
  assert.equal((await db.doc(`staffLinkRequests/vendor_${t}near`).get()).data().status, 'linked');
  await assert.rejects(requestLocalStaff(db, `${t}near`, 'vendor', now), /already connected/);
  // Never to a staff member of another area.
  await assert.rejects(adminLink(db, 'admin1', {code: FAR, staffUid: staff}, now), /outside the area/);
  await assert.rejects(requestLocalStaff(db, `${t}nobody`, 'vendor', now), /Register your shop/);
});
