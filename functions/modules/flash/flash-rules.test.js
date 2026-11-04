const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {collection, doc, getDoc, getDocs, limit, orderBy, query, setDoc, setLogLevel, where} = require('firebase/firestore');

const CHATS = ['flashUserChats', 'flashVendorChats', 'flashStaffChats'];

test('a person reads only their own chats; tickets are for the admin; only functions write', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  setLogLevel('error');
  const env = await initializeTestEnvironment({projectId: 'demo-neighbourly-flash', firestore: {rules: readFileSync(resolve(__dirname, '../../../firestore.rules'), 'utf8')}});
  try {
    await env.withSecurityRulesDisabled(async context => {
      const db = context.firestore();
      for (const name of CHATS) {
        await setDoc(doc(db, `${name}/c1`), {uid: 'p1', updatedAt: 1});
        await setDoc(doc(db, `${name}/c1/messages/m1`), {role: 'user', text: 'mine'});
      }
      await setDoc(doc(db, 'flashTickets/t1'), {uid: 'p1'});
      await setDoc(doc(db, 'flashTicketTriage/t1'), {urgency: 'high'});
      await setDoc(doc(db, 'flashStats/user'), {cameIn: 1});
      await setDoc(doc(db, 'flashConfig/main'), {dailyMessages: 30});
      await setDoc(doc(db, '_adminSessions/admin'), {expiresAt: new Date(Date.now() + 3600000)});
    });
    const p1 = env.authenticatedContext('p1', {email_verified: true}).firestore();
    const p2 = env.authenticatedContext('p2', {email_verified: true}).firestore();
    const unverified = env.authenticatedContext('p1', {email_verified: false}).firestore();
    const anonymous = env.unauthenticatedContext().firestore();
    const admin = env.authenticatedContext('admin', {email_verified: true, admin: true}).firestore();

    for (const name of CHATS) {
      await assertSucceeds(getDoc(doc(p1, `${name}/c1`)));
      await assertSucceeds(getDoc(doc(p1, `${name}/c1/messages/m1`)));
      await assertSucceeds(getDocs(query(collection(p1, name), where('uid', '==', 'p1'), orderBy('updatedAt', 'desc'), limit(20))));
      await assertSucceeds(getDoc(doc(admin, `${name}/c1/messages/m1`)));
      for (const stranger of [p2, unverified, anonymous]) {
        await assertFails(getDoc(doc(stranger, `${name}/c1`)));
        await assertFails(getDoc(doc(stranger, `${name}/c1/messages/m1`)));
      }
      await assertFails(getDocs(collection(p2, name)));
      await assertFails(setDoc(doc(p1, `${name}/c2`), {uid: 'p1'}));
      await assertFails(setDoc(doc(p1, `${name}/c1/messages/m2`), {role: 'flash', text: 'forged'}));
      await assertFails(setDoc(doc(admin, `${name}/c1`), {status: 'solved'}));
    }

    for (const path of ['flashTickets/t1', 'flashTicketTriage/t1', 'flashStats/user', 'flashConfig/main']) {
      await assertSucceeds(getDoc(doc(admin, path)));
      await assertFails(getDoc(doc(p1, path)));
      await assertFails(getDoc(doc(p2, path)));
      await assertFails(setDoc(doc(admin, path), {changed: true}));
    }
  } finally { await env.cleanup(); }
});
