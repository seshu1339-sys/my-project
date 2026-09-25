const {test} = require('node:test');
const assert = require('node:assert/strict');

// EMAIL_DRY_RUN=true (functions/.env.local) makes requestAdminOtp record the
// code in _emailDryRun instead of sending real mail, mirroring PUSH_DRY_RUN.
// Each admin uid below requests a code at most once successfully, so its
// _emailDryRun doc is unique and needs no ordering/index to look up.
test('admin OTP: request/verify success, wrong code, reuse, expiry, resend cooldown, rate limiting and unauthorized', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  process.env.EMAIL_DRY_RUN = 'true';
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const codeFor = async email => (await db.collection('_emailDryRun').where('to', '==', email).get()).docs[0].data().code;
  const wrongCodeFor = real => (real === '000000' ? '111111' : '000000');

  const admin = {auth: {uid: 'otpAdmin1', token: {admin: true, email_verified: true, email: 'otpadmin1@example.test'}}};
  const notAdmin = {auth: {uid: 'plainUser1', token: {email_verified: true, email: 'plain1@example.test'}}};
  const unverified = {auth: {uid: 'unverified1', token: {admin: true, email_verified: false, email: 'unverified1@example.test'}}};

  // ---- only a verified admin may request or verify a code
  await assert.rejects(() => fns.requestAdminOtp.run({...notAdmin, data: {}}), /Administrator/);
  await assert.rejects(() => fns.requestAdminOtp.run({...unverified, data: {}}), /Verify your email/);
  await assert.rejects(() => fns.requestAdminOtp.run({data: {}}), /Sign in/);

  // ---- a wrong code is rejected, and a requireAdmin()-gated callable stays locked out
  await fns.requestAdminOtp.run({...admin, data: {}});
  const code = await codeFor(admin.auth.token.email);
  await assert.rejects(() => fns.verifyAdminOtp.run({...admin, data: {code: wrongCodeFor(code)}}), /Incorrect code/);
  await assert.rejects(() => fns.offerAudienceSize.run({...admin, data: {}}), /verification expired/);

  // ---- the correct code succeeds exactly once (single use)
  const ok = await fns.verifyAdminOtp.run({...admin, data: {code}});
  assert.equal(ok.ok, true);
  await assert.rejects(() => fns.verifyAdminOtp.run({...admin, data: {code}}), /already used/);

  // ---- the fresh admin session now unlocks a real requireAdmin()-gated callable
  const audience = await fns.offerAudienceSize.run({...admin, data: {}});
  assert.equal(typeof audience.subscribers, 'number');

  // ---- resend cooldown: requesting again immediately is refused
  await assert.rejects(() => fns.requestAdminOtp.run({...admin, data: {}}), /wait/);

  // ---- malformed input is rejected outright
  await assert.rejects(() => fns.verifyAdminOtp.run({...admin, data: {code: 'abc'}}), /6-digit/);

  // ---- expiry: a code past its expiresAt is rejected even if it is correct
  const expired = {auth: {uid: 'otpAdmin2', token: {admin: true, email_verified: true, email: 'otpadmin2@example.test'}}};
  await fns.requestAdminOtp.run({...expired, data: {}});
  const expiredCode = await codeFor(expired.auth.token.email);
  await db.collection('_adminOtps').doc(expired.auth.uid).update({expiresAt: Timestamp.fromMillis(Date.now() - 1000)});
  await assert.rejects(() => fns.verifyAdminOtp.run({...expired, data: {code: expiredCode}}), /expired/);

  // ---- too many wrong attempts locks the code out, even though the real code would still work
  const locked = {auth: {uid: 'otpAdmin3', token: {admin: true, email_verified: true, email: 'otpadmin3@example.test'}}};
  await fns.requestAdminOtp.run({...locked, data: {}});
  const lockedCode = await codeFor(locked.auth.token.email);
  const guess = wrongCodeFor(lockedCode);
  for (let i = 0; i < 5; i++) await assert.rejects(() => fns.verifyAdminOtp.run({...locked, data: {code: guess}}));
  await assert.rejects(() => fns.verifyAdminOtp.run({...locked, data: {code: lockedCode}}), /Request a new code/);
});
