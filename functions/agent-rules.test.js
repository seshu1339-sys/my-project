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

test('health and app problems: the admin reads, only the status of a report changes, apps write nothing', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-health-rules', firestore: {rules: readFileSync(resolve(__dirname, '../firestore.rules'), 'utf8')}});
  try {
    await env.withSecurityRulesDisabled(async ctx => {
      const db = ctx.firestore();
      await setDoc(doc(db, '_adminSessions/owner'), {expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
      await setDoc(doc(db, 'healthStatus/current'), {ok: true});
      await setDoc(doc(db, 'appProblems/a'), {count: 1});
      await setDoc(doc(db, 'problemReports/r1'), {text: 'broken', status: 'new'});
    });
    const admin = env.authenticatedContext('owner', {role: 'admin', admin: true, email_verified: true}).firestore();
    const vendor = env.authenticatedContext('v1', {role: 'vendor', email_verified: true}).firestore();
    await assertSucceeds(getDoc(doc(admin, 'healthStatus/current')));
    await assertSucceeds(getDoc(doc(admin, 'appProblems/a')));
    await assertFails(getDoc(doc(vendor, 'healthStatus/current')));
    await assertFails(getDoc(doc(vendor, 'appProblems/a')));
    await assertFails(setDoc(doc(admin, 'healthStatus/current'), {ok: false}));
    await assertFails(setDoc(doc(vendor, 'appProblems/x'), {count: 1}));
    await assertSucceeds(updateDoc(doc(admin, 'problemReports/r1'), {status: 'fixed'}));
    await assertFails(updateDoc(doc(admin, 'problemReports/r1'), {status: 'gone'}));
    await assertFails(updateDoc(doc(admin, 'problemReports/r1'), {text: 'changed'}));
    await assertFails(getDoc(doc(vendor, 'problemReports/r1')));
    await assertFails(getDoc(doc(admin, 'appProblemDevices/x')));
  } finally {
    await env.cleanup();
  }
});

test('ads by command: everyone reads, only the admin writes', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-adminads-rules', firestore: {rules: readFileSync(resolve(__dirname, '../firestore.rules'), 'utf8')}});
  try {
    await env.withSecurityRulesDisabled(async ctx => {
      await setDoc(doc(ctx.firestore(), '_adminSessions/owner'), {expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
    });
    const admin = env.authenticatedContext('owner', {role: 'admin', admin: true, email_verified: true}).firestore();
    const vendor = env.authenticatedContext('v1', {role: 'vendor', email_verified: true}).firestore();
    const anonymous = env.unauthenticatedContext().firestore();
    await assertSucceeds(setDoc(doc(admin, 'adminAds/a1'), {title: 'Sale', active: true}));
    await assertSucceeds(getDoc(doc(anonymous, 'adminAds/a1')));
    await assertFails(setDoc(doc(vendor, 'adminAds/a2'), {title: 'Mine', active: true}));
    await assertFails(updateDoc(doc(vendor, 'adminAds/a1'), {active: false}));
  } finally {
    await env.cleanup();
  }
});

test('design history: the admin adds a line and may only mark it undone', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-design-rules', firestore: {rules: readFileSync(resolve(__dirname, '../firestore.rules'), 'utf8')}});
  try {
    await env.withSecurityRulesDisabled(async ctx => {
      await setDoc(doc(ctx.firestore(), '_adminSessions/owner'), {expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
    });
    const admin = env.authenticatedContext('owner', {role: 'admin', admin: true, email_verified: true}).firestore();
    const vendor = env.authenticatedContext('v1', {role: 'vendor', email_verified: true}).firestore();
    await assertSucceeds(setDoc(doc(admin, 'designHistory/h1'), {entryId: 'design.web.search.width', before: 0, after: 600, undone: false}));
    await assertSucceeds(updateDoc(doc(admin, 'designHistory/h1'), {undone: true, undoneAt: serverTimestamp()}));
    await assertFails(updateDoc(doc(admin, 'designHistory/h1'), {after: 1}));
    await assertFails(deleteDoc(doc(admin, 'designHistory/h1')));
    await assertFails(getDoc(doc(vendor, 'designHistory/h1')));
    await assertFails(setDoc(doc(vendor, 'designHistory/h2'), {after: 1}));
  } finally {
    await env.cleanup();
  }
});
