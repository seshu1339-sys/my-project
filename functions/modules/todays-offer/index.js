'use strict';
// Today's Offer module: a Premium vendor's single offer (see store.js). It knows Premium only through vendorPremium, never plans or payments.
//
//   submitTodaysOffer   vendor   -> photo link, price, 24 or 48 hours; live at once after the automatic check
//   removeTodaysOffer   admin    -> takes one offer down
//   clearTodaysOffers   schedule -> removes ended offers and their photos
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {getFirestore} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {requireAdminSession} = require('../../admin-session');
const {submitOffer, clearEnded, removeOffer} = require('./store');

const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};
const fail = error => { throw new HttpsError('failed-precondition', error.message); };
function requireVerified(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true) throw new HttpsError('permission-denied', 'Verify your email first.');
  return request.auth.uid;
}

exports.submitTodaysOffer = onCall(options, async request => {
  const uid = requireVerified(request);
  try { return await submitOffer(getFirestore(), getStorage().bucket(), uid, request.data || {}); } catch (error) { return fail(error); }
});
exports.removeTodaysOffer = onCall(options, async request => {
  const uid = requireVerified(request);
  if (request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(uid);
  try { return await removeOffer(getFirestore(), getStorage().bucket(), request.data?.vendorId); } catch (error) { return fail(error); }
});
exports.clearTodaysOffers = onSchedule({schedule: 'every 15 minutes', region: 'asia-south1', maxInstances: 1}, async () => {
  await clearEnded(getFirestore(), getStorage().bucket());
});
