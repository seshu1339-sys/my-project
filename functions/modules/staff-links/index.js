'use strict';
const {requireRole, isAdminToken} = require('../../role-auth');
// Staff Links module: vendors and service providers register themselves; a staff member links one by their ID within 30 minutes of
// the registration ("Registered by" in the admin panel). Staff never edit a linked person's shop, items or prices; the staff app
// only reads their updates. Own folder, own collection (staffLinks). Removing its one line from functions/index.js removes linking;
// registration and everything else keep working.
//
//   linkStaffRegistration    staff -> link the vendor / provider with this ID (VEN-... / SRV-...)
//   removeStaffLink          admin -> remove a wrong link
//   disableOldStaffAdded     admin -> suspend the vendors and providers staff created the old way (they must register themselves)
//   adminLinkStaff           admin -> link a vendor / provider to a staff member of their area, at any time
//   staffForArea             admin -> the active staff whose area holds this vendor / provider (to choose from)
//   requestLocalStaff        vendor / provider -> "connect me to the staff of my area" (from the Support Team chat)
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore} = require('firebase-admin/firestore');
const {requireAdminSession} = require('../../admin-session');
const {linkAccount, removeLink, disableOldStaffAdded, adminLink, requestLocalStaff, staffInAreaOf, registration} = require('./store');

const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};
const fail = error => { throw new HttpsError('failed-precondition', error.message); };
function requireVerified(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  requireRole(request);
  return request.auth.uid;
}
async function requireAdmin(request) {
  const uid = requireVerified(request);
  if (!isAdminToken(request.auth.token)) throw new HttpsError('permission-denied', 'Administrator access required.');
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
exports.adminLinkStaff = onCall(options, async request => {
  const uid = await requireAdmin(request);
  try { return await adminLink(getFirestore(), uid, request.data || {}); } catch (error) { return fail(error); }
});
exports.staffForArea = onCall({...options, timeoutSeconds: 60}, async request => {
  await requireAdmin(request);
  try {
    const db = getFirestore();
    const {app} = await registration(db, request.data || {});
    return {staff: await staffInAreaOf(db, app)};
  } catch (error) { return fail(error); }
});
exports.requestLocalStaff = onCall(options, async request => {
  const uid = requireRole(request, ['vendor', 'provider']);
  try { return await requestLocalStaff(getFirestore(), uid, request.auth.token.role); } catch (error) { return fail(error); }
});
