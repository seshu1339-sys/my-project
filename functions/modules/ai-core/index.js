'use strict';
// ai-core: the one shared library of the AI features, not a feature itself. It has no Cloud Functions of its own and is never loaded by
// functions/index.js. It owns three things only: the Anthropic connection, the log of every AI call, and the daily allowance.
//
//   aiCallLog/<id>         {feature, model, inputTokens, outputTokens, uid, stopReason, at}; only the admin reads it
//   aiDailyUse/<key>_<day> {count, day}; only functions touch it
//
// The API key: the one the admin sets in Settings > AI provider & usage (functions/ai-key.js, a server-only document), else the
// ANTHROPIC_API_KEY secret, which Firebase hands to a function as an environment variable. It is never in an app.
const {defineSecret} = require('firebase-functions/params');
const {Timestamp} = require('firebase-admin/firestore');

const anthropicKey = defineSecret('ANTHROPIC_API_KEY');
// The model names live in functions/ai-models.js (one place for every AI feature).
const {AI_MODELS, SONNET, HAIKU, keyIsSet} = require('../../ai-models');
const {currentAiKey, loadAiKey} = require('../../ai-key');
const {recordSpend} = require('../../ai-budget');
const IST = 19800000;

let client, clientKey = '';
/// The Anthropic client. Loaded on first use, so starting the other functions stays fast. Call loadAiKey(db) first in a function (it
/// reads the admin's key, cached); a new key makes a new client.
/// Until the owner sets the real key, it throws before any call, so nothing reaches Anthropic; every AI feature then falls back (Flash
/// makes a ticket, the assistant says it is not set up).
function anthropic() {
  const key = currentAiKey();
  if (!keyIsSet(key)) throw Object.assign(Error('The Anthropic key is not set up yet.'), {name: 'AiKeyMissing'});
  if (!client || clientKey !== key) {
    const Anthropic = require('@anthropic-ai/sdk').default;
    client = new Anthropic({apiKey: key});
    clientKey = key;
  }
  return client;
}

/// Records one AI call, and its cost against the month's AI money limit (functions/ai-budget.js). A failed log never fails the caller.
async function logAiCall(db, {feature, model, usage, uid = '', stopReason = ''}, now = Date.now()) {
  await recordSpend(db, model, usage, now);
  try {
    await db.collection('aiCallLog').add({
      feature, model, uid, stopReason,
      inputTokens: usage?.input_tokens ?? 0, outputTokens: usage?.output_tokens ?? 0, at: Timestamp.fromMillis(now),
    });
  } catch (error) { console.warn('AI call not logged', feature, error.message); }
}

/// Takes one use of today's allowance (the Indian day). False when [limit] is already used.
async function takeDailyUse(db, key, limit, now = Date.now()) {
  const day = new Date(now + IST).toISOString().slice(0, 10);
  const ref = db.collection('aiDailyUse').doc(`${key}_${day}`);
  return db.runTransaction(async tx => {
    const count = (await tx.get(ref)).data()?.count ?? 0;
    if (count >= limit) return false;
    tx.set(ref, {key, day, count: count + 1});
    return true;
  });
}

module.exports = {anthropicKey, anthropic, loadAiKey, logAiCall, takeDailyUse, SONNET, HAIKU, AI_MODELS, keyIsSet};
