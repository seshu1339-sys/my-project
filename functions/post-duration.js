'use strict';
// One post duration for everyone (owner, 12 Nov 2026). The admin chooses it in Business Profile (settings/business.postDuration:
// '24h', '7d' or '1m'; 24 hours when not set). Every post of a vendor or staff ends at the latest when this time has passed since it was
// posted, paid plans included (a plan gives more photos and posts, not a longer time):
//   (vendor item prices are not posts any more: they stay until the vendor changes them, owner 16 Nov 2026, vendor-prices.js)
//   exclusive items         products.postedAt     -> expiresAt, endsAt (ISO)
//   (Today's Offers boxes are not posts any more: they run with the vendor's plan, owner 13 Nov 2026)
//   Vendor Offers           vendorOffers.postedAt (else createdAt) -> endsAt (Timestamp); staff offers end the same day anyway
//   vendor ads              ads (source 'vendor').startsAt -> endsAt (ISO)
// A post keeps its own end (ownEndsAt: the days the vendor chose, the plan end) when that is earlier. The end is capped when the post
// is saved, so the website and the apps hide it at that time by themselves. When the admin changes the duration, the 15-minute job
// (scheduled-jobs.js) recalculates the posts that are still running, once (_jobState/postDuration remembers what was applied).
// Admin-made items (promotions, wholesale offers, right-box ads) and the shop's own catalogue are not posts and are not touched.
const {Timestamp} = require('firebase-admin/firestore');

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;
const POST_DURATIONS = {'24h': DAY_MS, '7d': 7 * DAY_MS, '1m': 30 * DAY_MS};
const DEFAULT_POST_DURATION = '24h';

const postDurationKey = business => (Object.hasOwn(POST_DURATIONS, String(business?.postDuration ?? '')) ? String(business.postDuration) : DEFAULT_POST_DURATION);
const postDurationMs = business => POST_DURATIONS[postDurationKey(business)];

async function readPostDurationMs(db) {
  return postDurationMs((await db.collection('settings').doc('business').get()).data());
}

/// The end of a post: its own end (when it has one) or the post duration after it was posted, whichever comes first.
const cappedEnd = (postedMs, durationMs, ownEndMs = Infinity) => Math.min(Number.isFinite(ownEndMs) ? ownEndMs : Infinity, postedMs + durationMs);

const millisOf = value => {
  if (value === undefined || value === null || value === '') return NaN;
  if (typeof value?.toMillis === 'function') return value.toMillis();
  if (typeof value === 'number') return value;
  return Date.parse(String(value));
};
const firstMillis = (...values) => values.map(millisOf).find(Number.isFinite) ?? NaN;
const iso = ms => new Date(ms).toISOString();

/// Recalculates the end of every post still running with the given duration. Writes only the documents whose end changes (and stores
/// ownEndsAt the first time, so a longer duration later can give back the time the vendor chose). Returns how many changed.
async function recapLivePosts(db, durationMs, now = Date.now()) {
  const writes = [];
  const plan = (ref, changes) => writes.push([ref, changes]);

  // Exclusive items that are live.
  for (const doc of (await db.collection('products').where('isExclusive', '==', true).get()).docs) {
    const item = doc.data();
    if (item.active !== true) continue;
    const posted = firstMillis(item.postedAt, item.createdAt);
    const own = firstMillis(item.ownEndsAt, item.expiresAt);
    if (!Number.isFinite(posted) || !Number.isFinite(own) || own <= now) continue;
    const end = cappedEnd(posted, durationMs, own);
    if (end !== millisOf(item.expiresAt) || end !== millisOf(item.endsAt)) plan(doc.ref, {expiresAt: iso(end), endsAt: iso(end), ownEndsAt: iso(own)});
  }
  // Today's Offers boxes and Vendor Offers (Timestamps).
  // Today's Offers boxes are not capped any more: they stay live while the vendor's plan runs (owner, 13 Nov 2026).
  for (const [collection, postedOf] of [['vendorOffers', o => firstMillis(o.postedAt, o.createdAt)]]) {
    for (const doc of (await db.collection(collection).where('endsAt', '>', Timestamp.fromMillis(now)).get()).docs) {
      const post = doc.data();
      if (collection === 'vendorOffers' && !['live', 'pending'].includes(post.status)) continue;
      const posted = postedOf(post);
      const own = firstMillis(post.ownEndsAt, post.endsAt);
      if (!Number.isFinite(posted) || !Number.isFinite(own)) continue;
      const end = cappedEnd(posted, durationMs, own);
      if (end !== millisOf(post.endsAt) || post.ownEndsAt === undefined) plan(doc.ref, {endsAt: Timestamp.fromMillis(end), ownEndsAt: Timestamp.fromMillis(own)});
    }
  }
  // Vendor ads (the admin's own ads have no source 'vendor' and are not touched).
  for (const doc of (await db.collection('ads').where('source', '==', 'vendor').get()).docs) {
    const ad = doc.data();
    const posted = millisOf(ad.startsAt);
    const own = firstMillis(ad.ownEndsAt, ad.endsAt);
    if (!Number.isFinite(posted) || !Number.isFinite(own) || own <= now || millisOf(ad.endsAt) <= now) continue;
    const end = cappedEnd(posted, durationMs, own);
    if (end !== millisOf(ad.endsAt) || ad.ownEndsAt === undefined) plan(doc.ref, {endsAt: iso(end), ownEndsAt: iso(own)});
  }

  for (let i = 0; i < writes.length; i += 400) {
    const batch = db.batch();
    for (const [ref, changes] of writes.slice(i, i + 400)) batch.update(ref, changes);
    await batch.commit();
  }
  return writes.length;
}

/// Runs recapLivePosts once whenever the admin's duration differs from the one last applied (also the first time after this rule
/// was deployed). Two document reads when nothing changed.
async function applyPostDurationIfChanged(db, now = Date.now()) {
  const durationMs = await readPostDurationMs(db);
  const state = db.collection('_jobState').doc('postDuration');
  const last = (await state.get()).data() || {};
  // Once after the "prices never run out" rule (owner, 16 Nov 2026): the items' old price ends go (same state document, no extra read).
  const pricesCleared = last.priceRule === PRICE_RULE ? 0 : await require('./vendor-prices').clearOldPriceEnds(db);
  if (last.durationMs === durationMs && last.priceRule === PRICE_RULE) return {changed: 0, durationMs};
  const changed = last.durationMs === durationMs ? 0 : await recapLivePosts(db, durationMs, now);
  await state.set({durationMs, priceRule: PRICE_RULE, appliedAt: Timestamp.fromMillis(now), changed, pricesCleared});
  return {changed, durationMs, pricesCleared};
}

/// The price rule applied (vendor-prices.js): prices never run out.
const PRICE_RULE = 'never-expire';

module.exports = {
  POST_DURATIONS, DEFAULT_POST_DURATION, DAY_MS,
  postDurationKey, postDurationMs, readPostDurationMs, cappedEnd, recapLivePosts, applyPostDurationIfChanged,
};
