'use strict';
// Vendor ads. A vendor submits an ad (or a change to one of their ads) from the vendor app; NOTHING goes live by itself: no automatic
// publishing and no automatic scanner. Every new ad and every change, including a new photo, waits in adSubmissions as 'pending' until the
// admin approves it by hand. While a change is pending, the approved ad on the site keeps showing its old photo and text.
//
//   submitVendorAd      vendor -> adSubmissions/<id> (pending)
//   decideVendorAd      admin  -> approve (creates or updates ads/<id>) or reject with a reason
//   removeVendorAd      admin  -> takes any vendor ad off the site at any time (kept in the admin list as Rejected)
//   setAdSummary        vendor -> daily / weekly / off summary for one of their ads
//   sendAdSummaries     every morning -> the chosen summaries, as notices in the vendor app (and a push when the vendor has them on)
// The vendor is told of every decision in vendorNotices.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {requireAdminSession} = require('./admin-session');
const {OPTIONS, areaFullMessage} = require('./radius');

const PLANS = {normal: {rounds: 1, seconds: 5}, silver: {rounds: 2, seconds: 7}, gold: {rounds: 3, seconds: 10}};
const CONTENT = ['image', 'text', 'imageText'];
const ACTIONS = ['', 'call', 'whatsapp', 'shop', 'link'];
const MAX_PENDING = 5;
const dayKey = (now = Date.now()) => new Date(now + 19800000).toISOString().slice(0, 10);

function text(value, max, label, {required = false} = {}) {
  const v = value === undefined || value === null ? '' : String(value).trim();
  if (required && !v) throw Error(`Enter ${label}.`);
  if (v.length > max) throw Error(`${label} is too long (at most ${max} characters).`);
  return v;
}

/// Checks what a vendor sent and returns the clean fields. Throws an Error with a plain message for the vendor.
function validateSubmission(data = {}, uid) {
  const contentType = CONTENT.includes(data.contentType) ? data.contentType : 'image';
  const plan = PLANS[data.package] ? data.package : 'normal';
  const durationDays = Math.round(Number(data.durationDays));
  if (!Number.isInteger(durationDays) || durationDays < 1 || durationDays > 365) throw Error('Choose how many days the ad should run (1 to 365).');
  const imageUrl = text(data.imageUrl, 1000, 'the picture link');
  if (imageUrl) {
    // Only a picture the vendor uploaded to their own folder in this project's storage.
    const ok = /^https:\/\/firebasestorage\.googleapis\.com\/v0\/b\/[^/]+\/o\/vendorProducts%2F/.test(imageUrl) && imageUrl.includes(`vendorProducts%2F${uid}%2F`);
    if (!ok) throw Error('Upload the picture again; it has to come from your own uploads.');
  }
  const title = text(data.title, 80, 'the title');
  const body = text(data.text, 300, 'the text');
  if (contentType !== 'text' && !imageUrl) throw Error('Add a picture.');
  if (contentType !== 'image' && !title && !body) throw Error('Add a title or some text.');
  if (contentType === 'text' && !title) throw Error('Add a title.');
  const tapAction = ACTIONS.includes(data.tapAction) ? data.tapAction : '';
  const tapValue = text(data.tapValue, 300, 'the tap target');
  if ((tapAction === 'call' || tapAction === 'whatsapp') && tapValue.replace(/\D/g, '').length < 10) throw Error('Enter a 10-digit phone number.');
  if (tapAction === 'link' && !tapValue.startsWith('https://')) throw Error('A link must start with https://');
  const color = (v, label) => {
    const c = text(v, 9, label);
    if (c && !/^#[0-9a-fA-F]{6,8}$/.test(c)) throw Error(`${label} must be a colour like #FFAA00.`);
    return c;
  };
  return {
    contentType, imageUrl, title, text: body, package: plan, durationDays, tapAction, tapValue,
    textColor: color(data.textColor, 'The text colour'), backgroundColor: color(data.backgroundColor, 'The background colour'),
    badge: text(data.badge, 20, 'the badge'), coupon: text(data.coupon, 20, 'the coupon code'),
  };
}

const CONTENT_FIELDS = ['contentType', 'imageUrl', 'title', 'text', 'tapAction', 'tapValue', 'textColor', 'backgroundColor', 'badge', 'coupon'];

async function notice(db, vendorId, type, title, body, extra = {}) {
  await db.collection('vendorNotices').add({vendorId, type, title, body, ...extra, createdAt: FieldValue.serverTimestamp()});
  try {
    const {_internal} = require('./notifications');
    await _internal.send(vendorId, `ad:${type}:${extra.submissionId || extra.adId || ''}:${Date.now()}`, {title, body}, {type: 'vendorAd', ...Object.fromEntries(Object.entries(extra).map(([k, v]) => [k, String(v)]))});
  } catch (error) { console.warn('Vendor notice push failed', error.message); }
}

/// Vendor sends an ad (or, with adId, a change to one of their own ads). Returns {submissionId, status: 'pending'}.
async function submitAd(db, uid, data, now = Date.now()) {
  const vendor = (await db.collection('vendors').doc(uid).get()).data();
  if (!vendor || vendor.status !== 'approved') throw Error('Only an approved vendor can submit ads.');
  if (vendor.suspended === true) throw Error('Your account is suspended.');
  const fields = validateSubmission(data, uid);
  let adId = null;
  if (data.adId !== undefined && data.adId !== null && data.adId !== '') {
    if (typeof data.adId !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(data.adId)) throw Error('That ad was not found.');
    const ad = (await db.collection('ads').doc(data.adId).get()).data();
    if (!ad || ad.vendorId !== uid) throw Error('That ad was not found.');
    adId = data.adId;
  }
  const pending = await db.collection('adSubmissions').where('vendorId', '==', uid).where('status', '==', 'pending').get();
  if (pending.size >= MAX_PENDING) throw Error(`You already have ${MAX_PENDING} ads waiting for approval. Wait for a decision first.`);
  if (adId && pending.docs.some(d => d.data().adId === adId)) throw Error('A change to this ad is already waiting for approval.');
  const ref = db.collection('adSubmissions').doc();
  await ref.set({
    ...fields, vendorId: uid, vendorCode: vendor.vendorCode || '', shopName: vendor.shopName || vendor.name || '', shopId: vendor.shopId || uid,
    kind: adId ? 'change' : 'new', adId, status: 'pending', submittedAt: Timestamp.fromMillis(now),
  });
  return {submissionId: ref.id, status: 'pending'};
}

/// Admin decides. Approving a new ad creates it; approving a change updates the ad on the site only now.
async function decideAd(db, data, now = Date.now()) {
  const {submissionId, approved, reason = ''} = data || {};
  const radiusKm = data?.radiusKm === undefined || data?.radiusKm === null || data?.radiusKm === 0 ? 0 : Number(data.radiusKm);
  if (radiusKm !== 0 && !OPTIONS.includes(radiusKm)) throw Error('Choose a radius from the list: 5, 10, 25, 50 or 100 km.');
  if (typeof submissionId !== 'string' || typeof approved !== 'boolean') throw Error('Provide the ad and the decision.');
  const ref = db.collection('adSubmissions').doc(submissionId);
  const submission = (await ref.get()).data();
  if (!submission) throw Error('That submission was not found.');
  if (submission.status !== 'pending') throw Error('Only a pending ad can be approved or rejected.');
  const why = String(reason).trim().slice(0, 300);
  if (!approved) {
    if (!why) throw Error('Give the vendor a reason for rejecting.');
    await ref.update({status: 'rejected', reason: why, decidedAt: Timestamp.fromMillis(now)});
    await notice(db, submission.vendorId, 'rejected', 'Your ad was not approved', `${submission.title || 'Your ad'}: ${why}`, {submissionId});
    return {status: 'rejected'};
  }
  const content = Object.fromEntries(CONTENT_FIELDS.map(k => [k, submission[k] ?? '']));
  let adId = submission.adId;
  if (submission.kind === 'change' && adId) {
    await db.collection('ads').doc(adId).update({...content, status: 'approved', reason: FieldValue.delete(), updatedAt: Timestamp.fromMillis(now)});
  } else {
    adId = `vad${now}${Math.floor(Math.random() * 1000)}`;
    const plan = PLANS[submission.package] || PLANS.normal;
    const vendor = (await db.collection('vendors').doc(submission.vendorId).get()).data() || {};
    const startsAt = new Date(now).toISOString(), endsAt = new Date(now + submission.durationDays * 86400000).toISOString();
    // The radius is centred on the vendor's registered shop location; the area may not already be full.
    let circle = {};
    if (radiusKm) {
      const lat = Number(vendor.latitude), lng = Number(vendor.longitude);
      if (!Number.isFinite(lat) || !Number.isFinite(lng) || (lat === 0 && lng === 0)) throw Error('This vendor has no saved shop location, so a radius cannot be set. Approve it without a radius or add the location first.');
      circle = {radiusKm, radiusShopId: submission.shopId, radiusLat: lat, radiusLng: lng};
      const max = Math.round(Number((await db.collection('settings').doc('adsConfig').get()).data()?.maxPerArea)) || 0;
      const others = (await db.collection('ads').get()).docs.map(d => ({id: d.id, ...d.data()}));
      const full = areaFullMessage({id: adId, startsAt, endsAt, ...circle}, others, max);
      if (full) throw Error(full);
    }
    await db.collection('ads').doc(adId).set({
      ...content, ...circle, status: 'approved', active: true, vendorId: submission.vendorId, vendorCode: submission.vendorCode, shopName: submission.shopName, shopId: submission.shopId,
      package: submission.package, rounds: plan.rounds, seconds: plan.seconds, maxPerDay: 0,
      startsAt, endsAt,
      order: Math.floor(now / 1000), source: 'vendor',
    });
    await db.collection('adsPrivate').doc(adId).set({paid: false, contactPerson: vendor.name || '', notes: 'Submitted from the vendor app'}, {merge: true});
  }
  await ref.update({status: 'approved', adId, decidedAt: Timestamp.fromMillis(now)});
  await notice(db, submission.vendorId, 'approved', 'Your ad is live', `${submission.title || 'Your ad'} was approved.`, {submissionId, adId});
  return {status: 'approved', adId};
}

/// Admin takes a vendor's ad off the site at any time. It stays in the admin list as Rejected, with the reason.
async function removeAd(db, data, now = Date.now()) {
  const {adId, reason = ''} = data || {};
  if (typeof adId !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(adId)) throw Error('Provide the ad.');
  const ref = db.collection('ads').doc(adId);
  const ad = (await ref.get()).data();
  if (!ad) throw Error('That ad was not found.');
  const why = String(reason).trim().slice(0, 300);
  await ref.update({status: 'rejected', active: false, reason: why, removedAt: Timestamp.fromMillis(now)});
  if (ad.vendorId) await notice(db, ad.vendorId, 'removed', 'Your ad was removed', `${ad.title || 'Your ad'}${why ? `: ${why}` : ''}`, {adId});
  return {status: 'removed'};
}

async function setSummary(db, uid, data) {
  const {adId, mode} = data || {};
  if (typeof adId !== 'string' || !['daily', 'weekly', 'off'].includes(mode)) throw Error('Choose daily, weekly or off.');
  const ad = (await db.collection('ads').doc(adId).get()).data();
  if (!ad || ad.vendorId !== uid) throw Error('That ad was not found.');
  await db.collection('ads').doc(adId).update({summary: mode});
  return {mode};
}

/// The numbers for the last [days] days ending yesterday (India), added up from the day records.
async function periodTotals(db, adId, days, now) {
  const total = {views: 0, unique: 0, taps: 0, seconds: 0, missed: 0};
  for (let i = 1; i <= days; i++) {
    const doc = (await db.collection('adStatsDaily').doc(`${adId}~${dayKey(now - i * 86400000)}`).get()).data();
    if (!doc) continue;
    for (const k of Object.keys(total)) total[k] += Number(doc[k]) || 0;
  }
  return total;
}

/// Sends the daily summaries every day and the weekly ones on Mondays (India). Returns how many notices were written.
async function sendSummaries(db, now = Date.now()) {
  const monday = new Date(now + 19800000).getUTCDay() === 1;
  const chosen = await db.collection('ads').where('summary', 'in', monday ? ['daily', 'weekly'] : ['daily']).get();
  let sent = 0;
  for (const doc of chosen.docs) {
    const ad = doc.data();
    if (!ad.vendorId || ad.status === 'rejected') continue;
    const weekly = ad.summary === 'weekly';
    const t = await periodTotals(db, doc.id, weekly ? 7 : 1, now);
    const body = `${ad.title || 'Your ad'}: ${t.views} views, ${t.unique} people, ${t.taps} taps, ${t.seconds} seconds on screen${t.missed ? `, ${t.missed} missed` : ''}.`;
    await notice(db, ad.vendorId, 'summary', weekly ? 'Your ad this week' : 'Your ad yesterday', body, {adId: doc.id, period: weekly ? 'week' : 'day', ...t});
    sent++;
  }
  return sent;
}

const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};
const fail = error => { throw new HttpsError('failed-precondition', error.message); };
function requireVerified(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true) throw new HttpsError('permission-denied', 'Verify your email first.');
  return request.auth.uid;
}
async function requireAdmin(request) {
  const uid = requireVerified(request);
  if (request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(uid);
}
exports.submitVendorAd = onCall(options, async request => {
  const uid = requireVerified(request);
  try { return await submitAd(getFirestore(), uid, request.data || {}); } catch (error) { return fail(error); }
});
exports.decideVendorAd = onCall(options, async request => {
  await requireAdmin(request);
  try { return await decideAd(getFirestore(), request.data || {}); } catch (error) { return fail(error); }
});
exports.removeVendorAd = onCall(options, async request => {
  await requireAdmin(request);
  try { return await removeAd(getFirestore(), request.data || {}); } catch (error) { return fail(error); }
});
exports.setAdSummary = onCall(options, async request => {
  const uid = requireVerified(request);
  try { return await setSummary(getFirestore(), uid, request.data || {}); } catch (error) { return fail(error); }
});
exports.sendAdSummaries = onSchedule({schedule: '30 8 * * *', timeZone: 'Asia/Kolkata', region: 'asia-south1', maxInstances: 1, timeoutSeconds: 300}, async () => {
  await sendSummaries(getFirestore());
});
exports._ads = {validateSubmission, submitAd, decideAd, removeAd, setSummary, sendSummaries, PLANS};
