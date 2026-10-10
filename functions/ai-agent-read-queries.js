'use strict';
// The read-only sibling of ai-agent-actions.js. A query has nothing to
// confirm, so unlike the action whitelist this file IS allowed to require
// integration modules directly — there's no execute-descriptor indirection
// to preserve for a pure read. Consumed only by ai-agent-query.js.
const github = require('./ai-agent-github');
const playConsole = require('./ai-agent-playconsole');
const firebaseOps = require('./ai-agent-firebase-ops');

function str(v) { return typeof v === 'string' ? v.trim() : ''; }
function requireRepo(p) {
  const repo = str(p.repo);
  if (!/^[\w.-]+\/[\w.-]+$/.test(repo)) throw new Error('Provide a repo as "owner/name".');
  return repo;
}

const queries = {
  'github.prStatus': {
    module: 'github', minRole: 'viewer',
    describe: p => `GitHub commit status for ${p.repo}@${p.ref}`,
    validate: p => ({repo: requireRepo(p), ref: str(p.ref) || 'HEAD'}),
    run: p => github.getCombinedStatus(p),
  },
  'github.pullRequests': {
    module: 'github', minRole: 'viewer',
    describe: p => `Pull requests (${p.state}) in ${p.repo}`,
    validate: p => ({repo: requireRepo(p), state: str(p.state) || 'open'}),
    run: p => github.listPullRequests(p),
  },
  'github.workflowRuns': {
    module: 'github', minRole: 'viewer',
    describe: p => `Recent workflow runs in ${p.repo}`,
    validate: p => ({repo: requireRepo(p)}),
    run: p => github.listWorkflowRuns(p),
  },
  'github.releases': {
    module: 'github', minRole: 'viewer',
    describe: p => `Recent releases in ${p.repo}`,
    validate: p => ({repo: requireRepo(p)}),
    run: p => github.listReleases(p),
  },
  'playConsole.trackStatus': {
    module: 'playConsole', minRole: 'operator',
    describe: p => `Play Console "${p.track}" track status`,
    validate: p => {
      const track = str(p.track);
      if (!['internal', 'alpha', 'beta', 'production'].includes(track)) {
        throw new Error('Provide a track: internal, alpha, beta, or production.');
      }
      return {packageName: str(p.packageName) || undefined, track};
    },
    run: p => playConsole.getTrackStatus(p),
  },
  'firebaseOps.hostingStatus': {
    module: 'firebaseOps', minRole: 'viewer',
    describe: p => `Firebase Hosting status for site "${p.siteId}"`,
    validate: p => {
      const siteId = str(p.siteId);
      if (!siteId) throw new Error('Provide a Hosting site id.');
      return {siteId};
    },
    run: p => firebaseOps.getHostingReleaseStatus(p),
  },
  'firebaseOps.functionStatus': {
    module: 'firebaseOps', minRole: 'viewer',
    describe: p => `Cloud Function status for "${p.functionName}"`,
    validate: p => {
      const functionName = str(p.functionName), project = str(p.project);
      if (!functionName || !project) throw new Error('Provide a function name and GCP project id.');
      return {functionName, project, location: str(p.location) || 'us-central1'};
    },
    run: p => firebaseOps.getFunctionStatus(p),
  },
};

module.exports = {queries};
