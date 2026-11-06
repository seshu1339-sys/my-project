'use strict';
// Photo limits module (owner, 6 Nov 2026). Every vendor has one shop photo (not counted); free vendors 2 extra photos, paid vendors
// their plan's number. Extra shop photos and own item photos share the allowance. When a paid plan ends, the first 2 extra photos stay
// and the others are deleted. Own folder (store.js). It reads vendorPremium (premium-status) and never imports another module.
//
//   submitItemPhoto   vendor  -> send an own photo for one item (waits for the admin's photo check), with how long it shows in search
//   setItemSearchTime vendor  -> how long an item shows in the website's category and search results (1 week to 3 months)
//   removeItemPhoto   vendor  -> back to our standard photo
//   reviewItemPhoto   admin   -> approve or reject an own item photo
//   trimPhotosOnPlanEnd trigger -> vendorPremium/<uid> went from active to not active
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {getFirestore} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {requireAdminSession} = require('../../admin-session');
const {FREE_EXTRA_PHOTOS} = require('../../plan-gate');
const S = require('./store');

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

exports.submitItemPhoto = onCall(options, async request => {
  const uid = requireVerified(request);
  try { return await S.submitItemPhoto(getFirestore(), getStorage().bucket(), uid, request.data || {}); } catch (error) { return fail(error); }
});
exports.setItemSearchTime = onCall(options, async request => {
  const uid = requireVerified(request);
  try { return await S.setItemSearchTime(getFirestore(), uid, request.data || {}); } catch (error) { return fail(error); }
});
exports.removeItemPhoto = onCall(options, async request => {
  const uid = requireVerified(request);
  try { return await S.removeItemPhoto(getFirestore(), getStorage().bucket(), uid, request.data || {}); } catch (error) { return fail(error); }
});
exports.reviewItemPhoto = onCall(options, async request => {
  await requireAdmin(request);
  try { return await S.reviewItemPhoto(getFirestore(), getStorage().bucket(), request.data || {}); } catch (error) { return fail(error); }
});
exports.trimPhotosOnPlanEnd = onDocumentWritten({document: 'vendorPremium/{uid}', region: 'asia-south1', maxInstances: 3, timeoutSeconds: 300}, async event => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (before?.active !== true || after?.active === true) return;
  const db = getFirestore();
  const free = (await db.collection('planServiceGates').doc('main').get()).data()?.freeExtraPhotos;
  await S.trimAfterPlan(db, getStorage().bucket(), event.params.uid, Number.isInteger(free) && free >= 0 ? free : FREE_EXTRA_PHOTOS);
});
