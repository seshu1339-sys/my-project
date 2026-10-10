'use strict';
// Foundation module for the AI Admin Agent: one config doc (aiAgentConfig/global)
// holding a master on/off switch, a per-module enabled map, and which pluggable
// LLM/voice provider is active. Every other ai-agent-*.js module calls
// requireModuleEnabled(moduleId) before doing anything — this is the single
// place "disable this module" (or the whole agent) is enforced server-side, so
// a client-side bug or a stale cached flag can never bypass it. Fails closed:
// if this doc doesn't exist yet, every module reports disabled.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {requireAdminSession} = require('./admin-session');
const db = getFirestore();
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};
const configRef = db.collection('aiAgentConfig').doc('global');

function requireUser(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true) throw new HttpsError('permission-denied', 'Verify your email first.');
  return request.auth.uid;
}
async function requireAdmin(request) {
  requireUser(request);
  if (request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
}

const DEFAULT_CONFIG = {
  enabled: false,
  modules: {},
  llmProvider: 'none',
  voiceProvider: 'text-match',
};

async function getConfigData() {
  const snap = await configRef.get();
  return snap.exists ? {...DEFAULT_CONFIG, ...snap.data()} : DEFAULT_CONFIG;
}

// Shared by every other ai-agent-*.js module. Fails closed: master switch off,
// a missing config doc, or an explicit `false` for this module all deny.
async function requireModuleEnabled(moduleId) {
  const config = await getConfigData();
  if (!config.enabled) throw new HttpsError('failed-precondition', 'The AI Admin Agent is turned off.');
  if (config.modules?.[moduleId] === false) throw new HttpsError('failed-precondition', `The "${moduleId}" module is turned off.`);
}

exports.getAgentConfig = onCall(options, async request => {
  await requireAdmin(request);
  return getConfigData();
});

exports.setAgentMasterEnabled = onCall(options, async request => {
  await requireAdmin(request);
  const enabled = request.data?.enabled === true;
  await configRef.set({enabled, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  return {ok: true};
});

exports.setAiAgentModuleEnabled = onCall(options, async request => {
  await requireAdmin(request);
  const moduleId = String(request.data?.moduleId || '');
  if (!moduleId) throw new HttpsError('invalid-argument', 'Provide a module id.');
  const enabled = request.data?.enabled !== false;
  await configRef.set({[`modules.${moduleId}`]: enabled, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  return {ok: true};
});

exports.setAgentLlmProvider = onCall(options, async request => {
  await requireAdmin(request);
  const provider = String(request.data?.provider || 'none');
  await configRef.set({llmProvider: provider, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  return {ok: true};
});

exports.setAgentVoiceProvider = onCall(options, async request => {
  await requireAdmin(request);
  const provider = String(request.data?.provider || 'text-match');
  await configRef.set({voiceProvider: provider, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  return {ok: true};
});

// Non-secret per-integration config (GitHub App id/installation id, Play
// Console package name, etc.) — real secrets never go through this, only
// `defineSecret` + `firebase functions:secrets:set`. Stored at
// aiAgentConfig/global.integrations.<integration>.<key>, same doc every
// other config setter already uses.
exports.setAgentIntegrationSetting = onCall(options, async request => {
  await requireAdmin(request);
  const integration = String(request.data?.integration || '');
  const key = String(request.data?.key || '');
  if (!/^[a-zA-Z0-9]+$/.test(integration) || !/^[a-zA-Z0-9]+$/.test(key)) {
    throw new HttpsError('invalid-argument', 'Provide an integration and key (letters/numbers only).');
  }
  const value = request.data?.value;
  if (typeof value !== 'string' && typeof value !== 'number' && typeof value !== 'boolean') {
    throw new HttpsError('invalid-argument', 'Provide a string, number, or boolean value.');
  }
  await configRef.set({[`integrations.${integration}.${key}`]: value, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  return {ok: true};
});

module.exports.requireModuleEnabled = requireModuleEnabled;
module.exports.getConfigData = getConfigData;
