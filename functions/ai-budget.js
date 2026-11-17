'use strict';
// The AI money limit (owner, free-limit plan 17 Nov 2026): Anthropic is the only paid service, at most ₹90 a month in code (the owner
// also sets $1.10 a month in the Anthropic console as the outer wall). Every AI call's real cost (its token counts × the model's price)
// is added up per month and per day; when the month reaches ₹90, or the day its share (₹3), every AI feature stops until the next
// month / day: loadAiKey() then answers "no key", and each feature falls back exactly as when no key is set (Flash makes a ticket,
// photo search asks for words, the AI Support box sends the question to the team…).
//
//   aiSpend/<YYYY-MM>     {inr, calls, inputTokens, outputTokens, month}   this month (India time), functions only, the admin reads it
//   aiSpend/<YYYY-MM-DD>  {inr, calls, day}                                 today
//   settings/agent        {aiMonthlyInr (≤ 90), aiDailyInr (≤ 10), usdToInr}  the admin may only lower the limits
//
// Prices in US dollars per million tokens (Claude Haiku 5.5 up to 100K-token prompts; Claude Sonnet 5.5). An unknown model is priced
// as the dearest one, so the limit is never under-counted.
const {FieldValue} = require('firebase-admin/firestore');

const PRICES = {
  'claude-haiku-5-5': {input: 0.10, output: 0.50},
  'claude-sonnet-5-5': {input: 2, output: 10},
};
const DEAREST = {input: 2, output: 10};
const MONTH_MAX_INR = 90;
const DAY_DEFAULT_INR = 3;
const USD_TO_INR = 88;
const IST = 19800000;

const monthKey = (now = Date.now()) => new Date(now + IST).toISOString().slice(0, 7);
const dayKey = (now = Date.now()) => new Date(now + IST).toISOString().slice(0, 10);

/// The admin's limits, always inside the owner's: at most ₹90 a month and ₹10 a day.
function limitsOf(agent = {}) {
  const num = (v, def, max) => {
    const n = Number(v);
    return Number.isFinite(n) && n >= 0 && n <= max ? n : def;
  };
  return {
    monthInr: num(agent.aiMonthlyInr, MONTH_MAX_INR, MONTH_MAX_INR),
    dayInr: num(agent.aiDailyInr, DAY_DEFAULT_INR, 10),
    usdToInr: num(agent.usdToInr, USD_TO_INR, 200) || USD_TO_INR,
  };
}

/// The cost of one call in rupees, from the tokens the API reported (cache writes count as input; cache reads at a tenth).
function costInr(model, usage = {}, usdToInr = USD_TO_INR) {
  const p = PRICES[String(model || '')] || DEAREST;
  const input = (usage.input_tokens || 0) + (usage.cache_creation_input_tokens || 0) * 1.25 + (usage.cache_read_input_tokens || 0) * 0.1;
  const usd = (input * p.input + (usage.output_tokens || 0) * p.output) / 1e6;
  return Math.round(usd * usdToInr * 10000) / 10000;
}

/// Adds one call to this month and today. Never throws (a call that happened is never undone).
async function recordSpend(db, model, usage, now = Date.now()) {
  try {
    const agent = (await db.collection('settings').doc('agent').get()).data() || {};
    const inr = costInr(model, usage, limitsOf(agent).usdToInr);
    const batch = db.batch();
    batch.set(db.collection('aiSpend').doc(monthKey(now)), {
      month: monthKey(now), inr: FieldValue.increment(inr), calls: FieldValue.increment(1),
      inputTokens: FieldValue.increment(usage?.input_tokens || 0), outputTokens: FieldValue.increment(usage?.output_tokens || 0),
    }, {merge: true});
    batch.set(db.collection('aiSpend').doc(dayKey(now)), {day: dayKey(now), inr: FieldValue.increment(inr), calls: FieldValue.increment(1)}, {merge: true});
    await batch.commit();
    return inr;
  } catch (error) {
    console.warn('AI spend not recorded', error.message);
    return 0;
  }
}

/// True while this month and today are under their limits. If the spend cannot be read, AI stays off (never over the limit).
async function budgetOk(db, now = Date.now()) {
  try {
    const [agent, month, day] = await db.getAll(
      db.collection('settings').doc('agent'),
      db.collection('aiSpend').doc(monthKey(now)),
      db.collection('aiSpend').doc(dayKey(now)),
    );
    const l = limitsOf(agent.data() || {});
    return (month.data()?.inr || 0) < l.monthInr && (day.data()?.inr || 0) < l.dayInr;
  } catch (error) {
    console.warn('AI budget not read: AI stays off', error.message);
    return false;
  }
}

module.exports = {PRICES, MONTH_MAX_INR, DAY_DEFAULT_INR, limitsOf, costInr, recordSpend, budgetOk, monthKey, dayKey};
