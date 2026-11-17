const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {ref, uploadBytes, getBytes} = require('firebase/storage');
const {doc, setDoc, getDoc, getDocs, collection, query, where, orderBy, limit, Timestamp} = require('firebase/firestore');

const root = resolve(__dirname, '../../..');
const projectId = process.env.GCLOUD_PROJECT || 'demo-neighbourly';
const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const jpegMeta = {contentType: 'image/jpeg'};

test('offers: anyone reads a live one, a vendor their own, the admin all; nobody writes them from the app', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-neighbourly-offers', firestore: {rules: readFileSync(resolve(root, 'firestore.rules'), 'utf8')}});
  try {
    const anonymous = env.unauthenticatedContext().firestore();
    const vendor = env.authenticatedContext('vendor1', {role: 'user', email_verified: true}).firestore();
    const other = env.authenticatedContext('vendor2', {role: 'user', email_verified: true}).firestore();
    const admin = env.authenticatedContext('owner', {role: 'admin', admin: true, email_verified: true}).firestore();
    const endsAt = Timestamp.fromMillis(Date.now() + 86400000);
    await env.withSecurityRulesDisabled(async ctx => {
      const db = ctx.firestore();
      await setDoc(doc(db, '_adminSessions/owner'), {expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
      await setDoc(doc(db, 'vendorOffers/live'), {vendorId: 'vendor1', status: 'live', endsAt, updatedAt: endsAt});
      await setDoc(doc(db, 'vendorOffers/waiting'), {vendorId: 'vendor1', status: 'pending', endsAt, updatedAt: endsAt});
      await setDoc(doc(db, 'vendorOffers/gone'), {vendorId: 'vendor1', status: 'removed', removedReason: 'Wrong photo', endsAt, updatedAt: endsAt});
      await setDoc(doc(db, 'vendorOffersConfig/main'), {approvalRequired: false});
    });
    await assertSucceeds(getDoc(doc(anonymous, 'vendorOffers/live')));
    await assertFails(getDoc(doc(anonymous, 'vendorOffers/waiting')));
    await assertFails(getDoc(doc(other, 'vendorOffers/gone')));
    await assertSucceeds(getDoc(doc(vendor, 'vendorOffers/gone')));
    await assertSucceeds(getDoc(doc(admin, 'vendorOffers/waiting')));
    // the three lists the app really asks for
    await assertSucceeds(getDocs(query(collection(anonymous, 'vendorOffers'), where('status', '==', 'live'), where('endsAt', '>', Timestamp.now()), orderBy('endsAt'), limit(300))));
    await assertSucceeds(getDocs(query(collection(vendor, 'vendorOffers'), where('vendorId', '==', 'vendor1'))));
    await assertSucceeds(getDocs(query(collection(admin, 'vendorOffers'), orderBy('updatedAt', 'desc'), limit(300))));
    await assertFails(getDocs(query(collection(other, 'vendorOffers'), where('vendorId', '==', 'vendor1'))));
    await assertFails(getDocs(query(collection(anonymous, 'vendorOffers'), limit(300))));
    // writes only through the functions, also for the owner and the admin
    await assertFails(setDoc(doc(vendor, 'vendorOffers/live'), {status: 'live', offerPrice: 1}));
    await assertFails(setDoc(doc(vendor, 'vendorOffers/mine'), {vendorId: 'vendor1', status: 'live'}));
    await assertFails(setDoc(doc(admin, 'vendorOffers/live'), {status: 'removed'}));
    await assertFails(getDoc(doc(vendor, 'vendorOffersConfig/main')));
    await assertSucceeds(getDoc(doc(admin, 'vendorOffersConfig/main')));
    await assertFails(setDoc(doc(vendor, 'vendorOffersConfig/main'), {approvalRequired: false}));
  } finally { await env.cleanup(); }
});

test('offer photos: only an approved vendor into their own folder; everyone can see them', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  const [host, port] = process.env.FIREBASE_STORAGE_EMULATOR_HOST.split(':');
  const env = await initializeTestEnvironment({
    projectId,
    firestore: {rules: readFileSync(resolve(root, 'firestore.rules'), 'utf8')},
    storage: {rules: readFileSync(resolve(root, 'storage.rules'), 'utf8'), host, port: Number(port)},
  });
  try {
    await env.withSecurityRulesDisabled(async ctx => {
      await setDoc(doc(ctx.firestore(), 'vendors/offerVendor'), {status: 'approved'});
      await setDoc(doc(ctx.firestore(), 'vendors/waitingVendor'), {status: 'pending'});
    });
    const vendor = env.authenticatedContext('offerVendor', {role: 'user', email_verified: true}).storage();
    const waiting = env.authenticatedContext('waitingVendor', {role: 'user', email_verified: true}).storage();
    const anonymous = env.unauthenticatedContext().storage();
    const put = (s, path, meta = jpegMeta) => uploadBytes(ref(s, path), jpeg, meta);
    await assertSucceeds(put(vendor, 'vendorOffers/offerVendor/1.webp'));
    await assertSucceeds(getBytes(ref(anonymous, 'vendorOffers/offerVendor/1.webp')));
    await assertFails(put(vendor, 'vendorOffers/someoneElse/1.webp'));
    await assertFails(put(vendor, 'vendorOffers/offerVendor/page.html', {contentType: 'text/html'}));
    await assertFails(put(waiting, 'vendorOffers/waitingVendor/1.webp'));
    await assertFails(put(anonymous, 'vendorOffers/offerVendor/2.webp'));
  } finally { await env.cleanup(); }
});
