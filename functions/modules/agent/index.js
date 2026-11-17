'use strict';
// Agent module (owner spec C + I, 17 Nov 2026): the server side of the admin command box. Admin-only callables:
//
//   setAiKey     admin -> {provider, key}  -> {provider, set, last4, setAt}  saves the AI key in _private/aiKey (server-only; '' clears it)
//   aiKeyStatus  admin -> {}               -> {provider, set, last4, setAt, source: 'admin' | 'secret' | 'none'}
//
// The key itself is never sent back to any app: only whether it is set and its last 4 letters. Every change is written to agentLog
// (who, what, when). Requires no other feature module, only the shared root files.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {requireRole, isAdminToken} = require('../../role-auth');
const {requireAdminSession} = require('../../admin-session');
const {keyIsSet} = require('../../ai-models');
const {PROVIDERS, resetAiKeyCache} = require('../../ai-key');

const options = {region: 'us-central1', maxInstances: 2, invoker: 'public'};

async function requireAdmin(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  requireRole(request);
  if (!isAdminToken(request.auth.token)) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
  return request.auth.uid;
}

/// What the admin page may see about the key.
async function keyStatus(db) {
  const data = (await db.collection('_private').doc('aiKey').get()).data() || {};
  const adminSet = keyIsSet(data.key);
  const secretSet = keyIsSet(process.env.ANTHROPIC_API_KEY);
  return {
    provider: PROVIDERS.includes(data.provider) ? data.provider : 'anthropic',
    set: adminSet || secretSet,
    last4: adminSet ? String(data.last4 || '') : '',
    setAt: data.setAt?.toMillis?.() ?? null,
    source: adminSet ? 'admin' : secretSet ? 'secret' : 'none',
  };
}

/// Saves (or with key '' clears) the admin's AI key. [uid] is the admin; [now] for the tests.
async function saveKey(db, uid, data = {}, now = Date.now()) {
  const provider = String(data.provider ?? 'anthropic');
  if (!PROVIDERS.includes(provider)) throw new HttpsError('invalid-argument', `Provider must be one of: ${PROVIDERS.join(', ')}.`);
  const key = String(data.key ?? '').trim();
  if (key && !keyIsSet(key)) throw new HttpsError('invalid-argument', 'That does not look like an API key (at least 20 letters).');
  if (key.length > 300) throw new HttpsError('invalid-argument', 'That key is too long.');
  if (key && provider === 'anthropic' && !key.startsWith('sk-ant-')) throw new HttpsError('invalid-argument', 'An Anthropic key starts with "sk-ant-".');
  const at = Timestamp.fromMillis(now);
  await db.collection('_private').doc('aiKey').set({provider, key, last4: key ? key.slice(-4) : '', setAt: at, setBy: uid});
  await db.collection('agentLog').add({uid, email: '', action: key ? 'ai_key_set' : 'ai_key_cleared', command: '', target: provider, platform: '', details: {}, at});
  resetAiKeyCache();
  return keyStatus(db);
}

exports.setAiKey = onCall(options, async request => saveKey(getFirestore(), await requireAdmin(request), request.data || {}));
exports.aiKeyStatus = onCall(options, async request => {
  await requireAdmin(request);
  return keyStatus(getFirestore());
});

exports._test = {keyStatus, saveKey};
