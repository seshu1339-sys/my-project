const {test} = require('node:test');
const assert = require('node:assert/strict');

// EMAIL_DRY_RUN=true (functions/.env.local) records the code in _emailDryRun instead of mailing it.
test('email code sign-in: request, wrong code, correct code gives a verified account, single use, bad input', {skip: !(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST)}, async () => {
  process.env.EMAIL_DRY_RUN = 'true';
  const {getFirestore} = require('firebase-admin/firestore');
  const {getAuth} = require('firebase-admin/auth');
  const fns = require('./index');
  const db = getFirestore();
  const codeFor = async email => (await db.collection('_emailDryRun').where('to', '==', email).get()).docs[0].data().code;

  await assert.rejects(() => fns.requestEmailLoginCode.run({data: {email: 'nope'}}), /valid email/);
  await assert.rejects(() => fns.verifyEmailLoginCode.run({data: {email: 'code.user@example.test', code: '123456'}}), /Ask for a code first/);

  await fns.requestEmailLoginCode.run({data: {email: 'Code.User@Example.test'}});
  const code = await codeFor('code.user@example.test');
  assert.match(code, /^\d{6}$/);
  await assert.rejects(() => fns.requestEmailLoginCode.run({data: {email: 'code.user@example.test'}}), /Please wait/);
  await assert.rejects(() => fns.verifyEmailLoginCode.run({data: {email: 'code.user@example.test', code: 'abc'}}), /6-digit/);
  await assert.rejects(() => fns.verifyEmailLoginCode.run({data: {email: 'code.user@example.test', code: code === '000000' ? '111111' : '000000'}}), /Wrong code\. 4 tries left/);

  const ok = await fns.verifyEmailLoginCode.run({data: {email: 'code.user@example.test', code}});
  assert.equal(typeof ok.token, 'string');
  const user = await getAuth().getUserByEmail('code.user@example.test');
  assert.equal(user.emailVerified, true);
  await assert.rejects(() => fns.verifyEmailLoginCode.run({data: {email: 'code.user@example.test', code}}), /already used/);

  // an existing, unverified account is found (not duplicated) and becomes verified
  const old = await getAuth().createUser({email: 'old.user@example.test', emailVerified: false});
  await fns.requestEmailLoginCode.run({data: {email: 'old.user@example.test'}});
  await fns.verifyEmailLoginCode.run({data: {email: 'old.user@example.test', code: await codeFor('old.user@example.test')}});
  const after = await getAuth().getUserByEmail('old.user@example.test');
  assert.equal(after.uid, old.uid);
  assert.equal(after.emailVerified, true);

  // five wrong codes lock that code, even for the right one
  await fns.requestEmailLoginCode.run({data: {email: 'lock.user@example.test'}});
  const real = await codeFor('lock.user@example.test');
  const wrong = real === '000000' ? '111111' : '000000';
  for (let i = 0; i < 5; i++) await assert.rejects(() => fns.verifyEmailLoginCode.run({data: {email: 'lock.user@example.test', code: wrong}}), /Wrong code/);
  await assert.rejects(() => fns.verifyEmailLoginCode.run({data: {email: 'lock.user@example.test', code: real}}), /Too many wrong codes/);
});
