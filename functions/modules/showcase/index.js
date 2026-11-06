'use strict';
// Showcase module: the paid vendors' boxes in Today's Offers and in the website's right-side ad boxes, seen only within the plan's km
// (store.js). Removing its one line from functions/index.js removes the records; offers and ads keep working as before.
//
//   chooseShowcasePhoto  vendor  -> the photo of their right-side ad box (one of their approved shop photos)
//   syncShowcaseOnPlan   trigger -> vendorPremium/<uid> changed (plan started, renewed, kind changed or ended)
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {getFirestore} = require('firebase-admin/firestore');
const {choosePhoto, syncPlan} = require('./store');

const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};

exports.chooseShowcasePhoto = onCall(options, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true) throw new HttpsError('permission-denied', 'Verify your email first.');
  try { return await choosePhoto(getFirestore(), request.auth.uid, request.data || {}); } catch (error) { throw new HttpsError('failed-precondition', error.message); }
});
exports.syncShowcaseOnPlan = onDocumentWritten({document: 'vendorPremium/{uid}', region: 'asia-south1', maxInstances: 3}, async event => {
  await syncPlan(getFirestore(), event.params.uid, event.data?.after?.data());
});
