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
//
// The ticket id comes from the chat, so a chat can never make two tickets. Tickets are read only to close and to triage: nothing that talks
// to a person reads them. uid and role come from the sign-in and the server's own records, never from the request.
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const {SONNET, HAIKU, logAiCall, takeDailyUse} = require('../ai-core');
const {askFlash} = require('./answer');
const {readTicket} = require('./triage');
const {DEFAULT_CONFIG, cleanText, helpFor, historyFor, ticketId, ticketReply, ticketText, validId, validateConfig} = require('./rules');

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

/// Flash's reply to one message; null for no usable answer. A failure here, of AI or of reading the facts, must not lose the person's problem.
async function flashAnswer(db, client, chat, {uid, category}, ref, help, now) {
  try {
    const facts = await chat.facts(db, uid, category, now);
    const history = historyFor(await readMessages(ref));
    // A chat may ask for the stronger model (the Premium vendors' advanced chat); the others use Haiku.
    const model = chat.model ?? HAIKU;
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

  const answer = await flashAnswer(db, client, chat, chatData, ref, helpFor(config, chat.helpField), now);
  const later = now + 1;
  if (!answer || answer.needsTeam) {
    return openTicket(db, chat, ref, chatData, {summary: answer?.summary ?? '', reason: answer ? 'flash' : 'no_answer', lastText: text}, later);
  }
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

/// Sonnet reads one new ticket for the admin. A trigger can fire twice, so a ticket already read is left alone.
async function triageTicket(db, client, id, ticket, now = Date.now()) {
  const ref = db.collection('flashTicketTriage').doc(id);
  if ((await ref.get()).exists) return;
  let triage = null;
  try {
    const result = await readTicket(client(), ticket);
    triage = result.triage;
    await logAiCall(db, {feature: 'flash_triage', model: SONNET, usage: result.response.usage, uid: ticket.uid, stopReason: result.response.stop_reason}, now);
  } catch (error) {
    console.warn('Ticket not read', error.status ?? error.name);
  }
  await ref.set({...(triage ?? {failed: true}), kind: ticket.kind, model: SONNET, at: Timestamp.fromMillis(now)});
}

module.exports = {readConfig, saveConfig, sendMessage, markSolved, markUnsolved, closeTicket, verifyChat, triageTicket};
