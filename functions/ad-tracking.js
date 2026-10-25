'use strict';
// Genuine ad view counting for the unified Ads system (lib/domain/ads.dart).
//
// The customer site / app reports what happened to each ad in small batches (callable trackAdEvents). Everything that decides what
// counts is decided HERE, on the server, never by the client:
//   view   the ad was on screen for at least 1 second with the page / app active. Counted at most once per device per ad per 30 minutes,
//          so refreshing again and again does not raise it. Also counts a "unique person" the first time a device ever sees the ad.
//   time   more seconds on screen for an ad whose view was counted in the last 35 minutes (no view, no time).
//   miss   the ad was scheduled into a box but was not visible for a second (tab hidden, scrolled away).
//   tap    the ad was tapped (every tap counts).
// Not counted at all: the vendor who owns the ad, the admin, field staff, known bots and crawlers, and the test devices listed in
// settings/adsConfig.testDevices.
//
// Every counted view / tap is written to adViews (time, town, device) so the admin can check any number later. Totals live in
// adStats/<ad> (what the vendor app and admin watch live) and per day in adStatsDaily/<ad>~<day>.
//
// A shop ad in a Right Side Ad Box (functions/shop-ads.js) is counted the same way: its id starts with "rbox-" and it is a
// rightBoxAds record (counted while it is live) instead of an ads one; its totals carry kind 'rightBox' and the box number.
const {createHash} = require('node:crypto');
const {FieldValue, Timestamp} = require('firebase-admin/firestore');

const VIEW_GAP_MS = 30 * 60 * 1000;
const TIME_WINDOW_MS = 35 * 60 * 1000;
const MAX_EVENTS = 50;
const TYPES = ['view', 'time', 'miss', 'tap'];
const BOT = /bot|crawl|spider|slurp|headless|lighthouse|phantom|puppeteer|playwright|selenium|curl|wget|python-requests|facebookexternalhit|preview/i;

const hash = value => createHash('sha256').update(value).digest('hex');
/// The day an event belongs to, in India (UTC+5:30), as YYYY-MM-DD.
const dayKey = (now = Date.now()) => new Date(now + 19800000).toISOString().slice(0, 10);
/// Town names become part of a field path, so keep them to simple letters and digits.
const townKey = town => String(town || '').trim().toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 40) || 'unknown';

function normalizeBatch(data = {}) {
  const visitorId = typeof data.visitorId === 'string' ? data.visitorId : '';
  if (!/^[a-zA-Z0-9-]{16,64}$/.test(visitorId)) throw Error('Provide a valid visitor id.');
  if (!Array.isArray(data.events) || !data.events.length) throw Error('Provide events.');
  if (data.events.length > MAX_EVENTS) throw Error(`At most ${MAX_EVENTS} events at a time.`);
  const events = data.events.map(e => {
    if (!TYPES.includes(e?.type)) throw Error('Unsupported event.');
    if (typeof e.adId !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(e.adId)) throw Error('Provide a valid ad id.');
    const seconds = Math.max(0, Math.min(120, Math.round(Number(e.seconds) || 0)));
    return {type: e.type, adId: e.adId, seconds};
  });
  return {
    visitorId, events,
    platform: data.platform === 'android' ? 'android' : 'web',
    town: typeof data.town === 'string' ? data.town.trim().slice(0, 60) : '',
  };
}

/// Why this caller's events are ignored, or '' when they count.
function ignoredBecause({userAgent, auth, ad, config, visitorId, staffUids = []}) {
  if (userAgent && BOT.test(userAgent)) return 'bot';
  const tests = String(config?.testDevices || '').split(/[,\s]+/).filter(Boolean);
  if (tests.includes(visitorId)) return 'test device';
  if (auth?.token?.admin === true) return 'admin';
  if (auth?.uid && staffUids.includes(auth.uid)) return 'staff';
  if (auth?.uid && ad?.vendorId && ad.vendorId === auth.uid) return 'owner';
  return '';
}

/// Applies a batch from one device. [context] = {userAgent, auth, staffUids}. Returns what was counted and what was left out.
async function recordAdEvents(db, batch, context, now = Date.now()) {
  const result = {views: 0, time: 0, missed: 0, taps: 0, duplicates: 0, ignored: 0, reason: ''};
  const config = (await db.collection('settings').doc('adsConfig').get()).data() || {};
  const day = dayKey(now), tk = townKey(batch.town), device = batch.platform;
  for (const event of batch.events) {
    const rightBox = event.adId.startsWith('rbox-');
    const adSnap = await db.collection(rightBox ? 'rightBoxAds' : 'ads').doc(event.adId).get();
    const ad = adSnap.data();
    if (!adSnap.exists || (rightBox ? ad.status !== 'live' : ad.status && ad.status !== 'approved')) { result.ignored++; continue; }
    const why = ignoredBecause({userAgent: context.userAgent, auth: context.auth, ad, config, visitorId: batch.visitorId, staffUids: context.staffUids});
    if (why) { result.ignored++; result.reason = why; continue; }
    const key = hash(`${event.adId}|${batch.visitorId}`);
    const guardRef = db.collection('adViewGuard').doc(key);
    const uniqueRef = db.collection('adUniques').doc(key);
    const statsRef = db.collection('adStats').doc(event.adId);
    const dailyRef = db.collection('adStatsDaily').doc(`${event.adId}~${day}`);
    const base = {adId: event.adId, vendorId: ad.vendorId || null, shopId: ad.shopId || null, ...(rightBox ? {kind: 'rightBox', box: ad.box || null} : {})};
    const inc = n => FieldValue.increment(n);
    // the same count, broken down by town and by device (nested maps: set() would take a dotted name literally)
    const split = (name, n) => ({towns: {[tk]: {[name]: inc(n)}}, devices: {[device]: {[name]: inc(n)}}});
    const outcome = await db.runTransaction(async tx => {
      const [guard, unique, today] = await Promise.all([tx.get(guardRef), event.type === 'view' ? tx.get(uniqueRef) : Promise.resolve(null), event.type === 'view' ? tx.get(dailyRef) : Promise.resolve(null)]);
      const last = guard.exists ? guard.data().lastAt.toMillis() : 0;
      const stat = (stats, daily) => {
        tx.set(statsRef, {...base, ...stats, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
        tx.set(dailyRef, {...base, day, ...daily}, {merge: true});
      };
      if (event.type === 'view') {
        if (now - last < VIEW_GAP_MS) return 'duplicate';
        tx.set(guardRef, {adId: event.adId, lastAt: Timestamp.fromMillis(now), expiresAt: Timestamp.fromMillis(now + 40 * 86400000)});
        const first = !unique.exists;
        if (first) tx.set(uniqueRef, {adId: event.adId, at: Timestamp.fromMillis(now)});
        stat({views: inc(1), seconds: inc(event.seconds), ...(first ? {unique: inc(1)} : {})},
          {views: inc(1), seconds: inc(event.seconds), ...split('views', 1), ...(first ? {unique: inc(1)} : {})});
        tx.set(db.collection('adViews').doc(), {...base, type: 'view', at: Timestamp.fromMillis(now), day, town: batch.town, device, seconds: event.seconds, visitor: key.slice(0, 12)});
        // The daily limit: once today's counted views reach it, the ad is marked for the rest of the (Indian) day and the site stops showing it.
        const limit = Math.round(Number(ad.maxPerDay)) || 0;
        if (!rightBox && limit > 0 && (today.exists ? Number(today.data().views) || 0 : 0) + 1 >= limit) tx.update(db.collection('ads').doc(event.adId), {capDay: day});
        return 'view';
      }
      if (event.type === 'time') {
        if (!event.seconds || now - last > TIME_WINDOW_MS) return 'ignored';
        stat({seconds: inc(event.seconds)}, {seconds: inc(event.seconds), ...split('seconds', event.seconds)});
        return 'time';
      }
      if (event.type === 'miss') {
        stat({missed: inc(1)}, {missed: inc(1), ...split('missed', 1)});
        return 'miss';
      }
      stat({taps: inc(1)}, {taps: inc(1), ...split('taps', 1)});
      tx.set(db.collection('adViews').doc(), {...base, type: 'tap', at: Timestamp.fromMillis(now), day, town: batch.town, device, visitor: key.slice(0, 12)});
      return 'tap';
    });
    if (outcome === 'view') result.views++;
    else if (outcome === 'time') result.time += event.seconds;
    else if (outcome === 'miss') result.missed++;
    else if (outcome === 'tap') result.taps++;
    else if (outcome === 'duplicate') result.duplicates++;
    else result.ignored++;
  }
  return result;
}

module.exports = {normalizeBatch, ignoredBecause, recordAdEvents, dayKey, townKey, VIEW_GAP_MS};
