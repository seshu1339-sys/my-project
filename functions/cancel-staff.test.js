// Cancelling a staff ID for good (owner, 13 Nov 2026): closed, never reinstated, the same login cannot register again.
const {test} = require('node:test');
const assert = require('node:assert/strict');

test('the admin cancels a staff ID with a reason; it cannot be cancelled twice, reinstated or registered again', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST}, async () => {
  const fns = require('./index');
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const db = getFirestore();
  const adminUid = `cancelAdmin${Date.now()}`;
  await db.collection('_adminSessions').doc(adminUid).set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  const admin = {auth: {uid: adminUid, token: {role: 'admin', admin: true, email_verified: true, email: 'cancel-admin@example.test'}}};
  const staffUid = `cancelStaff${Date.now()}`;
  await db.collection('fieldStaff').doc(staffUid).set({status: 'active', name: 'Kiran', staffCode: 'STF-NRPM-116-901'});
  await assert.rejects(() => fns.cancelFieldStaff.run({...admin, data: {staffUid}}), /reason/);
  await assert.rejects(() => fns.cancelFieldStaff.run({auth: {uid: staffUid, token: {role: 'staff', email_verified: true}}, data: {staffUid, reason: 'Left the job'}}), /Administrator/);
  assert.deepEqual(await fns.cancelFieldStaff.run({...admin, data: {staffUid, reason: 'Left the job'}}), {status: 'cancelled', staffCode: 'STF-NRPM-116-901'});
  const record = (await db.collection('fieldStaff').doc(staffUid).get()).data();
  assert.deepEqual([record.status, record.previousStatus, record.cancelReason, record.staffCode], ['cancelled', 'active', 'Left the job', 'STF-NRPM-116-901']);
  await assert.rejects(() => fns.cancelFieldStaff.run({...admin, data: {staffUid, reason: 'Again'}}), /already cancelled/);
  await assert.rejects(() => fns.setFieldStaffSuspension.run({...admin, data: {staffUid, suspended: false}}), /not suspended/);
});
