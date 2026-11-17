'use strict';
// AI Support module (owner spec "AI Agent + Health System" part 3, 17 Nov 2026): the "AI Support" box in the Vendor, Staff and User
// apps, the website and the admin panel sends what the person met to the LocaMarket team; the admin answers in the admin panel and the
// answer shows in the person's app (and as a push when they are signed in). Known problems use pre-written steps in the app (free);
// Claude Haiku answers only unknown problems and typed questions, only when the admin turned it on, and only up to the daily number.
//
//   openSupportTicket    anyone -> {app, platform, deviceId, version, device, problemId, problemKind, cause, side, message, screen,
//                                   option, text, screenshot?, lang, auto, ticketId?} -> {id, status}    ticketId: "Tell us more" for it
//   mySupportTickets     anyone -> {deviceId} -> {tickets: [{id, status, message, text, reply, at, replyAt}]}   their own (account or device)
//   answerSupportTicket  admin  -> {id, status: 'seen' | 'solved', reply?} -> {ok}       the reply shows in the app; push when signed in
//   askSupport           anyone -> {question, lang, context: {kind, cause, message, screen, app}} -> {text, off?, limit?}
//   solveSupportTickets  trigger on solvedProblems/<id> {problemId, by, at, how} (written when the admin marks a problem solved or a fix goes live):
//                        every open ticket of that problem -> solved, and each person gets "Your problem is solved" in their language
//
//   supportTickets/<id>  {uid, deviceKey, app, platform, version, device, problemId, problemKind, cause, side, message, screen, option,
//                         text, lang, auto, status: sent | seen | solved, reply, at, updatedAt, replyAt, userCode, phone, shot}
//   supportShots/<id>    {data (JPEG, base64), ticketId, at, expiresAt}    the person's screenshot (deleted when solved / after 30 days)
//
// Cost guards: 5 tickets and 10 AI answers a device a day; AI answers for everyone together at most settings/support.aiDailyLimit a day
// (default 50); texts are cut short; emails, links and long numbers are taken out; a screenshot is at most 300 KB.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {getFirestore, Timestamp, FieldValue} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {createHash} = require('node:crypto');
const {requireRole, isAdminToken} = require('../../role-auth');
const {requireAdminSession} = require('../../admin-session');
const {task} = require('../../task');
const {anthropic, anthropicKey, loadAiKey, logAiCall, takeDailyUse, AI_MODELS} = require('../ai-core');

const APPS = ['customer', 'vendor', 'staff', 'admin'];
const SIDES = ['user', 'device', 'our'];
const STATUSES = ['sent', 'seen', 'solved'];
const TICKETS_PER_DAY = 5;
const AI_PER_DEVICE = 10;
const MAX_SHOT = 300 * 1024;
const SHOT_DAYS = 30;
const options = {region: 'us-central1', maxInstances: 3, invoker: 'public'};
const IST = 19800000;

const dayKey = (now = Date.now()) => new Date(now + IST).toISOString().slice(0, 10);
const hash = v => createHash('sha256').update(String(v)).digest('hex');
const clip = (v, max) => String(v ?? '').trim().replace(/\s+/g, ' ').slice(0, max);
const clean = (v, max) => clip(v, 3000).replace(/\S+@\S+/g, '<email>').replace(/https?:\/\/\S+/g, '<link>').replace(/\d{6,}/g, '<number>').slice(0, max);
const langOf = v => (/^[a-z]{2,3}$/.test(String(v || '')) ? String(v) : 'en');
const deviceKeyOf = deviceId => hash(clip(deviceId, 100) || 'unknown').slice(0, 24);
/// The id of the problem a ticket is about: the same formula as functions/modules/app-problems problemId (kept in step by a test), so
/// "solved" reaches the tickets of that problem. '' when the box was opened without a problem (a typed question).
const problemIdOf = (app, platform, kind, message) => (kind && message ? `${app}~${platform}~${kind}~${hash(`${app}|${kind}|${message}`).slice(0, 16)}` : '');

/// "Your problem is solved" and the other words the person reads, in their language (the rest falls back to English).
const WORDS = {
  solved: {en: 'Your problem is solved. Thank you for telling us.', te: 'మీ సమస్య పరిష్కరించబడింది. మాకు తెలియజేసినందుకు ధన్యవాదాలు.', hi: 'आपकी समस्या हल हो गई है। हमें बताने के लिए धन्यवाद।'},
  reply: {en: 'LocaMarket team replied to your problem', te: 'మీ సమస్యకు LocaMarket టీమ్ సమాధానం ఇచ్చింది', hi: 'LocaMarket टीम ने आपकी समस्या का जवाब दिया'},
  title: {en: 'LocaMarket support', te: 'LocaMarket సహాయం', hi: 'LocaMarket सहायता'},
};
const word = (key, lang) => WORDS[key][lang] || WORDS[key].en;

async function requireAdmin(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  requireRole(request);
  if (!isAdminToken(request.auth.token)) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
  return request.auth.uid;
}

/// Takes one of the device's daily [field] allowance; false when used up.
async function takeDevice(db, deviceKey, field, cap, now) {
  const ref = db.collection('supportDevices').doc(`${deviceKey}~${dayKey(now)}`);
  return db.runTransaction(async tx => {
    const used = (await tx.get(ref)).data()?.[field] ?? 0;
    if (used >= cap) return false;
    tx.set(ref, {[field]: used + 1, day: dayKey(now), expiresAt: Timestamp.fromMillis(now + 3 * 86400000)}, {merge: true});
    return true;
  });
}

/// The person's Vendor / Staff ID and phone for the admin ('' when not known).
async function contactOf(db, auth) {
  if (!auth?.uid) return {code: '', phone: ''};
  const role = auth.token?.role;
  const phone = d => clip(d?.phone || d?.mobile || d?.whatsapp || '', 20);
  try {
    if (role === 'vendor') {
      const d = (await db.collection('vendors').doc(auth.uid).get()).data();
      return {code: String(d?.vendorCode || ''), phone: phone(d)};
    }
    if (role === 'staff') {
      const d = (await db.collection('fieldStaff').doc(auth.uid).get()).data();
      return {code: String(d?.staffCode || d?.code || ''), phone: phone(d)};
    }
    return {code: '', phone: phone((await db.collection('users').doc(auth.uid).get()).data())};
  } catch {
    return {code: '', phone: ''};
  }
}

function shotOf(base64) {
  if (!base64) return null;
  if (typeof base64 !== 'string' || base64.length > Math.ceil(MAX_SHOT * 4 / 3) + 8) throw new HttpsError('invalid-argument', 'The screenshot must be under 300 KB.');
  const head = Buffer.from(base64.slice(0, 8), 'base64');
  if (!(head[0] === 0xff && head[1] === 0xd8) && !(head[0] === 0x89 && head[1] === 0x50)) throw new HttpsError('invalid-argument', 'The screenshot must be a JPEG or PNG.');
  return base64;
}

/// Saves one ticket (the tests call it with a fake request).
async function openTicket(db, request, now = Date.now()) {
  const d = request.data || {};
  const app = APPS.includes(d.app) ? d.app : null;
  if (!app) throw new HttpsError('invalid-argument', `app must be one of ${APPS.join(', ')}`);
  const text = clean(d.text, 1000);
  const message = clean(d.message, 300);
  if (!text && !message) throw new HttpsError('invalid-argument', 'Write what went wrong.');
  const shot = shotOf(d.screenshot);
  const deviceKey = deviceKeyOf(d.deviceId || request.rawRequest?.ip);
  // "Tell us more" for a report the box already sent: added to it (only from the same device).
  if (d.ticketId) {
    const ref = db.collection('supportTickets').doc(clip(d.ticketId, 60));
    const t = (await ref.get()).data();
    if (!t || t.deviceKey !== deviceKey) throw new HttpsError('not-found', 'This problem report is not there any more.');
    if (!(await takeDevice(db, deviceKey, 'adds', 20, now))) throw new HttpsError('resource-exhausted', 'Thank you — our team has your messages.');
    const at = Timestamp.fromMillis(now);
    await ref.update({text: [t.text, text].filter(Boolean).join(' / ').slice(0, 3000), updatedAt: at, ...(shot ? {shot: true} : {}), ...(t.status === 'solved' ? {status: 'sent'} : {})});
    if (shot) await db.collection('supportShots').doc(ref.id).set({data: shot, ticketId: ref.id, at, expiresAt: Timestamp.fromMillis(now + SHOT_DAYS * 86400000)});
    return {id: ref.id, status: t.status === 'solved' ? 'sent' : t.status};
  }
  if (!(await takeDevice(db, deviceKey, 'tickets', TICKETS_PER_DAY, now))) {
    throw new HttpsError('resource-exhausted', `You have sent ${TICKETS_PER_DAY} problems today. Thank you — our team is looking at them.`);
  }
  const {code, phone} = await contactOf(db, request.auth);
  const platform = d.platform === 'android' ? 'android' : 'web';
  const problemKind = clip(d.problemKind, 20);
  const ref = db.collection('supportTickets').doc();
  const at = Timestamp.fromMillis(now);
  const batch = db.batch();
  batch.set(ref, {
    uid: request.auth?.uid || '', role: String(request.auth?.token?.role || ''), deviceKey, app, platform,
    version: clip(d.version, 30), device: clean(d.device, 80), problemId: clip(d.problemId, 120) || problemIdOf(app, platform, problemKind, message), problemKind,
    cause: clip(d.cause, 40).replace(/[^a-z_]/g, ''), side: SIDES.includes(d.side) ? d.side : 'our', message, screen: clip(d.screen, 60),
    option: clean(d.option, 80), text, lang: langOf(d.lang), auto: d.auto === true, status: 'sent', reply: '', userCode: code, phone,
    shot: !!shot, at, updatedAt: at,
  });
  if (shot) batch.set(db.collection('supportShots').doc(ref.id), {data: shot, ticketId: ref.id, at, expiresAt: Timestamp.fromMillis(now + SHOT_DAYS * 86400000)});
  await batch.commit();
  return {id: ref.id, status: 'sent'};
}

/// The person's own tickets: their account's, or (not signed in) their device's. Newest first, at most 20.
async function myTickets(db, request) {
  const deviceKey = deviceKeyOf(request.data?.deviceId || request.rawRequest?.ip);
  const queries = [db.collection('supportTickets').where('deviceKey', '==', deviceKey).limit(40).get()];
  if (request.auth?.uid) queries.push(db.collection('supportTickets').where('uid', '==', request.auth.uid).limit(40).get());
  const seen = new Map();
  for (const q of await Promise.all(queries)) for (const doc of q.docs) seen.set(doc.id, doc);
  const ms = t => t?.toMillis?.() ?? 0;
  return {
    tickets: [...seen.values()].map(doc => ({id: doc.id, ...doc.data()})).sort((a, b) => ms(b.at) - ms(a.at)).slice(0, 20).map(t => ({
      id: t.id, status: t.status, message: t.message, text: t.text, reply: t.reply || '', at: ms(t.at), replyAt: ms(t.replyAt), side: t.side,
    })),
  };
}

/// A push to the person's phones / browsers when they are signed in (users/<uid>/pushTokens). Never throws.
async function pushPerson(db, uid, title, body, {send = m => getMessaging().sendEachForMulticast(m)} = {}) {
  if (!uid) return 0;
  try {
    const tokens = (await db.collection('users').doc(uid).collection('pushTokens').limit(10).get()).docs.map(d => d.id);
    if (!tokens.length) return 0;
    const r = await send({tokens, notification: {title, body}, data: {type: 'support_reply'}});
    return r?.successCount ?? 0;
  } catch (e) {
    console.warn('Support push failed', e?.message || e);
    return 0;
  }
}

/// The admin's answer: seen / solved and a reply the person reads in their app.
async function answer(db, uid, data, now = Date.now(), {send} = {}) {
  const id = clip(data?.id, 60);
  const status = STATUSES.includes(data?.status) ? data.status : null;
  if (!id || !status || status === 'sent') throw new HttpsError('invalid-argument', 'Give the ticket id and the status seen or solved.');
  const reply = clip(data?.reply, 1500);
  const ref = db.collection('supportTickets').doc(id);
  const t = (await ref.get()).data();
  if (!t) throw new HttpsError('not-found', 'This problem report is not there any more.');
  const at = Timestamp.fromMillis(now);
  await ref.update({status, updatedAt: at, ...(reply ? {reply, replyAt: at, replyBy: uid} : {}), ...(status === 'solved' ? {solvedAt: at} : {})});
  if (status === 'solved') await db.collection('supportShots').doc(id).delete().catch(() => {});
  await db.collection('agentLog').add({uid, email: '', action: `support_${status}`, command: '', target: id, platform: t.app, details: {reply: reply.slice(0, 200)}, at: FieldValue.serverTimestamp()});
  const lang = t.lang || 'en';
  if (status === 'solved') await pushPerson(db, t.uid, word('title', lang), reply || word('solved', lang), {send});
  else if (reply) await pushPerson(db, t.uid, word('title', lang), `${word('reply', lang)}: ${reply.slice(0, 120)}`, {send});
  return {ok: true};
}

/// Marks every open ticket of [problemId] solved and tells each person, in their language: "Your problem is solved" (the fix agent
/// calls this when a fix goes live). Returns how many.
async function solveTicketsOf(db, problemId, now = Date.now(), {send} = {}) {
  if (!problemId) return 0;
  const q = await db.collection('supportTickets').where('problemId', '==', problemId).limit(300).get();
  const open = q.docs.filter(d => d.data().status !== 'solved');
  const at = Timestamp.fromMillis(now);
  for (const d of open) {
    await d.ref.update({status: 'solved', solvedAt: at, updatedAt: at, reply: d.data().reply || word('solved', d.data().lang || 'en')});
    await db.collection('supportShots').doc(d.id).delete().catch(() => {});
    await pushPerson(db, d.data().uid, word('title', d.data().lang || 'en'), word('solved', d.data().lang || 'en'), {send});
  }
  return open.length;
}

const LANG_NAMES = {en: 'English', te: 'Telugu', hi: 'Hindi', ta: 'Tamil', kn: 'Kannada', ml: 'Malayalam', mr: 'Marathi', bn: 'Bengali', gu: 'Gujarati', pa: 'Punjabi', or: 'Odia', ur: 'Urdu', as: 'Assamese'};
const SUPPORT_SYSTEM = lang => `You are the support helper inside the LocaMarket app (a local shopping app in India: customers, vendors, staff).
Answer in ${LANG_NAMES[lang] || 'the same language as the question'}, in very simple words, for someone who is not technical.
Give at most 5 short numbered steps the person can do on their phone or browser. If they cannot fix it themselves, say kindly that the
LocaMarket team has been told and will solve it. Never ask for or mention passwords, OTP codes, card or UPI details. No code, no technical
terms, no links. Never promise refunds or money. Keep it under 120 words.`;

/// One AI answer in the AI Support box (only when the admin turned it on, within the daily numbers). [client] is the tests' seam.
async function ask(db, request, now = Date.now(), client = anthropic) {
  const d = request.data || {};
  const s = (await db.collection('settings').doc('support').get()).data() || {};
  if (s.aiOn !== true) return {text: '', off: true};
  const question = clean(d.question, 600);
  if (!question) throw new HttpsError('invalid-argument', 'Type your question.');
  const limit = Number.isFinite(Number(s.aiDailyLimit)) ? Math.max(0, Math.min(2000, Math.round(Number(s.aiDailyLimit)))) : 50;
  if (!(await takeDevice(db, deviceKeyOf(d.deviceId || request.rawRequest?.ip), 'ai', AI_PER_DEVICE, now))) return {text: '', limit: true};
  if (!(await takeDailyUse(db, 'support_ai', limit, now))) return {text: '', limit: true};
  if (!(await loadAiKey(db))) return {text: '', off: true};
  const lang = langOf(d.lang);
  const c = d.context || {};
  const response = await client().messages.create({
    model: AI_MODELS.chat, max_tokens: 500, thinking: {type: 'disabled'}, system: SUPPORT_SYSTEM(lang),
    messages: [{role: 'user', content: `App: ${clip(c.app, 20)}. Screen: ${clip(c.screen, 60)}. What happened: ${clean(c.message, 200)} (${clip(c.cause, 40)}).\nQuestion: ${question}`}],
  });
  await logAiCall(db, {feature: 'support_ai', model: AI_MODELS.chat, usage: response.usage, uid: request.auth?.uid || '', stopReason: response.stop_reason}, now);
  return {text: response.content.filter(b => b.type === 'text').map(b => b.text).join('\n').trim()};
}

/// Deletes the people's screenshots past their 30 days (the solved ones are deleted at once).
async function cleanSupportShots(db, now = Date.now()) {
  const old = await db.collection('supportShots').where('expiresAt', '<', Timestamp.fromMillis(now)).limit(300).get();
  const b = db.batch();
  old.docs.forEach(d => b.delete(d.ref));
  if (old.size) await b.commit();
  return old.size;
}

exports.openSupportTicket = onCall(options, async request => openTicket(getFirestore(), request));
exports.mySupportTickets = onCall(options, async request => myTickets(getFirestore(), request));
exports.answerSupportTicket = onCall(options, async request => answer(getFirestore(), await requireAdmin(request), request.data));
exports.askSupport = onCall({...options, timeoutSeconds: 60, secrets: [anthropicKey]}, async request => {
  try {
    return await ask(getFirestore(), request);
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.warn('Support AI failed', e?.message || e);
    return {text: '', off: true};
  }
});
exports.cleanSupportShots = task(async () => console.log('Support screenshots deleted', await cleanSupportShots(getFirestore())));
exports.solveSupportTickets = onDocumentCreated({document: 'solvedProblems/{id}', region: 'asia-south1', maxInstances: 2}, async event => {
  const problemId = String(event.data?.data()?.problemId || '');
  console.log('Support tickets solved', await solveTicketsOf(getFirestore(), problemId));
});
exports._test = {openTicket, myTickets, answer, ask, solveTicketsOf, cleanSupportShots, deviceKeyOf, problemIdOf, WORDS, TICKETS_PER_DAY};
