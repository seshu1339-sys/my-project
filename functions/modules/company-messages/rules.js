'use strict';
// Company messages (owner, 18 Nov 2026: cost cuts part 5): the rules that need no database, so the tests check them without a server.
// The audience is a setting ('vendors' now); service providers and transport can be added to AUDIENCES later without changing the
// vendors' part.

/// The message types, as the vendor reads them (with the official "LOCAMARKET Team" badge).
const TYPES = {
  solved: 'Problem solved',
  offer: 'New offer',
  payment: 'Payment / charges change',
  account: 'Reset / account info',
  general: 'General info',
};
/// Payment / charges messages come only from the admin (owner, 18 Nov 2026).
const ADMIN_ONLY_TYPES = ['payment'];

const AUDIENCES = {
  vendors: {label: 'vendors', topicPrefix: 'cm_vendors', personTopic: 'cm_vendor'},
};

const MAX_TITLE = 80;
const MAX_BODY = 1500;
const MAX_LIST = 50; // towns, categories
const MAX_PEOPLE = 200; // Vendor IDs in one message
const MAX_PAIRS = 25; // town + category pushes
const INDEX_SIZE = 50; // the newest messages for everyone (companyMessagesIndex/<audience>)
const IST = 19800000;

/// "Krishna Bazar (Narsipatnam)" is in Narsipatnam (as lib/domain/towns.dart townKey and functions/push-center.js).
const townKey = town => {
  const bracket = String(town || '').match(/\(([^)]+)\)/);
  return String(bracket ? bracket[1] : town || '').trim().toLowerCase().replace(/\s+/g, ' ');
};
const categoryKey = category => String(category || '').trim().toLowerCase().replace(/\s+/g, ' ');
/// A Firebase Cloud Messaging topic name part: letters, digits and '-' only.
const slug = value => String(value || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60) || 'x';

/// The topics one vendor's app joins: everyone, their town, their category, themself (lib/modules/company_messages/company_push.dart
/// makes the same names).
function topicsFor(audience, {uid, town, category}) {
  const a = AUDIENCES[audience];
  return [
    `${a.topicPrefix}_all`,
    ...(townKey(town) ? [`${a.topicPrefix}_t_${slug(townKey(town))}`] : []),
    ...(categoryKey(category) ? [`${a.topicPrefix}_c_${slug(categoryKey(category))}`] : []),
    ...(uid ? [`${a.personTopic}_${slug(uid)}`] : []),
  ];
}

/// The pushes for one message: a topic, or a condition for a town AND a category, or each chosen person's own topic.
function pushPlan(audience, target, uids = []) {
  const a = AUDIENCES[audience];
  if (uids.length) return uids.slice(0, MAX_PEOPLE).map(uid => ({topic: `${a.personTopic}_${slug(uid)}`}));
  if (target.all) return [{topic: `${a.topicPrefix}_all`}];
  const towns = target.towns.map(t => `'${a.topicPrefix}_t_${slug(t)}' in topics`);
  const cats = target.categories.map(c => `'${a.topicPrefix}_c_${slug(c)}' in topics`);
  if (towns.length && cats.length) {
    const out = [];
    for (const t of towns) for (const c of cats) if (out.length < MAX_PAIRS) out.push({condition: `${t} && ${c}`});
    return out;
  }
  return [...towns, ...cats].map(cond => ({topic: cond.slice(1, cond.indexOf("' in topics"))}));
}

/// Does [vendor] {uid, town, category} get a message sent to [target]? Vendor IDs are resolved to uids before ([uids]).
function matches(target, vendor, uids = []) {
  if (uids.length) return uids.includes(vendor.uid);
  if (target.all) return true;
  const townOk = !target.towns.length || target.towns.includes(townKey(vendor.town));
  const catOk = !target.categories.length || target.categories.includes(categoryKey(vendor.category));
  return (target.towns.length > 0 || target.categories.length > 0) && townOk && catOk;
}

const text = (value, max, what, required = true) => {
  const v = typeof value === 'string' ? value.trim() : '';
  if (required && !v) throw Error(`Write the ${what}.`);
  if (v.length > max) throw Error(`Keep the ${what} under ${max} letters.`);
  return v;
};
const list = (value, key, max) => {
  const out = [...new Set((Array.isArray(value) ? value : []).map(key).filter(Boolean))];
  if (out.length > max) throw Error(`Choose at most ${max}.`);
  return out;
};
/// A date written YYYY-MM-DD (Indian day), or '' when none.
function dateOf(value, what) {
  if (value == null || value === '') return '';
  const v = String(value).trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(v) || Number.isNaN(Date.parse(`${v}T00:00:00Z`))) throw Error(`Write the ${what} as a date.`);
  return v;
}
const amountOf = (value, what) => {
  const n = Number(value);
  if (value === '' || value == null || !Number.isFinite(n) || n < 0 || n > 10000000) throw Error(`Write the ${what} in rupees.`);
  return Math.round(n * 100) / 100;
};

/// The message parts every send and edit checks. [staff]: no Payment / charges messages.
function validateContent(data = {}, {staff = false, now = Date.now()} = {}) {
  const type = Object.hasOwn(TYPES, data.type) ? data.type : null;
  if (!type) throw Error('Choose the message type.');
  if (staff && ADMIN_ONLY_TYPES.includes(type)) throw Error('Payment and charges messages come only from the admin.');
  const out = {type, title: text(data.title, MAX_TITLE, 'title'), body: text(data.body, MAX_BODY, 'message')};
  // Payment / charges: the old amount, the new amount and the day it starts, always (owner, 18 Nov 2026).
  if (type === 'payment') {
    out.oldAmount = amountOf(data.oldAmount, 'old amount');
    out.newAmount = amountOf(data.newAmount, 'new amount');
    out.startsOn = dateOf(data.startsOn, 'start date');
    if (!out.startsOn) throw Error('Write the date the new amount starts.');
  }
  out.showUntil = dateOf(data.showUntil, '"show until" date');
  const today = new Date(now + IST).toISOString().slice(0, 10);
  if (out.showUntil && out.showUntil < today) throw Error('The "show until" date has already passed.');
  return out;
}

/// Who gets it: everyone, or towns and / or categories (together: both must fit), or chosen Vendor IDs.
function validateTarget(data = {}) {
  const t = data.target || {};
  const target = {
    all: t.all === true,
    towns: list(t.towns, townKey, MAX_LIST),
    categories: list(t.categories, categoryKey, MAX_LIST),
    vendorCodes: list(t.vendorCodes, v => String(v || '').trim().toUpperCase(), MAX_PEOPLE),
  };
  if (target.all) return {all: true, towns: [], categories: [], vendorCodes: []};
  if (target.vendorCodes.length && (target.towns.length || target.categories.length)) throw Error('Choose Vendor IDs, or towns and categories, not both.');
  if (!target.vendorCodes.length && !target.towns.length && !target.categories.length) throw Error('Choose who gets it: all vendors, a town, a category or Vendor IDs.');
  return target;
}

/// The words of the push (the app shows the full message in the inbox).
const pushText = msg => ({title: `LOCAMARKET Team · ${TYPES[msg.type]}`, body: msg.title});

/// Still shown to vendors on the Indian day [now]: not deleted and not past its "show until" day.
function showing(msg, now = Date.now()) {
  if (msg.deleted === true) return false;
  return !msg.showUntil || msg.showUntil >= new Date(now + IST).toISOString().slice(0, 10);
}

/// One entry of the everyone-list (companyMessagesIndex): a message sent to all, towns or categories (not to chosen people).
const indexEntry = (id, msg) => ({
  id, type: msg.type, title: msg.title, body: msg.body, hasPhoto: msg.hasPhoto === true,
  ...(msg.type === 'payment' ? {oldAmount: msg.oldAmount, newAmount: msg.newAmount, startsOn: msg.startsOn} : {}),
  all: msg.target.all === true, towns: msg.target.towns, categories: msg.target.categories,
  showUntil: msg.showUntil || '', sentAt: msg.sentAt, edited: msg.edited === true, editedAt: msg.editedAt ?? null,
});

module.exports = {
  TYPES, ADMIN_ONLY_TYPES, AUDIENCES, INDEX_SIZE, MAX_PEOPLE, townKey, categoryKey, slug, topicsFor, pushPlan, matches, validateContent,
  validateTarget, pushText, showing, indexEntry,
};
