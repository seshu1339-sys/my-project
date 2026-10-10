'use strict';
// Turns free-text (typed or voice-transcribed) into one whitelisted action.
// A zero-cost rule-based parser always runs first and is the real default;
// an LLM provider is only consulted when one is configured AND the rule-based
// parser wasn't confident, and its output is ALWAYS re-validated against the
// whitelist before being returned — the model's raw output is never trusted
// directly, and the whole provider step is skippable with zero behavior change
// (provider 'none' never makes a network call).
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret} = require('firebase-functions/params');
const {requireAdminSession} = require('./admin-session');
const {actions} = require('./ai-agent-actions');
const {queries} = require('./ai-agent-read-queries');
const {requireModuleEnabled, getConfigData} = require('./ai-agent-config');
const {writeAuditLog} = require('./ai-agent-audit-log');
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};
const CONFIDENCE_THRESHOLD = 0.6;

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

// --- Rule-based parser: always available, zero cost, zero external calls ---
// Each rule builds either a writable action ({kind:'action', action, params})
// or a pure read ({kind:'readOnly', query, params}) — the two whitelists
// (ai-agent-actions.js / ai-agent-read-queries.js) stay the single source of
// truth either way; this is only pattern -> key/params mapping.
const RULES = [
  {re: /^(?:set|change)\s+(?:the\s+)?(?:scrolling\s+)?ticker\s+(?:text\s+)?to\s+(.+)$/i,
    build: m => ({kind: 'action', action: 'setTickerText', params: {text: m[1].trim()}})},
  {re: /^suspend\s+vendor\s+(\S+)\s*(?:for|because|:)\s*(.+)$/i,
    build: m => ({kind: 'action', action: 'suspendVendor', params: {vendorId: m[1], reason: m[2].trim()}})},
  {re: /^reinstate\s+vendor\s+(\S+)$/i,
    build: m => ({kind: 'action', action: 'reinstateVendor', params: {vendorId: m[1]}})},
  {re: /^approve\s+vendor\s+(?:application\s+)?(\S+)$/i,
    build: m => ({kind: 'action', action: 'approveVendorApplication', params: {vendorId: m[1]}})},
  {re: /^reject\s+vendor\s+(?:application\s+)?(\S+)\s*(?:for|because|:)\s*(.+)$/i,
    build: m => ({kind: 'action', action: 'rejectVendorApplication', params: {vendorId: m[1], reason: m[2].trim()}})},
  {re: /^suspend\s+staff\s+(\S+)\s*(?:for|because|:)\s*(.+)$/i,
    build: m => ({kind: 'action', action: 'suspendStaff', params: {staffUid: m[1], reason: m[2].trim()}})},
  {re: /^reinstate\s+staff\s+(\S+)$/i,
    build: m => ({kind: 'action', action: 'reinstateStaff', params: {staffUid: m[1]}})},
  {re: /^approve\s+staff\s+(?:request\s+)?(\S+)$/i,
    build: m => ({kind: 'action', action: 'approveStaffRequest', params: {staffUid: m[1]}})},
  {re: /^reject\s+staff\s+(?:request\s+)?(\S+)\s*(?:for|because|:)\s*(.+)$/i,
    build: m => ({kind: 'action', action: 'rejectStaffRequest', params: {staffUid: m[1], reason: m[2].trim()}})},
  {re: /^(?:reorder|move)\s+section\s+(\S+)\s+to\s+(?:position\s+)?(\d+)$/i,
    build: m => ({kind: 'action', action: 'reorderSection', params: {layoutKey: m[1], order: Number(m[2])}})},
  {re: /^resize\s+section\s+(\S+)\s+to\s+(\d+)$/i,
    build: m => ({kind: 'action', action: 'resizeSection', params: {layoutKey: m[1], height: Number(m[2])}})},
  {re: /^merge\s+(?:pull request|pr)\s+#?(\d+)\s+in\s+(\S+)$/i,
    build: m => ({kind: 'action', action: 'mergeGithubPullRequest', params: {repo: m[2], prNumber: Number(m[1])}})},
  {re: /^set\s+(internal|alpha|beta|production)\s+track\s+rollout\s+to\s+(\d+)%?\s+(?:for|in)\s+(\S+)$/i,
    build: m => ({kind: 'action', action: 'setPlayConsoleTrackRollout', params: {track: m[1], userFraction: Number(m[2]) / 100, packageName: m[3]}})},
  {re: /^(?:what'?s|check)\s+the\s+(?:ci\s+|commit\s+)?status\s+(?:of|for)\s+(\S+)(?:\s+(?:at|on)\s+(\S+))?$/i,
    build: m => ({kind: 'readOnly', query: 'github.prStatus', params: {repo: m[1], ref: m[2] || 'HEAD'}})},
  {re: /^(?:list|show)\s+(?:open\s+)?(?:pull requests|prs)\s+(?:in|for)\s+(\S+)$/i,
    build: m => ({kind: 'readOnly', query: 'github.pullRequests', params: {repo: m[1], state: 'open'}})},
  {re: /^(?:list|show)\s+(?:recent\s+)?workflow\s+runs\s+(?:in|for)\s+(\S+)$/i,
    build: m => ({kind: 'readOnly', query: 'github.workflowRuns', params: {repo: m[1]}})},
  {re: /^(?:list|show)\s+(?:recent\s+)?releases\s+(?:in|for)\s+(\S+)$/i,
    build: m => ({kind: 'readOnly', query: 'github.releases', params: {repo: m[1]}})},
  {re: /^check\s+(internal|alpha|beta|production)\s+track\s+status\s+(?:for|in)\s+(\S+)$/i,
    build: m => ({kind: 'readOnly', query: 'playConsole.trackStatus', params: {track: m[1], packageName: m[2]}})},
  {re: /^check\s+hosting\s+status\s+(?:for|of)\s+(\S+)$/i,
    build: m => ({kind: 'readOnly', query: 'firebaseOps.hostingStatus', params: {siteId: m[1]}})},
];

function ruleBasedParse(text) {
  const trimmed = text.trim();
  for (const rule of RULES) {
    const match = trimmed.match(rule.re);
    if (match) return {...rule.build(match), confidence: 1};
  }
  return {kind: 'action', action: 'unknown', params: {}, confidence: 0};
}

// --- Pluggable LLM provider factory. 'none' is the default and makes no
// network call. Each concrete provider is a small, independent adapter behind
// its own secret; removing a provider file/branch here never affects the
// rule-based path above. ---
const anthropicKey = defineSecret('AI_AGENT_ANTHROPIC_API_KEY');
const openaiKey = defineSecret('AI_AGENT_OPENAI_API_KEY');

function actionsSummary() {
  return Object.entries(actions).map(([key, a]) => `${key} (tier: ${a.tier})`).join('; ');
}

function getProvider(name) {
  if (name === 'anthropic') {
    return {
      secrets: [anthropicKey],
      async interpret(text) {
        if (!anthropicKey.value()) return null;
        const res = await fetch('https://api.anthropic.com/v1/messages', {
          method: 'POST',
          headers: {'content-type': 'application/json', 'x-api-key': anthropicKey.value(), 'anthropic-version': '2023-06-01'},
          body: JSON.stringify({
            model: 'claude-3-haiku-20240307', max_tokens: 300,
            messages: [{role: 'user', content: `Map this admin command to one action from: ${actionsSummary()}. Reply ONLY JSON {"action":"...","params":{...}}. Command: ${text}`}],
          }),
        });
        const json = await res.json();
        return JSON.parse(json?.content?.[0]?.text || '{}');
      },
    };
  }
  if (name === 'openai') {
    return {
      secrets: [openaiKey],
      async interpret(text) {
        if (!openaiKey.value()) return null;
        const res = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {'content-type': 'application/json', authorization: `Bearer ${openaiKey.value()}`},
          body: JSON.stringify({
            model: 'gpt-4o-mini', response_format: {type: 'json_object'},
            messages: [{role: 'user', content: `Map this admin command to one action from: ${actionsSummary()}. Reply ONLY JSON {"action":"...","params":{...}}. Command: ${text}`}],
          }),
        });
        const json = await res.json();
        return JSON.parse(json?.choices?.[0]?.message?.content || '{}');
      },
    };
  }
  return null; // 'none' or anything unrecognized — no network call, ever.
}

exports.interpretAgentCommand = onCall({...options, secrets: [anthropicKey, openaiKey]}, async request => {
  const uid = await requireAdmin(request);
  await requireModuleEnabled('interpreter');
  const text = String(request.data?.text || '').slice(0, 1000);
  if (!text.trim()) throw new HttpsError('invalid-argument', 'Say or type a command.');

  let result = ruleBasedParse(text);
  if (result.confidence < CONFIDENCE_THRESHOLD) {
    const config = await getConfigData();
    const provider = getProvider(config.llmProvider);
    if (provider) {
      try {
        const llmResult = await provider.interpret(text);
        // The LLM is only ever asked to pick a writable action (actionsSummary()
        // below lists actions, not queries) — it is never offered a shortcut
        // around the propose/confirm pipeline for a write.
        if (llmResult?.action) result = {kind: 'action', action: llmResult.action, params: llmResult.params || {}, confidence: 0.8};
      } catch {
        // Swallow — keep the rule-based (possibly 'unknown') result rather than fail the whole command.
      }
    }
  }
  // Re-validate against the real whitelist/query-list regardless of source
  // (rule-based or LLM) before ever returning it.
  if (result.kind === 'readOnly') {
    if (!queries[result.query]) result = {kind: 'action', action: 'unknown', params: {}, confidence: 0};
  } else if (!actions[result.action]) {
    result = {kind: 'action', action: 'unknown', params: {}, confidence: 0};
  }

  await writeAuditLog({uid, type: 'interpret', action: result.action || result.query, detail: text});
  return result;
});
