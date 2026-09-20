'use strict';
// Site and ad analytics. Events arrive from the customer app through the
// trackEvent callable and are only ever written here, server-side.
//
// Only aggregate counters are stored (plus hashed, expiring "already counted"
// markers used for unique counts): no per-visitor history and no personal data.
// The visitor id is a random value the app generates on the device.
//
// Counter documents are sharded so a busy day does not queue on one document.
const {createHash} = require('node:crypto');
const {FieldValue, Timestamp} = require('firebase-admin/firestore');

const TYPES = ['visit', 'adImpression', 'adClick'];
const SHARDS = 4;
const MARKER_TTL_MS = 40 * 86400000; // enable a Firestore TTL policy on analyticsSeen.expiresAt
const hash = value => createHash('sha256').update(value).digest('hex');
const dayKey = (now = Date.now()) => new Date(now).toISOString().slice(0, 10); // UTC day

function normalizeEvent(data = {}) {
  const visitorId = typeof data.visitorId === 'string' ? data.visitorId : '';
  if (!/^[a-zA-Z0-9-]{16,64}$/.test(visitorId)) throw Error('Provide a valid visitor id.');
  if (!TYPES.includes(data.type)) throw Error('Unsupported event.');
  const id = (value, label) => {
    if (value === undefined || value === null || value === '') return null;
    if (typeof value !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(value)) throw Error(`Provide a valid ${label}.`);
    return value;
  };
  const event = {
    visitorId, type: data.type, adId: id(data.adId, 'ad id'), sourceAd: id(data.sourceAd, 'source ad'),
    platform: data.platform === 'android' ? 'android' : 'web',
    placement: ['carousel', 'ad', 'box', 'ticker'].includes(data.placement) ? data.placement : null,
  };
  if (event.type !== 'visit' && !event.adId) throw Error('Provide the ad.');
  return event;
}

/// Counts one event. Unique counts use create-once markers so a repeated view,
/// reload or retried request never inflates them.
async function recordEvent(db, event, now = Date.now()) {
  const day = dayKey(now), shard = Math.floor(Math.random() * SHARDS);
  const daily = db.collection('analyticsDaily').doc(`${day}~${shard}`);
  const totals = db.collection('analyticsTotals').doc(`all~${shard}`);
  const adRef = id => db.collection('analyticsAds').doc(`${id}~${shard}`);
  const v = event.visitorId;
  // [marker key, counter document, counter field] - counted once per marker.
  const uniques = [];
  const counts = []; // [document, field]
  const extra = {};
  if (event.type === 'visit') {
    counts.push([daily, 'visits'], [totals, 'visits'], [daily, event.platform === 'android' ? 'visitsAndroid' : 'visitsWeb']);
    uniques.push([`${v}|${day}|visit`, daily, 'visitors'], [`${v}|life|visit`, totals, 'visitors']);
    if (event.sourceAd) {
      counts.push([daily, 'visitsFromAds'], [totals, 'visitsFromAds'], [adRef(event.sourceAd), 'visitsFromAds']);
      extra[adRef(event.sourceAd).path] = {placement: event.placement};
    }
  } else if (event.type === 'adImpression') {
    counts.push([daily, 'adImpressions'], [totals, 'adImpressions'], [adRef(event.adId), 'impressions']);
    extra[adRef(event.adId).path] = {placement: event.placement};
    uniques.push([`${v}|${day}|adView`, daily, 'adViewers'], [`${v}|life|adView`, totals, 'adViewers'], [`${v}|life|adView|${event.adId}`, adRef(event.adId), 'uniqueViewers']);
  } else {
    counts.push([daily, 'adClicks'], [totals, 'adClicks'], [adRef(event.adId), 'clicks']);
    extra[adRef(event.adId).path] = {placement: event.placement};
    uniques.push([`${v}|${day}|adClick`, daily, 'adClickers'], [`${v}|life|adClick`, totals, 'adClickers'], [`${v}|life|adClick|${event.adId}`, adRef(event.adId), 'uniqueClickers']);
  }
  await db.runTransaction(async tx => {
    const markers = uniques.map(([key]) => db.collection('analyticsSeen').doc(hash(key)));
    const seen = await Promise.all(markers.map(ref => tx.get(ref)));
    const inc = new Map(); // document path -> {ref, fields}
    const bump = (ref, field) => { const entry = inc.get(ref.path) || {ref, fields: {}}; entry.fields[field] = FieldValue.increment(1); inc.set(ref.path, entry); };
    for (const [ref, field] of counts) bump(ref, field);
    uniques.forEach(([, ref, field], i) => {
      if (seen[i].exists) return;
      bump(ref, field);
      tx.create(markers[i], {createdAt: FieldValue.serverTimestamp(), expiresAt: Timestamp.fromMillis(now + MARKER_TTL_MS)});
    });
    for (const {ref, fields} of inc.values()) {
      const meta = {lastEventAt: FieldValue.serverTimestamp(), ...(extra[ref.path] || {})};
      if (ref.parent.id === 'analyticsDaily') meta.day = day;
      if (ref.parent.id === 'analyticsAds') meta.adId = ref.id.split('~')[0];
      tx.set(ref, {...fields, ...meta}, {merge: true});
    }
  });
}
module.exports = {normalizeEvent, recordEvent, dayKey, SHARDS};
