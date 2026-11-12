'use strict';
// Email code sign-in: the backup for people with no Google account (or whose Google sign-in fails). A 6-digit code is emailed to the
// address; typing it in proves the address, so the email's own login is created (or found) with the email marked verified and the app
// signs in with a custom token. That login only proves the email: the app then asks enterRole (functions/role-logins.js) for the
// email's login in its own role. Same hashing, expiry and attempt limits as the admin code (admin-otp.js): the code is kept only as an
// HMAC.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret, defineString} = require('firebase-functions/params');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');
const {createHmac, createHash, randomInt, timingSafeEqual} = require('node:crypto');
const db = getFirestore();

const otpPepper = defineSecret('ADMIN_OTP_PEPPER');
// The sending Gmail address is not a secret: a plain setting in functions/.env.<project> (Secret Manager cost, Nov 2026).
const mailUser = defineString('ADMIN_MAIL_USER');
const mailPassword = defineSecret('ADMIN_MAIL_PASSWORD');
// Google Play's reviewers cannot open the playreview.* mailboxes, so these three emails (and no other) sign in with one fixed 6-digit
// code kept in Secret Manager; it is written only in Play Console's App access. No email is sent to them. Empty or unset = off.
const reviewCode = defineSecret('REVIEW_LOGIN_CODE');
const REVIEW_EMAILS = new Set(['playreview.user@locamarket.in', 'playreview.vendor@locamarket.in', 'playreview.staff@locamarket.in']);
function reviewCodeOn() {
  return /^\d{6}$/.test(String(reviewCode.value() || '').trim());
}

const CODE_TTL_MS = 10 * 60 * 1000;
const RESEND_COOLDOWN_MS = 45 * 1000;
const MAX_ATTEMPTS = 5;
const options = {region: 'us-central1', maxInstances: 5, invoker: 'public'};

function validEmail(value) {
  const email = typeof value === 'string' ? value.trim().toLowerCase() : '';
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new HttpsError('invalid-argument', 'Enter a valid email address.');
  return email;
}
const docId = email => createHash('sha256').update(email).digest('hex');
const hashCode = (email, code, pepper) => createHmac('sha256', pepper).update(`login:${email}:${code}`).digest();
const sameCode = (a, b) => timingSafeEqual(createHash('sha256').update(a).digest(), createHash('sha256').update(b).digest());

async function limit(key, max, windowMs) {
  const ref = db.collection('_rateLimits').doc(`emailLogin:${key}`);
  await db.runTransaction(async tx => {
    const data = (await tx.get(ref)).data();
    const now = Date.now();
    const fresh = !data || data.until <= now;
    if (!fresh && data.count >= max) throw new HttpsError('resource-exhausted', 'Too many attempts. Please try again later.');
    tx.set(ref, {count: fresh ? 1 : data.count + 1, until: fresh ? now + windowMs : data.until});
  });
}

async function sendCode(to, code) {
  if (process.env.EMAIL_DRY_RUN === 'true') {
    await db.collection('_emailDryRun').add({to, subject: 'Your sign-in code', code, kind: 'login', createdAt: FieldValue.serverTimestamp()});
    return;
  }
  const nodemailer = require('nodemailer');
  const transport = nodemailer.createTransport({service: 'gmail', auth: {user: mailUser.value(), pass: mailPassword.value()}});
  await transport.sendMail({
    from: mailUser.value(),
    to,
    subject: 'Your Loca Market sign-in code',
    text: `Your sign-in code is ${code}. It expires in 10 minutes and works once. If you did not ask for it, ignore this email and do not share the code.`,
  });
}

exports.requestEmailLoginCode = onCall({...options, secrets: [otpPepper, mailPassword, reviewCode]}, async request => {
  const email = validEmail(request.data?.email);
  await limit(`send:${docId(email)}`, 5, 15 * 60 * 1000);
  // A Play reviewer already has the review code from Play Console: nothing is sent.
  if (REVIEW_EMAILS.has(email) && reviewCodeOn()) return {ok: true, expiresInSeconds: CODE_TTL_MS / 1000, cooldownSeconds: RESEND_COOLDOWN_MS / 1000};
  const ref = db.collection('_emailLoginCodes').doc(docId(email));
  const now = Date.now();
  const sentAt = (await ref.get()).data()?.sentAt?.toMillis?.();
  if (sentAt && now - sentAt < RESEND_COOLDOWN_MS) {
    throw new HttpsError('resource-exhausted', `Please wait ${Math.ceil((RESEND_COOLDOWN_MS - (now - sentAt)) / 1000)}s before asking for another code.`);
  }
  const code = String(randomInt(0, 1000000)).padStart(6, '0');
  await ref.set({
    codeHash: hashCode(email, code, otpPepper.value()).toString('hex'),
    attempts: 0, consumed: false,
    expiresAt: Timestamp.fromMillis(now + CODE_TTL_MS), sentAt: Timestamp.fromMillis(now),
  });
  await sendCode(email, code);
  return {ok: true, expiresInSeconds: CODE_TTL_MS / 1000, cooldownSeconds: RESEND_COOLDOWN_MS / 1000};
});

exports.verifyEmailLoginCode = onCall({...options, secrets: [otpPepper, reviewCode]}, async request => {
  const email = validEmail(request.data?.email);
  const code = String(request.data?.code || '').trim();
  if (!/^\d{6}$/.test(code)) throw new HttpsError('invalid-argument', 'Enter the 6-digit code.');
  await limit(`verify:${docId(email)}`, 10, 15 * 60 * 1000);
  const ref = db.collection('_emailLoginCodes').doc(docId(email));
  const review = REVIEW_EMAILS.has(email) && reviewCodeOn();
  const result = review ? {ok: sameCode(code, String(reviewCode.value()).trim()), attemptsLeft: 1} : await db.runTransaction(async tx => {
    const data = (await tx.get(ref)).data();
    if (!data) throw new HttpsError('failed-precondition', 'Ask for a code first.');
    if (data.consumed) throw new HttpsError('failed-precondition', 'This code was already used. Ask for a new one.');
    if (!data.expiresAt || data.expiresAt.toMillis() <= Date.now()) throw new HttpsError('deadline-exceeded', 'This code has expired. Ask for a new one.');
    if (data.attempts >= MAX_ATTEMPTS) throw new HttpsError('resource-exhausted', 'Too many wrong codes. Ask for a new one.');
    const expected = hashCode(email, code, otpPepper.value());
    const actual = Buffer.from(data.codeHash, 'hex');
    if (!(expected.length === actual.length && timingSafeEqual(expected, actual))) {
      tx.update(ref, {attempts: FieldValue.increment(1)});
      return {ok: false, attemptsLeft: MAX_ATTEMPTS - data.attempts - 1};
    }
    tx.update(ref, {consumed: true});
    return {ok: true};
  });
  if (!result.ok && review) throw new HttpsError('invalid-argument', 'Wrong code.');
  if (!result.ok) throw new HttpsError('invalid-argument', result.attemptsLeft > 0 ? `Wrong code. ${result.attemptsLeft} tries left.` : 'Wrong code. Ask for a new one.');
  // The code proved the address: find or create the account and mark the email verified.
  const auth = getAuth();
  let user;
  try {
    user = await auth.getUserByEmail(email);
    if (!user.emailVerified) user = await auth.updateUser(user.uid, {emailVerified: true});
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
    user = await auth.createUser({email, emailVerified: true});
  }
  return {token: await auth.createCustomToken(user.uid)};
});
