'use strict';
// What Flash reads and writes. The three chats run through the same steps, each with its own definition (user/, vendor/, staff/) and its
// own collection, so one chat's records are never mixed with another's.
//
//   flashUserChats|flashVendorChats|flashPremiumChats|flashProviderChats|flashStaffChats/<id>  {uid, who, email, kind, category, status, ...}
//                                                         status: open -> solved, or open -> ticket -> closed
//     .../messages/<id>                                   {role: user | flash | admin, text, at}
//   flashTickets/<kind>_<chatId>                          {kind, chatId, uid, who, email, category, text, summary, reason, status: open | closed, ...}
//   flashTicketTriage/<ticketId>                          Sonnet's suggestion for the admin, or {failed: true}
//   flashStats/<kind>                                     {cameIn, solved, verified}; pending is cameIn - solved
//   flashConfig/main                                      {dailyMessages, helpUser, helpVendor, helpPremium, helpProvider, helpStaff, supportPhone, supportWhatsapp}
//   flashPublic/main                                      {supportPhone, supportWhatsapp}: the office number the Premium chat shows (signed-in read)
//   flashAnswers/main                                     {items: [ready answers], updatedAt, updatedBy}: the ready-question buttons and the
//                                                         stored answers (signed-in read; default-answers.json until the admin saves)
//   flashAnswerDaily/<YYYY-MM-DD> and /<YYYY-MM>          {period, ready, free, ai, team, byChat: {<kind>: {...}}}: how chats were answered
//                                                         (ready button, a stored answer to a typed question, AI, the team), for Health
//
// Cost cuts part 4 (owner, 18 Nov 2026): a typed question first gets a stored answer when its keywords match (no AI); only then AI within
// the daily limit; after that the team ("Our team will answer you.").
//
// The ticket id comes from the chat, so a chat can never make two tickets. Tickets are read only to close and to triage: nothing that talks
// to a person reads them. uid and role come from the sign-in and the server's own records, never from the request.
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const {AI_MODELS, logAiCall, takeDailyUse, keyIsSet} = require('../ai-core');
const {askFlash} = require('./answer');
const {readTicket} = require('./triage');
const {DEFAULT_CONFIG, cleanText, helpFor, historyFor, ticketId, ticketReply, ticketText, validId, validateConfig} = require('./rules');
const {DEFAULT_ANSWERS, matchAnswer, replyFor, validateAnswers} = require('./answers');

const IST_MS = 19800000;
const answersRef = db => db.collection('flashAnswers').doc('main');
let answersCache = {at: -Infinity, items: null};

/// The ready answers: the admin's list (read at most every 5 minutes), else the starting list.
async function readAnswers(db, now = Date.now()) {
  if (answersCache.items && now - answersCache.at < 300000) return answersCache.items;
  const items = (await answersRef(db).get()).data()?.items;
  answersCache = {at: now, items: Array.isArray(items) ? items : DEFAULT_ANSWERS};
  return answersCache.items;
}
const resetAnswersCache = () => { answersCache = {at: -Infinity, items: null}; };

/// The admin saves the ready answers (checked first).
async function saveAnswers(db, data = {}, adminUid = '', now = Date.now()) {
  const items = validateAnswers(data.items);
  await answersRef(db).set({items, updatedAt: Timestamp.fromMillis(now), updatedBy: adminUid});
  answersCache = {at: now, items};
  return {saved: items.length};
}

/// Counts how one question was answered: 'ready' (a ready button), 'free' (a stored answer to a typed question), 'ai' or 'team', for
/// the day and the month (Indian time). Never throws: a count must not break the chat.
async function countAnswer(db, kind, how, now = Date.now()) {
  const day = new Date(now + IST_MS).toISOString().slice(0, 10);
  const inc = FieldValue.increment(1);
  try {
    const batch = db.batch();
    for (const period of [day, day.slice(0, 7)]) {
      batch.set(db.collection('flashAnswerDaily').doc(period), {period, [how]: inc, byChat: {[kind]: {[how]: inc}}}, {merge: true});
    }
    await batch.commit();
  } catch (error) {
    console.warn('Flash count not saved', error.message);
  }
}

/// A ready button was tapped: the app showed its stored answer at once; this only counts it.
async function countReady(db, chat, data = {}, now = Date.now()) {
  const id = typeof data.answerId === 'string' ? data.answerId : '';
  const found = (await readAnswers(db, now)).find(a => a.id === id && a.active !== false && (a.chats || []).includes(chat.kind));
  if (!found) throw Error('That answer was not found.');
  await countAnswer(db, chat.kind, 'ready', now);
  return {counted: true};
}

const configRef = db => db.collection('flashConfig').doc('main');
const statsRef = (db, kind) => db.collection('flashStats').doc(kind);
const chatRef = (db, chat, id) => db.collection(chat.collection).doc(id);

async function readConfig(db) {
  return {...DEFAULT_CONFIG, ...(await configRef(db).get()).data()};
}

async function saveConfig(db, data = {}) {
  const fields = validateConfig(data);
  await configRef(db).set(fields, {merge: true});
  await db.collection('flashPublic').doc('main').set({supportPhone: fields.supportPhone, supportWhatsapp: fields.supportWhatsapp}, {merge: true});
  return fields;
}

const addMessage = (tx, ref, role, text, at) => tx.set(ref.collection('messages').doc(), {role, text, at: Timestamp.fromMillis(at)});

async function readMessages(ref) {
  return (await ref.collection('messages').orderBy('at').get()).docs.map(doc => doc.data());
}

/// The person's own open chat, or an error. Another person's chat looks the same as one that does not exist.
async function ownChat(db, chat, uid, chatId) {
  if (!validId(chatId)) throw Error('That chat was not found.');
  const ref = chatRef(db, chat, chatId);
  const data = (await ref.get()).data();
  if (data?.uid !== uid) throw Error('That chat was not found.');
  if (data.status !== 'open') throw Error('This chat has finished. Please start a new one.');
  return {ref, data};
}

/// Makes the chat and counts one issue in.
async function startChat(db, chat, person, category, now) {
  const ref = db.collection(chat.collection).doc();
  const data = {
    uid: person.uid, email: person.email ?? '', who: await chat.label(db, person.uid), kind: chat.kind, category,
    status: 'open', verified: false, createdAt: Timestamp.fromMillis(now), updatedAt: Timestamp.fromMillis(now),
  };
  await db.runTransaction(async tx => {
    tx.set(ref, data);
    tx.set(statsRef(db, chat.kind), {cameIn: FieldValue.increment(1)}, {merge: true});
  });
  return {ref, data};
}

/// Moves an open chat to a ticket and gives the fixed reply. Does nothing if the chat already moved on.
async function openTicket(db, chat, ref, data, {summary, reason, lastText}, now) {
  const reply = ticketReply(lastText);
  const text = ticketText(await readMessages(ref));
  const id = ticketId(chat.kind, ref.id);
  const status = await db.runTransaction(async tx => {
    const fresh = (await tx.get(ref)).data();
    if (fresh?.status !== 'open') return fresh?.status;
    tx.update(ref, {status: 'ticket', ticketId: id, updatedAt: Timestamp.fromMillis(now)});
    addMessage(tx, ref, 'flash', reply, now);
    tx.create(db.collection('flashTickets').doc(id), {
      kind: chat.kind, chatId: ref.id, uid: data.uid, who: data.who, email: data.email, category: data.category, text, summary, reason,
      // Premium vendors' tickets come first in the admin's Support Inbox.
      priority: chat.priority === true, status: 'open', createdAt: Timestamp.fromMillis(now),
    });
    return 'ticket';
  });
  return {chatId: ref.id, status, reply};
}

/// AI answers for everyone together each day, in all five chats (owner, 17 Nov 2026: inside the ₹90-a-month AI limit). After that the
/// chat becomes a ticket for the team, as when Flash has no answer.
/// (FLASH_DAILY_TOTAL / FLASH_TRIAGE_DAILY_TOTAL in the environment only for the tests.)
const flashDailyTotal = () => Number(process.env.FLASH_DAILY_TOTAL) || 30;
/// Tickets Flash reads for the admin each day (the rest stay unread for the admin, nothing is lost).
const triageDailyTotal = () => Number(process.env.FLASH_TRIAGE_DAILY_TOTAL) || 5;

/// Flash's reply to one message; null for no usable answer. A failure here, of AI or of reading the facts, must not lose the person's problem.
async function flashAnswer(db, client, chat, {uid, category}, ref, help, now) {
  if (!(await takeDailyUse(db, 'flash_all', flashDailyTotal(), now))) return null;
  try {
    const facts = await chat.facts(db, uid, category, now);
    const history = historyFor(await readMessages(ref));
    // A chat may ask for the stronger model (the Premium vendors' advanced chat); the others use Haiku.
    const model = chat.model ?? AI_MODELS.chat;
    const {answer, response} = await askFlash(client(), {rules: chat.rules, help, facts, history, model, effort: chat.effort ?? 'low'});
    await logAiCall(db, {feature: `flash_${chat.kind}`, model, usage: response.usage, uid, stopReason: response.stop_reason}, now);
    return answer;
  } catch (error) {
    console.warn('Flash could not answer', chat.kind, error.status ?? error.name);
    return null;
  }
}

/// One message from a person. Flash answers, or the chat becomes a ticket.
async function sendMessage(db, client, chat, person, data = {}, now = Date.now()) {
  const {uid} = person;
  if (!(await chat.allowed(db, uid))) throw Error('This chat is not for your account.');
  const text = cleanText(data.text);
  const existing = data.chatId ? await ownChat(db, chat, uid, data.chatId) : null;
  if (!existing && !chat.categories.includes(data.category)) throw Error('Choose a category.');
  const config = await readConfig(db);
  if (!(await takeDailyUse(db, `flash_${uid}`, config.dailyMessages, now))) throw Error(`You have used today's ${config.dailyMessages} messages. Please try again tomorrow.`);

  const {ref, data: chatData} = existing ?? await startChat(db, chat, person, data.category, now);
  await db.runTransaction(async tx => {
    addMessage(tx, ref, 'user', text, now);
    tx.update(ref, {updatedAt: Timestamp.fromMillis(now)});
  });
  const later = now + 1;

  // 1. A stored answer when the keywords match (no AI). One already given in this chat is not given again.
  const stored = matchAnswer(text, await readAnswers(db, now), chat.kind, {skip: chatData.givenAnswers || []});
  if (stored) {
    const reply = replyFor(stored, text);
    const status = await db.runTransaction(async tx => {
      const fresh = (await tx.get(ref)).data();
      if (fresh?.status === 'open') {
        addMessage(tx, ref, 'flash', reply, later);
        tx.update(ref, {givenAnswers: FieldValue.arrayUnion(stored.id)});
      }
      return fresh?.status;
    });
    await countAnswer(db, chat.kind, 'free', now);
    return {chatId: ref.id, status, reply, readyAnswer: stored.id};
  }

  // 2. AI within the daily limit; 3. else the team.
  const answer = await flashAnswer(db, client, chat, chatData, ref, helpFor(config, chat.helpField), now);
  if (!answer || answer.needsTeam) {
    await countAnswer(db, chat.kind, 'team', now);
    return openTicket(db, chat, ref, chatData, {summary: answer?.summary ?? '', reason: answer ? 'flash' : 'no_answer', lastText: text}, later);
  }
  await countAnswer(db, chat.kind, 'ai', now);
  const status = await db.runTransaction(async tx => {
    const fresh = (await tx.get(ref)).data();
    if (fresh?.status === 'open') addMessage(tx, ref, 'flash', answer.reply, later);
    return fresh?.status;
  });
  return {chatId: ref.id, status, reply: answer.reply};
}

/// The person says the problem is solved. It counts as solved, for the admin to check.
async function markSolved(db, chat, uid, data = {}, now = Date.now()) {
  const {ref} = await ownChat(db, chat, uid, data.chatId);
  await db.runTransaction(async tx => {
    if ((await tx.get(ref)).data()?.status !== 'open') throw Error('This chat has finished. Please start a new one.');
    tx.update(ref, {status: 'solved', solvedAt: Timestamp.fromMillis(now), updatedAt: Timestamp.fromMillis(now)});
    tx.set(statsRef(db, chat.kind), {solved: FieldValue.increment(1)}, {merge: true});
  });
  return {chatId: ref.id, status: 'solved'};
}

/// The person says Flash did not solve it.
async function markUnsolved(db, chat, uid, data = {}, now = Date.now()) {
  const {ref, data: chatData} = await ownChat(db, chat, uid, data.chatId);
  const messages = await readMessages(ref);
  const lastText = messages.filter(m => m.role === 'user').at(-1)?.text ?? '';
  await countAnswer(db, chat.kind, 'team', now);
  return openTicket(db, chat, ref, chatData, {summary: '', reason: 'person', lastText}, now);
}

/// Admin answers and closes a ticket. The answer goes into the person's chat, and the issue counts as solved.
async function closeTicket(db, chats, adminUid, data = {}, now = Date.now()) {
  const reply = cleanText(data.reply, 'Write the answer for this person.');
  if (!validId(data.ticketId)) throw Error('That ticket was not found.');
  const ticketRef = db.collection('flashTickets').doc(data.ticketId);
  await db.runTransaction(async tx => {
    const ticket = (await tx.get(ticketRef)).data();
    const chat = chats[ticket?.kind];
    if (!chat) throw Error('That ticket was not found.');
    if (ticket.status !== 'open') throw Error('This ticket is already closed.');
    const ref = chatRef(db, chat, ticket.chatId);
    tx.update(ticketRef, {status: 'closed', resolution: reply, closedBy: adminUid, closedAt: Timestamp.fromMillis(now)});
    tx.update(ref, {status: 'closed', updatedAt: Timestamp.fromMillis(now)});
    addMessage(tx, ref, 'admin', reply, now);
    tx.set(statsRef(db, chat.kind), {solved: FieldValue.increment(1)}, {merge: true});
  });
  return {status: 'closed'};
}

/// Admin checked a chat that Flash solved.
async function verifyChat(db, chats, adminUid, data = {}, now = Date.now()) {
  const chat = chats[data.kind];
  if (!chat || !validId(data.chatId)) throw Error('That chat was not found.');
  const ref = chatRef(db, chat, data.chatId);
  await db.runTransaction(async tx => {
    const found = (await tx.get(ref)).data();
    if (found?.status !== 'solved') throw Error('Only a chat that Flash solved can be verified.');
    if (found.verified === true) return;
    tx.update(ref, {verified: true, verifiedBy: adminUid, verifiedAt: Timestamp.fromMillis(now)});
    tx.set(statsRef(db, chat.kind), {verified: FieldValue.increment(1)}, {merge: true});
  });
  return {verified: true};
}

/// Haiku reads one new ticket for the admin. A trigger can fire twice, so a ticket already read is left alone.
async function triageTicket(db, client, id, ticket, now = Date.now()) {
  const ref = db.collection('flashTicketTriage').doc(id);
  if ((await ref.get()).exists) return;
  if (!(await takeDailyUse(db, 'flash_triage', triageDailyTotal(), now))) {
    await ref.set({failed: true, reason: "today's AI limit", kind: ticket.kind, at: Timestamp.fromMillis(now)});
    return;
  }
  let triage = null;
  try {
    const result = await readTicket(client(), ticket);
    triage = result.triage;
    await logAiCall(db, {feature: 'flash_triage', model: AI_MODELS.admin, usage: result.response.usage, uid: ticket.uid, stopReason: result.response.stop_reason}, now);
  } catch (error) {
    console.warn('Ticket not read', error.status ?? error.name);
  }
  await ref.set({...(triage ?? {failed: true}), kind: ticket.kind, model: AI_MODELS.admin, at: Timestamp.fromMillis(now)});
}

module.exports = {readAnswers, resetAnswersCache, saveAnswers, countAnswer, countReady, readConfig, saveConfig, sendMessage, markSolved, markUnsolved, closeTicket, verifyChat, triageTicket};
