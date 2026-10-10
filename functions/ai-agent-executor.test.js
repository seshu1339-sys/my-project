const {test} = require('node:test');
const assert = require('node:assert/strict');

test('AI Agent executor: whitelist, module gating, propose/confirm/reject', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();

  const uid = 'agentExecAdmin1';
  const admin = {auth: {uid, token: {admin: true, email_verified: true, email: 'agentexec1@example.test'}}};
  await db.collection('_adminSessions').doc(uid).set({expiresAt: Timestamp.fromMillis(Date.now() + 60 * 60 * 1000)});
  // Explicit, not relying on the RBAC bootstrap carve-out — other test files
  // (ai-agent-rbac.test.js) also write to aiAgentRoles, so this cannot assume
  // the collection is still empty when this file happens to run.
  await db.collection('aiAgentRoles').doc(uid).set({role: 'owner'});

  // ---- an action not in the whitelist is always refused.
  await assert.rejects(() => fns.proposeAgentAction.run({...admin, data: {action: 'deleteEverything', params: {}}}), /Unknown action/);

  // ---- with the master switch off, even a whitelisted action is refused.
  // (Explicitly set rather than relying on a fresh doc, since other
  // ai-agent-*.test.js files share this same global config doc.)
  await db.collection('aiAgentConfig').doc('global').set({enabled: false, modules: {}, llmProvider: 'none', voiceProvider: 'text-match'});
  await assert.rejects(() => fns.proposeAgentAction.run({...admin, data: {action: 'setTickerText', params: {text: 'hi'}}}), /turned off/);

  await db.collection('aiAgentConfig').doc('global').set({enabled: true, modules: {}, llmProvider: 'none', voiceProvider: 'text-match'});

  // ---- a 'safe' tier action proposes and confirms with no PIN needed, and
  // hands back the exact existing write shape to perform (never writes itself).
  const proposal = await fns.proposeAgentAction.run({...admin, data: {action: 'setTickerText', params: {text: 'Welcome!'}}});
  assert.equal(proposal.tier, 'safe');
  const confirmed = await fns.confirmAgentAction.run({...admin, data: {pendingActionId: proposal.pendingActionId}});
  assert.equal(confirmed.status, 'confirmed');
  assert.deepEqual(confirmed.execute, {kind: 'firestoreMerge', collection: 'settings', docId: 'scrollingText', data: {text: 'Welcome!'}});

  // ---- deciding the same action twice is refused.
  await assert.rejects(() => fns.confirmAgentAction.run({...admin, data: {pendingActionId: proposal.pendingActionId}}), /already decided/);

  // ---- a 'sensitive' tier action requires a PIN; confirming without one is refused.
  const suspendProposal = await fns.proposeAgentAction.run({...admin, data: {action: 'suspendVendor', params: {vendorId: 'v1', reason: 'policy violation'}}});
  assert.equal(suspendProposal.tier, 'sensitive');
  await assert.rejects(() => fns.confirmAgentAction.run({...admin, data: {pendingActionId: suspendProposal.pendingActionId}}), /PIN/);

  // ---- disabling the action's module blocks it even though it's already proposed.
  await db.collection('aiAgentConfig').doc('global').set({modules: {approvals: false}}, {merge: true});
  await assert.rejects(() => fns.confirmAgentAction.run({...admin, data: {pendingActionId: suspendProposal.pendingActionId, pin: '123456'}}), /turned off/);

  // ---- rejecting a pending action needs no PIN and marks it rejected.
  await db.collection('aiAgentConfig').doc('global').set({modules: {approvals: true}}, {merge: true});
  const rejectResult = await fns.confirmAgentAction.run({...admin, data: {pendingActionId: suspendProposal.pendingActionId, reject: true}});
  assert.equal(rejectResult.status, 'rejected');

  // ---- only the admin who proposed an action may decide it.
  const other = {auth: {uid: 'agentExecAdmin2', token: {admin: true, email_verified: true, email: 'agentexec2@example.test'}}};
  await db.collection('_adminSessions').doc('agentExecAdmin2').set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  await db.collection('aiAgentRoles').doc('agentExecAdmin2').set({role: 'owner'});
  const anotherProposal = await fns.proposeAgentAction.run({...admin, data: {action: 'resizeSection', params: {layoutKey: 'popular', height: 400}}});
  await assert.rejects(() => fns.confirmAgentAction.run({...other, data: {pendingActionId: anotherProposal.pendingActionId}}), /Only the admin who proposed/);
});

test('AI Agent executor: serverAction branch calls the integration write function directly, existing kinds unaffected', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const {actions} = require('./ai-agent-actions');
  const github = require('./ai-agent-github');

  const uid = 'agentServerActionAdmin1';
  const admin = {auth: {uid, token: {admin: true, email_verified: true, email: 'agentserveraction1@example.test'}}};
  await db.collection('_adminSessions').doc(uid).set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  await db.collection('aiAgentRoles').doc(uid).set({role: 'owner'});
  await db.collection('aiAgentConfig').doc('global').set({enabled: true, modules: {}, llmProvider: 'none', voiceProvider: 'text-match'});

  let calledWith = null;
  github.__testStubWrite = async params => {
    calledWith = params;
    return {stubbed: true};
  };
  actions.testServerAction = {
    tier: 'sensitive', module: 'github', minRole: 'operator',
    describe: p => `stub server action ${p.value}`,
    validate: p => ({value: String(p.value || '')}),
    kind: 'serverAction', integration: 'github', writeFn: '__testStubWrite',
  };
  try {
    await fns.setAgentPin.run({...admin, data: {pin: '135790'}});

    const proposal = await fns.proposeAgentAction.run({...admin, data: {action: 'testServerAction', params: {value: 'x'}}});
    const result = await fns.confirmAgentAction.run({...admin, data: {pendingActionId: proposal.pendingActionId, pin: '135790'}});
    assert.equal(result.status, 'executed');
    assert.deepEqual(result.result, {stubbed: true});
    assert.deepEqual(calledWith, {value: 'x'});
    assert.equal(result.execute, undefined);

    // The two pre-existing kinds are still unaffected by the new branch.
    const tickerProposal = await fns.proposeAgentAction.run({...admin, data: {action: 'setTickerText', params: {text: 'still works'}}});
    const tickerConfirm = await fns.confirmAgentAction.run({...admin, data: {pendingActionId: tickerProposal.pendingActionId}});
    assert.equal(tickerConfirm.execute.kind, 'firestoreMerge');
  } finally {
    delete actions.testServerAction;
    delete github.__testStubWrite;
  }
});
