const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, Timestamp} = require('firebase/firestore');

const root = resolve(__dirname, '../../..');
const later = () => Timestamp.fromMillis(Date.now() + 3600000);

test('vendors read only whether payments are open and their own requests; the switch and payment ids stay with the admin; only functions write', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-neighbourly-payments', firestore: {rules: readFileSync(resolve(root, 'firestore.rules'), 'utf8')}});
  try {
    const vendor = env.authenticatedContext('vendor1', {role: 'user', email_verified: true}).firestore();
    const anonymous = env.unauthenticatedContext().firestore();
    const admin = env.authenticatedContext('owner', {role: 'admin', admin: true, email_verified: true}).firestore();
    await env.withSecurityRulesDisabled(async ctx => {
      const db = ctx.firestore();
      await setDoc(doc(db, '_adminSessions/owner'), {expiresAt: later()});
      for (const path of ['paymentPublic/main', 'paymentSettings/main', 'paymentIds/pay_1', 'aiCallLog/1']) await setDoc(doc(db, path), {x: 1});
      await setDoc(doc(db, 'paymentRequests/mine'), {uid: 'vendor1', status: 'awaiting_payment'});
      await setDoc(doc(db, 'paymentRequests/theirs'), {uid: 'vendor2', status: 'awaiting_payment'});
    });
    await assertSucceeds(getDoc(doc(vendor, 'paymentPublic/main')));
    await assertFails(getDoc(doc(anonymous, 'paymentPublic/main')));
    await assertSucceeds(getDoc(doc(vendor, 'paymentRequests/mine')));
    await assertFails(getDoc(doc(vendor, 'paymentRequests/theirs')));
    for (const path of ['paymentSettings/main', 'paymentIds/pay_1', 'aiCallLog/1']) {
      await assertFails(getDoc(doc(vendor, path)));
      await assertSucceeds(getDoc(doc(admin, path)));
    }
    for (const path of ['paymentPublic/main', 'paymentSettings/main', 'paymentIds/pay_2', 'paymentRequests/mine']) {
      await assertFails(setDoc(doc(admin, path), {x: 2}));
      await assertFails(setDoc(doc(vendor, path), {x: 2}));
    }
  } finally { await env.cleanup(); }
});
