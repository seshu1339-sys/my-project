const {test} = require('node:test');
const assert = require('node:assert/strict');

test('AI Agent RBAC: bootstrap carve-out and role ranking', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  require('./index'); // initializeApp() side effect, same convention as every other ai-agent-*.test.js
  const {getFirestore} = require('firebase-admin/firestore');
  const {getRole, requireRole} = require('./ai-agent-rbac');
  const db = getFirestore();

  // Other test files (executor/confirmation/query) also seed aiAgentRoles
  // docs for their own uids, so this test cannot assume the collection is
  // still empty just because it's a fresh emulator — it makes that true
  // itself first, so the bootstrap-carve-out assertion below is deterministic
  // regardless of what ran earlier in the same emulator session.
  const existing = await db.collection('aiAgentRoles').get();
  await Promise.all(existing.docs.map(doc => doc.ref.delete()));

  assert.equal(await getRole('rbacNeverWrittenBeforeBootstrap'), 'owner');

  await db.collection('aiAgentRoles').doc('rbacOwner1').set({role: 'owner'});
  await db.collection('aiAgentRoles').doc('rbacOperator1').set({role: 'operator'});
  await db.collection('aiAgentRoles').doc('rbacViewer1').set({role: 'viewer'});

  assert.equal(await getRole('rbacOwner1'), 'owner');
  assert.equal(await getRole('rbacOperator1'), 'operator');
  assert.equal(await getRole('rbacViewer1'), 'viewer');
  // Now that the collection is non-empty, an uid with no doc is 'viewer' —
  // the carve-out has ended, same fail-closed philosophy as requireModuleEnabled.
  assert.equal(await getRole('rbacNeverWrittenAfterBootstrap'), 'viewer');

  await requireRole('rbacOwner1', 'owner');
  await requireRole('rbacOperator1', 'operator');
  await requireRole('rbacViewer1', 'viewer');
  await assert.rejects(() => requireRole('rbacOperator1', 'owner'), /requires the "owner" role/);
  await assert.rejects(() => requireRole('rbacViewer1', 'operator'), /requires the "operator" role/);
});
