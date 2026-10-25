'use strict';
// Usage analytics: what people do in the apps, for the admin's Analytics reports and for each vendor's, service provider's and staff
// member's own numbers in their app. The apps send small batches (trackUsage); what vendors, providers and staff do through the
// server (registering, adding items, changing prices, ticking "Ad for your shop", adding vendors) is counted where it happens
// (countUsage). Only counts are kept, never a log of everything:
//   usageDaily/<day>~<event>        {day, event, total, keys: {<k>: {key, label, town, count}}}   what was used, by what (shop, item, town...)
//   usageOwnerDaily/<owner>~<day>   {ownerId, day, counts: {<event>: n}}                          a shop owner's / provider's / staff's numbers
//   usagePersonDaily/<uid>~<day>    {uid, day, counts: {<event>: n}, keys: {...}}                 one signed-in person's day (admin report)
//   userActivity/<uid>              {uid, lastActiveAt, app, platform}                            when an account last used an app
// Cost guards: one device counts at most DEVICE_DAILY_CAP events a day (the rest are dropped), events must be on the fixed list,
// keys and labels are cut short, a batch is merged in memory so each document is written once, bots are ignored, and the per-person
// documents carry expiresAt (a Firestore TTL policy on usagePersonDaily.expiresAt removes them after PERSON_KEEP_DAYS).
const {createHash} = require('node:crypto');
const {FieldValue, Timestamp} = require('firebase-admin/firestore');

const DEVICE_DAILY_CAP = 400;
const MAX_BATCH = 50;
const PERSON_KEEP_DAYS = 400;

/// Every event the apps may send. [owner] says whose numbers it also counts for: 'shop' (the key is a shop id) or 'service'
/// (the key is a service listing id).
const CLIENT_EVENTS = {
  shop_call: {owner: 'shop'}, shop_whatsapp: {owner: 'shop'}, shop_directions: {owner: 'shop'},
  worker_call: {owner: 'service'}, worker_whatsapp: {owner: 'service'},
  map_view: {}, price_list_view: {}, service_open: {}, search: {}, search_no_result: {}, location_change: {},
  offer_click: {}, transport_click: {}, screen_view: {}, button: {}, notification_open: {},
  // the admin's Setup check (lib/services/app_monitoring.dart): key <app>/<platform>/<speed group> and <app>/<platform>/<crash|error>/<id>
  app_start: {}, app_error: {},
};
/// Counted by the server only (an app cannot send these).
const SERVER_EVENTS = ['vendor_register', 'item_added', 'price_changed', 'ad_interest', 'staff_added'];
const APPS = ['customer', 'vendor', 'staff', 'admin'];
const BOT = /bot|crawl|spider|slurp|headless|lighthouse|phantom|puppeteer|playwright|selenium|curl|wget|python-requests|preview/i;

const hash = value => createHash('sha256').update(value).digest('hex');
/// The Indian day (YYYY-MM-DD).
const dayKey = (now = Date.now()) => new Date(now + 19800000).toISOString().slice(0, 10);
/// A short, field-name-safe id for a key (keys become map field names).
const shortKey = key => hash(String(key)).slice(0, 12);
const clip = (value, max) => String(value ?? '').trim().replace(/\s+/g, ' ').slice(0, max);

function normalizeUsageBatch(data = {}) {
  const deviceId = typeof data.deviceId === 'string' ? data.deviceId : '';
  if (!/^[a-zA-Z0-9-]{16,64}$/.test(deviceId)) throw Error('Provide a valid device id.');
  const app = APPS.includes(data.app) ? data.app : 'customer';
  if (!Array.isArray(data.events) || data.events.length > MAX_BATCH) throw Error(`Send 0 to ${MAX_BATCH} events.`);
  const events = [];
  for (const e of data.events) {
    if (!e || !Object.hasOwn(CLIENT_EVENTS, e.event)) continue; // an unknown or server-only event is dropped, not an error
    events.push({event: e.event, key: clip(e.key, 100), label: clip(e.label, 100), town: clip(e.town, 60)});
  }
  return {deviceId, app, platform: data.platform === 'android' ? 'android' : 'web', events, touch: data.touch === true};
}

/// Adds [events] (already checked) to the day's counts, the owners' and the person's. [ownerOf] maps an event to the owner ids
/// whose numbers it counts for.
async function writeCounts(db, events, {uid = null, ownerOf = async () => [], now = Date.now()} = {}) {
  if (!events.length) return;
  const day = dayKey(now);
  const inc = n => FieldValue.increment(n);
  const byEvent = new Map(), byOwner = new Map(), person = {counts: {}, keys: {}};
  for (const e of events) {
    const k = shortKey(e.key || '-');
    const entry = byEvent.get(e.event) || {total: 0, keys: {}};
    entry.total++;
    const key = entry.keys[k] || {key: e.key, label: e.label, town: e.town, count: 0};
    key.count++;
    entry.keys[k] = key;
    byEvent.set(e.event, entry);
    for (const owner of await ownerOf(e)) {
      const counts = byOwner.get(owner) || {};
      counts[e.event] = (counts[e.event] || 0) + 1;
      byOwner.set(owner, counts);
    }
    if (uid) {
      person.counts[e.event] = (person.counts[e.event] || 0) + 1;
      const pk = `${e.event}~${k}`;
      person.keys[pk] = person.keys[pk] || {event: e.event, key: e.key, label: e.label, count: 0};
      person.keys[pk].count++;
    }
  }
  const batch = db.batch();
  for (const [event, entry] of byEvent) {
    batch.set(db.collection('usageDaily').doc(`${day}~${event}`), {
      day, event, total: inc(entry.total), updatedAt: FieldValue.serverTimestamp(),
      keys: Object.fromEntries(Object.entries(entry.keys).map(([k, v]) => [k, {key: v.key, label: v.label, town: v.town, count: inc(v.count)}])),
    }, {merge: true});
  }
  for (const [owner, counts] of byOwner) {
    batch.set(db.collection('usageOwnerDaily').doc(`${owner}~${day}`), {
      ownerId: owner, day, counts: Object.fromEntries(Object.entries(counts).map(([e, n]) => [e, inc(n)])), updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  if (uid) {
    batch.set(db.collection('usagePersonDaily').doc(`${uid}~${day}`), {
      uid, day, expiresAt: Timestamp.fromMillis(now + PERSON_KEEP_DAYS * 86400000),
      counts: Object.fromEntries(Object.entries(person.counts).map(([e, n]) => [e, inc(n)])),
      keys: Object.fromEntries(Object.entries(person.keys).map(([k, v]) => [k, {event: v.event, key: v.key, label: v.label, count: inc(v.count)}])),
    }, {merge: true});
  }
  await batch.commit();
}

/// Whose own numbers a shop or service event counts for: the shop's owner (the vendor) and the staff member who added it.
function ownerResolver(db) {
  const cache = new Map();
  return async e => {
    const kind = CLIENT_EVENTS[e.event]?.owner;
    if (!kind || !/^[A-Za-z0-9_-]{1,128}$/.test(e.key)) return [];
    const path = `${kind === 'shop' ? 'shops' : 'services'}/${e.key}`;
    if (!cache.has(path)) {
      const doc = (await db.doc(path).get()).data() || {};
      cache.set(path, [...new Set([kind === 'shop' ? doc.ownerId : doc.providerId || doc.ownerId, doc.addedByStaffUid].filter(Boolean))]);
    }
    return cache.get(path);
  };
}

const touchActivity = (db, uid, batch) =>
  db.collection('userActivity').doc(uid).set({uid, lastActiveAt: FieldValue.serverTimestamp(), app: batch.app, platform: batch.platform}, {merge: true});

/// A batch from one device. [context] = {uid, userAgent}. Returns {counted, dropped}.
async function recordUsage(db, batch, context = {}, now = Date.now()) {
  if (context.userAgent && BOT.test(context.userAgent)) return {counted: 0, dropped: batch.events.length, reason: 'bot'};
  const day = dayKey(now);
  if (!batch.events.length) {
    if (context.uid && batch.touch) await touchActivity(db, context.uid, batch);
    return {counted: 0, dropped: 0};
  }
  // the device's daily allowance
  const deviceRef = db.collection('_usageDevices').doc(hash(`${batch.deviceId}|${day}`));
  const allowed = await db.runTransaction(async tx => {
    const used = Number((await tx.get(deviceRef)).data()?.count) || 0;
    const take = Math.max(0, Math.min(batch.events.length, DEVICE_DAILY_CAP - used));
    tx.set(deviceRef, {count: used + take, day, expiresAt: Timestamp.fromMillis(now + 3 * 86400000)}, {merge: true});
    return take;
  });
  const events = batch.events.slice(0, allowed);
  await writeCounts(db, events, {uid: context.uid || null, ownerOf: ownerResolver(db), now});
  if (context.uid && batch.touch) await touchActivity(db, context.uid, batch);
  return {counted: events.length, dropped: batch.events.length - events.length};
}

/// Counts something done through the server (vendor_register, item_added, price_changed, ad_interest, staff_added). Never throws:
/// counting must not break the action itself. [owners] also get it in their own numbers; [uid] in their person report.
async function countUsage(db, event, {key = '', label = '', town = '', owners = [], uid = null} = {}, now = Date.now()) {
  try {
    if (!SERVER_EVENTS.includes(event)) throw Error(`Unknown server event ${event}`);
    const e = {event, key: clip(key, 100), label: clip(label, 100), town: clip(town, 60)};
    await writeCounts(db, [e], {uid, ownerOf: async () => owners.filter(Boolean), now});
  } catch (error) {
    console.warn('Usage count failed', event, error.message);
  }
}

module.exports = {normalizeUsageBatch, recordUsage, countUsage, writeCounts, dayKey, shortKey, CLIENT_EVENTS, SERVER_EVENTS, DEVICE_DAILY_CAP};
