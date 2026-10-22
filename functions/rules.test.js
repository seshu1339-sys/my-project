const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, updateDoc, serverTimestamp, Timestamp} = require('firebase/firestore');
test('Firestore denies escalation, PIN access and forged orders; isolates customer data', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-neighbourly', firestore: {rules: readFileSync(resolve(__dirname, '../firestore.rules'), 'utf8')}});
  try {
    const anonymous = env.unauthenticatedContext().firestore();
    const alice = env.authenticatedContext('alice', {email_verified: true}).firestore();
    const bob = env.authenticatedContext('bob', {email_verified: true}).firestore();
    const admin = env.authenticatedContext('owner', {admin: true, email_verified: true}).firestore();
    const staleAdmin = env.authenticatedContext('staleOwner', {admin: true, email_verified: true}).firestore();
    const expiredAdmin = env.authenticatedContext('expiredOwner', {admin: true, email_verified: true}).firestore();
    const unverified = env.authenticatedContext('new', {admin: true, email_verified: false}).firestore();
    // The admin claim alone no longer grants access: a fresh, unexpired
    // _adminSessions doc (written only by functions/admin-otp.js after a
    // successful email-OTP check) is also required. 'owner' has a valid one;
    // 'staleOwner' never completed OTP; 'expiredOwner' completed it too long ago.
    await env.withSecurityRulesDisabled(async ctx => {
      await setDoc(doc(ctx.firestore(), '_adminSessions/owner'), {expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
      await setDoc(doc(ctx.firestore(), '_adminSessions/expiredOwner'), {expiresAt: Timestamp.fromMillis(Date.now() - 1000)});
    });
    await assertFails(setDoc(doc(staleAdmin, 'products/noSession'), {name: 'Denied'}));
    await assertFails(setDoc(doc(expiredAdmin, 'products/expiredSession'), {name: 'Denied'}));
    await assertFails(setDoc(doc(unverified, 'products/nope'), {name: 'Denied'}));
    await assertFails(setDoc(doc(unverified, 'users/new'), {name: 'Denied'}));
    await assertSucceeds(setDoc(doc(admin, 'products/p1'), {name: 'Test', active: true}));
    await assertSucceeds(getDoc(doc(anonymous, 'products/p1')));
    await assertFails(setDoc(doc(alice, 'products/p1'), {price: 1}));
    // Unified Ads: everyone reads the ads, only the admin writes them; the admin-only side (adsPrivate) is never public.
    await assertSucceeds(setDoc(doc(admin, 'ads/ad1'), {title: 'Sale', status: 'approved'}));
    await assertSucceeds(getDoc(doc(anonymous, 'ads/ad1')));
    await assertFails(setDoc(doc(alice, 'ads/ad2'), {title: 'Mine'}));
    await assertFails(setDoc(doc(anonymous, 'ads/ad1'), {title: 'Hacked'}));
    await assertSucceeds(setDoc(doc(admin, 'adsPrivate/ad1'), {amount: 5000, paid: true}));
    await assertFails(getDoc(doc(anonymous, 'adsPrivate/ad1')));
    await assertFails(getDoc(doc(alice, 'adsPrivate/ad1')));
    await assertFails(setDoc(doc(alice, 'adsPrivate/ad1'), {paid: false}));
    // View counts: written by functions only; the admin reads all, a vendor only the totals of their own ads.
    await env.withSecurityRulesDisabled(async ctx => {
      await setDoc(doc(ctx.firestore(), 'adStats/ad1'), {vendorId: 'alice', views: 3});
      await setDoc(doc(ctx.firestore(), 'adStats/ad9'), {vendorId: 'someone', views: 9});
      await setDoc(doc(ctx.firestore(), 'adViews/v1'), {adId: 'ad1', town: 'Vizag'});
    });
    await assertSucceeds(getDoc(doc(alice, 'adStats/ad1')));
    await assertFails(getDoc(doc(alice, 'adStats/ad9')));
    await assertFails(getDoc(doc(anonymous, 'adStats/ad1')));
    await assertSucceeds(getDoc(doc(admin, 'adStats/ad9')));
    await assertFails(setDoc(doc(alice, 'adStats/ad1'), {views: 99999}));
    await assertFails(setDoc(doc(admin, 'adStats/ad1'), {views: 99999}));
    await assertFails(getDoc(doc(alice, 'adViews/v1')));
    await assertSucceeds(getDoc(doc(admin, 'adViews/v1')));
    await assertFails(getDoc(doc(admin, 'adViewGuard/x')));
    await assertFails(setDoc(doc(alice, 'users/alice'), {name: 'Alice', admin: true}));
    await assertSucceeds(setDoc(doc(alice, 'users/alice'), {name: 'Alice'}));
    // Language, saved-card display and wishlist are the other fields the client merges onto a profile.
    await assertSucceeds(setDoc(doc(alice, 'users/alice'), {name: 'Alice', language: 'hi', paymentBrand: 'Visa', paymentLast4: '4242', wishlist: ['p1', 'p2']}));
    await assertFails(setDoc(doc(alice, 'users/alice'), {name: 'Alice', paymentLast4: '42424'}));
    await assertFails(setDoc(doc(alice, 'users/alice'), {name: 'Alice', wishlist: 'p1'}));
    await assertFails(getDoc(doc(bob, 'users/alice')));
    const view = {pincode: '500001', lastViewedAt: serverTimestamp()};
    await assertSucceeds(setDoc(doc(alice, 'products/p1/viewers/alice'), view));
    await assertFails(setDoc(doc(bob, 'products/p1/viewers/alice'), view));
    await assertFails(getDoc(doc(bob, 'products/p1/viewers/alice')));
    await assertFails(setDoc(doc(alice, 'products/p1/viewers/alice'), {...view, pincode: 'bad'}));
    await assertSucceeds(setDoc(doc(alice, 'users/alice/pushTokens/token'), {token: 'token', updatedAt: serverTimestamp()}));
    await assertFails(getDoc(doc(bob, 'users/alice/pushTokens/token')));
    await assertFails(setDoc(doc(alice, 'users/alice/pushTokens/token'), {token: 'other', updatedAt: serverTimestamp()}));
    await assertSucceeds(setDoc(doc(alice, 'notificationSubscribers/alice'), {enabled: true, updatedAt: serverTimestamp()}));
    await assertFails(setDoc(doc(bob, 'notificationSubscribers/alice'), {enabled: true, updatedAt: serverTimestamp()}));
    // Optional last-known location, only ever written by the subscriber themselves.
    await assertSucceeds(setDoc(doc(alice, 'notificationSubscribers/alice'), {enabled: true, updatedAt: serverTimestamp(), pincode: '560001', latitude: 12.9716, longitude: 77.5946}));
    await assertFails(setDoc(doc(alice, 'notificationSubscribers/alice'), {enabled: true, updatedAt: serverTimestamp(), pincode: 'not-a-pincode'}));
    await assertFails(setDoc(doc(alice, 'notificationSubscribers/alice'), {enabled: true, updatedAt: serverTimestamp(), latitude: 200}));
    await assertFails(setDoc(doc(alice, 'notificationSubscribers/alice'), {enabled: true, updatedAt: serverTimestamp(), longitude: -200}));
    await assertFails(setDoc(doc(alice, 'notificationSubscribers/alice'), {enabled: true, updatedAt: serverTimestamp(), latitude: '12.9'}));
    await assertFails(setDoc(doc(bob, 'notificationSubscribers/alice'), {enabled: true, updatedAt: serverTimestamp(), latitude: 12.9716, longitude: 77.5946}));
    await assertFails(setDoc(doc(alice, '_notificationDeliveries/fake'), {sent: true}));
    // Field Assistant: a staff role doc and a submission queue, both function-write-only.
    await env.withSecurityRulesDisabled(async ctx => {
      await setDoc(doc(ctx.firestore(), 'fieldStaff/alice'), {uid: 'alice', status: 'active'});
      await setDoc(doc(ctx.firestore(), 'fieldSubmissions/s1'), {staffUid: 'alice', status: 'pending'});
    });
    await assertSucceeds(getDoc(doc(alice, 'fieldStaff/alice')));
    await assertSucceeds(getDoc(doc(admin, 'fieldStaff/alice')));
    await assertFails(getDoc(doc(bob, 'fieldStaff/alice')));
    await assertFails(setDoc(doc(alice, 'fieldStaff/alice'), {status: 'active'}));
    await assertSucceeds(getDoc(doc(alice, 'fieldSubmissions/s1')));
    await assertSucceeds(getDoc(doc(admin, 'fieldSubmissions/s1')));
    await assertFails(getDoc(doc(bob, 'fieldSubmissions/s1')));
    await assertFails(setDoc(doc(alice, 'fieldSubmissions/s1'), {status: 'approved'}));
    await assertFails(getDoc(doc(admin, '_pins/alice')));
    await assertFails(setDoc(doc(alice, 'orders/fake'), {userId: 'alice', total: 0}));
    await env.withSecurityRulesDisabled(async ctx => setDoc(doc(ctx.firestore(), 'orders/o1'), {userId: 'alice', total: 100, status: 'submitted'}));
    await assertSucceeds(getDoc(doc(alice, 'orders/o1')));
    await assertFails(getDoc(doc(bob, 'orders/o1')));
    await assertFails(updateDoc(doc(admin, 'orders/o1'), {total: 1}));
    await assertSucceeds(updateDoc(doc(admin, 'orders/o1'), {status: 'confirmed'}));
    const review = {userId: 'alice', name: 'Alice', rating: 5, text: 'Great', updatedAt: serverTimestamp()};
    // Review creation is callable-only so a client cannot bypass purchase verification.
    await assertFails(setDoc(doc(alice, 'products/p1/reviews/alice'), review));
    await assertFails(setDoc(doc(bob, 'products/p1/reviews/alice'), review));
    await assertFails(setDoc(doc(alice, 'products/p1/reviews/alice'), {...review, rating: 9}));
  } finally { await env.cleanup(); }
});
