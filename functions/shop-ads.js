'use strict';
// Ads for a vendor's shop in the Right Side Ad Boxes of the website (settings/rightAdBoxes, lib/domain/right_boxes.dart).
// For now an ad is arranged offline: the vendor ticks "Ad for your shop", the office calls them, takes the payment and the photo, uploads
// the photo into a box and links the box to the vendor here.
//   setAdInterest         vendor -> "I want an ad for my shop" ticked or unticked (vendors/<uid>.adInterest); the admin sees who wants one
//   assignRightBoxVendor  admin  -> links a box to a vendor (a new ad starts, its views from 0) or unlinks it (the ad ends)
// The ad is rightBoxAds/<adId> (written only here; the admin and the vendor read it), and only its id goes into the public settings
// (box<n>AdId), never who the vendor is. The customer site reports the views of a box that has a photo and an ad id through
// trackAdEvents (functions/ad-tracking.js), so the totals are in adStats/<adId>, which the vendor reads: the total views since the ad
// started, not who is watching now.
// Payment: every ad is payment 'offline' today. An in-app payment would be another payment value and its own callable that starts the
// ad once paid, without changing the ad record or the counting.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {requireAdminSession} = require('./admin-session');
const db = getFirestore();
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};

const RIGHT_BOX_AD_PREFIX = 'rbox-';
// The same numbers as lib/domain/right_boxes.dart (defaultRightBoxCount, maxRightBoxCount).
const DEFAULT_BOXES = 15;
const MAX_BOXES = 60;

function requireUser(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true) throw new HttpsError('permission-denied', 'Verify your email first.');
  return request.auth.uid;
}
async function requireAdmin(request) {
  requireUser(request);
  if (request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
}

/// How many boxes the admin has (settings/rightAdBoxes.count, 15 when not set).
function boxCount(settings = {}) {
  const n = Number(settings.count);
  return Number.isFinite(n) ? Math.max(0, Math.min(MAX_BOXES, Math.round(n))) : DEFAULT_BOXES;
}

const isRightBoxAd = adId => typeof adId === 'string' && adId.startsWith(RIGHT_BOX_AD_PREFIX);

/// A message in the vendor app (and a push when the vendor has them on), like the vendor-ads.js notices.
async function notice(vendorId, title, body, adId) {
  await db.collection('vendorNotices').add({vendorId, type: 'shopAd', title, body, adId, createdAt: FieldValue.serverTimestamp()});
  try {
    const {_internal} = require('./notifications');
    await _internal.send(vendorId, `shopAd:${adId}`, {title, body}, {type: 'vendorAd', adId});
  } catch (error) { console.warn('Shop ad notice push failed', error.message); }
}

exports.setAdInterest = onCall(options, async request => {
  const uid = requireUser(request);
  const interested = request.data?.interested;
  if (typeof interested !== 'boolean') throw new HttpsError('invalid-argument', 'Say whether you want an ad for your shop.');
  const ref = db.collection('vendors').doc(uid);
  const vendor = (await ref.get()).data();
  if (!vendor || vendor.status !== 'approved') throw new HttpsError('permission-denied', 'Your vendor application must be approved before you can use business features.');
  await ref.set({adInterest: interested, adInterestAt: FieldValue.serverTimestamp()}, {merge: true});
  return {interested};
});

exports.assignRightBoxVendor = onCall(options, async request => {
  await requireAdmin(request);
  const box = request.data?.box;
  const vendorId = request.data?.vendorId || '';
  if (!Number.isInteger(box) || box < 1 || box > MAX_BOXES) throw new HttpsError('invalid-argument', 'Choose a Right Side Ad Box.');
  if (typeof vendorId !== 'string' || (vendorId && !/^[A-Za-z0-9_-]{1,128}$/.test(vendorId))) throw new HttpsError('invalid-argument', 'Choose a vendor.');
  const settingsRef = db.collection('settings').doc('rightAdBoxes');
  const field = `box${box}AdId`;
  const out = await db.runTransaction(async tx => {
    const settings = (await tx.get(settingsRef)).data() || {};
    const currentId = isRightBoxAd(settings[field]) ? settings[field] : '';
    const currentRef = currentId ? db.collection('rightBoxAds').doc(currentId) : null;
    const current = currentRef ? (await tx.get(currentRef)).data() : null;
    // The same vendor again: the ad goes on (a new photo for the same shop does not restart the views).
    if (vendorId && current?.status === 'live' && current.vendorId === vendorId) return {adId: currentId, started: false};
    let vendor = null;
    if (vendorId) {
      if (box > boxCount(settings)) throw new HttpsError('invalid-argument', `There is no Right Side Ad Box ${box}.`);
      vendor = (await tx.get(db.collection('vendors').doc(vendorId))).data();
      if (!vendor || vendor.status !== 'approved') throw new HttpsError('failed-precondition', 'Choose an approved vendor.');
    }
    if (current?.status === 'live') tx.update(currentRef, {status: 'ended', endedAt: FieldValue.serverTimestamp(), endedBy: request.auth.uid});
    if (!vendor) {
      tx.set(settingsRef, {[field]: FieldValue.delete()}, {merge: true});
      return {adId: null, ended: current?.status === 'live' ? currentId : null};
    }
    const adId = `${RIGHT_BOX_AD_PREFIX}${box}-${db.collection('rightBoxAds').doc().id}`;
    tx.set(db.collection('rightBoxAds').doc(adId), {
      adId, box, vendorId, vendorName: String(vendor.name || ''), vendorCode: String(vendor.vendorCode || ''), shopId: vendor.shopId || vendorId,
      status: 'live', payment: 'offline', startedAt: FieldValue.serverTimestamp(), startedBy: request.auth.uid,
    });
    tx.set(settingsRef, {[field]: adId}, {merge: true});
    return {adId, started: true};
  });
  if (out.started) await notice(vendorId, 'Your shop ad is live', 'Your ad is on the website now, in the boxes on the right side. The vendor app shows how many people have seen it.', out.adId);
  return out;
});

exports._shopAds = {boxCount, isRightBoxAd, RIGHT_BOX_AD_PREFIX, DEFAULT_BOXES, MAX_BOXES};
