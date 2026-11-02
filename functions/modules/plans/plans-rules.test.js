const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc, setLogLevel} = require('firebase/firestore');

test('vendors read plans and only their own plan data; only functions write', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  setLogLevel('error');
  const env = await initializeTestEnvironment({projectId: 'demo-neighbourly-plans', firestore: {rules: readFileSync(resolve(__dirname, '../../../firestore.rules'), 'utf8')}});
  try {
    await env.withSecurityRulesDisabled(async context => {
      const db = context.firestore();
      await setDoc(doc(db, 'vendorPlans/p1'), {name: '1 Year', price: 4999, durationMonths: 12, active: true});
      await setDoc(doc(db, 'planServiceGates/main'), {vendorAds: true});
      await setDoc(doc(db, 'vendorPlanPeriods/r1'), {uid: 'v1', status: 'active'});
      await setDoc(doc(db, 'vendorPlanStatus/v1'), {uid: 'v1'});
      await setDoc(doc(db, 'paymentRequests/r1'), {uid: 'v1', amount: 4999});
    });
    const v1 = env.authenticatedContext('v1', {email_verified: true}).firestore();
    const v2 = env.authenticatedContext('v2', {email_verified: true}).firestore();
    const unverified = env.authenticatedContext('v3', {email_verified: false}).firestore();
    const anonymous = env.unauthenticatedContext().firestore();

    await assertSucceeds(getDoc(doc(v1, 'vendorPlans/p1')));
    await assertSucceeds(getDoc(doc(v1, 'planServiceGates/main')));
    await assertFails(getDoc(doc(anonymous, 'vendorPlans/p1')));
    await assertFails(getDoc(doc(unverified, 'vendorPlans/p1')));

    for (const path of ['vendorPlanPeriods/r1', 'vendorPlanStatus/v1', 'paymentRequests/r1']) {
      await assertSucceeds(getDoc(doc(v1, path)));
      await assertFails(getDoc(doc(v2, path)));
      await assertFails(getDoc(doc(anonymous, path)));
    }

    // Nobody writes these from an app: a vendor cannot give themselves a plan or change a price.
    await assertFails(setDoc(doc(v1, 'vendorPlanStatus/v1'), {endsAt: 9999999999999}));
    await assertFails(setDoc(doc(v1, 'vendorPlans/p1'), {price: 1}));
    await assertFails(setDoc(doc(v1, 'planServiceGates/main'), {vendorAds: false}));
    await assertFails(setDoc(doc(v1, 'paymentRequests/r1'), {status: 'verified'}));
    await assertFails(setDoc(doc(v1, 'vendorPlanPeriods/r1'), {status: 'active'}));
  } finally {
    await env.cleanup();
  }
});
