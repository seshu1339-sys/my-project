// Auto Approval (owner, 13 Nov 2026): the AI photo check (functions/photo-safety.js) and what registration does with it, in the
// emulators. A fake AI answers; no real call is made.
const {test} = require('node:test');
const assert = require('node:assert/strict');

const ready = {skip: !(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_STORAGE_EMULATOR_HOST)};
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0xff, 0xd9]);
const fakeAi = found => () => ({messages: {create: async request => {
  fakeAi.calls.push(request);
  return {stop_reason: 'end_turn', usage: {input_tokens: 10, output_tokens: 5}, content: [{type: 'text', text: JSON.stringify({found, note: found.length ? 'seen' : 'nothing'})}]};
}}});
fakeAi.calls = [];

test('the check: safe, unsafe with the reason, and never an automatic decision when it cannot run', ready, async () => {
  const fns = require('./index');
  const {getFirestore} = require('firebase-admin/firestore');
  const {checkBytes, unsafeReason, checksPerDay} = require('./photo-safety');
  const db = getFirestore();
  assert.equal(checksPerDay({}), 300);
  assert.deepEqual((await checkBytes(db, JPEG, 'image/jpeg', {makeClient: fakeAi([])})).verdict, 'safe');
  const bad = await checkBytes(db, JPEG, 'image/jpeg', {makeClient: fakeAi(['alcohol', 'tobacco', 'not-a-category'])});
  assert.deepEqual([bad.verdict, bad.categories], ['unsafe', ['alcohol', 'tobacco']]);
  assert.match(unsafeReason(bad.categories), /alcohol and cigarettes or tobacco/);
  assert.equal(fakeAi.calls.at(-1).model, 'claude-haiku-5-5');
  assert.equal((await checkBytes(db, Buffer.from('not an image'), 'text/plain', {makeClient: fakeAi([])})).verdict, 'unknown');
  assert.equal((await checkBytes(db, JPEG, 'image/jpeg')).verdict, 'unknown', 'no AI key in the tests: the admin decides');
  assert.ok(fns);
});

test('registration with Auto Approval: approved at once with the Vendor ID, refused for a forbidden photo, waits when OFF', ready, async () => {
  const fns = require('./index');
  const {getFirestore} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  const t = `aa${Date.now()}`;
  const apply = async (uid, code) => {
    await bucket.file(`vendorApplications/${uid}/vendorPhoto`).save(JPEG, {contentType: 'image/jpeg'});
    await db.doc(`vendorApplications/${uid}`).set({vendorId: uid, name: 'Ramu Kirana', ownerName: 'Ramu', shopCategory: 'Grocery', phone: '9000000001', pincode: '530008', latitude: 17.73, longitude: 83.28, address: '', description: '', vendorCode: code, status: 'pending', vendorPhotoPath: `vendorApplications/${uid}/vendorPhoto`});
  };
  const {autoDecideVendor} = fns._autoApproval;
  try {
    await db.doc('settings/business').set({autoApproval: ''}, {merge: true});
    await apply(`${t}off`, 'VEN-TEST-100-001');
    assert.equal(await autoDecideVendor(`${t}off`, {makeClient: fakeAi([])}), null, 'OFF: the admin approves as before');
    assert.equal((await db.doc(`vendorApplications/${t}off`).get()).data().status, 'pending');

    await db.doc('settings/business').set({autoApproval: 'true'}, {merge: true});
    await apply(`${t}ok`, 'VEN-TEST-100-002');
    assert.equal(await autoDecideVendor(`${t}ok`, {makeClient: fakeAi([])}), 'approved');
    const app = (await db.doc(`vendorApplications/${t}ok`).get()).data();
    assert.deepEqual([app.status, app.autoApproved], ['approved', true]);
    const vendor = (await db.doc(`vendors/${t}ok`).get()).data();
    assert.deepEqual([vendor.status, vendor.vendorCode, vendor.autoApproved], ['approved', 'VEN-TEST-100-002', true]);
    assert.equal((await db.doc(`shops/${t}ok`).get()).data().name, 'Ramu Kirana', 'the shop is public at once');

    await apply(`${t}bad`, 'VEN-TEST-100-003');
    assert.equal(await autoDecideVendor(`${t}bad`, {makeClient: fakeAi(['weapons'])}), 'rejected');
    const refused = (await db.doc(`vendorApplications/${t}bad`).get()).data();
    assert.equal(refused.status, 'rejected');
    assert.match(refused.decisionReason, /guns or weapons/);
    assert.equal((await db.doc(`vendors/${t}bad`).get()).exists, false);

    await apply(`${t}wait`, 'VEN-TEST-100-004');
    assert.equal(await autoDecideVendor(`${t}wait`), null, 'the check could not run: the admin decides');
    assert.equal((await db.doc(`vendorApplications/${t}wait`).get()).data().status, 'pending');
  } finally {
    await db.doc('settings/business').set({autoApproval: ''}, {merge: true});
  }
});

test('registration needs the owner photo, not the shop photo; the address and description are optional', () => {
  const {vendorApplication} = require('./domain');
  const details = vendorApplication({ownerName: 'Ramu', phone: '9000000001', name: 'Ramu Kirana', shopCategory: 'Grocery', pincode: '530008', latitude: 17.7, longitude: 83.2, gpsAddress: 'Main Road, Kancharapalem'});
  assert.equal(details.address, 'Main Road, Kancharapalem', 'the GPS address when none is typed');
  assert.equal(details.description, '');
  assert.throws(() => vendorApplication({ownerName: 'Ramu', phone: '9000000001', name: 'Ramu Kirana', pincode: '530008', latitude: 17.7, longitude: 83.2}), /category/, 'the category is still needed');
  assert.throws(() => vendorApplication({ownerName: 'Ramu', phone: '9000000001', name: 'Ramu Kirana', shopCategory: 'Grocery', latitude: 17.7, longitude: 83.2}), /pincode/);
});
