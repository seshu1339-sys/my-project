const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, updateDoc, serverTimestamp} = require('firebase/firestore');
test('Firestore denies escalation, PIN access and forged orders; isolates customer data', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-neighbourly', firestore: {rules: readFileSync(resolve(__dirname, '../firestore.rules'), 'utf8')}});
  try {
    const anonymous = env.unauthenticatedContext().firestore();
    const alice = env.authenticatedContext('alice', {email_verified: true}).firestore();
    const bob = env.authenticatedContext('bob', {email_verified: true}).firestore();
    const admin = env.authenticatedContext('owner', {admin: true, email_verified: true}).firestore();
    const unverified = env.authenticatedContext('new', {admin: true, email_verified: false}).firestore();
    await assertFails(setDoc(doc(unverified, 'products/nope'), {name: 'Denied'}));
    await assertFails(setDoc(doc(unverified, 'users/new'), {name: 'Denied'}));
    await assertSucceeds(setDoc(doc(admin, 'products/p1'), {name: 'Test', active: true}));
    await assertSucceeds(getDoc(doc(anonymous, 'products/p1')));
    await assertFails(setDoc(doc(alice, 'products/p1'), {price: 1}));
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
    await assertFails(setDoc(doc(alice, '_notificationDeliveries/fake'), {sent: true}));
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
