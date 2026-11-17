'use strict';
// Offer alerts: what this module reads and writes.
//   vendorOffers/<id>          read; the module writes only its own fields on it: alertClaimedAt, alertStatus, alertSentAt, alertRadiusKm
//   shops/<shopId>             read: the shop's latitude / longitude (the centre of the circle)
//   notificationSubscribers    read: who has notifications on, and their last known latitude / longitude
//   vendorOfferAlerts/<vendor> {lastAt}: the one-alert-a-day limit per vendor; /sent/<offerId> {reached, radiusKm, sentAt} for the admin
//   settings/business          read: vendorOfferAlertsEnabled (Push notifications switch, on unless switched off)
//   vendorPremium/<vendor>     read: only paid vendors (Silver, Gold, Premium: a running plan) may alert, within the plan's radiusKm
// The push itself goes through the [send] the caller passes in (notifications.js send in production), which checks the customer's
// devices, never sends the same alert twice and counts it for the admin's push centre.
const {Timestamp} = require('firebase-admin/firestore');
const {wantsAlert, planKm, placeOf, reach, alertCopy, vendorMayAlert} = require('./rules');

const PAGE = 300;
const PARALLEL = 25;

async function* enabledSubscribers(db) {
  let cursor;
  const query = db.collection('notificationSubscribers').where('enabled', '==', true).orderBy('__name__');
  do {
    const page = await (cursor ? query.startAfter(cursor) : query).limit(PAGE).get();
    for (const doc of page.docs) yield doc;
    cursor = page.size === PAGE ? page.docs.at(-1) : null;
  } while (cursor);
}

/// Claims the offer's alert once and sends it. Returns {status, reached}. Safe to call again: a claimed offer is never alerted twice.
async function releaseAlert(db, offerId, send, now = Date.now()) {
  const ref = db.collection('vendorOffers').doc(offerId);
  const settings = (await db.collection('settings').doc('business').get()).data() || {};
  const claim = await db.runTransaction(async tx => {
    const offer = (await tx.get(ref)).data();
    if (!offer || offer.status !== 'live' || !wantsAlert(offer) || offer.alertClaimedAt) return {status: 'not-due'};
    if ((offer.endsAt?.toMillis?.() ?? 0) <= now) return {status: 'not-due'};
    const at = Timestamp.fromMillis(now);
    if (settings.vendorOfferAlertsEnabled === false) {
      tx.update(ref, {alertClaimedAt: at, alertStatus: 'disabled'});
      return {status: 'disabled'};
    }
    const premium = (await tx.get(db.collection('vendorPremium').doc(offer.vendorId))).data();
    if (premium?.active !== true || (premium.endsAt?.toMillis?.() ?? 0) <= now) {
      tx.update(ref, {alertClaimedAt: at, alertStatus: 'paid-only'});
      return {status: 'paid-only'};
    }
    const limitRef = db.collection('vendorOfferAlerts').doc(offer.vendorId);
    const lastAt = (await tx.get(limitRef)).data()?.lastAt?.toMillis?.() ?? 0;
    if (!vendorMayAlert(lastAt, now)) {
      tx.update(ref, {alertClaimedAt: at, alertStatus: 'daily-limit'});
      return {status: 'daily-limit'};
    }
    // The alert reaches the vendor's plan km; it is written on the offer so the vendor app can say how far it went.
    const radiusKm = planKm(premium);
    tx.update(ref, {alertClaimedAt: at, alertStatus: 'sending', alertRadiusKm: radiusKm});
    tx.set(limitRef, {vendorId: offer.vendorId, lastAt: at, offerId}, {merge: true});
    return {status: 'claimed', offer: {...offer, alertRadiusKm: radiusKm}};
  });
  if (claim.status !== 'claimed') return {status: claim.status, reached: 0};
  const {offer} = claim;
  const shop = placeOf((await db.collection('shops').doc(offer.shopId).get()).data());
  if (!shop) {
    await ref.update({alertStatus: 'no-shop-location'});
    return {status: 'no-shop-location', reached: 0};
  }
  let reached = 0;
  let batch = [];
  const flush = async () => {
    const results = await Promise.all(batch.map(({uid, km}) =>
      send(uid, `vendorOfferAlert:${offerId}`, alertCopy(offer, km), {type: 'shopOffer', shopId: offer.shopId, offerId}).catch(error => {
        console.warn('Offer alert delivery failed', {offerId, error: String(error).slice(0, 120)});
        return 'failed';
      })));
    reached += results.filter(status => status === 'sent').length;
    batch = [];
  };
  for await (const subscriber of enabledSubscribers(db)) {
    if (subscriber.id === offer.vendorId) continue;
    const km = reach(shop, subscriber.data(), offer.alertRadiusKm);
    if (km === null) continue;
    batch.push({uid: subscriber.id, km});
    if (batch.length >= PARALLEL) await flush();
  }
  if (batch.length) await flush();
  // How many were reached is kept for the admin only (vendorOfferAlerts is admin-read): a live offer is public, and the vendor app
  // shows that the alert went, never a number.
  const sentAt = Timestamp.fromMillis(Date.now());
  await ref.update({alertStatus: 'sent', alertSentAt: sentAt});
  await db.collection('vendorOfferAlerts').doc(offer.vendorId).collection('sent').doc(offerId).set({offerId, radiusKm: offer.alertRadiusKm, reached, sentAt});
  return {status: 'sent', reached};
}

module.exports = {releaseAlert};
