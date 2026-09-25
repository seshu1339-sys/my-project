'use strict';
// Second factor for the admin panel: after password sign-in proves the admin
// custom claim, the client calls requestAdminOtp to get a 6-digit code emailed
// to that account's own registered (verified) address, then verifyAdminOtp to
// redeem it. Success mints a time-limited _adminSessions/{uid} document, which
// admin-session.js's requireAdminSession() then requires for every privileged
// callable and (via firestore.rules/storage.rules) every direct admin write.
//
// Codes are never stored in the clear: only an HMAC-SHA256 keyed by a secret
// pepper (ADMIN_OTP_PEPPER, set once via `firebase functions:secrets:set`,
// never in source or Git) is persisted, compared with a constant-time check.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret} = require('firebase-functions/params');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {createHmac, randomInt, timingSafeEqual} = require('node:crypto');
const db = getFirestore();

const otpPepper = defineSecret('ADMIN_OTP_PEPPER');
const mailUser = defineSecret('ADMIN_MAIL_USER');
const mailPassword = defineSecret('ADMIN_MAIL_PASSWORD');

const OTP_TTL_MS = 5 * 60 * 1000;
const RESEND_COOLDOWN_MS = 45 * 1000;
const MAX_ATTEMPTS = 5;
const SESSION_TTL_MS = 12 * 60 * 60 * 1000;
const options = {region: 'us-central1', maxInstances: 5, invoker: 'public'};

function requireAdminClaim(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true) throw new HttpsError('permission-denied', 'Verify your email first.');
  if (request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Administrator access required.');
  return request.auth.uid;
}

// A simple fixed-window counter, matching the pattern already used for other
// callables (see index.js's rateLimit), kept local here to avoid a circular
// require between index.js and this module.
async function otpRateLimit(key, limit, windowMs) {
  const ref = db.collection('_rateLimits').doc(`otp:${key}`);
  await db.runTransaction(async tx => {
    const data = (await tx.get(ref)).data();
    const now = Date.now();
    const fresh = !data || data.until <= now;
    if (!fresh && data.count >= limit) throw new HttpsError('resource-exhausted', 'Too many attempts. Please try again later.');
    tx.set(ref, {count: fresh ? 1 : data.count + 1, until: fresh ? now + windowMs : data.until});
  });
}

function hashCode(uid, code, pepper) {
  return createHmac('sha256', pepper).update(`${uid}:${code}`).digest();
}

// The Firebase emulators cannot deliver real mail, and CI/tests never have real
// Gmail credentials. With EMAIL_DRY_RUN=true (only ever set through
// functions/.env.local for local testing, mirroring PUSH_DRY_RUN in
// notifications.js) the code is recorded in _emailDryRun instead of sent, so
// the OTP flow can still be verified end to end without a real mailbox.
async function sendOtpEmail(to, code) {
  if (process.env.EMAIL_DRY_RUN === 'true') {
    await db.collection('_emailDryRun').add({to, subject: 'Your administrator verification code', code, createdAt: FieldValue.serverTimestamp()});
    return;
  }
  const nodemailer = require('nodemailer');
  const transport = nodemailer.createTransport({service: 'gmail', auth: {user: mailUser.value(), pass: mailPassword.value()}});
  await transport.sendMail({
    from: mailUser.value(),
    to,
    subject: 'Your administrator verification code',
    text: `Your admin verification code is ${code}. It expires in 5 minutes and can be used once. If you did not request this, ignore this email and do not share this code with anyone.`,
  });
}

exports.requestAdminOtp = onCall({...options, secrets: [otpPepper, mailUser, mailPassword]}, async request => {
  const uid = requireAdminClaim(request);
  const email = request.auth.token.email;
  if (!email) throw new HttpsError('failed-precondition', 'No email on this account.');
  await otpRateLimit(uid, 5, 15 * 60 * 1000);
  const ref = db.collection('_adminOtps').doc(uid);
  const now = Date.now();
  const sentAt = (await ref.get()).data()?.sentAt?.toMillis?.();
  if (sentAt && now - sentAt < RESEND_COOLDOWN_MS) {
    throw new HttpsError('resource-exhausted', `Please wait ${Math.ceil((RESEND_COOLDOWN_MS - (now - sentAt)) / 1000)}s before requesting another code.`);
  }
  const code = String(randomInt(0, 1000000)).padStart(6, '0');
  await ref.set({
    codeHash: hashCode(uid, code, otpPepper.value()).toString('hex'),
    attempts: 0,
    consumed: false,
    expiresAt: Timestamp.fromMillis(now + OTP_TTL_MS),
    sentAt: Timestamp.fromMillis(now),
  });
  await sendOtpEmail(email, code);
  return {ok: true, expiresInSeconds: OTP_TTL_MS / 1000, cooldownSeconds: RESEND_COOLDOWN_MS / 1000};
});

exports.verifyAdminOtp = onCall({...options, secrets: [otpPepper]}, async request => {
  const uid = requireAdminClaim(request);
  const code = String(request.data?.code || '').trim();
  if (!/^\d{6}$/.test(code)) throw new HttpsError('invalid-argument', 'Enter the 6-digit code.');
  await otpRateLimit(`verify:${uid}`, 10, 15 * 60 * 1000);
  const ref = db.collection('_adminOtps').doc(uid);
  const result = await db.runTransaction(async tx => {
    const data = (await tx.get(ref)).data();
    if (!data) throw new HttpsError('failed-precondition', 'Request a code first.');
    if (data.consumed) throw new HttpsError('failed-precondition', 'This code was already used. Request a new one.');
    if (!data.expiresAt || data.expiresAt.toMillis() <= Date.now()) throw new HttpsError('deadline-exceeded', 'This code has expired. Request a new one.');
    if (data.attempts >= MAX_ATTEMPTS) throw new HttpsError('resource-exhausted', 'Too many incorrect attempts. Request a new code.');
    const expected = hashCode(uid, code, otpPepper.value());
    const actual = Buffer.from(data.codeHash, 'hex');
    const match = expected.length === actual.length && timingSafeEqual(expected, actual);
    if (!match) {
      tx.update(ref, {attempts: FieldValue.increment(1)});
      return {ok: false, attemptsLeft: MAX_ATTEMPTS - data.attempts - 1};
    }
    tx.update(ref, {consumed: true});
    return {ok: true};
  });
  if (!result.ok) {
    throw new HttpsError('invalid-argument', result.attemptsLeft > 0 ? `Incorrect code. ${result.attemptsLeft} attempt(s) left.` : 'Incorrect code. Request a new one.');
  }
  await db.collection('_adminSessions').doc(uid).set({verifiedAt: FieldValue.serverTimestamp(), expiresAt: Timestamp.fromMillis(Date.now() + SESSION_TTL_MS)});
  return {ok: true};
});
