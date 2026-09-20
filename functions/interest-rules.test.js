const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, getDocs, collection, serverTimestamp, increment} = require('firebase/firestore');

test('product interest: counted views, no tampering, server-only alert fields, admin-only analytics', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-neighbourly', firestore: {rules: readFileSync(resolve(__dirname, '../firestore.rules'), 'utf8')}});
  try {
    await env.withSecurityRulesDisabled(async ctx => { await setDoc(doc(ctx.firestore(), 'products/p1'), {name: 'Lamp', price: 10}); });
    const alice = env.authenticatedContext('alice', {email_verified: true}).firestore();
    const bob = env.authenticatedContext('bob', {email_verified: true}).firestore();
    const anon = env.unauthenticatedContext().firestore();
    const admin = env.authenticatedContext('owner', {admin: true, email_verified: true}).firestore();
    const ref = db => doc(db, 'products/p1/viewers/alice');
    const count = () => ({pincode: '560001', lastViewedAt: serverTimestamp(), viewCount: increment(1)});

    await assertSucceeds(setDoc(ref(alice), count(), {merge: true}));                       // first view -> 1
    await assertSucceeds(setDoc(ref(alice), count(), {merge: true}));                       // second view -> 2
    await assertSucceeds(setDoc(ref(alice), {pincode: '', lastViewedAt: serverTimestamp(), viewCount: increment(1)}, {merge: true})); // moved: pincode may change
    await assertFails(setDoc(ref(alice), {pincode: '560001', lastViewedAt: serverTimestamp(), viewCount: increment(5)}, {merge: true})); // cannot inflate
    await assertFails(setDoc(ref(alice), {pincode: '560001', lastViewedAt: serverTimestamp(), viewCount: 1}, {merge: true}));            // cannot reset
    await assertFails(setDoc(ref(alice), {pincode: '560001', lastViewedAt: serverTimestamp(), viewCount: increment(1), lastAlertPrice: 1}, {merge: true})); // alert fields are server-only
    await assertFails(setDoc(ref(alice), {pincode: '5600', lastViewedAt: serverTimestamp(), viewCount: increment(1)}, {merge: true}));   // bad pincode
    await assertFails(setDoc(doc(bob, 'products/p1/viewers/alice'), count(), {merge: true}));                                            // someone else's record
    await assertFails(setDoc(doc(anon, 'products/p1/viewers/alice'), count(), {merge: true}));
    await assertFails(setDoc(doc(alice, 'products/p1/viewers/bob'), count(), {merge: true}));

    // server bookkeeping stays put and does not block later counted views
    await env.withSecurityRulesDisabled(async ctx => { await setDoc(doc(ctx.firestore(), 'products/p1/viewers/alice'), {lastAlertPrice: 9, alertCount: 1}, {merge: true}); });
    await assertSucceeds(setDoc(ref(alice), count(), {merge: true}));
    await assertFails(setDoc(ref(alice), {pincode: '560001', lastViewedAt: serverTimestamp(), viewCount: increment(1), alertCount: 0}, {merge: true}));

    // older apps (plain two-field write) keep working
    await assertSucceeds(setDoc(doc(bob, 'products/p1/viewers/bob'), {pincode: '560001', lastViewedAt: serverTimestamp()}));
    // a first counted view must start at exactly one
    await assertFails(setDoc(doc(bob, 'products/p1/viewers/bob2'), {pincode: '', lastViewedAt: serverTimestamp(), viewCount: 4}));

    // a customer reads only their own interest record; nobody but the admin reads analytics
    await assertSucceeds(getDoc(ref(alice)));
    await assertFails(getDoc(ref(bob)));
    await env.withSecurityRulesDisabled(async ctx => {
      await setDoc(doc(ctx.firestore(), 'analyticsDaily/2030-01-01~0'), {visits: 3});
      await setDoc(doc(ctx.firestore(), 'analyticsAds/rules-ad~0'), {impressions: 3});
      await setDoc(doc(ctx.firestore(), 'analyticsTotals/all~0'), {visitors: 3});
    });
    for (const path of ['analyticsDaily/2030-01-01~0', 'analyticsAds/rules-ad~0', 'analyticsTotals/all~0']) {
      await assertSucceeds(getDoc(doc(admin, path)));
      await assertFails(getDoc(doc(alice, path)));
      await assertFails(getDoc(doc(anon, path)));
      await assertFails(setDoc(doc(admin, path), {visits: 999}));               // even the admin cannot edit counters
      await assertFails(setDoc(doc(alice, path), {visits: 999}));
    }
    await assertSucceeds(getDocs(collection(admin, 'analyticsDaily')));
    await assertFails(getDocs(collection(alice, 'analyticsDaily')));
    await assertFails(getDoc(doc(admin, 'analyticsSeen/anything')));             // markers are never readable
  } finally { await env.cleanup(); }
});
