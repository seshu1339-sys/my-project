'use strict';
// Staff Links module: vendors and service providers register themselves; a staff member links one by their ID within 30 minutes of
// the registration ("Registered by" in the admin panel). Staff never edit a linked person's shop, items or prices; the staff app
// only reads their updates. Own folder, own collection (staffLinks). Removing its one line from functions/index.js removes linking;
// registration and everything else keep working.
//
//   linkStaffRegistration    staff -> link the vendor / provider with this ID (VEN-... / SRV-...)
//   removeStaffLink          admin -> remove a wrong link
//   disableOldStaffAdded     admin -> suspend the vendors and providers staff created the old way (they must register themselves)
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore} = require('firebase-admin/firestore');
const {requireAdminSession} = require('../../admin-session');
const {linkAccount, removeLink, disableOldStaffAdded} = require('./store');

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
  return uid;
}

exports.linkStaffRegistration = onCall(options, async request => {
  const uid = requireVerified(request);
  try { return await linkAccount(getFirestore(), uid, request.data || {}); } catch (error) { return fail(error); }
});
exports.removeStaffLink = onCall(options, async request => {
  await requireAdmin(request);
  try { return await removeLink(getFirestore(), request.data || {}); } catch (error) { return fail(error); }
});
exports.disableOldStaffAdded = onCall({...options, timeoutSeconds: 300}, async request => {
  const uid = await requireAdmin(request);
  try { return await disableOldStaffAdded(getFirestore(), uid); } catch (error) { return fail(error); }
});
