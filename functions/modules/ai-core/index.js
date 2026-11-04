'use strict';
// ai-core: the one shared library of the AI features, not a feature itself. It has no Cloud Functions of its own and is never loaded by
// functions/index.js. It owns three things only: the Anthropic connection, the log of every AI call, and the daily allowance.
//
//   aiCallLog/<id>         {feature, model, inputTokens, outputTokens, uid, stopReason, at}; only the admin reads it
//   aiDailyUse/<key>_<day> {count, day}; only functions touch it
//
// The API key lives in the ANTHROPIC_API_KEY secret, which Firebase hands to a function as an environment variable. It is never in an app.
const {defineSecret} = require('firebase-functions/params');
const {Timestamp} = require('firebase-admin/firestore');

const anthropicKey = defineSecret('ANTHROPIC_API_KEY');
const SONNET = 'claude-sonnet-5-5';
const HAIKU = 'claude-haiku-5-5';
const IST = 19800000;

let client;
/// The Anthropic client. Loaded on first use, so starting the other functions stays fast.
function anthropic() {
  if (!client) {
    const Anthropic = require('@anthropic-ai/sdk').default;
    client = new Anthropic({apiKey: process.env.ANTHROPIC_API_KEY});
  }
  return client;
}

/// Records one AI call. A failed log never fails the caller.
async function logAiCall(db, {feature, model, usage, uid = '', stopReason = ''}, now = Date.now()) {
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

module.exports = {anthropicKey, anthropic, logAiCall, takeDailyUse, SONNET, HAIKU};
