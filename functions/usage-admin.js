'use strict';
// Admin helpers for the Analytics reports (lib/ui/admin_analytics*.dart): who the people in the per-person report are.
//   accountLabels  admin -> for up to 100 account ids: the email, the name and what kind of account it is (customer, vendor,
//                  service provider, staff), so the report shows people, not ids.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');
const {requireAdminSession} = require('./admin-session');
const {accountKinds} = require('./accounts');
const db = getFirestore();
const options = {region: 'us-central1', maxInstances: 5, invoker: 'public'};

async function requireAdmin(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true || request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Administrator access required.');
  await requireAdminSession(request.auth.uid);
}

/// The kind of account, in words.
function kindOf(kinds) {
  if (kinds.vendor) return 'vendor';
  if (kinds.provider) return 'service provider';
  if (kinds.staff) return 'staff';
  return 'customer';
}

async function labelsFor(uids) {
  const out = {};
  const found = await getAuth().getUsers(uids.map(uid => ({uid})));
  for (const user of found.users) out[user.uid] = {email: user.email || '', name: user.displayName || '', disabled: user.disabled === true};
  for (const uid of uids) {
    out[uid] = {...(out[uid] || {email: '', name: '', missing: true}), kind: kindOf(await accountKinds(db, uid))};
  }
  return out;
}

exports.accountLabels = onCall(options, async request => {
  await requireAdmin(request);
  const uids = request.data?.uids;
  if (!Array.isArray(uids) || uids.length > 100 || uids.some(u => typeof u !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(u))) throw new HttpsError('invalid-argument', 'Provide up to 100 account ids.');
  return {labels: await labelsFor([...new Set(uids)])};
});

exports._usageAdmin = {labelsFor, kindOf};
