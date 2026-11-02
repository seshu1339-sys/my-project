const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {ref, uploadBytes, getBytes} = require('firebase/storage');
const {doc, setDoc, getDoc, Timestamp} = require('firebase/firestore');

const root = resolve(__dirname, '../../..');
const projectId = process.env.GCLOUD_PROJECT || 'demo-neighbourly';
const later = () => Timestamp.fromMillis(Date.now() + 3600000);

test('vendors read only the bank details to pay to; patterns, SMS records and logs stay with the admin; only functions write', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-neighbourly-payments', firestore: {rules: readFileSync(resolve(root, 'firestore.rules'), 'utf8')}});
  try {
    const vendor = env.authenticatedContext('vendor1', {email_verified: true}).firestore();
    const anonymous = env.unauthenticatedContext().firestore();
    const admin = env.authenticatedContext('owner', {admin: true, email_verified: true}).firestore();
    await env.withSecurityRulesDisabled(async ctx => {
      const db = ctx.firestore();
      await setDoc(doc(db, '_adminSessions/owner'), {expiresAt: later()});
      for (const path of ['paymentBankPublic/main', 'paymentBankConfig/main', 'paymentSms/1', 'paymentIds/1', 'paymentScreenshotHashes/1', 'aiCallLog/1', 'aiDailyUse/1']) await setDoc(doc(db, path), {x: 1});
    });
    await assertSucceeds(getDoc(doc(vendor, 'paymentBankPublic/main')));
    await assertFails(getDoc(doc(anonymous, 'paymentBankPublic/main')));
    for (const path of ['paymentBankConfig/main', 'paymentSms/1', 'paymentIds/1', 'aiCallLog/1']) {
      await assertFails(getDoc(doc(vendor, path)));
      await assertSucceeds(getDoc(doc(admin, path)));
    }
    for (const path of ['paymentScreenshotHashes/1', 'aiDailyUse/1']) {
      await assertFails(getDoc(doc(vendor, path)));
      await assertFails(getDoc(doc(admin, path)));
    }
    for (const path of ['paymentBankPublic/main', 'paymentBankConfig/main', 'paymentSms/2', 'paymentIds/2', 'aiCallLog/2']) {
      await assertFails(setDoc(doc(admin, path), {x: 2}));
      await assertFails(setDoc(doc(vendor, path), {x: 2}));
    }
  } finally { await env.cleanup(); }
});

test('a payment screenshot: the vendor adds their own, only they and the admin read it, and it cannot be swapped', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  const [host, port] = process.env.FIREBASE_STORAGE_EMULATOR_HOST.split(':');
  const env = await initializeTestEnvironment({
    projectId,
    firestore: {rules: readFileSync(resolve(root, 'firestore.rules'), 'utf8')},
    storage: {rules: readFileSync(resolve(root, 'storage.rules'), 'utf8'), host, port: Number(port)},
  });
  try {
    await env.withSecurityRulesDisabled(async ctx => setDoc(doc(ctx.firestore(), '_adminSessions/payOwner'), {expiresAt: later()}));
    const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);
    const meta = {contentType: 'image/png'};
    const name = `paymentScreenshots/payVendor/r${Date.now()}`;
    const vendor = env.authenticatedContext('payVendor', {email_verified: true}).storage();
    const other = env.authenticatedContext('payOther', {email_verified: true}).storage();
    const admin = env.authenticatedContext('payOwner', {admin: true, email_verified: true}).storage();
    await assertSucceeds(uploadBytes(ref(vendor, name), png, meta));
    await assertFails(uploadBytes(ref(vendor, name), png, meta), 'no swapping after sending');
    await assertFails(uploadBytes(ref(other, name.replace('payVendor', 'payVendor2')), png, meta));
    await assertSucceeds(getBytes(ref(vendor, name)));
    await assertSucceeds(getBytes(ref(admin, name)));
    await assertFails(getBytes(ref(other, name)));
    await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), name)));
  } finally { await env.cleanup(); }
});
