'use strict';
// Read-only sibling of ai-agent-executor.js. A query has nothing to confirm
// (nothing changes), so it bypasses the propose/confirm pipeline entirely:
// validate -> run -> audit-log -> return the data directly. No
// aiAgentPendingActions doc is ever created for a read.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {requireAdminSession} = require('./admin-session');
const {requireModuleEnabled} = require('./ai-agent-config');
const {requireRole} = require('./ai-agent-rbac');
const {writeAuditLog} = require('./ai-agent-audit-log');
const {queries} = require('./ai-agent-read-queries');
const {privateKey: githubPrivateKey} = require('./ai-agent-github');

const options = {region: 'us-central1', maxInstances: 10, invoker: 'public', secrets: [githubPrivateKey]};

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

exports.queryAgentIntegration = onCall(options, async request => {
  const uid = await requireAdmin(request);
  const queryKey = String(request.data?.query || '');
  const entry = queries[queryKey];
  if (!entry) throw new HttpsError('invalid-argument', 'Unknown query. The agent can only run a whitelisted query.');
  await requireModuleEnabled(entry.module);
  await requireRole(uid, entry.minRole || 'viewer');

  let params;
  try {
    params = entry.validate(request.data?.params || {});
  } catch (error) {
    throw new HttpsError('invalid-argument', error.message);
  }

  let data, success = true, errorMessage;
  try {
    data = await entry.run(params);
  } catch (error) {
    success = false;
    errorMessage = error.message;
  }
  await writeAuditLog({uid, type: 'read', action: queryKey, detail: entry.describe(params), result: success ? 'success' : `failed: ${errorMessage}`});
  if (!success) throw new HttpsError('internal', errorMessage || 'The query failed.');
  return {ok: true, data};
});
