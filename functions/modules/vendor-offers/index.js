'use strict';
// Vendor Offers module. Its own files, callables, collections and Storage folder (see store.js). It knows nothing about plans or payments.
// Removing its one line from functions/index.js removes all of it, and nothing else notices.
//
//   saveVendorOffer         vendor -> add or edit an own offer
//   deleteVendorOffer       vendor -> delete an own offer and its photos
//   reviewVendorOffer       admin  -> approve a waiting offer, or remove any offer
//   saveVendorOffersConfig  admin  -> whether new offers wait for approval
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {requireAdminSession} = require('../../admin-session');
const {saveOffer, deleteOffer, reviewOffer, saveConfig} = require('./store');

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

exports.saveVendorOffer = onCall(options, async request => {
  const uid = requireVerified(request);
  try { return await saveOffer(getFirestore(), getStorage().bucket(), uid, request.data || {}); } catch (error) { return fail(error); }
});
exports.deleteVendorOffer = onCall(options, async request => {
  const uid = requireVerified(request);
  try { return await deleteOffer(getFirestore(), getStorage().bucket(), uid, request.data?.offerId); } catch (error) { return fail(error); }
});
exports.reviewVendorOffer = onCall(options, async request => {
  await requireAdmin(request);
  try { return await reviewOffer(getFirestore(), request.data || {}); } catch (error) { return fail(error); }
});
exports.saveVendorOffersConfig = onCall(options, async request => {
  await requireAdmin(request);
  try { return await saveConfig(getFirestore(), request.data || {}); } catch (error) { return fail(error); }
});
