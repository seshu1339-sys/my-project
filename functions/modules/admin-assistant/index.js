'use strict';
// Admin AI assistant module (owner, 13 Nov 2026): the admin asks in plain words ("how many vendors are waiting?", "how many offers run
// today?") and Claude Sonnet 5.5 (the admin model, functions/ai-models.js) answers from today's counts. Read-only: it counts documents
// and changes nothing. Requires no other feature module, only the shared ai-core.
//
//   askAdminAssistant  admin -> {question} -> {answer, facts}
//   askAdminSearch     admin -> {query, index} -> {answer, serials}   the admin panel search's "Ask AI" (Haiku 5.5)
//
// Each admin has a daily allowance (settings/business.adminAiPerDay, 50 when not set). Past it, or before the Anthropic key is set,
// it says so and Anthropic is not called. Counting uses Firestore count() queries (one read per 1000 documents), never a full read.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {requireRole, isAdminToken} = require('../../role-auth');
const {requireAdminSession} = require('../../admin-session');
const {anthropic, anthropicKey, logAiCall, takeDailyUse, AI_MODELS, keyIsSet} = require('../ai-core');

const options = {region: 'us-central1', maxInstances: 3, invoker: 'public', secrets: [anthropicKey], timeoutSeconds: 120};
const DEFAULT_ADMIN_AI_PER_DAY = 50;
const MAX_QUESTION = 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

const SYSTEM = "You are the assistant of the administrator of LOCAMARKET, a local marketplace in India (customer website and app, " +
  "vendor app, staff app). Answer the administrator's question from FACTS only: today's counts from the database. Give exact numbers " +
  "and say which fact each comes from. If FACTS do not hold the answer, say what is missing and where in the admin panel to look. " +
  'Answer in the language of the question (Telugu or English), in at most eight short sentences or a short list. Never invent numbers.';

/// The admin's daily questions (1 to 500), 50 when not set.
function adminAiLimit(business) {
  const n = Math.round(Number(business?.adminAiPerDay));
  return Number.isFinite(n) && n >= 1 && n <= 500 ? n : DEFAULT_ADMIN_AI_PER_DAY;
}

/// Today's counts. A count that fails (a missing collection, a missing index) is null, never a failed answer.
async function adminFacts(db, now = Date.now()) {
  const count = async query => {
    try { return (await query.count().get()).data().count; } catch { return null; }
  };
  const c = name => db.collection(name);
  const nowTs = Timestamp.fromMillis(now), nowIso = new Date(now).toISOString();
  const weekAgo = Timestamp.fromMillis(now - 7 * DAY_MS);
  const [vendorsApproved, vendorsPending, shops, products, services, staff, premiumActive, offersLive, todaysOffersLive, vendorAds,
    pricesLive, ticketsOpen, paymentsWaiting, paymentsVerified, ordersWeek] = await Promise.all([
    count(c('vendors').where('status', '==', 'approved')), count(c('vendors').where('status', '==', 'pending')),
    count(c('shops')), count(c('products')), count(c('services')), count(c('fieldAssistants')),
    count(c('vendorPremium').where('active', '==', true)),
    count(c('vendorOffers').where('status', '==', 'live')), count(c('vendorTodaysOffers').where('endsAt', '>', nowTs)),
    count(c('ads').where('source', '==', 'vendor')), count(c('products').where('priceExpiresAt', '>', nowIso)),
    count(c('flashTickets').where('status', '==', 'open')),
    count(c('paymentRequests').where('status', '==', 'awaiting_payment')), count(c('paymentRequests').where('status', '==', 'verified')),
    count(c('orders').where('createdAt', '>', weekAgo)),
  ]);
  return {
    asOf: nowIso,
    vendors: {approved: vendorsApproved, waitingForApproval: vendorsPending},
    shops, products, services, staff,
    paidPlansRunning: premiumActive,
    posts: {vendorOffersLive: offersLive, todaysOffersRunning: todaysOffersLive, vendorAdsAllTime: vendorAds, vendorPricesStillValid: pricesLive},
    supportTicketsOpen: ticketsOpen,
    payments: {waitingToBePaid: paymentsWaiting, confirmed: paymentsVerified},
    ordersLast7Days: ordersWeek,
  };
}

async function requireAdmin(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  requireRole(request);
  if (!isAdminToken(request.auth.token)) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
  return request.auth.uid;
}

/// One answer. [client] makes the Anthropic client (ai-core's anthropic, a fake in the tests).
async function answerQuestion(db, client, uid, question, now = Date.now()) {
  const text = String(question ?? '').trim();
  if (!text) throw new HttpsError('invalid-argument', 'Type or say a question.');
  if (text.length > MAX_QUESTION) throw new HttpsError('invalid-argument', `Ask in at most ${MAX_QUESTION} letters.`);
  const limit = adminAiLimit((await db.collection('settings').doc('business').get()).data());
  if (!(await takeDailyUse(db, `admin_ai_${uid}`, limit, now))) {
    throw new HttpsError('resource-exhausted', `You have used today's ${limit} questions. Please try again tomorrow.`);
  }
  const facts = await adminFacts(db, now);
  let response;
  try {
    // Thinking stays adaptive at low effort; on a policy decline the API re-runs the request on its default fallback model.
    response = await client().beta.messages.create({
      model: AI_MODELS.admin, max_tokens: 4000,
      betas: ['server-side-fallback-2026-07-01'], fallbacks: 'default',
      output_config: {effort: 'low'},
      system: SYSTEM,
      messages: [{role: 'user', content: `<facts>\n${JSON.stringify(facts, null, 1)}\n</facts>\n\n${text}`}],
    });
  } catch (error) {
    console.warn('Admin assistant could not answer', error.status ?? error.name);
    throw new HttpsError('unavailable', error.name === 'AiKeyMissing' ? 'The AI assistant is not set up yet.' : 'The AI assistant is busy. Try again.');
  }
  await logAiCall(db, {feature: 'admin_assistant', model: response.model ?? AI_MODELS.admin, usage: response.usage, uid, stopReason: response.stop_reason}, now);
  if (response.stop_reason === 'refusal') return {answer: 'The assistant cannot answer this question. Please ask it another way.', facts};
  const answer = response.content.filter(block => block.type === 'text').map(block => block.text).join('\n').trim();
  return {answer: answer || 'No answer this time. Please ask again.', facts};
}

exports.askAdminAssistant = onCall(options, async request => {
  const uid = await requireAdmin(request);
  if (!keyIsSet(process.env.ANTHROPIC_API_KEY)) throw new HttpsError('failed-precondition', 'The AI assistant is not set up yet.');
  return answerQuestion(getFirestore(), anthropic, uid, request.data?.question);
});

// ---- The admin panel search's "Ask AI" (owner, 13 Nov 2026) ----
// The normal search (in the app, free) runs first; only when it finds nothing does the admin press "Ask AI". Claude Haiku 5.5 (the
// chat model, functions/ai-models.js) gets the list of every setting the panel has (sent by the panel, made from its own registries,
// so a new setting is in it by itself) with the current values, plus values only the server reads (staff targets, pay slabs, the
// Support Team chat limit), and answers which setting it is, its current value, and the serial to open it. Its own daily allowance
// (settings/business.adminSearchAiPerDay, 100 when not set); past it the normal search still works.
const DEFAULT_SEARCH_AI_PER_DAY = 100;
const MAX_INDEX = 1500;
const SEARCH_SYSTEM = 'You help the administrator of LOCAMARKET find a setting in the admin panel. SETTINGS lists every page and setting: ' +
  '"serial | group > section > name | key | current value". VALUES holds more current values (staff targets, pay slabs, limits). ' +
  'From the administrator\'s words (Telugu or English, everyday words), choose the 1 to 3 settings that match best and give their serials, ' +
  'best first. In "answer", say in the administrator\'s language, in one or two short sentences, which setting it is, where it is, ' +
  'and its current value when one is known (say "not set" when it is empty, and the default when SETTINGS gives one). ' +
  'Use only SETTINGS and VALUES; never invent a setting, a serial or a value. If nothing matches, give no serials and say so.';
const SEARCH_FORMAT = {
  type: 'json_schema',
  schema: {
    type: 'object',
    properties: {answer: {type: 'string'}, serials: {type: 'array', items: {type: 'string'}}},
    required: ['answer', 'serials'],
    additionalProperties: false,
  },
};

function searchAiLimit(business) {
  const n = Math.round(Number(business?.adminSearchAiPerDay));
  return Number.isFinite(n) && n >= 1 && n <= 1000 ? n : DEFAULT_SEARCH_AI_PER_DAY;
}

/// The panel's list, checked: [{serial, label, key, value}] -> one line each.
function indexLines(index) {
  if (!Array.isArray(index) || !index.length) throw new HttpsError('invalid-argument', 'The list of settings is missing.');
  return index.slice(0, MAX_INDEX).map(item => [item?.serial, item?.label, item?.key, item?.value]
    .map(v => String(v ?? '').replace(/\s+/g, ' ').trim().slice(0, 200)).join(' | ')).join('\n');
}

/// Values only the server reads: the pay config, each staff member's own targets, the Support Team chat's daily limit.
async function serverValues(db) {
  const [pay, own, staff, flash] = await Promise.all([
    db.collection('staffPayConfig').doc('main').get(), db.collection('staffPayTargets').get(), db.collection('fieldStaff').get(),
    db.collection('flashConfig').doc('main').get(),
  ]);
  const codes = Object.fromEntries(staff.docs.map(d => [d.id, d.data().staffCode || d.id]));
  const payData = pay.data() || {};
  return {
    staffPay: {dailyTarget: payData.dailyTarget ?? 50, monthlyTarget: payData.monthlyTarget ?? 'daily target x days of the month', slabs: payData.slabs || []},
    staffOwnTargets: Object.fromEntries(own.docs.map(d => [codes[d.id] || d.id, {dailyTarget: d.data().dailyTarget ?? 'same as everyone', monthlyTarget: d.data().monthlyTarget ?? 'same as everyone', slabs: d.data().slabs ?? 'same as everyone'}])),
    supportChatMessagesPerDay: flash.data()?.dailyMessages ?? 30,
  };
}

async function searchWithAi(db, client, uid, data = {}, now = Date.now()) {
  const query = String(data.query ?? '').trim();
  if (!query) throw new HttpsError('invalid-argument', 'Type or say what you are looking for.');
  if (query.length > 300) throw new HttpsError('invalid-argument', 'Ask in at most 300 letters.');
  const lines = indexLines(data.index);
  const limit = searchAiLimit((await db.collection('settings').doc('business').get()).data());
  if (!(await takeDailyUse(db, `admin_search_${uid}`, limit, now))) {
    throw new HttpsError('resource-exhausted', `You have used today's ${limit} AI searches. Please try again tomorrow; the normal search still works.`);
  }
  const values = await serverValues(db);
  let response;
  try {
    response = await client().messages.create({
      model: AI_MODELS.chat, max_tokens: 600,
      thinking: {type: 'disabled'},
      output_config: {effort: 'low', format: SEARCH_FORMAT},
      system: SEARCH_SYSTEM,
      messages: [{role: 'user', content: `<settings>\n${lines}\n</settings>\n<values>\n${JSON.stringify(values)}\n</values>\n\n${query}`}],
    });
  } catch (error) {
    console.warn('Admin search AI could not answer', error.status ?? error.name);
    throw new HttpsError('unavailable', error.name === 'AiKeyMissing' ? 'The AI search is not set up yet.' : 'The AI search is busy. Try again.');
  }
  await logAiCall(db, {feature: 'admin_search', model: AI_MODELS.chat, usage: response.usage, uid, stopReason: response.stop_reason}, now);
  let parsed = {answer: '', serials: []};
  try { parsed = JSON.parse(response.content.find(b => b.type === 'text')?.text || '{}'); } catch { /* answered as nothing found */ }
  const known = new Set(data.index.map(item => String(item?.serial ?? '')));
  const serials = (Array.isArray(parsed.serials) ? parsed.serials : []).map(String).filter(sr => known.has(sr)).slice(0, 3);
  return {answer: String(parsed.answer ?? '').trim() || 'No matching setting was found.', serials};
}

exports.askAdminSearch = onCall({...options, timeoutSeconds: 60}, async request => {
  const uid = await requireAdmin(request);
  if (!keyIsSet(process.env.ANTHROPIC_API_KEY)) throw new HttpsError('failed-precondition', 'The AI search is not set up yet.');
  return searchWithAi(getFirestore(), anthropic, uid, request.data || {});
});

exports._test = {adminFacts, answerQuestion, adminAiLimit, SYSTEM, DEFAULT_ADMIN_AI_PER_DAY, searchWithAi, searchAiLimit, indexLines, DEFAULT_SEARCH_AI_PER_DAY};
