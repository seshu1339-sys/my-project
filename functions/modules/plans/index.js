'use strict';
// Subscription Plans module. Its own files, callables and collections (see store.js). Removing its one line from functions/index.js
// removes all of it: shops, registration and the other modules keep working, and functions/plan-gate.js simply lets every service through.
//
//   savePlan              admin  -> add or edit a plan
//   savePlanGates         admin  -> which special services need a plan
//   startPlanPurchase     vendor -> chooses a plan; makes a paymentRequests document
//   activatePlanOnPayment trigger -> the payment module marked that request verified
//   adminActivatePlan     admin  -> starts a plan for a vendor by hand (Vendor ID + plan), no payment in the app
//   adminStopPlan         admin  -> stops a vendor's running plan
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentUpdated} = require('firebase-functions/v2/firestore');
const {getFirestore} = require('firebase-admin/firestore');
const {requireAdminSession} = require('../../admin-session');
const {savePlan, saveGates, startPurchase, activatePlan, adminActivatePlan, adminStopPlan} = require('./store');

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

exports.savePlan = onCall(options, async request => {
  await requireAdmin(request);
  try { return await savePlan(getFirestore(), request.data || {}); } catch (error) { return fail(error); }
});
exports.savePlanGates = onCall(options, async request => {
  await requireAdmin(request);
  try { return await saveGates(getFirestore(), request.data || {}); } catch (error) { return fail(error); }
});
exports.adminActivatePlan = onCall(options, async request => {
  await requireAdmin(request);
  try { return await adminActivatePlan(getFirestore(), request.data || {}, request.auth.uid); } catch (error) { return fail(error); }
});
exports.adminStopPlan = onCall(options, async request => {
  await requireAdmin(request);
  try { return await adminStopPlan(getFirestore(), request.data || {}, request.auth.uid); } catch (error) { return fail(error); }
});
exports.startPlanPurchase = onCall(options, async request => {
  const uid = requireVerified(request);
  try { return await startPurchase(getFirestore(), uid, request.data || {}); } catch (error) { return fail(error); }
});
exports.activatePlanOnPayment = onDocumentUpdated({document: 'paymentRequests/{requestId}', region: 'asia-south1', maxInstances: 3}, async event => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (after.source !== 'plans' || after.status !== 'verified' || before.status === 'verified') return;
  await activatePlan(getFirestore(), event.params.requestId, after);
});
