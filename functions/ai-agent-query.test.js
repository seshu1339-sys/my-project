const {test} = require('node:test');
const assert = require('node:assert/strict');

test('AI Agent query: unknown query, module gating, role gating, successful read', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const {queries} = require('./ai-agent-read-queries');

  const uid = 'agentQueryAdmin1';
  const admin = {auth: {uid, token: {admin: true, email_verified: true, email: 'agentquery1@example.test'}}};
  await db.collection('_adminSessions').doc(uid).set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  await db.collection('aiAgentConfig').doc('global').set({enabled: true, modules: {}, llmProvider: 'none', voiceProvider: 'text-match'});
  await db.collection('aiAgentRoles').doc(uid).set({role: 'owner'});

  await assert.rejects(() => fns.queryAgentIntegration.run({...admin, data: {query: 'nope.unknown'}}), /Unknown query/);

  // Stub a temporary query entry so this test never makes a real network call.
  queries['test.stub'] = {
    module: 'github', minRole: 'owner',
    describe: () => 'stub query',
    validate: p => ({echo: String(p.echo || '')}),
    run: async p => ({echoed: p.echo}),
  };
  try {
    await db.collection('aiAgentConfig').doc('global').set({modules: {github: false}}, {merge: true});
    await assert.rejects(() => fns.queryAgentIntegration.run({...admin, data: {query: 'test.stub', params: {echo: 'hi'}}}), /turned off/);
    await db.collection('aiAgentConfig').doc('global').set({modules: {github: true}}, {merge: true});

    await db.collection('aiAgentRoles').doc(uid).set({role: 'viewer'});
    await assert.rejects(() => fns.queryAgentIntegration.run({...admin, data: {query: 'test.stub', params: {echo: 'hi'}}}), /requires the "owner" role/);

    await db.collection('aiAgentRoles').doc(uid).set({role: 'owner'});
    const result = await fns.queryAgentIntegration.run({...admin, data: {query: 'test.stub', params: {echo: 'hi'}}});
    assert.deepEqual(result, {ok: true, data: {echoed: 'hi'}});
  } finally {
    delete queries['test.stub'];
  }
});
