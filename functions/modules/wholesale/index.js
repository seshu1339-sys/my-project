'use strict';
const {requireRole, isAdminToken} = require('../../role-auth');
// Wholesale module: offers the administrator adds for Premium vendors (see store.js). Removing its line from functions/index.js removes all of it.
//
//   saveWholesaleOffer    admin -> add or edit an offer
//   deleteWholesaleOffer  admin -> delete an offer
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore} = require('firebase-admin/firestore');
const {requireAdminSession} = require('../../admin-session');
const {saveOffer, deleteOffer} = require('./store');

const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};
const fail = error => { throw new HttpsError('failed-precondition', error.message); };
async function requireAdmin(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  requireRole(request);
  if (!isAdminToken(request.auth.token)) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
}

exports.saveWholesaleOffer = onCall(options, async request => {
  await requireAdmin(request);
  try { return await saveOffer(getFirestore(), request.data || {}); } catch (error) { return fail(error); }
});
exports.deleteWholesaleOffer = onCall(options, async request => {
  await requireAdmin(request);
  try { return await deleteOffer(getFirestore(), request.data?.offerId); } catch (error) { return fail(error); }
});
