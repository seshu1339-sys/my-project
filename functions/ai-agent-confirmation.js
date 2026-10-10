'use strict';
// Confirmation for sensitive/critical AI Agent actions. 'sensitive' tier uses a
// short Agent PIN, separate from the admin's login password, hashed the same
// way admin-otp.js hashes OTP codes (HMAC-SHA256 with its own secret pepper —
// never stored or compared in the clear). 'critical' tier reuses the EXISTING
// requestAdminOtp/verifyAdminOtp flow unmodified: the client calls those two
// callables itself first, and critical-tier confirmation here just checks that
// a code was successfully verified very recently (still inside its own 5-
// minute TTL window), proving a fresh OTP round just happened.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret} = require('firebase-functions/params');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {createHmac, timingSafeEqual} = require('node:crypto');
const {requireAdminSession} = require('./admin-session');
const db = getFirestore();
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};
const pinPepper = defineSecret('AI_AGENT_PIN_PEPPER');

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

async function pinRateLimit(uid) {
  const ref = db.collection('_rateLimits').doc(`agentpin:${uid}`);
  await db.runTransaction(async tx => {
    const data = (await tx.get(ref)).data();
    const now = Date.now();
    const fresh = !data || data.until <= now;
    if (!fresh && data.count >= 10) throw new HttpsError('resource-exhausted', 'Too many PIN attempts. Please try again later.');
    tx.set(ref, {count: fresh ? 1 : data.count + 1, until: fresh ? now + 15 * 60 * 1000 : data.until});
  });
}

function hashPin(uid, pin, pepper) {
  return createHmac('sha256', pepper).update(`${uid}:${pin}`).digest();
}

exports.setAgentPin = onCall({...options, secrets: [pinPepper]}, async request => {
  const uid = await requireAdmin(request);
  const pin = String(request.data?.pin || '').trim();
  if (!/^\d{4,8}$/.test(pin)) throw new HttpsError('invalid-argument', 'Choose a PIN of 4-8 digits.');
  await db.collection('_aiAgentPins').doc(uid).set({
    hash: hashPin(uid, pin, pinPepper.value()).toString('hex'),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {ok: true};
});

// Exported for ai-agent-executor.js to call directly — not a callable itself.
async function verifyAgentPin(uid, pin, pepperValue) {
  if (!/^\d{4,8}$/.test(String(pin || ''))) throw new HttpsError('invalid-argument', 'Enter your Agent PIN.');
  await pinRateLimit(uid);
  const snap = await db.collection('_aiAgentPins').doc(uid).get();
  if (!snap.exists) throw new HttpsError('failed-precondition', 'Set an Agent PIN first, in AI Agent settings.');
  const expected = hashPin(uid, pin, pepperValue);
  const actual = Buffer.from(snap.data().hash, 'hex');
  if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) {
    throw new HttpsError('permission-denied', 'Incorrect Agent PIN.');
  }
}

// Proof that the admin completed a fresh verifyAdminOtp round very recently
// (the code's own 5-minute TTL is the recency window) — reuses that existing
// flow exactly as-is, no changes to admin-otp.js.
async function requireRecentOtp(uid) {
  const snap = await db.collection('_adminOtps').doc(uid).get();
  const data = snap.data();
  if (!data?.consumed || !data.expiresAt || data.expiresAt.toMillis() <= Date.now()) {
    throw new HttpsError('failed-precondition', 'Verify a fresh administrator OTP code first for this critical action.');
  }
}

module.exports.verifyAgentPin = verifyAgentPin;
module.exports.requireRecentOtp = requireRecentOtp;
module.exports.pinPepper = pinPepper;
