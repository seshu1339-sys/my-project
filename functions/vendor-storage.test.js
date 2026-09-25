const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {ref, uploadBytes, getBytes} = require('firebase/storage');
const {doc, setDoc, Timestamp} = require('firebase/firestore');
const jpeg = () => new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const jpegMeta = {contentType: 'image/jpeg'};
// Needs both emulators because the Storage rules read Firestore vendor records.
test('vendor photos: private application photos, approved-only product photos', {skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  const [host, port] = process.env.FIREBASE_STORAGE_EMULATOR_HOST.split(':');
  const env = await initializeTestEnvironment({
    projectId: 'demo-neighbourly',
    firestore: {rules: readFileSync(resolve(__dirname, '../firestore.rules'), 'utf8')},
    storage: {rules: readFileSync(resolve(__dirname, '../storage.rules'), 'utf8'), host, port: Number(port)},
  });
  try {
    const anonymous = env.unauthenticatedContext().storage();
    const vendor = env.authenticatedContext('vendor1', {email_verified: true}).storage();
    const unverifiedVendor = env.authenticatedContext('vendor1', {email_verified: false}).storage();
    const other = env.authenticatedContext('vendor2', {email_verified: true}).storage();
    const admin = env.authenticatedContext('owner', {admin: true, email_verified: true}).storage();
    const app = (s, path = 'vendorApplications/vendor1/vendorPhoto', meta = jpegMeta, bytes = jpeg()) => uploadBytes(ref(s, path), bytes, meta);
    // Admin Storage access now also requires a fresh OTP-verified session (see admin-otp.js / storage.rules' adminSessionValid()).
    await env.withSecurityRulesDisabled(async ctx => setDoc(doc(ctx.firestore(), '_adminSessions/owner'), {expiresAt: Timestamp.fromMillis(Date.now() + 3600000)}));

    // --- application photos, before any application exists
    await assertSucceeds(app(vendor));
    await assertSucceeds(app(vendor, 'vendorApplications/vendor1/shopPhoto'));
    await assertFails(app(anonymous));
    await assertFails(app(unverifiedVendor));
    await assertFails(app(other));                                                        // someone else's folder
    await assertFails(app(vendor, 'vendorApplications/vendor1/passport'));               // only the two named photos
    await assertFails(app(vendor, 'vendorApplications/vendor1/vendorPhoto', {contentType: 'text/html'}));
    await assertFails(app(vendor, 'vendorApplications/vendor1/vendorPhoto', jpegMeta, new Uint8Array(5 * 1024 * 1024 + 1)));
    // --- who can read them
    await assertSucceeds(getBytes(ref(vendor, 'vendorApplications/vendor1/vendorPhoto')));
    await assertSucceeds(getBytes(ref(admin, 'vendorApplications/vendor1/shopPhoto')));
    await assertFails(getBytes(ref(other, 'vendorApplications/vendor1/vendorPhoto')));
    await assertFails(getBytes(ref(anonymous, 'vendorApplications/vendor1/vendorPhoto')));

    // --- once submitted (pending) the vendor can no longer swap photos; after rejection they can
    await env.withSecurityRulesDisabled(async ctx => { await ctx.firestore().doc('vendorApplications/vendor1').set({status: 'pending'}); });
    await assertFails(app(vendor));
    await env.withSecurityRulesDisabled(async ctx => { await ctx.firestore().doc('vendorApplications/vendor1').set({status: 'rejected'}); });
    await assertSucceeds(app(vendor));
    await env.withSecurityRulesDisabled(async ctx => { await ctx.firestore().doc('vendorApplications/vendor1').set({status: 'approved'}); });
    await assertFails(app(vendor));

    // --- product photos: only an APPROVED vendor, only its own folder
    const product = (s, uid = 'vendor1') => uploadBytes(ref(s, `vendorProducts/${uid}/p.jpg`), jpeg(), jpegMeta);
    await assertFails(product(vendor));                                                   // no vendor record yet
    await env.withSecurityRulesDisabled(async ctx => { await ctx.firestore().doc('vendors/vendor1').set({status: 'pending'}); });
    await assertFails(product(vendor));
    await env.withSecurityRulesDisabled(async ctx => { await ctx.firestore().doc('vendors/vendor1').set({status: 'approved'}); });
    await assertSucceeds(product(vendor));
    await assertFails(product(vendor, 'vendor2'));                                         // not their folder
    await assertFails(product(other, 'vendor1'));
    await assertFails(product(anonymous));
    await assertFails(uploadBytes(ref(vendor, 'vendorProducts/vendor1/x.html'), jpeg(), {contentType: 'text/html'}));
    await assertSucceeds(getBytes(ref(anonymous, 'vendorProducts/vendor1/p.jpg')));       // public catalog images
    // catalog folder stays admin-only
    await assertFails(uploadBytes(ref(vendor, 'catalog/x.jpg'), jpeg(), jpegMeta));
    await assertSucceeds(uploadBytes(ref(admin, 'catalog/x.jpg'), jpeg(), jpegMeta));
  } finally { await env.cleanup(); }
});
