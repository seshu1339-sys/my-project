const {test} = require('node:test');
const assert = require('node:assert/strict');

test('AI Agent confirmation: Agent PIN set/validate and gate a sensitive action', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const uid = 'agentPinAdmin1';
  const admin = {auth: {uid, token: {admin: true, email_verified: true, email: 'agentpin1@example.test'}}};
  await db.collection('_adminSessions').doc(uid).set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  await db.collection('aiAgentRoles').doc(uid).set({role: 'owner'});

  await assert.rejects(() => fns.setAgentPin.run({...admin, data: {pin: '12'}}), /4-8 digits/);
  const ok = await fns.setAgentPin.run({...admin, data: {pin: '246810'}});
  assert.equal(ok.ok, true);

  await db.collection('aiAgentConfig').doc('global').set({enabled: true, modules: {}, llmProvider: 'none', voiceProvider: 'text-match'});
  const proposal = await fns.proposeAgentAction.run({...admin, data: {action: 'suspendVendor', params: {vendorId: 'v9', reason: 'test reason'}}});

  await assert.rejects(() => fns.confirmAgentAction.run({...admin, data: {pendingActionId: proposal.pendingActionId, pin: '000000'}}), /Incorrect Agent PIN/);
  const confirmed = await fns.confirmAgentAction.run({...admin, data: {pendingActionId: proposal.pendingActionId, pin: '246810'}});
  assert.equal(confirmed.status, 'confirmed');
});
