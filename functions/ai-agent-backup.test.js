const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

test('AI Agent backup: rollback is instructions-only, never an automated restore', {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  const {getFirestore, Timestamp} = require('firebase-admin/firestore');
  const fns = require('./index');
  const db = getFirestore();
  const uid = 'agentBackupAdmin1';
  const admin = {auth: {uid, token: {admin: true, email_verified: true, email: 'agentbackup1@example.test'}}};
  await db.collection('_adminSessions').doc(uid).set({expiresAt: Timestamp.fromMillis(Date.now() + 3600000)});
  await db.collection('aiAgentConfig').doc('global').set({enabled: true, modules: {}, llmProvider: 'none', voiceProvider: 'text-match'});

  const jobRef = await db.collection('_aiAgentBackupJobs').add({gcsPath: 'gs://example-bucket/ai-agent-backups/2026-01-01', status: 'started'});
  const result = await fns.getRollbackInstructions.run({...admin, data: {jobId: jobRef.id}});
  assert.match(result.command, /^gcloud firestore import gs:\/\/example-bucket\/ai-agent-backups\/2026-01-01 --project=/);
  assert.ok(result.warning.toLowerCase().includes('production'));

  await assert.rejects(() => fns.getRollbackInstructions.run({...admin, data: {jobId: 'does-not-exist'}}), /Unknown backup job/);

  // Static safety check: the module's source never contains an automated
  // import/restore/delete call anywhere, not just in the paths exercised above.
  const source = fs.readFileSync(require.resolve('./ai-agent-backup.js'), 'utf8');
  assert.ok(!/importDocuments|restoreDocuments|\.delete\(/.test(source), 'ai-agent-backup.js must never contain an automated restore/delete call');
});
