'use strict';
// "Registered trusted Admin iPhone" — honestly, this is a persistent-token
// gate (like a long-lived cookie), not hardware attestation. It exists to
// reduce friction and scope WHO can even reach the WebAuthn/Face ID step that
// follows it; the real cryptographic boundary is that step (ai-agent-webauthn.js),
// backed by the device's Secure Enclave. Registering a new trusted device
// requires a just-completed OTP round as strong proof, reusing the existing
// email-OTP flow unmodified.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {createHash, randomBytes} = require('node:crypto');
const {requireAdminSession} = require('./admin-session');
const {requireModuleEnabled} = require('./ai-agent-config');
const {writeAuditLog} = require('./ai-agent-audit-log');
const {requireRecentOtp} = require('./ai-agent-confirmation');
const db = getFirestore();
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};

function requireUser(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true) throw new HttpsError('permission-denied', 'Verify your email first.');
  return request.auth.uid;
}
async function requireAdmin(request) {
  const uid = requireUser(request);
  if (request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(uid);
  return uid;
}
const sha256 = value => createHash('sha256').update(value).digest('hex');

exports.registerTrustedDevice = onCall(options, async request => {
  const uid = await requireAdmin(request);
  await requireModuleEnabled('trustedDevice');
  await requireRecentOtp(uid);
  const token = randomBytes(32).toString('hex');
  await db.collection('_aiAgentTrustedDevices').doc(uid).set({
    tokenHash: sha256(token),
    label: String(request.data?.label || 'iPhone').slice(0, 60),
    registeredAt: FieldValue.serverTimestamp(),
    lastSeenAt: FieldValue.serverTimestamp(),
  });
  await writeAuditLog({uid, type: 'trustedDevice', action: 'register', detail: 'A new trusted device was registered.'});
  return {token};
});

exports.verifyTrustedDevice = onCall(options, async request => {
  const uid = await requireAdmin(request);
  await requireModuleEnabled('trustedDevice');
  const token = String(request.data?.token || '');
  if (!token) throw new HttpsError('invalid-argument', 'No device token presented.');
  const ref = db.collection('_aiAgentTrustedDevices').doc(uid);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('failed-precondition', 'No trusted device has been registered yet.');
  if (sha256(token) !== snap.data().tokenHash) {
    throw new HttpsError('permission-denied', 'This is not the registered trusted device.');
  }
  await ref.update({lastSeenAt: FieldValue.serverTimestamp()});
  return {ok: true};
});
