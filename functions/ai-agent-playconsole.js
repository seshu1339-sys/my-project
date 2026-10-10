'use strict';
// Google Play Console integration for the Master AI Agent. Auth reuses the
// EXISTING Cloud Functions runtime service account via Application Default
// Credentials — the exact GoogleAuth template already used in
// ai-agent-backup.js, just a different scope. Zero new secrets: the one-time
// setup step is granting that same service account access directly in Play
// Console -> Setup -> API access (see ai-agent-config.js's
// setAgentIntegrationSetting for the non-secret packageName config).
//
// The Play Developer API makes even READING track status go through its
// transactional "edit" model (edits.insert -> read/write -> commit/delete) —
// confirmed via official docs, not an implementation choice. withEdit() below
// guarantees the edit is always deleted, even if the read/write throws.
const {GoogleAuth} = require('google-auth-library');
const {getConfigData} = require('./ai-agent-config');

const auth = new GoogleAuth({scopes: ['https://www.googleapis.com/auth/androidpublisher']});
const BASE_URL = 'https://androidpublisher.googleapis.com/androidpublisher/v3';

async function getToken() {
  const client = await auth.getClient();
  const {token} = await client.getAccessToken();
  return token;
}

async function requirePackageName(explicit) {
  if (explicit) return explicit;
  const config = await getConfigData();
  const packageName = config.integrations?.playConsole?.packageName;
  if (!packageName) throw new Error('Google Play Console integration is not configured yet — set packageName in AI Agent settings.');
  return packageName;
}

async function playFetch(path, init = {}) {
  const token = await getToken();
  const res = await fetch(`${BASE_URL}${path}`, {
    ...init,
    headers: {...init.headers, authorization: `Bearer ${token}`, 'content-type': 'application/json'},
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    const message = json?.error?.message || `Play Developer API error (${res.status})`;
    const error = new Error(message);
    // Google's post-2023 policy gate (personal accounts need a 12-tester,
    // 14-day closed test before Production unlocks) surfaces as an API error
    // message, not a distinct error code — detect it so the agent reports
    // the gap instead of treating it as a bug, per the explicit spec requirement.
    error.policyGateBlocked = /closed test|testers?|production access/i.test(message);
    throw error;
  }
  return json;
}

// Guarantees the edit is deleted even if `fn` throws. Edits also auto-expire
// server-side as a second line of defense, but this is the real guarantee.
async function withEdit(packageName, fn) {
  const base = `/applications/${packageName}`;
  const {id: editId} = await playFetch(`${base}/edits`, {method: 'POST', body: '{}'});
  try {
    return await fn({base, editId});
  } finally {
    await playFetch(`${base}/edits/${editId}`, {method: 'DELETE'}).catch(() => {});
  }
}

async function getTrackStatus({packageName, track}) {
  const pkg = await requirePackageName(packageName);
  return withEdit(pkg, async ({base, editId}) => {
    try {
      const data = await playFetch(`${base}/edits/${editId}/tracks/${track}`);
      return {track: data.track, releases: data.releases || []};
    } catch (error) {
      if (error.policyGateBlocked) return {policyGateBlocked: true, reason: error.message};
      throw error;
    }
  });
}

// serverAction write (tier 'critical', 'owner' role). Cannot create a new
// app, publish/unpublish, or complete content-rating forms — the API has no
// such capability; callers must not attempt it.
async function setTrackRollout({packageName, track, userFraction}) {
  const pkg = await requirePackageName(packageName);
  return withEdit(pkg, async ({base, editId}) => {
    await playFetch(`${base}/edits/${editId}/tracks/${track}`, {
      method: 'PUT', body: JSON.stringify({track, releases: [{status: 'inProgress', userFraction}]}),
    });
    const commit = await playFetch(`${base}/edits/${editId}:commit`, {method: 'POST', body: '{}'});
    return {committed: true, editId: commit.id};
  });
}

module.exports = {getTrackStatus, setTrackRollout, withEdit, playFetch};
