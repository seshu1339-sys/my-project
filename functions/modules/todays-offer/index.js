'use strict';
const {requireRole, isAdminToken} = require('../../role-auth');
// Today's Offer module: a paid vendor's Today's Offers boxes (see store.js). It knows the plan only through vendorPremium, never plans
// or payments.
//
//   submitTodaysOffer   vendor   -> one of their items, the offer price, 1 week to 3 months (and a box); live at once after the check
//   removeMyTodaysOffer vendor   -> takes one of their boxes down
//   removeTodaysOffer   admin    -> takes one offer down
//   setTodaysOfferHidden admin   -> hides an offer, or shows it again (also an offer whose photo check could not run)
//   todaysOfferOnPlanChange trigger -> vendorPremium/<uid> changed: the boxes follow the plan (hidden when it ends, back on renewal)
//   clearTodaysOffers   schedule -> removes ended offers and their photos
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {anthropicKey} = require('../../photo-safety');
// The schedule is in functions/scheduled-jobs.js (one 15-minute and one hourly job for all).
const {task} = require('../../task');
const {getFirestore} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {requireAdminSession} = require('../../admin-session');
const {submitOffer, removeOwnOffer, clearEnded, onPlanChange, setOfferHidden, removeOffer} = require('./store');

const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};
const fail = error => { throw new HttpsError('failed-precondition', error.message); };
function requireVerified(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  requireRole(request);
  return request.auth.uid;
}

exports.submitTodaysOffer = onCall({...options, memory: '512MiB', secrets: [anthropicKey]}, async request => {
  const uid = requireVerified(request);
  try { return await submitOffer(getFirestore(), getStorage().bucket(), uid, request.data || {}); } catch (error) { return fail(error); }
});
exports.removeMyTodaysOffer = onCall(options, async request => {
  const uid = requireVerified(request);
  try { return await removeOwnOffer(getFirestore(), getStorage().bucket(), uid, request.data || {}); } catch (error) { return fail(error); }
});
exports.removeTodaysOffer = onCall(options, async request => {
  const uid = requireVerified(request);
  if (!isAdminToken(request.auth.token)) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(uid);
  try { return await removeOffer(getFirestore(), getStorage().bucket(), request.data?.offerId ?? request.data?.vendorId); } catch (error) { return fail(error); }
});
exports.setTodaysOfferHidden = onCall(options, async request => {
  const uid = requireVerified(request);
  if (!isAdminToken(request.auth.token)) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(uid);
  try { return await setOfferHidden(getFirestore(), request.data?.offerId, request.data?.hidden); } catch (error) { return fail(error); }
});
exports.todaysOfferOnPlanChange = onDocumentWritten({document: 'vendorPremium/{uid}', region: 'asia-south1', maxInstances: 3}, async event => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  const same = key => JSON.stringify(before?.[key] ?? null) === JSON.stringify(after?.[key] ?? null);
  if (before && after && ['active', 'endsAt', 'offerBoxes', 'tier', 'planName'].every(same)) return;
  await onPlanChange(getFirestore(), event.params.uid, after);
});
exports.clearTodaysOffers = task(async () => {
  await clearEnded(getFirestore(), getStorage().bucket());
});
