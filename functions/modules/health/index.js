'use strict';
// Health module (owner spec F + H, 17 Nov 2026): the website / admin self-test, its results, and the "AI explain" of a failure.
//
//   dailyHealthCheck      task, 05:20 India time from hourlyTasks (no new scheduler job)   runs the checks (checks.js), no AI
//   runHealthCheckNow     admin -> {} -> {ok, failed, checks}                              the Health page's "Run now"
//   explainHealthProblem  admin -> {key, title, error, where} -> {text}                    only when settings/agent.aiExplain is 'true'
//
//   healthStatus/current   {at, ok, failed, checks: {<safe id>: {id, name, group, ok, error, ms, registryIds, since, explain}}, serverErrors}
//   healthRuns/<runId>     {at, ok, failed, results}   the last 30 runs
//   healthExplain/<key>    {text, at}                  each failure is explained once (later views cost nothing)
//
// Real server errors: the ERROR lines of the last 24 hours from Cloud Logging (read with the functions' own account; reading logs has no
// charge), grouped by function and message. When the logs cannot be read, the Health page says so instead of failing the check.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, Timestamp, FieldValue} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {requireRole, isAdminToken} = require('../../role-auth');
const {requireAdminSession} = require('../../admin-session');
const {task} = require('../../task');
const {anthropic, anthropicKey, loadAiKey, logAiCall, takeDailyUse, AI_MODELS} = require('../ai-core');
const {buildChecks, runChecks} = require('./checks');

const KEEP_RUNS = 30;
const EXPLAIN_PER_DAY = 30;
const EXPLAIN_PER_RUN = 5;
const options = {region: 'us-central1', maxInstances: 2, invoker: 'public', timeoutSeconds: 300, secrets: [anthropicKey]};

const safeId = id => String(id).replace(/[^A-Za-z0-9_-]+/g, '_').slice(0, 120);
const project = () => process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || JSON.parse(process.env.FIREBASE_CONFIG || '{}').projectId || 'demo';

async function requireAdmin(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  requireRole(request);
  if (!isAdminToken(request.auth.token)) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
  return request.auth.uid;
}

/// The ERROR lines of the server in the last 24 hours, grouped: [{service, message, count, last}]. [readLogs] is the REST call (a fake
/// in the tests). Returns {ok: false, note} when the logs cannot be read.
async function serverErrors(readLogs, now = Date.now()) {
  try {
    const since = new Date(now - 24 * 3600 * 1000).toISOString();
    const entries = await readLogs(`severity>=ERROR AND timestamp>="${since}" AND (resource.type="cloud_run_revision" OR resource.type="cloud_function")`);
    const groups = new Map();
    for (const e of entries) {
      const service = e.resource?.labels?.service_name || e.resource?.labels?.function_name || 'server';
      const raw = e.textPayload || e.jsonPayload?.message || e.jsonPayload?.error || JSON.stringify(e.jsonPayload || {}).slice(0, 200);
      const message = String(raw).split('\n')[0].replace(/\d{6,}/g, '<n>').slice(0, 200);
      const key = `${service}|${message}`;
      const g = groups.get(key) || {service, message, count: 0, last: ''};
      g.count++;
      if (!g.last || e.timestamp > g.last) g.last = e.timestamp;
      groups.set(key, g);
    }
    return {ok: true, list: [...groups.values()].sort((a, b) => b.count - a.count).slice(0, 30)};
  } catch (error) {
    return {ok: false, note: `Server logs could not be read: ${String(error?.message || error).slice(0, 200)}`, list: []};
  }
}

/// Reads Cloud Logging with the functions' own account (google-auth-library is already a dependency).
async function readCloudLogs(filter) {
  const {GoogleAuth} = require('google-auth-library');
  const client = await new GoogleAuth({scopes: ['https://www.googleapis.com/auth/logging.read']}).getClient();
  const res = await client.request({
    url: 'https://logging.googleapis.com/v2/entries:list', method: 'POST',
    data: {resourceNames: [`projects/${project()}`], filter, orderBy: 'timestamp desc', pageSize: 300},
  });
  return res.data.entries || [];
}

/// One run: the checks, the server errors, the status the admin panel reads (with when each failure started), the run history, and
/// (only with AI explain on) an explanation of each NEW failure. [deps] are fakes in the tests.
async function runHealth(db, deps = {}) {
  const now = deps.now ?? Date.now();
  const runId = `run_${now}`;
  const healthSettings = (await db.collection('settings').doc('health').get()).data() || {};
  const checks = deps.checks ?? buildChecks({db, bucket: deps.bucket ?? getStorage().bucket(), fetch: deps.fetch ?? fetch, project: project(), now, runId}, healthSettings);
  const results = await runChecks(checks);
  const logs = await serverErrors(deps.readLogs ?? readCloudLogs, now);
  const statusRef = db.collection('healthStatus').doc('current');
  const before = (await statusRef.get()).data()?.checks || {};
  const at = Timestamp.fromMillis(now);
  const map = {};
  const newlyFailed = [];
  for (const r of results) {
    const old = before[safeId(r.id)];
    const since = r.ok ? null : old && !old.ok && old.since ? old.since : at;
    if (!r.ok && (!old || old.ok)) newlyFailed.push(r);
    map[safeId(r.id)] = {...r, since, explain: !r.ok && old && !old.ok ? old.explain || '' : ''};
  }
  const failed = results.filter(r => !r.ok).length;
  // Explain the new failures (AI explain ON only; at most a few a run, and each failure once).
  const agent = (await db.collection('settings').doc('agent').get()).data() || {};
  if (agent.aiExplain === 'true') {
    for (const r of newlyFailed.slice(0, EXPLAIN_PER_RUN)) {
      try {
        map[safeId(r.id)].explain = await explain(db, deps.client ?? anthropic, 'system', {key: `check_${safeId(r.id)}_${hash(r.error)}`, title: r.name, error: r.error, where: r.group}, now);
      } catch (error) {
        console.warn('Health explain skipped', error.message);
      }
    }
  }
  await statusRef.set({at, ok: failed === 0 && logs.list.length === 0, failed, checks: map, serverErrors: logs.list, serverErrorsNote: logs.ok ? '' : logs.note});
  await db.collection('healthRuns').doc(runId).set({at, ok: failed === 0, failed, results, serverErrors: logs.list.length});
  const old = await db.collection('healthRuns').orderBy('at', 'desc').offset(KEEP_RUNS).limit(50).get();
  await Promise.all(old.docs.map(d => d.ref.delete()));
  return {ok: failed === 0, failed, checks: results, serverErrors: logs.list, newlyFailed: newlyFailed.map(r => r.id)};
}

function hash(text) {
  let h = 0x811c9dc5;
  for (const c of String(text)) h = Math.imul(h ^ c.charCodeAt(0), 0x01000193) >>> 0;
  return h.toString(16);
}

const EXPLAIN_SYSTEM = 'You help the owner of LOCAMARKET (a local marketplace: a Flutter customer website and admin panel on Firebase Hosting, ' +
  'Cloud Functions in Node.js, Firestore, Storage, and three Flutter Android apps: Vendor, Staff, User). A health check or an app found a ' +
  'failure. Answer in simple Telugu (technical names may stay in English) with exactly three parts, each under a heading:\n' +
  '1. కారణం — the most likely reason, in two or three sentences.\n2. ఎలా సరిచేయాలి — the steps to fix it, short.\n' +
  '3. Claude Code prompt — a ready prompt IN ENGLISH, in a code block, that the owner can paste into Claude Code in the project folder: ' +
  'name the failure, the error text, where it happens, and ask to find the cause, fix it with tests, and not deploy without approval.\n' +
  'Never invent file names you do not know; say "find the code that ..." instead.';

/// One explanation, cached by [key] (each failure is explained once). [client] makes the Anthropic client.
async function explain(db, client, uid, {key, title, error, where}, now = Date.now()) {
  const id = safeId(key || `${title}_${hash(error)}`);
  const ref = db.collection('healthExplain').doc(id);
  const cached = (await ref.get()).data();
  if (cached?.text) return cached.text;
  if (!(await loadAiKey(db))) throw new HttpsError('failed-precondition', 'The AI key is not set. Set it in Settings > AI provider & usage.');
  if (!(await takeDailyUse(db, 'health_explain', EXPLAIN_PER_DAY, now))) throw new HttpsError('resource-exhausted', `Today's ${EXPLAIN_PER_DAY} explanations are used. Try tomorrow.`);
  const response = await client().messages.create({
    model: AI_MODELS.chat, max_tokens: 1200,
    thinking: {type: 'disabled'},
    system: EXPLAIN_SYSTEM,
    messages: [{role: 'user', content: `Failure: ${String(title).slice(0, 200)}\nWhere: ${String(where).slice(0, 200)}\nError: ${String(error).slice(0, 1500)}`}],
  });
  await logAiCall(db, {feature: 'health_explain', model: AI_MODELS.chat, usage: response.usage, uid, stopReason: response.stop_reason}, now);
  const text = response.content.filter(b => b.type === 'text').map(b => b.text).join('\n').trim();
  if (text) await ref.set({text, at: Timestamp.fromMillis(now), title: String(title).slice(0, 200)});
  return text || 'No explanation this time.';
}

exports.dailyHealthCheck = task(async () => {
  const result = await runHealth(getFirestore());
  console.log('Health check', {failed: result.failed, newlyFailed: result.newlyFailed, serverErrors: result.serverErrors.length});
});

exports.runHealthCheckNow = onCall(options, async request => {
  const uid = await requireAdmin(request);
  const db = getFirestore();
  const result = await runHealth(db);
  await db.collection('agentLog').add({uid, email: '', action: 'health_run', command: '', target: `${result.failed} failed`, platform: '', details: {}, at: FieldValue.serverTimestamp()});
  return {ok: result.ok, failed: result.failed, checks: result.checks};
});

exports.explainHealthProblem = onCall(options, async request => {
  const uid = await requireAdmin(request);
  const db = getFirestore();
  const agent = (await db.collection('settings').doc('agent').get()).data() || {};
  if (agent.aiExplain !== 'true') throw new HttpsError('failed-precondition', 'AI explain is OFF. Turn it on in Settings > AI provider & usage.');
  const d = request.data || {};
  if (!d.title && !d.error) throw new HttpsError('invalid-argument', 'Say which failure.');
  return {text: await explain(db, anthropic, uid, {key: d.key, title: d.title || '', error: d.error || '', where: d.where || ''})};
});

exports._test = {runHealth, serverErrors, explain, safeId, EXPLAIN_SYSTEM};
