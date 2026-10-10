'use strict';
// The propose -> confirm -> (client executes) -> report pipeline, mirroring
// the existing vendorChanges pending/approved/rejected pattern. This file
// NEVER performs a vendor/staff/content/layout write itself: confirmAgentAction
// only validates and then hands back a descriptor (which existing Firestore
// write shape or which existing callable to use); the client performs that
// exact write through the app's own existing Store.save()/httpsCallable() code,
// then calls reportAgentActionExecuted so the audit log reflects the outcome.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {requireAdminSession} = require('./admin-session');
const {actions} = require('./ai-agent-actions');
const {requireModuleEnabled} = require('./ai-agent-config');
const {requireRole} = require('./ai-agent-rbac');
const {writeAuditLog} = require('./ai-agent-audit-log');
const {verifyAgentPin, requireRecentOtp, pinPepper} = require('./ai-agent-confirmation');
const github = require('./ai-agent-github');
const playConsole = require('./ai-agent-playconsole');
const db = getFirestore();
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};

// kind:'serverAction' entries name their integration/writeFn as plain
// strings (see ai-agent-actions.js's header comment) so this is the one
// place that maps those strings to the real functions.
const integrationModules = {github, playConsole};

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

exports.proposeAgentAction = onCall(options, async request => {
  const uid = await requireAdmin(request);
  const actionKey = String(request.data?.action || '');
  const action = actions[actionKey];
  if (!action) throw new HttpsError('invalid-argument', 'Unknown action. The agent can only propose a whitelisted action.');
  await requireModuleEnabled(action.module);
  await requireRole(uid, action.minRole || 'operator');
  let params;
  try {
    params = action.validate(request.data?.params || {});
  } catch (error) {
    throw new HttpsError('invalid-argument', error.message);
  }
  const preview = action.describe(params);
  const doc = {
    uid, action: actionKey, module: action.module, tier: action.tier,
    params, preview, status: 'pending', createdAt: FieldValue.serverTimestamp(),
  };
  const ref = await db.collection('aiAgentPendingActions').add(doc);
  await writeAuditLog({uid, type: 'propose', action: actionKey, detail: preview});
  return {pendingActionId: ref.id, preview, tier: action.tier};
});

exports.confirmAgentAction = onCall({...options, secrets: [pinPepper, github.privateKey]}, async request => {
  const uid = await requireAdmin(request);
  const pendingActionId = String(request.data?.pendingActionId || '');
  const ref = db.collection('aiAgentPendingActions').doc(pendingActionId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'This proposed action no longer exists.');
  const doc = snap.data();
  if (doc.uid !== uid) throw new HttpsError('permission-denied', 'Only the admin who proposed this action can decide it.');
  if (doc.status !== 'pending') throw new HttpsError('failed-precondition', 'This action was already decided.');
  const action = actions[doc.action];
  if (!action) throw new HttpsError('failed-precondition', 'This action is no longer available.');
  await requireModuleEnabled(action.module);
  await requireRole(uid, action.minRole || 'operator');

  if (request.data?.reject === true) {
    await ref.update({status: 'rejected', decidedAt: FieldValue.serverTimestamp()});
    await writeAuditLog({uid, type: 'reject', action: doc.action, detail: doc.preview});
    return {ok: true, status: 'rejected'};
  }

  if (action.tier === 'sensitive') {
    await verifyAgentPin(uid, request.data?.pin, pinPepper.value());
  } else if (action.tier === 'critical') {
    await requireRecentOtp(uid);
  }

  await ref.update({status: 'confirmed', decidedAt: FieldValue.serverTimestamp()});
  await writeAuditLog({uid, type: 'confirm', action: doc.action, detail: doc.preview});

  // kind:'serverAction': only the SERVER has credentials to act (GitHub App
  // key, Play Console service account) — there is nothing for the client to
  // execute, unlike the two kinds below. The server performs the write
  // itself, right here, and records the outcome — no execute descriptor,
  // no separate reportAgentActionExecuted call needed for this kind.
  if (action.kind === 'serverAction') {
    const fn = integrationModules[action.integration]?.[action.writeFn];
    let success = true, result, errorMessage;
    if (typeof fn !== 'function') {
      success = false;
      errorMessage = `Integration "${action.integration}" is not available.`;
    } else {
      try {
        result = await fn(doc.params);
      } catch (error) {
        success = false;
        errorMessage = error.message;
      }
    }
    await ref.update({status: success ? 'executed' : 'failed', executedAt: FieldValue.serverTimestamp()});
    await writeAuditLog({uid, type: 'execute', action: doc.action, detail: doc.preview, result: success ? 'success' : `failed: ${errorMessage}`});
    if (!success) throw new HttpsError('internal', errorMessage || 'The integration action failed.');
    return {ok: true, status: 'executed', result};
  }

  return {
    ok: true,
    status: 'confirmed',
    execute: action.kind === 'callable'
      ? {kind: 'callable', callableName: action.callableName, callableData: action.callableData(doc.params)}
      : {kind: 'firestoreMerge', collection: action.collection, docId: action.docId(doc.params), data: action.data(doc.params)},
  };
});

exports.reportAgentActionExecuted = onCall(options, async request => {
  const uid = await requireAdmin(request);
  const pendingActionId = String(request.data?.pendingActionId || '');
  const ref = db.collection('aiAgentPendingActions').doc(pendingActionId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Unknown pending action.');
  const doc = snap.data();
  if (doc.uid !== uid) throw new HttpsError('permission-denied', 'Not your action.');
  const success = request.data?.success === true;
  await ref.update({status: success ? 'executed' : 'failed', executedAt: FieldValue.serverTimestamp()});
  await writeAuditLog({uid, type: 'execute', action: doc.action, detail: doc.preview, result: success ? 'success' : String(request.data?.error || 'failed')});
  return {ok: true};
});
