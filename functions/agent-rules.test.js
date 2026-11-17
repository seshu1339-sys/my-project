// Firestore rules of the command box and the health checks (owner spec I, 17 Nov 2026): the agent log is written only by a signed-in
// admin as themself with the server's time and never changed; _private (the AI key) is closed to every app.
const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, getDocs, addDoc, updateDoc, deleteDoc, collection, serverTimestamp, Timestamp} = require('firebase/firestore');

test('agent log and server-only values', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-agent-rules', firestore: {rules: readFileSync(resolve(__dirname, '../firestore.rules'), 'utf8')}});
  try {
    await env.withSecurityRulesDisabled(async ctx => {
      await setDoc(doc(ctx.firestore(), '_adminSessions/owner'), {expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
      await setDoc(doc(ctx.firestore(), '_private/aiKey'), {key: 'sk-ant-secret'});
    });
    const admin = env.authenticatedContext('owner', {role: 'admin', admin: true, email_verified: true}).firestore();
    const vendor = env.authenticatedContext('v1', {role: 'vendor', email_verified: true}).firestore();
    const anonymous = env.unauthenticatedContext().firestore();
    const row = uid => ({uid, email: 'a@b.c', action: 'open', command: 'post duration', target: 'field.settings.postDuration', platform: '', details: {}, at: serverTimestamp()});

    const added = await assertSucceeds(addDoc(collection(admin, 'agentLog'), row('owner')));
    await assertFails(addDoc(collection(admin, 'agentLog'), row('someoneElse')));
    await assertFails(addDoc(collection(admin, 'agentLog'), {...row('owner'), at: Timestamp.fromMillis(0)}));
    await assertFails(addDoc(collection(admin, 'agentLog'), {...row('owner'), extra: 1}));
    await assertFails(addDoc(collection(vendor, 'agentLog'), row('v1')));
    await assertFails(updateDoc(added, {action: 'changed'}));
    await assertFails(deleteDoc(added));
    await assertSucceeds(getDocs(collection(admin, 'agentLog')));
    await assertFails(getDocs(collection(vendor, 'agentLog')));

    for (const db of [admin, vendor, anonymous]) {
      await assertFails(getDoc(doc(db, '_private/aiKey')));
      await assertFails(setDoc(doc(db, '_private/aiKey'), {key: 'x'}));
    }
  } finally {
    await env.cleanup();
  }
});
