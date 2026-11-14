// Staff Auto Approval and the admin's "Run AI check on pending" (owner, 14 Nov 2026), in the emulators. A fake AI answers; no real
// call is made.
const {test} = require('node:test');
const assert = require('node:assert/strict');

const ready = {skip: !(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_STORAGE_EMULATOR_HOST)};
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0xff, 0xd9]);
const fakeAi = found => () => ({messages: {create: async () => ({stop_reason: 'end_turn', usage: {input_tokens: 10, output_tokens: 5}, content: [{type: 'text', text: JSON.stringify({found, note: 'x'})}]})}});

test('staff: OFF waits, ON approves a safe photo (active, Auto Approved), refuses a forbidden one, the button runs while OFF', ready, async () => {
  const fns = require('./index');
  const {getFirestore} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  const db = getFirestore();
  const bucket = getStorage().bucket();
  const {autoDecideStaff} = fns._staffAutoApproval;
  const t = `sa${Date.now()}`;
  const register = async uid => {
    const path = `fieldStaffApplications/${uid}/staffPhoto`;
    await bucket.file(path).save(JPEG, {contentType: 'image/jpeg'});
    await db.doc(`fieldStaff/${uid}`).set({uid, name: 'Ravi', phone: '9000000001', staffCode: 'STF-TEST-1', staffPhotoPath: path, status: 'pending'});
  };
  try {
    await db.doc('settings/business').set({autoApproval: ''}, {merge: true});
    await register(`${t}off`);
    assert.equal(await autoDecideStaff(`${t}off`, {makeClient: fakeAi([])}), null, 'switch OFF: the admin decides');
    assert.equal((await db.doc(`fieldStaff/${t}off`).get()).data().status, 'pending');
    assert.equal(await autoDecideStaff(`${t}off`, {force: true, makeClient: fakeAi([])}), 'active', 'the admin button runs while OFF');

    await db.doc('settings/business').set({autoApproval: true}, {merge: true});
    await register(`${t}ok`);
    assert.equal(await autoDecideStaff(`${t}ok`, {makeClient: fakeAi([])}), 'active');
    const ok = (await db.doc(`fieldStaff/${t}ok`).get()).data();
    assert.deepEqual([ok.status, ok.autoApproved, ok.decidedBy], ['active', true, 'auto']);

    await register(`${t}bad`);
    assert.equal(await autoDecideStaff(`${t}bad`, {makeClient: fakeAi(['tobacco'])}), 'rejected');
    const bad = (await db.doc(`fieldStaff/${t}bad`).get()).data();
    assert.equal(bad.autoRejected, true);
    assert.match(bad.decisionReason, /cigarettes or tobacco/);

    await register(`${t}wait`);
    assert.equal(await autoDecideStaff(`${t}wait`), null, 'no AI key in the tests: stays pending for the admin');
    const wait = (await db.doc(`fieldStaff/${t}wait`).get()).data();
    assert.equal(wait.status, 'pending');
    assert.ok(wait.autoApprovalHeld);
    assert.equal(await autoDecideStaff(`${t}ok`, {makeClient: fakeAi([])}), null, 'only pending staff are decided');
  } finally {
    await db.doc('settings/business').set({autoApproval: ''}, {merge: true});
  }
});
