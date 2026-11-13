'use strict';
// Shop and service-provider star ratings (owner, 13 Nov 2026). A signed-in customer gives a shop or a provider 1 to 5 stars, a name
// and an optional short comment; one rating per customer per shop (rating again replaces it). The average, the count and the three
// latest comments are written on the shop (shops/<id>) or on the provider's listings (services where providerId), so the search
// list and the maps show them without extra reads. The vendor or provider reads their own ratings; the admin removes fake ones.
// No phone number is ever stored, and the rating's id is made from a hash of the customer's account, so nobody sees who it was.
//
//   rateShop           customer -> {kind: 'shop', shopId} | {kind: 'provider', listingId} + {stars, name, comment}
//   removeShopRating   admin    -> {ratingId}
//
//   shopRatings/<targetKey>_<hash>  {targetKey, kind, targetId, name, stars, comment, hidden, at, updatedAt}
// targetKey is "shop_<shopId>" or "provider_<providerId>". Public read of the ratings that are not hidden.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {createHash} = require('node:crypto');
const {requireRole, isAdminToken} = require('../../role-auth');
const {requireAdminSession} = require('../../admin-session');

const options = {region: 'us-central1', maxInstances: 5, invoker: 'public'};
const ID = /^[A-Za-z0-9_-]{1,128}$/;
const RECENT = 3;
const fail = (message, code = 'invalid-argument') => { throw new HttpsError(code, message); };
const raterHash = uid => createHash('sha256').update(`rating:${uid}`).digest('hex').slice(0, 24);

/// What is rated: {targetKey, kind, targetId}.
async function ratedTarget(db, data) {
  if (data.kind === 'shop') {
    if (typeof data.shopId !== 'string' || !ID.test(data.shopId)) fail('Choose the shop.');
    if (!(await db.collection('shops').doc(data.shopId).get()).exists) fail('Shop not found.', 'not-found');
    return {targetKey: `shop_${data.shopId}`, kind: 'shop', targetId: data.shopId};
  }
  if (data.kind === 'provider') {
    if (typeof data.listingId !== 'string' || !ID.test(data.listingId)) fail('Choose the service.');
    const listing = (await db.collection('services').doc(data.listingId).get()).data();
    const providerId = listing?.providerId;
    if (!providerId) fail('Service provider not found.', 'not-found');
    return {targetKey: `provider_${providerId}`, kind: 'provider', targetId: providerId};
  }
  fail('Choose a shop or a service provider.');
}

/// Checks the stars, name and comment.
function cleanRating(data) {
  const stars = Number(data.stars);
  if (!Number.isInteger(stars) || stars < 1 || stars > 5) fail('Choose 1 to 5 stars.');
  const name = String(data.name ?? '').replace(/\s+/g, ' ').trim();
  if (name.length < 2 || name.length > 40) fail('Enter your name (2 to 40 letters).');
  // A phone number is never kept: a long run of digits in the name or comment is refused.
  const comment = String(data.comment ?? '').replace(/\s+/g, ' ').trim();
  if (comment.length > 300) fail('Write at most 300 letters.');
  if (/\d{7,}/.test(`${name} ${comment}`.replace(/[\s-]/g, ''))) fail('Do not write phone numbers in a rating.');
  return {stars, name, comment};
}

/// The average, count and latest comments of one target, written where the apps read them.
async function refreshSummary(db, {targetKey, kind, targetId}) {
  const ratings = (await db.collection('shopRatings').where('targetKey', '==', targetKey).where('hidden', '==', false).get()).docs.map(d => d.data());
  const count = ratings.length;
  const avg = count ? Math.round((ratings.reduce((sum, r) => sum + r.stars, 0) / count) * 10) / 10 : 0;
  const recent = ratings.filter(r => r.comment).sort((a, b) => (b.updatedAt?.toMillis?.() ?? 0) - (a.updatedAt?.toMillis?.() ?? 0)).slice(0, RECENT)
    .map(r => ({name: r.name, stars: r.stars, comment: r.comment}));
  const summary = count ? {ratingAvg: avg, ratingCount: count, ratingRecent: recent} : {ratingAvg: FieldValue.delete(), ratingCount: FieldValue.delete(), ratingRecent: FieldValue.delete()};
  if (kind === 'shop') {
    const ref = db.collection('shops').doc(targetId);
    if ((await ref.get()).exists) await ref.update(summary);
  } else {
    const listings = await db.collection('services').where('providerId', '==', targetId).get();
    const batch = db.batch();
    listings.docs.forEach(doc => batch.update(doc.ref, summary));
    if (!listings.empty) await batch.commit();
  }
  return {avg, count};
}

/// One customer's rating (a new one, or a change of their own). Returns the new {avg, count}.
async function rate(db, uid, data = {}, now = Date.now()) {
  const target = await ratedTarget(db, data);
  const rating = cleanRating(data);
  const ref = db.collection('shopRatings').doc(`${target.targetKey}_${raterHash(uid)}`);
  const at = Timestamp.fromMillis(now);
  await db.runTransaction(async tx => {
    const current = (await tx.get(ref)).data();
    if (current?.hidden === true) fail('Your rating of this place was removed by the Support Team.', 'failed-precondition');
    tx.set(ref, {...target, ...rating, hidden: false, updatedAt: at, at: current?.at ?? at});
  });
  return refreshSummary(db, target);
}

/// The admin removes a (fake) rating: it is kept but hidden, and the average is worked out again.
async function remove(db, adminUid, ratingId, now = Date.now()) {
  if (typeof ratingId !== 'string' || !/^[A-Za-z0-9_-]{1,200}$/.test(ratingId)) fail('Choose a rating.');
  const ref = db.collection('shopRatings').doc(ratingId);
  const rating = (await ref.get()).data();
  if (!rating) fail('Rating not found.', 'not-found');
  await ref.update({hidden: true, removedBy: adminUid, removedAt: Timestamp.fromMillis(now)});
  return refreshSummary(db, rating);
}

exports.rateShop = onCall(options, async request => {
  const uid = requireRole(request, ['user']);
  return rate(getFirestore(), uid, request.data || {});
});

exports.removeShopRating = onCall(options, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  requireRole(request);
  if (!isAdminToken(request.auth.token)) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
  return remove(getFirestore(), request.auth.uid, request.data?.ratingId);
});

exports._ratings = {rate, remove, cleanRating, refreshSummary, raterHash};
