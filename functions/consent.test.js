// Consent records: only a signed-in, verified person can read or write their own, for the current version of the terms.
// The Firestore parts run against the emulator only (skipped without FIRESTORE_EMULATOR_HOST).
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {consentStatus, recordConsent} = require('./index');
const {getFirestore} = require('firebase-admin/firestore');

const skip = !process.env.FIRESTORE_EMULATOR_HOST;
const db = getFirestore();
const version = /POLICY_VERSION = '([^']+)'/.exec(fs.readFileSync(path.join(__dirname, 'consent.js'), 'utf8'))[1];
const auth = uid => ({auth: {uid, token: {email_verified: true, email: `${uid}@example.com`}}});

test('the app and the server name the same version of the terms', () => {
  const dart = fs.readFileSync(path.join(__dirname, '..', 'lib', 'domain', 'consent.dart'), 'utf8');
  assert.match(dart, new RegExp(`policyVersion = '${version}'`));
});

test('nobody who is not signed in with a verified email can use the consent functions', async () => {
  await assert.rejects(consentStatus.run({data: {}}), /Sign in/);
  await assert.rejects(recordConsent.run({auth: {uid: 'x', token: {email_verified: false}}, data: {app: 'customer', version}}), /Verify/);
});

test('an agreement is recorded with who, when and which version, and a stale version is refused', {skip}, async () => {
  const user = auth('consent-user');
  await db.collection('consents').doc('consent-user').delete().catch(() => {});
  assert.equal((await consentStatus.run({...user, data: {}})).accepted, false);
  await assert.rejects(recordConsent.run({...user, data: {app: 'customer', version: '2020-01-01'}}), /updated/);
  await assert.rejects(recordConsent.run({...user, data: {app: 'admin', version}}), /Unknown app/);
  assert.deepEqual(await recordConsent.run({...user, data: {app: 'vendor', version}}), {accepted: true, version});
  const record = (await db.collection('consents').doc('consent-user').get()).data();
  assert.equal(record.uid, 'consent-user');
  assert.equal(record.email, 'consent-user@example.com');
  assert.equal(record.version, version);
  assert.equal(record.app, 'vendor');
  assert.ok(record.acceptedAt);
  assert.equal((await consentStatus.run({...user, data: {}})).accepted, true);
  assert.equal((await db.collection('consents').doc('consent-user').collection('log').get()).size >= 1, true);
});
