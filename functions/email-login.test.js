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

test('Play review code: only the three playreview emails, no email sent, wrong code refused, off when unset', {skip: !(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST)}, async () => {
  process.env.EMAIL_DRY_RUN = 'true';
  const {getFirestore} = require('firebase-admin/firestore');
  const {getAuth} = require('firebase-admin/auth');
  const fns = require('./index');
  const db = getFirestore();
  const sentTo = async email => (await db.collection('_emailDryRun').where('to', '==', email).get()).size;
  const reviewer = 'playreview.vendor@locamarket.in';
  try {
    process.env.REVIEW_LOGIN_CODE = '482913';
    await fns.requestEmailLoginCode.run({data: {email: 'PlayReview.Vendor@locamarket.in'}});
    assert.equal(await sentTo(reviewer), 0, 'no email to the reviewer mailbox');
    await assert.rejects(() => fns.verifyEmailLoginCode.run({data: {email: reviewer, code: '111111'}}), {message: 'Wrong code.'});
    const ok = await fns.verifyEmailLoginCode.run({data: {email: reviewer, code: '482913'}});
    assert.equal(typeof ok.token, 'string');
    assert.equal((await getAuth().getUserByEmail(reviewer)).emailVerified, true);
    // it works again (reviewers sign in more than once), with no request first
    assert.equal(typeof (await fns.verifyEmailLoginCode.run({data: {email: 'playreview.user@locamarket.in', code: '482913'}})).token, 'string');

    // anyone else: the review code is just a wrong code
    await fns.requestEmailLoginCode.run({data: {email: 'someone@example.test'}});
    assert.equal(await sentTo('someone@example.test'), 1);
    const real = (await db.collection('_emailDryRun').where('to', '==', 'someone@example.test').get()).docs[0].data().code;
    if (real !== '482913') await assert.rejects(() => fns.verifyEmailLoginCode.run({data: {email: 'someone@example.test', code: '482913'}}), /tries left/);

    // unset: playreview emails get a normal emailed code again
    process.env.REVIEW_LOGIN_CODE = '';
    await assert.rejects(() => fns.verifyEmailLoginCode.run({data: {email: 'playreview.staff@locamarket.in', code: '482913'}}), /Ask for a code first/);
    await fns.requestEmailLoginCode.run({data: {email: 'playreview.staff@locamarket.in'}});
    assert.equal(await sentTo('playreview.staff@locamarket.in'), 1);
  } finally {
    delete process.env.REVIEW_LOGIN_CODE;
  }
});
