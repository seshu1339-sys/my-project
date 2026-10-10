'use strict';
// Scheduled Firestore export + admin-only listing. Deliberately NOT automated
// restore: getRollbackInstructions only ever RETURNS the exact `gcloud
// firestore import` command for a human to run themselves — restoring
// production data is too dangerous for a one-click AI action, by design.
//
// One manual, one-time infra step this file cannot perform itself: the Cloud
// Functions service account needs the "Cloud Datastore Import Export Admin"
// IAM role for the export call below to succeed once this is actually
// deployed. Grant it via the GCP Console or:
//   gcloud projects add-iam-policy-binding <project> \
//     --member="serviceAccount:<project>@appspot.gserviceaccount.com" \
//     --role="roles/datastore.importExportAdmin"
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {GoogleAuth} = require('google-auth-library');
const {requireAdminSession} = require('./admin-session');
const {requireModuleEnabled, getConfigData} = require('./ai-agent-config');
const {writeAuditLog} = require('./ai-agent-audit-log');
const db = getFirestore();
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};
const auth = new GoogleAuth({scopes: ['https://www.googleapis.com/auth/datastore']});

function requireUser(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true) throw new HttpsError('permission-denied', 'Verify your email first.');
  return request.auth.uid;
}
async function requireAdmin(request) {
  const uid = requireUser(request);
  if (request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(uid);
  return uid;
}

async function exportFirestore() {
  const projectId = await auth.getProjectId();
  const client = await auth.getClient();
  const {token} = await client.getAccessToken();
  const bucketName = getStorage().bucket().name;
  const gcsPath = `gs://${bucketName}/ai-agent-backups/${new Date().toISOString().replace(/[:.]/g, '-')}`;
  const res = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default):exportDocuments`, {
    method: 'POST',
    headers: {authorization: `Bearer ${token}`, 'content-type': 'application/json'},
    body: JSON.stringify({outputUriPrefix: gcsPath}),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(json?.error?.message || 'Firestore export request failed.');
  return {gcsPath, operationName: json.name};
}

exports.aiAgentDailyBackup = onSchedule({schedule: 'every 24 hours', region: 'asia-south1', maxInstances: 1, timeoutSeconds: 540}, async () => {
  const config = await getConfigData();
  if (!config.enabled || config.modules?.backup === false) return;
  try {
    const {gcsPath, operationName} = await exportFirestore();
    await db.collection('_aiAgentBackupJobs').add({gcsPath, operationName, startedAt: FieldValue.serverTimestamp(), status: 'started'});
    await writeAuditLog({type: 'backup', action: 'export', detail: gcsPath, result: 'started'});
  } catch (error) {
    await writeAuditLog({type: 'backup', action: 'export', result: `failed: ${error.message}`});
  }
});

exports.requestBackupNow = onCall(options, async request => {
  const uid = await requireAdmin(request);
  await requireModuleEnabled('backup');
  const {gcsPath, operationName} = await exportFirestore();
  await db.collection('_aiAgentBackupJobs').add({gcsPath, operationName, startedAt: FieldValue.serverTimestamp(), status: 'started', requestedBy: uid});
  await writeAuditLog({uid, type: 'backup', action: 'export', detail: gcsPath, result: 'started'});
  return {gcsPath};
});

exports.listBackups = onCall(options, async request => {
  await requireAdmin(request);
  await requireModuleEnabled('backup');
  const snap = await db.collection('_aiAgentBackupJobs').orderBy('startedAt', 'desc').limit(20).get();
  return {backups: snap.docs.map(d => ({id: d.id, ...d.data(), startedAt: d.data().startedAt?.toMillis?.() || null}))};
});

exports.getRollbackInstructions = onCall(options, async request => {
  await requireAdmin(request);
  await requireModuleEnabled('backup');
  const jobId = String(request.data?.jobId || '');
  const snap = await db.collection('_aiAgentBackupJobs').doc(jobId).get();
  if (!snap.exists) throw new HttpsError('not-found', 'Unknown backup job.');
  const projectId = await auth.getProjectId();
  const gcsPath = snap.data().gcsPath;
  return {
    gcsPath,
    command: `gcloud firestore import ${gcsPath} --project=${projectId}`,
    warning: 'This replaces live production Firestore data. Run it only from a trusted machine with gcloud authenticated as a project owner, never from inside this app.',
  };
});
