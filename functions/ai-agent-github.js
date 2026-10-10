'use strict';
// GitHub integration for the Master AI Agent. Auth is a GitHub App
// (GitHub's own recommendation over a personal access token for unattended
// automation: per-repo least-privilege, short-lived ~1h installation
// tokens, not tied to a personal account). Exports only plain functions —
// no onCall callables here — consumed by ai-agent-read-queries.js (reads)
// and ai-agent-actions.js/ai-agent-executor.js (serverAction writes).
//
// Non-secret config (App ID, installation ID) lives in
// aiAgentConfig/global.integrations.github.*, set via
// ai-agent-config.js's setAgentIntegrationSetting. The ONLY real secret is
// the App's private key (`privateKey`, exported below so any onCall that
// transitively calls into this module can list it in its own `secrets:`
// array — Firebase Functions only makes a secret's value readable to a
// function that explicitly declares it).
const {HttpsError} = require('firebase-functions/v2/https');
const {defineSecret} = require('firebase-functions/params');
const {createSign} = require('node:crypto');
const {getConfigData} = require('./ai-agent-config');

const privateKey = defineSecret('AI_AGENT_GITHUB_APP_PRIVATE_KEY');

function base64url(input) {
  return Buffer.from(input).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function signAppJwt(appId, pem) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({alg: 'RS256', typ: 'JWT'}));
  const payload = base64url(JSON.stringify({iat: now - 30, exp: now + 540, iss: appId}));
  const signer = createSign('RSA-SHA256');
  signer.update(`${header}.${payload}`);
  signer.end();
  const signature = base64url(signer.sign(pem));
  return `${header}.${payload}.${signature}`;
}

// Cached in-memory across warm invocations only; a cold start just re-mints
// a token, which is cheap and harmless. No Firestore doc needed for this.
let cachedToken = null;

async function getInstallationToken() {
  const config = await getConfigData();
  const appId = config.integrations?.github?.appId;
  const installationId = config.integrations?.github?.installationId;
  if (!appId || !installationId) {
    throw new HttpsError('failed-precondition', 'GitHub integration is not configured yet — set appId/installationId in AI Agent settings.');
  }
  if (!privateKey.value()) {
    throw new HttpsError('failed-precondition', 'The GitHub App private key secret is not set yet.');
  }
  if (cachedToken && cachedToken.expiresAt - Date.now() > 60 * 1000) return cachedToken.token;
  const jwt = signAppJwt(appId, privateKey.value());
  const res = await fetch(`https://api.github.com/app/installations/${installationId}/access_tokens`, {
    method: 'POST',
    headers: {authorization: `Bearer ${jwt}`, accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'},
  });
  const json = await res.json();
  if (!res.ok) throw new HttpsError('internal', json?.message || 'Could not mint a GitHub installation token.');
  cachedToken = {token: json.token, expiresAt: Date.parse(json.expires_at)};
  return cachedToken.token;
}

async function githubFetch(path, init = {}) {
  const token = await getInstallationToken();
  const res = await fetch(`https://api.github.com${path}`, {
    ...init,
    headers: {...init.headers, authorization: `Bearer ${token}`, accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'},
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(json?.message || `GitHub API error (${res.status})`);
  return json;
}

// ---- reads ----
async function getCombinedStatus({repo, ref}) { return githubFetch(`/repos/${repo}/commits/${encodeURIComponent(ref)}/status`); }
async function listPullRequests({repo, state}) { return githubFetch(`/repos/${repo}/pulls?state=${state || 'open'}`); }
async function listWorkflowRuns({repo}) { return githubFetch(`/repos/${repo}/actions/runs?per_page=10`); }
async function listReleases({repo}) { return githubFetch(`/repos/${repo}/releases?per_page=10`); }

// ---- writes (always behind confirmAgentAction's PIN/OTP gate) ----
async function mergePullRequest({repo, prNumber, mergeMethod}) {
  return githubFetch(`/repos/${repo}/pulls/${prNumber}/merge`, {
    method: 'PUT', headers: {'content-type': 'application/json'}, body: JSON.stringify({merge_method: mergeMethod || 'merge'}),
  });
}
async function createRelease({repo, tagName, name, body}) {
  return githubFetch(`/repos/${repo}/releases`, {
    method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({tag_name: tagName, name: name || tagName, body: body || ''}),
  });
}
async function deleteBranch({repo, branch}) {
  await githubFetch(`/repos/${repo}/git/refs/heads/${encodeURIComponent(branch)}`, {method: 'DELETE'});
  return {deleted: true};
}
async function dispatchWorkflow({repo, workflowId, ref, inputs}) {
  await githubFetch(`/repos/${repo}/actions/workflows/${workflowId}/dispatches`, {
    method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({ref: ref || 'main', inputs: inputs || {}}),
  });
  return {dispatched: true};
}

module.exports = {
  privateKey, signAppJwt, getInstallationToken,
  getCombinedStatus, listPullRequests, listWorkflowRuns, listReleases,
  mergePullRequest, createRelease, deleteBranch, dispatchWorkflow,
};
