'use strict';
// Firebase Hosting / Cloud Functions status checks for the Master AI Agent.
// Read-only ONLY, by deliberate scope decision: triggering a real deploy is
// a separate multi-step flow (versions.create -> populateFiles ->
// versions.patch FINALIZED -> releases.create for Hosting) and this project
// already has a standing no-auto-deploy posture (see ai-agent-backup.js's
// rollback-is-instructions-only precedent) — a future deployHostingRelease
// serverAction can be added later without any executor change.
//
// Same GoogleAuth/ADC template as ai-agent-backup.js and ai-agent-playconsole.js.
// Needs the runtime service account granted roles/firebasehosting.viewer and
// roles/cloudfunctions.viewer in GCP IAM (one-time manual step).
const {GoogleAuth} = require('google-auth-library');

const auth = new GoogleAuth({scopes: ['https://www.googleapis.com/auth/cloud-platform']});

async function getToken() {
  const client = await auth.getClient();
  const {token} = await client.getAccessToken();
  return token;
}

async function googleFetch(url) {
  const token = await getToken();
  const res = await fetch(url, {headers: {authorization: `Bearer ${token}`}});
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(json?.error?.message || `Google API error (${res.status})`);
  return json;
}

// One-shot, genuinely non-transactional — unlike Play Console's tracks.
async function getHostingReleaseStatus({siteId}) {
  const data = await googleFetch(`https://firebasehosting.googleapis.com/v1beta1/sites/${siteId}/releases?pageSize=1`);
  const release = data.releases?.[0];
  if (!release) return {siteId, liveVersion: null};
  return {siteId, liveVersion: release.version?.name, releaseType: release.type, releaseTime: release.releaseTime};
}

async function getFunctionStatus({functionName, project, location = 'us-central1'}) {
  const data = await googleFetch(`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/${location}/functions/${functionName}`);
  return {name: data.name, state: data.state, updateTime: data.updateTime};
}

module.exports = {getHostingReleaseStatus, getFunctionStatus};
