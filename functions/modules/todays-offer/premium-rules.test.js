const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {ref, uploadBytes, getBytes} = require('firebase/storage');
const {doc, setDoc, getDoc, getDocs, collection, query, where, orderBy, Timestamp} = require('firebase/firestore');

const root = resolve(__dirname, '../../..');
const projectId = process.env.GCLOUD_PROJECT || 'demo-neighbourly';
const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const jpegMeta = {contentType: 'image/jpeg'};
const later = () => Timestamp.fromMillis(Date.now() + 86400000);
const earlier = () => Timestamp.fromMillis(Date.now() - 1000);

test('premium data: own status only, live offers public, wholesale for active Premium vendors, every write through functions', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-neighbourly-premium', firestore: {rules: readFileSync(resolve(root, 'firestore.rules'), 'utf8')}});
  try {
    const anonymous = env.unauthenticatedContext().firestore();
    const premium = env.authenticatedContext('paid', {role: 'user', email_verified: true}).firestore();
    const lapsed = env.authenticatedContext('lapsed', {role: 'user', email_verified: true}).firestore();
    const free = env.authenticatedContext('free', {role: 'user', email_verified: true}).firestore();
    const admin = env.authenticatedContext('owner', {role: 'admin', admin: true, email_verified: true}).firestore();
    await env.withSecurityRulesDisabled(async ctx => {
      const db = ctx.firestore();
      await setDoc(doc(db, '_adminSessions/owner'), {expiresAt: later()});
      await setDoc(doc(db, 'vendorPremium/paid'), {active: true, endsAt: later()});
      await setDoc(doc(db, 'vendorPremium/lapsed'), {active: true, endsAt: earlier()});
      await setDoc(doc(db, 'vendorTodaysOffers/paid'), {vendorId: 'paid', price: 99, endsAt: later()});
      await setDoc(doc(db, 'wholesaleOffers/w1'), {name: 'Rice', phone: '9876543210', validUntil: later()});
    });
    await assertSucceeds(getDoc(doc(premium, 'vendorPremium/paid')));
    await assertFails(getDoc(doc(free, 'vendorPremium/paid')));
    await assertFails(setDoc(doc(premium, 'vendorPremium/paid'), {active: true, endsAt: later()}));
    await assertFails(setDoc(doc(free, 'vendorPremium/free'), {active: true, endsAt: later()}));

    await assertSucceeds(getDocs(query(collection(anonymous, 'vendorTodaysOffers'), where('endsAt', '>', Timestamp.now()), orderBy('endsAt'))));
    await assertFails(setDoc(doc(premium, 'vendorTodaysOffers/paid'), {vendorId: 'paid', price: 1, endsAt: later()}));

    const wholesale = db => getDocs(query(collection(db, 'wholesaleOffers'), where('validUntil', '>', Timestamp.now()), orderBy('validUntil')));
    await assertSucceeds(wholesale(premium));
    await assertSucceeds(wholesale(admin));
    await assertFails(wholesale(free));
    await assertFails(wholesale(lapsed), 'cut off at the plan end, before the status is switched off');
    await assertFails(wholesale(anonymous));
    await assertFails(setDoc(doc(admin, 'wholesaleOffers/w2'), {name: 'Denied'}));
  } finally { await env.cleanup(); }
});

test('offer photos: only an active Premium vendor into their own folder; wholesale photos only from the admin', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  const [host, port] = process.env.FIREBASE_STORAGE_EMULATOR_HOST.split(':');
  const env = await initializeTestEnvironment({
    projectId,
    firestore: {rules: readFileSync(resolve(root, 'firestore.rules'), 'utf8')},
    storage: {rules: readFileSync(resolve(root, 'storage.rules'), 'utf8'), host, port: Number(port)},
  });
  try {
    await env.withSecurityRulesDisabled(async ctx => {
      const db = ctx.firestore();
      await setDoc(doc(db, '_adminSessions/storeOwner'), {expiresAt: later()});
      await setDoc(doc(db, 'vendors/paidVendor'), {status: 'approved'});
      await setDoc(doc(db, 'vendorPremium/paidVendor'), {active: true, endsAt: later()});
      await setDoc(doc(db, 'vendors/freeVendor'), {status: 'approved'});
      await setDoc(doc(db, 'vendors/lapsedVendor'), {status: 'approved'});
      await setDoc(doc(db, 'vendorPremium/lapsedVendor'), {active: true, endsAt: earlier()});
    });
    const context = (uid, claims = {}) => env.authenticatedContext(uid, {role: 'vendor', loginEmail: `${uid}@example.test`, ...claims}).storage();
    const paid = context('paidVendor');
    const anonymous = env.unauthenticatedContext().storage();
    const put = (s, path, meta = jpegMeta) => uploadBytes(ref(s, path), jpeg, meta);
    await assertSucceeds(put(paid, 'vendorTodaysOffers/paidVendor/1.webp'));
    await assertSucceeds(getBytes(ref(anonymous, 'vendorTodaysOffers/paidVendor/1.webp')));
    await assertFails(put(paid, 'vendorTodaysOffers/someoneElse/1.webp'));
    await assertFails(put(paid, 'vendorTodaysOffers/paidVendor/a.html', {contentType: 'text/html'}));
    await assertFails(put(context('freeVendor'), 'vendorTodaysOffers/freeVendor/1.webp'));
    await assertFails(put(context('lapsedVendor'), 'vendorTodaysOffers/lapsedVendor/1.webp'));
    await assertSucceeds(put(context('storeOwner', {role: 'admin', admin: true}), 'wholesaleOffers/1.webp'));
    await assertFails(put(context('storeOwner', {role: 'user', admin: true}), 'wholesaleOffers/3.webp'), 'the admin claim counts only on the admin login');
    await assertFails(put(env.authenticatedContext('paidVendor', {email_verified: true, email: 'paid@example.test'}).storage(), 'vendorTodaysOffers/paidVendor/2.webp'), 'the email\'s own login has no role');
    await assertFails(put(paid, 'wholesaleOffers/2.webp'));
  } finally { await env.cleanup(); }
});
