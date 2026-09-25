'use strict';
// Shared by every requireAdmin() across the backend (index.js, exclusives.js,
// notifications.js, vendor-photos.js): a password + admin-claim check alone is
// no longer enough once email OTP is required. Every privileged callable must
// also prove a recent, successful OTP verification exists for this admin (see
// admin-otp.js, which is the only writer of _adminSessions). Sessions expire so
// OTP is required again periodically, not just once per browser's lifetime.
const {HttpsError} = require('firebase-functions/v2/https');
const {getFirestore} = require('firebase-admin/firestore');
const db = getFirestore();

async function requireAdminSession(uid) {
  const snap = await db.collection('_adminSessions').doc(uid).get();
  const expiresAt = snap.data()?.expiresAt?.toMillis?.();
  if (!expiresAt || expiresAt <= Date.now()) {
    throw new HttpsError('permission-denied', 'Admin verification expired. Sign in and verify your code again.');
  }
}
module.exports = {requireAdminSession};
