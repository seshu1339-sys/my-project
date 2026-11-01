'use strict';
// What each app lets a signed-in email do. Called by the vendor, staff and customer apps right after any sign-in (Google, email
// code or password) and whenever the app opens with a saved session.
//   user   -> anyone. A customer record is made on the first login; roles never matter here.
//   vendor -> the Vendor app (vendors and service providers). Refused when the email already holds the staff role.
//   staff  -> the Staff app. Refused when the email already holds the vendor or service-provider role.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {accountKinds, emailRole, ROLE_TAKEN} = require('./accounts');
const db = getFirestore();
const options = {region: 'us-central1', maxInstances: 10, invoker: 'public'};
const APP_ROLES = {vendor: ['vendor', 'provider'], staff: ['staff']};

exports.claimAppRole = onCall(options, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (request.auth.token.email_verified !== true) throw new HttpsError('permission-denied', 'Verify your email first.');
  const app = request.data?.app;
  const uid = request.auth.uid;
  if (app === 'user') {
    // A customer account is made on the first login; the same email may also be a vendor, provider or staff elsewhere.
    const ref = db.collection('users').doc(uid);
    if (!(await ref.get()).exists) await ref.set({customer: true, email: String(request.auth.token.email || '').toLowerCase(), createdAt: FieldValue.serverTimestamp()}, {merge: true});
    return {app, role: 'customer'};
  }
  const allowed = APP_ROLES[app];
  if (!allowed) throw new HttpsError('invalid-argument', 'Unknown app.');
  const held = await emailRole(db, request.auth.token.email);
  if (held && !allowed.includes(held)) throw new HttpsError('failed-precondition', ROLE_TAKEN);
  const kinds = await accountKinds(db, uid);
  const own = Object.keys(kinds).filter(kind => kinds[kind]);
  if (own.some(kind => !allowed.includes(kind))) throw new HttpsError('failed-precondition', ROLE_TAKEN);
  return {app, role: held || own[0] || ''};
});
