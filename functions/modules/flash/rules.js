'use strict';
// Flash: the checks and fixed words that need no database and no AI.
const IST = 19800000;
const TEXT_MAX = 1000;
const TICKET_TEXT_MAX = 4000;
const HELP_MAX = 4000;
const HISTORY = 20;
const DEFAULT_CONFIG = {dailyMessages: 30, helpUser: '', helpVendor: '', helpPremium: '', helpProvider: '', helpStaff: '', supportPhone: '', supportWhatsapp: ''};
const HELP_FIELDS = ['helpUser', 'helpVendor', 'helpPremium', 'helpProvider', 'helpStaff'];

// What Flash knows about using each app until the admin writes their own (Admin > Flash > Settings shows these to start from). Only
// what the apps really do; anything else goes to the team.
const DEFAULT_HELP = {
  helpUser: [
    'Search: type an item, for example tomato, in the search box and choose it. A map shows every shop in your town that sells it, with its price and a small photo, and a list beside it from the lowest price to the highest, with the distance. Turn on location to see how far each shop is.',
    'Tap a shop to see its photo, address and phone. Call calls the shop; the route button opens the way to the shop in Google Maps.',
    '"Updated today" next to a price means the shop set that price today. A shop\'s price disappears after 24 hours unless the shop sets it again.',
    "Today's Offers on the home page show offer items with the offer price and the normal price. Tap one to see the shop and the way there. An offer disappears after its end time.",
    'Services: tap Services, choose a service such as Plumber, and you see the providers near you with a photo, their charge per hour and a Call button.',
    'Notifications: turn them on to get an alert when a nearby shop posts a sudden offer. Tap the alert to see the shop and the way.',
    'There is no online payment for customers: find the cheapest shop in the app, go there and buy in person.',
  ].join('\n'),
  helpVendor: [
    'Sign in with your Google account (an email code is the backup). Register your shop with name, phone, email and your shop location (stand at the shop with location on). You get a Vendor ID such as VEN-NRPM-116-325 and your shop goes live after the admin approves it.',
    'Free plan: 2 items with photos, free for life. You can change your prices any day. A price lasts 24 hours; enter it again the next day.',
    'Paid plans (Silver, Gold, Premium): more photos, a bigger reach in km, Today\'s Offers boxes (Silver 1, Gold 3, Premium as set by the office) and a box in the website\'s ad boxes, for the plan\'s full period. Plans and prices are on the Plans card. To start a plan, contact the LOCAMARKET office.',
    'Today\'s Offers: open Today\'s Offers > Choose on a box > pick one of your items (its photo shows), the offer price and how long (1 week, 1 month, 2 months or 3 months). It is live at once and marked LIVE in orange in your item list.',
    'Search time: in Item photos, each item\'s menu > How long it shows in search (1 week to 3 months). After that time the item leaves search until you choose again; nothing is deleted.',
    'Add an item: Add an item > choose the category and the item from the list, the quantity and your price. Your first shop photo must be added first.',
    'Post an offer: My Offers > Add offer > name, offer price, normal price, days, and a photo you take or choose. Paid plans can switch on an alert to customers within the plan km (one alert a day).',
  ].join('\n'),
  helpPremium: '',
  helpProvider: [
    'Sign in with your Google account (an email code is the backup). Register under Services with your name, photo, mobile number, the service (plumber, electrician...), your charge per hour and your location. You get a Provider ID such as SRV-NRPM-116-001.',
    'Your listing goes live only after the admin checks it. Then customers near you see you under your service with your photo, charge per hour and distance, and can call you.',
    'You can change your charge per hour in the app at any time.',
  ].join('\n'),
  helpStaff: [
    'Your area: one area per staff member. Choose a free (green) area on the town map and register it while standing inside it with GPS on, after accepting the Terms & Conditions. It is held for you until the admin approves you.',
    "Today's Offers: Add Today's Offer > choose a shop in your area, the item from the list (its photo comes with it), the normal price, a lower offer price and a live camera photo at the shop. It is today's rate and ends by itself at midnight.",
    'Targets: monthly targets for live photos, vendor registrations and paid vendor registrations (a month counts only when complete), and rate updates on at least the set number of days a week. Each rate update needs a live camera photo at the shop (within 100 m, real GPS). The dashboard shows your progress and missed days.',
    'Vendors register themselves in the vendor app. Enter their Vendor ID under Add within 30 minutes of their registration to link them to you. You only see their updates; you cannot change their shop, items or prices.',
  ].join('\n'),
};
/// The help a chat uses: the admin's own text, or the default one.
const helpFor = (config, field) => (typeof config?.[field] === 'string' && config[field].trim() ? config[field] : DEFAULT_HELP[field] || '');
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
  const phone = name => {
    const text = typeof data[name] === 'string' ? data[name].trim() : '';
    if (text && !/^\+?[0-9 ]{8,16}$/.test(text)) throw Error('Enter the office number with digits only, like 9876543210.');
    return text;
  };
  return {dailyMessages, ...Object.fromEntries(HELP_FIELDS.map(name => [name, help(name)])), supportPhone: phone('supportPhone'), supportWhatsapp: phone('supportWhatsapp')};
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

module.exports = {DEFAULT_HELP, HELP_FIELDS, helpFor, DEFAULT_CONFIG, TEXT_MAX, TICKET_REPLY, TICKET_REPLY_TELUGU, cleanText, countByStatus, dateText, historyFor, newestFirst, ticketId, ticketReply, ticketText, validId, validateConfig};
