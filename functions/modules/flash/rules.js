'use strict';
// Flash: the checks and fixed words that need no database and no AI.
const IST = 19800000;
const TEXT_MAX = 1000;
const TICKET_TEXT_MAX = 4000;
const HELP_MAX = 4000;
const HISTORY = 20;
const DEFAULT_CONFIG = {dailyMessages: 30, helpUser: '', helpVendor: '', helpStaff: ''};
const ID = /^[a-zA-Z0-9_-]{1,160}$/;

// The promise made when a ticket opens. The server writes it, so AI can never change or skip it.
const TICKET_REPLY = 'Your problem has reached our team. It will be resolved within 24 hours.';
const TICKET_REPLY_TELUGU = 'మీ సమస్య మా టీమ్‌కు చేరింది. ఇరవై నాలుగు గంటల్లో పరిష్కారం అవుతుంది.';

const ticketReply = text => /[ఀ-౿]/.test(text) ? TICKET_REPLY_TELUGU : TICKET_REPLY;
const validId = id => typeof id === 'string' && ID.test(id);
const ticketId = (kind, chatId) => `${kind}_${chatId}`;

/// The text of one message, or an error for an empty or very long one.
function cleanText(value, what = 'Type a message.') {
  const text = typeof value === 'string' ? value.trim() : '';
  if (!text) throw Error(what);
  if (text.length > TEXT_MAX) throw Error(`Please keep it under ${TEXT_MAX} letters.`);
  return text;
}

function validateConfig(data = {}) {
  const {dailyMessages} = data;
  if (!Number.isInteger(dailyMessages) || dailyMessages < 1 || dailyMessages > 500) throw Error('The daily limit must be from 1 to 500 messages.');
  const help = name => {
    const text = typeof data[name] === 'string' ? data[name].trim() : '';
    if (text.length > HELP_MAX) throw Error(`Keep each help text under ${HELP_MAX} letters.`);
    return text;
  };
  return {dailyMessages, helpUser: help('helpUser'), helpVendor: help('helpVendor'), helpStaff: help('helpStaff')};
}

/// What the model sees of a chat: only this chat's person and Flash, oldest first, starting with the person (the API needs that).
function historyFor(messages) {
  const talk = messages.filter(m => m.role === 'user' || m.role === 'flash').slice(-HISTORY).map(m => ({role: m.role === 'user' ? 'user' : 'assistant', content: m.text}));
  while (talk.length && talk[0].role !== 'user') talk.shift();
  return talk;
}

/// The person's own words, for the ticket.
function ticketText(messages) {
  return messages.filter(m => m.role === 'user').map(m => m.text).join('\n').slice(0, TICKET_TEXT_MAX);
}

/// A stored time as a plain Indian date, or '' when there is none. Facts carry dates ready to read, so AI never works one out.
function dateText(stamp) {
  const ms = stamp?.toMillis?.();
  return Number.isFinite(ms) ? new Date(ms + IST).toISOString().slice(0, 10).split('-').reverse().join('/') : '';
}

const newestFirst = field => (a, b) => (b[field]?.toMillis?.() ?? 0) - (a[field]?.toMillis?.() ?? 0);

/// How many of [rows] have each status.
function countByStatus(rows) {
  const counts = {};
  for (const row of rows) counts[row.status ?? 'unknown'] = (counts[row.status ?? 'unknown'] ?? 0) + 1;
  return counts;
}

module.exports = {DEFAULT_CONFIG, TEXT_MAX, TICKET_REPLY, TICKET_REPLY_TELUGU, cleanText, countByStatus, dateText, historyFor, newestFirst, ticketId, ticketReply, ticketText, validId, validateConfig};
