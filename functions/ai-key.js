'use strict';
// The AI key the owner sets from admin Settings > AI provider & usage (owner, 17 Nov 2026: a server-only Firestore document, no Secret
// Manager versions). Only Cloud Functions read it: firestore.rules deny every app on _private/*. The ANTHROPIC_API_KEY secret (a
// placeholder now) stays as the fallback, so nothing changes for a function until a key is set either way.
//
//   _private/aiKey  {provider: 'anthropic', key, last4, setAt, setBy}
//
// loadAiKey(db) reads it at most once every CACHE_MS per server instance (one Firestore read), then currentAiKey() gives it at once.
const {keyIsSet} = require('./ai-models');
const {budgetOk} = require('./ai-budget');

const CACHE_MS = 5 * 60 * 1000;
const PROVIDERS = ['anthropic'];
let cached = {key: '', provider: 'anthropic', at: -Infinity};
// The AI money limit was reached at the last loadAiKey (functions/ai-budget.js): no key until it is under the limit again.
let overBudget = false;

/// The key to call the AI with now: the admin's key when set, else the secret, else ''. '' too when this month's or today's AI money
/// limit is used up.
function currentAiKey() {
  if (overBudget) return '';
  if (keyIsSet(cached.key)) return cached.key;
  const secret = process.env.ANTHROPIC_API_KEY;
  return keyIsSet(secret) ? secret.trim() : '';
}

/// Reads the admin's key (cached) and checks the AI money limit (every call: it must never be passed). Returns the key that will be
/// used ('' = AI is off). Never throws.
async function loadAiKey(db, now = Date.now(), {budget = budgetOk} = {}) {
  overBudget = !(await budget(db, now));
  if (now - cached.at > CACHE_MS) {
    try {
      const data = (await db.collection('_private').doc('aiKey').get()).data() || {};
      cached = {key: typeof data.key === 'string' ? data.key.trim() : '', provider: PROVIDERS.includes(data.provider) ? data.provider : 'anthropic', at: now};
    } catch (error) {
      console.warn('AI key not read', error.message);
      cached = {...cached, at: now};
    }
  }
  return currentAiKey();
}

/// Forgets the cached key (after the admin saves a new one on this instance, and in the tests).
function resetAiKeyCache() { cached = {key: '', provider: 'anthropic', at: -Infinity}; overBudget = false; }

module.exports = {currentAiKey, loadAiKey, resetAiKeyCache, PROVIDERS};
