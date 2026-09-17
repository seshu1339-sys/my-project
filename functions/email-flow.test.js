const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, deleteApp} = require('firebase/app');
const {getAuth, connectAuthEmulator, createUserWithEmailAndPassword, sendEmailVerification, applyActionCode, reload, getIdTokenResult, sendPasswordResetEmail, confirmPasswordReset, signOut, signInWithEmailAndPassword, deleteUser, sendSignInLinkToEmail, signInWithEmailLink, isSignInWithEmailLink} = require('firebase/auth');
test('email registration, verification token refresh and password reset', {skip: !process.env.FIREBASE_AUTH_EMULATOR_HOST}, async () => {
  const project = 'demo-neighbourly';
  const host = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const app = initializeApp({projectId: project, apiKey: 'emulator-only'}, 'email-flow');
  const auth = getAuth(app);
  connectAuthEmulator(auth, `http://${host}`, {disableWarnings: true});
  const email = `email-flow-${Date.now()}@example.test`;
  const codes = async type => {
    const r = await fetch(`http://${host}/emulator/v1/projects/${project}/oobCodes`);
    const b = await r.json();
    return b.oobCodes.filter(c => c.email === email && c.requestType === type).at(-1).oobCode;
  };
  try {
    const {user} = await createUserWithEmailAndPassword(auth, email, 'initial-password');
    assert.equal(user.emailVerified, false);
    assert.equal((await getIdTokenResult(user)).claims.email_verified, false);
    await sendEmailVerification(user);
    await applyActionCode(auth, await codes('VERIFY_EMAIL'));
    await reload(user);
    assert.equal(user.emailVerified, true);
    assert.equal((await getIdTokenResult(user, true)).claims.email_verified, true);
    await sendPasswordResetEmail(auth, email);
    await confirmPasswordReset(auth, await codes('PASSWORD_RESET'), 'replacement-password');
    await signOut(auth);
    await assert.rejects(signInWithEmailAndPassword(auth, email, 'initial-password'));
    const signedIn = await signInWithEmailAndPassword(auth, email, 'replacement-password');
    assert.equal(signedIn.user.emailVerified, true);
    await deleteUser(signedIn.user);
  } finally { await deleteApp(app); }
});

test('passwordless email link verifies ownership and cannot be reused', {skip: !process.env.FIREBASE_AUTH_EMULATOR_HOST}, async () => {
  const host = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const project = 'demo-neighbourly';
  const app = initializeApp({projectId: project, apiKey: 'emulator-only'}, 'passwordless-flow');
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://' + host, {disableWarnings: true});
  const email = 'passwordless-' + Date.now() + '@example.test';
  try {
    await sendSignInLinkToEmail(auth, email, {url: 'http://localhost/finish', handleCodeInApp: true});
    const response = await fetch('http://' + host + '/emulator/v1/projects/' + project + '/oobCodes');
    const code = (await response.json()).oobCodes.filter(c => c.email === email && c.requestType === 'EMAIL_SIGNIN').at(-1);
    assert(code, 'Expected sign-in link');
    assert(isSignInWithEmailLink(auth, code.oobLink));
    await assert.rejects(signInWithEmailLink(auth, 'wrong@example.test', code.oobLink));
    const result = await signInWithEmailLink(auth, email, code.oobLink);
    assert.equal(result.user.emailVerified, true);
    assert.equal((await getIdTokenResult(result.user, true)).claims.email_verified, true);
    await signOut(auth);
    await assert.rejects(signInWithEmailLink(auth, email, code.oobLink));
  } finally { await deleteApp(app); }
});
