// NIGHT CHECK (11 Nov 2026): role-based access in firestore.rules, run against the LOCAL emulator only. Each line prints
// RULE <who> <action> <path> <ALLOWED|DENIED> <as expected?>. Run from the project root:
//   firebase emulators:exec --project demo-neighbourly --only firestore "node --test test/night_check/rules_night.test.cjs"
const path = require('node:path');
const fn = (m) => require(path.resolve(__dirname, '../../functions/node_modules', m));
const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const {initializeTestEnvironment} = fn('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, getDocs, collection, deleteDoc, Timestamp} = fn('firebase/firestore');

test('role-based access', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-neighbourly', firestore: {rules: readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8')}});
  const who = {
    anonymous: env.unauthenticatedContext().firestore(),
    emailOnly: env.authenticatedContext('mail', {email: 'a@b.co', email_verified: true}).firestore(), // the email's own login, no role
    alice: env.authenticatedContext('alice', {role: 'user', email_verified: true, loginEmail: 'alice@x.co'}).firestore(),
    vendor: env.authenticatedContext('ven1', {role: 'vendor', email_verified: true, loginEmail: 'v@x.co'}).firestore(),
    staff: env.authenticatedContext('stf1', {role: 'staff', email_verified: true, loginEmail: 's@x.co'}).firestore(),
    adminNoOtp: env.authenticatedContext('stale', {role: 'admin', admin: true, email_verified: true}).firestore(),
    admin: env.authenticatedContext('owner', {role: 'admin', admin: true, email_verified: true}).firestore(),
  };
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, '_adminSessions/owner'), {expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
    await setDoc(doc(db, 'settings/business'), {name: 'x'});
    await setDoc(doc(db, 'products/p1'), {name: 'Rice', shopId: 's1', price: 10});
    await setDoc(doc(db, 'users/bob'), {name: 'Bob', phone: '9999999999'});
    await setDoc(doc(db, 'users/alice'), {name: 'Alice'});
    await setDoc(doc(db, 'orders/o-bob'), {customerId: 'bob', items: []});
    await setDoc(doc(db, 'roleLogins/x'), {email: 'a@b.co'});
    await setDoc(doc(db, 'adsPrivate/ad1'), {phone: '9'});
    await setDoc(doc(db, 'vendors/ven2'), {name: 'Other vendor'});
  });
  const results = [];
  async function check(name, action, p, run, expect) {
    let allowed;
    try { await run(); allowed = true; } catch (e) { allowed = false; }
    const ok = allowed === (expect === 'ALLOWED');
    results.push(ok);
    console.log(`RULE ${name} ${action} ${p} ${allowed ? 'ALLOWED' : 'DENIED'} ${ok ? 'as expected' : 'UNEXPECTED (expected ' + expect + ')'}`);
  }
  const W = (db, p, d = {x: 1}) => () => setDoc(doc(db, p), d);
  const R = (db, p) => () => getDoc(doc(db, p));
  const L = (db, c) => () => getDocs(collection(db, c));
  for (const name of ['anonymous', 'emailOnly', 'alice', 'vendor', 'staff', 'adminNoOtp']) {
    await check(name, 'write', 'settings/business', W(who[name], 'settings/business'), 'DENIED');
    await check(name, 'write', 'settings/areaNames', W(who[name], 'settings/areaNames'), 'DENIED');
    await check(name, 'write', 'products/p1', W(who[name], 'products/p1', {price: 1}), 'DENIED');
    await check(name, 'write', 'promotions/x', W(who[name], 'promotions/x'), 'DENIED');
    await check(name, 'write', 'ads/x', W(who[name], 'ads/x'), 'DENIED');
    await check(name, 'read', 'adsPrivate/ad1', R(who[name], 'adsPrivate/ad1'), 'DENIED');
    await check(name, 'read', 'users/bob', R(who[name], 'users/bob'), 'DENIED');
    await check(name, 'read', 'orders/o-bob', R(who[name], 'orders/o-bob'), 'DENIED');
    await check(name, 'list', 'users', L(who[name], 'users'), 'DENIED');
    await check(name, 'read', 'roleLogins/x', R(who[name], 'roleLogins/x'), 'DENIED');
    await check(name, 'delete', 'products/p1', () => deleteDoc(doc(who[name], 'products/p1')), 'DENIED');
  }
  await check('vendor', 'write', 'vendors/ven2 (another vendor)', W(who.vendor, 'vendors/ven2', {name: 'hacked'}), 'DENIED');
  await check('anonymous', 'read', 'settings/business', R(who.anonymous, 'settings/business'), 'ALLOWED');
  await check('anonymous', 'read', 'products/p1', R(who.anonymous, 'products/p1'), 'ALLOWED');
  await check('admin', 'write', 'settings/business', W(who.admin, 'settings/business', {name: 'y'}), 'ALLOWED');
  await check('admin', 'write', 'settings/areaNames', W(who.admin, 'settings/areaNames', {renames: ''}), 'ALLOWED');
  await check('admin', 'read', 'users/bob', R(who.admin, 'users/bob'), 'ALLOWED');
  await check('admin', 'read', 'roleLogins/x', R(who.admin, 'roleLogins/x'), 'DENIED');
  await check('alice', 'read', 'users/alice (own)', R(who.alice, 'users/alice'), 'ALLOWED');
  await env.cleanup();
  const bad = results.filter((x) => !x).length;
  console.log(`RULES checked ${results.length}, unexpected ${bad}`);
  if (bad) throw new Error(`${bad} unexpected rule results`);
});
